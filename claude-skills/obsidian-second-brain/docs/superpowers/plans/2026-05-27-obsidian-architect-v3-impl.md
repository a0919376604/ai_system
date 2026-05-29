# obsidian-architect v3 (Judgment-Driven Reframe) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `/obsidian-architect` 從 description-driven (列檔案、講 file location) 改為 judgment-driven (講設計優缺點與改進機會)。同步加 product-eye 三檔 (personas/jobs/flows)、瘦身 api-surface.md,並讓 `/obsidian-roadmap` Phase 1 改抓 architect 的 `## 改進機會` block 作為主訊號源。

**Architecture:** 不重做 scanner,只換 sections.py 的 block-names 跟 prompt directive (critic 而非 transcriber)。加 3 個新 type 的 signal collector (personas/jobs/flows) 同樣以 judgment frame 寫入。Migration v2→v3 採乾淨切換:刪舊 `@generated` block + 保留 `@user` block + tar.gz 安全網。`--frame=description` flag 保留 v2 backward compat。

**Tech Stack:** Python 3.10+, pytest, dataclass, pyyaml, 既有 `scripts/architect/{lang,sentinels,lockfile,sections,api_surface_render}.py`。

**Spec:** `docs/superpowers/specs/2026-05-27-obsidian-architect-v3-judgment-driven-design.md`

**Suggested branch:** `feat/architect-v3-judgment`

---

## Task layout

16 個任務分 8 phase。Phase A-D 是 architect 重做,Phase E 接 roadmap,Phase F-H 收尾。

| Phase | 任務 | 範圍 |
|---|---|---|
| A. Foundation | 1-2 | Heading map 加項 + lockfile v3 schema + migration helper |
| B. Sections.py reframe | 3-5 | Module / features critique frame + 新 block names + prompt directive |
| C. Product-eye types | 6-8 | personas / jobs / flows signal collectors |
| D. api-surface reframe | 9 | 從完整 table 改為分類概觀 |
| E. Roadmap integration | 10-11 | candidates.py 加 v3 欄位 + 讀 `## 改進機會` block |
| F. Schema docs | 12 | ai-first-rules.md 三新 type + module/features schema 變化 |
| G. Command body + adapter | 13-14 | 改寫 `commands/obsidian-architect.md` + 新 flag + 遷移流程 + adapter build |
| H. Polish | 15-16 | CHANGELOG / SKILL.md / README + 對 langlive-line-oa 端到端 smoke |

---

## Phase A — Foundation

### Task 1: Heading map + lockfile v3 schema

**Files:**
- Modify: `scripts/architect/lang.py`
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lang.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing test for new lang heading keys**

Append to `tests/architect/test_lang.py`:

```python
def test_heading_map_includes_v3_judgment_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Design strengths": "## 設計優點",
        "## Design weaknesses": "## 設計缺點 / 風險",
        "## Improvement opportunities": "## 改進機會",
        "## Module responsibility": "## 模組職責",
        "## Overall flow": "## 整體流程",
        "## Capability scope": "## 能力範圍",
        "## Journey": "## 旅程",
        "## Personas": "## 使用者型態",
        "## Jobs to be done": "## Jobs to be Done",
        "## Flows": "## 使用流程",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_v3_judgment_keys -v`
Expected: FAIL — missing heading keys.

- [ ] **Step 3: Append heading entries to lang.py HEADING_MAP**

Open `scripts/architect/lang.py`. In the HEADING_MAP dict, add (place inside the dict before the closing `}`):

```python
    # v3 judgment-driven frame
    "## Design strengths": {"en": "## Design strengths", "zh-TW": "## 設計優點"},
    "## Design weaknesses": {"en": "## Design weaknesses", "zh-TW": "## 設計缺點 / 風險"},
    "## Improvement opportunities": {"en": "## Improvement opportunities", "zh-TW": "## 改進機會"},
    "## Module responsibility": {"en": "## Module responsibility", "zh-TW": "## 模組職責"},
    "## Overall flow": {"en": "## Overall flow", "zh-TW": "## 整體流程"},
    "## Capability scope": {"en": "## Capability scope", "zh-TW": "## 能力範圍"},
    "## Journey": {"en": "## Journey", "zh-TW": "## 旅程"},
    "## Personas": {"en": "## Personas", "zh-TW": "## 使用者型態"},
    "## Jobs to be done": {"en": "## Jobs to be done", "zh-TW": "## Jobs to be Done"},
    "## Flows": {"en": "## Flows", "zh-TW": "## 使用流程"},
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_v3_judgment_keys -v`
Expected: PASS.

- [ ] **Step 5: Write failing test for lockfile v3 schema**

Append to `tests/architect/test_lockfile.py`:

```python
def test_v3_schema_with_frame_marker(tmp_path: Path):
    """v3 adds a `frame` field declaring which architect version produced this lockfile."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile
    lock = Lockfile(
        version=3,
        scanner_version="0.3.0",
        fields={},
        note_blocks={},
        sections={},
        functions={},
        frame="judgment-v3",
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    data = json.loads(target.read_text())
    assert data["frame"] == "judgment-v3"
    loaded = load_lockfile(target)
    assert loaded.frame == "judgment-v3"
    assert loaded.version == 3


def test_v2_lockfile_migrates_to_v3_on_load(tmp_path: Path):
    """Loading a v2 lockfile should yield version=3 with frame='description-v2' (legacy marker)."""
    import json
    from scripts.architect.lockfile import load_lockfile, CURRENT_SCHEMA
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 2,
        "scanner_version": "0.2.0",
        "fields": {},
        "note_blocks": {},
        "sections": {"features": {"signal-hash": "sha256:abc", "lang": "en"}},
        "functions": {},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == CURRENT_SCHEMA == 3
    # v2 entries preserved; frame defaults to legacy marker.
    assert loaded.sections["features"]["signal-hash"] == "sha256:abc"
    assert loaded.frame == "description-v2"
```

- [ ] **Step 6: Run lockfile tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py::test_v3_schema_with_frame_marker tests/architect/test_lockfile.py::test_v2_lockfile_migrates_to_v3_on_load -v`
Expected: FAIL — `frame` attribute / `CURRENT_SCHEMA=3` not defined.

- [ ] **Step 7: Bump lockfile schema to v3**

Open `scripts/architect/lockfile.py`. Update top:

```python
CURRENT_SCHEMA = 3
```

Update the `Lockfile` dataclass — add `frame` field:

```python
@dataclass
class Lockfile:
    version: int
    scanner_version: str
    fields: dict = field(default_factory=dict)
    note_blocks: dict = field(default_factory=dict)
    sections: dict = field(default_factory=dict)
    functions: dict = field(default_factory=dict)
    frame: str = "description-v2"  # description-v2 (legacy) | judgment-v3
```

Update `load_lockfile`:

```python
def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    incoming_version = data.get("version", 1)
    return Lockfile(
        version=CURRENT_SCHEMA,
        scanner_version=data.get("scanner_version", "0.0.0"),
        fields=data.get("fields", {}),
        note_blocks=data.get("note_blocks", {}),
        sections=data.get("sections", {}),
        functions=data.get("functions", {}),
        frame=data.get("frame", "description-v2" if incoming_version < 3 else "judgment-v3"),
    )
```

Update `write_lockfile`:

```python
def write_lockfile(lock: Lockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(lock)
    payload["version"] = CURRENT_SCHEMA
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))
```

- [ ] **Step 8: Run lockfile tests**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: PASS (all old + 2 new tests).

- [ ] **Step 9: Run full lang + lockfile tests**

Run: `uv run pytest tests/architect/test_lang.py tests/architect/test_lockfile.py -v`
Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add scripts/architect/lang.py scripts/architect/lockfile.py tests/architect/test_lang.py tests/architect/test_lockfile.py
git commit -m "feat(architect): lang headings + lockfile v3 schema with frame marker"
```

---

### Task 2: Migration helper — drop v2 @generated blocks, keep @user, archive tar.gz

**Files:**
- Create: `scripts/architect/migration.py`
- Create: `tests/architect/test_migration.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_migration.py`:

```python
import tarfile
from pathlib import Path

from scripts.architect.migration import (
    MigrationPlan,
    plan_v2_to_v3_migration,
    apply_v2_to_v3_migration,
    backup_architecture_dir,
)


def _setup_v2_architecture(arch_root: Path):
    """Create a synthetic v2 layout: modules/X.md with @generated blocks."""
    (arch_root / "modules").mkdir(parents=True)
    (arch_root / "modules" / "backend.md").write_text(
        "---\ntype: architecture-module\n---\n\n"
        "## For future Claude\nPreamble.\n\n"
        "## What it does\n"
        "<!-- @generated:start what-it-does -->\n"
        "It does backend things.\n"
        "<!-- @generated:end what-it-does -->\n\n"
        "## Key files\n"
        "<!-- @generated:start key-files -->\n"
        "- backend/main.py\n"
        "- backend/app.py\n"
        "<!-- @generated:end key-files -->\n\n"
        "## User notes\n"
        "<!-- @user:start user-notes -->\n"
        "This module has a tricky lifecycle, see ADR-007.\n"
        "<!-- @user:end user-notes -->\n"
    )


def test_plan_lists_blocks_to_drop_keep_and_archive(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    assert plan.files_to_modify == ["modules/backend.md"]
    backend_blocks = plan.blocks_per_file["modules/backend.md"]
    # v2 generated blocks slated for removal.
    assert "what-it-does" in backend_blocks["drop"]
    assert "key-files" in backend_blocks["drop"]
    # User block preserved.
    assert "user-notes" in backend_blocks["keep"]


def test_apply_strips_generated_keeps_user_blocks(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    apply_v2_to_v3_migration(arch, plan, dry_run=False)
    text = (arch / "modules" / "backend.md").read_text()
    # @generated blocks dropped along with their headings.
    assert "@generated:start what-it-does" not in text
    assert "@generated:start key-files" not in text
    assert "It does backend things." not in text
    assert "backend/main.py" not in text
    # @user block kept verbatim.
    assert "@user:start user-notes" in text
    assert "see ADR-007" in text
    # Preamble heading and YAML survive.
    assert "## For future Claude" in text


def test_dry_run_does_not_modify_files(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    before = (arch / "modules" / "backend.md").read_text()
    plan = plan_v2_to_v3_migration(arch)
    apply_v2_to_v3_migration(arch, plan, dry_run=True)
    after = (arch / "modules" / "backend.md").read_text()
    assert before == after


def test_backup_creates_tarball(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    archive = backup_architecture_dir(arch)
    assert archive.exists()
    assert archive.suffix == ".gz"
    # tar.gz contains the architecture tree.
    with tarfile.open(archive, "r:gz") as tf:
        names = tf.getnames()
        assert any("modules/backend.md" in n for n in names)


def test_plan_lists_v3_blocks_to_create(tmp_path: Path):
    arch = tmp_path / "Architecture"
    _setup_v2_architecture(arch)
    plan = plan_v2_to_v3_migration(arch)
    expected_v3 = {"scope", "strengths", "weaknesses", "improvements", "dependencies"}
    actual = set(plan.blocks_per_file["modules/backend.md"]["create"])
    assert expected_v3 <= actual, f"missing v3 blocks: {expected_v3 - actual}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_migration.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/architect/migration.py`**

```python
"""v2 → v3 migration helper.

Drops v2 @generated blocks (file-tree noise) and keeps @user blocks (judgment).
Provides plan-then-apply for safety + tar.gz archive as safety net.
"""

from __future__ import annotations

import re
import tarfile
import time
from dataclasses import dataclass, field
from pathlib import Path

# v2 generated block names that v3 supersedes — these get dropped.
V2_GENERATED_BLOCKS_TO_DROP = {
    "what-it-does", "how-it-works", "key-files",
    "depends-on", "consumed-by", "recent-activity",
}

# v3 generated blocks per file type (module-level).
V3_MODULE_BLOCKS = {"scope", "strengths", "weaknesses", "improvements", "dependencies"}

# Sentinel + heading detection.
_GENERATED_RE = re.compile(
    r"(##\s+[^\n]*\n\s*\n?)?"
    r"<!--\s*@generated:start\s+(\S+)\s*-->"
    r".*?"
    r"<!--\s*@generated:end\s+\2\s*-->\n?",
    re.DOTALL,
)
_USER_NAME_RE = re.compile(r"<!--\s*@user:start\s+(\S+)\s*-->")


@dataclass
class MigrationPlan:
    files_to_modify: list[str] = field(default_factory=list)
    # files_to_modify entry -> {"drop": [block_names], "keep": [block_names], "create": [block_names]}
    blocks_per_file: dict[str, dict[str, list[str]]] = field(default_factory=dict)


def plan_v2_to_v3_migration(arch_dir: Path) -> MigrationPlan:
    """Inspect an Architecture/ tree; return what would change without modifying."""
    plan = MigrationPlan()
    if not arch_dir.is_dir():
        return plan
    # Walk Architecture/*.md and Architecture/modules/*.md
    candidates = list(arch_dir.glob("*.md")) + list((arch_dir / "modules").glob("*.md"))
    for f in sorted(candidates):
        rel = str(f.relative_to(arch_dir))
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        drop = []
        for m in _GENERATED_RE.finditer(text):
            block_name = m.group(2)
            if block_name in V2_GENERATED_BLOCKS_TO_DROP:
                drop.append(block_name)
        keep = list(set(_USER_NAME_RE.findall(text)))
        if not drop and not keep:
            continue
        plan.files_to_modify.append(rel)
        # Determine v3 blocks to create per file type.
        if rel.startswith("modules/"):
            create = sorted(V3_MODULE_BLOCKS)
        else:
            # For overview / features / etc. the relevant blocks differ;
            # the command body inserts them. Here we just declare intent.
            create = ["scope", "strengths", "weaknesses", "improvements"]
        plan.blocks_per_file[rel] = {
            "drop": sorted(drop),
            "keep": sorted(keep),
            "create": create,
        }
    return plan


def apply_v2_to_v3_migration(arch_dir: Path, plan: MigrationPlan, dry_run: bool = False) -> None:
    """Drop v2 @generated blocks (and their preceding H2 heading) in place.

    Leaves @user blocks and unrelated content untouched. Caller is responsible
    for backup (call `backup_architecture_dir` first if desired).
    """
    if dry_run:
        return
    for rel in plan.files_to_modify:
        path = arch_dir / rel
        text = path.read_text(encoding="utf-8")
        new_text = _GENERATED_RE.sub(_drop_if_v2, text)
        # Collapse 3+ consecutive blank lines to 2 for tidiness.
        new_text = re.sub(r"\n{3,}", "\n\n", new_text)
        path.write_text(new_text, encoding="utf-8")


def _drop_if_v2(m: re.Match) -> str:
    """Replacement callback for `_GENERATED_RE`. Drops the match if its block
    name is in V2_GENERATED_BLOCKS_TO_DROP, otherwise leaves the original
    text untouched."""
    block_name = m.group(2)
    if block_name in V2_GENERATED_BLOCKS_TO_DROP:
        return ""
    return m.group(0)


def backup_architecture_dir(arch_dir: Path, archive_root: Path | None = None) -> Path:
    """Tar.gz the entire Architecture/ tree to a timestamped path.

    Default archive_root is `<arch_dir>/.._archive/`. Returns the archive path.
    """
    if archive_root is None:
        archive_root = arch_dir.parent / "_archive"
    archive_root.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    archive = archive_root / f"architecture-pre-v3-{ts}.tar.gz"
    with tarfile.open(archive, "w:gz") as tf:
        tf.add(arch_dir, arcname=arch_dir.name)
    return archive
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_migration.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/migration.py tests/architect/test_migration.py
git commit -m "feat(architect): v2->v3 migration helper (drop @generated, keep @user, tar.gz backup)"
```

---

## Phase B — Sections.py reframe (judgment frame)

### Task 3: Update `_BLOCK_NAMES` + `_BLOCK_HEADINGS` for module type (v3)

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test for v3 module block layout**

Append to `tests/architect/test_sections.py`:

```python
def test_module_v3_block_names_are_judgment_focused():
    """v3 drops what-it-does/how-it-works/key-files; adds scope/strengths/weaknesses/improvements."""
    from scripts.architect.sections import _BLOCK_NAMES
    assert "module" in _BLOCK_NAMES
    names = set(_BLOCK_NAMES["module"])
    assert {"scope", "strengths", "weaknesses", "improvements", "dependencies"} <= names
    assert "key-files" not in names
    assert "what-it-does" not in names


def test_module_block_headings_translate():
    """Each v3 module block must have a heading entry."""
    from scripts.architect.sections import _BLOCK_HEADINGS
    from scripts.architect.lang import heading
    for block in ("scope", "strengths", "weaknesses", "improvements", "dependencies"):
        h_en = _BLOCK_HEADINGS[block]
        assert heading(h_en, "zh-TW") != h_en, f"{block} heading {h_en!r} has no zh-TW mapping"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py::test_module_v3_block_names_are_judgment_focused tests/architect/test_sections.py::test_module_block_headings_translate -v`
Expected: FAIL — `_BLOCK_NAMES["module"]` missing OR contains v2 names.

- [ ] **Step 3: Update `_BLOCK_NAMES` in `scripts/architect/sections.py`**

Open `scripts/architect/sections.py`. Replace the `_BLOCK_NAMES` dict to add `module` key (a separate type from narrative sections) and update the values:

```python
_BLOCK_NAMES = {
    "api-surface": ("summary", "interface-overview", "env-overview"),
    "features": ("summary", "capability-scope", "strengths", "weaknesses", "improvements"),
    "decisions": ("summary", "stack-rationale", "detected-adrs", "pattern-decisions",
                  "commit-message-decisions", "promote-to-adr"),
    "roadmap": ("summary", "near-term", "trajectory", "todo-clusters", "signals-reviewed"),
    "future": ("summary", "known-limitations", "improvements"),
    # v3 module-type — judgment-driven, no file recital.
    "module": ("scope", "strengths", "weaknesses", "improvements", "dependencies"),
    # v3 product-eye new types
    "personas": ("summary", "personas-list"),
    "jobs": ("summary", "jobs-list"),
    "flows": ("summary", "flows-list"),
}
```

Update `_BLOCK_HEADINGS` — add new entries:

```python
_BLOCK_HEADINGS = {
    "summary": "## Summary",
    # api-surface (v3 — high-level, not full table)
    "interface-overview": "## Interface overview",
    "env-overview": "## Environment variables overview",
    # features (v3)
    "capability-scope": "## Capability scope",
    # decisions (unchanged)
    "stack-rationale": "## Stack rationale",
    "detected-adrs": "## Detected ADRs",
    "pattern-decisions": "## Pattern decisions",
    "commit-message-decisions": "## Commit-message decisions",
    "promote-to-adr": "## Promote to ADR",
    # roadmap (unchanged)
    "near-term": "## Near term",
    "trajectory": "## Trajectory",
    "todo-clusters": "## TODO clusters",
    "signals-reviewed": "## Signals reviewed",
    # future (v3 — drops gap-analysis & aspirational-ideas; uses improvements)
    "known-limitations": "## Known limitations",
    # v3 module judgment
    "scope": "## Module responsibility",
    "strengths": "## Design strengths",
    "weaknesses": "## Design weaknesses",
    "improvements": "## Improvement opportunities",
    "dependencies": "## Dependencies and consumers",
    # product-eye
    "personas-list": "## Personas",
    "jobs-list": "## Jobs to be done",
    "flows-list": "## Flows",
}
```

Also add the heading map entries to `lang.py` if not already there. `## Dependencies and consumers` is new, so:

Open `scripts/architect/lang.py`, append to HEADING_MAP:

```python
    "## Dependencies and consumers": {"en": "## Dependencies and consumers", "zh-TW": "## 相依與被誰使用"},
    "## Interface overview": {"en": "## Interface overview", "zh-TW": "## 介面類型概觀"},
    "## Environment variables overview": {"en": "## Environment variables overview", "zh-TW": "## 環境變數概觀"},
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_sections.py::test_module_v3_block_names_are_judgment_focused tests/architect/test_sections.py::test_module_block_headings_translate -v`
Expected: PASS.

- [ ] **Step 5: Run full sections test suite**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS (existing tests use `_BLOCK_NAMES["features"]` etc.; we shouldn't have broken anything since those entries still exist — but if any test references `_BLOCK_NAMES["api-surface"]` with old names like `cli-commands`, that test will fail. **If a pre-existing test fails because the api-surface block names changed, update the test to use the new names.** Tests for the new module/personas/jobs/flows types are in later tasks.)

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py scripts/architect/lang.py tests/architect/test_sections.py
git commit -m "feat(architect): v3 _BLOCK_NAMES with judgment frame for module + product-eye types"
```

---

### Task 4: Update prompt builders — critique frame + Evidence requirement

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing tests for v3 critique prompts**

Append to `tests/architect/test_sections.py`:

```python
def test_module_prompt_demands_judgment_not_description():
    """v3 module prompt must NOT ask for file lists; MUST ask for strengths/weaknesses/improvements."""
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend",
        repomix_packed="(packed code goes here)",
        agents_md_excerpt="(AGENTS.md excerpt)",
        output_lang="zh-TW",
    )
    # Must not ask for file listings
    assert "key files" not in prompt.lower()
    assert "list of files" not in prompt.lower()
    # Must ask for judgment blocks
    assert "strengths" in prompt
    assert "weaknesses" in prompt
    assert "improvement" in prompt.lower()
    # Each Imp must demand Evidence
    assert "evidence" in prompt.lower() or "Evidence" in prompt
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt


def test_module_prompt_en_no_chinese_directive():
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend",
        repomix_packed="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "繁體中文" not in prompt
    assert "Evidence" in prompt or "evidence" in prompt


def test_module_prompt_demands_evidence_required_for_each_improvement():
    from scripts.architect.sections import build_module_prompt
    prompt = build_module_prompt(
        module_slug="backend", repomix_packed="", agents_md_excerpt="", output_lang="en",
    )
    # Prompt must say: if you can't cite evidence, don't include that improvement.
    assert "do not" in prompt.lower() or "skip" in prompt.lower() or "drop" in prompt.lower()
    # And mention the required Imp fields explicitly.
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt, f"missing required Imp field {field!r}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py::test_module_prompt_demands_judgment_not_description tests/architect/test_sections.py::test_module_prompt_en_no_chinese_directive tests/architect/test_sections.py::test_module_prompt_demands_evidence_required_for_each_improvement -v`
Expected: FAIL — `build_module_prompt` not defined.

- [ ] **Step 3: Add `build_module_prompt` to `scripts/architect/sections.py`**

Append to `scripts/architect/sections.py`:

```python


def build_module_prompt(
    *,
    module_slug: str,
    repomix_packed: str,
    agents_md_excerpt: str,
    output_lang: str,
) -> str:
    """v3 — judgment-driven module synthesis prompt.

    NO file listing. The agent demands strengths / weaknesses / improvements,
    each grounded in Evidence (commit, decision wikilink, code path:line).
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 scope/strengths/weaknesses/improvements 段散文。"
            "Code identifier (檔名、function/class、env var、wikilink 內檔名段) "
            "保持英文。Evidence 中可包含 `path:line` inline 引用。"
        )
    else:
        lang_directive = (
            "Write scope/strengths/weaknesses/improvements prose in English. "
            "Code identifiers stay English. Evidence may include `path:line` inline citations."
        )

    return "\n".join([
        f"You are writing the architecture *judgment* document for module `{module_slug}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. DO NOT list files. The codebase is the source of truth — vault notes "
        "   capture judgment that the codebase does NOT record (design tradeoffs, risks, "
        "   improvement opportunities).",
        "2. DO NOT generate 'how it works' style transcription. If a reader needs that, "
        "   they read the code.",
        "3. EVERY improvement must cite Evidence. If you cannot cite Evidence for an idea, "
        "   DO NOT include that improvement — drop it. We refuse speculative roadmap items.",
        "",
        "## Output: produce 5 @generated blocks (JSON keys)",
        "- `scope` — 1–2 paragraphs: what is this module's responsibility, its boundary, "
        "  how it earns its place. May include a small Mermaid diagram if a flow matters.",
        "- `strengths` — 3–5 bullets, each ≤ 2 sentences, each with concrete Evidence "
        "  (commit SHA, ADR wikilink, AGENTS.md section, or `path:line`).",
        "- `weaknesses` — 3–5 bullets, each with concrete impact ('peak-load latency spikes "
        "  because event consumer shares the API process' — not 'could be better').",
        "- `improvements` — 2–4 improvement opportunities. Each MUST contain all five fields:",
        "    - **Why:** what problem it solves",
        "    - **Evidence:** wikilink or `path:line` showing the pain is real",
        "    - **Effort:** one of S | M | L | XL",
        "    - **Risk if not done:** concrete consequence",
        "    - **Confidence:** stated | high | medium | speculation",
        "  Omit Imps you cannot fully fill in — quality over quantity.",
        "- `dependencies` — wikilinks only (e.g. `[[modules/services]]`, `[[Architecture/decisions]]`). "
        "  NO file paths.",
        "",
        "Return strict JSON: {\"scope\": \"...\", \"strengths\": \"...\", \"weaknesses\": \"...\", "
        "\"improvements\": \"...\", \"dependencies\": \"...\"}.",
        "",
        "## Module context (repomix packed)",
        repomix_packed[:50000],  # cap to avoid blowing the prompt
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
    ])
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v 2>&1 | tail -25`
Expected: the 3 new tests PASS. (Other tests should still pass.)

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): build_module_prompt with judgment frame + Evidence-required rule"
```

---

### Task 5: Improvement block renderer + parser

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

The LLM returns each improvements block as a single markdown string. The downstream `/obsidian-roadmap` needs to parse individual Imp items back into structured data. Define a strict serializer + parser pair so the formatting is round-trip-stable.

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_sections.py`:

```python
def test_render_improvement_block_uses_strict_h3_format():
    from scripts.architect.sections import render_improvements_block, ImprovementItem
    items = [
        ImprovementItem(
            title="Extract EventConsumer to separate worker container",
            why="API process shares CPU with event loop; peak traffic blocks request handling.",
            evidence=["[[Architecture/decisions#Event routing principle]]",
                      "`backend/main.py:120`"],
            effort="M",
            risk_if_not_done="During campaigns LINE webhook backlog grows; admin UI lags.",
            confidence="medium",
        ),
    ]
    rendered = render_improvements_block(items, lang="en")
    assert "### Imp 1: Extract EventConsumer to separate worker container" in rendered
    assert "- **Why:** API process shares CPU" in rendered
    assert "- **Evidence:**" in rendered
    assert "[[Architecture/decisions#Event routing principle]]" in rendered
    assert "`backend/main.py:120`" in rendered
    assert "- **Effort:** M" in rendered
    assert "- **Risk if not done:**" in rendered
    assert "- **Confidence:** medium" in rendered


def test_render_improvement_block_zh_tw():
    from scripts.architect.sections import render_improvements_block, ImprovementItem
    items = [
        ImprovementItem(
            title="拆 EventConsumer 為獨立 worker",
            why="API 跟 EventConsumer 共用 process",
            evidence=["[[Architecture/decisions]]"],
            effort="M",
            risk_if_not_done="流量峰值 API 飆延遲",
            confidence="medium",
        ),
    ]
    rendered = render_improvements_block(items, lang="zh-TW")
    assert "### Imp 1: 拆 EventConsumer 為獨立 worker" in rendered
    assert "**為什麼:**" in rendered
    assert "**證據:**" in rendered
    assert "**Effort:** M" in rendered
    assert "**未做的風險:**" in rendered
    assert "**Confidence:** medium" in rendered


def test_parse_improvements_block_round_trips_render():
    from scripts.architect.sections import (
        render_improvements_block, parse_improvements_block, ImprovementItem,
    )
    items = [
        ImprovementItem(
            title="A",
            why="Because.",
            evidence=["[[X]]", "`y.py:1`"],
            effort="S",
            risk_if_not_done="Bad.",
            confidence="high",
        ),
        ImprovementItem(
            title="B",
            why="Why B.",
            evidence=["[[Z]]"],
            effort="L",
            risk_if_not_done="Worse.",
            confidence="speculation",
        ),
    ]
    rendered = render_improvements_block(items, lang="en")
    parsed = parse_improvements_block(rendered)
    assert len(parsed) == 2
    assert parsed[0].title == "A"
    assert parsed[0].effort == "S"
    assert parsed[0].evidence == ["[[X]]", "`y.py:1`"]
    assert parsed[1].title == "B"
    assert parsed[1].confidence == "speculation"


def test_parse_improvements_block_zh_tw_labels():
    from scripts.architect.sections import parse_improvements_block
    text = (
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** API 跟 EventConsumer 共用 process\n"
        "- **證據:** [[Architecture/decisions]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 流量峰值 API 飆延遲\n"
        "- **Confidence:** medium\n"
    )
    items = parse_improvements_block(text)
    assert len(items) == 1
    assert items[0].title == "拆 EventConsumer 為獨立 worker"
    assert items[0].effort == "M"
    assert items[0].confidence == "medium"


def test_parse_improvements_block_skips_malformed():
    """An Imp with fewer than 5 required fields is dropped, not partially parsed."""
    from scripts.architect.sections import parse_improvements_block
    text = (
        "### Imp 1: Good one\n"
        "- **Why:** w\n"
        "- **Evidence:** [[E]]\n"
        "- **Effort:** S\n"
        "- **Risk if not done:** r\n"
        "- **Confidence:** high\n"
        "\n"
        "### Imp 2: Missing fields\n"
        "- **Why:** only this\n"
    )
    items = parse_improvements_block(text)
    assert len(items) == 1
    assert items[0].title == "Good one"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v -k "improvement" 2>&1 | tail -30`
Expected: FAIL — `ImprovementItem` / `render_improvements_block` / `parse_improvements_block` not defined.

- [ ] **Step 3: Append `ImprovementItem` dataclass + renderer + parser to `scripts/architect/sections.py`**

```python


@dataclass
class ImprovementItem:
    title: str
    why: str
    evidence: list[str]
    effort: str               # S | M | L | XL
    risk_if_not_done: str
    confidence: str           # stated | high | medium | speculation


_FIELD_LABELS = {
    "en": {
        "Why": "Why",
        "Evidence": "Evidence",
        "Effort": "Effort",
        "Risk if not done": "Risk if not done",
        "Confidence": "Confidence",
    },
    "zh-TW": {
        "Why": "為什麼",
        "Evidence": "證據",
        "Effort": "Effort",
        "Risk if not done": "未做的風險",
        "Confidence": "Confidence",
    },
}


def render_improvements_block(items: list[ImprovementItem], lang: str = "en") -> str:
    """Render a list of ImprovementItem into the canonical markdown shape.

    Format is strict (see _IMP_RE for the inverse parser):
      ### Imp <n>: <title>
      - **Why:** <prose>
      - **Evidence:** <link1> | <link2>
      - **Effort:** S|M|L|XL
      - **Risk if not done:** <prose>
      - **Confidence:** stated|high|medium|speculation
    """
    labels = _FIELD_LABELS.get(lang, _FIELD_LABELS["en"])
    lines: list[str] = []
    for i, it in enumerate(items, 1):
        lines.append(f"### Imp {i}: {it.title}")
        lines.append(f"- **{labels['Why']}:** {it.why}")
        evidence_str = " | ".join(it.evidence) if it.evidence else "(none)"
        lines.append(f"- **{labels['Evidence']}:** {evidence_str}")
        lines.append(f"- **{labels['Effort']}:** {it.effort}")
        lines.append(f"- **{labels['Risk if not done']}:** {it.risk_if_not_done}")
        lines.append(f"- **{labels['Confidence']}:** {it.confidence}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


# Title line.
_IMP_TITLE_RE = re.compile(r"^###\s+Imp\s+\d+:\s+(.+?)\s*$", re.MULTILINE)
# Generic bold-prefix bullet:  - **Label:** Body
_IMP_BULLET_RE = re.compile(r"^-\s+\*\*([^*]+?):\*\*\s*(.+?)\s*$", re.MULTILINE)


def parse_improvements_block(text: str) -> list[ImprovementItem]:
    """Parse a markdown improvements block back into ImprovementItem list.

    Tolerant of zh-TW or en labels. An Imp missing any of the 5 required
    fields is silently dropped (we refuse partial roadmap candidates).
    """
    items: list[ImprovementItem] = []
    # Split text by Imp title boundaries.
    parts = _IMP_TITLE_RE.split(text)
    # _IMP_TITLE_RE.split returns: [before_first, title1, body1, title2, body2, ...]
    if len(parts) < 3:
        return []
    for i in range(1, len(parts), 2):
        title = parts[i].strip()
        body = parts[i + 1] if i + 1 < len(parts) else ""
        fields: dict[str, str] = {}
        for m in _IMP_BULLET_RE.finditer(body):
            label_raw = m.group(1).strip()
            value = m.group(2).strip()
            canonical = _canonicalize_field_label(label_raw)
            if canonical:
                fields[canonical] = value
        required = {"Why", "Evidence", "Effort", "Risk if not done", "Confidence"}
        if not required.issubset(fields.keys()):
            continue
        evidence = [e.strip() for e in fields["Evidence"].split("|") if e.strip()]
        items.append(ImprovementItem(
            title=title,
            why=fields["Why"],
            evidence=evidence,
            effort=fields["Effort"],
            risk_if_not_done=fields["Risk if not done"],
            confidence=fields["Confidence"],
        ))
    return items


_LABEL_ALIASES = {
    # Canonical key -> aliases in either language
    "Why": {"why", "為什麼"},
    "Evidence": {"evidence", "證據"},
    "Effort": {"effort"},
    "Risk if not done": {"risk if not done", "未做的風險", "risk"},
    "Confidence": {"confidence"},
}


def _canonicalize_field_label(label_raw: str) -> str | None:
    needle = label_raw.lower()
    for canonical, aliases in _LABEL_ALIASES.items():
        if needle in {a.lower() for a in aliases}:
            return canonical
    return None
```

Note: `re` is already imported at the top of `sections.py`. If not, add `import re`.

- [ ] **Step 4: Run improvement tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "improvement" 2>&1 | tail -15`
Expected: PASS (5 tests).

- [ ] **Step 5: Run full sections tests**

Run: `uv run pytest tests/architect/test_sections.py -q 2>&1 | tail -5`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): ImprovementItem + strict render/parse round-trip"
```

---

## Phase C — Product-eye new types

### Task 6: personas signal collector + prompt + composer

**Files:**
- Create: `scripts/architect/personas.py`
- Create: `tests/architect/test_personas.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_personas.py`:

```python
from pathlib import Path

from scripts.architect.personas import (
    Persona,
    collect_persona_signal,
    build_personas_prompt,
    render_personas_section,
)


def test_collect_persona_signal_prefers_readme_explicit_section(tmp_path: Path):
    """If README has '## Personas' or '## 使用者型態', use it as the canonical source."""
    (tmp_path / "README.md").write_text(
        "## Personas\n\n- Admin: 後台主管\n- Agent: 客服第一線\n\n## Other\nfoo\n"
    )
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "Admin" in sig.raw_text or "後台主管" in sig.raw_text


def test_collect_persona_signal_zh_tw_alias(tmp_path: Path):
    """`## 使用者型態` is treated as the same section."""
    (tmp_path / "README.md").write_text("## 使用者型態\n\n- 客服管理員\n- LINE 終端使用者\n")
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_persona_signal_falls_back_to_inferred(tmp_path: Path):
    """No explicit section -> has_explicit_section is False; raw_text empty."""
    (tmp_path / "README.md").write_text("# Project\n\nDoes things.\n")
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is False
    assert sig.raw_text == ""


def test_collect_persona_signal_missing_readme(tmp_path: Path):
    sig = collect_persona_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_personas_prompt_demands_structured_output_zh_tw():
    prompt = build_personas_prompt(
        project="myproj",
        readme_excerpt="(no personas section)",
        agents_md_excerpt="Admin uses /admin endpoints.",
        features_summary="Provides admin dashboard, chat workspace.",
        output_lang="zh-TW",
    )
    assert "myproj" in prompt
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Demands the schema fields.
    for field in ("誰", "目標", "觸點", "頻率", "主要痛點"):
        assert field in prompt, f"missing required persona field {field!r}"


def test_render_personas_section_outputs_h2_then_h3_per_persona():
    personas = [
        Persona(slug="admin",
                title="後台管理員 (Admin Manager)",
                who="後台主管,監督客服團隊",
                goals=["看整體 ticket 健康度", "調度 agent"],
                touchpoints=["/admin/dashboard", "/admin/metrics"],
                frequency="每天",
                pain_points=["沒有 SLA 警示", "無法批次 reassign ticket"],
                confidence="stated"),
        Persona(slug="agent",
                title="客服 agent",
                who="客服第一線",
                goals=["回覆 ticket"],
                touchpoints=["/chat/workspace"],
                frequency="每天",
                pain_points=["Customer history 不易展開"],
                confidence="medium"),
    ]
    rendered = render_personas_section(personas, lang="zh-TW")
    assert "### 後台管理員 (Admin Manager)" in rendered
    assert "**誰:** 後台主管" in rendered
    assert "**目標:**" in rendered
    assert "/admin/dashboard" in rendered
    assert "**主要痛點:**" in rendered
    assert "_confidence: stated_" in rendered or "stated" in rendered
    # Second persona present
    assert "### 客服 agent" in rendered
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_personas.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/architect/personas.py`**

```python
"""Personas signal collector + prompt builder + section renderer.

Source priority: explicit README '## Personas' / '## 使用者型態' section first;
otherwise LLM inference (handled by the agent via `build_personas_prompt`).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# H2 aliases that count as a personas section.
_PERSONA_ALIASES = (
    "personas", "user types", "user roles", "使用者型態", "使用者角色",
)


@dataclass
class PersonaSignal:
    has_explicit_section: bool
    raw_text: str             # markdown body under the matched H2, stripped


@dataclass
class Persona:
    slug: str
    title: str
    who: str
    goals: list[str]
    touchpoints: list[str]
    frequency: str
    pain_points: list[str]
    confidence: str = "medium"   # stated | high | medium | speculation


def collect_persona_signal(repo_root: Path) -> PersonaSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return PersonaSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return PersonaSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _PERSONA_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip()
        return PersonaSignal(has_explicit_section=True, raw_text=body)
    return PersonaSignal(has_explicit_section=False, raw_text="")


def build_personas_prompt(
    *,
    project: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    features_summary: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 title / who / goals / pain_points 等散文。"
            "Touchpoints (endpoint 路徑、CLI 命令) 保持英文。"
        )
        schema_fields = ("誰", "目標", "觸點", "頻率", "主要痛點")
    else:
        lang_directive = (
            "Write title / who / goals / pain_points in English. "
            "Touchpoints (endpoint paths, CLI commands) stay verbatim."
        )
        schema_fields = ("Who", "Goals", "Touchpoints", "Frequency", "Pain points")

    return "\n".join([
        f"You are documenting the personas for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- Return 2–5 personas — the people who interact with this product.",
        "- For each persona, fill ALL the following fields: " + ", ".join(schema_fields) + ".",
        "- Touchpoints must be concrete (endpoint paths / pages / events), not vague labels.",
        "- Mark `confidence` as `stated` if you cite README/AGENTS.md, `medium` if you inferred.",
        "",
        "Return strict JSON: a list of personas, each with keys "
        "`slug, title, who, goals (list), touchpoints (list), frequency, pain_points (list), confidence`.",
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
        "",
        "## features.md summary",
        features_summary[:3000],
    ])


_FIELD_LABELS = {
    "en": {
        "who": "Who",
        "goals": "Goals",
        "touchpoints": "Touchpoints",
        "frequency": "Frequency",
        "pain": "Pain points",
    },
    "zh-TW": {
        "who": "誰",
        "goals": "目標",
        "touchpoints": "觸點",
        "frequency": "頻率",
        "pain": "主要痛點",
    },
}


def render_personas_section(personas: list[Persona], lang: str = "en") -> str:
    """Render personas as H3-per-persona markdown."""
    labels = _FIELD_LABELS.get(lang, _FIELD_LABELS["en"])
    out: list[str] = []
    for p in personas:
        out.append(f"### {p.title}")
        out.append(f"- **{labels['who']}:** {p.who}")
        if p.goals:
            out.append(f"- **{labels['goals']}:**")
            for g in p.goals:
                out.append(f"  - {g}")
        if p.touchpoints:
            out.append(f"- **{labels['touchpoints']}:** {', '.join(p.touchpoints)}")
        if p.frequency:
            out.append(f"- **{labels['frequency']}:** {p.frequency}")
        if p.pain_points:
            out.append(f"- **{labels['pain']}:**")
            for pp in p.pain_points:
                out.append(f"  - {pp}")
        out.append(f"- _confidence: {p.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_personas.py -v`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/personas.py tests/architect/test_personas.py
git commit -m "feat(architect): personas signal collector + prompt + section renderer"
```

---

### Task 7: jobs signal collector + prompt + composer

**Files:**
- Create: `scripts/architect/jobs.py`
- Create: `tests/architect/test_jobs.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_jobs.py`:

```python
from pathlib import Path

from scripts.architect.jobs import (
    Job,
    collect_job_signal,
    build_jobs_prompt,
    render_jobs_section,
)


def test_collect_job_signal_finds_jtbd_section(tmp_path: Path):
    (tmp_path / "README.md").write_text(
        "## Jobs to be done\n\n"
        "- When admin sees a complaint, they want to triage quickly.\n"
        "- When agent receives a ticket, they want full context.\n"
    )
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "triage" in sig.raw_text


def test_collect_job_signal_zh_alias(tmp_path: Path):
    (tmp_path / "README.md").write_text("## 使用者工作\n\n- Foo\n")
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_job_signal_no_section(tmp_path: Path):
    (tmp_path / "README.md").write_text("# Project\n")
    sig = collect_job_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_jobs_prompt_includes_persona_context_and_demands_maturity():
    prompt = build_jobs_prompt(
        project="myproj",
        personas_summary="Admin, Agent",
        features_summary="Admin dashboard.",
        readme_excerpt="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "myproj" in prompt
    assert "Admin" in prompt
    # Each job MUST declare maturity.
    assert "maturity" in prompt.lower()
    assert "Alpha" in prompt and "Beta" in prompt and "GA" in prompt
    # Friction points required.
    assert "friction" in prompt.lower()


def test_render_jobs_section_groups_by_persona():
    jobs = [
        Job(slug="triage-complaint",
            persona="客服管理員",
            jtbd="當客戶投訴,管理員想快速分派處理",
            maturity="Beta",
            friction_points=["缺 priority 標籤", "無 SLA timer"],
            related_features=["[[features#Admin Dashboard]]"],
            related_flows=["[[flows#Ticket Handling]]"],
            confidence="medium"),
        Job(slug="answer-ticket",
            persona="客服 agent",
            jtbd="當收到 ticket,agent 想看完整 context 後回覆",
            maturity="GA",
            friction_points=["Customer history 展開要兩步"],
            related_features=["[[features#Conversation Workspace]]"],
            related_flows=["[[flows#Ticket Handling]]"],
            confidence="stated"),
    ]
    rendered = render_jobs_section(jobs, lang="zh-TW")
    # Persona acts as visual grouping.
    assert "**Persona:** 客服管理員" in rendered or "**使用者:** 客服管理員" in rendered
    assert "**JTBD:**" in rendered or "**目標:**" in rendered
    # Maturity label visible.
    assert "Beta" in rendered
    assert "GA" in rendered
    # Friction points list.
    assert "缺 priority 標籤" in rendered


def test_render_jobs_section_en():
    jobs = [Job(slug="x", persona="Admin", jtbd="Do X", maturity="Alpha",
                friction_points=["a"], related_features=[], related_flows=[],
                confidence="speculation")]
    rendered = render_jobs_section(jobs, lang="en")
    assert "**Persona:** Admin" in rendered
    assert "**JTBD:** Do X" in rendered
    assert "Alpha" in rendered
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_jobs.py -v`
Expected: FAIL.

- [ ] **Step 3: Implement `scripts/architect/jobs.py`**

```python
"""Jobs-to-be-done signal collector + prompt + section renderer."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_JOB_ALIASES = (
    "jobs to be done", "jtbd", "user jobs", "使用者工作", "工作清單",
)


@dataclass
class JobSignal:
    has_explicit_section: bool
    raw_text: str


@dataclass
class Job:
    slug: str
    persona: str              # persona title (free-text)
    jtbd: str                 # "When X, the user wants Y so that Z"
    maturity: str             # Alpha | Beta | GA
    friction_points: list[str]
    related_features: list[str]
    related_flows: list[str]
    confidence: str = "medium"


def collect_job_signal(repo_root: Path) -> JobSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return JobSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return JobSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _JOB_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        return JobSignal(has_explicit_section=True, raw_text=text[body_start:body_end].strip())
    return JobSignal(has_explicit_section=False, raw_text="")


def build_jobs_prompt(
    *,
    project: str,
    personas_summary: str,
    features_summary: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 JTBD 與 friction_points 散文。"
            "Slug、related_features 中的 anchor、persona 標題保持英文或既有命名。"
        )
    else:
        lang_directive = (
            "Write JTBD and friction_points in English. Slugs stay ascii-lowercase-hyphen."
        )

    return "\n".join([
        f"You are documenting Jobs-to-be-done (JTBD) for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- 3–6 jobs covering the main user journeys.",
        "- Each job belongs to one of the personas listed below.",
        "- JTBD format: 'When <context>, the user wants <outcome> so that <reason>'.",
        "- Each job MUST declare `maturity` as one of: `Alpha` (partial / behind flag), "
        "`Beta` (works but rough), `GA` (fully delivered).",
        "- Each job lists 1–4 concrete `friction_points` (specific things that suck today).",
        "- `related_features` / `related_flows` are wikilinks like `[[features#Section]]`.",
        "- `confidence`: `stated` if README/AGENTS.md spells out, else `medium` or `speculation`.",
        "",
        "Return strict JSON: a list of jobs.",
        "",
        "## Personas available",
        personas_summary[:3000],
        "",
        "## Features summary",
        features_summary[:3000],
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
    ])


def render_jobs_section(jobs: list[Job], lang: str = "en") -> str:
    out: list[str] = []
    for j in jobs:
        out.append(f"### {j.jtbd}" if lang == "en" else f"### {j.jtbd}")
        out.append(f"- **Persona:** {j.persona}")
        out.append(f"- **JTBD:** {j.jtbd}")
        out.append(f"- **Maturity:** {j.maturity}")
        if j.friction_points:
            fp_label = "Friction" if lang == "en" else "摩擦點"
            out.append(f"- **{fp_label}:**")
            for fp in j.friction_points:
                out.append(f"  - {fp}")
        if j.related_features:
            out.append(f"- **Related features:** {', '.join(j.related_features)}")
        if j.related_flows:
            out.append(f"- **Related flows:** {', '.join(j.related_flows)}")
        out.append(f"- _confidence: {j.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_jobs.py -v`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/jobs.py tests/architect/test_jobs.py
git commit -m "feat(architect): jobs (JTBD) signal collector + prompt + renderer"
```

---

### Task 8: flows signal collector + prompt + composer

**Files:**
- Create: `scripts/architect/flows.py`
- Create: `tests/architect/test_flows.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_flows.py`:

```python
from pathlib import Path

from scripts.architect.flows import (
    Flow,
    collect_flow_signal,
    build_flows_prompt,
    render_flows_section,
)


def test_collect_flow_signal_finds_user_flows_section(tmp_path: Path):
    (tmp_path / "README.md").write_text(
        "## User flows\n\n1. LINE message arrives -> webhook -> queue -> agent UI\n"
    )
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is True
    assert "LINE" in sig.raw_text


def test_collect_flow_signal_zh_alias(tmp_path: Path):
    (tmp_path / "README.md").write_text("## 使用路徑\n\n- A -> B -> C\n")
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is True


def test_collect_flow_signal_no_match(tmp_path: Path):
    (tmp_path / "README.md").write_text("# x")
    sig = collect_flow_signal(tmp_path)
    assert sig.has_explicit_section is False


def test_build_flows_prompt_demands_friction_assessment():
    prompt = build_flows_prompt(
        project="myproj",
        personas_summary="Admin, Agent",
        api_surface_summary="115 routes, 8 main groups.",
        readme_excerpt="",
        agents_md_excerpt="",
        output_lang="en",
    )
    assert "myproj" in prompt
    # Each flow must include a Mermaid block and friction assessment.
    assert "mermaid" in prompt.lower()
    assert "friction" in prompt.lower()


def test_render_flows_section_with_mermaid():
    flows = [
        Flow(slug="ticket-handling",
             title="客服 ticket 處理",
             personas=["客服 agent", "客服管理員"],
             steps_mermaid="sequenceDiagram\n  participant U as User\n  U->>L: msg",
             friction_assessment=["webhook->queue 速度 OK", "agent UI 無 typing indicator"],
             maturity="GA",
             related_modules=["[[modules/backend]]", "[[modules/frontend]]"],
             confidence="stated"),
    ]
    rendered = render_flows_section(flows, lang="zh-TW")
    assert "### 客服 ticket 處理" in rendered
    assert "```mermaid" in rendered
    assert "sequenceDiagram" in rendered
    assert "agent UI 無 typing indicator" in rendered
    assert "**Maturity:** GA" in rendered
    assert "[[modules/backend]]" in rendered
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_flows.py -v`
Expected: FAIL.

- [ ] **Step 3: Implement `scripts/architect/flows.py`**

```python
"""User flows signal collector + prompt + section renderer."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_FLOW_ALIASES = (
    "user flows", "user journeys", "使用路徑", "使用流程", "user flow",
)


@dataclass
class FlowSignal:
    has_explicit_section: bool
    raw_text: str


@dataclass
class Flow:
    slug: str
    title: str
    personas: list[str]
    steps_mermaid: str        # raw mermaid body (without ```mermaid fences)
    friction_assessment: list[str]
    maturity: str             # Alpha | Beta | GA
    related_modules: list[str]
    confidence: str = "medium"


def collect_flow_signal(repo_root: Path) -> FlowSignal:
    readme = repo_root / "README.md"
    if not readme.is_file():
        return FlowSignal(has_explicit_section=False, raw_text="")
    try:
        text = readme.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return FlowSignal(has_explicit_section=False, raw_text="")
    h2_re = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
    matches = list(h2_re.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        if title not in _FLOW_ALIASES:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        return FlowSignal(has_explicit_section=True, raw_text=text[body_start:body_end].strip())
    return FlowSignal(has_explicit_section=False, raw_text="")


def build_flows_prompt(
    *,
    project: str,
    personas_summary: str,
    api_surface_summary: str,
    readme_excerpt: str,
    agents_md_excerpt: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫 title / friction_assessment 散文。"
            "Mermaid 圖內的 actor 名稱與 message 字串依實際情境選用 (zh 或 en)。"
        )
    else:
        lang_directive = (
            "Write title / friction_assessment in English. Mermaid actor names "
            "match real-world labels (English unless the system uses other languages)."
        )

    return "\n".join([
        f"You are documenting end-to-end user flows for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Rules",
        "- 2–5 flows. Each is a *user-visible* path through the product, not a "
        "  data-pipeline diagram for engineers.",
        "- Each flow MUST include a `steps_mermaid` value — a `sequenceDiagram` body "
        "  showing the persona crossing the system. Keep it under 15 messages.",
        "- Each flow MUST list 2–5 `friction_assessment` items — concrete spots that "
        "  feel rough today, with a hint of the underlying mechanism.",
        "- Each flow declares `maturity` as `Alpha | Beta | GA`.",
        "- `related_modules` are wikilinks like `[[modules/backend]]`.",
        "- `confidence` is `stated` only if README spells out this flow.",
        "",
        "Return strict JSON: a list of flows.",
        "",
        "## Personas available",
        personas_summary[:3000],
        "",
        "## API surface summary",
        api_surface_summary[:3000],
        "",
        "## README excerpt",
        readme_excerpt[:5000],
        "",
        "## AGENTS.md excerpt",
        agents_md_excerpt[:5000],
    ])


def render_flows_section(flows: list[Flow], lang: str = "en") -> str:
    out: list[str] = []
    for f in flows:
        out.append(f"### {f.title}")
        if f.personas:
            persona_label = "Personas" if lang == "en" else "使用者"
            out.append(f"- **{persona_label}:** {', '.join(f.personas)}")
        out.append("")
        out.append("```mermaid")
        out.append(f.steps_mermaid.strip())
        out.append("```")
        out.append("")
        if f.friction_assessment:
            fric_label = "Friction" if lang == "en" else "摩擦點"
            out.append(f"- **{fric_label}:**")
            for fa in f.friction_assessment:
                out.append(f"  - {fa}")
        out.append(f"- **Maturity:** {f.maturity}")
        if f.related_modules:
            rm_label = "Related modules" if lang == "en" else "相關模組"
            out.append(f"- **{rm_label}:** {', '.join(f.related_modules)}")
        out.append(f"- _confidence: {f.confidence}_")
        out.append("")
    return "\n".join(out).rstrip() + "\n"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_flows.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/flows.py tests/architect/test_flows.py
git commit -m "feat(architect): flows signal collector + prompt + renderer with Mermaid"
```

---

## Phase D — api-surface reframe

### Task 9: api-surface — high-level overview, not exhaustive table

**Files:**
- Modify: `scripts/architect/api_surface_render.py`
- Modify: `tests/architect/test_api_surface_render.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_api_surface_render.py`:

```python
def test_render_interface_overview_groups_routes_by_prefix():
    """v3 — HTTP routes are bucketed by URL prefix, not listed one-by-one."""
    from scripts.architect.api_surface_render import render_interface_overview
    rows = [
        {"method": "GET", "path": "/auth/me", "handler": "me", "source": "src/api/auth.py:10"},
        {"method": "POST", "path": "/auth/login", "handler": "login", "source": "src/api/auth.py:20"},
        {"method": "GET", "path": "/admin/users", "handler": "list_users", "source": "src/api/admin.py:5"},
        {"method": "GET", "path": "/admin/metrics", "handler": "metrics", "source": "src/api/admin.py:15"},
        {"method": "POST", "path": "/chat/send", "handler": "send", "source": "src/api/chat.py:1"},
    ]
    overview = render_interface_overview(rows, lang="en")
    # Should mention total + grouping
    assert "5 routes" in overview or "Total: 5" in overview
    # Each prefix group cited as a bucket
    assert "/auth" in overview
    assert "/admin" in overview
    assert "/chat" in overview
    # Should NOT dump full table
    assert "list_users" not in overview or overview.count("/admin") < 5


def test_render_env_overview_groups_by_prefix():
    from scripts.architect.api_surface_render import render_env_overview
    rows = [
        {"name": "REDIS_HOST", "required": True, "default": None, "source": "x"},
        {"name": "REDIS_PORT", "required": True, "default": "6379", "source": "x"},
        {"name": "REDIS_PASSWORD", "required": False, "default": None, "source": "x"},
        {"name": "OPENAI_API_KEY", "required": True, "default": None, "source": "x"},
        {"name": "ADMIN_PASSWORD_HASH", "required": False, "default": None, "source": "x"},
    ]
    overview = render_env_overview(rows, lang="en")
    assert "5" in overview  # total count
    # Grouped by prefix (REDIS_*, OPENAI_*, ADMIN_*)
    assert "REDIS" in overview
    assert "OPENAI" in overview
    assert "ADMIN" in overview


def test_render_interface_overview_empty():
    from scripts.architect.api_surface_render import render_interface_overview
    assert render_interface_overview([], lang="en") == ""
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_api_surface_render.py -v -k "overview"`
Expected: FAIL — `render_interface_overview` / `render_env_overview` not defined.

- [ ] **Step 3: Add overview renderers to `scripts/architect/api_surface_render.py`**

Append to `scripts/architect/api_surface_render.py`:

```python


def render_interface_overview(http_rows: list[dict], lang: str = "en") -> str:
    """High-level HTTP route grouping by URL prefix.

    Returns a markdown summary (not the full table). Designed to live in
    api-surface.md under v3, where the exhaustive table moves out to scan-report.json.
    """
    if not http_rows:
        return ""
    # Bucket by first URL segment.
    buckets: dict[str, list[dict]] = {}
    for r in http_rows:
        path = r.get("path", "")
        first = path.lstrip("/").split("/")[0] or "(root)"
        buckets.setdefault(f"/{first}" if first != "(root)" else "/", []).append(r)

    n = len(http_rows)
    lines = [f"**{n} routes** grouped by URL prefix:"] if lang == "en" else [f"**{n} 條路由**,以 URL 前綴分組:"]
    for prefix in sorted(buckets):
        rows = buckets[prefix]
        methods = sorted({r.get("method", "") for r in rows})
        lines.append(f"- `{prefix}` — {len(rows)} routes, methods: {', '.join(methods)}")
    lines.append("")
    if lang == "en":
        lines.append("> Full route table lives in `/tmp/architect-<hash>/scan-report.json` "
                     "under `api_surface.http_routes`.")
    else:
        lines.append("> 完整路由表在 `/tmp/architect-<hash>/scan-report.json` 的 "
                     "`api_surface.http_routes`。")
    return "\n".join(lines)


def render_env_overview(env_rows: list[dict], lang: str = "en") -> str:
    """High-level env var grouping by name prefix."""
    if not env_rows:
        return ""
    buckets: dict[str, list[dict]] = {}
    for r in env_rows:
        name = r.get("name", "")
        prefix = name.split("_")[0] if "_" in name else name
        buckets.setdefault(prefix, []).append(r)

    n = len(env_rows)
    required_n = sum(1 for r in env_rows if r.get("required"))
    if lang == "en":
        lines = [f"**{n} variables** ({required_n} required), grouped by prefix:"]
    else:
        lines = [f"**{n} 個變數**({required_n} 個必填),以前綴分組:"]
    for prefix in sorted(buckets):
        rows = buckets[prefix]
        req = sum(1 for r in rows if r.get("required"))
        if lang == "en":
            lines.append(f"- `{prefix}_*` — {len(rows)} variables, {req} required")
        else:
            lines.append(f"- `{prefix}_*` — {len(rows)} 個,{req} 個必填")
    lines.append("")
    if lang == "en":
        lines.append("> Full env table lives in `/tmp/architect-<hash>/scan-report.json` "
                     "under `api_surface.env_vars`.")
    else:
        lines.append("> 完整環境變數表在 `/tmp/architect-<hash>/scan-report.json` 的 "
                     "`api_surface.env_vars`。")
    return "\n".join(lines)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_api_surface_render.py -v`
Expected: PASS (all old + 3 new tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/api_surface_render.py tests/architect/test_api_surface_render.py
git commit -m "feat(architect): api-surface overview renderers (prefix-grouped, not exhaustive)"
```

---

## Phase E — Roadmap integration

### Task 10: Extend `Candidate` dataclass with v3 fields

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_candidate_supports_v3_improvement_fields():
    from scripts.roadmap.candidates import Candidate
    c = Candidate(
        id="imp-x",
        title="Extract worker",
        source_wikilink="[[modules/backend#改進機會]]",
        source_line=0,
        kind="improvement",
        raw_text="full body",
        why="Because.",
        evidence=["[[a]]"],
        effort="M",
        risk_if_not_done="Bad.",
        confidence="medium",
    )
    assert c.why == "Because."
    assert c.effort == "M"
    assert c.confidence == "medium"


def test_candidate_v2_fields_still_work():
    """Existing v2 candidates without Imp metadata still construct fine."""
    from scripts.roadmap.candidates import Candidate
    c = Candidate(
        id="gap-x",
        title="A gap",
        source_wikilink="[[Architecture/future#落差分析]]",
        source_line=10,
        kind="gap",
        raw_text="...",
    )
    assert c.why is None
    assert c.effort is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py::test_candidate_supports_v3_improvement_fields tests/roadmap/test_candidates.py::test_candidate_v2_fields_still_work -v`
Expected: FAIL — extra kwargs rejected.

- [ ] **Step 3: Extend `Candidate` dataclass in `scripts/roadmap/candidates.py`**

Find the existing `@dataclass class Candidate:` definition and replace with:

```python
@dataclass
class Candidate:
    id: str
    title: str
    source_wikilink: str
    source_line: int
    kind: str
    raw_text: str
    # v3 additions (optional, populated when source is a structured Improvement).
    why: str | None = None
    evidence: list[str] = field(default_factory=list)
    effort: str | None = None
    risk_if_not_done: str | None = None
    confidence: str | None = None
```

Ensure `from dataclasses import dataclass, field` is at the top of the file.

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: PASS (all old + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "feat(roadmap): extend Candidate with optional v3 Improvement fields"
```

---

### Task 11: `detect_candidates` reads `## 改進機會` blocks from architect files

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_detect_candidates_reads_improvement_blocks_from_modules(tmp_path):
    """v3 — `## 改進機會` / `## Improvement opportunities` blocks in modules/*.md become candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    # A v3 module note with an improvement block.
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 拆 EventConsumer 為獨立 worker\n"
        "- **為什麼:** API process 與 event loop 共用\n"
        "- **證據:** [[Architecture/decisions#Event routing principle]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 流量峰值 API 延遲飆\n"
        "- **Confidence:** medium\n"
        "\n"
        "### Imp 2: 加 webhook signature verification\n"
        "- **為什麼:** 目前未驗證 LINE 來源\n"
        "- **證據:** `backend/main.py:80`\n"
        "- **Effort:** S\n"
        "- **未做的風險:** webhook 可被偽造\n"
        "- **Confidence:** stated\n"
    )
    # future.md still contributes via known-limitations (v3 keeps this section).
    (arch / "future.md").write_text(
        "## 已知限制\n"
        "- 沒有 SSO 整合 (stated)\n"
    )
    cands = detect_candidates(tmp_path)
    # 2 improvements from backend module + 1 limitation from future.md
    by_kind = {c.kind: [x for x in cands if x.kind == c.kind] for c in cands}
    imp_titles = [c.title for c in cands if c.kind == "improvement"]
    assert any("EventConsumer" in t for t in imp_titles)
    assert any("webhook signature" in t for t in imp_titles)
    # Improvement candidate carries Imp metadata.
    ec_cand = next(c for c in cands if c.kind == "improvement" and "EventConsumer" in c.title)
    assert ec_cand.effort == "M"
    assert ec_cand.confidence == "medium"
    assert any("Event routing" in e for e in ec_cand.evidence)
    # Limitation still picked up.
    assert any(c.kind == "limitation" for c in cands)


def test_detect_candidates_reads_improvements_from_overview(tmp_path):
    """Overview-level Imps also become candidates."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "overview.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 升級 LangGraph 為 pluggable adapter\n"
        "- **為什麼:** 目前只能跑 LangGraph,鎖死供應商\n"
        "- **證據:** [[Architecture/decisions]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 換模型成本高\n"
        "- **Confidence:** stated\n"
    )
    cands = detect_candidates(tmp_path)
    imp = [c for c in cands if c.kind == "improvement"]
    assert len(imp) == 1
    assert "LangGraph" in imp[0].title
    assert imp[0].effort == "L"


def test_detect_candidates_v2_fallback_when_no_improvement_blocks(tmp_path):
    """If no `## 改進機會` blocks exist (legacy v2 vault), fall back to v2 detection."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    arch.mkdir(parents=True)
    (arch / "future.md").write_text(
        "## 落差分析\n\n- README mentions streaming, not implemented\n"
        "## 期望中的想法\n\n- migrate to pluggable engines\n"
    )
    cands = detect_candidates(tmp_path)
    # Should still find these legacy candidates.
    kinds = {c.kind for c in cands}
    assert "gap" in kinds
    assert "aspiration" in kinds
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "improvement or v2_fallback" 2>&1 | tail -15`
Expected: FAIL — current detect_candidates doesn't read `## 改進機會` blocks.

- [ ] **Step 3: Update `detect_candidates` in `scripts/roadmap/candidates.py`**

Open `scripts/roadmap/candidates.py`. Find the `detect_candidates` function. Below it, add a new helper `_extract_improvements_from_file` and modify `detect_candidates` to call it. Replace the body of `detect_candidates`:

```python
def detect_candidates(project_root: Path) -> list[Candidate]:
    """Walk Architecture/ subfiles, extract candidates, dedup, return.

    v3: prefers `## 改進機會` / `## Improvement opportunities` blocks from any
    architect file (overview.md, features.md, modules/*.md, flows.md, jobs.md).
    Each Imp becomes a fully-structured Candidate. v2 sections (future.md
    落差分析 / 期望中的想法 / decisions.md Promote-to-ADR) are still consulted
    as supplementary signal.
    """
    arch = project_root / "Architecture"
    if not arch.is_dir():
        return []
    out: list[Candidate] = []
    # v3 improvements — walk every architect file.
    files = list(arch.glob("*.md")) + list((arch / "modules").glob("*.md"))
    for f in files:
        out.extend(_extract_improvements_from_file(f, arch))
    # v2 legacy signals.
    out.extend(_extract_from_file(arch / "future.md", _FUTURE_SECTIONS))
    out.extend(_extract_from_file(arch / "decisions.md", _DECISIONS_SECTIONS))
    out.extend(_extract_from_file(arch / "roadmap.md", _ROADMAP_SECTIONS, freq_dedup=True))
    return _dedup(out)


def _extract_improvements_from_file(path: Path, arch_root: Path) -> list[Candidate]:
    """Pull `## 改進機會` / `## Improvement opportunities` blocks via sections.parse_improvements_block."""
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    # Locate the H2 block body.
    pattern = re.compile(
        r"^##\s+(?:改進機會|Improvement opportunities)\s*$([\s\S]*?)(?=^##\s|\Z)",
        re.MULTILINE,
    )
    m = pattern.search(text)
    if not m:
        return []
    body = m.group(1)
    rel_path = path.relative_to(arch_root.parent).as_posix()
    # Use the same parser sections.py exposes.
    from scripts.architect.sections import parse_improvements_block
    imps = parse_improvements_block(body)
    out: list[Candidate] = []
    arch_rel = rel_path.replace(".md", "")
    anchor = "改進機會" if "改進機會" in text else "Improvement opportunities"
    for imp in imps:
        cand_id = _make_id("imp", _normalize_title(imp.title))
        out.append(Candidate(
            id=cand_id,
            title=imp.title,
            source_wikilink=f"[[{arch_rel}#{anchor}]]",
            source_line=0,
            kind="improvement",
            raw_text=imp.why,
            why=imp.why,
            evidence=imp.evidence,
            effort=imp.effort,
            risk_if_not_done=imp.risk_if_not_done,
            confidence=imp.confidence,
        ))
    return out
```

Ensure `import re` and the `_make_id` / `_normalize_title` / `_FUTURE_SECTIONS` / `_DECISIONS_SECTIONS` / `_ROADMAP_SECTIONS` / `_extract_from_file` / `_dedup` are all defined in the file (they should already be there from the v1 implementation).

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: PASS (all old + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "feat(roadmap): detect_candidates reads ## 改進機會 blocks from architect files (v3)"
```

---

## Phase F — Schema documentation

### Task 12: Update `references/ai-first-rules.md`

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Open `references/ai-first-rules.md`**

Skim for the existing `architecture-*` type definitions. The v3 changes touch:
- `architecture-module` (body section list changes)
- `architecture-features` (body section list changes)
- `architecture-api-surface` (body section list changes)
- Three NEW types: `architecture-personas`, `architecture-jobs`, `architecture-flows`

- [ ] **Step 2: Update `architecture-module` body section list**

Find the `### \`type: architecture-module\`` heading. Replace its body sections list with:

```markdown
Body sections (en / zh-TW), v3 judgment-driven layout:
- `## For future Claude` / `## 給未來 Claude`
- `## Module responsibility` / `## 模組職責`
- `## Design strengths` / `## 設計優點`
- `## Design weaknesses` / `## 設計缺點 / 風險`
- `## Improvement opportunities` / `## 改進機會` — H3 per Imp with Why/Evidence/Effort/Risk/Confidence
- `## Dependencies and consumers` / `## 相依與被誰使用` — wikilinks only, no file paths
- `## Related` / `## 相關`

v2 sections (`## What it does` / `## Key files` / `## How it works`) are dropped.
The codebase is the source of truth for file structure; module notes capture
judgment that the codebase does not record.
```

- [ ] **Step 3: Update `architecture-features` body section list**

Replace its body sections list with:

```markdown
Body sections (en / zh-TW), v3:
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Capability scope` / `## 能力範圍`
- `## Design strengths` / `## 設計優點`
- `## Design weaknesses` / `## 設計缺點 / 風險`
- `## Improvement opportunities` / `## 改進機會`
- `## Related` / `## 相關`

Capability descriptions reference modules via wikilink (`[[modules/backend]]`)
but MUST NOT contain raw file paths like `backend/main.py` in body prose.
Source citations (`path:line`) may appear inline as Evidence in Improvement
opportunities but never in the main capability description.
```

- [ ] **Step 4: Update `architecture-api-surface` body section list**

Replace its body sections list with:

```markdown
Body sections (en / zh-TW), v3:
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Interface overview` / `## 介面類型概觀` — prefix-grouped HTTP routes (NOT exhaustive table)
- `## Environment variables overview` / `## 環境變數概觀` — prefix-grouped env vars (NOT exhaustive)
- `## Related` / `## 相關`

Exhaustive route / export / env tables are intentionally removed from the
vault note. They live in `/tmp/architect-<hash>/scan-report.json` as
machine-readable artifacts for `/obsidian-roadmap` and other tooling. The
vault note is for human + future-Claude scanning at a high level.
```

- [ ] **Step 5: Add three new types**

After the existing `architecture-function` entry (or wherever the architecture types end), add:

```markdown
### `type: architecture-personas`

Generated by `/obsidian-architect` v3. Lives at `Projects/<P>/Architecture/personas.md`.

Captures the people who interact with the product — admin, agent, end-user, etc.
Each persona records Who / Goals / Touchpoints / Frequency / Pain points.
Personas are NOT design judgments (they are not critiqued), so this type
does not have `strengths` / `weaknesses` / `improvements` sections.

Required frontmatter:
- `type: architecture-personas`
- `date`, `project` (wikilink), `repo`, `last-scanned`, `commit`
- `sources` (list of files read, e.g. README.md, AGENTS.md)
- `confidence: stated | medium | speculation` (highest of any persona's confidence)
- `lang: zh-TW | en`
- `tags: [architecture, personas]`
- `ai-first: true`, `status: current | insufficient-signal`

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Personas` / `## 使用者型態` — H3 per persona with structured Who/Goals/Touchpoints/Frequency/Pain points
- `## Related` / `## 相關`

When personas are LLM-inferred (no explicit README section), the note opens
with an Obsidian callout: `> [!warning]+ 本檔大半為 LLM 推論,owner 校對前
不可作為正式產品 spec`.


### `type: architecture-jobs`

Generated by `/obsidian-architect` v3. Lives at `Projects/<P>/Architecture/jobs.md`.

Jobs-to-be-done — what users want to accomplish, framed as "When X, the user
wants Y so that Z". Each job belongs to a persona, declares maturity
(Alpha/Beta/GA), lists friction points, and cross-links to relevant features
and flows.

Required frontmatter: same shape as architecture-personas, with
`tags: [architecture, jobs]`.

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Jobs to be done` / `## Jobs to be Done` — H3 per job
- `## Related` / `## 相關`


### `type: architecture-flows`

Generated by `/obsidian-architect` v3. Lives at `Projects/<P>/Architecture/flows.md`.

End-to-end user flows: a persona crossing the system to accomplish a job.
Each flow includes a Mermaid sequence diagram, a friction assessment (2-5
concrete rough spots), maturity, and wikilinks to relevant modules.

Required frontmatter: same shape as architecture-personas, with
`tags: [architecture, flows]`.

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Flows` / `## 使用流程` — H3 per flow with Mermaid block + Friction + Maturity
- `## Related` / `## 相關`
```

- [ ] **Step 6: Build adapters to verify the file ships cross-platform**

Run: `bash scripts/build.sh --platform claude-code`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(ai-first-rules): v3 architect schemas — module reframe + 3 product-eye types"
```

---

## Phase G — Command body + adapter rebuild

### Task 13: Rewrite `commands/obsidian-architect.md` for v3 workflow

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Read current command body**

Run: `wc -l commands/obsidian-architect.md`
Expected: around 200-250 lines.

- [ ] **Step 2: Update the flag list at the top of the file**

Find the existing flag list (near the top after `Use the obsidian-second-brain skill...`). Add new flags:

```markdown
The argument is `<repo-path>` (local path or github URL). Optional flags:
`--project=<P>` (force project hub binding), `--refresh` (explicit refresh),
`--dry-run` (Phase 1 only, no vault writes), `--force` (ignore "no changes" gate),
`--functions=<off|public>`, `--skip-sections=<csv>`, `--only-sections=<csv>`,
`--lang=<en|zh-TW>` (override vault `_CLAUDE.md output-lang`).

**v3-specific flags:**
- `--frame=<judgment|description>` — default `judgment` (v3). Use `description`
  to fall back to v2 behaviour for compatibility.
- `--improvements-per-file=<N>` — cap on Imps per architect file. Default 4.
- `--require-evidence` — default true. When false, LLM may emit Imps without
  Evidence (debugging only; not recommended).
```

- [ ] **Step 3: Add a Migration Phase between Phase 1 and Phase 2**

After the Phase 1 (Deterministic scan) block and before Phase 2 (Manifest review), insert:

```markdown
## Phase 1.5: v2 → v3 migration (only when `--frame=judgment` AND existing vault is v2)

Detect if `Projects/<P>/Architecture/_manifest.lock.json` exists and reports
`schema-version: 2` (or `version` < 3, or `frame != "judgment-v3"`). If so:

1. Call `scripts.architect.migration.plan_v2_to_v3_migration(arch_dir)` to
   compute what would change.
2. Print the plan to the user — list which files will be modified, which
   `@generated` blocks will be dropped (the v2 file-tree noise), and which
   `@user` blocks will be preserved.
3. ASK user: `proceed | dry-run | abort`. (`--force` bypasses with proceed.)
4. On `proceed`: call `scripts.architect.migration.backup_architecture_dir(arch_dir)`
   to write `_archive/architecture-pre-v3-<timestamp>.tar.gz`, then call
   `apply_v2_to_v3_migration(arch_dir, plan, dry_run=False)`.
5. On `dry-run`: call `apply_v2_to_v3_migration(arch_dir, plan, dry_run=True)`
   and stop. User reviews, re-runs without dry-run when ready.

After successful migration, lockfile is overwritten in Phase 5 (per-section
synthesis) with `schema-version: 3` and `frame: "judgment-v3"`.
```

- [ ] **Step 4: Rewrite Phase 3 (Module synthesis) prompt directive**

Find the Phase 3 module synthesis block. Replace its core instruction with:

```markdown
## Phase 3: Per-module synthesis (v3 judgment frame)

For each module slug in the approved manifest (not excluded):

1. Pack the module's source paths via repomix:
   ```bash
   repomix --include "<paths>" --style xml --compress > /tmp/architect-<hash>/repomix-<slug>.xml
   ```
2. Build the LLM prompt:
   ```python
   from scripts.architect.sections import build_module_prompt
   prompt = build_module_prompt(
       module_slug=slug,
       repomix_packed=open("/tmp/architect-<hash>/repomix-<slug>.xml").read(),
       agents_md_excerpt=agents_md_text[:5000],
       output_lang=output_lang,
   )
   ```
3. Invoke the LLM. Expect strict JSON with 5 keys:
   `scope, strengths, weaknesses, improvements, dependencies`.
4. Validate the `improvements` block: parse via
   `scripts.architect.sections.parse_improvements_block(...)` and confirm
   ≥1 Imp survives (every Imp must include Why/Evidence/Effort/Risk/Confidence).
   If 0 Imps parse, retry once with stricter prompt; if still 0, write the
   block as `_(無 Evidence-grounded improvements;owner 校對)_` and continue.
5. Compose the module note via `scripts.architect.sections.compose_note(...)`
   with `section="module"` (note: v3 introduces this section name).
6. Write to `Projects/<P>/Architecture/modules/<slug>.md`.
7. Update `_manifest.lock.json` `modules[<slug>]` entry.

The new module note:
- Has NO `## Key files` section.
- Body is judgment, not transcription.
- Dependencies section uses wikilinks only.
```

- [ ] **Step 5: Replace Phase 3.5 to add personas/jobs/flows synthesis**

Find the existing Phase 3.5 (per-section narrative synthesis). Insert NEW sub-phases AFTER api-surface synthesis but BEFORE features synthesis:

```markdown
### Phase 3.5.5: personas / jobs / flows synthesis (v3)

After api-surface, BEFORE features (because features cross-references jobs/flows).

For each new product-eye file:

**Personas:**
```python
from scripts.architect.personas import collect_persona_signal, build_personas_prompt, render_personas_section, Persona
sig = collect_persona_signal(repo_root)
if sig.has_explicit_section:
    confidence_default = "stated"
    readme_excerpt = sig.raw_text
else:
    confidence_default = "medium"
    readme_excerpt = "(no explicit personas section)"
prompt = build_personas_prompt(
    project=project_name,
    readme_excerpt=readme_excerpt,
    agents_md_excerpt=agents_md_text[:5000],
    features_summary=features_summary_text,
    output_lang=output_lang,
)
# Agent invokes LLM, parses JSON into list[Persona], then:
note_body = render_personas_section(personas, lang=output_lang)
# Wrap in `## 使用者型態` heading + frontmatter + sentinel; write to personas.md.
```

**Jobs** — similar pattern using `scripts.architect.jobs` (depends on personas being written first so the prompt can cite them).

**Flows** — similar pattern using `scripts.architect.flows` (depends on personas + api-surface summary).

When `has_explicit_section is False`, prepend an Obsidian callout to the file body:
```markdown
> [!warning]+ 本檔大半為 LLM 推論,owner 校對前不可作為正式產品 spec
```
```

- [ ] **Step 6: Update Phase 4 overview synthesis to demand Improvement opportunities at project level**

Find the Phase 4 overview synthesis block. Add to its prompt requirements:

```markdown
## Phase 4: Overview synthesis (v3 frame)

In addition to the v2 MOC structure (Stack frontmatter, Capability MOC,
Structure MOC), the overview now emits its own `## 改進機會` block —
4-6 project-level improvement opportunities that span modules (e.g.
"split EventConsumer from API process for independent scaling"). Each
Imp follows the same Why/Evidence/Effort/Risk/Confidence schema.

Build prompt via `sections.build_overview_prompt(...)` (existing helper —
prompt instructs LLM to produce purpose / layer-map / external-deps /
key-abstractions / **improvements** blocks).

Add `improvements` to the overview's `_BLOCK_NAMES` if not already present.
```

- [ ] **Step 7: Build adapters**

Run: `bash scripts/build.sh`
Expected: 4 dist trees regenerate without errors.

- [ ] **Step 8: Inspect adapter output sanity**

Run: `wc -l dist/claude-code/commands/obsidian-architect.md dist/codex-cli/.codex/commands/obsidian-architect.md`
Expected: similar line counts; both files exist.

Run: `grep -c "v3" dist/claude-code/commands/obsidian-architect.md`
Expected: ≥ 1 (v3 references present).

- [ ] **Step 9: Commit**

```bash
git add commands/obsidian-architect.md dist/
git commit -m "feat(architect): v3 command body — judgment frame, migration phase, product-eye synthesis"
```

---

### Task 14: Add `--frame`, `--improvements-per-file`, `--require-evidence` flag plumbing in sections orchestration

This task is small but threads the new flags through where they matter.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test for `--improvements-per-file` enforcement**

Append to `tests/architect/test_sections.py`:

```python
def test_enforce_improvements_cap_drops_extras():
    """When LLM returns 6 Imps but cap is 4, keep highest-confidence + first ones."""
    from scripts.architect.sections import ImprovementItem, enforce_improvements_cap
    items = [
        ImprovementItem(title=f"Imp {i}", why="w", evidence=["[[e]]"],
                        effort="M", risk_if_not_done="r",
                        confidence="medium" if i % 2 else "stated")
        for i in range(6)
    ]
    capped = enforce_improvements_cap(items, max_n=4)
    assert len(capped) == 4
    # Higher-confidence items should win over lower if cap forces choice.
    titles = [c.title for c in capped]
    # At least one `stated` confidence Imp survives.
    assert any(c.confidence == "stated" for c in capped)


def test_enforce_evidence_required_drops_imps_without_evidence():
    from scripts.architect.sections import ImprovementItem, enforce_evidence_required
    items = [
        ImprovementItem(title="A", why="w", evidence=["[[x]]"], effort="S",
                        risk_if_not_done="r", confidence="stated"),
        ImprovementItem(title="B", why="w", evidence=[], effort="S",
                        risk_if_not_done="r", confidence="stated"),
    ]
    filtered = enforce_evidence_required(items, require=True)
    assert len(filtered) == 1
    assert filtered[0].title == "A"
    # With require=False, both survive (debug mode).
    assert len(enforce_evidence_required(items, require=False)) == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v -k "enforce" 2>&1 | tail -10`
Expected: FAIL — `enforce_improvements_cap` / `enforce_evidence_required` not defined.

- [ ] **Step 3: Append the helpers to `scripts/architect/sections.py`**

```python


_CONFIDENCE_RANK = {"stated": 0, "high": 1, "medium": 2, "speculation": 3}


def enforce_improvements_cap(items: list[ImprovementItem], max_n: int = 4) -> list[ImprovementItem]:
    """Drop excess Imps when LLM returned more than the configured cap.

    Sort by confidence rank (stated > high > medium > speculation) ascending
    so higher-confidence Imps survive, then preserve original ordering within
    same-confidence groups.
    """
    if len(items) <= max_n:
        return items
    indexed = list(enumerate(items))
    indexed.sort(key=lambda pair: (_CONFIDENCE_RANK.get(pair[1].confidence, 99), pair[0]))
    keep = sorted(indexed[:max_n], key=lambda pair: pair[0])
    return [it for _, it in keep]


def enforce_evidence_required(items: list[ImprovementItem], require: bool = True) -> list[ImprovementItem]:
    """Drop Imps with empty evidence when `require=True`.

    Default behaviour for v3. Pass `require=False` (via `--require-evidence`
    flag set to false) to allow Evidence-free Imps during debugging.
    """
    if not require:
        return items
    return [it for it in items if it.evidence]
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "enforce" 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Run full architect test suite**

Run: `uv run pytest tests/architect/ -q 2>&1 | tail -3`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): enforce_improvements_cap + enforce_evidence_required helpers"
```

---

## Phase H — Polish

### Task 15: CHANGELOG, SKILL.md, README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: Add CHANGELOG entry under `## Unreleased`**

Open `CHANGELOG.md`. Under `## Unreleased`, add:

```markdown
### Changed

- `/obsidian-architect` reframed from description-driven (file-tree recital)
  to judgment-driven (design strengths / weaknesses / improvement opportunities).
  Module notes no longer contain `## Key files` sections; the codebase is
  treated as the source of truth for code structure, and vault notes capture
  judgment that the codebase does not record.
- Every Improvement opportunity must cite Evidence (commit SHA, decision
  wikilink, AGENTS.md section, or `path:line`). LLM is instructed to drop
  Imps it cannot ground in Evidence rather than speculate.
- `api-surface.md` reframed from exhaustive HTTP route / export / env tables
  (17 KB) to high-level prefix-grouped overview (≤ 5 KB). Full tables remain
  available in `/tmp/architect-<hash>/scan-report.json` for tooling.
- Lockfile schema bumped to v3 with `frame` marker
  (`description-v2` legacy vs `judgment-v3` new).

### Added

- `Architecture/personas.md`, `jobs.md`, `flows.md` — product-eye layer
  capturing who uses the product, what jobs they want done, and the
  end-to-end flows they traverse. Each is judgment-aware (jobs declare
  maturity, flows include friction assessment).
- `--frame=<judgment|description>` flag on `/obsidian-architect`. Default
  `judgment` (v3). `description` falls back to v2 behaviour for compatibility.
- `--improvements-per-file=<N>` (default 4) and `--require-evidence` (default
  true) flags on `/obsidian-architect`.
- v2 → v3 migration step: drops v2 `@generated` file-tree blocks, preserves
  `@user` blocks, archives the pre-v3 Architecture/ tree to
  `_archive/architecture-pre-v3-<timestamp>.tar.gz` as a safety net.

### `/obsidian-roadmap` integration

- Phase 1 (gap detection) now reads `## 改進機會` / `## Improvement opportunities`
  blocks from every architect file. Each Imp arrives at Phase 3 with full
  metadata (Why, Evidence, Effort, Risk, Confidence), eliminating the
  Phase 1 inference step.
- `Candidate` dataclass extended with optional v3 fields (`why`, `evidence`,
  `effort`, `risk_if_not_done`, `confidence`). v2 candidates without these
  fields continue to work.
```

- [ ] **Step 2: Update SKILL.md description of architect**

Open `SKILL.md`. Find the section listing Layer 1 commands (architect). Replace the architect line with:

```markdown
- `/obsidian-architect <repo-path>` — Scan a codebase and produce judgment-driven
  architecture notes: overview + per-module designs + product-eye layer
  (personas, jobs, flows). Each file captures design strengths, weaknesses,
  and Evidence-grounded improvement opportunities — the kind of insight the
  codebase itself does NOT record. Improvement opportunities are the primary
  signal source for `/obsidian-roadmap`.
```

- [ ] **Step 3: Update README.md commands table**

Open `README.md`. Find the row for `/obsidian-architect`. Replace its description with:

```markdown
| `/obsidian-architect` | Judgment-driven architecture documentation (v3). Captures design pros/cons + Evidence-grounded improvement opportunities + product-eye layer (personas/jobs/flows). Feeds `/obsidian-roadmap` Phase 1. |
```

- [ ] **Step 4: Build adapters**

Run: `bash scripts/build.sh`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md SKILL.md README.md dist/
git commit -m "docs: announce architect v3 (judgment frame + product-eye + Evidence-required)"
```

---

### Task 16: End-to-end smoke against langlive-line-oa

**Files:** read-only

- [ ] **Step 1: Run full test suite**

Run: `uv run pytest tests/ -q 2>&1 | tail -5`
Expected: all green.

- [ ] **Step 2: Inspect existing vault state (pre-migration check)**

Run: `ls /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture/`
Expected: existing modules/, future.md, decisions.md, etc. (v2 layout).

Run: `head -3 /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture/_manifest.lock.json`
Expected: `version: 2` or similar (v2 lockfile).

- [ ] **Step 3: Dry-run migration plan against the real vault**

```bash
uv run python -c "
from pathlib import Path
from scripts.architect.migration import plan_v2_to_v3_migration
plan = plan_v2_to_v3_migration(
    Path('/Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture')
)
print('files to modify:', len(plan.files_to_modify))
for f, bs in plan.blocks_per_file.items():
    print(f'  {f}: drop={bs[\"drop\"]}, keep={bs[\"keep\"]}, create={bs[\"create\"]}')
"
```

Expected: at least 5 module files listed, each with `what-it-does`, `key-files`,
etc. in `drop` and `scope`, `strengths`, `weaknesses`, `improvements`, `dependencies`
in `create`.

- [ ] **Step 4: Spot-check the new helpers with a synthetic Improvement block**

```bash
uv run python << 'PYEOF'
from scripts.architect.sections import (
    ImprovementItem, render_improvements_block, parse_improvements_block,
    enforce_evidence_required, enforce_improvements_cap,
)

items = [
    ImprovementItem(
        title="Extract EventConsumer to separate worker container",
        why="API and event loop share CPU; peak traffic blocks request handling.",
        evidence=["[[Architecture/decisions#Event routing principle]]",
                  "`backend/main.py:120`"],
        effort="M",
        risk_if_not_done="During campaigns LINE webhook backlog grows; admin UI lags.",
        confidence="medium",
    ),
    ImprovementItem(
        title="Add webhook signature verification",
        why="Currently no verification of LINE webhook source.",
        evidence=[],  # missing Evidence
        effort="S",
        risk_if_not_done="Webhooks can be spoofed by anyone.",
        confidence="stated",
    ),
]

filtered = enforce_evidence_required(items, require=True)
print(f"After require_evidence: {len(filtered)} items")
capped = enforce_improvements_cap(filtered, max_n=4)
rendered = render_improvements_block(capped, lang="zh-TW")
print("--- rendered (zh-TW) ---")
print(rendered)
print("--- round-trip parse ---")
parsed = parse_improvements_block(rendered)
print(f"parsed back: {len(parsed)} items")
for p in parsed:
    print(f"  {p.title}: effort={p.effort}, confidence={p.confidence}")
PYEOF
```

Expected output:
- `After require_evidence: 1 items` (the Evidence-less Imp dropped).
- Rendered zh-TW block uses `為什麼:`, `證據:`, `Effort:`, `未做的風險:`, `Confidence:`.
- Round-trip parse recovers 1 ImprovementItem.

- [ ] **Step 5: Spot-check Phase-2 roadmap candidate extraction against a synthetic v3 module note**

```bash
uv run python << 'PYEOF'
import tempfile
from pathlib import Path
from scripts.roadmap.candidates import detect_candidates

with tempfile.TemporaryDirectory() as td:
    root = Path(td) / "proj"
    arch = root / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 拆 EventConsumer\n"
        "- **為什麼:** 共用 process\n"
        "- **證據:** [[Architecture/decisions]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 流量峰值延遲\n"
        "- **Confidence:** medium\n"
    )
    cands = detect_candidates(root)
    print(f"candidates: {len(cands)}")
    for c in cands:
        print(f"  {c.kind} | {c.title} | effort={c.effort} | conf={c.confidence}")
        print(f"     evidence={c.evidence}")
PYEOF
```

Expected output:
```
candidates: 1
  improvement | 拆 EventConsumer | effort=M | conf=medium
     evidence=['[[Architecture/decisions]]']
```

- [ ] **Step 6: Verify branch state**

Run: `git log --oneline -20`
Expected: roughly 15 commits, one per task in this plan.

Run: `uv run pytest tests/ -q && bash scripts/build.sh`
Expected: full green; all 4 adapter dist trees regenerate cleanly.

- [ ] **Step 7: Acceptance checklist (mirrors spec §14)**

Manually verify (no automation):

- [ ] `scripts/architect/sections.py` `_BLOCK_NAMES["module"]` contains scope/strengths/weaknesses/improvements/dependencies and NOT key-files/what-it-does
- [ ] `build_module_prompt` does not mention "key files" or "list of files"
- [ ] `ImprovementItem` serialize/parse round-trips
- [ ] Migration helper drops v2 @generated blocks but preserves @user blocks
- [ ] tar.gz backup created at `_archive/`
- [ ] `personas.py`, `jobs.py`, `flows.py` all have signal collector + prompt builder + renderer
- [ ] `api_surface_render` has `render_interface_overview` and `render_env_overview` producing prefix-grouped summaries
- [ ] `Candidate` dataclass supports v3 fields, v2 still works
- [ ] `detect_candidates` reads `## 改進機會` blocks from all architect files
- [ ] `references/ai-first-rules.md` documents 3 new types and the new module/features/api-surface body sections
- [ ] `commands/obsidian-architect.md` documents `--frame`, `--improvements-per-file`, `--require-evidence`
- [ ] CHANGELOG, SKILL.md, README updated
- [ ] All adapter dist trees rebuilt
- [ ] `tests/` all green
