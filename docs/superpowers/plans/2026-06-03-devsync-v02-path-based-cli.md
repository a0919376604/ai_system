# devsync v0.2 — Path-Based CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate devsync from `code_root`-based repo lookup (v0.1) to path-based CLI (v0.2), then adapt the `claudecode-discord` `/devsync start` slash command to match the new CLI and add repo autocomplete from `~/Desktop/code/`.

**Architecture:** Two-repo plan. Tasks 1-8 live in `/Users/leric/Desktop/code/ai_system/devsync/src/` (the vendored Python CLI source). Tasks 9-11 live in `/Users/leric/Desktop/code/claudecode-discord/` (TypeScript bot). Each task ends in its own commit. Tests TDD-shaped: write failing → implement → verify → commit. After each repo's work completes, push that repo independently.

**Tech Stack:** Python 3.11+, Typer, Pydantic v2, pytest (devsync CLI side). TypeScript 5 ESM, discord.js v14, vitest (claudecode-discord side).

**Spec:** `/Users/leric/Desktop/code/ai_system/docs/superpowers/specs/2026-06-03-devsync-v02-path-based-cli-design.md` (REQ-NNN / CON-NNN / AC-NNN IDs referenced).

---

## File Map

### devsync CLI side (`ai_system/devsync/src/`)

| File | Action | Tasks |
|---|---|---|
| `src/devsync/repo.py` | REWRITE (drop fuzzy + code_root) | 1 |
| `tests/test_repo.py` | REWRITE | 1 |
| `src/devsync/errors.py` | MODIFY (drop `AmbiguousRepo`) | 2 |
| `pyproject.toml` | MODIFY (drop rapidfuzz dep + version 0.2.0) | 2, 6 |
| `tests/test_errors.py` | MODIFY (drop AmbiguousRepo tests) | 2 |
| `src/devsync/config.py` | MODIFY (drop `code_root` field) | 3 |
| `tests/test_config_models.py` | MODIFY | 3 |
| `tests/test_config_merge.py` | MODIFY | 3 |
| `src/devsync/cli.py` | MODIFY (start signature + server fallback) | 4 |
| `tests/test_cli_start.py` | REWRITE | 4 |
| `tests/test_cli_doctor.py` | MODIFY (drop `code_root` from fixture) | 5 |
| `tests/test_cli_existing_prompt.py` | MODIFY (drop `code_root` from fixture) | 5 |
| `src/devsync/__init__.py` | MODIFY (version 0.2.0) | 6 |
| `ai_system/devsync/config.toml` | MODIFY (drop `code_root`) | 7 |
| `~/.config/devsync/config.toml` | MODIFY (drop `code_root`) | 7 |
| `ai_system/devsync/README.md` | MODIFY (migration note) | 7 |

### claudecode-discord side (`/Users/leric/Desktop/code/claudecode-discord`)

| File | Action | Tasks |
|---|---|---|
| `src/bot/commands/devsync.ts` | MODIFY (`handleStart` argv + autocomplete branch) | 9, 10 |
| `src/bot/commands/devsync.test.ts` | MODIFY (argv assertion + autocomplete for `start`) | 9, 10 |

---

## Task 1: Rewrite `repo.py` (path-only, drop fuzzy)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/repo.py`
- Rewrite: `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_repo.py`

- [ ] **Step 1: Write the failing tests**

Replace `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_repo.py` entirely with:

```python
from pathlib import Path

import pytest

from devsync.errors import NoSuchRepo
from devsync.repo import RepoSpec, resolve_repo


def test_repospec_from_simple_path(tmp_path):
    d = tmp_path / "my-project"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project"
    assert spec.local_path == d.resolve()
    assert spec.is_worktree is False


def test_repospec_from_worktree_path(tmp_path):
    d = tmp_path / "my-project-wt-3"
    d.mkdir()
    spec = RepoSpec.from_path(d)
    assert spec.name == "my-project-wt-3"
    assert spec.is_worktree is True
    assert spec.parent_repo == "my-project"


def test_resolve_repo_none_uses_cwd(tmp_path):
    repo = tmp_path / "my-project"
    repo.mkdir()
    spec = resolve_repo(None, cwd=repo)
    assert spec.name == "my-project"
    assert spec.local_path == repo.resolve()


def test_resolve_repo_absolute_path(tmp_path):
    repo = tmp_path / "alpha"
    repo.mkdir()
    spec = resolve_repo(str(repo))
    assert spec.name == "alpha"
    assert spec.local_path == repo.resolve()


def test_resolve_repo_relative_path(tmp_path, monkeypatch):
    (tmp_path / "beta").mkdir()
    monkeypatch.chdir(tmp_path)
    spec = resolve_repo("./beta")
    assert spec.name == "beta"
    assert spec.local_path == (tmp_path / "beta").resolve()


def test_resolve_repo_tilde_expansion(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    (tmp_path / "gamma").mkdir()
    spec = resolve_repo("~/gamma")
    assert spec.name == "gamma"
    assert spec.local_path == (tmp_path / "gamma").resolve()


def test_resolve_repo_nonexistent_raises(tmp_path):
    with pytest.raises(NoSuchRepo) as exc:
        resolve_repo(str(tmp_path / "does-not-exist"))
    assert "does-not-exist" in str(exc.value)


def test_resolve_repo_file_not_dir_raises(tmp_path):
    f = tmp_path / "afile.txt"
    f.write_text("not a dir")
    with pytest.raises(NoSuchRepo):
        resolve_repo(str(f))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/pytest tests/test_repo.py -v
```

Expected: ImportError or AttributeError because old `resolve_repo` takes `code_root` keyword, new tests don't pass it.

- [ ] **Step 3: Rewrite `repo.py`**

Replace `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/repo.py` entirely with:

```python
"""Repo path resolution. v0.2 — path-based only, no code_root."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from devsync.errors import NoSuchRepo

# Worktree naming convention: <parent-repo>-wt-N  (e.g., ai-eden-service-wt-3)
_WORKTREE_PATTERN = re.compile(r"^(?P<parent>.+)-wt-\d+$")


@dataclass(frozen=True)
class RepoSpec:
    name: str
    local_path: Path
    is_worktree: bool
    parent_repo: str | None

    @classmethod
    def from_path(cls, path: Path) -> RepoSpec:
        path = path.resolve()
        name = path.name
        match = _WORKTREE_PATTERN.match(name)
        if match:
            return cls(
                name=name,
                local_path=path,
                is_worktree=True,
                parent_repo=match.group("parent"),
            )
        return cls(name=name, local_path=path, is_worktree=False, parent_repo=None)


def resolve_repo(arg: str | None, *, cwd: Path | None = None) -> RepoSpec:
    """Resolve a path argument to a RepoSpec.

    - arg=None → use cwd (default Path.cwd()).
    - arg='.', './foo', '/abs', '~/...' → expanduser + resolve.

    Raises NoSuchRepo if the resolved path is not a directory.
    """
    if arg is None:
        cwd = cwd or Path.cwd()
        return RepoSpec.from_path(cwd)

    p = Path(arg).expanduser().resolve()
    if not p.is_dir():
        raise NoSuchRepo(arg, [])
    return RepoSpec.from_path(p)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
.venv/bin/pytest tests/test_repo.py -v
```

Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/src/devsync/repo.py devsync/src/tests/test_repo.py
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync v0.2): rewrite repo.py as path-only (drop code_root + fuzzy)"
```

---

## Task 2: Drop `AmbiguousRepo` + `rapidfuzz` dep

**Files:**
- Modify: `src/devsync/errors.py`
- Modify: `pyproject.toml`
- Modify: `tests/test_errors.py`

- [ ] **Step 1: Drop `AmbiguousRepo` from errors.py**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/errors.py`. Delete the entire `AmbiguousRepo` class (around line 19-27, the class that takes `name, matches`). Leave the other 5 error classes untouched.

- [ ] **Step 2: Drop `AmbiguousRepo` from tests**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_errors.py`. Remove:
- `AmbiguousRepo` from the imports block at the top
- The `test_ambiguous_repo_lists_candidates` function entirely
- The `AmbiguousRepo` entry in `test_all_exceptions_inherit_from_devsync_error`'s loop

- [ ] **Step 3: Drop `rapidfuzz` from pyproject.toml**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/pyproject.toml`. In the `[project] dependencies` block, remove the line `"rapidfuzz>=3",`. Leave typer/rich/pydantic untouched.

- [ ] **Step 4: Verify no lingering references**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
grep -rn "rapidfuzz\|AmbiguousRepo" src/ tests/ pyproject.toml
```

Expected: 0 matches.

- [ ] **Step 5: Run errors test + ensure suite still imports**

```bash
.venv/bin/pytest tests/test_errors.py tests/test_repo.py -v
```

Expected: tests/test_errors.py reduced count passes, test_repo.py still 8 pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/src/devsync/errors.py devsync/src/tests/test_errors.py devsync/src/pyproject.toml
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "chore(devsync v0.2): drop AmbiguousRepo + rapidfuzz dep (unused after path-only)"
```

---

## Task 3: Drop `code_root` from `Defaults`

**Files:**
- Modify: `src/devsync/config.py`
- Modify: `tests/test_config_models.py`
- Modify: `tests/test_config_merge.py`

- [ ] **Step 1: Update failing test for Defaults rejecting code_root**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_config_models.py`. Find `test_defaults_has_sensible_values` (currently uses `code_root="/Users/leric/Desktop/code"`). Replace its body with:

```python
def test_defaults_has_sensible_values():
    d = Defaults(remote_base="/home/leric/code")
    assert d.sync_mode == "one-way-replica"
    assert d.ignore_vcs is True
    assert ".DS_Store" in d.ignore
    assert d.ssh_after_start is True
```

Find `test_global_config_loads_servers_dict` (uses `code_root="/tmp/code"`). Replace its `Defaults(...)` call with:

```python
        defaults=Defaults(remote_base="/srv/code"),
```

Find `test_global_config_rejects_unknown_field` (uses `code_root="/x"`). Replace with:

```python
def test_global_config_rejects_unknown_field():
    with pytest.raises(ValidationError):
        GlobalConfig(
            defaults=Defaults(remote_base="/y"),
            servers={},
            unknown_field="boom",
        )
```

Add a new test at the end of the file:

```python
def test_defaults_rejects_code_root():
    """v0.2 dropped code_root; old configs must be flagged."""
    with pytest.raises(ValidationError):
        Defaults(code_root="/legacy/path", remote_base="/home/leric/code")
```

- [ ] **Step 2: Update test_config_merge.py**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_config_merge.py`. Find the `_global_cfg` helper. Replace its `Defaults(...)` block to remove `code_root="/Users/leric/Desktop/code"`. The new helper:

```python
def _global_cfg() -> GlobalConfig:
    return GlobalConfig(
        defaults=Defaults(
            remote_base="/home/leric/code",
            ignore=["*.pyc"],
        ),
        servers={
            "dl01": ServerConfig(host="dl01"),
            "dl02": ServerConfig(host="dl02", remote_base="/data/leric"),
        },
    )
```

- [ ] **Step 3: Run failing tests**

```bash
.venv/bin/pytest tests/test_config_models.py tests/test_config_merge.py -v
```

Expected: at least one failure ("unknown field 'code_root'" not raised because the field is still valid in the model). Specifically `test_defaults_rejects_code_root` should fail.

- [ ] **Step 4: Drop `code_root` from `Defaults` model**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/config.py`. Find the `class Defaults(_Strict):` block. Delete the line `code_root: str` (around line 43).

The class should now start (under existing docstring/blank line):

```python
class Defaults(_Strict):
    remote_base: str
    sync_mode: Literal[
        "one-way-replica", "one-way-safe", "two-way-resolved", "two-way-safe"
    ] = "one-way-replica"
    ignore_vcs: bool = True
    ignore: list[str] = Field(default_factory=lambda: list(DEFAULT_IGNORE))
    ssh_after_start: bool = True
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
.venv/bin/pytest tests/test_config_models.py tests/test_config_merge.py -v
```

Expected: all pass, including `test_defaults_rejects_code_root`.

- [ ] **Step 6: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/src/devsync/config.py devsync/src/tests/test_config_models.py devsync/src/tests/test_config_merge.py
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync v0.2): drop Defaults.code_root (path-based CLI doesn't need it)"
```

---

## Task 4: Rewrite `cli.py::start` (server-first + path optional)

**Files:**
- Modify: `src/devsync/cli.py`
- Rewrite: `tests/test_cli_start.py`

- [ ] **Step 1: Write the failing tests**

Replace `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_cli_start.py` entirely with:

```python
from pathlib import Path
from unittest.mock import Mock

from typer.testing import CliRunner

from devsync.cli import app


def _setup_config(mocker):
    from devsync.config import Defaults, GlobalConfig, ServerConfig

    cfg = GlobalConfig(
        defaults=Defaults(remote_base="/home/leric/code"),
        servers={"dl02": ServerConfig(host="dl02")},
    )
    mocker.patch("devsync.cli.load_global_config", return_value=cfg)
    mocker.patch("devsync.cli.ensure_daemon_running")
    mocker.patch("devsync.cli.ensure_remote_dir")
    mocker.patch("devsync.cli.probe_ssh")
    mocker.patch("devsync.cli._maybe_warn_large")
    mocker.patch("devsync.cli.list_managed_sessions", return_value=[])


def test_start_with_server_only_uses_cwd(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "my-repo").mkdir()
    monkeypatch.chdir(tmp_path / "my-repo")
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_with_explicit_path(mocker, tmp_path):
    _setup_config(mocker)
    (tmp_path / "other-repo").mkdir()
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", str(tmp_path / "other-repo"), "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_with_relative_path(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "rel-repo").mkdir()
    monkeypatch.chdir(tmp_path)
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "dl02", "./rel-repo", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_default_server_from_repo_toml(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    repo = tmp_path / "auto"
    repo.mkdir()
    (repo / ".devsync.toml").write_text('default_server = "dl02"\n')
    monkeypatch.chdir(repo)
    create = mocker.patch("devsync.cli.sync_create")

    result = CliRunner().invoke(app, ["start", "--no-ssh"])
    assert result.exit_code == 0, result.stdout
    create.assert_called_once()


def test_start_missing_server_and_no_default(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    repo = tmp_path / "no-default"
    repo.mkdir()
    monkeypatch.chdir(repo)

    result = CliRunner().invoke(app, ["start", "--no-ssh"])
    assert result.exit_code != 0
    out = (result.stdout or "") + (result.stderr or "")
    assert "no server" in out.lower() or "no_server" in out.lower()


def test_start_unknown_server_exits_nonzero(mocker, tmp_path, monkeypatch):
    _setup_config(mocker)
    (tmp_path / "my-repo").mkdir()
    monkeypatch.chdir(tmp_path / "my-repo")

    result = CliRunner().invoke(app, ["start", "ghost", "--no-ssh"])
    assert result.exit_code != 0
    out = (result.stdout or "") + (result.stderr or "")
    assert "ghost" in out.lower() or "unknown" in out.lower()


def test_start_nonexistent_path_exits_nonzero(mocker, tmp_path):
    _setup_config(mocker)
    result = CliRunner().invoke(app, ["start", "dl02", str(tmp_path / "missing"), "--no-ssh"])
    assert result.exit_code != 0
```

- [ ] **Step 2: Run tests to verify failures**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/pytest tests/test_cli_start.py -v
```

Expected: failures because CLI still takes `<repo> <server>`, not `<server> <path>`.

- [ ] **Step 3: Edit `cli.py::start` signature and logic**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/cli.py`. Find the `start` function (around line 124). Replace the function definition (signature + body) with:

```python
@app.command()
def start(
    server: str = typer.Argument(
        None,
        help="Target server (e.g., dl02). Optional if .devsync.toml has default_server.",
    ),
    path: str = typer.Argument(
        None,
        help="Path to the repo (abs, rel, or ~). Omit to use cwd.",
    ),
    no_ssh: bool = typer.Option(False, "--no-ssh", help="Don't auto-SSH after starting sync."),
) -> None:
    """Create a sync session and (optionally) SSH into the server."""
    try:
        cfg = load_global_config()
    except FileNotFoundError as e:
        typer.echo(f"✗ Config missing: {e}", err=True)
        raise typer.Exit(2) from e

    try:
        repo_spec = resolve_repo(path)
    except NoSuchRepo as e:
        typer.echo(f"✗ {e}", err=True)
        raise typer.Exit(2) from e

    repo_cfg = load_repo_config(repo_spec.local_path)

    resolved_server = server or repo_cfg.default_server
    if not resolved_server:
        typer.echo(
            "✗ No server specified and no default_server in .devsync.toml",
            err=True,
        )
        raise typer.Exit(2)

    if resolved_server not in cfg.servers:
        typer.echo(
            f"✗ Unknown server '{resolved_server}'. Known: {', '.join(sorted(cfg.servers))}",
            err=True,
        )
        raise typer.Exit(2)

    eff = resolve_effective_config(
        global_cfg=cfg,
        repo_cfg=repo_cfg,
        repo_name=repo_spec.name,
        server_name=resolved_server,
    )

    ensure_daemon_running()

    try:
        probe_ssh(resolved_server, eff.host)
    except ServerUnreachable as e:
        typer.echo(f"✗ {e}", err=True)
        typer.echo("  ▸ Check VPN: /vpn status", err=True)
        typer.echo(f"  ▸ Check SSH: ssh {eff.host}", err=True)
        raise typer.Exit(3) from e

    remote_parent = "/".join(eff.remote_path.rstrip("/").split("/")[:-1]) or "/"
    ensure_remote_dir(eff.host, remote_parent)

    _maybe_warn_large(repo_spec.local_path, eff.ignore)

    spec = SessionSpec(repo=repo_spec, server_name=resolved_server)
    name = spec.name

    existing = list_managed_sessions(f"repo={repo_spec.name},server={resolved_server}")
    if existing:
        existing_name = existing[0].get("name", name)
        typer.echo(f"ⓘ Session {existing_name} already exists.")
        choice = typer.prompt(
            "  [r] Reuse  [R] Restart  [c] Cancel",
            default="r",
            show_default=True,
        ).strip()
        if choice == "c":
            typer.echo("Cancelled.")
            raise typer.Exit(1)
        if choice == "R":
            sync_terminate(existing_name)
            sync_create(spec, eff)
            typer.echo(f"→ Restarted session: {name}")
        else:
            typer.echo(f"→ Reusing session: {existing_name}")
    else:
        try:
            sync_create(spec, eff)
        except SessionAlreadyExists:
            typer.echo(f"ⓘ Session {name} already exists. Reusing.")
        typer.echo(f"→ Sync session created: {name}")
        typer.echo(f"  Local : {repo_spec.local_path}")
        typer.echo(f"  Remote: {eff.host}:{eff.remote_path}")

    if no_ssh or not eff.ssh_after_start:
        typer.echo(f"  (use `devsync stop {repo_spec.name}` when done)")
        return

    import os
    typer.echo(f"  SSHing to {eff.host}:{eff.remote_path} ...")
    os.execvp(
        "ssh",
        ["ssh", eff.host, "-t", f"cd {eff.remote_path} && exec $SHELL -l"],
    )
```

- [ ] **Step 4: Remove `AmbiguousRepo` from cli.py imports**

In the same file, locate the imports block at the top. Find the line that imports from `devsync.errors`. Remove `AmbiguousRepo` from the tuple — leaving the other 6 names. Example before:

```python
from devsync.errors import (
    AmbiguousRepo,
    DevsyncError,
    NoSuchRepo,
    NoSuchServer,
    ServerUnreachable,
    SessionAlreadyExists,
)
```

After:

```python
from devsync.errors import (
    DevsyncError,
    NoSuchRepo,
    NoSuchServer,
    ServerUnreachable,
    SessionAlreadyExists,
)
```

(`NoSuchServer` may not actually be used after the refactor; ruff will flag it if so. If ruff complains, also drop `NoSuchServer`.)

- [ ] **Step 5: Run tests to verify they pass**

```bash
.venv/bin/pytest tests/test_cli_start.py -v
```

Expected: 7 tests pass.

- [ ] **Step 6: Type-check + ruff**

```bash
.venv/bin/python -c "import devsync.cli"
.venv/bin/ruff check src/ tests/ 2>&1 | head -10
```

Expected: import OK; ruff might flag unused `NoSuchServer` import — drop it if so.

- [ ] **Step 7: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/src/devsync/cli.py devsync/src/tests/test_cli_start.py
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync v0.2): cli.start rewritten — server first, path optional, cwd default"
```

---

## Task 5: Clean up `code_root` in other test fixtures

**Files:**
- Modify: `tests/test_cli_doctor.py`
- Modify: `tests/test_cli_existing_prompt.py`

- [ ] **Step 1: Strip `code_root` from test_cli_doctor.py fixtures**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_cli_doctor.py`. Find each `defaults=Defaults(...)` call. Remove the `code_root=str(tmp_path),` line from both occurrences (around lines 11 and 30). Leave `remote_base=...` intact.

After change, each `defaults=Defaults(...)` should look like:

```python
        defaults=Defaults(remote_base="/srv"),
```

- [ ] **Step 2: Strip `code_root` from test_cli_existing_prompt.py fixture**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/tests/test_cli_existing_prompt.py`. Find the `_setup` helper. Remove the `code_root=str(tmp_path),` line from the `Defaults(...)` call. Leave `remote_base=...` intact.

After change:

```python
        defaults=Defaults(remote_base="/home/leric/code"),
```

- [ ] **Step 3: Run the full suite**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/pytest -q
```

Expected: all tests pass (target count: roughly previous total ± a few; new `test_defaults_rejects_code_root` adds 1, `test_resolve_repo_*` net adds ~3, `test_ambiguous_repo_*` removes 1).

- [ ] **Step 4: Final ruff + tsc check**

```bash
.venv/bin/ruff check src/ tests/
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/tests/test_cli_doctor.py devsync/src/tests/test_cli_existing_prompt.py
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "chore(devsync v0.2): drop code_root from doctor + existing-prompt test fixtures"
```

---

## Task 6: Bump version to 0.2.0

**Files:**
- Modify: `src/devsync/__init__.py`
- Modify: `pyproject.toml`

- [ ] **Step 1: Update version string in `__init__.py`**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/src/devsync/__init__.py`. Find the `__version__` line. Change:

```python
__version__ = "0.1.0"
```

to:

```python
__version__ = "0.2.0"
```

- [ ] **Step 2: Update pyproject.toml version**

Open `/Users/leric/Desktop/code/ai_system/devsync/src/pyproject.toml`. Find the `version = "0.1.0"` line (under `[project]`). Change to:

```toml
version = "0.2.0"
```

- [ ] **Step 3: Verify**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/python -c "import devsync; print(devsync.__version__)"
grep '^version' pyproject.toml
```

Expected: prints `0.2.0` and `version = "0.2.0"`.

- [ ] **Step 4: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/src/devsync/__init__.py devsync/src/pyproject.toml
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "chore(devsync): bump version to 0.2.0"
```

---

## Task 7: Drop `code_root` from real config files + README migration note

**Files:**
- Modify: `ai_system/devsync/config.toml`
- Modify: `~/.config/devsync/config.toml` (NOT in git, but user-facing)
- Modify: `ai_system/devsync/README.md`

- [ ] **Step 1: Drop `code_root` from vendored config snapshot**

Open `/Users/leric/Desktop/code/ai_system/devsync/config.toml`. Find the line:

```toml
code_root = "/Users/leric/Desktop/code"
```

Delete that line. Leave the rest of `[defaults]` intact.

- [ ] **Step 2: Drop `code_root` from the live local config**

```bash
sed -i '' '/^code_root = /d' ~/.config/devsync/config.toml
cat ~/.config/devsync/config.toml | head -10
```

Expected: `code_root` line is gone from `~/.config/devsync/config.toml`. The `[defaults]` block has `remote_base` as its first content line.

- [ ] **Step 3: Append migration note to README**

Open `/Users/leric/Desktop/code/ai_system/devsync/README.md`. Find a suitable place after the "Layout" or "What `bootstrap.sh` does" section (e.g., right before "## What's not in this repo (security)"). Insert this new section verbatim:

```markdown
## Migration to v0.2 (from v0.1)

v0.2 dropped `[defaults].code_root` from `config.toml` and changed `devsync start`
argument order. On any machine that ran v0.1, run once:

```bash
sed -i '' '/^code_root = /d' ~/.config/devsync/config.toml
```

CLI changes:

- v0.1: `devsync start <repo-name> <server>` (looked up under `code_root`)
- v0.2: `devsync start [<server>] [<path>]`
  - `<path>` may be absolute, relative, or `~`-prefixed; omitted → cwd
  - `<server>` may be omitted if `.devsync.toml::default_server` is set

```

- [ ] **Step 4: Verify the runtime install still works**

```bash
devsync --version
devsync doctor 2>&1 | head -2
```

Expected: prints `0.2.0` (after Task 8 reinstalls; until then it may still be 0.1.0 — fine).

- [ ] **Step 5: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/config.toml devsync/README.md
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "chore(devsync v0.2): drop code_root from config snapshot + README migration note"
```

---

## Task 8: Reinstall + live smoke + push ai_system

**Files:** none (install + verify only)

- [ ] **Step 1: Force-reinstall devsync from vendored src**

```bash
cd /Users/leric/Desktop/code/ai_system
uv tool install -e devsync/src --force
which devsync
devsync --version
```

Expected: `~/.local/bin/devsync` printed; `0.2.0`.

- [ ] **Step 2: Verify uv tool entry points at vendored src**

```bash
uv tool list 2>&1 | grep -A2 "^devsync "
```

Expected: shows `devsync v0.2.0` (or similar) and editable source path under `ai_system/devsync/src`.

- [ ] **Step 3: Cwd-default smoke**

```bash
cd /Users/leric/Desktop/code/ai_system
devsync start dl02 --no-ssh 2>&1 | tail -10
```

Expected (VPN up): session `ai_system--dl02` created. Output shows:
```
→ Sync session created: ai_system--dl02
  Local : /Users/leric/Desktop/code/ai_system
  Remote: dl02:/<remote_base>/ai_system
```

(VPN down: SSH probe fails, exit 3 with VPN hint. Acceptable — code paths still verified.)

- [ ] **Step 4: Cleanup smoke session**

```bash
devsync stop ai_system 2>&1
```

Expected: `✓ Terminated 1 session(s) for repo 'ai_system'.` (if VPN was up).

- [ ] **Step 5: Absolute-path smoke**

```bash
cd /
devsync start dl02 /Users/leric/Desktop/code/ai_system --no-ssh 2>&1 | tail -5
devsync stop ai_system 2>&1
```

Expected: same session created and stopped successfully.

- [ ] **Step 6: Bad-path smoke**

```bash
devsync start dl02 /tmp/does-not-exist-zzz --no-ssh 2>&1
```

Expected: exits non-zero with `✗ No repo matching '/tmp/does-not-exist-zzz'`.

- [ ] **Step 7: Run full test suite once more**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/pytest -q
```

Expected: full suite green.

- [ ] **Step 8: Push ai_system**

```bash
cd /Users/leric/Desktop/code/ai_system
git push origin main
git log --oneline -8
```

Expected: pushed; top commits show the 7 v0.2 commits + spec amendment.

---

## Task 9: claudecode-discord — update `runDevsync` argv order

**Files:**
- Modify: `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.ts`
- Modify: `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.test.ts`

- [ ] **Step 1: Locate the existing argv assertions in test**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
grep -n 'runDevsync\\(\\[\\"start\\"\\|\\[\\"start\\"' src/bot/commands/devsync.test.ts | head -10
```

Expected: at least 2-3 lines like `expect(runDevsync.mock.calls[1][0]).toEqual(["start", "foo", "dl02", "--no-ssh"]);`.

- [ ] **Step 2: Update the failing tests first**

Open `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.test.ts`. Find every occurrence of `["start", "foo", "dl02", "--no-ssh"]` (or with different repo/server). Change argv order to `["start", "dl02", "<path>", "--no-ssh"]` where `<path>` is the path the bot would derive from `repo`. For the existing tests, `repo` was `"foo"` and the bot derives `path = os.homedir() + "/Desktop/code/foo"`.

Concretely, for each such assertion, replace:

```typescript
expect(runDevsync.mock.calls[1][0]).toEqual(["start", "foo", "dl02", "--no-ssh"]);
```

with:

```typescript
import os from "node:os";
import path from "node:path";
// ... at module top of test file ...

const expectedPath = path.join(os.homedir(), "Desktop", "code", "foo");
expect(runDevsync.mock.calls[1][0]).toEqual(["start", "dl02", expectedPath, "--no-ssh"]);
```

(Add the `import os` and `import path` lines at the top if not present.)

Also fix the test `test_button_handler_restart` (or similarly named) that calls `runDevsync` with start args twice — same transformation.

- [ ] **Step 3: Run vitest to confirm failures**

```bash
npx vitest run src/bot/commands/devsync.test.ts 2>&1 | tail -30
```

Expected: failures on the updated `toEqual` assertions because production code still emits old argv order.

- [ ] **Step 4: Update production code**

Open `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.ts`. Find the `handleStart` function. Currently the spawn looks like:

```typescript
const create = await runDevsync(["start", repo, server, "--no-ssh"]);
```

Replace with:

```typescript
import os from "node:os";
import path from "node:path";
// ... add to module-top imports if not already there ...

// inside handleStart:
const repoPath = path.join(os.homedir(), "Desktop", "code", repo);
const create = await runDevsync(["start", server, repoPath, "--no-ssh"]);
```

Find the button-restart handler (look for another `runDevsync(["start", ...])` call further down). Apply the same transformation.

If the file already imports `os` / `path` from `node:os` / `node:path`, just reuse them. Don't duplicate imports.

- [ ] **Step 5: Run vitest to verify tests pass**

```bash
npx vitest run src/bot/commands/devsync.test.ts 2>&1 | tail -15
```

Expected: all devsync tests pass.

- [ ] **Step 6: Type-check**

```bash
npx tsc --noEmit 2>&1 | head -10
```

Expected: clean.

- [ ] **Step 7: Commit**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
git -c user.email=a0919376604@gmail.com -c user.name=leric add src/bot/commands/devsync.ts src/bot/commands/devsync.test.ts
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync): adapt argv to devsync v0.2 — start <server> <path>

The bot still accepts <repo> as a name input on the Discord slash command
(better UX than asking the user to type paths), but translates to
~/Desktop/code/<repo> before invoking the v0.2 CLI."
```

---

## Task 10: claudecode-discord — `<repo>` autocomplete for `start`

**Files:**
- Modify: `src/bot/commands/devsync.ts`
- Modify: `src/bot/commands/devsync.test.ts`

- [ ] **Step 1: Write the failing test for autocomplete from ~/Desktop/code/**

Open `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.test.ts`. Append at the bottom (above closing `})` if file ends with a wrapping block):

```typescript
import fs from "node:fs";

describe("/devsync autocomplete — repo for start", () => {
  beforeEach(() => {
    vi.mocked(runDevsync).mockReset();
    vi.restoreAllMocks();
  });

  it("lists subdirectories of ~/Desktop/code when subcommand=start", async () => {
    vi.spyOn(os, "homedir").mockReturnValue("/fake/home");
    vi.spyOn(fs, "readdirSync").mockImplementation((p, opts) => {
      if (String(p) === "/fake/home/Desktop/code") {
        return [
          { name: "ai_system", isDirectory: () => true },
          { name: "claudecode-discord", isDirectory: () => true },
          { name: ".DS_Store", isDirectory: () => false },
          { name: ".cache", isDirectory: () => true },
        ] as any;
      }
      throw new Error(`unexpected readdir: ${p}`);
    });

    const interaction = {
      options: {
        getSubcommand: vi.fn(() => "start"),
        getFocused: vi.fn(() => ({ name: "repo", value: "" })),
      },
      respond: vi.fn().mockResolvedValue(undefined),
    } as any;

    await autocomplete(interaction);
    expect(interaction.respond).toHaveBeenCalled();
    const choices = vi.mocked(interaction.respond).mock.calls[0][0];
    const names = choices.map((c: any) => c.name);
    expect(names).toContain("ai_system");
    expect(names).toContain("claudecode-discord");
    expect(names).not.toContain(".DS_Store");   // file filtered
    expect(names).not.toContain(".cache");      // dotfile filtered
  });

  it("filters by prefix typed so far", async () => {
    vi.spyOn(os, "homedir").mockReturnValue("/fake/home");
    vi.spyOn(fs, "readdirSync").mockImplementation((p) => {
      if (String(p) === "/fake/home/Desktop/code") {
        return [
          { name: "ai_system", isDirectory: () => true },
          { name: "ai-eden", isDirectory: () => true },
          { name: "langlive", isDirectory: () => true },
        ] as any;
      }
      throw new Error("unexpected");
    });

    const interaction = {
      options: {
        getSubcommand: vi.fn(() => "start"),
        getFocused: vi.fn(() => ({ name: "repo", value: "ai" })),
      },
      respond: vi.fn().mockResolvedValue(undefined),
    } as any;

    await autocomplete(interaction);
    const names = vi.mocked(interaction.respond).mock.calls[0][0].map((c: any) => c.name);
    expect(names).toEqual(expect.arrayContaining(["ai_system", "ai-eden"]));
    expect(names).not.toContain("langlive");
  });

  it("still uses devsync ls for repo autocomplete on stop", async () => {
    vi.mocked(runDevsync).mockResolvedValue({
      ok: true,
      code: 0,
      stdout: "alpha--dl01\nbeta--dl02",
      stderr: "",
    });

    const interaction = {
      options: {
        getSubcommand: vi.fn(() => "stop"),
        getFocused: vi.fn(() => ({ name: "repo", value: "" })),
      },
      respond: vi.fn().mockResolvedValue(undefined),
    } as any;

    await autocomplete(interaction);
    expect(runDevsync).toHaveBeenCalledWith(["ls"]);
    const names = vi.mocked(interaction.respond).mock.calls[0][0].map((c: any) => c.name);
    expect(names).toEqual(expect.arrayContaining(["alpha", "beta"]));
  });
});
```

- [ ] **Step 2: Add `setAutocomplete(true)` to the `repo` option in the `start` subcommand**

Open `/Users/leric/Desktop/code/claudecode-discord/src/bot/commands/devsync.ts`. Find the `addSubcommand` block for `start` (around line 67-83). The `repo` option currently looks like:

```typescript
      .addStringOption((opt) =>
        opt
          .setName("repo")
          .setDescription("Repo name under code_root")
          .setRequired(true),
      )
```

Change to:

```typescript
      .addStringOption((opt) =>
        opt
          .setName("repo")
          .setDescription("Repo name (subdirectory of ~/Desktop/code/)")
          .setRequired(true)
          .setAutocomplete(true),
      )
```

- [ ] **Step 3: Branch the `autocomplete` function by subcommand**

In the same file, find the `autocomplete` function (around line 143). It currently has two branches: `focused.name === "server"` and `focused.name === "repo"`.

For the `repo` branch, distinguish by subcommand. Replace the existing `repo` branch with:

```typescript
  if (focused.name === "repo") {
    const sub = interaction.options.getSubcommand();
    if (sub === "start") {
      const reposDir = path.join(os.homedir(), "Desktop", "code");
      let entries: fs.Dirent[];
      try {
        entries = fs.readdirSync(reposDir, { withFileTypes: true });
      } catch {
        await interaction.respond([]);
        return;
      }
      const all = entries
        .filter((e) => e.isDirectory() && !e.name.startsWith("."))
        .map((e) => e.name);
      const filtered = all
        .filter((n) => n.startsWith(String(focused.value || "")))
        .slice(0, 25)
        .map((n) => ({ name: n, value: n }));
      await interaction.respond(filtered);
      return;
    }
    // Existing path: stop / status / flush → active sessions
    const ls = await runDevsync(["ls"]);
    if (!ls.ok) {
      await interaction.respond([]);
      return;
    }
    const all = reposFromLs(ls.stdout);
    const filtered = all
      .filter((n) => n.startsWith(String(focused.value || "")))
      .slice(0, 25)
      .map((n) => ({ name: n, value: n }));
    await interaction.respond(filtered);
    return;
  }
```

Make sure `import fs from "node:fs"` and `import path from "node:path"` and `import os from "node:os"` are present at module top (they may already be there from Task 9).

- [ ] **Step 4: Run vitest to verify the new tests pass**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
npx vitest run src/bot/commands/devsync.test.ts 2>&1 | tail -15
```

Expected: 3 new autocomplete tests pass, prior tests still pass.

- [ ] **Step 5: Type-check + full suite**

```bash
npx tsc --noEmit
npm test 2>&1 | tail -10
```

Expected: clean type-check; full vitest suite green.

- [ ] **Step 6: Commit**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
git -c user.email=a0919376604@gmail.com -c user.name=leric add src/bot/commands/devsync.ts src/bot/commands/devsync.test.ts
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync): autocomplete <repo> from ~/Desktop/code for start subcommand

Scans subdirectories of \$HOME/Desktop/code and offers them as choices,
filtered by what the user has typed (cap 25 per Discord limit). Dotfiles
and non-directories are skipped. stop/status/flush autocomplete is
unchanged (still queries devsync ls for active session names)."
```

---

## Task 11: claudecode-discord — final smoke + push

**Files:** none new

- [ ] **Step 1: Full vitest run**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
npm test 2>&1 | tail -10
```

Expected: all tests pass (existing + 3 new autocomplete + updated argv assertions).

- [ ] **Step 2: Type-check**

```bash
npx tsc --noEmit
```

Expected: clean.

- [ ] **Step 3: Verify bot starts cleanly**

```bash
# Stop any running bot, then:
npm run dev 2>&1 | head -20 &
DEV_PID=$!
sleep 6
kill $DEV_PID 2>/dev/null || true
wait 2>/dev/null
```

Expected output includes: `Registered N slash commands (...)` and no Discord API rejection. (If `/devsync` was registered with the new repo description text "Repo name (subdirectory of ~/Desktop/code/)", Discord will update on the next bot start.)

- [ ] **Step 4: Push claudecode-discord**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
git push origin main
git log --oneline -5
```

Expected: pushed; top 2 commits show the v0.2 adaptation work.

- [ ] **Step 5: Optional live Discord smoke**

In Discord, run:

```
/devsync start
```

→ Auto-completion should pop up listing the directories in `~/Desktop/code/` on the bot host. Pick one (e.g., `ai_system`). Then for `<server>` pick `dl02`. Bot should reply with the session-created success message (or VPN/probe error gracefully).

This step is **manual** — skip if you don't want to run Discord interaction now.

---

## Out of Scope (deferred to v0.3+)

Per the spec §11:

- ❌ v0.1 → v0.2 automatic migration tool
- ❌ Path fuzzy matching
- ❌ Multi `code_root` support
- ❌ `server` fuzzy match
- ❌ `AmbiguousRepo` backward-compat shim
- ❌ Discord `<repo>` field accepting full paths
- ❌ Multi-source `<repo>` autocomplete

---

## Acceptance Criteria Coverage

| Spec AC | Verified by | Task(s) |
|---|---|---|
| AC-001 (cwd default) | Task 4 Step 5 (`test_start_with_server_only_uses_cwd`) + Task 8 Step 3 | 4, 8 |
| AC-002 (absolute path) | Task 4 Step 5 (`test_start_with_explicit_path`) + Task 8 Step 5 | 4, 8 |
| AC-003 (relative path) | Task 4 Step 5 (`test_start_with_relative_path`) | 4 |
| AC-004 (tilde expansion) | Task 1 Step 4 (`test_resolve_repo_tilde_expansion`) | 1 |
| AC-005 (non-existent) | Task 1 Step 4 (`test_resolve_repo_nonexistent_raises`) + Task 8 Step 6 | 1, 8 |
| AC-006 (default_server) | Task 4 Step 5 (`test_start_default_server_from_repo_toml`) | 4 |
| AC-007 (missing server) | Task 4 Step 5 (`test_start_missing_server_and_no_default`) | 4 |
| AC-008 (unknown server) | Task 4 Step 5 (`test_start_unknown_server_exits_nonzero`) | 4 |
| AC-009 (reject `code_root`) | Task 3 Step 5 (`test_defaults_rejects_code_root`) + Task 7 (real config) | 3, 7 |
| AC-010 (non-start unchanged) | Task 5 full suite still green | 5, 8 |
| AC-011 (version 0.2.0) | Task 6 Step 3 | 6 |
| AC-012 (rapidfuzz removed) | Task 2 Step 4 | 2 |
| AC-013 (Discord start works v0.2) | Task 9 vitest argv assertions + Task 11 Step 5 (manual) | 9, 11 |
| AC-014 (Discord repo autocomplete) | Task 10 Step 4 (3 new tests) + Task 11 Step 5 (manual) | 10, 11 |
