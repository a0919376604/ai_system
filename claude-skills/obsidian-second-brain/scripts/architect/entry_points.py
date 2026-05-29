"""Detect repo entry points by parsing config files.

Returns a list of dicts with shape:
    {"path": "<repo-relative path or label>", "label": "<human label>", "kind": "<config-key>"}

Each detector is independent; this module is purely pattern-matching.
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


def detect_entry_points(repo_root: Path) -> list[dict]:
    """Run every detector and concatenate results."""
    repo_root = repo_root.resolve()
    eps: list[dict] = []
    eps.extend(_pyproject(repo_root))
    eps.extend(_package_json(repo_root))
    eps.extend(_cargo(repo_root))
    eps.extend(_go(repo_root))
    eps.extend(_makefile(repo_root))
    eps.extend(_dockerfile(repo_root))
    return eps


def _pyproject(repo_root: Path) -> list[dict]:
    path = repo_root / "pyproject.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    eps: list[dict] = []
    scripts = data.get("project", {}).get("scripts", {})
    for name, target in scripts.items():
        # target shape: "module.path:function"
        mod = target.split(":")[0].replace(".", "/") + ".py"
        eps.append({"path": mod, "label": f"pyproject.scripts.{name}", "kind": "pyproject"})
    poetry_scripts = data.get("tool", {}).get("poetry", {}).get("scripts", {})
    for name, target in poetry_scripts.items():
        mod = target.split(":")[0].replace(".", "/") + ".py"
        eps.append({"path": mod, "label": f"poetry.scripts.{name}", "kind": "pyproject-poetry"})
    return eps


def _package_json(repo_root: Path) -> list[dict]:
    path = repo_root / "package.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    eps: list[dict] = []
    if "main" in data:
        eps.append({"path": data["main"], "label": f"package.main ({data.get('name','?')})", "kind": "package-json"})
    bin_field = data.get("bin", {})
    if isinstance(bin_field, str):
        eps.append({"path": bin_field, "label": "package.bin", "kind": "package-json"})
    elif isinstance(bin_field, dict):
        for name, target in bin_field.items():
            eps.append({"path": target, "label": f"package.bin.{name}", "kind": "package-json"})
    return eps


def _cargo(repo_root: Path) -> list[dict]:
    path = repo_root / "Cargo.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    eps: list[dict] = []
    for bin_entry in data.get("bin", []):
        eps.append({
            "path": bin_entry.get("path", f"src/bin/{bin_entry.get('name','?')}.rs"),
            "label": f"cargo.bin.{bin_entry.get('name','?')}",
            "kind": "cargo",
        })
    if (repo_root / "src" / "main.rs").exists():
        eps.append({"path": "src/main.rs", "label": "cargo.default-bin", "kind": "cargo"})
    return eps


def _go(repo_root: Path) -> list[dict]:
    if not (repo_root / "go.mod").exists():
        return []
    eps: list[dict] = []
    for candidate in [repo_root / "main.go", repo_root / "cmd"]:
        if candidate.is_file():
            eps.append({"path": "main.go", "label": "go-main", "kind": "go"})
        elif candidate.is_dir():
            for sub in sorted(candidate.iterdir()):
                if (sub / "main.go").exists():
                    eps.append({
                        "path": f"cmd/{sub.name}/main.go",
                        "label": f"go-cmd.{sub.name}",
                        "kind": "go",
                    })
    return eps


_MAKEFILE_TARGET = re.compile(r"^([a-zA-Z0-9_.-]+):", re.MULTILINE)


def _makefile(repo_root: Path) -> list[dict]:
    path = repo_root / "Makefile"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    targets = _MAKEFILE_TARGET.findall(text)
    # Filter out variable assignments and .PHONY.
    interesting = [t for t in targets if not t.startswith(".") and t not in {"all", "clean"}]
    return [{"path": "Makefile", "label": f"make.{t}", "kind": "makefile"} for t in interesting[:5]]


_DOCKER_CMD = re.compile(r"^(ENTRYPOINT|CMD)\s+(.+)$", re.MULTILINE | re.IGNORECASE)


def _dockerfile(repo_root: Path) -> list[dict]:
    path = repo_root / "Dockerfile"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    eps: list[dict] = []
    for directive, value in _DOCKER_CMD.findall(text):
        eps.append({"path": "Dockerfile", "label": f"docker.{directive.upper()} {value.strip()[:60]}", "kind": "dockerfile"})
    return eps
