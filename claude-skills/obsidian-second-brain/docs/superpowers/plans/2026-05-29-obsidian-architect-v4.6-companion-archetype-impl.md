# obsidian-architect v4.6 (AI Companion Archetype) Implementation Plan

## Resolution (2026-05-30)

Task 15 originally hit a blocker: ai-eden-service `ai_flows count: 0` despite
Task 4's custom-pipeline loosening landing. Root cause: ai-eden inlines system
prompts as Python strings inside `app/providers/*_provider.py` and has NO
`prompts*` file — so the Task 4 loosening still failed the
`(prompt_files or any(p.name.startswith("prompts") for p in py_files))` clause.
The Task 4 unit test passed only because its synthetic fixture had a
`prompts.toml`.

Spec intent was `(prompt_files or has_companion_archetype_signal)`; the plan's
implementation dropped the second half. Follow-up fix:

- `scripts/architect/ai_flow.py`: added `companion_archetype: bool = False`
  kwarg to `detect_ai_flows` + `_classify_candidate`. Branch 2's prompt clause
  now reads `(prompt_files or prompts*.py or companion_archetype)`.
- `scripts/architect/scan.py`: reorders companion detection BEFORE
  `detect_ai_flows` and threads `companion_archetype=is_companion` through.
- `tests/architect/test_ai_flow.py`: 2 new fixture-shaped tests mirroring
  ai-eden's real layout (no prompts file):
  `test_custom_pipeline_with_companion_archetype_waives_prompts_file` and
  `test_companion_archetype_does_not_force_unrelated_repos` (sanity).

Smoke against ai-eden-service after fix: `ai_flows count: 1` (app,
custom-pipeline, openai) + `ai_companion.archetype=ai-companion` + all 4
layers detected. All 463 tests pass; 4 adapters build clean.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AI companion-bot archetype detection + 4-layer schema (Character Card / World / Storyline / cross-cutting overview, reusing v4.3 memory.md) to `/obsidian-architect`. Fix the v4.1 detector miss that gave `ai-eden-service` "0 AI flows" despite having LLMs + 4 distinct AI layers.

**Architecture:** Additive layer. New module `scripts/architect/companion_detect.py` exposes `detect_companion_archetype(repo_root, hub_frontmatter)` returning `CompanionDetection` with per-layer `LayerEvidence`. Auto-detect requires character + storyline signals together (avoids generic LLM-wrapper false positives); `archetype: ai-companion` frontmatter override forces all 4 layers present. `sections.py` registers 4 new section types (`character-card` / `world` / `storyline` / `companion-overview`) with 9/10/11/9 blocks respectively + 4 prompt builders + 4 composers. Scanner produces `scan_report["ai_companion"]`; Lockfile gains `ai_companion: dict` slot. Phase 3.7.5 in command body runs between v4.1 ai-flow synthesis (3.7) and v4.3 ai-memory (3.8). Roadmap candidate detector walks 3 new files; cross-layer Evidence bumps priority to `high`. Loosens v4.1 `_classify_candidate` so projects without `nodes/` dir can still register as custom-pipeline.

**Tech Stack:** Python 3.10+, pytest, `pathlib`, regex. Reuses v4.3 `detect_memory` + v4.5 `repo_resolver`. No new external deps.

**Plan-level notes:**
- Run tests from repo root `/Users/leric/Desktop/code/obsidian-second-brain` with `uv run pytest tests/path/test.py -v`.
- Co-author line: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- `dist/` is gitignored — never `git add dist/`.
- Pytest COLLECTION ERROR at "verify it fails" steps is the expected RED state for TDD — proceed to impl.

---

## File structure (locked)

**New files:**
- `scripts/architect/companion_detect.py` — `detect_companion_archetype()` + `CompanionDetection` + `LayerEvidence` dataclasses
- `tests/architect/test_companion_detect.py` — 8 unit tests
- `tests/architect/test_companion_sections.py` — 12 unit tests

**Modified files:**
- `scripts/architect/sections.py` — 4 new SECTION_TYPES + 4 _BLOCK_NAMES + ~14 new _BLOCK_HEADINGS + 4 preamble entries + 4 builders + 4 composers
- `scripts/architect/lang.py` — ~14 new zh-TW heading mappings
- `scripts/architect/ai_flow.py` — loosen custom-pipeline branch
- `tests/architect/test_ai_flow.py` — 2 new tests for loosened detection
- `scripts/architect/scan.py` — adds `ai_companion` to scan_report
- `scripts/architect/lockfile.py` — adds `ai_companion: dict` field
- `tests/architect/test_lockfile.py` — 1 new round-trip test
- `scripts/roadmap/candidates.py` — walks 3 new files + cross-layer evidence priority bump
- `tests/roadmap/test_candidates.py` — 3 new tests
- `commands/obsidian-architect.md` — Phase 3.7.5 + `--no-companion` / `--companion-only` flags
- `references/ai-first-rules.md` — 4 new schemas
- `SKILL.md`, `README.md`, `CHANGELOG.md` — v4.6 announcement

---

## Phase A: Foundation (sections.py + lang.py registration)

### Task 1: Register 4 section types + 39 blocks + 14 headings + preambles

**Files:**
- Modify: `scripts/architect/sections.py` (SECTION_TYPES + _BLOCK_NAMES + _BLOCK_HEADINGS + _preamble_for)
- Modify: `scripts/architect/lang.py` (HEADING_MAP)
- Create: `tests/architect/test_companion_sections.py`
- Modify: `tests/architect/test_lang.py` (append)

- [ ] **Step 1: Write failing test for registration smoke**

Create `tests/architect/test_companion_sections.py`:

```python
"""v4.6 companion archetype section registration tests."""
from __future__ import annotations

from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS


def test_character_card_section_type_present():
    assert SECTION_TYPES["character-card"] == "architecture-character-card"


def test_world_section_type_present():
    assert SECTION_TYPES["world"] == "architecture-world"


def test_storyline_section_type_present():
    assert SECTION_TYPES["storyline"] == "architecture-storyline"


def test_companion_overview_section_type_present():
    assert SECTION_TYPES["companion-overview"] == "architecture-companion-overview"


def test_character_card_block_names_v4_6():
    expected = (
        "summary", "card-schema", "definitions-inventory",
        "prompt-template-binding", "versioning-and-overrides",
        "strengths", "weaknesses", "improvements", "dependencies",
    )
    assert _BLOCK_NAMES["character-card"] == expected


def test_world_block_names_v4_6():
    expected = (
        "summary", "world-schema", "lore-inventory", "world-state",
        "loading-strategy", "mutation-rules",
        "strengths", "weaknesses", "improvements", "dependencies",
    )
    assert _BLOCK_NAMES["world"] == expected


def test_storyline_block_names_v4_6():
    expected = (
        "summary", "storyline-dsl", "state-machine", "progression-rules",
        "branching-logic", "persistence", "authoring-workflow",
        "strengths", "weaknesses", "improvements", "dependencies",
    )
    assert _BLOCK_NAMES["storyline"] == expected


def test_companion_overview_block_names_v4_6():
    expected = (
        "summary", "four-layer-diagram", "data-flow", "bind-points",
        "layer-maturity-table",
        "strengths", "weaknesses", "improvements", "dependencies",
    )
    assert _BLOCK_NAMES["companion-overview"] == expected


def test_v4_6_new_block_headings_registered():
    """All v4.6-specific block names must have entries in _BLOCK_HEADINGS."""
    new_blocks = [
        "card-schema", "definitions-inventory", "prompt-template-binding",
        "versioning-and-overrides",
        "world-schema", "lore-inventory", "world-state",
        "loading-strategy", "mutation-rules",
        "storyline-dsl", "state-machine", "progression-rules",
        "branching-logic", "persistence", "authoring-workflow",
        "four-layer-diagram", "data-flow", "bind-points",
        "layer-maturity-table",
    ]
    for block in new_blocks:
        assert block in _BLOCK_HEADINGS, f"missing heading for {block}"
```

- [ ] **Step 2: Append lang.py heading map test**

In `tests/architect/test_lang.py`, append:

```python
def test_heading_map_includes_v4_6_companion_keys():
    """v4.6 introduces 14 new H2 headings across the 4 companion section types."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Card schema": "## Card schema",
        "## Definitions inventory": "## 角色定義清單",
        "## Prompt template binding": "## Prompt template 綁定",
        "## Versioning & overrides": "## 版本與覆寫",
        "## World schema": "## World schema",
        "## Lore inventory": "## Lore 清單",
        "## Mutable world state": "## 動態 world state",
        "## Loading strategy": "## 載入策略",
        "## Mutation rules": "## 變動規則",
        "## Storyline DSL": "## Storyline DSL",
        "## State machine": "## 狀態機",
        "## Progression rules": "## 推進規則",
        "## Branching logic": "## 分支邏輯",
        "## Persistence": "## 持久化",
        "## Authoring workflow": "## 創作流程",
        "## Four-layer dependency diagram": "## 4 層依賴圖",
        "## Per-turn data flow": "## 每輪資料流",
        "## Bind points": "## 層間綁定",
        "## Layer maturity table": "## 各層成熟度",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_companion_sections.py tests/architect/test_lang.py::test_heading_map_includes_v4_6_companion_keys -v`
Expected: ~10 FAILs.

- [ ] **Step 4: Add `SECTION_TYPES` entries**

In `scripts/architect/sections.py`, find `SECTION_TYPES = {...}` (around line 37). Append before the closing brace (after existing `ai-rag` / `brainstorm` entries):

```python
    # v4.6 — AI companion archetype (4-layer schema)
    "character-card": "architecture-character-card",
    "world": "architecture-world",
    "storyline": "architecture-storyline",
    "companion-overview": "architecture-companion-overview",
}
```

- [ ] **Step 5: Add `_BLOCK_NAMES` entries**

In `_BLOCK_NAMES` dict, append after existing entries:

```python
    # v4.6 — AI companion archetype
    "character-card": (
        "summary", "card-schema", "definitions-inventory",
        "prompt-template-binding", "versioning-and-overrides",
        "strengths", "weaknesses", "improvements", "dependencies",
    ),
    "world": (
        "summary", "world-schema", "lore-inventory", "world-state",
        "loading-strategy", "mutation-rules",
        "strengths", "weaknesses", "improvements", "dependencies",
    ),
    "storyline": (
        "summary", "storyline-dsl", "state-machine", "progression-rules",
        "branching-logic", "persistence", "authoring-workflow",
        "strengths", "weaknesses", "improvements", "dependencies",
    ),
    "companion-overview": (
        "summary", "four-layer-diagram", "data-flow", "bind-points",
        "layer-maturity-table",
        "strengths", "weaknesses", "improvements", "dependencies",
    ),
}
```

- [ ] **Step 6: Add 19 new heading entries in `_BLOCK_HEADINGS`**

In `_BLOCK_HEADINGS` dict, append:

```python
    # v4.6 character-card block headings
    "card-schema": "## Card schema",
    "definitions-inventory": "## Definitions inventory",
    "prompt-template-binding": "## Prompt template binding",
    "versioning-and-overrides": "## Versioning & overrides",
    # v4.6 world block headings
    "world-schema": "## World schema",
    "lore-inventory": "## Lore inventory",
    "world-state": "## Mutable world state",
    "loading-strategy": "## Loading strategy",
    "mutation-rules": "## Mutation rules",
    # v4.6 storyline block headings
    "storyline-dsl": "## Storyline DSL",
    "state-machine": "## State machine",
    "progression-rules": "## Progression rules",
    "branching-logic": "## Branching logic",
    "persistence": "## Persistence",
    "authoring-workflow": "## Authoring workflow",
    # v4.6 companion-overview block headings
    "four-layer-diagram": "## Four-layer dependency diagram",
    "data-flow": "## Per-turn data flow",
    "bind-points": "## Bind points",
    "layer-maturity-table": "## Layer maturity table",
```

- [ ] **Step 7: Add zh-TW heading mappings in lang.py**

In `scripts/architect/lang.py`, find end of `HEADING_MAP` dict. Append:

```python
    # v4.6 companion archetype (Character Card / World / Storyline / cross-cutting)
    "## Card schema": {"en": "## Card schema", "zh-TW": "## Card schema"},
    "## Definitions inventory": {
        "en": "## Definitions inventory", "zh-TW": "## 角色定義清單",
    },
    "## Prompt template binding": {
        "en": "## Prompt template binding", "zh-TW": "## Prompt template 綁定",
    },
    "## Versioning & overrides": {
        "en": "## Versioning & overrides", "zh-TW": "## 版本與覆寫",
    },
    "## World schema": {"en": "## World schema", "zh-TW": "## World schema"},
    "## Lore inventory": {"en": "## Lore inventory", "zh-TW": "## Lore 清單"},
    "## Mutable world state": {
        "en": "## Mutable world state", "zh-TW": "## 動態 world state",
    },
    "## Loading strategy": {"en": "## Loading strategy", "zh-TW": "## 載入策略"},
    "## Mutation rules": {"en": "## Mutation rules", "zh-TW": "## 變動規則"},
    "## Storyline DSL": {"en": "## Storyline DSL", "zh-TW": "## Storyline DSL"},
    "## State machine": {"en": "## State machine", "zh-TW": "## 狀態機"},
    "## Progression rules": {"en": "## Progression rules", "zh-TW": "## 推進規則"},
    "## Branching logic": {"en": "## Branching logic", "zh-TW": "## 分支邏輯"},
    "## Persistence": {"en": "## Persistence", "zh-TW": "## 持久化"},
    "## Authoring workflow": {
        "en": "## Authoring workflow", "zh-TW": "## 創作流程",
    },
    "## Four-layer dependency diagram": {
        "en": "## Four-layer dependency diagram", "zh-TW": "## 4 層依賴圖",
    },
    "## Per-turn data flow": {
        "en": "## Per-turn data flow", "zh-TW": "## 每輪資料流",
    },
    "## Bind points": {"en": "## Bind points", "zh-TW": "## 層間綁定"},
    "## Layer maturity table": {
        "en": "## Layer maturity table", "zh-TW": "## 各層成熟度",
    },
```

- [ ] **Step 8: Add `_preamble_for` entries for 4 new section types**

In `_preamble_for(section, lang)`, in the zh-TW dict, append:

```python
            "character-card": "本檔是 AI 陪伴專案的 Character Card 層深判斷 — 角色定義、prompt template 綁定、versioning。跨層議題見 [[Architecture/ai-flows/companion-overview]]。",
            "world": "本檔是 AI 陪伴專案的 World 層深判斷 — lore inventory、mutable state、loading strategy、mutation rules。跨層議題見 [[Architecture/ai-flows/companion-overview]]。",
            "storyline": "本檔是 AI 陪伴專案的 Storyline 層深判斷 — DSL grammar、state machine、progression rules、branching、persistence、authoring workflow。",
            "companion-overview": "本檔是 AI 陪伴 archetype 的跨 4 層 cross-cutting 報告 — 依賴圖、每輪資料流、層間綁定、各層成熟度。Per-layer 詳細請見 [[ai-flows/character-card]] / [[ai-flows/world]] / [[ai-flows/storyline]] / [[ai-flows/memory]]。",
```

In the en dict, append:

```python
            "character-card": "Character Card layer deep dive for an AI companion project — character definitions, prompt template binding, versioning. Cross-layer concerns: [[Architecture/ai-flows/companion-overview]].",
            "world": "World layer deep dive — lore inventory, mutable world state, loading strategy, mutation rules. Cross-layer concerns: [[Architecture/ai-flows/companion-overview]].",
            "storyline": "Storyline layer deep dive — DSL grammar, state machine, progression rules, branching, persistence, authoring workflow.",
            "companion-overview": "Cross-cutting report for the AI companion archetype — 4-layer dependency diagram, per-turn data flow, bind points, layer maturity. For per-layer detail see [[ai-flows/character-card]] / [[ai-flows/world]] / [[ai-flows/storyline]] / [[ai-flows/memory]].",
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py tests/architect/test_lang.py -v`
Expected: 9 PASS in companion_sections + 1 new pass in lang.

- [ ] **Step 10: Run full suite for no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS (427 prior + 10 new = 437).

- [ ] **Step 11: Commit**

```bash
git add scripts/architect/sections.py scripts/architect/lang.py tests/architect/test_companion_sections.py tests/architect/test_lang.py
git commit -m "$(cat <<'EOF'
feat(architect): v4.6 — register 4 companion archetype section types + 19 headings

Adds SECTION_TYPES entries for character-card / world / storyline /
companion-overview (architecture-* prefix). _BLOCK_NAMES defines 9 /
10 / 11 / 9 blocks respectively (39 total, with summary / strengths /
weaknesses / improvements / dependencies shared across them).

19 new zh-TW heading mappings cover all the layer-specific H2s. Existing
v3 headings (summary / strengths / weaknesses / etc.) are reused.

Preamble entries describe each layer's scope and direct readers to the
cross-cutting companion-overview for inter-layer concerns.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Detector

### Task 2: `companion_detect.py` — character + storyline both required (happy path)

**Files:**
- Create: `scripts/architect/companion_detect.py`
- Create: `tests/architect/test_companion_detect.py`

- [ ] **Step 1: Write failing test (happy path)**

Create `tests/architect/test_companion_detect.py`:

```python
"""Tests for scripts.architect.companion_detect.detect_companion_archetype."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.companion_detect import (
    detect_companion_archetype,
    CompanionDetection,
    LayerEvidence,
)


def test_detect_companion_when_character_and_storyline_present(tmp_path: Path):
    """Both layers' signals → archetype=ai-companion, confidence=high."""
    chars = tmp_path / "app" / "characters"
    chars.mkdir(parents=True)
    (chars / "definitions").mkdir()
    (chars / "definitions" / "alice.json").write_text('{"name":"Alice"}', encoding="utf-8")
    (chars / "storyline.py").write_text(
        "# Storyline DSL\ndef beat(name): pass\n", encoding="utf-8"
    )

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert isinstance(result, CompanionDetection)
    assert result.archetype == "ai-companion"
    assert result.confidence == "high"
    assert result.layers["character-card"].present is True
    assert result.layers["storyline"].present is True


def test_detect_no_companion_when_only_character(tmp_path: Path):
    """Character but NO storyline → archetype=none (generic LLM wrapper)."""
    chars = tmp_path / "app" / "characters"
    chars.mkdir(parents=True)
    (chars / "definitions").mkdir()
    (chars / "definitions" / "alice.json").write_text('{}', encoding="utf-8")
    # No storyline file.

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert result.archetype == "none"


def test_detect_no_companion_when_only_storyline(tmp_path: Path):
    """Storyline but NO characters → archetype=none."""
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "storyline_dsl.py").write_text(
        "# storyline things\n", encoding="utf-8"
    )

    result = detect_companion_archetype(repo_root=tmp_path, hub_frontmatter=None)
    assert result.archetype == "none"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_companion_detect.py -v`
Expected: COLLECTION ERROR (`ModuleNotFoundError: No module named 'scripts.architect.companion_detect'`).

- [ ] **Step 3: Implement `companion_detect.py` happy path**

Create `scripts/architect/companion_detect.py`:

```python
"""Detect AI companion-bot archetype (Character Card / World / Storyline / Memory).

Auto-detect rule: BOTH character-card AND storyline signals must be present.
This avoids false positives on generic LLM-wrapper projects that have only
persona definitions.

Frontmatter override: `archetype: ai-companion` in project hub forces all 4
layers present with confidence='stated' regardless of code evidence. Used for
projects with non-standard directory names.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


# Alias dir names per layer.
_CHARACTER_DIR_NAMES = ("characters", "personas", "bots", "companions")
_WORLD_DIR_NAMES = ("worlds", "lore")          # also matches "world_*"
_STORYLINE_FILENAME_PATTERNS = (
    r"^storyline",
    r"^plot",
    r"^narrative",
    r"^script",
    r".*_dsl\.py$",
)
_STORYLINE_KEYWORDS = ("storyline", "plot", "beat", "progression")

# Files extensions that count as definition payloads.
_DEFINITION_EXTS = (".py", ".json", ".yaml", ".yml")


@dataclass
class LayerEvidence:
    present: bool = False
    root_paths: list[str] = field(default_factory=list)
    artifact_files: list[str] = field(default_factory=list)
    storyline_dsl_file: str | None = None
    llm_libs: list[str] = field(default_factory=list)
    confidence: str = "medium"   # 'speculation' | 'medium' | 'high' | 'stated'


@dataclass
class CompanionDetection:
    archetype: str                            # 'ai-companion' | 'none'
    confidence: str                           # 'stated' | 'high' | 'medium'
    layers: dict[str, LayerEvidence] = field(default_factory=dict)
    triggers: list[str] = field(default_factory=list)


def detect_companion_archetype(
    repo_root: Path,
    hub_frontmatter: dict | None = None,
) -> CompanionDetection:
    repo_root = repo_root.resolve()

    char_ev = _detect_character_layer(repo_root)
    world_ev = _detect_world_layer(repo_root)
    storyline_ev = _detect_storyline_layer(repo_root)
    # Memory layer: defer to v4.3 detect_memory (lightly invoked).
    memory_ev = _detect_memory_layer_stub(repo_root)

    layers = {
        "character-card": char_ev,
        "world": world_ev,
        "storyline": storyline_ev,
        "memory": memory_ev,
    }

    # Frontmatter override.
    if hub_frontmatter and hub_frontmatter.get("archetype") == "ai-companion":
        for ev in layers.values():
            ev.present = True
            ev.confidence = "stated" if ev.root_paths else "speculation"
        return CompanionDetection(
            archetype="ai-companion",
            confidence="stated",
            layers=layers,
            triggers=["frontmatter override: archetype: ai-companion"],
        )

    # Auto-detect: character AND storyline both required.
    if char_ev.present and storyline_ev.present:
        triggers = [f"character dir {char_ev.root_paths[0]}",
                    f"storyline file {storyline_ev.artifact_files[0]}"]
        return CompanionDetection(
            archetype="ai-companion", confidence="high",
            layers=layers, triggers=triggers,
        )

    return CompanionDetection(archetype="none", confidence="medium", layers=layers)


def _detect_character_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    for dir_name in _CHARACTER_DIR_NAMES:
        for d in repo_root.rglob(dir_name):
            if not d.is_dir() or any(part.startswith(".") for part in d.parts):
                continue
            payload = [
                p for p in d.rglob("*")
                if p.is_file() and p.suffix in _DEFINITION_EXTS
                and "__pycache__" not in p.parts
            ]
            if not payload:
                continue
            ev.present = True
            ev.confidence = "high"
            ev.root_paths.append(d.relative_to(repo_root).as_posix())
            for f in payload[:5]:
                ev.artifact_files.append(f.relative_to(repo_root).as_posix())
            return ev
    return ev


def _detect_world_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    for dir_name in _WORLD_DIR_NAMES + ("world_*",):
        for d in repo_root.rglob(dir_name):
            if not d.is_dir() or any(part.startswith(".") for part in d.parts):
                continue
            payload = [
                p for p in d.rglob("*")
                if p.is_file() and p.suffix in _DEFINITION_EXTS
            ]
            if not payload:
                continue
            ev.present = True
            ev.confidence = "high"
            ev.root_paths.append(d.relative_to(repo_root).as_posix())
            for f in payload[:5]:
                ev.artifact_files.append(f.relative_to(repo_root).as_posix())
            return ev
    return ev


def _detect_storyline_layer(repo_root: Path) -> LayerEvidence:
    ev = LayerEvidence()
    patterns = [re.compile(p) for p in _STORYLINE_FILENAME_PATTERNS]
    for py in repo_root.rglob("*.py"):
        if any(part.startswith(".") or part == "__pycache__" for part in py.parts):
            continue
        name = py.name
        if any(p.match(name) for p in patterns):
            # Confirm keyword presence inside file.
            try:
                text = py.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if any(kw in text.lower() for kw in _STORYLINE_KEYWORDS):
                ev.present = True
                ev.confidence = "high"
                rel = py.relative_to(repo_root).as_posix()
                ev.artifact_files.append(rel)
                if name.endswith("_dsl.py") or "dsl" in name.lower():
                    ev.storyline_dsl_file = rel
                if not ev.root_paths:
                    ev.root_paths.append(py.parent.relative_to(repo_root).as_posix())
                return ev
    return ev


def _detect_memory_layer_stub(repo_root: Path) -> LayerEvidence:
    """Light wrapper. Full v4.3 detect_memory is invoked separately in Phase 1
    of scan.py; this stub only flags presence based on import signals."""
    ev = LayerEvidence()
    for py in repo_root.rglob("*.py"):
        if any(part.startswith(".") or part == "__pycache__" for part in py.parts):
            continue
        try:
            text = py.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if "openai" in text or "anthropic" in text or "google.generativeai" in text:
            ev.llm_libs.append("openai/anthropic/google")
            ev.present = True
            ev.confidence = "medium"
            return ev
    return ev
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_detect.py -v`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/companion_detect.py tests/architect/test_companion_detect.py
git commit -m "$(cat <<'EOF'
feat(architect): companion_detect — character + storyline both required for archetype=ai-companion

New module scripts/architect/companion_detect.py + CompanionDetection +
LayerEvidence dataclasses. Auto-detect rule requires BOTH character AND
storyline signals to flag archetype=ai-companion. Character alone is not
enough (avoids generic LLM-wrapper false positives like /personas
directories that don't represent a true companion architecture).

This commit lands the happy path:
- _detect_character_layer: dir name in (characters/personas/bots/companions) + ≥1 definition file
- _detect_storyline_layer: file matching storyline*/plot*/narrative*/*_dsl.py + keyword presence
- _detect_world_layer + _detect_memory_layer_stub: included for completeness

Frontmatter override + alt directory names + edge cases come in Task 3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: Detector edge cases — frontmatter override + alt names + storyline DSL + only-character

**Files:**
- Modify: `tests/architect/test_companion_detect.py` (append)

- [ ] **Step 1: Append edge-case tests**

```python
def test_frontmatter_override_forces_archetype(tmp_path: Path):
    """`archetype: ai-companion` in hub frontmatter forces detection."""
    # Empty repo (no character / storyline dirs).
    result = detect_companion_archetype(
        repo_root=tmp_path,
        hub_frontmatter={"archetype": "ai-companion"},
    )
    assert result.archetype == "ai-companion"
    assert result.confidence == "stated"
    # All 4 layers marked present (even with no code evidence — confidence speculation).
    for layer_name in ("character-card", "world", "storyline", "memory"):
        assert result.layers[layer_name].present is True


def test_world_layer_optional(tmp_path: Path):
    """character + storyline present, world dir missing → archetype=ai-companion
    but world.present=False."""
    chars = tmp_path / "app" / "personas"
    chars.mkdir(parents=True)
    (chars / "alice.yaml").write_text("name: Alice\n", encoding="utf-8")
    (tmp_path / "app" / "storyline_engine.py").write_text(
        "# beat / storyline / progression engine\n", encoding="utf-8"
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "ai-companion"
    assert result.layers["character-card"].present is True
    assert result.layers["storyline"].present is True
    assert result.layers["world"].present is False


def test_storyline_dsl_file_recognized(tmp_path: Path):
    """A file ending in `_dsl.py` with storyline keyword → storyline_dsl_file populated."""
    chars = tmp_path / "characters"
    chars.mkdir()
    (chars / "alice.json").write_text("{}", encoding="utf-8")
    (tmp_path / "story_dsl.py").write_text(
        "# DSL for storyline + beat + progression\n", encoding="utf-8"
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.layers["storyline"].storyline_dsl_file == "story_dsl.py"


def test_detect_with_alt_directory_names(tmp_path: Path):
    """`personas/` / `bots/` / `companions/` all alias for character-card."""
    bots = tmp_path / "bots"
    bots.mkdir()
    (bots / "bot1.json").write_text("{}", encoding="utf-8")
    (tmp_path / "storyline.py").write_text("# storyline beat\n", encoding="utf-8")
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "ai-companion"
    assert "bots" in result.layers["character-card"].root_paths[0]


def test_no_archetype_when_storyline_keyword_missing_in_file(tmp_path: Path):
    """File named `storyline.py` but content doesn't contain the keyword → not a storyline."""
    chars = tmp_path / "characters"
    chars.mkdir()
    (chars / "alice.json").write_text("{}", encoding="utf-8")
    (tmp_path / "storyline.py").write_text(
        "# this file is named storyline but content unrelated\n"
        "def hello(): pass\n",
        encoding="utf-8",
    )
    # Filename pattern matches but content has 'storyline' keyword in comment too...
    # Adjust: use a filename that matches AND content without keyword.
    (tmp_path / "storyline.py").write_text(
        "def hello(): pass\n",
        encoding="utf-8",
    )
    result = detect_companion_archetype(repo_root=tmp_path)
    assert result.archetype == "none"
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_detect.py -v`
Expected: 8 PASS total (3 prior + 5 new).

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_companion_detect.py
git commit -m "$(cat <<'EOF'
test(architect): companion_detect edge cases — override / alt names / DSL / keyword check

Confirms:
- frontmatter override forces all 4 layers present (confidence=stated)
- world layer is optional (character + storyline enough for archetype)
- *_dsl.py file populates storyline_dsl_file field
- personas / bots / companions alias for character-card
- storyline filename WITHOUT keyword inside file → not a storyline (avoids
  false positive on generic files named storyline.py)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 4: Loosen `ai_flow.py` custom-pipeline branch + 2 tests

**Files:**
- Modify: `scripts/architect/ai_flow.py` (`_classify_candidate`)
- Modify: `tests/architect/test_ai_flow.py` (append)

- [ ] **Step 1: Write failing tests**

In `tests/architect/test_ai_flow.py`, append:

```python
def test_custom_pipeline_detected_without_nodes_dir_when_llm_imports(tmp_path: Path):
    """Repro: ai-eden-service has app/pipeline.py + LLM provider imports but
    no nodes/ dir. Should still detect as custom-pipeline."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["openai"]\n', encoding="utf-8"
    )
    app = tmp_path / "app"
    (app / "providers").mkdir(parents=True)
    (app / "providers" / "openai_provider.py").write_text(
        "from openai import OpenAI\nclient = OpenAI()\n", encoding="utf-8"
    )
    (app / "pipeline.py").write_text(
        "from app.providers.openai_provider import client\n"
        "def run(): return client.chat.completions.create(messages=[])\n",
        encoding="utf-8",
    )
    (app / "prompts.toml").write_text(
        '[system]\nbody = "You are an assistant"\n', encoding="utf-8"
    )
    from scripts.architect.ai_flow import detect_ai_flows
    flows = detect_ai_flows(tmp_path)
    assert len(flows) == 1
    assert flows[0].framework == "custom-pipeline"


def test_custom_pipeline_still_requires_pipeline_file(tmp_path: Path):
    """Sanity: openai imports + no pipeline.py → not a flow."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "m"\ndependencies = ["openai"]\n', encoding="utf-8"
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "main.py").write_text(
        "from openai import OpenAI\ndef hello(): pass\n", encoding="utf-8"
    )
    from scripts.architect.ai_flow import detect_ai_flows
    flows = detect_ai_flows(tmp_path)
    assert flows == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_ai_flow.py::test_custom_pipeline_detected_without_nodes_dir_when_llm_imports -v`
Expected: FAIL — current `_classify_candidate` requires `has_nodes_dir`.

- [ ] **Step 3: Loosen branch in `_classify_candidate`**

In `scripts/architect/ai_flow.py`, find the custom-pipeline branch (around line 158-166). REPLACE:

```python
    # Custom pipeline: has pipeline.py + nodes/ + prompts + LLM lib usage.
    has_pipeline_file = any(p.name == "pipeline.py" for p in py_files)
    has_nodes_dir = (candidate / "nodes").is_dir()
    if has_pipeline_file and has_nodes_dir and (has_llm_dep or llm_libs) and prompt_files:
        return AIFlow(
            slug=slug, name=name, framework="custom-pipeline", root_path=rel_root,
            ...
```

With:

```python
    # Custom pipeline: has pipeline.py + LLM signal. Either nodes/ dir OR LLM
    # provider imports in the surrounding files is enough — v4.6 loosened the
    # nodes/ requirement so roll-your-own LLM stacks (like ai-eden-service's
    # app/pipeline.py + app/providers/) get detected.
    has_pipeline_file = any(p.name == "pipeline.py" for p in py_files)
    has_nodes_dir = (candidate / "nodes").is_dir()
    has_llm_provider_imports = any(
        lib in import_text
        for lib in ("from openai", "import openai",
                    "from anthropic", "import anthropic",
                    "from google.generativeai", "import google.generativeai",
                    "from langchain_openai", "from langchain_google_genai")
    )
    if (
        has_pipeline_file
        and (has_nodes_dir or has_llm_provider_imports)
        and (has_llm_dep or llm_libs)
        and (prompt_files or any(p.name.startswith("prompts") for p in py_files))
    ):
        return AIFlow(
            slug=slug, name=name, framework="custom-pipeline", root_path=rel_root,
            ...
```

(Keep the rest of the `AIFlow(...)` construction identical.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_flow.py -v`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/ai_flow.py tests/architect/test_ai_flow.py
git commit -m "$(cat <<'EOF'
fix(architect): loosen custom-pipeline detection — nodes/ dir no longer required (v4.6)

ai_flow._classify_candidate's custom-pipeline branch previously required
`has_pipeline_file AND has_nodes_dir AND (has_llm_dep OR llm_libs) AND
prompt_files`. The nodes/ requirement excluded roll-your-own LLM stacks
like ai-eden-service's app/pipeline.py + app/providers/ + prompts.toml.

Loosened to: `has_pipeline_file AND (has_nodes_dir OR has_llm_provider_imports)
AND (has_llm_dep OR llm_libs) AND (prompt_files OR prompts*.* file)`.

Sanity-preserved: still requires pipeline.py file + LLM signal. Bare openai
import without pipeline.py is still NOT a flow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: Scanner integration

### Task 5: `scan_report.ai_companion` populated

**Files:**
- Modify: `scripts/architect/scan.py`
- Modify: `tests/architect/test_companion_sections.py` (append)

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_companion_sections.py`:

```python
def test_scan_report_includes_ai_companion_key(tmp_path):
    """build_scan_report exposes ai_companion key when archetype detected."""
    import subprocess
    import os
    from scripts.architect.scan import build_scan_report

    # Minimal git repo so scanner doesn't crash on git metadata.
    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    chars = tmp_path / "characters"
    chars.mkdir()
    (chars / "alice.json").write_text('{"name":"Alice"}', encoding="utf-8")
    (tmp_path / "storyline.py").write_text(
        "# storyline beat / progression\n", encoding="utf-8"
    )
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init"],
        cwd=tmp_path, check=True, capture_output=True,
        env={**os.environ, "GIT_AUTHOR_DATE": "2026-05-29T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-29T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "ai_companion" in report
    assert report["ai_companion"]["archetype"] == "ai-companion"
    assert report["ai_companion"]["layers"]["character-card"]["present"] is True


def test_scan_report_ai_companion_none_when_no_signals(tmp_path):
    """No character/storyline → archetype=none, key still present."""
    import subprocess
    import os
    from scripts.architect.scan import build_scan_report

    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "main.py").write_text("def hello(): pass\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init"],
        cwd=tmp_path, check=True, capture_output=True,
        env={**os.environ, "GIT_AUTHOR_DATE": "2026-05-29T00:00:00",
             "GIT_COMMITTER_DATE": "2026-05-29T00:00:00"},
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "ai_companion" in report
    assert report["ai_companion"]["archetype"] == "none"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "scan_report_includes_ai_companion"`
Expected: FAIL with `KeyError: 'ai_companion'`.

- [ ] **Step 3: Wire `detect_companion_archetype` into `scan.py`**

In `scripts/architect/scan.py`, find where `ai_memory` / `ai_rag` get populated (around the `_add_features_inputs` area or wherever v4.3 wired in). After those, add:

```python
    # v4.6 — AI companion archetype detection
    from scripts.architect.companion_detect import detect_companion_archetype
    from dataclasses import asdict

    hub_frontmatter = None
    if vault_project_dir is not None:
        # Try to read project hub frontmatter for archetype override.
        slug = vault_project_dir.name
        hub_path = vault_project_dir / f"{slug}.md"
        if hub_path.is_file():
            try:
                text = hub_path.read_text(encoding="utf-8")
                import re
                fm_match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
                if fm_match:
                    hub_frontmatter = {}
                    for line in fm_match.group(1).splitlines():
                        if ":" in line:
                            k, _, v = line.partition(":")
                            hub_frontmatter[k.strip()] = v.strip().strip('"').strip("'")
            except (OSError, UnicodeDecodeError):
                pass

    companion = detect_companion_archetype(
        repo_root=repo_root,
        hub_frontmatter=hub_frontmatter,
    )
    scan_report["ai_companion"] = {
        "archetype": companion.archetype,
        "confidence": companion.confidence,
        "triggers": companion.triggers,
        "layers": {
            layer_name: asdict(layer_ev)
            for layer_name, layer_ev in companion.layers.items()
        },
    }
```

(Place inside the `build_scan_report` function body, after existing scan steps.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py -v`
Expected: All PASS (11 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/scan.py tests/architect/test_companion_sections.py
git commit -m "$(cat <<'EOF'
feat(architect): scan_report adds ai_companion key (v4.6)

build_scan_report now calls detect_companion_archetype with:
- repo_root for code-evidence walks (character/world/storyline/memory)
- hub_frontmatter from Projects/<P>/<P>.md frontmatter (for archetype override)

Output JSON contains:
  ai_companion: {
      archetype: 'ai-companion' | 'none',
      confidence: 'stated' | 'high' | 'medium',
      triggers: [...],
      layers: {
          'character-card': LayerEvidence asdict,
          'world': LayerEvidence asdict,
          'storyline': LayerEvidence asdict,
          'memory': LayerEvidence asdict,
      }
  }

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: 4 prompt builders + 4 composers

### Task 6: `build_character_card_prompt` + `compose_character_card_note`

**Files:**
- Modify: `scripts/architect/sections.py` (append builders + composers)
- Modify: `tests/architect/test_companion_sections.py` (append)

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_companion_sections.py`:

```python
def test_build_character_card_prompt_requires_9_block_keys():
    from scripts.architect.sections import build_character_card_prompt
    prompt = build_character_card_prompt(
        project="ai-eden",
        layer_evidence={"present": True, "root_paths": ["app/characters/"],
                         "artifact_files": ["app/characters/schema.py"],
                         "confidence": "high"},
        repomix_packed="<files>...</files>",
        output_lang="zh-TW",
    )
    for key in ("summary", "card-schema", "definitions-inventory",
                "prompt-template-binding", "versioning-and-overrides",
                "strengths", "weaknesses", "improvements", "dependencies"):
        assert key in prompt


def test_compose_character_card_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_character_card_note
    blocks = {n: f"body for {n}" for n in (
        "summary", "card-schema", "definitions-inventory",
        "prompt-template-binding", "versioning-and-overrides",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_character_card_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_companion"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        card_count=6, schema_version="v1",
    )
    assert "card-count: 6" in note
    assert "schema-version: v1" in note
    assert "layer: character-card" in note
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "character_card_prompt or compose_character_card"`
Expected: 2 FAILs with `ImportError`.

- [ ] **Step 3: Implement builder + composer**

In `scripts/architect/sections.py`, append:

```python
def build_character_card_prompt(
    *,
    project: str,
    layer_evidence: dict,
    repomix_packed: str,
    output_lang: str,
) -> str:
    """v4.6 character-card layer synthesis prompt. Demands 9 strict-JSON blocks."""
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫散文。Code identifier / 檔案路徑 / "
            "function name / env var / wikilink 檔名段保持英文。"
        )
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = "Write all prose in English. Code identifiers stay verbatim."
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    import json as _json
    evidence_json = _json.dumps(layer_evidence, indent=2, ensure_ascii=False, default=str)

    return "\n".join([
        f"You are documenting the **Character Card** layer for AI-companion project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. NO invention. Empty signal → acknowledge absence.",
        "2. Wikilink-out cross-layer references — use [[ai-flows/world#World state]] etc.",
        "3. Tight bullet shape for strengths/weaknesses: **Title (≤30 char).** clarification (≤80 char).",
        "4. Full prompt body in collapsible callout `> [!quote]-` when system prompt detected.",
        "",
        "## Output: 9 @generated blocks (JSON keys)",
        "",
        "### `summary` — 1 paragraph (card count, format, customization model)",
        "### `card-schema` — data structure + validation rules, cite `code:path:line`",
        "### `definitions-inventory` — markdown table: Name | Source | Key traits | Active",
        "### `prompt-template-binding` — how card → system prompt; variables; full prompt callout",
        "### `versioning-and-overrides` — schema evolution + user-customization paths",
        f"### `strengths` — 3-5 tight bullets",
        f"### `weaknesses` — 3-5 tight bullets + failure modes",
        f"### `improvements` — 3-5 Imps: {improvement_shape}",
        "### `dependencies` — wikilinks only",
        "",
        "Return strict JSON: {\"summary\": \"...\", \"card-schema\": \"...\", ...all 9 keys...}.",
        "",
        "## Layer evidence (scanner signals)",
        evidence_json,
        "",
        "## Repomix-packed module context",
        repomix_packed[:50000],
    ])


def compose_character_card_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    card_count: int,
    schema_version: str | None,
) -> str:
    """Wrap compose_note(section='character-card', ...) + merge frontmatter."""
    note = compose_note(
        section="character-card", project=project, repo_label=repo_label,
        commit=commit, signal_sources=signal_sources, confidence=confidence,
        output_lang=output_lang, generated_blocks=generated_blocks,
    )
    sv = schema_version if schema_version else "unknown"
    extra_fm = (
        f"layer: character-card\n"
        f'depends-on: ["world", "storyline"]\n'
        f"mutated-by: []\n"
        f"card-count: {card_count}\n"
        f"schema-version: {sv}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "character_card"`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_companion_sections.py
git commit -m "$(cat <<'EOF'
feat(architect): build_character_card_prompt + compose_character_card_note (v4.6)

LLM prompt builder + note composer for the Character Card layer (9 blocks).
Encodes 4 critical rules: NO invention, wikilink-out cross-layer refs,
tight bullets, prompt callouts. Composer injects layer-specific frontmatter:
layer / depends-on / mutated-by / card-count / schema-version.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7: `build_world_prompt` + `compose_world_note`

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_companion_sections.py` (append)

- [ ] **Step 1: Append failing tests**

```python
def test_build_world_prompt_requires_10_block_keys():
    from scripts.architect.sections import build_world_prompt
    prompt = build_world_prompt(
        project="ai-eden",
        layer_evidence={"present": True, "root_paths": ["app/characters/worlds/"],
                         "artifact_files": [], "confidence": "high"},
        repomix_packed="", output_lang="zh-TW",
    )
    for key in ("summary", "world-schema", "lore-inventory", "world-state",
                "loading-strategy", "mutation-rules",
                "strengths", "weaknesses", "improvements", "dependencies"):
        assert key in prompt


def test_compose_world_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_world_note
    blocks = {n: f"body" for n in (
        "summary", "world-schema", "lore-inventory", "world-state",
        "loading-strategy", "mutation-rules",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_world_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["x"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        world_count=1, mutable=True,
    )
    assert "world-count: 1" in note
    assert "mutable: true" in note
    assert "layer: world" in note
    assert 'mutated-by: ["storyline"]' in note
```

- [ ] **Step 2: Run to verify failures**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "world_prompt or compose_world"`
Expected: 2 FAILs.

- [ ] **Step 3: Implement builder + composer**

In `scripts/architect/sections.py`, append (mirror Task 6's shape):

```python
def build_world_prompt(
    *,
    project: str,
    layer_evidence: dict,
    repomix_packed: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = "請以繁體中文撰寫。Code identifier 保持英文。"
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = "Write all prose in English."
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    import json as _json
    evidence_json = _json.dumps(layer_evidence, indent=2, ensure_ascii=False, default=str)

    return "\n".join([
        f"You are documenting the **World** layer for AI-companion project `{project}`.",
        f"Output language: {output_lang}. {lang_directive}",
        "",
        "## Critical rules",
        "1. NO invention.",
        "2. Wikilink-out cross-layer refs.",
        "3. Tight bullets for strengths/weaknesses.",
        "",
        "## Output: 10 @generated blocks",
        "",
        "### `summary` — 1 paragraph (world count, static-vs-mutable, multi-world)",
        "### `world-schema` — data structure",
        "### `lore-inventory` — static content index (table or list)",
        "### `world-state` — mutable fields + persistence store",
        "### `loading-strategy` — when loaded into LLM context, cache, token budget",
        "### `mutation-rules` — who mutates, when, conflict resolution",
        "### `strengths` — 3-5 tight bullets",
        "### `weaknesses` — 3-5 (corruption / consistency / token explosion)",
        f"### `improvements` — 3-5 Imps: {improvement_shape}",
        "### `dependencies` — wikilinks only",
        "",
        "Return strict JSON with all 10 keys.",
        "",
        "## Layer evidence",
        evidence_json,
        "",
        "## Repomix-packed module context",
        repomix_packed[:50000],
    ])


def compose_world_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    world_count: int,
    mutable: bool,
) -> str:
    note = compose_note(
        section="world", project=project, repo_label=repo_label,
        commit=commit, signal_sources=signal_sources, confidence=confidence,
        output_lang=output_lang, generated_blocks=generated_blocks,
    )
    extra_fm = (
        f"layer: world\n"
        f"depends-on: []\n"
        f'mutated-by: ["storyline"]\n'
        f"world-count: {world_count}\n"
        f"mutable: {str(mutable).lower()}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "world"`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_companion_sections.py
git commit -m "$(cat <<'EOF'
feat(architect): build_world_prompt + compose_world_note (v4.6)

10-block World layer schema. Composer injects layer / depends-on=[] /
mutated-by=["storyline"] / world-count / mutable frontmatter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `build_storyline_prompt` + `compose_storyline_note`

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_companion_sections.py` (append)

- [ ] **Step 1: Append failing tests**

```python
def test_build_storyline_prompt_requires_11_block_keys():
    from scripts.architect.sections import build_storyline_prompt
    prompt = build_storyline_prompt(
        project="ai-eden",
        layer_evidence={"present": True, "root_paths": [], "artifact_files": [],
                         "storyline_dsl_file": "storyline_dsl.py", "confidence": "high"},
        repomix_packed="", output_lang="zh-TW",
    )
    for key in ("summary", "storyline-dsl", "state-machine", "progression-rules",
                "branching-logic", "persistence", "authoring-workflow",
                "strengths", "weaknesses", "improvements", "dependencies"):
        assert key in prompt


def test_compose_storyline_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_storyline_note
    blocks = {n: "body" for n in (
        "summary", "storyline-dsl", "state-machine", "progression-rules",
        "branching-logic", "persistence", "authoring-workflow",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_storyline_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["x"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        dsl_format="ai-eden-storyline-dsl-v1", branch_count=4,
    )
    assert "dsl-format: ai-eden-storyline-dsl-v1" in note
    assert "branch-count: 4" in note
    assert "layer: storyline" in note
```

- [ ] **Step 2: Run to verify failures**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "storyline_prompt or compose_storyline"`
Expected: 2 FAILs.

- [ ] **Step 3: Implement builder + composer**

```python
def build_storyline_prompt(
    *,
    project: str,
    layer_evidence: dict,
    repomix_packed: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = "請以繁體中文撰寫。Code identifier 保持英文。"
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = "Write all prose in English."
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    import json as _json
    evidence_json = _json.dumps(layer_evidence, indent=2, ensure_ascii=False, default=str)

    return "\n".join([
        f"You are documenting the **Storyline** layer for AI-companion project `{project}`.",
        f"Output language: {output_lang}. {lang_directive}",
        "",
        "## Critical rules",
        "1. NO invention.",
        "2. Wikilink-out cross-layer refs.",
        "3. Mermaid state diagram in `state-machine` block when applicable.",
        "",
        "## Output: 11 @generated blocks",
        "",
        "### `summary` — DSL shape, storyline count, branching, state",
        "### `storyline-dsl` — Grammar + example code block",
        "### `state-machine` — States / transitions / triggers; Mermaid state diagram",
        "### `progression-rules` — When beats advance (intimacy gate / event / time)",
        "### `branching-logic` — Choice points / decision trees / user-input vs LLM",
        "### `persistence` — Storyline state store, cross-session continuity",
        "### `authoring-workflow` — Creator workflow, edit-reload, testing",
        "### `strengths` — 3-5 tight bullets",
        "### `weaknesses` — 3-5 (DSL escape / state drift / authoring barrier)",
        f"### `improvements` — 3-5 Imps: {improvement_shape}",
        "### `dependencies` — wikilinks only",
        "",
        "Return strict JSON with all 11 keys.",
        "",
        "## Layer evidence",
        evidence_json,
        "",
        "## Repomix-packed module context",
        repomix_packed[:50000],
    ])


def compose_storyline_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    dsl_format: str | None,
    branch_count: int | None,
) -> str:
    note = compose_note(
        section="storyline", project=project, repo_label=repo_label,
        commit=commit, signal_sources=signal_sources, confidence=confidence,
        output_lang=output_lang, generated_blocks=generated_blocks,
    )
    dsl_value = dsl_format if dsl_format else "none"
    branch_value = "null" if branch_count is None else str(branch_count)
    extra_fm = (
        f"layer: storyline\n"
        f'depends-on: ["character-card", "world"]\n'
        f'mutated-by: ["memory"]\n'
        f"dsl-format: {dsl_value}\n"
        f"branch-count: {branch_value}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "storyline"`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_companion_sections.py
git commit -m "$(cat <<'EOF'
feat(architect): build_storyline_prompt + compose_storyline_note (v4.6)

11-block Storyline layer schema. Composer injects layer / depends-on /
mutated-by / dsl-format / branch-count frontmatter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: `build_companion_overview_prompt` + `compose_companion_overview_note`

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_companion_sections.py` (append)

- [ ] **Step 1: Append failing tests**

```python
def test_build_companion_overview_prompt_requires_9_block_keys():
    from scripts.architect.sections import build_companion_overview_prompt
    prompt = build_companion_overview_prompt(
        project="ai-eden",
        ai_companion_signals={"archetype": "ai-companion", "confidence": "high",
                              "layers": {}},
        layer_summaries={"character-card": "6 cards", "world": "1 world",
                         "storyline": "WIP DSL", "memory": "none"},
        repomix_packed="", output_lang="zh-TW",
    )
    for key in ("summary", "four-layer-diagram", "data-flow", "bind-points",
                "layer-maturity-table",
                "strengths", "weaknesses", "improvements", "dependencies"):
        assert key in prompt


def test_compose_companion_overview_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_companion_overview_note
    blocks = {n: "body" for n in (
        "summary", "four-layer-diagram", "data-flow", "bind-points",
        "layer-maturity-table",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_companion_overview_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["x"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        layers_stable=2, layers_wip=1, layers_missing=1,
    )
    assert "layers-stable: 2" in note
    assert "layers-wip: 1" in note
    assert "layers-missing: 1" in note
    assert "archetype: ai-companion" in note
    assert "layer: overview" in note
```

- [ ] **Step 2: Run to verify failures**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "companion_overview"`
Expected: 2 FAILs.

- [ ] **Step 3: Implement builder + composer**

```python
def build_companion_overview_prompt(
    *,
    project: str,
    ai_companion_signals: dict,
    layer_summaries: dict[str, str],
    repomix_packed: str,
    output_lang: str,
) -> str:
    if output_lang == "zh-TW":
        lang_directive = "請以繁體中文撰寫。Mermaid node ID 保持英文。"
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = "Write all prose in English. Mermaid node IDs verbatim."
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    import json as _json
    signals_json = _json.dumps(ai_companion_signals, indent=2, ensure_ascii=False, default=str)
    summaries_lines = "\n".join(
        f"- **{name}**: {summary[:300]}"
        for name, summary in layer_summaries.items()
    )

    return "\n".join([
        f"You are documenting the **AI companion 4-layer cross-cutting** report for `{project}`.",
        f"Output language: {output_lang}. {lang_directive}",
        "",
        "## Critical rules",
        "1. NO invention.",
        "2. Wikilink-out per-layer detail. DO NOT rewrite single-layer content here.",
        "3. ONE Mermaid graph in `four-layer-diagram`.",
        "4. Cross-layer Imps only in `improvements` — single-layer Imps belong on per-layer files.",
        "",
        "## Output: 9 @generated blocks",
        "",
        "### `summary` — archetype detected; 4 layers one-line each",
        "### `four-layer-diagram` — ONE Mermaid: Character ↔ World ↔ Storyline ↔ Memory + LLM provider",
        "### `data-flow` — Per-turn: user → which layers consult, in what order → prompt → LLM → mutations",
        "### `bind-points` — Cross-layer contracts; each binding lists owner",
        "### `layer-maturity-table` — Table: Layer | Status (✅/⚠️/❌) | Wikilink | Primary risk",
        "### `strengths` — 3-5 cross-layer bullets",
        "### `weaknesses` — 3-5 cross-layer bullets",
        f"### `improvements` — 3-5 cross-layer Imps: {improvement_shape}",
        "### `dependencies` — wikilinks only",
        "",
        "Return strict JSON with all 9 keys.",
        "",
        "## Per-layer summaries (just-written, do NOT repeat verbatim)",
        summaries_lines,
        "",
        "## AI companion signals",
        signals_json,
        "",
        "## Repomix-packed context",
        repomix_packed[:30000],
    ])


def compose_companion_overview_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    layers_stable: int,
    layers_wip: int,
    layers_missing: int,
) -> str:
    note = compose_note(
        section="companion-overview", project=project, repo_label=repo_label,
        commit=commit, signal_sources=signal_sources, confidence=confidence,
        output_lang=output_lang, generated_blocks=generated_blocks,
    )
    extra_fm = (
        f"layer: overview\n"
        f"archetype: ai-companion\n"
        f"layers-stable: {layers_stable}\n"
        f"layers-wip: {layers_wip}\n"
        f"layers-missing: {layers_missing}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_companion_sections.py -v -k "companion_overview"`
Expected: All PASS.

- [ ] **Step 5: Run full suite for no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_companion_sections.py
git commit -m "$(cat <<'EOF'
feat(architect): build_companion_overview_prompt + compose_companion_overview_note (v4.6)

9-block cross-cutting overview schema. Builder receives layer_summaries
dict (just-written per-layer summaries) + ai_companion_signals. Composer
injects layer=overview / archetype=ai-companion / layers-stable/wip/
missing frontmatter for DataView aggregation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Lockfile

### Task 10: `Lockfile.ai_companion` slot

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_lockfile.py`:

```python
def test_lockfile_ai_companion_slot_round_trip(tmp_path):
    """sections.ai_companion round-trips through Lockfile.save → load (v4.6)."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_companion = {
        "archetype": "ai-companion",
        "confidence": "high",
        "layers": {
            "character-card": {
                "signal-hash": "sha256:abc", "lang": "zh-TW",
                "last-generated": "2026-05-29", "commit": "deadbeef",
                "card-count": 6, "schema-version": "v1",
            },
            "companion-overview": {
                "signal-hash": "sha256:def", "layers-stable": 2,
                "layers-wip": 1, "layers-missing": 1,
            },
        },
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_companion["archetype"] == "ai-companion"
    assert loaded.ai_companion["layers"]["character-card"]["card-count"] == 6
    assert loaded.ai_companion["layers"]["companion-overview"]["layers-stable"] == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lockfile.py -v -k "ai_companion_slot"`
Expected: FAIL with `AttributeError: 'Lockfile' object has no attribute 'ai_companion'`.

- [ ] **Step 3: Add `ai_companion` field to `Lockfile` dataclass**

In `scripts/architect/lockfile.py`, find the `Lockfile` dataclass. Add after existing `ai_rag`:

```python
    ai_rag: dict = field(default_factory=dict)
    # v4.6 — AI companion archetype (Character / World / Storyline / Memory)
    ai_companion: dict = field(default_factory=dict)
```

Also update `write_lockfile` and `load_lockfile` if they handle fields explicitly. If they use `dataclasses.asdict` / `Lockfile(**data)`, no further change needed.

If explicit handling, add:

```python
# In write_lockfile dict assembly:
out["ai_companion"] = lock.ai_companion

# In load_lockfile dict construction:
ai_companion=data.get("ai_companion", {}),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "$(cat <<'EOF'
feat(architect): Lockfile gains ai_companion slot (v4.6)

Additive dataclass field (no schema version bump). Stores per-layer
signal-hash / lang / last-generated / commit + layer-specific
metadata (card-count, schema-version, world-count, mutable,
dsl-format, branch-count, layers-stable/wip/missing).

Old lockfiles load cleanly with ai_companion={} default.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F: Roadmap signal

### Task 11: `detect_candidates` walks 3 new files + cross-layer Evidence priority bump

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_detect_candidates_walks_character_card_md(tmp_path):
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "character-card.md").write_text(
        "---\ntype: architecture-character-card\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Imp 1: 加入 attachment-style segmentation\n"
        "- **為什麼:** persona research 顯示分層 retention 提升\n"
        "- **證據:** [[Research/Web/2026-05-29-companion-chat-vs-story-rpg-retention]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 留存上不去\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("attachment-style" in t for t in titles), (
        f"character-card Imp not picked up; got {titles}"
    )


def test_detect_candidates_companion_overview_cross_layer_priority_high(tmp_path):
    """Imp citing ≥2 layer wikilinks gets priority=high (cross-layer signal)."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "companion-overview.md").write_text(
        "---\ntype: architecture-companion-overview\n---\n\n"
        "## Companion 改進方向\n"
        "<!-- @generated:start improvements -->\n"
        "### Imp 1: Storyline 與 Memory 共用 progression state\n"
        "- **為什麼:** 跨層 state 同步減少 drift\n"
        "- **證據:** [[Architecture/ai-flows/storyline]] | [[Architecture/ai-flows/memory]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** state 不一致\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    imp = next((c for c in cands if "progression state" in c.title), None)
    assert imp is not None
    assert imp.priority == "high"


def test_detect_candidates_companion_overview_single_layer_priority_normal(tmp_path):
    """Imp citing only 1 layer → priority=normal."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "companion-overview.md").write_text(
        "---\ntype: architecture-companion-overview\n---\n\n"
        "## Companion 改進方向\n"
        "<!-- @generated:start improvements -->\n"
        "### Imp 1: Single-layer Imp\n"
        "- **為什麼:** x\n"
        "- **證據:** [[Architecture/ai-flows/storyline]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** y\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    imp = next((c for c in cands if "Single-layer" in c.title), None)
    assert imp is not None
    assert imp.priority == "normal"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "character_card_md or companion_overview"`
Expected: 3 FAILs (candidates not detected).

- [ ] **Step 3: Extend `_extract_ai_cross_flow_candidates` in candidates.py**

In `scripts/roadmap/candidates.py:_extract_ai_cross_flow_candidates`, extend the loop to include 3 new file mappings:

```python
def _extract_ai_cross_flow_candidates(arch_root: Path) -> list[Candidate]:
    out: list[Candidate] = []
    file_mappings = (
        # v4.3
        ("ai-flows/memory.md", "ai-memory-improvement", "normal"),
        ("ai-flows/rag.md", "ai-rag-improvement", "normal"),
        # v4.6 — 4 companion layers
        ("ai-flows/character-card.md", "companion-character-improvement", "normal"),
        ("ai-flows/world.md", "companion-world-improvement", "normal"),
        ("ai-flows/storyline.md", "companion-storyline-improvement", "normal"),
        ("ai-flows/companion-overview.md", "companion-improvement", "normal"),
    )
    for fname, candidate_type, default_priority in file_mappings:
        note_path = arch_root / fname
        if not note_path.exists():
            continue
        try:
            text = note_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        imp_body = _extract_generated_block(text, "improvements")
        if not imp_body:
            continue
        rel = note_path.relative_to(arch_root.parent).as_posix().replace(".md", "")
        for entry in _parse_feature_imp_entries(imp_body):
            priority = default_priority
            evidence_list = entry["evidence"]
            # v4.3 rule: rag.md with embedding-aligned evidence → high
            if fname.endswith("rag.md") and any(
                "embedding-aligned" in evidence.lower() for evidence in evidence_list
            ):
                priority = "high"
            # v4.6 rule: companion-overview.md Imp citing ≥2 layer wikilinks → high
            if fname.endswith("companion-overview.md"):
                layer_wikilink_count = sum(
                    1 for ev in evidence_list
                    if any(
                        f"ai-flows/{layer}" in ev
                        for layer in ("character-card", "world", "storyline", "memory")
                    )
                )
                if layer_wikilink_count >= 2:
                    priority = "high"
            cand = _candidate_from_feature_imp(
                entry, rel=rel, block="improvements",
                kind=candidate_type, priority=priority,
            )
            cand.source = f"{fname}#improvements"
            out.append(cand)
    return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): detect_candidates walks 3 new v4.6 companion files

Adds candidate detection for:
- ai-flows/character-card.md → companion-character-improvement (normal)
- ai-flows/world.md → companion-world-improvement (normal)
- ai-flows/storyline.md → companion-storyline-improvement (normal)
- ai-flows/companion-overview.md → companion-improvement (priority=high
  when Evidence cites ≥2 distinct layer wikilinks — cross-layer Imps
  are high-leverage)

Existing v4.3 rag.md embedding-aligned rule preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G: Command body + AI-first rules + announcement

### Task 12: Phase 3.7.5 in command body + `--no-companion` / `--companion-only` flags

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "^## Phase 3\.7\|^## Phase 3\.8\|^## Phase 4" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-architect.md | head -5
```

- [ ] **Step 2: Add flag descriptions to top of command body**

After the v4.5 `--no-board-refresh` flag block, INSERT:

```markdown
**v4.6-specific flags:**
- `--no-companion` — even when archetype=ai-companion is detected, skip Phase 3.7.5 (companion synthesis). Default OFF.
- `--companion-only` — diagnostic: run Phase 1 + Phase 3.7.5 only. Useful for iterating on companion prompts.
```

- [ ] **Step 3: Insert Phase 3.7.5 between Phase 3.7 and 3.8**

After "Phase 3.7: AI Flow synthesis (v4.1)" closes, insert:

````markdown
## Phase 3.7.5: AI companion archetype synthesis (v4.6)

Skip if `--no-companion` is passed.

Skip if `scan_report["ai_companion"]["archetype"] == "none"`.

For each layer in `["character-card", "world", "storyline"]`:

1. Skip if lockfile `ai_companion.layers[<layer>].signal-hash` matches current signal AND `Architecture/ai-flows/<layer>.md` exists (refresh logic).

2. Run repomix on the layer's `root_paths`:
   ```bash
   repomix --include "<root_paths>" --style xml --compress -o /tmp/repomix-companion-<layer>.xml
   ```

3. Build prompt:
   ```python
   from scripts.architect.sections import build_character_card_prompt, build_world_prompt, build_storyline_prompt
   builder = {"character-card": build_character_card_prompt,
              "world": build_world_prompt,
              "storyline": build_storyline_prompt}[layer]
   prompt = builder(
       project=project_name,
       layer_evidence=scan_report["ai_companion"]["layers"][layer],
       repomix_packed=open(f"/tmp/repomix-companion-{layer}.xml").read(),
       output_lang=output_lang,
   )
   ```

4. Invoke LLM. Expect strict JSON: 9 / 10 / 11 block keys per layer.

5. Compose + write:
   ```python
   from scripts.architect.sections import compose_character_card_note, compose_world_note, compose_storyline_note

   if layer == "character-card":
       note = compose_character_card_note(
           project=project_name, repo_label=repo_label, commit=commit,
           signal_sources=signal_sources, confidence=layer_confidence,
           output_lang=output_lang, generated_blocks=llm_output,
           card_count=<count from evidence.artifact_files>,
           schema_version="v1",  # extract from frontmatter or default
       )
   # similar for world and storyline (different extra-fm kwargs)
   ```

6. Write to `Projects/<P>/Architecture/ai-flows/<layer>.md`.

After 3 per-layer files complete, build companion-overview:

1. Collect per-layer summaries (just-written `summary` block bodies).

2. Build prompt:
   ```python
   from scripts.architect.sections import build_companion_overview_prompt
   prompt = build_companion_overview_prompt(
       project=project_name,
       ai_companion_signals=scan_report["ai_companion"],
       layer_summaries=collected_summaries,
       repomix_packed=high_level_repomix,
       output_lang=output_lang,
   )
   ```

3. Invoke LLM. Expect 9 keys.

4. Compose + write to `Projects/<P>/Architecture/ai-flows/companion-overview.md`:
   ```python
   from scripts.architect.sections import compose_companion_overview_note
   layers_stable = sum(1 for ev in layers.values() if ev["confidence"] == "high")
   layers_wip = sum(1 for ev in layers.values() if ev["confidence"] == "medium")
   layers_missing = sum(1 for ev in layers.values() if ev["confidence"] == "speculation" or not ev["present"])
   note = compose_companion_overview_note(
       ..., layers_stable=layers_stable, layers_wip=layers_wip,
       layers_missing=layers_missing,
   )
   ```

5. Update lockfile `ai_companion` slot:
   ```python
   lockfile.ai_companion = {
       "archetype": scan_report["ai_companion"]["archetype"],
       "confidence": scan_report["ai_companion"]["confidence"],
       "layers": {
           layer: {"signal-hash": sig_hash, "lang": output_lang,
                   "last-generated": today_iso, "commit": commit, ...layer-specific...}
           for layer in ("character-card", "world", "storyline", "companion-overview")
       },
   }
   ```

6. Hub block + overview drill-down (idempotent, sentinel-aware):
   - Hub `Projects/<P>/<P>.md` `## 架構` block: add line `- AI 陪伴 4 層深判斷 (v4.6): [[Architecture/ai-flows/companion-overview]] | [[Architecture/ai-flows/character-card]] | [[Architecture/ai-flows/world]] | [[Architecture/ai-flows/storyline]]`
   - `overview.md ## 想深讀的入口`: add line `- **AI 陪伴 4 層深判斷:** [[ai-flows/companion-overview]] (4-layer dep + data flow) | per-layer: [[ai-flows/character-card]] | [[ai-flows/world]] | [[ai-flows/storyline]]`

If `--companion-only`: skip all other Phases (3, 3.5, 3.5.5, 3.7, 3.8, 3.9, 4, 7); only Phase 1 + 3.7.5 + lockfile + hub-update run.
````

- [ ] **Step 4: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "$(cat <<'EOF'
feat(architect): v4.6 command body — Phase 3.7.5 companion synthesis + flags

Phase 3.7.5 sits between v4.1 ai-flow (3.7) and v4.3 ai-memory (3.8).
Walks 3 per-layer prompts (character-card / world / storyline) →
compose + write per-layer note. After 3 done, builds companion-overview
using just-written summaries.

Flags: --no-companion / --companion-only. Lockfile ai_companion slot
populated with per-layer signal-hash + counts. Hub block + overview
drill-down get 4 new wikilinks (sentinel-aware idempotent).

Skipped paths (no archetype detected / flag passed) log a line; rest
of architect runs unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 13: 4 new schemas in ai-first-rules.md

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "architecture-ai-rag\|architecture-ai-memory\|project-brainstorm" /Users/leric/Desktop/code/obsidian-second-brain/references/ai-first-rules.md | head -5
```

- [ ] **Step 2: Add 4 v4.6 schemas after v4.3 ai-rag**

Insert after the `architecture-ai-rag` section:

````markdown
### `architecture-character-card` (v4.6 — Character Card layer)

**File:** `Projects/<P>/Architecture/ai-flows/character-card.md`

**Frontmatter:**
```yaml
type: architecture-character-card
layer: character-card
depends-on: ["world", "storyline"]
mutated-by: []
card-count: 6
schema-version: v1
...standard v4 fields...
```

**Body blocks** (9 @generated sentinels):
1. `summary` — `## 摘要` / `## Summary`
2. `card-schema` — `## Card schema`
3. `definitions-inventory` — `## 角色定義清單` / `## Definitions inventory` (markdown table)
4. `prompt-template-binding` — full prompt callout `> [!quote]-`
5. `versioning-and-overrides` — schema evolution + user customization
6. `strengths` / `weaknesses` / `improvements` / `dependencies`

### `architecture-world` (v4.6 — World layer)

**File:** `Projects/<P>/Architecture/ai-flows/world.md`

**Frontmatter:**
```yaml
type: architecture-world
layer: world
depends-on: []
mutated-by: ["storyline"]
world-count: 1
mutable: true
...
```

**Body blocks** (10 @generated): summary / world-schema / lore-inventory / world-state / loading-strategy / mutation-rules / strengths / weaknesses / improvements / dependencies.

### `architecture-storyline` (v4.6 — Storyline layer)

**File:** `Projects/<P>/Architecture/ai-flows/storyline.md`

**Frontmatter:**
```yaml
type: architecture-storyline
layer: storyline
depends-on: ["character-card", "world"]
mutated-by: ["memory"]
dsl-format: "<name or none>"
branch-count: <N or null>
...
```

**Body blocks** (11 @generated): summary / storyline-dsl / state-machine (Mermaid) / progression-rules / branching-logic / persistence / authoring-workflow / strengths / weaknesses / improvements / dependencies.

### `architecture-companion-overview` (v4.6 — cross-cutting)

**File:** `Projects/<P>/Architecture/ai-flows/companion-overview.md`

**Frontmatter:**
```yaml
type: architecture-companion-overview
layer: overview
archetype: ai-companion
layers-stable: 2
layers-wip: 1
layers-missing: 1
...
```

**Body blocks** (9 @generated): summary / four-layer-diagram (ONE Mermaid) / data-flow / bind-points / layer-maturity-table / strengths / weaknesses / improvements / dependencies.

**Voice constraints (all 4 v4.6 schemas):**
- NO invention. Empty signal → acknowledge absence.
- Wikilink-out cross-layer references; do not rehash per-layer content in overview.
- Strengths / weaknesses follow tight bullet shape from v3.1.
- ImprovementItem shape for improvements: `Why / Evidence / Effort / Risk if not done / Confidence`.

**Detection (v4.6):**
- Auto-detect: character + storyline signals BOTH present.
- Frontmatter override: `archetype: ai-companion` in project hub forces all 4 layers present.
- Memory layer reuses v4.3 `architecture-ai-memory` schema (not duplicated in v4.6).
````

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "$(cat <<'EOF'
docs(ai-first-rules): 4 v4.6 architecture-* schemas (companion archetype)

Defines schemas for character-card / world / storyline /
companion-overview. Block counts: 9 / 10 / 11 / 9. Frontmatter layer-
specific fields documented. Voice constraints + detection rules
referenced from main spec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 14: SKILL.md + README.md + CHANGELOG.md announcement

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md**

Find the `/obsidian-architect` description. Append:

```markdown
- **v4.6 (2026-05-29):** Adds AI companion-bot **archetype detection** + 4-layer
  schema (Character Card / World / Storyline + reuse v4.3 Memory) + cross-cutting
  companion-overview. Auto-detect requires character + storyline both present;
  `archetype: ai-companion` frontmatter override available. Phase 3.7.5 in
  command body. Flags `--no-companion` / `--companion-only`. Detector bug
  fixed: custom-pipeline no longer requires `nodes/` dir.
```

- [ ] **Step 2: Update README.md command description**

Update the `/obsidian-architect` row's description:

```markdown
| `/obsidian-architect <repo>` | Scan codebase + generate v4 architecture report + v4.1 AI flows + v4.2 features lens + v4.3 memory/RAG cross-flow + v4.5 board refresh + v4.6 AI companion archetype (4-layer schema for Character Card / World / Storyline projects) |
```

- [ ] **Step 3: Update CHANGELOG.md**

Append to existing `## [Unreleased]` section:

```markdown
- `/obsidian-architect` v4.6 — AI companion archetype detection + 4-layer
  schema. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-architect-v4.6-companion-archetype-design.md`.

  New module: `scripts/architect/companion_detect.py` with
  `detect_companion_archetype()` + `CompanionDetection` + `LayerEvidence`
  dataclasses. Auto-detect rule: character + storyline both present.
  Frontmatter `archetype: ai-companion` override.

  4 new section types: `character-card` (9 blocks) / `world` (10) /
  `storyline` (11) / `companion-overview` (9). 19 new heading mappings
  in `lang.py` with zh-TW translations.

  Detector loosened (`scripts/architect/ai_flow.py`): custom-pipeline
  no longer requires `nodes/` dir when LLM provider imports + prompts
  file present. Fixes "0 AI flows detected" miss on
  ai-eden-service-style stacks.

  Phase 3.7.5 in command body. Flags `--no-companion` / `--companion-only`.
  Lockfile gains `ai_companion: dict` slot. Roadmap candidate detector
  walks 3 new files; companion-overview Imp citing ≥2 layer wikilinks
  → priority `high`.
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+readme+changelog): v4.6 AI companion archetype announcement

SKILL.md gains a v4.6 bullet on /obsidian-architect; README's command
table mentions companion archetype; CHANGELOG Unreleased details new
module + 4 section types + detector loosening + Phase 3.7.5 + lockfile
slot + roadmap walk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H: Acceptance smoke

### Task 15: Verify detector + scan_report against ai-eden-service

**Files:** No code changes.

- [ ] **Step 1: Run scanner end-to-end against ai-eden-service**

```bash
HASH=$(date +%s)
OUT=/tmp/architect-v4.6-smoke-$HASH
mkdir -p "$OUT"
uv run python scripts/architect_scan.py /Users/leric/Desktop/code/ai-eden-service \
  --out "$OUT" \
  --vault-project-dir /Users/leric/Documents/SecondBrain/Projects/ai-eden-service
```

Expected: scanner runs without errors.

- [ ] **Step 2: Verify ai_companion key + per-layer evidence**

```bash
uv run python -c "
import json
with open('$OUT/scan-report.json') as f:
    d = json.load(f)
print('keys with ai_:', sorted(k for k in d if k.startswith('ai_')))
ac = d['ai_companion']
print(f'archetype: {ac[\"archetype\"]}')
print(f'confidence: {ac[\"confidence\"]}')
print(f'triggers: {ac[\"triggers\"]}')
for layer_name, ev in ac['layers'].items():
    print(f'  {layer_name}: present={ev[\"present\"]} confidence={ev[\"confidence\"]}')
    if ev.get('root_paths'):
        print(f'    root_paths: {ev[\"root_paths\"][:3]}')
"
```

Expected output:
- `ai_companion` key present
- `archetype: ai-companion`
- `confidence: high`
- `triggers` lists character + storyline evidence
- `character-card.present == True` with `root_paths` containing `app/characters/`
- `storyline.present == True`
- `world.present == True` (ai-eden has `app/characters/worlds/`)

- [ ] **Step 3: Verify v4.1 ai_flow detector now picks up app/pipeline.py**

```bash
uv run python -c "
import json
with open('$OUT/scan-report.json') as f:
    d = json.load(f)
print('ai_flows count:', len(d['ai_flows']))
for f in d['ai_flows']:
    print(f'  - {f[\"slug\"]}: framework={f[\"framework\"]} root={f[\"root_path\"]}')
"
```

Expected: ai_flows ≥ 1 (likely `app` or similar slug, framework=custom-pipeline). This is the v4.6 detector loosening kicking in.

- [ ] **Step 4: Run full test suite**

```bash
uv run pytest tests/ -q
```

Expected: All PASS (437 prior + ~28 new from this plan = ~465).

- [ ] **Step 5: Verify all 4 adapter builds**

```bash
bash scripts/build.sh
```

Expected: 4 platforms build OK.

- [ ] **Step 6: No commit — acceptance only**

If any step fails, write a `## Blocker` note at the top of this plan file describing observed mismatch + stop. Otherwise print `ALL TASKS COMPLETE`.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal | All 15 tasks |
| Scope (6 sub-areas) | 1 (sections+lang) / 2-4 (detector+ai_flow) / 5 (scan) / 6-9 (4 builders+composers) / 10 (lockfile) / 11 (roadmap) / 12 (command+flags) / 13 (ai-first) / 14 (announce) |
| 4-layer file shape | Task 1 |
| Frontmatter shape | Tasks 6-9 (composers inject) |
| Body block design (9/10/11/9) | Task 1 (registration), Tasks 6-9 (prompts demand them) |
| Voice constraints | Tasks 6-9 prompt builders include them |
| Detection (auto + frontmatter override) | Tasks 2-3 (`detect_companion_archetype`) + Task 5 (scan reads hub frontmatter) |
| Detection rules (character + storyline both required) | Task 2 happy path tests |
| ai_flow.py loosening | Task 4 |
| Scanner integration | Task 5 |
| LLM synthesis (4 builders) | Tasks 6-9 |
| Composers + extra frontmatter | Tasks 6-9 |
| Lockfile slot | Task 10 |
| Refresh logic | Task 12 (Phase 3.7.5 body documents signal-hash composition) |
| Roadmap integration (3 new files + cross-layer priority) | Task 11 |
| Command surface (flags + Phase 3.7.5) | Task 12 |
| Hub + overview drill-down | Task 12 (idempotent edits in Phase 3.7.5 step 6) |
| Migration / existing-vault | (additive — no migration needed; implicit) |
| Tests 1-27 | Distributed: detect (Tasks 2-3: 8), sections (Tasks 1, 6-9: 13), ai_flow (Task 4: 2), lockfile (Task 10: 1), roadmap (Task 11: 3); total 27 → over-coverage actual: ~28 |
| Out-of-scope items | (Per-character files / storyline visualizer / auto prompt extraction — NOT implemented) |
| Success criteria | Task 15 (smoke against ai-eden-service) |
