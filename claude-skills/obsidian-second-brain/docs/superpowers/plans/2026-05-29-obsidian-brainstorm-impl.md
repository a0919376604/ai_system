# `/obsidian-brainstorm` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new slash command `/obsidian-brainstorm <project>` that interviews the user (provocation-style, 4-6 bold next-direction ideas read from vault) and distills the conversation into `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`, with 9 `@generated` blocks that `/obsidian-roadmap` automatically picks up as candidates.

**Architecture:** Additive layer. New section type `brainstorm` in `sections.py` with 9 blocks. New helpers: `parse_hypothesis_block` (parallel to `parse_improvements_block`) and `compose_brainstorm_note` (parallel to `compose_features_note`). 8 new heading mappings in `lang.py`. Roadmap candidate detector walks `Brainstorms/` folder — `distilled-imps` block → `brainstorm-imp` candidates (priority `normal` for `stated` confidence, `low` for `hypothesis`/`speculation`); `hypotheses` block → `brainstorm-hypothesis` candidates (always `low`). New dedup rule: when candidates share Evidence wikilinks, `Brainstorms/` source wins over architecture-inferred sources. Command body is conversational (LLM reads vault → opens with 4-6 provocations → user reacts → Claude drills via follow-ups → Claude writes the note).

**Tech Stack:** Python 3.10+, pytest, existing `sections.py` / `lang.py` / `candidates.py` plumbing. No new Python modules. Reuses `parse_improvements_block` / `_parse_feature_imp_entries` / `_extract_generated_block` / `_candidate_from_feature_imp` / `compose_note` patterns.

**Plan-level notes:**
- Run tests from repo root `/Users/leric/Desktop/code/obsidian-second-brain` with `uv run pytest tests/path/test.py -v`.
- Co-author line on every commit: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- `dist/` is gitignored — never `git add dist/`. Staging commands list only source files.
- When pytest emits a COLLECTION ERROR (`ModuleNotFoundError` / missing attribute), that is the expected RED state for TDD — proceed to implementation.

---

## File structure (locked here)

**New files:**
- `commands/obsidian-brainstorm.md` — slash command body (conversational instructions for Claude)
- `tests/architect/test_brainstorm.py` — 6 tests (section registration + `parse_hypothesis_block` + `compose_brainstorm_note`)

**Modified files:**
- `scripts/architect/sections.py` — register `brainstorm` section type + 9 blocks + 8 new heading entries in `_BLOCK_HEADINGS`; add `parse_hypothesis_block`, `compose_brainstorm_note`, `_preamble_for("brainstorm", lang)` entries
- `scripts/architect/lang.py` — 8 new zh-TW heading mappings
- `scripts/roadmap/candidates.py` — walk `Projects/<P>/Brainstorms/*.md`; extract `distilled-imps` + `hypotheses` blocks; skip `status: actioned`; dedup pass favoring `Brainstorms/` source
- `tests/architect/test_lang.py` — assert 8 new heading mappings
- `tests/roadmap/test_candidates.py` — 3 tests (brainstorm walk + actioned skip + dedup beats architecture)
- `references/ai-first-rules.md` — `project-brainstorm` schema
- `SKILL.md` — Thinking tools layer announcement bullet
- `README.md` — command table row
- `CHANGELOG.md` — `## [Unreleased]` entry

---

## Phase A: Foundation (sections.py + lang.py registration)

### Task 1: Register `brainstorm` section type + 9 blocks + 8 new headings + preamble

**Files:**
- Modify: `scripts/architect/sections.py` (3 spots: `SECTION_TYPES`, `_BLOCK_NAMES`, `_BLOCK_HEADINGS`, `_preamble_for`)
- Modify: `scripts/architect/lang.py` (`HEADING_MAP`)
- Test: `tests/architect/test_brainstorm.py` (new file)
- Test: `tests/architect/test_lang.py` (append)

- [ ] **Step 1: Create new test file with registration smoke**

Create `tests/architect/test_brainstorm.py`:

```python
"""Tests for /obsidian-brainstorm section registration + helpers."""
from __future__ import annotations

from scripts.architect.sections import SECTION_TYPES, _BLOCK_NAMES, _BLOCK_HEADINGS


def test_brainstorm_section_type_present():
    assert SECTION_TYPES["brainstorm"] == "project-brainstorm"


def test_brainstorm_block_names_v1():
    expected = (
        "context",
        "opening-provocations",
        "drilled-explorations",
        "distilled-imps",
        "hypotheses",
        "parked",
        "open-questions",
        "meta-reflection",
        "dependencies",
    )
    assert _BLOCK_NAMES["brainstorm"] == expected


def test_brainstorm_block_headings_registered():
    """All v1 brainstorm block names must have entries in _BLOCK_HEADINGS."""
    new_blocks = [
        "context",
        "opening-provocations",
        "drilled-explorations",
        "distilled-imps",
        "hypotheses",
        "parked",
        "open-questions",
        "meta-reflection",
    ]
    for block in new_blocks:
        assert block in _BLOCK_HEADINGS, f"missing heading for {block}"
    # `dependencies` block reuses existing v3 mapping ("## Dependencies and consumers").
    assert "dependencies" in _BLOCK_HEADINGS
```

- [ ] **Step 2: Append lang.py heading map test**

In `tests/architect/test_lang.py`, append:

```python
def test_heading_map_includes_brainstorm_keys():
    """v1 brainstorm introduces 8 new H2 headings."""
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## Session context": "## 對話脈絡",
        "## Opening provocations": "## 開場 provocations",
        "## Drilled explorations": "## 深挖紀錄",
        "## Distilled improvements": "## 提煉的 Imps",
        "## Hypotheses to validate": "## 待驗證假設",
        "## Parked": "## 暫不討論",
        "## Open questions": "## 仍不清楚",
        "## Meta reflection": "## 自我覆盤",
    }
    for en, zh in required.items():
        assert en in HEADING_MAP, f"missing heading key {en!r}"
        assert HEADING_MAP[en]["zh-TW"] == zh, f"{en} should map to {zh!r}"
        assert HEADING_MAP[en]["en"] == en
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_brainstorm.py tests/architect/test_lang.py::test_heading_map_includes_brainstorm_keys -v`
Expected: 4 FAILs (3 in test_brainstorm.py + 1 in test_lang.py) — missing `brainstorm` key in `SECTION_TYPES` / `_BLOCK_NAMES`; missing new heading mappings.

- [ ] **Step 4: Add `SECTION_TYPES` entry**

In `scripts/architect/sections.py`, find `SECTION_TYPES = { ... }` dict (around line 37). Append BEFORE the closing brace (after the existing `ai-rag` entry):

```python
    # v4.4 — brainstorm (project-level interview)
    "brainstorm": "project-brainstorm",
}
```

- [ ] **Step 5: Add `_BLOCK_NAMES` entry**

In `_BLOCK_NAMES` dict (around line 144-180), append after the existing `ai-rag` entry:

```python
    # v4.4 — brainstorm (9 blocks for the project interview output)
    "brainstorm": (
        "context",
        "opening-provocations",
        "drilled-explorations",
        "distilled-imps",
        "hypotheses",
        "parked",
        "open-questions",
        "meta-reflection",
        "dependencies",
    ),
}
```

- [ ] **Step 6: Add 8 new heading entries in `_BLOCK_HEADINGS`**

In `_BLOCK_HEADINGS` dict (around line 192-238), append after the v4.3 entries:

```python
    # v4.4 brainstorm block headings
    "context": "## Session context",
    "opening-provocations": "## Opening provocations",
    "drilled-explorations": "## Drilled explorations",
    "distilled-imps": "## Distilled improvements",
    "hypotheses": "## Hypotheses to validate",
    "parked": "## Parked",
    "open-questions": "## Open questions",
    "meta-reflection": "## Meta reflection",
```

(Note: `dependencies` block name already maps to `## Dependencies and consumers` from v3 module schema — reuse it.)

- [ ] **Step 7: Add `_preamble_for("brainstorm", lang)` entries**

In `scripts/architect/sections.py` `_preamble_for(section, lang)` function (around line 350), in the zh-TW dict, add after the existing `ai-rag` entry:

```python
            "brainstorm": "本檔是 `/obsidian-brainstorm` session 輸出 — Claude 採訪式 brainstorm,從 vault 全部 project 素材出發,丟出大膽推測 (provocations),引導使用者反應與深挖,蒸餾成 ImprovementItem 與待驗證假設。被 `/obsidian-roadmap` 自動撿走進 backlog。",
```

In the en dict, add the corresponding entry:

```python
            "brainstorm": "Output of an `/obsidian-brainstorm` session — Claude interviews the user, starts from vault project materials, throws bold next-direction provocations, drills via follow-ups, and distills ImprovementItems plus hypotheses-to-validate. Picked up by `/obsidian-roadmap` automatically.",
```

- [ ] **Step 8: Add 8 zh-TW heading mappings in lang.py**

In `scripts/architect/lang.py`, find the end of `HEADING_MAP` dict (right before the closing `}` and `def heading(...)`). Append:

```python
    # v4.4 brainstorm (project interview output)
    "## Session context": {"en": "## Session context", "zh-TW": "## 對話脈絡"},
    "## Opening provocations": {
        "en": "## Opening provocations",
        "zh-TW": "## 開場 provocations",
    },
    "## Drilled explorations": {
        "en": "## Drilled explorations",
        "zh-TW": "## 深挖紀錄",
    },
    "## Distilled improvements": {
        "en": "## Distilled improvements",
        "zh-TW": "## 提煉的 Imps",
    },
    "## Hypotheses to validate": {
        "en": "## Hypotheses to validate",
        "zh-TW": "## 待驗證假設",
    },
    "## Parked": {"en": "## Parked", "zh-TW": "## 暫不討論"},
    "## Open questions": {"en": "## Open questions", "zh-TW": "## 仍不清楚"},
    "## Meta reflection": {"en": "## Meta reflection", "zh-TW": "## 自我覆盤"},
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_brainstorm.py tests/architect/test_lang.py -v`
Expected: 3 PASS in test_brainstorm.py + all existing lang tests PASS + 1 new pass.

- [ ] **Step 10: Run full test suite for no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS (395 prior + 4 new = 399).

- [ ] **Step 11: Commit**

```bash
git add scripts/architect/sections.py scripts/architect/lang.py tests/architect/test_brainstorm.py tests/architect/test_lang.py
git commit -m "$(cat <<'EOF'
feat(architect): register brainstorm section + 9 blocks + 8 zh-TW headings

New SECTION_TYPES["brainstorm"] = "project-brainstorm". _BLOCK_NAMES
defines 9 blocks for project-brainstorm output: context,
opening-provocations, drilled-explorations, distilled-imps, hypotheses,
parked, open-questions, meta-reflection, dependencies.

8 new zh-TW heading mappings (Session context / Opening provocations /
Drilled explorations / Distilled improvements / Hypotheses to validate /
Parked / Open questions / Meta reflection). `dependencies` reuses
existing v3 mapping.

Preamble describes the cross-vault interview lens and roadmap
integration.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Helpers — `parse_hypothesis_block` + `compose_brainstorm_note`

### Task 2: `parse_hypothesis_block` — extract hypothesis fields from markdown

**Files:**
- Modify: `scripts/architect/sections.py` (append near `parse_improvements_block`)
- Modify: `tests/architect/test_brainstorm.py` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/architect/test_brainstorm.py`:

```python
def test_parse_hypothesis_block_extracts_fields():
    """Hypothesis block has H3 entries with fields:
    假設 / 驗證方式 / kill criterion / owner / status."""
    from scripts.architect.sections import parse_hypothesis_block

    body = (
        "### H1: 客服自助 Rich Menu 能降 ticket 量 30%\n"
        "- **假設:** LINE Rich Menu 加 5 個自助 FAQ 入口後,客服 ticket 量在 4 週內降 ≥ 30%\n"
        "- **驗證方式:** 灰度部署到 20% 用戶,4 週後比較對照組 ticket 量\n"
        "- **kill criterion:** 降幅 < 10% 或客戶滿意度同步下降\n"
        "- **owner:** [[people/客服 lead]]\n"
        "- **status:** unvalidated\n"
        "\n"
        "### H2: 統一 embedding provider 後 recall 提升\n"
        "- **假設:** write+read 用同 embedding provider 後,golden-set recall@5 提升 ≥ 15%\n"
        "- **驗證方式:** 跑 evaluation/retrieval golden-set 對比\n"
        "- **kill criterion:** recall@5 變化 < 5%\n"
        "- **owner:** [[people/AI lead]]\n"
        "- **status:** unvalidated\n"
    )
    hyps = parse_hypothesis_block(body)
    assert len(hyps) == 2
    h1 = hyps[0]
    assert h1["title"] == "H1: 客服自助 Rich Menu 能降 ticket 量 30%"
    assert "LINE Rich Menu" in h1["assumption"]
    assert "灰度部署到 20%" in h1["validation"]
    assert "降幅 < 10%" in h1["kill_criterion"]
    assert "客服 lead" in h1["owner"]
    assert h1["status"] == "unvalidated"


def test_parse_hypothesis_block_ignores_entries_missing_required_fields():
    """An H3 missing assumption / validation / kill_criterion is dropped."""
    from scripts.architect.sections import parse_hypothesis_block

    body = (
        "### H1: incomplete (no fields)\n"
        "Just prose, no bullets.\n"
        "\n"
        "### H2: complete\n"
        "- **假設:** A\n"
        "- **驗證方式:** B\n"
        "- **kill criterion:** C\n"
        "- **owner:** D\n"
        "- **status:** unvalidated\n"
    )
    hyps = parse_hypothesis_block(body)
    assert len(hyps) == 1
    assert hyps[0]["title"] == "H2: complete"


def test_parse_hypothesis_block_returns_empty_when_no_h3():
    from scripts.architect.sections import parse_hypothesis_block
    assert parse_hypothesis_block("just paragraph text\nno h3 headings") == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_brainstorm.py -v -k "parse_hypothesis_block"`
Expected: 3 FAILs with `ImportError: cannot import name 'parse_hypothesis_block'`.

- [ ] **Step 3: Implement `parse_hypothesis_block`**

In `scripts/architect/sections.py`, append (near `parse_improvements_block`, around line 1862):

```python
_HYPOTHESIS_TITLE_RE = re.compile(r"^###\s+(.+?)\s*$", re.MULTILINE)
_HYPOTHESIS_FIELD_RE = re.compile(r"^-\s+\*\*(.+?):\*\*\s*(.+)$", re.MULTILINE)
_HYPOTHESIS_FIELD_ALIASES = {
    "assumption": "assumption",
    "假設": "assumption",
    "validation": "validation",
    "驗證方式": "validation",
    "kill criterion": "kill_criterion",
    "kill_criterion": "kill_criterion",
    "owner": "owner",
    "status": "status",
}


def parse_hypothesis_block(body: str) -> list[dict]:
    """Parse a brainstorm hypotheses block into dicts.

    Each H3 entry becomes a dict with fields:
    {title, assumption, validation, kill_criterion, owner, status}.
    Entries missing any of {assumption, validation, kill_criterion} are dropped.
    """
    parts = _HYPOTHESIS_TITLE_RE.split(body)
    if len(parts) < 3:
        return []
    out: list[dict] = []
    for i in range(1, len(parts), 2):
        title = parts[i].strip()
        entry_body = parts[i + 1] if i + 1 < len(parts) else ""
        fields: dict[str, str] = {}
        for m in _HYPOTHESIS_FIELD_RE.finditer(entry_body):
            key = _HYPOTHESIS_FIELD_ALIASES.get(m.group(1).strip().lower())
            if key:
                fields[key] = m.group(2).strip()
        required = {"assumption", "validation", "kill_criterion"}
        if not required.issubset(fields):
            continue
        out.append({
            "title": title,
            "assumption": fields["assumption"],
            "validation": fields["validation"],
            "kill_criterion": fields["kill_criterion"],
            "owner": fields.get("owner", ""),
            "status": fields.get("status", "unvalidated"),
        })
    return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_brainstorm.py -v -k "parse_hypothesis_block"`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_brainstorm.py
git commit -m "$(cat <<'EOF'
feat(architect): parse_hypothesis_block — extract hypothesis fields from brainstorm output

Parser parallels parse_improvements_block but for the brainstorm
hypotheses shape: each H3 has assumption / validation / kill_criterion /
owner / status fields. Entries missing required fields (assumption,
validation, kill_criterion) are dropped. Bilingual field labels: 假設 /
驗證方式 / kill criterion / owner / status work in both zh-TW and en.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: `compose_brainstorm_note` — assemble note with extra frontmatter

**Files:**
- Modify: `scripts/architect/sections.py` (append near `compose_features_note`)
- Modify: `tests/architect/test_brainstorm.py` (append)

- [ ] **Step 1: Write the failing test**

Append to `tests/architect/test_brainstorm.py`:

```python
def test_compose_brainstorm_note_emits_extra_frontmatter():
    """compose_brainstorm_note merges session-specific frontmatter
    (mode / lens-mix / depth / status / counts) before ai-first: true."""
    from scripts.architect.sections import compose_brainstorm_note

    blocks = {n: f"body for {n}" for n in (
        "context", "opening-provocations", "drilled-explorations",
        "distilled-imps", "hypotheses", "parked", "open-questions",
        "meta-reflection", "dependencies",
    )}
    note = compose_brainstorm_note(
        project="P",
        repo_label="local: /tmp/p",
        commit="abc1234",
        signal_sources=["Architecture/*", "Research/*", "board.md"],
        confidence="medium",
        output_lang="zh-TW",
        generated_blocks=blocks,
        mode="generate",
        lens_mix=["gap", "persona", "premortem"],
        depth="medium",
        status="fresh",
        session_duration_min=28,
        provocations_opened=5,
        provocations_drilled=2,
        imps_distilled=3,
        hypotheses_raised=2,
    )
    assert "mode: generate" in note
    assert "depth: medium" in note
    assert "status: fresh" in note
    assert "session-duration-min: 28" in note
    assert "provocations-opened: 5" in note
    assert "provocations-drilled: 2" in note
    assert "imps-distilled: 3" in note
    assert "hypotheses-raised: 2" in note
    # lens-mix is a YAML list
    assert 'lens-mix: ["gap", "persona", "premortem"]' in note
    # Order: extras must come BEFORE `ai-first: true`.
    fm = note.split("---", 2)[1]
    assert fm.index("mode:") < fm.index("ai-first:")
    assert fm.index("hypotheses-raised:") < fm.index("ai-first:")
    # Body contains all 9 blocks via sentinels.
    for name in blocks:
        assert f"<!-- @generated:start {name} -->" in note
        assert f"<!-- @generated:end {name} -->" in note


def test_compose_brainstorm_note_zh_tw_renders_h2_in_zh():
    """When output_lang=zh-TW, the H2 headings for brainstorm blocks come out in zh-TW."""
    from scripts.architect.sections import compose_brainstorm_note

    blocks = {n: f"body" for n in (
        "context", "opening-provocations", "drilled-explorations",
        "distilled-imps", "hypotheses", "parked", "open-questions",
        "meta-reflection", "dependencies",
    )}
    note = compose_brainstorm_note(
        project="P", repo_label="local: /tmp/p", commit="abc",
        signal_sources=["x"], confidence="medium", output_lang="zh-TW",
        generated_blocks=blocks, mode="generate", lens_mix=["gap"],
        depth="quick", status="fresh", session_duration_min=10,
        provocations_opened=4, provocations_drilled=0,
        imps_distilled=0, hypotheses_raised=0,
    )
    assert "## 對話脈絡" in note
    assert "## 開場 provocations" in note
    assert "## 深挖紀錄" in note
    assert "## 提煉的 Imps" in note
    assert "## 待驗證假設" in note
    assert "## 暫不討論" in note
    assert "## 仍不清楚" in note
    assert "## 自我覆盤" in note
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_brainstorm.py -v -k "compose_brainstorm_note"`
Expected: 2 FAILs with `ImportError: cannot import name 'compose_brainstorm_note'`.

- [ ] **Step 3: Implement `compose_brainstorm_note`**

In `scripts/architect/sections.py`, append (near `compose_features_note`):

```python
def compose_brainstorm_note(
    *,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    mode: str,
    lens_mix: list[str],
    depth: str,
    status: str,
    session_duration_min: int,
    provocations_opened: int,
    provocations_drilled: int,
    imps_distilled: int,
    hypotheses_raised: int,
) -> str:
    """Wrap compose_note(section='brainstorm', ...) and merge session-specific
    extra frontmatter fields BEFORE `ai-first: true`.

    Fields injected: mode, lens-mix, depth, status, session-duration-min,
    provocations-opened, provocations-drilled, imps-distilled, hypotheses-raised.
    """
    note = compose_note(
        section="brainstorm",
        project=project,
        repo_label=repo_label,
        commit=commit,
        signal_sources=signal_sources,
        confidence=confidence,
        output_lang=output_lang,
        generated_blocks=generated_blocks,
    )
    lens_mix_yaml = json.dumps(lens_mix, ensure_ascii=False)
    extra_fm = (
        f"mode: {mode}\n"
        f"lens-mix: {lens_mix_yaml}\n"
        f"depth: {depth}\n"
        f"status: {status}\n"
        f"session-duration-min: {session_duration_min}\n"
        f"provocations-opened: {provocations_opened}\n"
        f"provocations-drilled: {provocations_drilled}\n"
        f"imps-distilled: {imps_distilled}\n"
        f"hypotheses-raised: {hypotheses_raised}\n"
    )
    return note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
```

(`json` is already imported at the top of sections.py.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_brainstorm.py -v`
Expected: All PASS (3 from registration + 3 from parse + 2 from compose = 8).

- [ ] **Step 5: Run full test suite for no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_brainstorm.py
git commit -m "$(cat <<'EOF'
feat(architect): compose_brainstorm_note with session-specific extra frontmatter

Wraps compose_note(section="brainstorm", ...) and injects 9 extra
frontmatter fields before `ai-first: true`: mode, lens-mix (YAML list),
depth, status, session-duration-min, provocations-opened/drilled,
imps-distilled, hypotheses-raised. Same pattern as compose_features_note.

zh-TW heading rendering verified for all 8 brainstorm-specific H2s.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: Roadmap integration

### Task 4: `detect_candidates` walks `Projects/<P>/Brainstorms/` for `distilled-imps`

**Files:**
- Modify: `scripts/roadmap/candidates.py`
- Modify: `tests/roadmap/test_candidates.py`

- [ ] **Step 1: Write the failing test**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_detect_candidates_walks_brainstorms_distilled_imps(tmp_path):
    """detect_candidates picks up `distilled-imps` block from
    Projects/<P>/Brainstorms/*.md."""
    from scripts.roadmap.candidates import detect_candidates

    (tmp_path / "Architecture").mkdir()
    bs = tmp_path / "Brainstorms"
    bs.mkdir()
    (bs / "2026-05-29-vision-q3.md").write_text(
        "---\ntype: project-brainstorm\nstatus: fresh\n---\n\n"
        "## 提煉的 Imps\n"
        "<!-- @generated:start distilled-imps -->\n"
        "### Imp 1: Multi-channel inbox 試做\n"
        "- **為什麼:** 客戶要求 WhatsApp 開始多\n"
        "- **證據:** [[Architecture/features#missing-features]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 客戶轉投競品\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end distilled-imps -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    multichannel = next((c for c in cands if "Multi-channel" in c.title), None)
    assert multichannel is not None, (
        f"brainstorm distilled-imp not picked up; cands={[c.title for c in cands]}"
    )
    # Confidence stated → priority normal.
    assert multichannel.priority == "normal"


def test_detect_candidates_brainstorm_hypothesis_confidence_lowers_priority(tmp_path):
    """When a distilled-imp has Confidence: hypothesis or speculation,
    priority drops to low."""
    from scripts.roadmap.candidates import detect_candidates

    (tmp_path / "Architecture").mkdir()
    bs = tmp_path / "Brainstorms"
    bs.mkdir()
    (bs / "2026-05-29-speculative.md").write_text(
        "---\ntype: project-brainstorm\nstatus: fresh\n---\n\n"
        "## 提煉的 Imps\n"
        "<!-- @generated:start distilled-imps -->\n"
        "### Imp 1: 客戶端 LINE Rich Menu\n"
        "- **為什麼:** 自助查詢可分流客服 load\n"
        "- **證據:** [[Architecture/personas#LINE 終端使用者]]\n"
        "- **Effort:** L\n"
        "- **未做的風險:** 客服 load 線性成長\n"
        "- **Confidence:** speculation\n"
        "<!-- @generated:end distilled-imps -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    rich = next((c for c in cands if "Rich Menu" in c.title), None)
    assert rich is not None
    assert rich.priority == "low", (
        f"speculation confidence should lower priority to low; got {rich.priority}"
    )
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "brainstorms_distilled or brainstorm_hypothesis_confidence"`
Expected: 2 FAILs — candidates not detected (brainstorms folder not walked yet).

- [ ] **Step 3: Add a helper `_extract_brainstorm_candidates`**

In `scripts/roadmap/candidates.py`, append a new helper after `_extract_ai_cross_flow_candidates` (around line 277):

```python
def _extract_brainstorm_candidates(project_root: Path) -> list[Candidate]:
    """Extract v4.4 candidates from Projects/<P>/Brainstorms/*.md.

    - `distilled-imps` block → `brainstorm-imp` candidates
      (priority `low` for Confidence speculation/hypothesis, `normal` for stated)
    - `hypotheses` block → `brainstorm-hypothesis` candidates (always priority `low`)

    Skips brainstorm files whose frontmatter `status: actioned`.
    """
    bs_dir = project_root / "Brainstorms"
    if not bs_dir.is_dir():
        return []
    out: list[Candidate] = []
    for bs_path in sorted(bs_dir.glob("*.md")):
        try:
            text = bs_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if _brainstorm_status_actioned(text):
            continue
        rel = bs_path.relative_to(project_root).as_posix().replace(".md", "")
        imp_body = _extract_generated_block(text, "distilled-imps")
        if imp_body:
            for entry in _parse_feature_imp_entries(imp_body):
                priority = (
                    "low"
                    if entry["confidence"].lower() in ("speculation", "hypothesis")
                    else "normal"
                )
                cand = _candidate_from_feature_imp(
                    entry,
                    rel=rel,
                    block="distilled-imps",
                    kind="brainstorm-imp",
                    priority=priority,
                )
                cand.source = f"Brainstorms/{bs_path.name}#distilled-imps"
                out.append(cand)
        # hypotheses block — separate candidate type
        hyp_body = _extract_generated_block(text, "hypotheses")
        if hyp_body:
            from scripts.architect.sections import parse_hypothesis_block

            for hyp in parse_hypothesis_block(hyp_body):
                cand = Candidate(
                    title=hyp["title"],
                    why=hyp["assumption"],
                    evidence=[],
                    effort="?",
                    risk_if_not_done=hyp["kill_criterion"],
                    confidence="hypothesis",
                    kind="brainstorm-hypothesis",
                    priority="low",
                )
                cand.source = f"Brainstorms/{bs_path.name}#hypotheses"
                out.append(cand)
    return out


_FRONTMATTER_STATUS_RE = re.compile(r"^status:\s*(\S+)\s*$", re.MULTILINE)


def _brainstorm_status_actioned(text: str) -> bool:
    """Return True iff frontmatter contains `status: actioned`.

    Reads only the first frontmatter block (between two `---` lines).
    """
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return False
    fm = m.group(1)
    sm = _FRONTMATTER_STATUS_RE.search(fm)
    return bool(sm and sm.group(1).strip() == "actioned")
```

- [ ] **Step 4: Wire helper into `detect_candidates`**

In `scripts/roadmap/candidates.py`, find the `detect_candidates` function (around line 54). At the end (BEFORE the final `return _dedup(_dedup_candidates(out))` call), add:

```python
    # v4.4 — brainstorm session outputs feed roadmap signal.
    out.extend(_extract_brainstorm_candidates(project_root))

    return _dedup(_dedup_candidates(out))
```

(Adjust placement so the addition is inside the function body and before the return.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS (existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): detect_candidates walks Projects/<P>/Brainstorms/ (v4.4)

Two new candidate buckets:
- distilled-imps block → brainstorm-imp candidate. Priority `low` when
  Confidence speculation/hypothesis; `normal` when stated.
- hypotheses block → brainstorm-hypothesis candidate (always low).

Skips brainstorm files whose frontmatter has `status: actioned` (already
graduated to a T-NNN task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: `status: actioned` brainstorms are skipped

**Files:**
- Modify: `tests/roadmap/test_candidates.py` (append)

- [ ] **Step 1: Write the test**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_detect_candidates_brainstorm_actioned_status_skipped(tmp_path):
    """A brainstorm file with frontmatter `status: actioned` is NOT walked."""
    from scripts.roadmap.candidates import detect_candidates

    (tmp_path / "Architecture").mkdir()
    bs = tmp_path / "Brainstorms"
    bs.mkdir()
    (bs / "2026-04-01-already-done.md").write_text(
        "---\ntype: project-brainstorm\nstatus: actioned\n---\n\n"
        "## 提煉的 Imps\n"
        "<!-- @generated:start distilled-imps -->\n"
        "### Imp 1: Already graduated\n"
        "- **為什麼:** done\n"
        "- **證據:** [[x]]\n"
        "- **Effort:** S\n"
        "- **未做的風險:** none\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end distilled-imps -->\n",
        encoding="utf-8",
    )
    # Also add a fresh one to confirm the WALK still works for non-actioned files.
    (bs / "2026-05-29-fresh.md").write_text(
        "---\ntype: project-brainstorm\nstatus: fresh\n---\n\n"
        "## 提煉的 Imps\n"
        "<!-- @generated:start distilled-imps -->\n"
        "### Imp 1: Still in flight\n"
        "- **為什麼:** not done\n"
        "- **證據:** [[y]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** drift\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end distilled-imps -->\n",
        encoding="utf-8",
    )

    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    assert "Imp 1: Still in flight" in titles or "Still in flight" in titles
    assert not any("Already graduated" in t for t in titles), (
        f"actioned brainstorm should not be picked up; got {titles}"
    )
```

- [ ] **Step 2: Run the test**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "actioned_status_skipped"`
Expected: PASS (Task 4's `_brainstorm_status_actioned` helper already implements this).

- [ ] **Step 3: Commit**

```bash
git add tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
test(roadmap): brainstorm status=actioned is skipped while fresh sessions walk

Confirms the status-aware skip logic added in Task 4 — once a brainstorm
session's improvements have been graduated to a T-NNN task, the owner
sets frontmatter `status: actioned` and the candidate detector no longer
re-picks the same imps in subsequent roadmap runs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 6: Dedup pass — `Brainstorms/` source wins over architecture sources

**Files:**
- Modify: `scripts/roadmap/candidates.py` (find `_dedup_candidates`)
- Modify: `tests/roadmap/test_candidates.py` (append)

- [ ] **Step 1: Inspect existing `_dedup_candidates`**

```bash
grep -n "_dedup_candidates\b" /Users/leric/Desktop/code/obsidian-second-brain/scripts/roadmap/candidates.py | head -5
```

Read the existing implementation (around the line reported).

- [ ] **Step 2: Write the failing test**

Append to `tests/roadmap/test_candidates.py`:

```python
def test_detect_candidates_dedup_brainstorm_beats_architecture(tmp_path):
    """When a brainstorm-imp and an architecture-imp share an Evidence wikilink,
    the brainstorm-imp wins (user-confirmed > Claude-inferred)."""
    from scripts.roadmap.candidates import detect_candidates

    arch = tmp_path / "Architecture"
    arch.mkdir()
    bs = tmp_path / "Brainstorms"
    bs.mkdir()

    # Architecture-side Imp citing the same Evidence wikilink.
    (arch / "overview.md").write_text(
        "---\ntype: architecture-overview\n---\n\n"
        "## 跨模組改進機會\n"
        "<!-- @generated:start cross-cutting-improvements -->\n"
        "### Imp 1: Streaming reply (architecture inferred)\n"
        "- **為什麼:** llm.invoke 改 stream\n"
        "- **證據:** [[Architecture/modules/backend]] | [[Architecture/modules/frontend]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** UX 落後\n"
        "- **Confidence:** medium\n"
        "<!-- @generated:end cross-cutting-improvements -->\n",
        encoding="utf-8",
    )
    # Brainstorm-side Imp sharing the same Evidence wikilink — should win.
    (bs / "2026-05-29-streaming.md").write_text(
        "---\ntype: project-brainstorm\nstatus: fresh\n---\n\n"
        "## 提煉的 Imps\n"
        "<!-- @generated:start distilled-imps -->\n"
        "### Imp 1: Streaming reply (user-confirmed P0)\n"
        "- **為什麼:** owner Q3 confirm to ship\n"
        "- **證據:** [[Architecture/modules/backend]] | [[Architecture/modules/frontend]]\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 競品先上\n"
        "- **Confidence:** stated\n"
        "<!-- @generated:end distilled-imps -->\n",
        encoding="utf-8",
    )
    cands = detect_candidates(tmp_path)
    titles = [c.title for c in cands]
    # Brainstorm-imp must be present.
    assert any("user-confirmed P0" in t for t in titles), f"got {titles}"
    # Architecture-imp citing same evidence must be deduped out.
    assert not any("architecture inferred" in t for t in titles), (
        f"architecture imp with overlapping evidence should be deduped; got {titles}"
    )
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/roadmap/test_candidates.py -v -k "dedup_brainstorm_beats_architecture"`
Expected: FAIL — both candidates present in result.

- [ ] **Step 4: Inspect current dedup logic to find where to extend**

Read around the `_dedup_candidates` function. The current v4.2 dedup logic prefers `features.md` source. Extend it to also prefer `Brainstorms/` source over everything else.

- [ ] **Step 5: Modify the priority list in `_dedup_candidates`**

In `scripts/roadmap/candidates.py`, find the source-priority list used by `_dedup_candidates` (it'll be a regex / substring match on the candidate's `source` field). Update the priority so `Brainstorms/` beats `features.md` beats other architecture sources. The change typically lives in a helper like `_source_priority(source: str) -> int`. Concrete edit:

```python
def _source_priority(source: str) -> int:
    """Higher = wins in dedup tiebreak."""
    if not source:
        return 0
    if "Brainstorms/" in source:
        return 30   # v4.4 — user-confirmed beats everything
    if "features.md" in source:
        return 20   # v4.2 — PM lens beats architecture-inferred
    return 10       # default: architecture / module / decisions / etc.
```

(If the function name differs in the actual code, adapt — the principle is `Brainstorms/` source > `features.md` > others.)

- [ ] **Step 6: Run test to verify it passes**

Run: `uv run pytest tests/roadmap/test_candidates.py -v`
Expected: All PASS (existing + 3 new from Tasks 4-6).

- [ ] **Step 7: Run full suite for no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/roadmap/candidates.py tests/roadmap/test_candidates.py
git commit -m "$(cat <<'EOF'
feat(roadmap): dedup pass — Brainstorms/ source beats architecture source

Extends v4.2 dedup priority ladder. When two candidates share an
Evidence wikilink, the priority is now:
  Brainstorms/ (user-confirmed) > features.md (PM lens) > architecture (Claude-inferred)

Rationale: brainstorm sessions are explicit user judgment about
priority — they beat Claude's inferred Imps that just happen to cite
the same module. Prevents Roadmap.md from listing the same concern
twice with different framings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: Command body + ai-first rules + announcement

### Task 7: Write `commands/obsidian-brainstorm.md`

**Files:**
- Create: `commands/obsidian-brainstorm.md`

- [ ] **Step 1: Create the slash command file**

Create `commands/obsidian-brainstorm.md`:

````markdown
---
description: Interview-style brainstorm — Claude reads vault, opens with 4-6 bold next-direction provocations, drills via follow-ups, distills into a session file feeding /obsidian-roadmap
argument-hint: <project-name>
category: thinking
triggers_en: ["brainstorm project", "obsidian brainstorm", "what should I work on", "stuck on next step"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-brainstorm $ARGUMENTS`:

The argument is `<project-name>` (folder under `Projects/`). Optional flags:
- `--topic="<seed>"` — narrow the provocation focus (e.g. `--topic="客戶流失"`)
- `--lens=gap|persona|trend|premortem|mix` — provocation flavor; default `mix` (1-2 each, 4-6 total)
- `--depth=quick|medium|deep` — `quick` = open + react only; `medium` = drill 1-2 (default); `deep` = drill all
- `--lang=zh-TW|en` — override vault `_CLAUDE.md output-lang`
- `--research-window-days=N` — read Research/ window, default 30

If `<project-name>` is omitted and `pwd` is inside `Projects/<P>/`, default to `<P>`. Otherwise ASK the user which project.

## Phase 0: Pre-flight

- Confirm vault root has `_CLAUDE.md`. If no, abort with "Run /obsidian-init first."
- Confirm `Projects/<P>/` exists. If no, abort with "Run /obsidian-project <P> first."
- Ensure `Projects/<P>/Brainstorms/` exists (mkdir if needed).
- Resolve `output_lang`:
  ```bash
  uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
  ```

## Phase 1: Vault scan (deterministic, no LLM)

Read the following files and build a `BrainstormContext` dict (see spec for the exact JSON shape):

1. `Projects/<P>/Architecture/overview.md` — extract `## 跨模組改進機會` block via `_extract_generated_block(text, "cross-cutting-improvements")`. Parse via `parse_improvements_block`. Lens-hint = `gap`.
2. `Projects/<P>/Architecture/features.md` — extract `## 改進機會` AND `## 可加 features` blocks. Lens-hint = `gap` (improvements) + `persona` (missing-features).
3. `Projects/<P>/Architecture/ai-flows/*.md` (each file) — extract `## 改進機會` block.
4. `Projects/<P>/Architecture/personas.md` — read first 4 KB; extract each persona's `**主要痛點:**` bullets. Lens-hint = `persona`.
5. `Projects/<P>/Architecture/decisions.md` — extract `## 已知限制` block.
6. `Projects/<P>/Research/*.md` — files with `mtime` within `--research-window-days`. Per file: frontmatter `title` + first non-blank paragraph + `tags` + `date`. Lens-hint = `trend`.
7. `Projects/<P>/board.md` — `## 待辦` block titles (these are already in flight — avoid recommending them).
8. `Logs/YYYY-MM-DD.md` last 7 days — entries containing `[[<P>]]` wikilink (recent owner focus).
9. `Projects/<P>/Brainstorms/*.md` past sessions — `## 仍不清楚` + `## 暫不討論` blocks. **Count repeat parked titles** — if same title (fuzzy match) appears ≥3 times across past sessions, flag `repeat_count: N` in context.

If any of the Architecture/* files is missing, log a warning (e.g. "no Architecture/personas.md — persona-lens provocations may be weaker") but continue.

## Phase 2: Opening provocations (LLM, single message)

Using `BrainstormContext` + `--lens` recipe + `--topic` seed (if provided), produce **4-6 provocations** in a single chat message. Each provocation MUST include:

- **Title** (≤30 chars)
- **為什麼 / Why** (1-2 sentences)
- **證據 / Evidence** — wikilink to vault file, OR `(speculation, no vault evidence)` literal when Lens = `premortem` and pure reasoning
- **Lens** — one of `gap` / `persona` / `trend` / `premortem`
- **Confidence** — one of `stated` (vault explicit) / `hypothesis` (vault + reasoning jump) / `speculation` (pure reasoning)

**Lens recipe defaults (`--lens=mix`):** 1-2 gap + 1-2 persona + 1-2 trend + 1 premortem, total 4-6. If Research/ is empty, replace trend with extra gap.

**Repeat-parked rule:** if `BrainstormContext.past_brainstorms` shows a topic with `repeat_count ≥ 3`, prepend `🔁 第 N 次出現` to that provocation's title and bring it up as one of the slots (signals owner "this keeps being deferred").

**Voice constraints:**
- **Bold** — speculate user-novel directions, not just restate existing Imps
- **No filler** — banned phrases: "這個值得思考", "我覺得很有趣", "可能不錯"
- **No invented wikilinks** — only cite vault files that actually exist (Phase 1 saw them)

Format the message with P1-P6 labels so the user can reference by number.

## Phase 3: User reaction (chat)

Wait for user response. Parse one of:

- `drill P2, P5` — mark P2 + P5 for deep dive (Phase 4)
- `kill P1` — record killed
- `park P3 P4` — record parked (will accumulate for future repeat detection)
- `P6 改成 X` — rewrite a provocation; treat the rewritten one as drilled
- `none` — user has no appetite; skip Phase 4, write a minimal note with all provocations recorded

Collect into `drilled[]`, `killed[]`, `parked[]`, `rewritten{}` lists for Phase 5 writeback.

## Phase 4: Drill (LLM, multi-turn)

For each drilled provocation, ask **2-4 follow-up questions, ONE AT A TIME** from the pool below (or improvise based on the conversation):

- "If this shipped, what would success look like in 1 month? 6 months?"
- "What's the riskiest assumption?"
- "Who do you steal time/budget from to do this?"
- "What's the smallest test that would disprove it?" (drives hypothesis output)
- "Who would push back? What's their valid concern?"
- "3 months out, customer hasn't reacted — can you still hold?"
- "Conflicts with X on the board — how do you sequence?"

**Quote capture rule:** When the user answers, identify which sentence is a **verbatim quote** worth preserving (use `> ` in the writeup) and which content can be paraphrased.

Apply `--depth` rule:
- `quick` — skip Phase 4 entirely
- `medium` (default) — drill 1-2 provocations (those the user marked)
- `deep` — drill all marked, take as long as needed

## Phase 5: Distill + write file (LLM)

For each drilled provocation, distill into:

- **0-2 ImprovementItems** for `distilled-imps` block (`為什麼 / 證據 / Effort / 未做的風險 / Confidence`)
- **0-2 hypotheses** for `hypotheses` block (`假設 / 驗證方式 / kill criterion / owner / status`)
- **Open questions** the user couldn't answer → `open-questions` block

Compose via `scripts.architect.sections.compose_brainstorm_note`. Slug for filename comes from session theme: ascii-lowercase-hyphen of the session's central topic (e.g. `vision-q3`, `customer-churn`, `embedding-alignment`).

Write to `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`.

Frontmatter `confidence` field is `high` when `provocations_drilled >= 2`, otherwise `medium`.

## Phase 6: Hub + activity log

- Idempotent update of `Projects/<P>/<P>.md` `## Brainstorms` block (create sentinel `<!-- @generated:start brainstorms-section -->` if absent). Content:
  ```markdown
  - 最近 session: [[Brainstorms/YYYY-MM-DD-<slug>]] (N imps + M hypotheses)
  - 全部 sessions: [[Brainstorms/]] folder
  - 新 session: `/obsidian-brainstorm <P>`
  - 餵 Roadmap: `/obsidian-roadmap <P>` (自動拾取 status≠actioned 的 brainstorms)
  ```
- Append to today's `Logs/YYYY-MM-DD.md ## Activity`:
  ```
  **HH:MM** — brainstorm | <P> — <slug> — N imps + M hypotheses drilled
  ```

If `Logs/YYYY-MM-DD.md` doesn't exist, create with the standard daily frontmatter (`type: daily`, `date: YYYY-MM-DD`, `ai-first: true`, `tags: [daily]`, `## 給未來 Claude`, `## Activity` headings).

---

**AI-first rule:** Every note created by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus the brainstorm-specific fields documented in the schema), recency markers per external claim, mandatory `[[wikilinks]]` for every persona/module/research note referenced, sources preserved verbatim, confidence levels mandatory.

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag as a single-run override. All prose in chosen language; code identifiers, paths, function names, env vars, and wikilink filename segments remain English regardless.
````

- [ ] **Step 2: Verify slash command parses**

The slash command body is markdown — there's nothing to test programmatically. But rebuild adapters to confirm:

Run: `bash scripts/build.sh`
Expected: 4 platform adapters build successfully.

- [ ] **Step 3: Commit**

```bash
git add commands/obsidian-brainstorm.md
git commit -m "$(cat <<'EOF'
feat(commands): /obsidian-brainstorm — interview-style provocation + distill workflow

New slash command for "I'm stuck on next step" sessions. Claude:
1. Reads Projects/<P>/Architecture/* + features + ai-flows + personas +
   decisions + Research (within window) + board + recent Logs + past
   brainstorms
2. Opens with 4-6 bold provocations across lens mix
   (gap / persona / trend / premortem), each with Evidence wikilink +
   Confidence (stated/hypothesis/speculation)
3. User reacts (drill / kill / park / rewrite)
4. Claude drills marked provocations via 2-4 follow-ups each
5. Distills into Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md with
   9 @generated blocks
6. Updates hub `## Brainstorms` block + today's activity log

Picked up automatically by /obsidian-roadmap (Phase C earlier in this
plan wires the candidate detector).

Flags: --topic / --lens=gap|persona|trend|premortem|mix / --depth=quick|medium|deep
       / --lang / --research-window-days

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `project-brainstorm` schema in ai-first-rules.md

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Locate insertion point**

```bash
grep -n "architecture-ai-rag\|architecture-ai-memory\|project-brainstorm" /Users/leric/Desktop/code/obsidian-second-brain/references/ai-first-rules.md | head -5
```

- [ ] **Step 2: Add the schema entry**

Insert after the `architecture-ai-rag` section in `references/ai-first-rules.md`:

````markdown
### `project-brainstorm` (v4.4 — `/obsidian-brainstorm` session output)

**File:** `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`

**Frontmatter:**
```yaml
type: project-brainstorm
date: YYYY-MM-DD
project: "[[<project-name>]]"
mode: generate                       # generate (v1) | sharpen (future)
lens-mix: ["gap", "persona", "trend", "premortem"]
depth: medium                        # quick | medium | deep
status: fresh                        # fresh | reviewed | actioned (owner-set)
session-duration-min: 28
provocations-opened: 5
provocations-drilled: 2
imps-distilled: 3
hypotheses-raised: 2
related: ["[[Architecture/overview]]", "[[Architecture/features]]"]
sources: ["Architecture/*", "Research/*", "board.md", "recent Logs"]
confidence: medium                   # high when drilled ≥ 2; medium otherwise
lang: zh-TW
tags: [brainstorm, project]
ai-first: true
```

**Body blocks** (9 `@generated` sentinels):
1. `context` — `## 對話脈絡` / `## Session context`
2. `opening-provocations` — `## 開場 provocations` / `## Opening provocations` (ALL 4-6 preserved with `使用者反應: drilled|killed|parked` annotation)
3. `drilled-explorations` — `## 深挖紀錄` / `## Drilled explorations` (Claude's follow-up Qs + user's verbatim quotes via `> ` blockquote)
4. `distilled-imps` — `## 提煉的 Imps` / `## Distilled improvements` (ImprovementItem shape — fed into `/obsidian-roadmap`)
5. `hypotheses` — `## 待驗證假設` / `## Hypotheses to validate` (`假設 / 驗證方式 / kill criterion / owner / status`)
6. `parked` — `## 暫不討論` / `## Parked` (with `🔁 第 N 次出現` flag when repeated)
7. `open-questions` — `## 仍不清楚` / `## Open questions`
8. `meta-reflection` — `## 自我覆盤` / `## Meta reflection`
9. `dependencies` — wikilinks only

**Voice constraints:**
- NO invention of vault evidence. Every Evidence wikilink must point to a real vault file or be marked `(speculation, no vault evidence)`.
- Preserve user's verbatim quotes via `> ` blockquote; paraphrase other content.
- ALL killed / parked provocations stay in `opening-provocations` (don't delete) — preserves history trail.

**Status lifecycle (owner-driven):**
- `fresh` (default after session) — candidates fed into next `/obsidian-roadmap`
- `reviewed` — owner has read but not yet decided
- `actioned` — improvements graduated to T-NNN tasks; detector skips this file

**Roadmap pickup:**
- `distilled-imps` → `brainstorm-imp` candidates (priority `normal` for `stated`, `low` for `hypothesis`/`speculation`)
- `hypotheses` → `brainstorm-hypothesis` candidates (always `low`)
- Dedup: `Brainstorms/` source beats `features.md` beats architecture-inferred sources
````

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "$(cat <<'EOF'
docs(ai-first-rules): project-brainstorm schema (v4.4)

Defines the /obsidian-brainstorm session output schema: 9 @generated
blocks, voice constraints (no invention, verbatim quotes via `> `,
preserve killed/parked trail), status lifecycle (fresh / reviewed /
actioned), and roadmap pickup rules.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 9: SKILL.md + README.md + CHANGELOG.md announcement

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md**

Find the thinking-tools layer section in `SKILL.md` (search for "Thinking tools" or similar). Insert this entry in the layer's command list (placement: after `/obsidian-challenge` if present):

```markdown
- `/obsidian-brainstorm` — 卡住、不知道下一步該做什麼時,interview-style brainstorm。Claude 讀整個 vault(Architecture/* + features + ai-flows + personas + decisions + Research + board + 最近 Logs + 過去 brainstorms)後,丟出 4-6 個大膽的下個方向(混 gap / persona / trend / premortem lens),使用者反應後深挖,蒸餾成 ImprovementItem + 待驗證假設,寫進 `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`,自動被 `/obsidian-roadmap` 撿走。Flags: `--topic` / `--lens` / `--depth=quick|medium|deep` / `--research-window-days`。
```

- [ ] **Step 2: Update README.md command table**

In `README.md`, find the command table. Insert a row for `/obsidian-brainstorm`:

```markdown
| `/obsidian-brainstorm` | 卡住、不知道下一步該做什麼 → Claude 訪談式 brainstorm,丟 4-6 個大膽方向,使用者反應後深挖,蒸餾成 roadmap 候選 |
```

(Place after `/obsidian-challenge` or in the thinking-tools cluster — match the table's existing organization.)

- [ ] **Step 3: Update CHANGELOG.md**

Append to the `## [Unreleased]` section:

```markdown
- `/obsidian-brainstorm` — new slash command for "stuck on next step"
  sessions. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-brainstorm-design.md`.
  Claude reads vault (Architecture/* + features + ai-flows + personas +
  decisions + Research + board + recent Logs + past brainstorms) and
  opens with 4-6 bold provocations (gap / persona / trend / premortem
  lens). User reacts (drill / kill / park / rewrite); Claude drills via
  follow-ups. Output: `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`
  with 9 @generated blocks (context, opening-provocations,
  drilled-explorations, distilled-imps, hypotheses, parked,
  open-questions, meta-reflection, dependencies). `/obsidian-roadmap`
  picks up `distilled-imps` + `hypotheses` blocks automatically; new
  dedup rule prefers Brainstorms/ source over features.md and
  architecture-inferred sources.

  New helpers: `parse_hypothesis_block` and `compose_brainstorm_note`
  in `scripts/architect/sections.py`. 8 new heading mappings in
  `scripts/architect/lang.py`. Roadmap candidate detector extension
  in `scripts/roadmap/candidates.py:_extract_brainstorm_candidates`.
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+readme+changelog): /obsidian-brainstorm command announcement (v4.4)

SKILL.md gains the new command in the thinking-tools layer; README's
command table mentions the interview-style brainstorm; CHANGELOG
Unreleased lists all the additions (parse_hypothesis_block,
compose_brainstorm_note, lang headings, roadmap candidate walk).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Acceptance smoke

### Task 10: Verify Phase 1 vault reading works on langlive-line-oa

**Files:**
- No code changes. Real-vault smoke against `Projects/langlive-line-oa/`.

The full conversational `/obsidian-brainstorm` command can't be smoke-tested in this plan (it requires a live chat with the user). But Phase 1 (Vault scan, deterministic) can be — we just verify the helper functions correctly extract the BrainstormContext signals from langlive's vault state.

- [ ] **Step 1: Run a Python one-liner that exercises Phase 1 readers**

```bash
uv run python -c "
from pathlib import Path
from scripts.architect.sections import parse_improvements_block

vault = Path('/Users/leric/Documents/SecondBrain')
proj = vault / 'Projects/langlive-line-oa'
arch = proj / 'Architecture'

# Architecture cross-cutting improvements
overview_text = (arch / 'overview.md').read_text(encoding='utf-8')
start = '<!-- @generated:start cross-cutting-improvements -->'
end = '<!-- @generated:end cross-cutting-improvements -->'
s = overview_text.find(start)
e = overview_text.find(end, s)
imp_body = overview_text[s + len(start):e].strip() if s != -1 else ''
arch_imps = parse_improvements_block(imp_body)
print(f'Architecture cross-cutting imps detected: {len(arch_imps)}')
for imp in arch_imps[:3]:
    print(f'  - {imp.title!r} (Confidence: {imp.confidence})')

# personas pain hints
personas_text = (arch / 'personas.md').read_text(encoding='utf-8')[:4000]
import re
pains = re.findall(r'\*\*主要痛點:\*\*\n((?:\s*-\s+.+\n?)+)', personas_text)
print(f'Personas with 主要痛點 section: {len(pains)}')

# Research files (window 30 days)
research = proj / 'Research'
recent = []
import time
cutoff = time.time() - 30 * 86400
if research.is_dir():
    for f in research.rglob('*.md'):
        if f.stat().st_mtime > cutoff:
            recent.append(f.name)
print(f'Recent research files: {len(recent)} ({recent[:3]})')

# Past brainstorms
bs_dir = proj / 'Brainstorms'
past = list(bs_dir.glob('*.md')) if bs_dir.is_dir() else []
print(f'Past brainstorms: {len(past)}')
"
```

Expected output:
- `Architecture cross-cutting imps detected: 5` (langlive overview has 5 Imps in cross-cutting block)
- `Personas with 主要痛點 section: ≥ 3` (multiple personas have pain bullets)
- `Recent research files: 0` (langlive Research/ is currently empty)
- `Past brainstorms: 0` (no prior sessions yet — first run)

If any of these returns unexpected counts, that's a signal to investigate (langlive vault may have shifted).

- [ ] **Step 2: Run full test suite to confirm nothing else broke**

Run: `uv run pytest tests/ -q`
Expected: All PASS (395 prior + 13 new from this plan = 408).

- [ ] **Step 3: Run all 4 platform adapter builds**

Run: `bash scripts/build.sh`
Expected: 4 platform builds complete successfully (claude-code, codex-cli, gemini-cli, opencode).

- [ ] **Step 4: No commit needed — acceptance only**

If any of the above produces unexpected output, write a `## Blocker` note at the top of this plan file with the actual output and stop. Otherwise mark Task 10 complete and proceed to print `ALL TASKS COMPLETE`.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal | Tasks 1-9 (section + helpers + roadmap + command + docs all needed for goal to land) |
| Non-goals | Implicit — no automation written |
| Frame (command name + flags) | Task 7 (command body) |
| Lens definitions (gap/persona/trend/premortem) | Task 7 (command body Phase 2) |
| Phase 0 pre-flight | Task 7 |
| Phase 1 vault scan + BrainstormContext shape | Task 7 + Task 10 smoke |
| Phase 2 opening provocations | Task 7 |
| Phase 3 user reaction syntax | Task 7 |
| Phase 4 drill follow-ups + quote capture | Task 7 |
| Phase 5 distill + write | Tasks 1-3 (helpers) + Task 7 (command invocation) |
| Phase 6 hub + log update | Task 7 |
| Output schema 9 blocks | Task 1 (register), Task 3 (compose) |
| Frontmatter extra fields | Task 3 (compose_brainstorm_note tests) |
| `parse_hypothesis_block` | Task 2 |
| `compose_brainstorm_note` | Task 3 |
| Roadmap integration (distilled-imps + hypotheses) | Tasks 4-5 |
| Dedup priority (Brainstorms > features > architecture) | Task 6 |
| Status lifecycle (fresh/reviewed/actioned) | Task 5 (actioned skip) |
| ai-first-rules schema | Task 8 |
| SKILL.md / README.md / CHANGELOG.md announcement | Task 9 |
| Repeat-parked detection (≥3 times) | Task 7 (Phase 1 of command body — read past brainstorms `parked` titles, fuzzy match) |
| Graduation flow (4 paths) | Task 7 + Task 8 (documented) |
| Test coverage 11 items from spec | Distributed across Tasks 1, 2, 3, 4, 5, 6 (8 unit + 3 integration; Phase 1 smoke = Task 10) |
| Out-of-scope items (sharpen mode, multi-project, auto-trigger) | Frontmatter `mode: generate` allows future expansion without schema bump |
