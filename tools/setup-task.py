#!/usr/bin/env python3
"""
Setup script for new tasks using native TodoWrite integration.

This script creates a new task folder with FLAT STRUCTURE and initializes task-state.json.
No status files are created - workflow state is managed via TodoWrite + task-state.json.

Usage:
    python3 setup-task.py "Task Title" [options]

Flat Structure:
- All .md files are stored in task folder root (no subfolders)
- Only images/ subdirectory is created for visual assets
- Files: planning.md, analyzing.md, development.md, testing.md, etc.
- error.md is created when errors occur and require escalation
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional


# Embedded templates
TASK_STATE_TEMPLATE = """{
  "task_id": "{{TASK_ID}}",
  "title": "{{TITLE}}",
  "created_date": "{{CREATED_DATE}}",
  "updated_date": "{{UPDATED_DATE}}",
  "execution_mode": "async",
  "priority": "medium",
  "platform": "all",
  "dependencies": [],
  "blockers": [],

  "state": {
    "current": "planning:preparing",
    "previous": null,
    "statusCode": "0",
    "agent": "P",
    "transitions": []
  },

  "retries": {
    "P": 0, "A": 0, "T": 0, "D": 0, "Q": 0, "W": 0, "F": 0, "S": 0,
    "max": 3
  },

  "approvals": {},
  "escalations": [],

  "rule_checks": {
    "build": "pending",
    "code_review": "pending",
    "testing": "pending"
  }
}"""

PLANNING_TEMPLATE = """# Task Title

## Problem Statement

[Clear description of what needs to be done]

## Requirements

### Functional Requirements
- [ ] Requirement 1
- [ ] Requirement 2

### Non-Functional Requirements
- [ ] Performance: [specify if applicable]
- [ ] Security: [specify if applicable]
- [ ] Accessibility: [specify if applicable]

## Acceptance Criteria

- [ ] AC1: [Specific, testable criterion]
- [ ] AC2: [Specific, testable criterion]

## Execution Mode

- **Async**: Can run independently
- **Sync**: Must wait for dependencies

## Priority

[High/Medium/Low]

## Platform

[iOS / macOS / tvOS / watchOS / visionOS / All]

## Dependencies

- None

## Constraints

- None

## Success Metrics

- [ ] Metric 1
- [ ] Metric 2

## Notes

[Additional context or notes]
"""


def get_git_root() -> Optional[Path]:
    """Get the git repository root directory."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def get_project_root(explicit_root: Optional[Path] = None) -> Path:
    """Determine the project root directory."""
    if explicit_root:
        return explicit_root.resolve()

    git_root = get_git_root()
    if git_root:
        return git_root

    return Path.cwd()


def get_tasks_dir(project_root: Optional[Path] = None) -> Path:
    """Get the tasks directory path in PROJECT_ROOT/tasks/."""
    root = get_project_root(project_root)
    return root / "tasks"


def replace_placeholders(content: str, placeholders: Dict[str, str]) -> str:
    """Replace all placeholders in content with their values."""
    result = content
    for key, value in placeholders.items():
        placeholder = f"{{{{{key}}}}}"
        result = result.replace(placeholder, value)
    return result


def title_to_kebab_case(title: str) -> str:
    """Convert title to kebab-case for folder name."""
    title = re.sub(r'[^\w\s-]', '', title)
    title = re.sub(r'[\s_]+', '-', title)
    title = title.lower()
    title = re.sub(r'-+', '-', title).strip('-')
    return title


def generate_folder_name(title: str, date: Optional[str] = None) -> str:
    """Generate folder name in YYYYMMDD-short-title format."""
    if not date:
        date = datetime.now().strftime("%Y%m%d")

    kebab_title = title_to_kebab_case(title)
    return f"{date}-{kebab_title}"


def create_task_structure(
    task_dir: Path,
    task_info: Dict[str, str],
    task_id: str,
    dry_run: bool = False
) -> bool:
    """Create task folder structure."""
    if dry_run:
        print(f"[DRY RUN] Would create task folder: {task_dir}")
        return True

    if task_dir.exists():
        response = input(f"\nTask folder {task_dir} already exists. Overwrite? [y/N]: ").strip().lower()
        if response != 'y':
            print(f"Skipping task folder creation")
            return False

    directories = [
        task_dir,
        task_dir / "images",
    ]

    for directory in directories:
        directory.mkdir(parents=True, exist_ok=True)
        print(f"Created directory: {directory}")

    return True


def create_task_state_json(
    task_dir: Path,
    task_info: Dict[str, str],
    task_id: str,
    dry_run: bool = False
) -> bool:
    """Create task-state.json file."""
    now = datetime.now().isoformat() + "Z"

    placeholders = {
        "TASK_ID": task_id,
        "TITLE": task_info["title"],
        "CREATED_DATE": now,
        "UPDATED_DATE": now,
    }

    content = replace_placeholders(TASK_STATE_TEMPLATE, placeholders)

    state = json.loads(content)
    state["execution_mode"] = task_info.get("execution_mode", "async")
    state["priority"] = task_info.get("priority", "medium").lower()
    state["platform"] = task_info.get("platform", "all").lower()

    content = json.dumps(state, indent=2)

    filepath = task_dir / "task-state.json"

    if dry_run:
        print(f"[DRY RUN] Would create: {filepath}")
        return True

    try:
        filepath.write_text(content, encoding="utf-8")
        print(f"Created: {filepath}")
        return True
    except Exception as e:
        print(f"Error writing {filepath}: {e}", file=sys.stderr)
        return False


def create_planning_md(
    task_dir: Path,
    task_info: Dict[str, str],
    task_id: str,
    dry_run: bool = False
) -> bool:
    """Create planning.md file."""
    content = PLANNING_TEMPLATE

    content = content.replace("# Task Title", f"# {task_info['title']}")

    if task_info.get("description"):
        content = content.replace(
            "[Clear description of what needs to be done]",
            task_info["description"]
        )

    content = content.replace("[High/Medium/Low]", task_info.get("priority", "Medium"))

    if task_info.get("platform"):
        content = content.replace("[iOS / macOS / tvOS / watchOS / visionOS / All]", task_info["platform"])

    filepath = task_dir / "planning.md"

    if dry_run:
        print(f"[DRY RUN] Would create: {filepath}")
        return True

    try:
        filepath.write_text(content, encoding="utf-8")
        print(f"Created: {filepath}")
        return True
    except Exception as e:
        print(f"Error writing {filepath}: {e}", file=sys.stderr)
        return False


def print_todowrite_command(task_id: str):
    """Print TodoWrite command to initialize workflow."""
    print("\n" + "="*70)
    print("IMPORTANT: Initialize workflow with TodoWrite")
    print("="*70)
    print("\nCopy and paste this command into Claude Code:\n")
    print("TodoWrite({")
    print("  todos: [")
    print('    { content: "P1: Planning", status: "in_progress", activeForm: "Planning task requirements" },')
    print('    { content: "A0: Architecture", status: "pending", activeForm: "Architecting solution" },')
    print('    { content: "T0: Team Lead", status: "pending", activeForm: "Coordinating team" },')
    print('    { content: "D0: Development", status: "pending", activeForm: "Implementing code" },')
    print('    { content: "Q0: QA Testing", status: "pending", activeForm: "Testing solution" },')
    print('    { content: "W0: Documentation", status: "pending", activeForm: "Writing technical documentation" },')
    print('    { content: "F0: Finalization", status: "pending", activeForm: "Finalizing release" },')
    print('    { content: "S0: Stakeholder", status: "pending", activeForm: "Awaiting approval" }')
    print("  ]")
    print("});")
    print("\n" + "="*70 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Setup new task folder with native TodoWrite integration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 setup-task.py "Add Dark Mode"

  python3 setup-task.py "Add Dark Mode" \\
    --description "Add dark mode support to app" \\
    --execution-mode async \\
    --priority High \\
    --platform All \\
    --non-interactive

  python3 setup-task.py "Add Dark Mode" --dry-run
        """
    )

    parser.add_argument(
        "title",
        help="Task title (will be converted to kebab-case for folder name)"
    )

    parser.add_argument(
        "--description",
        help="Task description"
    )

    parser.add_argument(
        "--execution-mode",
        choices=["sync", "async"],
        default="async",
        help="Execution mode (default: async)"
    )

    parser.add_argument(
        "--priority",
        choices=["High", "Medium", "Low"],
        default="Medium",
        help="Priority (default: Medium)"
    )

    parser.add_argument(
        "--platform",
        choices=["iOS", "macOS", "tvOS", "watchOS", "visionOS", "All"],
        default="All",
        help="Target platform (default: All)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating files"
    )

    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Use command-line args only (no prompts)"
    )

    parser.add_argument(
        "--project-root",
        type=Path,
        help="Project root directory (default: git root or current directory)"
    )

    args = parser.parse_args()

    task_info = {
        "title": args.title,
        "description": args.description or "",
        "execution_mode": args.execution_mode,
        "priority": args.priority,
        "platform": args.platform,
    }

    if args.dry_run:
        print("\n=== DRY RUN MODE ===")
        print("No files will be written. Preview of changes:\n")

    project_root = get_project_root(args.project_root)
    folder_name = generate_folder_name(task_info["title"])
    task_id = folder_name
    task_dir = get_tasks_dir(project_root) / folder_name

    print(f"\nProject root: {project_root}")
    print(f"Task ID: {task_id}")
    print(f"Task folder: {task_dir}")
    print(f"Task title: {task_info['title']}")
    print(f"Execution mode: {task_info['execution_mode']}")
    print(f"Priority: {task_info['priority']}")
    print(f"Platform: {task_info['platform']}")
    print()

    if create_task_structure(task_dir, task_info, task_id, dry_run=args.dry_run):
        if not args.dry_run:
            create_task_state_json(task_dir, task_info, task_id, dry_run=args.dry_run)
            create_planning_md(task_dir, task_info, task_id, dry_run=args.dry_run)

    print("\n=== Summary ===")
    if args.dry_run:
        print(f"Would create task folder structure:")
    else:
        print(f"Created task folder structure:")

    print(f"  {task_dir}/")
    print(f"    ├── task-state.json")
    print(f"    ├── planning.md")
    print(f"    └── images/")
    print()
    print("  Additional files created as needed:")
    print("    - analyzing.md     (A stage)")
    print("    - development.md   (D stage)")
    print("    - testing.md       (Q stage)")
    print("    - documentation.md (W stage)")
    print("    - complete.md      (F stage)")
    print("    - release.md       (F stage)")
    print("    - error.md         (on errors/escalation)")

    if not args.dry_run:
        print("\nNext steps:")
        print("  1. Review planning.md")
        print("  2. Initialize TodoWrite (see command below)")
        print("  3. Start planning work")

        print_todowrite_command(task_id)


if __name__ == "__main__":
    main()
