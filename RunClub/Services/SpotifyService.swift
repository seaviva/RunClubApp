//
//  SpotifyService.swift
//  RunClub
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Foundation

final class SpotifyService {
    // Injected by the caller (RootView) right before making requests
    var accessTokenProvider: () -> String = { "" }

    // MARK: - Models
    private struct Me: Decodable { let id: String; let country: String? }
    private struct SavedTracks: Decodable {
        struct Item: Decodable {
            struct Track: Decodable {
                struct Artist: Decodable { let id: String; let name: String }
                let id: String
                let uri: String
                let duration_ms: Int?
                let artists: [Artist]?
            }
            let track: Track
        }
        let items: [Item]
        let next: String?
    }
    private struct TopArtistsResponse: Decodable {
        struct Artist: Decodable { let id: String }
        let items: [Artist]
    }

    private struct TopTracksResponse: Decodable {
        struct Track: Decodable { let id: String }
        let items: [Track]
    }

    private struct PlaylistCreateResponse: Decodable {
        let id: String
        let external_urls: [String: String]
    }

    private struct PlaylistItemsResponse: Decodable {
        struct Item: Decodable {
            struct Track: Decodable { let uri: String?; let id: String? }
            let track: Track?
        }
        let items: [Item]
        let total: Int?
    }

    private struct RecommendationResponse: Decodable {
        struct Track: Decodable {
            struct Album: Decodable { let release_date: String }
            struct Artist: Decodable { let id: String; let name: String }
            let id: String
            let uri: String
            let name: String
            let popularity: Int
            let explicit: Bool
            let duration_ms: Int
            let album: Album
            let artists: [Artist]
        }
        let tracks: [Track]
    }

    private struct SeveralTracksResponse: Decodable {
        struct Track: Decodable { let id: String? }
        let tracks: [Track?]
    }

    // For alternate-version lookup: need ISRC and basic metadata
    private struct SeveralTracksFullResponse: Decodable {
        struct Track: Decodable {
            struct Artist: Decodable { let id: String?; let name: String? }
            struct ExternalIDs: Decodable { let isrc: String? }
            let id: String?
            let name: String?
            let artists: [Artist]?
            let external_ids: ExternalIDs?
        }
        let tracks: [Track?]
    }

    private struct SearchTracksResponse: Decodable {
        struct Tracks: Decodable {
            struct Item: Decodable { let id: String? }
            let items: [Item]
        }
        let tracks: Tracks
    }

    private struct AudioFeaturesResponse: Decodable {
        struct Features: Decodable { let id: String; let tempo: Double }
        let audio_features: [Features?]
    }

    private struct ArtistsResponse: Decodable {
        struct Artist: Decodable { let id: String; let genres: [String] }
        let artists: [Artist]
    }

    private struct ArtistTopTracksResponse: Decodable {
        struct Track: Decodable {
            let id: String
            let uri: String
            let name: String
            let popularity: Int
            let explicit: Bool
            let duration_ms: Int
            struct Album: Decodable { let release_date: String }
            let album: Album
            struct Artist: Decodable { let id: String; let name: String }
            let artists: [Artist]
        }
        let tracks: [Track]
    }

    private struct SearchArtistsResponse: Decodable {
        struct Artists: Decodable {
            struct Item: Decodable { let id: String }
            let items: [Item]
        }
        let artists: Artists
    }

    // MARK: - Helpers
    private enum SpotifyServiceError: Error, LocalizedError {
        case http(status: Int, body: String, endpoint: String)
        var errorDescription: String? {
            switch self {
            case .http(let status, let body, let endpoint):
                return "HTTP \(status) @ \(endpoint): \(body)"
            }
        }
    }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("Bearer \(accessTokenProvider())", forHTTPHeaderField: "Authorization")
        if let body = body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = body
        }
        return r
    }

    private func fetch(_ request: URLRequest, label: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyServiceError.http(status: http.statusCode, body: body, endpoint: label)
        }
        return data
    }

    private func year(from releaseDate: String) -> Int? {
        // release_date can be YYYY-MM-DD or YYYY
        let comps = releaseDate.split(separator: "-")
        return Int(comps.first ?? "")
    }

    // MARK: - Public: Check track playability in market
    func playableIds(for ids: [String], market: String?) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        var result: Set<String> = []
        let chunkSize = 50
        var idx = 0
        while idx < ids.count {
            let chunk = Array(ids[idx..<min(idx + chunkSize, ids.count)])
            var comps = URLComponents(string: "https://api.spotify.com/v1/tracks")!
            comps.queryItems = [
                .init(name: "ids", value: chunk.joined(separator: ","))
            ]
            if let market { comps.queryItems?.append(.init(name: "market", value: market)) }
            let data = try await fetch(request(comps.url!), label: "GET /v1/tracks (playable)")
            let resp = try JSONDecoder().decode(SeveralTracksResponse.self, from: data)
            for t in resp.tracks {
                if let id = t?.id { result.insert(id) }
            }
            idx += chunkSize
        }
        return result
    }

    // MARK: - Public: Find alternate playable version by ISRC or Name/Artist
    /// Attempts to find a playable alternate release for a track in the given market.
    /// Returns a different track ID if found, or nil if none available.
    func findAlternatePlayableTrack(originalId: String, market: String?) async throws -> String? {
        // 1) Fetch original track details to get ISRC, name, and primary artist
        var comps = URLComponents(string: "https://api.spotify.com/v1/tracks")!
        comps.queryItems = [.init(name: "ids", value: originalId)]
        if let market { comps.queryItems?.append(.init(name: "market", value: market)) }
        do {
            let data = try await fetch(request(comps.url!), label: "GET /v1/tracks (details)")
            let details = try JSONDecoder().decode(SeveralTracksFullResponse.self, from: data)
            guard let first = details.tracks.first, let t = first else { return nil }
            let isrc = t.external_ids?.isrc
            let primaryArtist = (t.artists?.first)?.name ?? ""
            let title = t.name ?? ""

            // 2) Try ISRC search first
            if let isrc, !isrc.isEmpty {
                if let alt = try await findPlayableByISRC(isrc: isrc, excludeId: originalId, market: market) {
                    return alt
                }
            }
            // 3) Fallback: search by title + artist
            if !title.isEmpty {
                if let alt = try await findPlayableByTitleArtist(title: title, artist: primaryArtist, excludeId: originalId, market: market) {
                    return alt
                }
            }
        } catch {
            // Non-fatal; just return nil on failure
            return nil
        }
        return nil
    }

    private func findPlayableByISRC(isrc: String, excludeId: String, market: String?) async throws -> String? {
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [
            .init(name: "q", value: "isrc:\(isrc)"),
            .init(name: "type", value: "track"),
            .init(name: "limit", value: "10")
        ]
        if let market { comps.queryItems?.append(.init(name: "market", value: market)) }
        let data = try await fetch(request(comps.url!), label: "GET /v1/search?type=track (isrc)")
        let res = try JSONDecoder().decode(SearchTracksResponse.self, from: data)
        let ids = res.tracks.items.compactMap { $0.id }.filter { $0 != excludeId }
        guard !ids.isEmpty else { return nil }
        let playable = try await playableIds(for: ids, market: market)
        return ids.first(where: { playable.contains($0) })
    }

    private func findPlayableByTitleArtist(title: String, artist: String, excludeId: String, market: String?) async throws -> String? {
        // Build a conservative search query
        let qTitle = title.replacingOccurrences(of: "\"", with: "")
        let qArtist = artist.replacingOccurrences(of: "\"", with: "")
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [
            .init(name: "q", value: "track:\"\(qTitle)\" artist:\"\(qArtist)\""),
            .init(name: "type", value: "track"),
            .init(name: "limit", value: "10")
        ]
        if let market { comps.queryItems?.append(.init(name: "market", value: market)) }
        let data = try await fetch(request(comps.url!), label: "GET /v1/search?type=track (title)")
        let res = try JSONDecoder().decode(SearchTracksResponse.self, from: data)
        let ids = res.tracks.items.compactMap { $0.id }.filter { $0 != excludeId }
        guard !ids.isEmpty else { return nil }
        let playable = try await playableIds(for: ids, market: market)
        return ids.first(where: { playable.contains($0) })
    }

    // MARK: - Public profile helper
    func getProfileMarket() async throws -> String? {
        let data = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me (market)")
        let me = try JSONDecoder().decode(Me.self, from: data)
        return me.country
    }

    // MARK: - Crawler helpers (non-breaking additions)

    private struct SavedTracksPage: Decodable {
        struct Item: Decodable {
            let added_at: String?
            struct Track: Decodable {
                struct Artist: Decodable { let id: String?; let name: String? }
                struct Album: Decodable { let name: String?; let release_date: String? }
                let id: String?
                let uri: String?
                let name: String?
                let duration_ms: Int?
                let artists: [Artist]?
                let album: Album?
                let popularity: Int?
                let explicit: Bool?
                let is_local: Bool?
            }
            let track: Track
        }
        let items: [Item]
        let next: String?
        let total: Int?
    }

    private struct AudioFeaturesResponseFull: Decodable {
        struct Features: Decodable {
            let id: String?
            let tempo: Double?
            let energy: Double?
            let danceability: Double?
            let valence: Double?
            let loudness: Double?
            let key: Int?
            let mode: Int?
            let time_signature: Int?
        }
        let audio_features: [Features?]
    }

    private struct ArtistsResponseFull: Decodable {
        struct Artist: Decodable { let id: String; let name: String?; let genres: [String]; let popularity: Int? }
        let artists: [Artist]
    }

    private func parseISODate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func sleepMilliseconds(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    // Public simple types for crawler usage
    struct SimplifiedTrackItem {
        let trackId: String
        let name: String
        let artistId: String
        let artistName: String
        let durationMs: Int
        let albumName: String
        let albumReleaseYear: Int?
        let popularity: Int?
        let explicit: Bool
        let addedAt: Date
    }

    struct AudioFeaturesFullOut {
        let id: String
        let tempo: Double?
        let energy: Double?
        let danceability: Double?
        let valence: Double?
        let loudness: Double?
        let key: Int?
        let mode: Int?
        let timeSignature: Int?
    }

    struct ArtistDetailsOut {
        let id: String
        let name: String
        let genres: [String]
        let popularity: Int?
    }

    /// Page through user's liked tracks. Returns items and the next offset if any.
    func getLikedTracksPage(limit: Int, offset: Int, market: String?) async throws -> (items: [SimplifiedTrackItem], nextOffset: Int?, total: Int?) {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        var q: [URLQueryItem] = [
            .init(name: "limit", value: String(max(1, min(50, limit)))),
            .init(name: "offset", value: String(max(0, offset)))
        ]
        if let market { q.append(.init(name: "market", value: market)) }
        comps.queryItems = q
        var data: Data!
        var attempt = 0
        while true {
            do {
                data = try await fetch(request(comps.url!), label: "GET /v1/me/tracks (crawler)")
                break
            } catch let SpotifyServiceError.http(status, _, _) where status == 429 {
                attempt += 1
                let backoffMs = UInt64(min(60_000, 2_000 * (1 << max(0, attempt - 1))))
                await sleepMilliseconds(backoffMs)
                continue
            }
        }
        let page = try JSONDecoder().decode(SavedTracksPage.self, from: data)
        var out: [SimplifiedTrackItem] = []
        for item in page.items {
            let t = item.track
            guard t.is_local != true else { continue }
            guard let id = t.id, let name = t.name else { continue }
            let artistId = t.artists?.first?.id ?? id
            let artistName = t.artists?.first?.name ?? "Unknown"
            let duration = t.duration_ms ?? 0
            let albumName = t.album?.name ?? ""
            let releaseYear = year(from: t.album?.release_date ?? "")
            let popularity = t.popularity
            let explicit = t.explicit ?? false
            let addedAt = parseISODate(item.added_at) ?? Date()
            out.append(.init(trackId: id,
                             name: name,
                             artistId: artistId,
                             artistName: artistName,
                             durationMs: duration,
                             albumName: albumName,
                             albumReleaseYear: releaseYear,
                             popularity: popularity,
                             explicit: explicit,
                             addedAt: addedAt))
        }
        var nextOffset: Int? = nil
        if let next = page.next, let u = URLComponents(string: next), let off = u.queryItems?.first(where: { $0.name == "offset" })?.value, let offInt = Int(off) {
            nextOffset = offInt
        } else if page.next != nil {
            nextOffset = offset + min(50, limit)
        } else if let total = page.total, (offset + page.items.count) < total {
            // Fallback when next is missing but total indicates more pages
            nextOffset = offset + page.items.count
        }
        // throttle ~2–3 req/sec
        await sleepMilliseconds(400)
        return (out, nextOffset, page.total)
    }

    // Removed on-device audio-features fetch; we use external provider now.

    /// Batch fetch artists (50 ids per call)
    func getArtists(ids: [String]) async throws -> [String: ArtistDetailsOut] {
        guard !ids.isEmpty else { return [:] }
        var map: [String: ArtistDetailsOut] = [:]
        let chunks = stride(from: 0, to: ids.count, by: 50).map { Array(ids[$0..<min($0+50, ids.count)]) }
        for chunk in chunks {
            var comps = URLComponents(string: "https://api.spotify.com/v1/artists")!
            comps.queryItems = [.init(name: "ids", value: chunk.joined(separator: ","))]
            var data: Data!
            var attempt = 0
            while true {
                do {
                    data = try await fetch(request(comps.url!), label: "GET /v1/artists (crawler)")
                    break
                } catch let SpotifyServiceError.http(status, _, _) where status == 429 {
                    attempt += 1
                    let backoffMs = UInt64(min(60_000, 2_000 * (1 << max(0, attempt - 1))))
                    await sleepMilliseconds(backoffMs)
                    continue
                }
            }
            let res = try JSONDecoder().decode(ArtistsResponseFull.self, from: data)
            for a in res.artists {
                map[a.id] = .init(id: a.id,
                                   name: a.name ?? a.id,
                                   genres: a.genres,
                                   popularity: a.popularity)
            }
            await sleepMilliseconds(400)
        }
        return map
    }

    private func fetchTopArtistsSeed(limit: Int) async throws -> String? {
        let data = try await fetch(
            request(URL(string: "https://api.spotify.com/v1/me/top/artists?limit=\(max(1, min(5, limit)))")!),
            label: "GET /v1/me/top/artists"
        )
        let res = try JSONDecoder().decode(TopArtistsResponse.self, from: data)
        let ids = res.items.map { $0.id }
        return ids.isEmpty ? nil : ids.joined(separator: ",")
    }

    private func fetchTopTracksSeed(limit: Int) async throws -> String? {
        let data = try await fetch(
            request(URL(string: "https://api.spotify.com/v1/me/top/tracks?limit=\(max(1, min(5, limit)))")!),
            label: "GET /v1/me/top/tracks"
        )
        let res = try JSONDecoder().decode(TopTracksResponse.self, from: data)
        let ids = res.items.map { $0.id }
        return ids.isEmpty ? nil : ids.joined(separator: ",")
    }

    private func fetchLikedTracksSeed(limit: Int) async throws -> String? {
        let data = try await fetch(
            request(URL(string: "https://api.spotify.com/v1/me/tracks?limit=\(max(1, min(5, limit)))")!),
            label: "GET /v1/me/tracks (seed)"
        )
        let res = try JSONDecoder().decode(SavedTracks.self, from: data)
        let ids = res.items.map { $0.track.id }
        return ids.isEmpty ? nil : ids.joined(separator: ",")
    }

    private func fetchAllLikedTracks(maxTotal: Int = 200) async throws -> [SavedTracks.Item.Track] {
        var results: [SavedTracks.Item.Track] = []
        var url = URL(string: "https://api.spotify.com/v1/me/tracks?limit=50")!
        while results.count < maxTotal {
            let data = try await fetch(request(url), label: "GET /v1/me/tracks (page)")
            let page = try JSONDecoder().decode(SavedTracks.self, from: data)
            results.append(contentsOf: page.items.map { $0.track })
            if let next = page.next, let nextURL = URL(string: next) {
                url = nextURL
            } else {
                break
            }
        }
        return results
    }

    private func generateFromLikesPlaylist(name: String,
                                           template: RunTemplateType,
                                           durationCategory: DurationCategory) async throws -> URL {
        // 1) Who am I?
        let meData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me")
        let me = try JSONDecoder().decode(Me.self, from: meData)

        // 2) Pull up to 200 liked tracks
        var liked = try await fetchAllLikedTracks()
        // Filter by <= 6 min
        liked = liked.filter { ($0.duration_ms ?? 0) <= 6 * 60 * 1000 }

        // 3) Fit duration bounds with randomness and per-artist cap
        let (minSeconds, maxSeconds) = durationBoundsSeconds(for: template, category: durationCategory)
        var totalSeconds = 0
        var uris: [String] = []
        var perArtistCount: [String: Int] = [:]
        for track in liked.shuffled() {
            let secs = (track.duration_ms ?? 0) / 1000
            guard totalSeconds + secs <= maxSeconds else { continue }
            let artistId = track.artists?.first?.id ?? track.id
            if (perArtistCount[artistId] ?? 0) >= 2 { continue }
            uris.append(track.uri)
            perArtistCount[artistId, default: 0] += 1
            totalSeconds += secs
            if totalSeconds >= minSeconds { break }
        }

        // 4) Create playlist and add tracks
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": "RunClub · \(template.rawValue) · \(durationCategory.displayName)",
            "public": true
        ])
        let plData = try await fetch(request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                                      method: "POST",
                                      body: createBody), label: "POST /v1/users/{id}/playlists")
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        if !uris.isEmpty {
            let addBody = try JSONSerialization.data(withJSONObject: ["uris": uris])
            _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                                method: "POST",
                                body: addBody), label: "POST /v1/playlists/{id}/tracks (likes)")
        }

        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }

    // MARK: - Public: Create playlist helper for LocalGenerator
    /// Creates a public or private playlist with the given URIs and returns the Spotify web URL.
    func createPlaylist(name: String, description: String, isPublic: Bool, uris: [String]) async throws -> URL {
        // 1) Who am I?
        let meData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me (create)")
        let me = try JSONDecoder().decode(Me.self, from: meData)

        // 2) Create playlist
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": description,
            "public": isPublic
        ])
        let plData = try await fetch(request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                                      method: "POST",
                                      body: createBody), label: "POST /v1/users/{id}/playlists (local)")
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        // 3) Add tracks if any
        if !uris.isEmpty {
            let addBody = try JSONSerialization.data(withJSONObject: ["uris": uris])
            _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                                  method: "POST",
                                  body: addBody), label: "POST /v1/playlists/{id}/tracks (local)")

            // Debug: verify what actually landed in the playlist (helps diagnose missing first/last)
            if let verifyURL = URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks?fields=items(track(uri)),total") {
                do {
                    let itemsData = try await fetch(request(verifyURL), label: "GET /v1/playlists/{id}/tracks (verify)")
                    let resp = try JSONDecoder().decode(PlaylistItemsResponse.self, from: itemsData)
                    let got = resp.items.compactMap { $0.track?.uri }
                    let sent = uris
                    let sentSet = Set(sent)
                    let gotSet = Set(got)
                    let missing = Array(sentSet.subtracting(gotSet))
                    let extras = Array(gotSet.subtracting(sentSet))
                    print("Spotify add verify — sent: \(sent.count) got: \(got.count) missing: \(missing.count) extras: \(extras.count)")
                    if let first = got.first, let last = got.last {
                        print("Spotify add verify — first: \(first) last: \(last)")
                    }
                    if !missing.isEmpty { print("Spotify add verify — missing URIs: \(missing)") }
                } catch {
                    // Non-fatal; purely diagnostic
                    print("Spotify add verify failed: \(error)")
                }
            }
        }

        // 4) Return web URL
        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }

    private func seedGenreString(from genres: [Genre]) -> String? {
        guard !genres.isEmpty else { return nil }
        // Map app genres to Spotify seed genres
        let mapped = genres.prefix(5).map { g -> String in
            switch g {
            case .pop: return "pop"
            case .hipHopRap: return "hip-hop"
            case .rockAlt: return "rock"
            case .electronic: return "electronic"
            case .indie: return "indie"
            case .rnb: return "r-n-b"
            case .country: return "country"
            case .latin: return "latin"
            case .jazzBlues: return "jazz"
            case .classicalSoundtrack: return "classical"
            }
        }
        return mapped.joined(separator: ",")
    }

    private func decadeYearRange(_ decades: [Decade]) -> [(Int, Int)] {
        decades.map { d in
            switch d {
            case .seventies: return (1970, 1979)
            case .eighties: return (1980, 1989)
            case .nineties: return (1990, 1999)
            case .twoThousands: return (2000, 2009)
            case .twentyTens: return (2010, 2019)
            case .twentyTwenties: return (2020, 2029)
            }
        }
    }

    private func fetchArtistsGenresMap(ids: [String]) async throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        guard !ids.isEmpty else { return result }
        let chunks = stride(from: 0, to: ids.count, by: 50).map { Array(ids[$0..<min($0+50, ids.count)]) }
        for chunk in chunks {
            var comps = URLComponents(string: "https://api.spotify.com/v1/artists")!
            comps.queryItems = [.init(name: "ids", value: chunk.joined(separator: ","))]
            let data = try await fetch(request(comps.url!), label: "GET /v1/artists")
            let res = try JSONDecoder().decode(ArtistsResponse.self, from: data)
            for a in res.artists { result[a.id] = a.genres }
        }
        return result
    }

    private func searchArtistIds(for genre: String, market: String?, limit: Int) async throws -> [String] {
        var comps = URLComponents(string: "https://api.spotify.com/v1/search")!
        comps.queryItems = [
            .init(name: "q", value: "genre:\"\(genre)\""),
            .init(name: "type", value: "artist"),
            .init(name: "limit", value: String(limit))
        ]
        let data = try await fetch(request(comps.url!), label: "GET /v1/search?type=artist")
        let res = try JSONDecoder().decode(SearchArtistsResponse.self, from: data)
        return res.artists.items.map { $0.id }
    }

    private func fetchTopTracks(for artistId: String, market: String?) async throws -> [ArtistTopTracksResponse.Track] {
        var comps = URLComponents(string: "https://api.spotify.com/v1/artists/\(artistId)/top-tracks")!
        comps.queryItems = [.init(name: "market", value: market ?? "US")]
        let data = try await fetch(request(comps.url!), label: "GET /v1/artists/{id}/top-tracks")
        let res = try JSONDecoder().decode(ArtistTopTracksResponse.self, from: data)
        return res.tracks
    }

    private func bpmRange(for template: RunTemplateType) -> (Double, Double)? {
        switch template {
        case .rest: return nil
        case .easyRun: return (130, 150)
        case .strongSteady: return (150, 170)
        case .longEasy: return (130, 155)
        case .shortWaves, .longWaves, .pyramid, .kicker: return nil
        }
    }

    private func durationBoundsSeconds(for template: RunTemplateType, category: DurationCategory) -> (Int, Int) {
        switch template {
        case .rest:
            return (0, 0)
        case .longEasy:
            // Use 1.5× midpoint with ±2 min window, but cap >6min tracks separately
            let target = Int(Double(category.midpointMinutes) * 1.5) * 60
            return (max(target - 120, category.minMinutes * 60), target + 120)
        default:
            return (category.minMinutes * 60, category.maxMinutes * 60)
        }
    }

    // MARK: - Candidates (Recommendations with robust fallbacks, no audio-features)
    private func fetchRecommendationCandidates(minBPM: Double,
                                               maxBPM: Double,
                                               genres: [Genre],
                                               decades: [Decade],
                                               market: String?) async throws -> [RecommendationResponse.Track] {
        // Build recommendations request
        var queryItems: [URLQueryItem] = [
            .init(name: "limit", value: "100"),
            .init(name: "min_tempo", value: String(Int(minBPM))),
            .init(name: "target_tempo", value: String(Int((minBPM + maxBPM) / 2))),
            .init(name: "max_tempo", value: String(Int(maxBPM)))
        ]
        if let market { queryItems.append(.init(name: "market", value: market)) }
        let userGenreSeeds = seedGenreString(from: genres)
        if let userGenreSeeds { queryItems.append(.init(name: "seed_genres", value: userGenreSeeds)) }
        // Always include at least one genre seed
        if userGenreSeeds == nil { queryItems.append(.init(name: "seed_genres", value: "pop")) }

        var comps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        comps.queryItems = queryItems
        if let url = comps.url { print("Seg Recs URL:", url.absoluteString) }

        do {
            let recData = try await fetch(request(comps.url!), label: "GET /v1/recommendations (seg)")
            let recs = try JSONDecoder().decode(RecommendationResponse.self, from: recData)
            return recs.tracks
        } catch {
            // Fallback: search by genre -> artists -> top tracks
            let genresToUse = (genres.isEmpty ? [.pop] : genres).map { $0.rawValue.lowercased() }
            var artistIds: [String] = []
            for g in genresToUse { artistIds.append(contentsOf: (try? await searchArtistIds(for: g, market: market, limit: 20)) ?? []) }
            artistIds = Array(Array(Set(artistIds)).prefix(20))
            var tracks: [ArtistTopTracksResponse.Track] = []
            for aid in artistIds { tracks.append(contentsOf: (try? await fetchTopTracks(for: aid, market: market)) ?? []) }
            return tracks.map { t in
                RecommendationResponse.Track(id: t.id,
                                              uri: t.uri,
                                              name: t.name,
                                              popularity: t.popularity,
                                              explicit: t.explicit,
                                              duration_ms: t.duration_ms,
                                              album: .init(release_date: t.album.release_date),
                                              artists: t.artists.map { .init(id: $0.id, name: $0.name) })
            }
        }
    }

    // MARK: - Segmented generator for Waves/Pyramid/Kicker
    private func generateSegmentedRunPlaylist(name: String,
                                              template: RunTemplateType,
                                              durationCategory: DurationCategory,
                                              genres: [Genre],
                                              decades: [Decade]) async throws -> URL {
        let meData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me")
        let me = try JSONDecoder().decode(Me.self, from: meData)
        let (minSeconds, maxSeconds) = durationBoundsSeconds(for: template, category: durationCategory)
        let market = me.country

        // Define BPM bands for segments
        let easy: (Double, Double) = (130, 150)
        let steady: (Double, Double) = (150, 165)
        let high: (Double, Double) = (170, 185)

        // Build segment pattern
        var pattern: [(Double, Double)] = []
        switch template {
        case .shortWaves:
            pattern = [easy, high]
        case .longWaves:
            pattern = [easy, easy, high, high]
        case .pyramid:
            pattern = [easy, steady, high, steady, easy]
        case .kicker:
            pattern = [steady, steady, steady, high, high, high]
        default:
            pattern = [easy]
        }

        // Pre-fetch candidates for each unique band
        var bandToCandidates: [String: [RecommendationResponse.Track]] = [:]
        func key(_ b: (Double, Double)) -> String { "\(Int(b.0))_\(Int(b.1))" }
        for band in Set(pattern.map { key($0) }) {
            let parts = band.split(separator: "_")
            let lo = Double(parts[0]) ?? 130
            let hi = Double(parts[1]) ?? 150
            let tracks = try await fetchRecommendationCandidates(minBPM: lo, maxBPM: hi, genres: genres, decades: decades, market: market)
            bandToCandidates[band] = tracks
        }

        // Selection loop: iterate pattern until we fill duration
        var uris: [String] = []
        var totalSeconds = 0
        var seenTrackIds = Set<String>()
        var perArtistCount: [String: Int] = [:]
        var lastArtistId: String? = nil
        var recentArtistIds: [String] = [] // keep last 2 to improve variety

        func appendTrack(_ t: RecommendationResponse.Track) -> Bool {
            guard !seenTrackIds.contains(t.id) else { return false }
            let secs = t.duration_ms / 1000
            guard secs <= 6 * 60 else { return false }
            guard totalSeconds + secs <= maxSeconds else { return false }
            let artistId = t.artists.first?.id ?? t.id
            if let last = lastArtistId, last == artistId { return false } // avoid back-to-back same artist
            if recentArtistIds.contains(artistId) { return false } // avoid repeating within last 2
            if (perArtistCount[artistId] ?? 0) >= 2 { return false }
            uris.append(t.uri)
            seenTrackIds.insert(t.id)
            perArtistCount[artistId, default: 0] += 1
            totalSeconds += secs
            lastArtistId = artistId
            recentArtistIds.append(artistId)
            if recentArtistIds.count > 2 { recentArtistIds.removeFirst() }
            return true
        }

        var idx = 0
        while totalSeconds < minSeconds {
            let band = pattern[idx % pattern.count]
            let k = key(band)
            var tracks = bandToCandidates[k] ?? []
            var added = false
            for t in tracks.shuffled() {
                if appendTrack(t) { added = true; break }
            }
            if !added {
                // Try to widen BPM window for this band and retry
                let widenedLo = max(60, band.0 - 5)
                let widenedHi = min(220, band.1 + 5)
                let widened = try await fetchRecommendationCandidates(minBPM: widenedLo, maxBPM: widenedHi, genres: genres, decades: decades, market: market)
                // Merge new unique candidates
                let existingIds = Set(tracks.map { $0.id })
                let merged = tracks + widened.filter { !existingIds.contains($0.id) }
                bandToCandidates[k] = merged
                for t in merged.shuffled() {
                    if appendTrack(t) { added = true; break }
                }
                if !added {
                    // move to next band to keep progress
                    idx += 1
                    continue
                }
            }
            idx += 1
        }

        // Create playlist
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": "RunClub · \(template.rawValue) · \(durationCategory.displayName)",
            "public": true
        ])
        let plData = try await fetch(request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                                      method: "POST",
                                      body: createBody), label: "POST /v1/users/{id}/playlists (seg)")
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        if !uris.isEmpty {
            let addBody = try JSONSerialization.data(withJSONObject: ["uris": uris])
            _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                                method: "POST",
                                body: addBody), label: "POST /v1/playlists/{id}/tracks (seg)")
        }

        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }

    // MARK: - Public: simple smoke test
    /// Creates a private playlist from your recent liked tracks and returns its web URL.
    func createSimplePlaylistFromLikes(name: String) async throws -> URL {
        // 1) Who am I?
        let meData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me")
        let me = try JSONDecoder().decode(Me.self, from: meData)

        // 2) Get liked tracks (first 20)
        let likesData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me/tracks?limit=20")!), label: "GET /v1/me/tracks")
        let likes = try JSONDecoder().decode(SavedTracks.self, from: likesData)
        let uris = likes.items.map { $0.track.uri }

        // 3) Create playlist
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": "RunClub test playlist",
            "public": true
        ])
        let plData = try await fetch(request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                                  method: "POST",
                                  body: createBody), label: "POST /v1/users/{id}/playlists")
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        // 4) Add tracks (cap ~15 just to test)
        let addBody = try JSONSerialization.data(withJSONObject: [
            "uris": Array(uris.prefix(15))
        ])
        _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                            method: "POST",
                            body: addBody), label: "POST /v1/playlists/{id}/tracks")

        // 5) Return the playlist’s web URL
        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }

    // MARK: - Public: Generation (MVP Easy/Steady)
    /// Generates a playlist for Easy Run or Strong & Steady honoring hard filters, BPM, popularity, and duration bounds.
    func generateSimpleRunPlaylist(name: String,
                                   template: RunTemplateType,
                                   durationCategory: DurationCategory,
                                   genres: [Genre],
                                   decades: [Decade]) async throws -> URL {
        // If segmented template, use segmented pipeline (no audio-features dependency)
        if [.shortWaves, .longWaves, .pyramid, .kicker].contains(template) {
            return try await generateSegmentedRunPlaylist(name: name,
                                                         template: template,
                                                         durationCategory: durationCategory,
                                                         genres: genres,
                                                         decades: decades)
        }
        guard let (minBPM, maxBPM) = bpmRange(for: template) else {
            return try await generateFromLikesPlaylist(name: name, template: template, durationCategory: durationCategory)
        }

        // 1) Me for userId and market
        let meData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me")!), label: "GET /v1/me")
        let me = try JSONDecoder().decode(Me.self, from: meData)

        let bounds = durationBoundsSeconds(for: template, category: durationCategory)
        let (minSeconds, maxSeconds) = bounds

        // 2) Recommendations (ensure at least one seed)
        var queryItems: [URLQueryItem] = [
            .init(name: "limit", value: "100"),
            .init(name: "min_tempo", value: String(Int(minBPM))),
            .init(name: "target_tempo", value: String(Int((minBPM + maxBPM) / 2))),
            .init(name: "max_tempo", value: String(Int(maxBPM)))
        ]
        if let market = me.country { queryItems.append(.init(name: "market", value: market)) }
        var haveSeed = false
        // Prefer at least one genre seed (user-selected)
        let userGenreSeeds = seedGenreString(from: genres)
        if let seedGenres = userGenreSeeds { queryItems.append(.init(name: "seed_genres", value: seedGenres)); haveSeed = true }
        if !haveSeed {
            // Try top artists and tracks as seeds
            if let topArtistsSeed = try? await fetchTopArtistsSeed(limit: 2), !topArtistsSeed.isEmpty {
                queryItems.append(.init(name: "seed_artists", value: topArtistsSeed))
                haveSeed = true
            }
        }
        if !haveSeed {
            if let topTracksSeed = try? await fetchTopTracksSeed(limit: 2), !topTracksSeed.isEmpty {
                queryItems.append(.init(name: "seed_tracks", value: topTracksSeed))
                haveSeed = true
            }
        }
        if !haveSeed {
            // Fallback: liked tracks as seeds
            if let likedSeed = try? await fetchLikedTracksSeed(limit: 2), !likedSeed.isEmpty {
                queryItems.append(.init(name: "seed_tracks", value: likedSeed))
                haveSeed = true
            }
        }
        // Always ensure at least one genre seed exists; add safe default if user provided none
        if userGenreSeeds == nil {
            queryItems.append(.init(name: "seed_genres", value: "pop"))
        }
        var comps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        comps.queryItems = queryItems
        if let url = comps.url { print("Recommendations URL:", url.absoluteString) }
        var recs: RecommendationResponse
        do {
            let recData = try await fetch(request(comps.url!), label: "GET /v1/recommendations")
            recs = try JSONDecoder().decode(RecommendationResponse.self, from: recData)
        } catch {
            // Fallback path if recommendations fail: build candidates from genre → artists → top tracks;
            // if audio-features later 403 (permission), or we still fail to assemble, fallback to likes-based generator
            print("Recommendations failed, building via search:", error.localizedDescription)
            let market = me.country
            var artistIds: [String] = []
            let genresToUse = (genres.isEmpty ? [.pop] : genres).map { $0.rawValue.lowercased() }
            for g in genresToUse {
                let ids = (try? await searchArtistIds(for: g, market: market, limit: 20)) ?? []
                artistIds.append(contentsOf: ids)
            }
            artistIds = Array(Array(Set(artistIds)).prefix(20))
            var tracks: [ArtistTopTracksResponse.Track] = []
            for aid in artistIds {
                let tops = (try? await fetchTopTracks(for: aid, market: market)) ?? []
                tracks.append(contentsOf: tops)
            }
            let converted = tracks.map { t in
                RecommendationResponse.Track(id: t.id,
                                              uri: t.uri,
                                              name: t.name,
                                              popularity: t.popularity,
                                              explicit: t.explicit,
                                              duration_ms: t.duration_ms,
                                              album: .init(release_date: t.album.release_date),
                                              artists: t.artists.map { .init(id: $0.id, name: $0.name) })
            }
            recs = RecommendationResponse(tracks: converted)
        }

        // 3) Hard filter: decades and track duration <= 6min
        let decadeRanges = decadeYearRange(decades)
        func passesDecades(_ year: Int?) -> Bool {
            guard !decadeRanges.isEmpty else { return true }
            guard let y = year else { return false }
            return decadeRanges.contains(where: { (lo, hi) in (lo...hi).contains(y) })
        }

        var candidateTracks = recs.tracks.filter { t in
            t.popularity >= 40 && t.duration_ms <= 6 * 60 * 1000 && passesDecades(year(from: t.album.release_date))
        }

        // 4) Audio features for tempo validation
        let ids = candidateTracks.map { $0.id }
        var selected: [RecommendationResponse.Track] = []
        var featuresById: [String: Double] = [:]
        if !ids.isEmpty {
            var featComps = URLComponents(string: "https://api.spotify.com/v1/audio-features")!
            featComps.queryItems = [.init(name: "ids", value: ids.joined(separator: ","))]
            do {
                let featData = try await fetch(request(featComps.url!), label: "GET /v1/audio-features (batch)")
                let feats = try JSONDecoder().decode(AudioFeaturesResponse.self, from: featData)
                for f in feats.audio_features { if let f = f { featuresById[f.id] = f.tempo } }
            } catch let SpotifyServiceError.http(status, _, endpoint) where endpoint.contains("/v1/audio-features") && status == 403 {
                // If audio-features is not permitted, immediately fallback to likes-based generator
                return try await generateFromLikesPlaylist(name: name, template: template, durationCategory: durationCategory)
            }
        }

        // 5) Greedy fill within bounds, avoid duplicates and cap per artist
        var totalSeconds = 0
        var seenTrackIds = Set<String>()
        var perArtistCount: [String: Int] = [:]

        func tempoOk(_ id: String) -> Bool {
            guard let tempo = featuresById[id] else { return false }
            return tempo >= minBPM && tempo <= maxBPM
        }

        for track in candidateTracks.shuffled() {
            guard !seenTrackIds.contains(track.id) else { continue }
            guard tempoOk(track.id) else { continue }
            let artistId = track.artists.first?.id ?? track.id
            if (perArtistCount[artistId] ?? 0) >= 2 { continue }
            let secs = track.duration_ms / 1000
            if totalSeconds + secs > maxSeconds { continue }
            selected.append(track)
            seenTrackIds.insert(track.id)
            perArtistCount[artistId, default: 0] += 1
            totalSeconds += secs
            if totalSeconds >= minSeconds { break }
        }

        // If underfilled, relax popularity and widen tempo slightly, try again
        if totalSeconds < minSeconds {
            // Retry with lower popularity and wider BPM
            var retryItems = queryItems
            retryItems.removeAll { $0.name == "min_tempo" || $0.name == "max_tempo" }
            retryItems.append(.init(name: "min_tempo", value: String(Int(minBPM - 5))))
            retryItems.append(.init(name: "max_tempo", value: String(Int(maxBPM + 5))))
            var retryComps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
            retryComps.queryItems = retryItems
            let recData2 = try await fetch(request(retryComps.url!), label: "GET /v1/recommendations (retry)")
            let recs2 = try JSONDecoder().decode(RecommendationResponse.self, from: recData2)
            let more = recs2.tracks.filter { t in t.popularity >= 20 && t.duration_ms <= 6 * 60 * 1000 && passesDecades(year(from: t.album.release_date)) }
            candidateTracks.append(contentsOf: more)
            for track in candidateTracks.shuffled() {
                guard totalSeconds < minSeconds else { break }
                guard !seenTrackIds.contains(track.id) else { continue }
                if featuresById[track.id] == nil {
                    var featComps = URLComponents(string: "https://api.spotify.com/v1/audio-features")!
                    featComps.queryItems = [.init(name: "ids", value: track.id)]
                    do {
                        let featData2 = try await fetch(request(featComps.url!), label: "GET /v1/audio-features (single)")
                        let feats2 = try JSONDecoder().decode(AudioFeaturesResponse.self, from: featData2)
                        if let t = feats2.audio_features.first??.tempo { featuresById[track.id] = t }
                    } catch let SpotifyServiceError.http(status, _, endpoint) where endpoint.contains("/v1/audio-features") && status == 403 {
                        return try await generateFromLikesPlaylist(name: name, template: template, durationCategory: durationCategory)
                    }
                }
                guard let ttempo = featuresById[track.id], ttempo >= (minBPM - 5) && ttempo <= (maxBPM + 5) else { continue }
                let artistId = track.artists.first?.id ?? track.id
                if (perArtistCount[artistId] ?? 0) >= 2 { continue }
                let secs = track.duration_ms / 1000
                if totalSeconds + secs > maxSeconds { continue }
                selected.append(track)
                seenTrackIds.insert(track.id)
                perArtistCount[artistId, default: 0] += 1
                totalSeconds += secs
            }
        }

        // 6) Create playlist (public) and add tracks
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": "RunClub · \(template.rawValue) · \(durationCategory.displayName)",
            "public": true
        ])
        let plData = try await fetch(request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                                  method: "POST",
                                  body: createBody), label: "POST /v1/users/{id}/playlists")
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        let uris = selected.map { $0.uri }
        if !uris.isEmpty {
            let addBody = try JSONSerialization.data(withJSONObject: ["uris": uris])
            _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                                method: "POST",
                                body: addBody), label: "POST /v1/playlists/{id}/tracks")
        } else {
            // As a fallback, add up to 15 of the user's recent likes so the playlist isn't empty
            let likesData = try await fetch(request(URL(string: "https://api.spotify.com/v1/me/tracks?limit=15")!), label: "GET /v1/me/tracks (fallback)")
            let likes = try JSONDecoder().decode(SavedTracks.self, from: likesData)
            let likeUris = likes.items.map { $0.track.uri }
            if !likeUris.isEmpty {
                let addBody = try JSONSerialization.data(withJSONObject: ["uris": likeUris])
                _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                                    method: "POST",
                                    body: addBody), label: "POST /v1/playlists/{id}/tracks (fallback)")
            }
        }

        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }

    // MARK: - Public helpers
    func currentUserId() async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        req.addValue("Bearer \(accessTokenProvider())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        let me = try JSONDecoder().decode(Me.self, from: data)
        return me.id
    }
}

// MARK: - Preview helpers for RunPreviewService
extension SpotifyService {
    struct PreviewItemOut {
        let id: String
        let title: String
        let artist: String
        let imageURL: URL?
        let durationMs: Int
        let effort: LocalGenerator.EffortTier
    }

    private func tempoRange(for effort: LocalGenerator.EffortTier) -> (Double, Double) {
        switch effort {
        case .easy: return (130, 150)
        case .moderate: return (150, 162)
        case .strong: return (162, 175)
        case .hard: return (170, 185)
        case .max: return (175, 195)
        }
    }

    /// Build preview track list matching given efforts (no playlist creation yet)
    func sampleTracksForPreview(efforts: [LocalGenerator.EffortTier]) async throws -> [PreviewItemOut] {
        guard !efforts.isEmpty else { return [] }
        let market = try? await getProfileMarket()
        var usedTrackIds: Set<String> = []
        var usedArtistIds: [String: Int] = [:]
        var result: [PreviewItemOut] = []

        for effort in efforts {
            let (minTempo, maxTempo) = tempoRange(for: effort)
            let candidates = try await fetchRecommendationCandidates(minBPM: minTempo, maxBPM: maxTempo, genres: [], decades: [], market: market)
            var picked: RecommendationResponse.Track? = nil
            for t in candidates.shuffled() {
                if usedTrackIds.contains(t.id) { continue }
                let artistId = t.artists.first?.id ?? t.id
                if (usedArtistIds[artistId] ?? 0) >= 2 { continue }
                let secs = t.duration_ms / 1000
                if secs > 6 * 60 { continue }
                picked = t
                usedTrackIds.insert(t.id)
                usedArtistIds[artistId, default: 0] += 1
                break
            }
            if let t = picked {
                let title = t.name
                let artist = t.artists.first?.name ?? "Unknown"
                let preview = PreviewItemOut(id: t.id,
                                             title: title,
                                             artist: artist,
                                             imageURL: nil,
                                             durationMs: t.duration_ms,
                                             effort: effort)
                result.append(preview)
            }
        }
        return result
    }

    /// Replace a single preview track matching effort, avoiding excluded IDs
    func replaceTrackForPreview(effort: LocalGenerator.EffortTier, excluding: Set<String>) async throws -> PreviewItemOut {
        let market = try? await getProfileMarket()
        let (minTempo, maxTempo) = tempoRange(for: effort)
        let candidates = try await fetchRecommendationCandidates(minBPM: minTempo, maxBPM: maxTempo, genres: [], decades: [], market: market)
        for t in candidates.shuffled() {
            if excluding.contains(t.id) { continue }
            let secs = t.duration_ms / 1000
            if secs > 6 * 60 { continue }
            return PreviewItemOut(id: t.id,
                                  title: t.name,
                                  artist: t.artists.first?.name ?? "Unknown",
                                  imageURL: nil,
                                  durationMs: t.duration_ms,
                                  effort: effort)
        }
        // Fallback to first candidate
        let t = candidates.first!
        return PreviewItemOut(id: t.id,
                              title: t.name,
                              artist: t.artists.first?.name ?? "Unknown",
                              imageURL: nil,
                              durationMs: t.duration_ms,
                              effort: effort)
    }

    /// Confirm and create a playlist from preview tracks
    func createConfirmedPlaylist(from preview: PreviewRun) async throws -> URL {
        let durLabel: String = {
            if let m = preview.customMinutes { return "\(m) min" } else { return preview.duration.displayName }
        }()
        let name = "RunClub · \(preview.template.rawValue) · \(durLabel) · \(Date().formatted(date: .numeric, time: .omitted))"
        let description = "RunClub · \(preview.template.rawValue) · \(durLabel)"
        let uris = preview.tracks.map { "spotify:track:\($0.id)" }
        return try await createPlaylist(name: name, description: description, isPublic: true, uris: uris)
    }
}

