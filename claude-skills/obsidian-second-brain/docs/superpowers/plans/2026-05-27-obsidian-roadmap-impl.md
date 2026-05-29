# /obsidian-roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 實作 `/obsidian-roadmap <project>` 命令 — 把 Architecture 訊號 + Research 累積融合成 Project Roadmap.md 加 Tasks/T-NNN-*.md 加 board cards。

**Architecture:** 5-phase pipeline (Gap detection / Research linking / Theme synthesis / Batch review / Materialize)。Python helpers 處理 deterministic phase 跟 prompt building;LLM 由 agent (Claude in command body) 在 Phase 2c/3 跑。Phase 4 用 markdown paste-back review。Phase 5 純 deterministic write,讀 Phase 3 已 fully-spec 的 task JSON。`_roadmap.lock.json` 追蹤 theme + task materialization,re-run idempotent。

**Tech Stack:** Python 3.10+, pytest, dataclass, pyyaml, 既有 `scripts/architect/lang.py` heading map + `scripts/architect/sentinels.py`。慣例跟 architect 同 (pure functions + 整合在 `roadmap_synth.py` CLI orchestrator)。

**Spec:** `docs/superpowers/specs/2026-05-27-obsidian-roadmap-design.md`

**Suggested branch:** `feat/obsidian-roadmap`

---

## Task layout

15 個任務分 7 個 phase。Phase A 是 foundation;Phase B-E 的 helper 互相獨立可平行;Phase F-G 收斂。

| Phase | 任務 | 範圍 |
|---|---|---|
| A. Foundation | 1-2 | 加 lang heading + lockfile v1 |
| B. Candidates | 3 | Phase 1 scanner — 從 architect 檔抽 gap |
| C. Research matching | 4-5 | Phase 2 — keyword prefilter + relevance prompt builder |
| D. Renderers | 6-8 | Phase 5 — Roadmap.md / task / board card composer |
| E. Parser & prompts | 9-10 | Phase 4 review parser + Phase 3 synthesis prompt |
| F. CLI orchestrator | 11 | `roadmap_synth.py` — 串 Phase 1+2a 為 deterministic CLI |
| G. Schema + command + adapter | 12-13 | ai-first-rules + commands/obsidian-roadmap.md + adapter rebuild |
| H. Polish | 14-15 | CHANGELOG / SKILL.md / README / 端到端 smoke |

---

## Phase A — Foundation

### Task 1: 加 heading map 條目

**Files:**
- Modify: `scripts/architect/lang.py`
- Modify: `tests/architect/test_lang.py`

- [ ] **Step 1: Write failing test for new heading keys**

Append to `tests/architect/test_lang.py`:

```python
def test_heading_map_includes_roadmap_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Themes": "## 主題",
        "## Stale themes": "## 過時主題",
        "## Synthesis summary": "## 本次合成摘要",
        "## Acceptance criteria": "## 接受條件",
        "## Evidence": "## 佐證",
        "## Why": "## 為什麼",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_roadmap_keys -v`
Expected: FAIL with `AssertionError: missing heading key '## Themes'`.

- [ ] **Step 3: Add entries to HEADING_MAP**

Open `scripts/architect/lang.py`. Find the HEADING_MAP dict. Inside the dict (after the existing `# function notes.` block, before the closing `}`), add:

```python
    # roadmap (project-level, by /obsidian-roadmap)
    "## Themes": {"en": "## Themes", "zh-TW": "## 主題"},
    "## Stale themes": {"en": "## Stale themes", "zh-TW": "## 過時主題"},
    "## Synthesis summary": {"en": "## Synthesis summary", "zh-TW": "## 本次合成摘要"},
    "## Acceptance criteria": {"en": "## Acceptance criteria", "zh-TW": "## 接受條件"},
    "## Evidence": {"en": "## Evidence", "zh-TW": "## 佐證"},
    "## Why": {"en": "## Why", "zh-TW": "## 為什麼"},
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_lang.py::test_heading_map_includes_roadmap_keys -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lang.py tests/architect/test_lang.py
git commit -m "feat(roadmap): add heading map entries for Themes/Acceptance/Evidence/etc."
```

---

### Task 2: roadmap lockfile module

**Files:**
- Create: `scripts/roadmap/__init__.py`
- Create: `scripts/roadmap/lockfile.py`
- Create: `tests/roadmap/__init__.py`
- Create: `tests/roadmap/conftest.py`
- Create: `tests/roadmap/test_lockfile.py`

- [ ] **Step 1: Create package markers**

```bash
mkdir -p scripts/roadmap tests/roadmap
touch scripts/roadmap/__init__.py tests/roadmap/__init__.py
```

Create `tests/roadmap/conftest.py`:

```python
"""Shared fixtures for roadmap tests."""
```

- [ ] **Step 2: Write failing tests**

Create `tests/roadmap/test_lockfile.py`:

```python
from pathlib import Path

from scripts.roadmap.lockfile import (
    RoadmapLockfile,
    ThemeEntry,
    TaskEntry,
    hash_signal,
    load_lockfile,
    write_lockfile,
)


def test_hash_signal_is_deterministic():
    sig = {"foo": "bar", "evidence": ["a", "b"]}
    assert hash_signal(sig) == hash_signal(sig)


def test_hash_signal_independent_of_dict_order():
    a = hash_signal({"x": 1, "y": 2})
    b = hash_signal({"y": 2, "x": 1})
    assert a == b


def test_lockfile_round_trip(tmp_path: Path):
    lock = RoadmapLockfile(
        schema_version=1,
        last_synthesis="2026-05-27T19:00:00Z",
        last_architect_commit="344e321",
        themes={
            "ai-engine-pluggability": ThemeEntry(
                title="AI 引擎可插拔化",
                first_materialized="2026-05-27T19:00:00Z",
                last_refreshed="2026-05-27T19:00:00Z",
                signal_source_hash="sha256:abc",
                tasks=["T-001", "T-002"],
                status="active",
            ),
        },
        tasks={
            "T-001": TaskEntry(theme="ai-engine-pluggability", created="2026-05-27T19:00:00Z", slug="add-adapter"),
        },
        next_task_id=3,
    )
    target = tmp_path / "_roadmap.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.themes["ai-engine-pluggability"].title == "AI 引擎可插拔化"
    assert loaded.tasks["T-001"].slug == "add-adapter"
    assert loaded.next_task_id == 3


def test_load_missing_returns_none(tmp_path: Path):
    assert load_lockfile(tmp_path / "nope.json") is None


def test_theme_status_options():
    e = ThemeEntry(title="x", first_materialized="t", last_refreshed="t",
                   signal_source_hash="h", tasks=[], status="active")
    assert e.status in ("active", "stale", "needs-refresh")


def test_allocate_task_id(tmp_path: Path):
    """Lockfile helper that returns the next task ID and increments the counter."""
    from scripts.roadmap.lockfile import allocate_task_id
    lock = RoadmapLockfile(schema_version=1, last_synthesis="", last_architect_commit="",
                            themes={}, tasks={}, next_task_id=7)
    tid = allocate_task_id(lock)
    assert tid == "T-007"  # zero-padded to 3 digits
    assert lock.next_task_id == 8

    tid2 = allocate_task_id(lock)
    assert tid2 == "T-008"
    assert lock.next_task_id == 9
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_lockfile.py -v`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement `scripts/roadmap/lockfile.py`**

```python
"""Lockfile for /obsidian-roadmap.

Tracks per-project theme + task materialization across re-runs so refresh
can decide SKIP / REGENERATE / mark STALE without re-asking the user.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

CURRENT_SCHEMA = 1


@dataclass
class ThemeEntry:
    title: str
    first_materialized: str
    last_refreshed: str
    signal_source_hash: str
    tasks: list[str]              # list of task IDs (e.g. ["T-001", "T-002"])
    status: str                   # active | stale | needs-refresh


@dataclass
class TaskEntry:
    theme: str                    # theme slug
    created: str                  # ISO timestamp
    slug: str                     # slug used in filename (without "T-NNN-" prefix)


@dataclass
class RoadmapLockfile:
    schema_version: int
    last_synthesis: str           # ISO timestamp of last successful run
    last_architect_commit: str    # commit SHA of Architecture/ at last run
    themes: dict[str, ThemeEntry] = field(default_factory=dict)
    tasks: dict[str, TaskEntry] = field(default_factory=dict)
    next_task_id: int = 1


def hash_signal(signal: dict) -> str:
    """Stable SHA-256 hash of a JSON-serializable signal dict."""
    canonical = json.dumps(signal, sort_keys=True, default=str).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def load_lockfile(path: Path) -> RoadmapLockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    return RoadmapLockfile(
        schema_version=data.get("schema_version", CURRENT_SCHEMA),
        last_synthesis=data.get("last_synthesis", ""),
        last_architect_commit=data.get("last_architect_commit", ""),
        themes={k: ThemeEntry(**v) for k, v in data.get("themes", {}).items()},
        tasks={k: TaskEntry(**v) for k, v in data.get("tasks", {}).items()},
        next_task_id=data.get("next_task_id", 1),
    )


def write_lockfile(lock: RoadmapLockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": CURRENT_SCHEMA,
        "last_synthesis": lock.last_synthesis,
        "last_architect_commit": lock.last_architect_commit,
        "themes": {k: asdict(v) for k, v in lock.themes.items()},
        "tasks": {k: asdict(v) for k, v in lock.tasks.items()},
        "next_task_id": lock.next_task_id,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False))


def allocate_task_id(lock: RoadmapLockfile) -> str:
    """Return next task ID 'T-NNN' (3-digit zero-padded) and increment the counter."""
    tid = f"T-{lock.next_task_id:03d}"
    lock.next_task_id += 1
    return tid
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/roadmap/test_lockfile.py -v`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add scripts/roadmap/__init__.py scripts/roadmap/lockfile.py tests/roadmap/__init__.py tests/roadmap/conftest.py tests/roadmap/test_lockfile.py
git commit -m "feat(roadmap): add lockfile module with ThemeEntry/TaskEntry/allocate_task_id"
```

---

## Phase B — Phase-1 candidates

### Task 3: Gap candidate detector

**Files:**
- Create: `scripts/roadmap/candidates.py`
- Create: `tests/roadmap/test_candidates.py`
- Create: `tests/roadmap/fixtures/project-a/Architecture/future.md`
- Create: `tests/roadmap/fixtures/project-a/Architecture/decisions.md`
- Create: `tests/roadmap/fixtures/project-a/Architecture/roadmap.md`

- [ ] **Step 1: Create fixture: project-a with realistic Architecture files**

Create `tests/roadmap/fixtures/project-a/Architecture/future.md`:

```markdown
---
type: architecture-future
date: 2026-05-27
lang: zh-TW
confidence: speculation
status: current
---

## 給未來 Claude
Project A 的 gap 分析。

## 已知限制

- 沒有 SSO 整合 (stated: AGENTS.md)
- 後台只支援單一語言 (stated)

## 落差分析

- README 提到 streaming API,但 api-surface 沒對應 endpoint
- README 提到 plugin system,但 exports 中找不到 plugin_register

## 期望中的想法

- 把 AI 引擎抽象成 pluggable adapter (inferred from AGENTS.md)
- 加 webhook signature verification (suggested)
```

Create `tests/roadmap/fixtures/project-a/Architecture/decisions.md`:

```markdown
---
type: architecture-decisions
date: 2026-05-27
lang: zh-TW
status: current
---

## 給未來 Claude
Project A 的決定索引。

## 建議升級為 ADR

1. **為什麼 Redis Cluster 而不是 PostgreSQL 主要資料層** — AGENTS.md 暗示但未詳述。
2. **事件分流標準** — 為什麼有些走 stream,有些直接寫 Redis。
3. **TanStack Query 遷移策略** — Phase 3 分批遷移的決定。
```

Create `tests/roadmap/fixtures/project-a/Architecture/roadmap.md`:

```markdown
---
type: architecture-roadmap
date: 2026-05-27
lang: zh-TW
status: current
---

## 給未來 Claude
TODO clusters from project A.

## TODO 群組

### backend
- `backend/auth.py:42` (TODO) implement OAuth flow
- `backend/auth.py:88` (TODO) implement OAuth flow
- `backend/auth.py:120` (TODO) implement OAuth flow

### frontend
- `frontend/src/login.tsx:55` (TODO) hook into OAuth callback
- `frontend/src/login.tsx:71` (TODO) hook into OAuth callback
```

- [ ] **Step 2: Write failing tests**

Create `tests/roadmap/test_candidates.py`:

```python
from pathlib import Path

from scripts.roadmap.candidates import Candidate, detect_candidates

FIXTURE = Path(__file__).parent / "fixtures" / "project-a"


def test_detects_future_md_buckets():
    cands = detect_candidates(FIXTURE)
    kinds = {c.kind for c in cands}
    assert "limitation" in kinds
    assert "gap" in kinds
    assert "aspiration" in kinds


def test_detects_promote_to_adr():
    cands = detect_candidates(FIXTURE)
    promotes = [c for c in cands if c.kind == "promote-to-adr"]
    assert len(promotes) == 3
    assert any("Redis Cluster" in c.raw_text for c in promotes)


def test_detects_todo_clusters_only_when_frequency_ge_2():
    cands = detect_candidates(FIXTURE)
    clusters = [c for c in cands if c.kind == "todo-cluster"]
    # OAuth-flow TODOs appear 3 times in backend, 2 times in frontend -> 2 clusters
    assert len(clusters) >= 1
    assert any("OAuth" in c.raw_text for c in clusters)


def test_candidate_carries_source_wikilink():
    cands = detect_candidates(FIXTURE)
    for c in cands:
        if c.kind == "gap":
            assert c.source_wikilink.startswith("[[Architecture/future")
            return
    raise AssertionError("no gap candidate found")


def test_dedup_by_normalized_title():
    # Two candidates with same text after lowercasing + stripping punct should dedup
    from scripts.roadmap.candidates import Candidate, _dedup
    cands = [
        Candidate(title="加 SSO 整合", source_wikilink="[[a]]", source_line=1,
                  kind="gap", raw_text="加 SSO 整合"),
        Candidate(title="加 sso 整合", source_wikilink="[[b]]", source_line=2,
                  kind="aspiration", raw_text="加 sso 整合"),
    ]
    result = _dedup(cands)
    assert len(result) == 1


def test_missing_architecture_dir_returns_empty(tmp_path: Path):
    assert detect_candidates(tmp_path) == []


def test_candidate_has_stable_id():
    """Candidate id should be deterministic from kind + normalized title."""
    cands = detect_candidates(FIXTURE)
    ids = [c.id for c in cands]
    assert len(ids) == len(set(ids))  # all unique
    # Re-run yields same IDs
    cands2 = detect_candidates(FIXTURE)
    assert [c.id for c in cands2] == ids
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement `scripts/roadmap/candidates.py`**

```python
"""Phase 1 — gap candidate detection from Architecture/ files.

Reads future.md / decisions.md / roadmap.md, extracts bullets from known
sections, normalizes + deduplicates, returns ordered Candidate list.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Candidate:
    id: str                       # deterministic, derived from kind + normalized title
    title: str                    # display text
    source_wikilink: str          # `[[Architecture/future#期望中的想法]]` style
    source_line: int              # 1-indexed line in source file
    kind: str                     # gap | limitation | aspiration | promote-to-adr | todo-cluster
    raw_text: str                 # original bullet text


# Section heading -> (kind, source-file)
_FUTURE_SECTIONS = {
    "## 已知限制": "limitation",
    "## Known limitations": "limitation",
    "## 落差分析": "gap",
    "## Gap analysis": "gap",
    "## 期望中的想法": "aspiration",
    "## Aspirational ideas": "aspiration",
}

_DECISIONS_SECTIONS = {
    "## 建議升級為 ADR": "promote-to-adr",
    "## Promote to ADR": "promote-to-adr",
}

_ROADMAP_SECTIONS = {
    "## TODO 群組": "todo-cluster",
    "## TODO clusters": "todo-cluster",
}

_BULLET_RE = re.compile(r"^[-*]\s+(.+)$", re.MULTILINE)
_NUMBERED_RE = re.compile(r"^\d+\.\s+(.+)$", re.MULTILINE)


def detect_candidates(project_root: Path) -> list[Candidate]:
    """Walk Architecture/ subfiles, extract candidates, dedup, return."""
    arch = project_root / "Architecture"
    if not arch.is_dir():
        return []
    out: list[Candidate] = []
    out.extend(_extract_from_file(arch / "future.md", _FUTURE_SECTIONS))
    out.extend(_extract_from_file(arch / "decisions.md", _DECISIONS_SECTIONS))
    out.extend(_extract_from_file(arch / "roadmap.md", _ROADMAP_SECTIONS, freq_dedup=True))
    return _dedup(out)


def _extract_from_file(path: Path, section_to_kind: dict[str, str], freq_dedup: bool = False) -> list[Candidate]:
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    out: list[Candidate] = []
    file_stem = path.stem  # e.g. "future"
    arch_rel = f"Architecture/{file_stem}"
    for heading_str, kind in section_to_kind.items():
        body, body_start_line = _section_body(text, heading_str)
        if body is None:
            continue
        anchor = heading_str.lstrip("# ").strip()
        # For todo-cluster, count frequency by full bullet text.
        bullets = _BULLET_RE.findall(body) + _NUMBERED_RE.findall(body)
        freq: dict[str, int] = {}
        for b in bullets:
            freq[b] = freq.get(b, 0) + 1
        for raw, count in freq.items():
            if freq_dedup and count < 2:
                continue
            title = _normalize_title(raw)
            cand_id = _make_id(kind, title)
            # Approximate source_line as body_start_line; precise per-bullet line tracking is overkill.
            out.append(Candidate(
                id=cand_id,
                title=title or raw,
                source_wikilink=f"[[{arch_rel}#{anchor}]]",
                source_line=body_start_line,
                kind=kind,
                raw_text=raw.strip(),
            ))
    return out


def _section_body(text: str, heading: str) -> tuple[str | None, int]:
    """Return (body, 1-indexed start line) for the section whose H2 matches `heading`."""
    pattern = re.compile(rf"^{re.escape(heading)}\s*$", re.MULTILINE)
    m = pattern.search(text)
    if not m:
        return None, 0
    start = m.end()
    start_line = text[: m.start()].count("\n") + 1
    # Body until next H2 or EOF.
    rest = text[start:]
    next_h2 = re.search(r"\n##\s+", rest)
    end = start + (next_h2.start() if next_h2 else len(rest))
    return text[start:end].strip(), start_line


_PUNCT_RE = re.compile(r"[「」、,。!?:;]+")
_EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\U00002600-\U000027BF]+")


def _normalize_title(raw: str) -> str:
    s = raw.strip()
    s = _EMOJI_RE.sub("", s)
    s = _PUNCT_RE.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    # Strip leading inline-markdown like **bold** wrapper.
    s = re.sub(r"^\**\s*", "", s).rstrip("*").strip()
    # Cap length to keep IDs short.
    return s[:120]


def _make_id(kind: str, normalized_title: str) -> str:
    h = hashlib.sha1(f"{kind}::{normalized_title}".encode("utf-8")).hexdigest()[:10]
    return f"{kind[:3]}-{h}"


def _dedup(cands: list[Candidate]) -> list[Candidate]:
    """Drop later occurrences of candidates with the same normalized title."""
    seen: set[str] = set()
    out: list[Candidate] = []
    for c in cands:
        key = c.title.strip().lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(c)
    return out
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py tests/roadmap/fixtures/
git commit -m "feat(roadmap): Phase-1 gap candidate detector"
```

---

## Phase C — Research matching

### Task 4: Keyword prefilter (Phase 2b)

**Files:**
- Create: `scripts/roadmap/research_match.py`
- Create: `tests/roadmap/test_research_match.py`

- [ ] **Step 1: Write failing tests**

Create `tests/roadmap/test_research_match.py`:

```python
import time
from pathlib import Path

from scripts.roadmap.research_match import (
    ResearchMatch,
    keyword_prefilter,
    build_relevance_prompt,
)


def _make_research(path: Path, topic: str, tags: list[str], body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    fm = "---\n" + f"topic: {topic}\n" + f"tags: {tags}\n" + "type: research-deep\n" + "---\n"
    path.write_text(fm + "\n## Summary\n\n" + body)


def test_finds_match_in_project_research(tmp_path: Path):
    proj_research = tmp_path / "Projects" / "p" / "Research"
    _make_research(proj_research / "2026-05-15-oauth.md", "OAuth flow", ["oauth"], "OAuth 是 ...")
    matches = keyword_prefilter(
        candidate_id="gap-1",
        keywords=["OAuth", "SSO"],
        vault_root=tmp_path,
        project_research_dir=proj_research,
        vault_research_max_age_days=30,
    )
    assert any(m.path.endswith("2026-05-15-oauth.md") for m in matches)


def test_finds_match_in_vault_research_within_window(tmp_path: Path):
    vault_research = tmp_path / "Research" / "Deep"
    _make_research(vault_research / "2026-05-20-ai-engines.md", "AI Engines", ["ai", "engine"], "比較 LangGraph vs ...")
    matches = keyword_prefilter(
        candidate_id="gap-2",
        keywords=["LangGraph", "engine"],
        vault_root=tmp_path,
        project_research_dir=tmp_path / "Projects" / "p" / "Research",
        vault_research_max_age_days=30,
    )
    assert any(m.path.endswith("2026-05-20-ai-engines.md") for m in matches)


def test_skips_vault_research_older_than_window(tmp_path: Path):
    vault_research = tmp_path / "Research" / "Deep"
    _make_research(vault_research / "2025-01-01-old.md", "Old", ["old"], "older than window")
    # Forcibly age the file
    old = (vault_research / "2025-01-01-old.md")
    old_ts = time.time() - 60 * 24 * 3600  # 60 days ago
    import os
    os.utime(old, (old_ts, old_ts))
    matches = keyword_prefilter(
        candidate_id="gap-3",
        keywords=["old"],
        vault_root=tmp_path,
        project_research_dir=tmp_path / "Projects" / "p" / "Research",
        vault_research_max_age_days=30,
    )
    assert not any(m.path.endswith("old.md") for m in matches)


def test_caps_matches_per_candidate(tmp_path: Path):
    proj_research = tmp_path / "Projects" / "p" / "Research"
    for i in range(20):
        _make_research(proj_research / f"2026-05-{i:02d}-streaming.md", "streaming",
                       ["streaming"], "streaming body")
    matches = keyword_prefilter(
        candidate_id="gap-4",
        keywords=["streaming"],
        vault_root=tmp_path,
        project_research_dir=proj_research,
        vault_research_max_age_days=30,
        max_matches=10,
    )
    assert len(matches) <= 10


def test_build_relevance_prompt_lists_candidates_and_matches():
    matches_by_cand = {
        "gap-1": [
            ResearchMatch(candidate_id="gap-1", path="Research/Deep/2026-05-15-oauth.md",
                          summary_excerpt="OAuth is a delegated authorization protocol..."),
        ],
    }
    candidates_text = {"gap-1": "Add SSO integration"}
    prompt = build_relevance_prompt(matches_by_cand, candidates_text, output_lang="zh-TW")
    assert "gap-1" in prompt
    assert "Add SSO integration" in prompt
    assert "OAuth is a delegated" in prompt
    # zh-TW prompt should mention 繁體中文 OR be explicit about output language
    assert "繁體中文" in prompt or "zh-TW" in prompt or "Traditional Chinese" in prompt
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_research_match.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/roadmap/research_match.py`**

```python
"""Phase 2 — research linking helpers.

Provides:
- keyword_prefilter() — deterministic grep over project-scoped + recent vault-wide Research/
- build_relevance_prompt() — builds the LLM prompt for Phase 2c (agent runs the LLM)

The LLM relevance call itself happens in the slash command body (agent).
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from pathlib import Path

# Cap so a single candidate can't dominate the downstream LLM context window.
_DEFAULT_MAX_MATCHES = 10
_SUMMARY_EXCERPT_CHARS = 600
_TEXT_EXTENSIONS = {".md"}


@dataclass(frozen=True)
class ResearchMatch:
    candidate_id: str
    path: str               # vault-relative posix path
    summary_excerpt: str    # first ~600 chars of `## Summary` block or topic, for the LLM


def keyword_prefilter(
    *,
    candidate_id: str,
    keywords: list[str],
    vault_root: Path,
    project_research_dir: Path,
    vault_research_max_age_days: int = 30,
    max_matches: int = _DEFAULT_MAX_MATCHES,
) -> list[ResearchMatch]:
    """Return research notes whose topic / tags / body matches any keyword.

    Project-scoped Research/ is unfiltered by age; vault-wide Research/{Web,Deep}
    is restricted to recent files (mtime within the window).
    """
    vault_root = vault_root.resolve()
    project_research_dir = project_research_dir.resolve() if project_research_dir.exists() else None
    out: list[ResearchMatch] = []
    seen: set[Path] = set()
    cutoff = time.time() - vault_research_max_age_days * 24 * 3600

    # Project scope — no age filter.
    if project_research_dir and project_research_dir.is_dir():
        for f in project_research_dir.rglob("*.md"):
            if f in seen:
                continue
            match = _try_match(candidate_id, f, keywords, vault_root)
            if match:
                seen.add(f)
                out.append(match)
                if len(out) >= max_matches:
                    return out

    # Vault-wide scope — age-filtered.
    for sub in ("Research/Web", "Research/Deep"):
        d = vault_root / sub
        if not d.is_dir():
            continue
        for f in d.rglob("*.md"):
            if f in seen:
                continue
            try:
                if f.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            match = _try_match(candidate_id, f, keywords, vault_root)
            if match:
                seen.add(f)
                out.append(match)
                if len(out) >= max_matches:
                    return out
    return out


def _try_match(candidate_id: str, file: Path, keywords: list[str], vault_root: Path) -> ResearchMatch | None:
    if file.suffix not in _TEXT_EXTENSIONS:
        return None
    try:
        text = file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    haystack = text.lower()
    for kw in keywords:
        if kw.lower() in haystack:
            try:
                rel = file.relative_to(vault_root).as_posix()
            except ValueError:
                rel = str(file)
            return ResearchMatch(
                candidate_id=candidate_id,
                path=rel,
                summary_excerpt=_extract_summary_excerpt(text),
            )
    return None


_SUMMARY_RE = re.compile(r"^##\s+Summary\s*$([\s\S]*?)(?=^##\s|\Z)", re.MULTILINE)


def _extract_summary_excerpt(text: str) -> str:
    """Return the first ~600 chars of `## Summary` body, or topic frontmatter as fallback."""
    m = _SUMMARY_RE.search(text)
    if m:
        body = m.group(1).strip()
        return body[:_SUMMARY_EXCERPT_CHARS]
    # Fallback: pull `topic:` from frontmatter.
    fm_match = re.search(r"^topic:\s*[\"']?([^\"\'\n]+)", text, re.MULTILINE)
    return fm_match.group(1).strip() if fm_match else text[:_SUMMARY_EXCERPT_CHARS]


def build_relevance_prompt(
    matches_by_cand: dict[str, list[ResearchMatch]],
    candidates_text: dict[str, str],
    output_lang: str,
) -> str:
    """Build LLM prompt for Phase 2c (relevance check).

    The agent invokes the LLM with this prompt and expects JSON back:
    {candidate-id: [relevant-research-path, ...]}
    """
    lang_directive = (
        "輸出 JSON。判斷時思考用繁體中文 (zh-TW)。"
        if output_lang == "zh-TW"
        else "Output JSON. Reason in English."
    )
    lines = [
        "You are filtering research notes for relevance to roadmap candidates.",
        lang_directive,
        "",
        "For each candidate id below, return a JSON list of paths to research "
        "notes that are GENUINELY relevant (not just keyword-matching). Drop "
        "notes whose summary clearly addresses a different problem.",
        "",
        "Return strict JSON: {\"<candidate-id>\": [\"<path>\", ...], ...}",
        "",
        "Candidates:",
    ]
    for cid, text in candidates_text.items():
        lines.append(f"- {cid}: {text}")
    lines.append("")
    lines.append("Research matches per candidate:")
    for cid, matches in matches_by_cand.items():
        lines.append(f"### {cid}")
        for m in matches:
            lines.append(f"- path: {m.path}")
            lines.append(f"  summary: {m.summary_excerpt[:400]}")
    return "\n".join(lines)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_research_match.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/research_match.py tests/roadmap/test_research_match.py
git commit -m "feat(roadmap): keyword prefilter + LLM relevance prompt builder"
```

---

### Task 5: Keyword extraction prompt builder

**Files:**
- Modify: `scripts/roadmap/research_match.py`
- Modify: `tests/roadmap/test_research_match.py`

- [ ] **Step 1: Write failing test for keyword-extraction prompt**

Append to `tests/roadmap/test_research_match.py`:

```python
def test_build_keyword_extraction_prompt_lists_candidates_with_text():
    from scripts.roadmap.research_match import build_keyword_extraction_prompt
    candidates = {
        "gap-1": "加 SSO 整合 (stated: AGENTS.md)",
        "asp-2": "把 AI 引擎抽象成 pluggable adapter",
    }
    prompt = build_keyword_extraction_prompt(candidates, output_lang="zh-TW")
    assert "gap-1" in prompt
    assert "加 SSO 整合" in prompt
    assert "asp-2" in prompt
    # Prompt must explicitly ask for JSON output
    assert "JSON" in prompt
    # Must ask for 3-5 keywords per candidate
    assert "3" in prompt and "5" in prompt
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/roadmap/test_research_match.py::test_build_keyword_extraction_prompt_lists_candidates_with_text -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append to `scripts/roadmap/research_match.py`**

```python


def build_keyword_extraction_prompt(candidates: dict[str, str], output_lang: str) -> str:
    """Build LLM prompt for Phase 2a (keyword extraction).

    Agent invokes LLM with this prompt; expects JSON back: {cand-id: [kw, ...]}.
    """
    lang_directive = (
        "Output keywords in whatever language matches the candidate text "
        "(English code identifiers stay English; Chinese terms stay Chinese). "
        "Avoid stop words. Each keyword should be 1-3 tokens."
    )
    lines = [
        "Extract 3-5 short keywords per roadmap candidate, useful for searching "
        "across research notes.",
        lang_directive,
        "",
        "Return strict JSON: {\"<candidate-id>\": [\"<keyword>\", ...], ...}",
        "",
        "Candidates:",
    ]
    for cid, text in candidates.items():
        lines.append(f"- {cid}: {text}")
    return "\n".join(lines)
```

- [ ] **Step 4: Run test**

Run: `uv run pytest tests/roadmap/test_research_match.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/research_match.py tests/roadmap/test_research_match.py
git commit -m "feat(roadmap): keyword extraction prompt builder for Phase 2a"
```

---

## Phase D — Renderers (Phase-5 composers)

### Task 6: Roadmap.md composer

**Files:**
- Create: `scripts/roadmap/render.py`
- Create: `tests/roadmap/test_render.py`

- [ ] **Step 1: Write failing tests**

Create `tests/roadmap/test_render.py`:

```python
from datetime import date

from scripts.roadmap.render import (
    Theme,
    Task,
    compose_roadmap,
    compose_task_note,
    format_board_card,
)


def _sample_themes() -> list[Theme]:
    return [
        Theme(
            slug="ai-engine-pluggability",
            title="AI 引擎可插拔化",
            why="目前只支援 LangGraph (見 [[modules/backend]]);AGENTS.md 提 pluggable engine 但未落實。",
            priority="🔴",
            effort="M",
            evidence=["[[Architecture/future#期望中的想法]] 第 1 點",
                      "[[Projects/p/Research/2026-05-15-engine-comparison]]"],
            tasks=[
                Task(id="T-001", slug="add-engine-adapter-base",
                     description="在 backend/engines/ 加 EngineAdapter base class",
                     module_wikilink="[[modules/backend]]",
                     acceptance_criteria=["`backend/engines/adapter.py` 有 EngineAdapter ABC"]),
                Task(id="T-002", slug="port-langgraph-as-adapter",
                     description="把 LangGraph 實作改寫為 LangGraphAdapter",
                     module_wikilink="[[modules/backend]]",
                     acceptance_criteria=["adapter 通過整合測試"]),
            ],
        ),
    ]


def test_compose_roadmap_emits_frontmatter_and_themes_section_zh():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 1, "architect_signals": 2},
        output_lang="zh-TW",
    )
    assert note.startswith("---\n")
    assert "type: roadmap" in note
    assert 'project: "[[myproj]]"' in note
    assert "lang: zh-TW" in note
    assert "themes-count: 1" in note
    assert "tasks-count: 2" in note
    assert "## 給未來 Claude" in note
    assert "## 本次合成摘要" in note
    assert "## 主題" in note
    # Theme heading appears as H3
    assert "### 🔴 AI 引擎可插拔化" in note
    # Tasks are wiki-linked
    assert "[[Tasks/T-001-add-engine-adapter-base|T-001 在 backend/engines/ 加 EngineAdapter base class]]" in note
    # Evidence rendered as bullets
    assert "[[Architecture/future#期望中的想法]]" in note


def test_compose_roadmap_en_translates_headings():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 0, "architect_signals": 1},
        output_lang="en",
    )
    assert "## For future Claude" in note
    assert "## Synthesis summary" in note
    assert "## Themes" in note
    assert "## 給未來 Claude" not in note


def test_compose_roadmap_renders_stale_section():
    note = compose_roadmap(
        project="myproj",
        themes=_sample_themes(),
        stale_themes=[
            Theme(slug="dropped-thing", title="放棄的東西", why="signal disappeared",
                  priority="🟢", effort="S", evidence=[], tasks=[]),
        ],
        synthesis_summary={"themes": 1, "tasks": 2, "research_cited": 0, "architect_signals": 1},
        output_lang="zh-TW",
    )
    assert "## 過時主題" in note
    assert "放棄的東西" in note


def test_compose_task_note_zh():
    t = Task(id="T-001", slug="add-engine-adapter-base",
             description="在 backend/engines/ 加 EngineAdapter base class",
             module_wikilink="[[modules/backend]]",
             acceptance_criteria=["`backend/engines/adapter.py` 有 EngineAdapter ABC",
                                  "既有 LangGraph 可以 instantiate 為 adapter"])
    note = compose_task_note(
        task=t,
        theme_slug="ai-engine-pluggability",
        theme_title="AI 引擎可插拔化",
        project="myproj",
        output_lang="zh-TW",
    )
    assert "type: task" in note
    assert "roadmap-theme: ai-engine-pluggability" in note
    assert 'created-by: "obsidian-roadmap"' in note
    assert "status: backlog" in note
    assert "## 給未來 Claude" in note
    assert "## 接受條件" in note
    assert "EngineAdapter ABC" in note
    assert "[[Roadmap]]" in note
    assert "[[modules/backend]]" in note


def test_format_board_card_carries_theme_label():
    t = Task(id="T-007", slug="add-rate-limit",
             description="加 rate limit middleware",
             module_wikilink="[[modules/backend]]",
             acceptance_criteria=[])
    card = format_board_card(t, theme_slug="observability", priority="🔴")
    assert card.startswith("- [ ]")
    assert "[[Tasks/T-007-add-rate-limit|加 rate limit middleware]]" in card
    assert "🔴" in card
    assert "[theme: observability]" in card
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_render.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/roadmap/render.py`**

```python
"""Phase 5 — deterministic markdown composers.

These consume LLM-produced Theme/Task dataclasses and assemble:
- Roadmap.md (project-level curated view)
- Tasks/T-NNN-slug.md (one per task, /obsidian-task schema)
- board.md card line (single string appended to ## 待辦)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

from scripts.architect.lang import heading


@dataclass
class Task:
    id: str                       # "T-001"
    slug: str                     # "add-engine-adapter-base"
    description: str              # one-line zh-TW
    module_wikilink: str          # "[[modules/backend]]"
    acceptance_criteria: list[str]


@dataclass
class Theme:
    slug: str
    title: str
    why: str
    priority: str                 # "🔴" | "🟡" | "🟢"
    effort: str                   # "S" | "M" | "L" | "XL"
    evidence: list[str]
    tasks: list[Task]
    status: str = "active"        # active | stale


def compose_roadmap(
    *,
    project: str,
    themes: list[Theme],
    stale_themes: list[Theme],
    synthesis_summary: dict,
    output_lang: str,
) -> str:
    today = date.today().isoformat()
    tasks_count = sum(len(t.tasks) for t in themes)
    fm = [
        "---",
        "type: roadmap",
        f"date: {today}",
        f"updated: {today}",
        f'project: "[[{project}]]"',
        f"lang: {output_lang}",
        f"tags: [roadmap, {project}]",
        "ai-first: true",
        "status: active",
        f"last-synthesis: {today}",
        f"themes-count: {len(themes)}",
        f"tasks-count: {tasks_count}",
        "---",
    ]

    body: list[str] = ["", heading("## For future Claude", output_lang)]
    if output_lang == "zh-TW":
        body.append("這是 curated roadmap。策略主題對應原子 task。每個主題的 evidence 區指回 signal 來源。"
                    "Re-run 自動 dedup 並標 stale 主題。")
    else:
        body.append("Curated project roadmap. Themes group atomic tasks; evidence wikilinks "
                    "back to architect signal sources. Re-runs dedup and mark stale themes.")
    body.append("")

    # Synthesis summary
    body.append(heading("## Synthesis summary", output_lang))
    body.append("<!-- @generated:start synthesis-summary -->")
    if output_lang == "zh-TW":
        body.append(f"- 主題: {synthesis_summary['themes']}")
        body.append(f"- Tasks: {synthesis_summary['tasks']}")
        body.append(f"- 引用 research 篇數: {synthesis_summary['research_cited']}")
        body.append(f"- Architect signal 數: {synthesis_summary['architect_signals']}")
    else:
        body.append(f"- Themes: {synthesis_summary['themes']}")
        body.append(f"- Tasks: {synthesis_summary['tasks']}")
        body.append(f"- Research notes cited: {synthesis_summary['research_cited']}")
        body.append(f"- Architect signals used: {synthesis_summary['architect_signals']}")
    body.append("<!-- @generated:end synthesis-summary -->")
    body.append("")

    # Themes
    body.append(heading("## Themes", output_lang))
    body.append("<!-- @generated:start themes -->")
    for t in themes:
        body.extend(_render_theme(t, output_lang))
        body.append("")
    body.append("<!-- @generated:end themes -->")
    body.append("")

    # Stale
    if stale_themes:
        body.append(heading("## Stale themes", output_lang))
        body.append("<!-- @generated:start stale-themes -->")
        for t in stale_themes:
            body.append(f"### {t.title}")
            if output_lang == "zh-TW":
                body.append(f"_status: stale_ — signal 來源消失,留檔不刪。")
            else:
                body.append(f"_status: stale_ — signal source disappeared; kept for history.")
            body.append("")
        body.append("<!-- @generated:end stale-themes -->")
        body.append("")

    body.append(heading("## Related", output_lang))
    body.append(f"- [[{project}]]")
    body.append("- [[Architecture/overview]]")
    body.append("- [[board]]")

    return "\n".join(fm + body) + "\n"


def _render_theme(t: Theme, lang: str) -> list[str]:
    why_label = "為什麼" if lang == "zh-TW" else "Why"
    effort_label = "Effort" if lang == "en" else "Effort"
    evidence_label = "佐證" if lang == "zh-TW" else "Evidence"
    tasks_label = "Tasks"
    out = [f"### {t.priority} {t.title}"]
    out.append(f"**{why_label}:** {t.why}")
    out.append(f"**{effort_label}:** {t.effort}")
    if t.evidence:
        out.append(f"**{evidence_label}:**")
        for e in t.evidence:
            out.append(f"- {e}")
    if t.tasks:
        out.append(f"**{tasks_label}:**")
        for task in t.tasks:
            out.append(f"- [[Tasks/{task.id}-{task.slug}|{task.id} {task.description}]]")
    return out


def compose_task_note(
    *,
    task: Task,
    theme_slug: str,
    theme_title: str,
    project: str,
    output_lang: str,
) -> str:
    today = date.today().isoformat()
    fm = [
        "---",
        "type: task",
        f"date: {today}",
        f'project: "[[{project}]]"',
        f"roadmap-theme: {theme_slug}",
        f'created-by: "obsidian-roadmap"',
        f"lang: {output_lang}",
        "status: backlog",
        "priority: 🟡",
        f"tags: [task, {project}, {theme_slug}]",
        "ai-first: true",
        "---",
    ]
    body = ["", heading("## For future Claude", output_lang)]
    if output_lang == "zh-TW":
        body.append(f"任務 `{task.id}` — {task.description}。屬於 roadmap 主題「{theme_title}」。")
    else:
        body.append(f"Task `{task.id}` — {task.description}. Part of roadmap theme \"{theme_title}\".")
    body.append("")

    body.append(heading("## Acceptance criteria", output_lang))
    if task.acceptance_criteria:
        for c in task.acceptance_criteria:
            body.append(f"- {c}")
    else:
        body.append("_(待定義)_" if output_lang == "zh-TW" else "_(to be defined)_")
    body.append("")

    body.append(heading("## Related", output_lang))
    body.append("- [[Roadmap]]")
    body.append(f"- [[Roadmap#{theme_title}]]")
    if task.module_wikilink:
        body.append(f"- {task.module_wikilink}")
    return "\n".join(fm + body) + "\n"


def format_board_card(task: Task, theme_slug: str, priority: str) -> str:
    """Single line appended to board.md ## 待辦 section."""
    return f"- [ ] [[Tasks/{task.id}-{task.slug}|{task.description}]] {priority} [theme: {theme_slug}]"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_render.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/render.py tests/roadmap/test_render.py
git commit -m "feat(roadmap): Roadmap.md + task + board card composers"
```

---

### Task 7: Slug validator + fallback

**Files:**
- Modify: `scripts/roadmap/render.py`
- Modify: `tests/roadmap/test_render.py`

- [ ] **Step 1: Write failing test**

Append to `tests/roadmap/test_render.py`:

```python
def test_normalize_slug_keeps_valid():
    from scripts.roadmap.render import normalize_slug
    assert normalize_slug("add-engine-adapter-base") == "add-engine-adapter-base"
    assert normalize_slug("refresh-token-rotation") == "refresh-token-rotation"


def test_normalize_slug_falls_back_when_invalid():
    from scripts.roadmap.render import normalize_slug
    # Capitalised / spaces / Chinese -> fallback uses description
    assert normalize_slug("Add Adapter Base") == "add-adapter-base"
    assert normalize_slug("在 backend 加 EngineAdapter") == "backend-engineadapter"


def test_normalize_slug_caps_length():
    from scripts.roadmap.render import normalize_slug
    s = normalize_slug("a-" * 50)  # 100 chars
    assert len(s) <= 50


def test_normalize_slug_handles_empty():
    from scripts.roadmap.render import normalize_slug
    # All-non-ascii input falls back to hash-based slug
    s = normalize_slug("一個全中文的任務")
    assert s.startswith("task-")  # fallback prefix
    assert len(s) > 5
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/roadmap/test_render.py::test_normalize_slug_keeps_valid tests/roadmap/test_render.py::test_normalize_slug_falls_back_when_invalid tests/roadmap/test_render.py::test_normalize_slug_caps_length tests/roadmap/test_render.py::test_normalize_slug_handles_empty -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `normalize_slug` to `scripts/roadmap/render.py`**

```python


import re as _re
import hashlib as _hashlib

_VALID_SLUG_RE = _re.compile(r"^[a-z0-9][a-z0-9-]{0,49}$")
_NON_SLUG_CHARS = _re.compile(r"[^a-z0-9-]+")
_MULTI_HYPHEN = _re.compile(r"-{2,}")


def normalize_slug(raw: str, max_len: int = 50) -> str:
    """Return an ascii-lowercase-hyphen slug.

    - If already valid (matches `[a-z0-9][a-z0-9-]{0,49}`), return as-is.
    - Otherwise lowercase + replace non-ascii-slug chars with hyphen + collapse.
    - If the result is empty (e.g. all-non-ASCII input), fall back to
      `task-<short-hash>` so the filename is still legal.
    """
    s = raw.strip().lower()
    if _VALID_SLUG_RE.match(s):
        return s[:max_len]
    # Collapse: replace any run of non-slug chars with single hyphen.
    s = _NON_SLUG_CHARS.sub("-", s)
    s = _MULTI_HYPHEN.sub("-", s).strip("-")
    if not s:
        h = _hashlib.sha1(raw.encode("utf-8")).hexdigest()[:8]
        return f"task-{h}"
    return s[:max_len].rstrip("-")
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_render.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/render.py tests/roadmap/test_render.py
git commit -m "feat(roadmap): slug normalization with fallback for non-ASCII"
```

---

### Task 8: Hub file IO helpers

**Files:**
- Modify: `scripts/roadmap/render.py`
- Modify: `tests/roadmap/test_render.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/roadmap/test_render.py`:

```python
def test_append_board_card_to_existing_backlog(tmp_path):
    from scripts.roadmap.render import append_to_board
    board = tmp_path / "board.md"
    board.write_text(
        "---\n"
        "type: board\n"
        "---\n"
        "\n"
        "## 待辦\n"
        "\n"
        "- [ ] existing card\n"
        "\n"
        "## 進行中\n"
    )
    appended = append_to_board(board, ["- [ ] new card 1", "- [ ] new card 2"], heading_zh="## 待辦", heading_en="## Backlog")
    text = board.read_text()
    assert "- [ ] existing card" in text
    assert "- [ ] new card 1" in text
    assert "- [ ] new card 2" in text
    assert appended == 2
    # Cards land BEFORE ## 進行中, not after
    backlog_idx = text.index("## 待辦")
    inprogress_idx = text.index("## 進行中")
    new_card_idx = text.index("new card 1")
    assert backlog_idx < new_card_idx < inprogress_idx


def test_append_board_card_creates_backlog_section_if_missing(tmp_path):
    from scripts.roadmap.render import append_to_board
    board = tmp_path / "board.md"
    board.write_text("## 進行中\n\n## 已完成\n")
    appended = append_to_board(board, ["- [ ] one"], heading_zh="## 待辦", heading_en="## Backlog")
    text = board.read_text()
    assert "## 待辦" in text
    assert "- [ ] one" in text
    assert appended == 1
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/roadmap/test_render.py::test_append_board_card_to_existing_backlog tests/roadmap/test_render.py::test_append_board_card_creates_backlog_section_if_missing -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `append_to_board` to `scripts/roadmap/render.py`**

```python


def append_to_board(board_path, cards: list[str], heading_zh: str = "## 待辦", heading_en: str = "## Backlog") -> int:
    """Append `cards` (markdown lines) to the board's backlog heading.

    Looks for `heading_zh` first, then `heading_en`. If neither exists,
    appends a new `heading_zh` section at the end. Cards land at the END of
    the existing backlog list, just before the next H2 (or EOF).

    Returns the number of cards appended.
    """
    from pathlib import Path
    p = Path(board_path)
    text = p.read_text(encoding="utf-8")
    heading = heading_zh if heading_zh in text else (heading_en if heading_en in text else None)
    if heading is None:
        # Append new section at end.
        text = text.rstrip() + "\n\n" + heading_zh + "\n\n" + "\n".join(cards) + "\n"
        p.write_text(text, encoding="utf-8")
        return len(cards)
    # Find heading + the next ## heading (or EOF).
    h_idx = text.index(heading)
    body_start = text.index("\n", h_idx) + 1
    rest = text[body_start:]
    next_h2 = _re.search(r"\n##\s+", rest)
    body_end = body_start + (next_h2.start() if next_h2 else len(rest))
    body = text[body_start:body_end].rstrip()
    insertion = "\n".join(cards)
    new_body = (body + "\n" + insertion) if body else insertion
    text = text[:body_start] + new_body + "\n\n" + text[body_end:].lstrip("\n")
    p.write_text(text, encoding="utf-8")
    return len(cards)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_render.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/render.py tests/roadmap/test_render.py
git commit -m "feat(roadmap): append_to_board helper with section auto-create"
```

---

## Phase E — Parser + synthesis prompt

### Task 9: Review parser (Phase 4)

**Files:**
- Create: `scripts/roadmap/parser.py`
- Create: `tests/roadmap/test_parser.py`

- [ ] **Step 1: Write failing tests**

Create `tests/roadmap/test_parser.py`:

```python
import pytest

from scripts.roadmap.parser import (
    ReviewAction,
    parse_review_response,
    ParseError,
)


def test_parses_keep_all_default():
    """A row with empty action column defaults to K (keep)."""
    paste = """\
| # | Action | 主題 | Priority | Effort | Evidence | Tasks |
|---|---|---|---|---|---|---|
| 1 |  | AI 引擎可插拔化 | 🔴 | M | 2 | 4 |
| 2 |  | 觀測性補強 | 🟡 | M | 3 | 3 |
"""
    actions = parse_review_response(paste, n_themes=2)
    assert actions == [ReviewAction(idx=1, kind="K"), ReviewAction(idx=2, kind="K")]


def test_parses_explicit_kdme():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | K | A |
| 2 | D | B |
| 3 | M:1 | C |
| 4 | E | D |
"""
    actions = parse_review_response(paste, n_themes=4)
    assert actions[0].kind == "K"
    assert actions[1].kind == "D"
    assert actions[2].kind == "M"
    assert actions[2].merge_target == 1
    assert actions[3].kind == "E"


def test_dropped_rows_dont_appear():
    """User physically deleted row 3 from the paste -> treated as D."""
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | K | A |
| 2 | K | B |
"""
    actions = parse_review_response(paste, n_themes=3)
    assert {a.idx for a in actions if a.kind == "K"} == {1, 2}
    assert any(a.idx == 3 and a.kind == "D" for a in actions)


def test_merge_target_must_exist():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | M:99 | A |
"""
    with pytest.raises(ParseError, match="merge target 99 not in 1..1"):
        parse_review_response(paste, n_themes=1)


def test_invalid_action_value_raises():
    paste = """\
| # | Action | 主題 |
|---|---|---|
| 1 | XYZ | A |
"""
    with pytest.raises(ParseError, match="row 1.*invalid action 'XYZ'"):
        parse_review_response(paste, n_themes=1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_parser.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/roadmap/parser.py`**

```python
"""Phase 4 — parse user's batch-review paste back into ReviewActions."""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class ReviewAction:
    idx: int                      # 1-indexed theme position from Phase 3 output
    kind: str                     # K | D | M | E
    merge_target: int | None = None   # for M:<n>
    edit_payload: str | None = None   # for E (free-form, parsed downstream)


class ParseError(ValueError):
    pass


_ROW_RE = re.compile(r"^\|\s*(\d+)\s*\|\s*([^|]*?)\s*\|", re.MULTILINE)
_MERGE_RE = re.compile(r"^M\s*:\s*(\d+)\s*$", re.IGNORECASE)


def parse_review_response(paste: str, n_themes: int) -> list[ReviewAction]:
    """Parse the markdown table the user pasted back.

    Rules:
    - A row's Action cell may be empty (defaults to K), or K/D/M:<n>/E.
    - Rows the user deleted from the paste are treated as D.
    - Returns ordered ReviewAction list covering ALL theme indices 1..n_themes.
    """
    seen: dict[int, ReviewAction] = {}
    for m in _ROW_RE.finditer(paste):
        idx = int(m.group(1))
        action_cell = m.group(2).strip()
        if idx < 1 or idx > n_themes:
            # Out-of-range row — ignore (user added junk?).
            continue
        seen[idx] = _parse_action(idx, action_cell, n_themes)

    # Missing rows = dropped.
    out: list[ReviewAction] = []
    for i in range(1, n_themes + 1):
        out.append(seen.get(i, ReviewAction(idx=i, kind="D")))
    return out


def _parse_action(idx: int, cell: str, n_themes: int) -> ReviewAction:
    if cell == "" or cell.upper() == "K":
        return ReviewAction(idx=idx, kind="K")
    if cell.upper() == "D":
        return ReviewAction(idx=idx, kind="D")
    m = _MERGE_RE.match(cell)
    if m:
        target = int(m.group(1))
        if target < 1 or target > n_themes:
            raise ParseError(f"row {idx}: merge target {target} not in 1..{n_themes}")
        if target == idx:
            raise ParseError(f"row {idx}: cannot merge into itself")
        return ReviewAction(idx=idx, kind="M", merge_target=target)
    if cell.upper().startswith("E"):
        # E or "E:<payload>"
        payload = cell[2:] if cell[1:2] == ":" else ""
        return ReviewAction(idx=idx, kind="E", edit_payload=payload.strip() or None)
    raise ParseError(f"row {idx}: invalid action {cell!r}")
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_parser.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/parser.py tests/roadmap/test_parser.py
git commit -m "feat(roadmap): Phase-4 review-paste parser (K/D/M/E + default-K)"
```

---

### Task 10: Theme synthesis prompt builder (Phase 3)

**Files:**
- Modify: `scripts/roadmap/render.py` OR new file
- Modify: existing `tests/roadmap/test_render.py` OR new test file

Use a new file to keep render.py focused on output composition.

**Files:**
- Create: `scripts/roadmap/synthesis.py`
- Create: `tests/roadmap/test_synthesis.py`

- [ ] **Step 1: Write failing tests**

Create `tests/roadmap/test_synthesis.py`:

```python
import json

from scripts.roadmap.synthesis import build_synthesis_prompt


def test_synthesis_prompt_lists_candidates_with_evidence():
    candidates = [
        {"id": "gap-1", "title": "加 SSO 整合", "kind": "limitation",
         "evidence": ["[[Architecture/future#已知限制]]", "[[Research/Deep/2026-05-15-sso-providers]]"]},
        {"id": "asp-2", "title": "把 AI 引擎抽象成 pluggable adapter", "kind": "aspiration",
         "evidence": ["[[Architecture/future#期望中的想法]]"]},
    ]
    modules_summary = "backend (Python FastAPI), frontend (React 19)"
    prompt = build_synthesis_prompt(
        candidates=candidates,
        modules_summary=modules_summary,
        project="myproj",
        output_lang="zh-TW",
        max_themes=12,
    )
    assert "gap-1" in prompt
    assert "加 SSO 整合" in prompt
    assert "asp-2" in prompt
    assert "[[Research/Deep/2026-05-15-sso-providers]]" in prompt
    assert "myproj" in prompt
    assert "12" in prompt  # max_themes
    # Demands fully-spec'd tasks per spec §7 Phase 3
    assert "acceptance-criteria" in prompt
    assert "slug" in prompt
    # zh-TW directive
    assert "繁體中文" in prompt or "zh-TW" in prompt


def test_synthesis_prompt_en_no_zh_directive():
    prompt = build_synthesis_prompt(
        candidates=[],
        modules_summary="",
        project="x",
        output_lang="en",
        max_themes=6,
    )
    assert "English" in prompt or "en" in prompt
    assert "繁體中文" not in prompt
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_synthesis.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `scripts/roadmap/synthesis.py`**

```python
"""Phase 3 — LLM prompt builder for theme synthesis.

Output of the LLM (parsed by the agent) is a JSON list of themes with
fully-specified tasks (description + slug + module-wikilink + acceptance-criteria).
Phase 5 then writes files without further LLM calls.
"""

from __future__ import annotations

import json


def build_synthesis_prompt(
    *,
    candidates: list[dict],
    modules_summary: str,
    project: str,
    output_lang: str,
    max_themes: int = 12,
) -> str:
    """Build the LLM prompt for Phase 3 theme synthesis."""
    if output_lang == "zh-TW":
        lang_directive = (
            "輸出的 title / why / task description / acceptance-criteria 用繁體中文。"
            "Code identifier (檔名、function/class、env var、CLI 字串、URL、wikilink 內檔名段) "
            "保持英文。`slug` 必須 ascii-lowercase-hyphen,≤ 50 字元,動詞起頭。"
        )
    else:
        lang_directive = (
            "Output title / why / task description / acceptance-criteria in English. "
            "Slug must be ascii-lowercase-hyphen, <= 50 chars, verb-first."
        )

    lines = [
        f"You are synthesizing the Roadmap themes for project `{project}`.",
        f"Output language: {output_lang}.",
        lang_directive,
        "",
        f"Group {len(candidates)} candidate signals into {max_themes} or fewer themes. "
        "Each theme bundles related candidates and produces fully-specified tasks.",
        "",
        "Return STRICT JSON (no prose around it) — a list of themes:",
        json.dumps([{
            "slug": "<ascii-lowercase-hyphen, verb-first, ≤50 chars>",
            "title": "<short prose title>",
            "why": "<2-3 sentence rationale; cite candidates>",
            "priority": "<🔴 | 🟡 | 🟢>",
            "effort": "<S | M | L | XL>",
            "evidence": ["<wikilink>", "<wikilink>"],
            "candidate-ids": ["<id>", "<id>"],
            "tasks": [{
                "description": "<short, verb-first, ≤80 chars>",
                "slug": "<ascii-lowercase-hyphen>",
                "module-wikilink": "[[modules/<slug>]]",
                "acceptance-criteria": ["<bullet>", "<bullet>"],
            }],
        }], indent=2, ensure_ascii=False),
        "",
        f"Available modules: {modules_summary}",
        "",
        "Candidates:",
    ]
    for c in candidates:
        lines.append(f"- id={c['id']} kind={c['kind']}")
        lines.append(f"  title: {c['title']}")
        if c.get("evidence"):
            lines.append(f"  evidence: {c['evidence']}")
    return "\n".join(lines)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_synthesis.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/roadmap/synthesis.py tests/roadmap/test_synthesis.py
git commit -m "feat(roadmap): Phase-3 theme synthesis prompt builder"
```

---

## Phase F — CLI orchestrator

### Task 11: `roadmap_synth.py` CLI entry

**Files:**
- Create: `scripts/roadmap_synth.py`
- Create: `tests/roadmap/test_cli.py`

- [ ] **Step 1: Write failing tests**

Create `tests/roadmap/test_cli.py`:

```python
import json
import subprocess
import sys
from pathlib import Path


def _make_minimal_project(root: Path):
    arch = root / "Architecture"
    arch.mkdir(parents=True)
    (arch / "future.md").write_text(
        "## 落差分析\n\n- README 提到 streaming API 但 api-surface 沒對應 endpoint\n"
        "## 期望中的想法\n\n- 把 AI 引擎抽象成 pluggable adapter\n"
    )
    (arch / "decisions.md").write_text(
        "## 建議升級為 ADR\n\n1. **為什麼 Redis Cluster** — TBD\n"
    )
    (arch / "roadmap.md").write_text("## 給未來 Claude\n empty roadmap\n")


def test_cli_dry_run_emits_candidates(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    _make_minimal_project(proj)
    out_dir = tmp_path / "out"
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(out_dir),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode == 0, f"stderr: {result.stderr}"
    candidates_file = out_dir / "candidates.json"
    assert candidates_file.exists()
    data = json.loads(candidates_file.read_text())
    assert len(data) >= 3
    kinds = {c["kind"] for c in data}
    assert "gap" in kinds
    assert "aspiration" in kinds
    assert "promote-to-adr" in kinds


def test_cli_emits_keyword_prompt(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    _make_minimal_project(proj)
    out_dir = tmp_path / "out"
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(out_dir),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode == 0
    kp = out_dir / "keyword_extraction_prompt.txt"
    assert kp.exists()
    text = kp.read_text()
    assert "streaming" in text or "AI 引擎" in text or "Redis" in text


def test_cli_aborts_when_no_architecture_dir(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    proj.mkdir(parents=True)  # no Architecture subfolder
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(tmp_path / "out"),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode != 0
    assert "Architecture" in result.stderr or "Architecture" in result.stdout
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_cli.py -v`
Expected: FAIL — script not found.

- [ ] **Step 3: Implement `scripts/roadmap_synth.py`**

```python
#!/usr/bin/env python3
"""CLI entry for /obsidian-roadmap Phase 1+2a.

Phase 1: detect candidates from Architecture/.
Phase 2a: build the keyword-extraction LLM prompt.

The slash-command body (`commands/obsidian-roadmap.md`) invokes this
script to get a deterministic seed, then drives the LLM (Phase 2c, 3),
parses the response (Phase 4), and calls render.py composers (Phase 5).

Usage:
    python scripts/roadmap_synth.py --project-root <path> --vault-root <path> --out <dir> [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.roadmap.candidates import detect_candidates
from scripts.roadmap.research_match import build_keyword_extraction_prompt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 1+2a scan for /obsidian-roadmap")
    parser.add_argument("--project-root", required=True,
                        help="Path to Projects/<P>/ inside the vault")
    parser.add_argument("--vault-root", required=True,
                        help="Path to the vault root (where _CLAUDE.md lives)")
    parser.add_argument("--out", required=True,
                        help="Directory to write candidates.json + keyword_extraction_prompt.txt")
    parser.add_argument("--lang", default="en",
                        help="Output language for the keyword-extraction prompt directive")
    parser.add_argument("--dry-run", action="store_true",
                        help="(currently a no-op flag for future LLM-driven phases)")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    vault_root = Path(args.vault_root).resolve()
    out_dir = Path(args.out).resolve()

    if not project_root.is_dir():
        print(f"error: project-root {project_root} not a directory", file=sys.stderr)
        return 2
    if not (project_root / "Architecture").is_dir():
        print(f"error: {project_root}/Architecture not found. "
              "Run /obsidian-architect first.", file=sys.stderr)
        return 3
    if not (vault_root / "_CLAUDE.md").is_file():
        print(f"warning: {vault_root}/_CLAUDE.md not found", file=sys.stderr)

    out_dir.mkdir(parents=True, exist_ok=True)

    # Phase 1
    cands = detect_candidates(project_root)
    payload = [asdict(c) for c in cands]
    (out_dir / "candidates.json").write_text(
        json.dumps(payload, indent=2, ensure_ascii=False)
    )

    # Phase 2a — keyword-extraction prompt (agent calls LLM with this)
    candidates_text = {c.id: c.raw_text for c in cands}
    prompt = build_keyword_extraction_prompt(candidates_text, output_lang=args.lang)
    (out_dir / "keyword_extraction_prompt.txt").write_text(prompt)

    print(f"wrote {out_dir / 'candidates.json'} ({len(cands)} candidates)")
    print(f"wrote {out_dir / 'keyword_extraction_prompt.txt'} ({len(prompt)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/roadmap/test_cli.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Run full roadmap test suite**

Run: `uv run pytest tests/roadmap/ -v`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add scripts/roadmap_synth.py tests/roadmap/test_cli.py
git commit -m "feat(roadmap): roadmap_synth.py CLI for Phase-1 + Phase-2a"
```

---

## Phase G — Schema + command body + adapter rebuild

### Task 12: Update `references/ai-first-rules.md` with `type: roadmap`

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Read current `type: task` and architecture sections to know where to insert**

Run: `grep -n "^### \`type:" references/ai-first-rules.md`
Expected output: line numbers for existing type entries.

- [ ] **Step 2: Insert new `type: roadmap` section after the architecture types**

Open `references/ai-first-rules.md`. After the last `architecture-*` entry (likely `architecture-function`), add:

```markdown
### `type: roadmap`

Generated by `/obsidian-roadmap`. Lives at `Projects/<P>/Roadmap.md`. Sits
between `architecture-roadmap` (descriptive, signal-derived under `Architecture/`)
and `Tasks/T-*.md` (atomic execution). This is the curated, prescriptive view
of "what we'll build next".

Required frontmatter:
- `type: roadmap`
- `date`, `updated`, `project` (wikilink)
- `lang: zh-TW | en`
- `tags: [roadmap, <project-name>]`
- `ai-first: true`, `status: active | frozen | archived`
- `last-synthesis: YYYY-MM-DD`
- `themes-count: N`, `tasks-count: N`

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Synthesis summary` / `## 本次合成摘要` — N themes / tasks / research cited / architect signals
- `## Themes` / `## 主題` — H3 per theme with priority emoji + title, then **Why / Effort / Evidence / Tasks**
- `## Stale themes` / `## 過時主題` (optional) — themes whose source signal disappeared on re-run
- `## Related` / `## 相關`

LLM-written sections (`synthesis-summary`, `themes`, `stale-themes`) are wrapped
in `<!-- @generated:start <name> -->` ... `<!-- @generated:end <name> -->` sentinels.

Companion `_roadmap.lock.json` (NOT a vault note) lives next to Roadmap.md;
tracks theme + task materialization across re-runs.

### `type: task` (extended)

Existing schema unchanged. Two optional fields added when the task originates
from `/obsidian-roadmap`:

- `roadmap-theme: <theme-slug>` — links back to a theme heading in Roadmap.md
- `created-by: "obsidian-roadmap"` — provenance marker

These are additive and ignored by `/obsidian-task` and `/obsidian-board`.
```

- [ ] **Step 3: Build adapters to ensure file ships cross-platform**

Run: `bash scripts/build.sh --platform claude-code`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(ai-first-rules): add type: roadmap and task extensions"
```

---

### Task 13: Write `commands/obsidian-roadmap.md` body

**Files:**
- Create: `commands/obsidian-roadmap.md`

- [ ] **Step 1: Create the command file**

Create `commands/obsidian-roadmap.md`:

````markdown
---
description: Synthesize Architecture signals + Research into a project Roadmap.md plus T-NNN tasks plus board cards
argument-hint: <project-name>
category: thinking
triggers_en: ["roadmap", "synth roadmap", "plan backlog", "generate backlog", "what to build next"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-roadmap $ARGUMENTS`:

The argument is `<project-name>` (the folder name under `Projects/`). Optional flags:
`--dry-run` (Phase 1+2a only, write to /tmp), `--force` (treat all themes as new),
`--only-themes=<N>` (cap synthesis output, default 12), `--skip-research` (Phase 2 skipped,
signals only), `--lang=<en|zh-TW>` (override vault `_CLAUDE.md output-lang`),
`--scope-research-days=<N>` (vault-wide Research window, default 30).

If `<project-name>` is omitted and `pwd` is inside `Projects/<P>/`, default to `<P>`.
Otherwise ASK the user which project.

## Pre-flight

- Vault root has `_CLAUDE.md`? If no, abort with "Run /obsidian-init first."
- `Projects/<P>/Architecture/` exists with at least `future.md`? If no, abort with
  "Run /obsidian-architect <repo> first."
- Resolve `output_lang`:

  ```bash
  uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
  ```

## Phase 1+2a — Deterministic scan

```bash
uv run python scripts/roadmap_synth.py \
    --project-root <vault>/Projects/<P> \
    --vault-root <vault> \
    --out /tmp/roadmap-<hash>/ \
    --lang <output_lang>
```

Outputs:
- `/tmp/roadmap-<hash>/candidates.json` — Phase 1 candidates (gap / limitation / aspiration / promote-to-adr / todo-cluster)
- `/tmp/roadmap-<hash>/keyword_extraction_prompt.txt` — prompt for Phase 2a

If `--dry-run`: print candidate count to user and stop.

If candidate count is 0: report "No candidates found — Architecture/ signals are insufficient. Suggest adding README Limitations / Future Work sections, or running /obsidian-architect with richer signals." Stop.

## Phase 2a — Keyword extraction (LLM)

Read `/tmp/roadmap-<hash>/keyword_extraction_prompt.txt` and invoke the LLM with it. Expect JSON response: `{<candidate-id>: [<keyword>, ...]}`. Save to `/tmp/roadmap-<hash>/keywords.json`.

## Phase 2b — Keyword prefilter (deterministic)

For each candidate, call `scripts.roadmap.research_match.keyword_prefilter(...)` to find candidate research notes (project Research/ unfiltered + vault Research/{Web,Deep} within `--scope-research-days`, capped at 10 per candidate). Save matches to `/tmp/roadmap-<hash>/prefilter.json`.

## Phase 2c — LLM relevance check

Call `scripts.roadmap.research_match.build_relevance_prompt(matches_by_cand, candidates_text, output_lang)` to build the prompt. Invoke LLM; expect JSON: `{<candidate-id>: [<relevant-research-path>, ...]}`. Save to `/tmp/roadmap-<hash>/relevance.json`.

Build a merged "linked-candidates" view: each candidate now carries its evidence wikilinks (architect source + filtered research paths converted to `[[<path-without-extension>]]`).

## Phase 3 — Theme synthesis (LLM)

Read `Projects/<P>/Architecture/_manifest.yml` for `modules_summary` (e.g. "backend, frontend, services, ...").

Call `scripts.roadmap.synthesis.build_synthesis_prompt(candidates=linked_candidates, modules_summary=..., project=<P>, output_lang=..., max_themes=--only-themes-flag)`. Invoke LLM; expect JSON list of themes (per spec §7 Phase 3 schema, with fully-spec'd tasks).

Save to `/tmp/roadmap-<hash>/themes.json`.

## Phase 4 — Batch review (user)

Print a markdown table to the conversation:

```markdown
| # | Action | 主題 | Priority | Effort | Evidence | Tasks |
|---|---|---|---|---|---|---|
| 1 | __ | <title> | 🔴 | M | 2 | 4 |
...

(per-theme detail follows: why, evidence wikilinks, task descriptions)
```

Then ask user to paste back the table with the Action column filled in. Valid actions:
- (empty) or `K` — keep
- `D` — drop
- `M:<n>` — merge into theme <n>
- `E` — edit (user provides edited JSON inline below the table)

Parse via `scripts.roadmap.parser.parse_review_response(paste, n_themes)`. If `ParseError`: show the error to the user, ask them to re-paste. Max 3 retries before aborting.

Compute the final theme list (drop D rows, merge M rows into their target, apply E edits).

Re-prompt user "請確認 N themes / M tasks 將寫入。是否進 Phase 5?" — wait for Y/N.

## Phase 5 — Materialize (deterministic)

Load `Projects/<P>/_roadmap.lock.json` if it exists; otherwise initialize.

For each kept theme:
1. Compute signal-hash. If lockfile has this theme slug with matching hash, SKIP. If theme slug exists with different hash, mark `needs-refresh` and proceed. If new theme, allocate.
2. For each task, call `allocate_task_id(lock)` for the next "T-NNN" then `normalize_slug(task.slug or task.description)`.
3. Write `Projects/<P>/Tasks/T-NNN-<slug>.md` via `compose_task_note(...)`.
4. Append board card via `append_to_board(Projects/<P>/board.md, [format_board_card(task, theme.slug, theme.priority)], heading_zh="## 待辦", heading_en="## Backlog")`.
5. Update `lockfile.themes[slug]` and `lockfile.tasks[task-id]`.

Detect stale themes: every theme in lockfile whose slug doesn't appear in this run's kept themes. Mark `status: stale`, include in `stale_themes` arg to `compose_roadmap`.

Write `Projects/<P>/Roadmap.md` via `compose_roadmap(project=<P>, themes=kept, stale_themes=stale, synthesis_summary={...}, output_lang=...)`.

Write `Projects/<P>/_roadmap.lock.json` via `write_lockfile(...)`.

## Daily / operation log

- If `Logs/` exists, append `**HH:MM** - roadmap | <P> - synthesized N themes (K new, M refreshed) → N+K tasks` to `Logs/YYYY-MM-DD.md`.
- Otherwise append `## [YYYY-MM-DD] roadmap | <P> - ...` to `log.md`.
- Append to today's daily note `## Activity` section: `- /obsidian-roadmap: synthesized [[<P>/Roadmap]]`.

## Errors and edge cases

- Architecture/ missing → abort, suggest `/obsidian-architect`.
- All sections of `architecture-future` flagged `status: insufficient-signal` → no candidates → report + stop.
- Phase 2c LLM returns malformed JSON → retry once with stricter "STRICT JSON ONLY" preamble; if still bad, downgrade to "all matches kept" (skip relevance filter) with warning.
- Phase 4 parse fails 3 times → abort, save `/tmp/roadmap-<hash>/` for inspection.
- Phase 5 write of one task fails (e.g. permission) → rollback that theme's tasks, don't update lockfile entry for that theme, continue with others.
- Lockfile schema-version mismatch → abort, instruct user to upgrade or remove the lockfile.

---

**AI-first rule:** Every note created by this command MUST follow `references/ai-first-rules.md` — frontmatter (`type`, `date`, `lang`, `tags`, `ai-first: true`, plus type-specific fields), `## For future Claude` preamble, `[[wikilinks]]`, code identifiers preserved in English, recency markers for external claims.

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag override. Roadmap.md / Task notes / board cards use that language for prose + headings; T-NNN-slug filenames, frontmatter keys/enums, wikilink path segments, and code identifiers remain English. See `references/ai-first-rules.md` §Language.

**Obsidian Markdown:** Roadmap.md uses OFM wikilinks (`[[Tasks/T-001-foo|display]]`), bilingual H2/H3 headings, and the sentinel-aware `@generated` block convention from architect. Reference the `obsidian-markdown` skill for OFM specifics (callouts, embeds, anchor formatting).
````

- [ ] **Step 2: Build adapters**

Run: `bash scripts/build.sh`
Expected: 4 dist trees regenerate, no errors.

- [ ] **Step 3: Verify command appears in dist**

Run: `ls dist/claude-code/commands/obsidian-roadmap.md dist/codex-cli/.codex/commands/obsidian-roadmap.md dist/gemini-cli/.gemini/commands/obsidian-roadmap.md dist/opencode/.opencode/command/obsidian-roadmap.md`
Expected: all four files exist.

- [ ] **Step 4: Verify the adapter rewrote tool-name references to neutral wording**

Run: `grep -c "Read tool" dist/codex-cli/.codex/commands/obsidian-roadmap.md`
Expected: 0.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-roadmap.md dist/
git commit -m "feat(roadmap): commands/obsidian-roadmap.md body + adapter rebuild"
```

---

## Phase H — Polish

### Task 14: CHANGELOG, SKILL.md, README

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: Add CHANGELOG entry under `## Unreleased`**

Open `CHANGELOG.md`. Under the `## Unreleased` heading (create if missing), add:

```markdown
### Added

- `/obsidian-roadmap <project>` — synthesize a project Roadmap.md plus
  Tasks/T-NNN-*.md plus board cards from Architecture/ signals
  (future.md, decisions.md "Promote to ADR", roadmap.md TODO clusters)
  and accumulated Research/ (project-scoped + recent vault-wide). New
  `type: roadmap` schema lives at `Projects/<P>/Roadmap.md` (separate
  from `architecture-roadmap` under `Architecture/`). `_roadmap.lock.json`
  tracks theme + task materialization for idempotent re-runs.
- 5-phase pipeline: Phase 1 deterministic gap detection, Phase 2 two-stage
  research matching (keyword prefilter + LLM relevance), Phase 3 single
  LLM call producing fully-spec'd themes, Phase 4 batch markdown table
  review (K/D/M/E actions), Phase 5 deterministic file write.
- `type: task` gains two optional fields: `roadmap-theme` (links back to
  a Roadmap.md theme) and `created-by` (provenance marker).
```

- [ ] **Step 2: Update SKILL.md Layer 2 list**

Open `SKILL.md`. Find the Layer 2 (Thinking tools) section, near the other `obsidian-*` thinking commands. Insert:

```markdown
- `/obsidian-roadmap <project>` — fuse Architecture signals plus accumulated
  Research into a curated `Roadmap.md` plus `T-NNN-*.md` tasks plus board
  cards. Three layers: architecture (descriptive) → roadmap (prescriptive)
  → tasks (atomic). Idempotent via `_roadmap.lock.json`; supports vault-wide
  zh-TW via `_CLAUDE.md output-lang`.
```

- [ ] **Step 3: Update README.md commands table**

Open `README.md`. Find the commands table row that lists `/obsidian-task` or `/obsidian-board`. After it (or in the same Thinking-tools group), add:

```markdown
| `/obsidian-roadmap` | Synthesize Architecture signals + Research into Roadmap.md + Tasks + board cards. 5-phase pipeline with batch review. |
```

- [ ] **Step 4: Build adapters**

Run: `bash scripts/build.sh`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md SKILL.md README.md dist/
git commit -m "docs: announce /obsidian-roadmap command and type: roadmap schema"
```

---

### Task 15: End-to-end smoke test against langlive-line-oa

**Files:**
- (read-only verification — no new code)

- [ ] **Step 1: Run full test suite**

Run: `uv run pytest tests/ -q`
Expected: all green (architect + roadmap + research tests).

- [ ] **Step 2: Run Phase 1+2a CLI against the real langlive-line-oa project**

```bash
uv run python scripts/roadmap_synth.py \
    --project-root /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa \
    --vault-root /Users/leric/Documents/SecondBrain \
    --out /tmp/roadmap-smoke/ \
    --lang zh-TW
```

Expected output:
```
wrote /tmp/roadmap-smoke/candidates.json (N candidates)
wrote /tmp/roadmap-smoke/keyword_extraction_prompt.txt (M chars)
```

- [ ] **Step 3: Inspect candidates JSON**

```bash
python -c "import json; d = json.load(open('/tmp/roadmap-smoke/candidates.json')); \
print(f'total: {len(d)}'); \
print('kinds:', {k: sum(1 for c in d if c[\"kind\"] == k) for k in set(c['kind'] for c in d)}); \
print('sample:', d[0] if d else 'empty')"
```

Expected: candidates count > 0, kinds include `gap`, `aspiration`, `promote-to-adr`. Sample shows readable `title` + `source_wikilink` pointing to `[[Architecture/future#...]]`.

- [ ] **Step 4: Inspect keyword prompt**

```bash
head -30 /tmp/roadmap-smoke/keyword_extraction_prompt.txt
```

Expected: prompt body lists each candidate with its id and raw_text; explicitly demands JSON output; mentions 3-5 keywords per candidate.

- [ ] **Step 5: Spot-check Phase 5 composers in isolation**

```bash
uv run python << 'PYEOF'
from scripts.roadmap.render import Theme, Task, compose_roadmap, compose_task_note, format_board_card

t = Task(id="T-001", slug="add-engine-adapter-base",
         description="在 backend/engines/ 加 EngineAdapter base class",
         module_wikilink="[[modules/backend]]",
         acceptance_criteria=["`backend/engines/adapter.py` 有 EngineAdapter ABC"])
theme = Theme(slug="ai-engine-pluggability", title="AI 引擎可插拔化",
              why="目前只支援 LangGraph",
              priority="🔴", effort="M",
              evidence=["[[Architecture/future#期望中的想法]]"],
              tasks=[t])
roadmap_text = compose_roadmap(
    project="langlive-line-oa",
    themes=[theme], stale_themes=[],
    synthesis_summary={"themes": 1, "tasks": 1, "research_cited": 0, "architect_signals": 1},
    output_lang="zh-TW",
)
print("=== Roadmap.md sample ===")
print(roadmap_text)
print()
print("=== task note sample ===")
print(compose_task_note(task=t, theme_slug=theme.slug, theme_title=theme.title,
                       project="langlive-line-oa", output_lang="zh-TW"))
print()
print("=== board card ===")
print(format_board_card(t, theme_slug=theme.slug, priority=theme.priority))
PYEOF
```

Expected output snippets:
- `type: roadmap`, `lang: zh-TW`, `## 給未來 Claude`, `## 主題`, `### 🔴 AI 引擎可插拔化`
- `type: task`, `roadmap-theme: ai-engine-pluggability`, `## 接受條件`, `[[Roadmap]]`
- `- [ ] [[Tasks/T-001-add-engine-adapter-base|...]] 🔴 [theme: ai-engine-pluggability]`

If anything wrong: trace via the failing render test; the helpers are individually unit-tested so failure here = composer integration bug.

- [ ] **Step 6: Verify branch state**

Run: `git log --oneline -20`
Expected: roughly 15 commits, one per task in this plan.

Run: `uv run pytest tests/ -q && bash scripts/build.sh`
Expected: full green; all 4 adapter dist trees regenerate cleanly.

---

## Acceptance checklist (mirrors spec §12)

After all 15 tasks, verify by hand:

- [ ] Phase 1: scanning langlive-line-oa's Architecture/ yields ≥ 3 candidates
- [ ] Phase 2: `keyword_prefilter` on a candidate with a matching Research note returns ≥ 1 match; the LLM relevance prompt builds without error
- [ ] Phase 3: `build_synthesis_prompt` includes candidates + modules + max-themes; demands JSON with `acceptance-criteria`
- [ ] Phase 4: `parse_review_response` handles all four actions (K / D / M / E) and treats deleted rows as D
- [ ] Phase 5: `compose_roadmap`, `compose_task_note`, `format_board_card`, `append_to_board` all produce output matching the spec body schema
- [ ] `_roadmap.lock.json` round-trips through `load_lockfile` / `write_lockfile` with `ThemeEntry` + `TaskEntry` + `allocate_task_id` working
- [ ] `scripts/roadmap_synth.py --dry-run` produces `candidates.json` + `keyword_extraction_prompt.txt` against the real vault
- [ ] `bash scripts/build.sh` passes; new command file ships across all 4 platforms
- [ ] `references/ai-first-rules.md` has `type: roadmap` plus task extensions
- [ ] zh-TW mode: composer output uses `## 主題` / `## 接受條件`; code identifiers (T-NNN-slug, wikilink paths, frontmatter keys) stay English
- [ ] `obsidian-markdown` skill conventions respected (proper wikilinks, no bare `[[name]]` that risks fuzzy-match, no `>` quotes where callouts are right)
