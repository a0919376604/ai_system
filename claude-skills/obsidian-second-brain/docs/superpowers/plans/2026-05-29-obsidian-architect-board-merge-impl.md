# `/obsidian-architect` + Board Refresh Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `commands/obsidian-board.md` `--refresh` mode into a shared `scripts/board/refresh.py:refresh_board()` helper, then wire `/obsidian-architect` Phase 7 to call it automatically (opt-out via `--no-board-refresh`). Cron path stays unchanged externally.

**Architecture:** New `scripts/board/refresh.py` module with `RefreshResult` dataclass + `refresh_board(project_dir, signals=None, full=False)` function. When `signals=None`, the helper walks git + spec/plan files itself (cron path). When `signals` is provided (architect path), it reuses caller's already-collected `git_last_touch`, git-log, and spec/plan lists to avoid re-walking. Both `commands/obsidian-board.md --refresh` and `commands/obsidian-architect.md` Phase 7 import this helper. Bucket clustering uses keyword overlap against existing bucket H2 headings (deterministic — no LLM); unmatched items go to `## Misc / Untriaged`. Failure in architect Phase 7 is isolated; logs warning but doesn't fail architect.

**Tech Stack:** Python 3.10+, pytest, `subprocess` (git log), `pathlib`, regex frontmatter / sentinel parsing. No new external deps.

**Plan-level notes:**
- Run tests from repo root `/Users/leric/Desktop/code/obsidian-second-brain` with `uv run pytest tests/path/test.py -v`.
- Co-author line: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- `dist/` is gitignored — never `git add dist/`.
- Pytest COLLECTION ERROR at "verify it fails" steps is the expected RED state for TDD — proceed to impl.

---

## File structure (locked)

**New files:**
- `scripts/board/__init__.py` — empty package marker
- `scripts/board/refresh.py` — `RefreshResult` dataclass + `refresh_board()` + helpers
- `tests/board/__init__.py` — empty
- `tests/board/test_refresh.py` — 7 unit tests

**Modified files:**
- `commands/obsidian-board.md` — `--refresh` body replaced with `refresh_board()` call
- `commands/obsidian-architect.md` — new Phase 7 after "Daily and operation log" section + `--no-board-refresh` flag documentation
- `SKILL.md` — architect description gains board-refresh side effect note
- `CHANGELOG.md` — `## [Unreleased]` entry

**Untouched:**
- `scripts/cron/trigger-board-refresh.sh` — still calls `/obsidian-board --refresh`
- `scripts/cron/board-refresh-prompt.txt` — unchanged

---

## Phase A: Helper foundation

### Task 1: `RefreshResult` dataclass + `refresh_board()` skipped path

**Files:**
- Create: `scripts/board/__init__.py` (empty)
- Create: `scripts/board/refresh.py`
- Create: `tests/board/__init__.py` (empty)
- Create: `tests/board/test_refresh.py`

- [ ] **Step 1: Create empty package files**

```bash
mkdir -p /Users/leric/Desktop/code/obsidian-second-brain/scripts/board
mkdir -p /Users/leric/Desktop/code/obsidian-second-brain/tests/board
touch /Users/leric/Desktop/code/obsidian-second-brain/scripts/board/__init__.py
touch /Users/leric/Desktop/code/obsidian-second-brain/tests/board/__init__.py
```

- [ ] **Step 2: Write failing test**

Create `tests/board/test_refresh.py`:

```python
"""Tests for scripts.board.refresh.refresh_board."""
from __future__ import annotations

from pathlib import Path

from scripts.board.refresh import refresh_board, RefreshResult


def test_refresh_returns_skipped_when_no_board_md(tmp_path: Path):
    """When Projects/<P>/board.md doesn't exist → status='skipped'."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    # No board.md exists — only hub note.
    (proj_dir / "myproject.md").write_text(
        "---\nlocal-path: /tmp/myrepo\n---\n", encoding="utf-8"
    )

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert isinstance(result, RefreshResult)
    assert result.status == "skipped"
    assert "no board.md" in result.message.lower()
    assert result.project_slug == "myproject"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: COLLECTION ERROR `ModuleNotFoundError: No module named 'scripts.board.refresh'`.

- [ ] **Step 4: Implement skeleton**

Create `scripts/board/refresh.py`:

```python
"""Refresh Projects/<P>/board.md via deterministic git + spec/plan walk.

Shared helper for two callers:
- `/obsidian-board --refresh` (cron path) — passes signals=None; helper walks
  git log + spec/plan files itself.
- `/obsidian-architect` Phase 7 — passes signals dict with already-collected
  `git_last_touch`, git_log, spec/plan lists; helper reuses to avoid re-walking.

Bucket clustering is keyword-overlap match against existing bucket H2 headings
in the current board.md. Unmatched items go to `## Misc / Untriaged`.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class RefreshResult:
    status: str                       # 'ok' | 'skipped' | 'error'
    project_slug: str = ""
    board_path: Path | None = None
    done_count: int = 0
    in_flight_count: int = 0
    backlog_count: int = 0
    buckets: list[str] = field(default_factory=list)
    new_items: list[dict] = field(default_factory=list)
    last_refresh_before: str | None = None
    last_refresh_after: str = ""
    message: str = ""


def refresh_board(
    project_dir: Path,
    *,
    signals: dict | None = None,
    full: bool = False,
) -> RefreshResult:
    """Refresh board.md for the given project.

    See module docstring for the contract.
    """
    project_slug = project_dir.name
    board_path = project_dir / "board.md"
    if not board_path.is_file():
        return RefreshResult(
            status="skipped",
            project_slug=project_slug,
            board_path=board_path,
            message=f"no board.md in {project_slug} — run /obsidian-project to bootstrap",
        )

    # Full implementation lands in subsequent tasks. For now, return ok with
    # a stub message so the skipped path can be tested independently.
    return RefreshResult(
        status="ok",
        project_slug=project_slug,
        board_path=board_path,
        message="not yet implemented",
    )
```

- [ ] **Step 5: Run test to verify it passes**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 1 PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/board/__init__.py scripts/board/refresh.py tests/board/__init__.py tests/board/test_refresh.py
git commit -m "$(cat <<'EOF'
feat(board): refresh_board skeleton — package marker + RefreshResult + skipped path

New module scripts/board/refresh.py exposes refresh_board() + RefreshResult
dataclass. This commit lands:
- Package skeleton (scripts/board/, tests/board/)
- RefreshResult fields (status / project_slug / board_path / counts /
  buckets / new_items / last_refresh_before/after / message)
- Skipped-path: status='skipped' when Projects/<P>/board.md doesn't exist

Walks, classification, bucket clustering, and board.md write come in
subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B: Signals walk (git + spec/plan)

### Task 2: Walk git log + spec/plan files, parse last-refresh from board.md

**Files:**
- Modify: `scripts/board/refresh.py`
- Modify: `tests/board/test_refresh.py`

- [ ] **Step 1: Write failing test**

Append to `tests/board/test_refresh.py`:

```python
import subprocess
import os
import shutil


def _init_repo(repo: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=repo, check=True)


def _commit(repo: Path, path: str, content: str, message: str, date: str) -> None:
    p = repo / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    subprocess.run(["git", "add", path], cwd=repo, check=True)
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    subprocess.run(
        ["git", "commit", "-m", message, "--date", date],
        cwd=repo, check=True, capture_output=True, env=env,
    )


def test_refresh_walks_git_log_when_signals_none(tmp_path: Path):
    """signals=None → helper walks git log itself; populates new_items."""
    # Project skeleton.
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n"
        "## 待辦\n- placeholder\n",
        encoding="utf-8",
    )

    # Repo with one commit AFTER last-refresh.
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "add a", "2026-05-15T12:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    assert result.last_refresh_before == "2026-05-01T00:00:00"
    titles = [item.get("title", "") for item in result.new_items]
    assert any("add a" in t for t in titles), f"expected commit picked up; got {titles}"


def test_refresh_full_mode_ignores_last_refresh(tmp_path: Path):
    """full=True walks ALL git history regardless of last-refresh timestamp."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2030-01-01T00:00:00\n---\n",   # in the future
        encoding="utf-8",
    )

    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "old commit", "2026-01-01T00:00:00")

    # Without full=True the future timestamp would exclude everything.
    result = refresh_board(project_dir=proj_dir, signals=None, full=True)
    assert result.status == "ok"
    titles = [item.get("title", "") for item in result.new_items]
    assert any("old commit" in t for t in titles), (
        f"full mode should include pre-last-refresh commits; got {titles}"
    )
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 2 FAILs — helper currently returns stub with empty `new_items` and missing `last_refresh_before`.

- [ ] **Step 3: Implement signals-None walk**

Replace `scripts/board/refresh.py` content with:

```python
"""Refresh Projects/<P>/board.md via deterministic git + spec/plan walk."""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


_FRONTMATTER_LAST_REFRESH_RE = re.compile(
    r'^last-refresh:\s*"?(?P<ts>[^"\n]+)"?\s*$', re.MULTILINE
)
_FRONTMATTER_LOCAL_PATH_RE = re.compile(
    r'^local-path:\s*"?(?P<path>[^"\n]+)"?\s*$', re.MULTILINE
)


@dataclass
class RefreshResult:
    status: str
    project_slug: str = ""
    board_path: Path | None = None
    done_count: int = 0
    in_flight_count: int = 0
    backlog_count: int = 0
    buckets: list[str] = field(default_factory=list)
    new_items: list[dict] = field(default_factory=list)
    last_refresh_before: str | None = None
    last_refresh_after: str = ""
    message: str = ""


def refresh_board(
    project_dir: Path,
    *,
    signals: dict | None = None,
    full: bool = False,
) -> RefreshResult:
    project_slug = project_dir.name
    board_path = project_dir / "board.md"
    if not board_path.is_file():
        return RefreshResult(
            status="skipped",
            project_slug=project_slug,
            board_path=board_path,
            message=f"no board.md in {project_slug} — run /obsidian-project to bootstrap",
        )

    board_text = board_path.read_text(encoding="utf-8")
    last_refresh_before = _read_last_refresh(board_text)
    local_path = _resolve_local_path(project_dir, project_slug)

    if signals is None:
        since = None if full else last_refresh_before
        new_items = _walk_signals(local_path, since=since) if local_path else []
    else:
        new_items = _new_items_from_signals(signals)

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

    return RefreshResult(
        status="ok",
        project_slug=project_slug,
        board_path=board_path,
        new_items=new_items,
        last_refresh_before=last_refresh_before,
        last_refresh_after=now_iso,
        message=f"walked {len(new_items)} items",
    )


def _read_last_refresh(text: str) -> str | None:
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    fm = m.group(1)
    sm = _FRONTMATTER_LAST_REFRESH_RE.search(fm)
    return sm.group("ts").strip() if sm else None


def _resolve_local_path(project_dir: Path, project_slug: str) -> Path | None:
    hub_path = project_dir / f"{project_slug}.md"
    if not hub_path.is_file():
        return None
    text = hub_path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    fm = m.group(1)
    sm = _FRONTMATTER_LOCAL_PATH_RE.search(fm)
    if not sm:
        return None
    return Path(sm.group("path").strip())


def _walk_signals(local_path: Path, *, since: str | None) -> list[dict]:
    """Walk git log + spec/plan files. Each entry: {title, kind, when, source}."""
    if not local_path or not local_path.exists():
        return []
    items: list[dict] = []
    items.extend(_git_log_items(local_path, since=since))
    items.extend(_spec_plan_items(local_path, since=since))
    return items


def _git_log_items(repo: Path, *, since: str | None) -> list[dict]:
    cmd = ["git", "log", "--all", "--pretty=format:%H%x09%ad%x09%s%x09%D",
           "--date=iso-strict"]
    if since:
        cmd.append(f"--since={since}")
    try:
        proc = subprocess.run(
            cmd, cwd=str(repo), capture_output=True, text=True, check=False,
        )
    except (FileNotFoundError, OSError):
        return []
    if proc.returncode != 0:
        return []
    items: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        sha, when, subject = parts[0], parts[1], parts[2]
        refs = parts[3] if len(parts) > 3 else ""
        items.append({
            "title": subject,
            "kind": "commit",
            "when": when,
            "source": f"commit {sha[:8]}",
            "refs": refs,
        })
    return items


def _spec_plan_items(repo: Path, *, since: str | None) -> list[dict]:
    """List spec/plan files under docs/superpowers/. Filter by mtime if since set."""
    docs = repo / "docs" / "superpowers"
    if not docs.is_dir():
        return []
    items: list[dict] = []
    cutoff = _parse_iso_ts(since) if since else None
    for sub in ("specs", "plans"):
        d = docs / sub
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.md")):
            mtime = f.stat().st_mtime
            if cutoff is not None and mtime < cutoff:
                continue
            items.append({
                "title": f.stem,
                "kind": sub.rstrip("s"),  # "spec" or "plan"
                "when": datetime.fromtimestamp(mtime).isoformat(),
                "source": f.relative_to(repo).as_posix(),
            })
    return items


def _parse_iso_ts(ts: str) -> float | None:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def _new_items_from_signals(signals: dict) -> list[dict]:
    """Reuse caller-provided signals (architect Phase 7 path). Filled in Task 7."""
    return []
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 3 PASS (1 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/board/refresh.py tests/board/test_refresh.py
git commit -m "$(cat <<'EOF'
feat(board): refresh_board walks git log + spec/plan files when signals=None

Implements the cron-path walk:
- Reads `last-refresh` from board.md frontmatter (or None on first run).
- Reads `local-path` from Projects/<P>/<P>.md hub frontmatter.
- Walks `git log --since=<last-refresh>` (or full when full=True / missing).
- Walks docs/superpowers/{specs,plans}/*.md, filtered by mtime.
- Returns RefreshResult.new_items = [{title, kind, when, source, refs}, ...].

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C: Classification + bucket clustering

### Task 3: Classify items into Done / In-progress / Backlog + cluster into buckets

**Files:**
- Modify: `scripts/board/refresh.py` (extend `refresh_board` to compute counts + buckets)
- Modify: `tests/board/test_refresh.py`

- [ ] **Step 1: Write failing test**

Append:

```python
def test_refresh_classifies_commit_on_main_as_done(tmp_path: Path):
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n## 待辦\n- old item\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "feat: shipped feature A", "2026-05-15T12:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    assert result.done_count >= 1, f"commit on main should be Done; got {result.done_count}"


def test_refresh_classifies_brainstorm_branch_as_in_progress(tmp_path: Path):
    """Commits visible only on brainstorm/* branches are In Progress."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n", encoding="utf-8"
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "initial", "2026-05-10T00:00:00")
    # Make a brainstorm branch with a NEW commit.
    subprocess.run(["git", "checkout", "-b", "brainstorm/foo"], cwd=repo,
                   check=True, capture_output=True)
    _commit(repo, "b.py", "y=2\n", "wip: trying foo", "2026-05-16T00:00:00")
    subprocess.run(["git", "checkout", "main"], cwd=repo,
                   check=True, capture_output=True)

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.in_flight_count >= 1, (
        f"brainstorm/* commit should be In Progress; got {result.in_flight_count}"
    )


def test_refresh_clusters_into_existing_buckets_by_keyword(tmp_path: Path):
    """Items whose title contains a keyword from existing H2 bucket → that bucket.
    Unmatched → ## Misc / Untriaged."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    # Existing buckets: "## Auth" and "## Billing".
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n\n"
        "## Auth\n- existing auth item\n\n"
        "## Billing\n- existing billing item\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "auth.py", "x=1\n", "fix auth bug", "2026-05-15T00:00:00")
    _commit(repo, "billing.py", "x=2\n", "add billing feature", "2026-05-15T01:00:00")
    _commit(repo, "other.py", "x=3\n", "tweak something random", "2026-05-15T02:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert "Auth" in result.buckets, f"got {result.buckets}"
    assert "Billing" in result.buckets
    assert "Misc / Untriaged" in result.buckets
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 3 FAILs — current `refresh_board` doesn't classify or cluster.

- [ ] **Step 3: Implement classification + clustering**

In `scripts/board/refresh.py`, REPLACE the `refresh_board` function body's tail (after `new_items = ...`) AND add helpers. Concrete edit:

After the existing line `new_items = _new_items_from_signals(signals)`:

```python
    # Classify items into Done / In-progress / Backlog.
    done, in_flight, backlog = _classify_items(new_items)

    # Cluster into existing buckets (keyword overlap with H2 headings).
    existing_buckets = _existing_bucket_names(board_text)
    bucket_assignments = _cluster_items(
        done + in_flight + backlog, existing_buckets,
    )
    buckets = sorted(set(b for b in bucket_assignments.values()))
    # Always include Misc / Untriaged if any items fell there.
    if "Misc / Untriaged" not in buckets and any(
        v == "Misc / Untriaged" for v in bucket_assignments.values()
    ):
        buckets.append("Misc / Untriaged")
```

Update the `return` statement:

```python
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    return RefreshResult(
        status="ok",
        project_slug=project_slug,
        board_path=board_path,
        done_count=len(done),
        in_flight_count=len(in_flight),
        backlog_count=len(backlog),
        buckets=buckets,
        new_items=new_items,
        last_refresh_before=last_refresh_before,
        last_refresh_after=now_iso,
        message=f"walked {len(new_items)} items into {len(buckets)} bucket(s)",
    )
```

Add the helpers at the bottom of the module:

```python
_BRAINSTORM_REF_RE = re.compile(r"\brefs/(?:remotes/origin/)?(?:HEAD->\s*)?(?P<ref>\S+)")
_BUCKET_HEADING_RE = re.compile(r"^##\s+(?P<name>[^\n#].*?)\s*$", re.MULTILINE)


def _classify_items(items: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    """Return (done, in_flight, backlog) lists.

    Heuristic per spec:
    - Done: kind='commit' AND refs string contains 'main' (or master/trunk)
    - In Progress: kind='commit' AND refs string contains 'brainstorm/'
      (or kind='plan' — plans imply active work)
    - Backlog: kind='spec' with no matching commit/plan
    """
    done: list[dict] = []
    in_flight: list[dict] = []
    backlog: list[dict] = []
    for item in items:
        if item["kind"] == "commit":
            refs = item.get("refs", "")
            if "brainstorm/" in refs:
                in_flight.append(item)
            elif any(b in refs for b in ("main", "master", "trunk")) or refs == "":
                # Empty refs typically means a commit on the current branch (main).
                done.append(item)
            else:
                in_flight.append(item)
        elif item["kind"] == "plan":
            in_flight.append(item)
        elif item["kind"] == "spec":
            backlog.append(item)
        else:
            backlog.append(item)
    return done, in_flight, backlog


def _existing_bucket_names(board_text: str) -> list[str]:
    """Extract H2 bucket names from existing board.md, excluding synthesis sections."""
    synthesis_section_names = {
        "🔥 This Week", "待辦", "進行中", "已完成", "已完成 (本週)",
        "Patterns observed", "Bucket summary", "給未來 Claude",
    }
    buckets: list[str] = []
    for m in _BUCKET_HEADING_RE.finditer(board_text):
        name = m.group("name").strip()
        # Skip synthesis sections.
        if name in synthesis_section_names:
            continue
        # Skip emoji-prefixed synthesis variations.
        if any(name.endswith(s) for s in (" 本週", " (本週)")):
            continue
        buckets.append(name)
    return buckets


def _cluster_items(items: list[dict], existing_buckets: list[str]) -> dict[str, str]:
    """Assign each item to an existing bucket by keyword overlap; else Misc / Untriaged.

    Returns {item_title: bucket_name}.
    """
    assignments: dict[str, str] = {}
    bucket_keywords = {
        bucket: set(_tokenize_for_match(bucket)) for bucket in existing_buckets
    }
    for item in items:
        title_tokens = set(_tokenize_for_match(item["title"]))
        best_bucket = None
        best_overlap = 0
        for bucket, kws in bucket_keywords.items():
            overlap = len(title_tokens & kws)
            if overlap > best_overlap:
                best_overlap = overlap
                best_bucket = bucket
        assignments[item["title"]] = best_bucket or "Misc / Untriaged"
    return assignments


def _tokenize_for_match(text: str) -> list[str]:
    """Lower-case word tokens with length ≥ 3."""
    return [w for w in re.findall(r"[A-Za-z一-鿿]+", text.lower()) if len(w) >= 3]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 6 PASS (3 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/board/refresh.py tests/board/test_refresh.py
git commit -m "$(cat <<'EOF'
feat(board): refresh_board classifies items + clusters into existing buckets

Classification heuristic:
- commit on main / master / trunk (or no refs) → Done
- commit on brainstorm/* branch → In Progress
- spec file only → Backlog
- plan file → In Progress (implies active work)

Bucket clustering: keyword tokens (≥3 chars, Latin + CJK) overlap between
item title and existing H2 bucket headings. Best-overlap wins; no overlap
falls to `## Misc / Untriaged`. Synthesis sections (🔥 This Week / 待辦 /
進行中 / 已完成 / Patterns observed / Bucket summary) are excluded from
the bucket candidate list.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D: Signals reuse + board.md write

### Task 4: Signals-provided path (architect reuses git_last_touch + git_log)

**Files:**
- Modify: `scripts/board/refresh.py`
- Modify: `tests/board/test_refresh.py`

- [ ] **Step 1: Write failing test**

```python
def test_refresh_with_signals_reuses_caller_data(tmp_path: Path):
    """When signals={...} provided, helper uses items from there — skips git walks."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        "---\nlocal-path: /nonexistent/path\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\n---\n", encoding="utf-8"
    )

    # Architect passes pre-collected items.
    signals = {
        "git_commits": [
            {"title": "feat: pre-collected", "kind": "commit",
             "when": "2026-05-15T00:00:00", "source": "commit deadbeef",
             "refs": "HEAD -> main"},
        ],
        "spec_files": [],
        "plan_files": [],
    }
    result = refresh_board(project_dir=proj_dir, signals=signals, full=False)
    assert result.status == "ok"
    assert result.done_count == 1
    titles = [item["title"] for item in result.new_items]
    assert "feat: pre-collected" in titles
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/board/test_refresh.py::test_refresh_with_signals_reuses_caller_data -v`
Expected: FAIL — current `_new_items_from_signals` returns `[]`.

- [ ] **Step 3: Implement signals-provided path**

In `scripts/board/refresh.py`, REPLACE `_new_items_from_signals` with:

```python
def _new_items_from_signals(signals: dict) -> list[dict]:
    """Reuse caller-provided signals.

    signals shape:
        {
            "git_commits": [{"title", "kind", "when", "source", "refs"}, ...],
            "spec_files": [Path, ...],
            "plan_files": [Path, ...],
        }
    """
    items: list[dict] = []
    for commit in signals.get("git_commits", []):
        # Ensure all expected fields exist.
        items.append({
            "title": commit.get("title", ""),
            "kind": commit.get("kind", "commit"),
            "when": commit.get("when", ""),
            "source": commit.get("source", ""),
            "refs": commit.get("refs", ""),
        })
    for spec_path in signals.get("spec_files", []):
        p = Path(spec_path)
        items.append({
            "title": p.stem,
            "kind": "spec",
            "when": "",
            "source": str(p),
            "refs": "",
        })
    for plan_path in signals.get("plan_files", []):
        p = Path(plan_path)
        items.append({
            "title": p.stem,
            "kind": "plan",
            "when": "",
            "source": str(p),
            "refs": "",
        })
    return items
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 7 PASS (6 prior + 1 new).

- [ ] **Step 5: Commit**

```bash
git add scripts/board/refresh.py tests/board/test_refresh.py
git commit -m "$(cat <<'EOF'
feat(board): refresh_board signals-provided path — reuse caller data

When signals dict is passed, helper builds new_items from
signals["git_commits"] + signals["spec_files"] + signals["plan_files"]
instead of walking git/filesystem itself. Used by /obsidian-architect
Phase 7 to avoid re-walking what architect already collected.

Shape:
  signals = {
      "git_commits": [{title, kind, when, source, refs}, ...],
      "spec_files": [Path, ...],
      "plan_files": [Path, ...],
  }

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5: Write updated board.md (frontmatter `last-refresh` + bucket counts)

**Files:**
- Modify: `scripts/board/refresh.py`
- Modify: `tests/board/test_refresh.py`

- [ ] **Step 1: Write failing test**

```python
def test_refresh_writes_updated_last_refresh_to_frontmatter(tmp_path: Path):
    """After refresh, board.md frontmatter has updated last-refresh timestamp."""
    proj_dir = tmp_path / "Projects" / "myproject"
    proj_dir.mkdir(parents=True)
    (proj_dir / "myproject.md").write_text(
        f"---\nlocal-path: {tmp_path / 'repo'}\n---\n", encoding="utf-8"
    )
    (proj_dir / "board.md").write_text(
        "---\nlast-refresh: 2026-05-01T00:00:00\ntotal: 0\n---\n\n"
        "## 待辦\n- old\n",
        encoding="utf-8",
    )
    repo = tmp_path / "repo"
    repo.mkdir()
    _init_repo(repo)
    _commit(repo, "a.py", "x=1\n", "do thing", "2026-05-15T00:00:00")

    result = refresh_board(project_dir=proj_dir, signals=None, full=False)
    assert result.status == "ok"
    # Read board back; last-refresh should be NEWER than before.
    new_text = (proj_dir / "board.md").read_text(encoding="utf-8")
    new_ts = _FRONTMATTER_LAST_REFRESH_RE.search(new_text).group("ts").strip()
    assert new_ts > "2026-05-01T00:00:00", (
        f"new last-refresh should be later; got {new_ts}"
    )
    assert new_ts == result.last_refresh_after
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — current `refresh_board` doesn't write the file.

- [ ] **Step 3: Implement frontmatter update + write**

In `scripts/board/refresh.py`, modify `refresh_board` to write the file. Add this BEFORE the final `return`:

```python
    # Update frontmatter last-refresh and write back.
    new_board_text = _update_frontmatter_last_refresh(board_text, now_iso)
    # Best-effort total update (totals = done + in_flight + backlog).
    new_board_text = _update_frontmatter_totals(
        new_board_text,
        done=len(done),
        in_flight=len(in_flight),
        backlog=len(backlog),
    )
    board_path.write_text(new_board_text, encoding="utf-8")
```

Add helpers:

```python
def _update_frontmatter_last_refresh(text: str, new_ts: str) -> str:
    """Replace or add `last-refresh:` in the first frontmatter block."""
    m = re.match(r"^(---\n)(.*?)(\n---)", text, re.DOTALL)
    if not m:
        # No frontmatter — prepend.
        return f"---\nlast-refresh: {new_ts}\n---\n\n{text}"
    head, fm, tail = m.group(1), m.group(2), m.group(3)
    if _FRONTMATTER_LAST_REFRESH_RE.search(fm):
        new_fm = _FRONTMATTER_LAST_REFRESH_RE.sub(
            f"last-refresh: {new_ts}", fm, count=1,
        )
    else:
        new_fm = fm + f"\nlast-refresh: {new_ts}"
    return head + new_fm + tail + text[m.end():]


def _update_frontmatter_totals(
    text: str, *, done: int, in_flight: int, backlog: int,
) -> str:
    """Ensure frontmatter contains current totals (done / in-flight / backlog)."""
    m = re.match(r"^(---\n)(.*?)(\n---)", text, re.DOTALL)
    if not m:
        return text
    head, fm, tail = m.group(1), m.group(2), m.group(3)
    pairs = [("done", done), ("in-flight", in_flight), ("backlog", backlog)]
    new_fm = fm
    for key, value in pairs:
        pat = re.compile(rf"^{re.escape(key)}:\s*\d+\s*$", re.MULTILINE)
        if pat.search(new_fm):
            new_fm = pat.sub(f"{key}: {value}", new_fm)
        else:
            new_fm = new_fm + f"\n{key}: {value}"
    return head + new_fm + tail + text[m.end():]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/board/test_refresh.py -v`
Expected: 8 PASS.

- [ ] **Step 5: Run full suite to confirm no regression**

Run: `uv run pytest tests/ -q`
Expected: All PASS (419 prior + 8 new = 427).

- [ ] **Step 6: Commit**

```bash
git add scripts/board/refresh.py tests/board/test_refresh.py
git commit -m "$(cat <<'EOF'
feat(board): refresh_board updates frontmatter last-refresh + totals + writes

Final write step:
- Replaces or adds `last-refresh: <iso>` in board.md's first frontmatter
  block.
- Updates `done` / `in-flight` / `backlog` numeric keys (adds them if
  missing).
- Writes the new content back. Body sections preserved verbatim — bucket
  body regeneration is deliberately deferred (let the LLM command body
  handle topic-bucket rewriting; helper's job is signals + frontmatter
  bookkeeping).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E: Wire callers

### Task 6: `/obsidian-board --refresh` body uses `refresh_board()`

**Files:**
- Modify: `commands/obsidian-board.md` (replace Refresh mode body)

- [ ] **Step 1: Read current obsidian-board.md Refresh mode section**

```bash
sed -n '29,64p' /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-board.md
```

(Note the existing 9-step instructions.)

- [ ] **Step 2: Replace `### Refresh mode` body**

In `commands/obsidian-board.md`, find the `### Refresh mode (`--refresh` flag set)` section (~line 29-63). REPLACE its body with:

````markdown
### Refresh mode (`--refresh` flag set)

The deterministic refresh logic is implemented in `scripts/board/refresh.py:refresh_board()`. Invocation:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-board <repo> --refresh [--full]")
repo_token = tokens[0]
flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,
)
if resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state != "project":
    abort(resolution.message)

from scripts.board.refresh import refresh_board
result = refresh_board(
    project_dir=resolution.project_dir,
    signals=None,
    full=("--full" in flags),
)

if result.status == "skipped":
    print(result.message)
    return  # nothing to do
```

After helper returns:

1. Append activity log line to `Logs/YYYY-MM-DD.md ## Activity` (idempotent — only if today's log doesn't already have a matching `**HH:MM** - board | <P> refreshed` line for the same minute):
   ```
   **HH:MM** - board | <P> refreshed - <done> done, <in-flight> in-flight, <backlog> backlog across <N> buckets
   ```

2. Return a one-line summary to the caller (used by cron Discord notification):
   `board refreshed | <P> | <done>D <in-flight>P <backlog>B | <N> buckets`

3. The LLM (Claude executing this command body) is then responsible for regenerating the topic-bucket body sections in `board.md` based on `result.new_items` and `result.buckets`. The helper has already updated frontmatter `last-refresh` + totals; the LLM step is purely about prose-level reformatting of the bucket bodies (preserving the SYNTHESIZE rule for `## 🔥 This Week` / `## 待辦` / `## 進行中` / `## 已完成` if those sections don't exist yet).

If `--full` flag was passed, force full rebuild ignoring last-refresh. The helper handles this via its `full=True` parameter.
````

- [ ] **Step 3: Rebuild adapters to confirm parsing**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 4: Commit**

```bash
git add commands/obsidian-board.md
git commit -m "$(cat <<'EOF'
refactor(commands): /obsidian-board --refresh calls scripts.board.refresh helper

Body's Refresh mode now resolves <repo> via repo_resolver, then calls
refresh_board(signals=None). Helper handles the deterministic parts
(walk git log + spec/plan, classify Done/In-progress/Backlog, cluster
into existing buckets, update frontmatter last-refresh + totals).

The LLM (Claude executing the command) handles only the prose-level
bucket body regeneration + ## 🔥 This Week synthesis (when missing).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 7: Architect Phase 7 + `--no-board-refresh` flag

**Files:**
- Modify: `commands/obsidian-architect.md`

- [ ] **Step 1: Update flags list at top**

In `commands/obsidian-architect.md`, find the flags listing (after argument-hint frontmatter). Add to the v4-specific or v4.x flags section:

```markdown
**Board-refresh flag (v4.5):**
- `--no-board-refresh` — skip Phase 7 (board refresh). Default OFF (board.md auto-refreshes when present).
```

- [ ] **Step 2: Add Phase 7 section**

In `commands/obsidian-architect.md`, find the existing `## Daily and operation log` section (~line 624). Insert a NEW section BEFORE it:

````markdown
## Phase 7: Board refresh (auto, v4.5)

Skip if `--no-board-refresh` was passed.

Skip if `Projects/<project_slug>/board.md` doesn't exist (log line: "no board.md — skipping board refresh, run /obsidian-project <P> to bootstrap").

1. Assemble signals from already-collected Phase 1 data:

```python
import subprocess
from pathlib import Path

# last-refresh from board.md frontmatter (may be None on first run)
board_path = project_dir / "board.md"
board_text = board_path.read_text(encoding="utf-8")
import re
m = re.search(r'^last-refresh:\s*"?([^"\n]+)"?\s*$', board_text, re.MULTILINE)
last_refresh_iso = m.group(1).strip() if m else None

# Walk git log since last refresh (or full if missing).
cmd = ["git", "log", "--all", "--pretty=format:%H%x09%ad%x09%s%x09%D",
       "--date=iso-strict"]
if last_refresh_iso:
    cmd.append(f"--since={last_refresh_iso}")
proc = subprocess.run(cmd, cwd=str(repo_root), capture_output=True, text=True)
git_commits = []
for line in proc.stdout.splitlines():
    parts = line.split("\t")
    if len(parts) >= 3:
        sha, when, subject = parts[0], parts[1], parts[2]
        refs = parts[3] if len(parts) > 3 else ""
        git_commits.append({
            "title": subject, "kind": "commit", "when": when,
            "source": f"commit {sha[:8]}", "refs": refs,
        })

# Walk spec/plan files mtime-filtered.
docs = repo_root / "docs" / "superpowers"
spec_files = []
plan_files = []
import time
cutoff = None
if last_refresh_iso:
    try:
        from datetime import datetime
        cutoff = datetime.fromisoformat(last_refresh_iso.replace("Z", "+00:00")).timestamp()
    except ValueError:
        cutoff = None
for sub, dest in (("specs", spec_files), ("plans", plan_files)):
    d = docs / sub
    if d.is_dir():
        for f in sorted(d.glob("*.md")):
            if cutoff is None or f.stat().st_mtime >= cutoff:
                dest.append(f)

signals = {
    "git_commits": git_commits,
    "spec_files": spec_files,
    "plan_files": plan_files,
}
```

2. Call helper with failure isolation:

```python
from scripts.board.refresh import refresh_board

try:
    refresh_result = refresh_board(
        project_dir=project_dir,
        signals=signals,
        full=False,
    )
except Exception as e:
    refresh_result = None
    print(f"⚠️ board refresh failed: {e}; architect itself succeeded")
```

3. Use `refresh_result` in the next phase (Daily and operation log) to merge into a single combined activity log line:

   - If `refresh_result` is not None and `refresh_result.status == "ok"`:
     ```
     **HH:MM** - architect+board | <P> @ commit <sha> - <module-summary> + board (<done> done, <in-flight> in-flight, <backlog> backlog across <N> buckets)
     ```
   - If `refresh_result` is None or `status` != `"ok"`:
     ```
     **HH:MM** - architect | <P> @ commit <sha> - <module-summary> | board: <skipped/error message>
     ```

4. The architect's overall exit status is unaffected — architecture/* is the primary deliverable; Phase 7 failure is logged but non-blocking.
````

- [ ] **Step 3: Adjust `## Daily and operation log` section**

Modify the existing Daily-and-operation-log section to use the combined activity line format described in Phase 7 step 3. Concrete: change the bullet that says:

```
- If `Logs/` exists: append `**HH:MM** - architect | <P> - N modules (M new, K updated, L deprecated)` to `Logs/YYYY-MM-DD.md`.
```

To:

```
- If `Logs/` exists: append a single combined activity line to `Logs/YYYY-MM-DD.md ## Activity`. Format depends on Phase 7 outcome:
  - When Phase 7 succeeded: `**HH:MM** - architect+board | <P> @ commit <sha> - N modules (M new, K updated, L deprecated) + board (<done> done, <in-flight> in-flight, <backlog> backlog across <N> buckets)`
  - When Phase 7 was skipped or failed: `**HH:MM** - architect | <P> @ commit <sha> - N modules (M new, K updated, L deprecated) | board: <skipped/error message>`
```

- [ ] **Step 4: Rebuild adapters**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 5: Commit**

```bash
git add commands/obsidian-architect.md
git commit -m "$(cat <<'EOF'
feat(architect): Phase 7 — auto board-refresh + --no-board-refresh flag (v4.5)

After Phase 6 (Hub + activity log) finishes, Phase 7 calls
scripts.board.refresh.refresh_board with architect's already-collected
git log + spec/plan files (signals dict). Helper returns RefreshResult;
architect merges board counts into a single combined activity log line.

Failure-isolated: Phase 7 exception → warning logged, architect's
overall exit unaffected.

Skipped paths (no board.md / --no-board-refresh) get a separate "board:
skipped" suffix on the activity line, so reader sees that board refresh
was considered.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F: Docs

### Task 8: SKILL.md + CHANGELOG.md announcement

**Files:**
- Modify: `SKILL.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update SKILL.md**

In `SKILL.md`, find the `/obsidian-architect` row in the command table. Append to its description:

```markdown
(v4.5: also auto-refreshes Projects/<P>/board.md as Phase 7, opt-out via --no-board-refresh)
```

- [ ] **Step 2: Update CHANGELOG.md**

Append to the existing `## [Unreleased]` section:

```markdown
### Changed (architect + board merge)
- `/obsidian-architect <repo>` now auto-refreshes `Projects/<P>/board.md`
  as Phase 7 (after Architecture/* notes + hub block + activity log).
  Opt-out via `--no-board-refresh`. Activity log line is combined:
  `architect+board | <P> ... + board (<done> done, ...)`.
- `/obsidian-board <repo> --refresh` body now imports the shared helper
  `scripts.board.refresh.refresh_board()` instead of inline logic.
  External behavior unchanged; cron path unaffected.

### Added
- `scripts/board/refresh.py` — shared `refresh_board(project_dir,
  signals=None, full=False)` helper. Walks git log + spec/plan files
  when signals=None (cron path), reuses caller-provided signals dict
  when called from architect. Returns `RefreshResult` dataclass with
  counts + buckets + new items + last-refresh timestamps + message.
- 8 unit tests in `tests/board/test_refresh.py` covering skipped-when-
  no-board / signals-None walks / classification heuristic / bucket
  clustering / signals-provided reuse / frontmatter last-refresh update
  / full mode.
```

- [ ] **Step 3: Commit**

```bash
git add SKILL.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(skill+changelog): architect+board merge announcement (v4.5)

SKILL.md /obsidian-architect row mentions Phase 7 board refresh.
CHANGELOG Unreleased lists the helper extraction + both callers'
routing change + new tests.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G: Acceptance smoke

### Task 9: Smoke against langlive vault

**Files:** No code changes.

- [ ] **Step 1: Verify full test suite passes**

Run: `uv run pytest tests/ -q`
Expected: All PASS (419 prior + 8 new = 427).

- [ ] **Step 2: Verify all 4 platform adapter builds**

Run: `bash scripts/build.sh`
Expected: 4 platforms build OK.

- [ ] **Step 3: Manual smoke — refresh_board on langlive vault**

```bash
uv run python -c "
from pathlib import Path
from scripts.board.refresh import refresh_board

proj = Path('/Users/leric/Documents/SecondBrain/Projects/langlive-line-oa')
result = refresh_board(project_dir=proj, signals=None, full=False)

print(f'status: {result.status}')
print(f'project_slug: {result.project_slug}')
print(f'done: {result.done_count}, in_flight: {result.in_flight_count}, backlog: {result.backlog_count}')
print(f'buckets: {result.buckets[:10]}')
print(f'new_items count: {len(result.new_items)}')
print(f'last_refresh_before: {result.last_refresh_before}')
print(f'last_refresh_after: {result.last_refresh_after}')
print(f'message: {result.message}')
"
```

Expected output:
- `status: ok`
- `project_slug: langlive-line-oa`
- `done`, `in_flight`, `backlog` are non-negative integers (likely all 0 if last-refresh is recent)
- `buckets` may be empty (if last-refresh covers everything) or list existing topic buckets
- `last_refresh_after` is today's ISO timestamp

If status is `skipped`, that means langlive's project hub doesn't have a board.md — that's also a valid path.

- [ ] **Step 4: Verify combined activity log line format**

Inspect `Projects/langlive-line-oa/board.md` frontmatter:

```bash
head -10 /Users/leric/Documents/SecondBrain/Projects/langlive-line-oa/board.md
```

Expected:
- `last-refresh:` value is now today's ISO (newer than before the smoke)
- `done` / `in-flight` / `backlog` numeric keys present (or added)

- [ ] **Step 5: No commit — acceptance only**

If any step fails, write a `## Blocker` note at the top of this plan file and STOP. Otherwise mark Task 9 complete and print `ALL TASKS COMPLETE`.

---

## Spec coverage map (self-review aid)

| Spec section | Task(s) |
|---|---|
| Goal | All 9 tasks |
| Non-goals | (Implicit — cron stays calling /obsidian-board --refresh, no auto-create, no rename of /obsidian-board) |
| Scope (3 changes: extract / wire board / wire architect) | Tasks 1-5 (extract), Task 6 (wire board), Task 7 (wire architect) |
| RefreshResult dataclass shape | Task 1 |
| refresh_board signature + semantics | Tasks 1-5 |
| Architect Phase 7 (signals assembly + helper call + log merge) | Task 7 |
| /obsidian-board --refresh body change | Task 6 |
| Activity log combined format | Task 7 (Phase 7 step 3 + Daily-log section update) |
| File-by-file: scripts/board/__init__ | Task 1 |
| File-by-file: scripts/board/refresh.py | Tasks 1-5 |
| File-by-file: tests/board/test_refresh.py | Tasks 1-5 (each appends new tests) |
| File-by-file: commands/obsidian-board.md | Task 6 |
| File-by-file: commands/obsidian-architect.md | Task 7 |
| File-by-file: SKILL.md | Task 8 |
| File-by-file: CHANGELOG.md | Task 8 |
| Untouched: scripts/cron/* | (Confirmed not modified across all tasks) |
| Tests 1-6 | Distributed across Tasks 1-5 (delivered 8 actual unit tests vs spec's 6 — over-coverage) |
| Smoke test | Task 9 |
| Out-of-scope (caching / auto-create / diagnostics) | (Implicit; not implemented) |
