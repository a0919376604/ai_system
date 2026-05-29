"""Walk vault Projects/<P>/Research/ for excerpts feeding features.md gap analysis.

Pure function: given a project hub directory path, returns a list of dict
excerpts ordered by frontmatter `date:` descending. Used by Phase 1 scanner
to seed product-gap-analysis grounding.
"""
from __future__ import annotations

import re
from pathlib import Path

_MAX_FILES = 10
_MAX_TOTAL_BYTES = 10_000
_FIRST_PARA_CAP = 500

_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n(.*)$", re.DOTALL)
_TAGS_LIST_RE = re.compile(r"\[([^\]]*)\]")


def collect_research_excerpts(project_dir: Path) -> list[dict]:
    """Return excerpts from <project_dir>/Research/**/*.md.

    Each excerpt: {path (vault-relative posix), title, first_para, tags, date}.

    Returns [] if project_dir or Research/ subdir does not exist.
    Sorted by `date` frontmatter desc (most recent first).
    Capped at 10 files OR 10KB of total excerpt bytes, whichever hits first.
    """
    research_dir = project_dir / "Research"
    if not research_dir.is_dir():
        return []

    raw_entries: list[dict] = []
    for md_path in research_dir.rglob("*.md"):
        excerpt = _excerpt_from_file(md_path, project_dir)
        if excerpt is not None:
            raw_entries.append(excerpt)

    raw_entries.sort(key=lambda e: e.get("date", ""), reverse=True)

    # Cap by file count + cumulative byte count.
    out: list[dict] = []
    cumulative = 0
    for entry in raw_entries:
        if len(out) >= _MAX_FILES:
            break
        excerpt_bytes = len(entry["first_para"].encode("utf-8"))
        if cumulative + excerpt_bytes > _MAX_TOTAL_BYTES:
            break
        cumulative += excerpt_bytes
        out.append(entry)
    return out


def _excerpt_from_file(md_path: Path, project_dir: Path) -> dict | None:
    """Parse one research markdown file into an excerpt dict, or None on failure."""
    try:
        text = md_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None

    m = _FRONTMATTER_RE.match(text)
    if m is None:
        # No frontmatter — skip; research walker only handles structured notes.
        return None
    fm_block, body = m.group(1), m.group(2)

    fm = _parse_simple_frontmatter(fm_block)
    title = fm.get("title", md_path.stem)
    date = fm.get("date", "")
    tags = _parse_tags(fm.get("tags", "[]"))

    # First non-blank paragraph (until first \n\n).
    body = body.lstrip()
    para = body.split("\n\n", 1)[0].strip()
    if len(para) > _FIRST_PARA_CAP:
        para = para[:_FIRST_PARA_CAP].rsplit(" ", 1)[0] + "…"

    return {
        "path": str(md_path.relative_to(project_dir).as_posix()),
        "title": title,
        "first_para": para,
        "tags": tags,
        "date": date,
    }


def _parse_simple_frontmatter(block: str) -> dict[str, str]:
    """Minimal YAML-ish parser: `key: value` per line. Ignores nested structures
    other than `tags: [a, b]` which is handled separately via _parse_tags."""
    out: dict[str, str] = {}
    for line in block.splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip().strip('"').strip("'")
    return out


def _parse_tags(raw: str) -> list[str]:
    """Parse `[a, b, c]` style tag list. Returns [] if no match."""
    m = _TAGS_LIST_RE.search(raw)
    if not m:
        return []
    return [t.strip().strip('"').strip("'") for t in m.group(1).split(",") if t.strip()]
