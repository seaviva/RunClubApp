//
//  ThirdSourceDataStack.swift
//  RunClub
//
//  SwiftData container for the static third-source catalog.
//  Schema mirrors Likes (tracks/features/artists + crawl state) and is isolated
//  under its own ModelConfiguration name so other stores can refresh independently.
//

import Foundation
import SwiftData

final class ThirdSourceDataStack {
    static let shared = ThirdSourceDataStack()

    let container: ModelContainer
    let context: ModelContext

    private init() {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self
        ])
        // Use a named configuration so SwiftData creates a separate thirdsource.store
        let configuration = ModelConfiguration("thirdsource", schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            fatalError("Could not create ThirdSource ModelContainer: \(error)")
        }
    }
}


