## Resolution log

Both blockers captured during the codex run are cosmetic — the plan over-predicted FAIL counts because the **Task 1 placeholders coincidentally satisfied a future test**:

**Task 2 Step 2** — Expected 3 FAILs, got 2 FAILs + 1 PASS. `test_resolve_repo_arg_absolute_path_no_match` already passed because Task 1's `_resolve_absolute_path` placeholder returned `state="unknown"` with the input path in the message — which is exactly what the test asserts. The real missing functionality (single-match → `state="project"`, multiple-match → `state="ambiguous"`) DID fail correctly. TDD intent preserved.

**Task 3 Step 2** — Expected 4 FAILs, got 3 FAILs + 1 PASS. Same shape: `test_resolve_repo_arg_unknown_project_name` already passed because Task 1's placeholder returned `state="unknown"` with the full project list. The truly missing fuzzy / substring matching DID fail.

In both cases the RED state was incomplete but the implementation pressure was correctly applied. No fix needed — final 11 resolver tests pass, full suite 419 green, 4 adapters build.

# Obsidian CLI Family `<repo>` Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a shared `resolve_repo_arg()` helper and refactor 5 slash commands (`/obsidian-architect`, `/obsidian-brainstorm`, `/obsidian-roadmap`, `/obsidian-research`, `/obsidian-research-deep`) to use `<repo>` as their first positional argument, with `/research` + `/research-deep` becoming deprecation stubs.

**Architecture:** New module `scripts/commands/repo_resolver.py` with one public function `resolve_repo_arg(token, vault_root, allow_global)` returning a `RepoResolution` dataclass in one of 4 states (`project` / `global` / `ambiguous` / `unknown`). Each command body's Phase 0 calls the resolver, then branches on state. `/research` + `/research-deep` become thin redirect stubs printing a deprecation warning. New frontmatter field `param-autocomplete` reserved for future Discord adapter; existing adapters ignore unknown fields.

**Tech Stack:** Python 3.10+, pytest, `pathlib`, `difflib` (for Levenshtein-ish fuzzy match — using `SequenceMatcher` ratio + substring check), existing slash-command frontmatter conventions. No new external deps.

**Plan-level notes:**
- Run tests from repo root `/Users/leric/Desktop/code/obsidian-second-brain` with `uv run pytest tests/path/test.py -v`.
- Co-author line on every commit: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- `dist/` is gitignored — never `git add dist/`.
- When pytest emits a COLLECTION ERROR (`ModuleNotFoundError` / missing attribute), that's the expected RED state for TDD — proceed to implementation.

---

## File structure (locked here)

**New files:**
- `scripts/commands/__init__.py` — empty (package marker)
- `scripts/commands/repo_resolver.py` — `resolve_repo_arg()` + `RepoResolution` dataclass
- `tests/commands/__init__.py` — empty
- `tests/commands/test_repo_resolver.py` — 8 unit tests for resolver
- `commands/obsidian-research.md` — new file (content largely from `commands/research.md` + grammar change + Phase 0)
- `commands/obsidian-research-deep.md` — new file (content from `commands/research-deep.md` + grammar change)

**Modified files:**
- `commands/research.md` — replaced by thin deprecation stub
- `commands/research-deep.md` — replaced by thin deprecation stub
- `commands/obsidian-brainstorm.md` — `argument-hint: <repo>`; Phase 0 swap to `resolve_repo_arg`; rejection of `global` sentinel
- `commands/obsidian-roadmap.md` — same shape change
- `commands/obsidian-architect.md` — Phase 0 (Project routing) section replaced with `resolve_repo_arg` invocation
- `SKILL.md` — command table updated (5 rows)
- `README.md` — command table updated (5 rows)
- `CHANGELOG.md` — `## [Unreleased]` entry + `## Deprecated` block

---

## Phase A: Resolver helper

### Task 1: `RepoResolution` dataclass + `resolve_repo_arg` skeleton + exact-name + global-sentinel

**Files:**
- Create: `scripts/commands/__init__.py` (empty)
- Create: `scripts/commands/repo_resolver.py`
- Create: `tests/commands/__init__.py` (empty)
- Create: `tests/commands/test_repo_resolver.py`

- [ ] **Step 1: Create empty package files**

```bash
mkdir -p /Users/leric/Desktop/code/obsidian-second-brain/scripts/commands
mkdir -p /Users/leric/Desktop/code/obsidian-second-brain/tests/commands
touch /Users/leric/Desktop/code/obsidian-second-brain/scripts/commands/__init__.py
touch /Users/leric/Desktop/code/obsidian-second-brain/tests/commands/__init__.py
```

- [ ] **Step 2: Write failing tests for exact name match + global sentinel**

Create `tests/commands/test_repo_resolver.py`:

```python
"""Tests for scripts.commands.repo_resolver.resolve_repo_arg."""
from __future__ import annotations

from pathlib import Path

from scripts.commands.repo_resolver import resolve_repo_arg, RepoResolution


def _make_vault(tmp_path: Path, project_names: list[str]) -> Path:
    """Build a minimal vault with given project folders + each has a hub note."""
    (tmp_path / "_CLAUDE.md").write_text("vault root marker\n", encoding="utf-8")
    projects = tmp_path / "Projects"
    projects.mkdir()
    for name in project_names:
        proj_dir = projects / name
        proj_dir.mkdir()
        (proj_dir / f"{name}.md").write_text(
            "---\n"
            "type: project\n"
            f'project: "[[{name}]]"\n'
            "---\n",
            encoding="utf-8",
        )
    return tmp_path


def test_resolve_repo_arg_exact_project_name(tmp_path: Path):
    """Token matches a Projects/<name>/ folder exactly → state='project', bind."""
    vault = _make_vault(tmp_path, ["langlive-line-oa", "ai-eden-service"])
    res = resolve_repo_arg("langlive-line-oa", vault_root=vault, allow_global=False)
    assert res.state == "project"
    assert res.project_slug == "langlive-line-oa"
    assert res.project_dir == vault / "Projects/langlive-line-oa"


def test_resolve_repo_arg_global_sentinel_when_allowed(tmp_path: Path):
    """Token 'global' with allow_global=True → state='global'."""
    vault = _make_vault(tmp_path, ["whatever"])
    res = resolve_repo_arg("global", vault_root=vault, allow_global=True)
    assert res.state == "global"
    assert res.project_slug is None
    assert res.project_dir is None


def test_resolve_repo_arg_underscore_and_dash_also_global(tmp_path: Path):
    """Aliases '_' and '-' are also global sentinels when allowed."""
    vault = _make_vault(tmp_path, ["whatever"])
    assert resolve_repo_arg("_", vault_root=vault, allow_global=True).state == "global"
    assert resolve_repo_arg("-", vault_root=vault, allow_global=True).state == "global"


def test_resolve_repo_arg_global_rejected_when_not_allowed(tmp_path: Path):
    """Token 'global' with allow_global=False → state='unknown' (architect/brainstorm/roadmap)."""
    vault = _make_vault(tmp_path, ["whatever"])
    res = resolve_repo_arg("global", vault_root=vault, allow_global=False)
    assert res.state == "unknown"
    assert "global" in res.message.lower() or "not allowed" in res.message.lower()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v`
Expected: COLLECTION ERROR with `ModuleNotFoundError: No module named 'scripts.commands.repo_resolver'`.

- [ ] **Step 4: Implement skeleton + exact-name + global-sentinel**

Create `scripts/commands/repo_resolver.py`:

```python
"""Resolve a CLI `<repo>` argument into a vault project binding.

Used by the obsidian-* command family (architect / brainstorm / roadmap /
research / research-deep). Accepts three forms:
- Sentinel ('global' / '_' / '-') → state='global' (research commands only)
- Absolute path → match against project hub `local-path` frontmatter
- Project name → exact match against Projects/<name>/ folder, then fuzzy

Caller branches on `RepoResolution.state` to either continue execution,
ask the user to disambiguate, or abort with a message.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path


_GLOBAL_SENTINELS = ("global", "_", "-")


@dataclass
class RepoResolution:
    state: str                            # 'project' | 'global' | 'ambiguous' | 'unknown'
    project_slug: str | None = None       # set when state == 'project'
    project_dir: Path | None = None       # set when state == 'project'
    local_path: str | None = None         # bound repo path from hub frontmatter, if any
    candidates: list[str] = field(default_factory=list)  # for ambiguous / unknown
    message: str = ""                     # human-readable explanation


def resolve_repo_arg(
    token: str,
    vault_root: Path,
    *,
    allow_global: bool = False,
) -> RepoResolution:
    """Resolve a `<repo>` CLI token. See module docstring for full spec."""
    token = token.strip()
    if not token:
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="missing <repo> argument",
        )

    # Sentinel handling.
    if token in _GLOBAL_SENTINELS:
        if allow_global:
            return RepoResolution(state="global")
        return RepoResolution(
            state="unknown",
            candidates=_list_projects(vault_root),
            message=(
                f"'global' sentinel is not allowed for this command. "
                f"Pass a specific project name."
            ),
        )

    # Absolute path branch (Task 2 below).
    if token.startswith("/"):
        return _resolve_absolute_path(token, vault_root)

    # Project name branch (Task 3 below).
    return _resolve_project_name(token, vault_root)


def _list_projects(vault_root: Path) -> list[str]:
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return []
    return sorted(
        d.name for d in projects_dir.iterdir()
        if d.is_dir() and not d.name.startswith(".") and not d.name.startswith("_")
    )


def _resolve_absolute_path(token: str, vault_root: Path) -> RepoResolution:
    """Placeholder filled in by Task 2."""
    return RepoResolution(
        state="unknown",
        candidates=_list_projects(vault_root),
        message=f"absolute-path resolution not yet implemented for token: {token}",
    )


def _resolve_project_name(token: str, vault_root: Path) -> RepoResolution:
    """Project-name branch: exact match first."""
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="vault has no Projects/ folder",
        )
    exact = projects_dir / token
    if exact.is_dir():
        return RepoResolution(
            state="project",
            project_slug=token,
            project_dir=exact,
        )
    # Fuzzy / unknown branch — filled in by Task 3.
    return RepoResolution(
        state="unknown",
        candidates=_list_projects(vault_root),
        message=f"no project named {token!r}; available: {_list_projects(vault_root)}",
    )
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v`
Expected: 4 PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/commands/__init__.py scripts/commands/repo_resolver.py tests/commands/__init__.py tests/commands/test_repo_resolver.py
git commit -m "$(cat <<'EOF'
feat(commands): repo_resolver skeleton — exact name + global sentinel

New shared helper `scripts/commands/repo_resolver.py` for resolving the
<repo> CLI token used by the obsidian-* command family. RepoResolution
dataclass has 4 states (project / global / ambiguous / unknown).

This commit lands:
- Exact project-name match against Projects/<name>/ folder
- Sentinel ('global' / '_' / '-') handling with allow_global gate
- Empty-Projects/ + missing-token edge cases

Absolute-path resolution + fuzzy match come in Tasks 2-3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 2: Absolute-path resolution via hub `local-path` frontmatter

**Files:**
- Modify: `scripts/commands/repo_resolver.py` (fill in `_resolve_absolute_path`)
- Modify: `tests/commands/test_repo_resolver.py` (append)

- [ ] **Step 1: Write failing tests**

Append to `tests/commands/test_repo_resolver.py`:

```python
def test_resolve_repo_arg_absolute_path_single_match(tmp_path: Path):
    """Absolute path matches one hub's local-path → state='project'."""
    vault = _make_vault(tmp_path, ["langlive-line-oa"])
    # Override the hub note with explicit local-path.
    (vault / "Projects/langlive-line-oa/langlive-line-oa.md").write_text(
        "---\n"
        "type: project\n"
        'project: "[[langlive-line-oa]]"\n'
        'local-path: "/Users/leric/Desktop/code/langlive-line-oa"\n'
        "---\n",
        encoding="utf-8",
    )
    res = resolve_repo_arg(
        "/Users/leric/Desktop/code/langlive-line-oa",
        vault_root=vault,
        allow_global=False,
    )
    assert res.state == "project"
    assert res.project_slug == "langlive-line-oa"
    assert res.local_path == "/Users/leric/Desktop/code/langlive-line-oa"


def test_resolve_repo_arg_absolute_path_no_match(tmp_path: Path):
    """Absolute path with no matching hub → state='unknown'."""
    vault = _make_vault(tmp_path, ["langlive-line-oa"])
    # Hub has a different local-path (or none).
    (vault / "Projects/langlive-line-oa/langlive-line-oa.md").write_text(
        "---\n"
        'local-path: "/some/other/path"\n'
        "---\n",
        encoding="utf-8",
    )
    res = resolve_repo_arg(
        "/Users/leric/Desktop/code/nonexistent",
        vault_root=vault,
        allow_global=False,
    )
    assert res.state == "unknown"
    assert "nonexistent" in res.message or "no project hub" in res.message.lower()


def test_resolve_repo_arg_absolute_path_multiple_match(tmp_path: Path):
    """Absolute path matches multiple hubs → state='ambiguous'."""
    vault = _make_vault(tmp_path, ["proj-a", "proj-b"])
    for name in ("proj-a", "proj-b"):
        (vault / f"Projects/{name}/{name}.md").write_text(
            "---\n"
            f'local-path: "/Users/x/shared-repo"\n'
            "---\n",
            encoding="utf-8",
        )
    res = resolve_repo_arg(
        "/Users/x/shared-repo",
        vault_root=vault,
        allow_global=False,
    )
    assert res.state == "ambiguous"
    assert set(res.candidates) == {"proj-a", "proj-b"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v -k "absolute_path"`
Expected: 3 FAILs — current `_resolve_absolute_path` returns "not yet implemented".

- [ ] **Step 3: Implement `_resolve_absolute_path` + helper to read hub frontmatter**

In `scripts/commands/repo_resolver.py`, REPLACE the placeholder `_resolve_absolute_path` with:

```python
_LOCAL_PATH_RE = re.compile(r'^local-path:\s*"?(?P<path>[^"\n]+)"?\s*$', re.MULTILINE)


def _resolve_absolute_path(token: str, vault_root: Path) -> RepoResolution:
    """Walk Projects/*/<P>.md hubs; match by local-path frontmatter."""
    normalized = token.rstrip("/")
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="vault has no Projects/ folder",
        )

    matches: list[tuple[str, Path, str]] = []  # (slug, proj_dir, local_path)
    for proj_dir in projects_dir.iterdir():
        if not proj_dir.is_dir() or proj_dir.name.startswith((".", "_")):
            continue
        hub_path = proj_dir / f"{proj_dir.name}.md"
        if not hub_path.is_file():
            continue
        try:
            text = hub_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        # Only inspect the first frontmatter block.
        fm_match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
        if not fm_match:
            continue
        fm = fm_match.group(1)
        for m in _LOCAL_PATH_RE.finditer(fm):
            path_value = m.group("path").strip().rstrip("/")
            if path_value == normalized:
                matches.append((proj_dir.name, proj_dir, path_value))
                break

    if len(matches) == 0:
        return RepoResolution(
            state="unknown",
            candidates=_list_projects(vault_root),
            message=(
                f"no project hub binds to local-path {token!r}. "
                f"Either fix the project hub's frontmatter, or pass the project name "
                f"as the <repo> argument instead."
            ),
        )
    if len(matches) == 1:
        slug, proj_dir, local_path = matches[0]
        return RepoResolution(
            state="project",
            project_slug=slug,
            project_dir=proj_dir,
            local_path=local_path,
        )
    return RepoResolution(
        state="ambiguous",
        candidates=[m[0] for m in matches],
        message=(
            f"path {token!r} is bound by multiple project hubs: "
            f"{[m[0] for m in matches]}. Use --project=<name> or pass the project "
            f"name directly to disambiguate."
        ),
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v`
Expected: 7 PASS (4 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/commands/repo_resolver.py tests/commands/test_repo_resolver.py
git commit -m "$(cat <<'EOF'
feat(commands): repo_resolver — absolute-path resolution via hub local-path

When the <repo> token is an absolute path, walk Projects/*/<P>.md hubs
and match by the `local-path` frontmatter value. Single match →
state='project' with local_path populated. Multiple matches →
state='ambiguous'. Zero matches → state='unknown' with full project
list as candidates.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3: Fuzzy match + unknown fallback for project-name branch

**Files:**
- Modify: `scripts/commands/repo_resolver.py` (fill in fuzzy branch)
- Modify: `tests/commands/test_repo_resolver.py` (append)

- [ ] **Step 1: Write failing tests**

Append to `tests/commands/test_repo_resolver.py`:

```python
def test_resolve_repo_arg_fuzzy_substring_match_single(tmp_path: Path):
    """'langlive' is substring of one project → state='ambiguous' (require confirm)."""
    vault = _make_vault(tmp_path, ["langlive-line-oa", "other-thing"])
    res = resolve_repo_arg("langlive", vault_root=vault, allow_global=False)
    assert res.state == "ambiguous"
    assert "langlive-line-oa" in res.candidates


def test_resolve_repo_arg_fuzzy_substring_match_multiple(tmp_path: Path):
    """'service' is substring of multiple projects → state='ambiguous' with list."""
    vault = _make_vault(tmp_path, ["ai-eden-service", "user-service", "billing-service"])
    res = resolve_repo_arg("service", vault_root=vault, allow_global=False)
    assert res.state == "ambiguous"
    assert set(res.candidates) >= {"ai-eden-service", "user-service", "billing-service"}


def test_resolve_repo_arg_fuzzy_levenshtein_match(tmp_path: Path):
    """Single edit-distance typo on project name → ambiguous with the candidate."""
    vault = _make_vault(tmp_path, ["langlive-line-oa", "other-thing"])
    # 'langlivee-line-oa' (extra 'e') — substring won't catch it; SequenceMatcher will.
    res = resolve_repo_arg("langlivee-line-oa", vault_root=vault, allow_global=False)
    assert res.state == "ambiguous"
    assert "langlive-line-oa" in res.candidates


def test_resolve_repo_arg_unknown_project_name(tmp_path: Path):
    """Token not matching anything → state='unknown' with full project list."""
    vault = _make_vault(tmp_path, ["langlive-line-oa", "ai-eden-service"])
    res = resolve_repo_arg(
        "totally-unrelated-name",
        vault_root=vault,
        allow_global=False,
    )
    assert res.state == "unknown"
    assert set(res.candidates) == {"langlive-line-oa", "ai-eden-service"}
    assert "totally-unrelated-name" in res.message
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v -k "fuzzy or unknown_project_name"`
Expected: 4 FAILs — current code returns `unknown` for all non-exact names.

- [ ] **Step 3: Implement fuzzy match in `_resolve_project_name`**

In `scripts/commands/repo_resolver.py`, REPLACE the existing `_resolve_project_name` with:

```python
_FUZZY_THRESHOLD = 0.75   # SequenceMatcher ratio; tuned so 1-2 char typos pass


def _resolve_project_name(token: str, vault_root: Path) -> RepoResolution:
    """Project-name branch: exact match first, then fuzzy."""
    projects_dir = vault_root / "Projects"
    if not projects_dir.is_dir():
        return RepoResolution(
            state="unknown",
            candidates=[],
            message="vault has no Projects/ folder",
        )

    # Exact match.
    exact = projects_dir / token
    if exact.is_dir():
        return RepoResolution(
            state="project",
            project_slug=token,
            project_dir=exact,
        )

    # Fuzzy: substring OR SequenceMatcher ratio >= threshold.
    all_projects = _list_projects(vault_root)
    token_lower = token.lower()
    candidates: list[str] = []
    for name in all_projects:
        name_lower = name.lower()
        if token_lower in name_lower or name_lower in token_lower:
            candidates.append(name)
            continue
        ratio = SequenceMatcher(None, token_lower, name_lower).ratio()
        if ratio >= _FUZZY_THRESHOLD:
            candidates.append(name)

    if candidates:
        return RepoResolution(
            state="ambiguous",
            candidates=candidates,
            message=(
                f"{token!r} matches multiple/uncertain candidates: {candidates}. "
                f"Please confirm which project to use."
            ),
        )

    return RepoResolution(
        state="unknown",
        candidates=all_projects,
        message=(
            f"no project named {token!r}. Available: {all_projects}. "
            f"Pass one as <repo> or run /obsidian-project <name> to create."
        ),
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/commands/test_repo_resolver.py -v`
Expected: 11 PASS (7 prior + 4 new).

- [ ] **Step 5: Run full suite to confirm no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/commands/repo_resolver.py tests/commands/test_repo_resolver.py
git commit -m "$(cat <<'EOF'
feat(commands): repo_resolver — fuzzy match + unknown fallback

Project-name branch:
1. Exact match → state='project' (immediate bind)
2. Substring OR SequenceMatcher ratio >= 0.75 → state='ambiguous' with
   candidate list (single candidate still requires user confirmation to
   avoid silent typo correction)
3. No matches → state='unknown' with full project list as candidates

SequenceMatcher ratio threshold tuned at 0.75 so 1-2 char typos on a
10-char name still match.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Command body refactor (5 commands)

### Task 4: Create `commands/obsidian-research.md` from `commands/research.md`

**Files:**
- Create: `commands/obsidian-research.md` (new file)

- [ ] **Step 1: Read existing `commands/research.md`**

```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/research.md
```

(Note the existing content; copy it as the base.)

- [ ] **Step 2: Create `commands/obsidian-research.md`**

Create `commands/obsidian-research.md` with this content:

````markdown
---
description: Free-source web + academic research with citations — dossier saved to vault (renamed from /research in v4.5)
argument-hint: <repo> <topic>
category: research
triggers_en: ["research this", "look up", "find info on", "web research", "obsidian research"]
param-autocomplete:
  - name: repo
    source: vault-projects-plus-global
  - name: topic
    source: freetext
---

Use the obsidian-second-brain skill. Execute `/obsidian-research $ARGUMENTS`:

The first positional argument is `<repo>` — accepts (a) a project name like `langlive-line-oa`, (b) an absolute path that matches a project hub's `local-path` frontmatter, or (c) the sentinel `global` (also `_` or `-`) for vault-wide research. The rest of `$ARGUMENTS` is the research topic. Optional flag `--academic` restricts to arXiv / Semantic Scholar / OpenAlex / CrossRef only.

## Phase 0: Resolve <repo>

Parse the first whitespace-delimited token from `$ARGUMENTS`:

```python
import shlex
tokens = shlex.split(args, posix=True)
if len(tokens) < 2:
    abort("missing arguments. Usage: /obsidian-research <repo> <topic> [--academic]")
repo_token = tokens[0]
remaining = " ".join(tokens[1:])

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=True,
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "global":
    project_dir = None
    project_slug = None
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
    # After user picks, re-resolve with the picked name as repo_token.
elif resolution.state == "unknown":
    abort(resolution.message)

# remaining is now the topic + optional flags.
```

## Output routing

When `state == "global"` (sentinel was given): write to vault-wide `Research/Web/YYYY-MM-DD-<slug>.md` (or `Research/Academic/` if `--academic`).

When `state == "project"`: write to `Projects/<project_slug>/Research/<slug>-web.md`.

Frontmatter additions when project-scoped: `project: "[[<project_slug>]]"` and `tags: [research, <project_slug>, web]`.

## Phase 1 onward (unchanged from /research)

1. Read `_CLAUDE.md` first if it exists in the vault root.

2. Run the Python fetcher:
   ```bash
   uv run -m scripts.research.research "<topic>" [--academic]
   ```

3. Parse the stdout JSON. Shape:
   ```json
   {
     "topic": "...",
     "academic_mode": false,
     "results": [{"source": "...", "title": "...", "url": "...", "snippet": "...", "abstract": "...", "authors": [...], "year": 2024, "points": 47, "comments": 12, "posted_at": "..."}, ...],
     "stats": {"sources_attempted": 6, "sources_succeeded": 5, "results_total": 38, "success": true},
     "warnings": [...]
   }
   ```

4. Synthesize an AI-first dossier. Sections:
   - `## For future Claude` preamble
   - `## Summary` (3-5 sentences)
   - `## Key Facts` with `(as of YYYY-MM, source-domain.com)` recency markers
   - `## Timeline` (if temporally significant)
   - `## Key Players`
   - `## Contrarian Views`
   - `## Open Questions`
   - `## Sources` (every URL, deduped, grouped by source name)

5. Save to:
   - `Research/Web/YYYY-MM-DD-<slug>.md` (state=global, no --academic)
   - `Research/Academic/YYYY-MM-DD-<slug>.md` (state=global, --academic)
   - `Projects/<P>/Research/<slug>-web.md` (state=project)

   Frontmatter:
   ```yaml
   ---
   date: YYYY-MM-DD
   type: research
   tags: [research, <slug-tag>, <source-tags>]
   topic: "<topic>"
   model: claude-via-self
   sources: [<all urls>]
   ai-first: true
   ---
   ```

   When `state=project`, add `project: "[[<project_slug>]]"` to frontmatter.

6. Append one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** — research | <topic> — N sources, saved to [[Research/Web/<file>]]
   ```

7. Update `index.md` Research section.

8. If `stats.success` is false (< 3 sources returned), tell user plainly and suggest a narrower query before saving.

---

**AI-first rule:** Every note follows `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter, recency markers, mandatory `[[wikilinks]]`, sources verbatim with URLs inline, confidence levels.
````

- [ ] **Step 3: Verify the slash command file parses (build adapters)**

Run: `bash scripts/build.sh`
Expected: 4 platform adapters build successfully.

- [ ] **Step 4: Commit**

```bash
git add commands/obsidian-research.md
git commit -m "$(cat <<'EOF'
feat(commands): /obsidian-research — repo-first positional grammar (v4.5)

Renamed from /research. New grammar:
  /obsidian-research <repo> <topic> [--academic]

<repo> accepts: project name, absolute path (matched against hub
local-path frontmatter), or the sentinel `global` (also `_` / `-`).

Phase 0 delegates to scripts.commands.repo_resolver.resolve_repo_arg.

Output routing:
- state=global → vault-wide Research/Web/ (or Academic/)
- state=project → Projects/<P>/Research/<slug>-web.md

Frontmatter adds `param-autocomplete: [repo: vault-projects-plus-global,
topic: freetext]` for future Discord adapter consumption (existing
adapters ignore unknown fields).

Old /research command remains as a deprecation stub (Task 9).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: Create `commands/obsidian-research-deep.md` from `commands/research-deep.md`

**Files:**
- Create: `commands/obsidian-research-deep.md` (new file)

- [ ] **Step 1: Create the new command file**

Create `commands/obsidian-research-deep.md`:

````markdown
---
description: Vault-first deep research — Claude scans vault, identifies gaps, fetches per-gap free sources, synthesizes delta, propagates updates (renamed from /research-deep in v4.5)
argument-hint: <repo> <topic>
category: research
triggers_en: ["deep research", "thorough research", "vault-first research", "obsidian research deep"]
param-autocomplete:
  - name: repo
    source: vault-projects-plus-global
  - name: topic
    source: freetext
---

Use the obsidian-second-brain skill. Execute `/obsidian-research-deep $ARGUMENTS`:

The first positional argument is `<repo>` — accepts (a) a project name, (b) an absolute path matching a hub's `local-path` frontmatter, or (c) the sentinel `global` (also `_` or `-`) for vault-wide research. The rest is the research topic.

## Phase 0: Resolve <repo>

Parse the first token; call `scripts.commands.repo_resolver.resolve_repo_arg(token, vault_root, allow_global=True)`.

```python
import shlex
tokens = shlex.split(args, posix=True)
if len(tokens) < 2:
    abort("missing arguments. Usage: /obsidian-research-deep <repo> <topic>")
repo_token = tokens[0]
topic = " ".join(tokens[1:])

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=True,
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "global":
    project_dir = None
    project_slug = None
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown":
    abort(resolution.message)
```

## Output routing

When `state == "global"`: write to `Research/Deep/YYYY-MM-DD-<slug>.md`.
When `state == "project"`: write to `Projects/<P>/Research/<slug>-deep.md`.

## Phases 1-4 (unchanged from /research-deep)

1. Read `_CLAUDE.md` first.

2. **Phase 1 — vault baseline:**
   - Search `Research/`, `Projects/`, `Knowledge/`, `Ideas/` for any note mentioning the topic
   - List what's already known vs unknown
   - List wikilinks pointing into the topic from elsewhere

3. **Phase 2 — gap analysis:**
   - Based on baseline, formulate 3-5 specific sub-queries that would fill the gaps
   - Each 3-8 words, retrieval-friendly
   - At least one academic-leaning + one discourse-leaning when relevant

4. **Phase 3 — fetch:**
   ```bash
   uv run -m scripts.research.research_deep "<sub-q1>" "<sub-q2>" "<sub-q3>" ...
   ```

5. Parse stdout JSON:
   ```json
   {
     "sub_queries": ["...", "...", "..."],
     "per_query": [
       {"topic": "...", "results": [...], "stats": {...}, "warnings": [...]},
       ...
     ]
   }
   ```

6. **Phase 4 — synthesize delta** and save:
   - `Research/Deep/YYYY-MM-DD-<slug>.md` (state=global)
   - `Projects/<P>/Research/<slug>-deep.md` (state=project)

   Frontmatter when project-scoped includes `project: "[[<project_slug>]]"`.

7. Append one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** — research-deep | <topic> — N sub-queries, M total sources, saved to [[<file>]]
   ```

8. If propagation needed (decisions/ADRs/learnings/ideas surfaced from findings), follow `references/ai-first-rules.md` propagation chain.

---

**AI-first rule:** Same as /obsidian-research — `## For future Claude` preamble, rich frontmatter, recency markers, mandatory wikilinks, sources verbatim.
````

- [ ] **Step 2: Build adapters to confirm parsing**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 3: Commit**

```bash
git add commands/obsidian-research-deep.md
git commit -m "$(cat <<'EOF'
feat(commands): /obsidian-research-deep — repo-first positional grammar (v4.5)

Renamed from /research-deep. New grammar:
  /obsidian-research-deep <repo> <topic>

Same Phase 0 resolution as /obsidian-research. Output routing:
- state=global → vault-wide Research/Deep/
- state=project → Projects/<P>/Research/<slug>-deep.md

Old /research-deep remains as deprecation stub (Task 9).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 6: `/obsidian-brainstorm` argument-hint + Phase 0 swap

**Files:**
- Modify: `commands/obsidian-brainstorm.md`

- [ ] **Step 1: Locate the existing argument-hint + Phase 0 sections**

```bash
grep -n "argument-hint\|## Phase 0\|## Project routing\|## Phase 1.*Vault" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-brainstorm.md | head -8
```

- [ ] **Step 2: Update `argument-hint`**

In `commands/obsidian-brainstorm.md`, find:
```yaml
argument-hint: <project-name>
```

Replace with:
```yaml
argument-hint: <repo>
param-autocomplete:
  - name: repo
    source: vault-projects
```

- [ ] **Step 3: Replace Phase 0 with `resolve_repo_arg` invocation**

Find the existing "Phase 0: Pre-flight" section. REPLACE the body of that section (between the heading and the next `##` heading) with:

````markdown
## Phase 0: Pre-flight + resolve <repo>

- Confirm vault root has `_CLAUDE.md`. If no, abort with "Run /obsidian-init first."
- Parse the first whitespace-delimited token from `$ARGUMENTS` as the `<repo>` argument. Anything after is treated as flags.
- Resolve via shared helper:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-brainstorm <repo> [--topic=...] [--lens=...] [--depth=...]")
repo_token = tokens[0]
remaining_flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,   # brainstorm requires a real project
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown" or resolution.state == "global":
    abort(resolution.message)  # 'global' is rejected for brainstorm
```

- Confirm `Projects/<project_slug>/` exists. If no, abort with "Run /obsidian-project <P> first."
- Ensure `Projects/<project_slug>/Brainstorms/` exists (mkdir if needed).
- Resolve `output_lang`:
  ```bash
  uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
  ```
````

- [ ] **Step 4: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-brainstorm.md
git commit -m "$(cat <<'EOF'
refactor(commands): /obsidian-brainstorm uses <repo> + shared resolver

argument-hint: <project-name> → <repo>. Added param-autocomplete
frontmatter (vault-projects source).

Phase 0 now calls scripts.commands.repo_resolver.resolve_repo_arg
with allow_global=False. 'global' sentinel is rejected with the
resolver's message. Project resolution semantics (exact name match,
fuzzy ambiguity, unknown abort) are now shared with the rest of the
obsidian-* family.

Behavior change: user can now pass an absolute repo path as <repo>
and the resolver will match by hub local-path frontmatter (parity
with /obsidian-architect).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7: `/obsidian-roadmap` argument-hint + Phase 0 swap

**Files:**
- Modify: `commands/obsidian-roadmap.md`

- [ ] **Step 1: Update `argument-hint`**

In `commands/obsidian-roadmap.md`, find:
```yaml
argument-hint: <project-name>
```

Replace with:
```yaml
argument-hint: <repo>
param-autocomplete:
  - name: repo
    source: vault-projects
```

- [ ] **Step 2: Replace the project routing / Pre-flight section**

Find the section that resolves the project (it might be labeled "Pre-flight" or "Project routing" or simply mentioned at the top). Replace its body with the same `resolve_repo_arg` block as Task 6 step 3 (but referencing `/obsidian-roadmap <repo>` in the usage string), keeping the rest of the command body untouched.

Concrete edit:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-roadmap <repo> [--dry-run] [--force] [--only-themes=N] ...")
repo_token = tokens[0]
remaining_flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown" or resolution.state == "global":
    abort(resolution.message)
```

- [ ] **Step 3: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 4: Commit**

```bash
git add commands/obsidian-roadmap.md
git commit -m "$(cat <<'EOF'
refactor(commands): /obsidian-roadmap uses <repo> + shared resolver

argument-hint: <project-name> → <repo>. Pre-flight Phase 0 now uses
scripts.commands.repo_resolver.resolve_repo_arg(allow_global=False).
'global' sentinel rejected. Behavior change parallels /obsidian-brainstorm
— absolute paths now resolve via hub local-path frontmatter match.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 8: `/obsidian-architect` swap Phase 0 to shared resolver

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Locate the existing "Project routing" section**

```bash
grep -n "^## Project routing\|^## Phase 1\|^## Phase 0" /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-architect.md | head -5
```

- [ ] **Step 2: Replace "Project routing" with shared resolver call**

In `commands/obsidian-architect.md`, find `## Project routing`. The existing section walks the vault for `local-path` frontmatter match, asks user to disambiguate, falls back to project-name match. Replace that whole section with a unified resolver invocation:

````markdown
## Project routing (v4.5 — shared resolver)

Parse the first whitespace-delimited token from `$ARGUMENTS` as `<repo>`. Then:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-architect <repo> [--refresh] [--no-features] ...")
repo_token = tokens[0]
remaining_flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,   # architect requires a real project
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
    local_path = resolution.local_path
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown" or resolution.state == "global":
    # 'global' rejected for architect. unknown → may need /obsidian-project first.
    abort(resolution.message)
```

`<repo>` accepts (a) a project name like `langlive-line-oa`, (b) an absolute path that the project hub's `local-path` frontmatter binds to. If the path doesn't bind any hub, the resolver's error message includes the available project list and suggests running `/obsidian-project <name>` first.
````

- [ ] **Step 3: Also update `argument-hint` to confirm `<repo>` is there**

In the frontmatter, ensure:
```yaml
argument-hint: <repo>
param-autocomplete:
  - name: repo
    source: vault-projects
```

(The hint should already say `<repo>`; just add `param-autocomplete` if absent.)

- [ ] **Step 4: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "$(cat <<'EOF'
refactor(commands): /obsidian-architect uses shared resolve_repo_arg

Replaces inline "Project routing" logic with call to
scripts.commands.repo_resolver.resolve_repo_arg. Same semantics as
before (path/name resolution; ambiguity asks user; unknown aborts),
but routed through the shared helper for consistency across the
obsidian-* command family. Adds param-autocomplete frontmatter for
future Discord adapter wiring.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: Deprecation stubs for old `/research` + `/research-deep`

### Task 9: Convert `commands/research.md` and `commands/research-deep.md` into stubs

**Files:**
- Modify: `commands/research.md` (replace with stub)
- Modify: `commands/research-deep.md` (replace with stub)

- [ ] **Step 1: Replace `commands/research.md` content**

Replace the entire file contents with this thin redirect stub:

````markdown
---
description: "[deprecated] use /obsidian-research instead — to be removed in next minor release"
argument-hint: <topic>
category: research
triggers_en: ["research this", "look up", "find info on", "web research"]
---

Use the obsidian-second-brain skill. Execute `/research $ARGUMENTS`:

**⚠️ Deprecation notice:** `/research` is renamed to `/obsidian-research`. The old name still works for now but will be removed in the next minor release.

**Old grammar:** `/research <topic> [--project=<name>] [--academic]`
**New grammar:** `/obsidian-research <repo> <topic> [--academic]`

When invoked, this stub:

1. Prints to the user (visible in chat):
   ```
   ⚠️ /research is renamed to /obsidian-research. Use:
       /obsidian-research <repo> <topic> [--academic]
     (where <repo> is "global" for cross-project research, or a project name like "langlive-line-oa")
   ```

2. Translates the legacy invocation to the new grammar:
   - If `--project=<name>` flag is present, use `<name>` as `<repo>`.
   - Otherwise, use `global` as `<repo>`.
   - Forward the remaining args (the topic + `--academic` if present) to `/obsidian-research`.

3. Continues execution using the new command's body (see `commands/obsidian-research.md`).

This stub is removed in the next minor release. After that, only `/obsidian-research` is recognized.
````

- [ ] **Step 2: Replace `commands/research-deep.md` content**

Replace the entire file contents with:

````markdown
---
description: "[deprecated] use /obsidian-research-deep instead — to be removed in next minor release"
argument-hint: <topic>
category: research
triggers_en: ["deep research", "thorough research", "vault-first research"]
---

Use the obsidian-second-brain skill. Execute `/research-deep $ARGUMENTS`:

**⚠️ Deprecation notice:** `/research-deep` is renamed to `/obsidian-research-deep`. The old name still works for now but will be removed in the next minor release.

**Old grammar:** `/research-deep <topic> [--project=<name>]`
**New grammar:** `/obsidian-research-deep <repo> <topic>`

When invoked, this stub:

1. Prints to the user:
   ```
   ⚠️ /research-deep is renamed to /obsidian-research-deep. Use:
       /obsidian-research-deep <repo> <topic>
     (where <repo> is "global" for cross-project research, or a project name)
   ```

2. Translates legacy invocation to new grammar (same logic as /research stub: `--project=<name>` → `<name>` as `<repo>`; otherwise `global`).

3. Continues execution using `commands/obsidian-research-deep.md`'s body.

Removed in next minor release.
````

- [ ] **Step 3: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 4: Commit**

```bash
git add commands/research.md commands/research-deep.md
git commit -m "$(cat <<'EOF'
docs(commands): mark /research + /research-deep as deprecated stubs

Old commands now print a visible deprecation warning to the user and
translate the legacy invocation to the new <repo>-first grammar:
- --project=<name> flag → first positional <repo>
- no --project= flag → "global" sentinel as <repo>

Stubs will be removed in the next minor release. Until then, all old
trigger phrases continue to work but emit the warning.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: Docs

### Task 10: Update SKILL.md + README.md + CHANGELOG.md

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md command table**

In `SKILL.md`, find the command table (likely under a "Layers" / "Commands" section). Update / add rows so the 5 commands consistently use `<repo>`:

```markdown
| `/obsidian-architect <repo>` | Scan codebase + generate v4 architecture report + AI flows + features lens + memory/RAG cross-flow (v4.3 family) |
| `/obsidian-brainstorm <repo>` | Interview-style brainstorm — 4-6 provocations, drill via follow-ups, distill into Brainstorms/ session file |
| `/obsidian-roadmap <repo>` | Synthesize Architecture + Research + Brainstorms signals into Roadmap.md + T-NNN tasks |
| `/obsidian-research <repo> <topic>` | Free-source web + academic research (use `global` as `<repo>` for vault-wide) |
| `/obsidian-research-deep <repo> <topic>` | Vault-first deep research with gap analysis + multi-sub-query fetch + propagation |
```

Also add a "Deprecated" subsection:

```markdown
**Deprecated (removed in next minor release):**
- `/research` → use `/obsidian-research`
- `/research-deep` → use `/obsidian-research-deep`
```

- [ ] **Step 2: Update README.md command table**

Same shape update in README.md. Find the existing command table and update the 5 rows + add deprecation subsection.

- [ ] **Step 3: Update CHANGELOG.md**

Append to the existing `## [Unreleased]` section:

```markdown
### Changed (CLI family alignment)
- 5 commands now share `<repo>` first-positional grammar via the new
  `scripts/commands/repo_resolver.py` helper. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-cli-family-repo-alignment-design.md`.
- `/obsidian-architect <repo>` — unchanged user-facing; internal Phase 0
  now routes through shared resolver.
- `/obsidian-brainstorm <repo>` — argument-hint renamed from
  `<project-name>` (now also accepts absolute path via hub
  local-path match).
- `/obsidian-roadmap <repo>` — same shape change.
- `/obsidian-research <repo> <topic> [--academic]` — NEW (renamed from
  `/research`). `<repo>` accepts `global` sentinel for vault-wide.
- `/obsidian-research-deep <repo> <topic>` — NEW (renamed from
  `/research-deep`).

### Deprecated
- `/research` — use `/obsidian-research`. Stub remains for one minor
  release with deprecation warning; will be removed.
- `/research-deep` — use `/obsidian-research-deep`. Same treatment.

### Added
- `scripts/commands/repo_resolver.py` — shared `<repo>` argument resolver
  with `RepoResolution` dataclass (4 states: project / global /
  ambiguous / unknown). 11 unit tests in
  `tests/commands/test_repo_resolver.py`.
- Frontmatter field `param-autocomplete` for slash commands — reserved
  for future Discord adapter to generate slash-command schemas.
  Sources: `vault-projects` / `vault-projects-plus-global` / `freetext`.
```

- [ ] **Step 4: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+readme+changelog): CLI family <repo> alignment announcement

SKILL.md + README.md command tables updated for 5 unified commands.
Deprecated subsection lists /research + /research-deep.

CHANGELOG.md Unreleased gets Changed (CLI family alignment) +
Deprecated + Added (resolver helper + param-autocomplete frontmatter)
subsections.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Acceptance

### Task 11: Smoke tests + full suite + builds

**Files:** No code changes. Verification only.

- [ ] **Step 1: Run full test suite**

Run: `uv run pytest tests/ -q`
Expected: All PASS (existing 408 + 11 new resolver tests = 419).

- [ ] **Step 2: Run all 4 platform adapter builds**

Run: `bash scripts/build.sh`
Expected: All 4 platforms (claude-code, codex-cli, gemini-cli, opencode) build successfully.

- [ ] **Step 3: Manual smoke — verify resolver works against actual langlive vault**

```bash
uv run python -c "
from pathlib import Path
from scripts.commands.repo_resolver import resolve_repo_arg

vault = Path('/Users/leric/Documents/SecondBrain')

# Exact project name
r = resolve_repo_arg('langlive-line-oa', vault, allow_global=False)
print(f'name match: state={r.state}, slug={r.project_slug}')

# Absolute path (the real repo path bound to langlive-line-oa hub)
r = resolve_repo_arg('/Users/leric/Desktop/code/langlive-line-oa', vault, allow_global=False)
print(f'path match: state={r.state}, slug={r.project_slug}, local_path={r.local_path}')

# Global sentinel allowed
r = resolve_repo_arg('global', vault, allow_global=True)
print(f'global allowed: state={r.state}')

# Global sentinel rejected
r = resolve_repo_arg('global', vault, allow_global=False)
print(f'global rejected: state={r.state}, msg starts with: {r.message[:50]!r}')

# Fuzzy match
r = resolve_repo_arg('langlive', vault, allow_global=False)
print(f'fuzzy: state={r.state}, candidates={r.candidates}')

# Unknown
r = resolve_repo_arg('totally-unknown', vault, allow_global=False)
print(f'unknown: state={r.state}, candidate count={len(r.candidates)}')
"
```

Expected output (paraphrased):
- `name match: state=project, slug=langlive-line-oa`
- `path match: state=project, slug=langlive-line-oa, local_path=/Users/leric/Desktop/code/langlive-line-oa`
- `global allowed: state=global`
- `global rejected: state=unknown, msg starts with: "'global' sentinel is not allowed..."`
- `fuzzy: state=ambiguous, candidates=['langlive-line-oa']`
- `unknown: state=unknown, candidate count >= 2` (vault has at least langlive-line-oa + ai-eden-service)

- [ ] **Step 4: Verify deprecation stubs are present**

```bash
grep -c "deprecated" /Users/leric/Desktop/code/obsidian-second-brain/commands/research.md
grep -c "deprecated" /Users/leric/Desktop/code/obsidian-second-brain/commands/research-deep.md
```

Expected: both > 0.

- [ ] **Step 5: Verify new commands exist**

```bash
ls -la /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-research.md \
       /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-research-deep.md
```

Expected: both files exist, > 1 KB each.

- [ ] **Step 6: No commit — acceptance only**

If any step fails, write a `## Blocker` note at the top of this plan file describing the failure and STOP. Otherwise print `ALL TASKS COMPLETE`.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal | Tasks 1-11 (all needed for goal to land) |
| Non-goals | Implicit (Discord adapter not built; only Python scripts unchanged) |
| Scope (5 commands) | Tasks 4 (research), 5 (research-deep), 6 (brainstorm), 7 (roadmap), 8 (architect) |
| `<repo>` semantics — sentinel / path / name | Tasks 1, 2, 3 (resolver implementation) |
| New grammar per command | Tasks 4-8 (each command body update) |
| Shared resolver `scripts/commands/repo_resolver.py` | Tasks 1-3 |
| Backward compat (deprecation stubs) | Task 9 |
| Slash-command frontmatter `param-autocomplete` field | Tasks 4-8 (each command adds it) |
| Body parsing Phase 0 stub | Tasks 4-8 (each command's Phase 0 documents the resolver invocation) |
| Tests 1-8 (resolver unit) | Tasks 1, 2, 3 (4 + 3 + 4 = 11 resolver tests; spec listed 8 — overcounted) |
| Smoke 9-11 | Task 11 |
| Out-of-scope | Implicit (no Discord adapter ship, no `local-path` key rename, etc.) |
