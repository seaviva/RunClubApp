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
    // Keep track of any in-flight prefetch tasks so we can cancel them on demand
    private var prefetchQueue: [(offset: Int, task: Task<(items: [SpotifyService.SimplifiedTrackItem], nextOffset: Int?, total: Int?), Error>)] = []

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
        // Cancel any in-flight prefetches immediately to stop background paging
        for pair in prefetchQueue {
            pair.task.cancel()
        }
        prefetchQueue.removeAll()
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
                crawlState = CrawlState(status: .running, nextOffset: 0, crawlStartAt: Date())
                if let cs = crawlState { modelContext.insert(cs) }
            }
            crawlState?.status = .running
            crawlState?.crawlStartAt = Date()
            try? modelContext.save()
        }

        let market = marketProvider() ?? "US"
        var nextOffset = crawlState?.nextOffset ?? 0
        var total: Int? = nil
        var seenArtistIds: Set<String> = []
        // Background ingestors for enrichment
        let featuresIngestor = FeaturesIngestor(modelContext: modelContext,
                                                recco: ReccoBeatsService(),
                                                cache: ReccoIdCache(),
                                                progress: progressStore)
        let artistsIngestor = ArtistsIngestor(modelContext: modelContext,
                                              spotify: spotify,
                                              progress: progressStore)
        let ingestStart = Date()
        
        // Pipeline enrichment: collect track IDs and enrich in batches while fetching continues
        var pendingEnrichmentIds: [String] = []
        var enrichmentTasks: [Task<Void, Never>] = []
        let enrichmentBatchThreshold = 200  // Enrich every 200 tracks (4 pages)

        // Crawl pages with bounded prefetch depth
        var prefetchedPage: (items: [SpotifyService.SimplifiedTrackItem], nextOffset: Int?, total: Int?)? = nil
        // Ensure any stale tasks from previous runs are cancelled
        for pair in prefetchQueue { pair.task.cancel() }
        prefetchQueue.removeAll()
        pagingLoop: while true {
            if isCancelledFlag { break }
            do {
                // Fetch current page or consume prefetched result
                let page: (items: [SpotifyService.SimplifiedTrackItem], nextOffset: Int?, total: Int?)
                if let ready = prefetchedPage {
                    page = ready
                    prefetchedPage = nil
                } else {
                    page = try await spotify.getLikedTracksPage(limit: 50, offset: nextOffset, market: market)
                }
                total = total ?? page.total
                await MainActor.run { [weak progressStore] in
                    let total = page.total ?? max((progressStore?.tracksTotal ?? 0), nextOffset + page.items.count)
                    progressStore?.tracksTotal = total
                    progressStore?.tracksDone = min((progressStore?.tracksDone ?? 0) + page.items.count, total)
                }

                // Precompute identifiers
                let pageTrackIds = page.items.map { $0.trackId }
                let pageArtistIds = page.items.map { $0.artistId }
                // Determine missing artists by checking DB, then subtract what we've already seen in this run
                var missingArtistIds: [String] = []
                await MainActor.run {
                    let uniqueArtistIds = Array(Set(pageArtistIds))
                    let existingArtists = (try? modelContext.fetch(
                        FetchDescriptor<CachedArtist>(predicate: #Predicate { uniqueArtistIds.contains($0.id) })
                    )) ?? []
                    let existingIds = Set(existingArtists.map { $0.id })
                    let desired = Set(uniqueArtistIds).subtracting(existingIds).subtracting(seenArtistIds)
                    missingArtistIds = Array(desired)
                }
                seenArtistIds.formUnion(missingArtistIds)

                // Maintain a prefetch window up to Config.likesPagePrefetchDepth
                // Seed the queue starting from the immediate next offset
                if let baseNext = page.nextOffset, !isCancelledFlag {
                    // remove finished tasks
                    prefetchQueue.removeAll(where: { $0.task.isCancelled })
                    let depth = max(1, Config.likesPagePrefetchDepth)
                    // Schedule offsets baseNext, baseNext+50, baseNext+100, ...
                    var wantOffsets: [Int] = []
                    for k in 0..<depth {
                        let off = baseNext + (50 * k)
                        wantOffsets.append(off)
                    }
                    // Enqueue missing offsets
                    for off in wantOffsets {
                        if !prefetchQueue.contains(where: { $0.offset == off }) {
                            let t = Task { try await spotify.getLikedTracksPage(limit: 50, offset: off, market: market) }
                            prefetchQueue.append((offset: off, task: t))
                        }
                    }
                }

                // Upsert tracks and keep references for later updates
                var pageTrackRefs: [String: CachedTrack] = [:]
                await MainActor.run {
                    let existing = (try? modelContext.fetch(
                        FetchDescriptor<CachedTrack>(predicate: #Predicate { pageTrackIds.contains($0.id) })
                    )) ?? []
                    let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

                    for t in page.items {
                        if let ct = existingById[t.trackId] {
                            ct.name = t.name
                            ct.artistId = t.artistId
                            ct.artistName = t.artistName
                            ct.durationMs = t.durationMs
                            ct.albumName = t.albumName
                            ct.albumReleaseYear = t.albumReleaseYear
                            ct.popularity = t.popularity
                            ct.explicit = t.explicit
                            ct.addedAt = t.addedAt
                            pageTrackRefs[t.trackId] = ct
                        } else {
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
                            pageTrackRefs[t.trackId] = ct
                        }
                    }
                }

                // Pipeline enrichment: accumulate IDs and enrich in batches
                // This runs enrichment in parallel with fetching for better throughput
                if !pageTrackIds.isEmpty {
                    pendingEnrichmentIds.append(contentsOf: pageTrackIds)
                    
                    // Once we have enough IDs, kick off enrichment in background
                    if pendingEnrichmentIds.count >= enrichmentBatchThreshold {
                        let idsToEnrich = pendingEnrichmentIds
                        pendingEnrichmentIds = []
                        
                        let task = Task {
                            await featuresIngestor.enrichBatchNow(idsToEnrich)
                        }
                        enrichmentTasks.append(task)
                    }
                }
                
                // Artist enrichment still uses enqueue pattern (smaller dataset)
                if !missingArtistIds.isEmpty { await artistsIngestor.enqueue(missingArtistIds) }

                // Apply all DB updates in a single main-actor pass and save once
                await MainActor.run { [weak progressStore] in
                    try? modelContext.save()
                }

                // Update paging or exit
                if isCancelledFlag {
                    break pagingLoop
                } else if let expectedNext = page.nextOffset {
                    // Consume a prefetched page matching the expectedNext offset if available
                    if let idx = prefetchQueue.firstIndex(where: { $0.offset == expectedNext }) {
                        let pair = prefetchQueue.remove(at: idx)
                        do {
                            let pref = try await pair.task.value
                            prefetchedPage = (items: pref.items, nextOffset: pref.nextOffset, total: pref.total)
                            nextOffset = expectedNext
                        } catch {
                            // Prefetch failed; fall back to sequential progression
                            nextOffset = expectedNext
                        }
                    } else {
                        // No prefetched page found; proceed to expected next offset
                        nextOffset = expectedNext
                    }
                    await MainActor.run {
                        crawlState?.nextOffset = nextOffset
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

        // Regardless of outcome, ensure no dangling prefetches remain
        for pair in prefetchQueue { pair.task.cancel() }
        prefetchQueue.removeAll()

        let cancelledAtEnd = isCancelledFlag
        let ps = self.progressStore
        await MainActor.run {
            if cancelledAtEnd {
                crawlState?.status = .idle
            } else {
                crawlState?.status = .idle
                crawlState?.lastCompletedAt = Date()
                crawlState?.nextOffset = nil
                ps?.message = "Finishing enrichment…"
            }
            try? modelContext.save()
        }
        
        // Finish enrichment only if not cancelled; otherwise leave for a future run
        if !cancelledAtEnd {
            // Enrich any remaining pending IDs
            if !pendingEnrichmentIds.isEmpty {
                let remainingTask = Task {
                    await featuresIngestor.enrichBatchNow(pendingEnrichmentIds)
                }
                enrichmentTasks.append(remainingTask)
            }
            
            // Wait for all in-flight enrichment tasks to complete
            for task in enrichmentTasks {
                await task.value
            }
            
            // Finish artist enrichment
            await artistsIngestor.flushAndWait()
        }
        // Metrics
        await MainActor.run { [weak progressStore] in
            let secs: TimeInterval = {
                if let start = try? modelContext.fetch(FetchDescriptor<CrawlState>()).first?.crawlStartAt {
                    return Date().timeIntervalSince(start ?? ingestStart)
                }
                return Date().timeIntervalSince(ingestStart)
            }()
            let tracks = progressStore?.tracksDone ?? 0
            if tracks > 0 && secs > 0 {
                let tps = Double(tracks) / secs
                UserDefaults.standard.set(secs, forKey: "likesIngestDurationSec")
                UserDefaults.standard.set(tracks, forKey: "likesIngestTracks")
                UserDefaults.standard.set(tps, forKey: "likesIngestTPS")
            }
        }
        await MainActor.run { [weak progressStore] in progressStore?.isRunning = false }
    }
}


