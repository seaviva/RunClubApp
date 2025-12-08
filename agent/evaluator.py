"""
Evaluator module for assessing playlist generation quality.

This module provides both objective (metric-based) and subjective
(Claude-powered) evaluation of generated playlists.
"""

import os
from datetime import datetime
from pathlib import Path
from typing import Optional

import anthropic

from models import (
    GenerationResult,
    EvaluationResult,
    DimensionScore,
    HardRequirementResult,
    TrackSlot,
    EffortTier,
)
from config import (
    QUALITY_CRITERIA_PATH,
    CLAUDE_MODEL,
    DIMENSION_WEIGHTS,
    ANTHROPIC_API_KEY,
)


class ObjectiveEvaluator:
    """Evaluates generations based on objective metrics."""
    
    def __init__(self):
        """Initialize the objective evaluator."""
        pass
    
    def evaluate(self, generation: GenerationResult) -> EvaluationResult:
        """Evaluate a generation based on objective criteria.
        
        Args:
            generation: The generation result to evaluate
            
        Returns:
            EvaluationResult with objective scores
        """
        # Check hard requirements
        hard_requirements = self._check_hard_requirements(generation)
        all_passed = all(r.passed for r in hard_requirements)
        
        # Score dimensions
        dimension_scores = self._score_dimensions(generation)
        
        # Compute overall score (weighted average)
        overall = sum(d.score * d.weight for d in dimension_scores)
        
        return EvaluationResult(
            generation=generation,
            hard_requirements=hard_requirements,
            all_hard_requirements_passed=all_passed,
            dimension_scores=dimension_scores,
            overall_score=overall,
            evaluated_at=datetime.now(),
        )
    
    def _check_hard_requirements(self, gen: GenerationResult) -> list[HardRequirementResult]:
        """Check all hard requirements."""
        results = []
        
        # Duration compliance (±2 minutes)
        target_seconds = gen.run_minutes * 60
        duration_ok = abs(gen.total_seconds - target_seconds) <= 120
        results.append(HardRequirementResult(
            name="Duration Compliance",
            passed=duration_ok,
            details=f"Target: {target_seconds}s, Actual: {gen.total_seconds}s, Diff: {abs(gen.total_seconds - target_seconds)}s"
        ))
        
        # Warmup segment (±60s of target)
        warmup_ok = abs(gen.warmup_seconds - gen.warmup_target) <= 60
        results.append(HardRequirementResult(
            name="Warmup Duration",
            passed=warmup_ok,
            details=f"Target: {gen.warmup_target}s, Actual: {gen.warmup_seconds}s"
        ))
        
        # Cooldown segment (±60s of target)
        cooldown_ok = abs(gen.cooldown_seconds - gen.cooldown_target) <= 60
        results.append(HardRequirementResult(
            name="Cooldown Duration",
            passed=cooldown_ok,
            details=f"Target: {gen.cooldown_target}s, Actual: {gen.cooldown_seconds}s"
        ))
        
        # Effort bookends (starts and ends with Easy)
        if gen.slots:
            first_easy = gen.slots[0].effort == EffortTier.EASY
            last_easy = gen.slots[-1].effort == EffortTier.EASY
            bookends_ok = first_easy and last_easy
        else:
            bookends_ok = False
        results.append(HardRequirementResult(
            name="Effort Bookends",
            passed=bookends_ok,
            details=f"First: {gen.slots[0].effort.value if gen.slots else 'N/A'}, Last: {gen.slots[-1].effort.value if gen.slots else 'N/A'}"
        ))
        
        # No back-to-back same artist
        back_to_back = False
        for i in range(1, len(gen.slots)):
            if gen.slots[i].artist_id == gen.slots[i-1].artist_id:
                back_to_back = True
                break
        results.append(HardRequirementResult(
            name="No Back-to-Back Artist",
            passed=not back_to_back,
            details="No violations" if not back_to_back else "Found back-to-back same artist"
        ))
        
        # Per-artist cap (max 2)
        artist_counts = {}
        for slot in gen.slots:
            artist_counts[slot.artist_id] = artist_counts.get(slot.artist_id, 0) + 1
        max_per_artist = max(artist_counts.values()) if artist_counts else 0
        cap_ok = max_per_artist <= 2
        results.append(HardRequirementResult(
            name="Artist Cap",
            passed=cap_ok,
            details=f"Max tracks per artist: {max_per_artist}"
        ))
        
        # Track duration (≤6 min)
        long_tracks = [s for s in gen.slots if s.duration_ms > 6 * 60 * 1000]
        results.append(HardRequirementResult(
            name="Track Duration",
            passed=len(long_tracks) == 0,
            details=f"Tracks over 6 min: {len(long_tracks)}"
        ))
        
        return results
    
    def _score_dimensions(self, gen: GenerationResult) -> list[DimensionScore]:
        """Score each evaluation dimension."""
        scores = []
        
        # 1. Tempo Fitness
        tempo_score, tempo_issues = self._score_tempo_fitness(gen)
        scores.append(DimensionScore(
            name="Tempo Fitness",
            score=tempo_score,
            weight=DIMENSION_WEIGHTS["tempo_fitness"],
            notes=f"Avg tempoFit: {gen.avg_tempo_fit:.2f}",
            issues=tempo_issues,
        ))
        
        # 2. Energy Arc
        arc_score, arc_issues = self._score_energy_arc(gen)
        scores.append(DimensionScore(
            name="Energy Arc",
            score=arc_score,
            weight=DIMENSION_WEIGHTS["energy_arc"],
            notes=f"Based on segment energy progression",
            issues=arc_issues,
        ))
        
        # 3. Slot Fitness
        slot_score, slot_issues = self._score_slot_fitness(gen)
        scores.append(DimensionScore(
            name="Slot Fitness",
            score=slot_score,
            weight=DIMENSION_WEIGHTS["slot_fitness"],
            notes=f"Avg slotFit: {gen.avg_slot_fit:.2f}",
            issues=slot_issues,
        ))
        
        # 4. Variety & Freshness
        variety_score, variety_issues = self._score_variety(gen)
        scores.append(DimensionScore(
            name="Variety & Freshness",
            score=variety_score,
            weight=DIMENSION_WEIGHTS["variety"],
            notes=f"Rediscovery: {gen.rediscovery_pct:.0%}, Unique artists: {gen.unique_artists}",
            issues=variety_issues,
        ))
        
        # 5. Flow & Transitions
        flow_score, flow_issues = self._score_flow(gen)
        scores.append(DimensionScore(
            name="Flow & Transitions",
            score=flow_score,
            weight=DIMENSION_WEIGHTS["flow"],
            notes=f"Based on tempo/energy transitions",
            issues=flow_issues,
        ))
        
        # 6. Filter Adherence
        filter_score, filter_issues = self._score_filter_adherence(gen)
        scores.append(DimensionScore(
            name="Filter Adherence",
            score=filter_score,
            weight=DIMENSION_WEIGHTS["filter_adherence"],
            notes=f"Avg genre affinity: {gen.avg_genre_affinity:.2f}",
            issues=filter_issues,
        ))
        
        return scores
    
    def _score_tempo_fitness(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score tempo fitness dimension."""
        issues = []
        
        if gen.avg_tempo_fit >= 0.85:
            score = 10.0
        elif gen.avg_tempo_fit >= 0.75:
            score = 8.0 + (gen.avg_tempo_fit - 0.75) * 20
        elif gen.avg_tempo_fit >= 0.65:
            score = 6.0 + (gen.avg_tempo_fit - 0.65) * 20
        elif gen.avg_tempo_fit >= 0.50:
            score = 4.0 + (gen.avg_tempo_fit - 0.50) * 13.3
        else:
            score = max(1.0, gen.avg_tempo_fit * 8)
        
        # Check for individual poor fits
        poor_fits = [s for s in gen.slots if s.tempo_fit < 0.50]
        if poor_fits:
            issues.append(f"{len(poor_fits)} tracks with tempoFit < 0.50")
        
        very_poor = [s for s in gen.slots if s.tempo_fit < 0.35]
        if very_poor:
            issues.append(f"{len(very_poor)} tracks with tempoFit < 0.35 (critical)")
            score = max(1.0, score - len(very_poor) * 0.5)
        
        return min(10.0, max(1.0, score)), issues
    
    def _score_energy_arc(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score energy arc dimension."""
        issues = []
        score = 7.0  # Start neutral
        
        if not gen.slots:
            return 5.0, ["No slots to evaluate"]
        
        # Get segments
        warmup = [s for s in gen.slots if s.segment == "warmup"]
        main = [s for s in gen.slots if s.segment == "main"]
        cooldown = [s for s in gen.slots if s.segment == "cooldown"]
        
        # Check warmup starts calm
        if warmup:
            warmup_energies = [s.energy for s in warmup if s.energy is not None]
            if warmup_energies:
                avg_warmup_energy = sum(warmup_energies) / len(warmup_energies)
                if avg_warmup_energy > 0.7:
                    issues.append(f"Warmup too intense (avg energy: {avg_warmup_energy:.2f})")
                    score -= 1.5
                elif avg_warmup_energy < 0.6:
                    score += 0.5  # Good calm warmup
        
        # Check cooldown winds down
        if cooldown:
            cooldown_energies = [s.energy for s in cooldown if s.energy is not None]
            if cooldown_energies:
                avg_cooldown_energy = sum(cooldown_energies) / len(cooldown_energies)
                if avg_cooldown_energy > 0.65:
                    issues.append(f"Cooldown doesn't cool down (avg energy: {avg_cooldown_energy:.2f})")
                    score -= 1.5
                elif avg_cooldown_energy < 0.55:
                    score += 0.5  # Good cool cooldown
        
        # Check main section follows template pattern
        if main:
            main_efforts = [s.effort for s in main]
            # Basic check: does it have variety?
            unique_efforts = len(set(main_efforts))
            if unique_efforts == 1 and gen.template.value not in ["light", "tempo"]:
                issues.append("Main section lacks effort variety")
                score -= 1.0
            
            # Template-specific checks
            if gen.template.value == "hiit":
                # HIIT should alternate
                alternations = 0
                for i in range(1, len(main_efforts)):
                    if main_efforts[i] != main_efforts[i-1]:
                        alternations += 1
                if alternations < len(main_efforts) * 0.5:
                    issues.append("HIIT doesn't alternate enough")
                    score -= 1.5
        
        return min(10.0, max(1.0, score)), issues
    
    def _score_slot_fitness(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score slot fitness dimension."""
        issues = []
        
        if gen.avg_slot_fit >= 0.85:
            score = 10.0
        elif gen.avg_slot_fit >= 0.75:
            score = 8.0 + (gen.avg_slot_fit - 0.75) * 20
        elif gen.avg_slot_fit >= 0.65:
            score = 6.0 + (gen.avg_slot_fit - 0.65) * 20
        elif gen.avg_slot_fit >= 0.50:
            score = 4.0 + (gen.avg_slot_fit - 0.50) * 13.3
        else:
            score = max(1.0, gen.avg_slot_fit * 8)
        
        # Check for effort mismatches
        for slot in gen.slots:
            if slot.effort in [EffortTier.HARD, EffortTier.MAX]:
                if slot.energy and slot.energy < 0.5:
                    issues.append(f"Track {slot.index}: Hard slot but low energy ({slot.energy:.2f})")
            elif slot.effort == EffortTier.EASY:
                if slot.energy and slot.energy > 0.75:
                    issues.append(f"Track {slot.index}: Easy slot but high energy ({slot.energy:.2f})")
        
        return min(10.0, max(1.0, score)), issues
    
    def _score_variety(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score variety and freshness dimension."""
        issues = []
        score = 7.0
        
        # Rediscovery target is 50%
        if gen.rediscovery_pct >= 0.45 and gen.rediscovery_pct <= 0.55:
            score += 2.0
        elif gen.rediscovery_pct >= 0.35:
            score += 1.0
        elif gen.rediscovery_pct < 0.25:
            issues.append(f"Low rediscovery rate ({gen.rediscovery_pct:.0%})")
            score -= 1.5
        
        # Artist variety
        if gen.slots:
            artist_ratio = gen.unique_artists / len(gen.slots)
            if artist_ratio >= 0.9:
                score += 1.0
            elif artist_ratio < 0.7:
                issues.append(f"Low artist variety ({gen.unique_artists} unique in {len(gen.slots)} tracks)")
                score -= 1.0
        
        # Source distribution (prefer likes, but some variety is good)
        if gen.slots:
            likes_pct = gen.sources.count("likes") / len(gen.sources) if gen.sources else 0
            if likes_pct < 0.3:
                issues.append(f"Low likes usage ({likes_pct:.0%})")
                score -= 0.5
        
        return min(10.0, max(1.0, score)), issues
    
    def _score_flow(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score flow and transitions dimension."""
        issues = []
        score = 7.0
        
        if len(gen.slots) < 2:
            return 5.0, ["Not enough tracks to evaluate flow"]
        
        big_jumps = 0
        for i in range(1, len(gen.slots)):
            prev = gen.slots[i-1]
            curr = gen.slots[i]
            
            # Check tempo jumps
            if prev.tempo and curr.tempo:
                tempo_diff = abs(prev.tempo - curr.tempo)
                if tempo_diff > 20:
                    big_jumps += 1
                    if tempo_diff > 30:
                        issues.append(f"Large tempo jump between tracks {i-1} and {i}: {tempo_diff:.0f} BPM")
            
            # Check energy jumps
            if prev.energy and curr.energy:
                energy_diff = abs(prev.energy - curr.energy)
                if energy_diff > 0.3:
                    big_jumps += 1
        
        # Penalize for big jumps
        if big_jumps > 0:
            penalty = min(3.0, big_jumps * 0.5)
            score -= penalty
            if big_jumps > 3:
                issues.append(f"{big_jumps} jarring transitions")
        else:
            score += 2.0  # Smooth flow bonus
        
        return min(10.0, max(1.0, score)), issues
    
    def _score_filter_adherence(self, gen: GenerationResult) -> tuple[float, list[str]]:
        """Score filter adherence dimension."""
        issues = []
        
        # If no filters, full score
        if not gen.genres and not gen.decades:
            return 10.0, []
        
        # Use genre affinity as proxy
        if gen.avg_genre_affinity >= 0.8:
            score = 10.0
        elif gen.avg_genre_affinity >= 0.6:
            score = 8.0 + (gen.avg_genre_affinity - 0.6) * 10
        elif gen.avg_genre_affinity >= 0.4:
            score = 6.0 + (gen.avg_genre_affinity - 0.4) * 10
        else:
            score = max(1.0, gen.avg_genre_affinity * 15)
            issues.append(f"Low genre filter adherence ({gen.avg_genre_affinity:.2f})")
        
        # Check for zero-affinity tracks
        zero_affinity = [s for s in gen.slots if s.genre_affinity <= 0.0]
        if zero_affinity and gen.genres:
            issues.append(f"{len(zero_affinity)} tracks with no genre match")
            score = max(1.0, score - len(zero_affinity) * 0.5)
        
        return min(10.0, max(1.0, score)), issues


class SubjectiveEvaluator:
    """Uses Claude to provide subjective evaluation of playlists."""
    
    def __init__(self, api_key: Optional[str] = None):
        """Initialize the subjective evaluator.
        
        Args:
            api_key: Anthropic API key. If None, uses ANTHROPIC_API_KEY from config.
        """
        self.api_key = api_key or ANTHROPIC_API_KEY or os.environ.get("ANTHROPIC_API_KEY", "")
        self._client: Optional[anthropic.Anthropic] = None
        self._criteria_cache: Optional[str] = None
    
    @property
    def client(self) -> anthropic.Anthropic:
        """Get or create Anthropic client."""
        if self._client is None:
            if not self.api_key:
                raise RuntimeError("No Anthropic API key configured")
            self._client = anthropic.Anthropic(api_key=self.api_key)
        return self._client
    
    def _load_criteria(self) -> str:
        """Load quality criteria document."""
        if self._criteria_cache is None:
            if QUALITY_CRITERIA_PATH.exists():
                self._criteria_cache = QUALITY_CRITERIA_PATH.read_text()
            else:
                self._criteria_cache = "No quality criteria document found."
        return self._criteria_cache
    
    def evaluate(
        self,
        generation: GenerationResult,
        objective_result: EvaluationResult,
    ) -> EvaluationResult:
        """Add subjective evaluation to an existing objective result.
        
        Args:
            generation: The generation to evaluate
            objective_result: Existing objective evaluation result
            
        Returns:
            Updated EvaluationResult with subjective notes
        """
        criteria = self._load_criteria()
        
        # Build the prompt
        prompt = self._build_evaluation_prompt(generation, objective_result, criteria)
        
        try:
            response = self.client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=2000,
                messages=[
                    {"role": "user", "content": prompt}
                ],
            )
            
            # Parse response
            response_text = response.content[0].text
            notes, issues, suggestions = self._parse_response(response_text)
            
            # Update result
            objective_result.subjective_notes = notes
            objective_result.subjective_issues = issues
            objective_result.subjective_suggestions = suggestions
            
        except Exception as e:
            objective_result.subjective_notes = f"Subjective evaluation failed: {e}"
        
        return objective_result
    
    def _build_evaluation_prompt(
        self,
        gen: GenerationResult,
        obj_result: EvaluationResult,
        criteria: str,
    ) -> str:
        """Build the evaluation prompt for Claude."""
        
        # Format track list
        track_list = "\n".join([
            f"  {i+1}. [{s.segment}] {s.artist_name} - {s.track_name} "
            f"(effort: {s.effort.value}, tempo: {s.tempo:.0f if s.tempo else 'N/A'}, "
            f"energy: {s.energy:.2f if s.energy else 'N/A'})"
            for i, s in enumerate(gen.slots)
        ])
        
        # Format objective results
        obj_summary = "\n".join([
            f"  - {d.name}: {d.score:.1f}/10 (weight: {d.weight:.0%})"
            + (f" - Issues: {', '.join(d.issues)}" if d.issues else "")
            for d in obj_result.dimension_scores
        ])
        
        hard_req_summary = "\n".join([
            f"  - {r.name}: {'PASS' if r.passed else 'FAIL'} ({r.details})"
            for r in obj_result.hard_requirements
        ])
        
        return f"""You are evaluating a running playlist generated for a {gen.template.value.upper()} workout of {gen.run_minutes} minutes.

## Quality Criteria Reference
{criteria[:3000]}...

## Generation Details
- Template: {gen.template.value}
- Duration: {gen.run_minutes} minutes (actual: {gen.total_seconds}s)
- Genres selected: {', '.join(gen.genres) if gen.genres else 'None'}
- Decades selected: {', '.join(gen.decades) if gen.decades else 'None'}

## Track List
{track_list}

## Objective Evaluation Results
Hard Requirements:
{hard_req_summary}

Dimension Scores:
{obj_summary}

Overall Score: {obj_result.overall_score:.1f}/10

## Your Task
Provide a subjective assessment of this playlist. Consider:

1. **Musical Quality**: Do these tracks work well together? Would a runner enjoy this mix?

2. **Template Fit**: Does the energy curve match what a {gen.template.value} run should feel like?

3. **Pacing**: Are there any jarring transitions? Does it flow naturally?

4. **Specific Issues**: Call out any tracks that seem wrong for their position.

5. **Improvement Suggestions**: What specific algorithm changes might help?

Format your response as:
NOTES: <your overall assessment in 2-3 sentences>
ISSUES: <bullet list of specific issues, or "None">
SUGGESTIONS: <bullet list of algorithm improvement suggestions>
"""
    
    def _parse_response(self, response: str) -> tuple[str, list[str], list[str]]:
        """Parse Claude's response into structured data."""
        notes = ""
        issues = []
        suggestions = []
        
        current_section = None
        lines = response.strip().split("\n")
        
        for line in lines:
            line = line.strip()
            if line.startswith("NOTES:"):
                current_section = "notes"
                notes = line[6:].strip()
            elif line.startswith("ISSUES:"):
                current_section = "issues"
                rest = line[7:].strip()
                if rest and rest.lower() != "none":
                    issues.append(rest.lstrip("- •"))
            elif line.startswith("SUGGESTIONS:"):
                current_section = "suggestions"
                rest = line[12:].strip()
                if rest:
                    suggestions.append(rest.lstrip("- •"))
            elif line.startswith(("- ", "• ", "* ")):
                item = line[2:].strip()
                if current_section == "issues" and item.lower() != "none":
                    issues.append(item)
                elif current_section == "suggestions":
                    suggestions.append(item)
            elif current_section == "notes" and line:
                notes += " " + line
        
        return notes.strip(), issues, suggestions


class CombinedEvaluator:
    """Combines objective and subjective evaluation."""
    
    def __init__(self, use_subjective: bool = True):
        """Initialize the combined evaluator.
        
        Args:
            use_subjective: Whether to include Claude-based subjective evaluation
        """
        self.objective = ObjectiveEvaluator()
        self.subjective = SubjectiveEvaluator() if use_subjective else None
    
    def evaluate(self, generation: GenerationResult) -> EvaluationResult:
        """Evaluate a generation using both objective and subjective methods.
        
        Args:
            generation: The generation to evaluate
            
        Returns:
            Complete EvaluationResult
        """
        # First, objective evaluation
        result = self.objective.evaluate(generation)
        
        # Then, subjective evaluation if enabled
        if self.subjective:
            try:
                result = self.subjective.evaluate(generation, result)
            except Exception as e:
                result.subjective_notes = f"Subjective evaluation unavailable: {e}"
        
        return result


if __name__ == "__main__":
    # Quick test with mock data
    from models import Template, EffortTier, SourceKind
    
    # Create mock generation
    mock_slots = [
        TrackSlot(
            index=0, track_id="1", artist_id="a1", artist_name="Artist 1",
            track_name="Track 1", effort=EffortTier.EASY, source=SourceKind.LIKES,
            segment="warmup", tempo=155.0, energy=0.5, danceability=0.6,
            duration_ms=210000, tempo_fit=0.8, effort_index=0.45, slot_fit=0.85,
            genre_affinity=0.7, is_rediscovery=True,
        ),
        TrackSlot(
            index=1, track_id="2", artist_id="a2", artist_name="Artist 2",
            track_name="Track 2", effort=EffortTier.STRONG, source=SourceKind.LIKES,
            segment="main", tempo=170.0, energy=0.7, danceability=0.75,
            duration_ms=240000, tempo_fit=0.9, effort_index=0.65, slot_fit=0.9,
            genre_affinity=0.8, is_rediscovery=False,
        ),
        TrackSlot(
            index=2, track_id="3", artist_id="a3", artist_name="Artist 3",
            track_name="Track 3", effort=EffortTier.EASY, source=SourceKind.LIKES,
            segment="cooldown", tempo=150.0, energy=0.4, danceability=0.5,
            duration_ms=200000, tempo_fit=0.85, effort_index=0.4, slot_fit=0.88,
            genre_affinity=0.6, is_rediscovery=True,
        ),
    ]
    
    mock_gen = GenerationResult(
        template=Template.TEMPO,
        run_minutes=30,
        genres=["Rock & Alt"],
        track_ids=["1", "2", "3"],
        artist_ids=["a1", "a2", "a3"],
        efforts=[EffortTier.EASY, EffortTier.STRONG, EffortTier.EASY],
        sources=[SourceKind.LIKES, SourceKind.LIKES, SourceKind.LIKES],
        total_seconds=650,
        warmup_seconds=210,
        main_seconds=240,
        cooldown_seconds=200,
        warmup_target=300,
        cooldown_target=300,
        slots=mock_slots,
        avg_tempo_fit=0.85,
        avg_slot_fit=0.88,
        avg_genre_affinity=0.7,
        rediscovery_pct=0.67,
        unique_artists=3,
    )
    
    # Run objective evaluation
    evaluator = ObjectiveEvaluator()
    result = evaluator.evaluate(mock_gen)
    
    print("=== Objective Evaluation ===")
    print(f"Overall Score: {result.overall_score:.1f}/10")
    print("\nHard Requirements:")
    for req in result.hard_requirements:
        print(f"  {'✓' if req.passed else '✗'} {req.name}: {req.details}")
    print("\nDimension Scores:")
    for dim in result.dimension_scores:
        print(f"  {dim.name}: {dim.score:.1f}/10 ({dim.weight:.0%})")
        if dim.issues:
            for issue in dim.issues:
                print(f"    - {issue}")
