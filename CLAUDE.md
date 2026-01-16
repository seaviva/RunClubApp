# RunClub - Claude Code Project Guide

## Project Overview

RunClub is an iOS running app that generates Spotify playlists where track ordering encodes workout structure. The app matches playlist duration to requested run times (±2 minutes) and uses a local SwiftData cache to avoid repeated API calls.

**Key Concept**: Playlists aren't just random collections—track order represents effort phases (warm-up → core workout → cool-down) with tempo/energy matching each phase's intensity.

## Tech Stack

- **Platform**: iOS 16+, SwiftUI
- **Data**: SwiftData (local caching)
- **Auth**: Spotify via Juky (web-based token flow, supports override tokens)
- **External APIs**: Spotify Web API, ReccoBeats (audio features)
- **Location**: CoreLocation for run tracking
- **Notifications**: Local notifications for phase cues

## Architecture

**Feature-first organization** under `RunClub/Features/`:
- `Auth/` - Juky-based Spotify authentication
- `Home/` - Main screen, template selection, filters, duration picker
- `RunSession/` - Active run UI, playback control, phase orchestration
- `Generation/` - Local playlist generation algorithm
- `Settings/` - User preferences
- `Onboarding/` - Initial setup flow

**Other key directories** (all at `RunClub/` level):
- `Core/Models/` - SwiftData entities (CachedTrack, AudioFeature, CachedArtist, etc.)
- `Data/` - Library crawling, playlist sync, third-source data stack
- `Services/` - SpotifyService (low-level API client)
- `Support/` - Utilities (Buttons, Config, Fonts, Keychain, Seeders)
- `Resources/` - Bundled assets (Fonts, Video, ThirdSource data, JSON mappings)
- `RootView.swift`, `RunClubApp.swift` - App entry point at root level

**Core patterns**:
- MVVM with ObservableObjects (@Published, @StateObject)
- Coordinators for orchestrating complex flows (CrawlCoordinator, PlaylistsCoordinator)
- Services for API interactions

## Key Files

| File | Purpose |
|------|---------|
| `ALGORITHM_SPEC.md` | **Authoritative** spec for playlist generation algorithm |
| `LocalGenerator.swift` | Core generation logic (implements ALGORITHM_SPEC.md) |
| `RunOrchestrator.swift` | Manages run phases and cue scheduling |
| `SpotifyService.swift` | Low-level Spotify Web API client |
| `AuthService.swift` | Token management via Juky |
| `CachedModels.swift` | SwiftData entities for tracks, features, artists |

## Workout Templates (6 types)

| Template | Pattern | Description |
|----------|---------|-------------|
| Light | Mostly Easy | Recovery runs, ≤20% Moderate |
| Tempo | Mostly Strong | Sustained effort, 1-2 Hard spikes |
| HIIT | Easy↔Hard | Fartlek-style alternating |
| Intervals | Moderate↔Hard | Structured repeats |
| Pyramid | Mod→Strong→Hard→Max→... | Build up then down |
| Kicker | Base + final surge | End with Hard→Max ramp |

## Effort Tiers (5-tier system)

| Tier | BPM Window | Target Energy |
|------|------------|---------------|
| Easy | 150-165 | Capped at 0.70 |
| Moderate | 155-170 | Floor 0.35 |
| Strong | 160-178 | Floor 0.45 |
| Hard | 168-186 | Floor 0.55 |
| Max | 172-190 | Floor 0.65 |

## Build Commands

```bash
# Build the project (from RunClub/ subdirectory)
cd RunClub && xcodebuild -scheme RunClub -destination 'platform=iOS Simulator,id=4046DAA2-6CA0-472F-9875-07DEFD249326' build

# Run tests
cd RunClub && xcodebuild -scheme RunClub -destination 'platform=iOS Simulator,id=4046DAA2-6CA0-472F-9875-07DEFD249326' test
```

**Note**: XcodeBuildMCP is configured for automated builds. After code changes, verify the build compiles successfully.

## Development Guidelines

### Git Workflow
- **Work directly on main**: Do not create feature branches. All work happens on the `main` branch.
- **Commit frequently**: Make small, focused commits directly to main
- **Push after commits**: Push to origin/main after completing work

### Always Do
- **Read before editing**: Always read a file before modifying it
- **Verify builds**: After code changes, confirm the project builds
- **Discuss changes**: Have a conversation before making significant changes
- **Follow existing patterns**: Match the style of surrounding code
- **Check ALGORITHM_SPEC.md**: The generation algorithm spec is authoritative

### Code Style
- SwiftUI with MVVM pattern
- Use `@MainActor` for ObservableObjects
- Prefer `async/await` over callbacks
- Feature-first file organization

### Testing Approach
- Primary testing is manual on-device
- Generation quality is evaluated against ALGORITHM_SPEC.md criteria
- Future: Agentic evaluation of generated playlists against spec benchmarks

## Data Flow

```
User selects template + duration + filters
    ↓
LocalGenerator.swift builds effort curve from template
    ↓
Scores tracks from SwiftData cache (likes + playlists + third-source)
    ↓
Selects tracks matching tempo/energy for each slot
    ↓
Creates Spotify playlist via SpotifyService
    ↓
RunOrchestrator manages playback phases during run
```

## Data Sources (3-tier priority)

1. **Liked tracks** - User's Spotify likes (primary, highest scoring bonus)
2. **Playlist tracks** - User's owned/followed playlists
3. **Third-source catalog** - Pre-built database for thin filter coverage

All sources stored in SwiftData with audio features from ReccoBeats.

## Common Tasks

### Adding a new feature
1. Create files under appropriate `Features/` folder
2. Follow existing MVVM patterns
3. Wire into navigation from `RootView.swift` or `HomeView.swift`

### Modifying generation algorithm
1. Read `ALGORITHM_SPEC.md` first
2. Update spec if changing behavior
3. Test with multiple templates/durations
4. Verify tempo fitting and effort curves

### Debugging playlists
- Check `LocalGenerator.swift` for scoring logic
- Verify SwiftData cache has audio features (ReccoBeats)
- Review tier-specific tempo windows and energy constraints

## External Services

| Service | Purpose | Rate Limits |
|---------|---------|-------------|
| Spotify Web API | Auth, playlist creation, library access | ~2-3 req/sec, 429 backoff |
| ReccoBeats | Audio features (tempo, energy, etc.) | ≤40 IDs per batch |

## Library Cache & Crawling

The app caches user's Spotify library locally to enable fast, offline-capable generation:

- **Triggers**: After Spotify connect when cache empty or partial
- **Process**: Pages `/v1/me/tracks`, fetches audio features via ReccoBeats, batch-fetches artist details
- **Throttling**: ~2-3 req/sec with exponential backoff on 429s
- **Resumable**: Tracks progress in CrawlState; survives app restarts
- **UI**: Global progress toast during crawl; Settings shows counts and refresh option

## Known Limitations

- No native PKCE auth (uses Juky web flow)
- No HealthKit integration (CoreLocation only)
- No offline/Watch support yet
- `popularity` field is stored but never used in scoring

## File Locations

- **Project root**: `/Users/cvivadelli/Documents/RunClubApp/`
- **Xcode project**: `RunClub/RunClub.xcodeproj`
- **App source**: `RunClub/`
- **App entry point**: `RunClub/RunClub/` (RunClubApp.swift, RootView.swift)
- **Tests**: `RunClub/RunClubTests/`, `RunClub/RunClubUITests/`

## Future Ideas

Track planned features and improvements here:

- **User-tunable rediscovery ratio** (30–70%): Adjust rediscovery bias; default 50%
- **Personal affinity feedback**: Thumbs up/down and skip signals folded into scoring with decay
- **Genre-aware scoring refinements**: Incorporate speechiness/loudness for rap/metal/lofi cases
- **Transition smoothness**: Prefer adjacent tracks with compatible musical key and small energy deltas
- **HealthKit adaptivity**: Optional live pace/HR feedback to adjust slot targets
- **Offline and Watch support**: Pre-generate multiple runs; watchOS app for on-wrist controls
- **Social/sharing**: Share playlists, streaks, opt-in leaderboards
- **Advanced diversity**: Beyond 10-day lookback; artist/label/region diversity; user allow/deny lists
- **Template editor**: Power-user tool to design custom effort curves
- **Weekly scheduling**: A/B week structure with template rotation based on runs/week preference
