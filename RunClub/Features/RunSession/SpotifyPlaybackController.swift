//
//  SpotifyPlaybackController.swift
//  RunClub
//
//  Minimal Spotify playback abstraction. Uses App Remote when integrated; otherwise
//  falls back to opening the playlist in the Spotify app.
//

import Foundation
import Combine
import UIKit

@MainActor
final class SpotifyPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTrack: (title: String, artist: String, durationMs: Int)?
    @Published private(set) var nextTrack: (title: String, artist: String, durationMs: Int)?
    @Published private(set) var currentImageURL: URL?
    @Published private(set) var currentTrackProgressMs: Int = 0
    @Published private(set) var currentTrackId: String?
    @Published private(set) var playbackError: String?
    
    /// Callback invoked when track changes (for orchestrator sync)
    var onTrackChanged: ((String?) -> Void)?

    var onPlaybackEnded: (() -> Void)?

    // Track change detection helpers
    private var lastTrackSignature: String = ""
    private var lastAppRemoteTrackURI: String = ""
    private var triggeredEndRefresh: Bool = false

    private var lastPlaylistURI: String = ""
    
    // Periodic sync timer for accurate state tracking
    private var syncTimer: Timer?
    private static let syncInterval: TimeInterval = 3.0 // Poll Spotify every 3 seconds

    override init() {
        super.init()
        // Web API only
    }

    func connectIfNeeded() async { }

    // Prepare playback context early: preload playlist head and seed now-playing metadata.
    // Intentionally avoids foregrounding Spotify or initiating an App Remote connect to prevent app switching.
    func warmUpPlaybackContext(uri: String, foregroundIfNeeded: Bool) async {
        await connectIfNeeded()
        // Preload artwork/metadata so UI shows content before starting
        await preloadPlaylistHead(uri: uri)
        // Seed currently playing (if any) to avoid 0:00 flicker on first start
        await refreshNowPlaying()
    }

    func playPlaylist(uri: String) async {
        await ensureActiveDeviceAndPlay(uri: uri)
    }

    func pause() {
        Task { await pauseViaWebAPI() }
        isPlaying = false
        stopProgressTimer()
        stopSyncTimer()
    }

    func resume() {
        Task { await resumeViaWebAPI() }
        isPlaying = true
        startProgressTimer()
        startSyncTimer()
    }

    func stop() {
        Task { await pauseViaWebAPI() }
        isPlaying = false
        stopProgressTimer()
        stopSyncTimer()
    }
    
    // MARK: - Periodic Spotify State Sync
    // Polls Spotify API regularly to keep local state in sync with actual playback
    private func startSyncTimer() {
        stopSyncTimer()
        syncTimer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshNowPlaying()
            }
        }
        if let syncTimer {
            RunLoop.main.add(syncTimer, forMode: .common)
        }
    }
    
    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func openInSpotify(uri: String) {
        if let url = convertToSpotifyURL(uri: uri) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func convertToSpotifyURL(uri: String) -> URL? {
        // Accepts "spotify:playlist:ID" or https links. Prefer opening the spotify: scheme.
        if uri.hasPrefix("spotify:") {
            return URL(string: uri)
        }
        if let url = URL(string: uri), url.scheme?.hasPrefix("http") == true {
            // Try to convert https://open.spotify.com/playlist/ID to spotify://playlist/ID
            let path = url.path // e.g., "/playlist/ID"
            if path.hasPrefix("/playlist/") {
                let id = String(path.dropFirst("/playlist/".count))
                return URL(string: "spotify:playlist:\(id)")
            }
            if path.hasPrefix("/album/") {
                let id = String(path.dropFirst("/album/".count))
                return URL(string: "spotify:album:\(id)")
            }
            if path.hasPrefix("/track/") {
                let id = String(path.dropFirst("/track/".count))
                return URL(string: "spotify:track:\(id)")
            }
            return url
        }
        return nil
    }

    // MARK: - Metadata hooks (to be wired when App Remote is added)
    func updateTrackMetadata(now: (String, String, Int)?, next: (String, String, Int)?) {
        if let n = now { currentTrack = (n.0, n.1, n.2) } else { currentTrack = nil }
        if let nx = next { nextTrack = (nx.0, nx.1, nx.2) } else { nextTrack = nil }
    }

    // MARK: - Local progress ticking
    private var progressTimer: Timer?
    private func startProgressTimer() {
        progressTimer?.invalidate(); progressTimer = nil
        guard isPlaying else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Dispatch to MainActor since this callback runs on RunLoop but class is @MainActor
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isPlaying, let track = self.currentTrack else { return }
                let nextVal = min(track.durationMs, self.currentTrackProgressMs + 1000)
                self.currentTrackProgressMs = nextVal
                // Near end: trigger a metadata refresh to pick up next track when Web API is driving
                if nextVal >= track.durationMs - 2000 { // 2 second buffer before end
                    if !self.triggeredEndRefresh {
                        self.triggeredEndRefresh = true
                        await self.refreshNowPlaying()
                    }
                }
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }
    private func stopProgressTimer() {
        progressTimer?.invalidate(); progressTimer = nil
    }

    // MARK: - Web API playback control
    private struct DevicesEnvelope: Decodable { struct Device: Decodable { let id: String?; let is_active: Bool?; let is_restricted: Bool?; let name: String?; let type: String? }; let devices: [Device] }

    private func getDevices() async -> [DevicesEnvelope.Device] {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/devices") else { return [] }
        var req = URLRequest(url: u)
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        if let env = try? JSONDecoder().decode(DevicesEnvelope.self, from: data) { return env.devices } else { return [] }
    }

    private func transferPlayback(to deviceId: String, play: Bool) async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["device_ids": [deviceId], "play": play]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
            if http.statusCode == 403 { await MainActor.run { self.playbackError = "Spotify Premium is required to control playback." } }
            if !(200...299).contains(http.statusCode) {
                let _ = data // ignore body
            }
        }
    }

    func ensureActiveDeviceAndPlay(uri: String) async {
        await connectIfNeeded()
        lastAppRemoteTrackURI = ""
        func pickDevice(_ list: [DevicesEnvelope.Device]) -> DevicesEnvelope.Device? {
            if let active = list.first(where: { ($0.is_active ?? false) && ($0.is_restricted != true) }) { return active }
            if let phone = list.first(where: { ($0.type ?? "").lowercased() == "smartphone" && ($0.is_restricted != true) }) { return phone }
            if let comp = list.first(where: { ($0.type ?? "").lowercased() == "computer" && ($0.is_restricted != true) }) { return comp }
            return list.first(where: { $0.is_restricted != true })
        }
        var devices = await getDevices()
        var target = pickDevice(devices)
        if target == nil {
            if let url = URL(string: "spotify://") { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                devices = await getDevices()
                target = pickDevice(devices)
                if target != nil { break }
            }
        }
        guard let t = target, let deviceId = t.id else { await MainActor.run { self.playbackError = "No Spotify device available. Open Spotify, then try again." }; return }
        if !(t.is_active ?? false) {
            await transferPlayback(to: deviceId, play: true)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        await playViaWebAPI(uri: uri)
        isPlaying = true
        await MainActor.run { self.playbackError = nil }
    }
    private func playViaWebAPI(uri: String) async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/play") else { return }
        var body: [String: Any] = [:]
        if uri.hasPrefix("spotify:playlist:") {
            body = ["context_uri": uri]
        } else if uri.contains("open.spotify.com/playlist/") {
            if let id = uri.split(separator: "/").last { body = ["context_uri": "spotify:playlist:\(id)"] }
        }
        var req = URLRequest(url: u)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
            if http.statusCode == 403 { await MainActor.run { self.playbackError = "Spotify Premium is required to control playback." } }
            if !(200...299).contains(http.statusCode) {
                let _ = data // ignore body
            }
        }
        // Initial refresh to get current state
        await refreshNowPlaying()
        // Start progress timer and sync timer
        await MainActor.run {
            self.startProgressTimer()
            self.startSyncTimer()
        }
        // Poll a few more times to ensure state is accurate after Spotify fully starts
        kickstartProgressRefresh()
    }

    private func pauseViaWebAPI() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/pause") else { return }
        var req = URLRequest(url: u); req.httpMethod = "PUT"
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: req)
        // Brief delay to let Spotify settle, then refresh to get accurate position
        try? await Task.sleep(nanoseconds: 200_000_000)
        await refreshNowPlaying()
    }

    private func resumeViaWebAPI() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/play") else { return }
        var req = URLRequest(url: u); req.httpMethod = "PUT"
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: req)
        await refreshNowPlaying()
        await MainActor.run {
            self.startProgressTimer()
            self.startSyncTimer()
        }
        // Brief polling burst to ensure accurate state after resume
        kickstartProgressRefresh()
    }

    private func refreshNowPlaying() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track") else { return }
        var req = URLRequest(url: u)
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return }
        
        // Handle 204 No Content (nothing playing) gracefully
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 204 {
            // Nothing currently playing
            isPlaying = false
            return
        }
        guard http.statusCode == 200 else { return }
        
        struct NowPlaying: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable {
                    struct ImageObj: Decodable { let url: String; let height: Int?; let width: Int? }
                    let images: [ImageObj]?
                }
                let id: String?
                let name: String
                let duration_ms: Int?
                let artists: [Artist]?
                let album: Album?
            }
            let item: Item?
            let progress_ms: Int?
            let is_playing: Bool?
        }
        if let np = try? JSONDecoder().decode(NowPlaying.self, from: data), let item = np.item {
            let incomingTitle = item.name
            let incomingArtist = item.artists?.first?.name ?? ""
            let incomingId = item.id
            // Preserve prior non-zero duration if Spotify returns 0/unknown briefly after start
            var duration = item.duration_ms ?? 0
            if duration == 0, let cur = currentTrack {
                if cur.title == incomingTitle && cur.artist == incomingArtist && cur.durationMs > 0 {
                    duration = cur.durationMs
                } else if cur.durationMs > 0 {
                    duration = cur.durationMs
                }
            }
            let newSignature = "\(incomingTitle)|\(incomingArtist)|\(duration)"
            let didChange = (newSignature != lastTrackSignature)
            
            // Detect track change for orchestrator sync
            let previousTrackId = currentTrackId
            
            currentTrack = (incomingTitle, incomingArtist, duration)
            currentTrackId = incomingId
            
            // Select best quality image (prefer ~300px for good display at various sizes)
            if let images = item.album?.images, !images.isEmpty {
                let targetSize = 300
                let best = images.min(by: { img1, img2 in
                    let size1 = img1.height ?? img1.width ?? 0
                    let size2 = img2.height ?? img2.width ?? 0
                    return abs(size1 - targetSize) < abs(size2 - targetSize)
                })
                if let urlStr = best?.url, let url = URL(string: urlStr) {
                    currentImageURL = url
                } else if let urlStr = images.first?.url, let url = URL(string: urlStr) {
                    currentImageURL = url
                }
            } else {
                currentImageURL = nil
            }
            
            // ALWAYS use reported progress from Spotify as source of truth (fixes drift)
            let reported = np.progress_ms ?? 0
            currentTrackProgressMs = duration > 0 ? max(0, min(duration, reported)) : reported
            
            isPlaying = np.is_playing ?? isPlaying
            
            if didChange {
                lastTrackSignature = newSignature
                triggeredEndRefresh = false
                // Notify listeners of track change (e.g., for orchestrator phase sync)
                if previousTrackId != nil && incomingId != previousTrackId {
                    onTrackChanged?(incomingId)
                }
            }
        }
    }

    // Poll a few times after starting to smooth over SDK/web delay
    private func kickstartProgressRefresh() {
        Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await refreshNowPlaying()
            }
        }
    }

    // MARK: - Prefetch playlist head (for UI before starting playback)
    func preloadPlaylistHead(uri: String) async {
        guard let playlistId = extractPlaylistId(from: uri) else { return }
        var comps = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!
        comps.queryItems = [
            .init(name: "limit", value: "2"),
            .init(name: "fields", value: "items(track(name,artists(name),duration_ms,album(images(url))))")
        ]
        var req = URLRequest(url: comps.url!)
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        struct PlaylistHead: Decodable {
            struct Item: Decodable {
                struct Track: Decodable {
                    struct Artist: Decodable { let name: String }
                    struct Album: Decodable { struct Image: Decodable { let url: String }; let images: [Image]? }
                    let name: String
                    let duration_ms: Int
                    let artists: [Artist]?
                    let album: Album?
                }
                let track: Track?
            }
            let items: [Item]
        }
        if let head = try? JSONDecoder().decode(PlaylistHead.self, from: data) {
            let tracks = head.items.compactMap { $0.track }
            if let first = tracks.first {
                currentTrack = (first.name, first.artists?.first?.name ?? "", first.duration_ms)
                if let urlStr = first.album?.images?.first?.url, let url = URL(string: urlStr) { currentImageURL = url } else { currentImageURL = nil }
                currentTrackProgressMs = 0
            }
            if tracks.count > 1 {
                let second = tracks[1]
                nextTrack = (second.name, second.artists?.first?.name ?? "", second.duration_ms)
            } else { nextTrack = nil }
        }
    }

    private func extractPlaylistId(from uri: String) -> String? {
        if uri.hasPrefix("spotify:playlist:") { return uri.components(separatedBy: ":").last }
        if uri.contains("open.spotify.com/playlist/") {
            if let id = uri.split(separator: "/").last?.split(separator: "?").first { return String(id) }
        }
        return nil
    }
}


