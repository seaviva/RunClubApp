import Foundation
import SwiftData

/// CLI version of the LocalGenerator for playlist generation.
/// This mirrors the app's LocalGenerator algorithm for headless testing.
@MainActor
final class LocalGenerator {
    
    // MARK: - Types
    
    struct Slot {
        let effort: EffortTier
        let targetEffort: Double
    }
    
    struct Candidate {
        let track: CachedTrack
        let features: AudioFeature?
        let artist: CachedArtist?
        let isRediscovery: Bool
        let lastUsedAt: Date?
        let genreAffinity: Double
        let source: SourceKind
    }
    
    struct TierSpec {
        let targetEffort: Double
        let tempoToleranceBPM: Double
        let tempoFitMinimum: Double
        let weights: (tempo: Double, energy: Double, dance: Double)
        let energyMin: Double?
        let energyCapEasy: Double?
    }
    
    struct ScoreComponents {
        let tempoFit: Double
        let effortIndex: Double
        let slotFit: Double
        let baseScore: Double
    }
    
    struct SelectionResult {
        let selected: [Candidate]
        let totalSeconds: Int
        let efforts: [EffortTier]
        let segments: [String]  // "warmup", "main", "cooldown" for each track
        let debugLines: [String]
        let metrics: GenerationMetrics
    }
    
    struct GenerationMetrics {
        var warmupSeconds: Int = 0
        var mainSeconds: Int = 0
        var cooldownSeconds: Int = 0
        var warmupTarget: Int = 0
        var mainTarget: Int = 0
        var cooldownTarget: Int = 0
        var avgTempoFit: Double = 0.0
        var avgSlotFit: Double = 0.0
        var avgGenreAffinity: Double = 0.0
        var rediscoveryPct: Double = 0.0
        var uniqueArtists: Int = 0
        var neighborRelaxSlots: Int = 0
        var lockoutBreaks: Int = 0
        var sourceLikes: Int = 0
        var sourcePlaylists: Int = 0
        var sourceThird: Int = 0
    }
    
    // MARK: - Properties
    
    private let likesContext: ModelContext
    private let playlistsContext: ModelContext
    private let thirdSourceContext: ModelContext
    private var debugLines: [String] = []
    
    // MARK: - Initialization
    
    init(likesContext: ModelContext, playlistsContext: ModelContext, thirdSourceContext: ModelContext) {
        self.likesContext = likesContext
        self.playlistsContext = playlistsContext
        self.thirdSourceContext = thirdSourceContext
    }
    
    convenience init(bridge: DataBridge) {
        self.init(
            likesContext: bridge.likesContext,
            playlistsContext: bridge.playlistsContext,
            thirdSourceContext: bridge.thirdSourceContext
        )
    }
    
    // MARK: - Debug Logging
    
    private func emit(_ line: String) {
        debugLines.append(line)
    }
    
    // MARK: - Public API
    
    func generateDryRun(
        template: RunTemplateType,
        runMinutes: Int,
        genres: [Genre],
        decades: [Decade]
    ) throws -> GenerationOutput {
        debugLines = []
        
        // Select candidates
        let selection = try selectCandidates(
            template: template,
            runMinutes: runMinutes,
            genres: genres,
            decades: decades
        )
        
        // Build slot outputs
        var slots: [SlotOutput] = []
        let counts = plannedSegmentCounts(template: template, runMinutes: runMinutes)
        
        for (idx, candidate) in selection.selected.enumerated() {
            let effort = idx < selection.efforts.count ? selection.efforts[idx] : .easy
            let segment = idx < selection.segments.count ? selection.segments[idx] : "main"
            
            let slot = buildEffortTimeline(template: template, runMinutes: runMinutes)
            let targetEffort = idx < slot.count ? slot[idx].targetEffort : 0.4
            
            slots.append(SlotOutput(
                index: idx,
                segment: segment,
                effort: effort.rawValue,
                targetEffort: targetEffort,
                trackId: candidate.track.id,
                artistId: candidate.track.artistId,
                artistName: candidate.artist?.name ?? candidate.track.artistName,
                trackName: candidate.track.name,
                tempo: candidate.features?.tempo,
                energy: candidate.features?.energy,
                danceability: candidate.features?.danceability,
                durationSeconds: candidate.track.durationMs / 1000,
                tempoFit: score(candidate: candidate, slot: Slot(effort: effort, targetEffort: targetEffort)).tempoFit,
                effortIndex: score(candidate: candidate, slot: Slot(effort: effort, targetEffort: targetEffort)).effortIndex,
                slotFit: score(candidate: candidate, slot: Slot(effort: effort, targetEffort: targetEffort)).slotFit,
                genreAffinity: candidate.genreAffinity,
                isRediscovery: candidate.isRediscovery,
                usedNeighbor: false,
                brokeLockout: false,
                source: candidate.source.rawValue,
                genres: candidate.artist?.genres ?? []
            ))
        }
        
        let plan = durationPlan(for: template, minutes: runMinutes)
        
        return GenerationOutput(
            template: template.rawValue,
            runMinutes: runMinutes,
            genres: genres.map { $0.displayName },
            decades: decades.map { $0.displayName },
            trackIds: selection.selected.map { $0.track.id },
            artistIds: selection.selected.map { $0.track.artistId },
            efforts: selection.efforts.map { $0.rawValue },
            sources: selection.selected.map { $0.source.rawValue },
            totalSeconds: selection.totalSeconds,
            minSeconds: max(0, (plan.total - 2) * 60),
            maxSeconds: (plan.total + 2) * 60,
            warmupSeconds: selection.metrics.warmupSeconds,
            mainSeconds: selection.metrics.mainSeconds,
            cooldownSeconds: selection.metrics.cooldownSeconds,
            warmupTarget: selection.metrics.warmupTarget,
            mainTarget: selection.metrics.mainTarget,
            cooldownTarget: selection.metrics.cooldownTarget,
            preflightUnplayable: 0,
            swapped: 0,
            removed: 0,
            market: "US",
            slots: slots,
            avgTempoFit: selection.metrics.avgTempoFit,
            avgSlotFit: selection.metrics.avgSlotFit,
            avgGenreAffinity: selection.metrics.avgGenreAffinity,
            rediscoveryPct: selection.metrics.rediscoveryPct,
            uniqueArtists: selection.metrics.uniqueArtists,
            neighborRelaxSlots: selection.metrics.neighborRelaxSlots,
            lockoutBreaks: selection.metrics.lockoutBreaks,
            sourceLikes: selection.metrics.sourceLikes,
            sourcePlaylists: selection.metrics.sourcePlaylists,
            sourceThird: selection.metrics.sourceThird,
            debugLines: selection.debugLines,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    // MARK: - Duration Planning
    
    func durationPlan(for template: RunTemplateType, minutes: Int) -> (total: Int, wu: Int, core: Int, cd: Int) {
        let total = max(1, minutes)
        let wu: Int
        let cd: Int
        
        if total < 30 {
            wu = 5; cd = 5
        } else if total <= 45 {
            wu = 7; cd = 5
        } else {
            wu = 10; cd = 7
        }
        
        let core = max(0, total - wu - cd)
        return (total, wu, core, cd)
    }
    
    func plannedSegmentCounts(template: RunTemplateType, runMinutes: Int) -> (wuSlots: Int, coreSlots: Int, cdSlots: Int) {
        let planMins = durationPlan(for: template, minutes: runMinutes)
        let avgTrackSecs = 210.0
        let wuSlots = max(1, Int(round(Double(planMins.wu * 60) / avgTrackSecs)))
        let coreSlots = max(1, Int(round(Double(planMins.core * 60) / avgTrackSecs)))
        var cdSlots = max(1, Int(round(Double(planMins.cd * 60) / avgTrackSecs)))
        if planMins.cd >= 5 { cdSlots = max(cdSlots, 2) }
        return (wuSlots, coreSlots, cdSlots)
    }
    
    // MARK: - Effort Timeline
    
    func buildEffortTimeline(template: RunTemplateType, runMinutes: Int) -> [Slot] {
        let counts = plannedSegmentCounts(template: template, runMinutes: runMinutes)
        return buildEffortTimeline(template: template, wuSlots: counts.wuSlots, coreSlots: counts.coreSlots, cdSlots: counts.cdSlots)
    }
    
    private func buildEffortTimeline(template: RunTemplateType, wuSlots: Int, coreSlots: Int, cdSlots: Int) -> [Slot] {
        var plan: [Slot] = []
        
        // Warmup (Easy)
        for _ in 0..<wuSlots {
            plan.append(Slot(effort: .easy, targetEffort: 0.40))
        }
        
        // Core by template
        let m = coreSlots
        switch template {
        case .light:
            let modCount = min(max(0, Int(round(Double(m) * 0.2))), max(0, m - 1))
            let pre = max(0, (m - modCount) / 2)
            let post = max(0, m - modCount - pre)
            for _ in 0..<pre { plan.append(Slot(effort: .easy, targetEffort: 0.45)) }
            for _ in 0..<modCount { plan.append(Slot(effort: .moderate, targetEffort: 0.48)) }
            for _ in 0..<post { plan.append(Slot(effort: .easy, targetEffort: 0.45)) }
            
        case .tempo:
            if m <= 2 {
                for _ in 0..<m { plan.append(Slot(effort: .strong, targetEffort: 0.60)) }
            } else {
                let ramp = min(2, m)
                for _ in 0..<ramp { plan.append(Slot(effort: .moderate, targetEffort: 0.55)) }
                var mid = max(0, m - ramp)
                var hardSpikes = min(2, max(0, mid / 5))
                while mid > 0 {
                    if hardSpikes > 0 {
                        plan.append(Slot(effort: .hard, targetEffort: 0.72))
                        hardSpikes -= 1; mid -= 1
                        if mid <= 0 { break }
                    }
                    let chunk = min(2, mid)
                    for _ in 0..<chunk { plan.append(Slot(effort: .strong, targetEffort: 0.60)) }
                    mid -= chunk
                }
            }
            
        case .hiit:
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
            
        case .intervals:
            let pattern: [EffortTier] = [.moderate, .hard]
            for i in 0..<m {
                let e = pattern[i % pattern.count]
                plan.append(Slot(effort: e, targetEffort: e == .moderate ? 0.48 : 0.80))
            }
            
        case .pyramid:
            var seq: [EffortTier] = [.moderate, .strong, .hard, .max, .hard, .strong, .moderate]
            while seq.count > m {
                if let idx = seq.firstIndex(of: .max) { seq.remove(at: idx) }
                else { seq.remove(at: seq.count / 2) }
            }
            while seq.count < m { seq.insert(.strong, at: seq.count / 2) }
            for (idx, e) in seq.enumerated() {
                let t: Double = (e == .moderate ? 0.48 : e == .strong ? 0.60 : e == .hard ? 0.80 : 0.85)
                plan.append(Slot(effort: e, targetEffort: idx <= seq.count / 2 ? min(0.85, 0.35 + Double(idx) * 0.1) : t))
            }
            
        case .kicker:
            if m <= 2 {
                for _ in 0..<m { plan.append(Slot(effort: .hard, targetEffort: 0.80)) }
            } else {
                let tail = min(2, m)
                let head = m - tail
                for i in 0..<head {
                    plan.append(Slot(effort: (i % 2 == 0 ? .moderate : .strong), targetEffort: i % 2 == 0 ? 0.48 : 0.60))
                }
                for _ in 0..<min(2, tail) { plan.append(Slot(effort: .hard, targetEffort: 0.80)) }
                if tail > 1 { plan[plan.count - 1] = Slot(effort: .max, targetEffort: 0.85) }
            }
        }
        
        // Cooldown (Easy)
        for _ in 0..<cdSlots {
            plan.append(Slot(effort: .easy, targetEffort: 0.35))
        }
        
        return plan
    }
    
    // MARK: - Tier Specifications
    
    private func tierSpec(for tier: EffortTier) -> TierSpec {
        switch tier {
        case .easy:
            return TierSpec(targetEffort: 0.35, tempoToleranceBPM: 15, tempoFitMinimum: 0.35,
                          weights: (0.65, 0.25, 0.10), energyMin: nil, energyCapEasy: 0.70)
        case .moderate:
            return TierSpec(targetEffort: 0.48, tempoToleranceBPM: 12, tempoFitMinimum: 0.42,
                          weights: (0.62, 0.28, 0.10), energyMin: 0.35, energyCapEasy: nil)
        case .strong:
            return TierSpec(targetEffort: 0.60, tempoToleranceBPM: 10, tempoFitMinimum: 0.50,
                          weights: (0.60, 0.30, 0.10), energyMin: 0.45, energyCapEasy: nil)
        case .hard:
            return TierSpec(targetEffort: 0.72, tempoToleranceBPM: 8, tempoFitMinimum: 0.55,
                          weights: (0.58, 0.32, 0.10), energyMin: 0.55, energyCapEasy: nil)
        case .max:
            return TierSpec(targetEffort: 0.85, tempoToleranceBPM: 6, tempoFitMinimum: 0.60,
                          weights: (0.56, 0.34, 0.10), energyMin: 0.65, energyCapEasy: nil)
        }
    }
    
    // MARK: - Tempo Windows
    
    private func tempoWindow(for tier: EffortTier) -> (min: Double, max: Double) {
        switch tier {
        case .easy: return (150, 165)
        case .moderate: return (155, 170)
        case .strong: return (160, 178)
        case .hard: return (168, 186)
        case .max: return (172, 190)
        }
    }
    
    // MARK: - Scoring
    
    private func score(candidate: Candidate, slot: Slot) -> ScoreComponents {
        let energy = clamp01(candidate.features?.energy)
        let dance = clamp01(candidate.features?.danceability)
        let tempoBPM = candidate.features?.tempo
        let tempoFit = tempoFitScore(for: slot.effort, tempoBPM: tempoBPM, energy: energy, danceability: dance)
        
        let spec = tierSpec(for: slot.effort)
        let (wTempo, wEnergy, wDance) = spec.weights
        let effortIndex = wTempo * tempoFit + wEnergy * (energy ?? 0.5) + wDance * (dance ?? 0.5)
        let slotFit = max(0.0, 1.0 - abs(effortIndex - slot.targetEffort))
        var baseScore = 0.60 * slotFit
        
        // Energy shaping
        if slot.effort == .easy {
            let eVal = energy ?? 0.5
            if eVal > 0.70 {
                let penalty = 0.12 * min(1.0, (eVal - 0.70) / 0.30)
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
    
    private func tempoFitScore(for tier: EffortTier, tempoBPM: Double?, energy: Double?, danceability: Double?) -> Double {
        if let tempo = tempoBPM {
            let window = tempoWindow(for: tier)
            let dist = bestTempoMatchDistance(tempoBPM: tempo, window: window)
            if dist <= 0 { return 1.0 }
            let tolerance = tierSpec(for: tier).tempoToleranceBPM
            return max(0.0, 1.0 - (dist / tolerance))
        }
        let energyVal = max(0.0, min(1.0, energy ?? 0.5))
        let danceVal = max(0.0, min(1.0, danceability ?? 0.5))
        return max(0.0, min(1.0, 0.6 * energyVal + 0.4 * danceVal)) * 0.9
    }
    
    private func bestTempoMatchDistance(tempoBPM: Double, window: (min: Double, max: Double)) -> Double {
        let candidates = [tempoBPM, tempoBPM * 0.5, tempoBPM * 2.0]
        var best = Double.greatestFiniteMagnitude
        for candidate in candidates {
            let distance = distanceToTempoWindow(candidate: candidate, window: window)
            if distance < best { best = distance }
        }
        return best
    }
    
    private func distanceToTempoWindow(candidate: Double, window: (min: Double, max: Double)) -> Double {
        if candidate < window.min { return window.min - candidate }
        if candidate > window.max { return candidate - window.max }
        return 0
    }
    
    private func clamp01(_ v: Double?) -> Double? {
        guard let v = v else { return nil }
        return max(0.0, min(1.0, v))
    }
    
    // MARK: - Candidate Selection
    
    private func selectCandidates(
        template: RunTemplateType,
        runMinutes: Int,
        genres: [Genre],
        decades: [Decade]
    ) throws -> SelectionResult {
        let planDurMins = durationPlan(for: template, minutes: runMinutes)
        let genreFilterNames = genres.map { $0.displayName }.joined(separator: ", ")
        let decadeFilterNames = decades.map { $0.displayName }.joined(separator: ", ")
        emit("LocalGen config — template:\(template.rawValue) run:\(runMinutes)m segmentsPlanned:[wu:\(planDurMins.wu)m main:\(planDurMins.core)m cd:\(planDurMins.cd)m] filters:genres=[\(genreFilterNames.isEmpty ? "none" : genreFilterNames)] decades=[\(decadeFilterNames.isEmpty ? "none" : decadeFilterNames)]")
        
        // Build umbrella weights
        let selectedIds = genres.map { $0.umbrellaId }
        let umbrellaWeights = GenreUmbrellaService.shared.selectedWithNeighborsWeights(selectedIds: selectedIds, neighborWeight: 0.6)
        
        // Build candidate pool
        let pool = try buildCandidatePool(genres: genres, decades: decades, umbrellaWeights: umbrellaWeights)
        
        // Build effort timeline
        let counts = plannedSegmentCounts(template: template, runMinutes: runMinutes)
        let slots = buildEffortTimeline(template: template, wuSlots: counts.wuSlots, coreSlots: counts.coreSlots, cdSlots: counts.cdSlots)
        
        // Duration bounds
        let plan = durationPlan(for: template, minutes: runMinutes)
        let minSeconds = max(0, (plan.total - 2) * 60)
        let maxSeconds = (plan.total + 2) * 60
        
        var selected: [Candidate] = []
        var chosenEfforts: [EffortTier] = []
        var chosenSegments: [String] = []
        var perArtistCount: [String: Int] = [:]
        var recentArtists: [String] = []
        var secondsSoFar = 0
        var wuSecondsAcc = 0
        var mainSecondsAcc = 0
        var cdSecondsAcc = 0
        var chosenRediscovery = 0
        var metricTempoFitSum = 0.0
        var metricSlotFitSum = 0.0
        var metricCount = 0
        
        let perArtistMax = (template == .light ? 1 : 2)
        let cooldownStartIndex = counts.wuSlots + counts.coreSlots
        var lastTempo: Double? = nil
        
        for (slotIndex, slot) in slots.enumerated() {
            let isCooldownSlot = slotIndex >= cooldownStartIndex
            
            // Skip remaining CORE slots if we've hit min duration (but always process warmup and cooldown)
            if secondsSoFar >= minSeconds && slotIndex >= counts.wuSlots && !isCooldownSlot {
                emit("Slot #\(slotIndex) [skipped - duration hit, not cooldown]")
                continue
            }
            
            // Hard stop if we've exceeded max seconds
            if secondsSoFar >= maxSeconds {
                emit("Slot #\(slotIndex) [stopped - exceeded max seconds \(maxSeconds)]")
                break
            }
            
            // Filter available candidates
            let available = pool.filter { c in
                !selected.contains(where: { $0.track.id == c.track.id }) &&
                (perArtistCount[c.track.artistId] ?? 0) < perArtistMax &&
                (recentArtists.last != c.track.artistId)
            }
            
            guard !available.isEmpty else { continue }
            
            // Score candidates
            // Relax tempo requirements for cooldown to ensure we always fill it
            let tempoMinimum = isCooldownSlot ? 0.20 : tierSpec(for: slot.effort).tempoFitMinimum
            
            var scored: [(Candidate, Double)] = []
            for c in available {
                let base = score(candidate: c, slot: slot)
                if base.tempoFit < tempoMinimum { continue }
                
                // Basic scoring with bonuses
                var bonus = 0.0
                bonus += 0.08 * c.genreAffinity
                if c.isRediscovery { bonus += 0.05 }
                if c.source == .likes { bonus += 0.03 }
                
                // Transition smoothness bonus: prefer tracks within ±15 BPM of previous
                if let prevTempo = lastTempo, let thisTempo = c.features?.tempo {
                    let tempoDiff = abs(thisTempo - prevTempo)
                    if tempoDiff <= 15 {
                        bonus += 0.10  // Strong bonus for smooth transition
                    } else if tempoDiff <= 25 {
                        bonus += 0.05  // Mild bonus
                    } else if tempoDiff > 40 {
                        bonus -= 0.05  // Penalty for jarring jump
                    }
                }
                
                scored.append((c, base.baseScore + bonus))
            }
            
            guard !scored.isEmpty else {
                emit("Slot #\(slotIndex) [\(slot.effort)] • NO CANDIDATES passed scoring (available:\(available.count))")
                continue
            }
            
            // Select from top candidates
            scored.sort { $0.1 > $1.1 }
            let topK = Array(scored.prefix(8))
            let sum = topK.map { max(0.0001, $0.1) }.reduce(0, +)
            var r = Double.random(in: 0..<sum)
            var choice = topK.first!.0
            for (cand, s) in topK {
                r -= max(0.0001, s)
                if r <= 0 { choice = cand; break }
            }
            
            let secs = choice.track.durationMs / 1000
            // Allow cooldown tracks even if they slightly exceed max (up to 3 min over)
            let effectiveMax = isCooldownSlot ? maxSeconds + 180 : maxSeconds
            if secs <= 6 * 60 && secondsSoFar + secs <= effectiveMax {
                selected.append(choice)
                chosenEfforts.append(slot.effort)
                
                // Determine segment based on slot position (not output index)
                let segment: String
                if slotIndex < counts.wuSlots {
                    segment = "warmup"
                    wuSecondsAcc += secs
                } else if slotIndex < cooldownStartIndex {
                    segment = "main"
                    mainSecondsAcc += secs
                } else {
                    segment = "cooldown"
                    cdSecondsAcc += secs
                }
                chosenSegments.append(segment)
                
                secondsSoFar += secs
                perArtistCount[choice.track.artistId, default: 0] += 1
                recentArtists.append(choice.track.artistId)
                if recentArtists.count > 7 { recentArtists.removeFirst() }
                if choice.isRediscovery { chosenRediscovery += 1 }
                lastTempo = choice.features?.tempo  // Track for transition smoothness
                
                // Metrics
                let base = score(candidate: choice, slot: slot)
                metricTempoFitSum += base.tempoFit
                metricSlotFitSum += base.slotFit
                metricCount += 1
                
                emit("Slot #\(slotIndex) [\(slot.effort)] • \(choice.artist?.name ?? "?") — \(choice.track.name) • tempo=\(String(format: "%.0f", choice.features?.tempo ?? 0)) tempoFit=\(String(format: "%.2f", base.tempoFit)) slotFit=\(String(format: "%.2f", base.slotFit))")
            }
        }
        
        // Compute metrics
        let uniqueArtists = Set(selected.map { $0.track.artistId }).count
        var sourceLikes = 0, sourcePlaylists = 0, sourceThird = 0
        for c in selected {
            switch c.source {
            case .likes: sourceLikes += 1
            case .recs: sourcePlaylists += 1
            case .third: sourceThird += 1
            }
        }
        
        let avgGenreAffinity = selected.isEmpty ? 0.0 : selected.map { $0.genreAffinity }.reduce(0, +) / Double(selected.count)
        
        let metrics = GenerationMetrics(
            warmupSeconds: wuSecondsAcc,
            mainSeconds: mainSecondsAcc,
            cooldownSeconds: cdSecondsAcc,
            warmupTarget: planDurMins.wu * 60,
            mainTarget: planDurMins.core * 60,
            cooldownTarget: planDurMins.cd * 60,
            avgTempoFit: metricCount == 0 ? 0.0 : metricTempoFitSum / Double(metricCount),
            avgSlotFit: metricCount == 0 ? 0.0 : metricSlotFitSum / Double(metricCount),
            avgGenreAffinity: avgGenreAffinity,
            rediscoveryPct: selected.isEmpty ? 0.0 : Double(chosenRediscovery) / Double(selected.count),
            uniqueArtists: uniqueArtists,
            neighborRelaxSlots: 0,
            lockoutBreaks: 0,
            sourceLikes: sourceLikes,
            sourcePlaylists: sourcePlaylists,
            sourceThird: sourceThird
        )
        
        emit("LocalGen metrics — tracks:\(selected.count) time:\(secondsSoFar)s avgTempoFit:\(String(format: "%.2f", metrics.avgTempoFit)) avgSlotFit:\(String(format: "%.2f", metrics.avgSlotFit))")
        
        return SelectionResult(
            selected: selected,
            totalSeconds: secondsSoFar,
            efforts: chosenEfforts,
            segments: chosenSegments,
            debugLines: debugLines,
            metrics: metrics
        )
    }
    
    // MARK: - Candidate Pool Building
    
    private func buildCandidatePool(genres: [Genre], decades: [Decade], umbrellaWeights: [String: Double]) throws -> [Candidate] {
        // Fetch from all contexts
        let likesTracks = try likesContext.fetch(FetchDescriptor<CachedTrack>())
        let likesFeatures = try likesContext.fetch(FetchDescriptor<AudioFeature>())
        let likesArtists = try likesContext.fetch(FetchDescriptor<CachedArtist>())
        let usages = try likesContext.fetch(FetchDescriptor<TrackUsage>())
        
        let playlistsTracks = try playlistsContext.fetch(FetchDescriptor<CachedTrack>())
        let playlistsFeatures = try playlistsContext.fetch(FetchDescriptor<AudioFeature>())
        let playlistsArtists = try playlistsContext.fetch(FetchDescriptor<CachedArtist>())
        
        let thirdTracks = try thirdSourceContext.fetch(FetchDescriptor<CachedTrack>())
        let thirdFeatures = try thirdSourceContext.fetch(FetchDescriptor<AudioFeature>())
        let thirdArtists = try thirdSourceContext.fetch(FetchDescriptor<CachedArtist>())
        
        // Build lookups
        var featById: [String: AudioFeature] = [:]
        var artistById: [String: CachedArtist] = [:]
        var sourceById: [String: SourceKind] = [:]
        var tracks: [CachedTrack] = []
        
        let usageById = Dictionary(uniqueKeysWithValues: usages.map { ($0.trackId, $0) })
        
        // Add likes first (highest priority)
        for t in likesTracks {
            tracks.append(t)
            sourceById[t.id] = .likes
        }
        for f in likesFeatures { featById[f.trackId] = f }
        for a in likesArtists { artistById[a.id] = a }
        
        // Add playlists (second priority)
        for t in playlistsTracks {
            if sourceById[t.id] == nil {
                tracks.append(t)
                sourceById[t.id] = .recs
            }
        }
        for f in playlistsFeatures { if featById[f.trackId] == nil { featById[f.trackId] = f } }
        for a in playlistsArtists { if artistById[a.id] == nil { artistById[a.id] = a } }
        
        // Add third source (lowest priority)
        for t in thirdTracks {
            if sourceById[t.id] == nil {
                tracks.append(t)
                sourceById[t.id] = .third
            }
        }
        for f in thirdFeatures { if featById[f.trackId] == nil { featById[f.trackId] = f } }
        for a in thirdArtists { if artistById[a.id] == nil { artistById[a.id] = a } }
        
        // Filter to tracks with features
        tracks = tracks.filter { featById[$0.id] != nil }
        
        let now = Date()
        let tenDays: TimeInterval = 10 * 24 * 3600
        let sixtyDays: TimeInterval = 60 * 24 * 3600
        
        // Build candidates with filtering
        var candidates: [Candidate] = []
        for t in tracks {
            // Duration filter: min 1:30 (90s), max 6:00 (360s)
            guard t.durationMs >= 90 * 1000 else { continue }
            guard t.durationMs <= 6 * 60 * 1000 else { continue }
            guard t.isPlayable else { continue }
            
            // Require audio features with valid tempo
            guard let feat = featById[t.id], feat.tempo != nil else { continue }
            
            // 10-day lockout
            if let u = usageById[t.id], let last = u.lastUsedAt, now.timeIntervalSince(last) < tenDays {
                continue
            }
            
            // Genre filter
            if !genres.isEmpty {
                guard let a = artistById[t.artistId] else { continue }
                let aff = GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: umbrellaWeights)
                if aff <= 0.0 { continue }
            }
            
            // Decade filter
            if !decades.isEmpty {
                guard let year = t.albumReleaseYear else { continue }
                let matches = decades.contains { d in
                    let range = d.yearRange
                    return year >= range.0 && year <= range.1
                }
                if !matches { continue }
            }
            
            // Compute properties
            let isRediscovery: Bool = {
                if let u = usageById[t.id], let last = u.lastUsedAt {
                    return now.timeIntervalSince(last) >= sixtyDays
                }
                return true
            }()
            
            let affinity: Double = {
                guard let a = artistById[t.artistId] else { return 0.0 }
                return GenreUmbrellaService.shared.affinity(for: a.genres, targetUmbrellaWeights: umbrellaWeights)
            }()
            
            candidates.append(Candidate(
                track: t,
                features: featById[t.id],
                artist: artistById[t.artistId],
                isRediscovery: isRediscovery,
                lastUsedAt: usageById[t.id]?.lastUsedAt,
                genreAffinity: affinity,
                source: sourceById[t.id] ?? .likes
            ))
        }
        
        emit("Pool build — total:\(tracks.count) candidates:\(candidates.count)")
        return candidates
    }
}
