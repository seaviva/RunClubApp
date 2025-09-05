## RunClub – Product and Generation Master Plan (MVP → v1)

### Vision
- **Goal**: Minimal, fast running app that generates Spotify playlists where track order encodes workout structure and total time ≈ requested duration.
- **Scope**: Keep PKCE auth untouched. Build incrementally. iOS 16+, SwiftUI.

### Constraints
- **Auth**: Existing PKCE flow via `AuthService` must remain unchanged.
- **Storage**: Tokens in Keychain. User prefs local.
- **UI**: Minimal; runner-focused.
- **Spotify**: Use web API with user’s market from profile.

## Onboarding and Preferences
- **Runs per week (required)**: 2, 3, 4, 5.
- **Preferred duration category**:
  - Short: 20–30 min (midpoint default 25).
  - Medium: 30–45 min (midpoint default 37).
  - Long: 45–60 min (midpoint default 53).
- **Long & Easy rule**: 1.5× the selected duration category (respecting lower/upper derived bounds).
- **Storage**: `AppStorage` keys (e.g., `runsPerWeek`, `preferredDurationCategory`, `onboardingComplete`).
 - **Pace bucket (planned)**: A–D (default B until onboarding exists). Maps to a cadence anchor (SPM) used by the local generator; see `ALGORITHM_SPEC.md`.

## Duration Handling
- **Hard bounds**: Do not exceed the duration bracket bounds for the selected category, except when explicitly specified by a template rule (e.g., Long & Easy 1.5×).
- **Template-specific targets**: Each template has a target total and warm‑up/core/cool‑down split per category. The generator aims for these and allows small flexibility (≈±1 track) to fit within bounds; see details below and in `ALGORITHM_SPEC.md`.
- **Tolerance**: Prefer within ±60s of target while obeying bounds (flex around track boundaries).
- **Warm‑up/Cool‑down**: Reserved as Easy; roughly WU ≈ 20–25% and CD ≈ 15–20% of total, with per‑template splits below.
- **Duration bias by template**: Easy leans shorter; Strong & Steady / Pyramid / Kicker lean longer; Waves center (Long Waves slightly longer). See `ALGORITHM_SPEC.md`.
- **Waves note**: “Short Waves” and “Long Waves” describe interval pattern length, not strictly the total duration.

## Template Archetypes and Segment Logic
Definitions encode how playlist effort should flow (tiered effort per slot using a 5‑tier system: Easy, Moderate, Strong, Hard, Max). Tempo targets are derived from the runner’s cadence anchor, not fixed BPM. See `ALGORITHM_SPEC.md` for tier curves and slot windows.

- **Easy Run**: Mostly Easy; allow ≤20% low‑end Moderate in middle; WU/CD Easy.

- **Strong & Steady**: Mostly Strong; optionally 1–2 low‑end Hard spikes; no Max; WU/CD Easy.

- **Long & Easy**: Mostly Easy; ≤20% Moderate; WU/CD Easy. Duration may apply 1.5× rule per scheduler.

- **Short Waves** (fartlek): Repeat Easy ↔ Hard cycles; no Max in first cycle; at most one Max near the end if time; end Easy; WU/CD Easy.

- **Long Waves**: Repeat Moderate ↔ Hard (tighter range than short waves; start Moderate; fewer Hards; no Max); WU/CD Easy.

- **Pyramid**: Moderate → Strong → Hard → Max → Hard → Strong → Moderate (drop Max first if short); WU/CD Easy.

- **Kicker**: Moderate/Strong base; final ramp to Hard then Max; at most 1 Max and ≤2 Hard; for short runs end at Hard only; WU/CD Easy.

Notes:
- See `ALGORITHM_SPEC.md` for slot windows (cadence‑relative), relaxations, and scoring.

### Template Duration Targets (minutes → WU/Core/CD)
- **Easy Run** (leans short)
  - Short: 20–22 → 4/13/3 (baseline 20)
  - Medium: 32–35 → 6/22/6 (baseline 34)
  - Long: 47–50 → 8/34/8 (baseline 50)
- **Strong & Steady** (middle)
  - Short: 25 → 5/15/5
  - Medium: 38–40 → 7/25/7 (baseline 39)
  - Long: 55 → 9/37/9
- **Long & Easy** (1.5× weekend run)
  - Short (30×1.5): 45 → 8/29/8
  - Medium (45×1.5): 68 → 12/44/12
  - Long (60×1.5): 90 → 15/60/15
- **Short Waves** (alt easy/hard, middle)
  - Short: 26–28 → 5/17/4 (baseline 26)
  - Medium: 38–40 → 7/25/6 (baseline 38)
  - Long: 50–52 → 9/34/8 (baseline 51)
- **Long Waves** (2 easy/2 hard, leans long)
  - Short: 28–30 → 6/18/5 (baseline 29)
  - Medium: 43–45 → 8/29/8 (baseline 45)
  - Long: 58–60 → 10/40/10
- **Pyramid** (middle–long)
  - Short: 27–28 → 5/17/5 (baseline 27)
  - Medium: 40–42 → 7/26/7 (baseline 40)
  - Long: 55–57 → 9/37/9 (baseline 55)
- **Kicker** (middle, end surge)
  - Short: 25–26 → 5/15/5 (baseline 25)
  - Medium: 38–40 → 7/25/7 (baseline 39)
  - Long: 52–54 → 9/35/8 (baseline 52)

## Weekly Recommendation Scheduling
- **A/B week structure**: Use ISO week parity to alternate Week A/Week B to avoid monotony.
- **Even distribution**: Spread runs evenly across week; long run on Sunday by default.
- **If not a run day**: Show “Rest”. Always show “Do something else” to create a custom run.

## Home schedule (planned)
- Collapsed weekly strip with dots for run days only, today highlighted; tap to select.
- Chevron opens a month sheet; dots on run days; selecting a day updates Home.
- Day card title shows “Today’s run” if today; otherwise formatted date.
- Settings gear always visible in header.

- **2 runs/week**
  - Week A: Strong & Steady (Medium), Easy Run (Short)
  - Week B: Kicker (Medium), Long & Easy (Long×1.5)

- **3 runs/week**
  - Week A: Easy Run (Short), Strong & Steady (Medium), Short Waves (Medium)
  - Week B: Easy Run (Short), Pyramid (Medium), Long & Easy (Long×1.5)

- **4 runs/week**
  - Week A: Easy Run (Short), Strong & Steady (Medium), Short Waves (Medium), Long & Easy (Long×1.5)
  - Week B: Easy Run (Short), Kicker (Medium), Long Waves (Medium), Strong & Steady (Medium)

- **5 runs/week**
  - Week A: Easy Run (Short), Strong & Steady (Medium), Short Waves (Medium), Easy Run (Short), Long & Easy (Long×1.5)
  - Week B: Easy Run (Short), Pyramid (Medium), Strong & Steady (Medium), Kicker (Medium), Easy Run (Short)

## Customization Inputs
- **Template**: Choose any from the list above.
- **Duration**: Constrained by category bounds; Long & Easy applies 1.5× rule.
- **Genres**: Umbrella genres backed by JSON mapping (10 umbrellas). If a selected umbrella is thin, neighbor umbrellas are automatically considered with reduced weight.
- **Decades**: 70s, 80s, 90s, 00s, 10s, 20s.
- **Prompt**: Keyword extraction to genres/moods/decades; no LLM in MVP.

## Generation Pipeline
See `ALGORITHM_SPEC.md` for the complete local generation algorithm (templates, effort curves, scoring, rediscovery, diversity, and polish). This section tracks only high-level integration points.

1) Use local SwiftData cache (liked tracks + RB features + artist genres) and `ALGORITHM_SPEC.md` selection.
2) Create public playlist and return the web URL; open Spotify if available.

Warm-up and cooldown, template curves, rediscovery quota, diversity, and relaxations are defined in `ALGORITHM_SPEC.md`.

Playlist naming/privacy/description: unchanged; see `ALGORITHM_SPEC.md`.

### Recent updates (Local Generator)
- Genre filtering migrated to a bundled JSON umbrella mapping (10 umbrellas, ~1300 Spotify genres) with explicit neighbor relationships. Each artist gets a GenreAffinity to selected umbrellas; neighbors contribute with reduced weight. Selection uses affinity for filtering and adds a small scoring bonus to prefer on‑umbrella tracks while still broadening gracefully when thin.

## Endpoints and External Services
- Spotify
  - `GET /v1/me` (profile/market)
  - `GET /v1/me/tracks` (liked) — crawler
  - `GET /v1/artists` (details) — crawler
  - `POST /v1/users/{id}/playlists`, `POST /v1/playlists/{id}/tracks` — creation
- ReccoBeats
  - `GET /v1/track?ids=…` to resolve Spotify IDs → Recco IDs (batched)
  - `GET /v1/track/{id}/audio-features` (features)
Notes: Local generation is SwiftData‑first; legacy Spotify recommendations path is superseded by `ALGORITHM_SPEC.md`.

## Data Structures (planned)
- `UserPreferences`: `runsPerWeek`, `preferredDurationCategory`.
- `UserRunPrefs`: `paceBucket` (A–D; default B).
- `TrackUsage`: `trackId`, `lastUsedAt`, `usedCount`.
- `RunTemplateType`: enum of templates.
- Local selection operates on SwiftData joins of `CachedTrack` + `AudioFeature` + `CachedArtist`.

## Rules and Relaxations (local generation)
- Thin slots: widen tempo window, allow adjacent effort spillover, temporarily relax filters, and (once) allow breaking the 10‑day rule; see `ALGORITHM_SPEC.md`.
- Track length: prefer 2–5 min; never include >6 minutes.
- Per‑artist: max 2 per playlist, no back‑to‑back; soft spacing ~1 per 20 min.
- Duplicates: disallow exact duplicates.
- Duration bounds: always fit within category min/max; ±60s tolerance.

## Local Spotify Library Cache (SwiftData)
- Purpose: eliminate network reads during generation and reduce rate limiting by locally caching liked tracks, audio features, and artists.
- Data models (SwiftData):
  - `CachedTrack` (id, name, artistId, artistName, durationMs, albumName, albumReleaseYear, popularity?, explicit, addedAt)
  - `AudioFeature` (trackId, tempo?, energy?, danceability?, valence?, loudness?, key?, mode?, timeSignature?) — sourced from ReccoBeats
  - `CachedArtist` (id, name, genres:[String], popularity?)
  - `CrawlState` (status running/idle/failed, nextOffset:Int?, totals, lastError?, lastCompletedAt?)
- Behavior:
  - Triggers immediately after Spotify connect when cache is empty or `CrawlState.nextOffset` indicates a partial crawl; resumable across launches.
  - Pages `/v1/me/tracks?limit=50&offset=…&market=<userCountry>` until `next == null`.
  - Audio features via ReccoBeats: resolve Spotify IDs in ≤40‑id batches; fetch features per Recco ID with rate‑limit aware backoff.
  - Batch artists via Spotify `/v1/artists` (≤50 ids/call, de‑duped).
  - Skips unplayable/local tracks; upserts by Spotify IDs; persists after each page/batch.
  - Throttling: ~2–3 req/sec; 429 handling with exponential backoff (reads `Retry-After` when present, falls back to backoff cadence).
  - Cancel‑safe: user can cancel; state remains resumable with `nextOffset`.
  - Settings → “Refresh Library” clears tables and restarts from offset 0.

## Crawler UX
- Global progress toast while crawling: “Caching your library… Tracks: X/Y • Features: A/B • Artists: C/D” + Cancel.
- Completion toast on finish: “Library cached: N tracks” (3s).
- Settings → Library section: shows counts, last cached time, Refresh/Cancel.

## Caching and Performance
- Prefer local cache for generation to avoid network latency/limits (integration next phase).
- Batch audio features (≤100) and artists (≤50).
- Parallelize independent segment candidate fetches when token permits.
- Pagination: full crawl of likes (supports up to ~10k+); continue to refine memory/throughput.

## Privacy and Storage
- Tokens remain in Keychain (existing code).
- Preferences in `AppStorage`; no external persistence for MVP.

## Naming, Market, and Locale
- **Naming**: “RunClub · [Template] [MM/DD]”.
- **Market**: derive from `GET /v1/me`.
- **Timezone**: device timezone for “today”.

## Settings (future)
- Do not persist last-used customization automatically. Provide a Settings page later where users can update default runs/week and preferred duration and possibly default genres/decades.

## Settings (MVP)
- Preferences:
  - Runs per week: 2, 3, 4, 5 (AppStorage `runsPerWeek`).
  - Preferred duration: Short/Medium/Long (AppStorage `preferredDurationCategory`).
- Spotify:
  - Status: Connected/Not Connected.
  - Reconnect (PKCE login), Disconnect (clear credentials).
- App:
  - Reset onboarding flag.
  - Show version/build.

## Future: Auto-generation defaults
- Add a dedicated section to configure “Auto” playlist behavior:
  - % of liked songs to include by default (blend vs discovery).
  - Positive genre rules (always include these genres).
  - Negative genre rules (never include these genres).
  - This impacts default seeds and filters during generation.

## Future: Missed/Completed logic
- Users can mark a run “Run complete”.
- If a run is missed, auto-slide that run to the next day unless a run already exists that day; do not stack two runs.
- Calendar needs states: planned, completed (checkmark), missed (e.g., hollow dot/cross).
- Sliding respects the week’s remaining capacity; if no slots, suggest moving to the next week.
- Respect “disable weekend long runs” (future setting) when sliding.

## Open Questions
- Any locale-specific formatting for playlist naming beyond date? (e.g., `MMM d`)

## Housekeeping
- Fix `Info.plist` key: `LSAplicationQueriesSchemes` → `LSApplicationQueriesSchemes`.
- Keep PKCE auth unchanged.

## Roadmap
- Phase 0–1: Onboarding prefs, Home skeleton, A/B scheduler, “Do something else” flow stub. Generate uses current test path.
- Phase 2: Implement generation pipeline and template → segment mapping. Wire up customization filters.
- Phase 3: Quality passes, caching, better fallbacks. Prompt keyword expansion.
- Phase 4: Explore AI‑assisted playlist reasoning using user signals.

## Potential Future Ideas

- Playlist-based library sync (user-owned and followed playlists): During onboarding, offer an optional step to select which playlists to sync (owned + followed). This sets expectations around a longer initial sync and lets users scope to the playlists they care about.
  - Implement selective playlist crawl with pagination; upsert into SwiftData and record playlist membership for provenance.
  - Dedupe by `trackId` across likes and playlists; store source tags for future diversity rules.
  - Clear progress UI: per-playlist counts, ETA, cancel/resume; obey rate limits.
  - Permissions: request `playlist-read-private` when needed; gracefully degrade otherwise.
  - On-demand refresh in Settings; consider daily incremental refresh.

- User-tunable rediscovery ratio (30–70%): Adjust rediscovery bias in the local generator; default remains 50% per ALGORITHM_SPEC.

- Personal affinity feedback: thumbs up/down and skip signals folded into scoring with decay.

- Genre-aware scoring refinements: incorporate speechiness/loudness and genre-specific effort mapping to better handle rap/metal/lofi cases (see ALGORITHM_SPEC gaps).

- Transition smoothness: prefer adjacent tracks with compatible musical key and small energy deltas, especially for EASY/STEADY sections.

- HealthKit adaptivity: optional live pace/HR feedback to gently adjust slot targets within template bounds.

- Offline and Watch support: pre-generate multiple runs; watchOS app for on-wrist controls and segment haptics.

- Social/sharing: share playlists, streaks, opt-in leaderboards.

- Advanced diversity: beyond 10-day lookback, consider artist/label/region diversity and user allow/deny lists.

- Template editor: power-user tool to design custom effort curves honored by the generator.

## Build & Test Checkpoints
- After Phase 0–1 wiring:
  - Build and run on device; complete onboarding; relaunch app to confirm prefs persist.
  - Connect Spotify; ensure login redirect works; create test playlist and open in Spotify.
  - Verify Home shows today’s recommendation or Rest; open Customize and save selection; Generate uses chosen template/duration in name.
- After Customize additions (genres/decades/prompt):
  - Save/restore selections; ensure UI chips toggle correctly; no crashes when fields are empty.
- Before Generation pipeline (Phase 2):
  - Smoke test token refresh across app relaunch; handle offline/denied scopes gracefully.
- After initial Generation pipeline:
  - For each template and duration category, create 1 playlist; check order matches template shape and total duration within bounds (Long & Easy uses 1.5× rule).
  - Validate fallback behavior when recommendations are sparse (playlist still created, within bounds).

- After Library Cache & Crawler:
  - Connect Spotify and observe progress toast; verify live increments and that Cancel hides the toast and preserves resume (relaunch app → crawl resumes where left off).
  - Open Settings → Library: verify Tracks/Features/Artists counts increase over time; on completion, last cached time is set.
  - Tap Refresh Library: counts reset to 0 and crawl restarts from 0.
  - Generation smoke test during/after crawl: app remains responsive; playlist generation still works; no UI jank.


