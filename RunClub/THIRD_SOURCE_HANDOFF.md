### Third Song Source — External Project Handoff (Plug‑and‑Play SwiftData Store)

Purpose: Produce a prebuilt SwiftData store that RunClub loads as‑is. No ingestion/conversion in the app. You deliver a ready-to-use store; we drop it in and launch.


## What to Deliver

- A zipped “store triplet” for a dedicated third-source SwiftData container:
  - thirdsource.store
  - thirdsource.store-wal
  - thirdsource.store-shm

- These files must contain rows for the following entities (exact field names/types required):
  - CachedTrack — all third-source tracks
  - AudioFeature — features for those tracks
  - CachedArtist — artists referenced by those tracks
  - CrawlState — single row; status idle; counts filled
  - CachedPlaylist — present in schema (0 rows OK)
  - PlaylistMembership — present in schema (0 rows OK)

- Container identity (must match):
  - ModelConfiguration name: "thirdsource"
  - Schema: CachedTrack, AudioFeature, CachedArtist, CrawlState
  - Storage: SQLite (default), producing the triplet above


## Schema (Exact Field Names/Types)

Use these entities and properties verbatim. Names/types must match exactly or the app will consider the store incompatible.

CachedTrack (one row per track)
- id: String (Spotify track ID, unique)
- name: String
- artistId: String
- artistName: String
- durationMs: Int
- albumName: String
- albumReleaseYear: Int? (nullable)
- popularity: Int? (nullable)
- explicit: Bool
- addedAt: Date (UTC)
- isPlayable: Bool (true for included tracks)

AudioFeature (one row per track)
- trackId: String (FK to CachedTrack.id, unique)
- tempo: Double?
- energy: Double?
- danceability: Double?
- valence: Double?
- loudness: Double?
- key: Int?
- mode: Int?
- timeSignature: Int?

CachedArtist (artists referenced by tracks)
- id: String (Spotify artist ID, unique)
- name: String
- genres: [String] (normalized: lowercase, hyphen→space, “&”→“and”)
- popularity: Int?

CrawlState (single row)
- statusRaw: String (“idle”)
- nextOffset: Int? (nil)
- totalTracks: Int (row count of CachedTrack)
- totalFeatures: Int (row count of AudioFeature)
- totalArtists: Int (row count of CachedArtist)
- lastError: String? (nil)
- lastCompletedAt: Date? (now)
- crawlStartAt: Date? (now or nil)

CachedPlaylist (present in schema; 0 rows OK)
- id: String (unique)
- name: String
- ownerId: String
- ownerName: String
- isOwner: Bool
- isPublic: Bool
- collaborative: Bool
- imageURL: String?
- totalTracks: Int
- snapshotId: String?
- selectedForSync: Bool
- lastSyncedAt: Date?
- isSynthetic: Bool

PlaylistMembership (present in schema; 0 rows OK)
- id: String (unique composite like “playlistId|trackId”)
- playlistId: String
- trackId: String
- addedAt: Date?


## Exact Types (from the app — references)

CachedTrack, AudioFeature, CachedArtist, CrawlState are defined here:
```1:172:RunClub/Core/Models/CachedModels.swift
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
    // ...
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
    // ...
}

@Model
final class CachedArtist {
    @Attribute(.unique) var id: String // Spotify artist ID
    var name: String
    var genres: [String]
    var popularity: Int?
    // ...
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
    var crawlStartAt: Date?
    // ...
}
```

Container name and schema:
```1:32:RunClub/Data/ThirdSource/ThirdSourceDataStack.swift
let schema = Schema([
    CachedTrack.self,
    AudioFeature.self,
    CachedArtist.self,
    CrawlState.self
])
let configuration = ModelConfiguration("thirdsource", schema: schema, isStoredInMemoryOnly: false)
```


## Content Rules

- Every CachedTrack has a corresponding AudioFeature row (generator relies on features).
- Every CachedTrack.artistId exists in CachedArtist.
- Track length ≤ 6 minutes; prefer 2–5 minutes.
- isPlayable = true for included tracks.
- No duplicate track ids.
- Valid UTC dates for addedAt and CrawlState timestamps.
- Genres normalized (lowercase; hyphen→space; “&”→“and”).


## Packaging and Placement

- EITHER: Bundle-based install (easiest for you; app auto-seeds on first run and can auto-update when version changes)
  - Add the three files directly to the app bundle resources (e.g., place them under `RunClub/RunClub/Resources/ThirdSource/` in the Xcode project so they are copied into the app bundle):
    - thirdsource.store
    - thirdsource.store-wal
    - thirdsource.store-shm
  - Optional (recommended): include `RunClub/RunClub/Resources/ThirdSource/version.json` with shape `{ "version": "YYYY-MM-DD" }` or a semver string. The app will auto-replace the on-device store on next launch if the bundled version is newer. Back-compat: if you only provide `playlists.store*` file names, the app will copy them into `thirdsource.store*` destinations.
  - On first launch, the app will automatically copy these into Application Support if the Playlists store does not exist yet. Subsequent launches will not overwrite an existing store.

- OR: Ship as ThirdSourceStore_YYYYMMDD.zip with the three files at the root for manual install:
  - thirdsource.store
  - thirdsource.store-wal
  - thirdsource.store-shm

- Manual Installation (developer):
  - Quit RunClub.
  - Replace the Playlists store triplet under the app’s “Application Support” path for the simulator/device.
  - Relaunch RunClub.

- Future updates: repeat the replacement with a new triplet; the app will read it on launch.

Notes:
- The third source is now independent of the Playlists store. You can freely use “Sync Selected” for Playlists; it will not affect the third source.


## Minimal Writer (Example)

If you generate the store programmatically, construct the container with the same schema and configuration name, then insert rows and save:

```swift
import Foundation
import SwiftData

// Define models EXACTLY as in the app (names/fields/types). Then:
@main
struct SeedPlaylistsStore {
    static func main() throws {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self,
            CachedPlaylist.self,
            PlaylistMembership.self
        ])
        let config = ModelConfiguration("playlists", schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        // Insert artists, then tracks, then features
        // Example:
        let artist = CachedArtist(id: "0C0XlULifJtAgn6ZNCW2eu", name: "The Killers", genres: ["alternative rock", "indie rock"], popularity: 82)
        context.insert(artist)

        let t = CachedTrack(id: "3n3Ppam7vgaVa1iaRUc9Lp",
                            name: "Mr. Brightside",
                            artistId: artist.id,
                            artistName: artist.name,
                            durationMs: 222973,
                            albumName: "Hot Fuss",
                            albumReleaseYear: 2004,
                            popularity: 89,
                            explicit: false,
                            addedAt: Date(),
                            isPlayable: true)
        context.insert(t)

        let f = AudioFeature(trackId: t.id,
                             tempo: 148.07,
                             energy: 0.891,
                             danceability: 0.653,
                             valence: 0.447,
                             loudness: -4.89,
                             key: 1, mode: 1, timeSignature: 4)
        context.insert(f)

        let cs = CrawlState(status: .idle,
                            nextOffset: nil,
                            totalTracks: 1,
                            totalFeatures: 1,
                            totalArtists: 1,
                            lastError: nil,
                            lastCompletedAt: Date(),
                            crawlStartAt: Date())
        context.insert(cs)

        try context.save()
        // Copy the resulting playlists.store(+wal,+shm) as your deliverable.
    }
}
```


## Minimal Validator (Example)

Use this to open an existing triplet and verify counts/types using the same schema and "playlists" configuration name:

```swift
import Foundation
import SwiftData

@main
struct ValidatePlaylistsStore {
    static func main() throws {
        let schema = Schema([
            CachedTrack.self,
            AudioFeature.self,
            CachedArtist.self,
            CrawlState.self,
            CachedPlaylist.self,
            PlaylistMembership.self
        ])
        let config = ModelConfiguration("playlists", schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let tracks = try context.fetch(FetchDescriptor<CachedTrack>())
        let feats = try context.fetch(FetchDescriptor<AudioFeature>())
        let artists = try context.fetch(FetchDescriptor<CachedArtist>())
        let cs = try context.fetch(FetchDescriptor<CrawlState>()).first

        print("Tracks:", tracks.count, "Features:", feats.count, "Artists:", artists.count)
        print("CrawlState.statusRaw:", cs?.statusRaw ?? "nil")

        // Basic checks
        precondition(!tracks.isEmpty, "No tracks found")
        for t in tracks {
            precondition(t.durationMs <= 360000, "Track too long: \\(t.id)")
            precondition(feats.contains(where: { $0.trackId == t.id }), "Missing features for \\(t.id)")
            precondition(artists.contains(where: { $0.id == t.artistId }), "Missing artist for \\(t.id)")
        }
        print("Validation OK")
    }
}
```


## Common Pitfalls

- Using a different ModelConfiguration name (must be "playlists").
- Changing any field name/type — this makes the store incompatible.
- Omitting AudioFeature rows — the generator filters out tracks without features.
- Running “Sync selected playlists” in-app — that clears the Playlists store content.


## Update Process (Future Drops)

1) Produce a new triplet with the same configuration and schema.
2) Zip and ship to the RunClub team.
3) Developer replaces the existing triplet in “Application Support” and relaunches the app.

That’s it — no app code or pipelines required.


