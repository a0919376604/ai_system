"""Repo file walker. Filesystem traversal with .gitignore handling.

This module knows about files and directories. It does not know about
modules, manifests, or anything domain-specific to /obsidian-architect.
"""

from __future__ import annotations

from pathlib import Path

import pathspec

# Always-skip prefixes regardless of .gitignore. Includes .git itself
# (which is never gitignored but must not be walked) plus build outputs
# and dependency caches that are by convention not part of source.
ALWAYS_SKIP_DIRS = {
    ".git",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "dist",
    "build",
    "target",
    "out",
    ".next",
}


def _load_gitignore(repo_root: Path) -> pathspec.PathSpec:
    """Load .gitignore patterns from the repo root, if present."""
    gitignore = repo_root / ".gitignore"
    if not gitignore.exists():
        return pathspec.PathSpec.from_lines("gitignore", [])
    with gitignore.open() as fh:
        return pathspec.PathSpec.from_lines("gitignore", fh)


def _is_binary(path: Path) -> bool:
    """Cheap binary detection: scan first 8KB for a NUL byte."""
    try:
        with path.open("rb") as fh:
            chunk = fh.read(8192)
    except OSError:
        return True
    return b"\x00" in chunk


def walk_repo(repo_root: Path) -> list[str]:
    """Return a sorted list of POSIX-style relative file paths.

    Excludes: .git/, conventional build/cache dirs, .gitignore matches,
    binary files. Symlinks are followed only if they resolve inside repo_root.
    """
    repo_root = repo_root.resolve()
    spec = _load_gitignore(repo_root)
    results: list[str] = []

    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue

        # Always-skip check (by any path part)
        if any(part in ALWAYS_SKIP_DIRS for part in path.relative_to(repo_root).parts):
            continue

        rel = path.relative_to(repo_root).as_posix()
        if spec.match_file(rel):
            continue

        if _is_binary(path):
            continue

        # Symlink safety: must resolve inside repo_root.
        try:
            resolved = path.resolve()
            resolved.relative_to(repo_root)
        except ValueError:
            continue

        results.append(rel)

    return sorted(results)

import subprocess

# Extension to language label. Conservative list - unknown extensions
# fall into "other".
EXT_TO_LANG = {
    ".py": "python",
    ".pyi": "python",
    ".js": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
    ".java": "java",
    ".kt": "kotlin",
    ".swift": "swift",
    ".c": "c",
    ".h": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".hpp": "cpp",
    ".md": "markdown",
    ".sh": "shell",
    ".bash": "shell",
    ".zsh": "shell",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".json": "json",
    ".html": "html",
    ".css": "css",
}


def _approx_tokens(text: str) -> int:
    """Rough proxy for LLM tokens. Roughly 4 chars per token for code."""
    return max(1, len(text) // 4)


def language_stats(repo_root: Path) -> list[dict]:
    """Return per-language file count and approximate token count.

    Sorted by token count descending. Result shape:
        [{"lang": "python", "files": 23, "tokens": 18400}, ...]
    """
    repo_root = repo_root.resolve()
    by_lang: dict[str, dict] = {}
    for rel in walk_repo(repo_root):
        path = repo_root / rel
        lang = EXT_TO_LANG.get(path.suffix.lower(), "other")
        row = by_lang.setdefault(lang, {"lang": lang, "files": 0, "tokens": 0})
        row["files"] += 1
        try:
            row["tokens"] += _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
    return sorted(by_lang.values(), key=lambda r: r["tokens"], reverse=True)


def git_metadata(repo_root: Path) -> dict:
    """Return {'commit': <40-char SHA>, 'dirty': bool}.

    Assumes repo_root is a git repo. Caller validates beforehand.
    """
    repo_root = repo_root.resolve()
    commit = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "-C", str(repo_root), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return {"commit": commit, "dirty": bool(status.strip())}
