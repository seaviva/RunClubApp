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

    // Public lightweight DTO for external callers
    struct RecCandidate {
        let id: String
        let uri: String
        let name: String
        let popularity: Int
        let explicit: Bool
        let durationMs: Int
        let albumReleaseDate: String
        let artistId: String
        let artistName: String
    }

    // Public wrapper to fetch recommendation candidates for given tempo band and filters.
    // Maps to a lightweight DTO for consumption by crawlers/services outside this class.
    func getRecommendationCandidates(minBPM: Double,
                                     maxBPM: Double,
                                     genres: [Genre],
                                     decades: [Decade],
                                     market: String?) async throws -> [RecCandidate] {
        let tracks = try await fetchRecommendationCandidates(minBPM: minBPM,
                                                             maxBPM: maxBPM,
                                                             genres: genres,
                                                             decades: decades,
                                                             market: market)
        return tracks.map { t in
            RecCandidate(id: t.id,
                         uri: t.uri,
                         name: t.name,
                         popularity: t.popularity,
                         explicit: t.explicit,
                         durationMs: t.duration_ms,
                         albumReleaseDate: t.album.release_date,
                         artistId: t.artists.first?.id ?? t.id,
                         artistName: t.artists.first?.name ?? "?")
        }
    }

    // MARK: - Public: User Top Seeds
    enum TimeRange: String { case short_term, medium_term, long_term }

    func getUserTopArtistIds(limit: Int = 20, timeRange: TimeRange = .medium_term) async throws -> [String] {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/top/artists")!
        comps.queryItems = [
            .init(name: "limit", value: String(max(1, min(50, limit)))),
            .init(name: "time_range", value: timeRange.rawValue)
        ]
        let data = try await fetch(request(comps.url!), label: "GET /v1/me/top/artists")
        let res = try JSONDecoder().decode(TopArtistsResponse.self, from: data)
        return res.items.map { $0.id }
    }

    func getUserTopTrackIds(limit: Int = 50, timeRange: TimeRange = .medium_term) async throws -> [String] {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/top/tracks")!
        comps.queryItems = [
            .init(name: "limit", value: String(max(1, min(50, limit)))),
            .init(name: "time_range", value: timeRange.rawValue)
        ]
        let data = try await fetch(request(comps.url!), label: "GET /v1/me/top/tracks")
        let res = try JSONDecoder().decode(TopTracksResponse.self, from: data)
        return res.items.map { $0.id }
    }

    // MARK: - Public: Advanced recommendation candidates (seeds + targets)
    func getRecommendationCandidatesAdvanced(minBPM: Double,
                                             maxBPM: Double,
                                             seedArtists: [String],
                                             seedTracks: [String],
                                             seedGenres: [Genre],
                                             market: String?,
                                             targetEnergy: Double?,
                                             targetDanceability: Double?,
                                             targetValence: Double?,
                                             targetPopularity: Int?) async throws -> [RecCandidate] {
        // Build seeds with a hard cap of 5 combined across artists/tracks/genres
        let shuffledArtists = Array(seedArtists.shuffled())
        let shuffledTracks = Array(seedTracks.shuffled())
        let genreTokens: [String] = {
            guard let s = seedGenreString(from: seedGenres), !s.isEmpty else { return [] }
            return s.split(separator: ",").map { String($0) }
        }()

        var remaining = 5
        let pickedTracks = Array(shuffledTracks.prefix(min(remaining, shuffledTracks.count)))
        remaining -= pickedTracks.count
        let pickedArtists = Array(shuffledArtists.prefix(min(remaining, shuffledArtists.count)))
        remaining -= pickedArtists.count
        let pickedGenres = Array(genreTokens.prefix(max(0, remaining)))

        func buildQueryItems(minTempo: Double, maxTempo: Double,
                             includeEnergy: Bool, includeDance: Bool, includeValence: Bool, includePopularity: Bool) -> [URLQueryItem] {
            var items: [URLQueryItem] = [
                .init(name: "limit", value: "100"),
                .init(name: "min_tempo", value: String(Int(minTempo))),
                .init(name: "target_tempo", value: String(Int((minTempo + maxTempo) / 2))),
                .init(name: "max_tempo", value: String(Int(maxTempo)))
            ]
            if let market { items.append(.init(name: "market", value: market)) }
            if !pickedArtists.isEmpty { items.append(.init(name: "seed_artists", value: pickedArtists.joined(separator: ","))) }
            if !pickedTracks.isEmpty { items.append(.init(name: "seed_tracks", value: pickedTracks.joined(separator: ","))) }
            if !pickedGenres.isEmpty { items.append(.init(name: "seed_genres", value: pickedGenres.joined(separator: ","))) }
            if pickedArtists.isEmpty && pickedTracks.isEmpty && pickedGenres.isEmpty {
                items.append(.init(name: "seed_genres", value: "pop"))
            }
            // Broad filters: minimum energy/danceability 0.25; minimum popularity 25.
            if includeEnergy { items.append(.init(name: "min_energy", value: String(format: "%.2f", 0.25))) }
            if includeDance { items.append(.init(name: "min_danceability", value: String(format: "%.2f", 0.25))) }
            // Valence intentionally omitted
            if includePopularity { items.append(.init(name: "min_popularity", value: "25")) }
            return items
        }

        func exec(_ items: [URLQueryItem], label: String) async throws -> [RecCandidate] {
            var comps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
            comps.queryItems = items
            if let url = comps.url { print("Adv Recs URL:", url.absoluteString) }
            let recData = try await fetch(request(comps.url!), label: label)
            let recs = try JSONDecoder().decode(RecommendationResponse.self, from: recData)
            return recs.tracks.map { t in
                RecCandidate(id: t.id,
                             uri: t.uri,
                             name: t.name,
                             popularity: t.popularity,
                             explicit: t.explicit,
                             durationMs: t.duration_ms,
                             albumReleaseDate: t.album.release_date,
                             artistId: t.artists.first?.id ?? t.id,
                             artistName: t.artists.first?.name ?? "?")
            }
        }

        // Attempt 1: strict (all hints)
        do {
            var items = buildQueryItems(minTempo: minBPM, maxTempo: maxBPM,
                                        includeEnergy: true, includeDance: true, includeValence: true, includePopularity: true)
            var result = try await exec(items, label: "GET /v1/recommendations (adv)")
            if !result.isEmpty { return result }

            // Attempt 2: drop popularity and feature targets
            items = buildQueryItems(minTempo: minBPM, maxTempo: maxBPM,
                                    includeEnergy: false, includeDance: false, includeValence: false, includePopularity: false)
            result = try await exec(items, label: "GET /v1/recommendations (adv,no-hints)")
            if !result.isEmpty { return result }

            // Attempt 3: widen tempo slightly
            let widenedLo = max(60, minBPM - 5)
            let widenedHi = min(220, maxBPM + 5)
            items = buildQueryItems(minTempo: widenedLo, maxTempo: widenedHi,
                                    includeEnergy: false, includeDance: false, includeValence: false, includePopularity: false)
            result = try await exec(items, label: "GET /v1/recommendations (adv,widen)")
            if !result.isEmpty { return result }
        } catch {
            // fallthrough to genre→artist→top-tracks fallback below
        }

        // Fallback: broaden by genre search → artist top tracks
        let market = market
        let genresToUse = (seedGenres.isEmpty ? [.pop] : seedGenres).map { $0.rawValue.lowercased() }
        var artistIds: [String] = []
        for g in genresToUse { artistIds.append(contentsOf: (try? await searchArtistIds(for: g, market: market, limit: 20)) ?? []) }
        artistIds = Array(Array(Set(artistIds)).prefix(20))
        var tracks: [ArtistTopTracksResponse.Track] = []
        for aid in artistIds { tracks.append(contentsOf: (try? await fetchTopTracks(for: aid, market: market)) ?? []) }
        return tracks.map { t in
            RecCandidate(id: t.id,
                         uri: t.uri,
                         name: t.name,
                         popularity: t.popularity,
                         explicit: t.explicit,
                         durationMs: t.duration_ms,
                         albumReleaseDate: t.album.release_date,
                         artistId: t.artists.first?.id ?? t.id,
                         artistName: t.artists.first?.name ?? "?")
        }
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

    // MARK: - Helpers: Add tracks with chunking (100 per request)
    private func addTracksChunked(playlistId: String, uris: [String]) async throws {
        guard !uris.isEmpty else { return }
        let chunkSize = 100
        var index = 0
        while index < uris.count {
            let end = min(index + chunkSize, uris.count)
            let chunk = Array(uris[index..<end])
            let addBody = try JSONSerialization.data(withJSONObject: ["uris": chunk])
            _ = try await fetch(request(URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks")!,
                                  method: "POST",
                                  body: addBody), label: "POST /v1/playlists/{id}/tracks (chunk)")
            index = end
        }
    }

    // MARK: - Likes (Library) helpers
    func isTrackLiked(id: String) async throws -> Bool {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks/contains")!
        comps.queryItems = [.init(name: "ids", value: id)]
        let data = try await fetch(request(comps.url!), label: "GET /v1/me/tracks/contains")
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Bool], let first = arr.first { return first }
        return false
    }

    func likeTrack(id: String) async throws {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [.init(name: "ids", value: id)]
        _ = try await fetch(request(comps.url!, method: "PUT"), label: "PUT /v1/me/tracks")
    }

    func unlikeTrack(id: String) async throws {
        var comps = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        comps.queryItems = [.init(name: "ids", value: id)]
        _ = try await fetch(request(comps.url!, method: "DELETE"), label: "DELETE /v1/me/tracks")
    }

    private func fetch(_ request: URLRequest, label: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // Try to obtain a fresh token from Juky (headless) and retry once
            _ = await JukyHeadlessRefresher.refreshToken()
            if let fresh = await AuthService.sharedToken() {
                var retried = request
                var headers = retried.allHTTPHeaderFields ?? [:]
                headers["Authorization"] = "Bearer \(fresh)"
                retried.allHTTPHeaderFields = headers
                let (data2, response2) = try await URLSession.shared.data(for: retried)
                guard let http2 = response2 as? HTTPURLResponse else { return data2 }
                guard (200...299).contains(http2.statusCode) else {
                    let body2 = String(data: data2, encoding: .utf8) ?? ""
                    throw SpotifyServiceError.http(status: http2.statusCode, body: body2, endpoint: label)
                }
                return data2
            }
        }
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
            try await addTracksChunked(playlistId: pl.id, uris: uris)

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

    func fetchArtistsGenresMap(ids: [String]) async throws -> [String: [String]] {
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

    // MARK: - Public: simple smoke test
    /// Legacy helper retained for API compatibility. Use `LocalGenerator` flows instead.
    func createSimplePlaylistFromLikes(name: String) async throws -> URL {
        throw NSError(domain: "SpotifyService",
                      code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Legacy generator removed. Use LocalGenerator flows instead."])
    }

    /// Legacy helper retained solely to satisfy builds that still call into the removed generator paths.
    private func fetchAllLikedTracks(maxTotal: Int = 200) async throws -> [SavedTracks.Item.Track] {
        _ = maxTotal // keep signature parity
        return []
    }

    // MARK: - Public: Generation (MVP Easy/Steady)
    /// Legacy generator retained for backwards compatibility. Throws until backend-backed runs ship.
    @available(*, deprecated, message: "Use LocalGenerator.generatePlaylist instead.")
    func generateSimpleRunPlaylist(name: String,
                                   template: RunTemplateType,
                                   durationCategory: DurationCategory,
                                   genres: [Genre],
                                   decades: [Decade]) async throws -> URL {
        throw NSError(domain: "SpotifyService",
                      code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "Legacy Spotify generator removed. Use LocalGenerator flows instead."])
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

    // MARK: - Diagnostics
    /// Minimal probe to validate recommendations with a single seed genre and no feature hints.
    /// Returns the count and logs raw body when empty to help diagnose token/account behavior.
    func probeRecommendationsSimple(genre: String = "pop", limit: Int = 10) async -> (count: Int, sampleIds: [String]) {
        var comps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        comps.queryItems = [
            .init(name: "limit", value: String(max(1, min(100, limit)))),
            .init(name: "seed_genres", value: genre)
        ]
        do {
            let data = try await fetch(request(comps.url!), label: "GET /v1/recommendations (probe)")
            let recs = try JSONDecoder().decode(RecommendationResponse.self, from: data)
            let ids = recs.tracks.map { $0.id }
            print("Probe recs — genre=\(genre) limit=\(limit) -> count=\(ids.count)")
            return (ids.count, Array(ids.prefix(5)))
        } catch {
            // Print raw body if HTTP; otherwise just print error
            if case let SpotifyServiceError.http(status, body, endpoint) = error {
                print("Probe recs HTTP error — status=\(status) endpoint=\(endpoint) body=\(body.prefix(300)))")
            } else {
                print("Probe recs failed: \(error)")
            }
            return (0, [])
        }
    }

    /// Super-relaxed call: no market, only seed_genres; optionally adds a second genre.
    func probeRecommendationsSuperRelaxed(genres: [String] = ["pop"]) async -> (count: Int, sampleIds: [String]) {
        var comps = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        comps.queryItems = [
            .init(name: "limit", value: "20"),
            .init(name: "seed_genres", value: genres.joined(separator: ","))
        ]
        do {
            let data = try await fetch(request(comps.url!), label: "GET /v1/recommendations (super)")
            let recs = try JSONDecoder().decode(RecommendationResponse.self, from: data)
            let ids = recs.tracks.map { $0.id }
            print("Probe super — genres=\(genres) -> count=\(ids.count)")
            return (ids.count, Array(ids.prefix(5)))
        } catch {
            if case let SpotifyServiceError.http(status, body, endpoint) = error {
                print("Probe super HTTP error — status=\(status) endpoint=\(endpoint) body=\(body.prefix(300)))")
            } else {
                print("Probe super failed: \(error)")
            }
            return (0, [])
        }
    }
}

