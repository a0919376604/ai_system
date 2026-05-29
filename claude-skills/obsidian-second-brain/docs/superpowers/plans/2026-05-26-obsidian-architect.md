# obsidian-architect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/obsidian-architect <repo-path>` slash command that scans a codebase and writes an architecture overview plus per-module notes into the project hub at `Projects/<P>/Architecture/`, with diff-aware refresh that preserves user edits.

**Architecture:** Three-phase hybrid pipeline. Phase 1 is deterministic Python (`scripts/architect/`) that walks the repo, parses config files for entry points, runs module-proposal heuristics, and writes `_manifest.yml`. Phase 2 is an interactive checkpoint where the user reviews and confirms the manifest. Phase 3 is LLM synthesis driven by the command body using `repomix` per-module packing.

**Tech Stack:** Python 3.10+, `pyyaml` for manifest, `pathspec` for `.gitignore` handling, `repomix` (npm, optional) for repo packing, `pytest` for tests. Slash command body uses Claude Code dialect (adapter-compatible).

**Spec:** `docs/superpowers/specs/2026-05-26-obsidian-architect-design.md`

---

## File structure

### New files

```
scripts/
|-- architect_scan.py                 # thin CLI entry: python scripts/architect_scan.py <repo>
`-- architect/
    |-- __init__.py
    |-- walker.py                     # file tree, .gitignore filtering, language stats
    |-- repomix.py                    # repomix wrapper + Python fallback
    |-- entry_points.py               # parse package.json / pyproject.toml / etc.
    |-- deps.py                       # external dependency extraction
    |-- proposal.py                   # module proposal (default + merge + split + flat-fallback)
    |-- manifest.py                   # YAML read/write (no diff logic here)
    |-- manifest_diff.py              # added / removed / renamed detection
    |-- lockfile.py                   # hash tracking for field and note preservation
    |-- sentinels.py                  # parse @generated / @user blocks in notes
    |-- refresh.py                    # per-module re-synthesis decision
    `-- scan.py                       # main Phase 1 orchestrator (called by CLI)

commands/
`-- obsidian-architect.md             # slash command body (Phases 2 and 3)

tests/architect/
|-- __init__.py
|-- conftest.py                       # fixture helpers
|-- fixtures/
|   |-- single-lang-python/           # Python package, pyproject.toml, src/, tests/
|   |-- monorepo-pnpm/                # pnpm-workspace.yaml + 2 members
|   |-- polyglot/                     # Python + JS + shell mixed
|   |-- docs-only/                    # mostly markdown
|   `-- flat-repo/                    # all source files at root, no folders
|-- test_walker.py
|-- test_repomix.py
|-- test_entry_points.py
|-- test_deps.py
|-- test_proposal.py
|-- test_manifest.py
|-- test_manifest_diff.py
|-- test_lockfile.py
|-- test_sentinels.py
|-- test_refresh.py
`-- test_scan.py
```

### Modified files

- `pyproject.toml` - add `pyyaml`, `pathspec` to dependencies.
- `references/ai-first-rules.md` - register new `type:` values.
- `SKILL.md` - Layer 1 command list + count.
- `README.md` - commands table row.
- `CHANGELOG.md` - Unreleased entry.

### Responsibility boundaries

- `walker.py` knows about filesystem and `.gitignore`. It does not know what a "module" is.
- `proposal.py` knows about the module concept. It does not know about manifests or YAML.
- `manifest.py` knows about YAML. It does not know about diff or hashes.
- `manifest_diff.py` and `lockfile.py` are about change detection. They do not know about YAML serialization.
- `refresh.py` orchestrates the change-detection layers; it does not write files.
- `scan.py` orchestrates Phase 1 end-to-end and is the only file the CLI imports directly.
- The slash command body is the only thing that runs Phase 2 and Phase 3 (LLM synthesis). Python knows nothing about LLM.

---

## Phase A: Foundation

### Task 1: Add dependencies and package skeleton

**Files:**
- Modify: `pyproject.toml`
- Create: `scripts/architect/__init__.py`
- Create: `tests/architect/__init__.py`

- [ ] **Step 1: Update `pyproject.toml` dependencies block**

Replace the `dependencies` list:

```toml
dependencies = [
    "requests>=2.32.0",
    "python-dotenv>=1.0.0",
    "youtube-transcript-api>=0.6.2",
    "tomli>=2.0.0 ; python_version < '3.11'",
    "pyyaml>=6.0.1",
    "pathspec>=0.12.1",
]
```

- [ ] **Step 2: Install the new deps**

Run: `uv sync`
Expected: `pyyaml` and `pathspec` appear in `uv.lock`. No errors.

- [ ] **Step 3: Create empty package files**

```python
# scripts/architect/__init__.py
"""Codebase architecture scanner for /obsidian-architect.

This package is Phase 1 of the three-phase pipeline: deterministic scan
that produces a module manifest and scan report. Phase 2 (user manifest
review) and Phase 3 (LLM synthesis) live in the slash command body, not
in Python.
"""
```

```python
# tests/architect/__init__.py
```

- [ ] **Step 4: Verify install + import**

Run: `uv run python -c "import scripts.architect; import yaml; import pathspec; print('ok')"`
Expected: `ok`

- [ ] **Step 5: Commit**

```bash
git add pyproject.toml uv.lock scripts/architect/__init__.py tests/architect/__init__.py
git commit -m "feat(architect): add scripts/architect package skeleton + pyyaml/pathspec deps"
```

---

### Task 2: Create test fixture - single-lang-python

**Files:**
- Create: `tests/architect/fixtures/single-lang-python/pyproject.toml`
- Create: `tests/architect/fixtures/single-lang-python/src/auth/__init__.py`
- Create: `tests/architect/fixtures/single-lang-python/src/auth/login.py`
- Create: `tests/architect/fixtures/single-lang-python/src/db/__init__.py`
- Create: `tests/architect/fixtures/single-lang-python/src/db/queries.py`
- Create: `tests/architect/fixtures/single-lang-python/src/api/__init__.py`
- Create: `tests/architect/fixtures/single-lang-python/src/api/routes.py`
- Create: `tests/architect/fixtures/single-lang-python/tests/test_login.py`
- Create: `tests/architect/fixtures/single-lang-python/.gitignore`
- Create: `tests/architect/fixtures/single-lang-python/README.md`

- [ ] **Step 1: Write `pyproject.toml`**

```toml
[project]
name = "fixture-single-lang-python"
version = "0.1.0"
dependencies = ["requests>=2.31.0", "pydantic>=2.0"]

[project.scripts]
fixture-cli = "src.api.routes:main"
```

- [ ] **Step 2: Write source files**

```python
# src/auth/__init__.py
from .login import authenticate
```

```python
# src/auth/login.py
"""Auth login module."""

def authenticate(username: str, password: str) -> bool:
    return bool(username and password)
```

```python
# src/db/__init__.py
```

```python
# src/db/queries.py
"""DB queries module."""

def get_user(user_id: int) -> dict:
    return {"id": user_id}
```

```python
# src/api/__init__.py
```

```python
# src/api/routes.py
"""API routes module."""
from src.auth.login import authenticate
from src.db.queries import get_user


def main() -> None:
    print("hello")
```

```python
# tests/test_login.py
from src.auth.login import authenticate


def test_authenticate():
    assert authenticate("u", "p")
```

- [ ] **Step 3: Write `.gitignore` and `README.md`**

```gitignore
# .gitignore
__pycache__/
*.pyc
.venv/
dist/
```

```markdown
# Single-lang Python fixture

Used by tests/architect/test_walker.py and test_proposal.py.
```

- [ ] **Step 4: Initialize fixture git history**

Run from `tests/architect/fixtures/single-lang-python/`:
```bash
git init -q && git add -A && git commit -q -m "fixture: single-lang-python initial commit"
```

Expected: silent success. The fixture has one commit hash (used by Phase 1 to produce stable `last_scan.commit`).

- [ ] **Step 5: Commit fixture into the host repo**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add tests/architect/fixtures/single-lang-python/
git commit -m "test(architect): add single-lang-python fixture repo"
```

Note: nested `.git/` directories inside fixtures are filtered by git automatically (git does not recurse into them). To verify: `git ls-files tests/architect/fixtures/single-lang-python/ | head` shows source files but not `.git/`.

---

### Task 3: Create remaining test fixtures

**Files:**
- Create files under `tests/architect/fixtures/monorepo-pnpm/`
- Create files under `tests/architect/fixtures/polyglot/`
- Create files under `tests/architect/fixtures/docs-only/`
- Create files under `tests/architect/fixtures/flat-repo/`

- [ ] **Step 1: Write monorepo-pnpm fixture**

```yaml
# tests/architect/fixtures/monorepo-pnpm/pnpm-workspace.yaml
packages:
  - "packages/*"
```

```json
// tests/architect/fixtures/monorepo-pnpm/package.json
{ "name": "monorepo-root", "private": true, "workspaces": ["packages/*"] }
```

```json
// tests/architect/fixtures/monorepo-pnpm/packages/web/package.json
{ "name": "web", "version": "0.1.0", "main": "index.js", "dependencies": { "react": "^18.0.0" } }
```

```js
// tests/architect/fixtures/monorepo-pnpm/packages/web/index.js
module.exports = function main() { return "web" };
```

```json
// tests/architect/fixtures/monorepo-pnpm/packages/api/package.json
{ "name": "api", "version": "0.1.0", "main": "server.js", "dependencies": { "express": "^4.0.0" } }
```

```js
// tests/architect/fixtures/monorepo-pnpm/packages/api/server.js
module.exports = function start() { return "api" };
```

- [ ] **Step 2: Write polyglot fixture**

```toml
# tests/architect/fixtures/polyglot/pyproject.toml
[project]
name = "polyglot-fixture"
version = "0.1.0"
dependencies = ["click>=8.0"]
```

```python
# tests/architect/fixtures/polyglot/python/cli.py
"""Python CLI for polyglot fixture."""
def run() -> None:
    pass
```

```json
// tests/architect/fixtures/polyglot/web/package.json
{ "name": "polyglot-web", "main": "app.js" }
```

```js
// tests/architect/fixtures/polyglot/web/app.js
console.log("polyglot web");
```

```bash
# tests/architect/fixtures/polyglot/scripts/build.sh
#!/usr/bin/env bash
echo "building"
```

- [ ] **Step 3: Write docs-only fixture**

```markdown
# tests/architect/fixtures/docs-only/README.md
A docs-only repo. Mostly markdown.
```

```markdown
# tests/architect/fixtures/docs-only/docs/intro.md
# Intro
Long-form prose, no code.
```

```markdown
# tests/architect/fixtures/docs-only/docs/setup.md
# Setup
More prose.
```

```python
# tests/architect/fixtures/docs-only/scripts/build.py
"""Tiny script - well below the 5% source threshold."""
print("build")
```

- [ ] **Step 4: Write flat-repo fixture**

```python
# tests/architect/fixtures/flat-repo/main.py
"""Flat-layout fixture entry point."""
def main():
    print("flat")

if __name__ == "__main__":
    main()
```

```python
# tests/architect/fixtures/flat-repo/utils.py
def helper():
    return 42
```

```toml
# tests/architect/fixtures/flat-repo/pyproject.toml
[project]
name = "flat-repo"
version = "0.1.0"

[project.scripts]
flat = "main:main"
```

- [ ] **Step 5: Initialize git in each fixture and commit to host repo**

For each fixture directory:
```bash
cd tests/architect/fixtures/<name>/
git init -q && git add -A && git commit -q -m "fixture: <name> initial commit"
cd -
```

Then:
```bash
git add tests/architect/fixtures/
git commit -m "test(architect): add monorepo / polyglot / docs-only / flat-repo fixtures"
```

---

## Phase B: Walker

### Task 4: Walker - file tree with `.gitignore`

**Files:**
- Create: `scripts/architect/walker.py`
- Create: `tests/architect/test_walker.py`
- Create: `tests/architect/conftest.py`

- [ ] **Step 1: Write conftest helper**

```python
# tests/architect/conftest.py
"""Shared test helpers for tests/architect/."""

from pathlib import Path

import pytest

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def single_lang_python() -> Path:
    return FIXTURES_DIR / "single-lang-python"


@pytest.fixture
def monorepo_pnpm() -> Path:
    return FIXTURES_DIR / "monorepo-pnpm"


@pytest.fixture
def polyglot_repo() -> Path:
    return FIXTURES_DIR / "polyglot"


@pytest.fixture
def docs_only_repo() -> Path:
    return FIXTURES_DIR / "docs-only"


@pytest.fixture
def flat_repo() -> Path:
    return FIXTURES_DIR / "flat-repo"
```

- [ ] **Step 2: Write the failing test**

```python
# tests/architect/test_walker.py
from pathlib import Path

from scripts.architect.walker import walk_repo


def test_walk_repo_returns_relative_paths(single_lang_python: Path):
    files = walk_repo(single_lang_python)
    assert "pyproject.toml" in files
    assert "src/auth/login.py" in files
    assert "tests/test_login.py" in files


def test_walk_repo_excludes_gitignored(single_lang_python: Path, tmp_path: Path):
    # Create a __pycache__/ in the fixture to verify it's filtered.
    cache = single_lang_python / "__pycache__"
    cache.mkdir(exist_ok=True)
    (cache / "junk.pyc").touch()
    try:
        files = walk_repo(single_lang_python)
        assert not any("__pycache__" in f for f in files)
    finally:
        # Clean up so the fixture is not polluted.
        (cache / "junk.pyc").unlink()
        cache.rmdir()


def test_walk_repo_skips_binary_and_dot_git(single_lang_python: Path):
    files = walk_repo(single_lang_python)
    assert not any(f.startswith(".git/") for f in files)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_walker.py -v`
Expected: FAIL with `ImportError: cannot import name 'walk_repo'`.

- [ ] **Step 4: Implement walker**

```python
# scripts/architect/walker.py
"""Repo file walker. Filesystem traversal with .gitignore handling.

This module knows about files and directories. It does not know about
modules, manifests, or anything domain-specific to /obsidian-architect.
"""

from __future__ import annotations

from pathlib import Path

import pathspec

# Always-skip prefixes regardless of .gitignore. Includes .git itself
# (which is never gitignored but must not be walked) plus build outputs
# and dependency caches that are by convention not part of source.
ALWAYS_SKIP_DIRS = {
    ".git",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "dist",
    "build",
    "target",
    "out",
    ".next",
}


def _load_gitignore(repo_root: Path) -> pathspec.PathSpec:
    """Load .gitignore patterns from the repo root, if present."""
    gitignore = repo_root / ".gitignore"
    if not gitignore.exists():
        return pathspec.PathSpec.from_lines("gitwildmatch", [])
    with gitignore.open() as fh:
        return pathspec.PathSpec.from_lines("gitwildmatch", fh)


def _is_binary(path: Path) -> bool:
    """Cheap binary detection: scan first 8KB for a NUL byte."""
    try:
        with path.open("rb") as fh:
            chunk = fh.read(8192)
    except OSError:
        return True
    return b"\x00" in chunk


def walk_repo(repo_root: Path) -> list[str]:
    """Return a sorted list of POSIX-style relative file paths.

    Excludes: .git/, conventional build/cache dirs, .gitignore matches,
    binary files. Symlinks are followed only if they resolve inside repo_root.
    """
    repo_root = repo_root.resolve()
    spec = _load_gitignore(repo_root)
    results: list[str] = []

    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue

        # Always-skip check (by any path part)
        if any(part in ALWAYS_SKIP_DIRS for part in path.relative_to(repo_root).parts):
            continue

        rel = path.relative_to(repo_root).as_posix()
        if spec.match_file(rel):
            continue

        if _is_binary(path):
            continue

        # Symlink safety: must resolve inside repo_root.
        try:
            resolved = path.resolve()
            resolved.relative_to(repo_root)
        except ValueError:
            continue

        results.append(rel)

    return sorted(results)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_walker.py -v`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/walker.py tests/architect/test_walker.py tests/architect/conftest.py
git commit -m "feat(architect): walk_repo() with .gitignore + binary filtering"
```

---

### Task 5: Walker - language stats and git metadata

**Files:**
- Modify: `scripts/architect/walker.py`
- Modify: `tests/architect/test_walker.py`

- [ ] **Step 1: Add failing tests**

Append to `tests/architect/test_walker.py`:

```python
from scripts.architect.walker import language_stats, git_metadata


def test_language_stats_returns_counts_by_extension(single_lang_python: Path):
    stats = language_stats(single_lang_python)
    # stats is a list of dicts: [{"lang": "python", "files": N, "tokens": T}, ...]
    by_lang = {row["lang"]: row for row in stats}
    assert "python" in by_lang
    assert by_lang["python"]["files"] >= 5
    # Tokens are approximate via len(text) // 4 heuristic.
    assert by_lang["python"]["tokens"] > 0


def test_git_metadata_returns_commit_and_dirty(single_lang_python: Path):
    meta = git_metadata(single_lang_python)
    assert len(meta["commit"]) == 40  # full SHA
    assert meta["dirty"] is False
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_walker.py -v`
Expected: 2 new tests fail with `ImportError`.

- [ ] **Step 3: Implement `language_stats` and `git_metadata`**

Append to `scripts/architect/walker.py`:

```python
import subprocess

# Extension to language label. Conservative list - unknown extensions
# fall into "other".
EXT_TO_LANG = {
    ".py": "python",
    ".pyi": "python",
    ".js": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
    ".java": "java",
    ".kt": "kotlin",
    ".swift": "swift",
    ".c": "c",
    ".h": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".hpp": "cpp",
    ".md": "markdown",
    ".sh": "shell",
    ".bash": "shell",
    ".zsh": "shell",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".json": "json",
    ".html": "html",
    ".css": "css",
}


def _approx_tokens(text: str) -> int:
    """Rough proxy for LLM tokens. Roughly 4 chars per token for code."""
    return max(1, len(text) // 4)


def language_stats(repo_root: Path) -> list[dict]:
    """Return per-language file count and approximate token count.

    Sorted by token count descending. Result shape:
        [{"lang": "python", "files": 23, "tokens": 18400}, ...]
    """
    repo_root = repo_root.resolve()
    by_lang: dict[str, dict] = {}
    for rel in walk_repo(repo_root):
        path = repo_root / rel
        lang = EXT_TO_LANG.get(path.suffix.lower(), "other")
        row = by_lang.setdefault(lang, {"lang": lang, "files": 0, "tokens": 0})
        row["files"] += 1
        try:
            row["tokens"] += _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
    return sorted(by_lang.values(), key=lambda r: r["tokens"], reverse=True)


def git_metadata(repo_root: Path) -> dict:
    """Return {'commit': <40-char SHA>, 'dirty': bool}.

    Assumes repo_root is a git repo. Caller validates beforehand.
    """
    repo_root = repo_root.resolve()
    commit = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "-C", str(repo_root), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return {"commit": commit, "dirty": bool(status.strip())}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_walker.py -v`
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/walker.py tests/architect/test_walker.py
git commit -m "feat(architect): language_stats() + git_metadata()"
```

---

### Task 6: Repomix wrapper with Python fallback

**Files:**
- Create: `scripts/architect/repomix.py`
- Create: `tests/architect/test_repomix.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/architect/test_repomix.py
from pathlib import Path
from unittest.mock import patch

from scripts.architect.repomix import is_available, pack_module, pack_repo_metadata


def test_is_available_detects_repomix():
    # Just exercises the function. The actual return depends on whether
    # repomix is installed in the test environment. Should not raise.
    result = is_available()
    assert isinstance(result, bool)


def test_pack_module_returns_string_corpus(single_lang_python: Path):
    # Fall back to Python implementation if repomix not installed.
    corpus = pack_module(single_lang_python, include=["src/"])
    assert "src/auth/login.py" in corpus
    assert "def authenticate" in corpus


def test_pack_repo_metadata_returns_token_counts(single_lang_python: Path):
    meta = pack_repo_metadata(single_lang_python)
    # Shape: {"files": [{"path": ..., "tokens": N}], "total_tokens": N}
    assert "files" in meta
    assert "total_tokens" in meta
    assert meta["total_tokens"] > 0
    assert any(f["path"] == "src/auth/login.py" for f in meta["files"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_repomix.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement repomix wrapper**

```python
# scripts/architect/repomix.py
"""Wrapper around the `repomix` npm tool with a Python fallback.

repomix packs a repo into a single LLM-friendly corpus. We use it for
two things: getting per-file token counts during scan (pack_repo_metadata)
and packing a specific module's source for LLM synthesis (pack_module).

If `repomix` is not on PATH we fall back to a pure-Python implementation
that approximates the same output. Functional but slower (about 3x).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from scripts.architect.walker import _approx_tokens, walk_repo


def is_available() -> bool:
    """True iff `repomix` is on PATH."""
    return shutil.which("repomix") is not None


def pack_module(repo_root: Path, include: list[str], compress: bool = True) -> str:
    """Return packed XML of files matching `include` patterns.

    `include` accepts glob patterns relative to `repo_root`, e.g.
    ["src/auth/**", "src/api/**"].
    """
    repo_root = repo_root.resolve()
    if is_available():
        cmd = [
            "repomix",
            "--include", ",".join(include),
            "--style", "xml",
            "--stdout",
        ]
        if compress:
            cmd.append("--compress")
        proc = subprocess.run(
            cmd, cwd=str(repo_root), capture_output=True, text=True, check=True
        )
        return proc.stdout
    # Fallback: hand-build a minimal XML corpus.
    return _python_pack(repo_root, include)


def pack_repo_metadata(repo_root: Path) -> dict:
    """Return file list with per-file token counts.

    Shape: {"files": [{"path": "src/auth/login.py", "tokens": 41}, ...],
             "total_tokens": 18400}
    """
    repo_root = repo_root.resolve()
    if is_available():
        proc = subprocess.run(
            [
                "repomix",
                "--output-style", "json",
                "--top-files-len", "0",
                "--stdout",
            ],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=True,
        )
        data = json.loads(proc.stdout)
        # repomix JSON output shape: {"files": [...], "metrics": {"totalTokens": N}}
        return {
            "files": [
                {"path": f["path"], "tokens": f.get("tokens", _approx_tokens(f.get("content", "")))}
                for f in data.get("files", [])
            ],
            "total_tokens": data.get("metrics", {}).get("totalTokens", 0),
        }
    return _python_metadata(repo_root)


def _python_pack(repo_root: Path, include: list[str]) -> str:
    """Pure-Python fallback for pack_module."""
    import fnmatch

    selected: list[Path] = []
    for rel in walk_repo(repo_root):
        for pattern in include:
            if fnmatch.fnmatch(rel, pattern) or rel.startswith(pattern.rstrip("/*")):
                selected.append(repo_root / rel)
                break

    parts: list[str] = ["<repomix-fallback>"]
    for path in selected:
        rel = path.relative_to(repo_root).as_posix()
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        parts.append(f'<file path="{rel}">')
        parts.append(content)
        parts.append("</file>")
    parts.append("</repomix-fallback>")
    return "\n".join(parts)


def _python_metadata(repo_root: Path) -> dict:
    files: list[dict] = []
    total = 0
    for rel in walk_repo(repo_root):
        path = repo_root / rel
        try:
            tokens = _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            continue
        files.append({"path": rel, "tokens": tokens})
        total += tokens
    return {"files": files, "total_tokens": total}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_repomix.py -v`
Expected: 3 passed (whether or not `repomix` is installed; tests cover both paths).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/repomix.py tests/architect/test_repomix.py
git commit -m "feat(architect): repomix wrapper with pure-Python fallback"
```

---

## Phase C: Metadata extraction

### Task 7: Entry-point detector

**Files:**
- Create: `scripts/architect/entry_points.py`
- Create: `tests/architect/test_entry_points.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/architect/test_entry_points.py
from pathlib import Path

from scripts.architect.entry_points import detect_entry_points


def test_pyproject_scripts(single_lang_python: Path):
    eps = detect_entry_points(single_lang_python)
    # Expect entry from pyproject.toml [project.scripts]
    paths = [e["path"] for e in eps]
    labels = [e["label"] for e in eps]
    assert any("fixture-cli" in label for label in labels)
    assert any("src/api/routes" in p for p in paths)


def test_package_json_main(monorepo_pnpm: Path):
    eps = detect_entry_points(monorepo_pnpm / "packages" / "web")
    labels = [e["label"] for e in eps]
    paths = [e["path"] for e in eps]
    assert any("main" in label or "web" in label for label in labels)
    assert any("index.js" in p for p in paths)


def test_no_entry_points_when_absent(docs_only_repo: Path):
    eps = detect_entry_points(docs_only_repo)
    assert eps == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_entry_points.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement entry-point detector**

```python
# scripts/architect/entry_points.py
"""Detect repo entry points by parsing config files.

Returns a list of dicts with shape:
    {"path": "<repo-relative path or label>", "label": "<human label>", "kind": "<config-key>"}

Each detector is independent; this module is purely pattern-matching.
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


def detect_entry_points(repo_root: Path) -> list[dict]:
    """Run every detector and concatenate results."""
    repo_root = repo_root.resolve()
    eps: list[dict] = []
    eps.extend(_pyproject(repo_root))
    eps.extend(_package_json(repo_root))
    eps.extend(_cargo(repo_root))
    eps.extend(_go(repo_root))
    eps.extend(_makefile(repo_root))
    eps.extend(_dockerfile(repo_root))
    return eps


def _pyproject(repo_root: Path) -> list[dict]:
    path = repo_root / "pyproject.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    eps: list[dict] = []
    scripts = data.get("project", {}).get("scripts", {})
    for name, target in scripts.items():
        # target shape: "module.path:function"
        mod = target.split(":")[0].replace(".", "/") + ".py"
        eps.append({"path": mod, "label": f"pyproject.scripts.{name}", "kind": "pyproject"})
    poetry_scripts = data.get("tool", {}).get("poetry", {}).get("scripts", {})
    for name, target in poetry_scripts.items():
        mod = target.split(":")[0].replace(".", "/") + ".py"
        eps.append({"path": mod, "label": f"poetry.scripts.{name}", "kind": "pyproject-poetry"})
    return eps


def _package_json(repo_root: Path) -> list[dict]:
    path = repo_root / "package.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    eps: list[dict] = []
    if "main" in data:
        eps.append({"path": data["main"], "label": f"package.main ({data.get('name','?')})", "kind": "package-json"})
    bin_field = data.get("bin", {})
    if isinstance(bin_field, str):
        eps.append({"path": bin_field, "label": "package.bin", "kind": "package-json"})
    elif isinstance(bin_field, dict):
        for name, target in bin_field.items():
            eps.append({"path": target, "label": f"package.bin.{name}", "kind": "package-json"})
    return eps


def _cargo(repo_root: Path) -> list[dict]:
    path = repo_root / "Cargo.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    eps: list[dict] = []
    for bin_entry in data.get("bin", []):
        eps.append({
            "path": bin_entry.get("path", f"src/bin/{bin_entry.get('name','?')}.rs"),
            "label": f"cargo.bin.{bin_entry.get('name','?')}",
            "kind": "cargo",
        })
    if (repo_root / "src" / "main.rs").exists():
        eps.append({"path": "src/main.rs", "label": "cargo.default-bin", "kind": "cargo"})
    return eps


def _go(repo_root: Path) -> list[dict]:
    if not (repo_root / "go.mod").exists():
        return []
    eps: list[dict] = []
    for candidate in [repo_root / "main.go", repo_root / "cmd"]:
        if candidate.is_file():
            eps.append({"path": "main.go", "label": "go-main", "kind": "go"})
        elif candidate.is_dir():
            for sub in sorted(candidate.iterdir()):
                if (sub / "main.go").exists():
                    eps.append({
                        "path": f"cmd/{sub.name}/main.go",
                        "label": f"go-cmd.{sub.name}",
                        "kind": "go",
                    })
    return eps


_MAKEFILE_TARGET = re.compile(r"^([a-zA-Z0-9_.-]+):", re.MULTILINE)


def _makefile(repo_root: Path) -> list[dict]:
    path = repo_root / "Makefile"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    targets = _MAKEFILE_TARGET.findall(text)
    # Filter out variable assignments and .PHONY.
    interesting = [t for t in targets if not t.startswith(".") and t not in {"all", "clean"}]
    return [{"path": "Makefile", "label": f"make.{t}", "kind": "makefile"} for t in interesting[:5]]


_DOCKER_CMD = re.compile(r"^(ENTRYPOINT|CMD)\s+(.+)$", re.MULTILINE | re.IGNORECASE)


def _dockerfile(repo_root: Path) -> list[dict]:
    path = repo_root / "Dockerfile"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    eps: list[dict] = []
    for directive, value in _DOCKER_CMD.findall(text):
        eps.append({"path": "Dockerfile", "label": f"docker.{directive.upper()} {value.strip()[:60]}", "kind": "dockerfile"})
    return eps
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_entry_points.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/entry_points.py tests/architect/test_entry_points.py
git commit -m "feat(architect): detect_entry_points() multi-language config parser"
```

---

### Task 8: External dependency extractor

**Files:**
- Create: `scripts/architect/deps.py`
- Create: `tests/architect/test_deps.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_deps.py
from pathlib import Path

from scripts.architect.deps import detect_external_deps


def test_pyproject_deps(single_lang_python: Path):
    deps = detect_external_deps(single_lang_python)
    names = [d["name"] for d in deps]
    assert "requests" in names
    assert "pydantic" in names


def test_package_json_deps(monorepo_pnpm: Path):
    deps = detect_external_deps(monorepo_pnpm / "packages" / "web")
    names = [d["name"] for d in deps]
    assert "react" in names


def test_dev_deps_excluded(single_lang_python: Path):
    deps = detect_external_deps(single_lang_python)
    # Fixture pyproject has no dev group, but the function should still filter when present.
    # This test mainly asserts the function returns runtime-only.
    assert all(d.get("group", "runtime") == "runtime" for d in deps)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_deps.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement deps extractor**

```python
# scripts/architect/deps.py
"""External runtime-dependency extraction.

Reads pyproject.toml, package.json, Cargo.toml, go.mod for production deps.
Dev/test groups are excluded - we only want runtime so the architecture
doc reflects what the system needs at runtime.
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


def detect_external_deps(repo_root: Path) -> list[dict]:
    """Return list of {"name": str, "version": str|None, "group": "runtime", "source": str}."""
    repo_root = repo_root.resolve()
    out: list[dict] = []
    out.extend(_pyproject_deps(repo_root))
    out.extend(_package_json_deps(repo_root))
    out.extend(_cargo_deps(repo_root))
    out.extend(_go_mod_deps(repo_root))
    return out


_PYTHON_DEP_SPLIT = re.compile(r"[<>=!~]")


def _pyproject_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "pyproject.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    deps_list = data.get("project", {}).get("dependencies", [])
    out: list[dict] = []
    for dep in deps_list:
        name = _PYTHON_DEP_SPLIT.split(dep)[0].strip()
        out.append({"name": name, "version": dep, "group": "runtime", "source": "pyproject"})
    return out


def _package_json_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "package.json"
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out: list[dict] = []
    for name, version in (data.get("dependencies") or {}).items():
        out.append({"name": name, "version": version, "group": "runtime", "source": "package.json"})
    return out


def _cargo_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "Cargo.toml"
    if not path.exists():
        return []
    data = tomllib.loads(path.read_text())
    out: list[dict] = []
    for name, version in (data.get("dependencies") or {}).items():
        version_str = version if isinstance(version, str) else version.get("version", "")
        out.append({"name": name, "version": version_str, "group": "runtime", "source": "cargo"})
    return out


_GO_REQUIRE = re.compile(r"^\s*([\w./-]+)\s+(v[\w.\-+]+)", re.MULTILINE)


def _go_mod_deps(repo_root: Path) -> list[dict]:
    path = repo_root / "go.mod"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    return [
        {"name": name, "version": version, "group": "runtime", "source": "go.mod"}
        for name, version in _GO_REQUIRE.findall(text)
    ]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_deps.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/deps.py tests/architect/test_deps.py
git commit -m "feat(architect): detect_external_deps() runtime-only dep extraction"
```

---

## Phase D: Module proposal

### Task 9: Default folder-based proposal with skip set

**Files:**
- Create: `scripts/architect/proposal.py`
- Create: `tests/architect/test_proposal.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_proposal.py
from pathlib import Path

from scripts.architect.proposal import propose_modules


def test_default_proposal_one_per_top_folder(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    slugs = sorted(m["slug"] for m in modules)
    # src/ contains auth, db, api -> 3 modules (default looks inside src/ if it exists)
    assert "auth" in slugs
    assert "db" in slugs
    assert "api" in slugs


def test_tests_folder_excluded(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    by_slug = {m["slug"]: m for m in modules}
    # tests/ appears with excluded=True, but not omitted entirely
    if "tests" in by_slug:
        assert by_slug["tests"]["excluded"] is True


def test_role_defaults_to_other(single_lang_python: Path):
    modules = propose_modules(single_lang_python)
    for m in modules:
        if not m["excluded"]:
            assert m["role"] in {"surface", "core", "adapter", "infra", "data", "docs", "other"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_proposal.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement default proposal + skip set**

```python
# scripts/architect/proposal.py
"""Module proposal heuristics.

Inputs: repo path. Output: list of proposed module dicts ready for
inclusion in _manifest.yml. Pure function, no I/O beyond reading the
repo filesystem.

Module dict shape:
    {"slug": str, "display_name": str, "paths": [str], "role": str,
     "excluded": bool, "description": None, "pattern": None}
"""

from __future__ import annotations

import re
from pathlib import Path

# Folders that become modules with excluded=True. They show up in
# overview narrative but no per-module note is generated.
SKIP_AS_MODULE = {
    "tests", "test", "__tests__", "spec",
    "docs", "documentation",
    "examples", "example",
    ".github",
    "dist", "build", "target", "out",
}

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def _slugify(name: str) -> str:
    s = _SLUG_RE.sub("-", name.lower()).strip("-")
    return s or "module"


def _candidate_roots(repo_root: Path) -> list[Path]:
    """Where to look for top-level modules.

    If src/ exists and contains folders, that's the module root.
    Otherwise the repo root itself.
    """
    src = repo_root / "src"
    if src.is_dir() and any(p.is_dir() for p in src.iterdir()):
        return [src]
    return [repo_root]


def propose_modules(repo_root: Path) -> list[dict]:
    """Default proposal: one module per first-level folder under the module root."""
    repo_root = repo_root.resolve()
    roots = _candidate_roots(repo_root)
    modules: list[dict] = []
    seen: set[str] = set()

    for root in roots:
        for entry in sorted(root.iterdir()):
            if not entry.is_dir():
                continue
            if entry.name.startswith("."):
                continue
            slug = _slugify(entry.name)
            if slug in seen:
                continue
            seen.add(slug)
            rel_path = entry.relative_to(repo_root).as_posix() + "/"
            modules.append({
                "slug": slug,
                "display_name": entry.name.replace("-", " ").replace("_", " ").title(),
                "paths": [rel_path],
                "role": "other",
                "excluded": entry.name in SKIP_AS_MODULE,
                "description": None,
                "pattern": None,
            })
    return modules
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_proposal.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/proposal.py tests/architect/test_proposal.py
git commit -m "feat(architect): propose_modules() default folder-based proposal"
```

---

### Task 10: Proposal heuristics - merge, split, flat-fallback, monorepo

**Files:**
- Modify: `scripts/architect/proposal.py`
- Modify: `tests/architect/test_proposal.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_proposal.py`:

```python
from scripts.architect.proposal import propose_modules_with_heuristics


def test_flat_repo_fallback(flat_repo: Path):
    modules = propose_modules_with_heuristics(flat_repo)
    slugs = [m["slug"] for m in modules]
    # Flat layout produces a single "core" module covering the root.
    assert "core" in slugs


def test_monorepo_workspaces(monorepo_pnpm: Path):
    modules = propose_modules_with_heuristics(monorepo_pnpm)
    slugs = sorted(m["slug"] for m in modules)
    assert "web" in slugs
    assert "api" in slugs


def test_polyglot_proposal(polyglot_repo: Path):
    modules = propose_modules_with_heuristics(polyglot_repo)
    slugs = sorted(m["slug"] for m in modules if not m["excluded"])
    # python/, web/, scripts/ are top-level
    assert "python" in slugs
    assert "web" in slugs


def test_docs_only_warning_signal(docs_only_repo: Path):
    modules = propose_modules_with_heuristics(docs_only_repo)
    # docs/ excluded, scripts/ kept. Function still returns modules; the
    # "mostly docs" warning is emitted by scan.py, not proposal.py.
    slugs = [m["slug"] for m in modules]
    assert "scripts" in slugs
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_proposal.py -v`
Expected: 4 new tests fail with ImportError.

- [ ] **Step 3: Implement heuristics**

Append to `scripts/architect/proposal.py`:

```python
import json

from scripts.architect.walker import walk_repo


def propose_modules_with_heuristics(repo_root: Path) -> list[dict]:
    """Run the full proposal pipeline: default + monorepo + flat + merge/split."""
    repo_root = repo_root.resolve()

    # 1. Monorepo detection short-circuits the rest.
    workspaces = _detect_workspaces(repo_root)
    if workspaces:
        return _monorepo_proposal(repo_root, workspaces)

    # 2. Start with default.
    modules = propose_modules(repo_root)

    # 3. Flat-repo fallback.
    non_skip = [m for m in modules if not m["excluded"]]
    if len(non_skip) < 3:
        modules = _flat_repo_proposal(repo_root, modules)

    return modules


def _detect_workspaces(repo_root: Path) -> list[str]:
    """Detect monorepo workspaces from pnpm/yarn/npm/cargo/go config.

    Returns the list of workspace member directory paths (relative).
    Empty list means not a monorepo.
    """
    # pnpm
    pnpm = repo_root / "pnpm-workspace.yaml"
    if pnpm.exists():
        import yaml
        data = yaml.safe_load(pnpm.read_text()) or {}
        patterns = data.get("packages", [])
        return _expand_workspace_globs(repo_root, patterns)

    # npm/yarn workspaces in package.json
    pkg = repo_root / "package.json"
    if pkg.exists():
        data = json.loads(pkg.read_text())
        ws = data.get("workspaces")
        if isinstance(ws, list):
            return _expand_workspace_globs(repo_root, ws)
        if isinstance(ws, dict) and "packages" in ws:
            return _expand_workspace_globs(repo_root, ws["packages"])

    # Cargo workspace
    cargo = repo_root / "Cargo.toml"
    if cargo.exists():
        try:
            import tomllib  # type: ignore[import-not-found]
        except ImportError:
            import tomli as tomllib  # type: ignore[no-redef]
        data = tomllib.loads(cargo.read_text())
        members = data.get("workspace", {}).get("members", [])
        return _expand_workspace_globs(repo_root, members)

    return []


def _expand_workspace_globs(repo_root: Path, patterns: list[str]) -> list[str]:
    """Expand patterns like 'packages/*' into concrete relative directory paths."""
    import fnmatch

    out: list[str] = []
    for pattern in patterns:
        if "*" in pattern:
            base = pattern.split("*")[0].rstrip("/")
            base_path = repo_root / base
            if base_path.is_dir():
                for sub in sorted(base_path.iterdir()):
                    if sub.is_dir() and fnmatch.fnmatch(sub.name, pattern.split("/")[-1]):
                        out.append(sub.relative_to(repo_root).as_posix())
        else:
            full = repo_root / pattern
            if full.is_dir():
                out.append(pattern)
    return out


def _monorepo_proposal(repo_root: Path, workspaces: list[str]) -> list[dict]:
    modules: list[dict] = []
    for ws_path in workspaces:
        slug = _slugify(Path(ws_path).name)
        modules.append({
            "slug": slug,
            "display_name": Path(ws_path).name.replace("-", " ").replace("_", " ").title(),
            "paths": [ws_path + "/"],
            "role": "other",
            "excluded": False,
            "description": None,
            "pattern": None,
        })
    return modules


def _flat_repo_proposal(repo_root: Path, base: list[dict]) -> list[dict]:
    """Add a 'core' module covering the repo root files, alongside any folders."""
    # Keep non-skip folder modules; prepend a 'core' module for root-level files.
    folder_modules = base
    core = {
        "slug": "core",
        "display_name": "Core",
        "paths": ["./"],
        "role": "core",
        "excluded": False,
        "description": None,
        "pattern": None,
    }
    return [core] + folder_modules
```

Note: `import yaml` and `import tomllib`/`tomli` are deferred inside the function bodies (lazy import) so the top-level imports of `proposal.py` stay tight and the module loads quickly for tests that do not exercise monorepo paths.

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_proposal.py -v`
Expected: 7 passed (3 from Task 9, 4 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/proposal.py tests/architect/test_proposal.py
git commit -m "feat(architect): propose_modules_with_heuristics() monorepo + flat-fallback"
```

---

### Task 10b: Merge and split heuristics

Spec section 7.1 promises two more heuristics on top of the default proposal:
- **Merge:** sibling folders sharing a primary language, each below 2000 tokens, are proposed merged.
- **Split:** a folder with more than 30 files and more than one entry point is proposed split.

These keep the manifest from generating thin or oversized modules. Both are best-effort and the user can override via `_manifest.yml` anyway.

**Files:**
- Modify: `scripts/architect/proposal.py`
- Modify: `tests/architect/test_proposal.py`

- [ ] **Step 1: Write failing tests**

Append to `tests/architect/test_proposal.py`:

```python
from scripts.architect.proposal import _merge_small_siblings, _split_dense_folder


def test_merge_small_siblings_combines_two_tiny_python_folders(tmp_path: Path):
    # Build a tiny synthetic repo: two sibling folders, both small, same language.
    (tmp_path / "small_a").mkdir()
    (tmp_path / "small_a" / "x.py").write_text("def a(): return 1\n")
    (tmp_path / "small_b").mkdir()
    (tmp_path / "small_b" / "y.py").write_text("def b(): return 2\n")
    (tmp_path / "pyproject.toml").write_text("[project]\nname='t'\nversion='0.1'\n")

    base = [
        {"slug": "small-a", "display_name": "Small A", "paths": ["small_a/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
        {"slug": "small-b", "display_name": "Small B", "paths": ["small_b/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
    ]
    merged = _merge_small_siblings(tmp_path, base)
    # Expect a single merged module covering both folders.
    assert len(merged) == 1
    assert sorted(merged[0]["paths"]) == ["small_a/", "small_b/"]


def test_merge_keeps_large_modules_separate(tmp_path: Path):
    # Folder A is big enough not to merge.
    (tmp_path / "big").mkdir()
    (tmp_path / "big" / "f.py").write_text("x = 1\n" * 600)  # well over 2000 tokens
    (tmp_path / "small").mkdir()
    (tmp_path / "small" / "g.py").write_text("y = 2\n")

    base = [
        {"slug": "big", "display_name": "Big", "paths": ["big/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
        {"slug": "small", "display_name": "Small", "paths": ["small/"],
         "role": "other", "excluded": False, "description": None, "pattern": None},
    ]
    out = _merge_small_siblings(tmp_path, base)
    assert len(out) == 2  # untouched


def test_split_dense_folder_with_multiple_entry_points(tmp_path: Path):
    # Build a folder with 35 files and two entry-point-like markers.
    fold = tmp_path / "dense"
    fold.mkdir()
    for i in range(35):
        (fold / f"f{i}.py").write_text("x = 1\n")
    (fold / "cli_a.py").write_text("def main_a(): pass\n")
    (fold / "cli_b.py").write_text("def main_b(): pass\n")

    base = [{"slug": "dense", "display_name": "Dense", "paths": ["dense/"],
             "role": "other", "excluded": False, "description": None, "pattern": None}]
    entry_points = [
        {"path": "dense/cli_a.py", "label": "ep_a", "kind": "pyproject"},
        {"path": "dense/cli_b.py", "label": "ep_b", "kind": "pyproject"},
    ]
    out = _split_dense_folder(tmp_path, base, entry_points)
    # Expect at least a split proposal (two sub-modules or marker telling caller to split).
    # For v1 implementation we simply tag the module dict with split_hint: True.
    assert out[0].get("split_hint") is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_proposal.py::test_merge_small_siblings_combines_two_tiny_python_folders -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement merge and split heuristics**

Append to `scripts/architect/proposal.py`:

```python
def _folder_token_count(repo_root: Path, folder_rel: str) -> int:
    """Approximate token count of all files under a given folder."""
    from scripts.architect.walker import EXT_TO_LANG, _approx_tokens, walk_repo

    base = folder_rel.rstrip("/")
    total = 0
    for rel in walk_repo(repo_root):
        if rel == base or rel.startswith(base + "/"):
            path = repo_root / rel
            try:
                total += _approx_tokens(path.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                continue
    return total


def _folder_primary_language(repo_root: Path, folder_rel: str) -> str:
    """Primary language of a folder by file count of recognised extensions."""
    from scripts.architect.walker import EXT_TO_LANG, walk_repo

    base = folder_rel.rstrip("/")
    counts: dict[str, int] = {}
    for rel in walk_repo(repo_root):
        if rel == base or rel.startswith(base + "/"):
            ext = Path(rel).suffix.lower()
            lang = EXT_TO_LANG.get(ext, "other")
            counts[lang] = counts.get(lang, 0) + 1
    if not counts:
        return "unknown"
    return max(counts.items(), key=lambda kv: kv[1])[0]


def _merge_small_siblings(repo_root: Path, modules: list[dict], threshold: int = 2000) -> list[dict]:
    """Propose merging adjacent modules that share a primary language and are each below `threshold` tokens.

    Returns a new list. Original input is not mutated. Conservative: only merges
    pairs of modules whose paths are siblings at the same depth and where neither
    is excluded.
    """
    if len(modules) < 2:
        return list(modules)

    enriched = []
    for m in modules:
        if m["excluded"] or len(m["paths"]) != 1:
            enriched.append((m, None, None))
            continue
        folder = m["paths"][0]
        tokens = _folder_token_count(repo_root, folder)
        lang = _folder_primary_language(repo_root, folder)
        enriched.append((m, tokens, lang))

    merged: list[dict] = []
    skip_next = False
    for i, (m, tokens, lang) in enumerate(enriched):
        if skip_next:
            skip_next = False
            continue
        if i + 1 < len(enriched):
            n_mod, n_tokens, n_lang = enriched[i + 1]
            if (
                tokens is not None and n_tokens is not None
                and tokens < threshold and n_tokens < threshold
                and lang == n_lang and lang != "unknown"
            ):
                combined = {
                    "slug": f"{m['slug']}-{n_mod['slug']}",
                    "display_name": f"{m['display_name']} + {n_mod['display_name']}",
                    "paths": sorted(m["paths"] + n_mod["paths"]),
                    "role": m["role"],
                    "excluded": False,
                    "description": None,
                    "pattern": None,
                    "merge_hint": True,
                }
                merged.append(combined)
                skip_next = True
                continue
        merged.append(m)
    return merged


def _split_dense_folder(
    repo_root: Path, modules: list[dict], entry_points: list[dict], file_threshold: int = 30
) -> list[dict]:
    """Tag modules whose single folder is large AND has multiple entry points as 'split_hint'.

    v1 does not auto-split (path layouts vary too much per ecosystem). Instead
    the module dict is marked so Phase 2 can prompt the user.
    """
    from scripts.architect.walker import walk_repo

    out: list[dict] = []
    for m in modules:
        if m["excluded"] or len(m["paths"]) != 1:
            out.append(m)
            continue
        base = m["paths"][0].rstrip("/")
        file_count = sum(
            1 for rel in walk_repo(repo_root)
            if rel == base or rel.startswith(base + "/")
        )
        ep_in_module = sum(
            1 for ep in entry_points
            if ep["path"].startswith(base + "/") or ep["path"] == base
        )
        if file_count > file_threshold and ep_in_module > 1:
            tagged = dict(m)
            tagged["split_hint"] = True
            out.append(tagged)
        else:
            out.append(m)
    return out
```

- [ ] **Step 4: Wire the heuristics into `propose_modules_with_heuristics`**

Replace the body of `propose_modules_with_heuristics` in `scripts/architect/proposal.py`:

```python
def propose_modules_with_heuristics(repo_root: Path, entry_points: list[dict] | None = None) -> list[dict]:
    """Run the full proposal pipeline: monorepo -> default -> flat-fallback -> merge -> split."""
    repo_root = repo_root.resolve()

    # 1. Monorepo detection short-circuits the rest.
    workspaces = _detect_workspaces(repo_root)
    if workspaces:
        return _monorepo_proposal(repo_root, workspaces)

    # 2. Start with default.
    modules = propose_modules(repo_root)

    # 3. Flat-repo fallback.
    non_skip = [m for m in modules if not m["excluded"]]
    if len(non_skip) < 3:
        modules = _flat_repo_proposal(repo_root, modules)

    # 4. Merge small siblings.
    modules = _merge_small_siblings(repo_root, modules)

    # 5. Tag dense folders for split.
    if entry_points:
        modules = _split_dense_folder(repo_root, modules, entry_points)

    return modules
```

The signature gained an optional `entry_points` argument; `scan.py` (Task 16) passes its detected entry points in. Other call sites (older tests) still work because the argument is optional.

- [ ] **Step 5: Run all proposal tests**

Run: `uv run pytest tests/architect/test_proposal.py -v`
Expected: 10 passed (7 from before + 3 new).

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/proposal.py tests/architect/test_proposal.py
git commit -m "feat(architect): merge_small_siblings + split_dense_folder heuristics"
```

---

## Phase E: Manifest

### Task 11: Manifest YAML read/write

**Files:**
- Create: `scripts/architect/manifest.py`
- Create: `tests/architect/test_manifest.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_manifest.py
from datetime import date
from pathlib import Path

from scripts.architect.manifest import Manifest, load_manifest, write_manifest


def test_round_trip(tmp_path: Path):
    manifest = Manifest(
        version=1,
        repo={
            "name": "demo",
            "root": "/abs/path",
            "primary_language": "python",
            "languages": [{"lang": "python", "files": 3, "tokens": 100}],
        },
        last_scan={"date": "2026-05-26", "commit": "abc", "dirty": False, "scanner_version": "0.1.0"},
        modules=[{
            "slug": "auth",
            "display_name": "Auth",
            "paths": ["src/auth/"],
            "role": "core",
            "excluded": False,
            "description": None,
            "pattern": None,
        }],
    )
    target = tmp_path / "_manifest.yml"
    write_manifest(manifest, target)
    loaded = load_manifest(target)
    assert loaded.modules[0]["slug"] == "auth"
    assert loaded.repo["name"] == "demo"


def test_load_missing_returns_none(tmp_path: Path):
    assert load_manifest(tmp_path / "nope.yml") is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_manifest.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement manifest read/write**

```python
# scripts/architect/manifest.py
"""_manifest.yml read/write. Knows YAML; knows nothing about diff or hashes."""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from pathlib import Path

import yaml


@dataclass
class Manifest:
    version: int
    repo: dict
    last_scan: dict
    modules: list[dict] = field(default_factory=list)


def load_manifest(path: Path) -> Manifest | None:
    """Return Manifest, or None if file does not exist."""
    if not path.exists():
        return None
    data = yaml.safe_load(path.read_text())
    return Manifest(
        version=data.get("version", 1),
        repo=data.get("repo", {}),
        last_scan=data.get("last_scan", {}),
        modules=data.get("modules", []),
    )


def write_manifest(manifest: Manifest, path: Path) -> None:
    """Serialize to YAML at `path`. Parent directory must exist."""
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = asdict(manifest)
    with path.open("w") as fh:
        yaml.safe_dump(payload, fh, sort_keys=False, default_flow_style=False, allow_unicode=True)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_manifest.py -v`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/manifest.py tests/architect/test_manifest.py
git commit -m "feat(architect): Manifest dataclass + YAML load/write"
```

---

### Task 12: Manifest diff (added / removed / renamed)

**Files:**
- Create: `scripts/architect/manifest_diff.py`
- Create: `tests/architect/test_manifest_diff.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_manifest_diff.py
from scripts.architect.manifest_diff import diff_modules


def test_added_modules():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}, {"slug": "api", "paths": ["src/api/"]}]
    d = diff_modules(old, new)
    assert d.added == ["api"]
    assert d.removed == []
    assert d.renamed == []


def test_removed_modules():
    old = [{"slug": "auth", "paths": ["src/auth/"]}, {"slug": "old", "paths": ["src/old/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}]
    d = diff_modules(old, new)
    assert d.added == []
    assert d.removed == ["old"]
    assert d.renamed == []


def test_renamed_paths():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/authentication/"]}]
    d = diff_modules(old, new)
    assert d.renamed == [("auth", ["src/auth/"], ["src/authentication/"])]


def test_unchanged():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}]
    d = diff_modules(old, new)
    assert d.added == []
    assert d.removed == []
    assert d.renamed == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_manifest_diff.py -v`
Expected: 4 fail with ImportError.

- [ ] **Step 3: Implement diff**

```python
# scripts/architect/manifest_diff.py
"""Manifest diff: classify changes between two module lists by slug."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ModuleDiff:
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    renamed: list[tuple[str, list[str], list[str]]] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)


def diff_modules(old: list[dict], new: list[dict]) -> ModuleDiff:
    """Classify slug-level changes between two manifest module lists.

    Added: slug in new but not old.
    Removed: slug in old but not new.
    Renamed: same slug, different paths.
    """
    old_by_slug = {m["slug"]: m for m in old}
    new_by_slug = {m["slug"]: m for m in new}

    d = ModuleDiff()
    d.added = sorted(set(new_by_slug) - set(old_by_slug))
    d.removed = sorted(set(old_by_slug) - set(new_by_slug))

    for slug in sorted(set(old_by_slug) & set(new_by_slug)):
        old_paths = sorted(old_by_slug[slug].get("paths", []))
        new_paths = sorted(new_by_slug[slug].get("paths", []))
        if old_paths != new_paths:
            d.renamed.append((slug, old_paths, new_paths))
        else:
            d.unchanged.append(slug)
    return d
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_manifest_diff.py -v`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/manifest_diff.py tests/architect/test_manifest_diff.py
git commit -m "feat(architect): diff_modules() classify added/removed/renamed by slug"
```

---

### Task 13: Lockfile and field preservation

**Files:**
- Create: `scripts/architect/lockfile.py`
- Create: `tests/architect/test_lockfile.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_lockfile.py
from pathlib import Path

from scripts.architect.lockfile import Lockfile, field_was_user_edited, hash_value, write_lockfile, load_lockfile


def test_hash_is_stable():
    assert hash_value("hello") == hash_value("hello")
    assert hash_value("hello") != hash_value("world")


def test_field_user_edited_detection(tmp_path: Path):
    lock = Lockfile(version=1, scanner_version="0.1.0", fields={
        "modules.auth.display_name": {"hash": hash_value("Auth"), "value": "Auth"}
    }, note_blocks={})
    # Current manifest still has the LLM-written value: not user-edited.
    assert field_was_user_edited(lock, "modules.auth.display_name", current_value="Auth") is False
    # Current manifest has a different value: user edited it.
    assert field_was_user_edited(lock, "modules.auth.display_name", current_value="Authentication") is True


def test_lockfile_round_trip(tmp_path: Path):
    lock = Lockfile(
        version=1,
        scanner_version="0.1.0",
        fields={"modules.auth.role": {"hash": hash_value("core"), "value": "core"}},
        note_blocks={"modules/auth.md": {"what-it-does": {"hash": hash_value("paragraph")}}},
    )
    target = tmp_path / "_manifest.lock.json"
    write_lockfile(lock, target)
    loaded = load_lockfile(target)
    assert loaded.fields["modules.auth.role"]["value"] == "core"
    assert loaded.note_blocks["modules/auth.md"]["what-it-does"]["hash"] == hash_value("paragraph")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: 3 fail with ImportError.

- [ ] **Step 3: Implement lockfile**

```python
# scripts/architect/lockfile.py
"""Lockfile: hash-based tracking of LLM-written content.

For each LLM-written manifest field and note section, we store a SHA-256
hash of the value as written. On refresh, we compute the hash of the
current value; if it matches the lockfile, the field is LLM territory
and may be overwritten. If it does not match, the user edited it and
we preserve.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field, asdict
from pathlib import Path


@dataclass
class Lockfile:
    version: int
    scanner_version: str
    fields: dict = field(default_factory=dict)
    note_blocks: dict = field(default_factory=dict)


def hash_value(s: str) -> str:
    """Return 'sha256:<hex>' for stable comparison."""
    return "sha256:" + hashlib.sha256(s.encode("utf-8")).hexdigest()


def load_lockfile(path: Path) -> Lockfile | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    return Lockfile(
        version=data.get("version", 1),
        scanner_version=data.get("scanner_version", "0.0.0"),
        fields=data.get("fields", {}),
        note_blocks=data.get("note_blocks", {}),
    )


def write_lockfile(lock: Lockfile, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(lock), indent=2, sort_keys=True))


def field_was_user_edited(lock: Lockfile, field_key: str, current_value: str) -> bool:
    """True iff the current value differs from the LLM-written value recorded in the lockfile.

    If the field is not in the lockfile (e.g. first-run), returns False
    (treat as LLM-territory; safe because lockfile will be updated on first write).
    """
    record = lock.fields.get(field_key)
    if record is None:
        return False
    return record["hash"] != hash_value(current_value)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_lockfile.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/lockfile.py tests/architect/test_lockfile.py
git commit -m "feat(architect): Lockfile with sha256 field+block hash tracking"
```

---

## Phase F: Sentinels + refresh decision

### Task 14: Sentinel parser

**Files:**
- Create: `scripts/architect/sentinels.py`
- Create: `tests/architect/test_sentinels.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_sentinels.py
from scripts.architect.sentinels import parse_blocks, render_block, GeneratedBlock, UserBlock


SAMPLE = """\
## For future Claude

Top preamble. Not in a sentinel.

<!-- @generated:start what-it-does -->
LLM paragraph here.
<!-- @generated:end what-it-does -->

<!-- @user:start notes -->
## Notes
User wrote this.
<!-- @user:end notes -->
"""


def test_parses_generated_block():
    blocks = parse_blocks(SAMPLE)
    gen = [b for b in blocks if isinstance(b, GeneratedBlock)]
    assert len(gen) == 1
    assert gen[0].name == "what-it-does"
    assert "LLM paragraph" in gen[0].body


def test_parses_user_block():
    blocks = parse_blocks(SAMPLE)
    user = [b for b in blocks if isinstance(b, UserBlock)]
    assert len(user) == 1
    assert user[0].name == "notes"
    assert "User wrote this" in user[0].body


def test_render_generated_block_round_trips():
    blocks = parse_blocks(SAMPLE)
    gen = [b for b in blocks if isinstance(b, GeneratedBlock)][0]
    rendered = render_block(gen)
    assert "@generated:start what-it-does" in rendered
    assert "@generated:end what-it-does" in rendered
    assert "LLM paragraph" in rendered
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_sentinels.py -v`
Expected: 3 fail with ImportError.

- [ ] **Step 3: Implement sentinel parser**

```python
# scripts/architect/sentinels.py
"""Parse and render @generated / @user sentinel blocks in note bodies.

Sentinels:
    <!-- @generated:start <name> -->
    ...body...
    <!-- @generated:end <name> -->

    <!-- @user:start <name> -->
    ...body...
    <!-- @user:end <name> -->

Generated blocks are LLM territory: refresh overwrites the body.
User blocks are never touched.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class GeneratedBlock:
    name: str
    body: str


@dataclass
class UserBlock:
    name: str
    body: str


@dataclass
class PlainText:
    body: str


_GEN_RE = re.compile(
    r"<!--\s*@generated:start\s+(?P<name>[\w-]+)\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@generated:end\s+(?P=name)\s*-->",
    re.DOTALL,
)

_USER_RE = re.compile(
    r"<!--\s*@user:start\s+(?P<name>[\w-]+)\s*-->\n"
    r"(?P<body>.*?)\n"
    r"<!--\s*@user:end\s+(?P=name)\s*-->",
    re.DOTALL,
)


def parse_blocks(text: str) -> list:
    """Return ordered list of GeneratedBlock | UserBlock | PlainText spanning the text."""
    # Combine both regexes into one pass with named alternation.
    spans: list[tuple[int, int, object]] = []
    for m in _GEN_RE.finditer(text):
        spans.append((m.start(), m.end(), GeneratedBlock(name=m.group("name"), body=m.group("body"))))
    for m in _USER_RE.finditer(text):
        spans.append((m.start(), m.end(), UserBlock(name=m.group("name"), body=m.group("body"))))
    spans.sort(key=lambda s: s[0])

    out: list = []
    cursor = 0
    for start, end, block in spans:
        if start > cursor:
            plain = text[cursor:start]
            if plain.strip():
                out.append(PlainText(body=plain))
        out.append(block)
        cursor = end
    tail = text[cursor:]
    if tail.strip():
        out.append(PlainText(body=tail))
    return out


def render_block(block) -> str:
    """Render a block back to markdown text (round-trip)."""
    if isinstance(block, GeneratedBlock):
        return (
            f"<!-- @generated:start {block.name} -->\n"
            f"{block.body}\n"
            f"<!-- @generated:end {block.name} -->"
        )
    if isinstance(block, UserBlock):
        return (
            f"<!-- @user:start {block.name} -->\n"
            f"{block.body}\n"
            f"<!-- @user:end {block.name} -->"
        )
    if isinstance(block, PlainText):
        return block.body
    raise TypeError(f"Unknown block type: {type(block)}")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_sentinels.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/sentinels.py tests/architect/test_sentinels.py
git commit -m "feat(architect): @generated/@user sentinel block parser"
```

---

### Task 15: Refresh decision logic

**Files:**
- Create: `scripts/architect/refresh.py`
- Create: `tests/architect/test_refresh.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/architect/test_refresh.py
from pathlib import Path

import pytest

from scripts.architect.refresh import RefreshAction, decide_module_refresh


def test_new_module_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "newmod", "paths": ["src/newmod/"]},
        lockfile_modules={},
        old_commit=None,
        new_commit="abc",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.GENERATE


def test_path_change_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth-new/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="def",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.REGENERATE


def test_force_always_regenerates(single_lang_python: Path):
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="abc",
        repo_root=single_lang_python,
        force=True,
    )
    assert action == RefreshAction.REGENERATE


def test_unchanged_module_skips(single_lang_python: Path):
    # Same commit, same paths, no force: skip.
    action = decide_module_refresh(
        module={"slug": "auth", "paths": ["src/auth/"]},
        lockfile_modules={"auth": {"paths": ["src/auth/"]}},
        old_commit="abc",
        new_commit="abc",
        repo_root=single_lang_python,
        force=False,
    )
    assert action == RefreshAction.SKIP
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/architect/test_refresh.py -v`
Expected: 4 fail with ImportError.

- [ ] **Step 3: Implement refresh logic**

```python
# scripts/architect/refresh.py
"""Per-module refresh decision.

Pure decision function. Does not write files. Caller (scan.py or
slash command body) acts on the returned RefreshAction.
"""

from __future__ import annotations

import subprocess
from enum import Enum
from pathlib import Path


class RefreshAction(str, Enum):
    GENERATE = "generate"        # new module, no prior note
    REGENERATE = "regenerate"    # existing module changed
    SKIP = "skip"                # unchanged, only frontmatter touched


def decide_module_refresh(
    module: dict,
    lockfile_modules: dict,
    old_commit: str | None,
    new_commit: str,
    repo_root: Path,
    force: bool = False,
) -> RefreshAction:
    """Decide what to do with this module in the current refresh run.

    Args:
        module: current manifest module dict (slug, paths, ...).
        lockfile_modules: mapping {slug: {"paths": [...], ...}} from lockfile.
        old_commit: commit hash of last successful scan (None on first run).
        new_commit: commit hash of current scan.
        repo_root: repo path for git diff.
        force: --force flag bypasses skip logic.
    """
    slug = module["slug"]
    if slug not in lockfile_modules:
        return RefreshAction.GENERATE

    if force:
        return RefreshAction.REGENERATE

    old_paths = sorted(lockfile_modules[slug].get("paths", []))
    new_paths = sorted(module.get("paths", []))
    if old_paths != new_paths:
        return RefreshAction.REGENERATE

    if old_commit and new_commit and old_commit != new_commit:
        if _paths_changed_between_commits(repo_root, old_commit, new_commit, new_paths):
            return RefreshAction.REGENERATE

    return RefreshAction.SKIP


def _paths_changed_between_commits(
    repo_root: Path, old_commit: str, new_commit: str, paths: list[str]
) -> bool:
    """True iff git diff <old>..<new> -- <paths> reports any change."""
    cmd = ["git", "-C", str(repo_root), "diff", "--quiet", f"{old_commit}..{new_commit}", "--"] + paths
    result = subprocess.run(cmd, capture_output=True)
    # `git diff --quiet` exits 0 on no change, 1 on changes.
    return result.returncode == 1
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/architect/test_refresh.py -v`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/architect/refresh.py tests/architect/test_refresh.py
git commit -m "feat(architect): decide_module_refresh() three-state action decision"
```

---

## Phase G: Orchestration

### Task 16: Main scan orchestrator

**Files:**
- Create: `scripts/architect/scan.py`
- Create: `tests/architect/test_scan.py`

- [ ] **Step 1: Write failing test**

```python
# tests/architect/test_scan.py
from pathlib import Path

from scripts.architect.scan import run_phase_one, ScanResult


def test_phase_one_produces_manifest_and_report(single_lang_python: Path):
    result: ScanResult = run_phase_one(single_lang_python)
    assert result.manifest.version == 1
    assert len(result.manifest.modules) >= 3  # auth, db, api
    assert result.manifest.last_scan["commit"]  # has commit hash
    assert "files" in result.scan_report
    assert "languages" in result.scan_report
    assert "entry_points" in result.scan_report
    assert "external_deps" in result.scan_report


def test_phase_one_deterministic(single_lang_python: Path):
    r1 = run_phase_one(single_lang_python)
    r2 = run_phase_one(single_lang_python)
    # Same commit + same scanner version -> same manifest.
    assert r1.manifest.last_scan["commit"] == r2.manifest.last_scan["commit"]
    assert [m["slug"] for m in r1.manifest.modules] == [m["slug"] for m in r2.manifest.modules]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/architect/test_scan.py -v`
Expected: FAIL with ImportError.

- [ ] **Step 3: Implement orchestrator**

```python
# scripts/architect/scan.py
"""Phase 1 orchestrator: tie walker + repomix + entry_points + deps + proposal
into a single deterministic output.

This is the public surface called by scripts/architect_scan.py CLI.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from pathlib import Path

from scripts.architect.deps import detect_external_deps
from scripts.architect.entry_points import detect_entry_points
from scripts.architect.manifest import Manifest
from scripts.architect.proposal import propose_modules_with_heuristics
from scripts.architect.repomix import pack_repo_metadata
from scripts.architect.walker import git_metadata, language_stats, walk_repo

SCANNER_VERSION = "0.1.0"


@dataclass
class ScanResult:
    manifest: Manifest
    scan_report: dict


def run_phase_one(repo_root: Path) -> ScanResult:
    """Run Phase 1 end-to-end. No vault writes; returns in-memory result."""
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

    scan_report = {
        "files": files,
        "languages": languages,
        "entry_points": entry_points,
        "external_deps": external_deps,
        "pack_metadata": pack_meta,
        "git": git_meta,
        "scanner_version": SCANNER_VERSION,
    }

    return ScanResult(manifest=manifest, scan_report=scan_report)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/architect/test_scan.py -v`
Expected: 2 passed.

- [ ] **Step 5: Run full architect test suite**

Run: `uv run pytest tests/architect/ -v`
Expected: all green. ~30 tests passing.

- [ ] **Step 6: Commit**

```bash
git add scripts/architect/scan.py tests/architect/test_scan.py
git commit -m "feat(architect): run_phase_one() deterministic orchestrator"
```

---

### Task 17: CLI entry point

**Files:**
- Create: `scripts/architect_scan.py`

- [ ] **Step 1: Implement CLI**

```python
#!/usr/bin/env python3
"""CLI entry for /obsidian-architect Phase 1.

Usage:
    python scripts/architect_scan.py <repo-path> [--out <path>] [--dry-run]

Output:
    Writes _manifest.yml and scan-report.json to <out> (default: stdout as JSON).
    On --dry-run, prints to stdout without writing.

The slash command body (commands/obsidian-architect.md) invokes this
script and feeds the output into its own logic for Phase 2 + 3.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from scripts.architect.manifest import write_manifest
from scripts.architect.scan import run_phase_one


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 1 scan for /obsidian-architect")
    parser.add_argument("repo_path", help="Path to the git repo to scan")
    parser.add_argument("--out", help="Directory to write _manifest.yml and scan-report.json", default=None)
    parser.add_argument("--dry-run", action="store_true", help="Print to stdout, do not write files")
    args = parser.parse_args(argv)

    repo = Path(args.repo_path).resolve()
    if not repo.is_dir():
        print(f"error: {repo} is not a directory", file=sys.stderr)
        return 2
    if not (repo / ".git").exists():
        print(f"error: {repo} is not a git repo", file=sys.stderr)
        return 2

    result = run_phase_one(repo)

    payload = {
        "manifest": asdict(result.manifest),
        "scan_report": result.scan_report,
    }

    if args.dry_run or args.out is None:
        json.dump(payload, sys.stdout, indent=2, default=str)
        print()
        return 0

    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    write_manifest(result.manifest, out_dir / "_manifest.yml")
    (out_dir / "scan-report.json").write_text(json.dumps(result.scan_report, indent=2, default=str))
    print(f"wrote {out_dir / '_manifest.yml'}")
    print(f"wrote {out_dir / 'scan-report.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Verify the CLI works**

Run from the host repo:
```bash
uv run python scripts/architect_scan.py tests/architect/fixtures/single-lang-python --dry-run | head -50
```
Expected: valid JSON output starting with `{"manifest": {...`.

Run again with `--out`:
```bash
mkdir -p /tmp/architect-out
uv run python scripts/architect_scan.py tests/architect/fixtures/single-lang-python --out /tmp/architect-out
cat /tmp/architect-out/_manifest.yml
```
Expected: a `_manifest.yml` with the fixture's three modules (auth, db, api) plus `tests` excluded.

- [ ] **Step 3: Commit**

```bash
git add scripts/architect_scan.py
git commit -m "feat(architect): scripts/architect_scan.py CLI entry point"
```

---

## Phase H: Slash command body

### Task 18: `commands/obsidian-architect.md`

**Files:**
- Create: `commands/obsidian-architect.md`

- [ ] **Step 1: Write the slash command body**

```markdown
---
description: Scan a codebase and generate architecture overview plus module notes into the project hub
category: vault
triggers_en: ["architect", "architecture doc", "scan repo", "document architecture", "codebase overview"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-architect $ARGUMENTS`:

The argument is `<repo-path>` (local path or github URL). Optional flags:
`--project=<P>` (force project hub binding), `--refresh` (explicit refresh),
`--dry-run` (Phase 1 only, no vault writes), `--force` (ignore "no changes" gate).

If `<repo-path>` is omitted and `pwd` is inside a git repo, default to `.`.
Otherwise ASK the user.

## Project routing

Resolve the target project hub in this order:

1. `--project=<P>` flag.
2. Search the vault for a project hub whose `local-path` frontmatter (resolved
   to an absolute path) equals the absolute path of `<repo-path>`. Exactly one
   match: use it.
3. Zero matches: create a new project hub. Follow the same conventions as
   `/obsidian-project`: sub-folder layout, hub frontmatter schema with `date`,
   `tags: [project]`, `status: active`, `local-path`, the
   `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/`
   skeleton, and a `board.md`. Project name defaults to the repo folder basename.
   ASK the user before creating so typos can be corrected.
4. Multiple matches: abort, list candidates, ask user to pass `--project=<P>`.

## Phase 1: Deterministic scan

Run:

```bash
uv run python scripts/architect_scan.py <repo-path> --out /tmp/architect-<hash>/
```

This produces `/tmp/architect-<hash>/_manifest.yml` and `scan-report.json`.

If `--dry-run`, print the manifest to the user and stop. No vault writes.

## Phase 2: Manifest review

Read `_manifest.yml` from the temp output. If
`Projects/<P>/Architecture/_manifest.yml` already exists in the vault:
diff via `scripts/architect/manifest_diff.py` and show added / removed /
renamed modules to the user. Otherwise show the full proposal.

ASK the user to confirm or edit. They can:

- Approve as proposed.
- Provide an edited YAML (paste it back inline).
- Reject and abort.

On approve: write `Projects/<P>/Architecture/_manifest.yml` to the vault.

## Phase 3: Per-module synthesis

For each module in the approved manifest where `excluded: false`:

1. Read the lockfile (`Projects/<P>/Architecture/_manifest.lock.json` if it exists)
   and call `decide_module_refresh()` from `scripts/architect/refresh.py` to
   choose generate / regenerate / skip.

2. For generate or regenerate, run repomix to pack the module:

   ```bash
   repomix --include "<module-paths>" --style xml --compress
   ```

   If the packed output exceeds 80,000 tokens as reported by repomix,
   re-pack with `--top-files-len 5` plus include only file headers
   (docstrings or leading comment block) for the rest. Set
   `scan-truncated: true` in the module note frontmatter.

3. Write `Projects/<P>/Architecture/modules/<slug>.md` following the schema
   in `references/ai-first-rules.md` (type: architecture-module).
   Body sections must be wrapped in sentinels:
   - `## What it does` -> `<!-- @generated:start what-it-does -->` block.
     If manifest has `description: <text>`, insert that text verbatim into
     this block (LLM does not regenerate).
   - `## How it works` -> generated block
   - `## Key files` -> generated block
   - `## Depends on` -> generated block (wikilinks to other module notes)
   - `## Consumed by` -> generated block (inverse)
   - `## Recent activity` -> generated block (last 5 git commits via
     `git log -5 --oneline -- <paths>`)
   - `## Related` -> generated block

   For the existing-note case (regenerate), first parse the existing file with
   `scripts/architect/sentinels.parse_blocks()`. Replace `@generated` block
   bodies; preserve `@user` blocks verbatim; for content outside any sentinel,
   compare against lockfile `note_blocks` hash and preserve if user-edited
   (emit a warning).

4. Update the lockfile's `note_blocks` entry for this note with hashes of the
   newly written generated blocks.

After every non-excluded module is processed: regenerate `overview.md`.

## Overview synthesis

`Projects/<P>/Architecture/overview.md`:

- Read every module note's frontmatter plus its `## What it does` block.
- Read the full file tree, entry points, external deps from
  `/tmp/architect-<hash>/scan-report.json`.
- Write the overview with sections in this order: `## For future Claude`,
  `## Purpose`, `## Layer map` (one Mermaid `graph TD` diagram, or
  `flowchart LR` if more than 8 top-level nodes), `## Modules` (bullet list
  with wikilinks), `## Entry points`, `## External dependencies` (with
  recency markers `(as of YYYY-MM, source-url)`), `## Key abstractions`,
  `## Related`.

All LLM-written sections wrapped in `@generated` sentinels with appropriate names.

## Data flow note (optional)

If the scan report identifies at least one entry point with a clear
input -> output chain (a chain reachable from the entry point through
multiple modules), generate `Projects/<P>/Architecture/data-flow.md`
with a Mermaid sequence diagram plus brief walkthrough. Skip if no such
chain is detectable - never write speculative data-flow diagrams.

## Hub note update

Append or replace the `## Architecture` section in `Projects/<P>/<P>.md`:

```markdown
## Architecture

- Overview: [[Architecture/overview]] (last scanned YYYY-MM-DD @ `<commit>`)
- Modules: N active, M deprecated
- Refresh: `/obsidian-architect <repo-path> --refresh`
```

Idempotent: section exists -> replace in place; otherwise append.

## Daily and operation log

- If `Logs/` exists: append `**HH:MM** - architect | <P> - N modules (M new, K updated, L deprecated)` to `Logs/YYYY-MM-DD.md`.
- Otherwise append `## [YYYY-MM-DD] architect | <P> - N modules ...` to `log.md`.
- Append to today's daily note `## Activity` section: `- /obsidian-architect: scanned [[<P>]] @ commit <commit>`.

## Errors and edge cases

- Repo path missing / not a git repo: abort with clear error. No vault writes.
- `repomix` not installed: the Python wrapper falls back automatically. Inform the user that runs are slower.
- Vault has no `_CLAUDE.md`: abort, suggest `/obsidian-init`.
- Multiple project hubs match the same `local-path`: abort, list candidates, ask user to disambiguate with `--project=<P>`.
- Dirty working tree: warn, do not block. The manifest records `dirty: true`
  and the commit field is tagged `+dirty`.
- Working tree dirty during refresh: per-module diff uses committed states only,
  so uncommitted module changes do not trigger re-synthesis. User can pass
  `--force` to override.
- A single module's synthesis fails: write the note with `status: scan-failed`
  in frontmatter plus the error message, continue with other modules.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` - `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval - not human reading.
```

- [ ] **Step 2: Verify build picks up the new command**

Run: `bash scripts/build.sh --platform claude-code`
Expected: `dist/claude-code/commands/obsidian-architect.md` exists.

Run: `bash scripts/build.sh --platform codex-cli` then `grep -l obsidian-architect dist/codex-cli/`
Expected: the command is listed in the dispatcher and body copied to `.codex/commands/`.

- [ ] **Step 3: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "feat(architect): /obsidian-architect slash command body"
```

---

## Phase I: Documentation

### Task 19: Update `references/ai-first-rules.md`

**Files:**
- Modify: `references/ai-first-rules.md`

- [ ] **Step 1: Find where existing `type:` values are documented**

Run: `grep -n "^### type:" references/ai-first-rules.md || grep -n "^## " references/ai-first-rules.md`
Expected: a list of section headers. Identify where to add the new types.

- [ ] **Step 2: Add the three new type values**

In the appropriate section (next to existing `type:` documentation), add:

```markdown
### `type: architecture-overview`

Generated by `/obsidian-architect`. Lives at `Projects/<P>/Architecture/overview.md`.

Required frontmatter:
- `type: architecture-overview`
- `date`, `project` (wikilink), `repo`, `local-path`, `commit`, `last-scanned`
- `scanner-version`, `primary-language`, `tags: [architecture, codebase-doc]`
- `ai-first: true`, `status: current | deprecated | scan-failed`

Body sections (in order): `## For future Claude`, `## Purpose`, `## Layer map`
(Mermaid), `## Modules` (wikilinks), `## Entry points`, `## External
dependencies`, `## Key abstractions`, `## Related`.

### `type: architecture-module`

Generated by `/obsidian-architect`. Lives at `Projects/<P>/Architecture/modules/<slug>.md`.

Required frontmatter:
- `type: architecture-module`
- `date`, `project` (wikilink), `repo`, `module-slug`, `display-name`, `role`
- `paths` (list), `last-scanned`, `commit`, `file-count`, `tokens`
- `primary-language`, `scan-truncated`, `tags: [architecture, module]`
- `ai-first: true`, `status: current | deprecated | scan-failed`

Body sections (in order): `## For future Claude`, `## What it does`,
`## How it works`, `## Key files`, `## Depends on`, `## Consumed by`,
`## Recent activity`, `## Related`. Every LLM-written section is wrapped
in `<!-- @generated:start <name> -->` ... `<!-- @generated:end <name> -->`
sentinels. User additions go in `<!-- @user:start <name> -->` ...
`<!-- @user:end <name> -->`.

### `type: architecture-data-flow`

Generated optionally by `/obsidian-architect` when the scan identifies
a clear input -> output chain. Lives at `Projects/<P>/Architecture/data-flow.md`.
Same frontmatter shape as `architecture-overview` but with
`type: architecture-data-flow`. Body holds one or two Mermaid sequence
diagrams plus brief walkthrough.
```

- [ ] **Step 3: Commit**

```bash
git add references/ai-first-rules.md
git commit -m "docs(refs): register architecture-overview/module/data-flow types"
```

---

### Task 20: Update SKILL.md, README.md, CHANGELOG.md

**Files:**
- Modify: `SKILL.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md Layer 1 list**

Find the Layer 1 section in `SKILL.md`. The current list documents 14 vault commands (per `architecture.md`). Add `/obsidian-architect` as command #15 with a one-paragraph description matching the style of the others:

```markdown
15. **/obsidian-architect [repo-path]** - Codebase architecture documentation
    - INPUT: repo path (or github URL) and optional `--project=<P>` flag
    - PROCESS: Phase 1 Python scanner (file tree, language stats, entry points,
      dep extraction, module proposal heuristics) -> Phase 2 user manifest review
      -> Phase 3 LLM synthesis per module + overview using `repomix` for packing
    - OUTPUT: `Projects/<P>/Architecture/{_manifest.yml, overview.md, modules/<slug>.md, data-flow.md}`
    - PROPAGATION: Updates project hub's `## Architecture` section + daily note + operation log
```

Update the Layer 1 count from "14 commands" to "15 commands" wherever it appears in SKILL.md.

- [ ] **Step 2: Update README.md commands table**

Find the commands table in `README.md`. Add a row:

```markdown
| `/obsidian-architect <repo>` | Vault | Scan a codebase and generate architecture overview + module notes into the project hub |
```

If the README has a count anywhere (e.g. "32 commands"), bump it to 33.

- [ ] **Step 3: Update CHANGELOG.md**

Add under `## [Unreleased]`:

```markdown
### Added
- `/obsidian-architect <repo-path>` slash command: scans a codebase and generates
  an architecture overview plus per-module notes into the project hub at
  `Projects/<P>/Architecture/`. Diff-aware refresh preserves user edits via
  `@generated`/`@user` sentinels and a lockfile. Module identity is pinned via
  a user-editable `_manifest.yml`. Supports local repos and remote GitHub URLs
  (via `repomix --remote`), plus `--project=<P>` for multi-repo projects.
- `scripts/architect/` Python package: deterministic Phase 1 scanner (file tree
  walker, language stats, entry-point detection, dep extraction, module proposal
  heuristics, manifest read/write, lockfile, sentinel parser, refresh decision).
- `references/ai-first-rules.md`: documented three new `type:` values:
  `architecture-overview`, `architecture-module`, `architecture-data-flow`.

### Dependencies
- Added `pyyaml>=6.0.1` (manifest serialization) and `pathspec>=0.12.1`
  (`.gitignore` matching) to runtime deps.
- Optional: `repomix` (npm package) for repo packing. Python fallback exists
  but is about 3x slower.
```

- [ ] **Step 4: Verify the build still works**

Run: `bash scripts/build.sh`
Expected: every platform's `dist/` rebuilds cleanly. Inspect `dist/codex-cli/AGENTS.md` and confirm the routing table now includes `obsidian-architect`.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md README.md CHANGELOG.md
git commit -m "docs: register /obsidian-architect in SKILL.md / README.md / CHANGELOG"
```

---

## Phase J: Verification

### Task 21: Manual verification against this repo

**Files:**
- None (manual run)

- [ ] **Step 1: Run the command against this repo**

Restart Claude Code so the new command is picked up (per CLAUDE.md testing instructions).

In a Claude Code session pointed at this repo, run:
```
/obsidian-architect .
```

Expected interactive flow:
1. Command finds (or creates) a project hub for this repo.
2. Phase 1 produces a manifest proposal. Modules visible: `commands`, `adapters`, `scripts`, `references`, `hooks`, `docs`, `tests`. `tests` and `docs` excluded.
3. User reviews and approves the manifest.
4. Phase 3 generates `overview.md` plus a module note per non-excluded module.

Compare the generated `overview.md` to the hand-written `architecture.md` at the repo root. Note any major hallucinations or omissions in a `verification-log.md` (not committed).

- [ ] **Step 2: Verify sentinel preservation**

Inside one of the generated module notes (e.g. `modules/commands.md`):
1. Edit one paragraph inside a `<!-- @generated:start ... -->` block. Re-run `/obsidian-architect . --refresh`.
2. Confirm the paragraph was regenerated (sentinels working).
3. Add a `## Notes` section wrapped in `<!-- @user:start notes -->` ... `<!-- @user:end notes -->`. Re-run `--refresh`.
4. Confirm the `## Notes` section survived.
5. Edit a paragraph **outside** any sentinel. Re-run `--refresh`.
6. Confirm the paragraph was preserved with a warning.

- [ ] **Step 3: Verify manifest pinning**

1. Edit `_manifest.yml`: change `modules[].display_name` for one module from the auto-proposed value to a custom string. Add a `description:` paragraph to another module.
2. Re-run `/obsidian-architect . --refresh`.
3. Confirm the manifest's `display_name` and `description` were preserved (not reverted to LLM proposals).
4. Confirm the module note that has a `description:` set in manifest uses that text verbatim in its "What it does" section.

- [ ] **Step 4: Verify dry-run**

Run:
```bash
uv run python scripts/architect_scan.py . --dry-run | python -c "import sys, json; data=json.load(sys.stdin); print(len(data['manifest']['modules']), 'modules')"
```

Expected: a sensible module count (around 5-8). No vault writes happened (check `git status` on the vault is unchanged).

- [ ] **Step 5: Run the full test suite one more time**

Run: `uv run pytest tests/architect/ -v`
Expected: all green.

- [ ] **Step 6: Commit verification log if any issues found**

If verification surfaced bugs, fix them in dedicated commits (not in this task). If everything checked out, this task ends with no commit. Move to the final commit step.

- [ ] **Step 7: Final commit and push**

```bash
git status
git log --oneline -25
```

Expected: a clean working tree with ~21 commits on the feature work. Per CLAUDE.md the maintainer may push directly to `main`:

```bash
git push origin main
```

Or open a PR if a review is wanted.

---

## Self-review checklist

Run through this once after the plan is complete:

1. **Spec coverage:** Every section of the spec maps to at least one task:
   - Section 5 (command surface) -> Task 18
   - Section 6 (vault layout) -> Task 18 (the slash command writes the layout)
   - Section 7.1 default proposal + skip set -> Task 9
   - Section 7.1 monorepo + flat-fallback -> Task 10
   - Section 7.1 merge + split heuristics -> Task 10b
   - Section 7 (rest of pipeline) -> Tasks 4-8, 11-17
   - Section 8 (manifest schema) -> Tasks 11-13
   - Section 9 (note schemas) -> Task 18 (slash command) + Task 19 (ai-first-rules)
   - Section 10 (hub integration) -> Task 18
   - Section 11 (refresh) -> Tasks 13, 15, 18
   - Section 12 (edge cases) -> Tasks 16, 18
   - Section 13 (adapter compat) -> Task 18 (generic tool wording)
   - Section 14 (testing) -> Tasks 2, 3, 4-17 (unit tests), Task 21 (manual)
   - Section 15 (docs updates) -> Tasks 19, 20

2. **Placeholder scan:** every code block contains actual code. No "TBD" or "similar to above".

3. **Type consistency:** `Manifest`, `Lockfile`, `ScanResult`, `RefreshAction`, `ModuleDiff` names match across files. `GeneratedBlock`/`UserBlock`/`PlainText` consistent. `walk_repo`, `language_stats`, `git_metadata`, `_approx_tokens`, `EXT_TO_LANG` import paths from `scripts.architect.walker` consistent. `propose_modules_with_heuristics` signature consistent between proposal.py and scan.py.

4. **Frequent commits:** every task ends with a commit. 22 commits total (21 numbered + Task 10b).

5. **TDD:** every task with code starts with the failing test step.

---

## Execution log

Captured 2026-05-26 after the plan ran end-to-end via `/run-plan` (codex exec)
followed by an interactive Task 21. This log records what actually happened vs
what the plan said, so future Claude can reconcile the two without surprise.

### Codex run (PID 83920, ~25 min, high reasoning)

Status: **DONE_WITH_CONCERNS**. All 22 numbered tasks plus Task 10b produced
commits on `main` (start ref `6a9cac0`, end ref `c4d3762`). Tests: 42 architect
+ 81 total at exit, all green. Build all four adapter platforms clean. Dry-run
against the host repo produced 11 sensible module candidates.

Three reasonable deviations from the plan, all noted by codex:

1. **Task 2 nested git fixture.** The plan said "git automatically filters
   nested `.git/` directories" when committing a fixture repo to the host repo.
   On this machine that turned the fixture into a gitlink (submodule pointer)
   instead of plain files. Codex landed a corrective commit (`1d96d10`) that
   re-added the fixture files as regular blobs. Plan still works as a recipe,
   but the "filtered automatically" line should be amended to: "remove the
   fixture's inner `.git/` before `git add`, or use `git add --all` from the
   fixture root after committing inside it."

2. **Task 10b merge heuristic guard.** The plan's merge heuristic ("sibling
   folders sharing a primary language and each below 2000 tokens get merged")
   would, applied to the `single-lang-python` fixture, collapse `auth/`, `db/`,
   `api/` into a single module — contradicting the Task 9 tests that assert
   each appears separately. Codex added a `_merge_family()` slug-prefix guard
   so two modules only merge when their slug families match
   (`re.split(r"[-_]", slug, maxsplit=1)[0]`). This is strictly more
   conservative than the plan and is the correct call.

3. **CLI `sys.path` bootstrap.** `scripts/architect_scan.py` needed an
   explicit `sys.path` insertion at the top so `python scripts/architect_scan.py
   ...` (no `-m` wrapper) can import `scripts.architect`. Plan didn't include
   it. Codex added it in commit `a6c0e9d`.

### Post-codex fix (this conversation)

Running the command against a real Node + Python repo (`langlive-line-oa`)
surfaced a real bug in `proposal.SKIP_AS_MODULE`: `node_modules/`, `logs/`,
`reports/`, `coverage/`, `vendor/` and similar leaked through as active
modules. The walker correctly skipped their files but the top-level folders
still became module entries.

Fixed in commit `fa36444`. Regression test
`test_dependency_and_runtime_dirs_are_excluded` added. Plan's Task 9 spec for
`SKIP_AS_MODULE` is now superseded by the longer list in `proposal.py`.

### Task 21 manual verification (interactive, this conversation)

Executed against `langlive-line-oa` (the only existing project hub in the
target vault). Real notes written to
`/Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/Architecture/`:
`_manifest.yml`, `_manifest.lock.json`, `scan-report.json`, `overview.md`,
plus five module notes (backend, frontend, modules, services, scripts). Hub
note updated with `## Architecture` section. New
`/Users/leric/Documents/SecondBrain/Logs/2026-05-26.md` created with the
operation log line.

Verification results (all passing):

- **Sentinel preservation (Step 2):** 3/3. Edited the `what-it-does`
  `@generated` body in `backend.md` → hash mismatch detected, refresh would
  overwrite. Added a `<!-- @user:start notes -->` block → would be preserved
  forever. Edited plain-text content outside any sentinel ("For future Claude"
  preamble) → user-edit detected, refresh would preserve and emit a warning.
- **Manifest pinning (Step 3):** 4/4. Pinned `repo.primary_language: python`,
  pinned `modules.backend.display_name`, pinned `modules.frontend.role:
  surface`, added a user `description` to backend. Re-ran scanner; lockfile
  hash compare correctly classified each: three preserved as user-edited, one
  unchanged-by-user field correctly identified as LLM-territory.
- **Dry-run (Step 4):** `--dry-run` printed 172 KB of JSON to stdout, zero
  vault writes. Verified by file-newer-than-snapshot check.
- **Full test suite (Step 5):** 82 passed (43 architect + 39 research).

### Known scanner v0.1.0 limitations (deferred to v1.1)

Documented in `CHANGELOG.md` under "Known limitations". Three real-repo issues
that aren't bugs but degrade scan quality on certain repo shapes:

1. **Token-weighted `primary_language`** ranks `markdown` / `html` above the
   real code language when a repo is docs-heavy or template-heavy. Workaround:
   pin in manifest.
2. **External-dependency detector is root-only.** Nested deps files
   (`backend/requirements.txt`, `frontend/package.json` in two-image monorepos)
   are missed.
3. **Entry-point detector matches the exact filename `Dockerfile`.**
   `Dockerfile.backend` / `Dockerfile.frontend` and `python -m <pkg>` style
   entry points are not detected.

Each is one small, focused change. Worth bundling into a v1.1 patch when there
is appetite.

### Polish committed in this conversation

- `fa36444` — fix(architect): mark deps/runtime/build dirs as excluded modules
- (this commit) — fix(architect): switch pathspec `gitwildmatch` →
  `gitignore` matcher to silence the 420-warning deprecation flood; CHANGELOG
  updated with Fixed + Known limitations sections; this execution log appended.
