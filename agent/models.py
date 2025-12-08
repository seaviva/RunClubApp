"""
Pydantic models for the Playlist Generation Agent.

These models define the data structures used throughout the agent system,
ensuring type safety and validation.
"""

from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel, Field


# =============================================================================
# Enums
# =============================================================================

class EffortTier(str, Enum):
    """Effort tier matching LocalGenerator.EffortTier"""
    EASY = "easy"
    MODERATE = "moderate"
    STRONG = "strong"
    HARD = "hard"
    MAX = "max"


class SourceKind(str, Enum):
    """Track source matching LocalGenerator.SourceKind"""
    LIKES = "likes"
    RECS = "recs"
    THIRD = "third"


class Template(str, Enum):
    """Run template types"""
    LIGHT = "light"
    TEMPO = "tempo"
    HIIT = "hiit"
    INTERVALS = "intervals"
    PYRAMID = "pyramid"
    KICKER = "kicker"


# =============================================================================
# Track and Generation Models
# =============================================================================

class TrackSlot(BaseModel):
    """A single track slot in a generated playlist."""
    index: int
    track_id: str
    artist_id: str
    artist_name: Optional[str] = None
    track_name: Optional[str] = None
    effort: EffortTier
    source: SourceKind
    segment: str  # "warmup", "main", or "cooldown"
    
    # Audio features
    tempo: Optional[float] = None
    energy: Optional[float] = None
    danceability: Optional[float] = None
    duration_ms: int = 0
    
    # Scoring components
    tempo_fit: float = 0.0
    effort_index: float = 0.0
    slot_fit: float = 0.0
    genre_affinity: float = 0.0
    is_rediscovery: bool = False
    
    # Relaxation flags
    used_neighbor: bool = False
    broke_lockout: bool = False


class GenerationResult(BaseModel):
    """Result of a single playlist generation."""
    # Input parameters
    template: Template
    run_minutes: int
    genres: list[str] = Field(default_factory=list)
    decades: list[str] = Field(default_factory=list)
    
    # Output
    track_ids: list[str] = Field(default_factory=list)
    artist_ids: list[str] = Field(default_factory=list)
    efforts: list[EffortTier] = Field(default_factory=list)
    sources: list[SourceKind] = Field(default_factory=list)
    
    # Duration info
    total_seconds: int = 0
    min_seconds: int = 0
    max_seconds: int = 0
    
    # Segment durations
    warmup_seconds: int = 0
    main_seconds: int = 0
    cooldown_seconds: int = 0
    
    # Segment targets (from plan)
    warmup_target: int = 0
    main_target: int = 0
    cooldown_target: int = 0
    
    # Playability stats
    preflight_unplayable: int = 0
    swapped: int = 0
    removed: int = 0
    market: str = "US"
    
    # Parsed slot details
    slots: list[TrackSlot] = Field(default_factory=list)
    
    # Raw debug output
    debug_lines: list[str] = Field(default_factory=list)
    
    # Computed metrics (filled in by evaluator)
    avg_tempo_fit: float = 0.0
    avg_slot_fit: float = 0.0
    avg_genre_affinity: float = 0.0
    rediscovery_pct: float = 0.0
    unique_artists: int = 0
    neighbor_relax_slots: int = 0
    lockout_breaks: int = 0
    
    # Timestamp
    generated_at: datetime = Field(default_factory=datetime.now)


# =============================================================================
# Evaluation Models
# =============================================================================

class DimensionScore(BaseModel):
    """Score for a single evaluation dimension."""
    name: str
    score: float = Field(ge=1.0, le=10.0)
    weight: float
    notes: str = ""
    issues: list[str] = Field(default_factory=list)


class HardRequirementResult(BaseModel):
    """Result of checking a hard requirement."""
    name: str
    passed: bool
    details: str = ""


class EvaluationResult(BaseModel):
    """Complete evaluation of a generation."""
    generation: GenerationResult
    
    # Hard requirements
    hard_requirements: list[HardRequirementResult] = Field(default_factory=list)
    all_hard_requirements_passed: bool = True
    
    # Dimension scores
    dimension_scores: list[DimensionScore] = Field(default_factory=list)
    
    # Overall score (weighted average of dimensions)
    overall_score: float = 0.0
    
    # Subjective assessment from Claude
    subjective_notes: str = ""
    subjective_issues: list[str] = Field(default_factory=list)
    subjective_suggestions: list[str] = Field(default_factory=list)
    
    # Template-specific check results
    template_checks: dict[str, bool] = Field(default_factory=dict)
    
    # Evaluation timestamp
    evaluated_at: datetime = Field(default_factory=datetime.now)


# =============================================================================
# Modification Models
# =============================================================================

class ParameterChange(BaseModel):
    """A proposed change to a tunable parameter."""
    file_path: str
    parameter_name: str
    old_value: str
    new_value: str
    rationale: str
    is_numeric: bool = True  # If True, can be auto-applied


class CodeChange(BaseModel):
    """A proposed code modification."""
    file_path: str
    old_code: str
    new_code: str
    rationale: str
    is_structural: bool = False  # If True, requires approval
    
    # For tracking
    change_id: str = ""
    proposed_at: datetime = Field(default_factory=datetime.now)
    applied: bool = False
    approved: bool = False


class ChangeResult(BaseModel):
    """Result of applying a change."""
    change: CodeChange
    success: bool
    error: Optional[str] = None
    
    # Before/after metrics
    before_score: float = 0.0
    after_score: float = 0.0
    improvement: float = 0.0
    
    # Git info
    commit_sha: Optional[str] = None
    branch_name: Optional[str] = None


# =============================================================================
# Agent Session Models
# =============================================================================

class AgentIteration(BaseModel):
    """A single iteration of the agent loop."""
    iteration_number: int
    focus_area: str = ""
    
    # Generations run this iteration
    generations: list[GenerationResult] = Field(default_factory=list)
    evaluations: list[EvaluationResult] = Field(default_factory=list)
    
    # Changes proposed and applied
    proposed_changes: list[CodeChange] = Field(default_factory=list)
    applied_changes: list[ChangeResult] = Field(default_factory=list)
    
    # Summary
    avg_score_before: float = 0.0
    avg_score_after: float = 0.0
    improvement: float = 0.0
    
    # Timestamp
    started_at: datetime = Field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None


class AgentSession(BaseModel):
    """A complete agent session."""
    session_id: str
    started_at: datetime = Field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None
    
    # Configuration
    focus_areas: list[str] = Field(default_factory=list)
    max_iterations: int = 10
    
    # Iterations
    iterations: list[AgentIteration] = Field(default_factory=list)
    
    # Overall progress
    initial_avg_score: float = 0.0
    final_avg_score: float = 0.0
    total_improvement: float = 0.0
    
    # Summary of changes
    total_changes_proposed: int = 0
    total_changes_applied: int = 0
    total_changes_approved: int = 0
    
    # Git tracking
    branch_name: Optional[str] = None
    commits: list[str] = Field(default_factory=list)


# =============================================================================
# Tunable Parameter Models
# =============================================================================

class TunableParameter(BaseModel):
    """A single tunable parameter."""
    file: str
    parameter: str
    current_value: str
    value_type: str  # "float", "int", "tuple", etc.
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    description: str = ""
    
    # Extraction pattern (regex to find in code)
    pattern: Optional[str] = None
    
    # Location in file (for targeted edits)
    line_number: Optional[int] = None


class TunableParametersRegistry(BaseModel):
    """Registry of all tunable parameters."""
    numeric_tuning: list[TunableParameter] = Field(default_factory=list)
    structural_categories: list[str] = Field(default_factory=list)
    
    # Last updated
    updated_at: datetime = Field(default_factory=datetime.now)
