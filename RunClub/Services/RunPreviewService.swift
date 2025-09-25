//
//  RunPreviewService.swift
//  RunClub
//

import Foundation
import SwiftData

@MainActor
final class RunPreviewService {
    private let modelContext: ModelContext
    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func buildPreview(template: RunTemplateType,
                      duration: DurationCategory,
                      genres: [Genre],
                      decades: [Decade],
                      customMinutes: Int? = nil) async throws -> PreviewRun {
        let generator = LocalGenerator(modelContext: modelContext)
        let spotify = SpotifyService()
        let token = await AuthService.sharedToken() ?? ""
        spotify.accessTokenProvider = { token }
        let dry = try await generator.generateDryRun(template: template,
                                                     durationCategory: duration,
                                                     genres: genres,
                                                     decades: decades,
                                                     spotify: spotify,
                                                     customMinutes: customMinutes)
        // Map trackIds -> CachedTrack/CachedArtist
        let idsSet = Set(dry.trackIds)
        let tracks: [CachedTrack] = (try? modelContext.fetch(FetchDescriptor<CachedTrack>()))?.filter { idsSet.contains($0.id) } ?? []
        let byId = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var previewTracks: [PreviewTrack] = []
        for (idx, tid) in dry.trackIds.enumerated() {
            let eff = idx < dry.efforts.count ? dry.efforts[idx] : .easy
            if let ct = byId[tid] {
                previewTracks.append(PreviewTrack(id: ct.id,
                                                  title: ct.name,
                                                  artist: ct.artistName,
                                                  albumArtURL: nil,
                                                  durationMs: ct.durationMs,
                                                  effort: eff))
            } else {
                previewTracks.append(PreviewTrack(id: tid,
                                                  title: "Track",
                                                  artist: "",
                                                  albumArtURL: nil,
                                                  durationMs: 0,
                                                  effort: eff))
            }
        }
        return PreviewRun(template: template, duration: duration, customMinutes: customMinutes, tracks: previewTracks)
    }

    func replaceTrack(preview: PreviewRun, at index: Int, genres: [Genre], decades: [Decade]) async throws -> PreviewRun {
        guard index >= 0 && index < preview.tracks.count else { return preview }
        let slotEffort = preview.tracks[index].effort
        // Re-run dry run and pick a different track with the same effort tier
        let generator = LocalGenerator(modelContext: modelContext)
        let spotify = SpotifyService()
        let token = await AuthService.sharedToken() ?? ""
        spotify.accessTokenProvider = { token }
        let dry = try await generator.generateDryRun(template: preview.template,
                                                     durationCategory: preview.duration,
                                                     genres: genres,
                                                     decades: decades,
                                                     spotify: spotify,
                                                     customMinutes: preview.customMinutes)
        let exclude = Set(preview.tracks.map { $0.id })
        // Find candidate with same effort not in exclude
        var replacementId: String?
        for (idx2, tid) in dry.trackIds.enumerated() where idx2 < dry.efforts.count {
            if dry.efforts[idx2] == slotEffort && !exclude.contains(tid) { replacementId = tid; break }
        }
        guard let rid = replacementId else { return preview }
        // Map replacementId to CachedTrack
        if let ct = try? modelContext.fetch(FetchDescriptor<CachedTrack>()).first(where: { $0.id == rid }) {
            var next = preview
            next.tracks[index] = PreviewTrack(id: ct.id,
                                              title: ct.name,
                                              artist: ct.artistName,
                                              albumArtURL: nil,
                                              durationMs: ct.durationMs,
                                              effort: slotEffort)
            return next
        }
        return preview
    }
}


