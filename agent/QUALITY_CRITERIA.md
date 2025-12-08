# Playlist Quality Criteria

This document defines what makes a "good" playlist generation. The agent references this during evaluation, and you can tune these criteria over time as you learn what works best.

> **Note to Agent**: Follow these criteria as the primary source of truth. Use your own reasoning to catch issues not explicitly documented here, but always call out when you're applying judgment beyond these written rules.

---

## Hard Requirements (Must Pass)

These are non-negotiable. A generation that fails any of these is considered a failure regardless of other scores.

### Duration Compliance
- Total playlist duration must be within **±2 minutes** of the target run time
- Example: A 30-minute target must produce 28-32 minutes of music

### Segment Duration
- **Warmup segment**: Must be within ±60 seconds of the template's target
  - Short runs (<30 min): 5 min target
  - Medium runs (30-45 min): 7 min target  
  - Long runs (>45 min): 10 min target
- **Cooldown segment**: Must be within ±60 seconds of the template's target
  - Short runs: 5 min target
  - Medium/Long runs: 5-7 min target

### Effort Bookends
- First track(s) in warmup must be **Easy** effort
- Last track(s) in cooldown must be **Easy** effort
- No Hard or Max efforts in warmup or cooldown segments

### Artist Constraints
- **No back-to-back same artist** - Never two consecutive tracks by the same artist
- **Per-artist cap**: Maximum 2 tracks per artist in any playlist
- **Artist spacing**: Ideally 4+ tracks between same-artist appearances

### Track Constraints
- No track longer than 6 minutes
- No track shorter than 1 minute 30 seconds
- All tracks must be playable in the user's market

### Data Source Priority
- **Primary**: User's liked songs - these are explicit preferences
- **Secondary**: User's selected playlists - curated collections they enjoy
- **Tertiary (Backup)**: Third-source database - use when:
  - Discoverability is desired and user needs fresh music
  - No good matches exist in primary/secondary sources for a slot
  - Filling gaps in specific tempo/energy ranges
- When using backup sources, try to match user's general taste profile (genres, decades, energy preferences observed in their library)

### Default Preferences (No Filters Applied)
- **Decade preference**: Lean towards more modern music (2010s, 2020s) unless user's library clearly skews older
- **Energy-Effort alignment**: Critical requirement
  - Higher effort tiers (Hard, Max) → Higher energy tracks required
  - Lower effort tiers (Easy) → Lower energy tracks help calm the runner
  - Mismatched energy/effort is worse than mismatched tempo

---

## Scoring Dimensions (1-10 Scale)

Each dimension is scored independently. The overall quality score is a weighted average.

### 1. Tempo Fitness (Weight: 25%)

**What "good" looks like:**
- Each track's tempo falls within the appropriate BPM window for its effort tier
- Half-time (÷2) and double-time (×2) tempos are acceptable matches
- Average tempoFit score across all tracks ≥ 0.70

**Effort tier BPM windows:**
- Easy: 150-165 BPM (tolerance ±15)
- Moderate: 155-170 BPM (tolerance ±12)
- Strong: 160-178 BPM (tolerance ±10)
- Hard: 168-186 BPM (tolerance ±8)
- Max: 172-190 BPM (tolerance ±6)

**Scoring guide:**
- 10: Average tempoFit ≥ 0.85, no track below 0.60
- 8-9: Average tempoFit ≥ 0.75, at most 1 track below 0.50
- 6-7: Average tempoFit ≥ 0.65, some tempo mismatches but generally appropriate
- 4-5: Noticeable tempo mismatches, several tracks feel wrong for their slots
- 1-3: Tempo largely ignored, tracks randomly placed regardless of BPM

**Common failures:**
- Easy slots with high-tempo tracks that feel too intense
- Hard slots with low-energy tracks that don't drive effort
- Ignoring half-time/double-time matches when they'd work better

---

### 2. Energy Arc (Weight: 25%)

**What "good" looks like:**
- Energy flows naturally through the run, matching the template's intended effort curve
- Warmup gradually builds energy
- Core section follows template pattern (e.g., HIIT alternates, Tempo sustains)
- Cooldown winds down progressively

**Template-specific expectations:**
- **Light**: Gentle throughout, minimal intensity variation, meditative flow
- **Tempo**: Sustained moderate-high energy with 1-2 brief peaks
- **HIIT**: Sharp alternation between recovery and intensity, clear contrast
- **Intervals**: Regular cycling between moderate and hard efforts
- **Pyramid**: Clear build-up to peak, then symmetric descent
- **Kicker**: Gradual build with dramatic final push

**Scoring guide:**
- 10: Energy arc perfectly matches template intent, every transition feels natural
- 8-9: Arc is correct with minor imperfections in 1-2 transitions
- 6-7: General shape is right but some jarring transitions or flat sections
- 4-5: Template pattern is recognizable but poorly executed
- 1-3: No discernible arc, random energy distribution

**Common failures:**
- Warmup that's too intense too fast
- Cooldown that doesn't actually cool down
- HIIT without clear contrast between easy and hard
- Pyramid that peaks too early or too late

---

### 3. Slot Fitness (Weight: 20%)

**What "good" looks like:**
- Each track's combined effort index (tempo + energy + danceability) matches its slot's target
- Average slotFit score ≥ 0.75
- Hard slots actually feel hard; Easy slots actually feel easy

**Scoring guide:**
- 10: Average slotFit ≥ 0.85, every track feels right for its position
- 8-9: Average slotFit ≥ 0.75, minor mismatches don't disrupt the run
- 6-7: Average slotFit ≥ 0.65, some slots feel off but overall structure works
- 4-5: Multiple slots with wrong-feeling tracks
- 1-3: Slot assignments seem random

**Common failures:**
- "Hard" slots filled with chill tracks (high tempo but low energy)
- "Easy" slots with intense tracks (low tempo but high energy/danceability)
- Ignoring energy component when tempo matches

---

### 4. Variety & Freshness (Weight: 15%)

**What "good" looks like:**
- ~50% rediscovery tracks (liked but unused ≥60 days)
- Good genre distribution within selected umbrella(s)
- Decade spread when multiple decades selected
- No repetitive same-vibe sequences

**Scoring guide:**
- 10: 45-55% rediscovery, excellent genre/decade variety, every track feels fresh
- 8-9: 35-55% rediscovery, good variety, maybe 1-2 tracks feel predictable
- 6-7: 25-45% rediscovery, acceptable variety, some sameness
- 4-5: <25% rediscovery or significant genre/decade clustering
- 1-3: Playlist feels like same songs as always, heavy repetition

**Common failures:**
- Over-relying on frequently-used favorites
- All tracks from same sub-genre despite broad umbrella selection
- Ignoring decade filters or clustering in one decade

---

### 5. Flow & Transitions (Weight: 10%)

**What "good" looks like:**
- Adjacent tracks feel like they belong together
- No jarring genre whiplash (unless intentional for effort change)
- BPM changes between tracks are smooth (±10 BPM between adjacent tracks ideal)

**Scoring guide:**
- 10: Playlist flows like a curated DJ set, every transition feels intentional
- 8-9: Smooth flow with 1-2 slightly awkward transitions
- 6-7: Generally coherent but some jarring moments
- 4-5: Several transitions feel random or disruptive
- 1-3: No sense of flow, tracks feel randomly shuffled

**Common failures:**
- Acoustic folk → aggressive EDM with no buffer
- 40 BPM jumps between consecutive tracks
- Genre whiplash that isn't motivated by effort tier change

---

### 6. Filter Adherence (Weight: 5%)

**What "good" looks like:**
- All tracks match at least one selected genre umbrella (or neighbor)
- All tracks match at least one selected decade
- When filters are applied, they're respected consistently

**Scoring guide:**
- 10: 100% of tracks match all applied filters
- 8-9: 95%+ match, any exceptions are close neighbors
- 6-7: 85%+ match, some borderline cases
- 4-5: Noticeable filter violations
- 1-3: Filters largely ignored

**Common failures:**
- Neighbor umbrella tracks dominating over primary selections
- Wrong-decade tracks sneaking in
- Relaxation rules applied too liberally

---

## Template-Specific Quality Checks

Beyond the general dimensions, each template has specific quality markers:

### Light
- [ ] No track exceeds 0.70 energy
- [ ] No effort tier above Moderate (and Moderate ≤20% of core)
- [ ] Consistent "easy run" vibe throughout

### Tempo
- [ ] Core section sustains Strong effort consistently
- [ ] At most 2 Hard spikes, no Max
- [ ] Feels like a sustained threshold run

### HIIT
- [ ] Clear Easy↔Hard alternation visible in track sequence
- [ ] Each "Hard" slot actually feels significantly more intense than adjacent "Easy"
- [ ] At most 1 Max slot (near end only, if long enough)

### Intervals
- [ ] Regular Moderate↔Hard cycling
- [ ] Pattern is consistent, not random
- [ ] No Max slots

### Pyramid
- [ ] Clear build-up phase (Moderate → Strong → Hard → Max)
- [ ] Peak at or near middle of core section
- [ ] Symmetric (or near-symmetric) descent

### Kicker
- [ ] Gradual build through Moderate/Strong base
- [ ] Final 2-3 tracks ramp to Hard then Max
- [ ] "Finish strong" energy unmistakable

---

## Subjective Considerations

These are harder to quantify but the agent should consider:

### "Would I want to run to this?"
- Does the playlist feel motivating?
- Are there any tracks that would make you want to skip?
- Does the overall vibe match the run intent?

### Musical Coherence
- Do these tracks feel like they belong in the same playlist?
- Is there a sonic through-line even across genres?

### Surprise & Delight
- Are there any tracks that would make a runner smile?
- Is there a good balance of familiar favorites and fresh discoveries? Consider the source of the songs from the different databases and how this could impact this.

---

## Changelog

_Document changes to these criteria as you learn what works:_

| Date | Change | Rationale |
|------|--------|-----------|
| Initial | Created document | Baseline criteria based on ALGORITHM_SPEC.md |

---

## Notes for Tuning

If you find yourself consistently scoring low on a dimension, consider:

1. **Tempo Fitness low**: May need to adjust BPM windows or tolerance values
2. **Energy Arc issues**: Check effort curve construction in template definitions
3. **Slot Fitness problems**: Review tier weights (tempo/energy/dance blend)
4. **Variety lacking**: Adjust rediscovery bias or diversity bonuses
5. **Flow issues**: Consider adding transition smoothness to scoring
6. **Filter problems**: Review relaxation thresholds

Add notes here as you discover patterns.
