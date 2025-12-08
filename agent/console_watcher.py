"""
Console log watcher for ingesting live app output.

This module monitors console output from the iOS app (via Xcode or log files)
and can trigger agent improvements based on generation results seen in logs.

## How It Works

There are several ways to capture app console output:

1. **Xcode Console** (Development):
   - When running via Xcode, logs appear in the debug console
   - We can capture these by redirecting to a file or using log streaming

2. **Unified Logging** (macOS):
   - Use `log stream` to capture logs from the app
   - Filter by subsystem (com.runclub.app)

3. **Log File** (App writes to file):
   - App can write generation logs to a shared location
   - This module watches that file for changes

4. **Simulator Logs**:
   - Simulator logs are stored in ~/Library/Logs/CoreSimulator/

## Usage

```python
watcher = ConsoleWatcher()

# Option 1: Watch a specific log file
watcher.watch_file("/path/to/generation.log")

# Option 2: Stream from unified logging
watcher.stream_unified_logs()

# Option 3: Parse a pasted log
result = watcher.parse_generation_log(log_text)
```
"""

import json
import os
import re
import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Optional
import threading

from models import GenerationResult, EvaluationResult, EffortTier, SourceKind, Template, TrackSlot
from config import AGENT_DIR, PROJECT_ROOT


@dataclass
class ParsedGeneration:
    """A generation parsed from console logs."""
    timestamp: datetime
    template: str
    run_minutes: int
    genres: list[str] = field(default_factory=list)
    decades: list[str] = field(default_factory=list)
    
    # Parsed slots
    slots: list[dict] = field(default_factory=list)
    
    # Metrics extracted from log
    total_tracks: int = 0
    total_seconds: int = 0
    avg_tempo_fit: float = 0.0
    avg_slot_fit: float = 0.0
    rediscovery_pct: float = 0.0
    
    # Segment info
    warmup_seconds: int = 0
    main_seconds: int = 0
    cooldown_seconds: int = 0
    
    # Raw log lines
    debug_lines: list[str] = field(default_factory=list)
    
    # Any issues detected
    issues: list[str] = field(default_factory=list)


class LogParser:
    """Parses generation logs from the app's console output."""
    
    # Regex patterns for parsing log lines
    PATTERNS = {
        # LocalGen config — template:tempo run:30m segmentsPlanned:[wu:7m main:18m cd:5m] filters:...
        "config": re.compile(
            r'LocalGen config — template:(\w+) run:(\d+)m '
            r'segmentsPlanned:\[wu:(\d+)m (?:main|core):(\d+)m cd:(\d+)m\] '
            r'filters:genres=\[([^\]]*)\] decades=\[([^\]]*)\]'
        ),
        
        # Slot #0 seg=warmup [easy] tol=15 tgt=0.40 • Artist — Track • tempo=155 energy=0.50 dance=0.60...
        "slot": re.compile(
            r'Slot #(\d+) seg=(\w+) \[(\w+)\] tol=(\d+) tgt=([\d.]+) • '
            r'([^•]+) — ([^•]+) • '
            r'tempo=([\d.]+) energy=([\d.]+) dance=([\d.]+) dur=(\d+:\d+) • '
            r'tempoFit=([\d.]+) effortIdx=([\d.]+) slotFit=([\d.]+)'
        ),
        
        # LocalGen metrics — tracks:12 time:1820s rediscovery:50% tempoFit:0.75 slotFit:0.80...
        "metrics": re.compile(
            r'LocalGen metrics — tracks:(\d+) time:(\d+)s '
            r'(?:rediscovery:(\d+)% )?'
            r'(?:tempoFit:([\d.]+) )?'
            r'(?:slotFit:([\d.]+))?'
        ),
        
        # Pool build — total:500 lockoutFiltered:20 resulting:350
        "pool": re.compile(
            r'Pool build — total:(\d+) (?:lockoutFiltered:(\d+) )?(?:candidates:|resulting:)(\d+)'
        ),
        
        # segCheck:[wu:PASS cd:FAIL]
        "seg_check": re.compile(
            r'segCheck:\[wu:(PASS|FAIL) cd:(PASS|FAIL)\]'
        ),
    }
    
    def parse(self, log_text: str) -> Optional[ParsedGeneration]:
        """Parse a generation log into structured data.
        
        Args:
            log_text: Raw log text (can be multiple lines)
            
        Returns:
            ParsedGeneration or None if no generation found
        """
        lines = log_text.strip().split("\n")
        
        # Find config line to start
        config_match = None
        for line in lines:
            config_match = self.PATTERNS["config"].search(line)
            if config_match:
                break
        
        if not config_match:
            return None
        
        # Extract config
        template = config_match.group(1)
        run_minutes = int(config_match.group(2))
        wu_minutes = int(config_match.group(3))
        core_minutes = int(config_match.group(4))
        cd_minutes = int(config_match.group(5))
        genres_str = config_match.group(6)
        decades_str = config_match.group(7)
        
        genres = [g.strip() for g in genres_str.split(",") if g.strip() and g.strip() != "none"]
        decades = [d.strip() for d in decades_str.split(",") if d.strip() and d.strip() != "none"]
        
        # Parse slots
        slots = []
        for line in lines:
            slot_match = self.PATTERNS["slot"].search(line)
            if slot_match:
                slots.append({
                    "index": int(slot_match.group(1)),
                    "segment": slot_match.group(2),
                    "effort": slot_match.group(3),
                    "tolerance": int(slot_match.group(4)),
                    "target_effort": float(slot_match.group(5)),
                    "artist": slot_match.group(6).strip(),
                    "track": slot_match.group(7).strip(),
                    "tempo": float(slot_match.group(8)),
                    "energy": float(slot_match.group(9)),
                    "danceability": float(slot_match.group(10)),
                    "duration": slot_match.group(11),
                    "tempo_fit": float(slot_match.group(12)),
                    "effort_index": float(slot_match.group(13)),
                    "slot_fit": float(slot_match.group(14)),
                })
        
        # Parse metrics
        metrics_match = None
        for line in lines:
            metrics_match = self.PATTERNS["metrics"].search(line)
            if metrics_match:
                break
        
        total_tracks = int(metrics_match.group(1)) if metrics_match else len(slots)
        total_seconds = int(metrics_match.group(2)) if metrics_match else 0
        rediscovery_pct = float(metrics_match.group(3)) / 100 if metrics_match and metrics_match.group(3) else 0.0
        avg_tempo_fit = float(metrics_match.group(4)) if metrics_match and metrics_match.group(4) else 0.0
        avg_slot_fit = float(metrics_match.group(5)) if metrics_match and metrics_match.group(5) else 0.0
        
        # Detect issues
        issues = []
        for line in lines:
            seg_check = self.PATTERNS["seg_check"].search(line)
            if seg_check:
                if seg_check.group(1) == "FAIL":
                    issues.append("Warmup duration out of tolerance")
                if seg_check.group(2) == "FAIL":
                    issues.append("Cooldown duration out of tolerance")
        
        # Check for low metrics
        if avg_tempo_fit > 0 and avg_tempo_fit < 0.65:
            issues.append(f"Low average tempo fit: {avg_tempo_fit:.2f}")
        if avg_slot_fit > 0 and avg_slot_fit < 0.70:
            issues.append(f"Low average slot fit: {avg_slot_fit:.2f}")
        
        return ParsedGeneration(
            timestamp=datetime.now(),
            template=template,
            run_minutes=run_minutes,
            genres=genres,
            decades=decades,
            slots=slots,
            total_tracks=total_tracks,
            total_seconds=total_seconds,
            avg_tempo_fit=avg_tempo_fit,
            avg_slot_fit=avg_slot_fit,
            rediscovery_pct=rediscovery_pct,
            warmup_seconds=wu_minutes * 60,
            main_seconds=core_minutes * 60,
            cooldown_seconds=cd_minutes * 60,
            debug_lines=[l for l in lines if "LocalGen" in l or "Slot #" in l],
            issues=issues,
        )
    
    def to_generation_result(self, parsed: ParsedGeneration) -> GenerationResult:
        """Convert ParsedGeneration to GenerationResult for evaluation."""
        slots = []
        for s in parsed.slots:
            slots.append(TrackSlot(
                index=s["index"],
                track_id=f"parsed_{s['index']}",
                artist_id=f"artist_{s['index']}",
                artist_name=s["artist"],
                track_name=s["track"],
                effort=EffortTier(s["effort"]),
                source=SourceKind.LIKES,
                segment=s["segment"],
                tempo=s["tempo"],
                energy=s["energy"],
                danceability=s["danceability"],
                duration_ms=self._parse_duration(s["duration"]) * 1000,
                tempo_fit=s["tempo_fit"],
                effort_index=s["effort_index"],
                slot_fit=s["slot_fit"],
                genre_affinity=0.0,
                is_rediscovery=False,
            ))
        
        return GenerationResult(
            template=Template(parsed.template),
            run_minutes=parsed.run_minutes,
            genres=parsed.genres,
            decades=parsed.decades,
            track_ids=[f"parsed_{i}" for i in range(len(slots))],
            artist_ids=[f"artist_{i}" for i in range(len(slots))],
            efforts=[EffortTier(s["effort"]) for s in parsed.slots],
            sources=[SourceKind.LIKES] * len(slots),
            total_seconds=parsed.total_seconds,
            warmup_seconds=parsed.warmup_seconds,
            main_seconds=parsed.main_seconds,
            cooldown_seconds=parsed.cooldown_seconds,
            warmup_target=parsed.warmup_seconds,
            cooldown_target=parsed.cooldown_seconds,
            slots=slots,
            debug_lines=parsed.debug_lines,
            avg_tempo_fit=parsed.avg_tempo_fit,
            avg_slot_fit=parsed.avg_slot_fit,
            rediscovery_pct=parsed.rediscovery_pct,
            unique_artists=len(set(s["artist"] for s in parsed.slots)),
        )
    
    def _parse_duration(self, dur_str: str) -> int:
        """Parse duration string like '3:30' to seconds."""
        parts = dur_str.split(":")
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        return 0


class ConsoleWatcher:
    """Watches for and processes console output from the app."""
    
    def __init__(self, on_generation: Optional[Callable[[ParsedGeneration], None]] = None):
        """Initialize the console watcher.
        
        Args:
            on_generation: Callback when a generation is detected
        """
        self.parser = LogParser()
        self.on_generation = on_generation
        self._watching = False
        self._watch_thread: Optional[threading.Thread] = None
        
        # Buffer for accumulating log lines
        self._buffer: list[str] = []
    
    def parse_log(self, log_text: str) -> Optional[ParsedGeneration]:
        """Parse a log text and return structured data.
        
        Args:
            log_text: Raw log text
            
        Returns:
            ParsedGeneration or None
        """
        return self.parser.parse(log_text)
    
    def watch_file(self, path: str, poll_interval: float = 1.0):
        """Watch a log file for new generations.
        
        Args:
            path: Path to the log file
            poll_interval: How often to check for changes (seconds)
        """
        self._watching = True
        file_path = Path(path)
        last_size = 0
        
        print(f"Watching log file: {path}")
        print("Press Ctrl+C to stop")
        
        try:
            while self._watching:
                if file_path.exists():
                    current_size = file_path.stat().st_size
                    if current_size > last_size:
                        # Read new content
                        with open(file_path, 'r') as f:
                            f.seek(last_size)
                            new_content = f.read()
                        
                        self._process_content(new_content)
                        last_size = current_size
                
                time.sleep(poll_interval)
        except KeyboardInterrupt:
            print("\nStopped watching")
            self._watching = False
    
    def stream_unified_logs(self, subsystem: str = "com.runclub"):
        """Stream logs from macOS unified logging.
        
        Args:
            subsystem: App subsystem to filter by
        """
        print(f"Streaming unified logs for subsystem: {subsystem}")
        print("Press Ctrl+C to stop")
        
        try:
            process = subprocess.Popen(
                ["log", "stream", "--predicate", f'subsystem == "{subsystem}"', "--style", "compact"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            
            self._watching = True
            while self._watching:
                line = process.stdout.readline()
                if line:
                    self._buffer.append(line)
                    
                    # Check if we have a complete generation
                    if "LocalGen metrics" in line:
                        self._process_buffer()
                
        except KeyboardInterrupt:
            print("\nStopped streaming")
            self._watching = False
            process.terminate()
    
    def watch_simulator_logs(self):
        """Watch iOS Simulator logs for generations."""
        # Find the most recent simulator log
        sim_logs = Path.home() / "Library" / "Logs" / "CoreSimulator"
        
        if not sim_logs.exists():
            print("Simulator logs directory not found")
            return
        
        # Find most recent device folder
        device_folders = sorted(sim_logs.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True)
        
        if not device_folders:
            print("No simulator devices found")
            return
        
        log_file = device_folders[0] / "system.log"
        if log_file.exists():
            self.watch_file(str(log_file))
        else:
            print(f"No system.log found in {device_folders[0]}")
    
    def _process_content(self, content: str):
        """Process new log content."""
        lines = content.split("\n")
        self._buffer.extend(lines)
        
        # Look for complete generations
        buffer_text = "\n".join(self._buffer)
        if "LocalGen metrics" in buffer_text:
            self._process_buffer()
    
    def _process_buffer(self):
        """Process accumulated buffer for generations."""
        buffer_text = "\n".join(self._buffer)
        
        parsed = self.parser.parse(buffer_text)
        if parsed:
            print(f"\n📱 Detected generation: {parsed.template}/{parsed.run_minutes}min")
            print(f"   Tracks: {parsed.total_tracks}, Duration: {parsed.total_seconds}s")
            print(f"   Tempo Fit: {parsed.avg_tempo_fit:.2f}, Slot Fit: {parsed.avg_slot_fit:.2f}")
            
            if parsed.issues:
                print(f"   ⚠️  Issues: {', '.join(parsed.issues)}")
            
            if self.on_generation:
                self.on_generation(parsed)
        
        # Clear buffer
        self._buffer = []
    
    def stop(self):
        """Stop watching."""
        self._watching = False


class LiveAgentTrigger:
    """Triggers agent improvements based on live console output."""
    
    def __init__(
        self,
        evaluator,
        modifier,
        changelog_manager,
        min_score_for_improvement: float = 6.0,
        auto_apply: bool = False,
    ):
        """Initialize the live trigger.
        
        Args:
            evaluator: Evaluator instance
            modifier: SafeModifier instance
            changelog_manager: ChangelogManager instance
            min_score_for_improvement: Threshold below which to trigger improvements
            auto_apply: Whether to auto-apply changes
        """
        self.evaluator = evaluator
        self.modifier = modifier
        self.changelog = changelog_manager
        self.min_score = min_score_for_improvement
        self.auto_apply = auto_apply
        
        self.watcher = ConsoleWatcher(on_generation=self._on_generation)
        self.parser = LogParser()
        
        # Track recent generations for comparison
        self.recent_generations: list[ParsedGeneration] = []
        self.max_recent = 10
    
    def _on_generation(self, parsed: ParsedGeneration):
        """Handle a new generation from console logs."""
        # Store for comparison
        self.recent_generations.append(parsed)
        if len(self.recent_generations) > self.max_recent:
            self.recent_generations.pop(0)
        
        # Convert to GenerationResult and evaluate
        gen_result = self.parser.to_generation_result(parsed)
        eval_result = self.evaluator.evaluate(gen_result)
        
        print(f"\n📊 Evaluation: {eval_result.overall_score:.1f}/10")
        
        # Check if improvement needed
        if eval_result.overall_score < self.min_score:
            print(f"   Score below threshold ({self.min_score}), analyzing for improvements...")
            self._analyze_for_improvements(parsed, eval_result)
    
    def _analyze_for_improvements(self, parsed: ParsedGeneration, eval_result: EvaluationResult):
        """Analyze a poor generation and suggest improvements."""
        suggestions = []
        
        # Check which dimensions are weakest
        for dim in eval_result.dimension_scores:
            if dim.score < 6.0:
                suggestions.append(f"Weak {dim.name} ({dim.score:.1f}/10): {', '.join(dim.issues[:2])}")
        
        # Check for specific issues
        if parsed.avg_tempo_fit < 0.65:
            suggestions.append(
                f"Low tempo fit ({parsed.avg_tempo_fit:.2f}). "
                "Consider widening tempo tolerance or adjusting BPM windows."
            )
        
        if parsed.avg_slot_fit < 0.70:
            suggestions.append(
                f"Low slot fit ({parsed.avg_slot_fit:.2f}). "
                "Consider adjusting tier weights or effort index calculation."
            )
        
        # Check for slot-level issues
        for slot in parsed.slots:
            if slot["tempo_fit"] < 0.40:
                suggestions.append(
                    f"Track {slot['index']} ({slot['artist']} - {slot['track']}) has very low tempo fit "
                    f"({slot['tempo_fit']:.2f}) for {slot['effort']} slot."
                )
        
        if suggestions:
            print("\n💡 Improvement Suggestions:")
            for i, s in enumerate(suggestions[:5], 1):
                print(f"   {i}. {s}")
            
            if self.auto_apply:
                print("\n🤖 Auto-apply is enabled - would trigger agent here")
                # In a full implementation, this would start the agent
    
    def start_watching(self, log_path: Optional[str] = None):
        """Start watching for generations.
        
        Args:
            log_path: Path to log file. If None, tries simulator logs.
        """
        if log_path:
            self.watcher.watch_file(log_path)
        else:
            self.watcher.watch_simulator_logs()
    
    def process_pasted_log(self, log_text: str):
        """Process a manually pasted log.
        
        Args:
            log_text: Raw log text
        """
        parsed = self.parser.parse(log_text)
        if parsed:
            self._on_generation(parsed)
        else:
            print("Could not parse generation from log text")


def interactive_log_input():
    """Interactive mode for pasting logs."""
    print("=" * 60)
    print("LIVE LOG ANALYZER")
    print("=" * 60)
    print("\nPaste your console log below, then press Enter twice:")
    print("(Type 'quit' to exit)\n")
    
    parser = LogParser()
    
    from evaluator import ObjectiveEvaluator
    evaluator = ObjectiveEvaluator()
    
    while True:
        lines = []
        while True:
            try:
                line = input()
                if line.lower() == 'quit':
                    return
                if line == "" and lines and lines[-1] == "":
                    break
                lines.append(line)
            except EOFError:
                break
        
        if not lines:
            continue
        
        log_text = "\n".join(lines)
        parsed = parser.parse(log_text)
        
        if parsed:
            print(f"\n✅ Parsed generation: {parsed.template}/{parsed.run_minutes}min")
            print(f"   Tracks: {parsed.total_tracks}")
            print(f"   Duration: {parsed.total_seconds}s")
            print(f"   Tempo Fit: {parsed.avg_tempo_fit:.2f}")
            print(f"   Slot Fit: {parsed.avg_slot_fit:.2f}")
            print(f"   Slots: {len(parsed.slots)}")
            
            if parsed.issues:
                print(f"\n   ⚠️  Issues detected:")
                for issue in parsed.issues:
                    print(f"      - {issue}")
            
            # Evaluate
            gen_result = parser.to_generation_result(parsed)
            eval_result = evaluator.evaluate(gen_result)
            
            print(f"\n📊 Evaluation Score: {eval_result.overall_score:.1f}/10")
            for dim in eval_result.dimension_scores:
                marker = "⚠️ " if dim.score < 6.0 else "   "
                print(f"{marker}{dim.name}: {dim.score:.1f}/10")
        else:
            print("\n❌ Could not parse generation from log")
        
        print("\n" + "-" * 40)
        print("Paste another log or type 'quit' to exit:\n")


if __name__ == "__main__":
    interactive_log_input()
