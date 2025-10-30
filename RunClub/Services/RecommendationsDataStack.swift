//
//  RecommendationsDataStack.swift
//  RunClub
//
//  Created by AI Assistant on 10/1/25.
//

import Foundation
import SwiftData

/// Separate SwiftData container for Spotify Recommendations.
/// Uses the same schema as Likes (CachedTrack, AudioFeature, CachedArtist, CrawlState)
/// but persists to its own store file so data is fully isolated.
final class RecommendationsDataStack {
    static let shared = RecommendationsDataStack()

    let container: ModelContainer
    let context: ModelContext

    private init() {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self
        ])

        // Use a named configuration so SwiftData creates a separate recommendations.store
        let configuration = ModelConfiguration("recommendations", schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            do {
                container = try ModelContainer(for: schema, configurations: [configuration])
                context = ModelContext(container)
            } catch {
                fatalError("Could not create Recommendations ModelContainer: \(error)")
            }
        }
    }
}


