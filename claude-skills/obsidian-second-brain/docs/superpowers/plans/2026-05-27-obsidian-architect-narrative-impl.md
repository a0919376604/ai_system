# obsidian-architect 敘事化升級 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 擴充 `/obsidian-architect` 為敘事化輸出 — 在既有 manifest/module pipeline 之上加 5 個 narrative section (features/roadmap/decisions/future/api-surface)、MOC 化的 overview、可選 function-level 層,並支援 vault 全域繁中輸出。

**Architecture:** Phase 1 scanner 擴充 (新增 6 個 deterministic 偵測器:README/CHANGELOG/TODO/ADR/stack/API-surface)。新增 Phase 3.5 (section synthesizer) 介於 module 跟 overview 之間,每個 section 一個獨立 signal-hash + sentinel-aware 寫入。Lockfile v2 加 `sections`、`functions`、`lang` 欄位;語言切換 = signal 變動 = regenerate。

**Tech Stack:** Python 3.10+, pytest, dataclass, pathspec, pyyaml, tomllib;既有 architect 模組慣例 (pure functions + 整合在 `scan.py` orchestrator)。

**Spec:** `docs/superpowers/specs/2026-05-27-obsidian-architect-narrative-design.md`

**Suggested branch:** `feat/architect-narrative`

---

## Task layout

22 個任務分 8 個 phase。Phase A 是 foundation;Phase B 的 6 個 detector 互相獨立可平行;Phase C-E 依序;Phase F-H 是收尾。

| Phase | 任務 | 範圍 |
|---|---|---|
| A. Foundation | 1-2 | `lang.py`、lockfile v2 |
| B. Detectors | 3-9 | README、CHANGELOG、TODO、ADR、stack、API surface (CLI+HTTP+exports+env)、public-surface eligibility |
| B'. Integration | 10 | 把 detector 串進 `scan.py` |
| C. Sections base | 11 | `sections.py` 基礎 (signal hash、frontmatter composer、section file writer) |
| D. Per-section | 12-17 | api-surface / features / decisions / roadmap / future / function 六個 generator |
| E. Overview + refresh | 18-19 | Overview MOC、`decide_section_refresh()` |
| F. Schema docs | 20 | `ai-first-rules.md` 加 6 個新 type + 語言總則 + heading 對照表 |
| G. Command body | 21 | Update `commands/obsidian-architect.md` + 重建 adapter dist |
| H. Polish | 22 | CHANGELOG / SKILL.md / README.md / 對本 repo smoke test |

---

## Phase A — Foundation

### Task 1: 語言解析 `lang.py`

**Files:**
- Create: `scripts/architect/lang.py`
- Create: `tests/architect/test_lang.py`

- [ ] **Step 1: Write failing test for resolve_output_lang precedence**

Add to `tests/architect/test_lang.py`:

```python
from pathlib import Path

from scripts.architect.lang import resolve_output_lang


def test_cli_flag_wins(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("- output-lang: en\n")
    assert resolve_output_lang(cli_flag="zh-TW", vault_root=tmp_path) == "zh-TW"


def test_claude_md_when_no_flag(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("Some prelude.\n- output-lang: zh-TW\nMore.\n")
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "zh-TW"


def test_default_en_when_no_signal(tmp_path: Path):
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "en"


def test_invalid_lang_falls_back_to_en(tmp_path: Path):
    (tmp_path / "_CLAUDE.md").write_text("- output-lang: klingon\n")
    assert resolve_output_lang(cli_flag=None, vault_root=tmp_path) == "en"


def test_supported_langs_constant():
    from scripts.architect.lang import SUPPORTED_LANGS
    assert set(SUPPORTED_LANGS) == {"en", "zh-TW"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_lang.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'scripts.architect.lang'`

- [ ] **Step 3: Implement `lang.py`**

Create `scripts/architect/lang.py`:

```python
"""Resolve the output language for architect-generated notes.

Precedence: CLI flag > vault _CLAUDE.md `- output-lang: <code>` line > default 'en'.
"""

from __future__ import annotations

import re
from pathlib import Path

SUPPORTED_LANGS = ("en", "zh-TW")
DEFAULT_LANG = "en"

_OUTPUT_LANG_RE = re.compile(r"^\s*-\s*output-lang:\s*([A-Za-z0-9_-]+)\s*$", re.MULTILINE)


def resolve_output_lang(cli_flag: str | None, vault_root: Path) -> str:
    """Return the effective output language code.

    Args:
        cli_flag: value of `--lang=` passed to the command, or None.
        vault_root: directory containing `_CLAUDE.md`.

    Returns 'en' on any invalid or missing signal.
    """
    if cli_flag and cli_flag in SUPPORTED_LANGS:
        return cli_flag
    claude_md = vault_root / "_CLAUDE.md"
    if claude_md.exists():
        m = _OUTPUT_LANG_RE.search(claude_md.read_text(encoding="utf-8"))
        if m and m.group(1) in SUPPORTED_LANGS:
            return m.group(1)
    return DEFAULT_LANG
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lang.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Add heading map skeleton**

Append to `scripts/architect/lang.py`:

```python


HEADING_MAP: dict[str, dict[str, str]] = {
    # Universal headings reused across types.
    "## For future Claude": {"en": "## For future Claude", "zh-TW": "## 給未來 Claude"},
    "## Summary": {"en": "## Summary", "zh-TW": "## 摘要"},
    "## Related": {"en": "## Related", "zh-TW": "## 相關"},
    # Overview headings.
    "## Purpose": {"en": "## Purpose", "zh-TW": "## 用途"},
    "## Stack": {"en": "## Stack", "zh-TW": "## 技術棧"},
    "## Capability MOC": {"en": "## Capability MOC", "zh-TW": "## 能力地圖 MOC"},
    "## Structure MOC": {"en": "## Structure MOC", "zh-TW": "## 結構地圖 MOC"},
    "## API surface": {"en": "## API surface", "zh-TW": "## API 介面"},
    "## Layer map": {"en": "## Layer map", "zh-TW": "## 分層圖"},
    "## External dependencies": {"en": "## External dependencies", "zh-TW": "## 外部相依"},
    "## Key abstractions": {"en": "## Key abstractions", "zh-TW": "## 核心抽象"},
    # features.md
    "## Capability map": {"en": "## Capability map", "zh-TW": "## 能力地圖"},
    "## Notable details": {"en": "## Notable details", "zh-TW": "## 補充細節"},
    # roadmap.md
    "## Near term": {"en": "## Near term", "zh-TW": "## 近期"},
    "## Trajectory": {"en": "## Trajectory", "zh-TW": "## 軌跡"},
    "## TODO clusters": {"en": "## TODO clusters", "zh-TW": "## TODO 群組"},
    "## Signals reviewed": {"en": "## Signals reviewed", "zh-TW": "## 已檢視訊號"},
    # decisions.md
    "## Stack rationale": {"en": "## Stack rationale", "zh-TW": "## 技術棧理由"},
    "## Detected ADRs": {"en": "## Detected ADRs", "zh-TW": "## 已偵測的 ADR"},
    "## Pattern decisions": {"en": "## Pattern decisions", "zh-TW": "## 模式決定"},
    "## Commit-message decisions": {"en": "## Commit-message decisions", "zh-TW": "## Commit 訊息決定"},
    "## Promote to ADR": {"en": "## Promote to ADR", "zh-TW": "## 建議升級為 ADR"},
    # future.md
    "## Known limitations": {"en": "## Known limitations", "zh-TW": "## 已知限制"},
    "## Gap analysis": {"en": "## Gap analysis", "zh-TW": "## 落差分析"},
    "## Aspirational ideas": {"en": "## Aspirational ideas", "zh-TW": "## 期望中的想法"},
    # api-surface.md
    "## CLI commands": {"en": "## CLI commands", "zh-TW": "## CLI 命令"},
    "## HTTP routes": {"en": "## HTTP routes", "zh-TW": "## HTTP 路由"},
    "## Public exports": {"en": "## Public exports", "zh-TW": "## 公開匯出"},
    "## Environment variables": {"en": "## Environment variables", "zh-TW": "## 環境變數"},
    # modules (existing, restated for translation table completeness).
    "## What it does": {"en": "## What it does", "zh-TW": "## 功能說明"},
    "## How it works": {"en": "## How it works", "zh-TW": "## 運作方式"},
    "## Key files": {"en": "## Key files", "zh-TW": "## 重點檔案"},
    "## Depends on": {"en": "## Depends on", "zh-TW": "## 相依於"},
    "## Consumed by": {"en": "## Consumed by", "zh-TW": "## 被誰使用"},
    "## Recent activity": {"en": "## Recent activity", "zh-TW": "## 近期活動"},
    # function notes.
    "## Signature": {"en": "## Signature", "zh-TW": "## 函式簽章"},
    "## Inputs and outputs": {"en": "## Inputs and outputs", "zh-TW": "## 輸入輸出"},
    "## Behavior notes": {"en": "## Behavior notes", "zh-TW": "## 行為註記"},
    "## Callers": {"en": "## Callers", "zh-TW": "## 呼叫者"},
}


def heading(key: str, lang: str) -> str:
    """Translate a canonical (English) heading to the given language.

    Unknown keys pass through unchanged so the caller fails loud at render time.
    """
    return HEADING_MAP.get(key, {}).get(lang, key)
```

- [ ] **Step 6: Add tests for HEADING_MAP and heading()**

Append to `tests/architect/test_lang.py`:

```python
def test_heading_returns_zh_for_known_key():
    from scripts.architect.lang import heading
    assert heading("## Summary", "zh-TW") == "## 摘要"
    assert heading("## CLI commands", "zh-TW") == "## CLI 命令"


def test_heading_returns_en_for_en_lang():
    from scripts.architect.lang import heading
    assert heading("## Summary", "en") == "## Summary"


def test_heading_passes_through_unknown_key():
    from scripts.architect.lang import heading
    assert heading("## Unknown thing", "zh-TW") == "## Unknown thing"


def test_heading_map_covers_all_required_keys():
    from scripts.architect.lang import HEADING_MAP
    required = {
        "## For future Claude", "## Summary", "## Related",
        "## Purpose", "## Stack", "## Capability MOC", "## Structure MOC",
        "## API surface", "## Layer map", "## External dependencies", "## Key abstractions",
        "## Capability map", "## Notable details",
        "## Near term", "## Trajectory", "## TODO clusters", "## Signals reviewed",
        "## Stack rationale", "## Detected ADRs", "## Pattern decisions",
        "## Commit-message decisions", "## Promote to ADR",
        "## Known limitations", "## Gap analysis", "## Aspirational ideas",
        "## CLI commands", "## HTTP routes", "## Public exports", "## Environment variables",
        "## What it does", "## How it works", "## Key files", "## Depends on",
        "## Consumed by", "## Recent activity",
        "## Signature", "## Inputs and outputs", "## Behavior notes", "## Callers",
    }
    missing = required - set(HEADING_MAP.keys())
    assert not missing, f"missing heading keys: {missing}"
```

- [ ] **Step 7: Run all lang tests**

Run: `uv run pytest tests/architect/test_lang.py -v`
Expected: PASS (9 tests)

- [ ] **Step 8: Commit**

```bash
git add scripts/architect/lang.py tests/architect/test_lang.py
git commit -m "feat(architect): add language resolver and heading map"
```

---

### Task 2: Lockfile v2 schema (sections + functions + lang)

**Files:**
- Modify: `scripts/architect/lockfile.py`
- Modify: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing tests for v2 schema**

Append to `tests/architect/test_lockfile.py`:

```python
def test_v2_lockfile_round_trip_with_sections(tmp_path: Path):
    from scripts.architect.lockfile import Lockfile, hash_value, load_lockfile, write_lockfile
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        fields={},
        note_blocks={},
        sections={
            "features": {"signal-hash": hash_value("sig"), "lang": "zh-TW",
                         "note-blocks-hash": hash_value("nb"), "last-generated": "2026-05-27T10:00:00Z"},
        },
        functions={
            "cli/main": {"source-hash": hash_value("src"), "last-generated": "2026-05-27T10:00:00Z"},
        },
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.version == 2
    assert loaded.sections["features"]["lang"] == "zh-TW"
    assert loaded.functions["cli/main"]["source-hash"].startswith("sha256:")


def test_v1_lockfile_migrates_on_load(tmp_path: Path):
    """Loading a v1 lockfile should yield version=2 with empty sections/functions."""
    import json
    from scripts.architect.lockfile import load_lockfile
    target = tmp_path / "_manifest.lock.json"
    target.write_text(json.dumps({
        "version": 1,
        "scanner_version": "0.1.0",
        "fields": {"modules.auth.role": {"hash": "sha256:abc", "value": "core"}},
        "note_blocks": {"modules/auth.md": {"what-it-does": {"hash": "sha256:def"}}},
    }))
    loaded = load_lockfile(target)
    assert loaded.version == 2
    assert loaded.sections == {}
    assert loaded.functions == {}
    # Preserved.
    assert loaded.fields["modules.auth.role"]["value"] == "core"


def test_section_signal_was_changed(tmp_path: Path):
    from scripts.architect.lockfile import Lockfile, hash_value, section_signal_was_changed
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        fields={},
        note_blocks={},
        sections={"roadmap": {"signal-hash": hash_value("X"), "lang": "en",
                              "note-blocks-hash": "", "last-generated": ""}},
        functions={},
    )
    # Signal matches and lang matches: unchanged.
    assert section_signal_was_changed(lock, "roadmap", current_signal="X", current_lang="en") is False
    # Signal differs.
    assert section_signal_was_changed(lock, "roadmap", current_signal="Y", current_lang="en") is True
    # Lang differs (counts as changed).
    assert section_signal_was_changed(lock, "roadmap", current_signal="X", current_lang="zh-TW") is True
    # Missing section: changed (treat as first-run).
    assert section_signal_was_changed(lock, "features", current_signal="anything", current_lang="en") is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: FAIL — Lockfile lacks `sections`/`functions` fields and `section_signal_was_changed` does not exist.

- [ ] **Step 3: Extend `Lockfile` dataclass and add migration**

Replace `scripts/architect/lockfile.py` body with:

```python
"""Lockfile: hash-based tracking of LLM-written content.

For each LLM-written manifest field, note section, and narrative-section
generated note, we store a SHA-256 hash so refresh can decide regenerate
vs preserve.

Schema versions:
  v1: fields + note_blocks (modules only).
  v2: adds `sections` (per-section narrative notes) and `functions`
      (optional --functions=public layer). Loading v1 silently migrates.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

CURRENT_SCHEMA = 2


@dataclass
class Lockfile:
    version: int
    scanner_version: str
    fields: dict = field(default_factory=dict)
    note_blocks: dict = field(default_factory=dict)
    sections: dict = field(default_factory=dict)
    functions: dict = field(default_factory=dict)


def hash_value(s: str) -> str:
    """Return 'sha256:<hex>' for stable comparison."""
    return "sha256:" + hashlib.sha256(s.encode("utf-8")).hexdigest()


def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    return Lockfile(
        version=CURRENT_SCHEMA,
        scanner_version=data.get("scanner_version", "0.0.0"),
        fields=data.get("fields", {}),
        note_blocks=data.get("note_blocks", {}),
        sections=data.get("sections", {}),
        functions=data.get("functions", {}),
    )


def write_lockfile(lock: Lockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(lock)
    payload["version"] = CURRENT_SCHEMA
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))


def field_was_user_edited(lock: Lockfile, field_key: str, current_value: str) -> bool:
    """True iff the current value differs from the LLM-written value recorded in the lockfile.

    If the field is not in the lockfile (e.g. first-run), returns False
    (treat as LLM-territory; safe because lockfile will be updated on first write).
    """
    record = lock.fields.get(field_key)
    if record is None:
        return False
    return record["hash"] != hash_value(current_value)


def section_signal_was_changed(
    lock: Lockfile, section_name: str, current_signal: str, current_lang: str
) -> bool:
    """True iff the section's signal hash or lang differs from the lockfile entry.

    Missing section returns True (first-run = changed = should regenerate).
    """
    record = lock.sections.get(section_name)
    if record is None:
        return True
    if record.get("lang") != current_lang:
        return True
    return record.get("signal-hash") != hash_value(current_signal)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: PASS (all old + 3 new tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "feat(architect): bump lockfile schema to v2 with sections and functions"
```

---

## Phase B — Deterministic detectors (parallelizable)

### Task 3: README section parser

**Files:**
- Create: `scripts/architect/readme.py`
- Create: `tests/architect/test_readme.py`
- Create: `tests/architect/fixtures/readmes/full.md`
- Create: `tests/architect/fixtures/readmes/empty.md`

- [ ] **Step 1: Write fixture: a README with all interesting sections**

Create `tests/architect/fixtures/readmes/full.md`:

```markdown
# My Project

A short tagline.

## Features

- Fast HTTP client
- Async by default
- Plugin system

## Installation

Boilerplate not interesting.

## Roadmap

- v2: streaming support
- v3: WASM target

## Coming Soon

- gRPC adapter

## Limitations

- No Windows support
- Single-threaded only

## Known Issues

- Bug with large payloads

## Future Work

- Investigate io_uring
```

- [ ] **Step 2: Write fixture: empty README (no recognized sections)**

Create `tests/architect/fixtures/readmes/empty.md`:

```markdown
# Empty Project

Just a tagline, no sections.
```

- [ ] **Step 3: Write failing tests**

Create `tests/architect/test_readme.py`:

```python
from pathlib import Path

from scripts.architect.readme import extract_sections

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "readmes"


def test_extract_known_sections_from_full_readme():
    text = (FIXTURE_DIR / "full.md").read_text()
    sections = extract_sections(text)
    assert "Features" in sections
    assert "Fast HTTP client" in sections["Features"]
    assert "Roadmap" in sections
    assert "v2: streaming support" in sections["Roadmap"]
    assert "Coming Soon" in sections
    assert "gRPC adapter" in sections["Coming Soon"]
    assert "Limitations" in sections
    assert "No Windows support" in sections["Limitations"]
    assert "Known Issues" in sections
    assert "Future Work" in sections


def test_empty_readme_returns_empty_dict():
    text = (FIXTURE_DIR / "empty.md").read_text()
    assert extract_sections(text) == {}


def test_section_extraction_is_case_insensitive():
    text = "# Foo\n\n## FEATURES\n\n- one\n\n## roadmap\n\n- two\n"
    sections = extract_sections(text)
    assert "Features" in sections  # normalized to title-case key
    assert "Roadmap" in sections


def test_section_body_excludes_subsequent_h2():
    text = "## Features\n\n- a\n\n## Roadmap\n\n- b\n"
    sections = extract_sections(text)
    assert "Roadmap" not in sections["Features"]
    assert "- a" in sections["Features"]
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_readme.py -v`
Expected: FAIL — module not found.

- [ ] **Step 5: Implement `readme.py`**

Create `scripts/architect/readme.py`:

```python
"""Extract recognized sections from a README.

Returns a dict {canonical_section_name: body_text} where canonical names are
title-case strings drawn from a fixed alias map. Unknown sections are ignored.
"""

from __future__ import annotations

import re

# Map of lowercase alias -> canonical title-case name.
_ALIASES = {
    "features": "Features",
    "capabilities": "Features",
    "roadmap": "Roadmap",
    "coming soon": "Coming Soon",
    "upcoming": "Coming Soon",
    "limitations": "Limitations",
    "known issues": "Known Issues",
    "known limitations": "Limitations",
    "future work": "Future Work",
    "future": "Future Work",
    "what's next": "Future Work",
}

_H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)


def extract_sections(text: str) -> dict[str, str]:
    """Return {canonical_name: body} for every recognized H2 in `text`.

    Body is the raw text between this H2 and the next H2 (or EOF), stripped.
    """
    matches = list(_H2_RE.finditer(text))
    if not matches:
        return {}
    out: dict[str, str] = {}
    for i, m in enumerate(matches):
        title = m.group(1).strip().lower()
        canonical = _ALIASES.get(title)
        if canonical is None:
            continue
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        out[canonical] = text[body_start:body_end].strip()
    return out
```

- [ ] **Step 6: Run tests**

Run: `uv run pytest tests/architect/test_readme.py -v`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add scripts/architect/readme.py tests/architect/test_readme.py tests/architect/fixtures/readmes/
git commit -m "feat(architect): add README section extractor"
```

---

### Task 4: CHANGELOG parser

**Files:**
- Create: `scripts/architect/changelog.py`
- Create: `tests/architect/test_changelog.py`
- Create: `tests/architect/fixtures/changelogs/keepachangelog.md`

- [ ] **Step 1: Write fixture (Keep-a-Changelog style)**

Create `tests/architect/fixtures/changelogs/keepachangelog.md`:

```markdown
# Changelog

## Unreleased

### Added
- Foo
- Bar

### Fixed
- Crash on startup

## [0.3.0] - 2026-05-20

### Added
- Initial WASM target

## [0.2.0] - 2026-05-01

### Changed
- Renamed cli flag

## [0.1.0] - 2026-04-20

### Added
- First release
```

- [ ] **Step 2: Write failing tests**

Create `tests/architect/test_changelog.py`:

```python
from pathlib import Path

from scripts.architect.changelog import parse_changelog

FIXTURE = Path(__file__).parent / "fixtures" / "changelogs" / "keepachangelog.md"


def test_parses_unreleased_block():
    cl = parse_changelog(FIXTURE.read_text())
    assert cl.unreleased is not None
    assert "Foo" in cl.unreleased
    assert "Crash on startup" in cl.unreleased


def test_recent_versions_up_to_three():
    cl = parse_changelog(FIXTURE.read_text())
    assert len(cl.recent_versions) == 3
    assert cl.recent_versions[0].version == "0.3.0"
    assert cl.recent_versions[0].date == "2026-05-20"
    assert "WASM" in cl.recent_versions[0].body


def test_empty_changelog():
    cl = parse_changelog("# Changelog\n\nNothing yet.\n")
    assert cl.unreleased is None
    assert cl.recent_versions == []


def test_missing_file_returns_none_via_loader(tmp_path: Path):
    from scripts.architect.changelog import load_changelog
    assert load_changelog(tmp_path) is None
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_changelog.py -v`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement `changelog.py`**

Create `scripts/architect/changelog.py`:

```python
"""Parse CHANGELOG.md (Keep-a-Changelog flavored) for architect signals.

Returns:
- unreleased: raw body text under `## Unreleased`, or None.
- recent_versions: up to 3 most recent versioned blocks with parsed
  version + date + body.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)
_VERSION_RE = re.compile(r"^\[?(?P<ver>\d+\.\d+\.\d+[^\]\s]*)\]?(?:\s*-\s*(?P<date>[\d-]+))?$")


@dataclass
class VersionEntry:
    version: str
    date: str
    body: str


@dataclass
class Changelog:
    unreleased: str | None = None
    recent_versions: list[VersionEntry] = field(default_factory=list)


def parse_changelog(text: str) -> Changelog:
    cl = Changelog()
    matches = list(_H2_RE.finditer(text))
    for i, m in enumerate(matches):
        title = m.group(1).strip()
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip()
        if title.lower() == "unreleased":
            cl.unreleased = body
            continue
        vm = _VERSION_RE.match(title)
        if vm:
            cl.recent_versions.append(
                VersionEntry(version=vm.group("ver"), date=vm.group("date") or "", body=body)
            )
    cl.recent_versions = cl.recent_versions[:3]
    return cl


def load_changelog(repo_root: Path) -> Changelog | None:
    """Read CHANGELOG.md from repo root. Returns None if missing."""
    for name in ("CHANGELOG.md", "CHANGELOG", "HISTORY.md"):
        p = repo_root / name
        if p.exists():
            return parse_changelog(p.read_text(encoding="utf-8"))
    return None
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/architect/test_changelog.py -v`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/changelog.py tests/architect/test_changelog.py tests/architect/fixtures/changelogs/
git commit -m "feat(architect): add CHANGELOG parser"
```

---

### Task 5: TODO aggregator

**Files:**
- Create: `scripts/architect/todos.py`
- Create: `tests/architect/test_todos.py`

- [ ] **Step 1: Write failing tests with inline fixture repo**

Create `tests/architect/test_todos.py`:

```python
from pathlib import Path

from scripts.architect.todos import aggregate_todos


def _setup_repo(tmp_path: Path):
    (tmp_path / "src" / "auth").mkdir(parents=True)
    (tmp_path / "src" / "api").mkdir(parents=True)
    (tmp_path / "src" / "auth" / "login.py").write_text(
        "def login():\n"
        "    # TODO: rate limit this\n"
        "    # TODO(future): switch to OAuth2\n"
        "    # FIXME: handle empty password\n"
        "    pass\n"
    )
    (tmp_path / "src" / "api" / "routes.py").write_text(
        "# TODO: pagination\n"
        "# TODO(idea): GraphQL endpoint\n"
        "# TODO(roadmap): rate limiting at gateway level\n"
    )


def test_collects_todos_with_path_and_line(tmp_path: Path):
    _setup_repo(tmp_path)
    todos = aggregate_todos(tmp_path, module_paths={"auth": ["src/auth"], "api": ["src/api"]})
    auth = todos["auth"]
    assert any(t.text == "rate limit this" and t.label is None for t in auth)
    assert any(t.label == "future" for t in auth)
    assert any(t.kind == "FIXME" for t in auth)


def test_groups_by_module(tmp_path: Path):
    _setup_repo(tmp_path)
    todos = aggregate_todos(tmp_path, module_paths={"auth": ["src/auth"], "api": ["src/api"]})
    assert set(todos.keys()) == {"auth", "api"}
    assert len(todos["api"]) == 3


def test_unattributed_files_under_other(tmp_path: Path):
    (tmp_path / "stray.py").write_text("# TODO: this is not in any module\n")
    todos = aggregate_todos(tmp_path, module_paths={"foo": ["src/foo"]})
    assert "_unmapped" in todos
    assert todos["_unmapped"][0].text == "this is not in any module"


def test_skips_binary_and_oversize_files(tmp_path: Path):
    (tmp_path / "big.bin").write_bytes(b"\x00" * 200)
    todos = aggregate_todos(tmp_path, module_paths={})
    assert "_unmapped" not in todos or todos["_unmapped"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_todos.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `todos.py`**

Create `scripts/architect/todos.py`:

```python
"""Aggregate TODO / FIXME comments across the repo, grouped by module.

Each TODO is parsed for an optional label (e.g. `TODO(future): foo`) and the
free-text body. Output is suitable for roadmap.md and future.md synthesis.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_TEXT_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs", ".rb", ".java",
    ".kt", ".swift", ".c", ".cc", ".cpp", ".h", ".hpp", ".cs", ".php",
    ".sh", ".bash", ".zsh", ".lua", ".sql", ".md", ".yaml", ".yml", ".toml",
}
_MAX_FILE_BYTES = 512 * 1024

_TODO_RE = re.compile(
    r"(?P<kind>TODO|FIXME|XXX|HACK)"
    r"(?:\((?P<label>[a-zA-Z_-]+)\))?"
    r"\s*[:\-]?\s*"
    r"(?P<text>.+?)$",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass
class TodoItem:
    path: str         # repo-relative
    line: int
    kind: str         # TODO / FIXME / XXX / HACK
    label: str | None  # roadmap / future / idea / etc., or None
    text: str


def aggregate_todos(repo_root: Path, module_paths: dict[str, list[str]]) -> dict[str, list[TodoItem]]:
    """Walk the repo and group TODO items by module slug.

    Args:
        repo_root: absolute path to repo.
        module_paths: {module_slug: [repo-relative paths]} from manifest.

    Returns: {module_slug: [TodoItem]}.  Files not under any module land in
    the special bucket "_unmapped".
    """
    repo_root = repo_root.resolve()
    by_module: dict[str, list[TodoItem]] = {slug: [] for slug in module_paths}
    by_module["_unmapped"] = []
    for file in _iter_text_files(repo_root):
        rel = file.relative_to(repo_root).as_posix()
        slug = _which_module(rel, module_paths)
        try:
            text = file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for m in _TODO_RE.finditer(text):
            line_no = text[: m.start()].count("\n") + 1
            by_module[slug].append(
                TodoItem(
                    path=rel,
                    line=line_no,
                    kind=m.group("kind").upper(),
                    label=(m.group("label") or "").lower() or None,
                    text=m.group("text").strip(),
                )
            )
    # Drop empty buckets except _unmapped which callers may still inspect.
    return {k: v for k, v in by_module.items() if v or k == "_unmapped"}


def _iter_text_files(repo_root: Path):
    for p in repo_root.rglob("*"):
        if not p.is_file():
            continue
        if ".git" in p.parts or "node_modules" in p.parts or ".venv" in p.parts:
            continue
        if p.suffix.lower() not in _TEXT_EXTENSIONS:
            continue
        try:
            if p.stat().st_size > _MAX_FILE_BYTES:
                continue
        except OSError:
            continue
        yield p


def _which_module(rel_path: str, module_paths: dict[str, list[str]]) -> str:
    for slug, paths in module_paths.items():
        for prefix in paths:
            if rel_path == prefix or rel_path.startswith(prefix.rstrip("/") + "/"):
                return slug
    return "_unmapped"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_todos.py -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/todos.py tests/architect/test_todos.py
git commit -m "feat(architect): add TODO/FIXME aggregator grouped by module"
```

---

### Task 6: ADR / decision-document discovery

**Files:**
- Create: `scripts/architect/adr.py`
- Create: `tests/architect/test_adr.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_adr.py`:

```python
from pathlib import Path

from scripts.architect.adr import discover_decision_docs


def test_finds_docs_adr(tmp_path: Path):
    adr_dir = tmp_path / "docs" / "adr"
    adr_dir.mkdir(parents=True)
    (adr_dir / "0001-use-postgres.md").write_text("# Use Postgres\n\nWe chose Postgres because...\n")
    (adr_dir / "0002-switch-to-pnpm.md").write_text("# Switch to pnpm\n\n...\n")
    docs = discover_decision_docs(tmp_path)
    paths = [d.path for d in docs]
    assert "docs/adr/0001-use-postgres.md" in paths
    assert "docs/adr/0002-switch-to-pnpm.md" in paths


def test_finds_architecture_md(tmp_path: Path):
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture\n\nWe use hexagonal architecture.\n")
    docs = discover_decision_docs(tmp_path)
    titles = [d.title for d in docs]
    assert "Architecture" in titles


def test_finds_design_md(tmp_path: Path):
    (tmp_path / "DESIGN.md").write_text("# Design\n\nDesign notes.\n")
    docs = discover_decision_docs(tmp_path)
    titles = [d.title for d in docs]
    assert "Design" in titles


def test_returns_empty_when_no_docs(tmp_path: Path):
    assert discover_decision_docs(tmp_path) == []


def test_kind_classification(tmp_path: Path):
    (tmp_path / "docs" / "adr").mkdir(parents=True)
    (tmp_path / "docs" / "adr" / "0001-foo.md").write_text("# foo")
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture")
    docs = {d.kind for d in discover_decision_docs(tmp_path)}
    assert "adr" in docs
    assert "architecture-doc" in docs
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_adr.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `adr.py`**

Create `scripts/architect/adr.py`:

```python
"""Discover existing decision documents (ADRs, ARCHITECTURE.md, DESIGN.md).

Returns a list of DecisionDoc records describing each found file.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_ADR_DIRS = ("docs/adr", "docs/decisions", "architecture/decisions", "doc/adr")
_TOP_LEVEL_DOCS = (("ARCHITECTURE.md", "architecture-doc"), ("DESIGN.md", "design-doc"))


@dataclass
class DecisionDoc:
    path: str         # repo-relative posix path
    title: str        # first H1 or fallback to filename stem
    kind: str         # adr / architecture-doc / design-doc


def discover_decision_docs(repo_root: Path) -> list[DecisionDoc]:
    repo_root = repo_root.resolve()
    out: list[DecisionDoc] = []
    for d in _ADR_DIRS:
        adr_dir = repo_root / d
        if adr_dir.is_dir():
            for p in sorted(adr_dir.rglob("*.md")):
                out.append(DecisionDoc(
                    path=p.relative_to(repo_root).as_posix(),
                    title=_extract_title(p),
                    kind="adr",
                ))
    for filename, kind in _TOP_LEVEL_DOCS:
        p = repo_root / filename
        if p.is_file():
            out.append(DecisionDoc(
                path=p.relative_to(repo_root).as_posix(),
                title=_extract_title(p),
                kind=kind,
            ))
    return out


_H1_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)


def _extract_title(p: Path) -> str:
    try:
        text = p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return p.stem
    m = _H1_RE.search(text)
    return m.group(1).strip() if m else p.stem
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_adr.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/adr.py tests/architect/test_adr.py
git commit -m "feat(architect): discover ADRs and architecture/design docs"
```

---

### Task 7: Stack detector

**Files:**
- Create: `scripts/architect/stack.py`
- Create: `tests/architect/test_stack.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_stack.py`:

```python
from pathlib import Path

from scripts.architect.stack import detect_stack


def test_python_pyproject(tmp_path: Path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\n'
        'name = "x"\n'
        'dependencies = ["fastapi>=0.110", "sqlalchemy>=2.0"]\n'
        '[tool.pytest.ini_options]\n'
        'testpaths = ["tests"]\n'
    )
    stack = detect_stack(tmp_path)
    assert stack["primary-language"] == "Python"
    assert "FastAPI" in stack["frameworks"]
    assert "SQLAlchemy" in stack["frameworks"]
    assert stack["test"] == "pytest"


def test_typescript_nextjs(tmp_path: Path):
    (tmp_path / "package.json").write_text(
        '{"name":"x","dependencies":{"next":"14.0.0","react":"18.0.0",'
        '"@prisma/client":"5.0.0"},"devDependencies":{"vitest":"1.0.0"}}'
    )
    (tmp_path / "next.config.js").write_text("module.exports = {};\n")
    stack = detect_stack(tmp_path)
    assert stack["primary-language"] == "TypeScript or JavaScript"
    assert "Next.js" in stack["frameworks"]
    assert "Prisma" in stack["frameworks"]
    assert stack["test"] == "vitest"


def test_returns_empty_when_no_config(tmp_path: Path):
    assert detect_stack(tmp_path) == {}


def test_unrecognized_deps_are_dropped(tmp_path: Path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["some-random-lib"]\n'
    )
    stack = detect_stack(tmp_path)
    # primary-language is keyed off pyproject existence, so still present.
    assert stack.get("primary-language") == "Python"
    # No frameworks line in output because nothing recognized.
    assert "frameworks" not in stack or stack["frameworks"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_stack.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `stack.py`**

Create `scripts/architect/stack.py`:

```python
"""Best-effort stack detection from package manifests and root config files.

Returns a dict suitable for the overview frontmatter `stack:` block. Only
populates fields the detector can confidently fill; uncertain fields are
omitted (NEVER guessed).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib

# Map of dependency-name (lowercase) -> human framework label.
_FRAMEWORK_MAP = {
    # Python.
    "fastapi": "FastAPI",
    "flask": "Flask",
    "django": "Django",
    "starlette": "Starlette",
    "sqlalchemy": "SQLAlchemy",
    "pydantic": "Pydantic",
    "celery": "Celery",
    "click": "Click",
    "typer": "Typer",
    # JS/TS.
    "next": "Next.js",
    "react": "React",
    "vue": "Vue",
    "svelte": "Svelte",
    "express": "Express",
    "fastify": "Fastify",
    "@prisma/client": "Prisma",
    "prisma": "Prisma",
    "@trpc/server": "tRPC",
    "drizzle-orm": "Drizzle",
    # Go.
    "github.com/gin-gonic/gin": "Gin",
    "github.com/labstack/echo": "Echo",
}

_TEST_MAP_PY = {"pytest": "pytest", "unittest": "unittest"}
_TEST_MAP_JS = {"vitest": "vitest", "jest": "jest", "mocha": "mocha", "playwright": "playwright"}


def detect_stack(repo_root: Path) -> dict:
    """Return a dict ready to drop into overview frontmatter as `stack: {...}`."""
    repo_root = repo_root.resolve()
    stack: dict = {}
    py = _from_pyproject(repo_root)
    js = _from_package_json(repo_root)
    if py:
        stack["primary-language"] = "Python"
        stack.update(py)
    elif js:
        stack["primary-language"] = "TypeScript or JavaScript"
        stack.update(js)
    elif (repo_root / "Cargo.toml").exists():
        stack["primary-language"] = "Rust"
    elif (repo_root / "go.mod").exists():
        stack["primary-language"] = "Go"
    # Build tools.
    if (repo_root / "turbo.json").exists():
        stack.setdefault("build", "")
        stack["build"] = (stack.get("build") + " + turbo").strip(" +")
    return stack


def _from_pyproject(repo_root: Path) -> dict:
    p = repo_root / "pyproject.toml"
    if not p.exists():
        return {}
    data = tomllib.loads(p.read_text())
    deps = data.get("project", {}).get("dependencies", []) or []
    dev_deps = (
        data.get("dependency-groups", {}).get("dev", [])
        or data.get("tool", {}).get("poetry", {}).get("group", {}).get("dev", {}).get("dependencies", {})
        or []
    )
    out: dict = {}
    fws = sorted({_FRAMEWORK_MAP[_dep_name(d).lower()] for d in deps if _dep_name(d).lower() in _FRAMEWORK_MAP})
    if fws:
        out["frameworks"] = fws
    test_candidates = list(deps) + list(dev_deps if isinstance(dev_deps, list) else dev_deps.keys() if isinstance(dev_deps, dict) else [])
    for t in test_candidates:
        name = _dep_name(t).lower()
        if name in _TEST_MAP_PY:
            out["test"] = _TEST_MAP_PY[name]
            break
    if "tool" in data and "pytest" in data.get("tool", {}):
        out["test"] = "pytest"
    return out


def _from_package_json(repo_root: Path) -> dict:
    p = repo_root / "package.json"
    if not p.exists():
        return {}
    data = json.loads(p.read_text())
    deps = list((data.get("dependencies") or {}).keys()) + list((data.get("devDependencies") or {}).keys())
    out: dict = {}
    fws = sorted({_FRAMEWORK_MAP[d.lower()] for d in deps if d.lower() in _FRAMEWORK_MAP})
    if fws:
        out["frameworks"] = fws
    for d in deps:
        if d.lower() in _TEST_MAP_JS:
            out["test"] = _TEST_MAP_JS[d.lower()]
            break
    pkg_mgr = "npm"
    if (repo_root / "pnpm-lock.yaml").exists():
        pkg_mgr = "pnpm"
    elif (repo_root / "yarn.lock").exists():
        pkg_mgr = "yarn"
    out["build"] = pkg_mgr
    return out


_DEP_NAME_RE = re.compile(r"^([A-Za-z0-9._@/+-]+)")


def _dep_name(spec: str) -> str:
    """Extract the bare package name from a dep spec like 'fastapi>=0.110'."""
    m = _DEP_NAME_RE.match(spec)
    return m.group(1) if m else spec
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_stack.py -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/stack.py tests/architect/test_stack.py
git commit -m "feat(architect): add best-effort stack detector"
```

---

### Task 8: API surface detector (CLI / HTTP / exports / env)

**Files:**
- Create: `scripts/architect/api_surface.py`
- Create: `tests/architect/test_api_surface.py`

This task is bigger than most — 4 detectors share one module. Split into two commits if it helps reading, but the test file covers all four detectors at once.

- [ ] **Step 1: Write failing tests for all four detectors**

Create `tests/architect/test_api_surface.py`:

```python
from pathlib import Path

from scripts.architect.api_surface import detect_api_surface


def test_python_argparse_cli(tmp_path: Path):
    (tmp_path / "cli.py").write_text(
        "import argparse\n"
        "p = argparse.ArgumentParser()\n"
        "sub = p.add_subparsers()\n"
        "foo = sub.add_parser('foo', help='do foo')\n"
        "bar = sub.add_parser('bar', help='do bar')\n"
    )
    surf = detect_api_surface(tmp_path)
    cmds = {c.name for c in surf.cli_commands}
    assert "foo" in cmds
    assert "bar" in cmds


def test_fastapi_routes(tmp_path: Path):
    (tmp_path / "routes.py").write_text(
        "from fastapi import FastAPI\n"
        "app = FastAPI()\n"
        "@app.get('/items/{id}')\n"
        "def get_item(id: int): ...\n"
        "@app.post('/items')\n"
        "def create_item(): ...\n"
    )
    surf = detect_api_surface(tmp_path)
    assert any(r.method == "GET" and r.path == "/items/{id}" for r in surf.http_routes)
    assert any(r.method == "POST" and r.path == "/items" for r in surf.http_routes)


def test_python_all_exports(tmp_path: Path):
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text(
        '__all__ = ["login", "logout"]\n'
        'def login(): pass\n'
        'def logout(): pass\n'
        'def _internal(): pass\n'
    )
    surf = detect_api_surface(tmp_path)
    names = {e.symbol for e in surf.exports}
    assert "login" in names
    assert "logout" in names
    assert "_internal" not in names


def test_env_var_detection_python(tmp_path: Path):
    (tmp_path / "config.py").write_text(
        "import os\n"
        "DB_URL = os.getenv('DATABASE_URL', 'sqlite:///dev.db')\n"
        "API_KEY = os.environ['API_KEY']\n"
    )
    surf = detect_api_surface(tmp_path)
    vars_seen = {v.name for v in surf.env_vars}
    assert "DATABASE_URL" in vars_seen
    assert "API_KEY" in vars_seen
    db = next(v for v in surf.env_vars if v.name == "DATABASE_URL")
    assert db.default == "sqlite:///dev.db"


def test_empty_project_returns_detection_status_none(tmp_path: Path):
    surf = detect_api_surface(tmp_path)
    assert surf.detection_status == "none"
    assert surf.cli_commands == []
    assert surf.http_routes == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_api_surface.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `api_surface.py`**

Create `scripts/architect/api_surface.py`:

```python
"""Detect public API surface: CLI commands, HTTP routes, exports, env vars.

Each detector is pattern-matching only. Errors are silently dropped (a single
malformed file should never crash the scan).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_SUPPORTED_EXTS = {".py", ".js", ".ts", ".tsx"}
_MAX_FILE_BYTES = 512 * 1024


@dataclass
class CliCommand:
    name: str
    description: str
    source: str        # "<path>:<line>"


@dataclass
class HttpRoute:
    method: str
    path: str
    handler: str
    source: str


@dataclass
class Export:
    symbol: str
    kind: str          # "named" / "default" / "all"
    source: str


@dataclass
class EnvVar:
    name: str
    required: bool
    default: str | None
    source: str


@dataclass
class ApiSurface:
    cli_commands: list[CliCommand] = field(default_factory=list)
    http_routes: list[HttpRoute] = field(default_factory=list)
    exports: list[Export] = field(default_factory=list)
    env_vars: list[EnvVar] = field(default_factory=list)
    detection_status: str = "none"  # complete | partial | none


def detect_api_surface(repo_root: Path) -> ApiSurface:
    repo_root = repo_root.resolve()
    surf = ApiSurface()
    for p in _iter_source_files(repo_root):
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rel = p.relative_to(repo_root).as_posix()
        surf.cli_commands.extend(_detect_argparse(text, rel))
        surf.http_routes.extend(_detect_fastapi(text, rel))
        surf.http_routes.extend(_detect_express(text, rel))
        if p.name == "__init__.py" or p.suffix in {".js", ".ts"}:
            surf.exports.extend(_detect_python_all(text, rel) if p.suffix == ".py" else _detect_js_exports(text, rel))
        surf.env_vars.extend(_detect_env_vars(text, rel))
    if surf.cli_commands or surf.http_routes or surf.exports or surf.env_vars:
        surf.detection_status = "complete"
    return surf


def _iter_source_files(repo_root: Path):
    for p in repo_root.rglob("*"):
        if not p.is_file() or ".git" in p.parts or "node_modules" in p.parts:
            continue
        if p.suffix not in _SUPPORTED_EXTS:
            continue
        try:
            if p.stat().st_size > _MAX_FILE_BYTES:
                continue
        except OSError:
            continue
        yield p


_ARGPARSE_SUB_RE = re.compile(
    r"\.add_parser\(\s*['\"](?P<name>[\w_-]+)['\"]"
    r"(?:[^)]*?help\s*=\s*['\"](?P<help>[^'\"]*)['\"])?",
    re.DOTALL,
)


def _detect_argparse(text: str, rel: str) -> list[CliCommand]:
    out: list[CliCommand] = []
    for m in _ARGPARSE_SUB_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(CliCommand(
            name=m.group("name"),
            description=(m.group("help") or "").strip(),
            source=f"{rel}:{line}",
        ))
    return out


_FASTAPI_RE = re.compile(
    r"@\w+\.(?P<method>get|post|put|patch|delete)\(\s*['\"](?P<path>[^'\"]+)['\"]"
    r"[^)]*\)\s*\n\s*(?:async\s+)?def\s+(?P<handler>\w+)",
    re.IGNORECASE,
)


def _detect_fastapi(text: str, rel: str) -> list[HttpRoute]:
    out: list[HttpRoute] = []
    for m in _FASTAPI_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(HttpRoute(
            method=m.group("method").upper(),
            path=m.group("path"),
            handler=m.group("handler"),
            source=f"{rel}:{line}",
        ))
    return out


_EXPRESS_RE = re.compile(
    r"\bapp\.(?P<method>get|post|put|patch|delete)\(\s*['\"](?P<path>[^'\"]+)['\"]",
    re.IGNORECASE,
)


def _detect_express(text: str, rel: str) -> list[HttpRoute]:
    out: list[HttpRoute] = []
    for m in _EXPRESS_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(HttpRoute(
            method=m.group("method").upper(),
            path=m.group("path"),
            handler="(anonymous)",
            source=f"{rel}:{line}",
        ))
    return out


_ALL_RE = re.compile(r"^__all__\s*=\s*\[(?P<body>[^\]]*)\]", re.MULTILINE | re.DOTALL)
_QUOTED_NAME_RE = re.compile(r"['\"]([\w_]+)['\"]")


def _detect_python_all(text: str, rel: str) -> list[Export]:
    m = _ALL_RE.search(text)
    if not m:
        return []
    line = text[: m.start()].count("\n") + 1
    return [
        Export(symbol=n, kind="all", source=f"{rel}:{line}")
        for n in _QUOTED_NAME_RE.findall(m.group("body"))
    ]


_JS_NAMED_EXPORT_RE = re.compile(
    r"^export\s+(?:async\s+)?(?:function|const|let|var|class)\s+(?P<name>[A-Za-z_$][\w$]*)",
    re.MULTILINE,
)
_JS_DEFAULT_EXPORT_RE = re.compile(r"^export\s+default\s+(?:function\s+)?(?P<name>[A-Za-z_$][\w$]*)", re.MULTILINE)


def _detect_js_exports(text: str, rel: str) -> list[Export]:
    out: list[Export] = []
    for m in _JS_NAMED_EXPORT_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(Export(symbol=m.group("name"), kind="named", source=f"{rel}:{line}"))
    for m in _JS_DEFAULT_EXPORT_RE.finditer(text):
        line = text[: m.start()].count("\n") + 1
        out.append(Export(symbol=m.group("name"), kind="default", source=f"{rel}:{line}"))
    return out


_GETENV_RE = re.compile(
    r"os\.getenv\(\s*['\"](?P<name>[A-Z][A-Z0-9_]*)['\"]"
    r"(?:\s*,\s*['\"](?P<default>[^'\"]*)['\"])?",
)
_OSENV_BRACKET_RE = re.compile(r"os\.environ\[\s*['\"](?P<name>[A-Z][A-Z0-9_]*)['\"]\s*\]")
_PROCESSENV_RE = re.compile(r"process\.env\.(?P<name>[A-Z][A-Z0-9_]*)")


def _detect_env_vars(text: str, rel: str) -> list[EnvVar]:
    out: list[EnvVar] = []
    seen: set[str] = set()
    for m in _GETENV_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(
            name=m.group("name"),
            required=False,
            default=m.group("default"),
            source=f"{rel}:{line}",
        ))
    for m in _OSENV_BRACKET_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(name=m.group("name"), required=True, default=None, source=f"{rel}:{line}"))
    for m in _PROCESSENV_RE.finditer(text):
        if m.group("name") in seen:
            continue
        seen.add(m.group("name"))
        line = text[: m.start()].count("\n") + 1
        out.append(EnvVar(name=m.group("name"), required=False, default=None, source=f"{rel}:{line}"))
    return out
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_api_surface.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/api_surface.py tests/architect/test_api_surface.py
git commit -m "feat(architect): add API surface detector (CLI/HTTP/exports/env)"
```

---

### Task 9: Public-surface eligibility for `--functions=public`

**Files:**
- Create: `scripts/architect/public_surface.py`
- Create: `tests/architect/test_public_surface.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_public_surface.py`:

```python
from pathlib import Path

from scripts.architect.api_surface import ApiSurface, CliCommand, Export, HttpRoute
from scripts.architect.public_surface import eligible_functions


def test_collects_from_each_source(tmp_path: Path):
    surf = ApiSurface(
        cli_commands=[CliCommand(name="foo", description="do foo", source="src/cli.py:42")],
        http_routes=[HttpRoute(method="GET", path="/x", handler="get_x", source="src/api.py:10")],
        exports=[Export(symbol="login", kind="named", source="src/auth/__init__.py:3")],
    )
    elig = eligible_functions(surf, module_paths={"cli": ["src/cli.py"], "api": ["src/api.py"], "auth": ["src/auth"]})
    keys = {(e.module_slug, e.name) for e in elig}
    assert ("cli", "foo") in keys
    assert ("api", "get_x") in keys
    assert ("auth", "login") in keys


def test_unmapped_function_skipped():
    surf = ApiSurface(cli_commands=[CliCommand(name="orphan", description="", source="elsewhere/orphan.py:1")])
    elig = eligible_functions(surf, module_paths={"cli": ["src/cli.py"]})
    assert elig == []


def test_deduplicates_same_symbol():
    surf = ApiSurface(
        exports=[
            Export(symbol="login", kind="named", source="src/auth/login.py:5"),
            Export(symbol="login", kind="all", source="src/auth/__init__.py:3"),
        ],
    )
    elig = eligible_functions(surf, module_paths={"auth": ["src/auth"]})
    assert len(elig) == 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_public_surface.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `public_surface.py`**

Create `scripts/architect/public_surface.py`:

```python
"""Choose which functions get their own `Architecture/functions/<module>/<func>.md` note.

Eligibility (per spec §5.6):
- Symbol is a CLI subcommand handler
- Symbol is an HTTP route handler
- Symbol appears in __all__ or is a named/default export
Symbols whose source file maps to no manifest module are skipped.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from scripts.architect.api_surface import ApiSurface


@dataclass(frozen=True)
class EligibleFunction:
    module_slug: str
    name: str
    source: str        # "<path>:<line>" verbatim
    kind: str          # cli-handler / http-handler / export


def eligible_functions(surface: ApiSurface, module_paths: dict[str, list[str]]) -> list[EligibleFunction]:
    """Return deduplicated list of functions worthy of their own note."""
    seen: set[tuple[str, str]] = set()
    out: list[EligibleFunction] = []

    def _add(name: str, source: str, kind: str):
        slug = _which_module(source.split(":")[0], module_paths)
        if slug == "_unmapped":
            return
        key = (slug, name)
        if key in seen:
            return
        seen.add(key)
        out.append(EligibleFunction(module_slug=slug, name=name, source=source, kind=kind))

    for c in surface.cli_commands:
        _add(c.name, c.source, "cli-handler")
    for r in surface.http_routes:
        if r.handler == "(anonymous)":
            continue
        _add(r.handler, r.source, "http-handler")
    for e in surface.exports:
        _add(e.symbol, e.source, "export")
    return out


def _which_module(rel_path: str, module_paths: dict[str, list[str]]) -> str:
    for slug, paths in module_paths.items():
        for prefix in paths:
            if rel_path == prefix or rel_path.startswith(prefix.rstrip("/") + "/"):
                return slug
    return "_unmapped"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_public_surface.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/public_surface.py tests/architect/test_public_surface.py
git commit -m "feat(architect): add public-surface eligibility for --functions=public"
```

---

### Task 10: Wire new detectors into `scan.py` (extended scan-report)

**Files:**
- Modify: `scripts/architect/scan.py`
- Modify: `tests/architect/test_scan.py`

- [ ] **Step 1: Write failing tests for extended scan-report**

Append to `tests/architect/test_scan.py`:

```python
def test_scan_report_includes_narrative_signals(tmp_path: Path):
    """Phase 1 scan-report must now carry README sections, CHANGELOG, TODOs,
    ADRs, stack, and API surface — even if some are empty."""
    import subprocess
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    (tmp_path / "README.md").write_text("# X\n\n## Features\n\n- alpha\n")
    (tmp_path / "CHANGELOG.md").write_text("# Changelog\n\n## Unreleased\n\n- soon\n")
    (tmp_path / "ARCHITECTURE.md").write_text("# Architecture\n\nNotes.\n")
    (tmp_path / "pyproject.toml").write_text('[project]\nname = "x"\ndependencies = ["fastapi"]\n')
    (tmp_path / "main.py").write_text("# TODO: do thing\nprint('hi')\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", "init"], check=True)

    from scripts.architect.scan import run_phase_one
    result = run_phase_one(tmp_path)
    sr = result.scan_report
    assert "readme_sections" in sr
    assert "Features" in sr["readme_sections"]
    assert "changelog" in sr
    assert sr["changelog"]["unreleased"] is not None
    assert "decision_docs" in sr
    assert any(d["kind"] == "architecture-doc" for d in sr["decision_docs"])
    assert "stack" in sr
    assert sr["stack"]["primary-language"] == "Python"
    assert "todos" in sr
    assert "api_surface" in sr
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_scan.py::test_scan_report_includes_narrative_signals -v`
Expected: FAIL — scan-report missing the new keys.

- [ ] **Step 3: Extend `scan.py`**

Replace `scripts/architect/scan.py` body with:

```python
"""Phase 1 orchestrator: tie walker + repomix + entry_points + deps + proposal
plus narrative-signal detectors into a single deterministic output.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path

from scripts.architect.adr import discover_decision_docs
from scripts.architect.api_surface import detect_api_surface
from scripts.architect.changelog import load_changelog
from scripts.architect.deps import detect_external_deps
from scripts.architect.entry_points import detect_entry_points
from scripts.architect.manifest import Manifest
from scripts.architect.proposal import propose_modules_with_heuristics
from scripts.architect.readme import extract_sections
from scripts.architect.repomix import pack_repo_metadata
from scripts.architect.stack import detect_stack
from scripts.architect.todos import aggregate_todos
from scripts.architect.walker import git_metadata, language_stats, walk_repo

SCANNER_VERSION = "0.2.0"


@dataclass
class ScanResult:
    manifest: Manifest
    scan_report: dict


def run_phase_one(repo_root: Path) -> ScanResult:
    repo_root = repo_root.resolve()

    files = walk_repo(repo_root)
    languages = language_stats(repo_root)
    git_meta = git_metadata(repo_root)
    entry_points = detect_entry_points(repo_root)
    external_deps = detect_external_deps(repo_root)
    modules = propose_modules_with_heuristics(repo_root, entry_points=entry_points)
    pack_meta = pack_repo_metadata(repo_root)

    primary_language = languages[0]["lang"] if languages else "unknown"

    manifest = Manifest(
        version=1,
        repo={
            "name": repo_root.name,
            "root": str(repo_root),
            "primary_language": primary_language,
            "languages": languages,
        },
        last_scan={
            "date": date.today().isoformat(),
            "commit": git_meta["commit"][:7] + ("+dirty" if git_meta["dirty"] else ""),
            "dirty": git_meta["dirty"],
            "scanner_version": SCANNER_VERSION,
        },
        modules=modules,
    )

    # Narrative signal collection.
    readme_text = (repo_root / "README.md").read_text(encoding="utf-8") if (repo_root / "README.md").exists() else ""
    readme_sections = extract_sections(readme_text)
    changelog = load_changelog(repo_root)
    decision_docs = [asdict(d) for d in discover_decision_docs(repo_root)]
    stack = detect_stack(repo_root)
    module_paths_map = {m["slug"]: m.get("paths", []) for m in modules}
    todos = {
        slug: [asdict(t) for t in items]
        for slug, items in aggregate_todos(repo_root, module_paths_map).items()
    }
    api_surface = detect_api_surface(repo_root)

    scan_report = {
        "files": files,
        "languages": languages,
        "entry_points": entry_points,
        "external_deps": external_deps,
        "pack_metadata": pack_meta,
        "git": git_meta,
        "scanner_version": SCANNER_VERSION,
        # Narrative additions.
        "readme_sections": readme_sections,
        "changelog": _changelog_to_dict(changelog),
        "decision_docs": decision_docs,
        "stack": stack,
        "todos": todos,
        "api_surface": _api_surface_to_dict(api_surface),
    }

    return ScanResult(manifest=manifest, scan_report=scan_report)


def _changelog_to_dict(cl) -> dict:
    if cl is None:
        return {"unreleased": None, "recent_versions": []}
    return {
        "unreleased": cl.unreleased,
        "recent_versions": [asdict(v) for v in cl.recent_versions],
    }


def _api_surface_to_dict(surf) -> dict:
    return {
        "cli_commands": [asdict(c) for c in surf.cli_commands],
        "http_routes": [asdict(r) for r in surf.http_routes],
        "exports": [asdict(e) for e in surf.exports],
        "env_vars": [asdict(v) for v in surf.env_vars],
        "detection_status": surf.detection_status,
    }
```

- [ ] **Step 4: Run all architect tests**

Run: `uv run pytest tests/architect/ -v`
Expected: PASS (all previous + new test).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/scan.py tests/architect/test_scan.py
git commit -m "feat(architect): emit narrative signals in phase-1 scan-report"
```

---

## Phase C — Section synthesis base

### Task 11: `sections.py` foundation (signal collector, prompt builder, note composer)

This task is the heart of Phase 3.5 infrastructure. Each subsequent section generator (Tasks 12-17) imports from here.

**Files:**
- Create: `scripts/architect/sections.py`
- Create: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing tests for signal hashing**

Create `tests/architect/test_sections.py`:

```python
from pathlib import Path

from scripts.architect.sections import (
    SECTION_NAMES,
    build_prompt,
    collect_signals,
    compose_note,
    signal_hash,
)


def test_signal_hash_is_deterministic():
    sig = {"foo": "bar", "list": [1, 2, 3]}
    assert signal_hash(sig) == signal_hash(sig)


def test_signal_hash_changes_on_value_change():
    a = signal_hash({"k": "v1"})
    b = signal_hash({"k": "v2"})
    assert a != b


def test_signal_hash_independent_of_dict_order():
    a = signal_hash({"a": 1, "b": 2})
    b = signal_hash({"b": 2, "a": 1})
    assert a == b


def test_section_names_constant():
    assert SECTION_NAMES == ("api-surface", "features", "decisions", "roadmap", "future")


def test_collect_signals_features():
    scan_report = {
        "readme_sections": {"Features": "- alpha\n- beta"},
        "api_surface": {"cli_commands": [{"name": "foo", "description": "do foo", "source": "src/cli.py:1"}],
                        "http_routes": [], "exports": [], "env_vars": [], "detection_status": "complete"},
        "decision_docs": [],
        "changelog": {"unreleased": None, "recent_versions": []},
        "todos": {},
        "stack": {},
    }
    manifest_modules = [{"slug": "cli", "description": "CLI front-end", "paths": ["src/cli.py"]}]
    sig = collect_signals("features", scan_report, manifest_modules)
    assert sig["readme_features"] == "- alpha\n- beta"
    assert sig["cli_commands"][0]["name"] == "foo"
    assert sig["modules"][0]["slug"] == "cli"


def test_collect_signals_roadmap_pulls_changelog_and_todos():
    scan_report = {
        "readme_sections": {"Roadmap": "- streaming"},
        "changelog": {"unreleased": "- soon", "recent_versions": [{"version": "0.1.0", "date": "2026-01-01", "body": "init"}]},
        "todos": {"cli": [{"path": "src/cli.py", "line": 1, "kind": "TODO", "label": "roadmap", "text": "rate-limit"}]},
    }
    sig = collect_signals("roadmap", scan_report, manifest_modules=[])
    assert sig["readme_roadmap"] == "- streaming"
    assert sig["changelog_unreleased"] == "- soon"
    assert sig["roadmap_todos"][0]["text"] == "rate-limit"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement signal hashing and collectors in `sections.py`**

Create `scripts/architect/sections.py`:

```python
"""Section synthesis: signal collection, prompt building, note composition.

Each of the 5 narrative sections has its own signal subset. The signal subset
is hashed for refresh comparison. The composed note wraps LLM-generated body
in @generated sentinels and frontmatter.

LLM call itself happens in the slash command body (the agent). This module
provides pure helpers that the agent invokes for context and for writing.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date
from pathlib import Path

from scripts.architect.lang import heading

SECTION_NAMES = ("api-surface", "features", "decisions", "roadmap", "future")

# Section -> note filename (under Projects/<P>/Architecture/).
SECTION_FILENAMES = {
    "api-surface": "api-surface.md",
    "features": "features.md",
    "decisions": "decisions.md",
    "roadmap": "roadmap.md",
    "future": "future.md",
}

# Section -> frontmatter `type:` value.
SECTION_TYPES = {
    "api-surface": "architecture-api-surface",
    "features": "architecture-features",
    "decisions": "architecture-decisions",
    "roadmap": "architecture-roadmap",
    "future": "architecture-future",
}


def signal_hash(signal: dict) -> str:
    """Stable SHA-256 hash of a JSON-serializable signal dict."""
    canonical = json.dumps(signal, sort_keys=True, default=str).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def collect_signals(section: str, scan_report: dict, manifest_modules: list[dict]) -> dict:
    """Return the signal subset relevant to one section.

    Includes everything the LLM needs as context and everything that, if
    changed, should trigger regeneration.
    """
    if section not in SECTION_NAMES:
        raise ValueError(f"unknown section: {section}")
    readme = scan_report.get("readme_sections", {})
    cl = scan_report.get("changelog", {})
    todos = scan_report.get("todos", {})
    api = scan_report.get("api_surface", {})
    decision_docs = scan_report.get("decision_docs", [])
    stack = scan_report.get("stack", {})

    if section == "api-surface":
        return {
            "cli_commands": api.get("cli_commands", []),
            "http_routes": api.get("http_routes", []),
            "exports": api.get("exports", []),
            "env_vars": api.get("env_vars", []),
            "detection_status": api.get("detection_status", "none"),
        }
    if section == "features":
        return {
            "readme_features": readme.get("Features", ""),
            "cli_commands": api.get("cli_commands", []),
            "http_routes": api.get("http_routes", []),
            "modules": [{"slug": m["slug"], "description": m.get("description", ""), "paths": m.get("paths", [])} for m in manifest_modules],
        }
    if section == "decisions":
        return {
            "decision_docs": decision_docs,
            "stack": stack,
            "external_deps": scan_report.get("external_deps", []),
            "commit_message_decisions": scan_report.get("commit_decisions", []),
            "pattern_decisions": scan_report.get("pattern_decisions", []),
        }
    if section == "roadmap":
        roadmap_todos = []
        for slug, items in todos.items():
            if slug == "_unmapped":
                continue
            for t in items:
                if (t.get("label") or "").lower() in ("roadmap", "next", "plan"):
                    roadmap_todos.append({**t, "module": slug})
        return {
            "readme_roadmap": readme.get("Roadmap", "") or readme.get("Coming Soon", ""),
            "changelog_unreleased": cl.get("unreleased"),
            "changelog_recent": cl.get("recent_versions", []),
            "roadmap_todos": roadmap_todos,
        }
    if section == "future":
        future_todos = []
        for slug, items in todos.items():
            for t in items:
                if (t.get("label") or "").lower() in ("future", "idea", "someday"):
                    future_todos.append({**t, "module": slug})
        return {
            "readme_limitations": readme.get("Limitations", ""),
            "readme_known_issues": readme.get("Known Issues", ""),
            "readme_future_work": readme.get("Future Work", ""),
            "future_todos": future_todos,
            "truncated_modules": [m["slug"] for m in manifest_modules if m.get("scan_truncated")],
        }
    raise AssertionError("unreachable")  # pragma: no cover
```

- [ ] **Step 4: Run signal tests**

Run: `uv run pytest tests/architect/test_sections.py::test_signal_hash_is_deterministic tests/architect/test_sections.py::test_signal_hash_changes_on_value_change tests/architect/test_sections.py::test_signal_hash_independent_of_dict_order tests/architect/test_sections.py::test_section_names_constant tests/architect/test_sections.py::test_collect_signals_features tests/architect/test_sections.py::test_collect_signals_roadmap_pulls_changelog_and_todos -v`
Expected: PASS (6 tests).

- [ ] **Step 5: Write failing tests for prompt builder and note composer**

Append to `tests/architect/test_sections.py`:

```python
def test_build_prompt_en_lists_section_and_signals():
    prompt = build_prompt(
        section="features",
        signal={"readme_features": "- alpha", "cli_commands": [], "http_routes": [], "modules": []},
        output_lang="en",
        project="myproj",
    )
    assert "features" in prompt
    assert "English" in prompt or "en" in prompt
    assert "readme_features" in prompt


def test_build_prompt_zh_tw_demands_chinese_body_and_lists_dont_translate_rules():
    prompt = build_prompt(
        section="roadmap",
        signal={"readme_roadmap": "- streaming"},
        output_lang="zh-TW",
        project="myproj",
    )
    assert "繁體中文" in prompt or "zh-TW" in prompt
    # Spec §16.5 — must mention not-translating code identifiers.
    assert "code identifier" in prompt.lower() or "識別" in prompt or "檔名" in prompt


def test_compose_note_wraps_sentinels(tmp_path: Path):
    note = compose_note(
        section="features",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=["README.md", "src/cli.py"],
        confidence="high",
        output_lang="en",
        generated_blocks={"summary": "We do X.", "capability-map": "- alpha\n- beta"},
    )
    assert note.startswith("---\n")
    assert "type: architecture-features" in note
    assert "lang: en" in note
    assert "## For future Claude" in note
    assert "<!-- @generated:start summary -->" in note
    assert "We do X." in note
    assert "<!-- @generated:end summary -->" in note
    assert "<!-- @generated:start capability-map -->" in note


def test_compose_note_zh_tw_uses_translated_headings():
    note = compose_note(
        section="features",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=["README.md"],
        confidence="high",
        output_lang="zh-TW",
        generated_blocks={"summary": "做 X"},
    )
    assert "## 給未來 Claude" in note
    assert "## For future Claude" not in note
    assert "lang: zh-TW" in note


def test_compose_note_insufficient_signal_status():
    note = compose_note(
        section="future",
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        signal_sources=[],
        confidence="low",
        output_lang="en",
        generated_blocks={},
        status="insufficient-signal",
    )
    assert "status: insufficient-signal" in note
```

- [ ] **Step 6: Append `build_prompt` and `compose_note` to `sections.py`**

Append to `scripts/architect/sections.py`:

```python


_PROMPT_LANG_RULES_EN = (
    "Write the body in English. Preserve verbatim: file paths, function names, "
    "class names, variable names, CLI command strings, URLs."
)
_PROMPT_LANG_RULES_ZH = (
    "請以繁體中文 (Traditional Chinese, zh-TW) 撰寫散文與 heading。"
    "以下元素必須原樣保留英文 (code identifier / 機讀符號):"
    "檔案路徑、變數名、函式名、類別名、import path、CLI 命令字串、URL、"
    "frontmatter key、enum 值、wikilink 內的檔名段。"
    "範例:\n"
    "  ✅ 從 `src/cli.py:42` 的 `argparse` 解析器推論而來\n"
    "  ❌ From src/cli.py:42's argparse parser inferred\n"
    "  ❌ 從來源/cli.py:42 的 引數解析器 推論而來"
)

# Required @generated block names per section (preamble + body composition).
_BLOCK_NAMES = {
    "api-surface": ("summary", "cli-commands", "http-routes", "exports", "env-vars"),
    "features": ("summary", "capability-map", "notable-details"),
    "decisions": ("summary", "stack-rationale", "detected-adrs", "pattern-decisions",
                  "commit-message-decisions", "promote-to-adr"),
    "roadmap": ("summary", "near-term", "trajectory", "todo-clusters", "signals-reviewed"),
    "future": ("summary", "known-limitations", "gap-analysis", "aspirational-ideas"),
}


def build_prompt(section: str, signal: dict, output_lang: str, project: str) -> str:
    """Render the LLM prompt for a section synthesis."""
    rules = _PROMPT_LANG_RULES_ZH if output_lang == "zh-TW" else _PROMPT_LANG_RULES_EN
    blocks = _BLOCK_NAMES[section]
    lines = [
        f"You are synthesizing the `{section}` note for project `{project}`.",
        f"Output language: {output_lang}.",
        rules,
        "",
        "Produce one @generated block per name below. Each block body is the "
        "raw markdown text (no sentinel tags — those are added by the caller).",
        "Return JSON: {\"<block-name>\": \"<markdown body>\"}.",
        f"Required blocks: {list(blocks)}.",
        "",
        "Signal:",
        json.dumps(signal, indent=2, ensure_ascii=False, default=str),
    ]
    return "\n".join(lines)


def compose_note(
    *,
    section: str,
    project: str,
    repo_label: str,
    commit: str,
    signal_sources: list[str],
    confidence: str,
    output_lang: str,
    generated_blocks: dict[str, str],
    status: str = "current",
) -> str:
    """Assemble the final note markdown from LLM-generated blocks + metadata."""
    today = date.today().isoformat()
    type_value = SECTION_TYPES[section]
    tag_suffix = section.replace("-", "-")  # keep stable; e.g. "api-surface"
    fm_lines = [
        "---",
        f"type: {type_value}",
        f"date: {today}",
        f'project: "[[{project}]]"',
        f"repo: {repo_label}",
        f"last-scanned: {today}",
        f"commit: {commit}",
        f"sources: {json.dumps(signal_sources)}",
        f"confidence: {confidence}",
        f"lang: {output_lang}",
        f"tags: [architecture, {tag_suffix}]",
        "ai-first: true",
        f"status: {status}",
    ]
    if section == "api-surface":
        # detection-status hints at scanner confidence in the table contents.
        detection_status = "complete" if generated_blocks else "none"
        fm_lines.append(f"detection-status: {detection_status}")
    fm_lines.append("---")

    body_parts = [
        "",
        heading("## For future Claude", output_lang),
        _preamble_for(section, output_lang),
        "",
    ]
    for name in _BLOCK_NAMES[section]:
        body = generated_blocks.get(name, "").strip()
        if not body:
            continue
        body_parts.append(f"<!-- @generated:start {name} -->")
        body_parts.append(body)
        body_parts.append(f"<!-- @generated:end {name} -->")
        body_parts.append("")
    body_parts.append(heading("## Related", output_lang))
    body_parts.append(f"- [[Architecture/overview]]")
    body_parts.append(f"- [[{project}]]")
    return "\n".join(fm_lines + body_parts) + "\n"


def _preamble_for(section: str, lang: str) -> str:
    """Short preamble describing the note's purpose to future-Claude."""
    if lang == "zh-TW":
        return {
            "api-surface": "本檔是 API 介面參考表。要查命令或 endpoint 就看這裡。",
            "features": "本檔列出本 codebase 對使用者提供的能力。具體 CLI/HTTP 表在 [[Architecture/api-surface]],模組層級在 [[Architecture/modules]]。",
            "decisions": "本檔是關鍵技術決定的索引;真正的 ADR 應該透過 /obsidian-adr 升級到 Decisions/。",
            "roadmap": "本檔合成自 CHANGELOG、README、TODO 群組。標明來源,推論值低信心。",
            "future": "本檔是 gap 分析與北極星想法。多為推論,非已決方向。",
        }[section]
    return {
        "api-surface": "This is the API surface reference. Look up commands or endpoints here.",
        "features": "Capabilities exposed by this codebase. See [[Architecture/api-surface]] for the structured tables and [[Architecture/modules]] for per-module depth.",
        "decisions": "Index of key technical decisions. Promote individual entries to full ADRs via /obsidian-adr into Decisions/.",
        "roadmap": "Synthesized from CHANGELOG, README, and TODO clusters. Inference is marked.",
        "future": "Gap analysis and north-star ideas. Mostly inferred, not committed.",
    }[section]
```

- [ ] **Step 7: Run all sections tests**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS (11 tests).

- [ ] **Step 8: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): sections.py — signals, prompt builder, note composer"
```

---

## Phase D — Per-section generators

> **Note:** Tasks 12-16 are deterministic table renderers and signal-summary helpers consumed by the slash-command body. They do NOT call an LLM directly — the agent provides LLM output and passes it back through `compose_note()` from Task 11. What each Task 12-16 ADDS on top of Task 11 is a section-specific *deterministic content renderer* (api-surface tables, signals-reviewed lists, etc.) that doesn't need LLM help.

### Task 12: api-surface.md table renderer

api-surface is the most deterministic section: 4 tables straight from the scanner.

**Files:**
- Create: `scripts/architect/api_surface_render.py`
- Create: `tests/architect/test_api_surface_render.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_api_surface_render.py`:

```python
from scripts.architect.api_surface_render import (
    render_cli_table, render_http_table, render_exports_table, render_env_table,
)


def test_cli_table_en():
    rows = [{"name": "foo", "description": "do foo", "source": "src/cli.py:1", "module": "cli"}]
    table = render_cli_table(rows, lang="en")
    assert "| Command | Description | Source | Module |" in table
    assert "| `foo` | do foo | `src/cli.py:1` | [[modules/cli]] |" in table


def test_cli_table_zh():
    rows = [{"name": "foo", "description": "做 foo", "source": "src/cli.py:1", "module": "cli"}]
    table = render_cli_table(rows, lang="zh-TW")
    assert "| 指令 | 說明 | 來源 | 模組 |" in table


def test_empty_table_returns_empty_string():
    assert render_cli_table([], lang="en") == ""
    assert render_http_table([], lang="en") == ""


def test_http_table():
    rows = [{"method": "GET", "path": "/x", "handler": "get_x", "source": "src/api.py:5", "module": "api"}]
    table = render_http_table(rows, lang="en")
    assert "| Method | Path | Handler | Module |" in table
    assert "GET" in table and "`/x`" in table


def test_env_table_marks_required():
    rows = [
        {"name": "API_KEY", "required": True, "default": None, "source": "src/c.py:1", "used_by": "api"},
        {"name": "DB_URL", "required": False, "default": "sqlite://", "source": "src/c.py:2", "used_by": "db"},
    ]
    table = render_env_table(rows, lang="en")
    assert "API_KEY" in table and "yes" in table
    assert "DB_URL" in table and "sqlite://" in table
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_api_surface_render.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `api_surface_render.py`**

Create `scripts/architect/api_surface_render.py`:

```python
"""Deterministic markdown table renderers for api-surface.md sections.

These do not call an LLM. They turn scanner output into structured tables.
"""

from __future__ import annotations


_HEADERS = {
    "cli": {
        "en": ("Command", "Description", "Source", "Module"),
        "zh-TW": ("指令", "說明", "來源", "模組"),
    },
    "http": {
        "en": ("Method", "Path", "Handler", "Module"),
        "zh-TW": ("方法", "路徑", "Handler", "模組"),
    },
    "exports": {
        "en": ("Symbol", "Kind", "Source", "Module"),
        "zh-TW": ("符號", "種類", "來源", "模組"),
    },
    "env": {
        "en": ("Var", "Required", "Default", "Source"),
        "zh-TW": ("變數", "必填", "預設值", "來源"),
    },
}


def _table(headers: tuple[str, ...], rows: list[list[str]]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join(["---"] * len(headers)) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)
    return "\n".join([head, sep, body])


def render_cli_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["cli"][lang]
    body = [[f"`{r['name']}`", r.get("description", ""), f"`{r['source']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_http_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["http"][lang]
    body = [[r["method"], f"`{r['path']}`", f"`{r['handler']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_exports_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["exports"][lang]
    body = [[f"`{r['symbol']}`", r.get("kind", ""), f"`{r['source']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_env_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["env"][lang]
    yes_no = ("yes" if lang == "en" else "是", "no" if lang == "en" else "否")
    body = []
    for r in rows:
        body.append([
            f"`{r['name']}`",
            yes_no[0] if r.get("required") else yes_no[1],
            f"`{r['default']}`" if r.get("default") is not None else "",
            f"`{r['source']}`",
        ])
    return _table(h, body)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_api_surface_render.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/api_surface_render.py tests/architect/test_api_surface_render.py
git commit -m "feat(architect): api-surface table renderers (CLI/HTTP/exports/env)"
```

---

### Task 13: features.md — module-to-module helper

features.md is mostly LLM narrative, but it needs a helper that maps API surface entries to wikilinks. Keep that helper deterministic.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_module_for_path_returns_slug():
    from scripts.architect.sections import module_for_path
    manifest = [
        {"slug": "auth", "paths": ["src/auth"]},
        {"slug": "api", "paths": ["src/api/routes.py"]},
    ]
    assert module_for_path("src/auth/login.py", manifest) == "auth"
    assert module_for_path("src/api/routes.py", manifest) == "api"
    assert module_for_path("random/orphan.py", manifest) is None
```

- [ ] **Step 2: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_module_for_path_returns_slug -v`
Expected: FAIL — `module_for_path` not exported.

- [ ] **Step 3: Append `module_for_path` to `sections.py`**

Append:

```python


def module_for_path(rel_path: str, manifest_modules: list[dict]) -> str | None:
    """Return the slug of the module containing `rel_path`, or None."""
    src = rel_path.split(":")[0]
    for m in manifest_modules:
        for prefix in m.get("paths", []):
            if src == prefix or src.startswith(prefix.rstrip("/") + "/"):
                return m["slug"]
    return None
```

- [ ] **Step 4: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_module_for_path_returns_slug -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): module_for_path helper for features/api-surface wiring"
```

---

### Task 14: decisions.md — commit-message decision extractor

The "Commit-message decisions" sub-section requires deterministic mining of git log for the patterns listed in spec §6.

**Files:**
- Create: `scripts/architect/commit_decisions.py`
- Create: `tests/architect/test_commit_decisions.py`

- [ ] **Step 1: Write failing tests**

Create `tests/architect/test_commit_decisions.py`:

```python
import subprocess
from pathlib import Path

from scripts.architect.commit_decisions import extract_commit_decisions


def _git_repo(tmp_path: Path, commits: list[tuple[str, str]]):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@e"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    for fname, msg in commits:
        (tmp_path / fname).write_text("x")
        subprocess.run(["git", "-C", str(tmp_path), "add", fname], check=True)
        subprocess.run(["git", "-C", str(tmp_path), "commit", "-qm", msg], check=True)


def test_matches_decided(tmp_path: Path):
    _git_repo(tmp_path, [
        ("a.txt", "feat: add a"),
        ("b.txt", "chore: decided to use Postgres over MySQL"),
        ("c.txt", "fix: typo"),
    ])
    decisions = extract_commit_decisions(tmp_path, limit=10)
    assert any("decided to use Postgres" in d.message for d in decisions)


def test_matches_switched_chose_replaced(tmp_path: Path):
    _git_repo(tmp_path, [
        ("a", "switched from yarn to pnpm"),
        ("b", "chose Redis for cache"),
        ("c", "replaced flask with fastapi"),
        ("d", "moved to monorepo"),
    ])
    msgs = [d.message for d in extract_commit_decisions(tmp_path, limit=10)]
    assert len(msgs) == 4


def test_ignores_unrelated(tmp_path: Path):
    _git_repo(tmp_path, [("a", "bump version"), ("b", "wip")])
    assert extract_commit_decisions(tmp_path, limit=10) == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_commit_decisions.py -v`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `commit_decisions.py`**

Create `scripts/architect/commit_decisions.py`:

```python
"""Mine git commit messages for explicit technology / architecture decisions.

Patterns (case-insensitive) per spec §6:
  decided, chose, switched from, moved to, replaced X with Y
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

_PATTERN = re.compile(
    r"\b(?:decided|chose|switched\s+from|moved\s+to|replaced\b.+?\bwith)\b",
    re.IGNORECASE,
)


@dataclass
class CommitDecision:
    sha: str
    date: str
    message: str


def extract_commit_decisions(repo_root: Path, limit: int = 200) -> list[CommitDecision]:
    """Read recent commits and keep those whose message matches a decision pattern."""
    cmd = ["git", "-C", str(repo_root), "log", f"-n{limit}", "--pretty=%H%x01%cI%x01%s%n%b%x1e"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    decisions: list[CommitDecision] = []
    for record in out.split("\x1e"):
        record = record.strip()
        if not record:
            continue
        head, _, body = record.partition("\n")
        sha, date, subject = head.split("\x01", 2)
        full = (subject + "\n" + body).strip()
        if _PATTERN.search(full):
            decisions.append(CommitDecision(sha=sha[:7], date=date[:10], message=subject))
    return decisions
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_commit_decisions.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire commit_decisions into `scan.py`**

Edit `scripts/architect/scan.py` to call this detector. Find the section that builds `scan_report` and add:

```python
from scripts.architect.commit_decisions import extract_commit_decisions
# ...inside run_phase_one, before the scan_report dict:
commit_decisions = [asdict(c) for c in extract_commit_decisions(repo_root, limit=200)]
# Then in the dict, add:
        "commit_decisions": commit_decisions,
```

- [ ] **Step 6: Verify integration**

Run: `uv run pytest tests/architect/ -v`
Expected: PASS (all green; the section test consumed `commit_decisions` correctly).

- [ ] **Step 7: Commit**

```bash
git add scripts/architect/commit_decisions.py scripts/architect/scan.py tests/architect/test_commit_decisions.py
git commit -m "feat(architect): mine commit messages for decision-pattern matches"
```

---

### Task 15: roadmap.md — signals-reviewed renderer

Roadmap relies heavily on LLM narrative, but the "Signals reviewed" footer is deterministic and gives transparency.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_render_signals_reviewed_en():
    from scripts.architect.sections import render_signals_reviewed
    out = render_signals_reviewed(
        sources=["CHANGELOG.md", "README.md#Roadmap"],
        todo_counts={"cli": 3, "api": 1},
        lang="en",
    )
    assert "CHANGELOG.md" in out
    assert "README.md#Roadmap" in out
    assert "cli: 3 TODOs" in out


def test_render_signals_reviewed_zh():
    from scripts.architect.sections import render_signals_reviewed
    out = render_signals_reviewed(sources=["CHANGELOG.md"], todo_counts={"cli": 2}, lang="zh-TW")
    assert "cli:" in out
    assert "2" in out
```

- [ ] **Step 2: Run test**

Run: `uv run pytest tests/architect/test_sections.py::test_render_signals_reviewed_en tests/architect/test_sections.py::test_render_signals_reviewed_zh -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `render_signals_reviewed` to `sections.py`**

```python


def render_signals_reviewed(sources: list[str], todo_counts: dict[str, int], lang: str) -> str:
    """Emit the deterministic 'Signals reviewed' tail block."""
    todo_word = "TODOs" if lang == "en" else "個 TODO"
    parts = []
    for src in sources:
        parts.append(f"- `{src}`")
    for slug, n in sorted(todo_counts.items()):
        parts.append(f"- {slug}: {n} {todo_word}" if lang == "en" else f"- {slug}: {n} {todo_word}")
    return "\n".join(parts)
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS (all green).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): roadmap signals-reviewed renderer"
```

---

### Task 16: future.md — gap-analysis helper

Gap analysis is deterministic: features mentioned in README but not detected in api-surface.

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_gap_analysis_lists_mentioned_but_not_detected():
    from scripts.architect.sections import gap_analysis
    readme_features = "- Streaming HTTP\n- Plugin system\n- gRPC adapter\n"
    api = {
        "cli_commands": [],
        "http_routes": [{"method": "GET", "path": "/items"}],
        "exports": [{"symbol": "plugin_register", "kind": "named", "source": ""}],
        "env_vars": [],
    }
    gaps = gap_analysis(readme_features=readme_features, api_surface=api)
    # plugin_register suggests plugin system is implemented; streaming and gRPC are not.
    text = "\n".join(gaps)
    assert "Streaming" in text or "streaming" in text
    assert "gRPC" in text


def test_gap_analysis_empty_when_no_readme_features():
    from scripts.architect.sections import gap_analysis
    assert gap_analysis(readme_features="", api_surface={}) == []
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_sections.py::test_gap_analysis_lists_mentioned_but_not_detected tests/architect/test_sections.py::test_gap_analysis_empty_when_no_readme_features -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `gap_analysis` to `sections.py`**

```python


def gap_analysis(*, readme_features: str, api_surface: dict) -> list[str]:
    """Return bullets for features mentioned in README that the scanner could not locate.

    Heuristic: tokenize README feature bullets; check whether ANY surface entry's
    name/path/handler/symbol contains a normalized token. Bullets with no match
    become gap candidates.
    """
    if not readme_features:
        return []
    surface_strings = []
    for c in api_surface.get("cli_commands", []):
        surface_strings.append(c.get("name", "").lower())
        surface_strings.append(c.get("description", "").lower())
    for r in api_surface.get("http_routes", []):
        surface_strings.append(r.get("path", "").lower())
        surface_strings.append(r.get("handler", "").lower())
    for e in api_surface.get("exports", []):
        surface_strings.append(e.get("symbol", "").lower())
    haystack = " ".join(surface_strings)

    gaps: list[str] = []
    for line in readme_features.splitlines():
        line = line.strip()
        if not line.startswith("-"):
            continue
        bullet = line.lstrip("- ").strip()
        tokens = [t for t in bullet.lower().split() if len(t) > 3]
        if not any(t in haystack for t in tokens):
            gaps.append(bullet)
    return gaps
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): gap_analysis helper for future.md"
```

---

### Task 17: function-level note composer (`--functions=public`)

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing test**

Append to `tests/architect/test_sections.py`:

```python
def test_compose_function_note_en():
    from scripts.architect.sections import compose_function_note
    note = compose_function_note(
        project="myproj",
        repo_label="github.com/x/y",
        module_slug="cli",
        name="run",
        signature="def run(args: list[str]) -> int",
        source_file="src/cli.py",
        line_range="42-58",
        commit="abc1234",
        output_lang="en",
        generated_blocks={"what-it-does": "Entry point for CLI."},
    )
    assert "type: architecture-function" in note
    assert "module-slug: cli" in note
    assert "## Signature" in note
    assert "def run(args: list[str]) -> int" in note
    assert "Entry point for CLI." in note


def test_compose_function_note_zh_tw_translates_headings():
    from scripts.architect.sections import compose_function_note
    note = compose_function_note(
        project="myproj",
        repo_label="github.com/x/y",
        module_slug="cli",
        name="run",
        signature="def run() -> int",
        source_file="src/cli.py",
        line_range="42-58",
        commit="abc1234",
        output_lang="zh-TW",
        generated_blocks={"what-it-does": "CLI 入口點。"},
    )
    assert "## 函式簽章" in note
    assert "## 功能說明" in note
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_sections.py::test_compose_function_note_en tests/architect/test_sections.py::test_compose_function_note_zh_tw_translates_headings -v`
Expected: FAIL — function not defined.

- [ ] **Step 3: Append `compose_function_note` to `sections.py`**

```python


_FUNCTION_BLOCK_NAMES = ("what-it-does", "inputs-and-outputs", "behavior-notes", "callers")


def compose_function_note(
    *,
    project: str,
    repo_label: str,
    module_slug: str,
    name: str,
    signature: str,
    source_file: str,
    line_range: str,
    commit: str,
    output_lang: str,
    generated_blocks: dict[str, str],
) -> str:
    today = date.today().isoformat()
    fm = [
        "---",
        "type: architecture-function",
        f"date: {today}",
        f'project: "[[{project}]]"',
        f"repo: {repo_label}",
        f"module-slug: {module_slug}",
        f'display-name: "{name}"',
        f'signature: "{signature}"',
        f"source-file: {source_file}",
        f"line-range: {line_range}",
        f"last-scanned: {today}",
        f"commit: {commit}",
        f"lang: {output_lang}",
        "tags: [architecture, function]",
        "ai-first: true",
        "status: current",
        "---",
    ]
    body = [
        "",
        heading("## For future Claude", output_lang),
        ("函式 `" + name + "` 的單頁說明,與 [[modules/" + module_slug + "]] 連動。") if output_lang == "zh-TW"
        else ("Single-function reference for `" + name + "`. See [[modules/" + module_slug + "]] for context."),
        "",
        heading("## Signature", output_lang),
        "```",
        signature,
        "```",
        "",
    ]
    for blk in _FUNCTION_BLOCK_NAMES:
        text = generated_blocks.get(blk, "").strip()
        if not text:
            continue
        # Block name -> canonical heading. Hard-coded to keep heading names exact.
        h_map = {
            "what-it-does": "## What it does",
            "inputs-and-outputs": "## Inputs and outputs",
            "behavior-notes": "## Behavior notes",
            "callers": "## Callers",
        }
        body.append(heading(h_map[blk], output_lang))
        body.append(f"<!-- @generated:start {blk} -->")
        body.append(text)
        body.append(f"<!-- @generated:end {blk} -->")
        body.append("")
    body.append(heading("## Related", output_lang))
    body.append(f"- [[modules/{module_slug}]]")
    body.append(f"- [[Architecture/api-surface]]")
    return "\n".join(fm + body) + "\n"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): compose_function_note for --functions=public"
```

---

## Phase E — Overview MOC + refresh decisions

### Task 18: Overview MOC composer (stack frontmatter + MOC body)

**Files:**
- Modify: `scripts/architect/sections.py`
- Modify: `tests/architect/test_sections.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_sections.py`:

```python
def test_compose_overview_en_emits_moc():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={"primary-language": "Python", "frameworks": ["FastAPI"]},
        output_lang="en",
        modules=[{"slug": "cli", "display_name": "CLI"}, {"slug": "api", "display_name": "API"}],
        entry_points=[{"path": "src/cli.py", "label": "pyproject.scripts.run", "kind": "pyproject"}],
        generated_blocks={
            "purpose": "We do things.",
            "layer-map": "```mermaid\ngraph TD\n  A --> B\n```",
            "external-deps": "- FastAPI 0.110",
            "key-abstractions": "- Module",
        },
    )
    assert "type: architecture-overview" in note
    assert "moc-style: true" in note
    assert "primary-language: Python" in note
    assert "## Capability MOC" in note
    assert "[[Architecture/features]]" in note
    assert "[[Architecture/api-surface]]" in note
    assert "[[modules/cli]]" in note
    assert "graph TD" in note


def test_compose_overview_zh_tw_translates_and_omits_empty_stack():
    from scripts.architect.sections import compose_overview
    note = compose_overview(
        project="myproj",
        repo_label="github.com/x/y",
        commit="abc1234",
        stack={},  # empty -> no stack block in frontmatter
        output_lang="zh-TW",
        modules=[],
        entry_points=[],
        generated_blocks={},
    )
    assert "## 給未來 Claude" in note
    assert "## 能力地圖 MOC" in note
    assert "stack:" not in note  # empty stack omitted per spec §5.7
```

- [ ] **Step 2: Run tests**

Run: `uv run pytest tests/architect/test_sections.py::test_compose_overview_en_emits_moc tests/architect/test_sections.py::test_compose_overview_zh_tw_translates_and_omits_empty_stack -v`
Expected: FAIL — `compose_overview` not defined.

- [ ] **Step 3: Append `compose_overview` to `sections.py`**

```python


def _yaml_block(name: str, mapping: dict, indent: int = 2) -> str:
    """Render a simple flat YAML block. Lists are inline JSON-ish."""
    if not mapping:
        return ""
    out = [f"{name}:"]
    pad = " " * indent
    for k, v in mapping.items():
        if isinstance(v, list):
            out.append(f"{pad}{k}: [{', '.join(str(x) for x in v)}]")
        else:
            out.append(f"{pad}{k}: {v}")
    return "\n".join(out)


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
    """Compose the MOC-style overview.md."""
    today = date.today().isoformat()
    fm = [
        "---",
        "type: architecture-overview",
        "moc-style: true",
        f"date: {today}",
        f'project: "[[{project}]]"',
        f"repo: {repo_label}",
        f"last-scanned: {today}",
        f"commit: {commit}",
        f"lang: {output_lang}",
        "tags: [architecture, codebase-doc, moc]",
        "ai-first: true",
        "status: current",
    ]
    if stack:
        fm.append(_yaml_block("stack", stack))
    fm.append("---")

    body = [
        "",
        heading("## For future Claude", output_lang),
    ]
    if output_lang == "zh-TW":
        body.append("這個檔是 MOC。不要直接讀這裡的內容,跟著 wikilink 走。每個深入內容在自己的 note,future-Claude 想 grep 一段就 grep 那一段。")
    else:
        body.append("This note is a MOC. Don't read it for content — follow the wikilinks. Each deep-dive lives in its own note so you can grep one without loading the rest.")
    body.append("")

    # Purpose (LLM block).
    if generated_blocks.get("purpose"):
        body.append(heading("## Purpose", output_lang))
        body.append("<!-- @generated:start purpose -->")
        body.append(generated_blocks["purpose"])
        body.append("<!-- @generated:end purpose -->")
        body.append("")

    # Stack (mirrors frontmatter, deterministic).
    if stack:
        body.append(heading("## Stack", output_lang))
        for k, v in stack.items():
            if isinstance(v, list):
                body.append(f"- **{k}:** {', '.join(str(x) for x in v)}")
            else:
                body.append(f"- **{k}:** {v}")
        suffix = "(見 [[Architecture/decisions]] 的理由)" if output_lang == "zh-TW" else "(see [[Architecture/decisions]] for rationale)"
        body.append("")
        body.append(suffix)
        body.append("")

    # Capability MOC (deterministic).
    body.append(heading("## Capability MOC", output_lang))
    body.append("- [[Architecture/features]]")
    body.append("- [[Architecture/roadmap]]")
    body.append("- [[Architecture/decisions]]")
    body.append("- [[Architecture/future]]")
    body.append("")
    body.append(heading("## API surface", output_lang))
    body.append("- [[Architecture/api-surface]]")
    body.append("")

    # Structure MOC (deterministic).
    body.append(heading("## Structure MOC", output_lang))
    for m in modules:
        body.append(f"- [[modules/{m['slug']}]]")
    if entry_points:
        ep_label = "Entry points" if output_lang == "en" else "進入點"
        body.append(f"- **{ep_label}:**")
        for ep in entry_points:
            body.append(f"  - `{ep['label']}` -> `{ep['path']}`")
    body.append("")

    # Layer map (LLM block).
    if generated_blocks.get("layer-map"):
        body.append(heading("## Layer map", output_lang))
        body.append("<!-- @generated:start layer-map -->")
        body.append(generated_blocks["layer-map"])
        body.append("<!-- @generated:end layer-map -->")
        body.append("")

    # External deps (LLM block, deterministic-ish).
    if generated_blocks.get("external-deps"):
        body.append(heading("## External dependencies", output_lang))
        body.append("<!-- @generated:start external-deps -->")
        body.append(generated_blocks["external-deps"])
        body.append("<!-- @generated:end external-deps -->")
        body.append("")

    # Key abstractions (LLM).
    if generated_blocks.get("key-abstractions"):
        body.append(heading("## Key abstractions", output_lang))
        body.append("<!-- @generated:start key-abstractions -->")
        body.append(generated_blocks["key-abstractions"])
        body.append("<!-- @generated:end key-abstractions -->")
        body.append("")

    body.append(heading("## Related", output_lang))
    body.append(f"- [[{project}]]")
    return "\n".join(fm + body) + "\n"
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/architect/test_sections.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sections.py tests/architect/test_sections.py
git commit -m "feat(architect): compose_overview — MOC-style with stack frontmatter"
```

---

### Task 19: `decide_section_refresh()` and Hub `## Architecture` rendering

**Files:**
- Modify: `scripts/architect/refresh.py`
- Modify: `tests/architect/test_refresh.py`
- Create: `tests/architect/test_hub_section.py`

- [ ] **Step 1: Write failing test for refresh decision**

Append to `tests/architect/test_refresh.py`:

```python
def test_decide_section_refresh_first_run():
    from scripts.architect.lockfile import Lockfile
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0")
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.GENERATE


def test_decide_section_refresh_unchanged_skips():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(
        version=2,
        scanner_version="0.2.0",
        sections={"features": {"signal-hash": hash_value("X"), "lang": "en",
                                "note-blocks-hash": "", "last-generated": ""}},
    )
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.SKIP


def test_decide_section_refresh_signal_changed():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="Y", current_lang="en", force=False, refresh_flag=False)
    assert action == RefreshAction.REGENERATE


def test_decide_section_refresh_lang_changed():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="zh-TW", force=False, refresh_flag=False)
    assert action == RefreshAction.REGENERATE


def test_decide_section_refresh_force_always_regenerates():
    from scripts.architect.lockfile import Lockfile, hash_value
    from scripts.architect.refresh import decide_section_refresh, RefreshAction
    lock = Lockfile(version=2, scanner_version="0.2.0",
                    sections={"features": {"signal-hash": hash_value("X"), "lang": "en", "note-blocks-hash": "", "last-generated": ""}})
    action = decide_section_refresh(lock, section="features", current_signal="X", current_lang="en", force=True, refresh_flag=False)
    assert action == RefreshAction.REGENERATE
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_refresh.py -v`
Expected: FAIL — `decide_section_refresh` not defined.

- [ ] **Step 3: Append to `scripts/architect/refresh.py`**

```python


def decide_section_refresh(
    lock,
    *,
    section: str,
    current_signal: str,
    current_lang: str,
    force: bool = False,
    refresh_flag: bool = False,
) -> RefreshAction:
    """Decide what to do with a narrative-section note.

    - First run (no lockfile entry): GENERATE
    - --force: REGENERATE always
    - signal or lang differs: REGENERATE
    - otherwise: SKIP

    `refresh_flag` is reserved for future per-section --refresh semantics; today
    it is treated identically to no flag (skip on unchanged signal).
    """
    from scripts.architect.lockfile import section_signal_was_changed
    if force:
        return RefreshAction.REGENERATE
    if section_signal_was_changed(lock, section, current_signal=current_signal, current_lang=current_lang):
        record = lock.sections.get(section)
        return RefreshAction.GENERATE if record is None else RefreshAction.REGENERATE
    return RefreshAction.SKIP
```

- [ ] **Step 4: Write failing test for hub section renderer**

Create `tests/architect/test_hub_section.py`:

```python
from scripts.architect.refresh import render_hub_architecture_block


def test_hub_block_en():
    block = render_hub_architecture_block(
        commit="abc1234",
        last_scanned="2026-05-27",
        modules_active=4,
        modules_deprecated=1,
        repo_path="/path/to/repo",
        lang="en",
    )
    assert "## Architecture" in block
    assert "Overview: [[Architecture/overview]]" in block
    assert "(last scanned 2026-05-27 @ `abc1234`)" in block
    assert "Modules: 4 active, 1 deprecated" in block
    assert "/path/to/repo" in block


def test_hub_block_zh_tw():
    block = render_hub_architecture_block(
        commit="abc1234",
        last_scanned="2026-05-27",
        modules_active=4,
        modules_deprecated=1,
        repo_path="/path/to/repo",
        lang="zh-TW",
    )
    assert "## 架構" in block
    assert "總覽:" in block
    assert "(上次掃描 2026-05-27 @ `abc1234`)" in block
    assert "模組: 4 active, 1 deprecated" in block
```

- [ ] **Step 5: Run test**

Run: `uv run pytest tests/architect/test_hub_section.py -v`
Expected: FAIL — function not defined.

- [ ] **Step 6: Append `render_hub_architecture_block` to `refresh.py`**

```python


def render_hub_architecture_block(
    *,
    commit: str,
    last_scanned: str,
    modules_active: int,
    modules_deprecated: int,
    repo_path: str,
    lang: str,
) -> str:
    """Render the `## Architecture` block written into Projects/<P>/<P>.md."""
    if lang == "zh-TW":
        return "\n".join([
            "## 架構",
            "",
            f"- 總覽: [[Architecture/overview]] (上次掃描 {last_scanned} @ `{commit}`)",
            f"- 能力: [[Architecture/features]] | [[Architecture/api-surface]]",
            f"- 方向: [[Architecture/roadmap]] | [[Architecture/future]]",
            f"- 理由: [[Architecture/decisions]]",
            f"- 模組: {modules_active} active, {modules_deprecated} deprecated",
            f"- 重新整理: `/obsidian-architect {repo_path} --refresh`",
        ])
    return "\n".join([
        "## Architecture",
        "",
        f"- Overview: [[Architecture/overview]] (last scanned {last_scanned} @ `{commit}`)",
        f"- Capabilities: [[Architecture/features]] | [[Architecture/api-surface]]",
        f"- Direction: [[Architecture/roadmap]] | [[Architecture/future]]",
        f"- Rationale: [[Architecture/decisions]]",
        f"- Modules: {modules_active} active, {modules_deprecated} deprecated",
        f"- Refresh: `/obsidian-architect {repo_path} --refresh`",
    ])
```

- [ ] **Step 7: Run all refresh + hub tests**

Run: `uv run pytest tests/architect/test_refresh.py tests/architect/test_hub_section.py -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/architect/refresh.py tests/architect/test_refresh.py tests/architect/test_hub_section.py
git commit -m "feat(architect): section refresh decision + bilingual hub block renderer"
```

---

## Phase F — Schema documentation

### Task 20: Update `references/ai-first-rules.md`

This is documentation work — no Python tests, but the file is the authoritative schema for ai-first compliance.

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Read current `## Language` and architecture-overview/module entries**

Run: `grep -n "type: architecture" references/ai-first-rules.md`

Expected output: line numbers for the 3 existing entries (overview, module, data-flow).

- [ ] **Step 2: Add the new "Language" preamble section after the top header**

Open `references/ai-first-rules.md` and find the top-level introduction (before the first `### type:` heading). Add this block:

```markdown
## Language

Default note language is English. If the vault's `_CLAUDE.md` contains a line
`- output-lang: zh-TW`, all prose, headings, and human-readable text in
generated notes use Traditional Chinese. Frontmatter keys, enum values,
wikilink paths, sentinel HTML comments, code identifiers (file paths,
function names, class names, variable names, CLI command strings, URLs),
and recency markers like `(as of 2026-04, source-url)` remain English.

Architect commands respect the `--lang=<zh-TW|en>` flag for per-call
override. Other commands may follow the same pattern; until they do, hub
notes may temporarily contain mixed-language headings.

In zh-TW mode, the universal heading `## For future Claude` becomes
`## 給未來 Claude`; `## Related` becomes `## 相關`. Each `type:` below
lists its full bilingual heading set when relevant.
```

- [ ] **Step 3: Extend `architecture-overview` entry**

Find the existing `### type: architecture-overview` section. After the
"Required frontmatter" bullet list, add:

```markdown
Optional frontmatter (set when scanner can confidently fill):
- `moc-style: true` — set on every overview produced by the narrative pipeline
- `stack:` — block with keys `primary-language`, `frameworks` (list), `build`,
  `test`, `deploy`. Omit fields the scanner cannot confidently infer.
- `lang: zh-TW | en` — set to the effective output language.
```

- [ ] **Step 4: Add new `architecture-features` entry**

After the existing `architecture-module` entry, add:

```markdown
### `type: architecture-features`

Generated by `/obsidian-architect`. Lives at `Projects/<P>/Architecture/features.md`.

Required frontmatter:
- `type: architecture-features`
- `date`, `project` (wikilink), `repo`, `last-scanned`, `commit`
- `sources` (list of files actually read)
- `confidence: high | medium | low`
- `lang: zh-TW | en`
- `tags: [architecture, features]`
- `ai-first: true`, `status: current | insufficient-signal | scan-failed`

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Summary` / `## 摘要`
- `## Capability map` / `## 能力地圖`
- `## Notable details` / `## 補充細節` (optional)
- `## Related` / `## 相關`

LLM-written sections wrapped in `<!-- @generated:start <name> -->` ... `<!-- @generated:end <name> -->` sentinels.
```

- [ ] **Step 5: Add `architecture-roadmap`, `architecture-decisions`, `architecture-future`, `architecture-api-surface`**

Follow the same template as features. Use the per-section heading table from spec §16.8 for the bilingual heading list.

Copy and adapt for each:
- `architecture-roadmap`: tags `[architecture, roadmap]`; body `## Summary`, `## Near term` / `## 近期`, `## Trajectory` / `## 軌跡`, `## TODO clusters` / `## TODO 群組`, `## Signals reviewed` / `## 已檢視訊號`.
- `architecture-decisions`: tags `[architecture, decisions]`; body `## Summary`, `## Stack rationale` / `## 技術棧理由`, `## Detected ADRs` / `## 已偵測的 ADR`, `## Pattern decisions` / `## 模式決定`, `## Commit-message decisions` / `## Commit 訊息決定`, `## Promote to ADR` / `## 建議升級為 ADR`.
- `architecture-future`: tags `[architecture, future]`; body `## Summary`, `## Known limitations` / `## 已知限制`, `## Gap analysis` / `## 落差分析`, `## Aspirational ideas` / `## 期望中的想法`.
- `architecture-api-surface`: tags `[architecture, api-surface]`; extra frontmatter `detection-status: complete | partial | none`; body `## CLI commands` / `## CLI 命令`, `## HTTP routes` / `## HTTP 路由`, `## Public exports` / `## 公開匯出`, `## Environment variables` / `## 環境變數`.

- [ ] **Step 6: Add `architecture-function` (optional layer)**

```markdown
### `type: architecture-function` (optional)

Generated only when `/obsidian-architect` is run with `--functions=public`.
Lives at `Projects/<P>/Architecture/functions/<module-slug>/<func-slug>.md`.

Required frontmatter:
- `type: architecture-function`
- `date`, `project`, `repo`, `module-slug`, `display-name`, `signature`,
  `source-file`, `line-range`, `last-scanned`, `commit`
- `lang: zh-TW | en`
- `tags: [architecture, function]`
- `ai-first: true`, `status: current | deprecated`

Body sections (en / zh-TW):
- `## For future Claude` / `## 給未來 Claude`
- `## Signature` / `## 函式簽章` (verbatim code block)
- `## What it does` / `## 功能說明`
- `## Inputs and outputs` / `## 輸入輸出`
- `## Behavior notes` / `## 行為註記`
- `## Callers` / `## 呼叫者`
- `## Related` / `## 相關`
```

- [ ] **Step 7: Verify file builds**

Run: `bash scripts/build.sh --platform claude-code`
Expected: no errors; `dist/claude-code/references/ai-first-rules.md` mirrors the source.

- [ ] **Step 8: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(ai-first-rules): add 6 architecture-* types and language preamble"
```

---

## Phase G — Command body + adapters

### Task 21: Rewrite `commands/obsidian-architect.md`

This is the agent-facing instruction set. The Python helpers from Tasks 1-19 are now wired in via deterministic invocation in the command body.

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Read current command body to know what stays and what changes**

Run: `wc -l commands/obsidian-architect.md`
Expected: ~164 lines (the existing v1 body).

- [ ] **Step 2: Update Phase 1 section**

Find the "## Phase 1: Deterministic scan" block. Replace its description to mention the extended scan-report:

```markdown
## Phase 1: Deterministic scan

Run:

```bash
uv run python scripts/architect_scan.py <repo-path> --out /tmp/architect-<hash>/
```

This produces `/tmp/architect-<hash>/_manifest.yml` and `scan-report.json`.

The scan-report includes manifest signals AND narrative signals:
`readme_sections`, `changelog`, `decision_docs`, `stack`, `todos`, `api_surface`,
`commit_decisions`. Phase 3.5 consumes these.

If `--dry-run`, print the manifest to the user and stop. No vault writes.
```

- [ ] **Step 3: Add new Phase 3.5 section between Phase 3 and "## Overview synthesis"**

Insert after the existing Phase 3 block:

````markdown
## Phase 3.5: Per-section synthesis

Resolve `output_lang`:

```bash
uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
```

For each section in order (`api-surface`, `features`, `decisions`, `roadmap`,
`future`), and for each non-skipped section per `--skip-sections` /
`--only-sections`:

1. Call `scripts.architect.sections.collect_signals(section, scan_report, manifest_modules)` to get the signal subset.
2. Compute `signal_hash(signal)` and call `scripts.architect.refresh.decide_section_refresh(lock, section=..., current_signal=hash, current_lang=output_lang, force=force, refresh_flag=refresh)`. If SKIP, continue.
3. For api-surface, use the deterministic table renderers from `scripts.architect.api_surface_render` — no LLM call for the table contents; LLM only writes the `summary` block.
4. For features / decisions / roadmap / future, build the LLM prompt with `sections.build_prompt(...)`, run it, parse the JSON response into a `{block-name: body}` dict.
5. Call `sections.compose_note(section=..., generated_blocks=..., output_lang=..., ...)` to assemble the markdown.
6. Write to `Projects/<P>/Architecture/<filename>`.
7. Update the lockfile `sections[<name>]` entry with the new `signal-hash`, `lang`, `note-blocks-hash`, and `last-generated` timestamp.

For per-section content rules see `references/ai-first-rules.md` §language and §architecture-*.

If `--functions=public`:

8. Call `scripts.architect.public_surface.eligible_functions(api_surface, module_paths)` to get the candidate list.
9. For each candidate, run an LLM call to produce the body blocks (`what-it-does`, `inputs-and-outputs`, `behavior-notes`, `callers`).
10. Call `sections.compose_function_note(...)` and write to `Projects/<P>/Architecture/functions/<module>/<func>.md`.
11. Update lockfile `functions[<module>/<func>]`.

Failure isolation: if any one section or function synthesis throws, write the note with `status: scan-failed`, record the error in the body, and continue.
````

- [ ] **Step 4: Replace the "## Overview synthesis" block**

Replace the existing overview synthesis block (around line 105-118) with:

````markdown
## Overview synthesis (Phase 4 — MOC style)

Read every section note's `## Summary` block, plus stack, modules, and entry
points from the scan-report.

Run an LLM call to produce only the @generated blocks (`purpose`, `layer-map`,
`external-deps`, `key-abstractions`). The bilingual headings, Capability MOC,
Structure MOC, and stack body are rendered deterministically by
`sections.compose_overview()`.

Write the result to `Projects/<P>/Architecture/overview.md`. The frontmatter
includes `moc-style: true`, the detected `stack:` block (omitted if empty),
and `lang: <output_lang>`.

`overview.md` body section order (matching `compose_overview`):
1. `## For future Claude` / `## 給未來 Claude`
2. `## Purpose` / `## 用途` (LLM block)
3. `## Stack` / `## 技術棧` (deterministic, mirrors frontmatter)
4. `## Capability MOC` / `## 能力地圖 MOC` (wikilinks to all 4 narrative sections)
5. `## API surface` / `## API 介面` (wikilink to api-surface.md)
6. `## Structure MOC` / `## 結構地圖 MOC` (module wikilinks + entry points)
7. `## Layer map` / `## 分層圖` (LLM Mermaid block)
8. `## External dependencies` / `## 外部相依` (LLM block)
9. `## Key abstractions` / `## 核心抽象` (LLM block)
10. `## Related` / `## 相關`
````

- [ ] **Step 5: Replace the "## Hub note update" block**

Replace the existing block with:

````markdown
## Hub note update

Generate the `## Architecture` block via
`scripts.architect.refresh.render_hub_architecture_block(...)`, passing
`lang=output_lang`. Append or replace in `Projects/<P>/<P>.md`.

In `en` mode, the heading is `## Architecture`; in `zh-TW`, `## 架構`.
Idempotent: section exists -> replace in place; otherwise append.

Note: other commands (`/obsidian-project`, `/obsidian-board`) may still
write English headings into the same hub. Mixed-language is tolerated
during the cross-command rollout.
````

- [ ] **Step 6: Update the front-of-file flag documentation**

Find the line documenting flags (near the top, around "Optional flags:") and replace with:

```markdown
The argument is `<repo-path>` (local path or github URL). Optional flags:
`--project=<P>` (force project hub binding), `--refresh` (explicit refresh),
`--dry-run` (Phase 1 only, no vault writes), `--force` (ignore "no changes" gate),
`--functions=<off|public>` (default off; `public` generates per-function notes
for symbols on the public API surface), `--skip-sections=<csv>` and
`--only-sections=<csv>` for surgical regeneration, `--lang=<en|zh-TW>` to
override the vault default from `_CLAUDE.md`'s `- output-lang:` line.
```

- [ ] **Step 7: Update the AI-first reminder footer**

Find the bottom-of-file `**AI-first rule:**` paragraph. Append:

```markdown

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag as a single-run override. Run `scripts.architect.lang.resolve_output_lang(cli_flag, vault_root)` to get the effective language. All narrative section notes, the overview MOC, modules, and the hub `## Architecture` block must use that language. Code identifiers (paths, function names, CLI commands, URLs) and frontmatter keys/enums/sentinels remain English regardless. See `references/ai-first-rules.md` for the full rule set.
```

- [ ] **Step 8: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: all 4 adapter dist trees regenerate without errors.

- [ ] **Step 9: Inspect adapter output for one platform**

Run: `wc -l dist/codex-cli/.codex/commands/obsidian-architect.md`
Expected: similar line count to source; tool-name rewrites applied.

Run: `grep -c "Read tool" dist/codex-cli/.codex/commands/obsidian-architect.md`
Expected: 0 (rewritten to neutral wording by the adapter).

- [ ] **Step 10: Commit**

```bash
git add commands/obsidian-architect.md dist/
git commit -m "feat(architect): rewrite command body for Phase 3.5 + MOC + --lang"
```

---

## Phase H — Polish

### Task 22: CHANGELOG, SKILL.md, README.md, end-to-end smoke

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `SKILL.md`
- Modify: `README.md`

- [ ] **Step 1: Add CHANGELOG entry under Unreleased**

Open `CHANGELOG.md`. Find the `## Unreleased` heading (add it if missing,
right under the title). Append:

```markdown
### Added
- `/obsidian-architect` now produces narrative section notes alongside the
  module deep-dives: `features.md`, `roadmap.md`, `decisions.md`,
  `future.md`, and `api-surface.md`. `overview.md` becomes a MOC with a
  `stack:` frontmatter block.
- Optional function-level layer via `--functions=public` writes
  `Architecture/functions/<module>/<func>.md` for public-surface symbols.
- `--skip-sections=<csv>` and `--only-sections=<csv>` for surgical
  section regeneration; `--lang=<zh-TW|en>` for per-call language
  override. Vault-wide default lives in `_CLAUDE.md` as
  `- output-lang: zh-TW`.

### Changed
- Lockfile schema bumped to v2: adds `sections` and `functions` blocks,
  plus a `lang` field per entry. v1 lockfiles migrate silently (first
  v2 run regenerates all sections once; module entries are preserved).
- `references/ai-first-rules.md` documents 5 new `type:` values
  (`architecture-features`, `architecture-roadmap`, `architecture-decisions`,
  `architecture-future`, `architecture-api-surface`), 1 optional
  (`architecture-function`), and the language preamble that governs all
  generated notes.
```

- [ ] **Step 2: Update `SKILL.md` Layer 1 architect entry**

Open `SKILL.md`. Find the section describing `/obsidian-architect` under Layer 1. Replace with:

```markdown
- `/obsidian-architect <repo-path>` — scans a repo and writes a maintained
  architecture document set under `Projects/<P>/Architecture/`: a MOC
  `overview.md` with a detected `stack:` block; per-module deep notes
  under `modules/`; narrative section notes (`features`, `api-surface`,
  `decisions`, `roadmap`, `future`); optional function-level notes via
  `--functions=public`. Refresh is the same command re-run; per-section
  signal hashing skips unchanged work. Vault language defaults from
  `_CLAUDE.md`'s `- output-lang:` line; override with `--lang=`.
```

- [ ] **Step 3: Update README.md commands table**

Open `README.md`. Find the table row for `/obsidian-architect`. Replace the description column with:

```
Scan a codebase and write a maintained architecture set (MOC overview, modules, features, roadmap, decisions, future, api-surface) into the project hub; opt-in `--functions=public` layer; supports zh-TW output via vault `_CLAUDE.md` or `--lang`.
```

If a freeform paragraph describes architect output style, append a line:

```markdown
Output respects the vault's `_CLAUDE.md` `- output-lang:` setting; pass `--lang=zh-TW` (or `en`) to override per call.
```

- [ ] **Step 4: Build adapters once more to ensure docs are in sync**

Run: `bash scripts/build.sh`
Expected: no errors.

- [ ] **Step 5: Run full test suite**

Run: `uv run pytest tests/architect/ -v`
Expected: all green.

- [ ] **Step 6: End-to-end smoke against this very repo**

Run (dry-run so it doesn't write to your real vault):

```bash
uv run python scripts/architect_scan.py . --out /tmp/architect-smoke/ --dry-run
```

Then inspect:

```bash
python -c "import json; d = json.load(open('/tmp/architect-smoke/scan-report.json')) if False else None; \
print('--- run real scan: ---')"
uv run python scripts/architect_scan.py . --out /tmp/architect-smoke/
python -c "import json; sr = json.load(open('/tmp/architect-smoke/scan-report.json')); \
print('readme_sections keys:', list(sr['readme_sections'].keys())); \
print('changelog has unreleased:', sr['changelog']['unreleased'] is not None); \
print('decision_docs count:', len(sr['decision_docs'])); \
print('stack:', sr['stack']); \
print('todos modules:', list(sr['todos'].keys())); \
print('api_surface CLI count:', len(sr['api_surface']['cli_commands'])); \
print('commit_decisions count:', len(sr.get('commit_decisions', [])))"
```

Expected output should look roughly like:

```
readme_sections keys: ['Features', ...]
changelog has unreleased: True
decision_docs count: 2  # or more, depending on what's in docs/
stack: {'primary-language': 'Python', 'frameworks': ['...'], ...}
todos modules: [...]
api_surface CLI count: 0  # or N if architect has CLI subcommands
commit_decisions count: N
```

Any deviation that means the scanner crashes or returns empty everywhere is a bug — go back and trace through the failing detector.

- [ ] **Step 7: Spot-check section composition by calling helpers directly**

```bash
uv run python -c "
from scripts.architect.sections import compose_note, build_prompt
note = compose_note(section='features', project='obsidian-second-brain', repo_label='github.com/x/y', commit='abc1234', signal_sources=['README.md'], confidence='high', output_lang='zh-TW', generated_blocks={'summary': '繁中測試', 'capability-map': '- 範例能力'})
print(note)
print('---ASCII check---')
print('## 給未來 Claude' in note, 'lang: zh-TW' in note, 'type: architecture-features' in note)
"
```

Expected: All three booleans print True; the note body shows the zh-TW headings.

- [ ] **Step 8: Final commit**

```bash
git add CHANGELOG.md SKILL.md README.md dist/
git commit -m "docs: announce narrative architect upgrade (features/roadmap/decisions/future/api-surface + --lang)"
```

- [ ] **Step 9: Verify branch state**

Run: `git log --oneline feat/architect-narrative ^main | wc -l`
Expected: roughly 20-22 commits, one per task step group.

Run: `uv run pytest tests/architect/ -v && bash scripts/build.sh`
Expected: full green, all adapters build.

---

## Acceptance checklist (mirrors spec §15)

After all 22 tasks, verify by hand against the spec's acceptance criteria:

- [ ] `overview.md` has `moc-style: true` and populated `stack:` (or omitted if undetectable); body is mostly wikilinks
- [ ] `features.md` lists capabilities with wikilinks into `api-surface.md` and modules
- [ ] `api-surface.md` non-empty table for projects with CLI/HTTP; `detection-status: none` for libraries with neither
- [ ] `roadmap.md` has `## Signals reviewed` block even when no signal present
- [ ] `decisions.md` minimum: Stack rationale + (when present) Promote-to-ADR suggestions
- [ ] `future.md` `status: insufficient-signal` when no signal; content otherwise
- [ ] Hub note `## Architecture` block updated with 5 new wikilinks
- [ ] Source unchanged + re-run: zero notes touched
- [ ] `--refresh` re-run regenerates only sections whose signal hash changed
- [ ] `--functions=public` against a small library yields at least one function note
- [ ] `--only-sections=roadmap` regenerates only roadmap.md
- [ ] `bash scripts/build.sh` passes; all 4 adapter dist trees regenerate
- [ ] `_CLAUDE.md` `output-lang: zh-TW` + run -> all section headings and prose繁中,code identifiers stay English
- [ ] `--lang=en` overrides vault setting for one run
- [ ] Language switch triggers regeneration of all sections (lockfile `lang` changed)
- [ ] zh-TW inference markers look like `(推論自 src/foo.py:42)`
