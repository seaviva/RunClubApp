//
//  FeaturesIngestor.swift
//  RunClub
//
//  Batch-enrich AudioFeature for track IDs with concurrency and chunked saves.
//

import Foundation
import SwiftData

actor FeaturesIngestor {
    private let modelContext: ModelContext
    private let rb: ReccoBeatsService
    private let cache: ReccoIdCache
    private weak var progress: CrawlProgressStore?

    private var pendingIds: Set<String> = []

    init(modelContext: ModelContext,
         recco: ReccoBeatsService = ReccoBeatsService(),
         cache: ReccoIdCache = ReccoIdCache(),
         progress: CrawlProgressStore? = nil) {
        self.modelContext = modelContext
        self.rb = recco
        self.cache = cache
        self.progress = progress
    }

    func enqueue(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pendingIds.formUnion(ids)
    }

    func flushAndWait() async {
        guard !pendingIds.isEmpty else { return }
        // Snapshot actor state before switching executors
        let idsSnapshot = Array(pendingIds)
        let ctx = self.modelContext
        let source = self.progress?.debugName ?? "UNKNOWN"
        print("[FEATURES] flush begin — ids=\(idsSnapshot.count) source=\(source)")
        // Filter out IDs that already have features
        let toProcess: [String] = await MainActor.run {
            let existing = (try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { idsSnapshot.contains($0.trackId) }))) ?? []
            let have = Set(existing.map { $0.trackId })
            return Array(Set(idsSnapshot).subtracting(have))
        }
        pendingIds.removeAll()
        guard !toProcess.isEmpty else { return }

        // Resolve with cache first
        var spToRecco: [String: String] = [:]
        var unresolved: [String] = []
        for id in toProcess {
            if let rid = cache.get(id) { spToRecco[id] = rid } else { unresolved.append(id) }
        }
        if !unresolved.isEmpty {
            // Resolve in batches using API-supported patterns
            // The client internally splits to 40-id chunks; we call it repeatedly over a larger slice.
            let batchSize = Config.reccoResolveBatchSize
            var idx = 0
            while idx < unresolved.count {
                let end = min(idx + batchSize, unresolved.count)
                let chunk = Array(unresolved[idx..<end])
                let map = await rb.resolveReccoIds(spotifyIds: chunk)
                if !map.isEmpty {
                    spToRecco.merge(map) { _, new in new }
                    cache.merge(map)
                }
                idx = end
            }
        }
        guard !spToRecco.isEmpty else { return }

        // Fetch features with unified concurrency
        let maxConc = Config.featuresMaxConcurrency
        let featMap = await rb.getAudioFeaturesBulkMapped(spToRecco: spToRecco, maxConcurrency: maxConc)
        guard !featMap.isEmpty else { return }

        // Chunked save (e.g., 250 per transaction)
        let chunk = 250
        let pairs = Array(featMap)
        var i = 0
        let progressRef = self.progress
        while i < pairs.count {
            let end = min(i + chunk, pairs.count)
            let slice = Array(pairs[i..<end])
            await MainActor.run { [slice] in
                let keys = slice.map { $0.0 }
                let existing = (try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { keys.contains($0.trackId) }))) ?? []
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.trackId, $0) })
                for (sid, f) in slice {
                    if let af = existingById[sid] {
                        af.tempo = f.tempo
                        af.energy = f.energy
                        af.danceability = f.danceability
                        af.valence = f.valence
                        af.loudness = f.loudness
                        af.key = f.key
                        af.mode = f.mode
                        af.timeSignature = f.timeSignature
                    } else {
                        ctx.insert(AudioFeature(trackId: sid,
                                                tempo: f.tempo,
                                                energy: f.energy,
                                                danceability: f.danceability,
                                                valence: f.valence,
                                                loudness: f.loudness,
                                                key: f.key,
                                                mode: f.mode,
                                                timeSignature: f.timeSignature))
                    }
                }
                try? ctx.save()
                progressRef?.featuresDone += slice.count
            }
            i = end
        }
        print("[FEATURES] flush end — wrote=\(pairs.count) source=\(source)")
    }
}


