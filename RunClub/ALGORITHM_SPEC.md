## RunClub – Templates and Playlist Generation Algorithm

Scope: Authoritative specification for run template structure and the local playlist generation algorithm that uses SwiftData cache (Spotify liked tracks + ReccoBeats audio features + artist genres). This supersedes algorithm details in MASTER_PLAN.md.


### High-level goals:
	•	Uses template-tier tempo windows instead of user pace. Fixed BPM bands per effort tier still accept ½×/2× tempo so songs across genres can “feel” right without collecting cadence data.  ￼
	•	Builds runs as effort curves, not crude blocks. Warm-up/cooldown are reserved; Pyramid/Tempo/Waves are granular and ordered; Light avoids surges.  ￼
	•	Reduces repetition and boosts variety. 10-day lockout, artist spacing, genre/decade diversity bonus, and a rediscovery target (liked but unused ≥60 days) so playlists feel fresh.  ￼
	•	Fits duration reliably. It reserves WU/CD minutes, biases by template (Easy → shorter; Pyramid/Steady/Kicker → longer), then trims/extends edges to land within ±60s.  ￼
	•	Scores songs on fitness, not just rules. Slot scoring blends tempo fit with energy/danceability (and a proxy if tempo is missing), then samples from the top candidates with randomness to avoid sameness.  ￼
	•	Has graceful fallbacks. If a slot is thin, it widens tempo, allows adjacent effort, temporarily relaxes filters, and (once) can bend the 10-day rule without breaking artist spacing.  ￼
	•	Stays local and service-agnostic. Works entirely from your SwiftData cache (Spotify likes + ReccoBeats features) so you’re not beholden to live API quirks.  ￼

### Gaps / polish to consider:
	•	You previously okayed rap/metal speechiness handling; current spec doesn’t add speechiness or loudness into the EffortIndex (only energy/danceability/tempo). You could restore that small genre-aware tweak later.  ￼
	•	Rediscovery is fixed at 50% (good MVP). If you want a user-tunable “Likes vs New,” fold it into the scoring weight.
  - consider different scoring weighting for different effort buckets, for instance Chill but steady tracks with medium danceability (like lo-fi hip hop, acoustic pop with a beat) could now score well in Easy bucket whereas right now they might not because they are considered too danceable)  ￼



### How the algorithm works (simple but accurate):
  Step 1 — Understand today’s run.
    You choose a template (e.g., Long Waves). The app reserves 7–10 min warm-up and 5–8 min cool-down, then builds an effort curve (a target intensity per song) for the part in the middle. For example, Long Waves = EASY, EASY, HARD, HARD, repeated.  ￼
  Step 2 — Translate the template into tempo targets.
    Each effort tier has a predefined BPM window (e.g., EASY ≈ 150–165 BPM, HARD ≈ 168–186 BPM). Slots inherit those ranges so the generator keeps intensity curves consistent, and it still accepts half-time/double-time tempos (so ~82 or ~330 BPM can “feel” right).  ￼
  Step 3 — Build a candidate pool.
    From your liked tracks cache (with ReccoBeats features), it applies your genre/decade filters, tosses out anything used in the last 10 days, and tags rediscovery tracks (not used ≥60 days).  ￼
  Step 4 — Score each song for the current slot.
    For the slot you’re filling, each candidate gets a score based on:
	•	  Tempo fit to the slot window (best of BPM, half-time, or double-time).
	•	  Energy & danceability (good movers score higher).
	•	  Bonuses/penalties for recent use, artist spacing (no back-to-back), genre/decade diversity, and (later) personal thumbs-up/down. If tempo is missing, it uses an energy/danceability proxy so those tracks can still compete.  ￼
  Step 5 — Pick with variety.
    It samples from the top few (not just #1) with a bit of randomness, so playlists don’t repeat. It enforces rules like “no same artist twice in a row” and “max ~1 song per artist every ~20 minutes.”  ￼
  Step 6 — If it gets stuck, relax intelligently.
    Not enough good options? It widens the tempo window a little, allows a neighboring effort level for a slot, temporarily relaxes your filter for that slot only, and—only once—can ignore the 10-day rule (still no artist collisions).  ￼
  Step 7 — Fit the runtime and finalize.
    It trims or adds an EASY/STEADY edge track to hit your time bracket within ±60s, rechecks the wave/pyramid order, confirms it starts/ends EASY, and then creates the playlist and logs usage so future runs stay fresh.  ￼


### Inputs and Preferences
- Filters (hard includes): genres (via artist genres), decades (via album year).
- Explicit: allowed.
- Recency lockout: 10 days (RunClub usage, not Spotify plays).
- Rediscovery: 50% target of playlist tracks are liked-but-unused ≥60 days or never used (best-effort if thin inventory).

### Data and Models (SwiftData)
- CachedTrack(id, name, artistId, artistName, durationMs, albumName, albumReleaseYear?, popularity?, explicit, addedAt)
- AudioFeature(trackId, tempo?, energy?, danceability?, valence?, loudness?, key?, mode?, timeSignature?)
- CachedArtist(id, name, genres:[String], popularity?)
- TrackUsage(trackId, lastUsedAt, usedCount) — new, RunClub-only usage state

### Effort tiers (5-tier) and tempo targets
- Tiers: Easy, Moderate, Strong, Hard, Max. Each slot specifies a tier and target effort (0–1). Warm‑up and Cooldown are Easy.
- Each tier maps to a fixed BPM window; accept ½× and 2× multiples as valid tempo matches.
  - Easy: wider window; tolerance ≈ ±15 BPM; targetEffort ≈ 0.35
  - Moderate: ±12 BPM; targetEffort ≈ 0.48
  - Strong: ±10 BPM; targetEffort ≈ 0.60
  - Hard: ±8 BPM; targetEffort ≈ 0.72
  - Max: ±6 BPM (short slots only; capped); targetEffort ≈ 0.85
- If tempo missing, compute a tempoFit proxy from energy+danceability (proxyScore = 0.6×energy + 0.4×danceability) and use that in place of tempoFit so missing tempo isn’t punished.

### Warm‑up, Cooldown, and Duration Targets
- Reserve warm‑up at start and cooldown at end (both Easy). Use template‑specific targets per category; keep small flexibility (≈±1 track) at selection time to fit within bounds.
- Typical shares: WU ≈ 20–25% of total, CD ≈ 15–20% of total.
- Template duration targets (minutes → WU/Core/CD):
  - Light — Short 20–22 → 4/13/3; Medium 32–35 → 6/22/6; Long 47–50 → 8/34/8
  - Tempo — Short 25 → 5/15/5; Medium 38–40 → 7/25/7; Long 55 → 9/37/9
  - HIIT — Short 26–28 → 5/17/4; Medium 38–40 → 7/25/6; Long 50–52 → 9/34/8
  - Intervals — Short 28–30 → 6/18/5; Medium 43–45 → 8/29/8; Long 58–60 → 10/40/10
  - Pyramid — Short 27–28 → 5/17/5; Medium 40–42 → 7/26/7; Long 55–57 → 9/37/9
  - Kicker — Short 25–26 → 5/15/5; Medium 38–40 → 7/25/7; Long 52–54 → 9/35/8
- Duration bias by template: Light leans shorter; Tempo / Pyramid / Kicker lean longer; Waves centered (Intervals slightly longer).

### Templates as Tier Curves (adapts to run length)
- Light: mostly Easy; allow ≤20% low‑end Moderate in middle.
- Tempo: mostly Strong; optionally 1–2 low‑end Hard spikes; no Max.
- HIIT: strict alternation Easy↔Hard (one song each); start with Hard if warm‑up ended Easy to avoid Easy→Easy; no Max in first cycle; allow ≤1 Max only near the end (replacing a Hard) if long enough; Easy anchors between Hards.
- Intervals: repeat Moderate↔Hard; slightly tighter than HIIT (start Moderate; fewer Hards; no Max).
- Pyramid: Moderate → Strong → Hard → Max → Hard → Strong → Moderate; if short, drop Max first; if very short, Strong as peak.
- Kicker: Moderate/Strong base; final ramp to Hard then Max; at most 1 Max and ≤2 Hard; for short runs end at Hard only.

### Candidate Pool
- Start from liked CachedTrack joined with AudioFeature and CachedArtist.
- Apply hard filters: selected genres/decades.
- Genre includes now use JSON umbrella mapping with neighbors. Each track gets a per‑artist GenreAffinity ∈ [0,1] computed against selected umbrella ids (weight 1.0) and their neighbors (weight ~0.6). Artists pass the genre filter if affinity > 0 when user selected any umbrella; otherwise genre is not restricting.
- Enforce constraints: duration ≤ 6 min; 10‑day lockout via TrackUsage.
- Tag rediscovery eligible: lastUsedAt ≥ 60 days ago or never used.

### Scoring and Selection
- EffortIndex = tier‑weighted blend (tempo/energy/dance) with tier‑specific weights (e.g., Easy 0.65/0.25/0.10; Strong 0.60/0.30/0.10). Tier sets tempo tolerance, minimum tempoFit gates, and energy shaping (Easy caps high energy; higher tiers have soft energy floors).
  - tempoFit = closeness to the tier BPM window using min distance to the window, ½×, or 2×; if tempo missing, use proxy (0.6×energy+0.4×danceability).
- SlotFit = 1 − |EffortIndex − targetEffort|
- Final Score (per slot) = 0.60×SlotFit + 0.10×(1 − RecencyPenalty) + 0.10×ArtistSpacing + 0.10×Diversity + 0.08×GenreAffinity + 0.02×PersonalAffinity
  - RecencyPenalty grows as track nears 10‑day boundary (0 when far in past; capped to avoid over‑penalizing rediscovery).
  - ArtistSpacing: bonus if not used recently in playlist; forbid back‑to‑back; soft ~1 per 20 min; hard max 2 per playlist.
  - Diversity (Option 2): 10‑day lookback using TrackUsage.lastUsedAt. On‑the‑fly join genres/decades of those tracks; prefer underrepresented genres/decades vs this 10‑day window and vs current playlist‑in‑progress (small additive bonus).
  - PersonalAffinity: stub 0 for now; future hook for 👍/👎 feedback.
- Selection per slot: sample from top‑K=8 with temperature=0.7; respect no back‑to‑back artist and 6‑min max.

### Thin‑Slot Relaxations (in order)
1) Allow adjacent tier (±1) substitution for that slot; if still thin, allow ±2; cap relaxed slots per playlist.
2) Widen tempo window slightly within tier bounds (do not drop tier minimum tempoFit gate).
3) Broaden to neighbor umbrellas for that slot only (keep decades). Use neighbor weight (~0.6) when computing GenreAffinity.
4) If still thin, allow breaking the 10‑day lockout once (still no back‑to‑back artist).

### Rediscovery Quota
- Maintain a running 50% rediscovery target across the playlist; choose rediscovery when candidates are comparable. If inventory remains thin after relaxations, degrade gracefully without failing the generation.

### Duration Fit and Polish
- Compute target track count from selected bracket minus reserved WU/CD minutes.
- Hit bracket ±60s by nudging EASY/STEADY edges; never exceed category bounds.
- Final validations: start EASY, end EASY; enforce template curve (waves/pyramid ordering); no artist collisions; per‑artist caps and duplicate avoidance.

### Output and Persistence
- Create public playlist named: “RunClub · [Template] [MM/DD]”. Description includes template + duration summary.
- Persist TrackUsage for selected tracks: lastUsedAt = now; usedCount += 1.
- Log metrics for iteration: tempo‑fit %, rediscovery %, artist spacing (avg minutes), 10‑day compliance, per‑track scores.

### Defaults and Fallback
- Algorithm operates entirely on SwiftData cache. Remote fallbacks (e.g., Spotify recommendations) are not used in this local path; only consider remote if the local pool is empty after relaxations.


