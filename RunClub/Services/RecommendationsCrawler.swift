//
//  RecommendationsCrawler.swift
//  RunClub
//
//  Created by AI Assistant on 10/1/25.
//

import Foundation
import SwiftData

/// Crawls Spotify recommendations to prefill a separate SwiftData store (~1,000 tracks) with features and artists.
actor RecommendationsCrawler {
    private let spotify: SpotifyService
    private let recRepo: RecommendedSongsRepository
    private weak var progressStore: RecsProgressStore?
    private var isCancelledFlag: Bool = false

    init(spotify: SpotifyService,
         repository: RecommendedSongsRepository = RecommendedSongsRepository(),
         progressStore: RecsProgressStore?) {
        self.spotify = spotify
        self.recRepo = repository
        self.progressStore = progressStore
    }

    func cancel() {
        isCancelledFlag = true
        Task { @MainActor [weak progressStore] in
            print("[RECS] cancel called")
            progressStore?.isRunning = false
        }
    }

    func startInitialCache(targetCount: Int = 1000) async {
        // Metadata state in recommendations store
        let recsContext = RecommendationsDataStack.shared.context
        var recsState: CrawlState? = nil
        await MainActor.run {
            recsState = (try? recsContext.fetch(FetchDescriptor<CrawlState>()).first) ?? CrawlState(status: .running, nextOffset: 0)
            if let s = recsState, (try? recsContext.fetch(FetchDescriptor<CrawlState>()).isEmpty) == true { recsContext.insert(s) }
            recsState?.status = .running
            try? recsContext.save()
        }
        await MainActor.run { [weak progressStore] in
            progressStore?.isRunning = true
            progressStore?.message = "Syncing recommendations…"
            progressStore?.tracksTotal = targetCount
            progressStore?.tracksDone = 0
            progressStore?.featuresDone = 0
            progressStore?.artistsDone = 0
            if let name = progressStore?.debugName { print("[\(name)] start recs crawl target=\(targetCount)") } else { print("[RECS] start recs crawl target=\(targetCount)") }
        }

        // Seed seen with existing track IDs to avoid re-attempting duplicates
        var seen = (try? await MainActor.run { () -> Set<String> in
            (try? recRepo.existingTrackIdsSet()) ?? []
        }) ?? Set<String>()
        var tracksSaved = 0
        // Diversify across tempo bands and seeds (use single wide band for population)
        var bands: [(Double, Double)] = [(120,200)]
        let market = (try? await spotify.getProfileMarket()) ?? "US"
        // Build seed pools
        let topArtists = (try? await spotify.getUserTopArtistIds(limit: 20, timeRange: .medium_term)) ?? []
        let topTracks = (try? await spotify.getUserTopTrackIds(limit: 50, timeRange: .medium_term)) ?? []
        // Seed genres: balanced, app-supported umbrellas
        let seedGenres: [Genre] = [.pop, .electronic, .hipHopRap, .indie, .rockAlt, .rnb, .latin, .country]

        // Rotation/low-yield control
        var bandIndex = 0
        var zeroInsertStreak = 0
        var relaxTargets = false
        var ignoreMarket = false
        var genreOnlySeeds = false
        while tracksSaved < targetCount && !isCancelledFlag {
            let band = bands[bandIndex % bands.count]
            bandIndex += 1
            do {
                // Rotate seeds: mix of artists/tracks/genres and popularity targets
                var artistSlice = Array(topArtists.shuffled().prefix(Int.random(in: 0...3)))
                var trackSlice = Array(topTracks.shuffled().prefix( max(0, 5 - artistSlice.count)))
                var genreSlice = Array(seedGenres.shuffled().prefix( max(1, 5 - artistSlice.count - trackSlice.count)))
                if genreOnlySeeds { artistSlice = []; trackSlice = []; genreSlice = Array(seedGenres.shuffled().prefix(3)) }
                let popBuckets = [55, 35, 75].shuffled()
                let targetEnergy: Double = [0.55, 0.7, 0.85].shuffled().first!
                let targetDance: Double = [0.6, 0.7, 0.8].shuffled().first!
                let targetVal: Double = [0.5, 0.6, 0.45].shuffled().first!
                let candidates = try await spotify.getRecommendationCandidatesAdvanced(minBPM: band.0,
                                                                                       maxBPM: band.1,
                                                                                       seedArtists: artistSlice,
                                                                                       seedTracks: trackSlice,
                                                                                       seedGenres: genreSlice,
                                                                                       market: (ignoreMarket ? nil : market),
                                                                                       targetEnergy: (relaxTargets ? nil : targetEnergy),
                                                                                       targetDanceability: (relaxTargets ? nil : targetDance),
                                                                                       targetValence: (relaxTargets ? nil : targetVal),
                                                                                       targetPopularity: (relaxTargets ? nil : popBuckets.first))
                // Map and upsert new tracks/artists only
                var newTracks: [CachedTrack] = []
                var needArtistIds: [String] = []
                var dupes = 0
                for t in candidates {
                    if seen.contains(t.id) { dupes += 1; continue }
                    seen.insert(t.id)
                    // Year parsing from album.release_date (yyyy or yyyy-mm-dd)
                    var year: Int? = nil
                    let parts = t.albumReleaseDate.split(separator: "-")
                    if let y = Int(parts.first ?? "") { year = y }
                    let artistId = t.artistId
                    let artistName = t.artistName
                    let ct = CachedTrack(id: t.id,
                                         name: t.name,
                                         artistId: artistId,
                                         artistName: artistName,
                                         durationMs: t.durationMs,
                                         albumName: "",
                                         albumReleaseYear: year,
                                         popularity: t.popularity,
                                         explicit: t.explicit,
                                         addedAt: Date(),
                                         isPlayable: true)
                    newTracks.append(ct)
                    needArtistIds.append(artistId)
                    if newTracks.count >= 100 { /* bound batch insert size */ }
                }
                if !newTracks.isEmpty {
                    await MainActor.run {
                        do { try recRepo.upsertTracks(newTracks) } catch {
                            print("[RECS] upsertTracks batch failed: \(error)")
                        }
                    }
                    tracksSaved += newTracks.count
                    await MainActor.run { [weak progressStore] in
                        progressStore?.tracksDone = min(tracksSaved, targetCount)
                    }
                }
                print("[RECS] band=\(Int(band.0))-\(Int(band.1)) fetched=\(candidates.count) inserted=\(newTracks.count) dupes=\(dupes) totalSaved=\(tracksSaved)")
                zeroInsertStreak = (newTracks.isEmpty ? zeroInsertStreak + 1 : 0)
                if zeroInsertStreak == 5 {
                    // First widening: expand all bands by ±5 BPM
                    bands = bands.map { (max(60, $0.0 - 5), min(220, $0.1 + 5)) }
                    print("[RECS] widening BPM windows due to low yield — bands=\(bands.map { "\(Int($0.0))-\(Int($0.1))" }.joined(separator: ","))")
                } else if zeroInsertStreak == 8 {
                    // Second widening: drop popularity targeting by passing nil next iterations
                    relaxTargets = true
                    print("[RECS] relaxing feature/popularity targets due to low yield")
                } else if zeroInsertStreak == 10 {
                    // Third: broaden by omitting market
                    ignoreMarket = true
                    print("[RECS] dropping market filter to broaden pool")
                } else if zeroInsertStreak == 12 {
                    // Fourth: force genre-only seeds
                    genreOnlySeeds = true
                    print("[RECS] forcing genre-only seeds for broader coverage")
                } else if zeroInsertStreak >= 18 {
                    // If persistently zero, break after higher threshold to avoid infinite churn
                    if tracksSaved < targetCount {
                        print("[RECS] low-yield plateau; stopping early at \(tracksSaved)")
                        break
                    }
                }

                // Fetch features via ReccoBeats for the page
                let rb = ReccoBeatsService()
                let ids = newTracks.map { $0.id }
                let mapping = await rb.resolveReccoIds(spotifyIds: ids)
                let featuresMap = await rb.getAudioFeaturesBulkMapped(spToRecco: mapping, maxConcurrency: 6)
                var featureModels: [AudioFeature] = []
                for (sid, f) in featuresMap {
                    featureModels.append(AudioFeature(trackId: sid,
                                                      tempo: f.tempo,
                                                      energy: f.energy,
                                                      danceability: f.danceability,
                                                      valence: f.valence,
                                                      loudness: f.loudness,
                                                      key: f.key,
                                                      mode: f.mode,
                                                      timeSignature: f.timeSignature))
                }
                if !featureModels.isEmpty {
                    await MainActor.run { do { try recRepo.upsertAudioFeatures(featureModels) } catch { } }
                    await MainActor.run { [weak progressStore] in progressStore?.featuresDone += featureModels.count }
                }

                // Fetch artists for new tracks
                let uniqueArtistIds = Array(Set(needArtistIds))
                if !uniqueArtistIds.isEmpty {
                    do {
                        let artists = try await spotify.getArtists(ids: uniqueArtistIds)
                        var artistModels: [CachedArtist] = []
                        for (_, a) in artists { artistModels.append(CachedArtist(id: a.id, name: a.name, genres: a.genres, popularity: a.popularity)) }
                        if !artistModels.isEmpty {
                            await MainActor.run { do { try recRepo.upsertArtists(artistModels) } catch { } }
                            await MainActor.run { [weak progressStore] in progressStore?.artistsDone += artistModels.count }
                        }
                    } catch {
                        // Skip artist enrichment on error
                    }
                }
            } catch {
                // On error, small backoff and continue
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            // Gentle pacing to avoid hammering API in tight zero-yield loops
            try? await Task.sleep(nanoseconds: 250_000_000)
            // Cooperative cancellation check between iterations
            if Task.isCancelled { isCancelledFlag = true; break }
        }

        await MainActor.run { [weak progressStore] in progressStore?.isRunning = false }
        // Update metadata on completion
        await MainActor.run {
            recsState?.status = .idle
            recsState?.lastCompletedAt = Date()
            recsState?.totalTracks = ((try? recsContext.fetch(FetchDescriptor<CachedTrack>()).count) ?? 0)
            try? recsContext.save()
        }
    }
}


