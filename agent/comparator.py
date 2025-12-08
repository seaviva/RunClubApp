"""
Comparator module for analyzing multiple generations.

This module provides tools for comparing generations across runs to identify:
- Track repetition patterns (same songs appearing too often)
- Consistent issues (problems that occur every time)
- Variability in quality (are some templates more reliable?)
- Filter effectiveness (do filters actually change results?)
- Edge cases (specific parameter combinations that fail)
"""

from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
import json
from pathlib import Path

from models import (
    GenerationResult,
    EvaluationResult,
    EffortTier,
    Template,
)
from config import RUNS_DIR, ensure_directories


@dataclass
class TrackUsageStats:
    """Statistics about track usage across generations."""
    track_id: str
    artist_name: str
    track_name: str
    appearance_count: int
    generations: list[str] = field(default_factory=list)  # List of generation IDs
    slots_used: list[int] = field(default_factory=list)
    efforts_assigned: list[str] = field(default_factory=list)


@dataclass
class IssuePattern:
    """A recurring issue pattern across generations."""
    issue_type: str
    description: str
    occurrence_count: int
    affected_generations: list[str] = field(default_factory=list)
    example_details: list[str] = field(default_factory=list)


@dataclass
class ComparisonReport:
    """Complete comparison report for a batch of generations."""
    # Metadata
    report_id: str
    generated_at: datetime
    generations_compared: int
    
    # Quality summary
    avg_overall_score: float
    score_std_dev: float
    min_score: float
    max_score: float
    hard_req_pass_rate: float
    
    # Track repetition analysis
    most_used_tracks: list[TrackUsageStats] = field(default_factory=list)
    unique_tracks_total: int = 0
    avg_unique_tracks_per_gen: float = 0.0
    track_overlap_rate: float = 0.0  # % of tracks appearing in multiple gens
    
    # Issue patterns
    recurring_issues: list[IssuePattern] = field(default_factory=list)
    dimension_weaknesses: dict[str, float] = field(default_factory=dict)  # Dimension -> avg score
    
    # Template analysis
    template_scores: dict[str, float] = field(default_factory=dict)  # Template -> avg score
    template_reliability: dict[str, float] = field(default_factory=dict)  # Template -> pass rate
    
    # Filter effectiveness
    filter_impact: dict[str, dict] = field(default_factory=dict)
    
    # Recommendations
    recommendations: list[str] = field(default_factory=list)


class GenerationComparator:
    """Compares multiple generations to identify patterns and issues."""
    
    def __init__(self):
        """Initialize the comparator."""
        ensure_directories()
    
    def compare(
        self,
        evaluations: list[EvaluationResult],
        save_report: bool = True,
    ) -> ComparisonReport:
        """Compare multiple generations and produce a report.
        
        Args:
            evaluations: List of evaluation results to compare
            save_report: Whether to save the report to disk
            
        Returns:
            ComparisonReport with analysis
        """
        if not evaluations:
            raise ValueError("No evaluations to compare")
        
        report_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Basic quality stats
        scores = [e.overall_score for e in evaluations]
        avg_score = sum(scores) / len(scores)
        score_std = (sum((s - avg_score) ** 2 for s in scores) / len(scores)) ** 0.5
        pass_rate = sum(1 for e in evaluations if e.all_hard_requirements_passed) / len(evaluations)
        
        # Track usage analysis
        track_stats = self._analyze_track_usage(evaluations)
        
        # Issue pattern analysis
        issues = self._find_recurring_issues(evaluations)
        
        # Dimension weakness analysis
        dim_scores = self._analyze_dimensions(evaluations)
        
        # Template analysis
        template_scores, template_reliability = self._analyze_templates(evaluations)
        
        # Filter effectiveness
        filter_impact = self._analyze_filter_impact(evaluations)
        
        # Generate recommendations
        recommendations = self._generate_recommendations(
            track_stats, issues, dim_scores, template_scores, filter_impact
        )
        
        report = ComparisonReport(
            report_id=report_id,
            generated_at=datetime.now(),
            generations_compared=len(evaluations),
            avg_overall_score=avg_score,
            score_std_dev=score_std,
            min_score=min(scores),
            max_score=max(scores),
            hard_req_pass_rate=pass_rate,
            most_used_tracks=sorted(track_stats, key=lambda x: -x.appearance_count)[:20],
            unique_tracks_total=len(track_stats),
            avg_unique_tracks_per_gen=sum(len(e.generation.track_ids) for e in evaluations) / len(evaluations),
            track_overlap_rate=self._calc_overlap_rate(track_stats, len(evaluations)),
            recurring_issues=issues,
            dimension_weaknesses=dim_scores,
            template_scores=template_scores,
            template_reliability=template_reliability,
            filter_impact=filter_impact,
            recommendations=recommendations,
        )
        
        if save_report:
            self._save_report(report)
        
        return report
    
    def _analyze_track_usage(self, evaluations: list[EvaluationResult]) -> list[TrackUsageStats]:
        """Analyze track usage patterns across generations."""
        track_info: dict[str, TrackUsageStats] = {}
        
        for i, eval_result in enumerate(evaluations):
            gen = eval_result.generation
            gen_id = f"gen_{i}"
            
            for slot in gen.slots:
                if slot.track_id not in track_info:
                    track_info[slot.track_id] = TrackUsageStats(
                        track_id=slot.track_id,
                        artist_name=slot.artist_name or "Unknown",
                        track_name=slot.track_name or "Unknown",
                        appearance_count=0,
                    )
                
                stats = track_info[slot.track_id]
                stats.appearance_count += 1
                stats.generations.append(gen_id)
                stats.slots_used.append(slot.index)
                stats.efforts_assigned.append(slot.effort.value)
        
        return list(track_info.values())
    
    def _find_recurring_issues(self, evaluations: list[EvaluationResult]) -> list[IssuePattern]:
        """Find issues that occur across multiple generations."""
        issue_counts: dict[str, list[tuple[str, str]]] = defaultdict(list)
        
        for i, eval_result in enumerate(evaluations):
            gen_id = f"gen_{i}"
            
            # Check hard requirement failures
            for req in eval_result.hard_requirements:
                if not req.passed:
                    issue_counts[f"hard_req:{req.name}"].append((gen_id, req.details))
            
            # Check dimension issues
            for dim in eval_result.dimension_scores:
                for issue in dim.issues:
                    issue_counts[f"dim:{dim.name}:{issue}"].append((gen_id, issue))
            
            # Check subjective issues
            for issue in eval_result.subjective_issues:
                issue_counts[f"subjective:{issue}"].append((gen_id, issue))
        
        # Convert to IssuePattern objects (only issues occurring 2+ times)
        patterns = []
        for key, occurrences in issue_counts.items():
            if len(occurrences) >= 2:
                parts = key.split(":", 2)
                issue_type = parts[0]
                description = ":".join(parts[1:])
                
                patterns.append(IssuePattern(
                    issue_type=issue_type,
                    description=description,
                    occurrence_count=len(occurrences),
                    affected_generations=[o[0] for o in occurrences],
                    example_details=[o[1] for o in occurrences[:3]],
                ))
        
        return sorted(patterns, key=lambda x: -x.occurrence_count)
    
    def _analyze_dimensions(self, evaluations: list[EvaluationResult]) -> dict[str, float]:
        """Analyze average scores per dimension."""
        dim_scores: dict[str, list[float]] = defaultdict(list)
        
        for eval_result in evaluations:
            for dim in eval_result.dimension_scores:
                dim_scores[dim.name].append(dim.score)
        
        return {name: sum(scores) / len(scores) for name, scores in dim_scores.items()}
    
    def _analyze_templates(
        self, 
        evaluations: list[EvaluationResult]
    ) -> tuple[dict[str, float], dict[str, float]]:
        """Analyze performance by template type."""
        template_scores: dict[str, list[float]] = defaultdict(list)
        template_passes: dict[str, list[bool]] = defaultdict(list)
        
        for eval_result in evaluations:
            template = eval_result.generation.template.value
            template_scores[template].append(eval_result.overall_score)
            template_passes[template].append(eval_result.all_hard_requirements_passed)
        
        avg_scores = {t: sum(s) / len(s) for t, s in template_scores.items()}
        reliability = {t: sum(p) / len(p) for t, p in template_passes.items()}
        
        return avg_scores, reliability
    
    def _analyze_filter_impact(self, evaluations: list[EvaluationResult]) -> dict[str, dict]:
        """Analyze how filters affect generation quality."""
        with_genre_filter = []
        without_genre_filter = []
        with_decade_filter = []
        without_decade_filter = []
        
        for eval_result in evaluations:
            gen = eval_result.generation
            
            if gen.genres:
                with_genre_filter.append(eval_result.overall_score)
            else:
                without_genre_filter.append(eval_result.overall_score)
            
            if gen.decades:
                with_decade_filter.append(eval_result.overall_score)
            else:
                without_decade_filter.append(eval_result.overall_score)
        
        return {
            "genre_filter": {
                "with_filter_avg": sum(with_genre_filter) / len(with_genre_filter) if with_genre_filter else 0,
                "without_filter_avg": sum(without_genre_filter) / len(without_genre_filter) if without_genre_filter else 0,
                "sample_with": len(with_genre_filter),
                "sample_without": len(without_genre_filter),
            },
            "decade_filter": {
                "with_filter_avg": sum(with_decade_filter) / len(with_decade_filter) if with_decade_filter else 0,
                "without_filter_avg": sum(without_decade_filter) / len(without_decade_filter) if without_decade_filter else 0,
                "sample_with": len(with_decade_filter),
                "sample_without": len(without_decade_filter),
            }
        }
    
    def _calc_overlap_rate(self, track_stats: list[TrackUsageStats], num_gens: int) -> float:
        """Calculate what percentage of tracks appear in multiple generations."""
        if not track_stats:
            return 0.0
        multi_appearance = sum(1 for t in track_stats if t.appearance_count > 1)
        return multi_appearance / len(track_stats)
    
    def _generate_recommendations(
        self,
        track_stats: list[TrackUsageStats],
        issues: list[IssuePattern],
        dim_scores: dict[str, float],
        template_scores: dict[str, float],
        filter_impact: dict[str, dict],
    ) -> list[str]:
        """Generate actionable recommendations based on analysis."""
        recommendations = []
        
        # Track repetition
        heavily_used = [t for t in track_stats if t.appearance_count >= 3]
        if heavily_used:
            recommendations.append(
                f"High track repetition: {len(heavily_used)} tracks appear 3+ times. "
                "Consider increasing diversity bonuses or recency penalties."
            )
        
        # Recurring issues
        for issue in issues[:3]:  # Top 3 issues
            if issue.occurrence_count >= 3:
                recommendations.append(
                    f"Recurring issue ({issue.occurrence_count}x): {issue.description}. "
                    f"Affects generations: {', '.join(issue.affected_generations[:3])}"
                )
        
        # Weak dimensions
        for dim, score in dim_scores.items():
            if score < 6.0:
                recommendations.append(
                    f"Weak dimension: {dim} averages {score:.1f}/10. "
                    "Consider tuning related parameters."
                )
        
        # Template issues
        for template, score in template_scores.items():
            if score < 6.0:
                recommendations.append(
                    f"Template '{template}' underperforming (avg {score:.1f}). "
                    "Review effort curve and tier specs for this template."
                )
        
        # Filter effectiveness
        genre_data = filter_impact.get("genre_filter", {})
        if genre_data.get("with_filter_avg", 0) < genre_data.get("without_filter_avg", 0) - 0.5:
            recommendations.append(
                "Genre filters may be too restrictive - "
                "filtered generations score lower. Consider broadening umbrella matching."
            )
        
        return recommendations
    
    def _save_report(self, report: ComparisonReport):
        """Save comparison report to disk."""
        path = RUNS_DIR / f"comparison_{report.report_id}.json"
        
        # Convert to serializable dict
        data = {
            "report_id": report.report_id,
            "generated_at": report.generated_at.isoformat(),
            "generations_compared": report.generations_compared,
            "quality_summary": {
                "avg_score": report.avg_overall_score,
                "std_dev": report.score_std_dev,
                "min": report.min_score,
                "max": report.max_score,
                "hard_req_pass_rate": report.hard_req_pass_rate,
            },
            "track_analysis": {
                "unique_tracks": report.unique_tracks_total,
                "avg_per_gen": report.avg_unique_tracks_per_gen,
                "overlap_rate": report.track_overlap_rate,
                "most_used": [
                    {
                        "track_id": t.track_id,
                        "artist": t.artist_name,
                        "track": t.track_name,
                        "count": t.appearance_count,
                    }
                    for t in report.most_used_tracks[:10]
                ],
            },
            "recurring_issues": [
                {
                    "type": i.issue_type,
                    "description": i.description,
                    "count": i.occurrence_count,
                }
                for i in report.recurring_issues[:10]
            ],
            "dimension_scores": report.dimension_weaknesses,
            "template_scores": report.template_scores,
            "template_reliability": report.template_reliability,
            "filter_impact": report.filter_impact,
            "recommendations": report.recommendations,
        }
        
        path.write_text(json.dumps(data, indent=2))
        print(f"Comparison report saved: {path}")
    
    def print_summary(self, report: ComparisonReport):
        """Print a human-readable summary of the comparison."""
        print("\n" + "=" * 60)
        print("MULTI-GENERATION COMPARISON REPORT")
        print("=" * 60)
        
        print(f"\nGenerations compared: {report.generations_compared}")
        print(f"Average score: {report.avg_overall_score:.2f}/10 (±{report.score_std_dev:.2f})")
        print(f"Score range: {report.min_score:.1f} - {report.max_score:.1f}")
        print(f"Hard requirement pass rate: {report.hard_req_pass_rate:.0%}")
        
        print(f"\n--- Track Usage ---")
        print(f"Unique tracks: {report.unique_tracks_total}")
        print(f"Avg tracks per generation: {report.avg_unique_tracks_per_gen:.1f}")
        print(f"Track overlap rate: {report.track_overlap_rate:.0%}")
        
        if report.most_used_tracks:
            print("\nMost frequently used tracks:")
            for t in report.most_used_tracks[:5]:
                print(f"  {t.appearance_count}x: {t.artist_name} - {t.track_name}")
        
        if report.recurring_issues:
            print(f"\n--- Recurring Issues ({len(report.recurring_issues)} found) ---")
            for issue in report.recurring_issues[:5]:
                print(f"  [{issue.occurrence_count}x] {issue.issue_type}: {issue.description}")
        
        print(f"\n--- Dimension Scores ---")
        for dim, score in sorted(report.dimension_weaknesses.items(), key=lambda x: x[1]):
            indicator = "⚠️ " if score < 6.0 else "  "
            print(f"{indicator}{dim}: {score:.1f}/10")
        
        print(f"\n--- Template Performance ---")
        for template, score in sorted(report.template_scores.items(), key=lambda x: -x[1]):
            reliability = report.template_reliability.get(template, 0)
            print(f"  {template}: {score:.1f}/10 ({reliability:.0%} pass rate)")
        
        if report.recommendations:
            print(f"\n--- Recommendations ---")
            for i, rec in enumerate(report.recommendations, 1):
                print(f"  {i}. {rec}")
        
        print()


def run_comparison_batch(
    runner,
    evaluator,
    templates: list[str],
    durations: list[int],
    runs_per_combo: int = 2,
    genre_sets: Optional[list[list[str]]] = None,
) -> ComparisonReport:
    """Run a batch of generations and compare them.
    
    Args:
        runner: CLIRunner instance
        evaluator: CombinedEvaluator instance
        templates: Templates to test
        durations: Durations to test
        runs_per_combo: How many times to run each combination
        genre_sets: Optional genre filter sets to test
        
    Returns:
        ComparisonReport with analysis
    """
    from runner import CLIRunner
    from evaluator import CombinedEvaluator
    
    evaluations = []
    
    if genre_sets is None:
        genre_sets = [[], ["Rock & Alt", "Pop"]]  # Test with and without filters
    
    for template in templates:
        for duration in durations:
            for genres in genre_sets:
                for run_num in range(runs_per_combo):
                    try:
                        print(f"Running: {template}/{duration}min, genres={genres or 'none'}, run {run_num+1}/{runs_per_combo}")
                        
                        gen = runner.run_generation(
                            template=template,
                            minutes=duration,
                            genres=genres if genres else None,
                        )
                        
                        eval_result = evaluator.evaluate(gen)
                        evaluations.append(eval_result)
                        
                        print(f"  Score: {eval_result.overall_score:.1f}/10")
                        
                    except Exception as e:
                        print(f"  Failed: {e}")
    
    comparator = GenerationComparator()
    report = comparator.compare(evaluations)
    comparator.print_summary(report)
    
    return report


if __name__ == "__main__":
    # Demo with mock data
    print("Comparator module loaded. Use run_comparison_batch() to compare generations.")
