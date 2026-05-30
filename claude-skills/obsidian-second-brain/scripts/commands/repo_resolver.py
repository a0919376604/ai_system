"""Resolve a CLI `<repo>` argument into a vault project binding.

Used by the obsidian-* command family (architect / brainstorm / roadmap /
research / research-deep). Accepts three forms:
- Sentinel ('global' / '_' / '-') -> state='global' (research commands only)
- Absolute path -> match against project hub `local-path` frontmatter
- Project name -> exact match against Projects/<name>/ folder, then fuzzy

Caller branches on `RepoResolution.state` to either continue execution,
ask the user to disambiguate, or abort with a message.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path


_GLOBAL_SENTINELS = ("global", "_", "-")
_LOCAL_PATH_RE = re.compile(r'^local-path:\s*"?(?P<path>[^"\n]+)"?\s*$', re.MULTILINE)
_FUZZY_THRESHOLD = 0.75


@dataclass
class RepoResolution:
    state: str
    project_slug: str | None = None
    project_dir: Path | None = None
    local_path: str | None = None
    candidates: list[str] = field(default_factory=list)
    message: str = ""


def resolve_repo_arg(
    token: str,
    vault_root: Path,
    *,
    allow_global: bool = False,
) -> RepoResolution:
    """Resolve a `<repo>` CLI token. See module docstring for full spec."""
    token = token.strip()
    if not token:
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="missing <repo> argument",
        )

    if token in _GLOBAL_SENTINELS:
        if allow_global:
            return RepoResolution(state="global")
        return RepoResolution(
            state="unknown",
            candidates=_list_projects(vault_root),
            message=(
                "'global' sentinel is not allowed for this command. "
                "Pass a specific project name."
            ),
        )

    if token.startswith("/"):
        return _resolve_absolute_path(token, vault_root)

    return _resolve_project_name(token, vault_root)


def _list_projects(vault_root: Path) -> list[str]:
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return []
    return sorted(
        d.name
        for d in projects_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".") and not d.name.startswith("_")
    )


def _resolve_absolute_path(token: str, vault_root: Path) -> RepoResolution:
    """Walk Projects/*/<P>.md hubs; match by local-path frontmatter."""
    normalized = token.rstrip("/")
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="vault has no Projects/ folder",
        )

    matches: list[tuple[str, Path, str]] = []
    for proj_dir in projects_dir.iterdir():
        if not proj_dir.is_dir() or proj_dir.name.startswith((".", "_")):
            continue
        hub_path = proj_dir / f"{proj_dir.name}.md"
        if not hub_path.is_file():
            continue
        try:
            text = hub_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        fm_match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
        if not fm_match:
            continue
        fm = fm_match.group(1)
        for match in _LOCAL_PATH_RE.finditer(fm):
            path_value = match.group("path").strip().rstrip("/")
            if path_value == normalized:
                matches.append((proj_dir.name, proj_dir, path_value))
                break

    if len(matches) == 0:
        return RepoResolution(
            state="unknown",
            candidates=_list_projects(vault_root),
            message=(
                f"no project hub binds to local-path {token!r}. "
                "Either fix the project hub's frontmatter, or pass the project name "
                "as the <repo> argument instead."
            ),
        )
    if len(matches) == 1:
        slug, proj_dir, local_path = matches[0]
        return RepoResolution(
            state="project",
            project_slug=slug,
            project_dir=proj_dir,
            local_path=local_path,
        )
    return RepoResolution(
        state="ambiguous",
        candidates=[match[0] for match in matches],
        message=(
            f"path {token!r} is bound by multiple project hubs: "
            f"{[match[0] for match in matches]}. Use --project=<name> or pass the "
            "project name directly to disambiguate."
        ),
    )


def _resolve_project_name(token: str, vault_root: Path) -> RepoResolution:
    """Project-name branch: exact match first, then fuzzy."""
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="vault has no Projects/ folder",
        )

    exact = projects_dir / token
    if exact.is_dir():
        return RepoResolution(
            state="project",
            project_slug=token,
            project_dir=exact,
        )

    all_projects = _list_projects(vault_root)
    token_lower = token.lower()
    candidates: list[str] = []
    for name in all_projects:
        name_lower = name.lower()
        if token_lower in name_lower or name_lower in token_lower:
            candidates.append(name)
            continue
        ratio = SequenceMatcher(None, token_lower, name_lower).ratio()
        if ratio >= _FUZZY_THRESHOLD:
            candidates.append(name)

    if candidates:
        return RepoResolution(
            state="ambiguous",
            candidates=candidates,
            message=(
                f"{token!r} matches multiple/uncertain candidates: {candidates}. "
                "Please confirm which project to use."
            ),
        )

    return RepoResolution(
        state="unknown",
        candidates=all_projects,
        message=(
            f"no project named {token!r}. Available: {all_projects}. "
            "Pass one as <repo> or run /obsidian-project <name> to create."
        ),
    )
