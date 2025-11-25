//
//  FeaturesIngestor.swift
//  RunClub
//
//  Batch-enrich AudioFeature for track IDs using optimized batch endpoint.
//  Uses wave-based concurrency to maximize throughput while avoiding rate limits.
//

import Foundation
import SwiftData

actor FeaturesIngestor {
    private let modelContext: ModelContext
    private let rb: ReccoBeatsService
    private weak var progress: CrawlProgressStore?

    private var pendingIds: Set<String> = []

    init(modelContext: ModelContext,
         recco: ReccoBeatsService = ReccoBeatsService(),
         cache: ReccoIdCache = ReccoIdCache(),  // Kept for API compatibility, no longer used
         progress: CrawlProgressStore? = nil) {
        self.modelContext = modelContext
        self.rb = recco
        self.progress = progress
    }

    func enqueue(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        pendingIds.formUnion(ids)
    }
    
    /// Process a batch of IDs immediately without waiting for flushAndWait.
    /// This enables pipelining - enriching while still fetching more tracks.
    func enrichBatchNow(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let ctx = self.modelContext
        
        // Filter out IDs that already have features
        let toProcess: [String] = await MainActor.run {
            let existing = (try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { ids.contains($0.trackId) }))) ?? []
            let have = Set(existing.map { $0.trackId })
            return Array(Set(ids).subtracting(have))
        }
        guard !toProcess.isEmpty else { return }
        
        // Fetch features using optimized batch endpoint (accepts Spotify IDs directly)
        let featMap = await rb.getAudioFeaturesBatchDirect(
            spotifyIds: toProcess,
            batchSize: Config.reccoBatchSize,
            waveConcurrency: Config.reccoWaveConcurrency,
            waveDelayMs: Config.reccoWaveDelayMs
        )
        guard !featMap.isEmpty else { return }
        
        // Save to database
        await saveFeatures(featMap)
    }

    func flushAndWait() async {
        guard !pendingIds.isEmpty else { return }
        
        // Snapshot and clear pending IDs
        let idsSnapshot = Array(pendingIds)
        pendingIds.removeAll()
        
        let ctx = self.modelContext
        let source = self.progress?.debugName ?? "UNKNOWN"
        let startTime = Date()
        print("[FEATURES] flush begin — ids=\(idsSnapshot.count) source=\(source)")
        
        // Filter out IDs that already have features
        let toProcess: [String] = await MainActor.run {
            let existing = (try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { idsSnapshot.contains($0.trackId) }))) ?? []
            let have = Set(existing.map { $0.trackId })
            return Array(Set(idsSnapshot).subtracting(have))
        }
        guard !toProcess.isEmpty else {
            print("[FEATURES] flush skip — all \(idsSnapshot.count) already cached")
            return
        }
        
        print("[FEATURES] fetching features for \(toProcess.count) tracks (skipped \(idsSnapshot.count - toProcess.count) cached)")
        
        // Fetch features using optimized batch endpoint
        // This uses wave-based concurrency and accepts Spotify IDs directly (no ID resolution needed!)
        let featMap = await rb.getAudioFeaturesBatchDirect(
            spotifyIds: toProcess,
            batchSize: Config.reccoBatchSize,
            waveConcurrency: Config.reccoWaveConcurrency,
            waveDelayMs: Config.reccoWaveDelayMs
        )
        
        guard !featMap.isEmpty else {
            print("[FEATURES] flush end — no features returned")
            return
        }
        
        // Save to database
        await saveFeatures(featMap)
        
        let elapsed = Date().timeIntervalSince(startTime)
        let rate = Double(featMap.count) / elapsed
        print("[FEATURES] flush end — wrote=\(featMap.count) in \(String(format: "%.1f", elapsed))s (\(String(format: "%.0f", rate)) tracks/sec) source=\(source)")
    }
    
    /// Save features to the database in chunks
    private func saveFeatures(_ featMap: [String: ReccoBeatsAudioFeatures]) async {
        let ctx = self.modelContext
        let progressRef = self.progress
        
        // Chunked save (250 per transaction to avoid memory pressure)
        let chunkSize = 250
        let pairs = Array(featMap)
        var i = 0
        
        while i < pairs.count {
            let end = min(i + chunkSize, pairs.count)
            let slice = Array(pairs[i..<end])
            
            await MainActor.run { [slice] in
                let keys = slice.map { $0.0 }
                let existing = (try? ctx.fetch(FetchDescriptor<AudioFeature>(predicate: #Predicate { keys.contains($0.trackId) }))) ?? []
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.trackId, $0) })
                
                for (spotifyId, features) in slice {
                    if let existing = existingById[spotifyId] {
                        // Update existing record
                        existing.tempo = features.tempo
                        existing.energy = features.energy
                        existing.danceability = features.danceability
                        existing.valence = features.valence
                        existing.loudness = features.loudness
                        existing.key = features.key
                        existing.mode = features.mode
                        existing.timeSignature = features.timeSignature
                    } else {
                        // Insert new record
                        ctx.insert(AudioFeature(
                            trackId: spotifyId,
                            tempo: features.tempo,
                            energy: features.energy,
                            danceability: features.danceability,
                            valence: features.valence,
                            loudness: features.loudness,
                            key: features.key,
                            mode: features.mode,
                            timeSignature: features.timeSignature
                        ))
                    }
                }
                try? ctx.save()
                progressRef?.featuresDone += slice.count
            }
            i = end
        }
    }
}
