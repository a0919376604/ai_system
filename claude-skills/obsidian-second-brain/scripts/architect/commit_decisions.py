"""Mine git commit messages for explicit technology / architecture decisions.

Patterns (case-insensitive) per spec §6:
  decided, chose, switched from, moved to, replaced X with Y
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

_PATTERN = re.compile(
    r"\b(?:decided|chose|switched\s+from|moved\s+to|replaced\b.+?\bwith)\b",
    re.IGNORECASE,
)


@dataclass
class CommitDecision:
    sha: str
    date: str
    message: str


def extract_commit_decisions(repo_root: Path, limit: int = 200) -> list[CommitDecision]:
    """Read recent commits and keep those whose message matches a decision pattern."""
    cmd = ["git", "-C", str(repo_root), "log", f"-n{limit}", "--pretty=%H%x01%cI%x01%s%n%b%x1e"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    decisions: list[CommitDecision] = []
    for record in out.split("\x1e"):
        record = record.strip()
        if not record:
            continue
        head, _, body = record.partition("\n")
        sha, date, subject = head.split("\x01", 2)
        full = (subject + "\n" + body).strip()
        if _PATTERN.search(full):
            decisions.append(CommitDecision(sha=sha[:7], date=date[:10], message=subject))
    return decisions
