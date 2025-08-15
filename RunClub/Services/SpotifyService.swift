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
    private struct Me: Decodable { let id: String }
    private struct SavedTracks: Decodable {
        struct Item: Decodable {
            struct Track: Decodable { let uri: String }
            let track: Track
        }
        let items: [Item]
    }
    private struct PlaylistCreateResponse: Decodable {
        let id: String
        let external_urls: [String: String]
    }

    // MARK: - Helpers
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

    // MARK: - Public: simple smoke test
    /// Creates a private playlist from your recent liked tracks and returns its web URL.
    func createSimplePlaylistFromLikes(name: String) async throws -> URL {
        // 1) Who am I?
        let (meData, _) = try await URLSession.shared.data(
            for: request(URL(string: "https://api.spotify.com/v1/me")!)
        )
        let me = try JSONDecoder().decode(Me.self, from: meData)

        // 2) Get liked tracks (first 20)
        let (likesData, _) = try await URLSession.shared.data(
            for: request(URL(string: "https://api.spotify.com/v1/me/tracks?limit=20")!)
        )
        let likes = try JSONDecoder().decode(SavedTracks.self, from: likesData)
        let uris = likes.items.map { $0.track.uri }

        // 3) Create playlist
        let createBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "description": "RunClub test playlist",
            "public": false
        ])
        let (plData, _) = try await URLSession.shared.data(
            for: request(URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!,
                         method: "POST",
                         body: createBody)
        )
        let pl = try JSONDecoder().decode(PlaylistCreateResponse.self, from: plData)

        // 4) Add tracks (cap ~15 just to test)
        let addBody = try JSONSerialization.data(withJSONObject: [
            "uris": Array(uris.prefix(15))
        ])
        _ = try await URLSession.shared.data(
            for: request(URL(string: "https://api.spotify.com/v1/playlists/\(pl.id)/tracks")!,
                         method: "POST",
                         body: addBody)
        )

        // 5) Return the playlist’s web URL
        let urlString = pl.external_urls["spotify"] ?? "https://open.spotify.com/playlist/\(pl.id)"
        return URL(string: urlString)!
    }
}

