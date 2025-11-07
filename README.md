# RunClub

RunClub is a SwiftUI app that builds high-energy running playlists from a runner's Spotify library. The experience is entirely on-device today: we authenticate via Juky, crawl the user's library into SwiftData, and generate playlists tailored to planned workouts.

## Quick Start

- **Requirements**
  - Xcode 16.0+
  - iOS 18 simulator or device
  - A Spotify Premium account (required for playback and liked-song access)
- **Build steps**
  1. Clone this repo and open `RunClub/RunClub.xcodeproj` in Xcode.
  2. Select the `RunClub` scheme and the desired simulator/device.
  3. Run (⌘R). The first launch will prompt for Health, Notifications, and Spotify access.
  4. Authenticate with Spotify via the embedded Juky web view. The override token is stored in Keychain and automatically reused on subsequent launches.

> **Tip**: When testing against a real device, ensure Safari is logged into the target Spotify account before launching RunClub—Juky inherits that session.

## Project Layout

| Path | Purpose |
| --- | --- |
| `Models/` | SwiftData models shared across features (track cache, user prefs, etc.). |
| `Services/` | Business logic (Spotify API client, crawlers, notifications, health sync, orchestration). |
| `Views/` | SwiftUI view hierarchy composed around `HomeView`.
| `RunClub/RunClub/Support/` | Styling, fonts, configuration, and Keychain wrappers.
| `RunClub/RunClubApp.swift` | App entry point, dependency bootstrapping.

Key services to understand:

- **`AuthService`** – Manages override access tokens sourced from Juky. It now treats native credentials as a secondary fallback and never attempts PKCE flows on-device (ready for future backend handoff).
- **`SpotifyService`** – Thin API client that focuses on lightweight operations (recommendation probing, playlist creation, library utilities). Legacy bulk playlist generation code has been retired in favour of `LocalGenerator`.
- **`LocalGenerator`** – Builds run plans using cached audio metadata. It is the single source of truth for playlist construction and the main integration point when a backend service becomes available.
- **`CrawlCoordinator` / `RecommendationsCoordinator`** – Own the long-running library sync jobs and write into SwiftData caches.
- **`RunPreviewService`** – Produces preview playlists by combining `LocalGenerator` with cached metadata. Confirms runs via `SpotifyService.createPlaylist`.

## Data & Persistence

- **SwiftData stores**: Two containers (library + recommendations) keep cached tracks and features. `RecommendedSongsRepository` exposes an interface that can be swapped for a backend-backed repository later.
- **Keychain**: Stores the Juky override access token and optional refresh/expiry metadata.
- **UserDefaults**: Tracks lightweight state like onboarding completion, selected templates, and crawl progress flags.

## Preparing for the Future Backend

- All write-heavy services (`LocalGenerator`, `RecommendedSongsRepository`, playlist confirmation) are sealed behind small entry points so their implementations can be swapped with network-backed equivalents without touching the view layer.
- `AuthService` exposes `sharedToken()` and a token override hook so the backend can issue branded tokens and keep clients off the Spotify refresh flow.
- Legacy playlist generation functions that tightly coupled to the Spotify Recommendations API have been deprecated. Any future playlist building should go through `LocalGenerator` or a backend endpoint.

## Development Guidelines

- Document public methods with concise doc comments.
- Keep networking work on a background actor, surfaces back to `@MainActor` prior to touching UI state.
- Prefer dependency injection over singletons—`RootView` exposes only the pieces that are required globally.
- When touching Spotify endpoints, prefer adding focused helpers on `SpotifyService` rather than embedding fetch logic in views.
- Tests live under `RunClubTests/`; run them via `xcodebuild test -scheme RunClub -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Operational Notes

- **Notifications**: `NotificationScheduler` issues “next track” alerts; they are safe to disable while testing.
- **HealthKit**: The app currently writes workouts only; reading metrics is blocked on permissions until the backend ships.
- **Metrics & Logging**: Long-running operations print structured logs (prefixed with `[LIKES_TOAST]`, `[RECS_TOAST]`, etc.) for quick debugging in Xcode's console.

## Troubleshooting

- **401 responses from Spotify** → `SpotifyService` automatically invokes `JukyHeadlessRefresher` and retries with the refreshed token.
- **Empty recommendations** → Use the diagnostics buttons under `Settings → Spotify Debug` to probe the account/market (calls `probeRecommendationsSimple` and `probeRecommendationsSuperRelaxed`).
- **SwiftData crashes on model change** → Delete `~/Library/Developer/CoreSimulator/.../default.store*` and relaunch, or use the `Reset Library` button in Settings.

## Contributing

Before opening PRs:

1. Run the full test suite.
2. Verify there are no lint warnings in touched files.
3. Update documentation and the Cursor rules if you change coding conventions.

Happy running! 🏃‍♀️🎶
