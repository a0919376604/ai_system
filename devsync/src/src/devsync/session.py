"""Session naming and label assembly for mutagen create."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from devsync.repo import RepoSpec


def session_name(repo_name: str, server_name: str) -> str:
    """Canonical session name. Double-dash separator is deliberate so single-dash
    repo names like `ai-eden-service` don't collide visually with the server segment."""
    return f"{repo_name}--{server_name}"


@dataclass
class SessionSpec:
    repo: RepoSpec
    server_name: str

    @property
    def name(self) -> str:
        return session_name(self.repo.name, self.server_name)

    def labels(self) -> list[tuple[str, str]]:
        """Returns label pairs to be passed as `--label k=v` to mutagen."""
        worktree_label = self.repo.name if self.repo.is_worktree else "none"
        return [
            ("managed-by", "devsync"),
            ("repo", self.repo.name),
            ("server", self.server_name),
            ("worktree", worktree_label),
            # Mutagen labels reject ':', so use '-' between H/M/S (still parseable).
            ("created-at", datetime.now(UTC).strftime("%Y-%m-%dT%H-%M-%SZ")),
        ]
