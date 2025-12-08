"""
Runner module for invoking the Swift CLI and parsing results.

This module provides the bridge between the Python agent and the Swift CLI,
handling subprocess invocation, output parsing, and error handling.
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

from models import (
    GenerationResult,
    TrackSlot,
    EffortTier,
    SourceKind,
    Template,
)
from config import (
    CLI_DIR,
    CLI_EXECUTABLE,
    CLI_TIMEOUT,
    PROJECT_ROOT,
    SIMULATOR_DATA_DIR,
)


class CLIRunner:
    """Runs the Swift CLI and parses results."""
    
    def __init__(self, cli_path: Optional[Path] = None):
        """Initialize the runner.
        
        Args:
            cli_path: Path to the CLI executable. If None, uses default from config.
        """
        self.cli_path = cli_path or CLI_EXECUTABLE
        self._built = False
    
    def ensure_built(self) -> bool:
        """Ensure the CLI is built. Returns True if successful."""
        if self._built:
            return True
        
        # Check if executable exists
        if self.cli_path.exists():
            self._built = True
            return True
        
        # Try to build it
        print("Building CLI...")
        try:
            result = subprocess.run(
                ["swift", "build", "-c", "release"],
                cwd=CLI_DIR,
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode == 0:
                self._built = True
                return True
            else:
                print(f"Build failed: {result.stderr}")
                return False
        except subprocess.TimeoutExpired:
            print("Build timed out")
            return False
        except Exception as e:
            print(f"Build error: {e}")
            return False
    
    def run_generation(
        self,
        template: str,
        minutes: int,
        genres: Optional[list[str]] = None,
        decades: Optional[list[str]] = None,
        include_debug: bool = True,
    ) -> GenerationResult:
        """Run a playlist generation.
        
        Args:
            template: Run template (light, tempo, hiit, intervals, pyramid, kicker)
            minutes: Target run duration in minutes
            genres: Optional list of genre filters
            decades: Optional list of decade filters
            include_debug: Whether to include debug lines in output
            
        Returns:
            GenerationResult with all generation data
            
        Raises:
            RuntimeError: If CLI is not available or generation fails
        """
        if not self.ensure_built():
            raise RuntimeError("CLI not available. Run 'swift build -c release' in cli/")
        
        # Build command
        cmd = [
            str(self.cli_path),
            "generate",
            "--template", template,
            "--minutes", str(minutes),
            "--pretty",
        ]
        
        if genres:
            cmd.extend(["--genres", ",".join(genres)])
        
        if decades:
            cmd.extend(["--decades", ",".join(decades)])
        
        if include_debug:
            cmd.append("--debug")
        
        # Build environment with data directory
        env = dict(os.environ)
        if SIMULATOR_DATA_DIR:
            env["RUNCLUB_DATA_DIR"] = SIMULATOR_DATA_DIR
        
        # Run CLI
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=CLI_TIMEOUT,
                cwd=PROJECT_ROOT,
                env=env,
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"CLI timed out after {CLI_TIMEOUT}s")
        except Exception as e:
            raise RuntimeError(f"CLI execution failed: {e}")
        
        # Check for errors
        if result.returncode != 0:
            # Try to parse error output
            try:
                error_data = json.loads(result.stdout)
                raise RuntimeError(f"Generation failed: {error_data.get('error', 'Unknown error')}")
            except json.JSONDecodeError:
                raise RuntimeError(f"CLI failed with code {result.returncode}: {result.stderr}")
        
        # Parse output - CLI may output warnings before JSON
        stdout = result.stdout
        
        # Find the start of JSON (first '{')
        json_start = stdout.find('{')
        if json_start == -1:
            raise RuntimeError(f"No JSON found in CLI output: {stdout[:500]}")
        
        json_str = stdout[json_start:]
        
        try:
            data = json.loads(json_str)
        except json.JSONDecodeError as e:
            raise RuntimeError(f"Failed to parse CLI output: {e}\nOutput: {json_str[:500]}")
        
        return self._parse_generation_result(data, template, minutes, genres, decades)
    
    def get_data_stats(self) -> dict:
        """Get statistics about available data.
        
        Returns:
            Dictionary with data statistics
        """
        if not self.ensure_built():
            raise RuntimeError("CLI not available")
        
        # Build environment with data directory
        env = dict(os.environ)
        if SIMULATOR_DATA_DIR:
            env["RUNCLUB_DATA_DIR"] = SIMULATOR_DATA_DIR
        
        result = subprocess.run(
            [str(self.cli_path), "info"],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=PROJECT_ROOT,
            env=env,
        )
        
        # Parse text output (info command outputs human-readable text)
        stats = {}
        for line in result.stdout.split("\n"):
            if ":" in line:
                key, value = line.split(":", 1)
                key = key.strip().lower().replace(" ", "_")
                value = value.strip()
                try:
                    stats[key] = int(value)
                except ValueError:
                    stats[key] = value
        
        return stats
    
    def _parse_generation_result(
        self,
        data: dict,
        template: str,
        minutes: int,
        genres: Optional[list[str]],
        decades: Optional[list[str]],
    ) -> GenerationResult:
        """Parse CLI JSON output into GenerationResult model."""
        
        # Parse slots
        slots = []
        for slot_data in data.get("slots", []):
            slots.append(TrackSlot(
                index=slot_data["index"],
                track_id=slot_data["trackId"],
                artist_id=slot_data["artistId"],
                artist_name=slot_data.get("artistName"),
                track_name=slot_data.get("trackName"),
                effort=EffortTier(slot_data["effort"]),
                source=SourceKind(slot_data["source"]),
                segment=slot_data["segment"],
                tempo=slot_data.get("tempo"),
                energy=slot_data.get("energy"),
                danceability=slot_data.get("danceability"),
                duration_ms=slot_data.get("durationSeconds", 0) * 1000,
                tempo_fit=slot_data.get("tempoFit", 0.0),
                effort_index=slot_data.get("effortIndex", 0.0),
                slot_fit=slot_data.get("slotFit", 0.0),
                genre_affinity=slot_data.get("genreAffinity", 0.0),
                is_rediscovery=slot_data.get("isRediscovery", False),
                used_neighbor=slot_data.get("usedNeighbor", False),
                broke_lockout=slot_data.get("brokeLockout", False),
            ))
        
        # Parse efforts
        efforts = [EffortTier(e) for e in data.get("efforts", [])]
        
        # Parse sources
        sources = [SourceKind(s) for s in data.get("sources", [])]
        
        return GenerationResult(
            template=Template(template),
            run_minutes=minutes,
            genres=genres or [],
            decades=decades or [],
            track_ids=data.get("trackIds", []),
            artist_ids=data.get("artistIds", []),
            efforts=efforts,
            sources=sources,
            total_seconds=data.get("totalSeconds", 0),
            min_seconds=data.get("minSeconds", 0),
            max_seconds=data.get("maxSeconds", 0),
            warmup_seconds=data.get("warmupSeconds", 0),
            main_seconds=data.get("mainSeconds", 0),
            cooldown_seconds=data.get("cooldownSeconds", 0),
            warmup_target=data.get("warmupTarget", 0),
            main_target=data.get("mainTarget", 0),
            cooldown_target=data.get("cooldownTarget", 0),
            preflight_unplayable=data.get("preflightUnplayable", 0),
            swapped=data.get("swapped", 0),
            removed=data.get("removed", 0),
            market=data.get("market", "US"),
            slots=slots,
            debug_lines=data.get("debugLines", []),
            avg_tempo_fit=data.get("avgTempoFit", 0.0),
            avg_slot_fit=data.get("avgSlotFit", 0.0),
            avg_genre_affinity=data.get("avgGenreAffinity", 0.0),
            rediscovery_pct=data.get("rediscoveryPct", 0.0),
            unique_artists=data.get("uniqueArtists", 0),
            neighbor_relax_slots=data.get("neighborRelaxSlots", 0),
            lockout_breaks=data.get("lockoutBreaks", 0),
            generated_at=datetime.fromisoformat(data.get("generatedAt", datetime.now().isoformat())),
        )


def run_batch_generations(
    runner: CLIRunner,
    templates: list[str],
    durations: list[int],
    genre_sets: Optional[list[list[str]]] = None,
    decade_sets: Optional[list[list[str]]] = None,
) -> list[GenerationResult]:
    """Run a batch of generations across different parameters.
    
    Args:
        runner: CLI runner instance
        templates: List of templates to test
        durations: List of durations to test
        genre_sets: Optional list of genre filter sets
        decade_sets: Optional list of decade filter sets
        
    Returns:
        List of generation results
    """
    results = []
    
    # Default to no filters if not specified
    if genre_sets is None:
        genre_sets = [[]]  # One empty set = no genre filter
    if decade_sets is None:
        decade_sets = [[]]
    
    for template in templates:
        for duration in durations:
            for genres in genre_sets:
                for decades in decade_sets:
                    try:
                        result = runner.run_generation(
                            template=template,
                            minutes=duration,
                            genres=genres if genres else None,
                            decades=decades if decades else None,
                        )
                        results.append(result)
                        print(f"✓ {template}/{duration}min - {len(result.track_ids)} tracks")
                    except Exception as e:
                        print(f"✗ {template}/{duration}min - {e}")
    
    return results


if __name__ == "__main__":
    # Quick test
    runner = CLIRunner()
    
    try:
        stats = runner.get_data_stats()
        print("Data stats:", stats)
    except Exception as e:
        print(f"Could not get stats: {e}")
    
    try:
        result = runner.run_generation(
            template="tempo",
            minutes=30,
        )
        print(f"\nGeneration result:")
        print(f"  Tracks: {len(result.track_ids)}")
        print(f"  Duration: {result.total_seconds}s")
        print(f"  Avg tempo fit: {result.avg_tempo_fit:.2f}")
        print(f"  Avg slot fit: {result.avg_slot_fit:.2f}")
    except Exception as e:
        print(f"Generation failed: {e}")
