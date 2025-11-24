//
//  ArtistsIngestor.swift
//  RunClub
//
//  Batch-enrich artist details with chunked saves.
//

import Foundation
import SwiftData

actor ArtistsIngestor {
    private let modelContext: ModelContext
    private let spotify: SpotifyService
    private weak var progress: CrawlProgressStore?

    private var pendingIds: Set<String> = []

    init(modelContext: ModelContext, spotify: SpotifyService, progress: CrawlProgressStore? = nil) {
        self.modelContext = modelContext
        self.spotify = spotify
        self.progress = progress
    }

    func enqueue(_ artistIds: [String]) {
        guard !artistIds.isEmpty else { return }
        pendingIds.formUnion(artistIds)
    }

    func flushAndWait() async {
        guard !pendingIds.isEmpty else { return }
        // Snapshot actor state before switching executors
        let idsSnapshot = Array(pendingIds)
        let ctx = self.modelContext
        // Filter out IDs already in DB (perform fetch on main actor with captured context and ids)
        let toProcess: [String] = await MainActor.run {
            let existing = (try? ctx.fetch(FetchDescriptor<CachedArtist>(predicate: #Predicate { idsSnapshot.contains($0.id) }))) ?? []
            let have = Set(existing.map { $0.id })
            return Array(Set(idsSnapshot).subtracting(have))
        }
        pendingIds.removeAll()
        guard !toProcess.isEmpty else { return }

        // Spotify allows 50 ids per request; we'll fetch sequentially but it's already chunked there
        do {
            let artists = try await spotify.getArtists(ids: toProcess)
            guard !artists.isEmpty else { return }
            let progressRef = self.progress
            await MainActor.run { [artists] in
                let models = artists.values.map { a in
                    CachedArtist(id: a.id, name: a.name, genres: a.genres, popularity: a.popularity)
                }
                for m in models { ctx.insert(m) }
                try? ctx.save()
                progressRef?.artistsDone += models.count
            }
        } catch {
            // swallow; non-fatal
        }
    }
}


