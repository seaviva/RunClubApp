"""
Orchestrator module for the playlist generation agent.

This module implements the main agent loop using Claude's tool-use capabilities
to iteratively improve the playlist generation algorithm.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Optional
import uuid

import anthropic
import yaml

from models import (
    GenerationResult,
    EvaluationResult,
    CodeChange,
    AgentSession,
    AgentIteration,
)
from config import (
    CLAUDE_MODEL,
    ANTHROPIC_API_KEY,
    PROJECT_ROOT,
    QUALITY_CRITERIA_PATH,
    TUNABLE_PARAMS_PATH,
    LOCAL_GENERATOR_PATH,
    RUNS_DIR,
    REPORTS_DIR,
    MAX_ITERATIONS,
    TEMPLATES,
    DURATIONS,
    ensure_directories,
)
from runner import CLIRunner
from evaluator import CombinedEvaluator
from modifier import SafeModifier, ParameterTuner
from comparator import GenerationComparator, ComparisonReport
from changelog_manager import ChangelogManager, VersionEntry, ParameterChange, MetricsDelta


# =============================================================================
# Tool Definitions
# =============================================================================

TOOLS = [
    {
        "name": "run_generation",
        "description": "Run a playlist generation with specified parameters and return the results. Use this to test current algorithm performance.",
        "input_schema": {
            "type": "object",
            "properties": {
                "template": {
                    "type": "string",
                    "enum": ["light", "tempo", "hiit", "intervals", "pyramid", "kicker"],
                    "description": "The run template type"
                },
                "minutes": {
                    "type": "integer",
                    "description": "Target run duration in minutes (typically 20-60)"
                },
                "genres": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Optional genre filters (e.g., ['Rock & Alt', 'Pop'])"
                },
                "decades": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Optional decade filters (e.g., ['90s', '00s'])"
                }
            },
            "required": ["template", "minutes"]
        }
    },
    {
        "name": "read_file",
        "description": "Read the contents of a source file. Use this to understand current algorithm implementation.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Path to the file relative to project root"
                }
            },
            "required": ["path"]
        }
    },
    {
        "name": "read_quality_criteria",
        "description": "Read the quality criteria document that defines what makes a good playlist.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "read_tunable_parameters",
        "description": "Read the registry of parameters that can be tuned.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "propose_numeric_change",
        "description": "Propose a numeric parameter change. These are auto-applied if they improve quality.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file": {
                    "type": "string",
                    "description": "Path to the file to modify"
                },
                "old_code": {
                    "type": "string",
                    "description": "The exact code to replace"
                },
                "new_code": {
                    "type": "string",
                    "description": "The new code to insert"
                },
                "rationale": {
                    "type": "string",
                    "description": "Explanation of why this change should improve quality"
                }
            },
            "required": ["file", "old_code", "new_code", "rationale"]
        }
    },
    {
        "name": "propose_structural_change",
        "description": "Propose a structural code change. These require user approval before being applied.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file": {
                    "type": "string",
                    "description": "Path to the file to modify"
                },
                "old_code": {
                    "type": "string",
                    "description": "The exact code to replace"
                },
                "new_code": {
                    "type": "string",
                    "description": "The new code to insert"
                },
                "rationale": {
                    "type": "string",
                    "description": "Explanation of why this change should improve quality"
                }
            },
            "required": ["file", "old_code", "new_code", "rationale"]
        }
    },
    {
        "name": "run_tests",
        "description": "Run the test suite to validate changes don't break anything.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "get_current_metrics",
        "description": "Get a summary of metrics from recent generations.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "compare_generations",
        "description": "Run a comparison analysis across all generations so far. Identifies patterns, recurring issues, and track repetition.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "get_changelog",
        "description": "Get the current algorithm version and recent changes from the changelog.",
        "input_schema": {
            "type": "object",
            "properties": {}
        }
    }
]


# =============================================================================
# Agent Orchestrator
# =============================================================================

class AgentOrchestrator:
    """Main orchestrator for the playlist improvement agent."""
    
    def __init__(
        self,
        api_key: Optional[str] = None,
        use_subjective: bool = True,
        auto_approve_numeric: bool = True,
    ):
        """Initialize the orchestrator.
        
        Args:
            api_key: Anthropic API key. Uses environment if not provided.
            use_subjective: Whether to include Claude-based subjective evaluation
            auto_approve_numeric: Whether to auto-apply numeric changes
        """
        self.api_key = api_key or ANTHROPIC_API_KEY or os.environ.get("ANTHROPIC_API_KEY", "")
        if not self.api_key:
            raise RuntimeError("No Anthropic API key configured")
        
        self.client = anthropic.Anthropic(api_key=self.api_key)
        self.runner = CLIRunner()
        self.evaluator = CombinedEvaluator(use_subjective=use_subjective)
        self.modifier = SafeModifier()
        self.tuner = ParameterTuner(self.modifier)
        self.comparator = GenerationComparator()
        self.changelog = ChangelogManager()
        self.auto_approve_numeric = auto_approve_numeric
        
        # Track changes for changelog
        self.applied_changes: list[dict] = []
        self.initial_metrics: dict[str, float] = {}
        
        # Session state
        self.session: Optional[AgentSession] = None
        self.current_iteration: Optional[AgentIteration] = None
        self.generations: list[GenerationResult] = []
        self.evaluations: list[EvaluationResult] = []
        
        ensure_directories()
    
    # =========================================================================
    # Tool Execution
    # =========================================================================
    
    def execute_tool(self, name: str, input_data: dict) -> str:
        """Execute a tool and return the result as a string.
        
        Args:
            name: Tool name
            input_data: Tool input parameters
            
        Returns:
            Tool result as string (JSON for complex data)
        """
        try:
            if name == "run_generation":
                result = self._tool_run_generation(
                    template=input_data["template"],
                    minutes=input_data["minutes"],
                    genres=input_data.get("genres"),
                    decades=input_data.get("decades"),
                )
                return json.dumps(result, indent=2, default=str)
            
            elif name == "read_file":
                return self._tool_read_file(input_data["path"])
            
            elif name == "read_quality_criteria":
                return self._tool_read_quality_criteria()
            
            elif name == "read_tunable_parameters":
                return self._tool_read_tunable_parameters()
            
            elif name == "propose_numeric_change":
                result = self._tool_propose_numeric_change(
                    file=input_data["file"],
                    old_code=input_data["old_code"],
                    new_code=input_data["new_code"],
                    rationale=input_data["rationale"],
                )
                return json.dumps(result, indent=2)
            
            elif name == "propose_structural_change":
                result = self._tool_propose_structural_change(
                    file=input_data["file"],
                    old_code=input_data["old_code"],
                    new_code=input_data["new_code"],
                    rationale=input_data["rationale"],
                )
                return json.dumps(result, indent=2)
            
            elif name == "run_tests":
                return self._tool_run_tests()
            
            elif name == "get_current_metrics":
                return self._tool_get_current_metrics()
            
            elif name == "compare_generations":
                return self._tool_compare_generations()
            
            elif name == "get_changelog":
                return self._tool_get_changelog()
            
            else:
                return f"Unknown tool: {name}"
                
        except Exception as e:
            return f"Error executing {name}: {str(e)}"
    
    def _tool_run_generation(
        self,
        template: str,
        minutes: int,
        genres: Optional[list[str]] = None,
        decades: Optional[list[str]] = None,
    ) -> dict:
        """Run a generation and return results."""
        try:
            gen = self.runner.run_generation(
                template=template,
                minutes=minutes,
                genres=genres,
                decades=decades,
            )
            self.generations.append(gen)
            
            # Run evaluation
            eval_result = self.evaluator.evaluate(gen)
            self.evaluations.append(eval_result)
            
            # Return summary
            return {
                "success": True,
                "tracks": len(gen.track_ids),
                "total_seconds": gen.total_seconds,
                "overall_score": eval_result.overall_score,
                "hard_requirements_passed": eval_result.all_hard_requirements_passed,
                "dimension_scores": {
                    d.name: {"score": d.score, "issues": d.issues}
                    for d in eval_result.dimension_scores
                },
                "avg_tempo_fit": gen.avg_tempo_fit,
                "avg_slot_fit": gen.avg_slot_fit,
                "rediscovery_pct": gen.rediscovery_pct,
            }
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    def _tool_read_file(self, path: str) -> str:
        """Read a source file."""
        full_path = PROJECT_ROOT / path
        if not full_path.exists():
            return f"File not found: {path}"
        return full_path.read_text()
    
    def _tool_read_quality_criteria(self) -> str:
        """Read quality criteria document."""
        if QUALITY_CRITERIA_PATH.exists():
            return QUALITY_CRITERIA_PATH.read_text()
        return "Quality criteria document not found."
    
    def _tool_read_tunable_parameters(self) -> str:
        """Read tunable parameters registry."""
        if TUNABLE_PARAMS_PATH.exists():
            return TUNABLE_PARAMS_PATH.read_text()
        return "Tunable parameters registry not found."
    
    def _tool_propose_numeric_change(
        self,
        file: str,
        old_code: str,
        new_code: str,
        rationale: str,
    ) -> dict:
        """Propose and optionally apply a numeric change."""
        change = CodeChange(
            file_path=file,
            old_code=old_code,
            new_code=new_code,
            rationale=rationale,
            is_structural=False,
            change_id=str(uuid.uuid4())[:8],
        )
        
        if self.auto_approve_numeric:
            result = self.modifier.apply_and_test(change)
            if result.success:
                # Commit the change
                sha = self.modifier.commit_change(
                    message=f"Tune: {rationale[:50]}",
                    files=[file],
                )
                # Track for changelog
                self.applied_changes.append({
                    "file": file,
                    "old_code": old_code,
                    "new_code": new_code,
                    "rationale": rationale,
                })
                return {
                    "applied": True,
                    "commit": sha,
                    "rationale": rationale,
                }
            else:
                return {
                    "applied": False,
                    "error": result.error,
                }
        else:
            return {
                "proposed": True,
                "requires_approval": False,
                "rationale": rationale,
            }
    
    def _tool_propose_structural_change(
        self,
        file: str,
        old_code: str,
        new_code: str,
        rationale: str,
    ) -> dict:
        """Propose a structural change (requires approval)."""
        change = CodeChange(
            file_path=file,
            old_code=old_code,
            new_code=new_code,
            rationale=rationale,
            is_structural=True,
            change_id=str(uuid.uuid4())[:8],
        )
        
        # Request approval
        approved = self.modifier.request_approval(change)
        
        if approved:
            result = self.modifier.apply_and_test(change)
            if result.success:
                sha = self.modifier.commit_change(
                    message=f"Structural: {rationale[:50]}",
                    files=[file],
                )
                return {
                    "approved": True,
                    "applied": True,
                    "commit": sha,
                }
            else:
                return {
                    "approved": True,
                    "applied": False,
                    "error": result.error,
                }
        else:
            return {
                "approved": False,
                "applied": False,
            }
    
    def _tool_run_tests(self) -> str:
        """Run the test suite."""
        success, output = self.modifier.run_tests()
        return f"Tests {'passed' if success else 'failed'}.\n\n{output[:1000]}"
    
    def _tool_get_current_metrics(self) -> str:
        """Get summary of recent generations."""
        if not self.evaluations:
            return "No generations run yet."
        
        # Compute averages
        scores = [e.overall_score for e in self.evaluations]
        tempo_fits = [e.generation.avg_tempo_fit for e in self.evaluations]
        slot_fits = [e.generation.avg_slot_fit for e in self.evaluations]
        
        # Store for changelog comparison
        self.initial_metrics = {
            "avg_overall_score": sum(scores) / len(scores),
            "avg_tempo_fit": sum(tempo_fits) / len(tempo_fits),
            "avg_slot_fit": sum(slot_fits) / len(slot_fits),
        }
        
        return json.dumps({
            "generations_run": len(self.evaluations),
            "avg_overall_score": sum(scores) / len(scores),
            "avg_tempo_fit": sum(tempo_fits) / len(tempo_fits),
            "avg_slot_fit": sum(slot_fits) / len(slot_fits),
            "hard_req_pass_rate": sum(1 for e in self.evaluations if e.all_hard_requirements_passed) / len(self.evaluations),
            "templates_tested": list(set(e.generation.template.value for e in self.evaluations)),
        }, indent=2)
    
    def _tool_compare_generations(self) -> str:
        """Run comparison analysis across generations."""
        if len(self.evaluations) < 2:
            return "Need at least 2 generations to compare."
        
        report = self.comparator.compare(self.evaluations, save_report=True)
        
        return json.dumps({
            "generations_compared": report.generations_compared,
            "avg_score": report.avg_overall_score,
            "score_std_dev": report.score_std_dev,
            "hard_req_pass_rate": report.hard_req_pass_rate,
            "track_overlap_rate": report.track_overlap_rate,
            "unique_tracks": report.unique_tracks_total,
            "recurring_issues": [
                {"issue": i.description, "count": i.occurrence_count}
                for i in report.recurring_issues[:5]
            ],
            "dimension_scores": report.dimension_weaknesses,
            "template_scores": report.template_scores,
            "recommendations": report.recommendations[:5],
        }, indent=2)
    
    def _tool_get_changelog(self) -> str:
        """Get current version and recent changelog."""
        version = self.changelog.get_current_version()
        
        # Read recent changelog content
        changelog_path = self.changelog.path
        if changelog_path.exists():
            content = changelog_path.read_text()
            # Get first 2000 chars after the header
            start = content.find("## [")
            excerpt = content[start:start+2000] if start > 0 else content[:2000]
        else:
            excerpt = "No changelog found."
        
        return f"Current version: {version}\n\nRecent changes:\n{excerpt}"
    
    # =========================================================================
    # Agent Loop
    # =========================================================================
    
    def run(
        self,
        focus: str = "overall improvement",
        max_iterations: int = MAX_ITERATIONS,
        initial_generations: int = 3,
    ) -> AgentSession:
        """Run the agent loop.
        
        Args:
            focus: What aspect to focus on improving
            max_iterations: Maximum number of improvement iterations
            initial_generations: Number of baseline generations to run first
            
        Returns:
            AgentSession with all results
        """
        # Initialize session
        self.session = AgentSession(
            session_id=str(uuid.uuid4())[:8],
            focus_areas=[focus],
            max_iterations=max_iterations,
        )
        
        # Create agent branch
        branch = self.modifier.create_agent_branch(focus)
        self.session.branch_name = branch
        print(f"\n🔀 Created branch: {branch}")
        
        # Build initial prompt
        system_prompt = self._build_system_prompt(focus)
        messages = [
            {
                "role": "user",
                "content": f"""I want you to help improve the playlist generation algorithm.

Focus area: {focus}

Start by:
1. Reading the quality criteria to understand what "good" means
2. Running a few generations across different templates to establish baseline performance
3. Identifying the weakest dimension or most common issues
4. Proposing targeted improvements

After each change, run more generations to validate the improvement.

Continue until you've made meaningful progress or exhausted reasonable options."""
            }
        ]
        
        iteration = 0
        while iteration < max_iterations:
            iteration += 1
            print(f"\n{'='*60}")
            print(f"ITERATION {iteration}")
            print(f"{'='*60}")
            
            # Call Claude
            response = self.client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=4096,
                system=system_prompt,
                tools=TOOLS,
                messages=messages,
            )
            
            # Process response
            assistant_content = []
            tool_results = []
            
            for block in response.content:
                if block.type == "text":
                    print(f"\n📝 Agent: {block.text[:500]}...")
                    assistant_content.append(block)
                    
                elif block.type == "tool_use":
                    print(f"\n🔧 Tool: {block.name}")
                    print(f"   Input: {json.dumps(block.input, indent=2)[:200]}...")
                    
                    # Execute tool
                    result = self.execute_tool(block.name, block.input)
                    print(f"   Result: {result[:200]}...")
                    
                    assistant_content.append(block)
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })
            
            # Add assistant message
            messages.append({"role": "assistant", "content": assistant_content})
            
            # Add tool results if any
            if tool_results:
                messages.append({"role": "user", "content": tool_results})
            
            # Check if we should stop
            if response.stop_reason == "end_turn" and not tool_results:
                print("\n✅ Agent completed.")
                break
        
        # Finalize session
        self.session.completed_at = datetime.now()
        if self.evaluations:
            scores = [e.overall_score for e in self.evaluations]
            self.session.final_avg_score = sum(scores) / len(scores)
        
        # Log changes to changelog if any were made
        if self.applied_changes:
            final_metrics = {
                "avg_overall_score": self.session.final_avg_score,
                "avg_tempo_fit": sum(e.generation.avg_tempo_fit for e in self.evaluations) / len(self.evaluations),
                "avg_slot_fit": sum(e.generation.avg_slot_fit for e in self.evaluations) / len(self.evaluations),
            }
            
            self.changelog.log_agent_changes(
                changes=self.applied_changes,
                before_metrics=self.initial_metrics or {},
                after_metrics=final_metrics,
                session_id=self.session.session_id,
                branch_name=self.session.branch_name or "",
            )
        
        # Save session report
        self._save_report()
        
        return self.session
    
    def _build_system_prompt(self, focus: str) -> str:
        """Build the system prompt for the agent."""
        return f"""You are an AI agent specialized in improving playlist generation algorithms.

Your goal is to iteratively improve the LocalGenerator algorithm by:
1. Running generations to understand current performance
2. Evaluating results against quality criteria
3. Identifying weaknesses and proposing targeted fixes
4. Validating improvements with before/after comparisons

Current focus: {focus}

Guidelines:
- Always read the quality criteria first to understand what "good" means
- Run diverse test cases (different templates, durations, filters)
- Make small, targeted changes rather than large rewrites
- Numeric tuning is auto-applied; structural changes require approval
- Validate changes don't break tests before committing
- Provide clear rationale for every change

Available tools:
- run_generation: Test the algorithm with specific parameters
- read_file: Read source code to understand implementation
- read_quality_criteria: Understand evaluation standards
- read_tunable_parameters: See what can be safely tuned
- propose_numeric_change: Auto-apply numeric parameter changes
- propose_structural_change: Propose code changes (requires approval)
- run_tests: Validate changes don't break anything
- get_current_metrics: See summary of recent performance

Be systematic and thorough. Each iteration should:
1. Analyze current state
2. Identify one specific issue
3. Propose a targeted fix
4. Validate the improvement"""
    
    def _save_report(self):
        """Save session report to disk."""
        if not self.session:
            return
        
        report_path = REPORTS_DIR / f"session_{self.session.session_id}.md"
        
        report = f"""# Agent Session Report

**Session ID**: {self.session.session_id}
**Started**: {self.session.started_at}
**Completed**: {self.session.completed_at}
**Branch**: {self.session.branch_name}

## Focus Areas
{chr(10).join(f"- {f}" for f in self.session.focus_areas)}

## Summary
- Generations run: {len(self.evaluations)}
- Final avg score: {self.session.final_avg_score:.2f}

## Evaluations
"""
        
        for i, eval_result in enumerate(self.evaluations):
            gen = eval_result.generation
            report += f"""
### Generation {i+1}
- Template: {gen.template.value}
- Duration: {gen.run_minutes}min
- Tracks: {len(gen.track_ids)}
- Overall Score: {eval_result.overall_score:.1f}/10
- Hard Requirements: {'PASS' if eval_result.all_hard_requirements_passed else 'FAIL'}
"""
        
        report_path.write_text(report)
        print(f"\n📄 Report saved: {report_path}")


# =============================================================================
# Entry Point
# =============================================================================

def run_agent_cli():
    """Command-line entry point for the agent."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Run the playlist improvement agent")
    parser.add_argument("--focus", default="overall improvement", help="Focus area for improvements")
    parser.add_argument("--iterations", type=int, default=5, help="Maximum iterations")
    parser.add_argument("--no-subjective", action="store_true", help="Skip subjective evaluation")
    parser.add_argument("--manual-approve", action="store_true", help="Require approval for all changes")
    
    args = parser.parse_args()
    
    orchestrator = AgentOrchestrator(
        use_subjective=not args.no_subjective,
        auto_approve_numeric=not args.manual_approve,
    )
    
    session = orchestrator.run(
        focus=args.focus,
        max_iterations=args.iterations,
    )
    
    print(f"\n{'='*60}")
    print("SESSION COMPLETE")
    print(f"{'='*60}")
    print(f"Session ID: {session.session_id}")
    print(f"Branch: {session.branch_name}")
    print(f"Generations: {len(orchestrator.evaluations)}")
    if orchestrator.evaluations:
        print(f"Final avg score: {session.final_avg_score:.2f}")


if __name__ == "__main__":
    run_agent_cli()
