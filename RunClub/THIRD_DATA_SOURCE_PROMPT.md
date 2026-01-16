### Third Song Data Source Ingestion Project — AI Build Prompt

You are an expert AI software engineer tasked with building a separate ingestion project that creates a large, static third song data source for RunClub. This source backfills thin filters (e.g., “70s country”) and injects variety so users always get some fresh tracks in generated runs. The output is a set of static files that will be copied into the RunClub app repo and imported locally as a third data source alongside existing Likes and Playlists caches.

The ingestion project must use a normal Spotify Web API Authorization Code flow with the app owner’s personal developer account (no Juky). Tracks must be enriched with ReccoBeats audio features. The final artifacts should align with RunClub’s existing SwiftData models so the app can import the data with zero ambiguity.


## Context and Alignment

- RunClub caches and operates on three core model types in SwiftData:
  - CachedTrack: id (Spotify track ID), name, artistId, artistName, durationMs, albumName, albumReleaseYear?, popularity?, explicit, addedAt, isPlayable
  - AudioFeature: trackId, tempo?, energy?, danceability?, valence?, loudness?, key?, mode?, timeSignature?
  - CachedArtist: id (Spotify artist ID), name, genres:[String], popularity?

- Auxiliary enums used by the app:
  - Genre umbrellas derive from a bundled mapping file and power affinity/neighbor logic for selection UX.
  - Decade enum values: “70s”, “80s”, “90s”, “00s”, “10s”, “20s”.

- Generation rules (high-level) relevant to ingestion filtering:
  - Prefer track lengths 2–5 minutes; never include >6 minutes.
  - Avoid duplicates; spacing and per-artist constraints are applied later in generation.
  - Selection operates on joins of CachedTrack + AudioFeature + CachedArtist.


## Objective

Build a stand-alone ingestion project that:
1) Crawls Spotify using a large, configurable set of search terms and playlist-name searches to gather tens of thousands of candidate tracks across decades and genres.
2) Enriches each unique track with ReccoBeats audio features.
3) Classifies each row with derived metadata needed by RunClub (e.g., umbrella genres and decade).
4) Applies quality filters (length, market playability, dedupe by ID/ISRC) and basic sanity checks.
5) Exports static files matching RunClub’s model shapes for painless import.
6) Produces a manifest and metrics for auditability and reproducibility.


## Technology and Constraints

- Language: Python 3.11 preferred (ok to propose Node 20 if strongly justified).
- Packages:
  - Spotify: spotipy (or direct requests with robust token/ratelimit support).
  - ReccoBeats: simple requests client with retries/backoff.
  - Dataframes/IO: pandas or polars (for CSV/Parquet/JSONL), or streaming JSONL writers if memory concerns.
- Auth:
  - Spotify: Authorization Code flow to obtain and persist a refresh token; do not require user interaction beyond initial grant. Use env vars: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, SPOTIFY_REFRESH_TOKEN, SPOTIFY_REDIRECT_URI.
  - ReccoBeats: RECCOBEATS_BASE_URL, RECCOBEATS_API_KEY (or equivalent).
- Concurrency/Rate limiting: honor Spotify rate limits; implement automatic retry with exponential backoff and jitter; respect ReccoBeats quotas similarly.
- Idempotence: persist intermediate caches (discovered tracks, artists, features) to avoid re-fetching; safe to resume.
- Determinism: seed-based ordering and stable set operations where applicable; version the output with a manifest.


## Inputs (Configurable)

- Search term seeds (high cardinality):
  - Genres, subgenres, umbrella labels, era/decade modifiers, “running”-adjacent descriptors (e.g., “upbeat”, “tempo”, “fast”), locale variants.
  - Examples: “70s country”, “1970s outlaw country”, “90s alt rock”, “drum and bass running”, “latin reggaeton fast”.

- Playlist name seeds:
  - Examples: “metal running playlist”, “indie running”, “country tempo run”, “house workout”, “electronic running”, “80s running mix”.

- Query parameters:
  - Per-seed search types: track search vs playlist search; top-N caps; pagination size; per-seed de-dup settings.
  - Market: primary target market (e.g., US) for playability filtering; fallback behavior if not present in markets.
  - Distribution targets: minimum counts per umbrella x decade grid (see “Coverage & Balancing”).


## Outputs (Static Artifacts to Copy into RunClub)

Decision: Export a single canonical “wide” JSONL as the primary artifact, and also generate the three app-aligned files for drop-in import. The wide file preserves every column you need (including the example you provided); the splitter converts to the exact RunClub model shapes.

Export artifacts (JSON Lines, newline-delimited JSON), with gzip-compressed variants. Names may include a version/tag or date stamp from the manifest.

0) catalog_wide.jsonl[.gz] (canonical denormalized dataset)
   - Includes all ingestion fields (full provenance, playlist sources, search seeds, Recco metadata, extra features) with snake_case keys.
   - Must include (at minimum) the following fields to satisfy your example and audit needs:
     - id: string (UUID row id; stable within a run)
     - spotify_track_id: string
     - isrc: string|null
     - name: string
     - duration_ms: int
     - explicit: boolean
     - album_name: string
     - album_release_date: string (YYYY-MM-DD or YYYY)
     - album_release_year: int|null
     - album_decade_label: "70s" | "80s" | "90s" | "00s" | "10s" | "20s" | null
     - album_image_url: string|null
     - popularity_snapshot: int|null
     - popularity_bucket: int|null
     - available_us: boolean
     - available_primary_markets: string[] (e.g. ["US","CA","GB","AU"])
     - preview_url: string|null
     - artist_ids: string[] (primary artist should be index 0)
     - artist_names: string[] (same order as artist_ids)
     - artist_genres: string[][] (per-artist normalized genres; same order)
     - artist_image_urls: string[]|null (optional, same order)
     - source_playlist_id: string|null (primary source)
     - source_playlist_name: string|null
     - source_playlist_owner: string|null (e.g., "spotify")
     - sources: array of objects (optional, for multi-source provenance), items like:
         { "type": "playlist", "playlist_id": "...", "owner": "spotify", "name": "..." }
         { "type": "search", "term": "rock running" }
     - recco_track_id: string|null
     - recco_features_version: string|null
     - recco_features_at: ISO-8601 string|null
     - tempo: number|null
     - energy: number|null
     - danceability: number|null
     - valence: number|null
     - loudness: number|null
     - acousticness: number|null
     - instrumentalness: number|null
     - liveness: number|null
     - speechiness: number|null
     - key: int|null
     - mode: int|null
     - time_signature: int|null
     - created_at: ISO-8601 string
     - updated_at: ISO-8601 string
   - Notes:
     - Keep arrays for artists and multi-source provenance; the splitter will flatten as needed.
     - Retain additional ingestion-only fields as you see fit under a `_extra` object.

1) cached_tracks.jsonl[.gz]
   - Shape aligns to CachedTrack in the app:
     - id: string (Spotify track ID)
     - name: string
     - artistId: string
     - artistName: string
     - durationMs: int
     - albumName: string
     - albumReleaseYear: int|null
     - popularity: int|null
     - explicit: boolean
     - addedAt: ISO-8601 string (UTC)
     - isPlayable: boolean (true if playable in target market or globally; see filtering)
   - Additional ingestion-only fields (safe for the app to ignore) are allowed but should be prefixed to avoid collisions, e.g. _ingestSource, _ingestQuery, _ingestPlaylistId, _ingestDiscoveredAt, _isrc.

2) audio_features.jsonl[.gz]
   - Shape aligns to AudioFeature:
     - trackId: string (Spotify track ID)
     - tempo: number|null
     - energy: number|null
     - danceability: number|null
     - valence: number|null
     - loudness: number|null
     - key: int|null
     - mode: int|null
     - timeSignature: int|null

3) cached_artists.jsonl[.gz]
   - Shape aligns to CachedArtist:
     - id: string (Spotify artist ID)
     - name: string
     - genres: string[] (normalized to lower case; hyphens→spaces, “&”→“and”)
     - popularity: int|null

4) manifest.json
   - Metadata to ensure reproducibility and QA:
     - version: string (semantic or date-based)
     - createdAt: ISO-8601
     - spotify: { market, seedsSummary, searchCounts, playlistCounts }
     - reccobeats: { featureCoveragePct, errors, retries }
     - totals: { tracks, artists, audioFeatures, byUmbrellaAndDecade: { [umbrella]: { [decade]: count } } }
     - filtersApplied: { minDurationMs, maxDurationMs, explicitPolicy, playabilityPolicy, dedupePolicy }
     - fileHashes: { filename: sha256 }

Note: JSONL is preferred for streamable imports. If needed, also provide CSV and/or a single Parquet for analysts, but JSONL is canonical for the app importer.

### Splitter: Field Mapping to App Models
- From catalog_wide.jsonl to cached_tracks.jsonl:
  - spotify_track_id → id
  - name → name
  - artist_ids[0] → artistId (primary artist)
  - artist_names[0] → artistName
  - duration_ms → durationMs
  - album_name → albumName
  - album_release_year → albumReleaseYear
  - popularity_snapshot → popularity
  - explicit → explicit
  - created_at (or a derived discoveredAt) → addedAt
  - isPlayable computed as: available_us OR (available_primary_markets contains primary market) → isPlayable
  - Additionally copy (prefixed) ingestion-only fields if desired: _isrc, _album_decade_label, _preview_url, _album_image_url, _popularity_bucket, _available_primary_markets, _source_playlist_id, _source_playlist_name, _source_playlist_owner, _recco_features_version, _recco_features_at

- From catalog_wide.jsonl to audio_features.jsonl:
  - spotify_track_id → trackId
  - tempo, energy, danceability, valence, loudness, key, mode, time_signature → same (others like acousticness/instrumentalness/liveness/speechiness remain only in catalog_wide)

- From catalog_wide.jsonl to cached_artists.jsonl:
  - For each position i:
    - artist_ids[i] → id
    - artist_names[i] → name
    - artist_genres[i] (normalize: lowercased, hyphen→space, “&”→“and”) → genres
    - popularity not always present in the canonical row; if fetched during artist enrichment, emit it; else null


## Core Pipeline

1) Seed Expansion
   - Normalize incoming search terms and playlist-name seeds.
   - Expand via templates across decades (70s/80s/90s/00s/10s/20s), umbrellas, and locale synonyms.
   - De-duplicate seeds and cap expansions per dimension to control crawl breadth.

2) Spotify Discovery
   - Track search (query to /search type=track) and playlist search (type=playlist).
   - For playlist search hits, fetch top K playlists per seed, then fetch tracks from each playlist (paginate).
   - Collect candidates as Spotify track IDs with provenance fields (seed term, source=search/playlist, playlistId/owner where applicable).
   - Persist raw discovery snapshots for idempotence and audit.

3) Canonical Track Resolution
   - Fetch track details in batches: name, artists, album, duration_ms, popularity, explicit, available_markets, is_playable, external_ids.isrc, linked_from.
   - Determine market playability (target market or “sufficient” global coverage). Set isPlayable.
   - Extract primary artist (artistId, artistName) and album metadata (album name, release date→year).
   - Derive albumReleaseYear (int?) from album.release_date.
   - Compute derived decade using year → {“70s”, “80s”, “90s”, “00s”, “10s”, “20s”}. If no year, leave null; the app can ignore decade if missing.

4) Artist Metadata
   - Batch-fetch artists to get normalized genres (lowercased; hyphens→spaces; “&”→“and”) and popularity.
   - Store one row per unique artist in cached_artists.jsonl.

5) ReccoBeats Enrichment
   - Resolve Spotify track IDs to Recco IDs (batched).
   - Fetch audio features for all resolved tracks and store rows in audio_features.jsonl keyed by trackId.
   - Handle missing features gracefully; null fields are acceptable.

6) Quality Filters and Dedupe
   - Duration: keep 120,000ms ≤ durationMs ≤ 360,000ms (2–6 min). Prefer 2–5 min; retain up to 6 min to avoid over-pruning very thin categories.
   - Playability: require isPlayable=true per target market logic.
   - Dedupe:
     - Primary: Spotify track ID uniqueness.
     - Secondary: ISRC-based collapse (prefer most popular or first-seen). Track linked_from can also indicate duplicates.
   - Explicit: retain; the app may filter later. Include explicit flag.

7) Coverage & Balancing
   - Compute umbrella genres from artist genres using an internal mapping (the app’s mapping informs what umbrellas exist; ingestion should aim to cover each umbrella broadly even if the exact mapping file differs). Store umbrella ids in additional ingestion-only fields if helpful for QA; the app will compute umbrellas again at runtime, but your distribution logic should still target umbrella x decade coverage.
   - Target minimum counts per umbrella x decade (configurable; e.g., 400–800 per cell). Include ramp/soft targets and a global cap to maintain total size.
   - For thin cells, expand neighbors (related umbrellas) and adjacent decades to backfill.

8) Export
   - Write JSONL files with one object per line; UTF‑8; no BOM.
   - Provide gzipped variants (.gz) and compute sha256 for manifest.


## Provenance and Incremental Re-run Policy

- Playlist/source tracking:
  - Maintain a persistent “playlist registry” with: playlist_id, owner, name, snapshot_id, first_seen_at, last_processed_at, last_snapshot_processed.
  - Skip re-processing a playlist if snapshot_id is unchanged since last_processed_at.
  - Record per-run diffs if snapshot_id changed (process only new tracks).

- Seed/term tracking:
  - Maintain a “seed ledger” keyed by seed term and search type (track or playlist) with last_seen_at, last_offset, and counts.
  - Store edges seed_term → spotify_track_id to avoid duplicate candidate work across different seeds.

- Track/feature enrichment tracking:
  - Maintain a “track registry” keyed by spotify_track_id with fields: last_enriched_at, has_features, has_artist, last_seen_sources (playlist ids, search terms).
  - Only call ReccoBeats for tracks lacking features or when feature version changes (recco_features_version).

- Provenance in catalog_wide:
  - Keep primary source_playlist_* columns (as in your example) and optionally a “sources” array to record all contributing seeds/playlists for audit.

- Idempotence:
  - All write steps are upserts keyed by IDs; re-running produces stable outputs, without duplicating rows.


## Data Shapes (Examples)

Example cached_tracks.jsonl row:
```json
{
  "id": "2xLMifQCjDGFmkHkpNLD9h",
  "name": "Song Title",
  "artistId": "1vCWHaC5f2uS3yhpwWbIA6",
  "artistName": "Artist Name",
  "durationMs": 212000,
  "albumName": "Album Name",
  "albumReleaseYear": 1977,
  "popularity": 58,
  "explicit": false,
  "addedAt": "2025-10-15T14:26:05Z",
  "isPlayable": true,
  "_ingestSource": "playlist",
  "_ingestQuery": "70s country running",
  "_ingestPlaylistId": "37i9dQZF1DX76Wlfdnj7AP",
  "_isrc": "USUM71703861",
  "_decade": "70s",
  "_umbrellas": ["Country & Americana"]
}
```

Example audio_features.jsonl row:
```json
{
  "trackId": "2xLMifQCjDGFmkHkpNLD9h",
  "tempo": 167.2,
  "energy": 0.71,
  "danceability": 0.62,
  "valence": 0.43,
  "loudness": -6.1,
  "key": 9,
  "mode": 1,
  "timeSignature": 4
}
```

Example cached_artists.jsonl row:
```json
{
  "id": "1vCWHaC5f2uS3yhpwWbIA6",
  "name": "Artist Name",
  "genres": ["country", "alt country"],
  "popularity": 67
}
```


## CLI and Project Structure

- Repo layout (suggested):
  - src/
    - config/
      - seeds/
        - search_terms.txt (or .json)
        - playlist_terms.txt (or .json)
      - settings.yaml (market, caps, quotas, limits)
    - spotify_client.py (auth/token, rate limit aware calls, batching)
    - reccobeats_client.py (resolve IDs, fetch features; retries/backoff)
    - discovery.py (seed expansion, search, playlist fetch, candidate set)
    - resolver.py (track/artist canonicalization, market checks, decade derivation)
    - features.py (reccobeats enrichment)
    - filters.py (duration/playability/explicit policies, dedupe by id/isrc)
    - balance.py (umbrella x decade coverage logic)
    - export.py (writers for jsonl + gz, sha256, manifest)
    - util/
      - cache_store.py (local sqlite or jsonl append-only caches)
      - logging.py
  - scripts/
    - run_discovery.sh
    - run_enrichment.sh
    - export_static.sh
  - Makefile (phony: bootstrap, crawl, enrich, export, clean)
  - requirements.txt / pyproject.toml

- CLI commands (examples):
  - python -m src.discovery --config config/settings.yaml --seeds config/seeds/search_terms.txt --playlist-seeds config/seeds/playlist_terms.txt --out .cache/discovery.parquet
  - python -m src.resolver --in .cache/discovery.parquet --out .cache/resolved.parquet --market US
  - python -m src.features --in .cache/resolved.parquet --out .cache/features.parquet
  - python -m src.filters --tracks .cache/resolved.parquet --features .cache/features.parquet --out .cache/filtered.parquet
  - python -m src.balance --in .cache/filtered.parquet --quota config/settings.yaml --out .cache/balanced.parquet
  - python -m src.export --in .cache/balanced.parquet --artists .cache/artists.parquet --out ./export/ --write-catalog-wide --write-splits


## Policies and Heuristics

- Market playability:
  - Accept if is_playable true or available_markets includes target market (e.g., US). If ambiguous, prefer conservative exclusion unless thin coverage forces inclusion.

- Duration:
  - Target 2–5 min; permit up to 6 min only if otherwise eliminating valuable coverage. Enforce hard cap at 6 min.

- Dedupe:
  - Collapse variants sharing same ISRC to a single canonical track (break ties on earliest release year or stable ID ordering).
  - Always unique on final Spotify track ID in exported files.

- Artists and genres:
  - Normalize artist genres to lowercased, hyphen→space, “&”→“and” (app’s mapping uses this normalization).
  - Derive umbrellas for balancing purposes using an internal mapping aligned in spirit to the app’s umbrellas; the app will recompute umbrellas at runtime.

- Decade derivation:
  - From albumReleaseYear: 1970–1979→“70s”, 1980–1989→“80s”, 1990–1999→“90s”, 2000–2009→“00s”, 2010–2019→“10s”, 2020–present→“20s”.

- Coverage balancing (examples; configurable):
  - Minimum 400–800 tracks per umbrella x decade cell with a global target of 15–40k total tracks.
  - For thin cells, expand to neighbor umbrellas and adjacent decades; prefer keeping umbrella consistent before crossing decades.

- Logging and QA:
  - Emit per-seed discovery counts, rejection reasons (duration, playability, dedupe), and feature coverage %.
  - Stop-the-world sanity checks: average duration, feature field null rates, decade distribution, umbrella balance.


## Acceptance Criteria

- Deliverables:
  - catalog_wide.jsonl[.gz], cached_tracks.jsonl[.gz], audio_features.jsonl[.gz], cached_artists.jsonl[.gz], manifest.json
  - requirements.txt (or pyproject.toml) and README with setup/usage.
  - Caches under .cache/ to enable resumption (may be excluded from the final copy).

- Data quality:
  - ≥ 95% of exported tracks have ReccoBeats features populated (null acceptable for misses).
  - ≥ 90% tracks have albumReleaseYear and a derived decade.
  - Duration policy respected; no tracks > 6 minutes.
  - Dedupe by ID and by ISRC implemented.
  - Manifest present with correct sha256s and accurate totals.

- Performance and resilience:
  - Handles tens of thousands of tracks in a single run with automatic pagination and backoff.
  - Idempotent: rerunning does not balloon duplicates; incremental additions are possible.


## Security and Secrets

- Use environment variables for all secrets; never commit secrets.
- Provide a .env.example listing required variables.
- Persist only the Spotify refresh token locally in a developer-safe manner for unattended runs.


## Stretch Goals (Optional)

- Export alternative formats (CSV/Parquet) for analytics.
- Include a lightweight ISRC-to-Spotify canonicalizer to stabilize dedupe decisions.
- Provide a small “smoke test” corpus generator for CI (e.g., 500 tracks across a few umbrellas/decades).
- Include a script to compute per-tempo buckets helpful for pacing previews (derived from ReccoBeats tempo).


## Integration Notes for RunClub (FYI)

- The app’s importer will read JSONL files and upsert into its own SwiftData store with the same model shapes (CachedTrack, AudioFeature, CachedArtist). No code changes should be required if shapes match.
- Additional ingestion-only fields (prefixed with “_”) are ignored by the importer.
- The static files will live under the app bundle’s resources or an import path specified in the app; size considerations suggest gzip and on-device streaming import.


## Sourcing Strategy and Seed Keywords (Provided)

Use the following approach and keywords to maximize coverage while keeping high-signal material. Favor owner=spotify editorial first, then high-follower community lists.

1) Editorial workout/running lists (owner=spotify)
   - Keywords: workout, running, run mix, cardio, HIIT, gym, pump up, training motivation, beast mode, treadmill, power run, marathon training, tempo run, sprint workout, interval training

2) Umbrella-anchored “energy” lists
   - For umbrellas like: Pop, Rock, Indie, Hip-Hop, R&B, Electronic, Latin, Metal, Country, Afrobeat, K-pop, Bollywood, Reggaeton, EDM, House, Techno
   - Patterns per {umbrella}:
     {umbrella} workout
     {umbrella} running
     {umbrella} cardio
     {umbrella} HIIT
     {umbrella} pump up
     {umbrella} gym
     {umbrella} power run
     {umbrella} interval
     fast {umbrella}
     high energy {umbrella}
     {umbrella} bangers
     uptempo {umbrella}
   - Examples: rock running, fast rock, indie workout, uptempo indie, latin cardio, reggaeton running, electronic workout, edm running, house workout, techno running, hip-hop workout, rap running, metal workout, punk running

3) Decade refreshers (let features filter the run-suitable subset)
   - Decades: 70s, 80s, 90s, 2000s, 2010s, 2020s
   - Patterns:
     {decade} hits
     best of {decade}
     {decade} pop hits
     {decade} rock hits
     {decade} dance hits
     {decade} throwbacks
     throwback hits
     nostalgia {decade}
     club hits {decade}
     party hits {decade}
   - Optional workout angle: {decade} workout, {decade} running

4) Trend feeders (freshness)
   - Top 50 USA, Viral 50 USA, Top 50 Global, Viral 50 Global
   - New Music Friday, mint, Dance Rising, Fresh Finds, Rock This, RapCaviar, Pop Rising, Viva Latino, Today’s Top Hits, New Joints, New Music Pop, New Music Rock
   - Filter owner=spotify first; then apply acoustic/feature gates.

5) Cadence-specific lists (precision BPM mining)
   - Common cadences, vary ±5 BPM:
     150, 155, 160, 165, 170, 175, 180 bpm
   - Also:
     {bpm} bpm workout
     {bpm} bpm run mix
     cadence {bpm} running
     {bpm} spm running

6) Long-tail sub-genre backfill (quota top-ups)
   - Sub-genres (examples):
     Pop family: dance pop, electropop, hyperpop
     Rock/Alt: alternative rock, indie rock, pop punk, emo, punk rock
     Electronic: house, big room, techno, trance, drum & bass, dubstep, electro house
     Hip-Hop/R&B: trap, boom bap, grime, drill, contemporary r&b
     Latin: reggaeton, dembow, latin pop, urbano latino
     Global: afrobeat, amapiano, bhangra, bollywood, k-pop, j-pop
     Metal/Hard: metalcore, hard rock, hardcore punk
     Funk/Disco: nu disco, funk, disco
   - Patterns per {subgenre}:
     {subgenre} workout
     {subgenre} running
     {subgenre} cardio
     fast {subgenre}
     high energy {subgenre}


## Getting Started (Checklist for the Agent)

1) Bootstrap Python project with virtualenv and requirements.
2) Implement Spotify Authorization Code flow to obtain refresh token; document one-time grant steps.
3) Build spotify_client with rate-limit aware batching for tracks, artists, playlists.
4) Implement discovery from search terms and playlist terms; persist raw candidates.
5) Implement resolver (canonical track rows), artist fetch, decade derivation, market playability flag.
6) Implement ReccoBeats client for ID resolution and feature fetch; join features to tracks.
7) Implement filters (duration, playability, dedupe by ID/ISRC).
8) Implement balancing to hit umbrella x decade quotas.
9) Export JSONL files and manifest with checksums and counts.
10) Provide README with commands and troubleshooting.


---

If any assumption is unclear (e.g., ReccoBeats endpoints, umbrellas list, or market policy), proceed with sensible defaults and document decisions in the manifest’s notes field. The primary priority is producing high-coverage, balanced, deduplicated, feature-enriched static files that strictly match the field names/types of CachedTrack, AudioFeature, and CachedArtist.


