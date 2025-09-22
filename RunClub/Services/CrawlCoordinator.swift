//
//  CrawlCoordinator.swift
//  RunClub
//
//  Created by AI Assistant on 8/25/25.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
final class CrawlCoordinator: ObservableObject {
    var progress: CrawlProgressStore
    private var crawler: LibraryCrawler?
    private var modelContext: ModelContext?

    init(progress: CrawlProgressStore = CrawlProgressStore()) {
        self.progress = progress
    }


    func configure(auth: AuthService, modelContext: ModelContext, progressStore: CrawlProgressStore) async {
        self.modelContext = modelContext
        self.progress = progressStore
        let spotify = SpotifyService()
        if let token = await auth.accessToken() {
            spotify.accessTokenProvider = { token }
        }
        let market = try? await spotify.getProfileMarket()
        self.crawler = LibraryCrawler(spotify: spotify, modelContext: modelContext, marketProvider: { market }, progressStore: progressStore)
    }

    func startIfNeeded() async {
        guard let modelContext, let crawler else { return }
        let state = try? modelContext.fetch(FetchDescriptor<CrawlState>()).first
        let tracksCount = (try? modelContext.fetch(FetchDescriptor<CachedTrack>()).count) ?? 0
        if tracksCount == 0 || (state?.nextOffset ?? 0) > 0 {
            await crawler.startOrResume()
        }
    }

    func refresh() async {
        guard let crawler else { return }
        try? await crawler.refreshFromScratch()
        await crawler.startOrResume()
    }

    func cancel() async {
        await crawler?.cancel()
    }
}


