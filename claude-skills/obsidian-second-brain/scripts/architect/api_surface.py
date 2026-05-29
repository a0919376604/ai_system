"""Detect public API surface: CLI commands, HTTP routes, exports, env vars.

Each detector is pattern-matching only. Errors are silently dropped (a single
malformed file should never crash the scan).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_SUPPORTED_EXTS = {".py", ".js", ".ts", ".tsx"}
_MAX_FILE_BYTES = 512 * 1024


@dataclass
class CliCommand:
    name: str
    description: str
    source: str        # "<path>:<line>"


@dataclass
class HttpRoute:
    method: str
    path: str
    handler: str
    source: str


@dataclass
class Export:
    symbol: str
    kind: str          # "named" / "default" / "all"
    source: str


@dataclass
class EnvVar:
    name: str
    required: bool
    default: str | None
    source: str


@dataclass
class ApiSurface:
    cli_commands: list[CliCommand] = field(default_factory=list)
    http_routes: list[HttpRoute] = field(default_factory=list)
    exports: list[Export] = field(default_factory=list)
    env_vars: list[EnvVar] = field(default_factory=list)
    detection_status: str = "none"  # complete | partial | none


def detect_api_surface(repo_root: Path) -> ApiSurface:
    repo_root = repo_root.resolve()
    surf = ApiSurface()
    for p in _iter_source_files(repo_root):
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rel = p.relative_to(repo_root).as_posix()
        surf.cli_commands.extend(_detect_argparse(text, rel))
        surf.http_routes.extend(_detect_fastapi(text, rel))
        surf.http_routes.extend(_detect_express(text, rel))
        if p.name == "__init__.py" or p.suffix in {".js", ".ts"}:
            surf.exports.extend(_detect_python_all(text, rel) if p.suffix == ".py" else _detect_js_exports(text, rel))
        surf.env_vars.extend(_detect_env_vars(text, rel))
    if surf.cli_commands or surf.http_routes or surf.exports or surf.env_vars:
        surf.detection_status = "complete"
    return surf


_EXCLUDED_PATH_PARTS = frozenset({
    ".git", "node_modules",
    # Python virtualenv conventions — packages here are vendored deps, not surface.
    ".venv", "venv", "env", "virtualenv",
    # Build / cache artefacts that often mirror or wrap source.
    "dist", "build", ".next", ".nuxt", ".turbo", ".cache",
    "__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache",
    # Vendored deps in some Go / PHP / Ruby layouts.
    "vendor",
    # IDE / OS noise.
    ".idea", ".vscode",
    # Claude Code / Conductor worktrees — these mirror the repo and double-count
    # every API surface item if walked.
    ".claude", "worktrees",
})


def _iter_source_files(repo_root: Path):
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if _EXCLUDED_PATH_PARTS.intersection(p.parts):
            continue
        if p.suffix not in _SUPPORTED_EXTS:
            continue
        try:
            if p.stat().st_size > _MAX_FILE_BYTES:
                continue
        except OSError:
            continue
        yield p


_ARGPARSE_SUB_RE = re.compile(
    r"\.add_parser\(\s*['\"](?P<name>[\w_-]+)['\"]"
    r"(?:[^)]*?help\s*=\s*['\"](?P<help>[^'\"]*)['\"])?",
    re.DOTALL,
)


def _detect_argparse(text: str, rel: str) -> list[CliCommand]:
    out: list[CliCommand] = []
    for m in _ARGPARSE_SUB_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(CliCommand(
            name=m.group("name"),
            description=(m.group("help") or "").strip(),
            source=f"{rel}:{line}",
        ))
    return out


_FASTAPI_RE = re.compile(
    r"@(?P<var>\w+)\.(?P<method>get|post|put|patch|delete)\(\s*['\"](?P<path>[^'\"]+)['\"]"
    r"[^)]*\)\s*\n\s*(?:async\s+)?def\s+(?P<handler>\w+)",
    re.IGNORECASE,
)

# `<var> = APIRouter(... prefix="..." ...)` — captures the variable name + its
# declared prefix so per-file decorator paths can be joined into the full
# mounted path (matches FastAPI's actual routing behavior).
_APIROUTER_RE = re.compile(
    r"(?P<var>\w+)\s*=\s*APIRouter\([^)]*prefix\s*=\s*['\"](?P<prefix>[^'\"]+)['\"]"
)


def _detect_fastapi(text: str, rel: str) -> list[HttpRoute]:
    # Build (var → prefix) map from in-file APIRouter declarations.
    prefix_map: dict[str, str] = {}
    for m in _APIROUTER_RE.finditer(text):
        prefix_map[m.group("var")] = m.group("prefix")

    out: list[HttpRoute] = []
    for m in _FASTAPI_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        prefix = prefix_map.get(m.group("var"), "")
        full_path = prefix + m.group("path")
        out.append(HttpRoute(
            method=m.group("method").upper(),
            path=full_path,
            handler=m.group("handler"),
            source=f"{rel}:{line}",
        ))
    return out


_EXPRESS_RE = re.compile(
    r"\bapp\.(?P<method>get|post|put|patch|delete)\(\s*['\"](?P<path>[^'\"]+)['\"]",
    re.IGNORECASE,
)


def _detect_express(text: str, rel: str) -> list[HttpRoute]:
    out: list[HttpRoute] = []
    for m in _EXPRESS_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(HttpRoute(
            method=m.group("method").upper(),
            path=m.group("path"),
            handler="(anonymous)",
            source=f"{rel}:{line}",
        ))
    return out


_ALL_RE = re.compile(r"^__all__\s*=\s*\[(?P<body>[^\]]*)\]", re.MULTILINE | re.DOTALL)
_QUOTED_NAME_RE = re.compile(r"['\"]([\w_]+)['\"]")


def _detect_python_all(text: str, rel: str) -> list[Export]:
    m = _ALL_RE.search(text)
    if not m:
        return []
    line = text[: m.start()].count("\n") + 1
    return [
        Export(symbol=n, kind="all", source=f"{rel}:{line}")
        for n in _QUOTED_NAME_RE.findall(m.group("body"))
    ]


_JS_NAMED_EXPORT_RE = re.compile(
    r"^export\s+(?:async\s+)?(?:function|const|let|var|class)\s+(?P<name>[A-Za-z_$][\w$]*)",
    re.MULTILINE,
)
_JS_DEFAULT_EXPORT_RE = re.compile(r"^export\s+default\s+(?:function\s+)?(?P<name>[A-Za-z_$][\w$]*)", re.MULTILINE)


def _detect_js_exports(text: str, rel: str) -> list[Export]:
    out: list[Export] = []
    for m in _JS_NAMED_EXPORT_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(Export(symbol=m.group("name"), kind="named", source=f"{rel}:{line}"))
    for m in _JS_DEFAULT_EXPORT_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(Export(symbol=m.group("name"), kind="default", source=f"{rel}:{line}"))
    return out


_GETENV_RE = re.compile(
    r"os\.getenv\(\s*['\"](?P<name>[A-Z][A-Z0-9_]*)['\"]"
    r"(?:\s*,\s*['\"](?P<default>[^'\"]*)['\"])?",
)
_OSENV_BRACKET_RE = re.compile(r"os\.environ\[\s*['\"](?P<name>[A-Z][A-Z0-9_]*)['\"]\s*\]")
_PROCESSENV_RE = re.compile(r"process\.env\.(?P<name>[A-Z][A-Z0-9_]*)")


def _detect_env_vars(text: str, rel: str) -> list[EnvVar]:
    out: list[EnvVar] = []
    seen: set[str] = set()
    for m in _GETENV_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(
            name=m.group("name"),
            required=False,
            default=m.group("default"),
            source=f"{rel}:{line}",
        ))
    for m in _OSENV_BRACKET_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(name=m.group("name"), required=True, default=None, source=f"{rel}:{line}"))
    for m in _PROCESSENV_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(name=m.group("name"), required=False, default=None, source=f"{rel}:{line}"))
    return out
