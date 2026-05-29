#!/usr/bin/env python3
"""CLI entry for /obsidian-roadmap Phase 1+2a.

Phase 1: detect candidates from Architecture/.
Phase 2a: build the keyword-extraction LLM prompt.

The slash-command body (`commands/obsidian-roadmap.md`) invokes this
script to get a deterministic seed, then drives the LLM (Phase 2c, 3),
parses the response (Phase 4), and calls render.py composers (Phase 5).

Usage:
    python scripts/roadmap_synth.py --project-root <path> --vault-root <path> --out <dir> [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.roadmap.candidates import detect_candidates
from scripts.roadmap.research_match import build_keyword_extraction_prompt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 1+2a scan for /obsidian-roadmap")
    parser.add_argument("--project-root", required=True,
                        help="Path to Projects/<P>/ inside the vault")
    parser.add_argument("--vault-root", required=True,
                        help="Path to the vault root (where _CLAUDE.md lives)")
    parser.add_argument("--out", required=True,
                        help="Directory to write candidates.json + keyword_extraction_prompt.txt")
    parser.add_argument("--lang", default="en",
                        help="Output language for the keyword-extraction prompt directive")
    parser.add_argument("--dry-run", action="store_true",
                        help="(currently a no-op flag for future LLM-driven phases)")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    vault_root = Path(args.vault_root).resolve()
    out_dir = Path(args.out).resolve()

    if not project_root.is_dir():
        print(f"error: project-root {project_root} not a directory", file=sys.stderr)
        return 2
    if not (project_root / "Architecture").is_dir():
        print(f"error: {project_root}/Architecture not found. "
              "Run /obsidian-architect first.", file=sys.stderr)
        return 3
    if not (vault_root / "_CLAUDE.md").is_file():
        print(f"warning: {vault_root}/_CLAUDE.md not found", file=sys.stderr)

    out_dir.mkdir(parents=True, exist_ok=True)

    # Phase 1
    cands = detect_candidates(project_root)
    payload = [asdict(c) for c in cands]
    (out_dir / "candidates.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False)
    )

    # Phase 2a — keyword-extraction prompt (agent calls LLM with this)
    candidates_text = {c.id: c.raw_text for c in cands}
    prompt = build_keyword_extraction_prompt(candidates_text, output_lang=args.lang)
    (out_dir / "keyword_extraction_prompt.txt").write_text(prompt)

    print(f"wrote {out_dir / 'candidates.json'} ({len(cands)} candidates)")
    print(f"wrote {out_dir / 'keyword_extraction_prompt.txt'} ({len(prompt)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
