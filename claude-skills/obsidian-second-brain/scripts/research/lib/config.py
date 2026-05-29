"""Reads ~/.config/obsidian-second-brain/research.toml.

The file is optional. Defaults below are used when missing or partial.
No API keys live here — this is purely polite-pool email + tunables.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


_DEFAULT_SEARXNG = [
    "https://searx.be",
    "https://search.brave4u.com",
    "https://priv.au",
]


@dataclass(frozen=True)
class Config:
    contact_email: str | None = None
    searxng_instances: list[str] = field(default_factory=lambda: list(_DEFAULT_SEARXNG))
    cache_ttl_hours: int = 24
    arxiv_seconds: float = 3.0
    reddit_seconds: float = 0.5
    semantic_scholar_seconds: float = 3.0


_CACHE: Config | None = None


def _config_path() -> Path:
    return Path(os.path.expanduser("~/.config/obsidian-second-brain/research.toml"))


def load() -> Config:
    global _CACHE
    if _CACHE is not None:
        return _CACHE

    p = _config_path()
    if not p.exists():
        _CACHE = Config()
        return _CACHE

    raw = tomllib.loads(p.read_text())
    cfg = Config(
        contact_email=raw.get("contact_email"),
        searxng_instances=raw.get("searxng", {}).get("instances", list(_DEFAULT_SEARXNG)),
        cache_ttl_hours=int(raw.get("cache", {}).get("ttl_hours", 24)),
        arxiv_seconds=float(raw.get("rate_limits", {}).get("arxiv_seconds", 3.0)),
        reddit_seconds=float(raw.get("rate_limits", {}).get("reddit_seconds", 0.5)),
        semantic_scholar_seconds=float(
            raw.get("rate_limits", {}).get("semantic_scholar_seconds", 3.0)
        ),
    )
    _CACHE = cfg
    return cfg


def get_contact_email() -> str | None:
    return load().contact_email


__all__ = ["Config", "load", "get_contact_email"]
