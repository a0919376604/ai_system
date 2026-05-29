"""External runtime-dependency extraction.

Reads pyproject.toml, package.json, Cargo.toml, go.mod for production deps.
Dev/test groups are excluded - we only want runtime so the architecture
doc reflects what the system needs at runtime.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


def detect_external_deps(repo_root: Path) -> list[dict]:
    """Return list of {"name": str, "version": str|None, "group": "runtime", "source": str}."""
    repo_root = repo_root.resolve()
    out: list[dict] = []
    out.extend(_pyproject_deps(repo_root))
    out.extend(_package_json_deps(repo_root))
    out.extend(_cargo_deps(repo_root))
    out.extend(_go_mod_deps(repo_root))
    return out


_PYTHON_DEP_SPLIT = re.compile(r"[<>=!~]")


def _pyproject_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "pyproject.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    deps_list = data.get("project", {}).get("dependencies", [])
    out: list[dict] = []
    for dep in deps_list:
        name = _PYTHON_DEP_SPLIT.split(dep)[0].strip()
        out.append({"name": name, "version": dep, "group": "runtime", "source": "pyproject"})
    return out


def _package_json_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "package.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out: list[dict] = []
    for name, version in (data.get("dependencies") or {}).items():
        out.append({"name": name, "version": version, "group": "runtime", "source": "package.json"})
    return out


def _cargo_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "Cargo.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    out: list[dict] = []
    for name, version in (data.get("dependencies") or {}).items():
        version_str = version if isinstance(version, str) else version.get("version", "")
        out.append({"name": name, "version": version_str, "group": "runtime", "source": "cargo"})
    return out


_GO_REQUIRE = re.compile(r"^\s*([\w./-]+)\s+(v[\w.\-+]+)", re.MULTILINE)


def _go_mod_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "go.mod"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    return [
        {"name": name, "version": version, "group": "runtime", "source": "go.mod"}
        for name, version in _GO_REQUIRE.findall(text)
    ]
