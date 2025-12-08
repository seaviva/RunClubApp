"""
Changelog manager for tracking algorithm versions.

This module maintains CHANGELOG.md with structured version tracking,
making it easy to see how the algorithm has evolved over time.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

from config import AGENT_DIR


CHANGELOG_PATH = AGENT_DIR / "CHANGELOG.md"


@dataclass
class ParameterChange:
    """A single parameter change."""
    parameter: str
    old_value: str
    new_value: str
    rationale: str
    impact: str = ""


@dataclass
class CodeChange:
    """A code-level change."""
    location: str  # e.g., "computeBonuses()" or "selectCandidates()"
    description: str
    rationale: str
    impact: str = ""


@dataclass
class MetricsDelta:
    """Before/after metrics comparison."""
    metric: str
    before: float
    after: float
    
    @property
    def delta(self) -> float:
        return self.after - self.before
    
    @property
    def delta_str(self) -> str:
        d = self.delta
        return f"+{d:.2f}" if d >= 0 else f"{d:.2f}"


@dataclass
class VersionEntry:
    """A complete version entry for the changelog."""
    version: str
    date: str
    summary: str
    parameter_changes: list[ParameterChange] = field(default_factory=list)
    code_changes: list[CodeChange] = field(default_factory=list)
    metrics: list[MetricsDelta] = field(default_factory=list)
    session_id: Optional[str] = None
    branch_name: Optional[str] = None


class ChangelogManager:
    """Manages the algorithm changelog."""
    
    def __init__(self, path: Optional[Path] = None):
        """Initialize the changelog manager.
        
        Args:
            path: Path to CHANGELOG.md. Defaults to agent/CHANGELOG.md.
        """
        self.path = path or CHANGELOG_PATH
    
    def get_current_version(self) -> str:
        """Get the current version number from the changelog."""
        if not self.path.exists():
            return "0.0.0"
        
        content = self.path.read_text()
        
        # Find the first version header (after [Unreleased])
        pattern = r'## \[(\d+\.\d+\.\d+)\]'
        matches = re.findall(pattern, content)
        
        if matches:
            return matches[0]
        return "0.0.0"
    
    def bump_version(self, bump_type: str = "patch") -> str:
        """Bump the version number.
        
        Args:
            bump_type: "major", "minor", or "patch"
            
        Returns:
            New version string
        """
        current = self.get_current_version()
        parts = [int(x) for x in current.split(".")]
        
        if bump_type == "major":
            parts = [parts[0] + 1, 0, 0]
        elif bump_type == "minor":
            parts = [parts[0], parts[1] + 1, 0]
        else:  # patch
            parts = [parts[0], parts[1], parts[2] + 1]
        
        return ".".join(str(p) for p in parts)
    
    def add_version(self, entry: VersionEntry):
        """Add a new version entry to the changelog.
        
        Args:
            entry: Version entry to add
        """
        content = self.path.read_text() if self.path.exists() else ""
        
        # Build the entry markdown
        entry_md = self._format_entry(entry)
        
        # Find where to insert (after [Unreleased] section)
        unreleased_pattern = r'(## \[Unreleased\].*?)(---\n\n## \[)'
        match = re.search(unreleased_pattern, content, re.DOTALL)
        
        if match:
            # Insert after unreleased, before first version
            new_content = (
                content[:match.end(1)] +
                "\n---\n\n" +
                entry_md +
                "\n" +
                content[match.start(2):]
            )
        else:
            # Just append after unreleased
            unreleased_end = content.find("---", content.find("[Unreleased]"))
            if unreleased_end > 0:
                new_content = (
                    content[:unreleased_end + 3] +
                    "\n\n" +
                    entry_md +
                    content[unreleased_end + 3:]
                )
            else:
                new_content = content + "\n\n" + entry_md
        
        self.path.write_text(new_content)
        print(f"Added version {entry.version} to changelog")
    
    def _format_entry(self, entry: VersionEntry) -> str:
        """Format a version entry as markdown."""
        lines = [
            f"## [{entry.version}] - {entry.date}",
            "",
            "### Summary",
            entry.summary,
            "",
        ]
        
        if entry.parameter_changes:
            lines.extend([
                "### Parameter Changes",
                "",
            ])
            for pc in entry.parameter_changes:
                lines.append(f"- **`{pc.parameter}`**: {pc.old_value} → {pc.new_value}")
                lines.append(f"  - Rationale: {pc.rationale}")
                if pc.impact:
                    lines.append(f"  - Impact: {pc.impact}")
                lines.append("")
        
        if entry.code_changes:
            lines.extend([
                "### Code Changes",
                "",
            ])
            for cc in entry.code_changes:
                lines.append(f"- **{cc.location}**: {cc.description}")
                lines.append(f"  - Rationale: {cc.rationale}")
                if cc.impact:
                    lines.append(f"  - Impact: {cc.impact}")
                lines.append("")
        
        if entry.metrics:
            lines.extend([
                "### Before/After Metrics",
                "",
                "| Metric | Before | After | Delta |",
                "|--------|--------|-------|-------|",
            ])
            for m in entry.metrics:
                lines.append(f"| {m.metric} | {m.before:.2f} | {m.after:.2f} | {m.delta_str} |")
            lines.append("")
        
        if entry.session_id or entry.branch_name:
            lines.extend([
                "### Agent Session",
                "",
            ])
            if entry.session_id:
                lines.append(f"- Session ID: {entry.session_id}")
            if entry.branch_name:
                lines.append(f"- Branch: {entry.branch_name}")
            lines.append("")
        
        return "\n".join(lines)
    
    def log_agent_changes(
        self,
        changes: list[dict],
        before_metrics: dict[str, float],
        after_metrics: dict[str, float],
        session_id: str,
        branch_name: str,
        bump_type: str = "patch",
    ) -> str:
        """Log changes made by the agent.
        
        Args:
            changes: List of change dicts with keys: file, old_code, new_code, rationale
            before_metrics: Metrics before changes
            after_metrics: Metrics after changes
            session_id: Agent session ID
            branch_name: Git branch name
            bump_type: Version bump type
            
        Returns:
            New version string
        """
        new_version = self.bump_version(bump_type)
        
        # Parse changes into typed objects
        param_changes = []
        code_changes = []
        
        for change in changes:
            rationale = change.get("rationale", "")
            
            # Determine if it's a parameter or code change
            if any(kw in rationale.lower() for kw in ["tune", "adjust", "→", "->"]):
                # Likely a parameter change
                param_changes.append(ParameterChange(
                    parameter=self._extract_param_name(change.get("old_code", "")),
                    old_value=self._extract_value(change.get("old_code", "")),
                    new_value=self._extract_value(change.get("new_code", "")),
                    rationale=rationale,
                ))
            else:
                # Code change
                code_changes.append(CodeChange(
                    location=change.get("file", "Unknown").split("/")[-1],
                    description=rationale[:100],
                    rationale=rationale,
                ))
        
        # Build metrics deltas
        metrics = []
        for metric in before_metrics:
            if metric in after_metrics:
                metrics.append(MetricsDelta(
                    metric=metric,
                    before=before_metrics[metric],
                    after=after_metrics[metric],
                ))
        
        # Create and add entry
        entry = VersionEntry(
            version=new_version,
            date=datetime.now().strftime("%Y-%m-%d"),
            summary=f"Agent-driven improvements focusing on {len(changes)} change(s).",
            parameter_changes=param_changes,
            code_changes=code_changes,
            metrics=metrics,
            session_id=session_id,
            branch_name=branch_name,
        )
        
        self.add_version(entry)
        return new_version
    
    def _extract_param_name(self, code: str) -> str:
        """Try to extract parameter name from code snippet."""
        # Look for patterns like "tempoToleranceBPM: 15"
        match = re.search(r'(\w+)\s*[:=]\s*[\d.]+', code)
        if match:
            return match.group(1)
        return code[:30].strip()
    
    def _extract_value(self, code: str) -> str:
        """Try to extract value from code snippet."""
        # Look for numeric values
        match = re.search(r'[:=]\s*([\d.]+)', code)
        if match:
            return match.group(1)
        # Look for tuple values
        match = re.search(r'\(([\d.,\s]+)\)', code)
        if match:
            return f"({match.group(1)})"
        return code[:20].strip()
    
    def update_parameter_table(self, parameter: str, value: str, version: str):
        """Update the quick reference parameter table.
        
        Args:
            parameter: Parameter name
            value: New value
            version: Version where changed
        """
        content = self.path.read_text()
        
        # Find the parameter in the table
        pattern = rf'(\| `{re.escape(parameter)}` \|) [^|]+ (\| [^|]+ \|)'
        replacement = rf'\1 {value} \2'
        
        if re.search(pattern, content):
            # Update existing row
            new_content = re.sub(pattern, replacement, content)
        else:
            # Add new row (find end of table)
            table_pattern = r'(\| `[^`]+` \| [^|]+ \| [^|]+ \|)\n(\n### Version History)'
            match = re.search(table_pattern, content)
            if match:
                new_row = f"\n| `{parameter}` | {value} | {version} |"
                new_content = content[:match.end(1)] + new_row + content[match.start(2):]
            else:
                new_content = content
        
        self.path.write_text(new_content)


if __name__ == "__main__":
    # Demo
    manager = ChangelogManager()
    print(f"Current version: {manager.get_current_version()}")
    print(f"Next patch: {manager.bump_version('patch')}")
    print(f"Next minor: {manager.bump_version('minor')}")
