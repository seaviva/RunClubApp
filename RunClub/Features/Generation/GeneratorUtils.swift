//
//  GeneratorUtils.swift
//  RunClub
//
//  Utilities for pace→cadence mapping and tempo window helpers used by the local generator.
//

import Foundation

enum EffortLevel {
    case easy
    case steady
    case hard
}

enum PaceUtils {
    // Map pace bucket → cadence anchor (steps per minute)
    static func cadenceAnchorSPM(for bucket: PaceBucket) -> Double {
        switch bucket {
        case .A: return 158
        case .B: return 165
        case .C: return 172
        case .D: return 178
        }
    }

    // Derive slot tempo window from cadence anchor and effort level
    // Windows are in SPM and accept half/double‑time matching elsewhere
    static func tempoWindowSPM(anchor: Double, effort: EffortLevel) -> (min: Double, max: Double) {
        switch effort {
        case .easy:
            return (anchor * 0.90, anchor * 1.00)
        case .steady:
            return (anchor * 1.00, anchor * 1.05)
        case .hard:
            return (anchor * 1.05, anchor * 1.10)
        }
    }

    // Compute the best match distance to the window considering tempo, half‑time, and double‑time.
    // Returns the candidate tempo that best fits and its absolute distance to the window (0 when inside).
    static func bestTempoMatchDistance(tempoBPM: Double,
                                       anchorSPM: Double,
                                       effort: EffortLevel) -> (matchedTempo: Double, distanceBPM: Double) {
        // Map cadence SPM → target BPM window (we treat SPM≈BPM for single-step beats)
        let window = tempoWindowSPM(anchor: anchorSPM, effort: effort)
        // Candidate tempos: bpm (exact), half-time, double-time
        let candidates = [tempoBPM, tempoBPM * 0.5, tempoBPM * 2.0]
        var best: (Double, Double) = (tempoBPM, distanceToWindow(candidate: tempoBPM, window: window))
        for c in candidates {
            let d = distanceToWindow(candidate: c, window: window)
            if d < best.1 { best = (c, d) }
        }
        return best
    }

    // Convert a distance (BPM) into a [0,1] fit score using a linear falloff with tolerance.
    // If inside window → 1.0; else decays to 0 at toleranceBPM.
    static func tempoFitScore(tempoBPM: Double?,
                              energy: Double?,
                              danceability: Double?,
                              anchorSPM: Double,
                              effort: EffortLevel,
                              toleranceBPM: Double = 15.0) -> Double {
        if let t = tempoBPM {
            let (_, dist) = bestTempoMatchDistance(tempoBPM: t, anchorSPM: anchorSPM, effort: effort)
            if dist <= 0 { return 1.0 }
            let score = max(0.0, 1.0 - (dist / toleranceBPM))
            return score
        }
        // Missing tempo → use proxy from energy+danceability (neutral, not punitive)
        let e = max(0.0, min(1.0, energy ?? 0.0))
        let d = max(0.0, min(1.0, danceability ?? 0.0))
        return max(0.0, min(1.0, 0.6 * e + 0.4 * d)) * 0.9 // slight downweight when tempo missing
    }

    // MARK: - Private
    private static func distanceToWindow(candidate: Double, window: (min: Double, max: Double)) -> Double {
        if candidate < window.min { return window.min - candidate }
        if candidate > window.max { return candidate - window.max }
        return 0
    }
}


