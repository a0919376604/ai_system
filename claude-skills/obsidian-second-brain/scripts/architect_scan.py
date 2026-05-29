#!/usr/bin/env python3
"""CLI entry for /obsidian-architect Phase 1.

Usage:
    python scripts/architect_scan.py <repo-path> [--out <path>] [--dry-run]

Output:
    Writes _manifest.yml and scan-report.json to <out> (default: stdout as JSON).
    On --dry-run, prints to stdout without writing.

The slash command body (commands/obsidian-architect.md) invokes this
script and feeds the output into its own logic for Phase 2 + 3.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.architect.manifest import write_manifest
from scripts.architect.scan import run_phase_one


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 1 scan for /obsidian-architect")
    parser.add_argument("repo_path", help="Path to the git repo to scan")
    parser.add_argument("--out", help="Directory to write _manifest.yml and scan-report.json", default=None)
    parser.add_argument("--dry-run", action="store_true", help="Print to stdout, do not write files")
    parser.add_argument(
        "--vault-project-dir",
        type=Path,
        default=None,
        help="Vault project hub dir for research walking (v4.2 features)",
    )
    args = parser.parse_args(argv)

    repo = Path(args.repo_path).resolve()
    if not repo.is_dir():
        print(f"error: {repo} is not a directory", file=sys.stderr)
        return 2
    if not (repo / ".git").exists():
        print(f"error: {repo} is not a git repo", file=sys.stderr)
        return 2

    result = run_phase_one(repo, vault_project_dir=args.vault_project_dir)

    payload = {
        "manifest": asdict(result.manifest),
        "scan_report": result.scan_report,
    }

    if args.dry_run or args.out is None:
        json.dump(payload, sys.stdout, indent=2, default=str)
        print()
        return 0

    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    write_manifest(result.manifest, out_dir / "_manifest.yml")
    (out_dir / "scan-report.json").write_text(json.dumps(result.scan_report, indent=2, default=str))
    print(f"wrote {out_dir / '_manifest.yml'}")
    print(f"wrote {out_dir / 'scan-report.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
