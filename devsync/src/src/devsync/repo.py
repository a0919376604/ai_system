"""Repo path resolution. v0.2 — path-based only, no code_root."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from devsync.errors import NoSuchRepo

# Worktree naming convention: <parent-repo>-wt-N  (e.g., ai-eden-service-wt-3)
_WORKTREE_PATTERN = re.compile(r"^(?P<parent>.+)-wt-\d+$")


@dataclass(frozen=True)
class RepoSpec:
    name: str
    local_path: Path
    is_worktree: bool
    parent_repo: str | None

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


def resolve_repo(arg: str | None, *, cwd: Path | None = None) -> RepoSpec:
    """Resolve a path argument to a RepoSpec.

    - arg=None → use cwd (default Path.cwd()).
    - arg='.', './foo', '/abs', '~/...' → expanduser + resolve.

    Raises NoSuchRepo if the resolved path is not a directory.
    """
    if arg is None:
        cwd = cwd or Path.cwd()
        return RepoSpec.from_path(cwd)

    p = Path(arg).expanduser().resolve()
    if not p.is_dir():
        raise NoSuchRepo(arg, [])
    return RepoSpec.from_path(p)
