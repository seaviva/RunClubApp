//
//  PreviewRun.swift
//  RunClub
//

import Foundation

struct PreviewTrack: Identifiable, Hashable {
    let id: String        // Spotify track ID
    let title: String
    let artist: String
    let albumArtURL: URL?
    let durationMs: Int
    let effort: LocalGenerator.EffortTier
}

struct PreviewRun: Identifiable, Hashable {
    let id = UUID()
    let template: RunTemplateType
    let duration: DurationCategory
    let customMinutes: Int?
    var tracks: [PreviewTrack]
}


