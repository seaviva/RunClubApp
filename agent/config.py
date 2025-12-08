"""
Configuration for the Playlist Generation Agent.

This module defines paths, API settings, and other configuration values.
"""

import os
from pathlib import Path

# =============================================================================
# Paths
# =============================================================================

# Project root (RunClubApp directory)
PROJECT_ROOT = Path(__file__).parent.parent

# Agent directory
AGENT_DIR = Path(__file__).parent

# Swift CLI directory
CLI_DIR = PROJECT_ROOT / "cli"

# Swift source files
SWIFT_SOURCES = PROJECT_ROOT / "RunClub"
LOCAL_GENERATOR_PATH = SWIFT_SOURCES / "Features" / "Generation" / "LocalGenerator.swift"
SPOTIFY_SERVICE_PATH = SWIFT_SOURCES / "Services" / "SpotifyService.swift"

# Quality criteria document
QUALITY_CRITERIA_PATH = AGENT_DIR / "QUALITY_CRITERIA.md"

# Tunable parameters registry
TUNABLE_PARAMS_PATH = AGENT_DIR / "tunable_parameters.yaml"

# Output directories
RUNS_DIR = AGENT_DIR / "runs"
REPORTS_DIR = AGENT_DIR / "reports"

# =============================================================================
# SwiftData Store Locations
# =============================================================================

# iOS Simulator data directory (set after running app in simulator)
# This path is auto-detected but can be overridden via environment variable
SIMULATOR_DATA_DIR = os.environ.get(
    "RUNCLUB_DATA_DIR",
    str(Path.home() / "Library/Developer/CoreSimulator/Devices/37CD2C44-9234-4180-B737-33F41C3CCB3D/data/Containers/Data/Application/86C0DE83-B9AF-4F40-B4D6-976C7AF8BA07/Library/Application Support")
)

def get_app_container_path() -> Path:
    """Get the app's container path where SwiftData stores live."""
    # First check the configured simulator path
    if SIMULATOR_DATA_DIR and Path(SIMULATOR_DATA_DIR).exists():
        return Path(SIMULATOR_DATA_DIR)
    
    home = Path.home()
    
    # Try the standard app container location
    app_container = home / "Library" / "Containers" / "com.runclub.app" / "Data"
    if app_container.exists():
        return app_container
    
    # Fallback to looking in Library/Application Support
    app_support = home / "Library" / "Application Support" / "RunClub"
    if app_support.exists():
        return app_support
    
    raise FileNotFoundError(
        "Could not locate SwiftData stores. "
        "Please run the app at least once to create the data stores."
    )

# Store file names (SwiftData uses .store extension)
LIKES_STORE = "default.store"
PLAYLISTS_STORE = "playlists.store"  
THIRD_SOURCE_STORE = "thirdsource.store"

# =============================================================================
# API Configuration
# =============================================================================

# Anthropic API key (from environment)
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# Model to use for evaluation and reasoning
CLAUDE_MODEL = "claude-sonnet-4-20250514"

# Model for simpler tasks (cost optimization)
CLAUDE_MODEL_FAST = "claude-sonnet-4-20250514"

# =============================================================================
# Agent Behavior
# =============================================================================

# Maximum iterations per agent run
MAX_ITERATIONS = 10

# Number of generations to run per evaluation batch
GENERATIONS_PER_BATCH = 5

# Templates to test (cycle through these)
TEMPLATES = ["light", "tempo", "hiit", "intervals", "pyramid", "kicker"]

# Duration options to test (minutes)
DURATIONS = [20, 30, 45, 60]

# Git branch prefix for agent changes
GIT_BRANCH_PREFIX = "agent/"

# Commit message prefix
GIT_COMMIT_PREFIX = "[Agent]"

# =============================================================================
# Scoring Thresholds
# =============================================================================

# Minimum overall score to consider a generation "good"
MIN_ACCEPTABLE_SCORE = 6.0

# Score improvement threshold to commit a change
MIN_IMPROVEMENT_DELTA = 0.1

# Dimension weights (must sum to 1.0)
DIMENSION_WEIGHTS = {
    "tempo_fitness": 0.25,
    "energy_arc": 0.25,
    "slot_fitness": 0.20,
    "variety": 0.15,
    "flow": 0.10,
    "filter_adherence": 0.05,
}

# =============================================================================
# CLI Configuration  
# =============================================================================

# Path to the built CLI executable (after swift build)
CLI_EXECUTABLE = CLI_DIR / ".build" / "release" / "RunClubCLI"

# Timeout for CLI commands (seconds)
CLI_TIMEOUT = 60

# =============================================================================
# Ensure output directories exist
# =============================================================================

def ensure_directories():
    """Create output directories if they don't exist."""
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
