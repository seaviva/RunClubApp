import Foundation
import SwiftData

// =============================================================================
// MARK: - SwiftData Models (Mirroring App Models)
// =============================================================================

/// Cached track from Spotify library
@Model
final class CachedTrack {
    @Attribute(.unique) var id: String
    var name: String
    var artistId: String
    var artistName: String
    var durationMs: Int
    var albumName: String
    var albumReleaseYear: Int?
    var popularity: Int?
    var explicit: Bool
    var addedAt: Date
    var isPlayable: Bool = true

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

/// Audio features for a track
@Model
final class AudioFeature {
    @Attribute(.unique) var trackId: String
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

/// Cached artist with genres
@Model
final class CachedArtist {
    @Attribute(.unique) var id: String
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

/// Track usage for recency/lockout tracking
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

/// Crawl state (needed for schema compatibility)
@Model
final class CrawlState {
    var statusRaw: String
    var nextOffset: Int?
    var totalTracks: Int
    var totalFeatures: Int
    var totalArtists: Int
    var lastError: String?
    var lastCompletedAt: Date?
    var crawlStartAt: Date?

    init(statusRaw: String = "idle",
         nextOffset: Int? = nil,
         totalTracks: Int = 0,
         totalFeatures: Int = 0,
         totalArtists: Int = 0,
         lastError: String? = nil,
         lastCompletedAt: Date? = nil,
         crawlStartAt: Date? = nil) {
        self.statusRaw = statusRaw
        self.nextOffset = nextOffset
        self.totalTracks = totalTracks
        self.totalFeatures = totalFeatures
        self.totalArtists = totalArtists
        self.lastError = lastError
        self.lastCompletedAt = lastCompletedAt
        self.crawlStartAt = crawlStartAt
    }
}

// =============================================================================
// MARK: - Enums (Mirroring App Enums)
// =============================================================================

/// Run template types
enum RunTemplateType: String, CaseIterable, Codable {
    case light
    case tempo
    case hiit
    case intervals
    case pyramid
    case kicker
    
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .tempo: return "Tempo"
        case .hiit: return "HIIT"
        case .intervals: return "Intervals"
        case .pyramid: return "Pyramid"
        case .kicker: return "Kicker"
        }
    }
}

/// Genre categories
enum Genre: String, CaseIterable, Codable {
    case pop
    case hipHopRap
    case rockAlt
    case electronic
    case indie
    case rnb
    case country
    case latin
    case jazzBlues
    case classicalSoundtrack
    
    var displayName: String {
        switch self {
        case .pop: return "Pop"
        case .hipHopRap: return "Hip-Hop & Rap"
        case .rockAlt: return "Rock & Alt"
        case .electronic: return "Electronic"
        case .indie: return "Indie"
        case .rnb: return "R&B"
        case .country: return "Country"
        case .latin: return "Latin"
        case .jazzBlues: return "Jazz & Blues"
        case .classicalSoundtrack: return "Classical & Soundtrack"
        }
    }
    
    /// Map to umbrella ID used in genre mapping
    var umbrellaId: String {
        switch self {
        case .pop: return "Pop"
        case .hipHopRap: return "Hip-Hop & Rap"
        case .rockAlt: return "Rock & Alt"
        case .electronic: return "Electronic & Dance"
        case .indie: return "Indie & Alternative"
        case .rnb: return "R&B & Soul"
        case .country: return "Country & Folk"
        case .latin: return "Latin"
        case .jazzBlues: return "Jazz & Blues"
        case .classicalSoundtrack: return "Classical & Soundtrack"
        }
    }
}

/// Decade categories
enum Decade: String, CaseIterable, Codable {
    case seventies
    case eighties
    case nineties
    case twoThousands
    case twentyTens
    case twentyTwenties
    
    var displayName: String {
        switch self {
        case .seventies: return "70s"
        case .eighties: return "80s"
        case .nineties: return "90s"
        case .twoThousands: return "00s"
        case .twentyTens: return "10s"
        case .twentyTwenties: return "20s"
        }
    }
    
    var yearRange: (Int, Int) {
        switch self {
        case .seventies: return (1970, 1979)
        case .eighties: return (1980, 1989)
        case .nineties: return (1990, 1999)
        case .twoThousands: return (2000, 2009)
        case .twentyTens: return (2010, 2019)
        case .twentyTwenties: return (2020, 2029)
        }
    }
}

/// Effort tiers for track selection
enum EffortTier: String, Codable, CaseIterable {
    case easy
    case moderate
    case strong
    case hard
    case max
}

/// Track source
enum SourceKind: String, Codable {
    case likes
    case recs
    case third
}

// =============================================================================
// MARK: - Output Models (for JSON serialization)
// =============================================================================

/// Slot information for a single track in the playlist
struct SlotOutput: Codable {
    let index: Int
    let segment: String  // "warmup", "main", "cooldown"
    let effort: String
    let targetEffort: Double
    let trackId: String
    let artistId: String
    let artistName: String
    let trackName: String
    let tempo: Double?
    let energy: Double?
    let danceability: Double?
    let durationSeconds: Int
    let tempoFit: Double
    let effortIndex: Double
    let slotFit: Double
    let genreAffinity: Double
    let isRediscovery: Bool
    let usedNeighbor: Bool
    let brokeLockout: Bool
    let source: String
    let genres: [String]
}

/// Complete generation result for JSON output
struct GenerationOutput: Codable {
    // Input parameters
    let template: String
    let runMinutes: Int
    let genres: [String]
    let decades: [String]
    
    // Track lists
    let trackIds: [String]
    let artistIds: [String]
    let efforts: [String]
    let sources: [String]
    
    // Duration info
    let totalSeconds: Int
    let minSeconds: Int
    let maxSeconds: Int
    
    // Segment durations
    let warmupSeconds: Int
    let mainSeconds: Int
    let cooldownSeconds: Int
    
    // Segment targets
    let warmupTarget: Int
    let mainTarget: Int
    let cooldownTarget: Int
    
    // Playability stats
    let preflightUnplayable: Int
    let swapped: Int
    let removed: Int
    let market: String
    
    // Slot details
    let slots: [SlotOutput]
    
    // Aggregate metrics
    let avgTempoFit: Double
    let avgSlotFit: Double
    let avgGenreAffinity: Double
    let rediscoveryPct: Double
    let uniqueArtists: Int
    let neighborRelaxSlots: Int
    let lockoutBreaks: Int
    
    // Source distribution
    let sourceLikes: Int
    let sourcePlaylists: Int
    let sourceThird: Int
    
    // Raw debug lines
    let debugLines: [String]
    
    // Timestamp
    let generatedAt: String
}

/// Data statistics output
struct DataStatsOutput: Codable {
    let likesTrackCount: Int
    let likesFeaturesCount: Int
    let likesArtistCount: Int
    let playlistsTrackCount: Int
    let playlistsFeaturesCount: Int
    let playlistsArtistCount: Int
    let thirdSourceTrackCount: Int
    let thirdSourceFeaturesCount: Int
    let thirdSourceArtistCount: Int
    let totalTracks: Int
    let tracksWithFeatures: Int
}
