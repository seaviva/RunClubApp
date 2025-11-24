//
//  PlaylistsDataStack.swift
//  RunClub
//
//  Separate SwiftData container for Playlists cache (owned/followed + recently played).
//

import Foundation
import SwiftData

/// Separate SwiftData container for Playlists.
/// Reuses core track/artist/feature models and adds playlist entities.
final class PlaylistsDataStack {
    static let shared = PlaylistsDataStack()

    let container: ModelContainer
    let context: ModelContext

    private init() {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self,
            CachedPlaylist.self,
            PlaylistMembership.self
        ])
        let configuration = ModelConfiguration("playlists", schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            fatalError("Could not create Playlists ModelContainer: \(error)")
        }
    }

    @MainActor
    func resetStore() throws {
        try context.delete(model: PlaylistMembership.self)
        try context.delete(model: CachedTrack.self)
        try context.delete(model: AudioFeature.self)
        try context.delete(model: CachedArtist.self)
        try context.delete(model: CrawlState.self)
        try context.save()
    }

    /// Clears tracks, memberships, features, artists, and crawl metadata but keeps CachedPlaylist rows (and selection).
    @MainActor
    func resetContent() throws {
        try context.delete(model: PlaylistMembership.self)
        try context.delete(model: CachedTrack.self)
        try context.delete(model: AudioFeature.self)
        try context.delete(model: CachedArtist.self)
        try context.delete(model: CrawlState.self)
        try context.save()
    }
}


