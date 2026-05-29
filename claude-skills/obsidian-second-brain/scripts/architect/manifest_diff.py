"""Manifest diff: classify changes between two module lists by slug."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ModuleDiff:
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    renamed: list[tuple[str, list[str], list[str]]] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)


def diff_modules(old: list[dict], new: list[dict]) -> ModuleDiff:
    """Classify slug-level changes between two manifest module lists.

    Added: slug in new but not old.
    Removed: slug in old but not new.
    Renamed: same slug, different paths.
    """
    old_by_slug = {m["slug"]: m for m in old}
    new_by_slug = {m["slug"]: m for m in new}

    d = ModuleDiff()
    d.added = sorted(set(new_by_slug) - set(old_by_slug))
    d.removed = sorted(set(old_by_slug) - set(new_by_slug))

    for slug in sorted(set(old_by_slug) & set(new_by_slug)):
        old_paths = sorted(old_by_slug[slug].get("paths", []))
        new_paths = sorted(new_by_slug[slug].get("paths", []))
        if old_paths != new_paths:
            d.renamed.append((slug, old_paths, new_paths))
        else:
            d.unchanged.append(slug)
    return d
