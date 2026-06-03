"""Repo path resolution with fuzzy matching and worktree awareness."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from rapidfuzz import fuzz, process

from devsync.errors import AmbiguousRepo, NoSuchRepo

# Worktree naming convention: <parent-repo>-wt-N  (e.g., ai-eden-service-wt-3)
_WORKTREE_PATTERN = re.compile(r"^(?P<parent>.+)-wt-\d+$")

FUZZY_CUTOFF = 70


@dataclass(frozen=True)
class RepoSpec:
    name: str
    local_path: Path
    is_worktree: bool
    parent_repo: str | None  # name of the main repo if this is a worktree

    @classmethod
    def from_path(cls, path: Path) -> RepoSpec:
        path = path.resolve()
        name = path.name
        match = _WORKTREE_PATTERN.match(name)
        if match:
            return cls(
                name=name,
                local_path=path,
                is_worktree=True,
                parent_repo=match.group("parent"),
            )
        return cls(name=name, local_path=path, is_worktree=False, parent_repo=None)


def _list_repo_dirs(code_root: Path) -> list[str]:
    return sorted(p.name for p in code_root.iterdir() if p.is_dir() and not p.name.startswith("."))


def resolve_repo(
    arg: str | None,
    *,
    code_root: Path,
    cwd: Path | None = None,
) -> RepoSpec:
    """Resolve a repo argument to a RepoSpec.

    - If `arg` is None, use `cwd` (defaults to current working directory).
    - If `arg` is an exact dir name under `code_root`, use it.
    - Otherwise fuzzy match against entries in `code_root`.
    """
    if arg is None:
        cwd = cwd or Path.cwd()
        return RepoSpec.from_path(cwd)

    # Exact match first
    exact = code_root / arg
    if exact.is_dir():
        return RepoSpec.from_path(exact)

    candidates = _list_repo_dirs(code_root)
    if not candidates:
        raise NoSuchRepo(arg, candidates)

    # rapidfuzz returns list of (match, score, index) above cutoff
    raw = process.extract(arg, candidates, scorer=fuzz.WRatio, score_cutoff=FUZZY_CUTOFF, limit=10)
    matches = [m[0] for m in raw]

    if len(matches) == 1:
        return RepoSpec.from_path(code_root / matches[0])
    if len(matches) > 1:
        raise AmbiguousRepo(arg, matches)
    raise NoSuchRepo(arg, candidates)
