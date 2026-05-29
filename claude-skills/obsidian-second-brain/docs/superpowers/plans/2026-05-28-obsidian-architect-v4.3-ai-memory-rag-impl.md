## Resolution log

All four codex-run blockers resolved inline (Tasks 2, 3, 6, 15):

**Task 2 — `_REDUCER_DEF_RE` unterminated character set.** The plan's regex
`r"...->\s*[A-Za-z\[\]"` had an unterminated character class. Replaced with the
tighter pattern from spec `r"def\s+(?P<name>add_messages\w*|\w+_reducer)\s*\("`,
which matches the langlive `add_messages_limited` case and is anchored to
function names containing `add_messages*` or `*_reducer`. Implementation in
`scripts/architect/ai_memory_detect.py`; 7 tests pass (Task 2 + Task 3 edge
cases folded into one file, plus the false-positive guard added below).

**Task 3 — depends on Task 2.** Resolved with Task 2 (4 edge-case tests sit
next to the happy-path tests in the same file).

**Task 6 — scanner integration.** Added `detect_memory` + `detect_rag` calls
to `scripts/architect/scan.py:run_phase_one`. `scan_report` now exposes
`ai_memory` + `ai_rag` keys. 2 integration tests in
`tests/architect/test_ai_memory_rag_compose.py`.

**Task 15 — smoke surfaced 3 detector false-positives.** Re-run scanner against
langlive-line-oa found:

1. `backends=['base', 'redis']` — `langgraph.checkpoint.base` is the abstract
   base module, not a backend. Fixed via `_LANGGRAPH_CHECKPOINT_NON_BACKEND`
   exclusion set (`base` / `serde` / `__init__` / `abc`).
2. `qdrant` false-positive — `mem0_memory.py` contains the literal string
   `"qdrant"` as a config option. Fixed by tightening `_VECTOR_STORE_HINTS`
   to require import-pattern matches (`"import weaviate"`, `"qdrant_client"`)
   rather than bare substrings.
3. `role=both` for both flows — `qa_to_kb/evaluation/` contains eval-only
   code exercising both read + write paths. Fixed by skipping `evaluation/`,
   `tests/`, `test/`, `examples/`, `__pycache__/` subdirectories in role
   classification (still counted for vector store / embedding / rerank
   inventory; those signals are valid wherever they appear).

3 new tests lock the fixes in (one per false-positive).

**One known limitation:** for langlive, `embedding_aligned: true` is reported
even though the production retrieve path (engines using Gemini
`text-embedding-004`) does NOT align with qa_to_kb's writes (OpenAI
`text-embedding-3-small`). Cause: engines is a genuine `role=both` flow (does
both `/load-data` writes AND FAQ retrieve reads) AND its code references
BOTH embedding model strings. The detector aggregates all per-flow models
into both write+read sets, so they appear aligned at set level. Per-call-site
model attribution is out of scope for regex-level detection — the LLM
synthesis prompt for `rag.md` has access to all per-flow signals and can
surface this nuance in prose. (Possible future enhancement: track which
embedding model lives in which file, then map files to read vs write call
sites.)

**Final state:** 395 tests pass (319 baseline + 76 across v4.1 / v4.2 / v4.3);
4 platform adapters build; langlive smoke returns clean memory data
(redis backend correctly identified, no `base` pollution) and correct role
classification for both flows (engines=both, qa_to_kb=write).

# obsidian-architect v4.3 (AI memory + RAG cross-flow notes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `/obsidian-architect` detects ≥1 AI flow, additionally produce `Architecture/ai-flows/memory.md` (lifecycle / TTL / compaction / context-window) and `Architecture/ai-flows/rag.md` (ingest → vector store → retrieve pipeline, with embedding alignment check). Two new cross-flow notes that complement v4.1 per-flow notes.

**Architecture:** Pure additive layer. Two new pure-function helpers (`ai_memory_detect.py`, `ai_rag_detect.py`) walk each AI flow's `root_path` and return signal dicts. Scanner wires them into `scan_report["ai_memory"]` + `scan_report["ai_rag"]`. `sections.py` registers two new section types (`ai-memory`, `ai-rag`) with 11 blocks each + new `_BLOCK_HEADINGS` entries + `build_ai_memory_prompt` / `build_ai_rag_prompt` / `compose_ai_memory_note` / `compose_ai_rag_note`. Lockfile gains `ai_memory` + `ai_rag` dict slots (additive; no schema bump). Roadmap candidate detector walks both new files; `embedding_aligned: false` evidence raises priority to `high`. Command body adds Phase 3.8 + Phase 3.9 between existing 3.7 (per-flow AI notes) and Phase 4 (overview).

**Tech Stack:** Python 3.10+, pytest, `pathlib`, existing v4.1 `detect_ai_flows` / `AIFlow` dataclass, existing v4 `compose_note` / `_BLOCK_NAMES` plumbing, existing v4.2 `compose_features_note` extra-frontmatter pattern.

**Plan-level note on test commands:** Run from repo root `/Users/leric/Desktop/code/obsidian-second-brain` with `uv run pytest tests/path/test_name.py -v`.

**Plan-level note on the codebase's scanner entry point:** The scanner function is `run_phase_one(repo_root, vault_project_dir=None) -> ScanResult` in `scripts/architect/scan.py`. A second wrapper `build_scan_report(...)` returns the JSON-serializable dict. Test fixtures will call `build_scan_report` and inspect its return dict.

**Plan-level note on commit messages:** Every commit ends with
```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**Plan-level note on `dist/`:** `dist/` is gitignored. Do NOT include it in `git add` — staging commands in this plan list only source files.

**Plan-level note on `ModuleNotFoundError` test runs:** When a test imports a module that doesn't exist yet, pytest emits a COLLECTION ERROR rather than a per-test FAIL. The error message still says "ModuleNotFoundError"; this is the expected "RED" state for TDD purposes. Don't be alarmed by the wording difference.

---

## File structure (locked here so tasks reference consistent paths)

**New files:**
- `scripts/architect/ai_memory_detect.py` — `detect_memory(repo_root: Path, ai_flows: list) -> dict`. Pure function. Walks each flow's `root_path`, returns per-flow + summary signal dict.
- `scripts/architect/ai_rag_detect.py` — `detect_rag(repo_root: Path, ai_flows: list) -> dict`. Pure function. Same shape; computes `embedding_aligned` cross-flow.
- `tests/architect/test_ai_memory_detect.py` — 5 tests for memory detection patterns.
- `tests/architect/test_ai_rag_detect.py` — 7 tests for RAG detection + alignment.
- `tests/architect/test_ai_memory_rag_compose.py` — 5 tests for prompt builders + composers.

**Modified files:**
- `scripts/architect/sections.py` — register `ai-memory` + `ai-rag` in `SECTION_TYPES` + `_BLOCK_NAMES`; add `build_ai_memory_prompt`, `build_ai_rag_prompt`, `compose_ai_memory_note`, `compose_ai_rag_note`; add preamble entries.
- `scripts/architect/lang.py` — add 10 new heading mappings.
- `scripts/architect/scan.py` — wire `detect_memory` + `detect_rag` into `build_scan_report`.
- `scripts/architect/lockfile.py` — add `ai_memory: dict` + `ai_rag: dict` fields on `Lockfile` dataclass.
- `scripts/roadmap/candidates.py` — walk `ai-flows/memory.md` + `ai-flows/rag.md`; embedding-aligned evidence → priority `high`.
- `tests/architect/test_lockfile.py` — round-trip test for new slots.
- `tests/architect/test_lang.py` — heading map test for v4.3 keys.
- `tests/roadmap/test_candidates.py` — 2 tests for new file walks + priority bump.
- `commands/obsidian-architect.md` — Phase 3.8 + Phase 3.9 + flags + hub/overview links.
- `references/ai-first-rules.md` — `architecture-ai-memory` + `architecture-ai-rag` schemas.
- `SKILL.md` — v4.3 announcement bullet.
- `README.md` — mention v4.3 layer in command description.
- `CHANGELOG.md` — `## [Unreleased]` entry.

---

## Phase A: Foundation (sections.py registration)

### Task 1: Register `ai-memory` + `ai-rag` section types + 22 blocks + 10 headings + preambles

**Files:**
- Modify: `scripts/architect/sections.py` (3 spots: `SECTION_TYPES`, `_BLOCK_NAMES`, `_preamble_for`)
- Modify: `scripts/architect/lang.py` (HEADING_MAP)
- Test: `tests/architect/test_ai_memory_rag_compose.py` (new file)
- Test: `tests/architect/test_lang.py` (append)

- [ ] **Step 1: Create new test file with registration smoke**

Create `tests/architect/test_ai_memory_rag_compose.py`:
```python
"""v4.3 AI memory + RAG cross-flow tests."""
from __future__ import annotations

from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS


def test_ai_memory_section_type_present():
    assert SECTION_TYPES["ai-memory"] == "architecture-ai-memory"


def test_ai_rag_section_type_present():
    assert SECTION_TYPES["ai-rag"] == "architecture-ai-rag"


def test_ai_memory_block_names_v4_3():
    expected = (
        "summary",
        "flow-memory-map",
        "backend-and-storage",
        "scope-and-lifecycle",
        "context-window-management",
        "compaction-strategy",
        "long-term-vs-short",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    )
    assert _BLOCK_NAMES["ai-memory"] == expected


def test_ai_rag_block_names_v4_3():
    expected = (
        "summary",
        "rag-data-flow",
        "ingest-pipeline",
        "vector-store-config",
        "retrieve-strategy",
        "embedding-providers",
        "evaluation",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    )
    assert _BLOCK_NAMES["ai-rag"] == expected


def test_v4_3_new_block_headings_registered():
    """All v4.3-specific block names must have entries in _BLOCK_HEADINGS."""
    new_blocks = [
        "flow-memory-map", "backend-and-storage", "scope-and-lifecycle",
        "context-window-management", "compaction-strategy", "long-term-vs-short",
        "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers",
    ]
    for block in new_blocks:
        assert block in _BLOCK_HEADINGS, f"missing heading for {block}"
```

- [ ] **Step 2: Append lang.py heading map test**

In `tests/architect/test_lang.py`, append:
```python
def test_heading_map_includes_v4_3_keys():
    """v4.3 introduces 10 new H2 headings across memory.md + rag.md."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        # memory.md
        "## Per-flow memory map": "## 各流程記憶機制",
        "## Backend & storage": "## 儲存層",
        "## Scope & lifecycle": "## 範疇與生命週期",
        "## Context window management": "## Context window 管理",
        "## Compaction strategy": "## 壓縮策略",
        "## Long-term vs short-term memory": "## 長期 vs 短期記憶",
        # rag.md
        "## RAG data flow": "## RAG 資料流",
        "## Ingest pipeline": "## Ingest 管線",
        "## Vector store config": "## Vector store 設定",
        "## Retrieve strategy": "## Retrieve 策略",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py tests/architect/test_lang.py::test_heading_map_includes_v4_3_keys -v`
Expected: FAILs — missing keys in `SECTION_TYPES` / `_BLOCK_NAMES` / `HEADING_MAP`.

- [ ] **Step 4: Add SECTION_TYPES entries**

In `scripts/architect/sections.py`, find `SECTION_TYPES = { ... }` (around line 37). Append two entries inside the dict (place them after the existing `ai-flow` entry):

```python
    "ai-flow": "architecture-ai-flow",
    # v4.3 cross-flow lenses
    "ai-memory": "architecture-ai-memory",
    "ai-rag": "architecture-ai-rag",
}
```

- [ ] **Step 5: Add `_BLOCK_NAMES` entries**

In `_BLOCK_NAMES` dict (around line 144), append (after the existing `ai-flow` entry):

```python
    # v4.3 — cross-flow AI memory lens (lifecycle / TTL / compaction).
    "ai-memory": (
        "summary",
        "flow-memory-map",
        "backend-and-storage",
        "scope-and-lifecycle",
        "context-window-management",
        "compaction-strategy",
        "long-term-vs-short",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    ),
    # v4.3 — cross-flow RAG lens (ingest → store → retrieve).
    "ai-rag": (
        "summary",
        "rag-data-flow",
        "ingest-pipeline",
        "vector-store-config",
        "retrieve-strategy",
        "embedding-providers",
        "evaluation",
        "strengths",
        "weaknesses",
        "improvements",
        "dependencies",
    ),
}
```

- [ ] **Step 6: Add heading entries in `_BLOCK_HEADINGS`**

In `_BLOCK_HEADINGS` dict (around line 192), append (place after the v4.1 ai-flow entries):

```python
    # v4.3 memory block headings
    "flow-memory-map": "## Per-flow memory map",
    "backend-and-storage": "## Backend & storage",
    "scope-and-lifecycle": "## Scope & lifecycle",
    "context-window-management": "## Context window management",
    "compaction-strategy": "## Compaction strategy",
    "long-term-vs-short": "## Long-term vs short-term memory",
    # v4.3 rag block headings
    "rag-data-flow": "## RAG data flow",
    "ingest-pipeline": "## Ingest pipeline",
    "vector-store-config": "## Vector store config",
    "retrieve-strategy": "## Retrieve strategy",
    "embedding-providers": "## Embedding providers",
```

(Note: `evaluation` already maps via `## Evaluation` from `## Evaluation & observability` is a separate v4.1 mapping. For ai-rag use just `## Evaluation`; we'll add the simpler mapping in lang.py next step if missing.)

- [ ] **Step 7: Verify `## Evaluation` heading**

Grep for the heading:
```bash
grep "Evaluation" /Users/leric/Desktop/code/obsidian-second-brain/scripts/architect/sections.py
```
If `"evaluation": "## Evaluation"` is missing from `_BLOCK_HEADINGS`, add it next to the rag-data-flow line:
```python
    "evaluation": "## Evaluation",
```
(The v4.1 ai-flow uses `## Evaluation & observability` already; the new ai-rag `evaluation` block name reuses the same KEY but we want simpler heading text. Reusing the same block name means same heading is rendered — that's fine. So if `## Evaluation` is missing add it; if `evaluation` is already present in `_BLOCK_HEADINGS` mapping to `## Evaluation & observability`, leave alone — both files will get `## Evaluation & observability`.)

- [ ] **Step 8: Add zh-TW heading mappings in lang.py**

In `scripts/architect/lang.py`, find the end of `HEADING_MAP` dict (right before the closing `}` and `def heading(...)`). Append:

```python
    # v4.3 memory.md cross-flow lens
    "## Per-flow memory map": {"en": "## Per-flow memory map", "zh-TW": "## 各流程記憶機制"},
    "## Backend & storage": {"en": "## Backend & storage", "zh-TW": "## 儲存層"},
    "## Scope & lifecycle": {"en": "## Scope & lifecycle", "zh-TW": "## 範疇與生命週期"},
    "## Context window management": {
        "en": "## Context window management",
        "zh-TW": "## Context window 管理",
    },
    "## Compaction strategy": {"en": "## Compaction strategy", "zh-TW": "## 壓縮策略"},
    "## Long-term vs short-term memory": {
        "en": "## Long-term vs short-term memory",
        "zh-TW": "## 長期 vs 短期記憶",
    },
    # v4.3 rag.md cross-flow lens
    "## RAG data flow": {"en": "## RAG data flow", "zh-TW": "## RAG 資料流"},
    "## Ingest pipeline": {"en": "## Ingest pipeline", "zh-TW": "## Ingest 管線"},
    "## Vector store config": {"en": "## Vector store config", "zh-TW": "## Vector store 設定"},
    "## Retrieve strategy": {"en": "## Retrieve strategy", "zh-TW": "## Retrieve 策略"},
```

(Note: `## Embedding providers` stays English in both lang per the design — already English in `_BLOCK_HEADINGS`; no lang.py entry needed.)

- [ ] **Step 9: Add preamble entries in `_preamble_for`**

In `scripts/architect/sections.py` `_preamble_for(section, lang)` function (around line 350), in the zh-TW dict, add two entries (place them after the existing `"ai-flow":` entry):

```python
            "ai-flow": "本檔是單一 AI 流程的深判斷 — 包含 graph 結構、state schema、prompts 全文、LLM 設定、評估與設計優缺點。",
            "ai-memory": "本檔是 AI 記憶層的跨流程深判斷 — lifecycle、TTL、compaction、context window 管理。Per-flow state shape 請見 [[Architecture/ai-flows/<slug>#State schema]]。",
            "ai-rag": "本檔是 RAG (retrieval-augmented generation) 跨流程管線深判斷 — ingest → vector store → retrieve、embedding 對齊、評估。Per-flow LLM 設定請見 [[Architecture/ai-flows/<slug>#LLM config]]。",
```

In the en dict, add the corresponding English entries:

```python
            "ai-flow": "Per-AI-subsystem deep dive — graph topology, state schema, full prompts, LLM config, evaluation, design strengths and weaknesses.",
            "ai-memory": "Cross-flow AI memory lens — lifecycle, TTL, compaction, context window management. For per-flow state shape see [[Architecture/ai-flows/<slug>#State schema]].",
            "ai-rag": "Cross-flow RAG (retrieval-augmented generation) lens — ingest → vector store → retrieve, embedding alignment, evaluation. For per-flow LLM config see [[Architecture/ai-flows/<slug>#LLM config]].",
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py tests/architect/test_lang.py -v`
Expected: 5 PASS in `test_ai_memory_rag_compose.py` + all existing lang tests PASS.

- [ ] **Step 11: Run full test suite to confirm no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS (358 prior + 5 new = 363+).

- [ ] **Step 12: Commit**

```bash
git add scripts/architect/sections.py scripts/architect/lang.py tests/architect/test_ai_memory_rag_compose.py tests/architect/test_lang.py
git commit -m "$(cat <<'EOF'
feat(architect): v4.3 — register ai-memory + ai-rag section types + 22 blocks + 10 headings

Adds two new SECTION_TYPES (architecture-ai-memory, architecture-ai-rag)
and two new _BLOCK_NAMES entries with 11 blocks each. Adds 10 zh-TW
heading mappings (Per-flow memory map / Backend & storage / Scope &
lifecycle / Context window management / Compaction strategy / Long-term
vs short-term memory + RAG data flow / Ingest pipeline / Vector store
config / Retrieve strategy). Preamble entries describe the cross-flow
lens angle and direct readers to wikilink-out to per-flow detail.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Memory detector

### Task 2: `detect_memory` happy path — LangGraph custom RedisSaver

**Files:**
- Create: `scripts/architect/ai_memory_detect.py`
- Create: `tests/architect/test_ai_memory_detect.py`

- [ ] **Step 1: Write the failing test**

Create `tests/architect/test_ai_memory_detect.py`:
```python
"""Tests for scripts.architect.ai_memory_detect.detect_memory."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.ai_memory_detect import detect_memory


def test_detects_langgraph_custom_redis_saver(tmp_path: Path):
    """Custom RedisSaver subclass + thread_id-keyed checkpointer construction."""
    flow_root = tmp_path / "backend" / "engines" / "langgraph"
    flow_root.mkdir(parents=True)
    (flow_root / "graphs").mkdir()
    (flow_root / "graphs" / "main.py").write_text(
        "from engines.langgraph.utils.simple_redis_saver import SimpleRedisSaver\n"
        "from redis import Redis\n"
        "def get_checkpointer():\n"
        "    return SimpleRedisSaver(redis_client=Redis(), key_prefix='simple_ckpt_v2')\n"
        "workflow = StateGraph(AgentState)\n"
        "app = workflow.compile(checkpointer=get_checkpointer())\n",
        encoding="utf-8",
    )
    (flow_root / "utils").mkdir()
    (flow_root / "utils" / "simple_redis_saver.py").write_text(
        "from redis import Redis\n"
        "class SimpleRedisSaver:\n"
        "    def put(self, x): pass\n"
        "    def get(self, x): pass\n"
        "    def list(self, x): pass\n",
        encoding="utf-8",
    )

    # Minimal AIFlow shim — only needs slug + root_path.
    class _Flow:
        slug = "engines-langgraph"
        root_path = "backend/engines/langgraph"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["engines-langgraph"]
    assert fm["has_memory"] is True
    assert "redis" in fm["backends"]
    assert "SimpleRedisSaver" in fm["checkpointer_classes"]
    assert any("simple_ckpt_v2" in k for k in fm["key_patterns"])


def test_returns_has_memory_false_when_no_checkpointer(tmp_path: Path):
    """A flow with no checkpointer / saver / memory import reports has_memory=false."""
    flow_root = tmp_path / "modules" / "qa_to_kb"
    flow_root.mkdir(parents=True)
    (flow_root / "pipeline.py").write_text(
        "def run_pipeline(input):\n"
        "    return process(input)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "modules-qa-to-kb"
        root_path = "modules/qa_to_kb"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["modules-qa-to-kb"]
    assert fm["has_memory"] is False
    assert fm["backends"] == []
    assert fm["checkpointer_classes"] == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_ai_memory_detect.py -v`
Expected: COLLECTION ERROR with `ModuleNotFoundError: No module named 'scripts.architect.ai_memory_detect'`.

- [ ] **Step 3: Implement `ai_memory_detect.py`**

Create `scripts/architect/ai_memory_detect.py`:
```python
"""Detect AI memory architecture signals per AI flow.

Pure function. Given a repo root and list of AIFlow records, returns a
dict shaped per the v4.3 spec: per-flow signals + cross-flow summary.

Categories of signal detected:
- Backend: redis / postgres / sqlite / in-memory / file / langchain
- Checkpointer classes (LangGraph Saver subclasses + custom impls)
- Key patterns (string literals near checkpointer construction)
- Reducer funcs + extracted caps (e.g. `result[-N:]`)
- Compaction funcs (summarize / compact / memory_update)

Used by Phase 1 scanner to feed scan_report["ai_memory"]; downstream
LLM synthesis in Phase 3.8 turns this into Architecture/ai-flows/memory.md.
"""
from __future__ import annotations

import re
from pathlib import Path

# ---------- regex patterns ----------

# `from langgraph.checkpoint.X import ...` — captures X.
_LANGGRAPH_CHECKPOINT_RE = re.compile(
    r"from\s+langgraph\.checkpoint\.(?P<backend>\w+)\s+import"
)
# `from langchain.memory import ...` — captures memory class names.
_LANGCHAIN_MEMORY_RE = re.compile(
    r"from\s+langchain\.memory\s+import\s+(?P<names>[\w\s,]+)"
)
# `class FooSaver:` or `class FooSaver(BaseSaver):` — captures class name when name ends with "Saver".
_CUSTOM_SAVER_CLASS_RE = re.compile(
    r"class\s+(?P<name>\w*Saver)\b"
)
# `key_prefix=` or `key_prefix =` followed by string literal — captures pattern.
_KEY_PREFIX_RE = re.compile(
    r"key_prefix\s*=\s*['\"](?P<pattern>[^'\"]+)['\"]"
)
# Reducer function defs: `def <name>(left, right) -> List[...]:` shape.
_REDUCER_DEF_RE = re.compile(
    r"def\s+(?P<name>\w*(?:reduce|reducer|messages|merge)\w*)\s*\([^)]*\)\s*->\s*[A-Za-z\[\]"
)
# Reducer cap extraction: `result[-N:]` or `result[:N]`.
_REDUCER_CAP_RE = re.compile(
    r"(?:return\s+)?\w+\s*\[\s*-?(?P<n>\d+)\s*:\s*\]"
)
# Compaction function defs.
_COMPACTION_FUNC_RE = re.compile(
    r"def\s+(?P<name>\w*(?:summari[sz]e|compact|memory_update)\w*)\s*\("
)

_BACKEND_HINTS = {
    "memory": "in-memory",
    "redis": "redis",
    "postgres": "postgres",
    "sqlite": "sqlite",
    "duckdb": "duckdb",
}


def detect_memory(repo_root: Path, ai_flows: list) -> dict:
    """Walk each AI flow's root_path; aggregate per-flow + summary memory signals.

    `ai_flows` is a list of objects with `slug: str` and `root_path: str` attrs
    (matches the v4.1 `AIFlow` dataclass; tests use a lightweight shim).
    """
    repo_root = repo_root.resolve()
    per_flow: dict[str, dict] = {}

    for flow in ai_flows:
        flow_dir = repo_root / flow.root_path
        if not flow_dir.is_dir():
            per_flow[flow.slug] = _empty_flow_record()
            continue
        per_flow[flow.slug] = _scan_flow(flow_dir, repo_root)

    # Summary.
    memory_flows = sum(1 for v in per_flow.values() if v["has_memory"])
    stateless_flows = len(per_flow) - memory_flows
    all_backends: set[str] = set()
    for v in per_flow.values():
        all_backends.update(v["backends"])

    if not all_backends:
        primary = "none"
        uniform = True
    elif len(all_backends) == 1:
        primary = next(iter(all_backends))
        uniform = True
    else:
        primary = "mixed"
        uniform = False

    return {
        "per_flow": per_flow,
        "summary": {
            "memory_flows": memory_flows,
            "stateless_flows": stateless_flows,
            "primary_backend": primary,
            "uniform_backend": uniform,
        },
    }


def _empty_flow_record() -> dict:
    return {
        "has_memory": False,
        "backends": [],
        "checkpointer_classes": [],
        "checkpointer_sources": [],
        "key_patterns": [],
        "reducer_funcs": [],
        "reducer_caps": [],
        "compaction_funcs": [],
        "compaction_sources": [],
    }


def _scan_flow(flow_dir: Path, repo_root: Path) -> dict:
    backends: set[str] = set()
    checkpointer_classes: list[str] = []
    checkpointer_sources: list[str] = []
    key_patterns: list[str] = []
    reducer_funcs: list[str] = []
    reducer_caps: list[dict] = []
    compaction_funcs: list[str] = []
    compaction_sources: list[str] = []

    for py_file in flow_dir.rglob("*.py"):
        try:
            text = py_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = py_file.relative_to(repo_root).as_posix()

        for m in _LANGGRAPH_CHECKPOINT_RE.finditer(text):
            backend_label = _BACKEND_HINTS.get(m.group("backend"), m.group("backend"))
            backends.add(backend_label)
        if _LANGCHAIN_MEMORY_RE.search(text):
            backends.add("langchain")
        for m in _CUSTOM_SAVER_CLASS_RE.finditer(text):
            name = m.group("name")
            if name in checkpointer_classes:
                continue
            checkpointer_classes.append(name)
            checkpointer_sources.append(rel)
            # Infer backend from class name when possible.
            lname = name.lower()
            if "redis" in lname:
                backends.add("redis")
            elif "postgres" in lname or "pg" in lname:
                backends.add("postgres")
            elif "sqlite" in lname:
                backends.add("sqlite")
            elif "file" in lname or "disk" in lname:
                backends.add("file")
        for m in _KEY_PREFIX_RE.finditer(text):
            pat = m.group("pattern")
            if pat not in key_patterns:
                key_patterns.append(pat)
        for m in _REDUCER_DEF_RE.finditer(text):
            name = m.group("name")
            if name in reducer_funcs:
                continue
            reducer_funcs.append(name)
            # Look ahead ~40 lines for a cap pattern.
            tail = text[m.end():]
            cap_m = _REDUCER_CAP_RE.search(tail[:2000])
            if cap_m:
                reducer_caps.append({
                    "name": name,
                    "limit": int(cap_m.group("n")),
                    "source": rel,
                })
        for m in _COMPACTION_FUNC_RE.finditer(text):
            name = m.group("name")
            if name in compaction_funcs:
                continue
            compaction_funcs.append(name)
            compaction_sources.append(rel)

    has_memory = bool(backends or checkpointer_classes or compaction_funcs)
    return {
        "has_memory": has_memory,
        "backends": sorted(backends),
        "checkpointer_classes": checkpointer_classes,
        "checkpointer_sources": checkpointer_sources,
        "key_patterns": key_patterns,
        "reducer_funcs": reducer_funcs,
        "reducer_caps": reducer_caps,
        "compaction_funcs": compaction_funcs,
        "compaction_sources": compaction_sources,
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_detect.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/ai_memory_detect.py tests/architect/test_ai_memory_detect.py
git commit -m "$(cat <<'EOF'
feat(architect): ai_memory_detect — per-flow memory backend + checkpointer + reducer detection

Pure-function detector. Walks each AI flow's root_path, returns per-flow
signal dict (has_memory, backends, checkpointer classes, key patterns,
reducer funcs + caps, compaction funcs) plus cross-flow summary
(memory_flows, stateless_flows, primary_backend, uniform_backend).

Detection patterns: langgraph.checkpoint.X imports for backend labels,
*Saver class names for custom checkpointer detection, key_prefix=
literals, reducer-shape function defs with `result[-N:]` cap extraction,
summarize/compact/memory_update function names.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: `detect_memory` edge cases — langchain memory + reducer cap + langgraph in-memory

**Files:**
- Modify: `tests/architect/test_ai_memory_detect.py` (append)

- [ ] **Step 1: Append edge-case tests**

```python
def test_detects_langgraph_in_memory_checkpointer(tmp_path: Path):
    """`from langgraph.checkpoint.memory import MemorySaver` → in-memory backend."""
    flow_root = tmp_path / "agents" / "small"
    flow_root.mkdir(parents=True)
    (flow_root / "graph.py").write_text(
        "from langgraph.checkpoint.memory import MemorySaver\n"
        "from langgraph.graph import StateGraph\n"
        "checkpointer = MemorySaver()\n"
        "g = StateGraph(dict)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "agents-small"
        root_path = "agents/small"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["agents-small"]
    assert fm["has_memory"] is True
    assert "in-memory" in fm["backends"]


def test_detects_langchain_memory(tmp_path: Path):
    """`from langchain.memory import ConversationBufferMemory` → langchain backend."""
    flow_root = tmp_path / "agents" / "chat"
    flow_root.mkdir(parents=True)
    (flow_root / "agent.py").write_text(
        "from langchain.memory import ConversationBufferMemory\n"
        "memory = ConversationBufferMemory()\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "agents-chat"
        root_path = "agents/chat"

    result = detect_memory(tmp_path, [_Flow()])
    assert "langchain" in result["per_flow"]["agents-chat"]["backends"]


def test_extracts_reducer_cap_from_slice(tmp_path: Path):
    """`def add_messages_limited(...) -> List: ... return result[-100:]` → cap=100."""
    flow_root = tmp_path / "engine"
    flow_root.mkdir(parents=True)
    (flow_root / "state.py").write_text(
        "from typing import List\n"
        "def add_messages_limited(left: List, right: List) -> List[str]:\n"
        "    if not isinstance(left, list): left = []\n"
        "    if not isinstance(right, list): right = []\n"
        "    result = left + right\n"
        "    return result[-100:]\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engine"
        root_path = "engine"

    result = detect_memory(tmp_path, [_Flow()])
    fm = result["per_flow"]["engine"]
    assert "add_messages_limited" in fm["reducer_funcs"]
    caps = {c["name"]: c["limit"] for c in fm["reducer_caps"]}
    assert caps.get("add_messages_limited") == 100


def test_summary_primary_backend_uniform(tmp_path: Path):
    """When 2 flows both have memory + same backend, summary reports uniform."""
    for slug in ("a", "b"):
        d = tmp_path / slug
        d.mkdir()
        (d / "saver.py").write_text(
            "class FooRedisSaver:\n"
            "    def put(self, x): pass\n"
            "    def get(self, x): pass\n"
            "    def list(self, x): pass\n",
            encoding="utf-8",
        )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_memory(tmp_path, [_Flow("a"), _Flow("b")])
    s = result["summary"]
    assert s["memory_flows"] == 2
    assert s["stateless_flows"] == 0
    assert s["primary_backend"] == "redis"
    assert s["uniform_backend"] is True
```

- [ ] **Step 2: Run tests to verify they pass (implementation already covers these patterns)**

Run: `uv run pytest tests/architect/test_ai_memory_detect.py -v`
Expected: 6 PASS total (2 prior + 4 new).

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_ai_memory_detect.py
git commit -m "$(cat <<'EOF'
test(architect): ai_memory_detect edge cases — langgraph in-memory / langchain / reducer cap / uniform summary

Confirms detection of:
- `from langgraph.checkpoint.memory` → backend=in-memory
- `from langchain.memory` → backend=langchain
- Reducer cap extraction from `result[-N:]` slice
- summary.primary_backend="redis" + uniform_backend=true when 2 flows
  share the same backend signal

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: RAG detector

### Task 4: `detect_rag` happy path — Weaviate retrieve + role classifier

**Files:**
- Create: `scripts/architect/ai_rag_detect.py`
- Create: `tests/architect/test_ai_rag_detect.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_ai_rag_detect.py`:
```python
"""Tests for scripts.architect.ai_rag_detect.detect_rag."""
from __future__ import annotations

from pathlib import Path

from scripts.architect.ai_rag_detect import detect_rag


def test_detects_weaviate_retrieve_role_read(tmp_path: Path):
    """Flow calling `.similarity_search` + `.hybrid` → role='read', vector_store=weaviate."""
    flow_root = tmp_path / "engines"
    flow_root.mkdir()
    (flow_root / "retrieve.py").write_text(
        "import weaviate\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "vs = WeaviateVectorStore(client=weaviate.Client('http://x'))\n"
        "def retrieve(query):\n"
        "    return vs.similarity_search(query, k=12)\n",
        encoding="utf-8",
    )
    (flow_root / "embed.py").write_text(
        "from langchain_google_genai import GoogleGenerativeAIEmbeddings\n"
        "embedding = GoogleGenerativeAIEmbeddings(model='models/text-embedding-004')\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engines"
        root_path = "engines"

    result = detect_rag(tmp_path, [_Flow()])
    fr = result["per_flow"]["engines"]
    assert fr["role"] == "read"
    assert "weaviate" in fr["vector_stores"]
    assert "google_generativeai" in fr["embedding_libs"]
    assert "models/text-embedding-004" in fr["embedding_models"]


def test_detects_top_k_and_alpha_params(tmp_path: Path):
    """Regex extracts top_k= and hybrid_alpha= from retrieve calls."""
    flow_root = tmp_path / "engines"
    flow_root.mkdir()
    (flow_root / "retrieve.py").write_text(
        "import weaviate\n"
        "def retrieve(query):\n"
        "    return search(query, top_k=12, hybrid_alpha=0.8, rerank_num=6)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "engines"
        root_path = "engines"

    result = detect_rag(tmp_path, [_Flow()])
    params = result["per_flow"]["engines"]["retrieve_params"]
    assert params.get("top_k") == 12
    assert params.get("hybrid_alpha") == 0.8
    assert params.get("rerank_num") == 6
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_ai_rag_detect.py -v`
Expected: COLLECTION ERROR with `ModuleNotFoundError: No module named 'scripts.architect.ai_rag_detect'`.

- [ ] **Step 3: Implement `ai_rag_detect.py`**

Create `scripts/architect/ai_rag_detect.py`:
```python
"""Detect RAG architecture signals per AI flow.

Pure function. Walks each AIFlow.root_path, returns per-flow signals
(role read/write/both/none, vector stores, embedding libs/models,
retrieve params, rerank libs, chunking) + cross-flow summary
(read_flows, write_flows, vector_stores, embedding_aligned, mismatch).

embedding_aligned is the money-shot field: 3-state bool (true / false /
null) reflecting whether write-side and read-side embedding models match.
"""
from __future__ import annotations

import re
from pathlib import Path

# ---------- vector store detection ----------

_VECTOR_STORE_HINTS = {
    "weaviate": ("weaviate", "langchain_weaviate"),
    "chromadb": ("chromadb", "chroma"),
    "pinecone": ("pinecone",),
    "qdrant": ("qdrant_client", "qdrant"),
    "lancedb": ("lancedb",),
    "faiss": ("faiss",),
    "pgvector": ("pgvector",),
}

# ---------- embedding detection ----------

_EMBEDDING_LIB_HINTS = {
    "openai": ("OpenAIEmbeddings", "langchain_openai"),
    "google_generativeai": ("GoogleGenerativeAIEmbeddings", "google_generativeai", "google.generativeai"),
    "cohere": ("CohereEmbeddings",),
    "sentence_transformers": ("sentence_transformers", "SentenceTransformer"),
}

_EMBEDDING_MODEL_RE = re.compile(
    r"['\"](?P<model>(?:models/)?(?:text-embedding-[0-9a-z\-]+|all-MiniLM-[0-9a-z\-]+|embedding-[a-z0-9\-]+))['\"]"
)

# ---------- chunking detection ----------

_CHUNKING_CLASS_HINTS = (
    "RecursiveCharacterTextSplitter",
    "CharacterTextSplitter",
    "SemanticSplitterNodeParser",
    "TokenTextSplitter",
)

# ---------- rerank detection ----------

_RERANK_LIB_HINTS = {
    "jina-reranker": ("JinaReranker", "jina_reranker"),
    "cohere-rerank": ("CohereRerank",),
    "sentence_transformers-cross-encoder": ("CrossEncoder",),
}

# ---------- role classifier ----------

_READ_CALL_RE = re.compile(
    r"\.(?:similarity_search|hybrid|search|query|retrieve)\b"
)
_WRITE_CALL_RE = re.compile(
    r"\.(?:add_documents|upsert|add\s*\()"
)
_EMBED_CALL_RE = re.compile(
    r"\.(?:embed_documents|embed_query|embed_texts)\s*\("
)

# ---------- retrieve params ----------

_PARAM_RE = re.compile(
    r"\b(?P<key>top_k|hybrid_alpha|alpha|fetch_k|rerank_num|k)\s*=\s*(?P<val>[0-9.]+)"
)


def detect_rag(repo_root: Path, ai_flows: list) -> dict:
    repo_root = repo_root.resolve()
    per_flow: dict[str, dict] = {}

    for flow in ai_flows:
        flow_dir = repo_root / flow.root_path
        if not flow_dir.is_dir():
            per_flow[flow.slug] = _empty_rag_record()
            continue
        per_flow[flow.slug] = _scan_flow(flow_dir, repo_root)

    summary = _build_summary(per_flow)
    return {"per_flow": per_flow, "summary": summary}


def _empty_rag_record() -> dict:
    return {
        "role": "none",
        "vector_stores": [],
        "vector_store_sources": [],
        "embedding_libs": [],
        "embedding_models": [],
        "embedding_dims": None,
        "retrieve_params": {},
        "rerank_libs": [],
        "chunking": None,
    }


def _scan_flow(flow_dir: Path, repo_root: Path) -> dict:
    vector_stores: set[str] = set()
    vector_store_sources: list[str] = []
    embedding_libs: set[str] = set()
    embedding_models: set[str] = set()
    rerank_libs: set[str] = set()
    has_read_calls = False
    has_write_calls = False
    has_embed_calls = False
    retrieve_params: dict[str, float | int] = {}
    chunking: dict | None = None

    for py_file in flow_dir.rglob("*.py"):
        try:
            text = py_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = py_file.relative_to(repo_root).as_posix()

        # Vector store libs.
        for label, hints in _VECTOR_STORE_HINTS.items():
            if any(h in text for h in hints):
                if label not in vector_stores:
                    vector_stores.add(label)
                    vector_store_sources.append(rel)
        # Embedding libs.
        for label, hints in _EMBEDDING_LIB_HINTS.items():
            if any(h in text for h in hints):
                embedding_libs.add(label)
        # Embedding models.
        for m in _EMBEDDING_MODEL_RE.finditer(text):
            embedding_models.add(m.group("model"))
        # Rerank libs.
        for label, hints in _RERANK_LIB_HINTS.items():
            if any(h in text for h in hints):
                rerank_libs.add(label)
        # Role-classifier hints.
        if _READ_CALL_RE.search(text):
            has_read_calls = True
        if _WRITE_CALL_RE.search(text):
            has_write_calls = True
        if _EMBED_CALL_RE.search(text):
            has_embed_calls = True
        # Retrieve params.
        for m in _PARAM_RE.finditer(text):
            k = m.group("key")
            v = m.group("val")
            val: float | int = float(v) if "." in v else int(v)
            retrieve_params.setdefault(k, val)
        # Chunking.
        if chunking is None:
            for cls in _CHUNKING_CLASS_HINTS:
                if cls in text:
                    chunking = {"strategy": cls, "source": rel}
                    break

    role = _classify_role(has_read_calls, has_write_calls, has_embed_calls)

    return {
        "role": role,
        "vector_stores": sorted(vector_stores),
        "vector_store_sources": vector_store_sources,
        "embedding_libs": sorted(embedding_libs),
        "embedding_models": sorted(embedding_models),
        "embedding_dims": None,
        "retrieve_params": retrieve_params,
        "rerank_libs": sorted(rerank_libs),
        "chunking": chunking,
    }


def _classify_role(read: bool, write: bool, embed: bool) -> str:
    if write and read:
        return "both"
    if write or (embed and not read):
        return "write" if write or embed else "none"
    if read:
        return "read"
    return "none"


def _build_summary(per_flow: dict) -> dict:
    read_flows = sum(1 for v in per_flow.values() if v["role"] in ("read", "both"))
    write_flows = sum(1 for v in per_flow.values() if v["role"] in ("write", "both"))
    all_stores: set[str] = set()
    for v in per_flow.values():
        all_stores.update(v["vector_stores"])

    write_models: set[str] = set()
    read_models: set[str] = set()
    for v in per_flow.values():
        if v["role"] in ("write", "both"):
            write_models.update(v["embedding_models"])
        if v["role"] in ("read", "both"):
            read_models.update(v["embedding_models"])

    if not write_models or not read_models:
        embedding_aligned = None
        alignment_mismatch: list[dict] = []
    elif write_models == read_models:
        embedding_aligned = True
        alignment_mismatch = []
    else:
        embedding_aligned = False
        alignment_mismatch = []
        for slug_w, v_w in per_flow.items():
            if v_w["role"] not in ("write", "both"):
                continue
            for slug_r, v_r in per_flow.items():
                if v_r["role"] not in ("read", "both"):
                    continue
                if set(v_w["embedding_models"]) == set(v_r["embedding_models"]):
                    continue
                alignment_mismatch.append({
                    "write": {"flow": slug_w, "model": ",".join(v_w["embedding_models"]) or "?"},
                    "read": {"flow": slug_r, "model": ",".join(v_r["embedding_models"]) or "?"},
                })

    if not all_stores:
        primary_store = "none"
    elif len(all_stores) == 1:
        primary_store = next(iter(all_stores))
    else:
        primary_store = "mixed"

    return {
        "read_flows": read_flows,
        "write_flows": write_flows,
        "vector_stores": sorted(all_stores),
        "primary_vector_store": primary_store,
        "embedding_aligned": embedding_aligned,
        "alignment_mismatch": alignment_mismatch,
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_rag_detect.py -v`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/ai_rag_detect.py tests/architect/test_ai_rag_detect.py
git commit -m "$(cat <<'EOF'
feat(architect): ai_rag_detect — per-flow vector store + embedding + role classifier

Pure-function detector. Walks each AI flow root_path, returns per-flow
signal dict (role read/write/both/none, vector stores, embedding libs +
models, retrieve params, rerank libs, chunking) plus cross-flow summary
(read_flows, write_flows, embedding_aligned 3-state, alignment_mismatch).

Detection patterns:
- Vector stores: imports of weaviate/chromadb/pinecone/qdrant/lancedb/
  faiss/pgvector/langchain_weaviate
- Embedding: OpenAI / Google / Cohere / sentence-transformers libs +
  model string regex (text-embedding-*, all-MiniLM-*, embedding-*)
- Role: similarity_search/.hybrid → read; .add_documents/.upsert → write
- Params: top_k=N, hybrid_alpha=N regex
- Chunking: RecursiveCharacterTextSplitter / CharacterTextSplitter / etc

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: `detect_rag` write side + alignment cases

**Files:**
- Modify: `tests/architect/test_ai_rag_detect.py` (append)

- [ ] **Step 1: Append write-side + alignment tests**

```python
def test_detects_write_role_via_add_documents(tmp_path: Path):
    flow_root = tmp_path / "ingest"
    flow_root.mkdir()
    (flow_root / "writer.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "from langchain_weaviate.vectorstores import WeaviateVectorStore\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs = WeaviateVectorStore(embedding=embed)\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "ingest"
        root_path = "ingest"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["per_flow"]["ingest"]["role"] == "write"


def test_summary_embedding_aligned_false_when_models_differ(tmp_path: Path):
    """Write flow uses text-embedding-3-small; read flow uses text-embedding-004.
    Summary must flag embedding_aligned=false + populate alignment_mismatch."""
    writer = tmp_path / "writer"
    writer.mkdir()
    (writer / "w.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )
    reader = tmp_path / "reader"
    reader.mkdir()
    (reader / "r.py").write_text(
        "from langchain_google_genai import GoogleGenerativeAIEmbeddings\n"
        "embed = GoogleGenerativeAIEmbeddings(model='models/text-embedding-004')\n"
        "vs.similarity_search(q, k=5)\n",
        encoding="utf-8",
    )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_rag(tmp_path, [_Flow("writer"), _Flow("reader")])
    s = result["summary"]
    assert s["embedding_aligned"] is False
    assert len(s["alignment_mismatch"]) == 1
    mismatch = s["alignment_mismatch"][0]
    assert mismatch["write"]["flow"] == "writer"
    assert mismatch["read"]["flow"] == "reader"
    assert "text-embedding-3-small" in mismatch["write"]["model"]
    assert "text-embedding-004" in mismatch["read"]["model"]


def test_summary_embedding_aligned_true_when_both_use_same_model(tmp_path: Path):
    for slug in ("writer", "reader"):
        d = tmp_path / slug
        d.mkdir()
        suffix = "vs.add_documents(docs)" if slug == "writer" else "vs.similarity_search(q)"
        (d / "x.py").write_text(
            "from langchain_openai import OpenAIEmbeddings\n"
            "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
            f"{suffix}\n",
            encoding="utf-8",
        )

    class _Flow:
        def __init__(self, slug):
            self.slug = slug
            self.root_path = slug

    result = detect_rag(tmp_path, [_Flow("writer"), _Flow("reader")])
    assert result["summary"]["embedding_aligned"] is True
    assert result["summary"]["alignment_mismatch"] == []


def test_summary_embedding_aligned_null_when_only_one_side(tmp_path: Path):
    """Only a write flow exists → alignment is N/A (null), not false."""
    writer = tmp_path / "writer"
    writer.mkdir()
    (writer / "w.py").write_text(
        "from langchain_openai import OpenAIEmbeddings\n"
        "embed = OpenAIEmbeddings(model='text-embedding-3-small')\n"
        "vs.add_documents(docs)\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "writer"
        root_path = "writer"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["summary"]["embedding_aligned"] is None


def test_returns_role_none_when_no_rag_calls(tmp_path: Path):
    flow_root = tmp_path / "plain"
    flow_root.mkdir()
    (flow_root / "x.py").write_text(
        "def hello(): pass\n",
        encoding="utf-8",
    )

    class _Flow:
        slug = "plain"
        root_path = "plain"

    result = detect_rag(tmp_path, [_Flow()])
    assert result["per_flow"]["plain"]["role"] == "none"


def test_empty_ai_flows_list_returns_empty(tmp_path: Path):
    result = detect_rag(tmp_path, [])
    assert result["per_flow"] == {}
    assert result["summary"]["read_flows"] == 0
    assert result["summary"]["write_flows"] == 0
    assert result["summary"]["embedding_aligned"] is None
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_rag_detect.py -v`
Expected: 8 PASS total (2 prior + 6 new).

- [ ] **Step 3: Commit**

```bash
git add tests/architect/test_ai_rag_detect.py
git commit -m "$(cat <<'EOF'
test(architect): ai_rag_detect write-side + embedding_aligned 3-state cases

Adds 6 tests covering:
- Write role via .add_documents
- embedding_aligned=false when write/read models differ (with mismatch
  records)
- embedding_aligned=true when both sides use same model
- embedding_aligned=null when only one side exists
- role=none for flows without any RAG calls
- Empty ai_flows list returns empty per_flow + zero counts

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: Scanner integration

### Task 6: `build_scan_report` adds `ai_memory` + `ai_rag` keys

**Files:**
- Modify: `scripts/architect/scan.py` (find `build_scan_report` body)
- Modify: `tests/architect/test_ai_memory_rag_compose.py` (append)

- [ ] **Step 1: Write the failing test**

In `tests/architect/test_ai_memory_rag_compose.py`, append:
```python
def test_scan_report_includes_ai_memory_and_ai_rag(tmp_path):
    """build_scan_report exposes ai_memory + ai_rag dicts when ai_flows detected."""
    import subprocess
    from scripts.architect.scan import build_scan_report

    # Set up a minimal repo + LangGraph flow with checkpointer.
    subprocess.run(["git", "init", "-b", "main"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)

    (tmp_path / "README.md").write_text("r\n", encoding="utf-8")
    (tmp_path / "AGENTS.md").write_text("a\n", encoding="utf-8")
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname="m"\ndependencies=["langgraph"]\n',
        encoding="utf-8",
    )
    flow = tmp_path / "app"
    (flow / "nodes").mkdir(parents=True)
    for n in ("intent", "retrieve", "generate"):
        (flow / "nodes" / f"{n}.py").write_text(
            f"def {n}(s): return s\n",
            encoding="utf-8",
        )
    (flow / "prompts").mkdir()
    (flow / "prompts" / "system.py").write_text('SYSTEM = "x"\n', encoding="utf-8")
    (flow / "core").mkdir()
    (flow / "core" / "state.py").write_text("class S: pass\n", encoding="utf-8")
    (flow / "graph.py").write_text(
        "from langgraph.checkpoint.memory import MemorySaver\n"
        "from langgraph.graph import StateGraph\n"
        "checkpointer = MemorySaver()\n"
        "g = StateGraph(dict)\n"
        "g.add_node('intent', None)\n"
        "g.add_node('retrieve', None)\n"
        "g.add_node('generate', None)\n",
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "."], cwd=tmp_path, check=True)
    subprocess.run(
        ["git", "commit", "-m", "init"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
    )

    report = build_scan_report(tmp_path, vault_project_dir=None)
    assert "ai_memory" in report
    assert "ai_rag" in report
    # Flow detected and memory recognized.
    assert any(f["slug"] == "app" or "app" in f["slug"] for f in report["ai_flows"])
    fm_keys = list(report["ai_memory"]["per_flow"].keys())
    assert fm_keys, f"expected at least one per-flow record; got {fm_keys}"
    # in-memory backend detected.
    sole = report["ai_memory"]["per_flow"][fm_keys[0]]
    assert sole["has_memory"] is True
    assert "in-memory" in sole["backends"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py::test_scan_report_includes_ai_memory_and_ai_rag -v`
Expected: FAIL with `KeyError: 'ai_memory'`.

- [ ] **Step 3: Modify `build_scan_report` to populate the new keys**

In `scripts/architect/scan.py`, find `build_scan_report` (around line 126). After the existing `ai_flows` population block, add:

```python
    # v4.3 — cross-flow AI memory + RAG signals
    from scripts.architect.ai_memory_detect import detect_memory
    from scripts.architect.ai_rag_detect import detect_rag

    report["ai_memory"] = detect_memory(repo_root, result.ai_flows)
    report["ai_rag"] = detect_rag(repo_root, result.ai_flows)
```

(If the assembly site uses a variable name other than `result.ai_flows` for the list of AIFlow records produced earlier in the same function, adapt the reference accordingly — `grep "ai_flows" scripts/architect/scan.py` to confirm the local variable name.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v`
Expected: All PASS.

- [ ] **Step 5: Run full suite for no regressions**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/scan.py tests/architect/test_ai_memory_rag_compose.py
git commit -m "$(cat <<'EOF'
feat(architect): scan_report adds ai_memory + ai_rag (v4.3)

build_scan_report now invokes detect_memory and detect_rag against the
list of AI flows produced by detect_ai_flows. Output JSON contains two
new top-level keys:
- ai_memory: { per_flow: {slug: {...}}, summary: {memory_flows, ...} }
- ai_rag: { per_flow: {slug: {role, vector_stores, ...}}, summary: {..., embedding_aligned} }

When ai_flows is empty (non-AI project), both keys still present with
per_flow={} and zero counts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Prompts + compose

### Task 7: `build_ai_memory_prompt` — strict-JSON 11-block instructions

**Files:**
- Modify: `scripts/architect/sections.py` (append new function near `build_ai_flow_prompt`)
- Modify: `tests/architect/test_ai_memory_rag_compose.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_build_ai_memory_prompt_requires_11_block_keys():
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={
            "per_flow": {
                "engines": {
                    "has_memory": True,
                    "backends": ["redis"],
                    "checkpointer_classes": ["SimpleRedisSaver"],
                    "checkpointer_sources": ["backend/.../saver.py"],
                    "key_patterns": ["simple_ckpt_v2"],
                    "reducer_funcs": ["add_messages_limited"],
                    "reducer_caps": [{"name": "add_messages_limited", "limit": 100, "source": "..."}],
                    "compaction_funcs": ["session_summary"],
                    "compaction_sources": ["..."],
                }
            },
            "summary": {"memory_flows": 1, "stateless_flows": 0,
                        "primary_backend": "redis", "uniform_backend": True},
        },
        ai_flows_summary=[{"slug": "engines", "framework": "langgraph",
                           "root_path": "backend/engines/langgraph"}],
        output_lang="zh-TW",
    )
    for key in (
        "summary", "flow-memory-map", "backend-and-storage",
        "scope-and-lifecycle", "context-window-management",
        "compaction-strategy", "long-term-vs-short", "strengths",
        "weaknesses", "improvements", "dependencies",
    ):
        assert key in prompt, f"prompt must reference block key {key!r}"


def test_build_ai_memory_prompt_no_invention_rule():
    """When a signal field is empty/null, prompt must instruct LLM to acknowledge absence."""
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={"per_flow": {}, "summary": {"memory_flows": 0,
                                                         "stateless_flows": 1,
                                                         "primary_backend": "none",
                                                         "uniform_backend": True}},
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "未偵測到" in prompt or "acknowledge absence" in prompt.lower() or "no invention" in prompt.lower()


def test_build_ai_memory_prompt_wikilink_out_directive():
    """Prompt MUST instruct LLM to wikilink-out per-flow state-schema rather than rewrite."""
    from scripts.architect.sections import build_ai_memory_prompt

    prompt = build_ai_memory_prompt(
        project="P",
        ai_memory_signals={"per_flow": {}, "summary": {"memory_flows": 0,
                                                         "stateless_flows": 0,
                                                         "primary_backend": "none",
                                                         "uniform_backend": True}},
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "[[ai-flows/" in prompt
    assert "State schema" in prompt or "state-schema" in prompt
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py::test_build_ai_memory_prompt_requires_11_block_keys -v`
Expected: FAIL with `ImportError: cannot import name 'build_ai_memory_prompt'`.

- [ ] **Step 3: Implement `build_ai_memory_prompt`**

In `scripts/architect/sections.py`, append (after `build_ai_flow_prompt`, before `render_prompts_block`):

```python
def build_ai_memory_prompt(
    *,
    project: str,
    ai_memory_signals: dict,
    ai_flows_summary: list[dict],
    output_lang: str,
) -> str:
    """v4.3 — AI memory cross-flow synthesis prompt.

    Demands the LLM produce 11 @generated block bodies. Critical rule:
    NO invention — when scanner signals are empty/null/false, the prose
    MUST acknowledge absence rather than hallucinate. Per-flow detail
    must wikilink out to [[ai-flows/<slug>#State schema]] rather than
    rehash.
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫所有散文。"
            "Code identifier (檔案路徑、變數名、函式名、env var)、class name、"
            "model 字串保持英文/原文。"
        )
        absence_label = "未偵測到"
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = (
            "Write all prose in English. Code identifiers, paths, function names, "
            "env vars, class names, and model strings stay verbatim."
        )
        absence_label = "(not detected)"
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    flows_inventory = "\n".join(
        f"  - {f['slug']} ({f['framework']}, {f['root_path']})"
        for f in ai_flows_summary
    ) or "  (no AI flows)"

    return "\n".join([
        f"You are documenting the **cross-flow AI memory lens** for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. NO invention. When a scanner field below is empty/null/false, the prose "
        f"MUST acknowledge absence verbatim (e.g. '{absence_label} TTL policy'). "
        "Hallucinated TTLs / eviction rules are worse than acknowledged unknowns.",
        "2. Per-flow detail MUST wikilink out — DO NOT rewrite state shape. Use "
        "`[[ai-flows/<slug>#State schema]]` from the flow-memory-map table.",
        "3. strengths / weaknesses use the v3.1 tight bullet shape: "
        "**Title (≤30 char).** clarification (≤80 char).",
        "4. Improvements must follow ImprovementItem shape with Evidence as wikilink "
        "or path:line.",
        "",
        "## Output: produce 11 @generated blocks (JSON keys)",
        "",
        "### `summary`",
        "1 paragraph. Which flows have memory (wikilinks), which are stateless, "
        "backend in one line, policy one line.",
        "",
        "### `flow-memory-map`",
        "Markdown table: | Flow | Has memory | Backend | Scope | Persistence | "
        "Wikilink to [[ai-flows/<slug>#State schema]] |.",
        "",
        "### `backend-and-storage`",
        "Backend per flow (Redis / Postgres / file / in-memory), serializer, "
        "key pattern, encryption-at-rest, backup policy. Each fact must cite "
        "`code:path:line` from scanner.",
        "",
        "### `scope-and-lifecycle`",
        "session-scoped vs user-scoped vs request-scoped. Creation/destruction "
        "trigger. Orphan cleanup job (exists? where?). TTL & eviction — when "
        "undetected, state plainly 'no TTL / eviction policy detected'.",
        "",
        "### `context-window-management`",
        "Reducer pattern, max-tokens, truncation, fallback when exceeded.",
        "",
        "### `compaction-strategy`",
        "When summarizer triggers; wikilink to `[[ai-flows/<slug>#Prompts]]`; "
        "frequency; storage path.",
        "",
        "### `long-term-vs-short`",
        "Resumable session state vs cross-session knowledge. When NO long-term "
        "memory exists, plainly state so.",
        "",
        "### `strengths`",
        "3-5 tight bullets.",
        "",
        "### `weaknesses`",
        "3-5 tight bullets. Failure modes: unbounded growth / race conditions / "
        "serializer drift / cross-worker inconsistency / silent eviction.",
        "",
        "### `improvements`",
        f"3-5 Imps with: {improvement_shape}.",
        "",
        "### `dependencies`",
        "Wikilinks only: each [[ai-flows/<slug>]], [[decisions]] relevant ADR, "
        "external lib references.",
        "",
        "Return strict JSON: {\"summary\": \"...\", \"flow-memory-map\": \"...\", "
        "\"backend-and-storage\": \"...\", \"scope-and-lifecycle\": \"...\", "
        "\"context-window-management\": \"...\", \"compaction-strategy\": \"...\", "
        "\"long-term-vs-short\": \"...\", \"strengths\": \"...\", "
        "\"weaknesses\": \"...\", \"improvements\": \"...\", "
        "\"dependencies\": \"...\"}.",
        "",
        "## AI flows inventory",
        flows_inventory,
        "",
        "## Scanner-detected memory signals (per-flow + summary)",
        json.dumps(ai_memory_signals, indent=2, ensure_ascii=False, default=str),
    ])
```

(Note: `import json` is already at the top of `sections.py` from existing code.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v -k "build_ai_memory_prompt"`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_ai_memory_rag_compose.py
git commit -m "$(cat <<'EOF'
feat(architect): build_ai_memory_prompt — strict JSON 11-block cross-flow lens prompt

LLM prompt for memory.md synthesis. Encodes 4 critical rules:
1. NO invention (empty/null/false signals → acknowledge absence)
2. Wikilink-out to [[ai-flows/<slug>#State schema]] (no rehash)
3. Tight bullet shape for strengths/weaknesses
4. ImprovementItem shape for improvements

Embeds ai_memory_signals JSON + ai_flows_summary inline so the LLM has
all detection evidence directly accessible.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `build_ai_rag_prompt` — strict-JSON 11-block + embedding-aligned warning rule

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_ai_memory_rag_compose.py` (append)

- [ ] **Step 1: Write the failing test**

```python
def test_build_ai_rag_prompt_requires_11_block_keys():
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {
                "writer": {"role": "write", "vector_stores": ["weaviate"],
                           "embedding_libs": ["openai"],
                           "embedding_models": ["text-embedding-3-small"],
                           "retrieve_params": {}, "rerank_libs": [], "chunking": None,
                           "vector_store_sources": [], "embedding_dims": None},
                "reader": {"role": "read", "vector_stores": ["weaviate"],
                           "embedding_libs": ["google_generativeai"],
                           "embedding_models": ["models/text-embedding-004"],
                           "retrieve_params": {"hybrid_alpha": 0.8, "top_k": 12},
                           "rerank_libs": [], "chunking": None,
                           "vector_store_sources": [], "embedding_dims": None},
            },
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": False,
                        "alignment_mismatch": [{"write": {"flow": "writer",
                                                          "model": "text-embedding-3-small"},
                                                 "read": {"flow": "reader",
                                                          "model": "models/text-embedding-004"}}]},
        },
        ai_flows_summary=[
            {"slug": "writer", "framework": "custom-pipeline", "root_path": "modules/writer"},
            {"slug": "reader", "framework": "langgraph", "root_path": "backend/reader"},
        ],
        output_lang="zh-TW",
    )
    for key in (
        "summary", "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers", "evaluation",
        "strengths", "weaknesses", "improvements", "dependencies",
    ):
        assert key in prompt, f"prompt must reference {key!r}"


def test_build_ai_rag_prompt_embedding_aligned_false_warning():
    """When embedding_aligned=false, prompt MUST instruct LLM to flag mismatch in
    weaknesses + improvements blocks."""
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {},
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": False, "alignment_mismatch": []},
        },
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    assert "embedding_aligned" in prompt or "embedding-aligned" in prompt
    assert "false" in prompt.lower()
    assert "weakness" in prompt.lower() or "缺點" in prompt
    assert "improvement" in prompt.lower() or "改進" in prompt


def test_build_ai_rag_prompt_aligned_true_no_warning():
    """When embedding_aligned=true, prompt should NOT push a misalignment warning."""
    from scripts.architect.sections import build_ai_rag_prompt

    prompt = build_ai_rag_prompt(
        project="P",
        ai_rag_signals={
            "per_flow": {},
            "summary": {"read_flows": 1, "write_flows": 1,
                        "vector_stores": ["weaviate"], "primary_vector_store": "weaviate",
                        "embedding_aligned": True, "alignment_mismatch": []},
        },
        ai_flows_summary=[],
        output_lang="zh-TW",
    )
    # The prompt MUST NOT insist on a misalignment Imp.
    assert "MUST flag the mismatch" not in prompt
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v -k "build_ai_rag_prompt"`
Expected: 3 FAILs with `ImportError`.

- [ ] **Step 3: Implement `build_ai_rag_prompt`**

In `scripts/architect/sections.py`, append:

```python
def build_ai_rag_prompt(
    *,
    project: str,
    ai_rag_signals: dict,
    ai_flows_summary: list[dict],
    output_lang: str,
) -> str:
    """v4.3 — AI RAG cross-flow synthesis prompt.

    11 @generated blocks. When summary.embedding_aligned is False, prompt
    instructs LLM to flag the mismatch in weaknesses AND open an Imp to
    align providers.
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫所有散文。Code identifier、檔案路徑、env var、"
            "model 字串保持原文。Mermaid node ID 也保持英文。"
        )
        absence_label = "未偵測到"
        improvement_shape = "**為什麼:** / **證據:** / **Effort:** / **未做的風險:** / **Confidence:**"
    else:
        lang_directive = "Write all prose in English. Code identifiers stay verbatim."
        absence_label = "(not detected)"
        improvement_shape = "**Why:** / **Evidence:** / **Effort:** / **Risk if not done:** / **Confidence:**"

    summary = ai_rag_signals.get("summary", {})
    embedding_aligned = summary.get("embedding_aligned")

    if embedding_aligned is False:
        alignment_directive = (
            "5. **embedding_aligned is `false`.** weaknesses block MUST contain a "
            "bullet flagging the embedding provider mismatch. improvements block "
            "MUST contain an Imp to align providers (Confidence: stated). "
            "Embedding-providers block MUST include a ⚠️ row pointing at the mismatch."
        )
    else:
        alignment_directive = (
            "5. embedding_aligned is "
            f"`{embedding_aligned}` — no special-case warning required."
        )

    flows_inventory = "\n".join(
        f"  - {f['slug']} ({f['framework']}, {f['root_path']})"
        for f in ai_flows_summary
    ) or "  (no AI flows)"

    return "\n".join([
        f"You are documenting the **cross-flow RAG lens** for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. NO invention. Empty/null/false signals → prose says "
        f"'{absence_label} <field>'.",
        "2. Per-flow detail wikilinks to `[[ai-flows/<slug>#LLM config]]` and "
        "`[[ai-flows/<slug>#State schema]]`; do not rehash.",
        "3. Tight bullet shape for strengths/weaknesses.",
        "4. ImprovementItem shape for improvements.",
        alignment_directive,
        "",
        "## Output: produce 11 @generated blocks (JSON keys)",
        "",
        "### `summary`",
        "1 paragraph. Which flows read, which write, vector store, primary embedding. "
        "**embedding-aligned flag explicit one-liner** (e.g. '⚠️ embedding 不對齊').",
        "",
        "### `rag-data-flow`",
        "ONE Mermaid graph: ingest pipeline (writer flow) → vector store → retrieve "
        "(reader flow). Each node label includes `path` annotation.",
        "",
        "### `ingest-pipeline`",
        "Write side: chunking (splitter, size, overlap), embedding provider/model/dims, "
        "upsert pattern, schema, re-index trigger.",
        "",
        "### `vector-store-config`",
        "Store choice, schema, multi-tenancy, index versioning, capacity bound.",
        "",
        "### `retrieve-strategy`",
        "Read side: search backend (hybrid α / BM25 / vector-only), top-k, rerank lib, "
        "MMR, metadata filter.",
        "",
        "### `embedding-providers`",
        "Per-flow: lib + model + dims. Vector space consistency check — when write+read "
        "models differ, include ⚠️ row.",
        "",
        "### `evaluation`",
        "recall@k metrics, hit-rate tracking, golden-set, link to `evaluation/` "
        "sub-module if present. When absent: `> [!warning] 無 retrieve eval`.",
        "",
        "### `strengths`",
        "3-5 tight bullets.",
        "",
        "### `weaknesses`",
        "3-5 tight bullets. Common: vector space mismatch / no eval / no incremental "
        "update / stale chunks.",
        "",
        "### `improvements`",
        f"3-5 Imps with: {improvement_shape}.",
        "",
        "### `dependencies`",
        "Wikilinks only: each [[ai-flows/<slug>]], [[decisions]] relevant, external lib.",
        "",
        "Return strict JSON: {\"summary\": \"...\", \"rag-data-flow\": \"...\", "
        "\"ingest-pipeline\": \"...\", \"vector-store-config\": \"...\", "
        "\"retrieve-strategy\": \"...\", \"embedding-providers\": \"...\", "
        "\"evaluation\": \"...\", \"strengths\": \"...\", \"weaknesses\": \"...\", "
        "\"improvements\": \"...\", \"dependencies\": \"...\"}.",
        "",
        "## AI flows inventory",
        flows_inventory,
        "",
        "## Scanner-detected RAG signals",
        json.dumps(ai_rag_signals, indent=2, ensure_ascii=False, default=str),
    ])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v -k "build_ai_rag_prompt"`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_ai_memory_rag_compose.py
git commit -m "$(cat <<'EOF'
feat(architect): build_ai_rag_prompt — strict JSON 11-block + embedding-aligned warning

LLM prompt for rag.md synthesis. Adds 5th critical rule: when scanner
reports embedding_aligned=false, prompt instructs LLM to flag mismatch
in weaknesses + improvements + embedding-providers blocks. When
embedding_aligned is true or null, no warning pushed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: `compose_ai_memory_note` + `compose_ai_rag_note` with extra frontmatter

**Files:**
- Modify: `scripts/architect/sections.py` (append)
- Modify: `tests/architect/test_ai_memory_rag_compose.py` (append)

- [ ] **Step 1: Write failing tests**

```python
def test_compose_ai_memory_note_emits_extra_frontmatter():
    from scripts.architect.sections import compose_ai_memory_note

    blocks = {n: f"body for {n}" for n in (
        "summary", "flow-memory-map", "backend-and-storage", "scope-and-lifecycle",
        "context-window-management", "compaction-strategy", "long-term-vs-short",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    note = compose_ai_memory_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["scan: ai_memory"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks=blocks,
        memory_flows=1,
        stateless_flows=1,
        backend="redis",
    )
    assert "memory-flows: 1" in note
    assert "stateless-flows: 1" in note
    assert 'backend: "redis"' in note
    # Order: extra fields before ai-first: true.
    fm = note.split("---", 2)[1]
    assert fm.index("memory-flows") < fm.index("ai-first")


def test_compose_ai_rag_note_emits_embedding_aligned_bool_or_null():
    from scripts.architect.sections import compose_ai_rag_note

    blocks = {n: f"body for {n}" for n in (
        "summary", "rag-data-flow", "ingest-pipeline", "vector-store-config",
        "retrieve-strategy", "embedding-providers", "evaluation",
        "strengths", "weaknesses", "improvements", "dependencies",
    )}
    # Case 1: aligned is false.
    note_false = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=1, vector_store="weaviate",
        embedding_aligned=False,
    )
    assert "embedding-aligned: false" in note_false
    # Case 2: aligned is None.
    note_null = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=0, vector_store="weaviate",
        embedding_aligned=None,
    )
    assert "embedding-aligned: null" in note_null
    # Case 3: aligned is True.
    note_true = compose_ai_rag_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["scan: ai_rag"], confidence="high",
        output_lang="zh-TW", generated_blocks=blocks,
        rag_flows_read=1, rag_flows_write=1, vector_store="weaviate",
        embedding_aligned=True,
    )
    assert "embedding-aligned: true" in note_true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v -k "compose_ai_memory_note or compose_ai_rag_note"`
Expected: 2 FAILs with `ImportError`.

- [ ] **Step 3: Implement composers**

In `scripts/architect/sections.py`, append:

```python
def compose_ai_memory_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    memory_flows: int,
    stateless_flows: int,
    backend: str,
) -> str:
    """Wrap compose_note(section='ai-memory', ...) and merge 3 extra frontmatter
    fields BEFORE `ai-first: true`."""
    note = compose_note(
        section="ai-memory",
        project=project,
        repo_label=repo_label,
        commit=commit,
        signal_sources=signal_sources,
        confidence=confidence,
        output_lang=output_lang,
        generated_blocks=generated_blocks,
    )
    extra_fm = (
        f"memory-flows: {memory_flows}\n"
        f"stateless-flows: {stateless_flows}\n"
        f'backend: "{backend}"\n'
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)


def compose_ai_rag_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    rag_flows_read: int,
    rag_flows_write: int,
    vector_store: str,
    embedding_aligned: bool | None,
) -> str:
    """Wrap compose_note(section='ai-rag', ...) and merge 4 extra frontmatter
    fields. `embedding_aligned` is rendered as YAML `true` / `false` / `null`."""
    note = compose_note(
        section="ai-rag",
        project=project,
        repo_label=repo_label,
        commit=commit,
        signal_sources=signal_sources,
        confidence=confidence,
        output_lang=output_lang,
        generated_blocks=generated_blocks,
    )
    if embedding_aligned is None:
        aligned_value = "null"
    elif embedding_aligned is True:
        aligned_value = "true"
    else:
        aligned_value = "false"
    extra_fm = (
        f"rag-flows-read: {rag_flows_read}\n"
        f"rag-flows-write: {rag_flows_write}\n"
        f'vector-store: "{vector_store}"\n'
        f"embedding-aligned: {aligned_value}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_ai_memory_rag_compose.py -v`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_ai_memory_rag_compose.py
git commit -m "$(cat <<'EOF'
feat(architect): compose_ai_memory_note + compose_ai_rag_note (v4.3)

Wraps compose_note(section=...) and merges section-specific extra
frontmatter before ai-first: true. ai_memory adds memory-flows /
stateless-flows / backend. ai_rag adds rag-flows-read / rag-flows-write
/ vector-store / embedding-aligned (3-state: true/false/null).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F: Lockfile slots

### Task 10: `Lockfile.ai_memory` + `Lockfile.ai_rag` round-trip

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write the failing test**

In `tests/architect/test_lockfile.py`, append:
```python
def test_lockfile_ai_memory_slot_round_trip(tmp_path):
    """sections.ai_memory round-trips through Lockfile.save → load (v4.3)."""
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_memory = {
        "signal-hash": "sha256:abc",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "d4f5",
        "memory_flows": 1,
        "stateless_flows": 1,
        "backend": "redis",
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_memory["memory_flows"] == 1
    assert loaded.ai_memory["backend"] == "redis"


def test_lockfile_ai_rag_slot_round_trip(tmp_path):
    from scripts.architect.lockfile import Lockfile

    lock = Lockfile(version=4, scanner_version="0.2.0", frame="report-v4")
    lock.ai_rag = {
        "signal-hash": "sha256:def",
        "lang": "zh-TW",
        "last-generated": "2026-05-29",
        "commit": "d4f5",
        "rag_flows_read": 1,
        "rag_flows_write": 1,
        "vector_store": "weaviate",
        "embedding_aligned": False,
    }
    p = tmp_path / "_manifest.lock.json"
    lock.save(p)
    loaded = Lockfile.load(p)
    assert loaded.ai_rag["embedding_aligned"] is False
    assert loaded.ai_rag["vector_store"] == "weaviate"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py -v -k "ai_memory_slot or ai_rag_slot"`
Expected: FAILs with `AttributeError: 'Lockfile' object has no attribute 'ai_memory'`.

- [ ] **Step 3: Add `ai_memory` + `ai_rag` fields to the Lockfile dataclass**

In `scripts/architect/lockfile.py`, find the `Lockfile` dataclass (around line 27). Add two new fields after the existing `ai_flows: dict = field(...)` line:

```python
    ai_flows: dict = field(
        default_factory=dict
    )  # v4.1 — per-flow + per-prompt source-hash tracking
    # v4.3 — cross-flow AI memory + RAG lenses (additive; no schema bump)
    ai_memory: dict = field(default_factory=dict)
    ai_rag: dict = field(default_factory=dict)
```

- [ ] **Step 4: Update `write_lockfile` / `load_lockfile` to serialize the new fields**

Inspect `scripts/architect/lockfile.py` `write_lockfile` and `load_lockfile`. If they use `dataclasses.asdict(lock)` and reconstruct via `Lockfile(**data)`, the new fields are picked up automatically. If serialization is field-by-field, add explicit handling:

```python
# In write_lockfile, when assembling the dict to dump:
out["ai_memory"] = lock.ai_memory
out["ai_rag"] = lock.ai_rag

# In load_lockfile, when constructing Lockfile from the loaded dict:
ai_memory=data.get("ai_memory", {}),
ai_rag=data.get("ai_rag", {}),
```

Concrete edits depend on what's there — confirm with `grep "ai_flows" scripts/architect/lockfile.py` to see how that v4.1 field is plumbed and mirror the pattern.

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: All PASS (prior tests + 2 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "$(cat <<'EOF'
feat(architect): Lockfile gains ai_memory + ai_rag slots (v4.3)

Additive dataclass fields (no schema version bump). Both default to {}
when absent; older lockfiles load cleanly with empty dicts. Serializer
+ loader pass the keys through, parallel to v4.1's ai_flows handling.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G: Roadmap signal

### Task 11: `detect_candidates` walks memory.md + rag.md (embedding-aligned → priority high)

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Inspect existing candidates module**

```bash
grep -n "features.md\|missing-features\|improvements\|Candidate" /Users/leric/Desktop/code/obsidian-second-brain/scripts/roadmap/candidates.py | head -20
```

- [ ] **Step 2: Write the failing tests**

In `tests/roadmap/test_candidates.py`, append:
```python
def test_detect_candidates_walks_ai_memory_md(tmp_path):
    """detect_candidates picks up improvements block from ai-flows/memory.md."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "memory.md").write_text(
        "---\ntype: architecture-ai-memory\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Add TTL to SimpleRedisSaver keys\n"
        "- **為什麼:** 無 TTL → 無限長 session state\n"
        "- **證據:** [[Architecture/ai-flows/memory#Scope & lifecycle]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** Redis 容量爆\n"
        "- **Confidence:** high\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("TTL" in t for t in titles), f"memory Imp not picked up; got {titles}"


def test_detect_candidates_rag_md_embedding_aligned_evidence_raises_priority(tmp_path):
    """When an Imp from rag.md cites embedding-aligned: false evidence, priority becomes high."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "rag.md").write_text(
        "---\ntype: architecture-ai-rag\nembedding-aligned: false\n---\n\n"
        "## 改進機會\n"
        "<!-- @generated:start improvements -->\n"
        "### Align write+read embedding providers\n"
        "- **為什麼:** embedding-aligned: false → vector space 不一致\n"
        "- **證據:** [[Architecture/ai-flows/rag#Embedding providers]] (embedding-aligned: false)\n"
        "- **Effort:** M\n"
        "- **未做的風險:** retrieve recall 受損\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end improvements -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    align = next((c for c in cands if "Align" in c.title), None)
    assert align is not None, f"rag Imp not picked up; cands={[c.title for c in cands]}"
    assert align.priority == "high", (
        f"expected priority=high due to embedding-aligned evidence; got {align.priority}"
    )
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "ai_memory_md or rag_md_embedding"`
Expected: FAILs (candidates not detected).

- [ ] **Step 4: Extend `detect_candidates` to walk both new files**

In `scripts/roadmap/candidates.py`, find the section that walks `features.md` (added in v4.2). After it (before the dedup pass), add:

```python
    # v4.3 — walk AI memory + RAG cross-flow notes.
    for fname, candidate_type, default_priority in (
        ("ai-flows/memory.md", "ai-memory-improvement", "normal"),
        ("ai-flows/rag.md", "ai-rag-improvement", "normal"),
    ):
        note_path = project_dir / "Architecture" / fname
        if not note_path.exists():
            continue
        text = note_path.read_text(encoding="utf-8")
        imp_body = _extract_generated_block(text, "improvements")
        if not imp_body:
            continue
        for imp in parse_improvements_block(imp_body):
            priority = default_priority
            # rag.md only: bump priority when evidence cites embedding-aligned.
            if fname.endswith("rag.md") and "embedding-aligned" in (imp.evidence or "").lower():
                priority = "high"
            candidates.append(_candidate_from_imp(
                imp,
                source=f"{fname}#improvements",
                candidate_type=candidate_type,
                priority=priority,
            ))
```

(Concrete naming depends on what `_extract_generated_block` / `_candidate_from_imp` / `parse_improvements_block` are called in this file. Adapt to the existing names from v4.2 implementation.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS.

- [ ] **Step 6: Run full suite**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): detect_candidates walks ai-flows/memory.md + ai-flows/rag.md (v4.3)

Two new source buckets:
- ai-flows/memory.md ## 改進機會 → candidate_type=ai-memory-improvement,
  priority=normal
- ai-flows/rag.md ## 改進機會 → candidate_type=ai-rag-improvement;
  priority=high when Evidence contains 'embedding-aligned' substring
  (vector space mismatch is high-leverage), normal otherwise

Existing dedup pass (Evidence wikilink overlap) extends transparently.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H: Command body + AI-first rules + announcement

### Task 12: Phase 3.8 + 3.9 in command body + `--no-ai-memory` / `--no-ai-rag` flags

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Locate insertion points**

```bash
grep -n "## Phase 3\.7\|## Phase 4\|--no-ai-flows\|--no-features\|--features-only" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-architect.md
```

- [ ] **Step 2: Add flag descriptions to top of command body**

After the `--features-only` block (v4.2 flags), insert:

```markdown
**v4.3-specific flags:**
- `--no-ai-memory` — even when ≥1 AI flow is detected, skip Phase 3.8 (memory.md).
  Default OFF (memory.md IS produced when ≥1 AI flow is detected).
- `--no-ai-rag` — same shape; skips Phase 3.9 (rag.md). Default OFF.
- `--ai-memory-only` — diagnostic: run Phase 1 + 3.7 (per-flow ai-flow notes,
  needed for cross-link integrity) + Phase 3.8 only. Useful for iterating on
  the memory prompt.
- `--ai-rag-only` — same shape for Phase 3.9.
```

- [ ] **Step 3: Insert Phase 3.8 between existing 3.7 and Phase 4**

After "Phase 3.7: AI Flow synthesis (v4.1)" section closes, insert:

````markdown
## Phase 3.8: AI memory synthesis (v4.3)

Skip if `--no-ai-memory` is passed.

Skip if `scan_report["ai_flows"]` is empty.

Skip if `lockfile.ai_memory.signal-hash` matches the new signal hash AND
`Projects/<P>/Architecture/ai-flows/memory.md` exists (refresh logic).

1. Compute signal hash:
   ```python
   from scripts.architect.sections import signal_hash
   import hashlib
   memory_signal = {
       "ai_memory": scan_report["ai_memory"],
       "per_flow_state_schema_hash": {
           f["slug"]: _sha256_block(arch_dir / "ai-flows" / f"{f['slug']}.md",
                                      "state-schema")
           for f in scan_report["ai_flows"]
       },
   }
   sig_hash = signal_hash(memory_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_memory_prompt
   prompt = build_ai_memory_prompt(
       project=project_name,
       ai_memory_signals=scan_report["ai_memory"],
       ai_flows_summary=[
           {"slug": f["slug"], "framework": f["framework"],
            "root_path": f["root_path"]}
           for f in scan_report["ai_flows"]
       ],
       output_lang=output_lang,
   )
   ```

3. Invoke the LLM. Expect strict JSON: 11 keys (all markdown strings).

4. Compose:
   ```python
   from scripts.architect.sections import compose_ai_memory_note
   note = compose_ai_memory_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["scan: ai_memory",
                        f"ai-flows: {', '.join(f['slug'] for f in scan_report['ai_flows'])}",
                        "manifest: modules"],
       confidence="high" if scan_report["ai_memory"]["summary"]["memory_flows"] > 0 else "medium",
       output_lang=output_lang,
       generated_blocks=llm_output,
       memory_flows=scan_report["ai_memory"]["summary"]["memory_flows"],
       stateless_flows=scan_report["ai_memory"]["summary"]["stateless_flows"],
       backend=scan_report["ai_memory"]["summary"]["primary_backend"],
   )
   ```

5. Write to `Projects/<P>/Architecture/ai-flows/memory.md`.

6. Update lockfile `ai_memory`:
   ```python
   lockfile.ai_memory = {
       "signal-hash": sig_hash,
       "lang": output_lang,
       "last-generated": today_iso,
       "commit": commit,
       "memory_flows": scan_report["ai_memory"]["summary"]["memory_flows"],
       "stateless_flows": scan_report["ai_memory"]["summary"]["stateless_flows"],
       "backend": scan_report["ai_memory"]["summary"]["primary_backend"],
   }
   ```

## Phase 3.9: AI RAG synthesis (v4.3)

Skip if `--no-ai-rag` is passed.

Skip if `scan_report["ai_flows"]` is empty.

Skip if `lockfile.ai_rag.signal-hash` matches the new signal hash AND
`Projects/<P>/Architecture/ai-flows/rag.md` exists.

1. Compute signal hash (mirrors Phase 3.8 but uses `llm-config` block hash
   per flow, since embedding model lives there):
   ```python
   rag_signal = {
       "ai_rag": scan_report["ai_rag"],
       "per_flow_llm_config_hash": {
           f["slug"]: _sha256_block(arch_dir / "ai-flows" / f"{f['slug']}.md",
                                      "llm-config")
           for f in scan_report["ai_flows"]
       },
   }
   sig_hash = signal_hash(rag_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_rag_prompt
   prompt = build_ai_rag_prompt(
       project=project_name,
       ai_rag_signals=scan_report["ai_rag"],
       ai_flows_summary=[...same shape as Phase 3.8...],
       output_lang=output_lang,
   )
   ```

3. Invoke LLM. Expect strict JSON: 11 keys.

4. Compose:
   ```python
   from scripts.architect.sections import compose_ai_rag_note
   summary = scan_report["ai_rag"]["summary"]
   note = compose_ai_rag_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["scan: ai_rag",
                        f"ai-flows: {', '.join(f['slug'] for f in scan_report['ai_flows'])}",
                        "manifest: modules"],
       confidence="high" if summary["embedding_aligned"] is not None else "medium",
       output_lang=output_lang,
       generated_blocks=llm_output,
       rag_flows_read=summary["read_flows"],
       rag_flows_write=summary["write_flows"],
       vector_store=summary["primary_vector_store"],
       embedding_aligned=summary["embedding_aligned"],
   )
   ```

5. Write to `Projects/<P>/Architecture/ai-flows/rag.md`.

6. Update lockfile `ai_rag` (mirrors Phase 3.8 pattern).

7. Hub block + overview drill-down (idempotent, sentinel-aware):
   - Hub `Projects/<P>/<P>.md` architecture-section block: ensure line
     `- AI memory + RAG 深判斷 (v4.3): [[Architecture/ai-flows/memory]] | [[Architecture/ai-flows/rag]]`
     is present once.
   - `Projects/<P>/Architecture/overview.md` drill-down block: ensure line
     `- **AI 跨流程深判斷:** [[ai-flows/memory]] (lifecycle + TTL + compaction) | [[ai-flows/rag]] (data flow + embedding 對齊)`
     is present once.

If `--ai-memory-only` or `--ai-rag-only`: skip Phases 3 / 3.5 / 3.5.5 (features) / 4 (overview);
only Phase 1 + 3.7 (needed for cross-link integrity) + the target phase run.
````

- [ ] **Step 4: Rebuild adapters to confirm command body parses**

Run: `bash scripts/build.sh`
Expected: 4 platform adapters build successfully.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "$(cat <<'EOF'
feat(architect): v4.3 command body — Phase 3.8 + 3.9 ai memory + rag synthesis + flags

Phase 3.8 (AI memory) and Phase 3.9 (AI RAG) sit between 3.7 (per-flow
ai-flow notes) and Phase 4 (overview). Each runs only when ≥1 AI flow
detected and signal-hash differs from lockfile.

Flags: --no-ai-memory / --no-ai-rag / --ai-memory-only / --ai-rag-only.

Hub block + overview drill-down receive cross-flow links (sentinel-aware
idempotent update).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(`dist/` is gitignored — staging command lists only source files.)

### Task 13: `architecture-ai-memory` + `architecture-ai-rag` schemas in ai-first-rules.md

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "architecture-ai-flow\|architecture-features" /Users/leric/Desktop/code/obsidian-second-brain/references/ai-first-rules.md
```

- [ ] **Step 2: Add v4.3 schemas after `architecture-ai-flow` section**

Insert:

````markdown
### `architecture-ai-memory` (v4.3 — cross-flow memory lens)

**File:** `Projects/<P>/Architecture/ai-flows/memory.md`

**Frontmatter:**
```yaml
type: architecture-ai-memory
date: YYYY-MM-DD
project: "[[<project-name>]]"
local-path: "/abs/path/to/repo"           # or repo: "<url>"
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["scan: ai_memory", "ai-flows: <slug1>, <slug2>", "manifest: modules"]
confidence: high                          # high when concrete checkpointer detected
lang: zh-TW
tags: [architecture, ai-memory]
ai-first: true
status: current
memory-flows: 1
stateless-flows: 1
backend: "redis"                          # primary; "mixed" or "none"
```

**Body blocks** (11 @generated sentinels):
1. `summary` — `## 摘要` / `## Summary`
2. `flow-memory-map` — `## 各流程記憶機制` / `## Per-flow memory map` (markdown table)
3. `backend-and-storage` — `## 儲存層` / `## Backend & storage`
4. `scope-and-lifecycle` — `## 範疇與生命週期` / `## Scope & lifecycle`
5. `context-window-management` — `## Context window 管理`
6. `compaction-strategy` — `## 壓縮策略`
7. `long-term-vs-short` — `## 長期 vs 短期記憶`
8. `strengths` — `## 設計優點`
9. `weaknesses` — `## 設計缺點 / 風險`
10. `improvements` — `## 改進機會` (ImprovementItem shape)
11. `dependencies` — `## 相依`

**Voice constraints:**
- NO invention. Empty/null/false scanner signals → prose acknowledges absence.
- Per-flow detail wikilinks out to `[[ai-flows/<slug>#State schema]]`.
- Strengths / weaknesses follow tight bullet shape.

### `architecture-ai-rag` (v4.3 — cross-flow RAG lens)

**File:** `Projects/<P>/Architecture/ai-flows/rag.md`

**Frontmatter:**
```yaml
type: architecture-ai-rag
date: YYYY-MM-DD
project: "[[<project-name>]]"
local-path: "/abs/path/to/repo"
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["scan: ai_rag", "ai-flows: <slug1>, <slug2>", "manifest: modules"]
confidence: high
lang: zh-TW
tags: [architecture, ai-rag]
ai-first: true
status: current
rag-flows-read: 1
rag-flows-write: 1
vector-store: "weaviate"
embedding-aligned: false                  # true | false | null (null when only one side exists)
```

**Body blocks** (11 @generated sentinels):
1. `summary`
2. `rag-data-flow` — `## RAG 資料流` (single Mermaid graph)
3. `ingest-pipeline` — `## Ingest 管線`
4. `vector-store-config` — `## Vector store 設定`
5. `retrieve-strategy` — `## Retrieve 策略`
6. `embedding-providers` — `## Embedding providers`
7. `evaluation` — `## Evaluation`
8. `strengths`
9. `weaknesses`
10. `improvements`
11. `dependencies`

**Voice constraints (same as ai-memory) PLUS:**
- When `embedding-aligned: false`: `weaknesses` MUST include a bullet flagging the provider mismatch; `improvements` MUST include an Imp to align providers (`Confidence: stated`); `embedding-providers` block MUST include a ⚠️ row.
- When `embedding-aligned: true` or `null`: no warning enforced.
````

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "$(cat <<'EOF'
docs(ai-first-rules): v4.3 architecture-ai-memory + architecture-ai-rag schemas

Defines the cross-flow lens schemas: 11 @generated blocks each, voice
constraints (no invention, wikilink-out to per-flow detail), and
embedding-aligned: false → mandatory weaknesses + improvements + warning
in embedding-providers block.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 14: v4.3 announcement in SKILL.md / README.md / CHANGELOG.md

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md**

Find the `/obsidian-architect` description in SKILL.md and add a v4.3 bullet:

```markdown
- **v4.3 (2026-05-28):** Adds two **cross-flow** AI architecture notes when ≥1 AI
  flow detected: `ai-flows/memory.md` (lifecycle / TTL / compaction / context
  window management) and `ai-flows/rag.md` (ingest → vector store → retrieve;
  embedding alignment check). Frontmatter `embedding-aligned: false` is the
  flagship cross-project DataView field — shows misaligned embedding providers
  between write side (qa_to_kb-style) and read side (engines-style). Flags
  `--no-ai-memory` / `--no-ai-rag` / `--ai-memory-only` / `--ai-rag-only`.
```

- [ ] **Step 2: Update README.md command description**

In README.md's commands table, update the `/obsidian-architect` row's description:

Before:
```markdown
| `/obsidian-architect` | Scan codebase + generate v4 architecture report (8 files) + v4.1 AI flows layer + v4.2 product features lens (online/deprecated, gap analysis, doc-sync drift) |
```

After:
```markdown
| `/obsidian-architect` | Scan codebase + generate v4 architecture report (8 files) + v4.1 AI flows layer + v4.2 product features lens + v4.3 AI memory + RAG cross-flow notes (lifecycle, embedding alignment) |
```

- [ ] **Step 3: Update CHANGELOG.md**

Append to the existing `## [Unreleased]` section:

```markdown
- `/obsidian-architect` v4.3 — `ai-flows/memory.md` + `ai-flows/rag.md` cross-flow
  notes. Per spec
  `docs/superpowers/specs/2026-05-28-obsidian-architect-v4.3-ai-memory-rag-design.md`.
  Adds `ai_memory_detect.py` (langgraph checkpointer + langchain memory + reducer
  cap extraction), `ai_rag_detect.py` (vector store + embedding lib + 3-state
  embedding_aligned check), 4 new sections.py helpers (`build_ai_memory_prompt`,
  `build_ai_rag_prompt`, `compose_ai_memory_note`, `compose_ai_rag_note`),
  Lockfile `ai_memory` + `ai_rag` slots (additive), roadmap candidate walks for
  `ai-memory-improvement` + `ai-rag-improvement` (priority `high` when
  `embedding-aligned` evidence cited).
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+readme+changelog): v4.3 AI memory + RAG cross-flow layer announcement

SKILL.md gains a v4.3 bullet; README's command table mentions the
cross-flow AI lenses; CHANGELOG Unreleased lists the additions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase I: Acceptance smoke

### Task 15: Run scanner against `langlive-line-oa` and verify v4.3 keys

**Files:**
- No code changes. Real-vault smoke.

- [ ] **Step 1: Run scanner end-to-end**

```bash
HASH=$(date +%s)
OUT=/tmp/architect-v4.3-smoke-$HASH
mkdir -p "$OUT"
uv run python scripts/architect_scan.py /Users/leric/Desktop/code/langlive-line-oa \
  --out "$OUT" \
  --vault-project-dir /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa
```

Expected: `$OUT/_manifest.yml` and `$OUT/scan-report.json` written. No errors.

- [ ] **Step 2: Verify `ai_memory` + `ai_rag` keys present and correct**

```bash
uv run python -c "
import json
d = json.load(open('$OUT/scan-report.json'))
print('Top-level keys with ai_:', sorted(k for k in d if k.startswith('ai_')))

# Memory checks
fm = d['ai_memory']['per_flow']
print()
print('ai_memory.per_flow:')
for slug, rec in fm.items():
    print(f'  {slug}: has_memory={rec[\"has_memory\"]} backends={rec[\"backends\"]}')

# RAG checks
fr = d['ai_rag']['per_flow']
print()
print('ai_rag.per_flow:')
for slug, rec in fr.items():
    print(f'  {slug}: role={rec[\"role\"]} stores={rec[\"vector_stores\"]} embed_models={rec[\"embedding_models\"]}')

print()
print('ai_rag.summary.embedding_aligned:', d['ai_rag']['summary']['embedding_aligned'])
print('ai_rag.summary.alignment_mismatch:', d['ai_rag']['summary']['alignment_mismatch'])
"
```

Expected output:
- `ai_memory` and `ai_rag` keys both present
- `engines-langgraph`: `has_memory=True` with `backends` including `redis`
- `modules-qa-to-kb`: `has_memory=False`
- `engines-langgraph`: RAG `role=read` (or `both`), vector_stores includes `weaviate`
- `modules-qa-to-kb`: RAG `role=write` (or `both`)
- `embedding_aligned: false` with one mismatch record showing the OpenAI (qa_to_kb) vs Google (engines) provider split

- [ ] **Step 3: Verify full test suite**

```bash
uv run pytest tests/ -q
```

Expected: All PASS (prior 358 + ~24 new = ~382).

- [ ] **Step 4: Verify all 4 platform adapter builds**

```bash
bash scripts/build.sh
```

Expected: 4 platform builds complete successfully.

- [ ] **Step 5: No commit needed — acceptance only**

If any of Steps 1-4 produced unexpected results, write a `## Blocker` note at the top of this plan file describing the observed mismatch (with exact command output), then stop. Otherwise mark Task 15 complete and report `ALL TASKS COMPLETE`.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal / non-goals | Task 1 (registration captures the additive nature) |
| Trigger conditions table | Task 12 (Phase 3.8 / 3.9 body encodes skip logic) |
| Frame & file shape | Task 1 (block schema), Task 9 (composers + frontmatter) |
| Frontmatter (memory.md, rag.md) | Task 9 (composer extra-frontmatter merge) |
| Body block design (11 + 11) | Task 1 (schemas + headings), Task 7 + 8 (prompt directives), Task 9 (compose) |
| Voice constraints (no invention, wikilink-out) | Task 7 (build_ai_memory_prompt), Task 8 (build_ai_rag_prompt) |
| embedding_aligned 3-state behavior | Task 5 (detector), Task 8 (prompt), Task 9 (composer) |
| Scanner additions (ai_memory + ai_rag) | Task 2-3 (memory detector), Task 4-5 (RAG detector), Task 6 (scan integration) |
| Detection patterns (langgraph savers, vector stores, embed models, retrieve params) | Tasks 2, 3, 4, 5 (with concrete regexes) |
| LLM synthesis prompts | Tasks 7, 8 |
| Composer + extra frontmatter | Task 9 |
| Lockfile additions | Task 10 |
| Refresh logic / signal hash composition | Task 12 (Phase 3.8 / 3.9 body documents signal hash composition) |
| Roadmap integration | Task 11 |
| Command surface (flags) | Task 12 |
| Phase ordering | Task 12 (Phase 3.7 → 3.8 → 3.9 → 4 documented) |
| Hub note + overview drill-down | Task 12 |
| Migration / existing-vault handling | (no migration needed in v4.x; implicit in Task 12 skip logic) |
| Tests 1-22 | Distributed: Tasks 2, 3 (memory detect); 4, 5 (rag detect); 7, 8 (prompts); 9 (composers); 10 (lockfile); 11 (roadmap) |
| Out of scope (live eval, dashboard, embed migration helper) | NOT implemented — explicit in spec |
| Success criteria | Task 15 (langlive smoke) |
