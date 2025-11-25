//
//  PlaylistsCrawler.swift
//  RunClub
//
//  Syncs selected playlists (and synthetic Recently Played) into the Playlists store.
//

import Foundation
import SwiftData

actor PlaylistsCrawler {
    private let spotify: SpotifyService
    private let repo: PlaylistsRepository
    private weak var progress: CrawlProgressStore?
    private let ctx: ModelContext
    private let likesCtx: ModelContext
    private var isCancelled: Bool = false

    init(spotify: SpotifyService,
         repository: PlaylistsRepository = PlaylistsRepository(),
         progress: CrawlProgressStore?,
         context: ModelContext = PlaylistsDataStack.shared.context,
         likesContext: ModelContext) {
        self.spotify = spotify
        self.repo = repository
        self.progress = progress
        self.ctx = context
        self.likesCtx = likesContext
    }

    func cancel() {
        isCancelled = true
        Task { @MainActor [weak progress] in progress?.isRunning = false }
    }

    /// Refreshes all selected playlists and the synthetic 'recently-played' if selected.
    func refreshSelected() async {
        if isCancelled { isCancelled = false }
        let ingestStart = Date()
        var totalAdded = 0
        // Background ingestors for enrichment (features + artists)
        let featuresIngestor = FeaturesIngestor(modelContext: ctx,
                                                recco: ReccoBeatsService(),
                                                cache: ReccoIdCache(),
                                                progress: progress)
        let artistsIngestor = ArtistsIngestor(modelContext: ctx,
                                              spotify: spotify,
                                              progress: progress)
        
        // Pipeline enrichment: collect track IDs and enrich in batches
        var pendingEnrichmentIds: [String] = []
        var enrichmentTasks: [Task<Void, Never>] = []
        let enrichmentBatchThreshold = 200
        
        await MainActor.run { [weak progress] in
            progress?.isRunning = true
            progress?.message = "Syncing playlists…"
            progress?.tracksDone = 0
            progress?.tracksTotal = 0
            progress?.featuresDone = 0
            progress?.artistsDone = 0
        }
        // Fetch selected playlists metadata
        var selected: [CachedPlaylist] = []
        await MainActor.run {
            let all = (try? ctx.fetch(FetchDescriptor<CachedPlaylist>())) ?? []
            selected = all.filter { $0.selectedForSync }
        }
        // Prune: remove memberships for de-selected playlists, then delete tracks not referenced by any remaining membership
        await pruneDeselectedData(keepPlaylistIds: Set(selected.map { $0.id }))
        // Handle synthetic Recently Played first if present
        if let rp = selected.first(where: { $0.id == "recently-played" }) {
            let (count, ids) = await syncRecentlyPlayed(playlist: rp,
                                                 artistsIngestor: artistsIngestor)
            totalAdded += count
            pendingEnrichmentIds.append(contentsOf: ids)
        }
        // Then handle real playlists
        for p in selected where p.id != "recently-played" {
            if isCancelled { break }
            let (count, ids) = await syncPlaylist(p,
                                           artistsIngestor: artistsIngestor)
            totalAdded += count
            pendingEnrichmentIds.append(contentsOf: ids)
            
            // Kick off enrichment batch if threshold reached
            if pendingEnrichmentIds.count >= enrichmentBatchThreshold {
                let idsToEnrich = pendingEnrichmentIds
                pendingEnrichmentIds = []
                let task = Task {
                    await featuresIngestor.enrichBatchNow(idsToEnrich)
                }
                enrichmentTasks.append(task)
            }
        }
        
        // Enrich any remaining pending IDs
        await MainActor.run { [weak progress] in
            progress?.message = "Finishing enrichment…"
        }
        if !pendingEnrichmentIds.isEmpty {
            let remainingTask = Task {
                await featuresIngestor.enrichBatchNow(pendingEnrichmentIds)
            }
            enrichmentTasks.append(remainingTask)
        }
        
        // Wait for all enrichment tasks
        for task in enrichmentTasks {
            await task.value
        }
        
        // Flush artist enrichment
        await artistsIngestor.flushAndWait()
        
        await MainActor.run { [weak progress] in progress?.isRunning = false }
        // Metrics
        let secs = Date().timeIntervalSince(ingestStart)
        if totalAdded > 0 && secs > 0 {
            UserDefaults.standard.set(secs, forKey: "playlistsIngestDurationSec")
            UserDefaults.standard.set(totalAdded, forKey: "playlistsIngestTracks")
            UserDefaults.standard.set(Double(totalAdded) / secs, forKey: "playlistsIngestTPS")
        }
    }

    // Remove memberships for playlists not selected and delete any tracks left with no memberships
    private func pruneDeselectedData(keepPlaylistIds: Set<String>) async {
        await MainActor.run {
            // 1) Delete memberships for deselected playlists
            let memberships = (try? ctx.fetch(FetchDescriptor<PlaylistMembership>())) ?? []
            var trackIdCounts: [String: Int] = [:]
            for m in memberships {
                if keepPlaylistIds.contains(m.playlistId) {
                    trackIdCounts[m.trackId, default: 0] += 1
                } else {
                    ctx.delete(m)
                }
            }
            try? ctx.save()
            // 2) Recompute track references post-deletion and remove orphan tracks + features
            let remaining = (try? ctx.fetch(FetchDescriptor<PlaylistMembership>())) ?? []
            var stillReferenced: Set<String> = Set(remaining.map { $0.trackId })
            let allTracks = (try? ctx.fetch(FetchDescriptor<CachedTrack>())) ?? []
            for t in allTracks {
                if !stillReferenced.contains(t.id) {
                    // Delete AudioFeature first if present
                    let tid = t.id
                    if let af = ((try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { $0.trackId == tid })))?.first) {
                        ctx.delete(af)
                    }
                    ctx.delete(t)
                }
            }
            try? ctx.save()
        }
    }

    /// Returns (count, trackIds) for pipelined enrichment
    private func syncRecentlyPlayed(playlist: CachedPlaylist,
                                    artistsIngestor: ArtistsIngestor) async -> (Int, [String]) {
        if isCancelled { return (0, []) }
        let market = (try? await spotify.getProfileMarket()) ?? "US"
        do {
            let items = try await spotify.getRecentlyPlayed(limit: 50, market: market)
            // Upsert tracks
            let tracks: [CachedTrack] = items.map { i in
                CachedTrack(id: i.trackId,
                            name: i.name,
                            artistId: i.artistId,
                            artistName: i.artistName,
                            durationMs: i.durationMs,
                            albumName: i.albumName,
                            albumReleaseYear: i.albumReleaseYear,
                            popularity: i.popularity,
                            explicit: i.explicit,
                            addedAt: i.addedAt,
                            isPlayable: true)
            }
            await MainActor.run {
                do { try repo.upsertTracks(tracks) } catch { }
            }
            // Collect IDs for pipelined enrichment
            let trackIds = items.map { $0.trackId }
            let artistIds = Array(Set(items.map { $0.artistId }))
            await artistsIngestor.enqueue(artistIds)
            // Upsert memberships (for all, including those present in likes)
            let pairs = items.map { (trackId: $0.trackId, addedAt: $0.addedAt as Date?) }
            await MainActor.run {
                do { try repo.upsertMemberships(playlistId: playlist.id, items: pairs) } catch { }
                playlist.totalTracks = items.count
                playlist.lastSyncedAt = Date()
                try? ctx.save()
            }
            await MainActor.run { [weak progress] in
                progress?.tracksDone += items.count
                progress?.tracksTotal += items.count
            }
            return (items.count, trackIds)
        } catch {
            // non-fatal
            return (0, [])
        }
    }

    /// Returns (count, trackIds) for pipelined enrichment
    private func syncPlaylist(_ playlist: CachedPlaylist,
                              artistsIngestor: ArtistsIngestor) async -> (Int, [String]) {
        if isCancelled { return (0, []) }
        let market = (try? await spotify.getProfileMarket()) ?? "US"
        var offset = 0
        var total: Int? = nil
        var added = 0
        var allTrackIds: [String] = []
        await MainActor.run { [weak progress] in
            progress?.message = "Syncing \(playlist.name)…"
        }
        var allPairs: [(String, Date?)] = []
        while true {
            if isCancelled { break }
            do {
                let page = try await spotify.getPlaylistTracksPage(playlistId: playlist.id, limit: 100, offset: offset, market: market)
                total = total ?? page.total
                // Upsert tracks
                let tracks: [CachedTrack] = page.items.map { i in
                    CachedTrack(id: i.trackId,
                                name: i.name,
                                artistId: i.artistId,
                                artistName: i.artistName,
                                durationMs: i.durationMs,
                                albumName: i.albumName,
                                albumReleaseYear: i.albumReleaseYear,
                                popularity: i.popularity,
                                explicit: i.explicit,
                                addedAt: i.addedAt,
                                isPlayable: true)
                }
                await MainActor.run {
                    do { try repo.upsertTracks(tracks) } catch { }
                }
                // Collect IDs for pipelined enrichment
                let trackIds = page.items.map { $0.trackId }
                let artistIds = Array(Set(page.items.map { $0.artistId }))
                allTrackIds.append(contentsOf: trackIds)
                await artistsIngestor.enqueue(artistIds)
                // Collect membership pairs
                for it in page.items { allPairs.append((it.trackId, it.addedAt)) }
                await MainActor.run { [weak progress] in
                    let cur = progress?.tracksDone ?? 0
                    progress?.tracksDone = cur + page.items.count
                    progress?.tracksTotal = max(progress?.tracksTotal ?? 0, total ?? cur + page.items.count)
                }
                added += page.items.count
                if let next = page.nextOffset {
                    offset = next
                } else {
                    break
                }
            } catch {
                break
            }
        }
        if !allPairs.isEmpty {
            await MainActor.run {
                do { try repo.upsertMemberships(playlistId: playlist.id, items: allPairs.map { (trackId: $0.0, addedAt: $0.1) }) } catch { }
                playlist.totalTracks = allPairs.count
                playlist.lastSyncedAt = Date()
                try? ctx.save()
            }
        }
        return (added, allTrackIds)
    }
}


