//
//  RunClubTests.swift
//  RunClubTests
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Testing
@testable import RunClub
import SwiftData

@MainActor
final class GeneratorMatrixTests {
    @Test("All templates × durations dry-run fits bounds and rules")
    func matrix() async throws {
        // Use the app's shared container (already configured in app). If unavailable, fail early.
        guard let container = try? ModelContainer(for: Schema([CachedTrack.self, AudioFeature.self, CachedArtist.self, CrawlState.self])) else {
            throw TestError.message("ModelContainer init failed")
        }
        let mc = container.mainContext
        let gen = LocalGenerator(modelContext: mc)
        let spotify = SpotifyService()
        // Access token is required for market + playability lookups
        if let root = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let delegate = root.delegate as? RunClubApp {
            // no-op; in unit context we expect token already injected by app
            _ = delegate
        }

        var failures: [String] = []
        for template in RunTemplateType.allCases {
            for duration in DurationCategory.allCases {
                do {
                    let r = try await gen.generateDryRun(template: template,
                                                          durationCategory: duration,
                                                          genres: [],
                                                          decades: [],
                                                          spotify: spotify)
                    // 1) Duration bounds
                    if !(r.totalSeconds >= r.minSeconds && r.totalSeconds <= r.maxSeconds) {
                        failures.append("bounds: \(template.rawValue)-\(duration.displayName) seconds=\(r.totalSeconds) range=[\(r.minSeconds),\(r.maxSeconds)]")
                    }
                    // 2) Per-artist ≤ 2 and no back-to-back
                    var perArtist: [String: Int] = [:]
                    for (i, aid) in r.artistIds.enumerated() {
                        perArtist[aid, default: 0] += 1
                        if i > 0 && r.artistIds[i-1] == aid { failures.append("back-to-back: \(template.rawValue)-\(duration.displayName) @\(i)") }
                    }
                    if perArtist.values.contains(where: { $0 > 2 }) {
                        failures.append("artist-cap: \(template.rawValue)-\(duration.displayName) caps=\(perArtist)")
                    }
                    // 3) Template caps
                    let maxCount = r.efforts.filter { $0 == .max }.count
                    if maxCount > 1 { failures.append("max-cap: \(template.rawValue)-\(duration.displayName) max=\(maxCount)") }
                    if template == .kicker {
                        let hardCount = r.efforts.filter { $0 == .hard }.count
                        if hardCount > 2 { failures.append("kicker-hard-cap: \(duration.displayName) hard=\(hardCount)") }
                    }
                    // 4) Preflight playability should be zero after swaps
                    if r.preflightUnplayable > 0 && (r.preflightUnplayable != r.swapped + r.removed) {
                        failures.append("preflight: \(template.rawValue)-\(duration.displayName) unplayable=\(r.preflightUnplayable) swapped=\(r.swapped) removed=\(r.removed)")
                    }
                } catch {
                    failures.append("exception: \(template.rawValue)-\(duration.displayName) \(error)")
                }
            }
        }
        #expect(failures.isEmpty, .message(failures.joined(separator: " | ")))
    }
}

struct RunClubTests {

    @Test func genreUmbrella_smoke() async throws {
        // Load mapping
        let service = GenreUmbrellaService.shared
        service.loadIfNeeded()

        // Sanity: expect 10 umbrellas from the provided file (names as display ids)
        #expect(service.umbrellasById.count >= 10)

        // Build weights for a single selected umbrella and its neighbors
        let weights = service.selectedWithNeighborsWeights(selectedIds: ["Rock & Alt"], neighborWeight: 0.6)
        #expect(weights["Rock & Alt"] == 1.0)

        // Ensure at least one neighbor exists
        #expect(weights.count > 1)

        // Affinity: artist with mixed genres should have non-zero affinity for Rock & Alt selection
        let artistGenres = ["indie rock", "garage rock", "alternative", "dance pop"]
        let affinity = service.affinity(for: artistGenres, targetUmbrellaWeights: weights)
        #expect(affinity > 0.0)
    }

    

}
