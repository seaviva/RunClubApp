//
//  LibraryCrawler.swift
//  RunClub
//
//  Created by AI Assistant on 8/25/25.
//

import Foundation
import SwiftData

class CrawlProgressStore: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var tracksDone: Int = 0
    @Published var tracksTotal: Int = 0
    @Published var featuresDone: Int = 0
    @Published var artistsDone: Int = 0
    @Published var message: String = ""
    // Debug source tag to distinguish stores in logs/UI (e.g., LIKES or RECS)
    var debugName: String = "GENERIC"
}

actor LibraryCrawler {
    private let spotify: SpotifyService
    private let modelContext: ModelContext
    private let marketProvider: () -> String?
    private weak var progressStore: CrawlProgressStore?
    private var isCancelledFlag: Bool = false

    init(spotify: SpotifyService,
         modelContext: ModelContext,
         marketProvider: @escaping () -> String?,
         progressStore: CrawlProgressStore?) {
        self.spotify = spotify
        self.modelContext = modelContext
        self.marketProvider = marketProvider
        self.progressStore = progressStore
    }

    func cancel() {
        isCancelledFlag = true
        // Immediately update UI state for responsiveness
        Task { @MainActor [weak progressStore] in
            progressStore?.isRunning = false
        }
    }

    func refreshFromScratch() async throws {
        try await MainActor.run {
            // Clear all cached entities
            try modelContext.delete(model: CachedTrack.self)
            try modelContext.delete(model: AudioFeature.self)
            try modelContext.delete(model: CachedArtist.self)
            // Preserve CrawlState so we can track runs; reset fields
            if let cs = try? modelContext.fetch(FetchDescriptor<CrawlState>()).first {
                cs.status = .idle
                cs.nextOffset = 0
                cs.totalTracks = 0
                cs.totalFeatures = 0
                cs.totalArtists = 0
                cs.lastError = nil
                cs.lastCompletedAt = nil
            }
            try modelContext.save()
        }
    }

    func startOrResume() async {
        if isCancelledFlag { isCancelledFlag = false }
        await MainActor.run { [weak progressStore] in
            progressStore?.isRunning = true
            progressStore?.message = "Caching your library…"
            // Keep counts if resuming; only reset on fresh start
            if (progressStore?.tracksDone ?? 0) == 0 {
                progressStore?.tracksTotal = 0
                progressStore?.featuresDone = 0
                progressStore?.artistsDone = 0
            }
            if let name = progressStore?.debugName { print("[\(name)] start likes crawl") }
        }

        // Load or create crawl state on main actor
        var crawlState: CrawlState?
        await MainActor.run {
            do {
                let fetch = FetchDescriptor<CrawlState>()
                crawlState = try modelContext.fetch(fetch).first
            } catch {
                crawlState = nil
            }
            if crawlState == nil {
                crawlState = CrawlState(status: .running, nextOffset: 0)
                if let cs = crawlState { modelContext.insert(cs) }
            }
            crawlState?.status = .running
            try? modelContext.save()
        }

        let market = marketProvider() ?? "US"
        var nextOffset = crawlState?.nextOffset ?? 0
        var total: Int? = nil

        // Crawl pages
        pagingLoop: while true {
            if isCancelledFlag { break }
            do {
                // Restored page size after debugging
                let page = try await spotify.getLikedTracksPage(limit: 50, offset: nextOffset, market: market)
                total = total ?? page.total
                await MainActor.run { [weak progressStore] in
                    let total = page.total ?? max((progressStore?.tracksTotal ?? 0), nextOffset + page.items.count)
                    progressStore?.tracksTotal = total
                    progressStore?.tracksDone = min((progressStore?.tracksDone ?? 0) + page.items.count, total)
                }

                // Upsert tracks (main actor)
                var trackIds: [String] = []
                var artistIds: [String] = []
                await MainActor.run {
                    for t in page.items {
                        let ct = CachedTrack(id: t.trackId,
                                             name: t.name,
                                             artistId: t.artistId,
                                             artistName: t.artistName,
                                             durationMs: t.durationMs,
                                             albumName: t.albumName,
                                             albumReleaseYear: t.albumReleaseYear,
                                             popularity: t.popularity,
                                             explicit: t.explicit,
                                             addedAt: t.addedAt,
                                             isPlayable: true)
                        modelContext.insert(ct)
                        trackIds.append(t.trackId)
                        artistIds.append(t.artistId)
                    }
                    try? modelContext.save()
                }

                // Playability preflight per page
                if !trackIds.isEmpty && !isCancelledFlag {
                    do {
                        let playable = try await spotify.playableIds(for: trackIds, market: market)
                        await MainActor.run {
                            for tid in trackIds {
                                if let ct = try? modelContext.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.id == tid })).first {
                                    ct.isPlayable = playable.contains(tid)
                                }
                            }
                            try? modelContext.save()
                        }
                    } catch {
                        print("Playability preflight failed: \(error)")
                    }
                }

                // Fetch audio features via ReccoBeats (non-fatal on errors)
                if !trackIds.isEmpty && !isCancelledFlag {
                    let rb = ReccoBeatsService()
                    // 1) Resolve Spotify IDs -> Recco IDs once per page
                    let mapping = await rb.resolveReccoIds(spotifyIds: trackIds)
                    print("RB resolve mapped", mapping.count, "of", trackIds.count)
                    // 2) Fetch features keyed by Spotify ID
                    let featuresMap = await rb.getAudioFeaturesBulkMapped(spToRecco: mapping, maxConcurrency: 8)
                    print("RB features fetched", featuresMap.count)
                    let successCount = featuresMap.count
                    await MainActor.run {
                        for (spotifyId, f) in featuresMap {
                            let af = AudioFeature(trackId: spotifyId,
                                                  tempo: f.tempo,
                                                  energy: f.energy,
                                                  danceability: f.danceability,
                                                  valence: f.valence,
                                                  loudness: f.loudness,
                                                  key: f.key,
                                                  mode: f.mode,
                                                  timeSignature: f.timeSignature)
                            modelContext.insert(af)
                        }
                        try? modelContext.save()
                    }
                    await MainActor.run { [weak progressStore] in progressStore?.featuresDone += successCount }
                    print("RB page summary — mapped \(mapping.count) of \(trackIds.count), features saved: \(successCount)")
                }

                // Fetch artists in batches (dedup first)
                let uniqueArtistIds = Array(Set(artistIds))
                if !uniqueArtistIds.isEmpty && !isCancelledFlag {
                    do {
                        let artists = try await spotify.getArtists(ids: uniqueArtistIds)
                        await MainActor.run {
                            for (_, a) in artists {
                                let ca = CachedArtist(id: a.id, name: a.name, genres: a.genres, popularity: a.popularity)
                                modelContext.insert(ca)
                            }
                            try? modelContext.save()
                        }
                        await MainActor.run { [weak progressStore] in
                            progressStore?.artistsDone += artists.count
                        }
                    } catch {
                        print("Artists fetch failed:", String(describing: error))
                        // Skip artists on error and continue crawling
                    }
                }

                // Update paging or exit
                if isCancelledFlag {
                    break pagingLoop
                } else if let no = page.nextOffset {
                    nextOffset = no
                    await MainActor.run {
                        crawlState?.nextOffset = no
                        try? modelContext.save()
                    }
                } else {
                    break pagingLoop
                }
            } catch {
                await MainActor.run {
                    crawlState?.status = .failed
                    crawlState?.lastError = String(describing: error)
                    try? modelContext.save()
                }
                await MainActor.run { [weak progressStore] in progressStore?.isRunning = false }
                return
            }
            // Removed per-page delay to improve throughput; RB client handles 429 backoff
            if !isCancelledFlag { /* no-op */ }
        }

        let cancelledAtEnd = isCancelledFlag
        await MainActor.run {
            if cancelledAtEnd {
                crawlState?.status = .idle
            } else {
                crawlState?.status = .idle
                crawlState?.lastCompletedAt = Date()
                crawlState?.nextOffset = nil
            }
            try? modelContext.save()
        }
        await MainActor.run { [weak progressStore] in progressStore?.isRunning = false }
    }
}


