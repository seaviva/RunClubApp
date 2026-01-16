## RunClub – Templates and Playlist Generation Algorithm

Scope: Authoritative specification for run template structure and the local playlist generation algorithm that uses SwiftData cache (Spotify liked tracks + ReccoBeats audio features + artist genres). This supersedes algorithm details in MASTER_PLAN.md.


### High-level goals:
	•	Uses template-tier tempo windows instead of user pace. Fixed BPM bands per effort tier still accept ½×/2× tempo so songs across genres can "feel" right without collecting cadence data.
	•	Builds runs as effort curves, not crude blocks. Warm-up/cooldown are reserved; Pyramid/Tempo/Waves are granular and ordered; Light avoids surges.
	•	Reduces repetition and boosts variety. 10-day lockout, artist spacing, genre/decade diversity bonus, and a rediscovery target (liked but unused ≥60 days) so playlists feel fresh.
	•	Fits duration reliably. It reserves WU/CD minutes, biases by template (Easy → shorter; Pyramid/Steady/Kicker → longer), then trims/extends edges to land within ±60s.
	•	Scores songs on fitness, not just rules. Slot scoring blends tempo fit with energy/danceability (and a proxy if tempo is missing), then samples from the top candidates with randomness to avoid sameness.
	•	Has graceful fallbacks. If a slot is thin, it widens tempo, allows adjacent effort, temporarily relaxes filters, and (once) can bend the 10-day rule without breaking artist spacing.
	•	Stays local and service-agnostic. Works entirely from your SwiftData cache (Spotify likes + ReccoBeats features) so you're not beholden to live API quirks.

### Gaps / polish to consider:
	•	You previously okayed rap/metal speechiness handling; current spec doesn't add speechiness or loudness into the EffortIndex (only energy/danceability/tempo). You could restore that small genre-aware tweak later.
	•	Rediscovery is fixed at 50% (good MVP). If you want a user-tunable "Likes vs New," fold it into the scoring weight.
	•	Danceability has no tier-specific constraints (no floor for high-intensity tiers, no cap for Easy). Consider adding shaping similar to energy.



### How the algorithm works (simple but accurate):
  Step 1 — Understand today's run.
    You choose a template (e.g., Long Waves). The app reserves 7–10 min warm-up and 5–8 min cool-down, then builds an effort curve (a target intensity per song) for the part in the middle. For example, Long Waves = EASY, EASY, HARD, HARD, repeated.
  Step 2 — Translate the template into tempo targets.
    Each effort tier has a predefined BPM window (e.g., EASY ≈ 150–165 BPM, HARD ≈ 168–186 BPM). Slots inherit those ranges so the generator keeps intensity curves consistent, and it still accepts half-time/double-time tempos (so ~82 or ~330 BPM can "feel" right).
  Step 3 — Build a candidate pool.
    From your liked tracks cache (with ReccoBeats features), it applies your genre/decade filters, tosses out anything used in the last 10 days, and tags rediscovery tracks (not used ≥60 days).
  Step 4 — Score each song for the current slot.
    For the slot you're filling, each candidate gets a score based on:
	•	  Tempo fit to the slot window (best of BPM, half-time, or double-time).
	•	  Energy & danceability (good movers score higher).
	•	  Bonuses/penalties for recent use, artist spacing (no back-to-back), genre/decade diversity, and (later) personal thumbs-up/down. If tempo is missing, it uses an energy/danceability proxy so those tracks can still compete.
  Step 5 — Pick with variety.
    It samples from the top few (not just #1) with a bit of randomness, so playlists don't repeat. It enforces rules like "no same artist twice in a row" and "max ~1 song per artist every ~20 minutes."
  Step 6 — If it gets stuck, relax intelligently.
    Not enough good options? It widens the tempo window a little, allows a neighboring effort level for a slot, temporarily relaxes your filter for that slot only, and—only once—can ignore the 10-day rule (still no artist collisions).
  Step 7 — Fit the runtime and finalize.
    It trims or adds an EASY/STEADY edge track to hit your time bracket within ±60s, rechecks the wave/pyramid order, confirms it starts/ends EASY, and then creates the playlist and logs usage so future runs stay fresh.


### Inputs and Preferences
- Filters (hard includes): genres (via artist genres), decades (via album year).
- Explicit: allowed.
- Recency lockout: 10 days (RunClub usage, not Spotify plays).
- Rediscovery: 50% target of playlist tracks are liked-but-unused ≥60 days or never used (best-effort if thin inventory).

### Data and Models (SwiftData)
- CachedTrack(id, name, artistId, artistName, durationMs, albumName, albumReleaseYear?, popularity?, explicit, addedAt)
  - Note: `popularity` is stored but **never used** in generation logic or filtering
- AudioFeature(trackId, tempo?, energy?, danceability?, valence?, loudness?, key?, mode?, timeSignature?)
- CachedArtist(id, name, genres:[String], popularity?)
  - Note: `popularity` is stored but **never used** in generation logic or filtering
- TrackUsage(trackId, lastUsedAt, usedCount) — RunClub-only usage state

#### Audio Features: Used vs Stored
| Field | Used in Generation? | How Used |
|-------|---------------------|----------|
| `tempo` | ✅ Yes | Core tempoFit scoring per tier; accepts ½× and 2× multiples |
| `energy` | ✅ Yes | EffortIndex blend + tier-specific energy shaping (caps/floors) |
| `danceability` | ✅ Yes | EffortIndex blend (no constraints, purely weighted) |
| `valence` | ❌ No | Stored only |
| `loudness` | ❌ No | Stored only |
| `key` | ❌ No | Stored only |
| `mode` | ❌ No | Stored only |
| `timeSignature` | ❌ No | Stored only |


---

## Hard Filters (Candidate Pool)

These completely **exclude** tracks from consideration (pass/fail):

| Filter | Requirement | Notes |
|--------|-------------|-------|
| **Audio Features** | Must have AudioFeature record | Tracks without ReccoBeats enrichment are excluded |
| **Playability** | `isPlayable == true` | Filters out unplayable/regional-locked tracks |
| **Duration Min** | ≥ 90 seconds (1:30) | Too short for a run segment |
| **Duration Max** | ≤ 360 seconds (6:00) | Too long; disrupts pacing |
| **Genre** | Artist genres must have affinity > 0 with selected umbrella(s) | Only applies if user selected genre filters |
| **Decade** | `albumReleaseYear` must fall in selected decade range(s) | Only applies if user selected decade filters |
| **10-day Lockout** | `TrackUsage.lastUsedAt` > 10 days ago OR never used | Prevents overplaying recent tracks |


---

## Effort Tiers (5-Tier System)

Each slot in the playlist has an effort tier that determines tempo targets, scoring weights, and energy shaping.

### Tier Specifications (from code)

| Tier | Target Effort | BPM Window | Tempo Tolerance | Min tempoFit Gate | Weights (tempo/energy/dance) |
|------|--------------|------------|-----------------|-------------------|------------------------------|
| **Easy** | 0.35 | 150–165 | ±18 BPM | 0.35 | 0.65 / 0.25 / 0.10 |
| **Moderate** | 0.48 | 155–170 | ±14 BPM | 0.42 | 0.62 / 0.28 / 0.10 |
| **Strong** | 0.60 | 160–178 | ±10 BPM | 0.50 | 0.60 / 0.30 / 0.10 |
| **Hard** | 0.72 | 168–186 | ±8 BPM | 0.55 | 0.58 / 0.32 / 0.10 |
| **Max** | 0.85 | 172–190 | ±6 BPM | 0.60 | 0.56 / 0.34 / 0.10 |

### Tempo Matching
- Accepts **BPM**, **½× BPM**, and **2× BPM** — uses the best match to the tier window
- `tempoFit = 1.0 - (distance_to_window / tolerance)`
- If tempo is missing: proxy = `(0.6 × energy + 0.4 × danceability) × 0.9`

### Energy Shaping (Soft Constraints)

| Tier | Energy Floor | Energy Cap | Effect |
|------|-------------|------------|--------|
| **Easy** | None | **0.70** | Energy > 0.70 → penalty up to **-0.12** (keeps warmup/cooldown chill) |
| **Moderate** | **0.35** | None | Energy < 0.35 → penalty up to -0.10 |
| **Strong** | **0.45** | None | Energy < 0.45 → penalty up to -0.10 |
| **Hard** | **0.55** | None | Energy < 0.55 → penalty up to -0.10 |
| **Max** | **0.65** | None | Energy < 0.65 → penalty up to -0.10 |

**Energy penalty formula (for floors):**
```
penalty = 0.10 × min(1.0, (floor - energy) / floor)
```

**Energy penalty formula (for Easy cap):**
```
penalty = 0.12 × min(1.0, (energy - 0.70) / 0.30)
```

### Danceability Handling
- **No constraints** — danceability has no floor or cap for any tier
- Purely contributes 10% weight to EffortIndex
- Gap: Consider adding similar shaping as energy in future


---

## Scoring System

### EffortIndex Calculation

```
EffortIndex = (wTempo × tempoFit) + (wEnergy × energy) + (wDance × danceability)
```

Where weights are tier-specific (see table above). Default energy/dance = 0.5 if missing.

### SlotFit Calculation

```
SlotFit = 1.0 - |EffortIndex - targetEffort|
```

### Base Score

```
baseScore = 0.60 × SlotFit - energyPenalty (if applicable)
```

### Bonus Components (added to baseScore)

| Bonus | Weight | Logic |
|-------|--------|-------|
| **Recency** | +0.10 max | Tracks not used recently get full bonus; decays linearly as approach 10-day boundary |
| **Artist Spacing** | +0.16 max | Full bonus if artist hasn't appeared recently in playlist; scales by distance (dist 1→0, dist 7+→full) |
| **Diversity** | +0.10 max | Prefers underrepresented genres/decades vs 10-day lookback and current playlist (split 50/50 genres/decades) |
| **Artist Novelty** | +0.08 max | Artists not used in >10 days get boost; never-used artists get +0.06 |
| **Genre Affinity** | +0.08 max | Higher affinity to selected umbrella(s) = higher bonus |
| **Umbrella Balance** | +0.12 / -0.05 | When multiple genres selected: bonus for underrepresented umbrella, penalty for over-represented |
| **Rediscovery Bias** | +0.05 max | Tracks unused ≥60 days get boosted toward 50% target (scales by how far behind target) |
| **Source Preference** | +0.03 | Likes and playlists get +0.03; third-source catalog gets +0.00 |

### Final Score

```
FinalScore = baseScore + recencyBonus + artistSpacingBonus + diversityBonus 
           + artistNoveltyBonus + genreAffinityBonus + umbrellaBalanceBonus 
           + rediscoveryBias + sourcePreference
```


---

## Selection Process

For each slot:
1. Score all candidates in the pool
2. Filter out candidates below minimum tempoFit gate for the tier
3. Apply energy shaping penalties
4. Take **top-K** candidates (K varies by tier: Easy=25, Moderate=15, others=8)
5. **Weighted random sample** from top-K (not just #1) to add variety
6. Enforce: no back-to-back same artist, max 2 per artist per playlist
7. Check playability; attempt alternate version swap if unplayable


---

## Warm‑up, Cooldown, and Duration Targets
- Reserve warm‑up at start and cooldown at end (both Easy tier).
- Typical shares: WU ≈ 20–25% of total, CD ≈ 15–20% of total.
- Duration policy (based on total minutes):
  - < 30 min: WU = 5 min, CD = 5 min
  - 30–45 min: WU = 7 min, CD = 5 min
  - > 45 min: WU = 10 min, CD = 7 min

### Template duration targets (minutes → WU/Core/CD):
  - Light — Short 20–22 → 4/13/3; Medium 32–35 → 6/22/6; Long 47–50 → 8/34/8
  - Tempo — Short 25 → 5/15/5; Medium 38–40 → 7/25/7; Long 55 → 9/37/9
  - HIIT — Short 26–28 → 5/17/4; Medium 38–40 → 7/25/6; Long 50–52 → 9/34/8
  - Intervals — Short 28–30 → 6/18/5; Medium 43–45 → 8/29/8; Long 58–60 → 10/40/10
  - Pyramid — Short 27–28 → 5/17/5; Medium 40–42 → 7/26/7; Long 55–57 → 9/37/9
  - Kicker — Short 25–26 → 5/15/5; Medium 38–40 → 7/25/7; Long 52–54 → 9/35/8


---

## Templates as Tier Curves (adapts to run length)
- Light: mostly Easy; allow ≤20% low‑end Moderate in middle.
- Tempo: mostly Strong; optionally 1–2 low‑end Hard spikes; no Max.
- HIIT: strict alternation Easy↔Hard (one song each); start with Hard if warm‑up ended Easy to avoid Easy→Easy; no Max in first cycle; allow ≤1 Max only near the end (replacing a Hard) if long enough; Easy anchors between Hards.
- Intervals: repeat Moderate↔Hard; slightly tighter than HIIT (start Moderate; fewer Hards; no Max).
- Pyramid: Moderate → Strong → Hard → Max → Hard → Strong → Moderate; if short, drop Max first; if very short, Strong as peak.
- Kicker: Moderate/Strong base; final ramp to Hard then Max; at most 1 Max and ≤2 Hard; for short runs end at Hard only.


---

## Thin‑Slot Relaxations (in order)

When a slot has too few viable candidates:

1. **Adjacent tier spillover (±1)**: Re-score with neighboring effort tier; require slotFit ≥ 0.70
2. **Second-adjacent tier (±2)**: If still thin, try ±2 tiers; require slotFit ≥ 0.65
3. **Neighbor umbrella broadening**: Expand genre filter to include neighbor umbrellas (weight ~0.6) for this slot only; max 2 slots per playlist
4. **10-day lockout break**: Allow one track within lockout window per playlist (still enforce artist spacing)


---

## Rediscovery Quota
- Maintain a running 50% rediscovery target across the playlist
- Rediscovery = tracks with `lastUsedAt` ≥ 60 days ago OR never used
- Rediscovery bias bonus scales with how far below target the playlist currently is
- If inventory remains thin after relaxations, degrade gracefully without failing


---

## Duration Fit and Polish
- Target: playlist duration within ±2 minutes of selected run length
- Trim from end if over; add Easy tail tracks if under
- Segment-aware gating: WU and CD each stay within ±60s of target
- Final validations: start Easy, end Easy; enforce template curve ordering; no artist collisions


---

## Output and Persistence
- Create public playlist named: "RunClub · [Template] [MM/DD]"
- Description includes template + duration summary
- Persist TrackUsage for selected tracks: `lastUsedAt = now; usedCount += 1`
- Log metrics: tempo-fit %, rediscovery %, artist spacing, segment durations, source breakdown


---

## Defaults and Fallback
- Algorithm operates entirely on SwiftData cache (likes + playlists + third-source catalog)
- Remote fallbacks (e.g., Spotify recommendations API) are **not used** in local generation
- Source priority: likes preferred, then playlists database, then third-source catalog
