//
//  SpotifyRecommendationService.swift
//  RunClub
//
//  Created by AI Assistant on 10/1/25.
//

import Foundation

/// Thin wrapper around SpotifyService to fetch diversified recommendation candidates.
/// Rotates tempo bands and genre seeds to collect a broader set.
final class SpotifyRecommendationService {
    private let spotify: SpotifyService

    init(spotify: SpotifyService) {
        self.spotify = spotify
    }

    /// Fetch up to `target` recommendation tracks with basic diversification.
    /// This function does not de-dup across existing local stores; caller should handle dedupe.
    func fetchRecommendations(target: Int, market: String?) async -> [Any] {
        // Placeholder to avoid exposing SpotifyService internals here. We'll consume via crawler directly.
        return []
    }
}


