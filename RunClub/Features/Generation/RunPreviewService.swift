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
                      runMinutes: Int,
                      genres: [Genre],
                      decades: [Decade]) async throws -> PreviewRun {
        let generator = LocalGenerator(modelContext: modelContext)
        let spotify = SpotifyService()
        let token = await AuthService.sharedToken() ?? ""
        spotify.accessTokenProvider = { token }
        let dry = try await generator.generateDryRun(template: template,
                                                     runMinutes: runMinutes,
                                                     genres: genres,
                                                     decades: decades,
                                                     spotify: spotify)
        // Map trackIds -> CachedTrack across all contexts (likes, playlists, third)
        let idsSet = Set(dry.trackIds)
        var byId: [String: CachedTrack] = [:]
        // 1) Third-source context (lowest precedence)
        if let ts = try? ThirdSourceDataStack.shared.context.fetch(FetchDescriptor<CachedTrack>()) {
            for t in ts where idsSet.contains(t.id) { byId[t.id] = t }
        }
        // 2) Playlists context (overlays third)
        if let pl = try? PlaylistsDataStack.shared.context.fetch(FetchDescriptor<CachedTrack>()) {
            for t in pl where idsSet.contains(t.id) { byId[t.id] = t }
        }
        // 3) Primary model context (overlays both)
        if let prim = try? modelContext.fetch(FetchDescriptor<CachedTrack>()) {
            for t in prim where idsSet.contains(t.id) { byId[t.id] = t }
        }
        
        // Fetch album art URLs from Spotify
        let albumArtURLs = (try? await spotify.getAlbumArtURLs(for: dry.trackIds)) ?? [:]
        
        var previewTracks: [PreviewTrack] = []
        for (idx, tid) in dry.trackIds.enumerated() {
            let eff = idx < dry.efforts.count ? dry.efforts[idx] : .easy
            let artURL = albumArtURLs[tid]
            if let ct = byId[tid] {
                previewTracks.append(PreviewTrack(id: ct.id,
                                                  title: ct.name,
                                                  artist: ct.artistName,
                                                  albumArtURL: artURL,
                                                  durationMs: ct.durationMs,
                                                  effort: eff))
            } else {
                previewTracks.append(PreviewTrack(id: tid,
                                                  title: "Track",
                                                  artist: "",
                                                  albumArtURL: artURL,
                                                  durationMs: 0,
                                                  effort: eff))
            }
        }
        return PreviewRun(template: template, runMinutes: runMinutes, tracks: previewTracks)
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
                                                     runMinutes: preview.runMinutes,
                                                     genres: genres,
                                                     decades: decades,
                                                     spotify: spotify)
        let exclude = Set(preview.tracks.map { $0.id })
        // Find candidate with same effort not in exclude
        var replacementId: String?
        for (idx2, tid) in dry.trackIds.enumerated() where idx2 < dry.efforts.count {
            if dry.efforts[idx2] == slotEffort && !exclude.contains(tid) { replacementId = tid; break }
        }
        guard let rid = replacementId else { return preview }
        
        // Fetch album art for replacement track
        let artURLs = (try? await spotify.getAlbumArtURLs(for: [rid])) ?? [:]
        let artURL = artURLs[rid]
        
        // Map replacementId to CachedTrack (check all contexts)
        var ct: CachedTrack?
        if let t = try? modelContext.fetch(FetchDescriptor<CachedTrack>()).first(where: { $0.id == rid }) {
            ct = t
        } else if let t = try? PlaylistsDataStack.shared.context.fetch(FetchDescriptor<CachedTrack>()).first(where: { $0.id == rid }) {
            ct = t
        } else if let t = try? ThirdSourceDataStack.shared.context.fetch(FetchDescriptor<CachedTrack>()).first(where: { $0.id == rid }) {
            ct = t
        }
        
        if let ct {
            var next = preview
            next.tracks[index] = PreviewTrack(id: ct.id,
                                              title: ct.name,
                                              artist: ct.artistName,
                                              albumArtURL: artURL,
                                              durationMs: ct.durationMs,
                                              effort: slotEffort)
            return next
        }
        return preview
    }
}


