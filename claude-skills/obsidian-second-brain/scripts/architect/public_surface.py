"""Choose which functions get their own `Architecture/functions/<module>/<func>.md` note.

Eligibility (per spec §5.6):
- Symbol is a CLI subcommand handler
- Symbol is an HTTP route handler
- Symbol appears in __all__ or is a named/default export
Symbols whose source file maps to no manifest module are skipped.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from scripts.architect.api_surface import ApiSurface


@dataclass(frozen=True)
class EligibleFunction:
    module_slug: str
    name: str
    source: str        # "<path>:<line>" verbatim
    kind: str          # cli-handler / http-handler / export


def eligible_functions(surface: ApiSurface, module_paths: dict[str, list[str]]) -> list[EligibleFunction]:
    """Return deduplicated list of functions worthy of their own note."""
    seen: set[tuple[str, str]] = set()
    out: list[EligibleFunction] = []

    def _add(name: str, source: str, kind: str):
        slug = _which_module(source.split(":")[0], module_paths)
        if slug == "_unmapped":
            return
        key = (slug, name)
        if key in seen:
            return
        seen.add(key)
        out.append(EligibleFunction(module_slug=slug, name=name, source=source, kind=kind))

    for c in surface.cli_commands:
        _add(c.name, c.source, "cli-handler")
    for r in surface.http_routes:
        if r.handler == "(anonymous)":
            continue
        _add(r.handler, r.source, "http-handler")
    for e in surface.exports:
        _add(e.symbol, e.source, "export")
    return out


def _which_module(rel_path: str, module_paths: dict[str, list[str]]) -> str:
    for slug, paths in module_paths.items():
        for prefix in paths:
            if rel_path == prefix or rel_path.startswith(prefix.rstrip("/") + "/"):
                return slug
    return "_unmapped"
