"""
Modifier module for safe code modifications.

This module handles proposing, validating, and applying code changes
with git-based safety (branches, commits, rollback capability).
"""

import os
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional
import uuid

from models import CodeChange, ChangeResult, ParameterChange
from config import (
    PROJECT_ROOT,
    LOCAL_GENERATOR_PATH,
    GIT_BRANCH_PREFIX,
    GIT_COMMIT_PREFIX,
    MIN_IMPROVEMENT_DELTA,
)


class SafeModifier:
    """Handles safe code modifications with git integration."""
    
    def __init__(self, repo_path: Optional[Path] = None):
        """Initialize the modifier.
        
        Args:
            repo_path: Path to the git repository. Defaults to PROJECT_ROOT.
        """
        self.repo_path = repo_path or PROJECT_ROOT
        self._current_branch: Optional[str] = None
        self._original_branch: Optional[str] = None
    
    # =========================================================================
    # Git Operations
    # =========================================================================
    
    def _run_git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        """Run a git command."""
        cmd = ["git"] + list(args)
        return subprocess.run(
            cmd,
            cwd=self.repo_path,
            capture_output=True,
            text=True,
            check=check,
        )
    
    def get_current_branch(self) -> str:
        """Get the current git branch name."""
        result = self._run_git("rev-parse", "--abbrev-ref", "HEAD")
        return result.stdout.strip()
    
    def has_uncommitted_changes(self) -> bool:
        """Check if there are uncommitted changes."""
        result = self._run_git("status", "--porcelain")
        return bool(result.stdout.strip())
    
    def create_agent_branch(self, focus: str = "improvement") -> str:
        """Create a new branch for agent changes.
        
        Args:
            focus: Description of the improvement focus
            
        Returns:
            Name of the created branch
        """
        # Store original branch
        self._original_branch = self.get_current_branch()
        
        # Create branch name
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_focus = re.sub(r'[^a-zA-Z0-9_-]', '_', focus.lower())[:30]
        branch_name = f"{GIT_BRANCH_PREFIX}{safe_focus}_{timestamp}"
        
        # Create and checkout branch
        self._run_git("checkout", "-b", branch_name)
        self._current_branch = branch_name
        
        return branch_name
    
    def commit_change(self, message: str, files: Optional[list[str]] = None) -> str:
        """Commit changes with a message.
        
        Args:
            message: Commit message
            files: Specific files to commit. If None, commits all changes.
            
        Returns:
            Commit SHA
        """
        # Stage files
        if files:
            for f in files:
                self._run_git("add", f)
        else:
            self._run_git("add", "-A")
        
        # Commit
        full_message = f"{GIT_COMMIT_PREFIX} {message}"
        self._run_git("commit", "-m", full_message)
        
        # Get commit SHA
        result = self._run_git("rev-parse", "HEAD")
        return result.stdout.strip()[:8]
    
    def rollback_last_commit(self) -> bool:
        """Rollback the last commit.
        
        Returns:
            True if successful
        """
        try:
            self._run_git("reset", "--hard", "HEAD~1")
            return True
        except subprocess.CalledProcessError:
            return False
    
    def return_to_original_branch(self) -> bool:
        """Return to the original branch before agent changes.
        
        Returns:
            True if successful
        """
        if self._original_branch:
            try:
                self._run_git("checkout", self._original_branch)
                return True
            except subprocess.CalledProcessError:
                return False
        return False
    
    def delete_branch(self, branch_name: str, force: bool = False) -> bool:
        """Delete a branch.
        
        Args:
            branch_name: Branch to delete
            force: Force delete even if not merged
            
        Returns:
            True if successful
        """
        try:
            flag = "-D" if force else "-d"
            self._run_git("branch", flag, branch_name)
            return True
        except subprocess.CalledProcessError:
            return False
    
    # =========================================================================
    # Code Reading
    # =========================================================================
    
    def read_file(self, path: Path) -> str:
        """Read a file's contents.
        
        Args:
            path: Path to the file (relative to repo or absolute)
            
        Returns:
            File contents
        """
        if not path.is_absolute():
            path = self.repo_path / path
        return path.read_text()
    
    def find_in_file(self, path: Path, pattern: str) -> list[tuple[int, str]]:
        """Find lines matching a pattern.
        
        Args:
            path: Path to the file
            pattern: Regex pattern to match
            
        Returns:
            List of (line_number, line_content) tuples
        """
        content = self.read_file(path)
        regex = re.compile(pattern)
        matches = []
        
        for i, line in enumerate(content.split("\n"), 1):
            if regex.search(line):
                matches.append((i, line))
        
        return matches
    
    # =========================================================================
    # Code Modification
    # =========================================================================
    
    def apply_change(self, change: CodeChange) -> ChangeResult:
        """Apply a code change.
        
        Args:
            change: The change to apply
            
        Returns:
            ChangeResult with success/failure info
        """
        path = Path(change.file_path)
        if not path.is_absolute():
            path = self.repo_path / path
        
        try:
            # Read current content
            content = path.read_text()
            
            # Verify old_code exists
            if change.old_code not in content:
                return ChangeResult(
                    change=change,
                    success=False,
                    error=f"Could not find the code to replace in {change.file_path}",
                )
            
            # Apply replacement
            new_content = content.replace(change.old_code, change.new_code, 1)
            
            # Verify change was made
            if new_content == content:
                return ChangeResult(
                    change=change,
                    success=False,
                    error="No change was made (old_code == new_code?)",
                )
            
            # Write new content
            path.write_text(new_content)
            
            # Mark as applied
            change.applied = True
            
            return ChangeResult(
                change=change,
                success=True,
                branch_name=self._current_branch,
            )
            
        except Exception as e:
            return ChangeResult(
                change=change,
                success=False,
                error=str(e),
            )
    
    def revert_change(self, change: CodeChange) -> bool:
        """Revert a previously applied change.
        
        Args:
            change: The change to revert
            
        Returns:
            True if successful
        """
        if not change.applied:
            return False
        
        # Swap old and new to revert
        revert = CodeChange(
            file_path=change.file_path,
            old_code=change.new_code,
            new_code=change.old_code,
            rationale=f"Revert: {change.rationale}",
        )
        
        result = self.apply_change(revert)
        if result.success:
            change.applied = False
        return result.success
    
    # =========================================================================
    # Numeric Tuning (Auto-Apply)
    # =========================================================================
    
    def create_numeric_change(
        self,
        file_path: str,
        parameter_name: str,
        old_value: str,
        new_value: str,
        rationale: str,
    ) -> CodeChange:
        """Create a numeric parameter change.
        
        Args:
            file_path: Path to the file to modify
            parameter_name: Name of the parameter being changed
            old_value: Current value (as string)
            new_value: New value (as string)
            rationale: Reason for the change
            
        Returns:
            CodeChange ready to apply
        """
        return CodeChange(
            file_path=file_path,
            old_code=old_value,
            new_code=new_value,
            rationale=f"{parameter_name}: {old_value} -> {new_value}. {rationale}",
            is_structural=False,
            change_id=str(uuid.uuid4())[:8],
        )
    
    def find_and_update_numeric(
        self,
        file_path: Path,
        pattern: str,
        group: int,
        new_value: str,
        rationale: str,
    ) -> Optional[CodeChange]:
        """Find a numeric value by pattern and create a change to update it.
        
        Args:
            file_path: Path to the file
            pattern: Regex pattern with groups
            group: Which group contains the value to change
            new_value: New value to use
            rationale: Reason for the change
            
        Returns:
            CodeChange if pattern found, None otherwise
        """
        content = self.read_file(file_path)
        regex = re.compile(pattern)
        match = regex.search(content)
        
        if not match:
            return None
        
        old_code = match.group(0)
        old_value = match.group(group)
        new_code = old_code.replace(old_value, new_value, 1)
        
        return CodeChange(
            file_path=str(file_path),
            old_code=old_code,
            new_code=new_code,
            rationale=f"Tuning: {old_value} -> {new_value}. {rationale}",
            is_structural=False,
            change_id=str(uuid.uuid4())[:8],
        )
    
    # =========================================================================
    # Structural Changes (Require Approval)
    # =========================================================================
    
    def create_structural_change(
        self,
        file_path: str,
        old_code: str,
        new_code: str,
        rationale: str,
    ) -> CodeChange:
        """Create a structural code change (requires approval).
        
        Args:
            file_path: Path to the file to modify
            old_code: Code to replace
            new_code: New code
            rationale: Reason for the change
            
        Returns:
            CodeChange marked as structural
        """
        return CodeChange(
            file_path=file_path,
            old_code=old_code,
            new_code=new_code,
            rationale=rationale,
            is_structural=True,
            change_id=str(uuid.uuid4())[:8],
        )
    
    def request_approval(self, change: CodeChange) -> bool:
        """Request user approval for a structural change.
        
        Args:
            change: The change requiring approval
            
        Returns:
            True if approved
        """
        print("\n" + "=" * 60)
        print("STRUCTURAL CHANGE REQUIRES APPROVAL")
        print("=" * 60)
        print(f"\nFile: {change.file_path}")
        print(f"\nRationale: {change.rationale}")
        print(f"\n--- OLD CODE ---")
        print(change.old_code)
        print(f"\n--- NEW CODE ---")
        print(change.new_code)
        print("\n" + "=" * 60)
        
        while True:
            response = input("\nApprove this change? [y/n/d(iff)]: ").strip().lower()
            if response == 'y':
                change.approved = True
                return True
            elif response == 'n':
                change.approved = False
                return False
            elif response == 'd':
                # Show a simple diff
                old_lines = change.old_code.split("\n")
                new_lines = change.new_code.split("\n")
                print("\nDiff:")
                for i, (old, new) in enumerate(zip(old_lines, new_lines)):
                    if old != new:
                        print(f"  - {old}")
                        print(f"  + {new}")
    
    # =========================================================================
    # Test Running
    # =========================================================================
    
    def run_tests(self) -> tuple[bool, str]:
        """Run the test suite.
        
        Returns:
            Tuple of (success, output)
        """
        try:
            result = subprocess.run(
                ["swift", "test"],
                cwd=self.repo_path / "RunClub",
                capture_output=True,
                text=True,
                timeout=300,
            )
            return result.returncode == 0, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return False, "Tests timed out"
        except Exception as e:
            return False, str(e)
    
    def run_swift_build(self) -> tuple[bool, str]:
        """Run swift build to check for compilation errors.
        
        Returns:
            Tuple of (success, output)
        """
        try:
            result = subprocess.run(
                ["swift", "build"],
                cwd=self.repo_path / "cli",
                capture_output=True,
                text=True,
                timeout=120,
            )
            return result.returncode == 0, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return False, "Build timed out"
        except Exception as e:
            return False, str(e)
    
    # =========================================================================
    # Convenience Methods
    # =========================================================================
    
    def apply_and_test(self, change: CodeChange) -> ChangeResult:
        """Apply a change and run tests to validate.
        
        Args:
            change: The change to apply
            
        Returns:
            ChangeResult with test validation
        """
        # Apply the change
        result = self.apply_change(change)
        if not result.success:
            return result
        
        # Run build check
        build_ok, build_output = self.run_swift_build()
        if not build_ok:
            # Revert and report failure
            self.revert_change(change)
            result.success = False
            result.error = f"Build failed after change: {build_output[:500]}"
            return result
        
        return result
    
    def apply_with_approval(self, change: CodeChange) -> ChangeResult:
        """Apply a change, requesting approval if structural.
        
        Args:
            change: The change to apply
            
        Returns:
            ChangeResult
        """
        if change.is_structural and not change.approved:
            if not self.request_approval(change):
                return ChangeResult(
                    change=change,
                    success=False,
                    error="Change was not approved",
                )
        
        return self.apply_and_test(change)


class ParameterTuner:
    """Specialized tuner for LocalGenerator parameters."""
    
    def __init__(self, modifier: SafeModifier):
        """Initialize the tuner.
        
        Args:
            modifier: SafeModifier instance to use
        """
        self.modifier = modifier
        self.file_path = LOCAL_GENERATOR_PATH
    
    def get_tier_spec_value(self, tier: str, field: str) -> Optional[str]:
        """Get a value from tierSpec for a specific tier.
        
        Args:
            tier: Tier name (easy, moderate, strong, hard, max)
            field: Field name (e.g., tempoToleranceBPM, tempoFitMinimum)
            
        Returns:
            Current value as string, or None if not found
        """
        content = self.modifier.read_file(self.file_path)
        
        # Find the tier case block
        tier_pattern = rf'case \.{tier}:.*?return TierSpec\((.*?)\)'
        match = re.search(tier_pattern, content, re.DOTALL)
        if not match:
            return None
        
        spec_content = match.group(1)
        
        # Find the specific field
        field_pattern = rf'{field}:\s*([\d.]+)'
        field_match = re.search(field_pattern, spec_content)
        if field_match:
            return field_match.group(1)
        
        return None
    
    def create_tier_spec_change(
        self,
        tier: str,
        field: str,
        new_value: str,
        rationale: str,
    ) -> Optional[CodeChange]:
        """Create a change to update a tierSpec value.
        
        Args:
            tier: Tier name
            field: Field name
            new_value: New value
            rationale: Reason for change
            
        Returns:
            CodeChange or None if field not found
        """
        old_value = self.get_tier_spec_value(tier, field)
        if old_value is None:
            return None
        
        if old_value == new_value:
            return None  # No change needed
        
        # Build the old and new patterns
        old_pattern = f"{field}: {old_value}"
        new_pattern = f"{field}: {new_value}"
        
        # Read file and find the specific occurrence in the tier block
        content = self.modifier.read_file(self.file_path)
        tier_pattern = rf'(case \.{tier}:.*?return TierSpec\(.*?){field}:\s*{re.escape(old_value)}(.*?\))'
        match = re.search(tier_pattern, content, re.DOTALL)
        
        if not match:
            return None
        
        old_code = match.group(0)
        new_code = old_code.replace(f"{field}: {old_value}", f"{field}: {new_value}", 1)
        
        return CodeChange(
            file_path=str(self.file_path),
            old_code=old_code,
            new_code=new_code,
            rationale=f"Tune {tier}.{field}: {old_value} -> {new_value}. {rationale}",
            is_structural=False,
            change_id=str(uuid.uuid4())[:8],
        )
    
    def get_tempo_window(self, tier: str) -> Optional[tuple[float, float]]:
        """Get the tempo window for a tier.
        
        Args:
            tier: Tier name
            
        Returns:
            Tuple of (min, max) or None
        """
        content = self.modifier.read_file(self.file_path)
        
        pattern = rf'case \.{tier}:\s*return\s*\((\d+),\s*(\d+)\)'
        match = re.search(pattern, content)
        if match:
            return (float(match.group(1)), float(match.group(2)))
        return None
    
    def create_tempo_window_change(
        self,
        tier: str,
        new_min: float,
        new_max: float,
        rationale: str,
    ) -> Optional[CodeChange]:
        """Create a change to update a tempo window.
        
        Args:
            tier: Tier name
            new_min: New minimum BPM
            new_max: New maximum BPM
            rationale: Reason for change
            
        Returns:
            CodeChange or None
        """
        current = self.get_tempo_window(tier)
        if current is None:
            return None
        
        old_min, old_max = current
        if (old_min, old_max) == (new_min, new_max):
            return None
        
        old_code = f"case .{tier}: return ({int(old_min)}, {int(old_max)})"
        new_code = f"case .{tier}: return ({int(new_min)}, {int(new_max)})"
        
        return CodeChange(
            file_path=str(self.file_path),
            old_code=old_code,
            new_code=new_code,
            rationale=f"Tune {tier} tempo window: ({old_min}, {old_max}) -> ({new_min}, {new_max}). {rationale}",
            is_structural=False,
            change_id=str(uuid.uuid4())[:8],
        )


if __name__ == "__main__":
    # Quick test
    modifier = SafeModifier()
    
    print(f"Current branch: {modifier.get_current_branch()}")
    print(f"Has uncommitted changes: {modifier.has_uncommitted_changes()}")
    
    # Test parameter tuner
    tuner = ParameterTuner(modifier)
    
    for tier in ["easy", "moderate", "strong", "hard", "max"]:
        tol = tuner.get_tier_spec_value(tier, "tempoToleranceBPM")
        window = tuner.get_tempo_window(tier)
        print(f"{tier}: tolerance={tol}, window={window}")
