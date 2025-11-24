//
//  PlaylistsRepository.swift
//  RunClub
//
//  Repository for managing playlists cache in the Playlists store.
//

import Foundation
import SwiftData

final class PlaylistsRepository {
    private let context: ModelContext

    init(context: ModelContext = PlaylistsDataStack.shared.context) {
        self.context = context
    }

    // MARK: - Playlists
    @MainActor
    func upsertPlaylists(_ playlists: [CachedPlaylist]) throws {
        guard !playlists.isEmpty else { return }
        let ids = playlists.map { $0.id }
        let existing = (try? context.fetch(FetchDescriptor<CachedPlaylist>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for p in playlists {
            if let e = byId[p.id] {
                e.name = p.name
                e.ownerId = p.ownerId
                e.ownerName = p.ownerName
                e.isOwner = p.isOwner
                e.isPublic = p.isPublic
                e.collaborative = p.collaborative
                e.imageURL = p.imageURL
                e.totalTracks = p.totalTracks
                e.snapshotId = p.snapshotId
                // Preserve user's existing selection; do not overwrite here
                e.lastSyncedAt = p.lastSyncedAt
                e.isSynthetic = p.isSynthetic
            } else {
                context.insert(p)
            }
        }
        try context.save()
    }

    @MainActor
    func setSelection(playlistId: String, selected: Bool) throws {
        let fetch = FetchDescriptor<CachedPlaylist>(predicate: #Predicate { $0.id == playlistId })
        if let p = try context.fetch(fetch).first {
            p.selectedForSync = selected
            try context.save()
        }
    }

    // MARK: - Tracks / Artists / Features (shared models, isolated store)
    @MainActor
    func upsertTracks(_ tracks: [CachedTrack]) throws {
        guard !tracks.isEmpty else { return }
        let ids = tracks.map { $0.id }
        let existing = (try? context.fetch(FetchDescriptor<CachedTrack>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for t in tracks {
            if let e = byId[t.id] {
                e.name = t.name
                e.artistId = t.artistId
                e.artistName = t.artistName
                e.durationMs = t.durationMs
                e.albumName = t.albumName
                e.albumReleaseYear = t.albumReleaseYear
                e.popularity = t.popularity
                e.explicit = t.explicit
                e.addedAt = t.addedAt
                e.isPlayable = t.isPlayable
            } else {
                context.insert(t)
            }
        }
        try context.save()
    }

    @MainActor
    func upsertArtists(_ artists: [CachedArtist]) throws {
        guard !artists.isEmpty else { return }
        let ids = artists.map { $0.id }
        let existing = (try? context.fetch(FetchDescriptor<CachedArtist>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for a in artists {
            if let e = byId[a.id] {
                e.name = a.name
                e.genres = a.genres
                e.popularity = a.popularity
            } else {
                context.insert(a)
            }
        }
        try context.save()
    }

    @MainActor
    func upsertAudioFeatures(_ features: [AudioFeature]) throws {
        guard !features.isEmpty else { return }
        let ids = features.map { $0.trackId }
        let existing = (try? context.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { ids.contains($0.trackId) }))) ?? []
        let byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.trackId, $0) })
        for f in features {
            if let e = byId[f.trackId] {
                e.tempo = f.tempo
                e.energy = f.energy
                e.danceability = f.danceability
                e.valence = f.valence
                e.loudness = f.loudness
                e.key = f.key
                e.mode = f.mode
                e.timeSignature = f.timeSignature
            } else {
                context.insert(f)
            }
        }
        try context.save()
    }

    // MARK: - Playlist Memberships
    @MainActor
    func upsertMemberships(playlistId: String, items: [(trackId: String, addedAt: Date?)]) throws {
        guard !items.isEmpty else { return }
        // Fetch existing rows for this playlist to avoid duplicates
        let existing = (try? context.fetch(FetchDescriptor<PlaylistMembership>(predicate: #Predicate { $0.playlistId == playlistId }))) ?? []
        let existingIds = Set(existing.map { $0.trackId })
        for item in items {
            if existingIds.contains(item.trackId) {
                if let row = existing.first(where: { $0.trackId == item.trackId }) {
                    row.addedAt = item.addedAt
                }
            } else {
                context.insert(PlaylistMembership(playlistId: playlistId, trackId: item.trackId, addedAt: item.addedAt))
            }
        }
        try context.save()
    }
}


