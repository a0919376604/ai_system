from datetime import date
from pathlib import Path

from scripts.architect.manifest import Manifest, load_manifest, write_manifest


def test_round_trip(tmp_path: Path):
    manifest = Manifest(
        version=1,
        repo={
            "name": "demo",
            "root": "/abs/path",
            "primary_language": "python",
            "languages": [{"lang": "python", "files": 3, "tokens": 100}],
        },
        last_scan={"date": "2026-05-26", "commit": "abc", "dirty": False, "scanner_version": "0.1.0"},
        modules=[{
            "slug": "auth",
            "display_name": "Auth",
            "paths": ["src/auth/"],
            "role": "core",
            "excluded": False,
            "description": None,
            "pattern": None,
        }],
    )
    target = tmp_path / "_manifest.yml"
    write_manifest(manifest, target)
    loaded = load_manifest(target)
    assert loaded.modules[0]["slug"] == "auth"
    assert loaded.repo["name"] == "demo"


def test_load_missing_returns_none(tmp_path: Path):
    assert load_manifest(tmp_path / "nope.yml") is None
