#!/usr/bin/env python3
"""
Entry point for the Playlist Generation Agent.

This script provides the main CLI for running the improvement agent.

Usage:
    python run_agent.py --focus "tempo fitting" --iterations 5
    python run_agent.py --help
"""

import argparse
import sys
from pathlib import Path

# Add agent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from orchestrator import AgentOrchestrator
from config import ensure_directories


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Run the playlist generation improvement agent",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Run with default settings
    python run_agent.py
    
    # Focus on a specific dimension
    python run_agent.py --focus "tempo fitness"
    python run_agent.py --focus "energy arc"
    python run_agent.py --focus "slot fitness"
    
    # Run more iterations
    python run_agent.py --iterations 10
    
    # Skip subjective evaluation (faster)
    python run_agent.py --no-subjective
    
    # Require approval for all changes
    python run_agent.py --manual-approve
"""
    )
    
    parser.add_argument(
        "--focus",
        default="overall improvement",
        help="Focus area for improvements (e.g., 'tempo fitting', 'energy arc')"
    )
    
    parser.add_argument(
        "--iterations",
        type=int,
        default=5,
        help="Maximum number of improvement iterations (default: 5)"
    )
    
    parser.add_argument(
        "--no-subjective",
        action="store_true",
        help="Skip Claude-based subjective evaluation (faster but less thorough)"
    )
    
    parser.add_argument(
        "--manual-approve",
        action="store_true",
        help="Require manual approval for all changes (including numeric tuning)"
    )
    
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run evaluations only, don't propose any changes"
    )
    
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose output"
    )
    
    args = parser.parse_args()
    
    # Ensure directories exist
    ensure_directories()
    
    print("=" * 60)
    print("PLAYLIST GENERATION AGENT")
    print("=" * 60)
    print(f"Focus: {args.focus}")
    print(f"Max iterations: {args.iterations}")
    print(f"Subjective evaluation: {'No' if args.no_subjective else 'Yes'}")
    print(f"Auto-approve numeric: {'No' if args.manual_approve else 'Yes'}")
    print("=" * 60)
    
    try:
        orchestrator = AgentOrchestrator(
            use_subjective=not args.no_subjective,
            auto_approve_numeric=not args.manual_approve,
        )
        
        session = orchestrator.run(
            focus=args.focus,
            max_iterations=args.iterations,
        )
        
        print("\n" + "=" * 60)
        print("SESSION COMPLETE")
        print("=" * 60)
        print(f"Session ID: {session.session_id}")
        print(f"Branch: {session.branch_name}")
        print(f"Generations evaluated: {len(orchestrator.evaluations)}")
        
        if orchestrator.evaluations:
            print(f"Final average score: {session.final_avg_score:.2f}/10")
            
            # Show dimension breakdown
            print("\nDimension scores (last generation):")
            last_eval = orchestrator.evaluations[-1]
            for dim in last_eval.dimension_scores:
                print(f"  {dim.name}: {dim.score:.1f}/10")
        
        print(f"\nReport saved to: agent/reports/session_{session.session_id}.md")
        
    except KeyboardInterrupt:
        print("\n\nSession interrupted by user.")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
