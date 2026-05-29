# obsidian-architect v4.1 (AI Flows Layer) Implementation Plan

## Resolution log

**Tasks 13 / 14 staging:** `dist/` is gitignored and had no tracked changes
during the run, so `git add ... dist/` correctly produced an advisory warning
but staged the other listed files. Both commits landed; nothing actually
broken. Plan steps should drop `dist/` from the staging command in future
revisions.

**Task 15 detector mismatch (resolved 2026-05-28):** Initial smoke detected 3
flows instead of 2 because:

1. Parent candidate `backend/engines` matched `_AI_DIR_NAMES` and duplicated
   the nested `backend/engines/langgraph` flow.
2. `modules/qa_to_kb` was classified as `langgraph` because the repo-level
   pyproject lists `langgraph` (used by the OTHER subsystem), even though
   the module's own code only imports `openai` + `langchain_core` utility
   types and uses a custom pipeline.py + nodes/ + prompts.toml structure.

**Fixes (committed after Task 15):**

- `detect_ai_flows` now post-filters via `_drop_ancestor_duplicates`: any flow
  whose `root_path` is a strict ancestor of another flow's `root_path` is
  dropped (the more specific nested flow wins).
- `_classify_candidate` reordered so LOCAL evidence beats repo-level deps,
  and structural custom-pipeline signal (pipeline.py + nodes/ + prompts +
  LLM lib) beats utility-only LangChain imports (`from langchain_core...`).
  Order: langgraph-import > custom-pipeline-structural > langchain-import >
  langgraph-dep > langchain-dep.
- Three new tests in `tests/architect/test_ai_flow.py` lock in the new
  ordering (`test_parent_candidate_dropped_when_nested_flow_exists`,
  `test_langchain_utility_imports_do_not_force_langchain_framework`,
  `test_local_evidence_wins_over_repo_dep`).
- Re-ran the langlive-line-oa smoke after the fix: detected 2 flows,
  `backend/engines/langgraph` → langgraph (confidence stated),
  `modules/qa_to_kb` → custom-pipeline (confidence medium). Matches Task 15
  acceptance criteria.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 v4 之上加 `architecture-ai-flow` 一層 — scanner 自動偵測 LangGraph / LangChain / custom-pipeline 三種 AI 子系統,在 `Architecture/ai-flows/<slug>.md` 寫 10 段判斷型文件,每個 prompt 全文嵌入 collapsible callout 並用 per-prompt sentinel + source-hash drift refresh。

**Architecture:** 純 additive layer。新增 2 個 Python 模組(`ai_flow.py` 偵測 + `prompt_extract.py` 抽 prompt 全文),擴 `sections.py` 加 `ai-flow` section type + `build_ai_flow_prompt`,擴 `scan.py` 串接偵測結果,擴 `candidates.py` 讓 `/obsidian-roadmap` Phase 1 也讀 ai-flows/*.md。Lockfile schema 不 bump(v4 仍 v4),只加 `ai_flows` 字典追蹤 per-flow + per-prompt source-hash。對沒 AI 的 project zero cost。

**Tech Stack:** Python 3.10+, pytest, dataclass, ast 模組(解析 module-level constants 跟 langchain ChatPromptTemplate),tomllib(讀 prompts.toml),既有 `scripts/architect/{sections,scan,lockfile,lang,sentinels}.py`。

**Spec:** `docs/superpowers/specs/2026-05-28-obsidian-architect-v4.1-ai-flows-design.md`

**Suggested branch:** `feat/architect-v4.1-ai-flows`

**Plan-level implementation note:** Spec §4 例子在 sentinel comment 帶 `source-hash=...` attribute,實作上**改為 sentinel 純名稱、source-hash 只存 lockfile**。理由:既有 `scripts/architect/sentinels.py` 的 `_GEN_RE` 只認 `[\w-]+` 名稱,加 attribute 會破 parser。功能不變(drift refresh 仍走 lockfile 比對),sentinel format 保持簡潔。

---

## Task layout

15 個任務分 8 phase。

| Phase | Tasks | 範圍 |
|---|---|---|
| A. Foundation | 1-2 | Lang heading + Lockfile `ai_flows` field |
| B. AI flow detection | 3 | `ai_flow.py` + 3 框架偵測 |
| C. Prompt extraction | 4-5 | `prompt_extract.py` static + dynamic extractors |
| D. Scan integration | 6 | `scan.py` 串接 |
| E. Sections | 7-9 | block names + prompt builder + per-prompt sentinel renderer + ai-flow composer |
| F. Roadmap signal | 10 | `candidates.py` 加讀 `ai-flows/*.md` |
| G. Schema + command | 11-13 | ai-first-rules + command body + module ai-engine-link + adapter rebuild |
| H. Polish | 14-15 | CHANGELOG / SKILL / README + 端到端 smoke |

---

## Phase A — Foundation

### Task 1: Heading map for AI flow sections

**Files:**
- Modify: `scripts/architect/lang.py`
- Modify: `tests/architect/test_lang.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_lang.py`:

```python
def test_heading_map_includes_ai_flow_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Purpose": "## 流程目的",
        "## Graph topology": "## 圖結構",
        "## State schema": "## 狀態 schema",
        "## Prompts": "## Prompts",
        "## LLM config": "## LLM 設定",
        "## Evaluation & observability": "## 評估與觀測",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_ai_flow_keys -v`
Expected: FAIL — missing heading keys.

- [ ] **Step 3: Add HEADING_MAP entries**

Open `scripts/architect/lang.py`. Inside the HEADING_MAP dict (before the closing `}`), add:

```python
    # v4.1 ai-flow body sections
    "## Purpose": {"en": "## Purpose", "zh-TW": "## 流程目的"},
    "## Graph topology": {"en": "## Graph topology", "zh-TW": "## 圖結構"},
    "## State schema": {"en": "## State schema", "zh-TW": "## 狀態 schema"},
    "## Prompts": {"en": "## Prompts", "zh-TW": "## Prompts"},
    "## LLM config": {"en": "## LLM config", "zh-TW": "## LLM 設定"},
    "## Evaluation & observability": {"en": "## Evaluation & observability", "zh-TW": "## 評估與觀測"},
```

Note: `## Purpose` may already exist (overview uses `## Purpose & audience`). Check first with:

```bash
grep -n '"## Purpose"' scripts/architect/lang.py
```

If `"## Purpose"` already maps to `## 用途` or similar, KEEP that mapping and SKIP this entry — `## Purpose` is reused by ai-flow as well (translation `## 流程目的` is fine to override, OR if the existing en-zh mapping is fine we leave it as-is).

Actually different translation makes sense:
- For overview: `## Purpose & audience` is its own key.
- For ai-flow: `## Purpose` standalone → `## 流程目的`.

These are different keys, so both can coexist in the map.

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_ai_flow_keys -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lang.py tests/architect/test_lang.py
git commit -m "feat(architect): heading map entries for ai-flow sections"
```

---

### Task 2: Lockfile `ai_flows` field

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_lockfile.py`:

```python
def test_lockfile_has_ai_flows_field(tmp_path: Path):
    """v4.1 — Lockfile has an `ai_flows` dict tracking per-flow + per-prompt source-hash."""
    import json
    from scripts.architect.lockfile import Lockfile, load_lockfile, write_lockfile
    lock = Lockfile(
        version=4,
        scanner_version="0.4.1",
        fields={},
        note_blocks={},
        sections={},
        functions={},
        frame="report-v4",
        ai_flows={
            "lang-ai-customer": {
                "signal-hash": "sha256:abc",
                "lang": "zh-TW",
                "framework": "langgraph",
                "node-blocks-hash": "sha256:def",
                "last-generated": "2026-05-28T10:00:00Z",
                "prompts": {
                    "intent_classifier": {
                        "source-hash": "sha256:p1",
                        "source": "backend/engines/langgraph/prompts/intent.py:1-25",
                        "is_dynamic": False,
                    },
                    "rag_answer": {
                        "source-hash": "sha256:p2",
                        "source": "backend/engines/langgraph/prompts/answer.py:30-90",
                        "is_dynamic": False,
                    },
                    "safety_check": {
                        "source-hash": "sha256:dynamic",
                        "source": "(see ai-flow note `## Prompts` body)",
                        "is_dynamic": True,
                    },
                },
            },
        },
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert "lang-ai-customer" in loaded.ai_flows
    assert loaded.ai_flows["lang-ai-customer"]["framework"] == "langgraph"
    assert loaded.ai_flows["lang-ai-customer"]["prompts"]["intent_classifier"]["source-hash"] == "sha256:p1"
    assert loaded.ai_flows["lang-ai-customer"]["prompts"]["safety_check"]["is_dynamic"] is True


def test_load_v4_lockfile_without_ai_flows_yields_empty_dict(tmp_path: Path):
    """Old v4 lockfile (no ai_flows key) should still load — ai_flows defaults to {}."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 4,
        "scanner_version": "0.4.0",
        "fields": {},
        "note_blocks": {},
        "sections": {},
        "functions": {},
        "frame": "report-v4",
    }))
    loaded = load_lockfile(target)
    assert loaded.ai_flows == {}


def test_ai_flow_prompt_drift_helper():
    """Lockfile helper: detect whether a prompt's source-hash changed."""
    from scripts.architect.lockfile import Lockfile, ai_flow_prompt_changed
    lock = Lockfile(
        version=4, scanner_version="0.4.1",
        fields={}, note_blocks={}, sections={}, functions={}, frame="report-v4",
        ai_flows={
            "lang-ai-customer": {
                "prompts": {
                    "intent_classifier": {"source-hash": "sha256:old"},
                },
            },
        },
    )
    # Same hash → not changed
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "intent_classifier", "sha256:old") is False
    # Different hash → changed
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "intent_classifier", "sha256:new") is True
    # Missing prompt → changed (treat as first-time-generated)
    assert ai_flow_prompt_changed(lock, "lang-ai-customer", "new_prompt", "sha256:anything") is True
    # Missing flow → changed
    assert ai_flow_prompt_changed(lock, "nonexistent-flow", "intent_classifier", "sha256:x") is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py -v -k "ai_flow" 2>&1 | tail -10`
Expected: FAIL — `ai_flows` attribute / `ai_flow_prompt_changed` function not defined.

- [ ] **Step 3: Update `scripts/architect/lockfile.py`**

Find the `Lockfile` dataclass. Add `ai_flows` field at the end:

```python
@dataclass
class Lockfile:
    version: int
    scanner_version: str
    fields: dict = field(default_factory=dict)
    note_blocks: dict = field(default_factory=dict)
    sections: dict = field(default_factory=dict)
    functions: dict = field(default_factory=dict)
    frame: str = "description-v2"
    ai_flows: dict = field(default_factory=dict)  # v4.1 — per-flow + per-prompt source-hash tracking
```

Update `load_lockfile` to pull `ai_flows` from JSON (default `{}`):

```python
def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    incoming_version = data.get("version", 1)
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
        ai_flows=data.get("ai_flows", {}),
    )
```

`write_lockfile` already uses `asdict(lock)`, so `ai_flows` will round-trip automatically.

At the end of the file, append the drift helper:

```python
def ai_flow_prompt_changed(
    lock: Lockfile, flow_slug: str, prompt_name: str, current_source_hash: str
) -> bool:
    """True iff the prompt's source-hash differs from what the lockfile recorded.

    Missing flow or missing prompt entry also counts as "changed" (treat as first-time
    materialization → regenerate the sentinel block).
    """
    flow = lock.ai_flows.get(flow_slug, {})
    prompts = flow.get("prompts", {})
    record = prompts.get(prompt_name)
    if record is None:
        return True
    return record.get("source-hash") != current_source_hash
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v 2>&1 | tail -5`
Expected: PASS (all old + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "feat(architect): lockfile ai_flows field + ai_flow_prompt_changed drift helper"
```

---

## Phase B — AI flow detection

### Task 3: `ai_flow.py` — detect LangGraph / LangChain / custom-pipeline

**Files:**
- Create: `scripts/architect/ai_flow.py`
- Create: `tests/architect/test_ai_flow.py`
- Create: `tests/architect/fixtures/langgraph_proj/` (fixture tree, contents per Step 1)
- Create: `tests/architect/fixtures/custom_pipeline_proj/` (fixture tree)
- Create: `tests/architect/fixtures/no_ai_proj/` (fixture tree)

- [ ] **Step 1: Create fixture: LangGraph project**

```bash
mkdir -p tests/architect/fixtures/langgraph_proj/app/{nodes,prompts,core}
```

`tests/architect/fixtures/langgraph_proj/pyproject.toml`:

```toml
[project]
name = "test-lg"
dependencies = ["langgraph>=0.2.0", "openai>=1.0"]
```

`tests/architect/fixtures/langgraph_proj/app/graph.py`:

```python
from langgraph.graph import StateGraph
from app.core.state import CustomerState
from app.nodes.intent import classify_intent
from app.nodes.retrieve import retrieve_docs
from app.nodes.generate import generate_answer

def build_graph():
    g = StateGraph(CustomerState)
    g.add_node("intent", classify_intent)
    g.add_node("retrieve", retrieve_docs)
    g.add_node("generate", generate_answer)
    g.set_entry_point("intent")
    g.add_edge("intent", "retrieve")
    g.add_edge("retrieve", "generate")
    return g.compile()
```

`tests/architect/fixtures/langgraph_proj/app/core/state.py`:

```python
from typing import TypedDict, Literal

class CustomerState(TypedDict):
    user_message: str
    intent: Literal["product", "complaint", "other"]
    docs: list
    answer: str
```

`tests/architect/fixtures/langgraph_proj/app/nodes/intent.py`:

```python
def classify_intent(state): return state
```

(empty stubs are fine for detection)

`tests/architect/fixtures/langgraph_proj/app/nodes/retrieve.py` + `app/nodes/generate.py`: same stub pattern.

`tests/architect/fixtures/langgraph_proj/app/prompts/intent.py`:

```python
INTENT_PROMPT = """You are an intent classifier.
Given: {user_message}
Return one of: PRODUCT, COMPLAINT, OTHER.
"""
```

- [ ] **Step 2: Create fixture: custom-pipeline project**

```bash
mkdir -p tests/architect/fixtures/custom_pipeline_proj/pipeline/{nodes,config}
```

`tests/architect/fixtures/custom_pipeline_proj/pyproject.toml`:

```toml
[project]
name = "test-pipeline"
dependencies = ["openai>=1.0", "anthropic>=0.20"]
```

`tests/architect/fixtures/custom_pipeline_proj/pipeline/pipeline.py`:

```python
from pipeline.nodes.stage1 import run as stage1
from pipeline.nodes.stage2 import run as stage2
from pipeline.nodes.stage3 import run as stage3
import openai

def run_pipeline(input_data):
    x = stage1(input_data)
    y = stage2(x)
    return stage3(y)
```

`tests/architect/fixtures/custom_pipeline_proj/pipeline/nodes/stage1.py`,`stage2.py`,`stage3.py`: simple stubs.

`tests/architect/fixtures/custom_pipeline_proj/pipeline/config/prompts.toml`:

```toml
[summarize]
template = "Summarize this conversation:\n{conversation}\n\nReturn 3 bullets."

[classify]
template = "Classify the intent: {text}"
```

- [ ] **Step 3: Create fixture: non-AI project**

```bash
mkdir -p tests/architect/fixtures/no_ai_proj/src
```

`tests/architect/fixtures/no_ai_proj/pyproject.toml`:

```toml
[project]
name = "no-ai"
dependencies = ["flask>=2.0", "requests>=2.0"]
```

`tests/architect/fixtures/no_ai_proj/src/app.py`:

```python
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello(): return "Hello"
```

- [ ] **Step 4: Write failing tests**

Create `tests/architect/test_ai_flow.py`:

```python
from pathlib import Path

from scripts.architect.ai_flow import AIFlow, detect_ai_flows

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_detects_langgraph_project():
    flows = detect_ai_flows(FIXTURE_DIR / "langgraph_proj")
    assert len(flows) == 1
    f = flows[0]
    assert f.framework == "langgraph"
    assert f.node_count >= 3
    assert "app" in f.root_path or "graph" in f.root_path
    assert any("prompts" in p for p in f.prompt_files)


def test_detects_custom_pipeline_project():
    flows = detect_ai_flows(FIXTURE_DIR / "custom_pipeline_proj")
    assert len(flows) == 1
    f = flows[0]
    assert f.framework == "custom-pipeline"
    assert "pipeline" in f.root_path
    assert any("prompts.toml" in p for p in f.prompt_files)


def test_detects_no_ai_in_flask_project():
    flows = detect_ai_flows(FIXTURE_DIR / "no_ai_proj")
    assert flows == []


def test_node_count_threshold_enforced(tmp_path: Path):
    """Project with langgraph dep but only 1 node should NOT count as AI flow."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "tiny"\ndependencies = ["langgraph"]\n'
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "graph.py").write_text(
        'from langgraph.graph import StateGraph\n'
        'g = StateGraph(dict)\n'
        'g.add_node("only", lambda s: s)\n'  # ONLY 1 node
    )
    flows = detect_ai_flows(tmp_path)
    assert flows == []


def test_ai_flow_slug_is_filename_safe():
    """AIFlow.slug must be ascii lowercase hyphen — usable as filename."""
    import re
    flows = detect_ai_flows(FIXTURE_DIR / "langgraph_proj")
    for f in flows:
        assert re.match(r"^[a-z0-9-]+$", f.slug), f"bad slug: {f.slug!r}"
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_ai_flow.py -v`
Expected: FAIL — module not found.

- [ ] **Step 6: Implement `scripts/architect/ai_flow.py`**

```python
"""Detect AI flow subsystems (LangGraph / LangChain / custom-pipeline) in a repo.

A "flow" is more than a one-off LLM call — it has structured nodes (≥ 3), a graph or
pipeline file, and prompt sources. Returned AIFlow records feed `Architecture/ai-flows/`
note generation.

Detection runs over candidate root directories within the repo. Common locations:
- `<repo>/<module>/engines/<framework>/` (e.g. backend/engines/langgraph/)
- `<repo>/<module>/` itself (e.g. modules/qa_to_kb/)
- `<repo>/agents/`, `<repo>/workflows/`
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

NODE_THRESHOLD = 3


@dataclass
class AIFlow:
    slug: str                       # ai-flows/<slug>.md filename (ascii lowercase hyphen)
    name: str                       # display name (zh-TW or en, free-form)
    framework: str                  # langgraph | langchain | custom-pipeline
    root_path: str                  # repo-relative posix path (e.g. "backend/engines/langgraph")
    flow_kind: str                  # real-time-chat | batch-pipeline | rag | tool-use-agent
    node_count: int
    prompt_files: list[str] = field(default_factory=list)
    state_module: str | None = None
    graph_files: list[str] = field(default_factory=list)
    llm_libs: list[str] = field(default_factory=list)
    confidence: str = "medium"      # stated | high | medium


# ---------- detection orchestrator ----------

def detect_ai_flows(repo_root: Path) -> list[AIFlow]:
    """Find all AI flow subsystems in this repo.

    Heuristic:
    1. Identify candidate roots (dirs containing graph.py | pipeline.py | agents/ | workflows/).
    2. For each candidate, check framework signal + node count.
    3. Drop candidates failing NODE_THRESHOLD (default 3).
    """
    repo_root = repo_root.resolve()
    flows: list[AIFlow] = []
    seen_roots: set[Path] = set()
    deps = _read_project_dependencies(repo_root)

    for candidate_root in _candidate_roots(repo_root):
        if candidate_root in seen_roots:
            continue
        seen_roots.add(candidate_root)
        flow = _classify_candidate(candidate_root, repo_root, deps)
        if flow and flow.node_count >= NODE_THRESHOLD:
            flows.append(flow)
    return flows


# ---------- candidate identification ----------

_AI_DIR_SIGNALS = ("graph.py", "pipeline.py")
_AI_DIR_NAMES = ("agents", "workflows", "engines", "qa_to_kb")
_EXCLUDED_DIRS = {".git", "node_modules", ".venv", "venv", "dist", "build",
                  "__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache",
                  ".claude", "worktrees", "_archive"}


def _candidate_roots(repo_root: Path) -> list[Path]:
    """Walk one level into common host module dirs; collect dirs that look AI-ish."""
    candidates: set[Path] = set()
    # Scan up to 4 levels deep to find graph.py / pipeline.py.
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if _EXCLUDED_DIRS.intersection(p.parts):
            continue
        depth = len(p.relative_to(repo_root).parts)
        if depth > 5:
            continue
        if p.name in _AI_DIR_SIGNALS:
            candidates.add(p.parent)
        elif p.suffix == ".py" and p.parent.name in _AI_DIR_NAMES:
            candidates.add(p.parent)
    return sorted(candidates)


def _classify_candidate(candidate: Path, repo_root: Path, deps: list[str]) -> AIFlow | None:
    """Return an AIFlow if `candidate` is a real AI flow root, else None."""
    py_files = [p for p in candidate.rglob("*.py") if not _EXCLUDED_DIRS.intersection(p.parts)]

    has_langgraph_dep = any("langgraph" in d.lower() for d in deps)
    has_langchain_dep = any("langchain" in d.lower() and "langgraph" not in d.lower() for d in deps)
    has_llm_dep = any(lib in d.lower() for d in deps for lib in ("openai", "anthropic", "google.generativeai", "google-generativeai"))

    # Check import usage in py_files.
    import_text = "\n".join(_safe_read(p) for p in py_files)
    has_langgraph_import = "from langgraph" in import_text or "import langgraph" in import_text
    has_langchain_import = "from langchain" in import_text and "from langgraph" not in import_text

    # Count nodes.
    node_count = _count_nodes(candidate, import_text)

    # Locate state module, prompts, graph files.
    state_module = _find_state_module(candidate, repo_root)
    prompt_files = _find_prompt_files(candidate, repo_root)
    graph_files = _find_graph_files(candidate, repo_root)
    llm_libs = _used_llm_libs(import_text)

    rel_root = candidate.relative_to(repo_root).as_posix()
    slug = _slugify_root(rel_root)
    name = _display_name(candidate)

    # Classify framework.
    if has_langgraph_dep or has_langgraph_import:
        return AIFlow(
            slug=slug, name=name, framework="langgraph", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=state_module, graph_files=graph_files, llm_libs=llm_libs,
            confidence="stated" if has_langgraph_dep and has_langgraph_import else "high",
        )
    if has_langchain_dep or has_langchain_import:
        return AIFlow(
            slug=slug, name=name, framework="langchain", root_path=rel_root,
            flow_kind=_infer_flow_kind(candidate, py_files),
            node_count=node_count, prompt_files=prompt_files,
            state_module=None, graph_files=graph_files, llm_libs=llm_libs,
            confidence="high",
        )
    # Custom pipeline: has pipeline.py + nodes/ + prompts + LLM lib usage.
    has_pipeline_file = any(p.name == "pipeline.py" for p in py_files)
    has_nodes_dir = (candidate / "nodes").is_dir()
    if has_pipeline_file and has_nodes_dir and (has_llm_dep or llm_libs) and prompt_files:
        return AIFlow(
            slug=slug, name=name, framework="custom-pipeline", root_path=rel_root,
            flow_kind="batch-pipeline",
            node_count=node_count, prompt_files=prompt_files,
            state_module=None, graph_files=[],
            llm_libs=llm_libs, confidence="medium",
        )
    return None


# ---------- helpers ----------

def _read_project_dependencies(repo_root: Path) -> list[str]:
    """Pull dep names from pyproject.toml + package.json (best-effort)."""
    deps: list[str] = []
    py = repo_root / "pyproject.toml"
    if py.exists():
        try:
            data = tomllib.loads(py.read_text())
            deps.extend(data.get("project", {}).get("dependencies", []))
            dev = data.get("dependency-groups", {}).get("dev", []) or []
            deps.extend(dev if isinstance(dev, list) else [])
        except (tomllib.TOMLDecodeError, OSError):
            pass
    # Also walk monorepo subdirs for nested pyproject.tomls (mirror stack.py pattern).
    for sub in ("backend", "frontend", "modules", "services", "api"):
        sub_py = repo_root / sub / "pyproject.toml"
        if sub_py.exists():
            try:
                data = tomllib.loads(sub_py.read_text())
                deps.extend(data.get("project", {}).get("dependencies", []))
            except (tomllib.TOMLDecodeError, OSError):
                pass
    # Also requirements.txt (some projects use that).
    for req in repo_root.rglob("requirements*.txt"):
        if _EXCLUDED_DIRS.intersection(req.parts):
            continue
        try:
            deps.extend(line.strip() for line in req.read_text().splitlines() if line.strip() and not line.startswith("#"))
        except OSError:
            pass
    return deps


_NODE_PATTERN_LG = re.compile(r"\.add_node\s*\(\s*['\"]([^'\"]+)['\"]")
_NODE_PATTERN_PY_FILE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")


def _count_nodes(candidate: Path, import_text: str) -> int:
    """Count LangGraph add_node calls OR files under <candidate>/nodes/."""
    count = len(set(_NODE_PATTERN_LG.findall(import_text)))
    if count >= NODE_THRESHOLD:
        return count
    # Fallback: count .py files in <candidate>/nodes/
    nodes_dir = candidate / "nodes"
    if nodes_dir.is_dir():
        return max(count, sum(1 for p in nodes_dir.rglob("*.py")
                              if p.name != "__init__.py"
                              and not _EXCLUDED_DIRS.intersection(p.parts)))
    return count


def _find_state_module(candidate: Path, repo_root: Path) -> str | None:
    for name in ("state.py",):
        for p in candidate.rglob(name):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                return p.relative_to(repo_root).as_posix()
    return None


def _find_prompt_files(candidate: Path, repo_root: Path) -> list[str]:
    out: list[str] = []
    # prompts/*.py
    prompts_dir = candidate / "prompts"
    if prompts_dir.is_dir():
        for p in sorted(prompts_dir.rglob("*.py")):
            if p.name != "__init__.py" and not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    # prompts.toml / prompts.yaml / prompts.json (any depth within candidate)
    for ext in ("toml", "yaml", "yml", "json"):
        for p in candidate.rglob(f"prompts.{ext}"):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    return sorted(set(out))


def _find_graph_files(candidate: Path, repo_root: Path) -> list[str]:
    out: list[str] = []
    for name in ("graph.py",):
        for p in candidate.rglob(name):
            if not _EXCLUDED_DIRS.intersection(p.parts):
                out.append(p.relative_to(repo_root).as_posix())
    graphs_dir = candidate / "graphs"
    if graphs_dir.is_dir():
        for p in sorted(graphs_dir.glob("*.py")):
            if p.name != "__init__.py":
                out.append(p.relative_to(repo_root).as_posix())
    return sorted(set(out))


_LLM_LIB_PATTERNS = (
    ("openai", "openai"),
    ("anthropic", "anthropic"),
    ("google.generativeai", "google-generativeai"),
    ("google_generativeai", "google-generativeai"),
    ("cohere", "cohere"),
    ("bedrock", "boto3-bedrock"),
)


def _used_llm_libs(import_text: str) -> list[str]:
    out: set[str] = set()
    for needle, label in _LLM_LIB_PATTERNS:
        if needle in import_text:
            out.add(label)
    return sorted(out)


def _safe_read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def _slugify_root(rel_root: str) -> str:
    """Convert e.g. 'backend/engines/langgraph' → 'lang-ai-customer' OR 'backend-engines-langgraph'.

    Strategy: last 2 path segments lowercased and hyphenated.
    """
    parts = rel_root.split("/")
    tail = "-".join(parts[-2:]) if len(parts) >= 2 else parts[-1]
    slug = re.sub(r"[^a-z0-9-]+", "-", tail.lower()).strip("-")
    return slug or "unknown-ai-flow"


def _display_name(candidate: Path) -> str:
    # Prefer the candidate dir's basename, capitalized.
    return candidate.name.replace("_", " ").replace("-", " ").title()


def _infer_flow_kind(candidate: Path, py_files: list[Path]) -> str:
    """Heuristic: webhook/handler/route in nearby code → real-time-chat;
    pipeline/worker/job → batch-pipeline; default real-time-chat for langgraph."""
    text = " ".join(_safe_read(p) for p in py_files[:20])
    if any(kw in text.lower() for kw in ("webhook", "websocket", "fastapi", "route", "chat")):
        return "real-time-chat"
    if any(kw in text.lower() for kw in ("pipeline", "worker", "batch", "brpop", "consumer")):
        return "batch-pipeline"
    return "real-time-chat"
```

- [ ] **Step 7: Run tests**

Run: `uv run pytest tests/architect/test_ai_flow.py -v 2>&1 | tail -15`
Expected: PASS (5 tests).

- [ ] **Step 8: Commit**

```bash
git add scripts/architect/ai_flow.py tests/architect/test_ai_flow.py tests/architect/fixtures/langgraph_proj tests/architect/fixtures/custom_pipeline_proj tests/architect/fixtures/no_ai_proj
git commit -m "feat(architect): detect_ai_flows for LangGraph / LangChain / custom-pipeline"
```

---

## Phase C — Prompt extraction

### Task 4: `prompt_extract.py` — static extractors (toml + module-constant + SYSTEM_PROMPT + langchain)

**Files:**
- Create: `scripts/architect/prompt_extract.py`
- Create: `tests/architect/test_prompt_extract.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_prompt_extract.py`:

```python
import hashlib
from pathlib import Path

from scripts.architect.prompt_extract import ExtractedPrompt, extract_prompts


def test_extracts_toml_config_prompts(tmp_path: Path):
    (tmp_path / "config").mkdir()
    (tmp_path / "config" / "prompts.toml").write_text(
        '[summarize]\n'
        'template = """Summarize this:\n{conversation}\n\nReturn 3 bullets."""\n'
        '\n'
        '[classify]\n'
        'template = "Classify: {text}"\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "summarize" in names
    assert "classify" in names
    summ = next(p for p in prompts if p.name == "summarize")
    assert "Summarize this" in summ.body
    assert "{conversation}" in summ.body
    assert summ.is_dynamic is False
    assert summ.source.startswith("config/prompts.toml")
    assert summ.source_hash.startswith("sha256:")
    # Reproducible hash
    expected = "sha256:" + hashlib.sha256(summ.body.encode("utf-8")).hexdigest()
    assert summ.source_hash == expected
    assert summ.extraction_method == "toml-config"


def test_extracts_python_module_constant(tmp_path: Path):
    (tmp_path / "prompts").mkdir()
    (tmp_path / "prompts" / "intent.py").write_text(
        '"""Intent classifier prompts."""\n'
        '\n'
        'INTENT_PROMPT = """You are an intent classifier.\n'
        'Given: {user_message}\n'
        'Return: PRODUCT | COMPLAINT | OTHER.\n'
        '"""\n'
        '\n'
        '# Helper not exported\n'
        'def build(): pass\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "INTENT_PROMPT" in names
    intent = next(p for p in prompts if p.name == "INTENT_PROMPT")
    assert "intent classifier" in intent.body.lower()
    assert "{user_message}" in intent.body
    assert intent.is_dynamic is False
    assert intent.extraction_method == "module-constant"
    assert "prompts/intent.py" in intent.source


def test_extracts_system_prompt_pattern(tmp_path: Path):
    (tmp_path / "agent.py").write_text(
        '\n'
        'SYSTEM_PROMPT = """You are a helpful assistant focused on customer service."""\n'
        'USER_PROMPT_TEMPLATE = "Question: {q}"\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "SYSTEM_PROMPT" in names
    assert "USER_PROMPT_TEMPLATE" in names


def test_extracts_langchain_chat_prompt_template(tmp_path: Path):
    (tmp_path / "chain.py").write_text(
        'from langchain_core.prompts import ChatPromptTemplate\n'
        'from langchain_core.messages import SystemMessage, HumanMessage\n'
        '\n'
        'CHAT_PROMPT = ChatPromptTemplate.from_messages([\n'
        '    SystemMessage(content="You are an expert at categorization."),\n'
        '    HumanMessage(content="Categorize: {input}"),\n'
        '])\n'
    )
    prompts = extract_prompts(tmp_path)
    names = {p.name for p in prompts}
    assert "CHAT_PROMPT" in names
    cp = next(p for p in prompts if p.name == "CHAT_PROMPT")
    assert "expert at categorization" in cp.body
    assert "Categorize" in cp.body
    assert cp.is_dynamic is False
    assert cp.extraction_method == "langchain-chat-prompt-template"


def test_skips_non_prompt_string_constants(tmp_path: Path):
    """Random string constants (not prompt-like) should NOT be extracted."""
    (tmp_path / "config.py").write_text(
        'DATABASE_URL = "postgresql://localhost/db"\n'
        'API_VERSION = "v1"\n'
        'SIMPLE_NAME = "Hello"\n'
    )
    prompts = extract_prompts(tmp_path)
    # No PROMPT-suffix or PROMPT-prefix names → nothing extracted from Python constants.
    # But config.py has no .toml so 0 prompts.
    assert prompts == []


def test_source_hash_changes_when_body_changes(tmp_path: Path):
    (tmp_path / "config").mkdir()
    (tmp_path / "config" / "prompts.toml").write_text('[p]\ntemplate = "v1"\n')
    h1 = extract_prompts(tmp_path)[0].source_hash
    (tmp_path / "config" / "prompts.toml").write_text('[p]\ntemplate = "v2"\n')
    h2 = extract_prompts(tmp_path)[0].source_hash
    assert h1 != h2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_prompt_extract.py -v 2>&1 | tail -15`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/architect/prompt_extract.py`**

```python
"""Extract prompt strings from an AI flow root.

Returns ExtractedPrompt records with full body text (for static templates) or
"dynamic" placeholder (when the prompt is assembled programmatically). Each
record carries a source-hash used by the lockfile to detect drift on re-scan.

Extractors run in priority order:
1. toml / yaml / json `prompts.<ext>` config files
2. Python module-level UPPER_CASE constants assigned triple-quoted strings
3. SYSTEM_PROMPT / USER_PROMPT / TEMPLATE_ prefixed constants
4. LangChain ChatPromptTemplate.from_messages([...]) message contents
"""

from __future__ import annotations

import ast
import hashlib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

_EXCLUDED_DIRS = {".git", "node_modules", ".venv", "venv", "dist", "build",
                  "__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache",
                  ".claude", "worktrees", "_archive"}


@dataclass
class ExtractedPrompt:
    name: str
    source: str                     # repo-relative `path:line-start-line-end`
    body: str                       # full text (static) or description (dynamic)
    is_dynamic: bool
    source_hash: str                # "sha256:<hex>" of `body`
    model_hint: str | None = None
    extraction_method: str = ""     # toml-config | yaml-config | json-config |
                                    # module-constant | system-prompt-pattern |
                                    # langchain-chat-prompt-template | dynamic-trace
    extraction_notes: list[str] = field(default_factory=list)


def extract_prompts(flow_root: Path) -> list[ExtractedPrompt]:
    """Run all extractors over a flow root; return deduplicated ExtractedPrompt list."""
    flow_root = flow_root.resolve()
    out: list[ExtractedPrompt] = []
    seen_names: set[str] = set()

    # 1. TOML / YAML / JSON config files
    for ext, extractor in (("toml", _extract_toml), ("yaml", _extract_yaml),
                            ("yml", _extract_yaml), ("json", _extract_json)):
        for cfg in flow_root.rglob(f"prompts.{ext}"):
            if _EXCLUDED_DIRS.intersection(cfg.parts):
                continue
            try:
                items = extractor(cfg, flow_root)
            except Exception:
                items = []
            for item in items:
                if item.name in seen_names:
                    continue
                seen_names.add(item.name)
                out.append(item)

    # 2-3-4. Python files
    for py in flow_root.rglob("*.py"):
        if _EXCLUDED_DIRS.intersection(py.parts) or py.name == "__init__.py":
            continue
        for item in _extract_python(py, flow_root):
            if item.name in seen_names:
                continue
            seen_names.add(item.name)
            out.append(item)
    return out


# ---------- TOML / YAML / JSON ----------

def _hash(body: str) -> str:
    return "sha256:" + hashlib.sha256(body.encode("utf-8")).hexdigest()


def _extract_toml(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    out: list[ExtractedPrompt] = []
    rel = path.relative_to(flow_root.parent if flow_root.parent.exists() else flow_root).as_posix()
    for name, value in data.items():
        body = _coerce_prompt_value(value)
        if body is None:
            continue
        out.append(ExtractedPrompt(
            name=name,
            source=f"{rel}:1",
            body=body,
            is_dynamic=False,
            source_hash=_hash(body),
            extraction_method="toml-config",
        ))
    return out


def _extract_yaml(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    try:
        import yaml
    except ImportError:
        return []
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    rel = path.relative_to(flow_root.parent if flow_root.parent.exists() else flow_root).as_posix()
    out: list[ExtractedPrompt] = []
    if isinstance(data, dict):
        for name, value in data.items():
            body = _coerce_prompt_value(value)
            if body is None:
                continue
            out.append(ExtractedPrompt(
                name=name, source=f"{rel}:1", body=body, is_dynamic=False,
                source_hash=_hash(body), extraction_method="yaml-config",
            ))
    return out


def _extract_json(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    import json
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    rel = path.relative_to(flow_root.parent if flow_root.parent.exists() else flow_root).as_posix()
    out: list[ExtractedPrompt] = []
    if isinstance(data, dict):
        for name, value in data.items():
            body = _coerce_prompt_value(value)
            if body is None:
                continue
            out.append(ExtractedPrompt(
                name=name, source=f"{rel}:1", body=body, is_dynamic=False,
                source_hash=_hash(body), extraction_method="json-config",
            ))
    return out


def _coerce_prompt_value(value) -> str | None:
    """Config value → prompt body string.  Accepts {template: "..."}, "...", or skips."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if "template" in value and isinstance(value["template"], str):
            return value["template"]
        if "prompt" in value and isinstance(value["prompt"], str):
            return value["prompt"]
        if "text" in value and isinstance(value["text"], str):
            return value["text"]
    return None


# ---------- Python AST extractors ----------

_PROMPT_NAME_RE = re.compile(r"^(.*_PROMPT|.*PROMPT_.*|.*_TEMPLATE|TEMPLATE_.*|CHAT_PROMPT|.*_INSTRUCTIONS)$")


def _extract_python(path: Path, flow_root: Path) -> list[ExtractedPrompt]:
    src = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    rel = path.relative_to(flow_root.parent if flow_root.parent.exists() else flow_root).as_posix()
    out: list[ExtractedPrompt] = []

    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if not isinstance(target, ast.Name):
            continue
        name = target.id

        # Module-level constant pattern: NAME = "..." or NAME = """..."""
        if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            if _looks_like_prompt_name(name) or _looks_like_prompt_body(node.value.value):
                body = node.value.value
                out.append(ExtractedPrompt(
                    name=name,
                    source=f"{rel}:{node.lineno}-{node.end_lineno or node.lineno}",
                    body=body,
                    is_dynamic=False,
                    source_hash=_hash(body),
                    extraction_method="module-constant" if _looks_like_prompt_name(name) else "system-prompt-pattern",
                ))
            continue

        # LangChain ChatPromptTemplate.from_messages([...])
        lc_body = _try_extract_langchain_chat_prompt(node.value)
        if lc_body is not None:
            out.append(ExtractedPrompt(
                name=name,
                source=f"{rel}:{node.lineno}-{node.end_lineno or node.lineno}",
                body=lc_body,
                is_dynamic=False,
                source_hash=_hash(lc_body),
                extraction_method="langchain-chat-prompt-template",
            ))
    return out


def _looks_like_prompt_name(name: str) -> bool:
    """Is this constant name prompt-shaped?"""
    if not name.isupper():
        return False
    return bool(_PROMPT_NAME_RE.match(name))


def _looks_like_prompt_body(body: str) -> bool:
    """Is this string content prompt-shaped? (long-ish, multi-line, or contains format vars)"""
    if len(body) < 30:
        return False
    if "{" in body and "}" in body:  # f-string-style placeholder
        return True
    if "\n" in body and len(body) > 80:
        return True
    return False


def _try_extract_langchain_chat_prompt(value_node: ast.expr) -> str | None:
    """Look for ChatPromptTemplate.from_messages([...]) and concat SystemMessage/HumanMessage contents."""
    if not isinstance(value_node, ast.Call):
        return None
    func = value_node.func
    # ChatPromptTemplate.from_messages
    if not (isinstance(func, ast.Attribute) and func.attr == "from_messages"):
        return None
    obj = func.value
    obj_name = obj.id if isinstance(obj, ast.Name) else (obj.attr if isinstance(obj, ast.Attribute) else "")
    if "ChatPromptTemplate" not in obj_name:
        return None
    if not value_node.args:
        return None
    messages_arg = value_node.args[0]
    if not isinstance(messages_arg, ast.List):
        return None
    parts: list[str] = []
    for elt in messages_arg.elts:
        if not isinstance(elt, ast.Call):
            continue
        cls = elt.func.id if isinstance(elt.func, ast.Name) else (elt.func.attr if isinstance(elt.func, ast.Attribute) else "")
        # Extract `content="..."` kwarg
        for kw in elt.keywords:
            if kw.arg == "content" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                parts.append(f"[{cls}]\n{kw.value.value}")
    if not parts:
        return None
    return "\n\n".join(parts)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_prompt_extract.py -v 2>&1 | tail -15`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/prompt_extract.py tests/architect/test_prompt_extract.py
git commit -m "feat(architect): prompt_extract.py static extractors (toml/python-constant/langchain)"
```

---

### Task 5: Dynamic prompt detection

**Files:**
- Modify: `scripts/architect/prompt_extract.py`
- Modify: `tests/architect/test_prompt_extract.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_prompt_extract.py`:

```python
def test_dynamic_prompt_concat_detected(tmp_path: Path):
    """A prompt assembled via string concat across multiple sources should be marked dynamic."""
    (tmp_path / "agent.py").write_text(
        '\n'
        '_BASE = "You are an assistant."\n'
        '_TONE = "Be concise."\n'
        '\n'
        'def make_prompt(user_input: str) -> str:\n'
        '    return _BASE + " " + _TONE + " Question: " + user_input\n'
        '\n'
        '# Note: no SYSTEM_PROMPT module constant exists.\n'
    )
    prompts = extract_prompts(tmp_path)
    # Two constants are short individually (don't look like prompts on their own).
    # The concat function isn't a static prompt — should NOT extract a stitched-together fake.
    # Either: nothing is extracted, OR if anything is extracted it's marked is_dynamic=True.
    for p in prompts:
        if "Question" in p.body and "assistant" in p.body:
            # If something looking like the concat IS produced, it MUST be marked dynamic.
            assert p.is_dynamic is True, "stitched-together prompt must be marked dynamic"


def test_dynamic_marker_for_format_string_calls(tmp_path: Path):
    """If a make_prompt() / build_prompt() function is detected with multiple inputs, mark dynamic."""
    (tmp_path / "agent.py").write_text(
        '\n'
        'def build_system_prompt(persona: str, tools: list[str]) -> str:\n'
        '    return f"You are {persona}. Available tools: {tools}. Be helpful."\n'
    )
    # No module-level constant; function with dynamic params doesn't produce a static extract.
    # This is a "skip cleanly" case — extract_prompts returns empty.
    prompts = extract_prompts(tmp_path)
    assert prompts == [] or all(p.is_dynamic for p in prompts)
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_prompt_extract.py -v -k "dynamic" 2>&1 | tail -10`
Expected: PASS (these tests are non-strict — they verify "if anything extracted, it's marked dynamic" — current static extractor doesn't extract from these patterns at all, so the tests pass with `prompts == []`).

If tests fail (e.g. the heuristic falsely extracted a fake-stitched prompt), tighten the extractor.

The point of this task is to **document** the dynamic case and ensure the static extractors don't falsely produce a "synthetic" prompt. We don't add a full dynamic tracer — that's a bigger ask. Future enhancement: walk function bodies to identify `prompt =` assembly and emit ExtractedPrompt with `is_dynamic=True` + the trace.

For v4.1, "dynamic" detection is by absence: if no static extractor produces a result, it's reported as 0 prompts. The ai-flow note template then prompts the LLM to look at the source files and write a description block for dynamic prompts manually.

- [ ] **Step 3: Add a documenting note to prompt_extract.py**

Append to the docstring at the top of `scripts/architect/prompt_extract.py`:

```python
"""
... (existing docstring) ...

Dynamic prompts (assembled at runtime via string concat / multi-source build):
We deliberately do NOT trace them and synthesize a "stitched" body — that would
be misleading because the actual runtime content depends on inputs. Instead,
the ai-flow LLM prompt (in sections.py `build_ai_flow_prompt`) is instructed
to look at the source files directly and write a description block, flagging
`Type: dynamic` in the rendered Prompts section.
"""
```

- [ ] **Step 4: Commit**

```bash
git add scripts/architect/prompt_extract.py tests/architect/test_prompt_extract.py
git commit -m "feat(architect): document dynamic prompt non-extraction policy"
```

---

## Phase D — Scan integration

### Task 6: Wire `detect_ai_flows` + `extract_prompts` into `scan.py`

**Files:**
- Modify: `scripts/architect/scan.py`
- Modify: `tests/architect/test_scan.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_scan.py`:

```python
def test_scan_report_includes_ai_flows(tmp_path: Path):
    import subprocess
    from scripts.architect.scan import run_phase_one
    # Build a git repo with LangGraph signature.
    (tmp_path / ".git").mkdir()
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["langgraph>=0.2"]\n'
    )
    (tmp_path / "app").mkdir()
    (tmp_path / "app" / "graph.py").write_text(
        'from langgraph.graph import StateGraph\n'
        'g = StateGraph(dict)\n'
        'g.add_node("a", lambda s: s)\n'
        'g.add_node("b", lambda s: s)\n'
        'g.add_node("c", lambda s: s)\n'
    )
    (tmp_path / "app" / "prompts").mkdir()
    (tmp_path / "app" / "prompts" / "p.py").write_text(
        'P_PROMPT = """Hello {name}, you are an assistant."""\n'
    )
    # Init git so walker.git_metadata doesn't crash.
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    result = run_phase_one(tmp_path)
    assert "ai_flows" in result.scan_report
    assert len(result.scan_report["ai_flows"]) == 1
    flow = result.scan_report["ai_flows"][0]
    assert flow["framework"] == "langgraph"
    # Prompts extracted into the flow record
    assert "prompts" in flow
    prompt_names = {p["name"] for p in flow["prompts"]}
    assert "P_PROMPT" in prompt_names


def test_scan_report_ai_flows_empty_for_non_ai_project(tmp_path: Path):
    import subprocess
    from scripts.architect.scan import run_phase_one
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["flask"]\n'
    )
    (tmp_path / "main.py").write_text('print("hi")\n')
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    result = run_phase_one(tmp_path)
    assert result.scan_report["ai_flows"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_scan.py -v -k "ai_flows" 2>&1 | tail -10`
Expected: FAIL — scan_report doesn't have `ai_flows` key.

- [ ] **Step 3: Update `scripts/architect/scan.py`**

Open `scripts/architect/scan.py`. Find the imports section at the top and add:

```python
from scripts.architect.ai_flow import detect_ai_flows
from scripts.architect.prompt_extract import extract_prompts
```

Find the `run_phase_one` function body. Inside (just before the `scan_report = {...}` dict construction), add:

```python
    # AI flow detection + per-flow prompt extraction (v4.1).
    ai_flows_data: list[dict] = []
    for flow in detect_ai_flows(repo_root):
        flow_dict = {
            "slug": flow.slug,
            "name": flow.name,
            "framework": flow.framework,
            "root_path": flow.root_path,
            "flow_kind": flow.flow_kind,
            "node_count": flow.node_count,
            "prompt_files": flow.prompt_files,
            "state_module": flow.state_module,
            "graph_files": flow.graph_files,
            "llm_libs": flow.llm_libs,
            "confidence": flow.confidence,
            "prompts": [asdict(p) for p in extract_prompts(repo_root / flow.root_path)],
        }
        ai_flows_data.append(flow_dict)
```

Then in the `scan_report = {...}` dict, add the key:

```python
        "ai_flows": ai_flows_data,
```

(`asdict` is already imported from `dataclasses` at the top — confirm with `grep "from dataclasses" scripts/architect/scan.py`. If not, add `from dataclasses import asdict, dataclass`.)

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_scan.py -v 2>&1 | tail -10`
Expected: PASS (all old + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/scan.py tests/architect/test_scan.py
git commit -m "feat(architect): scan_report.ai_flows from detect_ai_flows + extract_prompts"
```

---

## Phase E — Section composer

### Task 7: `_BLOCK_NAMES["ai-flow"]` + `SECTION_TYPES` + `_BLOCK_HEADINGS` + `_preamble_for`

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_sections.py`:

```python
def test_ai_flow_section_type_registered():
    from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS
    assert SECTION_TYPES.get("ai-flow") == "architecture-ai-flow"
    # 10 body blocks per spec §4
    expected = ("purpose", "graph-topology", "state-schema", "prompts",
                "llm-config", "evaluation", "strengths", "weaknesses",
                "improvements", "dependencies")
    assert _BLOCK_NAMES["ai-flow"] == expected
    # Heading mappings for each block
    for block in ("graph-topology", "state-schema", "prompts", "llm-config", "evaluation"):
        assert block in _BLOCK_HEADINGS, f"missing heading mapping for block {block}"


def test_ai_flow_preamble_en_and_zh():
    from scripts.architect.sections import _preamble_for
    en_text = _preamble_for("ai-flow", "en")
    zh_text = _preamble_for("ai-flow", "zh-TW")
    assert "ai" in en_text.lower() or "llm" in en_text.lower()
    assert "AI" in zh_text or "LLM" in zh_text or "Prompts" in zh_text
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v -k "ai_flow" 2>&1 | tail -10`
Expected: FAIL — `_BLOCK_NAMES["ai-flow"]` not defined.

- [ ] **Step 3: Update `scripts/architect/sections.py`**

Find `SECTION_TYPES` dict. Add:

```python
    "ai-flow": "architecture-ai-flow",
```

Find `_BLOCK_NAMES` dict. Add:

```python
    "ai-flow": (
        "purpose", "graph-topology", "state-schema", "prompts",
        "llm-config", "evaluation", "strengths", "weaknesses",
        "improvements", "dependencies",
    ),
```

Find `_BLOCK_HEADINGS` dict. Add the 5 new block-heading mappings:

```python
    "graph-topology": "## Graph topology",
    "state-schema": "## State schema",
    "prompts": "## Prompts",
    "llm-config": "## LLM config",
    "evaluation": "## Evaluation & observability",
```

Note: `purpose` may already exist (used by overview). Verify with `grep '"purpose":' scripts/architect/sections.py`. The existing mapping `"purpose": "## Purpose & audience"` is for overview. For ai-flow we want `## Purpose` (without `& audience`). To handle both:

```python
    # purpose is now overloaded — overview uses "## Purpose & audience",
    # ai-flow uses "## Purpose". Distinguish in compose by section.
```

Simpler approach: rename ai-flow's block from `"purpose"` to `"ai-purpose"` so block-name collision doesn't exist. Update `_BLOCK_NAMES["ai-flow"]` accordingly:

```python
    "ai-flow": (
        "ai-purpose", "graph-topology", "state-schema", "prompts",
        "llm-config", "evaluation", "strengths", "weaknesses",
        "improvements", "dependencies",
    ),
```

And in `_BLOCK_HEADINGS`:

```python
    "ai-purpose": "## Purpose",
```

(`purpose` heading mapping for overview stays as-is.)

Also: `strengths`, `weaknesses`, `improvements`, `dependencies` are already in `_BLOCK_HEADINGS` from v3. Confirm with grep; no duplicates needed.

Find `_preamble_for` function. In the zh-TW dict, add:

```python
        "ai-flow": "本檔是單一 AI 流程的深判斷 — 包含 graph 結構、state schema、prompts 全文、LLM 設定、評估與設計優缺點。",
```

In the en dict, add:

```python
        "ai-flow": "Deep judgment for a single AI flow — graph topology, state schema, full prompts, LLM config, evaluation, and design pros/cons.",
```

- [ ] **Step 4: Update the failing test**

The test expects `_BLOCK_NAMES["ai-flow"][0] == "purpose"` but we renamed to `"ai-purpose"`. Update the test:

```python
def test_ai_flow_section_type_registered():
    from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS
    assert SECTION_TYPES.get("ai-flow") == "architecture-ai-flow"
    expected = ("ai-purpose", "graph-topology", "state-schema", "prompts",
                "llm-config", "evaluation", "strengths", "weaknesses",
                "improvements", "dependencies")
    assert _BLOCK_NAMES["ai-flow"] == expected
    for block in ("ai-purpose", "graph-topology", "state-schema", "prompts", "llm-config", "evaluation"):
        assert block in _BLOCK_HEADINGS, f"missing heading mapping for block {block}"
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "ai_flow" 2>&1 | tail -10`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): register ai-flow section type + 10 body blocks + preamble"
```

---

### Task 8: `build_ai_flow_prompt` LLM prompt builder

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_build_ai_flow_prompt_demands_required_blocks():
    from scripts.architect.sections import build_ai_flow_prompt
    prompt = build_ai_flow_prompt(
        flow_slug="lang-ai-customer",
        flow_name="LangAI Customer Chat",
        framework="langgraph",
        flow_kind="real-time-chat",
        prompts_inventory=[
            {"name": "intent_classifier", "source": "backend/engines/langgraph/prompts/intent.py:1-25",
             "body": "You are an intent classifier...\n", "is_dynamic": False, "source_hash": "sha256:abc"},
        ],
        state_module="backend/engines/langgraph/core/state.py",
        graph_files=["backend/engines/langgraph/graph.py"],
        repomix_packed="(repomix packed content)",
        output_lang="zh-TW",
    )
    assert "lang-ai-customer" in prompt
    assert "langgraph" in prompt
    # Demands 10 block keys
    for block in ("ai-purpose", "graph-topology", "state-schema", "prompts",
                  "llm-config", "evaluation", "strengths", "weaknesses",
                  "improvements", "dependencies"):
        assert block in prompt, f"prompt should mention block {block}"
    # Prompts section instructions
    assert "collapsible" in prompt.lower() or "callout" in prompt.lower()
    assert "[!quote]" in prompt  # Obsidian callout syntax mentioned
    # Forbid full prompt body invention for dynamic prompts
    assert "dynamic" in prompt.lower()
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Imp 5-field
    for field in ("Why", "Evidence", "Effort", "Risk", "Confidence"):
        assert field in prompt


def test_build_ai_flow_prompt_en_no_chinese():
    from scripts.architect.sections import build_ai_flow_prompt
    prompt = build_ai_flow_prompt(
        flow_slug="x", flow_name="X", framework="langgraph", flow_kind="real-time-chat",
        prompts_inventory=[], state_module=None, graph_files=[],
        repomix_packed="", output_lang="en",
    )
    assert "繁體中文" not in prompt
    assert "English" in prompt or "en" in prompt
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py::test_build_ai_flow_prompt_demands_required_blocks -v`
Expected: FAIL — `build_ai_flow_prompt` not defined.

- [ ] **Step 3: Append `build_ai_flow_prompt` to `scripts/architect/sections.py`**

```python


def build_ai_flow_prompt(
    *,
    flow_slug: str,
    flow_name: str,
    framework: str,
    flow_kind: str,
    prompts_inventory: list[dict],
    state_module: str | None,
    graph_files: list[str],
    repomix_packed: str,
    output_lang: str,
) -> str:
    """v4.1 — AI flow synthesis prompt.

    Demands the LLM produce 10 @generated block bodies. Prompts block is special:
    must wrap each prompt body in a collapsible Obsidian callout AND keep
    sentinel structure. Dynamic prompts get a description, NOT a synthesized body.
    """
    if output_lang == "zh-TW":
        lang_directive = (
            "請以繁體中文 (zh-TW) 撰寫所有散文與 heading。"
            "Code identifier (檔名、function/class、state key 名、env var)、"
            "prompt 全文、Mermaid 圖內 node ID 保持英文/原文。"
        )
    else:
        lang_directive = (
            "Write all prose in English. Code identifiers, prompt text, and "
            "Mermaid node IDs stay verbatim."
        )

    # Inventory summary for the prompt (the agent fills in full bodies in block 4).
    prompts_summary_lines = []
    for p in prompts_inventory:
        marker = "(DYNAMIC — describe assembly, do NOT synthesize body)" if p.get("is_dynamic") else ""
        prompts_summary_lines.append(
            f"  - name={p['name']}  source={p['source']}  is_dynamic={p.get('is_dynamic', False)} {marker}"
        )
        if not p.get("is_dynamic"):
            preview = p.get("body", "")[:200]
            prompts_summary_lines.append(f"    body preview: {preview!r}")
    prompts_summary = "\n".join(prompts_summary_lines) if prompts_summary_lines else "  (no static prompts extracted)"

    return "\n".join([
        f"You are documenting the AI flow `{flow_slug}` ({flow_name}).",
        f"Framework: {framework}.  Flow kind: {flow_kind}.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        "## Critical rules",
        "1. DO NOT invent prompt body text. For each static prompt extracted (see "
        "   inventory below), use its body VERBATIM inside the rendered block. "
        "   For DYNAMIC prompts, write a description of how it is assembled "
        "   (which source files contribute), and DO NOT synthesize a body.",
        "2. Every improvement must cite Evidence — wikilinks to [[modules/<slug>]]"
        " or `path:line`. Drop any Imp you cannot ground in Evidence.",
        "3. Strengths and weaknesses follow the v3.1 tight bullet shape: "
        "**Title (≤ 30 chars).** 1 line clarification (≤ 80 chars).",
        "",
        "## Output: produce 10 @generated blocks (JSON keys)",
        "",
        "### `ai-purpose`",
        "1 paragraph: when this AI runs, for whom, what it solves, what it outputs.",
        "",
        "### `graph-topology`",
        "ONE Mermaid `graph TD` showing nodes + edges + conditional routing. "
        "Each node label includes its source `path:line`.",
        "",
        "### `state-schema`",
        "If a State TypedDict / pydantic model exists (see "
        f"{state_module or '(none found)'}), copy its Python form into a "
        "```python``` block.  If dynamic / dict-only, describe the keys you "
        "see referenced.",
        "",
        "### `prompts`",
        "For EACH prompt in the inventory below, render ONE H3 + 4 metadata bullets +",
        "ONE collapsible callout wrapping the body, inside a per-prompt @generated sentinel.",
        "Format STRICTLY:",
        "  ```",
        "  ### <prompt name>",
        "  - **用途 / Purpose:** <1 句>",
        "  - **Source:** `<path:line-range>`",
        "  - **Model:** <model_hint or unknown>",
        "  - **Type:** static template  OR  dynamic — see assembly notes",
        "",
        "  <!-- @generated:start prompt-<slug> -->",
        "  > [!quote]- 完整 prompt",
        "  > ````",
        "  > <full body verbatim from inventory, OR dynamic description>",
        "  > ````",
        "  <!-- @generated:end prompt-<slug> -->",
        "  ```",
        "Where `prompt-<slug>` uses ascii-lowercase-hyphen of the prompt name.",
        "Do NOT modify the prompt body — copy from inventory below verbatim.",
        "",
        "### `llm-config`",
        "Markdown table: | Role | Model | Temperature | Fallback | Latency budget |",
        "Pull values from the inventory's `model_hint` + any visible `model=...` / "
        "`temperature=...` in graph files.  Mark unknowns as `?`.",
        "",
        "### `evaluation`",
        "Does owner have eval framework? metrics? tracing (LangSmith/Helicone/Phoenix)? "
        "If absent → `> [!warning] 無 eval framework — 評估完全靠人工 / 客訴.` " "(zh-TW)",
        "",
        "### `strengths`",
        "3-5 tight bullets each with Evidence.",
        "",
        "### `weaknesses`",
        "3-5 tight bullets each with concrete impact. Include AI-specific failure "
        "modes (hallucination / cost / latency / rate-limit / prompt-injection).",
        "",
        "### `improvements`",
        "2-4 Imps. Each MUST contain:",
        "  - **為什麼 / Why:** <≤ 1 sentence>",
        "  - **證據 / Evidence:** wikilink or `path:line`",
        "  - **Effort:** S | M | L | XL",
        "  - **未做的風險 / Risk if not done:** <≤ 1 sentence>",
        "  - **Confidence:** stated | high | medium | speculation",
        "",
        "### `dependencies`",
        "Wikilinks only:",
        "  - Host module:  `[[modules/<host>]]`",
        "  - External APIs:  Gemini / OpenAI / Anthropic / ...",
        "  - Framework:  LangGraph / LangChain (link to decision if exists)",
        "  - Observability:  LangSmith / Phoenix (if stated)",
        "",
        "Return strict JSON: {\"ai-purpose\": \"...\", \"graph-topology\": \"...\", "
        "\"state-schema\": \"...\", \"prompts\": \"...\", \"llm-config\": \"...\", "
        "\"evaluation\": \"...\", \"strengths\": \"...\", \"weaknesses\": \"...\", "
        "\"improvements\": \"...\", \"dependencies\": \"...\"}.",
        "",
        "## Prompts inventory (use these bodies verbatim)",
        prompts_summary,
        "",
        "## Graph files",
        ", ".join(graph_files) if graph_files else "(none detected)",
        "",
        "## Repomix-packed module context",
        repomix_packed[:50000],
    ])
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "build_ai_flow_prompt" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): build_ai_flow_prompt — strict JSON with prompts callout structure"
```

---

### Task 9: Per-prompt sentinel rendering helper

`compose_note(section="ai-flow", ...)` works for the outer block sentinels. But the prompts block content is a nested structure — multiple `### <name>` H3s each with their own `@generated:start prompt-<slug>` sentinel inside the outer `@generated:start prompts` sentinel.

We need a helper that takes a list of extracted prompts + their LLM-written metadata and emits the correctly-formatted prompts block body. The agent in command body assembles the LLM output JSON; this helper validates / formats the prompts portion.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_render_prompts_block_static_creates_collapsible_callout():
    from scripts.architect.sections import render_prompts_block
    inventory = [
        {
            "name": "intent_classifier",
            "source": "backend/engines/langgraph/prompts/intent.py:1-25",
            "body": "You are an intent classifier.\nUser: {user_message}\n",
            "is_dynamic": False,
            "model_hint": "gemini-flash",
        },
    ]
    annotations = {
        "intent_classifier": {"purpose": "把客戶訊息分類", "type_note": ""},
    }
    rendered = render_prompts_block(inventory, annotations, lang="zh-TW")
    # H3 + metadata + sentinel + callout
    assert "### intent_classifier" in rendered
    assert "**用途:**" in rendered or "**Purpose:**" in rendered
    assert "**Source:** `backend/engines/langgraph/prompts/intent.py:1-25`" in rendered
    assert "**Model:** gemini-flash" in rendered
    assert "**Type:** static template" in rendered
    assert "<!-- @generated:start prompt-intent-classifier -->" in rendered
    assert "<!-- @generated:end prompt-intent-classifier -->" in rendered
    assert "> [!quote]- 完整 prompt" in rendered
    assert "You are an intent classifier" in rendered
    assert "{user_message}" in rendered  # preserved


def test_render_prompts_block_dynamic_omits_collapsible_callout():
    from scripts.architect.sections import render_prompts_block
    inventory = [
        {
            "name": "build_system_prompt",
            "source": "agent.py:10",
            "body": "Assembled from _BASE + persona block at utils/persona.py:42 + tools list at runtime.",
            "is_dynamic": True,
            "model_hint": "gpt-4o",
        },
    ]
    annotations = {"build_system_prompt": {"purpose": "Runtime-assembled system prompt", "type_note": "Dynamic"}}
    rendered = render_prompts_block(inventory, annotations, lang="zh-TW")
    assert "### build_system_prompt" in rendered
    assert "**Type:** dynamic" in rendered
    # NO collapsible callout for dynamic
    assert "[!quote]" not in rendered
    # But still wrapped in sentinel for refresh
    assert "<!-- @generated:start prompt-build-system-prompt -->" in rendered
    # And the description IS visible (not hidden)
    assert "Assembled from _BASE" in rendered


def test_render_prompts_block_empty_inventory():
    from scripts.architect.sections import render_prompts_block
    rendered = render_prompts_block([], {}, lang="zh-TW")
    assert "(no static prompts extracted)" in rendered or "未偵測到 prompts" in rendered
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v -k "render_prompts_block" 2>&1 | tail -10`
Expected: FAIL — `render_prompts_block` not defined.

- [ ] **Step 3: Implement in `scripts/architect/sections.py`**

Append:

```python


def render_prompts_block(
    inventory: list[dict],
    annotations: dict[str, dict],
    lang: str = "en",
) -> str:
    """Render the `## Prompts` block body for an ai-flow note.

    Each prompt becomes:
      - H3 with the prompt name
      - 4 metadata bullets (Purpose, Source, Model, Type)
      - Per-prompt @generated sentinel wrapping a collapsible callout (static)
        OR an inline description (dynamic)

    Args:
        inventory: list of ExtractedPrompt-asdict (from scan-report.json's ai_flows[N].prompts).
        annotations: dict[prompt-name → {purpose: str, type_note: str}] — the agent's per-prompt copy.
        lang: 'en' | 'zh-TW'.
    """
    if not inventory:
        return "(未偵測到 prompts;若有動態組合 prompt,請手動補入 @user 區塊)" if lang == "zh-TW" else "(no static prompts extracted; add dynamic prompts manually in @user blocks)"

    labels = {
        "zh-TW": {"purpose": "用途", "type_static": "static template", "type_dynamic": "dynamic",
                  "callout": "> [!quote]- 完整 prompt"},
        "en": {"purpose": "Purpose", "type_static": "static template", "type_dynamic": "dynamic",
               "callout": "> [!quote]- Full prompt"},
    }[lang]

    out: list[str] = []
    for entry in inventory:
        name = entry["name"]
        slug = _slugify_prompt(name)
        purpose = annotations.get(name, {}).get("purpose", "(LLM 未補上 / not annotated)")
        type_value = labels["type_dynamic"] if entry.get("is_dynamic") else labels["type_static"]
        type_note = annotations.get(name, {}).get("type_note", "")
        if type_note:
            type_value = f"{type_value} — {type_note}"

        out.append(f"### {name}")
        out.append(f"- **{labels['purpose']}:** {purpose}")
        out.append(f"- **Source:** `{entry['source']}`")
        model = entry.get("model_hint") or "?"
        out.append(f"- **Model:** {model}")
        out.append(f"- **Type:** {type_value}")
        out.append("")
        out.append(f"<!-- @generated:start prompt-{slug} -->")
        if entry.get("is_dynamic"):
            # Dynamic prompts: inline description, no collapsible callout.
            out.append(entry["body"])
        else:
            out.append(labels["callout"])
            out.append("> ````")
            for line in entry["body"].splitlines():
                out.append(f"> {line}")
            out.append("> ````")
        out.append(f"<!-- @generated:end prompt-{slug} -->")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


_SLUG_NORM_RE = re.compile(r"[^a-z0-9-]+")


def _slugify_prompt(name: str) -> str:
    """Prompt name → ascii-lowercase-hyphen slug suitable for sentinel name."""
    s = name.lower()
    s = _SLUG_NORM_RE.sub("-", s).strip("-")
    return s or "unknown"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "render_prompts_block" 2>&1 | tail -10`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): render_prompts_block — per-prompt sentinel + collapsible callout"
```

---

## Phase F — Roadmap signal source

### Task 10: `candidates.py` reads `ai-flows/*.md`

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write failing test**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_v4_1_detect_candidates_reads_ai_flows_dir(tmp_path):
    """v4.1: detect_candidates also walks Architecture/ai-flows/*.md."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "ai-flows").mkdir(parents=True)
    (arch / "ai-flows" / "lang-ai-customer.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 加 prompt eval framework\n"
        "- **為什麼:** 完全靠人工\n"
        "- **證據:** `backend/engines/langgraph/`\n"
        "- **Effort:** L\n"
        "- **未做的風險:** prompt regression 無法 catch\n"
        "- **Confidence:** stated\n"
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert any("prompt eval framework" in t for t in titles), \
        f"ai-flow Imp not picked up by detect_candidates; got: {titles}"
    imp = next(c for c in cands if "prompt eval" in c.title)
    assert imp.effort == "L"
    assert imp.confidence == "stated"


def test_v4_1_detect_candidates_no_ai_flows_dir_still_works(tmp_path):
    """If ai-flows/ doesn't exist, detect_candidates falls through cleanly."""
    from scripts.roadmap.candidates import detect_candidates
    arch = tmp_path / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: backend Imp\n"
        "- **為什麼:** ...\n- **證據:** [[x]]\n- **Effort:** S\n"
        "- **未做的風險:** ...\n- **Confidence:** high\n"
    )
    cands = detect_candidates(tmp_path)
    assert any("backend Imp" in c.title for c in cands)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "v4_1" 2>&1 | tail -10`
Expected: FAIL — detect_candidates doesn't walk ai-flows/.

- [ ] **Step 3: Update `detect_candidates` in `scripts/roadmap/candidates.py`**

Find the `detect_candidates` function. Inside, where it builds `candidate_files`, add the ai-flows directory:

```python
def detect_candidates(project_root: Path) -> list[Candidate]:
    arch = project_root / "Architecture"
    if not arch.is_dir():
        return []
    out: list[Candidate] = []

    candidate_files = []
    if (arch / "overview.md").is_file():
        candidate_files.append(arch / "overview.md")
    if (arch / "decisions.md").is_file():
        candidate_files.append(arch / "decisions.md")
    if (arch / "modules").is_dir():
        candidate_files.extend(sorted((arch / "modules").glob("*.md")))
    # v4.1: AI flow improvements feed roadmap signal.
    if (arch / "ai-flows").is_dir():
        candidate_files.extend(sorted((arch / "ai-flows").glob("*.md")))

    for f in candidate_files:
        out.extend(_extract_improvements_from_file(f, arch))

    if (arch / "decisions.md").is_file():
        out.extend(_extract_from_file(arch / "decisions.md", _DECISIONS_SECTIONS))
        out.extend(_extract_known_limitations(arch / "decisions.md", arch))

    return _dedup(out)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "v4_1" 2>&1 | tail -10`
Expected: PASS (2 new tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "feat(roadmap): v4.1 — detect_candidates walks Architecture/ai-flows/"
```

---

## Phase G — Schema docs + command body

### Task 11: `references/ai-first-rules.md` — add `architecture-ai-flow` schema

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Append the new type schema after `architecture-function`**

Open `references/ai-first-rules.md`. After the `architecture-function` section (or at the end of the architecture types), insert:

```markdown
### `type: architecture-ai-flow`

Generated by `/obsidian-architect` v4.1. Lives at `Projects/<P>/Architecture/ai-flows/<flow-slug>.md`.

One note per AI subsystem detected — LangGraph chat engine, LangChain agent,
custom-pipeline batch worker, etc. The note captures graph topology, state
schema, full prompt text (collapsible), LLM config, evaluation gaps, and
design judgment (strengths / weaknesses / improvements).

Required frontmatter:
- `type: architecture-ai-flow`
- `date`, `project` (wikilink), `commit`, `last-scanned`
- `local-path` (vault repo absolute path) OR `repo` (URL string)
- `sources: [<paths>]` (architect roots scanned for this flow)
- `ai-framework: langgraph | langchain | custom-pipeline | autogen | semantic-kernel | crewai`
- `flow-kind: real-time-chat | batch-pipeline | rag | tool-use-agent | classification | extraction`
- `maturity: Alpha | Beta | GA`
- `confidence: stated | high | medium | speculation`
- `lang: zh-TW | en`
- `tags: [architecture, ai-flow, <framework>]`
- `ai-first: true`, `status: current | scan-failed | insufficient-signal`

Body sections (en / zh-TW), 10 sections:
- `## For future Claude` / `## 給未來 Claude`
- `## Purpose` / `## 流程目的`
- `## Graph topology` / `## 圖結構` — Mermaid `graph TD`
- `## State schema` / `## 狀態 schema` — TypedDict / pydantic model verbatim
- `## Prompts` / `## Prompts` — H3 per prompt, collapsible callout for static body,
  description for dynamic. Each wrapped in per-prompt `@generated:start prompt-<slug>` sentinel.
- `## LLM config` / `## LLM 設定` — markdown table (Role / Model / Temperature / Fallback / Latency)
- `## Evaluation & observability` / `## 評估與觀測`
- `## Design strengths` / `## 設計優點`
- `## Design weaknesses` / `## 設計缺點 / 風險`
- `## Improvement opportunities` / `## 改進機會` — strict 5-field Imp format
- `## Dependencies and consumers` / `## 相依與被誰使用` — wikilinks only
- `## Related` / `## 相關`

Per-prompt sentinel structure (inside the Prompts block):

```markdown
### <prompt-name>
- **用途 / Purpose:** <one sentence>
- **Source:** `<path:line-range>`
- **Model:** <model name or ?>
- **Type:** static template  OR  dynamic — <assembly description>

<!-- @generated:start prompt-<slug> -->
> [!quote]- 完整 prompt
> ````
> <full body verbatim>
> ````
<!-- @generated:end prompt-<slug> -->
```

Each prompt's `source-hash` is tracked in the lockfile `ai_flows.<slug>.prompts.<name>.source-hash`.
Refresh compares hashes; only changed prompts regenerate their per-prompt sentinel.
Dynamic prompts skip drift checking (source-hash="sha256:dynamic" sentinel constant).

The host module note(s) gain a sentinel-wrapped `**AI engine:** [[ai-flows/<slug>]]` line
showing which AI flow they host.
```

- [ ] **Step 2: Build adapters to verify ships cross-platform**

Run: `bash scripts/build.sh --platform claude-code`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(ai-first-rules): v4.1 architecture-ai-flow schema"
```

---

### Task 12: Module note ai-engine-link helper + tests

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_format_ai_engine_link_for_module():
    from scripts.architect.sections import format_ai_engine_link
    line = format_ai_engine_link(
        flow_slug="lang-ai-customer",
        framework="langgraph",
        flow_kind="real-time-chat",
        lang="zh-TW",
    )
    # Sentinel-wrapped, 1-line wikilink
    assert "<!-- @generated:start ai-engine-link -->" in line
    assert "<!-- @generated:end ai-engine-link -->" in line
    assert "[[ai-flows/lang-ai-customer]]" in line
    assert "langgraph" in line.lower()
    assert "real-time-chat" in line.lower()
    # User-facing label
    assert "**AI engine:**" in line


def test_format_ai_engine_link_en():
    from scripts.architect.sections import format_ai_engine_link
    line = format_ai_engine_link(
        flow_slug="qa-to-kb", framework="custom-pipeline",
        flow_kind="batch-pipeline", lang="en",
    )
    assert "[[ai-flows/qa-to-kb]]" in line
    assert "custom-pipeline" in line.lower()
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "ai_engine_link" 2>&1 | tail -10`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `format_ai_engine_link` to `scripts/architect/sections.py`**

```python


def format_ai_engine_link(
    *,
    flow_slug: str,
    framework: str,
    flow_kind: str,
    lang: str = "en",
) -> str:
    """Render a sentinel-wrapped 1-line `**AI engine:** [[ai-flows/<slug>]]` row.

    Inserted into the host module's note so the reader sees the module hosts
    an AI subsystem with one click to the deep judgment file.
    """
    label = "**AI engine:**"
    return "\n".join([
        "<!-- @generated:start ai-engine-link -->",
        f"{label} [[ai-flows/{flow_slug}]] ({framework}; {flow_kind})",
        "<!-- @generated:end ai-engine-link -->",
    ])
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v -k "ai_engine_link" 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): format_ai_engine_link helper for module-to-ai-flow wikilink"
```

---

### Task 13: Update `commands/obsidian-architect.md` for Phase 3.7 + flag + adapter rebuild

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Update flag documentation at top of file**

Find the existing flag list. Add:

```markdown
**v4.1-specific flags:**
- `--no-ai-flows` — even when scanner detects AI subsystem(s), do NOT produce
  `ai-flows/` notes. Use this if you don't want the AI flow layer for a project.
  Default OFF (AI flows ARE produced when detected).
```

- [ ] **Step 2: Add Phase 3.7 — AI Flow synthesis (between Phase 3 module synthesis and Phase 4 overview)**

Insert after Phase 3.5 (per-section synthesis):

```markdown
## Phase 3.7: AI Flow synthesis (v4.1)

For each AI flow in `scan_report["ai_flows"]` (skip if `--no-ai-flows`):

1. Run repomix on `flow["root_path"]`:
   ```bash
   repomix --include "<flow.root_path>/**" --style xml --compress --top-files-len 30 -o /tmp/repomix-<slug>.xml
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_flow_prompt
   prompt = build_ai_flow_prompt(
       flow_slug=flow["slug"],
       flow_name=flow["name"],
       framework=flow["framework"],
       flow_kind=flow["flow_kind"],
       prompts_inventory=flow["prompts"],
       state_module=flow.get("state_module"),
       graph_files=flow.get("graph_files", []),
       repomix_packed=repomix_text,
       output_lang=output_lang,
   )
   ```

3. Invoke LLM. Expect strict JSON with 10 block keys (ai-purpose / graph-topology /
   state-schema / prompts (annotations only) / llm-config / evaluation / strengths /
   weaknesses / improvements / dependencies).

4. **Prompts block reconstruction.** The LLM's `prompts` value is annotations only —
   it provides per-prompt `{purpose, type_note}` dict, but does NOT generate the body
   (bodies come from the inventory verbatim). Reconstruct via:
   ```python
   from scripts.architect.sections import render_prompts_block
   prompts_body = render_prompts_block(
       inventory=flow["prompts"],
       annotations=llm_output["prompts_annotations"],  # LLM returns this map
       lang=output_lang,
   )
   ```
   Then put `prompts_body` into `generated_blocks["prompts"]` for compose_note.

5. Compose: `compose_note(section="ai-flow", project=<P>, ...)`. Frontmatter
   needs `ai-framework`, `flow-kind`, `maturity` — these are emitted by appending
   custom fields after the standard set (compose_note doesn't know about them, so
   merge AFTER the call by string-replace the `tags: ` line):
   ```python
   note = compose_note(...)
   extra_fm = f"ai-framework: {flow['framework']}\nflow-kind: {flow['flow_kind']}\nmaturity: {llm_output.get('maturity', 'Beta')}\n"
   note = note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
   ```

6. Write to `Projects/<P>/Architecture/ai-flows/<flow-slug>.md` (create
   `ai-flows/` directory if needed).

7. Update lockfile `ai_flows[<slug>]`:
   - `signal-hash`, `lang`, `framework`, `last-generated`
   - Per-prompt sub-dict from inventory (source-hash from each ExtractedPrompt)

8. For each module hosting an AI flow, write a sentinel block via
   `format_ai_engine_link(...)`. Insert it into `modules/<host>.md` near the top
   (after `## 給未來 Claude` preamble). Idempotent — sentinel-aware update.

   To determine which module hosts an AI flow:
   - Match flow's `root_path` against each module's `paths`. First matching
     module hosts the flow.
   - Example: flow `lang-ai-customer` at `backend/engines/langgraph` matches
     module `backend` (paths `["backend/"]`).
   - For flows that don't match any module's `paths`, skip the link (the
     `ai-flows/` note still exists, just no module-side back-pointer).
```

- [ ] **Step 3: Update Phase 4 overview to reference ai-flows**

Find Phase 4. Update the `## Module map` and `## Drill-down entries` instructions:

```markdown
## Phase 4: Overview synthesis (v4 + v4.1)

In the Module map section, for each module that hosts an AI flow,
append ` + AI: [[ai-flows/<slug>]]` to its module line.

In the Drill-down entries section, if `ai-flows/` directory exists,
add a row:
- `## AI Flows:` `[[ai-flows/<slug-1>]]` | `[[ai-flows/<slug-2>]]` | ...
```

- [ ] **Step 4: Build adapters**

Run: `bash scripts/build.sh`
Expected: 4 dist trees regenerate cleanly.

- [ ] **Step 5: Verify**

Run: `wc -l dist/claude-code/commands/obsidian-architect.md`
Expected: substantially longer than before (Phase 3.7 added ~80 lines).

Run: `grep -c "ai-flow" dist/claude-code/commands/obsidian-architect.md`
Expected: ≥ 5 (v4.1 references present).

- [ ] **Step 6: Commit**

```bash
git add commands/obsidian-architect.md dist/
git commit -m "feat(architect): v4.1 command body — Phase 3.7 AI Flow synthesis + module ai-engine-link + --no-ai-flows flag"
```

---

## Phase H — Polish

### Task 14: CHANGELOG / SKILL.md / README.md

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: CHANGELOG.md** — under `## Unreleased`, add:

```markdown
### Added

- `/obsidian-architect` v4.1 — AI Flows layer. Scanner auto-detects LangGraph,
  LangChain, and custom-pipeline AI subsystems (threshold: ≥ 3 nodes) and
  produces `Architecture/ai-flows/<slug>.md` per flow. Each note has 10 body
  sections: Purpose / Graph topology / State schema / Prompts / LLM config /
  Evaluation / Strengths / Weaknesses / Improvements / Dependencies.
- Full prompt text embedded in vault via Obsidian collapsible callout
  (`> [!quote]-`) for AI-first self-contained context. Per-prompt sentinel
  with source-hash tracking in lockfile — only modified prompts regenerate
  their block on refresh.
- New `architecture-ai-flow` type in `references/ai-first-rules.md`.
- Host module notes gain a sentinel-wrapped `**AI engine:** [[ai-flows/<slug>]]`
  line when they host a detected flow.
- `--no-ai-flows` flag opts out (e.g. for projects where the AI layer should
  remain in module notes).

### Changed

- `/obsidian-roadmap` Phase 1 signal source extended: now also walks
  `Architecture/ai-flows/*.md` for `## Improvement opportunities` blocks.
- Lockfile schema (still v4, no version bump) gains an `ai_flows` field with
  per-flow + per-prompt source-hash tracking.

### Detection rules

- LangGraph: `langgraph` dep OR `from langgraph` import + `graph.py` + ≥ 3 nodes
- LangChain: `langchain` dep (without langgraph) + ≥ 3 nodes
- Custom-pipeline: `pipeline.py` + `nodes/` + prompts file + OpenAI/Anthropic/Gemini lib
- Projects without these signals get no `ai-flows/` directory (zero cost).
```

- [ ] **Step 2: SKILL.md** — update Layer 1 architect bullet:

```markdown
- `/obsidian-architect <repo-path>` — Generate a self-contained, top-down
  architecture report. 8 files: `overview.md` + 5 module judgment notes +
  `decisions.md` + `personas.md`. For projects with detected AI subsystems
  (LangGraph / LangChain / custom-pipeline), adds `ai-flows/<slug>.md` per
  AI flow with full prompts (collapsible callout), graph topology, state
  schema, LLM config, eval gaps, and design judgment. Feeds
  `/obsidian-roadmap` Phase 1 via cross-cutting + module + AI flow Imps.
```

- [ ] **Step 3: README.md** — update commands table description:

```markdown
| `/obsidian-architect` | Top-down architecture report. 8 files + per-AI-flow note for LangGraph/pipeline projects. v4.1. |
```

- [ ] **Step 4: Build adapters**

Run: `bash scripts/build.sh`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md SKILL.md README.md dist/
git commit -m "docs(skill+readme+changelog): v4.1 AI Flows layer announcement"
```

---

### Task 15: End-to-end smoke against langlive-line-oa

**Files:** none (read-only verification)

- [ ] **Step 1: Run full test suite**

Run: `uv run pytest tests/ -q 2>&1 | tail -5`
Expected: all green.

- [ ] **Step 2: Verify ai-flow detector against the real vault**

```bash
uv run python << 'PYEOF'
from pathlib import Path
from scripts.architect.ai_flow import detect_ai_flows

repo = Path("/Users/leric/Desktop/code/langlive-line-oa")
flows = detect_ai_flows(repo)
print(f"detected: {len(flows)} flow(s)")
for f in flows:
    print(f"  slug={f.slug}")
    print(f"    framework={f.framework}")
    print(f"    root_path={f.root_path}")
    print(f"    flow_kind={f.flow_kind}")
    print(f"    node_count={f.node_count}")
    print(f"    prompt_files={f.prompt_files[:3]}{'...' if len(f.prompt_files) > 3 else ''}")
    print(f"    state_module={f.state_module}")
    print(f"    llm_libs={f.llm_libs}")
PYEOF
```

Expected:
- 2 flows detected
- `framework=langgraph` for `backend/engines/langgraph` (or similar)
- `framework=custom-pipeline` for `modules/qa_to_kb`
- Both have non-empty `prompt_files`

- [ ] **Step 3: Verify prompt_extract against backend/engines/langgraph/prompts/**

```bash
uv run python << 'PYEOF'
from pathlib import Path
from scripts.architect.prompt_extract import extract_prompts

flow_root = Path("/Users/leric/Desktop/code/langlive-line-oa/backend/engines/langgraph")
prompts = extract_prompts(flow_root)
print(f"extracted: {len(prompts)} prompt(s)")
for p in prompts[:5]:
    print(f"  name={p.name!r}")
    print(f"    source={p.source}")
    print(f"    is_dynamic={p.is_dynamic}")
    print(f"    body_preview={p.body[:120]!r}")
    print(f"    source_hash={p.source_hash[:30]}...")
    print(f"    method={p.extraction_method}")
PYEOF
```

Expected: ≥ 1 prompt extracted; bodies are real text from `prompts/*.py`; each has a sha256 source_hash.

- [ ] **Step 4: Verify scan_report.ai_flows on the real vault**

```bash
REPO=/Users/leric/Desktop/code/langlive-line-oa
OUT=/tmp/architect-v4.1-smoke
rm -rf "$OUT"
uv run python scripts/architect_scan.py "$REPO" --out "$OUT" 2>&1 | tail -3
echo ""
uv run python -c "
import json
sr = json.load(open('$OUT/scan-report.json'))
ai = sr.get('ai_flows', [])
print(f'ai_flows count: {len(ai)}')
for f in ai:
    print(f\"  {f['slug']}: framework={f['framework']}, prompts={len(f.get('prompts', []))}\")
"
```

Expected output:
```
ai_flows count: 2
  <some-slug>: framework=langgraph, prompts=N1
  <some-slug>: framework=custom-pipeline, prompts=N2
```

- [ ] **Step 5: Synthetic compose_note + render_prompts_block round-trip**

```bash
uv run python << 'PYEOF'
from scripts.architect.sections import (
    compose_note, render_prompts_block, format_ai_engine_link,
)

# Simulate prompts inventory
inventory = [
    {"name": "intent_classifier", "source": "backend/engines/langgraph/prompts/intent.py:1-25",
     "body": "You are an intent classifier.\nUser: {user_message}\nReturn one of: PRODUCT, COMPLAINT, OTHER.",
     "is_dynamic": False, "model_hint": "gemini-flash"},
    {"name": "build_dynamic_prompt", "source": "agent.py:42",
     "body": "Assembled from _BASE + persona block at utils/persona.py:42",
     "is_dynamic": True, "model_hint": None},
]
annotations = {
    "intent_classifier": {"purpose": "把客戶訊息分類為 5 種 intent", "type_note": ""},
    "build_dynamic_prompt": {"purpose": "Runtime-assembled system prompt", "type_note": "Dynamic"},
}
prompts_body = render_prompts_block(inventory, annotations, lang="zh-TW")
print("=== render_prompts_block (zh-TW) ===")
print(prompts_body)
print()

print("=== format_ai_engine_link ===")
print(format_ai_engine_link(
    flow_slug="lang-ai-customer",
    framework="langgraph",
    flow_kind="real-time-chat",
    lang="zh-TW",
))
PYEOF
```

Expected output includes:
- Static prompt rendered with `> [!quote]-` collapsible callout containing full body
- Dynamic prompt rendered with `**Type:** dynamic — Dynamic` and inline description (no callout)
- Sentinel pairs `<!-- @generated:start prompt-intent-classifier -->` etc.
- AI engine link line with sentinel + wikilink

- [ ] **Step 6: Verify branch state**

Run: `git log --oneline -20`
Expected: ~15 commits since branch start (one per task in this plan).

Run: `uv run pytest tests/ -q && bash scripts/build.sh`
Expected: all green; 4 adapter dist trees regenerate cleanly.

- [ ] **Step 7: Final acceptance checklist (mirrors spec §13)**

Manual verification:

- [ ] `scripts/architect/ai_flow.py` exists with `detect_ai_flows` + `AIFlow` dataclass
- [ ] `scripts/architect/prompt_extract.py` exists with `extract_prompts` + 4 extractors (toml / module-constant / SYSTEM_PROMPT / langchain) + dynamic policy doc
- [ ] `scripts/architect/sections.py` has `_BLOCK_NAMES["ai-flow"]` (10-tuple), `_BLOCK_HEADINGS` with new entries, `build_ai_flow_prompt`, `render_prompts_block`, `format_ai_engine_link`
- [ ] `scripts/architect/scan.py` emits `ai_flows` key in scan_report
- [ ] `scripts/architect/lockfile.py` `Lockfile.ai_flows` field + `ai_flow_prompt_changed` helper
- [ ] `scripts/roadmap/candidates.py` walks `ai-flows/*.md`
- [ ] `references/ai-first-rules.md` documents `architecture-ai-flow` schema with per-prompt sentinel structure
- [ ] `commands/obsidian-architect.md` has Phase 3.7 + `--no-ai-flows` flag + module ai-engine-link step
- [ ] CHANGELOG / SKILL.md / README.md updated
- [ ] All adapter dist trees rebuilt
- [ ] Real langlive-line-oa scan detects 2 AI flows (langgraph + custom-pipeline)
- [ ] Synthetic round-trip emits correct callout structure + sentinels
- [ ] Tests all green
