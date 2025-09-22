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
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

@MainActor
final class SpotifyPlaybackController: NSObject, ObservableObject {
    enum Availability { case appRemote, webAPI, appOnly, unavailable }

    @Published private(set) var availability: Availability = .unavailable
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTrack: (title: String, artist: String, durationMs: Int)?
    @Published private(set) var nextTrack: (title: String, artist: String, durationMs: Int)?

    var onPlaybackEnded: (() -> Void)?

#if canImport(SpotifyiOS)
    // App Remote instance (only when Spotify SDK is available)
    private var appRemoteInstance: SPTAppRemote?
    private static weak var currentController: SpotifyPlaybackController?
#endif

    override init() {
        super.init()
        refreshAvailability()
#if canImport(SpotifyiOS)
        SpotifyPlaybackController.currentController = self
#endif
    }

    func refreshAvailability() {
        #if canImport(SpotifyiOS)
        if let url = URL(string: "spotify://"), UIApplication.shared.canOpenURL(url) {
            availability = .appRemote
            return
        }
        #endif
        availability = .webAPI
    }

    func connectIfNeeded() async { refreshAvailability() }

    func playPlaylist(uri: String) async {
        await connectIfNeeded()
        print("[SpotifyPlayback] availability=\(availability)")
        switch availability {
        case .appRemote:
            #if canImport(SpotifyiOS)
            await connectAppRemoteIfNeeded()
            appRemotePlay(uri: uri)
            isPlaying = true
            #endif
        case .webAPI:
            await playViaWebAPI(uri: uri)
            isPlaying = true
        case .appOnly:
            openInSpotify(uri: uri)
            isPlaying = true
        case .unavailable:
            // Nothing we can do programmatically
            isPlaying = false
        }
    }

    func pause() {
        switch availability {
        case .appRemote:
            #if canImport(SpotifyiOS)
            appRemoteInstance?.playerAPI?.pause(nil)
            isPlaying = false
            #endif
        case .webAPI:
            Task { await pauseViaWebAPI() }
            isPlaying = false
        case .appOnly, .unavailable:
            // No control in fallback
            break
        }
    }

    func resume() {
        switch availability {
        case .appRemote:
            #if canImport(SpotifyiOS)
            appRemoteInstance?.playerAPI?.resume(nil)
            isPlaying = true
            #endif
        case .webAPI:
            Task { await resumeViaWebAPI() }
            isPlaying = true
        case .appOnly, .unavailable:
            // No control in fallback
            break
        }
    }

    func stop() {
        switch availability {
        case .appRemote:
            #if canImport(SpotifyiOS)
            appRemoteInstance?.playerAPI?.pause(nil)
            isPlaying = false
            #endif
        case .webAPI:
            Task { await pauseViaWebAPI() }
            isPlaying = false
        case .appOnly, .unavailable:
            // No control in fallback
            break
        }
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

    // MARK: - Web API playback control
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
        _ = try? await URLSession.shared.data(for: req)
        await refreshNowPlaying()
    }

    private func pauseViaWebAPI() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/pause") else { return }
        var req = URLRequest(url: u); req.httpMethod = "PUT"
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: req)
        await refreshNowPlaying()
    }

    private func resumeViaWebAPI() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/play") else { return }
        var req = URLRequest(url: u); req.httpMethod = "PUT"
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        _ = try? await URLSession.shared.data(for: req)
        await refreshNowPlaying()
    }

    private func refreshNowPlaying() async {
        guard let u = URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track") else { return }
        var req = URLRequest(url: u)
        if let token = await AuthService.sharedToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        struct NowPlaying: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                let name: String
                let duration_ms: Int?
                let artists: [Artist]?
            }
            let item: Item?
        }
        if let np = try? JSONDecoder().decode(NowPlaying.self, from: data), let item = np.item {
            currentTrack = (item.name, item.artists?.first?.name ?? "", item.duration_ms ?? 0)
        }
    }
}

#if canImport(SpotifyiOS)
// MARK: - App Remote integration
extension SpotifyPlaybackController: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    private var appRemoteClientID: String { Config.clientID }
    private var appRemoteRedirectURI: String { Config.redirectURI }

    private func makeAppRemote() -> SPTAppRemote {
        let configuration = SPTConfiguration(clientID: appRemoteClientID, redirectURL: URL(string: appRemoteRedirectURI)!)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.connectionParameters.accessToken = nil
        remote.delegate = self
        return remote
    }

    private func appRemotePlay(uri: String) {
        if appRemoteInstance?.isConnected == true {
            appRemoteInstance?.playerAPI?.play(uri, callback: { _, _ in })
            appRemoteInstance?.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
                if error == nil { self?.appRemoteInstance?.playerAPI?.delegate = self }
            })
        } else {
            // One-time wake: this will open Spotify, start playback, and redirect back
            appRemoteInstance?.authorizeAndPlayURI(uri)
        }
    }

    private func setAppRemoteToken(_ token: String) {
        if appRemoteInstance == nil { appRemoteInstance = makeAppRemote() }
        appRemoteInstance?.connectionParameters.accessToken = token
    }

    private func connectAppRemoteIfNeeded() async {
        if appRemoteInstance == nil { appRemoteInstance = makeAppRemote() }
        guard let token = await AuthService.sharedToken() else { return }
        setAppRemoteToken(token)
        if appRemoteInstance?.isConnected != true {
            _ = appRemoteInstance?.connect()
        }
    }

    // MARK: SPTAppRemoteDelegate
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
        // Fetch initial state
        appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
            if let state = result as? SPTAppRemotePlayerState {
                self?.handle(state: state)
            }
        }
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if error == nil { appRemote.playerAPI?.delegate = self }
        })
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        // Fallback to Web API on failure
        Task { @MainActor in self.availability = .webAPI }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        // Keep web api as fallback
        Task { @MainActor in self.availability = .webAPI }
    }

    // MARK: SPTAppRemotePlayerStateDelegate
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor in self.handle(state: playerState) }
    }

    private func handle(state: SPTAppRemotePlayerState) {
        isPlaying = !state.isPaused
        let title = state.track.name
        let artist = state.track.artist.name
        let durationMs = Int(state.track.duration)
        currentTrack = (title, artist, durationMs)
        // Spotify App Remote does not expose next-track metadata directly; we'll leave nextTrack nil.
    }

    // MARK: - URL callback handling (authorizeAndPlayURI)
    static func handleRedirectURL(_ url: URL) {
        guard let controller = SpotifyPlaybackController.currentController,
              let app = controller.appRemoteInstance else { return }
        let params = app.authorizationParameters(from: url)
        if let token = params?[SPTAppRemoteAccessTokenKey] {
            app.connectionParameters.accessToken = token
            _ = app.connect()
        }
    }
}
#endif


