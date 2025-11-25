//
//  RunClubTests.swift
//  RunClubTests
//
//  Created by Christian Vivadelli on 8/15/25.
//

import Testing
@testable import RunClub

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
