//
//  LocalGenerator.swift
//  RunClub
//
//  Scaffolding for local playlist generation using SwiftData cache.
//  This service will build effort curves, select tracks, and create a playlist via Spotify.
//

import Foundation
import SwiftData

final class LocalGenerator {
    enum GenerationError: Error, LocalizedError {
        case notImplemented
        var errorDescription: String? {
            switch self {
            case .notImplemented: return "Local generator not implemented yet"
            }
        }
    }
    // MARK: - Public helpers for run orchestration
    // Expose planned slots and segment counts for a given template/runMinutes.
    func plannedSlots(template: RunTemplateType, runMinutes: Int) -> [Slot] {
        return buildEffortTimeline(template: template, minutes: runMinutes)
    }

    func plannedSegmentCounts(template: RunTemplateType, runMinutes: Int) -> (wuSlots: Int, coreSlots: Int, cdSlots: Int) {
        let planMins = durationPlan(for: template, minutes: runMinutes)
        // Use empirical average track length estimate to map minutes→slots
        let avgTrackSecs = 210.0 // default estimate; dynamic average used during selection
        let wuSlots = max(1, Int(round(Double(planMins.wu * 60) / avgTrackSecs)))
        let coreSlots = max(1, Int(round(Double(planMins.core * 60) / avgTrackSecs)))
        var cdSlots = max(1, Int(round(Double(planMins.cd * 60) / avgTrackSecs)))
        if planMins.cd >= 5 { cdSlots = max(cdSlots, 2) } // prefer at least 2 cooldown tracks for 5m target
        return (wuSlots, coreSlots, cdSlots)
    }

    private let modelContext: ModelContext
    // Playlists store context (owned/followed + recently played)
    private let playlistsContext: ModelContext
    // Third-source static catalog context
    private let thirdSourceContext: ModelContext
    // Optional sink used by dry-run to collect log lines
    private var debugSink: ((String) -> Void)? = nil

    init(modelContext: ModelContext,
         playlistsContext: ModelContext = PlaylistsDataStack.shared.context,
         thirdSourceContext: ModelContext = ThirdSourceDataStack.shared.context) {
        self.modelContext = modelContext
        self.playlistsContext = playlistsContext
        self.thirdSourceContext = thirdSourceContext
    }

    private func emit(_ line: String) {
        print(line)
        debugSink?(line)
    }

    // Public entrypoint: create a Spotify playlist and return its URL using local selection
    func generatePlaylist(name: String,
                          template: RunTemplateType,
                          runMinutes: Int,
                          genres: [Genre],
                          decades: [Decade],
                          spotify: SpotifyService) async throws -> URL {
        // 1) Select local candidates honoring rules, rediscovery, relaxations
        let market = (try? await spotify.getProfileMarket()) ?? "US"
        let isPlayable: ((String) async -> Bool) = { trackId in
            do {
                let set = try await spotify.playableIds(for: [trackId], market: market)
                return set.contains(trackId)
            } catch { return true }
        }
        let sel = try await selectCandidates(template: template,
                                       runMinutes: runMinutes,
                                       genres: genres,
                                       decades: decades,
                                       isPlayable: isPlayable)

        // Guard: do not create empty playlist; fallback early
        if sel.selected.isEmpty {
            throw GenerationError.notImplemented // trigger upstream fallback
        }

        // 2) Duration polish: nudge within template-aligned bounds by optionally dropping/adding edge tracks
        // Use plan-aligned bounds for all templates: ±2 minutes around plan.total
        let postPlan = durationPlan(for: template, minutes: runMinutes)
        var minSeconds = max(0, (postPlan.total - 2) * 60)
        var maxSeconds = (postPlan.total + 2) * 60
        var chosen = sel.selected
        var total = sel.totalSeconds

        // If over, drop from the end until within bounds
        while total > maxSeconds && !chosen.isEmpty {
            let idx = chosen.count - 1
            let secs = chosen[idx].track.durationMs / 1000
            // Always drop last if it helps; stop if dropping would go below minSeconds and there is only one choice
            if total - secs >= minSeconds || chosen.count > 1 {
                total -= secs
                chosen.remove(at: idx)
            } else {
                break
            }
        }
        // Note: Do not top-up here; selection handles tail extension to preserve sequencing

        // 3) Preflight playability (batch) and attempt alternate-version swaps when needed
        let ids = chosen.map { $0.track.id }
        let playableSet: Set<String> = (try? await spotify.playableIds(for: ids, market: market)) ?? Set(ids)
        var finalUris: [String] = []
        var finalTrackIds: [String] = []
        var preflightFailures = 0
        var swapsSucceeded = 0
        var removedCount = 0
        for c in chosen {
            let id = c.track.id
            if playableSet.contains(id) {
                finalUris.append("spotify:track:\(id)")
                finalTrackIds.append(id)
                continue
            }
            preflightFailures += 1
            do {
                if let altId = try await spotify.findAlternatePlayableTrack(originalId: id, market: market) {
                    finalUris.append("spotify:track:\(altId)")
                    finalTrackIds.append(altId)
                    swapsSucceeded += 1
                } else {
                    removedCount += 1
                }
            } catch {
                removedCount += 1
            }
        }
        emit("Playability preflight — checked:\(ids.count) unplayable:\(preflightFailures) swapped:\(swapsSucceeded) removed:\(removedCount)")

        // 4) Create playlist on Spotify
        if !finalUris.isEmpty {
            let firstName = (chosen.first?.artist?.name ?? "?") + " — " + (chosen.first?.track.name ?? "?")
            let lastName = (chosen.last?.artist?.name ?? "?") + " — " + (chosen.last?.track.name ?? "?")
            emit("AddTracks debug — count:\(finalUris.count) total:\(total)s bounds:[\(minSeconds)s,\(maxSeconds)s] first:\(firstName) last:\(lastName)")
        } else {
            emit("AddTracks debug — count:\(finalUris.count) total:\(total)s bounds:[\(minSeconds)s,\(maxSeconds)s]")
        }
        let url = try await spotify.createPlaylist(name: name,
                                                   description: "RunClub · \(template.rawValue) · ~\(postPlan.total)min",
                                                   isPublic: true,
                                                   uris: finalUris)

        // 5) Persist TrackUsage updates (use finalTrackIds to reflect swaps)
        let idsForUsage = finalTrackIds
        await MainActor.run {
            for tid in idsForUsage {
                let fd = FetchDescriptor<TrackUsage>(predicate: #Predicate { $0.trackId == tid })
                if let u = try? modelContext.fetch(fd).first {
                    u.lastUsedAt = Date()
                    u.usedCount += 1
                } else {
                    modelContext.insert(TrackUsage(trackId: tid, lastUsedAt: Date(), usedCount: 1))
                }
            }
            try? modelContext.save()
            emit("TrackUsage updated \(idsForUsage.count) tracks")
        }

        return url
    }

    // MARK: - Candidate pool (scaffold)
    enum SourceKind { case likes, recs, third }

    struct Candidate {
        let track: CachedTrack
        let features: AudioFeature?
        let artist: CachedArtist?
        let isRediscovery: Bool
        let lastUsedAt: Date?
        let genreAffinity: Double // 0–1 affinity to selected umbrella(s) incl. neighbors
        let source: SourceKind
    }

    private func buildCandidatePool(genres: [Genre], decades: [Decade], umbrellaWeights: [String: Double]) async throws -> [Candidate] {
        // Fetch from likes (primary) and optionally from recs store
        let (likesTracks, likesFeat, likesArtists, usageById): ([CachedTrack], [String: AudioFeature], [String: CachedArtist], [String: TrackUsage]) = try await MainActor.run {
            let tracks = try modelContext.fetch(FetchDescriptor<CachedTrack>())
            let feats = try modelContext.fetch(FetchDescriptor<AudioFeature>())
            let featById = Dictionary(uniqueKeysWithValues: feats.map { ($0.trackId, $0) })
            let artists = try modelContext.fetch(FetchDescriptor<CachedArtist>())
            let artistById = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
            let usages = try modelContext.fetch(FetchDescriptor<TrackUsage>())
            let usageById = Dictionary(uniqueKeysWithValues: usages.map { ($0.trackId, $0) })
            return (tracks, featById, artistById, usageById)
        }
        var tracks: [CachedTrack] = likesTracks
        var featById: [String: AudioFeature] = likesFeat
        var artistById: [String: CachedArtist] = likesArtists
        var sourceById: [String: SourceKind] = Dictionary(uniqueKeysWithValues: likesTracks.map { ($0.id, .likes) })

        // Always include playlists database as secondary pool; prefer likes on id conflict
        let (plTracks, plFeat, plArtists): ([CachedTrack], [String: AudioFeature], [String: CachedArtist]) = try await MainActor.run {
            let tracks = try playlistsContext.fetch(FetchDescriptor<CachedTrack>())
            let feats = try playlistsContext.fetch(FetchDescriptor<AudioFeature>())
            let featById = Dictionary(uniqueKeysWithValues: feats.map { ($0.trackId, $0) })
            let artists = try playlistsContext.fetch(FetchDescriptor<CachedArtist>())
            let artistById = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
            return (tracks, featById, artistById)
        }
        for t in plTracks { if sourceById[t.id] == nil { tracks.append(t); sourceById[t.id] = .recs } }
        for (k, v) in plFeat { if featById[k] == nil { featById[k] = v } }
        for (k, v) in plArtists { if artistById[k] == nil { artistById[k] = v } }
        // Include third-source database as tertiary pool; prefer likes then playlists on id conflict
        let (tsTracks, tsFeat, tsArtists): ([CachedTrack], [String: AudioFeature], [String: CachedArtist]) = try await MainActor.run {
            let tracks = try thirdSourceContext.fetch(FetchDescriptor<CachedTrack>())
            let feats = try thirdSourceContext.fetch(FetchDescriptor<AudioFeature>())
            let featById = Dictionary(uniqueKeysWithValues: feats.map { ($0.trackId, $0) })
            let artists = try thirdSourceContext.fetch(FetchDescriptor<CachedArtist>())
            let artistById = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
            return (tracks, featById, artistById)
        }
        for t in tsTracks { if sourceById[t.id] == nil { tracks.append(t); sourceById[t.id] = .third } }
        for (k, v) in tsFeat { if featById[k] == nil { featById[k] = v } }
        for (k, v) in tsArtists { if artistById[k] == nil { artistById[k] = v } }
        // Gate: only use tracks with audio features available (enriched)
        tracks = tracks.filter { featById[$0.id] != nil }

        let now = Date()
        let tenDays: TimeInterval = 10 * 24 * 3600
        let sixtyDays: TimeInterval = 60 * 24 * 3600

        var lockoutFilteredCount = 0
        var totalTracksSeen = 0
        func passesFilters(_ t: CachedTrack) -> Bool {
            totalTracksSeen += 1
            // Must be playable and ≤ 6 minutes
            guard t.isPlayable else { return false }
            guard t.durationMs <= 6 * 60 * 1000 else { return false }
            // Genre includes (umbrella affinity): if user selected any, require affinity > 0
            if !genres.isEmpty {
                guard let a = artistById[t.artistId] else { return false }
                let aff = GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: umbrellaWeights)
                if aff <= 0.0 { return false }
            }
            // Decade includes
            if !decades.isEmpty {
                guard let year = t.albumReleaseYear else { return false }
                let decadeLabel: String
                switch year {
                case 1970...1979: decadeLabel = "70s"
                case 1980...1989: decadeLabel = "80s"
                case 1990...1999: decadeLabel = "90s"
                case 2000...2009: decadeLabel = "00s"
                case 2010...2019: decadeLabel = "10s"
                default: decadeLabel = "20s"
                }
                let wanted = Set(decades.map { $0.displayName })
                if !wanted.contains(decadeLabel) { return false }
            }
            // 10‑day lockout
            if let u = usageById[t.id], let last = u.lastUsedAt, now.timeIntervalSince(last) < tenDays {
                lockoutFilteredCount += 1
                return false
            }
            return true
        }

        let result: [Candidate] = tracks.compactMap { (t: CachedTrack) -> Candidate? in
            guard passesFilters(t) else { return nil }
            let u = usageById[t.id]
            let isRediscovery: Bool = {
                if let last = u?.lastUsedAt { return now.timeIntervalSince(last) >= sixtyDays }
                return true
            }()
            let artist = artistById[t.artistId]
            let affinity: Double = {
                guard let a = artist else { return 0.0 }
                return GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: umbrellaWeights)
            }()
            return Candidate(track: t,
                             features: featById[t.id],
                             artist: artist,
                             isRediscovery: isRediscovery,
                             lastUsedAt: u?.lastUsedAt,
                             genreAffinity: affinity,
                             source: sourceById[t.id] ?? .likes)
        }
        emit("Pool build — total:\(totalTracksSeen) lockoutFiltered:\(lockoutFilteredCount) resulting:\(result.count)")
        return result
    }

    // MARK: - Diversity (10‑day lookback) and bonuses
    private func diversityLookbackStats(days: Int = 10) async throws -> (genreCounts: [String: Int], decadeCounts: [String: Int]) {
        let now = Date()
        let window = TimeInterval(days * 24 * 3600)
        let usages = try await MainActor.run { try modelContext.fetch(FetchDescriptor<TrackUsage>()) }
        let usedIds = usages.filter { if let d = $0.lastUsedAt { return now.timeIntervalSince(d) <= window } else { return false } }.map { $0.trackId }
        guard !usedIds.isEmpty else { return ([:], [:]) }
        let tracks = try await MainActor.run { try modelContext.fetch(FetchDescriptor<CachedTrack>()) }.filter { usedIds.contains($0.id) }
        let artists = try await MainActor.run { try modelContext.fetch(FetchDescriptor<CachedArtist>()) }
        let artistById = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0) })
        var g: [String: Int] = [:]
        var d: [String: Int] = [:]
        for t in tracks {
            if let a = artistById[t.artistId] {
                for gen in a.genres { g[gen, default: 0] += 1 }
            }
            if let year = t.albumReleaseYear { d[decadeLabel(for: year), default: 0] += 1 }
        }
        return (g, d)
    }

    private func decadeLabel(for year: Int) -> String {
        switch year {
        case 1970...1979: return "70s"
        case 1980...1989: return "80s"
        case 1990...1999: return "90s"
        case 2000...2009: return "00s"
        case 2010...2019: return "10s"
        default: return "20s"
        }
    }

    // MARK: - Genre umbrella matching
    // Legacy genre keyword mapping removed in favor of JSON umbrellas and neighbor broadening.

    private struct BonusContext {
        let recentArtists: [String] // last few selected artistIds
        let perArtistCount: [String: Int]
        // For balancing: counts per selected umbrella id so far in this playlist
        let playlistUmbrellaCounts: [String: Int]
        let selectedUmbrellaIds: [String]
        let playlistDecadeCounts: [String: Int]
        let lookbackGenres: [String: Int]
        let lookbackDecades: [String: Int]
        let secondsSoFar: Int
        let genreBonusWeight: Double
        let artistLastUsed: [String: Date]
    }

    private func computeBonuses(for candidate: Candidate,
                                base: ScoreComponents,
                                context: BonusContext,
                                rediscoveryTargetBias: Double) -> Double {
        var bonus: Double = 0.0
        let now = Date()
        // 1) Recency: +0.10 × (1 − penalty). Penalty declines to 0 after 10 days.
        if let last = candidate.lastUsedAt {
            let daysSince = now.timeIntervalSince(last) / (24 * 3600)
            let penalty = max(0.0, min(1.0, 1.0 - (daysSince / 10.0)))
            bonus += 0.10 * (1.0 - penalty)
        } else {
            bonus += 0.10 // never used gets full recency bonus
        }
        // 2) Artist spacing: stronger bonus and wider window to promote diversity.
        let artistId = candidate.track.artistId
        if let idx = context.recentArtists.lastIndex(of: artistId) {
            let dist = context.recentArtists.count - idx
            // dist 1 → 0, dist 7+ → ~1
            let scaled = max(0.0, min(1.0, Double(dist - 1) / 6.0))
            bonus += 0.16 * scaled
        } else {
            bonus += 0.16
        }
        // 3) Diversity bonus (10‑day lookback + current playlist)
        var diversity = 0.0
        if let a = candidate.artist {
            // Lower historical count → higher boost
            let histMax = max(1, context.lookbackGenres.values.max() ?? 1)
            for gen in a.genres {
                let c = context.lookbackGenres[gen] ?? 0
                diversity += (Double(histMax - c) / Double(histMax)) * 0.05 // up to half of 0.10 from genres
            }
        }
        if let y = candidate.track.albumReleaseYear {
            let label = decadeLabel(for: y)
            let histMax = max(1, context.lookbackDecades.values.max() ?? 1)
            let c = context.lookbackDecades[label] ?? 0
            diversity += (Double(histMax - c) / Double(histMax)) * 0.05 // up to half of 0.10 from decades
        }
        bonus += min(0.10, diversity)

        // 4) Artist novelty across runs: if artist not used recently beyond 10 days, small boost
        if let lastArtistUse = context.artistLastUsed[candidate.track.artistId] {
            let daysSince = now.timeIntervalSince(lastArtistUse) / (24 * 3600)
            if daysSince > 10 {
                let scale = min(1.0, (daysSince - 10.0) / 20.0) // 0→1 over next ~20 days
                bonus += 0.08 * scale
            }
        } else {
            // Never used artist gets a small novelty bump
            bonus += 0.06
        }

        // 5) Genre Affinity: small positive bonus if aligned with selected umbrella(s)/neighbors
        bonus += context.genreBonusWeight * candidate.genreAffinity
        // 5b) Multi-umbrella balance bonus: favor underrepresented selected umbrellas
        if let a = candidate.artist, !context.selectedUmbrellaIds.isEmpty {
            var bestId: String?
            var bestScore: Double = 0.0
            for id in context.selectedUmbrellaIds {
                let s = GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: [id: 1.0])
                if s > bestScore { bestScore = s; bestId = id }
            }
            if let bid = bestId, bestScore > 0.0 {
                let total = max(1, context.playlistUmbrellaCounts.values.reduce(0, +))
                let cur = context.playlistUmbrellaCounts[bid] ?? 0
                let curShare = Double(cur) / Double(total)
                let desiredShare = 1.0 / Double(context.selectedUmbrellaIds.count)
                let deficit = max(0.0, desiredShare - curShare)
                let surplus = max(0.0, curShare - desiredShare)
                // Stronger incentives: up to +0.12 bonus for deficit; up to -0.05 penalty for surplus
                bonus += min(0.12, 0.60 * deficit)
                bonus -= min(0.05, 0.25 * surplus)
            }
        }

        // 6) Rediscovery bias (to help meet 50% target)
        if candidate.isRediscovery { bonus += 0.05 * rediscoveryTargetBias }

        // 7) Mild source bias: likes/playlists slightly preferred over third
        switch candidate.source {
        case .likes, .recs:
            bonus += 0.03
        case .third:
            bonus += 0.00
        }

        return bonus
    }

    // MARK: - Selection loop (scaffold with constraints)
    struct SelectionResult {
        let selected: [Candidate]
        let totalSeconds: Int
        let efforts: [EffortTier]
    }

    private func selectCandidates(template: RunTemplateType,
                                  runMinutes: Int,
                                  genres: [Genre],
                                  decades: [Decade],
                                  isPlayable: @escaping (String) async -> Bool) async throws -> SelectionResult {
        // Planned segment durations (minutes)
        let planDurMins = durationPlan(for: template, minutes: runMinutes)
        // Filters summary header
        let genreFilterNames = genres.map { $0.displayName }.joined(separator: ", ")
        let decadeFilterNames = decades.map { $0.displayName }.joined(separator: ", ")
        emit("LocalGen config — template:\(template.rawValue) run:\(runMinutes)m segmentsPlanned:[wu:\(planDurMins.wu)m main:\(planDurMins.core)m cd:\(planDurMins.cd)m] filters:genres=[\(genreFilterNames.isEmpty ? "none" : genreFilterNames)] decades=[\(decadeFilterNames.isEmpty ? "none" : decadeFilterNames)]")

        var anchorSPM = PaceUtils.cadenceAnchorSPM(for: await fetchPaceBucket())
        if let prefs = try? await MainActor.run(resultType: UserRunPrefs?.self, body: { try modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first }),
           let custom = prefs.customCadenceSPM {
            anchorSPM = custom
        }
        // Build umbrella weights for selected only first; broaden to neighbors if pool is thin
        let selectedIds: [String] = genres.map { GenreUmbrellaBridge.umbrellaId(for: $0) }
        let selOnlyWeights = GenreUmbrellaService.shared.selectedWithNeighborsWeights(selectedIds: selectedIds, neighborWeight: 0.0)
        var pool = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: selOnlyWeights)
        var usedNeighborBroadening = false
        var neighborRelaxSlots = 0
        var lockoutBreaks = 0
        if !genres.isEmpty && pool.count < 200 {
            let neighborWeights = GenreUmbrellaService.shared.selectedWithNeighborsWeights(selectedIds: selectedIds, neighborWeight: 0.6)
            pool = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: neighborWeights)
            usedNeighborBroadening = true
        }
        // Diversity lookback
        let look = try await diversityLookbackStats(days: 10)

        // Use the same planned segment slot counts as the preview UI to keep labels aligned
        let counts = plannedSegmentCounts(template: template, runMinutes: runMinutes)
        let warmupSlotsPlan = counts.wuSlots
        let mainSlotsPlan = counts.coreSlots
        let cooldownSlotsPlan = counts.cdSlots
        // Build an effort timeline using explicit slot counts for alignment
        let slots = buildEffortTimeline(template: template, wuSlots: warmupSlotsPlan, coreSlots: mainSlotsPlan, cdSlots: cooldownSlotsPlan)

        // Safety: ensure labeling counts match our constructed slots
        // (warmupSlotsPlan + mainSlotsPlan + cooldownSlotsPlan) == slots.count

        // Cross-run artist cooldown lookup (3-day hard, 10-day soft)
        var artistLastUsed: [String: Date] = [:]
        do {
            let usages = try await MainActor.run { try modelContext.fetch(FetchDescriptor<TrackUsage>()) }
            let tracks = try await MainActor.run { try modelContext.fetch(FetchDescriptor<CachedTrack>()) }
            let trackById = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            for u in usages {
                guard let d = u.lastUsedAt, let art = trackById[u.trackId]?.artistId else { continue }
                if let cur = artistLastUsed[art] {
                    if d > cur { artistLastUsed[art] = d }
                } else {
                    artistLastUsed[art] = d
                }
            }
        } catch { }

        // Duration bounds in seconds (plan.total ±2 minutes)
        let plan = durationPlan(for: template, minutes: runMinutes)
        var minSeconds = max(0, (plan.total - 2) * 60)
        var maxSeconds = (plan.total + 2) * 60

        var selected: [Candidate] = []
        var chosenEfforts: [EffortTier] = []
        var perArtistCount: [String: Int] = [:]
        var recentArtists: [String] = [] // last few to avoid repeats (wider window)
        var secondsSoFar = 0
        let targetRediscovery = max(1, (slots.count / 2))
        var chosenRediscovery = 0
        // Caps tracking
        var maxSelected = 0
        var hardSelected = 0
        // Umbrella balancing counts (by selected umbrella id)
        var perUmbrellaCounts: [String: Int] = [:]

        func add(_ c: Candidate) {
            selected.append(c)
            secondsSoFar += c.track.durationMs / 1000
            let a = c.track.artistId
            perArtistCount[a, default: 0] += 1
            recentArtists.append(a)
            if recentArtists.count > 7 { recentArtists.removeFirst() }
            if c.isRediscovery { chosenRediscovery += 1 }
            // Update umbrella balance counts using best-matching selected umbrella id
            if let artist = c.artist, !selectedIds.isEmpty {
                var bestId: String?
                var bestScore: Double = 0.0
                for id in selectedIds {
                    let s = GenreUmbrellaService.shared.affinity(for: artist.genres, targetUmbrellaWeights: [id: 1.0])
                    if s > bestScore { bestScore = s; bestId = id }
                }
                if let bid = bestId, bestScore > 0.0 {
                    perUmbrellaCounts[bid, default: 0] += 1
                }
            }
        }

        // Iterate slots until we reach minSeconds or exhaust slots
        // Metrics accumulators
        var metricTempoFitSum = 0.0
        var metricSlotFitSum = 0.0
        var metricCount = 0

        var slotIndex = 0
        // Reserve space for cooldown by target seconds until we reach cooldown segment
        let cdTargetSeconds = planDurMins.cd * 60
        // Segment target seconds for gating
        let wuTarget = planDurMins.wu * 60
        let cdTarget = planDurMins.cd * 60
        let secondsPerSlotEstimate = 240 // legacy fallback (not used in reserve anymore)
        // Segment seconds accumulators
        var wuSecondsAcc = 0
        var mainSecondsAcc = 0
        var cdSecondsAcc = 0
        // Helpers
        func segmentLabel(for idx: Int) -> String {
            if idx < warmupSlotsPlan { return "warmup" }
            if idx < warmupSlotsPlan + mainSlotsPlan { return "main" }
            if idx < slots.count { return "cooldown" }
            return "cooldown"
        }
        func formatMMSS(_ secs: Int) -> String {
            let m = secs / 60
            let s = secs % 60
            return String(format: "%d:%02d", m, s)
        }
        func filterDesignation(for candidate: Candidate, usedNeighborWeights: Bool) -> String {
            guard !selectedIds.isEmpty, let artist = candidate.artist else {
                return (genres.isEmpty && decades.isEmpty) ? "none" : "—"
            }
            var selMatches: [String] = []
            for id in selectedIds {
                let a = GenreUmbrellaService.shared.affinity(for: artist.genres, targetUmbrellaWeights: [id: 1.0])
                if a > 0.0 { selMatches.append(id) }
            }
            if usedNeighborWeights {
                let neighborWeights = GenreUmbrellaService.shared.selectedWithNeighborsWeights(selectedIds: selectedIds, neighborWeight: 0.6)
                let neighborOnlyIds = neighborWeights.keys.filter { (neighborWeights[$0] ?? 0.0) < 1.0 }
                var neighMatches: [String] = []
                for id in neighborOnlyIds {
                    let a = GenreUmbrellaService.shared.affinity(for: artist.genres, targetUmbrellaWeights: [id: 1.0])
                    if a > 0.0 { neighMatches.append(id) }
                }
                if !neighMatches.isEmpty {
                    if selMatches.isEmpty {
                        return neighMatches.joined(separator: "|") + " (neigh)"
                    } else {
                        return selMatches.joined(separator: "|") + " + " + neighMatches.joined(separator: "|") + " (neigh)"
                    }
                }
            }
            if !selMatches.isEmpty { return selMatches.joined(separator: "|") }
            return genres.isEmpty ? "none" : "—"
        }
        for slot in slots {
            guard secondsSoFar < minSeconds else { break }
            // Filter pool by hard per-artist cap and not already chosen
            let perArtistMax = (template == .easyRun ? 1 : 2)
            let now = Date()
            let threeDays: TimeInterval = 3 * 24 * 3600
            // Unified availability: include likes, playlists, and third-source every slot; no source gating here
            var available = pool.filter { c in
                !selected.contains(where: { $0.track.id == c.track.id }) &&
                (perArtistCount[c.track.artistId] ?? 0) < perArtistMax &&
                (recentArtists.last != c.track.artistId)
            }
            if available.isEmpty { continue }

            // Compute scores
            var scored: [(Candidate, Double)] = []
            var slotUsedNeighbor = false
            var slotBrokeLockout = false
            // Enforce caps by blocking primary tier when exceeded
            let primaryBlockedByCaps: Bool = {
                if slot.effort == .max && maxSelected >= 1 { return true }
                if template == .kicker && slot.effort == .hard && hardSelected >= 2 { return true }
                return false
            }()
            let ctx = BonusContext(recentArtists: recentArtists,
                                   perArtistCount: perArtistCount,
                                   playlistUmbrellaCounts: perUmbrellaCounts,
                                   selectedUmbrellaIds: selectedIds,
                                   playlistDecadeCounts: [:],
                                   lookbackGenres: look.genreCounts,
                                   lookbackDecades: look.decadeCounts,
                                   secondsSoFar: secondsSoFar,
                                   genreBonusWeight: 0.08,
                                   artistLastUsed: artistLastUsed)
            let rediscoveryBias = max(0.0, min(1.0, Double(targetRediscovery - chosenRediscovery) / Double(targetRediscovery)))
            if !primaryBlockedByCaps {
                // Optional fairness gating in WU/CD: if behind on an umbrella, bias/gate to that umbrella
                var gatingUmbrella: String? = nil
                if selectedIds.count > 1 {
                    let totalSoFar = max(1, perUmbrellaCounts.values.reduce(0, +))
                    var bestDeficit: Double = 0.0
                    var gid: String? = nil
                    for id in selectedIds {
                        let share = Double(perUmbrellaCounts[id] ?? 0) / Double(totalSoFar)
                        let desired = 1.0 / Double(selectedIds.count)
                        let deficit = desired - share
                        if deficit > bestDeficit { bestDeficit = deficit; gid = id }
                    }
                    let inWU = slotIndex < warmupSlotsPlan
                    let inCD = slotIndex >= (warmupSlotsPlan + mainSlotsPlan)
                    if (inWU || inCD) && bestDeficit > 0.10 { gatingUmbrella = gid }
                }
                for c in available {
                    // Cross-run artist cooldown: skip if used within 3 days
                    if let lu = artistLastUsed[c.track.artistId], now.timeIntervalSince(lu) < threeDays { continue }
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: slot)
                    // GATE: require minimum tempo fit for this effort level
                    if base.tempoFit < tempoFitThreshold(for: slot.effort) { continue }
                    // WU/CD min track length and fairness gating when behind
                    let secs = c.track.durationMs / 1000
                    let isWU = slotIndex < warmupSlotsPlan
                    let isCD = slotIndex >= (warmupSlotsPlan + mainSlotsPlan)
                    if (isWU || isCD) && secs < 90 { continue }
                    if let gid = gatingUmbrella, let a = c.artist {
                        let aff = GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: [gid: 1.0])
                        if aff <= 0.0 { continue }
                    }
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    scored.append((c, total))
                }
            }
            // If slot is thin (few scored), apply relaxations progressively
            if scored.isEmpty {
                // 1) Allow adjacent effort spillover up to 30%: re-score with neighboring effort if close
                // Adjacent tier relax: prefer ±1 tier
                let neighborEffort: EffortTier = {
                    switch slot.effort {
                    case .easy: return .moderate
                    case .moderate: return .easy
                    case .strong: return .moderate
                    case .hard: return .strong
                    case .max: return .hard
                    }
                }()
                var rescored: [(Candidate, Double)] = []
                for c in available {
                    var neighborSlot = slot
                    neighborSlot = Slot(effort: neighborEffort, targetEffort: slot.targetEffort)
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: neighborSlot)
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    if base.slotFit >= 0.70 { rescored.append((c, total)) }
                }
                scored = rescored
            }

            if scored.isEmpty {
                // 1b) Second-adjacent relax (±2) with slightly lower slotFit threshold
                let secondEffort: EffortTier = {
                    switch slot.effort {
                    case .easy: return .strong
                    case .moderate: return .hard
                    case .strong: return .easy
                    case .hard: return .moderate
                    case .max: return .moderate
                    }
                }()
                var rescored2: [(Candidate, Double)] = []
                for c in available {
                    var neighborSlot = slot
                    neighborSlot = Slot(effort: secondEffort, targetEffort: slot.targetEffort)
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: neighborSlot)
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    if base.slotFit >= 0.65 { rescored2.append((c, total)) }
                }
                scored = rescored2
            }

            if scored.isEmpty && neighborRelaxSlots < 2 {
                // 2) Broaden genre umbrellas to neighbors for this slot only (guard: max 2 slots per playlist)
                let selectedIds = genres.map { GenreUmbrellaBridge.umbrellaId(for: $0) }
                let neighborWeights = GenreUmbrellaService.shared.selectedWithNeighborsWeights(selectedIds: selectedIds, neighborWeight: 0.6)
                // Try likes-first
                available = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: neighborWeights)
                    .filter { c in !selected.contains(where: { $0.track.id == c.track.id }) && (perArtistCount[c.track.artistId] ?? 0) < 2 && (recentArtists.last != c.track.artistId) && c.source == .likes }
                // If still none, fall back to secondary pools (playlists or third-source)
                if available.isEmpty {
                    available = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: neighborWeights)
                        .filter { c in !selected.contains(where: { $0.track.id == c.track.id }) && (perArtistCount[c.track.artistId] ?? 0) < 2 && (recentArtists.last != c.track.artistId) && (c.source == .recs || c.source == .third) }
                }
                for c in available {
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: slot)
                    if base.tempoFit < tempoFitThreshold(for: slot.effort) { continue }
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    if base.slotFit >= 0.60 { scored.append((c, total)) }
                }
                if !scored.isEmpty { neighborRelaxSlots += 1; slotUsedNeighbor = true }
            }

            if scored.isEmpty && lockoutBreaks < 1 {
                // 3) Break 10-day rule once if still stuck (no back-to-back, keep artist cap) — max once per playlist
                let now = Date()
                let lockout: TimeInterval = 10 * 24 * 3600
                // Try likes-first within lockout break
                available = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: selOnlyWeights)
                    .filter { c in
                        // Ignore lockout here by recreating availability with only length/artist rules
                        !selected.contains(where: { $0.track.id == c.track.id }) &&
                        (perArtistCount[c.track.artistId] ?? 0) < 2 &&
                        (recentArtists.last != c.track.artistId) &&
                        c.track.durationMs <= 6 * 60 * 1000 &&
                        c.source == .likes &&
                        // explicitly include within lockout if necessary
                        (c.lastUsedAt == nil || now.timeIntervalSince(c.lastUsedAt!) < lockout)
                    }
                if available.isEmpty {
                    available = try await buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: selOnlyWeights)
                        .filter { c in
                            !selected.contains(where: { $0.track.id == c.track.id }) &&
                            (perArtistCount[c.track.artistId] ?? 0) < 2 &&
                            (recentArtists.last != c.track.artistId) &&
                            c.track.durationMs <= 6 * 60 * 1000 &&
                            (c.source == .recs || c.source == .third) &&
                            (c.lastUsedAt == nil || now.timeIntervalSince(c.lastUsedAt!) < lockout)
                        }
                }
                for c in available {
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: slot)
                    if base.tempoFit < tempoFitThreshold(for: slot.effort) { continue }
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    if base.slotFit >= 0.55 { scored.append((c, total)) }
                }
                if !scored.isEmpty { lockoutBreaks += 1; slotBrokeLockout = true }
            }

            guard !scored.isEmpty else { continue }
            // Take top-K with weighted pick (wider for Easy to improve variety)
            scored.sort { $0.1 > $1.1 }
            let k = (slot.effort == .easy ? 25 : (slot.effort == .moderate ? 15 : 8))
            let topK = Array(scored.prefix(k))
            let sum = topK.map { max(0.0001, $0.1) }.reduce(0, +)
            var r = Double.random(in: 0..<sum)
            var choice = topK.first!.0
            for (cand, s) in topK {
                r -= max(0.0001, s)
                if r <= 0 { choice = cand; break }
            }
            // Availability preflight via injected checker: replace with next playable candidate if needed
            if await !isPlayable(choice.track.id) {
                for alt in topK.dropFirst().map({ $0.0 }) {
                    if await isPlayable(alt.track.id) { choice = alt; break }
                }
            }
            // Enforce 6-min track length and do not exceed maxSeconds
            var secs = choice.track.durationMs / 1000
            // Reserve capacity for cooldown target seconds until reaching cooldown segment
            let reserveSeconds = (slotIndex < (warmupSlotsPlan + mainSlotsPlan)) ? cdTargetSeconds : 0
            if secs <= 6 * 60 && secondsSoFar + secs <= max(0, maxSeconds - reserveSeconds) {
                // Segment-aware duration gating for warmup/cooldown to keep within ±60s
                let segForGating = segmentLabel(for: slotIndex)
                if segForGating == "warmup" {
                    let allowed = wuTarget + 60
                    if wuSecondsAcc + secs > allowed {
                        // Try to find a shorter alternative within topK
                        if let alt = topK.dropFirst().map({ $0.0 }).first(where: { (cand: Candidate) in
                            (wuSecondsAcc + (cand.track.durationMs / 1000)) <= allowed
                        }) {
                            choice = alt
                            secs = alt.track.durationMs / 1000
                        }
                    }
                } else if segForGating == "cooldown" {
                    let allowed = cdTarget + 60
                    if cdSecondsAcc + secs > allowed {
                        if let alt = topK.dropFirst().map({ $0.0 }).first(where: { (cand: Candidate) in
                            (cdSecondsAcc + (cand.track.durationMs / 1000)) <= allowed
                        }) {
                            choice = alt
                            secs = alt.track.durationMs / 1000
                        }
                    }
                }
                add(choice)
                chosenEfforts.append(slot.effort)
                if slot.effort == .max { maxSelected += 1 }
                if slot.effort == .hard { hardSelected += 1 }
                // Per-slot debug log for sequencing validation
                let b = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
                let tempoStr = String(format: "%.0f", choice.features?.tempo ?? 0)
                let energyStr = String(format: "%.2f", choice.features?.energy ?? 0.0)
                let danceStr = String(format: "%.2f", choice.features?.danceability ?? 0.0)
                let artistName = choice.artist?.name ?? "?"
                let neighborStr = slotUsedNeighbor ? "true" : "false"
                let lockStr = slotBrokeLockout ? "true" : "false"
                let tol = tierSpec(for: slot.effort).tempoToleranceBPM
                let durSecs = choice.track.durationMs / 1000
                let seg = segmentLabel(for: slotIndex)
                let filt = filterDesignation(for: choice, usedNeighborWeights: slotUsedNeighbor)
                let srcStr: String = {
                    switch choice.source {
                    case .likes: return "likes"
                    case .recs: return "playlists"
                    case .third: return "third"
                    }
                }()
                let genresStr: String = {
                    if let gs = choice.artist?.genres, !gs.isEmpty {
                        return Array(gs.prefix(2)).joined(separator: "/")
                    }
                    return "none"
                }()
                let line = "Slot #\(slotIndex) seg=\(seg) [\(slot.effort)] tol=\(Int(tol)) " +
                          "tgt=\(String(format: "%.2f", slot.targetEffort)) • " +
                          "\(artistName) — \(choice.track.name) • " +
                          "tempo=\(tempoStr) energy=\(energyStr) dance=\(danceStr) dur=\(formatMMSS(durSecs)) • " +
                          "tempoFit=\(String(format: "%.2f", b.tempoFit)) " +
                          "effortIdx=\(String(format: "%.2f", b.effortIndex)) " +
                          "slotFit=\(String(format: "%.2f", b.slotFit)) • " +
                          "aff=\(String(format: "%.2f", choice.genreAffinity)) " +
                          "redis=\(choice.isRediscovery) neighbor=\(neighborStr) lockoutBreak=\(lockStr) filter=\(filt) src=\(srcStr) genres=\(genresStr)"
                emit(line)
                // Accumulate segment seconds
                if slotIndex < warmupSlotsPlan { wuSecondsAcc += durSecs }
                else if slotIndex < warmupSlotsPlan + mainSlotsPlan { mainSecondsAcc += durSecs }
                else { cdSecondsAcc += durSecs }
            }

            // Metrics
            let base = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
            metricTempoFitSum += base.tempoFit
            metricSlotFitSum += base.slotFit
            metricCount += 1
            slotIndex += 1
        }

        // Tail extension: if under minSeconds after planned slots, add Easy tail with full logging to preserve sequencing
        if secondsSoFar < minSeconds {
            let secondsPerSlotEstimate = 240
            let extraSlots = Int(ceil(Double(minSeconds - secondsSoFar) / Double(secondsPerSlotEstimate)))
            if extraSlots > 0 {
                for _ in 0..<extraSlots {
                    guard secondsSoFar < minSeconds else { break }
                    // Treat tail extension as main adjustments rather than cooldown to avoid inflating cooldown
                    let slot = Slot(effort: .easy, targetEffort: 0.45)
                    let perArtistMax = (template == .easyRun ? 1 : 2)
                    let now = Date()
                    let threeDays: TimeInterval = 3 * 24 * 3600
                    // Tail extension prefers likes first
                    var available = pool.filter { c in
                        !selected.contains(where: { $0.track.id == c.track.id }) &&
                        (perArtistCount[c.track.artistId] ?? 0) < perArtistMax &&
                        (recentArtists.last != c.track.artistId) && c.source == .likes
                    }
                    if available.isEmpty {
                        available = pool.filter { c in
                            !selected.contains(where: { $0.track.id == c.track.id }) &&
                            (perArtistCount[c.track.artistId] ?? 0) < perArtistMax &&
                            (recentArtists.last != c.track.artistId) && c.source == .recs
                    }
                    if available.isEmpty { break }
                    }
                    var scored: [(Candidate, Double)] = []
                    let ctx = BonusContext(recentArtists: recentArtists,
                                           perArtistCount: perArtistCount,
                                           playlistUmbrellaCounts: perUmbrellaCounts,
                                           selectedUmbrellaIds: selectedIds,
                                           playlistDecadeCounts: [:],
                                           lookbackGenres: look.genreCounts,
                                           lookbackDecades: look.decadeCounts,
                                           secondsSoFar: secondsSoFar,
                                           genreBonusWeight: 0.08,
                                           artistLastUsed: artistLastUsed)
                    let rediscoveryBias = max(0.0, min(1.0, Double(targetRediscovery - chosenRediscovery) / Double(targetRediscovery)))
                    for c in available {
                        if let lu = artistLastUsed[c.track.artistId], now.timeIntervalSince(lu) < threeDays { continue }
                        let base = score(candidate: c, anchorSPM: anchorSPM, slot: slot)
                        if base.tempoFit < tempoFitThreshold(for: slot.effort) { continue }
                        let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                        let total = base.baseScore + bonus
                        scored.append((c, total))
                    }
                    guard !scored.isEmpty else { break }
                    scored.sort { $0.1 > $1.1 }
                    let topK = Array(scored.prefix(8))
                    let sum = topK.map { max(0.0001, $0.1) }.reduce(0, +)
                    var r = Double.random(in: 0..<sum)
                    var choice = topK.first!.0
                    for (cand, s) in topK { r -= max(0.0001, s); if r <= 0 { choice = cand; break } }
                    let secs = choice.track.durationMs / 1000
                    if secs <= 6 * 60 && secondsSoFar + secs <= maxSeconds {
                        add(choice)
                        chosenEfforts.append(slot.effort)
                        let b = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
                        let tempoStr = String(format: "%.0f", choice.features?.tempo ?? 0)
                        let energyStr = String(format: "%.2f", choice.features?.energy ?? 0.0)
                        let danceStr = String(format: "%.2f", choice.features?.danceability ?? 0.0)
                        let artistName = choice.artist?.name ?? "?"
                        let tol = tierSpec(for: slot.effort).tempoToleranceBPM
                        // Label tail extension as main
                        let seg = "main"
                        let filt = filterDesignation(for: choice, usedNeighborWeights: false)
                        let srcStr: String = {
                            switch choice.source {
                            case .likes: return "likes"
                            case .recs: return "playlists"
                            case .third: return "third"
                            }
                        }()
                        let genresStr: String = {
                            if let gs = choice.artist?.genres, !gs.isEmpty {
                                return Array(gs.prefix(2)).joined(separator: "/")
                            }
                            return "none"
                        }()
                        let line = "Slot #\(slotIndex) seg=\(seg) [\(slot.effort)] tol=\(Int(tol)) " +
                                  "tgt=\(String(format: "%.2f", slot.targetEffort)) • " +
                                  "\(artistName) — \(choice.track.name) • " +
                                  "tempo=\(tempoStr) energy=\(energyStr) dance=\(danceStr) dur=\(formatMMSS(secs)) • " +
                                  "tempoFit=\(String(format: "%.2f", b.tempoFit)) " +
                                  "effortIdx=\(String(format: "%.2f", b.effortIndex)) " +
                                  "slotFit=\(String(format: "%.2f", b.slotFit)) • " +
                                  "aff=\(String(format: "%.2f", choice.genreAffinity)) " +
                                  "redis=\(choice.isRediscovery) neighbor=false lockoutBreak=false filter=\(filt) src=\(srcStr) genres=\(genresStr)"
                        emit(line)
                        let base = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
                        metricTempoFitSum += base.tempoFit
                        metricSlotFitSum += base.slotFit
                        metricCount += 1
                        // Tail extension contributes to main segment
                        mainSecondsAcc += secs
                        slotIndex += 1
                    } else { break }
                }
            }
        }

        // Cooldown reconcile: ensure cooldown within target window by topping up (with optional main swap/drop if needed)
        if cdSecondsAcc < (cdTarget - 60) {
            while cdSecondsAcc < (cdTarget - 60) && secondsSoFar < maxSeconds {
                let slot = Slot(effort: .easy, targetEffort: 0.35)
                let perArtistMax = (template == .easyRun ? 1 : 2)
                // prefer likes first
                var available = pool.filter { c in
                    !selected.contains(where: { $0.track.id == c.track.id }) &&
                    (perArtistCount[c.track.artistId] ?? 0) < perArtistMax &&
                    (recentArtists.last != c.track.artistId) &&
                    c.track.durationMs >= 90 * 1000
                }
                var scored: [(Candidate, Double)] = []
                let ctx = BonusContext(recentArtists: recentArtists,
                                       perArtistCount: perArtistCount,
                                       playlistUmbrellaCounts: perUmbrellaCounts,
                                       selectedUmbrellaIds: selectedIds,
                                       playlistDecadeCounts: [:],
                                       lookbackGenres: look.genreCounts,
                                       lookbackDecades: look.decadeCounts,
                                       secondsSoFar: secondsSoFar,
                                       genreBonusWeight: 0.08,
                                       artistLastUsed: artistLastUsed)
                let rediscoveryBias = max(0.0, min(1.0, Double(targetRediscovery - chosenRediscovery) / Double(targetRediscovery)))
                for c in available {
                    let base = score(candidate: c, anchorSPM: anchorSPM, slot: slot)
                    if base.tempoFit < tempoFitThreshold(for: slot.effort) { continue }
                    let bonus = computeBonuses(for: c, base: base, context: ctx, rediscoveryTargetBias: rediscoveryBias)
                    let total = base.baseScore + bonus
                    scored.append((c, total))
                }
                guard !scored.isEmpty else { break }
                scored.sort { $0.1 > $1.1 }
                let topK = Array(scored.prefix(12))
                let sum = topK.map { max(0.0001, $0.1) }.reduce(0, +)
                var r = Double.random(in: 0..<sum)
                var choice = topK.first!.0
                for (cand, s) in topK { r -= max(0.0001, s); if r <= 0 { choice = cand; break } }
                var secs = choice.track.durationMs / 1000
                // Keep within +60s if possible
                let allowed = cdTarget + 60
                if cdSecondsAcc + secs > allowed {
                    if let alt = topK.dropFirst().map({ $0.0 }).first(where: { (cand: Candidate) in
                        (cdSecondsAcc + (cand.track.durationMs / 1000)) <= allowed
                    }) {
                        choice = alt
                        secs = alt.track.durationMs / 1000
                    }
                }
                if secs <= 6 * 60 && secondsSoFar + secs <= maxSeconds {
                    add(choice)
                    chosenEfforts.append(.easy)
                    let b = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
                    let tempoStr = String(format: "%.0f", choice.features?.tempo ?? 0)
                    let energyStr = String(format: "%.2f", choice.features?.energy ?? 0.0)
                    let danceStr = String(format: "%.2f", choice.features?.danceability ?? 0.0)
                    let artistName = choice.artist?.name ?? "?"
                    let tol = tierSpec(for: slot.effort).tempoToleranceBPM
                    let srcStr: String = {
                        switch choice.source {
                        case .likes: return "likes"
                        case .recs: return "playlists"
                        case .third: return "third"
                        }
                    }()
                    let genresStr: String = {
                        if let gs = choice.artist?.genres, !gs.isEmpty {
                            return Array(gs.prefix(2)).joined(separator: "/")
                        }
                        return "none"
                    }()
                    let line = "Slot #\(slotIndex) seg=cooldown [easy] tol=\(Int(tol)) " +
                              "tgt=\(String(format: "%.2f", slot.targetEffort)) • " +
                              "\(artistName) — \(choice.track.name) • " +
                              "tempo=\(tempoStr) energy=\(energyStr) dance=\(danceStr) dur=\(formatMMSS(secs)) • " +
                              "tempoFit=\(String(format: "%.2f", b.tempoFit)) " +
                              "effortIdx=\(String(format: "%.2f", b.effortIndex)) " +
                              "slotFit=\(String(format: "%.2f", b.slotFit)) • " +
                              "aff=\(String(format: "%.2f", choice.genreAffinity)) " +
                              "redis=\(choice.isRediscovery) neighbor=false lockoutBreak=false filter=\(filterDesignation(for: choice, usedNeighborWeights: false)) src=\(srcStr) genres=\(genresStr)"
                    emit(line)
                    // Metrics updates
                    let base = score(candidate: choice, anchorSPM: anchorSPM, slot: slot)
                    metricTempoFitSum += base.tempoFit
                    metricSlotFitSum += base.slotFit
                    metricCount += 1
                    cdSecondsAcc += secs
                    slotIndex += 1
                } else {
                    // At max time; try to free time by dropping last MAIN track and retry
                    let lastMainIdx = min(max(0, warmupSlotsPlan + mainSlotsPlan - 1), max(0, selected.count - 1))
                    if selected.indices.contains(lastMainIdx) && (warmupSlotsPlan + mainSlotsPlan) <= selected.count {
                        let removed = selected.remove(at: lastMainIdx)
                        let removedSecs = removed.track.durationMs / 1000
                        secondsSoFar -= removedSecs
                        // Adjust mainSecondsAcc conservatively
                        mainSecondsAcc = max(0, mainSecondsAcc - removedSecs)
                        if chosenEfforts.indices.contains(lastMainIdx) { chosenEfforts.remove(at: lastMainIdx) }
                        emit("PostProcess — dropped main at #\(lastMainIdx) to free \(removedSecs)s for cooldown")
                        // Continue loop; will attempt to add cooldown again
                        continue
                    } else {
                        break
                    }
                }
            }
        }

        // Basic metrics printout
        let rediscoveryPct = selected.isEmpty ? 0.0 : (Double(chosenRediscovery) / Double(selected.count))
        let avgTempoFit = metricCount == 0 ? 0.0 : metricTempoFitSum / Double(metricCount)
        let avgSlotFit = metricCount == 0 ? 0.0 : metricSlotFitSum / Double(metricCount)
        let avgAffinity = pool.isEmpty ? 0.0 : (pool.map { $0.genreAffinity }.reduce(0, +) / Double(pool.count))
        let affShare = pool.isEmpty ? 0.0 : (Double(pool.filter { $0.genreAffinity > 0.0 }.count) / Double(pool.count))
        // Tier counts and color class
        let tierCounts = Dictionary(grouping: chosenEfforts, by: { $0 }).mapValues { $0.count }
        func colorClass(for efforts: [EffortTier]) -> String {
            if efforts.contains(where: { $0 == .hard || $0 == .max }) { return "hard" }
            if efforts.contains(where: { $0 == .strong }) { return "middle" }
            return "easy"
        }
        let color = colorClass(for: chosenEfforts)
        // PASS/FAIL checks for ±1 minute tolerance on WU/CD
        let wuOk = abs(wuSecondsAcc - wuTarget) <= 60
        let cdOk = abs(cdSecondsAcc - cdTarget) <= 60
        // Source and umbrella summaries
        var srcLikes = 0, srcRecs = 0, srcThird = 0
        for s in selected {
            switch s.source {
            case .likes: srcLikes += 1
            case .recs: srcRecs += 1
            case .third: srcThird += 1
            }
        }
        let umbrellaSummary = perUmbrellaCounts
        emit("LocalGen metrics — tracks:\(selected.count) time:\(secondsSoFar)s rediscovery:\(Int(rediscoveryPct * 100))% tempoFit:\(String(format: "%.2f", avgTempoFit)) slotFit:\(String(format: "%.2f", avgSlotFit)) pool:\(pool.count) avgAffinity:\(String(format: "%.2f", avgAffinity)) affShare:\(String(format: "%.2f", affShare)) neighborsInit:\(usedNeighborBroadening) neighborSlots:\(neighborRelaxSlots) lockoutBreaks:\(lockoutBreaks) tiers:\(tierCounts) color:\(color) segSecs:[wu:\(wuSecondsAcc) main:\(mainSecondsAcc) cd:\(cdSecondsAcc)] segmentsPlanned:[wu:\(planDurMins.wu)m main:\(planDurMins.core)m cd:\(planDurMins.cd)m] segCheck:[wu:\(wuOk ? "PASS" : "FAIL") cd:\(cdOk ? "PASS" : "FAIL")] src:[likes:\(srcLikes) playlists:\(srcRecs) third:\(srcThird)] umbrellas:\(umbrellaSummary) filtersApplied:\(!(genres.isEmpty && decades.isEmpty))")

        return SelectionResult(selected: selected, totalSeconds: secondsSoFar, efforts: chosenEfforts)
    }

    // MARK: - Dry-run API for automated tests (no playlist creation or writes)
    struct DryRunResult {
        let trackIds: [String]
        let artistIds: [String]
        let sources: [SourceKind]
        let efforts: [EffortTier]
        let totalSeconds: Int
        let minSeconds: Int
        let maxSeconds: Int
        let preflightUnplayable: Int
        let swapped: Int
        let removed: Int
        let market: String
        // Detailed debug lines captured during selection
        let debugLines: [String]
    }

    func generateDryRun(template: RunTemplateType,
                         runMinutes: Int,
                         genres: [Genre],
                         decades: [Decade],
                         spotify: SpotifyService,
                         customMinutes: Int? = nil) async throws -> DryRunResult {
        let market = (try? await spotify.getProfileMarket()) ?? "US"
        let isPlayable: ((String) async -> Bool) = { trackId in
            do { return try await spotify.playableIds(for: [trackId], market: market).contains(trackId) }
            catch { return true }
        }
        var lines: [String] = []
        self.debugSink = { lines.append($0) }
        let sel = try await selectCandidates(template: template,
                                             runMinutes: runMinutes,
                                             genres: genres,
                                             decades: decades,
                                             isPlayable: isPlayable)
        self.debugSink = nil
        // Duration polish (±2m around either custom minutes or plan.total)
        let plan = durationPlan(for: template, minutes: runMinutes)
        let targetMinutes = customMinutes ?? runMinutes
        let minSeconds = max(0, (targetMinutes - 2) * 60)
        let maxSeconds = (targetMinutes + 2) * 60
        var chosen = sel.selected
        var total = sel.totalSeconds
        while total > maxSeconds && !chosen.isEmpty {
            let idx = chosen.count - 1
            let secs = chosen[idx].track.durationMs / 1000
            if total - secs >= minSeconds || chosen.count > 1 { total -= secs; chosen.remove(at: idx) } else { break }
        }
        // Preflight (batch) and simulate swaps
        let ids = chosen.map { $0.track.id }
        let playableSet: Set<String> = (try? await spotify.playableIds(for: ids, market: market)) ?? Set(ids)
        var preflightFailures = 0
        var swaps = 0
        var removed = 0
        var finalIds: [String] = []
        var finalArtistIds: [String] = []
        var finalSources: [SourceKind] = []
        for c in chosen {
            let id = c.track.id
            if playableSet.contains(id) {
                finalIds.append(id); finalArtistIds.append(c.track.artistId); finalSources.append(c.source); continue
            }
            preflightFailures += 1
            do {
                if let alt = try await spotify.findAlternatePlayableTrack(originalId: id, market: market) {
                    finalIds.append(alt); finalArtistIds.append(c.track.artistId); finalSources.append(c.source); swaps += 1
                } else {
                    removed += 1
                }
            } catch {
                removed += 1
            }
        }
        // Recompute total seconds from final chosen set where possible
        if removed > 0 {
            // best-effort: subtract average track length for removed items
            let avg = chosen.map { $0.track.durationMs / 1000 }.reduce(0, +) / max(1, chosen.count)
            total = max(0, total - removed * avg)
        }
        return DryRunResult(trackIds: finalIds,
                             artistIds: finalArtistIds,
                             sources: finalSources,
                             efforts: sel.efforts,
                             totalSeconds: total,
                             minSeconds: minSeconds,
                             maxSeconds: maxSeconds,
                             preflightUnplayable: preflightFailures,
                             swapped: swaps,
                             removed: removed,
                             market: market,
                             debugLines: lines)
    }

    // MARK: - Effort curve scaffolding
    struct Slot {
        let effort: EffortTier
        let targetEffort: Double // 0–1
    }

    private func fetchPaceBucket() async -> PaceBucket {
        // Try to fetch a single UserRunPrefs record; default to .B if none exists
        if let prefs = try? await MainActor.run(resultType: UserRunPrefs?.self, body: { try modelContext.fetch(FetchDescriptor<UserRunPrefs>()).first }) {
            return prefs.paceBucket
        }
        return .B
    }

    // Template-specific duration plan (minutes). Baselines chosen per spec; small flexibility occurs later.
    private func durationPlan(for template: RunTemplateType, minutes: Int) -> (total: Int, wu: Int, core: Int, cd: Int) {
        if template == .rest { return (0,0,0,0) }
        let total = max(1, minutes)
        // Bucketed warmup/cooldown policy with ±1 minute tolerance handled at selection time
        let wu: Int
        let cd: Int
        if total < 30 {
            wu = 5
            cd = 5
        } else if total <= 45 {
            wu = 7
            cd = 5
        } else {
            wu = 10
            cd = 7
        }
        var core = max(0, total - wu - cd)
        // Ensure non-negative allocation
        if core < 0 { core = 0 }
        return (total, wu, core, cd)
    }

    private func buildEffortTimeline(template: RunTemplateType,
                                     minutes: Int) -> [Slot] {
        // Rest day: no effort timeline
        if template == .rest { return [] }
        // Use template-specific duration plan; core minutes map to slot count (~1 slot ≈ 4 min).
        let planMins = durationPlan(for: template, minutes: minutes)
        let wu = planMins.wu
        let middle = max(0, planMins.core)
        let cd = planMins.cd

        // Helper to emit n EASY slots to approximate minutes; we will later map minutes→tracks.
        func slots(of effort: EffortTier, count: Int, target: Double) -> [Slot] {
            guard count > 0 else { return [] }
            return (0..<count).map { _ in Slot(effort: effort, targetEffort: target) }
        }

        // Basic curves; granular tuning will happen during full implementation.
        var plan: [Slot] = []
        // Warm-up (Easy ~0.40)
        plan += slots(of: .easy, count: max(1, wu / 4), target: 0.40)

        // Middle by template (approximate to minute buckets of ~4 min per slot)
        let m = max(1, middle / 4)
        switch template {
        case .rest:
            break
        case .easyRun:
            // Mostly Easy; allow ≤20% low-end Moderate in middle
            let modCount = min(max(0, Int(round(Double(m) * 0.2))), max(0, m - 1))
            let pre = (m - modCount) / 2
            let post = m - modCount - pre
            plan += slots(of: .easy, count: pre, target: 0.45)
            plan += slots(of: .moderate, count: modCount, target: 0.48)
            plan += slots(of: .easy, count: post, target: 0.45)
        case .strongSteady:
            // Mostly Strong; up to 2 low-end Hard spikes; no Max
            if m <= 2 {
                plan += slots(of: .strong, count: m, target: 0.60)
            } else {
                let ramp = min(2, m)
                plan += slots(of: .moderate, count: ramp, target: 0.55)
                var mid = max(0, m - ramp)
                var hardSpikes = min(2, max(0, mid / 5))
                while mid > 0 {
                    if hardSpikes > 0 {
                        plan += slots(of: .hard, count: 1, target: 0.72)
                        hardSpikes -= 1; mid -= 1
                        if mid <= 0 { break }
                    }
                    let chunk = min(2, mid)
                    plan += slots(of: .strong, count: chunk, target: 0.60)
                    mid -= chunk
                }
            }
        case .shortWaves:
            // Strict alternation between Easy and Hard, one song at a time.
            // Start with Hard if warm-up ended with Easy to avoid Easy→Easy adjacency.
            // Allow one Max near the end only (not in first cycle), replacing a Hard.
            var usedMax = false
            let startWithHard = !plan.isEmpty && plan.last?.effort == .easy
            for i in 0..<m {
                let isHardPos = (i % 2 == 0) ? startWithHard : !startWithHard
                if isHardPos {
                    if !usedMax && i > 1 && i >= m - 3 && m >= 6 {
                        plan.append(Slot(effort: .max, targetEffort: 0.85)); usedMax = true
                    } else {
                        plan.append(Slot(effort: .hard, targetEffort: 0.80))
                    }
                } else {
                    plan.append(Slot(effort: .easy, targetEffort: 0.45))
                }
            }
        case .longWaves:
            // Repeat Moderate ↔ Hard; no Max
            let pattern: [EffortTier] = [.moderate, .hard]
            for i in 0..<m { let e = pattern[i % pattern.count]; plan.append(Slot(effort: e, targetEffort: e == .moderate ? 0.48 : 0.80)) }
        case .pyramid:
            // Moderate → Strong → Hard → Max → Hard → Strong → Moderate (drop Max first if short)
            var seq: [EffortTier] = [.moderate, .strong, .hard, .max, .hard, .strong, .moderate]
            while seq.count > m { if let idx = seq.firstIndex(of: .max) { seq.remove(at: idx) } else { seq.remove(at: seq.count/2) } }
            while seq.count < m { seq.insert(.strong, at: seq.count/2) }
            for (idx, e) in seq.enumerated() {
                let t: Double = (e == .moderate ? 0.48 : e == .strong ? 0.60 : e == .hard ? 0.80 : 0.85)
                plan.append(Slot(effort: e, targetEffort: idx <= seq.count/2 ? min(0.85, 0.35 + Double(idx) * 0.1) : t))
            }
        case .kicker:
            // Moderate/Strong base; final ramp to Hard then Max; caps: max≤1, hard≤2; for short runs end at Hard only
            if m <= 2 {
                plan += slots(of: .hard, count: m, target: 0.80)
            } else {
                let tail = min(2, m)
                let head = m - tail
                // base
                for i in 0..<head { plan.append(Slot(effort: (i % 2 == 0 ? .moderate : .strong), targetEffort: i % 2 == 0 ? 0.48 : 0.60)) }
                // ramp
                plan += slots(of: .hard, count: min(2, tail), target: 0.80)
                if tail > 1 { plan[plan.count - 1] = Slot(effort: .max, targetEffort: 0.85) }
            }
        case .longEasy:
            // Mostly Easy; ≤20% Moderate
            let modCount = min(max(0, Int(round(Double(m) * 0.2))), max(0, m - 1))
            let pre = (m - modCount) / 2
            let post = m - modCount - pre
            plan += slots(of: .easy, count: pre, target: 0.45)
            plan += slots(of: .moderate, count: modCount, target: 0.48)
            plan += slots(of: .easy, count: post, target: 0.45)
        }

        // Cooldown (Easy ~0.35)
        plan += slots(of: .easy, count: max(1, cd / 4), target: 0.35)
        return plan
    }

    // Overload: Build effort timeline using explicit slot counts for warmup/core/cooldown.
    private func buildEffortTimeline(template: RunTemplateType,
                                     wuSlots: Int,
                                     coreSlots: Int,
                                     cdSlots: Int) -> [Slot] {
        if template == .rest { return [] }
        func slots(of effort: EffortTier, count: Int, target: Double) -> [Slot] {
            guard count > 0 else { return [] }
            return (0..<count).map { _ in Slot(effort: effort, targetEffort: target) }
        }
        var plan: [Slot] = []
        // Warm-up (Easy ~0.40)
        plan += slots(of: .easy, count: max(0, wuSlots), target: 0.40)
        // Core by template using coreSlots as the count 'm'
        let m = max(0, coreSlots)
        switch template {
        case .rest:
            break
        case .easyRun:
            let modCount = min(max(0, Int(round(Double(m) * 0.2))), max(0, m - 1))
            let pre = max(0, (m - modCount) / 2)
            let post = max(0, m - modCount - pre)
            plan += slots(of: .easy, count: pre, target: 0.45)
            plan += slots(of: .moderate, count: modCount, target: 0.48)
            plan += slots(of: .easy, count: post, target: 0.45)
        case .strongSteady:
            if m <= 2 {
                plan += slots(of: .strong, count: m, target: 0.60)
            } else {
                let ramp = min(2, m)
                plan += slots(of: .moderate, count: ramp, target: 0.55)
                var mid = max(0, m - ramp)
                var hardSpikes = min(2, max(0, mid / 5))
                while mid > 0 {
                    if hardSpikes > 0 {
                        plan += slots(of: .hard, count: 1, target: 0.72)
                        hardSpikes -= 1; mid -= 1
                        if mid <= 0 { break }
                    }
                    let chunk = min(2, mid)
                    plan += slots(of: .strong, count: chunk, target: 0.60)
                    mid -= chunk
                }
            }
        case .shortWaves:
            var usedMax = false
            let startWithHard = !plan.isEmpty && plan.last?.effort == .easy
            for i in 0..<m {
                let isHardPos = (i % 2 == 0) ? startWithHard : !startWithHard
                if isHardPos {
                    if !usedMax && i > 1 && i >= m - 3 && m >= 6 {
                        plan.append(Slot(effort: .max, targetEffort: 0.85)); usedMax = true
                    } else {
                        plan.append(Slot(effort: .hard, targetEffort: 0.80))
                    }
                } else {
                    plan.append(Slot(effort: .easy, targetEffort: 0.45))
                }
            }
        case .longWaves:
            let pattern: [EffortTier] = [.moderate, .hard]
            for i in 0..<m { let e = pattern[i % pattern.count]; plan.append(Slot(effort: e, targetEffort: e == .moderate ? 0.48 : 0.80)) }
        case .pyramid:
            var seq: [EffortTier] = [.moderate, .strong, .hard, .max, .hard, .strong, .moderate]
            while seq.count > m { if let idx = seq.firstIndex(of: .max) { seq.remove(at: idx) } else { seq.remove(at: seq.count/2) } }
            while seq.count < m { seq.insert(.strong, at: seq.count/2) }
            for (idx, e) in seq.enumerated() {
                let t: Double = (e == .moderate ? 0.48 : e == .strong ? 0.60 : e == .hard ? 0.80 : 0.85)
                plan.append(Slot(effort: e, targetEffort: idx <= seq.count/2 ? min(0.85, 0.35 + Double(idx) * 0.1) : t))
            }
        case .kicker:
            if m <= 2 {
                plan += slots(of: .hard, count: m, target: 0.80)
            } else {
                let tail = min(2, m)
                let head = m - tail
                for i in 0..<head { plan.append(Slot(effort: (i % 2 == 0 ? .moderate : .strong), targetEffort: i % 2 == 0 ? 0.48 : 0.60)) }
                plan += slots(of: .hard, count: min(2, tail), target: 0.80)
                if tail > 1 { plan[plan.count - 1] = Slot(effort: .max, targetEffort: 0.85) }
            }
        case .longEasy:
            let modCount = min(max(0, Int(round(Double(m) * 0.2))), max(0, m - 1))
            let pre = max(0, (m - modCount) / 2)
            let post = max(0, m - modCount - pre)
            plan += slots(of: .easy, count: pre, target: 0.45)
            plan += slots(of: .moderate, count: modCount, target: 0.48)
            plan += slots(of: .easy, count: post, target: 0.45)
        }
        // Cooldown (Easy ~0.35)
        plan += slots(of: .easy, count: max(0, cdSlots), target: 0.35)
        return plan
    }

    // MARK: - Effort tiers (5-tier scaffolding)
    enum EffortTier: String { case easy, moderate, strong, hard, max }

    struct TierSpec {
        let targetEffort: Double
        let tempoToleranceBPM: Double
        let tempoFitMinimum: Double
        let weights: (tempo: Double, energy: Double, dance: Double)
        let energyMin: Double? // soft floor (nil for easy)
        let energyCapEasy: Double? // cap only used for easy
    }

    // Defaults per tier; not yet wired into scoring (scaffold only)
    private func tierSpec(for tier: EffortTier) -> TierSpec {
        switch tier {
        case .easy:
            return TierSpec(targetEffort: 0.35,
                            tempoToleranceBPM: 15,
                            tempoFitMinimum: 0.35,
                            weights: (0.65, 0.25, 0.10),
                            energyMin: nil,
                            energyCapEasy: 0.70)
        case .moderate:
            return TierSpec(targetEffort: 0.48,
                            tempoToleranceBPM: 12,
                            tempoFitMinimum: 0.42,
                            weights: (0.62, 0.28, 0.10),
                            energyMin: 0.35,
                            energyCapEasy: nil)
        case .strong:
            return TierSpec(targetEffort: 0.60,
                            tempoToleranceBPM: 10,
                            tempoFitMinimum: 0.50,
                            weights: (0.60, 0.30, 0.10),
                            energyMin: 0.45,
                            energyCapEasy: nil)
        case .hard:
            return TierSpec(targetEffort: 0.72,
                            tempoToleranceBPM: 8,
                            tempoFitMinimum: 0.55,
                            weights: (0.58, 0.32, 0.10),
                            energyMin: 0.55,
                            energyCapEasy: nil)
        case .max:
            return TierSpec(targetEffort: 0.85,
                            tempoToleranceBPM: 6,
                            tempoFitMinimum: 0.60,
                            weights: (0.56, 0.34, 0.10),
                            energyMin: 0.65,
                            energyCapEasy: nil)
        }
    }

    // Bridge for future migration from 3-level EffortLevel to 5-tier EffortTier
    private func mapEffortLevelToTier(_ e: EffortLevel) -> EffortTier {
        switch e { case .easy: return .easy; case .steady: return .strong; case .hard: return .hard }
    }

    // MARK: - Scoring core (EffortIndex, SlotFit)
    struct ScoreComponents {
        let tempoFit: Double
        let effortIndex: Double
        let slotFit: Double
        let baseScore: Double // 0.60 × SlotFit (bonuses added later)
    }

    private func score(candidate: Candidate,
                       anchorSPM: Double,
                       slot: Slot) -> ScoreComponents {
        let energy = clamp01(candidate.features?.energy)
        let dance = clamp01(candidate.features?.danceability)
        let tempoBPM = candidate.features?.tempo
        // Map 5-tier to 3-level window for now; use tier tolerance
        let tol = tierSpec(for: slot.effort).tempoToleranceBPM
        let effort3: EffortLevel = mapTierToEffortLevel(slot.effort)
        let tempoFit = PaceUtils.tempoFitScore(tempoBPM: tempoBPM,
                                               energy: energy,
                                               danceability: dance,
                                               anchorSPM: anchorSPM,
                                               effort: effort3,
                                               toleranceBPM: tol)
        // Tier-specific weights
        let spec = tierSpec(for: slot.effort)
        let (wTempo, wEnergy, wDance) = spec.weights
        let effortIndex = wTempo * tempoFit + wEnergy * (energy ?? 0.5) + wDance * (dance ?? 0.5)
        let slotFit = max(0.0, 1.0 - abs(effortIndex - slot.targetEffort))
        var baseScore = 0.60 * slotFit
        // Energy shaping: Easy cap, higher-tier floors (soft)
        if slot.effort == .easy {
            let eVal = energy ?? 0.5
            if eVal > 0.70 {
                let penalty = 0.12 * min(1.0, (eVal - 0.70) / 0.30) // up to -0.12
                baseScore = max(0.0, baseScore - penalty)
            }
        } else if let floor = spec.energyMin {
            let eVal = energy ?? 0.5
            if eVal < floor {
                let penalty = 0.10 * min(1.0, (floor - eVal) / floor)
                baseScore = max(0.0, baseScore - penalty)
            }
        }
        return ScoreComponents(tempoFit: tempoFit, effortIndex: effortIndex, slotFit: slotFit, baseScore: baseScore)
    }

    private func tempoFitThreshold(for effort: EffortTier) -> Double {
        let spec = tierSpec(for: effort)
        return spec.tempoFitMinimum
    }

    private func mapTierToEffortLevel(_ t: EffortTier) -> EffortLevel {
        switch t { case .easy: return .easy; case .moderate: return .steady; case .strong: return .steady; case .hard: return .hard; case .max: return .hard }
    }

    private func clamp01(_ v: Double?) -> Double? {
        guard let v = v else { return nil }
        return max(0.0, min(1.0, v))
    }
}


