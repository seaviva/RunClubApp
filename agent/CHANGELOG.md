# Algorithm Changelog

This file tracks all changes made to the playlist generation algorithm, whether by the agent or manually. Each change includes a version number, date, rationale, and impact.

> **Format**: Changes are logged in reverse chronological order (newest first).
> Each version bump follows semver-ish conventions:
> - Major (X.0.0): Structural algorithm changes
> - Minor (0.X.0): New features or significant tuning
> - Patch (0.0.X): Small parameter adjustments

---

## [Unreleased]

_Changes staged but not yet committed._

---

## [1.0.0] - 2024-12-08

### Initial Version
- **Summary**: Baseline algorithm as implemented in LocalGenerator.swift
- **Components**:
  - 5-tier effort system (Easy, Moderate, Strong, Hard, Max)
  - Tempo-based scoring with half/double-time matching
  - Energy/danceability weighted scoring
  - Genre umbrella matching with neighbor broadening
  - 10-day track lockout, 50% rediscovery target
  - Per-artist caps and spacing bonuses
  - Template-specific effort curves
  - Duration planning with warmup/cooldown segments

### Baseline Metrics
- _To be filled after first comparison run_

---

## Change Template

When adding a new version, copy this template:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Summary
Brief description of what changed and why.

### Changes
- **Parameter**: `tierSpec.easy.tempoToleranceBPM` 15 → 18
  - Rationale: Easy slots were too strict, rejecting good tracks
  - Impact: +5% track pool for Easy slots

- **Code**: Modified scoring formula in `computeBonuses()`
  - Rationale: Artist spacing wasn't being weighted enough
  - Impact: Better artist variety in output

### Before/After Metrics
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Avg Score | 6.5 | 7.2 | +0.7 |
| Tempo Fit | 0.72 | 0.78 | +0.06 |
| ... | ... | ... | ... |

### Agent Session
- Session ID: abc123
- Iterations: 5
- Branch: agent/tempo_fitting_20241208
```

---

## Quick Reference

### Current Parameter Values

_Key tunable parameters and their current values:_

| Parameter | Value | Last Changed |
|-----------|-------|--------------|
| `tierSpec.easy.tempoToleranceBPM` | 15 | v1.0.0 |
| `tierSpec.easy.tempoFitMinimum` | 0.35 | v1.0.0 |
| `tierSpec.easy.weights` | (0.65, 0.25, 0.10) | v1.0.0 |
| `tempoWindow.easy` | (150, 165) | v1.0.0 |
| `bonus.recencyWeight` | 0.10 | v1.0.0 |
| `bonus.artistSpacingWeight` | 0.16 | v1.0.0 |
| `bonus.genreAffinityWeight` | 0.08 | v1.0.0 |

### Version History Summary

| Version | Date | Focus | Score Delta |
|---------|------|-------|-------------|
| 1.0.0 | 2024-12-08 | Initial | - |

---

## Notes

- All agent-made changes are committed to dedicated branches
- Use `git log --oneline --grep="[Agent]"` to see agent commits
- Metrics are computed from comparison batches (typically 10+ generations)
