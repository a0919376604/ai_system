"""Typed exceptions used across devsync."""

from __future__ import annotations


class DevsyncError(Exception):
    """Base class for all devsync errors. Catch this to handle any devsync failure."""


class NoSuchRepo(DevsyncError):
    def __init__(self, name: str, candidates: list[str]) -> None:
        super().__init__(
            f"No repo matching '{name}'. Available: {', '.join(sorted(candidates)) or '(none)'}"
        )
        self.name = name
        self.candidates = candidates


class NoSuchServer(DevsyncError):
    def __init__(self, name: str, candidates: list[str]) -> None:
        super().__init__(f"No server matching '{name}'. Available: {', '.join(sorted(candidates))}")
        self.name = name
        self.candidates = candidates


class ServerUnreachable(DevsyncError):
    def __init__(self, name: str, host: str, reason: str = "") -> None:
        msg = f"Cannot reach server '{name}' ({host})"
        if reason:
            msg += f": {reason}"
        super().__init__(msg)
        self.name = name
        self.host = host


class MutagenDaemonError(DevsyncError):
    """Mutagen daemon failed to start or is misbehaving."""


class SessionAlreadyExists(DevsyncError):
    def __init__(self, name: str) -> None:
        super().__init__(f"Mutagen session '{name}' already exists.")
        self.name = name
