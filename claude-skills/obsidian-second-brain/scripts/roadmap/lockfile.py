"""Lockfile for /obsidian-roadmap.

Tracks per-project theme + task materialization across re-runs so refresh
can decide SKIP / REGENERATE / mark STALE without re-asking the user.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

CURRENT_SCHEMA = 1


@dataclass
class ThemeEntry:
    title: str
    first_materialized: str
    last_refreshed: str
    signal_source_hash: str
    tasks: list[str]              # list of task IDs (e.g. ["T-001", "T-002"])
    status: str                   # active | stale | needs-refresh


@dataclass
class TaskEntry:
    theme: str                    # theme slug
    created: str                  # ISO timestamp
    slug: str                     # slug used in filename (without "T-NNN-" prefix)


@dataclass
class RoadmapLockfile:
    schema_version: int
    last_synthesis: str           # ISO timestamp of last successful run
    last_architect_commit: str    # commit SHA of Architecture/ at last run
    themes: dict[str, ThemeEntry] = field(default_factory=dict)
    tasks: dict[str, TaskEntry] = field(default_factory=dict)
    next_task_id: int = 1


def hash_signal(signal: dict) -> str:
    """Stable SHA-256 hash of a JSON-serializable signal dict."""
    canonical = json.dumps(signal, sort_keys=True, default=str).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def load_lockfile(path: Path) -> RoadmapLockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    return RoadmapLockfile(
        schema_version=data.get("schema_version", CURRENT_SCHEMA),
        last_synthesis=data.get("last_synthesis", ""),
        last_architect_commit=data.get("last_architect_commit", ""),
        themes={k: ThemeEntry(**v) for k, v in data.get("themes", {}).items()},
        tasks={k: TaskEntry(**v) for k, v in data.get("tasks", {}).items()},
        next_task_id=data.get("next_task_id", 1),
    )


def write_lockfile(lock: RoadmapLockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": CURRENT_SCHEMA,
        "last_synthesis": lock.last_synthesis,
        "last_architect_commit": lock.last_architect_commit,
        "themes": {k: asdict(v) for k, v in lock.themes.items()},
        "tasks": {k: asdict(v) for k, v in lock.tasks.items()},
        "next_task_id": lock.next_task_id,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False))


def allocate_task_id(lock: RoadmapLockfile) -> str:
    """Return next task ID 'T-NNN' (3-digit zero-padded) and increment the counter."""
    tid = f"T-{lock.next_task_id:03d}"
    lock.next_task_id += 1
    return tid
