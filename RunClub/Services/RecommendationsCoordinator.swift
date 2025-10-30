//
//  RecommendationsCoordinator.swift
//  RunClub
//
//  Created by AI Assistant on 10/1/25.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class RecommendationsCoordinator: ObservableObject {
    @Published var progress: RecsProgressStore
    private var crawler: RecommendationsCrawler?
    private var runningTask: Task<Void, Never>? = nil

    init(progress: RecsProgressStore = RecsProgressStore()) {
        self.progress = progress
    }

    func configure(auth: AuthService, progressStore: RecsProgressStore? = nil) async {
        if let progressStore { self.progress = progressStore }
        let spotify = SpotifyService()
        if let token = await auth.accessToken() { spotify.accessTokenProvider = { token } }
        self.crawler = RecommendationsCrawler(spotify: spotify,
                                              repository: RecommendedSongsRepository(),
                                              progressStore: self.progress)
    }

    func startIfNeeded(targetCount: Int = 1000) async {
        guard let crawler else { return }
        // Use the recommendations store context to check if data exists
        let mc = RecommendationsDataStack.shared.context
        let tracksCount = (try? mc.fetch(FetchDescriptor<CachedTrack>()).count) ?? 0
        if tracksCount == 0 {
            runningTask?.cancel()
            runningTask = Task { await crawler.startInitialCache(targetCount: targetCount) }
        }
    }

    func refresh(targetCount: Int = 1000) async {
        guard let crawler else { return }
        runningTask?.cancel()
        runningTask = Task { await crawler.startInitialCache(targetCount: targetCount) }
    }

    func cancel() async {
        runningTask?.cancel()
        await crawler?.cancel()
    }
}


