"""Wrapper around the `repomix` npm tool with a Python fallback.

repomix packs a repo into a single LLM-friendly corpus. We use it for
two things: getting per-file token counts during scan (pack_repo_metadata)
and packing a specific module's source for LLM synthesis (pack_module).

If `repomix` is not on PATH we fall back to a pure-Python implementation
that approximates the same output. Functional but slower (about 3x).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from scripts.architect.walker import _approx_tokens, walk_repo


def is_available() -> bool:
    """True iff `repomix` is on PATH."""
    return shutil.which("repomix") is not None


def pack_module(repo_root: Path, include: list[str], compress: bool = True) -> str:
    """Return packed XML of files matching `include` patterns.

    `include` accepts glob patterns relative to `repo_root`, e.g.
    ["src/auth/**", "src/api/**"].
    """
    repo_root = repo_root.resolve()
    if is_available():
        cmd = [
            "repomix",
            "--include", ",".join(include),
            "--style", "xml",
            "--stdout",
        ]
        if compress:
            cmd.append("--compress")
        proc = subprocess.run(
            cmd, cwd=str(repo_root), capture_output=True, text=True, check=True
        )
        return proc.stdout
    # Fallback: hand-build a minimal XML corpus.
    return _python_pack(repo_root, include)


def pack_repo_metadata(repo_root: Path) -> dict:
    """Return file list with per-file token counts.

    Shape: {"files": [{"path": "src/auth/login.py", "tokens": 41}, ...],
             "total_tokens": 18400}
    """
    repo_root = repo_root.resolve()
    if is_available():
        proc = subprocess.run(
            [
                "repomix",
                "--output-style", "json",
                "--top-files-len", "0",
                "--stdout",
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)
        # repomix JSON output shape: {"files": [...], "metrics": {"totalTokens": N}}
        return {
            "files": [
                {"path": f["path"], "tokens": f.get("tokens", _approx_tokens(f.get("content", "")))}
                for f in data.get("files", [])
            ],
            "total_tokens": data.get("metrics", {}).get("totalTokens", 0),
        }
    return _python_metadata(repo_root)


def _python_pack(repo_root: Path, include: list[str]) -> str:
    """Pure-Python fallback for pack_module."""
    import fnmatch

    selected: list[Path] = []
    for rel in walk_repo(repo_root):
        for pattern in include:
            if fnmatch.fnmatch(rel, pattern) or rel.startswith(pattern.rstrip("/*")):
                selected.append(repo_root / rel)
                break

    parts: list[str] = ["<repomix-fallback>"]
    for path in selected:
        rel = path.relative_to(repo_root).as_posix()
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        parts.append(f'<file path="{rel}">')
        parts.append(content)
        parts.append("</file>")
    parts.append("</repomix-fallback>")
    return "\n".join(parts)


def _python_metadata(repo_root: Path) -> dict:
    files: list[dict] = []
    total = 0
    for rel in walk_repo(repo_root):
        path = repo_root / rel
        try:
            tokens = _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
        files.append({"path": rel, "tokens": tokens})
        total += tokens
    return {"files": files, "total_tokens": total}
