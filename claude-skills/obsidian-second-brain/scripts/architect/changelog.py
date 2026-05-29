"""Parse CHANGELOG.md (Keep-a-Changelog flavored) for architect signals.

Returns:
- unreleased: raw body text under `## Unreleased`, or None.
- recent_versions: up to 3 most recent versioned blocks with parsed
  version + date + body.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
_VERSION_RE = re.compile(r"^\[?(?P<ver>\d+\.\d+\.\d+[^\]\s]*)\]?(?:\s*-\s*(?P<date>[\d-]+))?$")


@dataclass
class VersionEntry:
    version: str
    date: str
    body: str


@dataclass
class Changelog:
    unreleased: str | None = None
    recent_versions: list[VersionEntry] = field(default_factory=list)


def parse_changelog(text: str) -> Changelog:
    cl = Changelog()
    matches = list(_H2_RE.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip()
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip()
        if title.strip("[]").lower() == "unreleased":
            cl.unreleased = body
            continue
        vm = _VERSION_RE.match(title)
        if vm:
            cl.recent_versions.append(
                VersionEntry(version=vm.group("ver"), date=vm.group("date") or "", body=body)
            )
    cl.recent_versions = cl.recent_versions[:3]
    return cl


def load_changelog(repo_root: Path) -> Changelog | None:
    """Read CHANGELOG.md from repo root. Returns None if missing."""
    for name in ("CHANGELOG.md", "CHANGELOG", "HISTORY.md"):
        p = repo_root / name
        if p.exists():
            return parse_changelog(p.read_text(encoding="utf-8"))
    return None
