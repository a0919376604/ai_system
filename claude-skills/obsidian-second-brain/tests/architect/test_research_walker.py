"""Tests for scripts.architect.research_walker.collect_research_excerpts."""
from __future__ import annotations

from pathlib import Path

import pytest

from scripts.architect.research_walker import collect_research_excerpts

FIXTURE = Path(__file__).parent / "fixtures" / "vault_with_research"


def test_walks_research_dir_recursively():
    """Both top-level and sub/ research notes are returned."""
    excerpts = collect_research_excerpts(FIXTURE)
    paths = [e["path"] for e in excerpts]
    assert any(p.endswith("A.md") for p in paths), f"missing A.md; got {paths}"
    assert any(p.endswith("B.md") for p in paths), f"missing B.md; got {paths}"


def test_excerpt_fields_populated_from_frontmatter():
    """Each excerpt has title, first_para, tags, date keys."""
    excerpts = collect_research_excerpts(FIXTURE)
    a = next(e for e in excerpts if e["path"].endswith("A.md"))
    assert a["title"] == "LINE bot 趨勢 2026"
    assert a["date"] == "2026-04-15"
    assert "competitor" in a["tags"]
    assert "LINE 官方 2026 Q1" in a["first_para"]
    assert len(a["first_para"]) <= 500


def test_ordered_by_date_desc():
    """Most recent date first."""
    excerpts = collect_research_excerpts(FIXTURE)
    assert excerpts[0]["date"] >= excerpts[-1]["date"]
    # A (2026-04) before B (2026-03)
    assert excerpts[0]["path"].endswith("A.md")


def test_returns_empty_when_dir_missing(tmp_path):
    """No Research/ subdir → empty list, no crash."""
    assert collect_research_excerpts(tmp_path) == []


def test_caps_at_max_files(tmp_path):
    """When >10 research notes exist, return only 10 (most recent dates)."""
    research = tmp_path / "Research"
    research.mkdir()
    for i in range(15):
        # date format YYYY-MM-DD; use month MM = i+1 (Jan = 01, etc.) padded.
        month = f"{(i % 12) + 1:02d}"
        (research / f"note-{i:02d}.md").write_text(
            f"---\ntitle: Note {i}\ndate: 2026-{month}-01\ntags: []\n---\n\n"
            f"Body paragraph for note {i}.\n",
            encoding="utf-8",
        )
    excerpts = collect_research_excerpts(tmp_path)
    assert len(excerpts) == 10


def test_skips_notes_without_frontmatter(tmp_path):
    """Markdown files without `---` frontmatter are skipped (treated as junk)."""
    research = tmp_path / "Research"
    research.mkdir()
    (research / "no-fm.md").write_text("Just a paragraph, no frontmatter.\n", encoding="utf-8")
    (research / "with-fm.md").write_text(
        "---\ntitle: T\ndate: 2026-05-01\ntags: []\n---\n\nBody.\n",
        encoding="utf-8",
    )
    excerpts = collect_research_excerpts(tmp_path)
    assert len(excerpts) == 1
    assert excerpts[0]["title"] == "T"
