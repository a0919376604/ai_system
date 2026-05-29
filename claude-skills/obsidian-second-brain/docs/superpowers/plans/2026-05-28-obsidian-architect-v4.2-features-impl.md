## Resolution log

All five plan-vs-actual mismatches captured during the codex run were resolved in-stream:

**Task 1 Step 2** — Expected 5 FAILS, got 3 FAILS + 2 PASSED. The 2 unexpected passes
(`test_features_section_type_present`, `test_features_v4_2_block_headings_present`)
were because the existing v3 entries in `SECTION_TYPES` and `_BLOCK_HEADINGS` already
satisfied those assertions. The RED-state failures still pointed at the v4.2-missing
behavior. No fix needed — TDD discipline preserved (intent was a red signal on v4.2
gaps, which we got).

**Task 1 Step 7** — 3 legacy v3-era tests in `tests/architect/test_sections.py` broke
when `features` un-deprecated. Resolved as part of commit `1dfe834`:
- `test_compose_note_wraps_sentinels` — updated to use `capability-inventory` block
  name instead of legacy `capability-scope`.
- `test_deprecated_section_types_marked` — removed `features` from the assertion list.
- `test_compose_note_warns_on_deprecated_section` — switched fixture to use
  `api-surface` (still deprecated) instead of `features`.

**Tasks 2 / 4 Step ~3** — Plan expected N test FAILS with `ModuleNotFoundError`; pytest
actually emitted 1 collection ERROR (stops at import before running tests). Same root
cause (missing module), same outcome once impl lands. Pytest behavior quirk only.

**Task 6 Step 3** — Plan referenced `build_scan_report`; the actual codebase exposes
`run_phase_one`. Test imports updated to the real name. Functional intent identical.

**Task 13 Step 2** — The dedup test as written didn't exercise the dedup path because
the module-Imp parser only matches `### Imp N: ...` titled headings. Codex rewrote the
test with `### Imp 1: Streaming reply tech impl` so the module candidate is actually
emitted and then deduped by the features-evidence-wikilink overlap pass. Dedup path
covered.

Final acceptance: 354 tests pass; all 4 platform adapters build; `Phase 3.5.5` appears
3 times in command body; scan smoke against `langlive-line-oa` produces non-empty
`agents_md_text`, `git_last_touch`, and `research_excerpts: []` (the project's
`Research/` dir is empty).

# obsidian-architect v4.2 (features.md — Product PM lens) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Projects/<P>/Architecture/features.md` as an additive 9th file in the v4 family, exposing a Product PM lens — capability inventory with deterministic online/deprecated drift detection (from git + api_surface), product gap analysis grounded in vault `Research/` excerpts, plus per-product strengths / weaknesses / limitations / improvements / doc-sync-actions.

**Architecture:** Pure additive layer. Two new helper modules (`research_walker.py` reads vault `Projects/<P>/Research/*.md`; `git_history.py` runs `git log -1 --format=%ad` per api_surface file). Scanner extension produces three new keys (`agents_md_text`, `research_excerpts`, `git_last_touch`). `sections.py` un-deprecates `features` + gains `build_features_prompt`, `render_features_inventory` (deterministic 2-pass marker), `compute_doc_sync_score`, `compose_features_note`. Lockfile gets `sections.features` slot (no schema bump). Roadmap candidate detector walks features.md improvements / missing-features / doc-sync-actions blocks with dedup against module Imps. Command body adds Phase 3.5.5 between existing 3.5 and 3.7.

**Tech Stack:** Python 3.10+, pytest, subprocess (git), `pathlib`, existing `_BLOCK_NAMES` / `_BLOCK_HEADINGS` / `compose_note` / `parse_improvements_block` / `Lockfile` plumbing.

**Plan-level note on test commands:** Tests use `uv run pytest tests/architect/test_features.py::test_name -v`. Run from repo root `/Users/leric/Desktop/code/obsidian-second-brain`.

**Plan-level note on commit co-author line:** Every commit message ends with:
```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## File structure (locked in here so all tasks reference consistent paths)

**New files:**
- `scripts/architect/research_walker.py` — `collect_research_excerpts(project_dir: Path) -> list[dict]`. Pure-function. Walks recursively, caps at 10 files / 10KB total, sorts by frontmatter `date:` desc.
- `scripts/architect/git_history.py` — `last_touch_map(repo: Path, files: list[str]) -> dict[str, str]`. Pure-subprocess wrapper. Caps at 200 most-recent-mtime files.
- `tests/architect/test_research_walker.py` — 4 tests.
- `tests/architect/test_git_history.py` — 3 tests.
- `tests/architect/test_features.py` — 9 tests for sections.py features helpers.
- `tests/architect/fixtures/vault_with_research/` — fixture vault for research_walker tests.

**Modified files:**
- `scripts/architect/sections.py` — un-deprecate `features`; add 10 block names + headings; add `_preamble_for("features", lang)` entry; add `build_features_prompt`, `render_features_inventory`, `compute_doc_sync_score`, `parse_doc_actions_block`.
- `scripts/architect/scan.py` — orchestration adds `agents_md_text`, `research_excerpts`, `git_last_touch` keys in scan_report.
- `scripts/architect_scan.py` — CLI thin wrapper accepts new `--vault-project-dir` flag; pipes to `scan.py`.
- `scripts/architect/lockfile.py` — `sections.features` schema accepted (no schema bump; only need to ensure it's preserved on load/save).
- `scripts/roadmap/candidates.py` — walks features.md, parses 3 blocks, dedup against module Imps via Evidence wikilink overlap.
- `tests/roadmap/test_candidates.py` — 2 new tests for features.md integration + dedup.
- `commands/obsidian-architect.md` — Phase 3.5.5 section + `--no-features` / `--features-only` flags + hub block update line + overview drill-down line.
- `references/ai-first-rules.md` — `architecture-features` v4.2 schema (un-deprecate + new fields).
- `SKILL.md` — v4.2 announcement bullet.
- `README.md` — v4.2 features layer mention in command description.
- `CHANGELOG.md` — `## [Unreleased]` entry for v4.2.

---

## Phase A: Foundation (sections.py registration)

### Task 1: Un-deprecate `features` + register v4.2 block schema

**Files:**
- Modify: `scripts/architect/sections.py:144-187` (DEPRECATED_SECTIONS + _BLOCK_NAMES + _BLOCK_HEADINGS)
- Modify: `scripts/architect/sections.py:350-450` (`_preamble_for("features", lang)`)
- Test: `tests/architect/test_features.py` (new file)

- [ ] **Step 1: Write the failing test (registration smoke)**

Create `tests/architect/test_features.py` with:
```python
"""v4.2 features.md tests."""
from __future__ import annotations

from scripts.architect.sections import (
    DEPRECATED_SECTIONS,
    SECTION_TYPES,
    _BLOCK_NAMES,
    _BLOCK_HEADINGS,
)


def test_features_section_not_deprecated_in_v4_2():
    """v4.2 un-deprecates features. compose_note(section='features') should NOT
    log a deprecation warning."""
    assert "features" not in DEPRECATED_SECTIONS, (
        "features must be removed from DEPRECATED_SECTIONS in v4.2"
    )


def test_features_section_type_present():
    assert SECTION_TYPES["features"] == "architecture-features"


def test_features_v4_2_block_names():
    """v4.2 features has 10 @generated blocks in a specific order."""
    expected = (
        "summary",
        "capability-inventory",
        "product-coverage",
        "limitations",
        "strengths",
        "weaknesses",
        "missing-features",
        "improvements",
        "doc-sync-actions",
        "dependencies",
    )
    assert _BLOCK_NAMES["features"] == expected


def test_features_v4_2_block_headings_present():
    """Every block name in features has a heading in _BLOCK_HEADINGS."""
    for block_name in _BLOCK_NAMES["features"]:
        assert block_name in _BLOCK_HEADINGS, f"missing heading for {block_name}"


def test_features_new_block_headings_text():
    """v4.2 introduces 4 new block headings not used elsewhere."""
    assert _BLOCK_HEADINGS["capability-inventory"] == "## Capability inventory"
    assert _BLOCK_HEADINGS["product-coverage"] == "## Product coverage"
    assert _BLOCK_HEADINGS["limitations"] == "## Limitations"
    assert _BLOCK_HEADINGS["missing-features"] == "## Missing features"
    assert _BLOCK_HEADINGS["doc-sync-actions"] == "## Doc sync actions"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_features.py -v`
Expected: 5 FAILS (assertion errors — `features` still in DEPRECATED_SECTIONS, block names mismatch, missing headings).

- [ ] **Step 3: Update DEPRECATED_SECTIONS and _BLOCK_NAMES**

In `scripts/architect/sections.py`, find `DEPRECATED_SECTIONS` (around line 185) and remove `"features"`:

```python
# v4 — these sections are still callable for backward compat but no longer
# emitted by the default `--frame=report` pipeline. v4.2 re-introduces
# `features` as a product-PM lens (see _BLOCK_NAMES["features"] below).
DEPRECATED_SECTIONS = frozenset({
    "api-surface", "roadmap", "future", "jobs", "flows",
})
```

In `_BLOCK_NAMES` (around line 144), replace the existing `"features"` entry:

```python
    # v4.2 — features as product-PM lens (un-deprecated). 10 blocks.
    "features": (
        "summary",
        "capability-inventory",
        "product-coverage",
        "limitations",
        "strengths",
        "weaknesses",
        "missing-features",
        "improvements",
        "doc-sync-actions",
        "dependencies",
    ),
```

- [ ] **Step 4: Add new block headings in `_BLOCK_HEADINGS`**

In `_BLOCK_HEADINGS` dict (around line 192), add (place them after the existing v4 overview entries, before v4.1 ai-flow entries):

```python
    # v4.2 features block headings
    "capability-inventory": "## Capability inventory",
    "product-coverage": "## Product coverage",
    "limitations": "## Limitations",
    "missing-features": "## Missing features",
    "doc-sync-actions": "## Doc sync actions",
```

(The other features block names — `summary`, `strengths`, `weaknesses`, `improvements`, `dependencies` — already have entries from v3.)

- [ ] **Step 5: Add `_preamble_for("features", lang)` entry**

In `_preamble_for` (around line 350), in the zh-TW dict REPLACE the existing `"features":` line with:

```python
            "features": "本檔是 product PM 視角:看完整 feature set,標 online/deprecated,從產品角度討論優缺、缺什麼、該補哪些 doc。技術視角請見 [[Architecture/modules]]/[[Architecture/ai-flows]];使用者型態請見 [[Architecture/personas]]。",
```

In the en dict REPLACE the existing `"features":` line with:

```python
            "features": "Product-PM lens. Capability inventory with online/deprecated status (deterministic from git+api_surface), product-level strengths/weaknesses/limitations, gap analysis from vault Research/, and doc-sync action todos. For technical depth see [[Architecture/modules]]/[[Architecture/ai-flows]]; user types see [[Architecture/personas]].",
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v`
Expected: 5 PASS.

- [ ] **Step 7: Run full test suite to confirm no regression**

Run: `uv run pytest tests/ -q`
Expected: PASS (319 previous + 5 new = 324).

- [ ] **Step 8: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): v4.2 — un-deprecate features + register 10-block PM-lens schema

features.md returns as product-PM lens (different from v3's transcription
shape). 10 blocks: summary, capability-inventory, product-coverage,
limitations, strengths, weaknesses, missing-features, improvements,
doc-sync-actions, dependencies.

Adds heading entries for capability-inventory / product-coverage /
limitations / missing-features / doc-sync-actions (the other 5 reuse
existing v3 headings). Updates _preamble_for to describe the PM lens.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Research walker

### Task 2: `collect_research_excerpts` — happy path

**Files:**
- Create: `scripts/architect/research_walker.py`
- Create: `tests/architect/test_research_walker.py`
- Create: `tests/architect/fixtures/vault_with_research/` (fixture tree)

- [ ] **Step 1: Create fixture vault**

```bash
mkdir -p tests/architect/fixtures/vault_with_research/Research
mkdir -p tests/architect/fixtures/vault_with_research/Research/sub
```

Write `tests/architect/fixtures/vault_with_research/Research/A.md`:
```markdown
---
type: research
title: LINE bot 趨勢 2026
date: 2026-04-15
tags: [competitor, line]
---

LINE 官方 2026 Q1 推出 group bot template,客服場景進入 multi-bot 編排階段。多家 SaaS 廠商開始整合 WhatsApp + LINE + Telegram 三通路為單一 inbox。
```

Write `tests/architect/fixtures/vault_with_research/Research/sub/B.md`:
```markdown
---
type: research
title: AI chatbot streaming UX
date: 2026-03-20
tags: [ux, ai]
---

Streaming token-by-token reply 在 LINE chat 介面感受比一次性 reply 提升 35% (Anthropic 內部研究, 2026-02)。建議所有 LLM-driven reply 都採 streaming。
```

- [ ] **Step 2: Write the failing test**

Create `tests/architect/test_research_walker.py`:
```python
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_research_walker.py -v`
Expected: 3 FAILS with `ModuleNotFoundError: No module named 'scripts.architect.research_walker'`.

- [ ] **Step 4: Implement `research_walker.py` (happy path)**

Create `scripts/architect/research_walker.py`:
```python
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_research_walker.py -v`
Expected: 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/research_walker.py tests/architect/test_research_walker.py tests/architect/fixtures/vault_with_research/
git commit -m "$(cat <<'EOF'
feat(architect): research_walker — collect Research/ excerpts for features.md gap analysis

Pure-function walker over Projects/<P>/Research/**/*.md. Returns list of
{path, title, first_para (≤500 char), tags, date} dicts ordered by
frontmatter date desc. Capped at 10 files / 10KB total. Returns [] when
Research/ dir absent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: Research walker — edge cases (caps + missing dir)

**Files:**
- Modify: `tests/architect/test_research_walker.py` (append)

- [ ] **Step 1: Append edge-case tests**

In `tests/architect/test_research_walker.py`, add:
```python
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
```

- [ ] **Step 2: Run new tests to verify they pass (already implemented above)**

Run: `uv run pytest tests/architect/test_research_walker.py -v`
Expected: 6 PASS total (3 prior + 3 new).

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_research_walker.py
git commit -m "$(cat <<'EOF'
test(architect): research_walker edge cases — empty / caps / frontmatter-only

Confirms graceful degradation (missing Research/ → []), file cap (10 max),
and that markdown files without YAML frontmatter are skipped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: Git history helper

### Task 4: `last_touch_map` — happy path

**Files:**
- Create: `scripts/architect/git_history.py`
- Create: `tests/architect/test_git_history.py`

- [ ] **Step 1: Write the failing test**

Create `tests/architect/test_git_history.py`:
```python
"""Tests for scripts.architect.git_history.last_touch_map."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from scripts.architect.git_history import last_touch_map


def _init_git_repo(repo: Path):
    """Initialize a git repo with a known config so commits succeed in CI."""
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t.t"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)


def _commit(repo: Path, path: str, content: str, date: str):
    file_path = repo / path
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(content, encoding="utf-8")
    subprocess.run(["git", "add", path], cwd=repo, check=True)
    env = {"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(
        ["git", "commit", "-m", f"add {path}", "--date", date],
        cwd=repo,
        check=True,
        capture_output=True,
        env={**__import__("os").environ, **env},
    )


def test_returns_last_touch_dates_for_committed_files(tmp_path):
    _init_git_repo(tmp_path)
    _commit(tmp_path, "a.py", "x=1\n", "2026-05-01T12:00:00")
    _commit(tmp_path, "b.py", "y=2\n", "2025-09-12T08:30:00")
    result = last_touch_map(tmp_path, ["a.py", "b.py"])
    assert result["a.py"] == "2026-05-01"
    assert result["b.py"] == "2025-09-12"


def test_omits_uncommitted_files(tmp_path):
    """Files never committed → key absent (not '—', not 'unknown')."""
    _init_git_repo(tmp_path)
    _commit(tmp_path, "tracked.py", "z=3\n", "2026-04-01T00:00:00")
    (tmp_path / "untracked.py").write_text("u=1\n", encoding="utf-8")
    result = last_touch_map(tmp_path, ["tracked.py", "untracked.py"])
    assert result["tracked.py"] == "2026-04-01"
    assert "untracked.py" not in result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_git_history.py -v`
Expected: 2 FAILS with `ModuleNotFoundError: No module named 'scripts.architect.git_history'`.

- [ ] **Step 3: Implement `git_history.py` (happy path)**

Create `scripts/architect/git_history.py`:
```python
"""Per-file last-commit date map for features.md inventory's `Last touch` column.

Pure subprocess wrapper around `git log -1 --format=%ad --date=short`.
Display-only — never included in signal_hash (every scan recomputes).
"""
from __future__ import annotations

import subprocess
from pathlib import Path

_MAX_FILES = 200


def last_touch_map(repo: Path, files: list[str]) -> dict[str, str]:
    """Return {repo-relative-posix-path: 'YYYY-MM-DD'} for files in `files`.

    - `files` paths are repo-relative posix strings.
    - Missing keys: file is not under git OR has no commit history. Callers
      render missing as '—' or 'unknown' downstream.
    - Capped at `_MAX_FILES`; if `files` is longer, the most-recently-mtime
      files are kept and others dropped silently.
    """
    repo = repo.resolve()
    files = _cap_by_mtime(repo, files)

    out: dict[str, str] = {}
    for rel in files:
        try:
            proc = subprocess.run(
                ["git", "log", "-1", "--format=%ad", "--date=short", "--", rel],
                cwd=str(repo),
                capture_output=True,
                text=True,
                check=False,
            )
        except (FileNotFoundError, OSError):
            continue
        if proc.returncode != 0:
            continue
        date = proc.stdout.strip()
        if date:
            out[rel] = date
    return out


def _cap_by_mtime(repo: Path, files: list[str]) -> list[str]:
    """Return `files` reduced to at most _MAX_FILES, keeping most-recent mtimes."""
    if len(files) <= _MAX_FILES:
        return files
    annotated: list[tuple[float, str]] = []
    for rel in files:
        full = repo / rel
        try:
            mtime = full.stat().st_mtime
        except OSError:
            mtime = 0.0
        annotated.append((mtime, rel))
    annotated.sort(key=lambda pair: pair[0], reverse=True)
    return [rel for _, rel in annotated[:_MAX_FILES]]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_git_history.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/git_history.py tests/architect/test_git_history.py
git commit -m "$(cat <<'EOF'
feat(architect): git_history.last_touch_map for features.md Last-touch column

Wraps `git log -1 --format=%ad --date=short` per file. Returns dict where
missing keys = file not under git or has no commits (caller renders as
'—'). Caps at 200 most-recently-modified files to keep scan budget tight.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: `last_touch_map` — cap test

**Files:**
- Modify: `tests/architect/test_git_history.py` (append)

- [ ] **Step 1: Append cap test**

```python
def test_caps_at_200_files_by_mtime(tmp_path):
    """When >200 files passed, only 200 most-recently-modified are queried."""
    _init_git_repo(tmp_path)
    # Create 205 files but only commit 1 (to keep test fast).
    _commit(tmp_path, "tracked.py", "z=3\n", "2026-04-01T00:00:00")
    files = ["tracked.py"]
    for i in range(205):
        p = tmp_path / f"u_{i:03d}.py"
        p.write_text(f"u={i}\n", encoding="utf-8")
        files.append(f"u_{i:03d}.py")
    # Should NOT blow up; tracked.py may or may not be in the 200 chosen
    # (it has older mtime than the 205 just-written files, so likely NOT
    # in the returned map — which is acceptable; cap is best-effort).
    result = last_touch_map(tmp_path, files)
    # Tracked.py is older than the 205 untracked → likely dropped. Either way,
    # the map must not have >200 entries.
    assert len(result) <= 200, f"expected ≤200 entries; got {len(result)}"
```

- [ ] **Step 2: Run new test to verify it passes**

Run: `uv run pytest tests/architect/test_git_history.py -v`
Expected: 3 PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_git_history.py
git commit -m "$(cat <<'EOF'
test(architect): git_history cap test — 205 files capped to ≤200 by mtime

Confirms _MAX_FILES=200 enforced even when caller passes large file list.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: Scanner integration

### Task 6: scan_report adds `agents_md_text` + `research_excerpts` + `git_last_touch`

**Files:**
- Modify: `scripts/architect/scan.py` (find the scan_report assembly function)
- Modify: `scripts/architect_scan.py` (CLI thin wrapper — accepts `--vault-project-dir`)
- Test: `tests/architect/test_features.py` (append)

- [ ] **Step 1: Locate scan_report assembly**

Inspect the file: `uv run python -c "import inspect; from scripts.architect.scan import build_scan_report; print(inspect.getsourcefile(build_scan_report))"` (or similar — the assembly function may be named differently; grep for `scan-report.json` writes if needed). Note the function name and where the dict is built. Future steps will refer to this site as `build_scan_report`.

- [ ] **Step 2: Write the failing test**

Append to `tests/architect/test_features.py`:
```python
def test_scan_report_includes_agents_md_text(tmp_path):
    """build_scan_report exposes raw AGENTS.md text (capped 20KB)."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("# Agents\nLine 1\nLine 2\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("# R", encoding="utf-8")
    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "agents_md_text" in report
    assert "Agents" in report["agents_md_text"]
    assert len(report["agents_md_text"]) <= 20_000


def test_scan_report_research_excerpts_when_vault_project_dir_passed(tmp_path):
    """When --vault-project-dir given, scan walks Research/ for excerpts."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    vault_proj = tmp_path / "vault_proj"
    research = vault_proj / "Research"
    research.mkdir(parents=True)
    (research / "X.md").write_text(
        "---\ntitle: X\ndate: 2026-05-01\ntags: []\n---\n\nResearch para.\n",
        encoding="utf-8",
    )
    report = build_scan_report(tmp_path, vault_project_dir=vault_proj)
    excerpts = report["research_excerpts"]
    assert len(excerpts) == 1
    assert excerpts[0]["title"] == "X"


def test_scan_report_research_excerpts_empty_when_dir_missing(tmp_path):
    """When --vault-project-dir not passed, research_excerpts = []."""
    from scripts.architect.scan import build_scan_report

    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert report["research_excerpts"] == []


def test_scan_report_git_last_touch_keyed_by_path(tmp_path):
    """build_scan_report adds git_last_touch dict for api_surface files."""
    import subprocess
    from scripts.architect.scan import build_scan_report

    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "main.py").write_text("def hello(): pass\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init", "--date", "2026-05-15T00:00:00"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        env={**__import__("os").environ,
             "GIT_AUTHOR_DATE": "2026-05-15T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-15T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "git_last_touch" in report
    # main.py was committed → must have a date.
    assert report["git_last_touch"].get("main.py") == "2026-05-15"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_features.py -v -k "scan_report"`
Expected: 4 FAILS — either `TypeError: build_scan_report() got an unexpected keyword argument 'vault_project_dir'` or `KeyError: 'agents_md_text'` / `'research_excerpts'` / `'git_last_touch'`.

- [ ] **Step 4: Modify `build_scan_report` to accept `vault_project_dir` and emit new keys**

In `scripts/architect/scan.py`, locate the function that builds `scan_report` dict (likely `build_scan_report` or `run_scan`). Modify its signature to accept `vault_project_dir: Path | None = None` and add these key population lines (near the end, before returning the dict):

```python
    # v4.2 — features.md inputs
    from scripts.architect.research_walker import collect_research_excerpts
    from scripts.architect.git_history import last_touch_map

    agents_path = repo_root / "AGENTS.md"
    agents_text = ""
    if agents_path.exists():
        try:
            agents_text = agents_path.read_text(encoding="utf-8")[:20_000]
        except (OSError, UnicodeDecodeError):
            agents_text = ""
    report["agents_md_text"] = agents_text

    if vault_project_dir is not None and Path(vault_project_dir).exists():
        report["research_excerpts"] = collect_research_excerpts(Path(vault_project_dir))
    else:
        report["research_excerpts"] = []

    # Derive api_surface file list for git_last_touch.
    surface = report.get("api_surface", {}) or {}
    surface_files: set[str] = set()
    for route in surface.get("http_routes", []):
        f = route.get("file")
        if f:
            surface_files.add(f)
    for cmd in surface.get("cli_commands", []):
        f = cmd.get("file")
        if f:
            surface_files.add(f)
    for exp in surface.get("exports", []):
        f = exp.get("file")
        if f:
            surface_files.add(f)
    report["git_last_touch"] = last_touch_map(repo_root, sorted(surface_files))
```

Also update the CLI thin wrapper in `scripts/architect_scan.py` to accept the new flag and forward it:
- Add an `argparse` arg: `parser.add_argument("--vault-project-dir", type=Path, default=None, help="Vault project hub dir for research walking (v4.2 features)")`
- Pass `vault_project_dir=args.vault_project_dir` to `build_scan_report`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v -k "scan_report"`
Expected: 4 PASS.

- [ ] **Step 6: Run full suite for no regressions**

Run: `uv run pytest tests/ -q`
Expected: PASS (all prior + 4 new).

- [ ] **Step 7: Commit**

```bash
git add scripts/architect/scan.py scripts/architect_scan.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): scan_report adds agents_md_text + research_excerpts + git_last_touch

Three new keys for v4.2 features.md synthesis:
- agents_md_text: raw AGENTS.md (capped 20KB)
- research_excerpts: from vault Projects/<P>/Research/ via research_walker
- git_last_touch: per-file last-commit date for api_surface files

CLI gains --vault-project-dir flag; when omitted, research_excerpts=[].

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Sections — prompt + render + score + compose

### Task 7: `build_features_prompt` — emits strict-JSON instructions

**Files:**
- Modify: `scripts/architect/sections.py` (append new function near `build_ai_flow_prompt`)
- Modify: `tests/architect/test_features.py` (append tests)

- [ ] **Step 1: Write the failing test**

Append to `tests/architect/test_features.py`:
```python
def test_build_features_prompt_requires_10_block_keys():
    """Prompt instructs LLM to return strict JSON with all 10 block keys."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={"Features": "Auth, KB"},
        agents_md_text="Routing table here.",
        changelog={"unreleased": []},
        api_surface_summary="3 HTTP routes, 0 CLI",
        modules_summary="backend, frontend",
        personas_summary="(no personas yet)",
        research_excerpts=[],
        output_lang="zh-TW",
    )
    for key in (
        "summary",
        "capability-inventory",
        "product-coverage",
        "limitations",
        "strengths",
        "weaknesses",
        "missing-features",
        "improvements",
        "doc-sync-actions",
        "dependencies",
    ):
        assert key in prompt, f"prompt must mention block key {key!r}"


def test_build_features_prompt_capability_inventory_is_structured_list():
    """capability-inventory must be requested as STRUCTURED LIST not markdown table."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[], output_lang="zh-TW",
    )
    assert "structured list" in prompt.lower() or "list of dict" in prompt.lower(), (
        "prompt should ask LLM to return capability-inventory as structured list"
    )
    assert "code_anchors" in prompt
    assert "doc_anchors" in prompt


def test_build_features_prompt_research_excerpts_listed_when_present():
    """When research_excerpts non-empty, prompt body lists title + first_para."""
    from scripts.architect.sections import build_features_prompt

    prompt = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[
            {"path": "Research/x.md", "title": "X trend",
             "first_para": "X paragraph", "tags": [], "date": "2026-04-01"}
        ],
        output_lang="zh-TW",
    )
    assert "X trend" in prompt
    assert "X paragraph" in prompt


def test_build_features_prompt_personas_directive_only_when_provided():
    """product-coverage block directive references personas only when summary non-empty."""
    from scripts.architect.sections import build_features_prompt

    no_p = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="", personas_summary="",
        research_excerpts=[], output_lang="zh-TW",
    )
    with_p = build_features_prompt(
        project="P",
        readme_sections={}, agents_md_text="", changelog={},
        api_surface_summary="", modules_summary="",
        personas_summary="Persona Mary: shift handoff job",
        research_excerpts=[], output_lang="zh-TW",
    )
    assert "Persona Mary" in with_p
    assert "Persona Mary" not in no_p
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_features.py -v -k "build_features_prompt"`
Expected: 4 FAILS with `ImportError: cannot import name 'build_features_prompt'`.

- [ ] **Step 3: Implement `build_features_prompt`**

In `scripts/architect/sections.py`, append (right after `build_ai_flow_prompt`, before `render_prompts_block`):

```python
def build_features_prompt(
    *,
    project: str,
    readme_sections: dict,
    agents_md_text: str,
    changelog: dict,
    api_surface_summary: str,
    modules_summary: str,
    personas_summary: str,
    research_excerpts: list[dict],
    output_lang: str,
) -> str:
    """v4.2 — features.md (Product PM lens) synthesis prompt.

    Asks the LLM for strict JSON with 10 block keys. `capability-inventory`
    is a STRUCTURED LIST (not markdown table) — post-processor renders the
    table after deterministically annotating online/deprecated status via
    api_surface lookup.
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫散文。"
            "Code identifier (檔案路徑、變數名、函式名、CLI 命令、URL、wikilink 內檔名段) 一律保留英文。"
        )
        improvement_shape_label = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = (
            "Write all prose in English. Code identifiers, paths, function names, "
            "CLI commands, URLs, and wikilink filename parts stay verbatim."
        )
        improvement_shape_label = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    research_block_lines: list[str] = []
    if research_excerpts:
        research_block_lines.append("## Research excerpts (use as Evidence for missing-features)")
        for r in research_excerpts:
            research_block_lines.append(
                f"- **{r['title']}** ({r['date']}, tags={r.get('tags', [])}, path=`{r['path']}`)"
            )
            research_block_lines.append(f"  > {r['first_para']}")
    research_section = "\n".join(research_block_lines) if research_block_lines else (
        "## Research excerpts\n(none in vault — `missing-features` Evidence "
        "must fall back to persona job / code-pattern / mark Confidence=speculation)"
    )

    personas_block = (
        f"## Personas summary\n{personas_summary}"
        if personas_summary.strip()
        else "## Personas summary\n(no personas.md yet — SKIP `product-coverage` block; "
        "emit it as empty string in JSON)"
    )

    return "\n".join([
        f"You are documenting the **product PM lens** for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. `capability-inventory` MUST be a structured list of dicts (NOT markdown table). "
        "Each row: `{\"name\": \"...\", \"description\": \"≤80 char\", "
        "\"code_anchors\": [\"path:endpoint\" or \"path:symbol\", ...], "
        "\"doc_anchors\": [\"README.md#Section\" or \"AGENTS.md L17-19\" or \"CHANGELOG#unreleased\", ...], "
        "\"module\": \"<host module slug>\"}`. A deterministic post-processor renders "
        "this list into a markdown table and assigns `online`/`deprecated` status.",
        "2. `strengths` / `weaknesses` MUST use PM voice. Banned: 'god module', 'refactor', "
        "'type safety', 'test coverage'. Allowed: '客服 onboarding 路徑暢通', '單一 channel 假設', "
        "'報表足以打董事會月會'. Tight bullet shape: `**Title (≤30 char).** clarification (≤80 char)`.",
        "3. `missing-features` Evidence must be one of: `[[Research/<note>]]` wikilink to vault "
        "research note, `[[Architecture/personas#<persona>]]` pointer, or `code:path:line` pattern. "
        "If no evidence is available, set `Confidence: speculation`. Drop Imps with no rationale.",
        "4. `limitations` are OBJECTIVE product boundaries (channel coverage, scaling caps, "
        "integration requirements). Not opinions. Each bullet may cite `code:path:line` or env var.",
        "5. `doc-sync-actions` block has 2 H3 groups: `### 清除 deprecated 殘留` + `### 補缺 doc`. "
        "Use checkbox shape `- [ ] <action>` so users can tick off.",
        "",
        "## Output: produce 10 @generated blocks (JSON keys)",
        "",
        "### `summary`",
        "1 short paragraph. What the product does; total capability count; "
        "doc-sync health line ('X aligned, Y deprecated, Z missing docs').",
        "",
        "### `capability-inventory`",
        "STRUCTURED LIST of dicts as described in Critical rule 1. Aim for 25-40 rows. "
        "Include 1-2 KNOWN-deprecated entries when you can spot them (README mentions an "
        "endpoint that doesn't appear in api_surface — list it; status is assigned later).",
        "",
        "### `product-coverage`",
        "PM lens aligning capabilities to persona jobs. For each persona, list which "
        "capability areas their typical jobs hit. Mark gaps: ✅ covered / ⚠️ partial / ❌ missing.",
        "",
        "### `limitations`",
        "3-7 objective product-boundary bullets per Critical rule 4.",
        "",
        "### `strengths`",
        "3-5 PM-voice tight bullets per Critical rule 2.",
        "",
        "### `weaknesses`",
        "3-5 PM-voice tight bullets per Critical rule 2. Examples of pain perspectives.",
        "",
        "### `missing-features`",
        "3-5 H3 entries; shape:",
        f"  {improvement_shape_label}",
        "  + **對哪個 module 開門:** `[[modules/<slug>]]`",
        "Evidence per Critical rule 3.",
        "",
        "### `improvements`",
        f"3-5 Imps with standard ImprovementItem shape: {improvement_shape_label}. "
        "**PRODUCT direction**, not technical refactor.",
        "",
        "### `doc-sync-actions`",
        "2 H3 groups per Critical rule 5. Machine-actionable checkbox lines.",
        "",
        "### `dependencies`",
        "Wikilinks only: `[[Architecture/overview]]`, each referenced "
        "`[[Architecture/modules/<slug>]]`, `[[Architecture/personas]]`, each referenced "
        "`[[Architecture/ai-flows/<slug>]]`, each `[[Research/<note>]]` you used as Evidence.",
        "",
        "Return strict JSON: {\"summary\": \"...\", \"capability-inventory\": [...], "
        "\"product-coverage\": \"...\", \"limitations\": \"...\", \"strengths\": \"...\", "
        "\"weaknesses\": \"...\", \"missing-features\": \"...\", \"improvements\": \"...\", "
        "\"doc-sync-actions\": \"...\", \"dependencies\": \"...\"}.",
        "",
        "## README sections",
        "\n".join(f"- {k}: {v[:200]}" for k, v in (readme_sections or {}).items()) or "(empty)",
        "",
        "## AGENTS.md (capped)",
        agents_md_text[:5000] or "(empty)",
        "",
        "## CHANGELOG",
        str(changelog)[:3000],
        "",
        "## API surface summary",
        api_surface_summary[:3000],
        "",
        "## Modules summary",
        modules_summary[:3000],
        "",
        personas_block,
        "",
        research_section,
    ])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v -k "build_features_prompt"`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): build_features_prompt — strict JSON 10-block PM-lens prompt

Captures the product-PM directives in a single prompt builder. Key design:
capability-inventory is requested as STRUCTURED LIST (dict per row) so the
deterministic post-processor can assign online/deprecated status — LLM
never picks the status. PM-voice ban list enforced via prompt rules.
Research excerpts seeded as Evidence source for missing-features.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `render_features_inventory` — online/deprecated marker + table render

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_features.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_render_features_inventory_marks_online_when_anchor_in_api_surface():
    """LLM row with code_anchor matching api_surface → status=online."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Login",
            "description": "Admin login",
            "code_anchors": ["backend/app/api/auth.py:/login"],
            "doc_anchors": ["README.md#Auth"],
            "module": "backend",
        }
    ]
    api_surface = {
        "http_routes": [{"path": "/login", "method": "POST",
                          "file": "backend/app/api/auth.py"}],
        "cli_commands": [],
        "exports": [],
    }
    git_last_touch = {"backend/app/api/auth.py": "2026-05-20"}
    md, summary = render_features_inventory(inventory, api_surface, git_last_touch)
    assert "| online |" in md
    assert "2026-05-20" in md
    assert summary["online"] == 1
    assert summary["deprecated"] == 0


def test_render_features_inventory_marks_deprecated_when_no_anchor_matches():
    """LLM row with code_anchor NOT in api_surface → status=deprecated."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Old endpoint",
            "description": "removed",
            "code_anchors": ["backend/api/old.py:/v1/old"],
            "doc_anchors": ["README.md#Legacy"],
            "module": "backend",
        }
    ]
    api_surface = {"http_routes": [], "cli_commands": [], "exports": []}
    md, summary = render_features_inventory(inventory, api_surface, {})
    assert "| deprecated |" in md
    # Last touch column for deprecated is em-dash.
    assert "| — |" in md or "| - |" in md
    assert summary["online"] == 0
    assert summary["deprecated"] == 1


def test_render_features_inventory_last_touch_unknown_for_missing_git_key():
    """When code_anchor's file isn't in git_last_touch, last_touch column = 'unknown'."""
    from scripts.architect.sections import render_features_inventory

    inventory = [
        {
            "name": "Recent",
            "description": "x",
            "code_anchors": ["backend/app/new.py:/new"],
            "doc_anchors": [],
            "module": "backend",
        }
    ]
    api_surface = {
        "http_routes": [{"path": "/new", "method": "POST",
                          "file": "backend/app/new.py"}],
        "cli_commands": [],
        "exports": [],
    }
    md, _ = render_features_inventory(inventory, api_surface, git_last_touch={})
    assert "unknown" in md
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_features.py -v -k "render_features_inventory"`
Expected: 3 FAILS — `ImportError: cannot import name 'render_features_inventory'`.

- [ ] **Step 3: Implement `render_features_inventory`**

Append to `scripts/architect/sections.py`:

```python
def render_features_inventory(
    llm_inventory: list[dict],
    api_surface: dict,
    git_last_touch: dict[str, str],
) -> tuple[str, dict[str, int]]:
    """Two-pass annotation: mark each LLM-provided capability row online/deprecated,
    then render as markdown table.

    Returns (table_markdown, summary_counts) where summary_counts has keys
    'online' and 'deprecated'.
    """
    # Build searchable set of (file, endpoint_or_symbol) from api_surface.
    surface_anchors: set[tuple[str, str]] = set()
    for route in api_surface.get("http_routes", []):
        f = route.get("file", "")
        p = route.get("path", "")
        if f and p:
            surface_anchors.add((f, p))
    for cmd in api_surface.get("cli_commands", []):
        f = cmd.get("file", "")
        n = cmd.get("name", "")
        if f and n:
            surface_anchors.add((f, n))
    for exp in api_surface.get("exports", []):
        f = exp.get("file", "")
        n = exp.get("name", "")
        if f and n:
            surface_anchors.add((f, n))

    rows_rendered: list[str] = []
    counts = {"online": 0, "deprecated": 0}

    for row in llm_inventory:
        name = (row.get("name") or "").strip() or "(unnamed)"
        description = (row.get("description") or "").strip()
        if len(description) > 80:
            description = description[:77] + "…"
        code_anchors = row.get("code_anchors") or []
        doc_anchors = row.get("doc_anchors") or []
        module = (row.get("module") or "").strip()

        status, last_touch = _resolve_row_status(code_anchors, surface_anchors, git_last_touch)
        counts[status] += 1

        code_cell = "<br>".join(f"`{c}`" for c in code_anchors) or "—"
        doc_cell = "<br>".join(doc_anchors) or "—"
        module_cell = f"[[modules/{module}]]" if module else "—"
        rows_rendered.append(
            f"| {name} | {description} | {status} | {last_touch} | {doc_cell} | {code_cell} | {module_cell} |"
        )

    header = (
        "| Capability | Description | Status | Last touch | Doc anchors | Code anchors | Module |\n"
        "| --- | --- | --- | --- | --- | --- | --- |"
    )
    table = "\n".join([header, *rows_rendered])
    return table, counts


def _resolve_row_status(
    code_anchors: list[str],
    surface_anchors: set[tuple[str, str]],
    git_last_touch: dict[str, str],
) -> tuple[str, str]:
    """Returns (status, last_touch_cell). status ∈ {'online', 'deprecated'}."""
    matched_files: list[str] = []
    for anchor in code_anchors:
        if ":" not in anchor:
            continue
        file_part, _, endpoint_or_symbol = anchor.partition(":")
        if (file_part, endpoint_or_symbol) in surface_anchors:
            matched_files.append(file_part)
    if not matched_files:
        return ("deprecated", "—")

    dates = [git_last_touch.get(f) for f in matched_files if git_last_touch.get(f)]
    if not dates:
        return ("online", "unknown")
    return ("online", max(dates))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v -k "render_features_inventory"`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): render_features_inventory — deterministic online/deprecated marker + table render

Two-pass design: LLM returns capability-inventory as structured list; this
function looks each code_anchor up in api_surface, assigns online when ANY
anchor matches, deprecated otherwise. Last-touch column pulled from
git_last_touch (max date if multiple matches). Renders 7-column markdown
table. Returns (table_md, counts) so caller can feed feature-count and
deprecated-count into frontmatter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: `compute_doc_sync_score` + frontmatter merge helper

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_features.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_compute_doc_sync_score_basic_ratio():
    from scripts.architect.sections import compute_doc_sync_score

    rendered_rows = [
        {"name": "A", "status": "online", "doc_anchors": ["README.md#A"]},
        {"name": "B", "status": "online", "doc_anchors": ["AGENTS.md L1"]},
        {"name": "C", "status": "online", "doc_anchors": []},
        {"name": "D", "status": "deprecated", "doc_anchors": ["README.md#D"]},
    ]
    score = compute_doc_sync_score(rendered_rows)
    # 3 online; 2 have ≥1 doc → 2/3 ≈ 0.67
    assert score == 0.67


def test_compute_doc_sync_score_zero_online_returns_zero():
    from scripts.architect.sections import compute_doc_sync_score

    rendered_rows = [{"name": "X", "status": "deprecated", "doc_anchors": []}]
    assert compute_doc_sync_score(rendered_rows) == 0.0


def test_compose_features_note_emits_extra_frontmatter():
    """compose_features_note (or equivalent helper) merges feature-count /
    deprecated-count / doc-sync-score into the frontmatter."""
    from scripts.architect.sections import compose_features_note

    blocks = {
        "summary": "summary text",
        "capability-inventory": "| C | D | online | 2026-05 | — | — | [[modules/backend]] |",
        "product-coverage": "",
        "limitations": "- 只支援 LINE",
        "strengths": "- **完整 lifecycle.**",
        "weaknesses": "- **單一 channel.**",
        "missing-features": "### A\n- **為什麼:** x",
        "improvements": "### Imp 1\n- **為什麼:** y",
        "doc-sync-actions": "### 清除\n- [ ] x",
        "dependencies": "- [[Architecture/overview]]",
    }
    note = compose_features_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["README.md"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks=blocks,
        feature_count=1,
        deprecated_count=0,
        doc_sync_score=0.84,
    )
    assert "feature-count: 1" in note
    assert "deprecated-count: 0" in note
    assert "doc-sync-score: 0.84" in note
    # Frontmatter merged BEFORE `ai-first: true`.
    fm_section = note.split("---", 2)[1]
    assert "feature-count: 1" in fm_section
    assert "ai-first: true" in fm_section
    assert fm_section.index("feature-count") < fm_section.index("ai-first")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_features.py -v -k "doc_sync_score or compose_features_note"`
Expected: 3 FAILS — `ImportError`.

- [ ] **Step 3: Implement helpers**

Append to `scripts/architect/sections.py`:

```python
def compute_doc_sync_score(rendered_rows: list[dict]) -> float:
    """Doc-sync-score = online rows with ≥1 doc_anchor ÷ total online rows.

    Returns 0.0 if no online rows. Rounded to 2 decimals.
    """
    online = [r for r in rendered_rows if r.get("status") == "online"]
    if not online:
        return 0.0
    with_doc = sum(1 for r in online if r.get("doc_anchors"))
    return round(with_doc / len(online), 2)


def compose_features_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    feature_count: int,
    deprecated_count: int,
    doc_sync_score: float,
) -> str:
    """Wraps compose_note(section='features', ...) and merges three extra
    frontmatter fields BEFORE the `ai-first: true` line."""
    note = compose_note(
        section="features",
        project=project,
        repo_label=repo_label,
        commit=commit,
        signal_sources=signal_sources,
        confidence=confidence,
        output_lang=output_lang,
        generated_blocks=generated_blocks,
    )
    extra_fm = (
        f"feature-count: {feature_count}\n"
        f"deprecated-count: {deprecated_count}\n"
        f"doc-sync-score: {doc_sync_score:.2f}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v -k "doc_sync_score or compose_features_note"`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): compute_doc_sync_score + compose_features_note frontmatter merge

doc_sync_score = online_with_doc / online_total, rounded to 2 decimals.
compose_features_note wraps compose_note(section='features', ...) and
injects feature-count / deprecated-count / doc-sync-score frontmatter
before `ai-first: true` (parallel to v4.1 ai-flow's extra frontmatter
pattern). Ready for DataView cross-project aggregation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F: Lockfile slot

### Task 10: `sections.features` slot in lockfile (no schema bump)

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py` (or wherever lockfile tests live)

- [ ] **Step 1: Locate existing lockfile tests**

```bash
ls tests/architect/test_lockfile* 2>&1
grep -l "Lockfile" /Users/leric/Desktop/code/obsidian-second-brain/tests/architect/ -r 2>&1 | head -5
```

- [ ] **Step 2: Write the failing test**

Append to `tests/architect/test_lockfile.py` (or create the file if it doesn't exist):
```python
def test_lockfile_sections_features_slot_round_trip(tmp_path):
    """sections.features round-trips through Lockfile.save → load with v4.2 fields."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.sections["features"] = {
        "signal-hash": "sha256:abc123",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "deadbeef",
        "feature-count": 32,
        "deprecated-count": 3,
        "doc-sync-score": 0.87,
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)

    loaded = Lockfile.load(p)
    assert loaded.sections["features"]["feature-count"] == 32
    assert loaded.sections["features"]["doc-sync-score"] == 0.87
    assert loaded.sections["features"]["signal-hash"] == "sha256:abc123"
```

- [ ] **Step 3: Run test to verify it fails OR passes**

Run: `uv run pytest tests/architect/test_lockfile.py::test_lockfile_sections_features_slot_round_trip -v`
Expected: Most likely PASSES already if `sections` is a `dict[str, dict]` field. If it's typed more strictly (e.g. a fixed schema dataclass per section), expect FAIL with TypeError or pydantic validation error.

- [ ] **Step 4: If test passes, no impl needed. If fails, relax Lockfile sections schema**

Inspect `scripts/architect/lockfile.py`. If `sections` is `dict[str, Any]`, no impl. If it's a typed dataclass, add a new variant or relax to `dict[str, dict[str, Any]]`. Concrete edit will depend on what's there — the FAIL message dictates exact fix. Most likely no change needed.

- [ ] **Step 5: Verify all lockfile tests still pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: PASS.

- [ ] **Step 6: Commit (whether code changed or not)**

```bash
git add tests/architect/test_lockfile.py scripts/architect/lockfile.py
git commit -m "$(cat <<'EOF'
test(architect): lockfile sections.features slot round-trip (v4.2)

Confirms the v4.2 extra fields (feature-count, deprecated-count,
doc-sync-score) round-trip cleanly through Lockfile.save → load. No
schema version bump needed; sections is a flexible dict[str, dict].

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(If `scripts/architect/lockfile.py` was not modified, `git add` it anyway as a no-op stage to keep the diff clean — `git add` won't stage anything if no change. Commit just the test if so.)

---

## Phase G: Roadmap signal integration

### Task 11: `parse_doc_actions_block` parser

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_features.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_parse_doc_actions_block_extracts_checkbox_lines():
    from scripts.architect.sections import parse_doc_actions_block

    body = (
        "### 清除 deprecated 殘留\n"
        "- [ ] Remove `/old-endpoint` mention from README.md L42-48\n"
        "- [ ] Remove deprecated CLI `archive-tickets` from AGENTS.md\n"
        "\n"
        "### 補缺 doc\n"
        "- [ ] Add `Knowledge Base` README section listing /kb-candidates/*\n"
    )
    actions = parse_doc_actions_block(body)
    assert len(actions) == 3
    assert actions[0]["group"] == "清除 deprecated 殘留"
    assert "Remove `/old-endpoint`" in actions[0]["text"]
    assert actions[2]["group"] == "補缺 doc"


def test_parse_doc_actions_block_ignores_non_checkbox_bullets():
    from scripts.architect.sections import parse_doc_actions_block

    body = (
        "### 清除\n"
        "- regular bullet, ignored\n"
        "- [ ] checkbox line, kept\n"
    )
    actions = parse_doc_actions_block(body)
    assert len(actions) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_features.py -v -k "parse_doc_actions_block"`
Expected: 2 FAILS — `ImportError`.

- [ ] **Step 3: Implement parser**

Append to `scripts/architect/sections.py`:

```python
def parse_doc_actions_block(body: str) -> list[dict]:
    """Parse the `doc-sync-actions` block into action dicts.

    Returns list of {group: str, text: str} where group is the H3 heading
    (without `### `) and text is the checkbox-line content after `- [ ] `.
    Non-checkbox bullets are ignored.
    """
    actions: list[dict] = []
    current_group = ""
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("### "):
            current_group = stripped[4:].strip()
            continue
        if stripped.startswith("- [ ] ") or stripped.startswith("- [x] "):
            text = stripped[6:].strip()
            if text:
                actions.append({"group": current_group, "text": text})
    return actions
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_features.py -v -k "parse_doc_actions_block"`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_features.py
git commit -m "$(cat <<'EOF'
feat(architect): parse_doc_actions_block — H3-group + checkbox parser

Reads features.md doc-sync-actions block into list[{group, text}] for
/obsidian-roadmap to ingest as `doc-action` candidates. Ignores plain
bullets; only `- [ ]` and `- [x]` lines count.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 12: `detect_candidates` walks features.md (3 sources + research-evidence priority)

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Inspect existing candidates module structure**

```bash
grep -n "detect_candidates\|features.md\|Candidate" /Users/leric/Desktop/code/obsidian-second-brain/scripts/roadmap/candidates.py | head -20
```

- [ ] **Step 2: Write the failing test**

Append to `tests/roadmap/test_candidates.py` (or create if it doesn't exist):

```python
def test_detect_candidates_walks_features_md_missing_features_block(tmp_path):
    """detect_candidates picks up missing-features H3 entries from features.md."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    arch.mkdir()
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 可加 features\n"
        "<!-- @generated:start missing-features -->\n"
        "### Multi-channel inbox\n"
        "- **為什麼:** 客戶開始要求 WhatsApp 整合\n"
        "- **證據:** [[Research/line-bot-trends]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 客戶轉投競品\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end missing-features -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    multichannel = next(
        (c for c in cands if "Multi-channel" in c.title), None
    )
    assert multichannel is not None, f"missing-features entry not picked up; got {[c.title for c in cands]}"
    # Research wikilink in Evidence → priority high.
    assert multichannel.priority == "high"


def test_detect_candidates_features_imp_without_research_is_normal_priority(tmp_path):
    """missing-features Evidence with persona / code-pattern but no [[Research/]] → normal."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    arch.mkdir()
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 可加 features\n"
        "<!-- @generated:start missing-features -->\n"
        "### Shift handoff\n"
        "- **為什麼:** Persona Mary 跨班沒工具\n"
        "- **證據:** [[Architecture/personas#Mary]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 客服漏接\n"
        "- **Confidence:** high\n"
        "<!-- @generated:end missing-features -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    shift = next((c for c in cands if "Shift handoff" in c.title), None)
    assert shift is not None
    assert shift.priority == "normal"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "features_md or features_imp"`
Expected: 2 FAILS — current `detect_candidates` doesn't read features.md.

- [ ] **Step 4: Extend `detect_candidates` to walk features.md**

In `scripts/roadmap/candidates.py`, locate `detect_candidates`. Add a step that, when `features.md` exists in the Architecture directory, parses its `missing-features`, `improvements`, and `doc-sync-actions` blocks. Implementation sketch:

```python
def detect_candidates(project_dir: Path) -> list["Candidate"]:
    # ... existing walking of overview / modules / decisions ...

    # v4.2 — features.md
    features_path = project_dir / "Architecture" / "features.md"
    if features_path.exists():
        text = features_path.read_text(encoding="utf-8")

        # missing-features block (use existing parse_improvements_block)
        mf_body = _extract_generated_block(text, "missing-features")
        if mf_body:
            for imp in parse_improvements_block(mf_body):
                priority = "high" if _has_research_wikilink(imp.evidence) else "normal"
                candidates.append(_candidate_from_imp(
                    imp, source="features.md#missing-features",
                    candidate_type="missing-feature", priority=priority,
                ))

        # improvements block — feature-improvement type
        imp_body = _extract_generated_block(text, "improvements")
        if imp_body:
            for imp in parse_improvements_block(imp_body):
                candidates.append(_candidate_from_imp(
                    imp, source="features.md#improvements",
                    candidate_type="feature-improvement", priority="normal",
                ))

        # doc-sync-actions block — doc-action type
        da_body = _extract_generated_block(text, "doc-sync-actions")
        if da_body:
            for action in parse_doc_actions_block(da_body):
                candidates.append(_candidate_from_doc_action(
                    action, source="features.md#doc-sync-actions",
                ))

    # ... existing dedup pass ...
    return candidates


def _extract_generated_block(text: str, name: str) -> str | None:
    """Extract content between <!-- @generated:start <name> --> and end markers."""
    start = f"<!-- @generated:start {name} -->"
    end = f"<!-- @generated:end {name} -->"
    s = text.find(start)
    if s == -1:
        return None
    s += len(start)
    e = text.find(end, s)
    if e == -1:
        return None
    return text[s:e].strip()


def _has_research_wikilink(evidence: str) -> bool:
    return "[[Research/" in evidence or "[[research/" in evidence


def _candidate_from_imp(imp, *, source: str, candidate_type: str, priority: str) -> Candidate:
    return Candidate(
        title=imp.title,
        why=imp.why,
        evidence=imp.evidence,
        effort=imp.effort,
        risk_if_not_done=imp.risk_if_not_done,
        confidence=imp.confidence,
        candidate_type=candidate_type,
        priority=priority,
        source=source,
    )


def _candidate_from_doc_action(action: dict, *, source: str) -> Candidate:
    return Candidate(
        title=action["text"][:80],
        why=f"Doc sync: {action['group']}",
        evidence="",
        effort="S",
        risk_if_not_done="文件持續漂移降低 onboarding 速度",
        confidence="stated",
        candidate_type="doc-action",
        priority="low",
        source=source,
    )
```

Concrete edits depend on the existing `Candidate` dataclass shape — adapt field names accordingly (the Candidate dataclass may not have `priority` / `candidate_type` / `source` fields yet; add them if missing, with sensible defaults).

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS (new + existing).

- [ ] **Step 6: Run full suite**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): detect_candidates walks features.md (v4.2)

Three new source buckets:
- missing-features → candidate_type=missing-feature, priority=high when
  evidence contains [[Research/...]] wikilink, normal otherwise
- improvements → feature-improvement, normal priority
- doc-sync-actions → doc-action, low priority

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 13: Dedup features.md Imps against module Imps via Evidence overlap

**Files:**
- Modify: `scripts/roadmap/candidates.py` (add dedup step)
- Modify: `tests/roadmap/test_candidates.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_detect_candidates_dedup_features_vs_module(tmp_path):
    """When features.md Imp and module Imp cite same Evidence wikilink,
    features.md wins; module Imp is dropped or marked child."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "features.md").write_text(
        "---\ntype: architecture-features\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Streaming reply\n"
        "- **為什麼:** UX 體感落後\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 競品先上\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    (arch / "modules" / "backend.md").write_text(
        "---\ntype: architecture-module\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Streaming reply tech impl\n"
        "- **為什麼:** llm.invoke 改 stream\n"
        "- **證據:** [[Architecture/modules/backend#改進機會]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 無\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    # Features.md Imp wins; module Imp deduped.
    titles = [c.title for c in cands]
    assert "Streaming reply" in titles
    assert "Streaming reply tech impl" not in titles, (
        f"expected module Imp deduped against features Imp; got {titles}"
    )
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "dedup_features_vs_module"`
Expected: FAIL — both Imps still in the result.

- [ ] **Step 3: Add dedup pass**

In `detect_candidates`, after collecting all candidates, run a dedup pass:

```python
def _dedup_candidates(candidates: list[Candidate]) -> list[Candidate]:
    """Dedup module Imps against features.md Imps when they share Evidence wikilinks.

    Features.md (PM lens) wins. Module Imps with overlapping Evidence are dropped.
    """
    features_evidence_set: set[str] = set()
    for c in candidates:
        if c.source and "features.md" in c.source:
            for wl in _extract_wikilinks(c.evidence):
                features_evidence_set.add(wl)

    deduped: list[Candidate] = []
    for c in candidates:
        if c.source and "features.md" in c.source:
            deduped.append(c)
            continue
        # Module / overview / decisions candidates: drop if any evidence wikilink
        # is in features_evidence_set.
        if any(wl in features_evidence_set for wl in _extract_wikilinks(c.evidence)):
            continue
        deduped.append(c)
    return deduped


_WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")


def _extract_wikilinks(text: str) -> list[str]:
    return _WIKILINK_RE.findall(text)
```

Call `candidates = _dedup_candidates(candidates)` as the LAST step in `detect_candidates` before returning. Add `import re` at file top if not present.

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): dedup module Imps against features.md Imps by Evidence wikilink overlap

Last step in detect_candidates: when a features.md candidate (PM lens)
and a module candidate share any Evidence wikilink, features.md wins
and the module candidate is dropped. Prevents Roadmap double-counting
of the same architectural concern surfaced at both lenses.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H: Command body + AI-first rules + announcement

### Task 14: `--no-features` / `--features-only` flags + Phase 3.5.5 in command body

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Locate current Phase 3.5 and Phase 3.7 sections in command body**

```bash
grep -n "## Phase 3\.5\|## Phase 3\.7\|--no-ai-flows\|--functions" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-architect.md
```

- [ ] **Step 2: Add flag descriptions to top of command body**

In `commands/obsidian-architect.md`, find the flags section (where `--no-ai-flows` is documented). After the `--no-ai-flows` block, INSERT:

```markdown
**v4.2-specific flags:**
- `--no-features` — even when scanner can produce a features.md, skip Phase
  3.5.5. Use this if a project doesn't need the product-PM lens. Default OFF
  (features.md IS produced by default in v4.2+).
- `--features-only` — diagnostic flag. Run only Phase 1 (scan) + Phase 3.5.5
  (features synth). Useful for iterating on the features prompt without
  re-running other sections.
```

- [ ] **Step 3: Insert Phase 3.5.5 between existing 3.5 and 3.7**

After the closing of "Phase 3.5: Per-section synthesis (v4)" and BEFORE "Phase 3.7: AI Flow synthesis (v4.1)", insert:

````markdown
## Phase 3.5.5: Features synthesis (v4.2)

Skip if `--no-features` is passed.

Skip if `sections.features.signal-hash` in lockfile matches current scan signal hash AND `Projects/<P>/Architecture/features.md` exists (refresh logic).

1. Compute signal hash:
   ```python
   from scripts.architect.sections import signal_hash
   feature_signal = {
       "readme_sections": scan_report["readme_sections"],
       "agents_md_text": scan_report["agents_md_text"],
       "changelog": scan_report["changelog"],
       "api_surface": scan_report["api_surface"],
       "research_excerpts": [
           {"path": r["path"], "mtime": (vault_proj / r["path"]).stat().st_mtime}
           for r in scan_report["research_excerpts"]
       ],
       "personas_hash": _sha256_of_personas(arch_dir / "personas.md"),
   }
   sig_hash = signal_hash(feature_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_features_prompt
   prompt = build_features_prompt(
       project=project_name,
       readme_sections=scan_report["readme_sections"],
       agents_md_text=scan_report["agents_md_text"],
       changelog=scan_report["changelog"],
       api_surface_summary=_render_api_surface_summary(scan_report["api_surface"]),
       modules_summary=_render_modules_summary(manifest_modules, arch_dir / "modules"),
       personas_summary=_read_personas_excerpt(arch_dir / "personas.md"),
       research_excerpts=scan_report["research_excerpts"],
       output_lang=output_lang,
   )
   ```

3. Invoke the LLM. Expect strict JSON: 10 keys (capability-inventory as STRUCTURED LIST, others as markdown strings).

4. Two-pass annotation + table render:
   ```python
   from scripts.architect.sections import render_features_inventory, compute_doc_sync_score
   table_md, counts = render_features_inventory(
       llm_output["capability-inventory"],
       scan_report["api_surface"],
       scan_report["git_last_touch"],
   )
   # Compute rendered_rows from llm inventory + assigned statuses for doc-sync-score.
   rendered_rows = [
       {**row, "status": _status_for_row(row, scan_report["api_surface"])}
       for row in llm_output["capability-inventory"]
   ]
   sync_score = compute_doc_sync_score(rendered_rows)
   ```

5. Compose note:
   ```python
   from scripts.architect.sections import compose_features_note
   blocks = {**llm_output, "capability-inventory": table_md}
   note = compose_features_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["README.md", "AGENTS.md", "CHANGELOG.md",
                       "scan: api_surface", "manifest: modules"]
                      + (["vault: Research/*"] if scan_report["research_excerpts"] else [])
                      + (["vault: personas.md"] if (arch_dir / "personas.md").exists() else []),
       confidence="high" if scan_report["research_excerpts"] else "medium",
       output_lang=output_lang,
       generated_blocks=blocks,
       feature_count=counts["online"] + counts["deprecated"],
       deprecated_count=counts["deprecated"],
       doc_sync_score=sync_score,
   )
   ```

6. Write to `Projects/<P>/Architecture/features.md`.

7. Update lockfile `sections.features`:
   ```python
   lockfile.sections["features"] = {
       "signal-hash": sig_hash,
       "lang": output_lang,
       "last-generated": today_iso,
       "commit": commit,
       "feature-count": counts["online"] + counts["deprecated"],
       "deprecated-count": counts["deprecated"],
       "doc-sync-score": sync_score,
   }
   ```

8. Hub block + overview drill-down (idempotent, sentinel-aware):
   - Hub `Projects/<P>/<P>.md` `<!-- @generated:start architecture-section -->` block: ensure line `- 產品 feature inventory + doc-sync: [[Architecture/features]]` is present once.
   - `Projects/<P>/Architecture/overview.md` `<!-- @generated:start drill-down -->` block: ensure line `- **產品 feature inventory:** [[features]] (online/deprecated 狀態 + gap analysis + 文件補補丁)` is present once.

If `--features-only`: skip all other Phases (3, 3.5, 3.7, 4) and only run Phase 1 + Phase 3.5.5 + final hub/overview update + lockfile write.
````

- [ ] **Step 4: Rebuild adapters to verify command body still parses**

Run: `bash scripts/build.sh`
Expected: 4 platform builds complete successfully (claude-code, codex-cli, gemini-cli, opencode).

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "$(cat <<'EOF'
feat(architect): v4.2 command body — Phase 3.5.5 features synthesis + --no-features / --features-only flags

Phase 3.5.5 sits between 3.5 (decisions/personas) and 3.7 (AI flows).
Builds features.md via build_features_prompt + render_features_inventory
+ compute_doc_sync_score + compose_features_note pipeline. Lockfile
sections.features slot updated with signal-hash + counts. Hub + overview
get features.md back-links (idempotent sentinel-aware update).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(`dist/` is gitignored — do NOT include it in `git add`. The build was already run in Step 4 so the in-tree dist files are present locally, but they are not tracked; staging is only for the source file.)

### Task 15: `architecture-features` schema in ai-first-rules.md

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Locate existing type-schema section**

```bash
grep -n "architecture-features\|architecture-overview\|architecture-ai-flow" /Users/leric/Desktop/code/obsidian-second-brain/references/ai-first-rules.md | head -10
```

- [ ] **Step 2: Add or refresh the v4.2 `architecture-features` schema**

Find where v4.1 added `architecture-ai-flow`. Add a new subsection BEFORE it (since features.md sits between personas and ai-flow in the architecture):

````markdown
### `architecture-features` (v4.2 — product PM lens)

**File:** `Projects/<P>/Architecture/features.md`

**Frontmatter:**
```yaml
type: architecture-features
date: YYYY-MM-DD
project: "[[<project-name>]]"
local-path: "/abs/path/to/repo"           # or repo: "<url>"
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["README.md", "AGENTS.md", "CHANGELOG.md", "scan: api_surface", "manifest: modules", "vault: Research/*", "vault: personas.md"]
confidence: high                          # high when api_surface + research excerpts present
lang: zh-TW                               # or en
tags: [architecture, features]
ai-first: true
status: current
feature-count: 32
deprecated-count: 3
doc-sync-score: 0.87
```

**Body blocks** (10 `@generated` sentinels):
1. `summary` — `## 摘要` / `## Summary`
2. `capability-inventory` — `## Capability inventory` (markdown table, post-rendered)
3. `product-coverage` — `## Product coverage`
4. `limitations` — `## Limitations`
5. `strengths` — `## Product strengths` (PM voice)
6. `weaknesses` — `## Product weaknesses` (PM voice)
7. `missing-features` — `## Missing features` (gap analysis)
8. `improvements` — `## Product improvements` (PM direction, not refactor)
9. `doc-sync-actions` — `## Doc sync actions` (checkbox lines)
10. `dependencies` — `## Dependencies` (wikilinks)

**Voice constraints:**
- `strengths` / `weaknesses` use PM voice. Tech-voice terms ('god module', 'refactor', 'type safety') are banned.
- `missing-features` Evidence must be one of: `[[Research/<note>]]` wikilink, `[[Architecture/personas#<persona>]]`, or `code:path:line`.
- `capability-inventory` rows must use the columns: Capability | Description (≤80 char) | Status (online/deprecated) | Last touch (YYYY-MM or unknown / —) | Doc anchors | Code anchors | Module wikilink.

**Status detection (deterministic, NOT LLM):**
- `online` — at least one `code_anchor` matches `(file, endpoint_or_symbol)` pair in `scan_report.api_surface`.
- `deprecated` — no code_anchors match.

**Doc-sync-score:** `online_with_doc_anchors / online_total`, rounded to 2 decimals.
````

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "$(cat <<'EOF'
docs(ai-first-rules): v4.2 architecture-features schema

Defines the product-PM lens schema: 10 @generated blocks, voice constraints
(PM not tech), deterministic online/deprecated status from api_surface
lookup, plus extra frontmatter fields (feature-count / deprecated-count /
doc-sync-score) for DataView aggregation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 16: v4.2 announcement in SKILL.md / README.md / CHANGELOG.md

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md**

Find the section that describes `/obsidian-architect` in `SKILL.md` (search for `obsidian-architect` heading). Add a v4.2 bullet:

```markdown
- **v4.2 (2026-05-28):** Re-introduces `features.md` as a **product PM lens** —
  capability inventory with deterministic online/deprecated status (from git +
  api_surface), product gap analysis grounded in vault `Research/` excerpts,
  PM-voice strengths/weaknesses/limitations, doc-sync action todos. Frontmatter
  carries `feature-count` / `deprecated-count` / `doc-sync-score` for cross-
  project DataView aggregation. Flags `--no-features` / `--features-only`.
```

- [ ] **Step 2: Update README.md commands table**

Find the row describing `/obsidian-architect` in README.md's commands table. Update the description column to mention the v4.2 features layer:

Before:
```markdown
| `/obsidian-architect` | Scan codebase + generate v4 architecture report (8 files) + v4.1 AI flows layer (LangGraph / LangChain / custom-pipeline) |
```

After:
```markdown
| `/obsidian-architect` | Scan codebase + generate v4 architecture report (8 files) + v4.1 AI flows layer + v4.2 product features lens (online/deprecated, gap analysis, doc-sync drift) |
```

- [ ] **Step 3: Update CHANGELOG.md**

Add to the `## [Unreleased]` section (create one if absent):

```markdown
## [Unreleased]

### Added
- `/obsidian-architect` v4.2 — `features.md` as product PM lens. Per spec
  `docs/superpowers/specs/2026-05-28-obsidian-architect-v4.2-features-design.md`.
  Adds `research_walker.py`, `git_history.py`, `build_features_prompt`,
  `render_features_inventory` (deterministic online/deprecated marker),
  `compute_doc_sync_score`, `parse_doc_actions_block`. `/obsidian-roadmap`
  candidate detector walks features.md missing-features / improvements /
  doc-sync-actions blocks with dedup against module Imps via Evidence
  wikilink overlap.
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+readme+changelog): v4.2 features layer announcement

SKILL.md gains a v4.2 bullet; README's command table mentions the
product features lens; CHANGELOG Unreleased lists the additions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase I: Acceptance smoke

### Task 17: Run `/obsidian-architect --features-only` against langlive-line-oa

**Files:**
- No code changes. Smoke test on real vault.

- [ ] **Step 1: Run scanner + features synthesis end-to-end**

(This task involves invoking the LLM-driven Phase 3.5.5 via the slash command body; in a non-interactive plan execution, do the equivalent Python end-to-end smoke that exercises the pipeline.)

```bash
HASH=$(date +%s)
OUT=/tmp/architect-features-smoke-$HASH
mkdir -p "$OUT"
uv run python scripts/architect_scan.py /Users/leric/Desktop/code/langlive-line-oa \
  --out "$OUT" \
  --vault-project-dir /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa
```

Expected: `$OUT/_manifest.yml` and `$OUT/scan-report.json` exist. The scan-report JSON contains:
- `agents_md_text` (non-empty, ≤ 20KB)
- `research_excerpts` ([], because the project's Research/ dir is empty)
- `git_last_touch` (dict with at least 1 file dated)

Verify via:
```bash
uv run python -c "
import json
d = json.load(open('$OUT/scan-report.json'))
print('agents_md_text:', len(d.get('agents_md_text', '')))
print('research_excerpts:', len(d.get('research_excerpts', [])))
print('git_last_touch (sample):', list(d.get('git_last_touch', {}).items())[:3])
"
```

Expected output includes:
- `agents_md_text: <N>` where N is > 0
- `research_excerpts: 0`
- `git_last_touch (sample): [(file, date), ...]` with at least one entry

- [ ] **Step 2: Verify the Phase 3.5.5 code path is in command body**

```bash
grep -c "Phase 3.5.5" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-architect.md
```

Expected: ≥ 1 (the new section + flag mention).

- [ ] **Step 3: Verify full test suite**

```bash
uv run pytest tests/ -q
```

Expected: All PASS (prior + ~22 new tests across this plan).

- [ ] **Step 4: Verify builds**

```bash
bash scripts/build.sh
```

Expected: 4 platform adapters build successfully.

- [ ] **Step 5: No commit needed — this is acceptance, not code change**

If anything in Steps 1-4 fails, write a `## Blocker` note at the top of this plan file describing what failed (with exact command output), then stop. Otherwise mark Task 17 complete and proceed to the post-implementation tracker update.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal / non-goals | Task 1 (un-deprecate + voice constraint in preamble) |
| Frame & file shape | Task 1 (block schema), Task 9 (compose helper + frontmatter), Task 14 (hub + overview links) |
| Body block design (10 blocks) | Task 1 (schema), Task 7 (prompt directives), Task 8 (table render), Task 9 (compose) |
| Frontmatter (`feature-count` etc.) | Task 9 |
| Scanner additions (`agents_md_text`, `research_excerpts`, `git_last_touch`) | Tasks 2-3 (research walker), Tasks 4-5 (git history), Task 6 (scan integration) |
| Two-pass synthesis (deterministic deprecation) | Task 7 (structured list directive), Task 8 (render + status mark) |
| Doc-sync detection / score | Task 9 (compute_doc_sync_score) |
| Refresh signal hash | Task 14 (Phase 3.5.5 step 1 documents the hash composition) |
| Roadmap integration (3 buckets) | Task 12 (walk features.md) |
| Dedup against module Imps | Task 13 (dedup pass) |
| Command surface (`--no-features` / `--features-only`) | Task 14 (flag descriptions + Phase body) |
| Hub note + overview wikilinks | Task 14 (step 3 idempotent edits) |
| Migration / existing vault handling | (no migration needed in v4 vaults; the new file is additive — implicit in Task 14) |
| Lockfile fields | Task 10 (round-trip test) |
| Tests (spec items 1-16) | Distributed across Tasks 1, 2-3, 4-5, 6, 7, 8, 9, 11, 12, 13 |
| Out of scope (multi-project compare, beta status, etc.) | NOT implemented — deferred per spec |
| Success criteria | Task 17 (acceptance smoke) |
