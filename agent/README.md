# Playlist Generation Agent

A Claude-powered agent that iteratively improves the RunClub playlist generation algorithm.

## Overview

This agent system:
1. Runs playlist generations via a Swift CLI connected to your real data
2. Evaluates results against structured quality criteria
3. Auto-applies numeric parameter tuning
4. Flags structural changes for your approval
5. Tracks all changes in git with detailed rationale

## Setup

### Prerequisites

- Python 3.10+
- Swift 5.9+ (for CLI)
- Anthropic API key

### Installation

```bash
# From the RunClubApp directory

# 1. Set up Python environment
cd agent
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. Set your Anthropic API key
export ANTHROPIC_API_KEY="your-key-here"

# 3. Build the Swift CLI
cd ../cli
swift build -c release
```

### Data Requirements

The CLI needs access to your SwiftData stores. Either:
- Run the RunClub app at least once to create the data stores
- Or set `RUNCLUB_DATA_DIR` to point to your store files

## Usage

### Basic Usage

```bash
cd agent
source .venv/bin/activate

# Run with default settings (5 iterations, focus on overall improvement)
python run_agent.py

# Focus on a specific dimension
python run_agent.py --focus "tempo fitness"
python run_agent.py --focus "energy arc"

# Run more iterations
python run_agent.py --iterations 10
```

### Options

| Flag | Description |
|------|-------------|
| `--focus TEXT` | Focus area for improvements |
| `--iterations N` | Maximum improvement iterations |
| `--no-subjective` | Skip Claude subjective evaluation (faster) |
| `--manual-approve` | Require approval for all changes |
| `--dry-run` | Evaluate only, don't propose changes |
| `-v, --verbose` | Verbose output |

## How It Works

### 1. Generation

The agent runs playlist generations via the Swift CLI:

```
RunClubCLI generate --template tempo --minutes 30 --genres "Rock & Alt"
```

This outputs detailed JSON with:
- Track selection with effort assignments
- Scoring metrics (tempoFit, slotFit, etc.)
- Debug information

### 2. Evaluation

Each generation is evaluated on:

**Hard Requirements** (must pass):
- Duration within ±2 minutes
- Warmup/cooldown within targets
- Effort bookends (Easy start/end)
- No back-to-back same artist
- Per-artist caps

**Scoring Dimensions** (1-10):
- Tempo Fitness (25%)
- Energy Arc (25%)
- Slot Fitness (20%)
- Variety & Freshness (15%)
- Flow & Transitions (10%)
- Filter Adherence (5%)

### 3. Improvement

The agent proposes changes based on evaluation:

**Numeric Tuning** (auto-applied):
- Tempo tolerances
- BPM windows
- Scoring weights
- Bonus multipliers

**Structural Changes** (require approval):
- New scoring components
- Algorithm flow changes
- Pool building logic

### 4. Validation

All changes are:
- Tested with swift build
- Committed with detailed rationale
- Tracked in a dedicated branch

## Files

| File | Purpose |
|------|---------|
| `QUALITY_CRITERIA.md` | Defines what "good" means (user-editable) |
| `CHANGELOG.md` | Version-tracked history of all algorithm changes |
| `tunable_parameters.yaml` | Registry of tunable parameters |
| `config.py` | Paths and configuration |
| `models.py` | Data models |
| `runner.py` | CLI invocation |
| `evaluator.py` | Objective + subjective evaluation |
| `comparator.py` | Multi-generation comparison and pattern detection |
| `modifier.py` | Git-safe code modification |
| `changelog_manager.py` | Version tracking and changelog updates |
| `console_watcher.py` | Live log ingestion from app console |
| `orchestrator.py` | Main agent loop |
| `run_agent.py` | Entry point |

## Multi-Generation Comparison

The agent compares multiple generations to identify patterns:

```python
from comparator import run_comparison_batch

# Run batch and get analysis
report = run_comparison_batch(
    runner, evaluator,
    templates=["tempo", "hiit"],
    durations=[30, 45],
    runs_per_combo=3,  # Run each combo 3 times
)

# See track repetition, recurring issues, template reliability
```

## Live Console Log Ingestion

You can paste console logs from Xcode to get instant analysis:

```bash
python console_watcher.py
# Then paste your console output
```

Or watch logs automatically:

```python
from console_watcher import LiveAgentTrigger

trigger = LiveAgentTrigger(evaluator, modifier, changelog)
trigger.start_watching("/path/to/log/file")
```

## Version Tracking

All changes are logged to `CHANGELOG.md` with:
- Version numbers (semver-style)
- Before/after metrics
- Rationale for each change
- Session and branch references

View current version:
```python
from changelog_manager import ChangelogManager
print(ChangelogManager().get_current_version())
```

## Customizing Quality Criteria

Edit `QUALITY_CRITERIA.md` to tune what the agent optimizes for:

```markdown
## Hard Requirements
- Duration within target +/- 2 minutes
- ...

## Scoring Dimensions

### 1. Tempo Fitness (Weight: 25%)
What "good" looks like: ...
```

## Output

After each session:
- Report saved to `agent/reports/session_<id>.md`
- Changes committed to `agent/<focus>_<timestamp>` branch
- Generations logged to `agent/runs/`

## Safety

- All changes happen on a dedicated git branch
- Numeric tuning stays within defined ranges
- Structural changes require explicit approval
- Swift build validates changes compile
- Easy rollback via git
