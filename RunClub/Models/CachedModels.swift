//
//  CachedModels.swift
//  RunClub
//
//  Created by AI Assistant on 8/25/25.
//

import Foundation
import SwiftData

@Model
final class CachedTrack {
    @Attribute(.unique) var id: String // Spotify track ID
    var name: String
    var artistId: String
    var artistName: String
    var durationMs: Int
    var albumName: String
    var albumReleaseYear: Int?
    var popularity: Int?
    var explicit: Bool
    var addedAt: Date
    var isPlayable: Bool = true // market-playable cached flag (default for migration)

    init(id: String,
         name: String,
         artistId: String,
         artistName: String,
         durationMs: Int,
         albumName: String,
         albumReleaseYear: Int?,
         popularity: Int?,
         explicit: Bool,
         addedAt: Date,
         isPlayable: Bool = true) {
        self.id = id
        self.name = name
        self.artistId = artistId
        self.artistName = artistName
        self.durationMs = durationMs
        self.albumName = albumName
        self.albumReleaseYear = albumReleaseYear
        self.popularity = popularity
        self.explicit = explicit
        self.addedAt = addedAt
        self.isPlayable = isPlayable
    }
}

@Model
final class AudioFeature {
    @Attribute(.unique) var trackId: String // Spotify track ID (FK)
    var tempo: Double?
    var energy: Double?
    var danceability: Double?
    var valence: Double?
    var loudness: Double?
    var key: Int?
    var mode: Int?
    var timeSignature: Int?

    init(trackId: String,
         tempo: Double?,
         energy: Double?,
         danceability: Double?,
         valence: Double?,
         loudness: Double?,
         key: Int?,
         mode: Int?,
         timeSignature: Int?) {
        self.trackId = trackId
        self.tempo = tempo
        self.energy = energy
        self.danceability = danceability
        self.valence = valence
        self.loudness = loudness
        self.key = key
        self.mode = mode
        self.timeSignature = timeSignature
    }
}

@Model
final class CachedArtist {
    @Attribute(.unique) var id: String // Spotify artist ID
    var name: String
    var genres: [String]
    var popularity: Int?

    init(id: String, name: String, genres: [String], popularity: Int?) {
        self.id = id
        self.name = name
        self.genres = genres
        self.popularity = popularity
    }
}

enum CrawlStatus: String, Codable {
    case running
    case idle
    case failed
}

@Model
final class CrawlState {
    var statusRaw: String
    var nextOffset: Int?
    var totalTracks: Int
    var totalFeatures: Int
    var totalArtists: Int
    var lastError: String?
    var lastCompletedAt: Date?

    var status: CrawlStatus {
        get { CrawlStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    init(status: CrawlStatus = .idle,
         nextOffset: Int? = nil,
         totalTracks: Int = 0,
         totalFeatures: Int = 0,
         totalArtists: Int = 0,
         lastError: String? = nil,
         lastCompletedAt: Date? = nil) {
        self.statusRaw = status.rawValue
        self.nextOffset = nextOffset
        self.totalTracks = totalTracks
        self.totalFeatures = totalFeatures
        self.totalArtists = totalArtists
        self.lastError = lastError
        self.lastCompletedAt = lastCompletedAt
    }
}

// MARK: - Run generation support

enum PaceBucket: String, Codable, CaseIterable {
    case A, B, C, D
}

@Model
final class UserRunPrefs {
    var paceBucketRaw: String
    var customCadenceSPM: Double?

    var paceBucket: PaceBucket {
        get { PaceBucket(rawValue: paceBucketRaw) ?? .B }
        set { paceBucketRaw = newValue.rawValue }
    }

    init(paceBucket: PaceBucket = .B, customCadenceSPM: Double? = nil) {
        self.paceBucketRaw = paceBucket.rawValue
        self.customCadenceSPM = customCadenceSPM
    }
}

@Model
final class TrackUsage {
    @Attribute(.unique) var trackId: String
    var lastUsedAt: Date?
    var usedCount: Int

    init(trackId: String, lastUsedAt: Date? = nil, usedCount: Int = 0) {
        self.trackId = trackId
        self.lastUsedAt = lastUsedAt
        self.usedCount = usedCount
    }
}


