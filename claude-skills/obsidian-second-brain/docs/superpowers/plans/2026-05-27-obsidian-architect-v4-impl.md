# obsidian-architect v4 (Consolidated Report) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `/obsidian-architect` 從 v3 的「14 個 fragmented 檔 + MOC overview」收斂為「8 個檔 + 自包含 top-down overview 報告」,讓讀者打開 overview.md 一次看懂整個 project。

**Architecture:** v4 不重做 module / personas / decisions schema (v3.1 tight bullets 仍正確);只重寫 overview 為 8 段 top-down report (Purpose → System diagram → Stack → Capabilities → Flows → Module map → Cross-cutting improvements → Drill-down)。Migration 自動刪除 6 個過時檔 (future / roadmap / jobs / api-surface / features / flows),把 future.md 的 known-limitations 段遷入 decisions.md,tar.gz 整 tree 備份。

**Tech Stack:** Python 3.10+, pytest, dataclass, 既有 `scripts/architect/{sections,lockfile,migration,lang}.py`。

**Spec:** `docs/superpowers/specs/2026-05-27-obsidian-architect-v4-consolidated-report-design.md`

**Suggested branch:** `feat/architect-v4-consolidated`

---

## Task layout

16 個任務分 7 phase。Phase A-B 是 foundation;Phase C 是 overview 重寫的核心;D-E 收尾 decisions + roadmap signal;F-H 是 schema docs + command body + polish。

| Phase | 任務 | 範圍 |
|---|---|---|
| A. Foundation | 1-2 | Heading map + lockfile v4 schema |
| B. Migration helper | 3 | `plan_v3_to_v4_migration` + `apply` + known-limitations 遷移 |
| C. Overview rewrite | 4-7 | `_BLOCK_NAMES["overview"]` v4 schema + `compose_overview` rewrite + deprecation markers |
| D. Decisions enhancement | 8 | `decisions` 加 `known-limitations` block |
| E. Roadmap narrowing | 9 | `detect_candidates` 範圍收斂 |
| F. Schema docs | 10 | `ai-first-rules.md` 更新 |
| G. Command body | 11 | `commands/obsidian-architect.md` v4 rewrite + adapter build |
| H. Polish | 12-16 | --frame flag + CHANGELOG / SKILL / README / smoke |

---

## Phase A — Foundation

### Task 1: Heading map for v4 new headings

**Files:**
- Modify: `scripts/architect/lang.py`
- Modify: `tests/architect/test_lang.py`

- [ ] **Step 1: Write failing test for new headings**

Append to `tests/architect/test_lang.py`:

```python
def test_heading_map_includes_v4_report_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Purpose & audience": "## 這是什麼 / 為誰服務",
        "## System diagram": "## 系統架構圖",
        "## Capabilities": "## 核心能力",
        "## Flows": "## 核心使用流程",
        "## Module map": "## 模組地圖",
        "## Cross-cutting improvements": "## 跨模組改進機會",
        "## Drill-down entries": "## 想深讀的入口",
        "## Known limitations": "## 已知限制",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_v4_report_keys -v`
Expected: FAIL — missing heading keys.

- [ ] **Step 3: Add entries to HEADING_MAP in `scripts/architect/lang.py`**

In the HEADING_MAP dict, add inside (before the closing `}`):

```python
    # v4 consolidated-report frame (overview top-down sections)
    "## Purpose & audience": {"en": "## Purpose & audience", "zh-TW": "## 這是什麼 / 為誰服務"},
    "## System diagram": {"en": "## System diagram", "zh-TW": "## 系統架構圖"},
    "## Capabilities": {"en": "## Capabilities", "zh-TW": "## 核心能力"},
    "## Flows": {"en": "## Flows", "zh-TW": "## 核心使用流程"},
    "## Module map": {"en": "## Module map", "zh-TW": "## 模組地圖"},
    "## Cross-cutting improvements": {"en": "## Cross-cutting improvements", "zh-TW": "## 跨模組改進機會"},
    "## Drill-down entries": {"en": "## Drill-down entries", "zh-TW": "## 想深讀的入口"},
    # v4 decisions.md addition (absorb from future.md)
    "## Known limitations": {"en": "## Known limitations", "zh-TW": "## 已知限制"},
```

Note: `## Known limitations` may already exist (from the v3 future schema). If `grep -n "## Known limitations" scripts/architect/lang.py` returns a hit, leave that line and only add the 7 new keys.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_v4_report_keys -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lang.py tests/architect/test_lang.py
git commit -m "feat(architect): v4 heading entries for report-style overview + known limitations"
```

---

### Task 2: Lockfile schema bump v3 → v4

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_lockfile.py`:

```python
def test_v4_schema_with_report_frame(tmp_path: Path):
    """v4 lockfile defaults to frame='report-v4'."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile, CURRENT_SCHEMA
    assert CURRENT_SCHEMA == 4
    lock = Lockfile(
        version=4,
        scanner_version="0.4.0",
        fields={},
        note_blocks={},
        sections={"overview": {"signal-hash": "sha256:abc", "lang": "zh-TW"}},
        functions={},
        frame="report-v4",
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.frame == "report-v4"


def test_v3_lockfile_migrates_to_v4(tmp_path: Path):
    """Loading a v3 lockfile yields version=4 with frame preserved (judgment-v3)."""
    import json
    from scripts.architect.lockfile import load_lockfile, CURRENT_SCHEMA
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 3,
        "scanner_version": "0.3.0",
        "fields": {},
        "note_blocks": {},
        "sections": {"features": {"signal-hash": "x", "lang": "zh-TW"}},
        "functions": {},
        "frame": "judgment-v3",
    }))
    loaded = load_lockfile(target)
    assert loaded.version == CURRENT_SCHEMA == 4
    assert loaded.frame == "judgment-v3"  # preserved until v4 migration runs
    assert loaded.sections["features"]["signal-hash"] == "x"


def test_v2_lockfile_still_migrates_through_to_v4(tmp_path: Path):
    """A pre-v3 vault should still load (frame defaults to description-v2)."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 2,
        "scanner_version": "0.2.0",
        "fields": {},
        "note_blocks": {},
        "sections": {},
        "functions": {},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == 4
    assert loaded.frame == "description-v2"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py::test_v4_schema_with_report_frame tests/architect/test_lockfile.py::test_v3_lockfile_migrates_to_v4 tests/architect/test_lockfile.py::test_v2_lockfile_still_migrates_through_to_v4 -v`
Expected: FAIL — CURRENT_SCHEMA still 3.

- [ ] **Step 3: Update `scripts/architect/lockfile.py`**

Change the top of the file:

```python
CURRENT_SCHEMA = 4
```

Update `load_lockfile` to handle frame default per version:

```python
def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    incoming_version = data.get("version", 1)
    # Frame default based on which version produced the file.
    # Lets the v3→v4 migration step (later) detect and rewrite frame after upgrading content.
    if "frame" in data:
        frame = data["frame"]
    elif incoming_version >= 4:
        frame = "report-v4"
    elif incoming_version == 3:
        frame = "judgment-v3"
    else:
        frame = "description-v2"
    return Lockfile(
        version=CURRENT_SCHEMA,
        scanner_version=data.get("scanner_version", "0.0.0"),
        fields=data.get("fields", {}),
        note_blocks=data.get("note_blocks", {}),
        sections=data.get("sections", {}),
        functions=data.get("functions", {}),
        frame=frame,
    )
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: PASS (all old + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "feat(architect): bump lockfile schema to v4 with report frame default"
```

---

## Phase B — Migration helper v3 → v4

### Task 3: v3 → v4 migration (delete 6 obsolete files + carry known-limitations)

**Files:**
- Modify: `scripts/architect/migration.py`
- Modify: `tests/architect/test_migration.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_migration.py`:

```python
def _setup_v3_architecture(arch_root: Path):
    """Create a synthetic v3 layout: 14 files including the 6 to-be-deleted."""
    (arch_root / "modules").mkdir(parents=True)
    (arch_root / "overview.md").write_text(
        "---\ntype: architecture-overview\nmoc-style: true\n---\n\n"
        "## For future Claude\nMOC\n"
    )
    (arch_root / "future.md").write_text(
        "---\ntype: architecture-future\n---\n\n"
        "## 給未來 Claude\nGap analysis.\n\n"
        "## 已知限制\n"
        "<!-- @generated:start known-limitations -->\n"
        "- backend/.env deprecated\n"
        "- plain-text password fallback\n"
        "<!-- @generated:end known-limitations -->\n\n"
        "## 落差分析\nthings.\n"
    )
    (arch_root / "decisions.md").write_text(
        "---\ntype: architecture-decisions\n---\n\n"
        "## 給未來 Claude\nDecisions index.\n\n"
        "## 技術棧理由\n"
        "<!-- @generated:start stack-rationale -->\n- React + FastAPI\n<!-- @generated:end stack-rationale -->\n"
    )
    for fname in ("roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md", "personas.md"):
        (arch_root / fname).write_text(f"---\ntype: architecture-{fname.replace('.md', '')}\n---\n\nbody\n")
    for slug in ("backend", "frontend"):
        (arch_root / "modules" / f"{slug}.md").write_text(
            f"---\ntype: architecture-module\n---\n\n## 模組職責\nx\n"
        )


def test_v3_to_v4_plan_lists_6_files_to_delete(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    expected_deletes = {"future.md", "roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md"}
    assert set(plan.files_to_delete) == expected_deletes


def test_v3_to_v4_plan_keeps_overview_modules_decisions_personas(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    kept = set(plan.files_to_keep)
    assert "overview.md" in kept
    assert "decisions.md" in kept
    assert "personas.md" in kept
    assert "modules/backend.md" in kept
    assert "modules/frontend.md" in kept


def test_v3_to_v4_plan_extracts_known_limitations_from_future(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    assert plan.known_limitations_to_migrate is not None
    assert "backend/.env deprecated" in plan.known_limitations_to_migrate
    assert "plain-text password fallback" in plan.known_limitations_to_migrate


def test_v3_to_v4_apply_deletes_obsolete_files(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=False)
    for fname in ("future.md", "roadmap.md", "jobs.md", "api-surface.md", "features.md", "flows.md"):
        assert not (arch / fname).exists(), f"{fname} should have been deleted"
    # Files to keep still present.
    assert (arch / "overview.md").exists()
    assert (arch / "decisions.md").exists()
    assert (arch / "personas.md").exists()
    assert (arch / "modules" / "backend.md").exists()


def test_v3_to_v4_apply_merges_known_limitations_into_decisions(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=False)
    decisions_text = (arch / "decisions.md").read_text(encoding="utf-8")
    # Known limitations block now present in decisions.md
    assert "@generated:start known-limitations" in decisions_text
    assert "backend/.env deprecated" in decisions_text


def test_v3_to_v4_dry_run_does_not_modify(tmp_path: Path):
    from scripts.architect.migration import plan_v3_to_v4_migration, apply_v3_to_v4_migration
    arch = tmp_path / "Architecture"
    _setup_v3_architecture(arch)
    before_future = (arch / "future.md").read_text()
    before_decisions = (arch / "decisions.md").read_text()
    plan = plan_v3_to_v4_migration(arch)
    apply_v3_to_v4_migration(arch, plan, dry_run=True)
    assert (arch / "future.md").exists()
    assert (arch / "future.md").read_text() == before_future
    assert (arch / "decisions.md").read_text() == before_decisions
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_migration.py -v -k "v3_to_v4"`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Add v3→v4 helpers to `scripts/architect/migration.py`**

Append to `scripts/architect/migration.py`:

```python


V4_FILES_TO_DELETE = (
    "future.md",
    "roadmap.md",
    "jobs.md",
    "api-surface.md",
    "features.md",
    "flows.md",
)


@dataclass
class V3ToV4Plan:
    files_to_delete: list[str] = field(default_factory=list)
    files_to_keep: list[str] = field(default_factory=list)
    known_limitations_to_migrate: str | None = None


_KNOWN_LIM_BLOCK_RE = re.compile(
    r"<!--\s*@generated:start\s+known-limitations\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@generated:end\s+known-limitations\s*-->",
    re.DOTALL,
)


def plan_v3_to_v4_migration(arch_dir: Path) -> V3ToV4Plan:
    """Inspect a v3 Architecture/ tree; return what would change for v4."""
    plan = V3ToV4Plan()
    if not arch_dir.is_dir():
        return plan
    for fname in V4_FILES_TO_DELETE:
        if (arch_dir / fname).is_file():
            plan.files_to_delete.append(fname)
    # Files to keep: top-level .md NOT in delete list, plus modules/*.md
    for f in sorted(arch_dir.glob("*.md")):
        if f.name in V4_FILES_TO_DELETE:
            continue
        plan.files_to_keep.append(f.name)
    for f in sorted((arch_dir / "modules").glob("*.md")) if (arch_dir / "modules").is_dir() else []:
        plan.files_to_keep.append(f"modules/{f.name}")
    # Extract known-limitations from future.md (if present).
    future = arch_dir / "future.md"
    if future.is_file():
        try:
            text = future.read_text(encoding="utf-8")
            m = _KNOWN_LIM_BLOCK_RE.search(text)
            if m:
                plan.known_limitations_to_migrate = m.group("body").strip()
        except UnicodeDecodeError:
            pass
    return plan


def apply_v3_to_v4_migration(arch_dir: Path, plan: V3ToV4Plan, dry_run: bool = False) -> None:
    """Carry out the v3 → v4 migration.

    1. Merge known-limitations into decisions.md (if present).
    2. Delete the 6 obsolete files.
    Caller should have already called backup_architecture_dir() for safety.
    """
    if dry_run:
        return
    # Step 1: Merge known-limitations into decisions.md.
    if plan.known_limitations_to_migrate:
        _merge_known_limitations_into_decisions(arch_dir, plan.known_limitations_to_migrate)
    # Step 2: Delete obsolete files.
    for fname in plan.files_to_delete:
        target = arch_dir / fname
        if target.is_file():
            target.unlink()


def _merge_known_limitations_into_decisions(arch_dir: Path, body: str) -> None:
    """Append a `## 已知限制 / Known limitations` sentinel block to decisions.md."""
    decisions = arch_dir / "decisions.md"
    if not decisions.is_file():
        return
    text = decisions.read_text(encoding="utf-8")
    # Idempotent: if the block already exists, skip.
    if "@generated:start known-limitations" in text:
        return
    # Detect language from existing decisions.md frontmatter.
    lang = "en"
    if "lang: zh-TW" in text:
        lang = "zh-TW"
    heading_str = "## 已知限制" if lang == "zh-TW" else "## Known limitations"
    # Insert before the "## Related" / "## 相關" heading if present, else append.
    related_marker = "## 相關" if lang == "zh-TW" else "## Related"
    insertion = (
        f"\n{heading_str}\n"
        f"<!-- @generated:start known-limitations -->\n"
        f"{body}\n"
        f"<!-- @generated:end known-limitations -->\n"
    )
    if related_marker in text:
        text = text.replace(related_marker, insertion + "\n" + related_marker, 1)
    else:
        text = text.rstrip() + "\n" + insertion + "\n"
    decisions.write_text(text, encoding="utf-8")
```

Make sure the top of `scripts/architect/migration.py` has both `field` from `dataclasses` and `re` imported (they should already be there).

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_migration.py -v`
Expected: PASS (all old + 6 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/migration.py tests/architect/test_migration.py
git commit -m "feat(architect): v3->v4 migration helper — delete 6 obsolete files + merge known-limitations"
```

---

## Phase C — Overview rewrite

### Task 4: `_BLOCK_NAMES["overview"]` v4 schema + deprecation markers

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test for v4 overview block layout**

Append to `tests/architect/test_sections.py`:

```python
def test_overview_v4_block_names_are_top_down_report():
    """v4 overview has 8 body sections matching the top-down report structure."""
    from scripts.architect.sections import _BLOCK_NAMES
    assert "overview" in _BLOCK_NAMES
    expected = (
        "purpose",
        "system-diagram",
        "stack-summary",
        "capabilities",
        "flows",
        "module-map",
        "cross-cutting-improvements",
        "drill-down",
    )
    assert _BLOCK_NAMES["overview"] == expected, \
        f"v4 overview should have these 8 blocks in order, got: {_BLOCK_NAMES['overview']}"


def test_deprecated_section_types_marked():
    """v4 marks 6 deprecated SECTION_TYPES entries (still callable for backward compat)."""
    from scripts.architect.sections import SECTION_TYPES, DEPRECATED_SECTIONS
    for s in ("api-surface", "features", "roadmap", "future", "jobs", "flows"):
        assert s in SECTION_TYPES, f"{s} still in SECTION_TYPES (kept for backward compat)"
        assert s in DEPRECATED_SECTIONS, f"{s} should be in DEPRECATED_SECTIONS"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py::test_overview_v4_block_names_are_top_down_report tests/architect/test_sections.py::test_deprecated_section_types_marked -v`
Expected: FAIL — overview block names mismatch + DEPRECATED_SECTIONS not defined.

- [ ] **Step 3: Update `scripts/architect/sections.py`**

Find the `_BLOCK_NAMES` dict. Update the `"overview"` key (add it if missing):

```python
_BLOCK_NAMES = {
    "api-surface": ("summary", "interface-overview", "env-overview"),  # DEPRECATED in v4
    "features": ("summary", "capability-scope", "strengths", "weaknesses", "improvements"),  # DEPRECATED
    "decisions": ("summary", "stack-rationale", "detected-adrs", "pattern-decisions",
                  "commit-message-decisions", "promote-to-adr", "known-limitations"),
    "roadmap": ("summary", "near-term", "trajectory", "todo-clusters", "signals-reviewed"),  # DEPRECATED
    "future": ("summary", "known-limitations", "improvements"),  # DEPRECATED
    "module": ("scope", "strengths", "weaknesses", "improvements", "dependencies"),
    # v4 overview — 8 top-down report sections.
    "overview": (
        "purpose",
        "system-diagram",
        "stack-summary",
        "capabilities",
        "flows",
        "module-map",
        "cross-cutting-improvements",
        "drill-down",
    ),
    "personas": ("summary", "personas-list"),
    "jobs": ("summary", "jobs-list"),  # DEPRECATED
    "flows": ("summary", "flows-list"),  # DEPRECATED
}

# v4 — these sections are still callable for backward compat but no longer
# emitted by the default `--frame=report` pipeline. The v3 vault migration
# deletes their vault files; the schema entries stay so old vaults still load.
DEPRECATED_SECTIONS = frozenset({
    "api-surface", "features", "roadmap", "future", "jobs", "flows",
})
```

Also update `_BLOCK_HEADINGS` to add v4 entries:

```python
_BLOCK_HEADINGS = {
    "summary": "## Summary",
    # ... existing entries ...
    # v4 overview report sections
    "purpose": "## Purpose & audience",
    "system-diagram": "## System diagram",
    "stack-summary": "## Stack",
    "capabilities": "## Capabilities",
    "flows": "## Flows",
    "module-map": "## Module map",
    "cross-cutting-improvements": "## Cross-cutting improvements",
    "drill-down": "## Drill-down entries",
}
```

(Keep existing entries — only add the v4 ones if they're not already present from earlier tasks.)

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py::test_overview_v4_block_names_are_top_down_report tests/architect/test_sections.py::test_deprecated_section_types_marked -v`
Expected: PASS.

- [ ] **Step 5: Run full sections tests**

Run: `uv run pytest tests/architect/test_sections.py -q 2>&1 | tail -3`
Expected: all green (the `compose_overview` test from v3 may now fail since block names changed — if so, mark XFAIL or update; see Task 5 which handles compose_overview rewrite).

If a v3 compose_overview test fails (e.g. `test_compose_overview_en_emits_moc`), add `@pytest.mark.xfail(reason="v4 overview rewrite — see Task 5")` to it temporarily. We'll fix in Task 5.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): v4 overview block names + DEPRECATED_SECTIONS marker"
```

---

### Task 5: Rewrite `compose_overview` for v4 report schema

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing tests for v4 compose_overview**

Append to `tests/architect/test_sections.py`:

```python
def test_compose_overview_v4_emits_8_body_sections_zh_tw():
    """v4 overview writes a self-contained report, not a MOC."""
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="local: /tmp/x",
        commit="abc1234",
        stack={"primary-language": "Python", "frameworks": ["FastAPI"]},
        output_lang="zh-TW",
        modules=[
            {"slug": "backend", "display_name": "Backend"},
            {"slug": "frontend", "display_name": "Frontend"},
        ],
        entry_points=[],
        generated_blocks={
            "purpose": "Project does Y for Z personas.",
            "system-diagram": "```mermaid\ngraph TD\n  A-->B\n```",
            "capabilities": "### Auth\n- login\n### Webhook\n- LINE webhook",
            "flows": "### Flow 1: foo\n```mermaid\nsequenceDiagram\n```\n",
            "cross-cutting-improvements": "### Imp 1: ...",
        },
    )
    # frontmatter
    assert "type: architecture-overview" in note
    assert "report-style: true" in note
    assert "moc-style:" not in note  # v3 marker absent
    # 8 H2 sections (zh-TW)
    assert "## 給未來 Claude" in note
    assert "## 這是什麼 / 為誰服務" in note
    assert "## 系統架構圖" in note
    assert "## 技術棧" in note
    assert "## 核心能力" in note
    assert "## 核心使用流程" in note
    assert "## 模組地圖" in note
    assert "## 跨模組改進機會" in note
    assert "## 想深讀的入口" in note
    # Module-map section auto-renders deterministic wikilinks (independent of LLM blocks)
    assert "[[modules/backend]]" in note
    assert "[[modules/frontend]]" in note
    # Drill-down section lists deterministic wikilinks
    assert "[[decisions]]" in note
    assert "[[personas]]" in note


def test_compose_overview_v4_en():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={"primary-language": "Python"},
        output_lang="en",
        modules=[{"slug": "backend", "display_name": "Backend"}],
        entry_points=[],
        generated_blocks={"purpose": "Does X.", "system-diagram": "```mermaid\ngraph TD\n  A\n```"},
    )
    for h in [
        "## For future Claude",
        "## Purpose & audience",
        "## System diagram",
        "## Stack",
        "## Capabilities",
        "## Flows",
        "## Module map",
        "## Cross-cutting improvements",
        "## Drill-down entries",
    ]:
        assert h in note, f"missing heading {h!r}"


def test_compose_overview_v4_module_map_renders_each_module_one_line():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x",
        repo_label="local: /tmp/x",
        commit="a",
        stack={},
        output_lang="zh-TW",
        modules=[
            {"slug": "backend", "display_name": "Backend"},
            {"slug": "frontend", "display_name": "Frontend"},
            {"slug": "services", "display_name": "Services"},
        ],
        entry_points=[],
        generated_blocks={},
    )
    # Each module appears as a one-line bullet with its wikilink.
    assert "[[modules/backend]]" in note
    assert "[[modules/frontend]]" in note
    assert "[[modules/services]]" in note


def test_compose_overview_v4_drill_down_links_to_keep_files():
    """Drill-down section links to overview/decisions/personas/Roadmap (the v4 keep set)."""
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="x", repo_label="local: /tmp/x", commit="a",
        stack={}, output_lang="zh-TW", modules=[], entry_points=[],
        generated_blocks={},
    )
    drill_section = note[note.index("## 想深讀的入口"):]
    assert "[[decisions]]" in drill_section
    assert "[[personas]]" in drill_section
    assert "[[Roadmap]]" in drill_section  # produced by /obsidian-roadmap
    # Does NOT link to obsolete files
    for obsolete in ("api-surface", "features", "future", "roadmap", "jobs", "flows"):
        assert f"[[{obsolete}]]" not in drill_section, \
            f"drill-down should not reference deleted v3 file {obsolete!r}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v -k "v4" 2>&1 | tail -20`
Expected: FAIL — `compose_overview` v3 implementation doesn't emit `report-style`, doesn't have v4 sections.

- [ ] **Step 3: Find and replace `compose_overview` in `scripts/architect/sections.py`**

Locate the existing `def compose_overview(...)` function. Replace its body entirely:

```python
def compose_overview(
    *,
    project: str,
    repo_label: str,
    commit: str,
    stack: dict,
    output_lang: str,
    modules: list[dict],
    entry_points: list[dict],
    generated_blocks: dict[str, str],
) -> str:
    """Compose the v4 top-down report overview.md.

    Body sections (in order):
      1. Purpose & audience (LLM block: `purpose`)
      2. System diagram (LLM block: `system-diagram`)
      3. Stack (deterministic mirror of frontmatter `stack`)
      4. Capabilities (LLM block: `capabilities`)
      5. Flows (LLM block: `flows`)
      6. Module map (deterministic from `modules` arg)
      7. Cross-cutting improvements (LLM block: `cross-cutting-improvements`)
      8. Drill-down entries (deterministic wikilinks)
    """
    today = date.today().isoformat()
    fm = [
        "---",
        "type: architecture-overview",
        "report-style: true",
        f"date: {today}",
        f'project: "[[{project}]]"',
        *_repo_yaml_lines(repo_label),
        f"last-scanned: {today}",
        f"commit: {commit}",
        f"lang: {output_lang}",
        "tags: [architecture, codebase-doc, report]",
        "ai-first: true",
        "status: current",
    ]
    if stack:
        fm.append(_yaml_block("stack", stack))
    fm.append("---")

    body: list[str] = ["", heading("## For future Claude", output_lang)]
    if output_lang == "zh-TW":
        body.append(
            "本檔一次說完整個 project 的設計。打開這個檔就懂全貌,detail 在 "
            "[[modules/...]] / [[decisions]] / [[personas]]。"
        )
    else:
        body.append(
            "This single file tells the whole project story top-down. Drill into "
            "[[modules/...]] / [[decisions]] / [[personas]] when you need more detail."
        )
    body.append("")

    # 1. Purpose & audience (LLM block)
    body.append(heading("## Purpose & audience", output_lang))
    purpose = generated_blocks.get("purpose", "").strip()
    if purpose:
        body.append("<!-- @generated:start purpose -->")
        body.append(purpose)
        body.append("<!-- @generated:end purpose -->")
    body.append("")

    # 2. System diagram (LLM block, expects Mermaid inside)
    body.append(heading("## System diagram", output_lang))
    diagram = generated_blocks.get("system-diagram", "").strip()
    if diagram:
        body.append("<!-- @generated:start system-diagram -->")
        body.append(diagram)
        body.append("<!-- @generated:end system-diagram -->")
    body.append("")

    # 3. Stack (deterministic mirror of frontmatter)
    body.append(heading("## Stack", output_lang))
    if stack:
        for k, v in stack.items():
            if k == "modules":
                continue  # internal nesting, don't expand here
            if isinstance(v, list):
                body.append(f"- **{k}:** {', '.join(str(x) for x in v)}")
            else:
                body.append(f"- **{k}:** {v}")
        if output_lang == "zh-TW":
            body.append("- (完整理由見 [[decisions#技術棧理由]])")
        else:
            body.append("- (Full rationale in [[decisions#Stack rationale]])")
    else:
        body.append(
            "- (No stack detected. Add `pyproject.toml` / `package.json` at repo root.)"
            if output_lang == "en"
            else "- (Scanner 未偵測到 stack。請在 repo root 加 `pyproject.toml` / `package.json`。)"
        )
    body.append("")

    # 4. Capabilities (LLM block)
    body.append(heading("## Capabilities", output_lang))
    caps = generated_blocks.get("capabilities", "").strip()
    if caps:
        body.append("<!-- @generated:start capabilities -->")
        body.append(caps)
        body.append("<!-- @generated:end capabilities -->")
    body.append("")

    # 5. Flows (LLM block)
    body.append(heading("## Flows", output_lang))
    flows = generated_blocks.get("flows", "").strip()
    if flows:
        body.append("<!-- @generated:start flows -->")
        body.append(flows)
        body.append("<!-- @generated:end flows -->")
    body.append("")

    # 6. Module map (deterministic)
    body.append(heading("## Module map", output_lang))
    for m in modules:
        slug = m["slug"]
        display = m.get("display_name", slug)
        body.append(f"- **{display}** — [[modules/{slug}]]")
    body.append("")

    # 7. Cross-cutting improvements (LLM block, contains Imp 1/2/3 strict format)
    body.append(heading("## Cross-cutting improvements", output_lang))
    imps = generated_blocks.get("cross-cutting-improvements", "").strip()
    if imps:
        body.append("<!-- @generated:start cross-cutting-improvements -->")
        body.append(imps)
        body.append("<!-- @generated:end cross-cutting-improvements -->")
    body.append("")

    # 8. Drill-down entries (deterministic)
    body.append(heading("## Drill-down entries", output_lang))
    if output_lang == "zh-TW":
        body.append("- **模組設計判斷:** " + " | ".join(
            f"[[modules/{m['slug']}]]" for m in modules
        ) if modules else "- **模組設計判斷:** (尚未偵測到模組)")
        body.append("- **完整技術決定 + ADR 候選 + 已知限制:** [[decisions]]")
        body.append("- **使用者型態 reference:** [[personas]]")
        body.append("- **Curated Roadmap + Tasks backlog:** [[Roadmap]] (由 `/obsidian-roadmap` 產出)")
    else:
        body.append("- **Per-module design judgment:** " + " | ".join(
            f"[[modules/{m['slug']}]]" for m in modules
        ) if modules else "- **Per-module design judgment:** (no modules detected)")
        body.append("- **Full technical decisions + ADR candidates + Known limitations:** [[decisions]]")
        body.append("- **Persona reference:** [[personas]]")
        body.append("- **Curated Roadmap + Tasks backlog:** [[Roadmap]] (from `/obsidian-roadmap`)")
    body.append("")

    body.append(heading("## Related", output_lang))
    body.append(f"- [[{project}]]")

    return "\n".join(fm + body) + "\n"
```

The function above relies on a couple of helpers already in `sections.py`: `_repo_yaml_lines`, `_yaml_block`, `heading`. Confirm they exist via `grep -n "_yaml_block\|_repo_yaml_lines" scripts/architect/sections.py`. If `_yaml_block` is missing, scroll up in `sections.py` to find the v3 `compose_overview` which uses it; the helper should already be defined just above.

- [ ] **Step 4: Run v4 overview tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "v4" 2>&1 | tail -15`
Expected: PASS (4 new v4 tests).

- [ ] **Step 5: Remove the XFAIL on v3 overview test (if added in Task 4)**

If `tests/architect/test_sections.py` had v3 overview tests marked XFAIL in Task 4, remove the `@pytest.mark.xfail` decorator and update those tests to expect the v4 output (or delete them if they're superseded). Keep them only if they verify backward-compat behavior that v4 must preserve.

For each `test_compose_overview_en_emits_moc` / `test_compose_overview_zh_tw_translates_and_omits_empty_stack` v3 test, replace its body to call `compose_overview` with `output_lang` matching, and assert v4 sections appear (mirror the v4 tests above with simpler expectations).

If a v3 test specifically asserts `moc-style: true`, just delete that test — that's a v3-specific assertion that v4 has obsoleted.

- [ ] **Step 6: Run full sections tests**

Run: `uv run pytest tests/architect/test_sections.py -q 2>&1 | tail -3`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): rewrite compose_overview for v4 top-down report (8 sections)"
```

---

### Task 6: Overview synthesis prompt for v4

`compose_overview` produces structure; the LLM still has to fill the 4 LLM blocks (purpose / system-diagram / capabilities / flows / cross-cutting-improvements). Add `build_overview_prompt`.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_build_overview_prompt_v4_demands_report_blocks():
    from scripts.architect.sections import build_overview_prompt
    prompt = build_overview_prompt(
        project="myproj",
        modules_summary="backend, frontend, services",
        agents_md_excerpt="Tech Stack: FastAPI, React.",
        readme_excerpt="LINE OA admin tool.",
        personas_summary="Admin, Agent, End-user",
        per_module_improvements_summary="See modules/*.md improvements",
        output_lang="zh-TW",
    )
    # Demands the 5 LLM block names
    assert "purpose" in prompt
    assert "system-diagram" in prompt or "system_diagram" in prompt
    assert "capabilities" in prompt
    assert "flows" in prompt
    assert "cross-cutting-improvements" in prompt or "cross_cutting" in prompt
    # Demands Mermaid in system-diagram
    assert "mermaid" in prompt.lower()
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Cross-cutting Imps must follow strict 5-field format
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_sections.py::test_build_overview_prompt_v4_demands_report_blocks -v`
Expected: FAIL — `build_overview_prompt` not defined.

- [ ] **Step 3: Append `build_overview_prompt` to `sections.py`**

```python


def build_overview_prompt(
    *,
    project: str,
    modules_summary: str,
    agents_md_excerpt: str,
    readme_excerpt: str,
    personas_summary: str,
    per_module_improvements_summary: str,
    output_lang: str,
) -> str:
    """v4 — top-down report overview synthesis prompt.

    The LLM produces 5 blocks; `compose_overview` then assembles with
    deterministic Stack / Module map / Drill-down sections.
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫所有 prose。Code identifier (檔名、function、"
            "endpoint path、env var、wikilink 內檔名段) 保持英文。"
        )
    else:
        lang_directive = (
            "Write all prose in English. Code identifiers stay English."
        )

    return "\n".join([
        f"You are writing the v4 top-down architecture *report* for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. This is a REPORT, not an MOC. The reader opens overview.md and gets the "
        "   whole story; they should NOT need to drill into other files just to "
        "   understand what this project is and what's important about it.",
        "2. The Stack / Module map / Drill-down sections are rendered deterministically "
        "   by the caller — DO NOT produce them. Focus on the 5 LLM blocks below.",
        "3. Cross-cutting improvements MUST be cross-module. Single-module problems "
        "   stay in their module note. Each cross-cutting Imp should cite ≥ 2 modules "
        "   in its Evidence.",
        "",
        "## Output: produce 5 @generated blocks (JSON keys)",
        "",
        "### `purpose`",
        "1 short paragraph + a 3-5 bullet 'For whom' list of primary personas.",
        "  Example shape (zh-TW):",
        "  ```",
        "  - **是什麼:** 一句話定義",
        "  - **服務對象 (主要 personas):**",
        "    - <persona 1> — <one-line role>",
        "    - <persona 2> — <one-line role>",
        "  - **核心承諾:** 1-2 句",
        "  ```",
        "",
        "### `system-diagram`",
        "ONE Mermaid `graph TD` block showing the project at top-down level:",
        "external systems → frontend/backend → internal modules → data layer.",
        "Format:",
        "  ```mermaid",
        "  graph TD",
        "      External --> ...",
        "  ```",
        "Keep ≤ 12 nodes. This is the bird's-eye view; specific flows live in §Flows.",
        "",
        "### `capabilities`",
        "What this codebase DOES, grouped by capability area as H3 sub-sections, "
        "each with 1-3 short bullets. Format:",
        "  ```",
        "  ### Authentication",
        "  - <capability>, links to [[modules/<slug>]]",
        "  ",
        "  ### Webhook ingest",
        "  - <capability>",
        "  ```",
        "Aim for 5-8 capability areas. NO file paths in body prose — wikilinks only.",
        "",
        "### `flows`",
        "3-5 key user-level flows. Each flow is an H3 + Mermaid sequence + 2-4 "
        "friction bullets. Format:",
        "  ```",
        "  ### Flow 1: <name in zh-TW or en>",
        "  ```mermaid",
        "  sequenceDiagram",
        "      participant U as User",
        "      U->>S: ...",
        "  ```",
        "  **摩擦 / Friction:**",
        "  - <concrete pain> → 詳見 [[modules/<slug>#改進機會]]",
        "  - ...",
        "  ```",
        "Pick the most user-visible / business-critical flows. Skip internal-only data flows.",
        "",
        "### `cross-cutting-improvements`",
        "Top 3-5 improvement opportunities that span multiple modules. Each MUST:",
        "  - Be a cross-cutting concern (e.g. 'extract worker convention' impacts "
        "    backend + modules; 'TS migration' impacts frontend × N pages).",
        "  - Cite ≥ 2 modules in Evidence (wikilinks to module Imps).",
        "  - Follow the strict 5-field format:",
        "    ```",
        "    ### Imp <n>: <verb-first title ≤ 30 chars>",
        "    - **為什麼 / Why:** <≤ 1 sentence>",
        "    - **證據 / Evidence:** [[modules/<slug>#改進機會]] Imp N | [[modules/<other>...]] Imp M",
        "    - **Effort:** S | M | L | XL",
        "    - **未做的風險 / Risk if not done:** <≤ 1 sentence>",
        "    - **Confidence:** stated | high | medium | speculation",
        "    ```",
        "  - If you cannot identify cross-module evidence, DO NOT invent the Imp.",
        "",
        "Return strict JSON: {\"purpose\": \"...\", \"system-diagram\": \"...\", "
        "\"capabilities\": \"...\", \"flows\": \"...\", \"cross-cutting-improvements\": \"...\"}.",
        "",
        "## Project context",
        f"### Modules detected: {modules_summary}",
        "",
        "### Personas summary",
        personas_summary[:2000],
        "",
        "### Per-module improvement opportunities (cite these in cross-cutting evidence)",
        per_module_improvements_summary[:4000],
        "",
        "### README excerpt",
        readme_excerpt[:4000],
        "",
        "### AGENTS.md excerpt",
        agents_md_excerpt[:4000],
    ])
```

- [ ] **Step 4: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_build_overview_prompt_v4_demands_report_blocks -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): build_overview_prompt for v4 top-down report synthesis"
```

---

### Task 7: Mark deprecated SECTION_TYPES (no removal — backward compat)

Tasks 4-6 already handled the `DEPRECATED_SECTIONS` frozenset. This task adds explicit logging/warning when deprecated sections are composed.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_compose_note_warns_on_deprecated_section(caplog):
    """Calling compose_note(section='features'|etc.) still works but logs a deprecation warning."""
    import logging
    from scripts.architect.sections import compose_note
    with caplog.at_level(logging.WARNING):
        note = compose_note(
            section="features",
            project="x",
            repo_label="local: /tmp/x",
            commit="a",
            signal_sources=[],
            confidence="medium",
            output_lang="en",
            generated_blocks={"summary": "Test"},
        )
    assert "deprecated" in caplog.text.lower()
    assert "features" in caplog.text.lower()
    # Note still produced (backward compat).
    assert "type: architecture-features" in note
```

- [ ] **Step 2: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_compose_note_warns_on_deprecated_section -v`
Expected: FAIL — no warning emitted.

- [ ] **Step 3: Add logger + deprecation warning to `compose_note` in `sections.py`**

At the top of `scripts/architect/sections.py`, add:

```python
import logging

_logger = logging.getLogger(__name__)
```

Inside `compose_note`, after the line `type_value = SECTION_TYPES[section]`, add:

```python
    if section in DEPRECATED_SECTIONS:
        _logger.warning(
            "compose_note(section=%r) — this section type is DEPRECATED in v4. "
            "It is still callable for backward compat but no longer emitted by "
            "the default --frame=report pipeline.",
            section,
        )
```

- [ ] **Step 4: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_compose_note_warns_on_deprecated_section -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): log deprecation warning when compose_note hits deprecated sections"
```

---

## Phase D — Decisions enhancement

### Task 8: `decisions.md` adds `known-limitations` block

**Files:**
- Modify: (already done in Task 4 — `_BLOCK_NAMES["decisions"]` now includes "known-limitations")
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write test verifying decisions can emit known-limitations**

Append to `tests/architect/test_sections.py`:

```python
def test_compose_decisions_emits_known_limitations_block():
    from scripts.architect.sections import compose_note
    note = compose_note(
        section="decisions",
        project="x",
        repo_label="local: /tmp/x",
        commit="a",
        signal_sources=[],
        confidence="medium",
        output_lang="zh-TW",
        generated_blocks={
            "summary": "Decisions index.",
            "stack-rationale": "- React + FastAPI",
            "known-limitations": "- backend/.env deprecated\n- plain-text password fallback",
        },
    )
    assert "## 已知限制" in note
    assert "@generated:start known-limitations" in note
    assert "backend/.env deprecated" in note
```

- [ ] **Step 2: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_compose_decisions_emits_known_limitations_block -v`
Expected: PASS (Task 4 already wired `known-limitations` into `_BLOCK_NAMES["decisions"]` and `_BLOCK_HEADINGS`).

If the test FAILS because `known-limitations` heading mapping is missing, add to `_BLOCK_HEADINGS` in `sections.py`:

```python
    "known-limitations": "## Known limitations",
```

Re-run the test until PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_sections.py
# scripts/architect/sections.py may also need a small fix; include if so.
git commit -m "test(architect): decisions emits known-limitations block (v4)"
```

---

## Phase E — Roadmap narrowing

### Task 9: `detect_candidates` reads only overview + modules + decisions

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write failing test**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_v4_detect_candidates_skips_deleted_files(tmp_path):
    """v4: detect_candidates does NOT read future/roadmap/jobs/api-surface/features/flows files,
    even if they exist (legacy vault). It only reads overview + modules + decisions."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    # Overview with cross-cutting improvements
    (arch / "overview.md").write_text(
        "## 跨模組改進機會\n\n"
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** 共用 process\n"
        "- **證據:** [[modules/backend#改進機會]] Imp 1\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 流量峰值\n"
        "- **Confidence:** medium\n"
    )
    # Module with improvements
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 抽 sweeper\n"
        "- **為什麼:** main.py 過大\n"
        "- **證據:** `backend/main.py:58-388`\n"
        "- **Effort:** M\n"
        "- **未做的風險:** test scope 擴大\n"
        "- **Confidence:** high\n"
    )
    # Decisions with promote-to-ADR
    (arch / "decisions.md").write_text(
        "## 建議升級為 ADR\n\n"
        "1. **Redis vs PostgreSQL 角色釐清** — AGENTS.md 暗示未詳述\n"
    )
    # Legacy v3 file SHOULD BE IGNORED even if present.
    (arch / "features.md").write_text(
        "## 改進機會\n\n"
        "### Imp 99: 不該被撿到\n"
        "- **為什麼:** ...\n"
        "- **證據:** [[fake]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** ...\n"
        "- **Confidence:** speculation\n"
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("EventConsumer" in t for t in titles)
    assert any("抽 sweeper" in t for t in titles)
    # The deleted-file Imp must NOT be picked up.
    assert not any("Imp 99" in t or "不該被撿到" in t for t in titles), \
        f"v4 detect_candidates should skip features.md; got titles={titles}"


def test_v4_detect_candidates_reads_known_limitations_in_decisions(tmp_path):
    """The known-limitations content (migrated from future.md) becomes 'limitation' kind candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "decisions.md").write_text(
        "## 已知限制\n\n"
        "- backend/.env deprecated\n"
        "- plain-text password fallback\n"
    )
    cands = detect_candidates(tmp_path)
    kinds = {c.kind for c in cands}
    assert "limitation" in kinds
    titles = [c.title for c in cands if c.kind == "limitation"]
    assert any("env deprecated" in t for t in titles)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "v4_detect" 2>&1 | tail -10`
Expected: FAIL — current `detect_candidates` walks all files including features.md.

- [ ] **Step 3: Update `scripts/roadmap/candidates.py`**

Find `detect_candidates` function. Update the file-walking section:

```python
def detect_candidates(project_root: Path) -> list[Candidate]:
    """Walk Architecture/ files, extract candidates.

    v4: only reads overview.md, modules/*.md, and decisions.md `## 改進機會`
    or `## Improvement opportunities` blocks. Legacy v3 files (future.md,
    roadmap.md, jobs.md, api-surface.md, features.md, flows.md) are NOT walked
    even if they exist — those go through v3->v4 migration first.

    Also extracts `## 已知限制` from decisions.md as kind=limitation candidates.
    """
    arch = project_root / "Architecture"
    if not arch.is_dir():
        return []
    out: list[Candidate] = []

    # v4 signal sources — only overview + modules/*.md + decisions.md.
    candidate_files = []
    if (arch / "overview.md").is_file():
        candidate_files.append(arch / "overview.md")
    if (arch / "decisions.md").is_file():
        candidate_files.append(arch / "decisions.md")
    if (arch / "modules").is_dir():
        candidate_files.extend(sorted((arch / "modules").glob("*.md")))

    for f in candidate_files:
        out.extend(_extract_improvements_from_file(f, arch))

    # Decisions.md gets two extra extraction paths beyond `## 改進機會`:
    # 1. `## 建議升級為 ADR` (promote-to-ADR list) — kept from v3
    # 2. `## 已知限制` (known limitations, post-v4 migration) — new in v4
    if (arch / "decisions.md").is_file():
        out.extend(_extract_from_file(arch / "decisions.md", _DECISIONS_SECTIONS))
        out.extend(_extract_known_limitations(arch / "decisions.md", arch))

    return _dedup(out)


_KNOWN_LIM_SECTIONS = {
    "## 已知限制": "limitation",
    "## Known limitations": "limitation",
}


def _extract_known_limitations(path: Path, arch_root: Path) -> list[Candidate]:
    """Extract known-limitations bullets from decisions.md as `limitation` candidates."""
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    out: list[Candidate] = []
    for heading_str, kind in _KNOWN_LIM_SECTIONS.items():
        body, body_line = _section_body(text, heading_str)
        if body is None:
            continue
        anchor = heading_str.lstrip("# ").strip()
        bullets = _BULLET_RE.findall(body)
        rel = path.relative_to(arch_root.parent).as_posix().replace(".md", "")
        for raw in bullets:
            title = _normalize_title(raw)
            cand_id = _make_id(kind, title)
            out.append(Candidate(
                id=cand_id,
                title=title or raw,
                source_wikilink=f"[[{rel}#{anchor}]]",
                source_line=body_line,
                kind=kind,
                raw_text=raw.strip(),
            ))
    return out
```

If `_section_body`, `_BULLET_RE`, `_normalize_title`, `_make_id`, `_extract_from_file`, `_DECISIONS_SECTIONS`, `_dedup`, `_extract_improvements_from_file` are not already defined in candidates.py (they should be from earlier tasks in v3 plan), they need to remain — only the top-level `detect_candidates` body changes.

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_candidates.py -v 2>&1 | tail -15`
Expected: all green (existing + 2 new). If a v3-era test expects features.md or roadmap.md to be walked, update it: those expectations are obsolete in v4.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "feat(roadmap): v4 narrow signal source to overview/modules/decisions + known-limitations"
```

---

## Phase F — Schema docs

### Task 10: Update `references/ai-first-rules.md` for v4

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Read current schema for `architecture-overview` and decide where to update**

Run: `grep -n "type: architecture-overview\|type: architecture-features\|type: architecture-flows\|type: architecture-future\|type: architecture-roadmap\|type: architecture-jobs\|type: architecture-api-surface" references/ai-first-rules.md`

Find the lines and prepare edits.

- [ ] **Step 2: Update `architecture-overview` schema entry**

Find the `### \`type: architecture-overview\`` heading. Replace its body with:

```markdown
Generated by `/obsidian-architect`. Lives at `Projects/<P>/Architecture/overview.md`.
v4 produces a self-contained top-down report (no longer a MOC). Reader opens
this single file and gets the whole project story.

Required frontmatter:
- `type: architecture-overview`
- `report-style: true` (v4) — replaces v3's `moc-style: true`
- `date`, `project` (wikilink), `commit`, `last-scanned`
- `lang: zh-TW | en`
- `tags: [architecture, codebase-doc, report]`
- `ai-first: true`, `status: current`

Optional frontmatter:
- `stack:` block with primary-language / frameworks / test / build / deploy.
  Omit fields the scanner cannot infer (never guess).

Body sections (v4, in this top-down order):
1. `## For future Claude` / `## 給未來 Claude`
2. `## Purpose & audience` / `## 這是什麼 / 為誰服務` — 1 段 + 3-5 persona bullets
3. `## System diagram` / `## 系統架構圖` — 1 Mermaid `graph TD`
4. `## Stack` / `## 技術棧` — deterministic mirror of frontmatter `stack:`
5. `## Capabilities` / `## 核心能力` — H3-per-area capability inventory with module wikilinks
6. `## Flows` / `## 核心使用流程` — 3-5 user flows, each = Mermaid sequence + 2-4 friction bullets
7. `## Module map` / `## 模組地圖` — 1 line per module, all wikilinks
8. `## Cross-cutting improvements` / `## 跨模組改進機會` — 3-5 Imps that span ≥ 2 modules
9. `## Drill-down entries` / `## 想深讀的入口` — deterministic wikilinks to detail files
10. `## Related` / `## 相關`

LLM-written sections (purpose / system-diagram / capabilities / flows /
cross-cutting-improvements) wrapped in `<!-- @generated:start <name> -->` ...
`<!-- @generated:end <name> -->` sentinels. Deterministic sections (Stack / Module map
/ Drill-down / Related) emit no sentinels.

v3 → v4 migration: `moc-style: true` becomes `report-style: true`; v3 sections
(`purpose` / `layer-map` / `external-deps` / `key-abstractions`) are obsolete
and replaced.
```

- [ ] **Step 3: Add a DEPRECATED banner above each of the 6 obsolete types**

For each of these schema entries, prepend a deprecation banner:

- `### \`type: architecture-features\``
- `### \`type: architecture-roadmap\``
- `### \`type: architecture-future\``
- `### \`type: architecture-jobs\``
- `### \`type: architecture-flows\``
- `### \`type: architecture-api-surface\``

Above each, insert:

```markdown
> [!warning] DEPRECATED in v4
> This type is no longer emitted by the default `--frame=report` pipeline.
> Content moved to:
> - `architecture-features` → `architecture-overview` `## Capabilities` section
> - `architecture-flows` → `architecture-overview` `## Flows` section
> - `architecture-future` "Known limitations" → `architecture-decisions` `## Known limitations`
> - `architecture-future` "Aspirational ideas" / "Gap analysis" → per-module `## Improvement opportunities`
> - `architecture-roadmap` → removed; curated roadmap lives in `Projects/<P>/Roadmap.md` (from `/obsidian-roadmap`)
> - `architecture-jobs` → friction content moved to module Imps; JTBD content moved to `## Capabilities` framing
> - `architecture-api-surface` → removed; machine-readable surface lives in `/tmp/architect-<hash>/scan-report.json`
>
> The schema below is preserved so old vaults still load; `compose_note(section=...)`
> still works but logs a deprecation warning.
```

- [ ] **Step 4: Update `architecture-decisions` to mention `## Known limitations`**

Find `### \`type: architecture-decisions\``. In its body sections list, add (after `## Promote to ADR`):

```markdown
- `## Known limitations` / `## 已知限制` — concrete things that don't work today
  (migrated from v3 `architecture-future`).
```

- [ ] **Step 5: Build adapters to verify file ships cross-platform**

Run: `bash scripts/build.sh --platform claude-code`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(ai-first-rules): v4 overview schema + 6 deprecated types + decisions known-limitations"
```

---

## Phase G — Command body

### Task 11: Rewrite `commands/obsidian-architect.md` for v4 workflow

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Update flag documentation at top of file**

Find the `--frame=<judgment|description>` line in the command body. Replace with:

```markdown
**v4-specific flags:**
- `--frame=<report|judgment|description>` — default `report` (v4). `judgment`
  falls back to v3 behaviour; `description` to v2. v4 produces 8 files
  (overview + 5 modules + decisions + personas); legacy frames keep their
  larger file counts.
- `--keep-deprecated` — when migrating v3→v4, do NOT delete the 6 obsolete
  files. Not recommended; tar.gz backup already preserves them.
- `--improvements-per-file=<N>` — cap on per-file Imps, default 4. Overview
  cross-cutting Imps cap separately at 5.
- `--require-evidence` — default true. When false, LLM may emit Imps without
  Evidence (debugging only).
```

- [ ] **Step 2: Add a new Phase 1.6 v3 → v4 migration step (after Phase 1.5 v2→v3)**

Find the existing "Phase 1.5: v2 → v3 migration" block. After its end (before Phase 2), insert:

```markdown
## Phase 1.6: v3 → v4 migration (only when `--frame=report` AND existing vault is v3)

Detect if `Projects/<P>/Architecture/_manifest.lock.json` exists and reports
`frame: "judgment-v3"` (or `version: 3`).

1. Call `scripts.architect.migration.plan_v3_to_v4_migration(arch_dir)`.
2. Print the plan to the user — 6 files to delete (`future.md`, `roadmap.md`,
   `jobs.md`, `api-surface.md`, `features.md`, `flows.md`), known-limitations
   content to migrate into `decisions.md`, files kept (`overview.md`,
   `modules/*`, `decisions.md`, `personas.md`).
3. ASK user `proceed | dry-run | abort`. `--force` bypasses with proceed.
   `--keep-deprecated` skips the delete step but still merges known-limitations.
4. On `proceed`: call `backup_architecture_dir(arch_dir)` first
   (tar.gz to `_archive/architecture-pre-v4-<timestamp>.tar.gz`), then
   `apply_v3_to_v4_migration(arch_dir, plan, dry_run=False)`.
5. On `dry-run`: call `apply_v3_to_v4_migration(... dry_run=True)` and stop.

After successful migration the overview.md content from v3 is now stale (it's
still the v3 MOC). Phase 4 (Overview synthesis below) overwrites it with v4
report content. Lockfile is rewritten in Phase 5 with `version: 4`,
`frame: "report-v4"`.
```

- [ ] **Step 3: Simplify Phase 3.5 — only write overview/decisions/personas/modules**

Find the existing Phase 3.5 block. Replace with:

```markdown
## Phase 3.5: Per-section synthesis (v4)

Order:
1. **decisions.md** — `compose_note(section="decisions", ...)`. New block
   `known-limitations` is populated from migration carry-over (if any) plus
   LLM additions; the LLM should produce the other blocks (summary,
   stack-rationale, etc.) per existing v3 behavior.
2. **personas.md** — `compose_note(section="personas", ...)`. Lighter v4
   version: drop the heavy pain-points list (those moved to module Imps).

Removed in v4 (no longer written): api-surface.md, features.md, roadmap.md,
future.md, jobs.md, flows.md. If `--frame=judgment` is passed, the v3
behavior is restored and these are written.

api-surface detection still runs as part of Phase 1 deterministic scan; the
data lives in `scan-report.json` for `/obsidian-roadmap` and other tooling.
```

- [ ] **Step 4: Rewrite Phase 4 — overview synthesis**

Replace the Phase 4 block:

```markdown
## Phase 4: Overview synthesis (v4 top-down report)

This is the centerpiece of v4. The overview becomes a self-contained report.

1. Gather context inputs:
   - `modules_summary` — slug + display name + 1-line role per module
     (from manifest + module note `## 模組職責` blocks).
   - `personas_summary` — first 2 KB of `personas.md`.
   - `per_module_improvements_summary` — concatenation of each module's
     `## 改進機會` block (capped). The LLM uses this to write cross-cutting
     Imps with proper Evidence wikilinks.
   - `readme_excerpt`, `agents_md_excerpt` — first 4 KB of each.

2. Build the prompt: `scripts.architect.sections.build_overview_prompt(...)`.

3. Invoke the LLM. Expect strict JSON:
   ```json
   {
     "purpose": "...",
     "system-diagram": "```mermaid\\n...\\n```",
     "capabilities": "### Area\\n- ...",
     "flows": "### Flow 1: ...\\n```mermaid\\n...\\n```\\n**摩擦:**\\n- ...",
     "cross-cutting-improvements": "### Imp 1: ...\\n- **為什麼:** ..."
   }
   ```

4. Validate `cross-cutting-improvements` via `parse_improvements_block(...)`.
   Each Imp must cite ≥ 2 modules in its Evidence (cross-cutting requirement).
   If a candidate Imp cites only one module, downgrade it / drop it. Aim for
   3-5 Imps total.

5. Compose: `scripts.architect.sections.compose_overview(...)` assembles the
   8-section report. Stack section is auto-generated from `stack` arg
   (which was detected by Phase 1 scanner). Module map and Drill-down
   sections are deterministic from `modules` arg.

6. Write to `Projects/<P>/Architecture/overview.md`. The frontmatter has
   `report-style: true` and `lang: <output_lang>`.

7. Update lockfile section entry: `sections.overview.signal-hash`,
   `sections.overview.lang`, etc.
```

- [ ] **Step 5: Update Hub note update section to reflect 8-file v4 structure**

Find the Hub note update block. Replace the listed wikilinks to reflect v4:

```markdown
## Hub note update (v4)

Append/replace `## Architecture` (or `## 架構` if zh-TW) block in
`Projects/<P>/<P>.md`. v4 wikilinks:

```markdown
## 架構

- 總覽 (top-down 報告): [[Architecture/overview]] (v4 report-style, 上次掃描 YYYY-MM-DD @ `<sha>`)
- 模組設計判斷: [[Architecture/modules/backend]] | [[Architecture/modules/frontend]] | ... (list each module)
- 技術決定 + ADR 候選 + 已知限制: [[Architecture/decisions]]
- 使用者型態 reference: [[Architecture/personas]]
- Curated Roadmap: [[Roadmap]]
- 重新整理: `/obsidian-architect <repo-path> --refresh`
```

The legacy v3 wikilinks to `future.md` / `roadmap.md` / `jobs.md` /
`api-surface.md` / `features.md` / `flows.md` MUST be removed from the
hub block — those vault files no longer exist post-migration.
```

- [ ] **Step 6: Build adapters**

Run: `bash scripts/build.sh`
Expected: 4 dist trees regenerate cleanly.

- [ ] **Step 7: Inspect**

Run: `wc -l dist/claude-code/commands/obsidian-architect.md dist/codex-cli/.codex/commands/obsidian-architect.md`
Expected: both files exist, comparable line counts.

Run: `grep -c "v4" dist/claude-code/commands/obsidian-architect.md`
Expected: ≥ 3 (v4 markers present).

- [ ] **Step 8: Commit**

```bash
git add commands/obsidian-architect.md dist/
git commit -m "feat(architect): v4 command body — report frame, v3->v4 migration phase, 8-file output"
```

---

## Phase H — Polish

### Task 12: `--frame=report` resolution helper

`commands/obsidian-architect.md` references `--frame=report` but the parsing logic needs to recognize it. Most resolution is in the command body (agent-driven), but provide a Python helper for default-resolution.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_resolve_frame_default_is_report():
    from scripts.architect.sections import resolve_frame
    assert resolve_frame(None) == "report"
    assert resolve_frame("report") == "report"
    assert resolve_frame("judgment") == "judgment"
    assert resolve_frame("description") == "description"


def test_resolve_frame_invalid_falls_back_to_report():
    from scripts.architect.sections import resolve_frame
    assert resolve_frame("vibe-driven") == "report"
    assert resolve_frame("") == "report"
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_sections.py::test_resolve_frame_default_is_report tests/architect/test_sections.py::test_resolve_frame_invalid_falls_back_to_report -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `resolve_frame` to `sections.py`**

```python


SUPPORTED_FRAMES = ("report", "judgment", "description")
DEFAULT_FRAME = "report"


def resolve_frame(cli_flag: str | None) -> str:
    """Return the effective architect frame.

    Precedence: CLI flag > default ('report'). Invalid or empty falls back.
    """
    if cli_flag and cli_flag in SUPPORTED_FRAMES:
        return cli_flag
    return DEFAULT_FRAME
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "resolve_frame" 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): resolve_frame() with report default + judgment/description fallback"
```

---

### Task 13: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Open CHANGELOG.md and find `## Unreleased`**

If `## Unreleased` doesn't exist, create it right under the title.

- [ ] **Step 2: Append entries**

Under `## Unreleased`, add:

```markdown
### Changed

- `/obsidian-architect` v4 — Overview reframed from MOC to self-contained
  top-down report. Reader opens overview.md once and gets the whole project
  story; detail files (modules, decisions, personas) are now drill-down
  references, not required reading. 6 obsolete files deleted in migration:
  `future.md`, `roadmap.md`, `jobs.md`, `api-surface.md`, `features.md`,
  `flows.md`. Their content moved:
  - `features.md` → `overview.md` `## Capabilities` section
  - `flows.md` → `overview.md` `## Flows` section (with Mermaid + friction)
  - `future.md` "Known limitations" → `decisions.md` `## Known limitations`
  - `future.md` "Aspirational ideas" → per-module `## Improvement opportunities`
  - `roadmap.md` removed (curated roadmap is `/obsidian-roadmap`'s output)
  - `jobs.md` removed (friction → module Imps; JTBD → capability framing)
  - `api-surface.md` removed (machine-readable only, in `scan-report.json`)
- `Architecture/` directory now has 8 files: `overview.md`, `modules/<5>.md`,
  `decisions.md`, `personas.md` (down from 14).
- Lockfile schema bumped to v4 with `frame: "report-v4"` default.
- `/obsidian-roadmap` Phase 1 signal source narrowed to overview + modules
  + decisions only. Same number of candidates (no improvements lost) but
  cleaner source provenance.
- `decisions.md` body section list gains `## Known limitations` (auto-migrated
  from v3 `future.md` content on first v4 run).

### Added

- `--frame=<report|judgment|description>` flag on `/obsidian-architect`.
  Default `report` (v4). `judgment` keeps v3 14-file output; `description`
  restores v2 file-tree-listing behavior.
- `--keep-deprecated` flag — skip deletion of v3 files during migration
  (not recommended; tar.gz backup already preserves them).
- v3 → v4 migration step: tar.gz `Architecture/_archive/...` backup;
  `--dry-run` shows plan; auto-merges known-limitations into decisions.md.

### Deprecated

- `architecture-features`, `architecture-flows`, `architecture-future`,
  `architecture-roadmap`, `architecture-jobs`, `architecture-api-surface`
  schema types. Still callable for backward compat (with deprecation log
  warning), but no longer emitted by the default `--frame=report` pipeline.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): v4 consolidated report frame announcement"
```

---

### Task 14: Update SKILL.md + README.md

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: Update SKILL.md architect description (Layer 1)**

Find the `/obsidian-architect` bullet under Layer 1. Replace with:

```markdown
- `/obsidian-architect <repo-path>` — Generate a self-contained, top-down
  architecture report (v4). Reader opens `Architecture/overview.md` once
  and gets purpose → system diagram → stack → capabilities → flows →
  module map → cross-cutting improvements → drill-down. Detail files
  (5 per-module judgment notes + decisions + personas) are drill-down
  references only. 8 files total; no MOC fragmentation. Feeds
  `/obsidian-roadmap` Phase 1 via `## Improvement opportunities` blocks.
```

- [ ] **Step 2: Update README.md commands table**

Find the `/obsidian-architect` row in the commands table. Replace its
description with:

```markdown
| `/obsidian-architect` | Top-down architecture report (v4). Self-contained `overview.md` + 5 module judgments + decisions + personas. Replaces the v3 14-file MOC layout. |
```

- [ ] **Step 3: Build adapters**

Run: `bash scripts/build.sh`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md dist/
git commit -m "docs(skill+readme): announce architect v4 consolidated report frame"
```

---

### Task 15: Run full test suite

**Files:** none (verification only)

- [ ] **Step 1: Run all architect + roadmap tests**

Run: `uv run pytest tests/ -q 2>&1 | tail -5`
Expected: all green.

If any v3 test fails because it expected v3 behavior (e.g. `moc-style: true`,
features.md being walked, etc.), update the test to either:
- expect v4 behavior, OR
- pass `frame="judgment"` explicitly to invoke v3 backward-compat path.

DO NOT mark tests as XFAIL; resolve them properly.

- [ ] **Step 2: Run test count check**

Run: `uv run pytest tests/ --collect-only -q 2>&1 | tail -5`
Expected: total test count ≥ 270 (we added ~10 new v4 tests).

- [ ] **Step 3: Commit any fixed tests**

```bash
git add tests/
git diff --cached --quiet || git commit -m "test: align v3-era tests with v4 frame default"
```

(Skip the commit if no changes were needed.)

---

### Task 16: End-to-end smoke against langlive-line-oa

**Files:** none (verification + dry-run; do NOT modify the real vault)

- [ ] **Step 1: Read current state of langlive-line-oa Architecture/**

```bash
ls /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture/
```

Expected: 14 v3 files (overview.md + 5 modules + features/decisions/personas/jobs/flows/roadmap/future/api-surface).

- [ ] **Step 2: Dry-run migration plan against the real vault**

```bash
uv run python << 'PYEOF'
from pathlib import Path
from scripts.architect.migration import plan_v3_to_v4_migration

arch = Path("/Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture")
plan = plan_v3_to_v4_migration(arch)
print(f"files to delete: {plan.files_to_delete}")
print(f"files to keep: {plan.files_to_keep}")
print(f"known-limitations to migrate: {plan.known_limitations_to_migrate[:300] if plan.known_limitations_to_migrate else 'NONE'}")
PYEOF
```

Expected output:
- `files to delete: ['future.md', 'roadmap.md', 'jobs.md', 'api-surface.md', 'features.md', 'flows.md']`
- `files to keep: ['overview.md', 'decisions.md', 'personas.md', 'modules/backend.md', ...]` (8 files)
- `known-limitations to migrate: ...` (non-empty — v3 future.md has 5 known limitations)

- [ ] **Step 3: Spot-check `compose_overview` with synthetic blocks**

```bash
uv run python << 'PYEOF'
from scripts.architect.sections import compose_overview, parse_improvements_block, ImprovementItem, render_improvements_block

# Synthetic cross-cutting Imp using strict format
imp = ImprovementItem(
    title="拆 EventConsumer 為獨立 worker",
    why="API 與 event 共用 process,峰值互卡",
    evidence=["[[modules/backend#改進機會]] Imp 1", "[[modules/modules#改進機會]] Imp 2"],
    effort="L",
    risk_if_not_done="峰值客服 UI 延遲飆",
    confidence="medium",
)
ccr = render_improvements_block([imp], lang="zh-TW")

note = compose_overview(
    project="langlive-line-oa",
    repo_label="local: /Users/leric/Desktop/code/langlive-line-oa",
    commit="fce278d",
    stack={"primary-language": "Python + TypeScript", "frameworks": ["FastAPI", "React 19"]},
    output_lang="zh-TW",
    modules=[
        {"slug": "backend", "display_name": "Backend"},
        {"slug": "frontend", "display_name": "Frontend"},
        {"slug": "modules", "display_name": "Modules (qa-to-kb)"},
        {"slug": "scripts", "display_name": "Scripts"},
        {"slug": "services", "display_name": "Services"},
    ],
    entry_points=[],
    generated_blocks={
        "purpose": "- **是什麼:** LINE OA admin tool\n- **服務對象:**\n  - 客服管理員 — 看 dashboard\n  - 客服 Agent — 回覆 ticket",
        "system-diagram": "```mermaid\ngraph TD\n  LINE --> Backend\n  Frontend --> Backend\n```",
        "capabilities": "### Auth\n- bcrypt + admin approval\n\n### Webhook\n- LINE ingest",
        "flows": "### Flow 1: LINE 客戶詢問\n```mermaid\nsequenceDiagram\n  U->>S: msg\n```\n\n**摩擦:**\n- WebSocket 斷線 → 見 [[modules/backend#改進機會]]",
        "cross-cutting-improvements": ccr,
    },
)
print(note)
print("---")
print(f"size: {len(note)} bytes")
print(f"H2 count: {note.count(chr(10) + '## ')}")
PYEOF
```

Expected output:
- Note containing all 8 H2 sections (`## 給未來 Claude`, `## 這是什麼 / 為誰服務`, `## 系統架構圖`, `## 技術棧`, `## 核心能力`, `## 核心使用流程`, `## 模組地圖`, `## 跨模組改進機會`, `## 想深讀的入口`, `## 相關`).
- Frontmatter has `report-style: true`.
- Module map deterministically lists `[[modules/backend]]`, `[[modules/frontend]]`, etc.
- Drill-down section links to `[[decisions]]`, `[[personas]]`, `[[Roadmap]]`.
- Size ≈ 3-5 KB (synthetic minimal blocks; real run will be 8-12 KB).
- H2 count == 10 (9 main + Related).

- [ ] **Step 4: Verify `/obsidian-roadmap` Phase 1 still works against v4 (synthetic)**

```bash
uv run python << 'PYEOF'
import tempfile
from pathlib import Path
from scripts.roadmap.candidates import detect_candidates

with tempfile.TemporaryDirectory() as td:
    root = Path(td) / "proj"
    arch = root / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "overview.md").write_text(
        "## 跨模組改進機會\n\n"
        "### Imp 1: cross-module Imp\n"
        "- **為什麼:** spans 2 modules\n"
        "- **證據:** [[modules/backend#改進機會]] Imp 1 | [[modules/frontend#改進機會]] Imp 1\n"
        "- **Effort:** L\n"
        "- **未做的風險:** flow blocked\n"
        "- **Confidence:** stated\n"
    )
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: backend-specific\n"
        "- **為什麼:** something\n"
        "- **證據:** `backend/main.py:42`\n"
        "- **Effort:** M\n"
        "- **未做的風險:** ...\n"
        "- **Confidence:** high\n"
    )
    (arch / "decisions.md").write_text(
        "## 已知限制\n\n"
        "- backend/.env deprecated\n"
    )
    # Legacy v3 file should be ignored by v4 detect_candidates.
    (arch / "features.md").write_text("## 改進機會\n\n### Imp 99: should-be-ignored\n- **為什麼:** ...\n- **證據:** x\n- **Effort:** S\n- **未做的風險:** ...\n- **Confidence:** speculation\n")
    cands = detect_candidates(root)
    print(f"total candidates: {len(cands)}")
    by_kind = {}
    for c in cands:
        by_kind.setdefault(c.kind, []).append(c.title)
    for kind, titles in by_kind.items():
        print(f"  {kind}: {titles}")
    # features.md Imp 99 should NOT appear.
    titles_all = [c.title for c in cands]
    assert "should-be-ignored" not in " ".join(titles_all), \
        "v4 detect_candidates leaked features.md candidate"
    print("✓ features.md ignored (v4 narrowing works)")
PYEOF
```

Expected output:
- `total candidates: 3` (1 cross-module + 1 module + 1 limitation).
- `improvement: ['cross-module Imp', 'backend-specific']`
- `limitation: ['backend env deprecated']` (or similar)
- `✓ features.md ignored (v4 narrowing works)`

- [ ] **Step 5: Verify branch state**

Run: `git log --oneline -20`
Expected: ~15 commits, one per task in this plan.

Run: `uv run pytest tests/ -q && bash scripts/build.sh`
Expected: all green; all 4 adapter dist trees regenerate cleanly.

- [ ] **Step 6: Final acceptance checklist (mirrors spec §14)**

Manually verify:

- [ ] `scripts/architect/sections.py` `_BLOCK_NAMES["overview"]` has the 8 v4 sections in order
- [ ] `SECTION_TYPES["overview"]` still exists; `DEPRECATED_SECTIONS` frozenset has the 6 deprecated entries
- [ ] `compose_overview` emits `report-style: true` and the 8 body sections
- [ ] `build_overview_prompt` exists and demands cross-module Evidence for Imps
- [ ] `plan_v3_to_v4_migration` lists exactly 6 files to delete
- [ ] `apply_v3_to_v4_migration` deletes those 6 files and merges known-limitations into decisions.md
- [ ] `compose_note(section="features"|...)` logs a deprecation warning but still produces output
- [ ] `detect_candidates` only walks overview + modules + decisions (verified by synthetic test)
- [ ] `references/ai-first-rules.md` has the v4 overview schema + 6 DEPRECATED banners + decisions known-limitations
- [ ] `commands/obsidian-architect.md` has the new `--frame=report` default + Phase 1.6 migration + simplified Phase 3.5
- [ ] CHANGELOG, SKILL.md, README updated
- [ ] All adapter dist trees rebuilt
- [ ] Real langlive-line-oa migration plan correctly identifies 6 files + extracts known-limitations
- [ ] Synthetic overview compose produces 8 H2 sections, ~3-5 KB
- [ ] `tests/` all green (≥ 270 tests)
