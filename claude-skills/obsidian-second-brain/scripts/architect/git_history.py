"""Per-file last-commit date map for features.md inventory's `Last touch` column.

Pure subprocess wrapper around `git log -1 --format=%ad --date=short`.
Display-only — never included in signal_hash (every scan recomputes).
"""
from __future__ import annotations

import subprocess
from pathlib import Path

_MAX_FILES = 200


def last_touch_map(repo: Path, files: list[str]) -> dict[str, str]:
    """Return {repo-relative-posix-path: 'YYYY-MM-DD'} for files in `files`.

    - `files` paths are repo-relative posix strings.
    - Missing keys: file is not under git OR has no commit history. Callers
      render missing as '—' or 'unknown' downstream.
    - Capped at `_MAX_FILES`; if `files` is longer, the most-recently-mtime
      files are kept and others dropped silently.
    """
    repo = repo.resolve()
    files = _cap_by_mtime(repo, files)

    out: dict[str, str] = {}
    for rel in files:
        try:
            proc = subprocess.run(
                ["git", "log", "-1", "--format=%ad", "--date=short", "--", rel],
                cwd=str(repo),
                capture_output=True,
                text=True,
                check=False,
            )
        except (FileNotFoundError, OSError):
            continue
        if proc.returncode != 0:
            continue
        date = proc.stdout.strip()
        if date:
            out[rel] = date
    return out


def _cap_by_mtime(repo: Path, files: list[str]) -> list[str]:
    """Return `files` reduced to at most _MAX_FILES, keeping most-recent mtimes."""
    if len(files) <= _MAX_FILES:
        return files
    annotated: list[tuple[float, str]] = []
    for rel in files:
        full = repo / rel
        try:
            mtime = full.stat().st_mtime
        except OSError:
            mtime = 0.0
        annotated.append((mtime, rel))
    annotated.sort(key=lambda pair: pair[0], reverse=True)
    return [rel for _, rel in annotated[:_MAX_FILES]]
