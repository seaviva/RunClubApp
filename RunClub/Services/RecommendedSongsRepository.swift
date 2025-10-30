//
//  RecommendedSongsRepository.swift
//  RunClub
//
//  Created by AI Assistant on 10/1/25.
//

import Foundation
import SwiftData

/// Repository for managing Recommended songs in the separate recommendations store.
/// Mirrors operations available for Likes, using the same model types but isolated container.
final class RecommendedSongsRepository {
    private let context: ModelContext

    init(context: ModelContext = RecommendationsDataStack.shared.context) {
        self.context = context
    }

    // MARK: - Upserts
    @MainActor
    func upsertTracks(_ tracks: [CachedTrack]) throws {
        guard !tracks.isEmpty else { return }
        do {
            for t in tracks { context.insert(t) }
            try context.save()
        } catch {
            // Fallback: insert one-by-one skipping conflicts
            context.rollback()
            for t in tracks {
                do {
                    context.insert(t)
                    try context.save()
                } catch {
                    context.rollback()
                    // likely duplicate unique id; skip
                }
            }
        }
    }

    @MainActor
    func upsertAudioFeatures(_ features: [AudioFeature]) throws {
        guard !features.isEmpty else { return }
        do {
            for f in features { context.insert(f) }
            try context.save()
        } catch {
            context.rollback()
            for f in features {
                do {
                    context.insert(f)
                    try context.save()
                } catch {
                    context.rollback()
                }
            }
        }
    }

    @MainActor
    func upsertArtists(_ artists: [CachedArtist]) throws {
        guard !artists.isEmpty else { return }
        do {
            for a in artists { context.insert(a) }
            try context.save()
        } catch {
            context.rollback()
            for a in artists {
                do {
                    context.insert(a)
                    try context.save()
                } catch {
                    context.rollback()
                }
            }
        }
    }

    // MARK: - Fetch
    @MainActor
    func fetchAllTracks() throws -> [CachedTrack] {
        try context.fetch(FetchDescriptor<CachedTrack>())
    }

    @MainActor
    func fetchAudioFeatures() throws -> [AudioFeature] {
        try context.fetch(FetchDescriptor<AudioFeature>())
    }

    @MainActor
    func fetchArtists() throws -> [CachedArtist] {
        try context.fetch(FetchDescriptor<CachedArtist>())
    }

    // MARK: - Queries
    @MainActor
    func track(byId id: String) throws -> CachedTrack? {
        try context.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { $0.id == id })).first
    }

    @MainActor
    func audioFeature(forTrackId id: String) throws -> AudioFeature? {
        try context.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { $0.trackId == id })).first
    }

    @MainActor
    func artist(byId id: String) throws -> CachedArtist? {
        try context.fetch(FetchDescriptor<CachedArtist>(predicate: #Predicate { $0.id == id })).first
    }
    @MainActor
    func existingTrackIdsSet() throws -> Set<String> {
        let all = try context.fetch(FetchDescriptor<CachedTrack>())
        return Set(all.map { $0.id })
    }
}


