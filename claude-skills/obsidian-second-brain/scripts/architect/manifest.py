"""_manifest.yml read/write. Knows YAML; knows nothing about diff or hashes."""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from pathlib import Path

import yaml


@dataclass
class Manifest:
    version: int
    repo: dict
    last_scan: dict
    modules: list[dict] = field(default_factory=list)


def load_manifest(path: Path) -> Manifest | None:
    """Return Manifest, or None if file does not exist."""
    if not path.exists():
        return None
    data = yaml.safe_load(path.read_text())
    return Manifest(
        version=data.get("version", 1),
        repo=data.get("repo", {}),
        last_scan=data.get("last_scan", {}),
        modules=data.get("modules", []),
    )


def write_manifest(manifest: Manifest, path: Path) -> None:
    """Serialize to YAML at `path`. Parent directory must exist."""
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(manifest)
    with path.open("w") as fh:
        yaml.safe_dump(payload, fh, sort_keys=False, default_flow_style=False, allow_unicode=True)
