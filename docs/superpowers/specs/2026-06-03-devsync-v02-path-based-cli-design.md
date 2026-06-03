# devsync v0.2 — Path-Based CLI (Remove `code_root`)

**日期**: 2026-06-03
**作者**: brainstorm with Claude
**狀態**: approved, ready for implementation plan
**Implementation plan**: (to be created via `writing-plans` skill)

---

## Problem

devsync v0.1.0 把所有 repo 假設在單一 `code_root`（預設 `/Users/leric/Desktop/code`）底下，
`devsync start <repo> <server>` 的 `<repo>` 是個會被 fuzzy match 到 `code_root` 下子目錄的「名稱」。
這個設計在原作者本機運作良好，但 vendored 到 `ai_system/devsync/src/` 之後 push 到其他 Mac
上（例如 user `m2107007` 而非 `leric`），`code_root` 路徑根本不存在，`Path.iterdir()` 直接拋
`FileNotFoundError`：

```
File "/Users/m2107007/Desktop/code/ai_system/devsync/src/src/devsync/repo.py:66"
    candidates = _list_repo_dirs(code_root)
FileNotFoundError: [Errno 2] No such file or directory:
    '/Users/leric/Desktop/code'
```

使用者預期：「我在 repo 目錄下打一個指令，就把這個 repo 同步上去」—— 不需要 config 知道
任何路徑、不需要 cross-machine 翻譯 path。

## Root cause

`Defaults.code_root` 設計為**全域共享的絕對路徑**，於是 synced config 一定攜帶該路徑、
無法跨機器使用。同時 `<repo>` 名稱 lookup 強依賴此路徑能 enumerate 出子目錄。

## Solution

**v0.2 — path-based, no `code_root`。**

1. 移除 `Defaults.code_root` 欄位。Synced config 不再含跨機器路徑。
2. `devsync start` 改成 **`<server>` 在前、`<path>` 選填**：
   - 沒帶 path → `Path.cwd()` 當 repo
   - 帶 path → `Path(arg).expanduser().resolve()`（absolute / relative / `~` 都接）
3. 移除 fuzzy repo name matching。Repo identity = filesystem 上的 dir（透過 basename 推 repo name）。
4. 加上 `<server>` 也可選填，從 repo-local `.devsync.toml::default_server` fallback。

Stop / status / flush / ssh / ls / doctor 都不受影響 — 它們透過 mutagen label query 找
session，不碰 filesystem。

---

## Requirements

### Functional

- **REQ-001** — `devsync start [<server>] [<path>]` 兩個位置參數都 optional。
- **REQ-002** — `<path>` 省略時，使用 `Path.cwd()` 當 repo 路徑。
- **REQ-003** — `<path>` 提供時，套用 `Path(path).expanduser().resolve()` 後當 repo 路徑。Tilde、相對、絕對皆受支援。
- **REQ-004** — 若解析後路徑不是 directory，丟 `NoSuchRepo` 並 exit 2。
- **REQ-005** — `<server>` 省略時，從 `<repo>/.devsync.toml::default_server` 取。兩處都沒有則 exit 2 並印「No server specified and no default_server in .devsync.toml」訊息。
- **REQ-006** — `<server>` 必須對應 `~/.config/devsync/config.toml::[servers.*]` 的 key。未知 server 印 known list 並 exit 2。
- **REQ-007** — `Defaults` model 不再包含 `code_root` 欄位。`extra="forbid"` 仍有效，舊 config 帶 `code_root` 會被 Pydantic 視為驗證錯誤並 exit 2 with 友善訊息（透過既有 `load_global_config` 的 TOMLDecodeError-style wrap）。
- **REQ-008** — `repo.py::resolve_repo` 新簽章 `resolve_repo(arg: str | None, *, cwd: Path | None = None) -> RepoSpec`，無 `code_root` 參數。
- **REQ-009** — 移除 `_list_repo_dirs` 函式、`rapidfuzz` import、`AmbiguousRepo` 例外類別。
- **REQ-010** — `pyproject.toml` 從 `dependencies` 移除 `rapidfuzz`。
- **REQ-011** — 升級到 `version = "0.2.0"`（`pyproject.toml` + `src/devsync/__init__.py`）。
- **REQ-012** — `~/.config/devsync/config.toml` 與 `ai_system/devsync/config.toml` 都移除 `code_root` 那行。

### Non-Functional

- **REQ-020** — Stop / status / flush / ssh / ls / doctor 行為與輸出 100% 不變。
- **REQ-021** — 與 v0.1 的 CLI 形狀 BREAKING change；無向後相容 shim。
- **REQ-022** — 不修改 `claudecode-discord` 的 `/devsync` slash command；該整合等 v0.2 land 後另開 issue 修。
- **REQ-023** — 既有 tests 全套保持綠（既有的、非 code_root 相關的）。

---

## Constraints

- **CON-001** — devsync 必須仍能透過 `uv tool install -e ai_system/devsync/src` 安裝且 `~/.local/bin/devsync` 指向 vendored source（沿用 v0.1 的設定）。
- **CON-002** — `~/.config/devsync/config.toml` 的 `[servers.*]` 與 `remote_base` 維持不變；新 Mac 上只需要刪 `code_root` 那行就能用。
- **CON-003** — `.devsync.toml::default_server` 必須是 `cfg.servers` 中存在的 key，否則 fallback 後仍會 fail unknown-server 檢查。
- **CON-004** — `RepoSpec.from_path` 不變，仍是 worktree-aware（`<name>-wt-N`）。
- **CON-005** — Session naming `<repo>--<server>` 不變，repo 部分仍是 `RepoSpec.name`（path basename）。

---

## Architecture

### CLI shape diff

```
BEFORE (v0.1)                          AFTER (v0.2)
─────────────────────────────────────  ─────────────────────────────────────
devsync start <repo-name> <server>      devsync start [<server>] [<path>]
  ↓ fuzzy lookup under code_root          ↓ Path(arg).expanduser().resolve()
  ↓ FileNotFoundError on alien Mac        ↓ NoSuchRepo if !is_dir()
  RepoSpec                                RepoSpec
```

### Files changed

```
ai_system/devsync/
├── config.toml              ← MODIFY: drop code_root line
└── src/
    ├── pyproject.toml         ← MODIFY: version 0.2.0, drop rapidfuzz
    ├── src/devsync/
    │   ├── __init__.py         ← MODIFY: __version__ = "0.2.0"
    │   ├── config.py           ← MODIFY: drop code_root from Defaults
    │   ├── repo.py             ← REWRITE: drop fuzzy + _list_repo_dirs
    │   ├── errors.py           ← MODIFY: drop AmbiguousRepo
    │   └── cli.py              ← MODIFY: start() signature + server fallback
    ├── tests/
    │   ├── test_repo.py            ← REWRITE
    │   ├── test_config_models.py   ← MODIFY (drop code_root tests)
    │   ├── test_config_merge.py    ← MODIFY (drop code_root usage)
    │   └── test_cli_start.py       ← REWRITE
    └── README.md               ← MODIFY: migration note
```

### Data flow (start command)

```
                $ devsync start dl02 [/path]
                            │
                            ▼
            ┌──────────────────────────────┐
            │ load_global_config()         │
            │  - reads ~/.config/devsync/  │
            │    config.toml                │
            │  - extra=forbid catches      │
            │    leftover code_root        │
            └────────────┬─────────────────┘
                         │
                         ▼
            ┌──────────────────────────────┐
            │ resolve_repo(path or None)   │
            │  - None → Path.cwd()         │
            │  - given → expanduser().     │
            │    resolve()                  │
            │  - !is_dir → NoSuchRepo      │
            └────────────┬─────────────────┘
                         │
                         ▼
            ┌──────────────────────────────┐
            │ load_repo_config(local_path) │
            │  - reads <repo>/.devsync.toml│
            └────────────┬─────────────────┘
                         │
                         ▼
            ┌──────────────────────────────┐
            │ server fallback:             │
            │  CLI arg > repo_cfg          │
            │    .default_server > error   │
            └────────────┬─────────────────┘
                         │
                         ▼
            ┌──────────────────────────────┐
            │ rest of start (unchanged):    │
            │  effective config            │
            │  daemon ensure                │
            │  probe + ensure_remote_dir   │
            │  scan large files            │
            │  reuse prompt / sync_create  │
            │  ssh exec (or --no-ssh)      │
            └──────────────────────────────┘
```

---

## Detailed Design

### §5.1 `repo.py` 新版

```python
"""Repo path resolution. v0.2 — path-based only, no code_root."""

from __future__ import annotations
import re
from dataclasses import dataclass
from pathlib import Path

from devsync.errors import NoSuchRepo

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
                name=name, local_path=path,
                is_worktree=True, parent_repo=match.group("parent"),
            )
        return cls(name=name, local_path=path, is_worktree=False, parent_repo=None)


def resolve_repo(arg: str | None, *, cwd: Path | None = None) -> RepoSpec:
    """Resolve a path argument to a RepoSpec.

    - arg=None → use cwd (default Path.cwd())
    - arg='.', './foo', '/abs', '~/...' → expanduser + resolve

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

### §5.2 `config.py` diff

`Defaults` 移除 `code_root: str` 欄位。其他不變。

### §5.3 `cli.py::start` 新版

```python
@app.command()
def start(
    server: str = typer.Argument(
        None,
        help="Target server (e.g., dl02). Optional if .devsync.toml has default_server.",
        autocompletion=_server_completions,
    ),
    path: str = typer.Argument(
        None,
        help="Path to the repo (abs, rel, ~). Omit to use cwd.",
    ),
    no_ssh: bool = typer.Option(False, "--no-ssh"),
) -> None:
    """Create a sync session and (optionally) SSH into the server."""
    try:
        cfg = load_global_config()
    except FileNotFoundError as e:
        typer.echo(f"✗ Config missing: {e}", err=True)
        raise typer.Exit(2)

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

    # ... rest unchanged (effective config, daemon, probe, ensure dir,
    #     warn large, existing session reuse prompt, sync_create, ssh)
```

### §5.4 `pyproject.toml` diff

```diff
 [project]
 name = "devsync"
-version = "0.1.0"
+version = "0.2.0"
 ...
 dependencies = [
   "typer>=0.12",
   "rich>=13",
   "pydantic>=2",
-  "rapidfuzz>=3",
 ]
```

### §5.5 `errors.py` diff

```diff
-class AmbiguousRepo(DevsyncError):
-    def __init__(self, name, matches):
-        super().__init__(...)
-        ...
```

---

## Test Strategy

### 改寫 `tests/test_repo.py`

- 保留：worktree-aware `from_path`、cwd-default
- 改寫：`resolve_repo` 簽章不再有 `code_root`
- 新增：
  - `test_resolve_repo_absolute_path(tmp_path)` — `/abs/path` 被 resolve
  - `test_resolve_repo_relative_path(tmp_path)` — `./foo` rel to cwd
  - `test_resolve_repo_tilde(tmp_path, monkeypatch)` — `~/foo` 經 expanduser
  - `test_resolve_repo_nonexistent_raises_no_such_repo()` — NoSuchRepo on missing dir

### 改寫 `tests/test_config_models.py`

- 移除 `test_defaults_has_sensible_values` 中的 `code_root` 期望
- 新增 `test_defaults_rejects_unknown_field_code_root` — 帶 `code_root` 的舊 TOML 被 ValidationError 拒絕
- 移除 `test_config_merge` 中所有 `code_root=...` 構造

### 改寫 `tests/test_cli_start.py`

3 條 happy path 對應 3 種 server fallback：

- `test_start_with_server_and_path_explicit`
- `test_start_with_server_and_cwd_default`（mock cwd）
- `test_start_with_default_server_from_repo_toml`

錯誤路徑：

- `test_start_missing_server_and_no_default_exits_2`
- `test_start_unknown_server_exits_2`
- `test_start_path_not_dir_exits_2`

### 不寫單元測試的部分

- Pydantic 自己的 extra=forbid 行為（已被 v0.1 一個 test 覆蓋，只調整資料）
- Typer 的 positional ordering（trust the framework）
- Live `devsync start` against real server（mutagen integration；smoke 階段做）

### Smoke checklist（manual，加進 README）

```
[ ] cd ~/Desktop/code/ai_system && devsync start dl02 --no-ssh
    → 看到 session `ai_system--dl02` 建立、Remote path 是 /nas02/.../ai_system
[ ] devsync stop ai_system
[ ] cd / && devsync start dl02 ~/Desktop/code/ai_system --no-ssh
    → 與上一樣的 session
[ ] devsync stop ai_system
[ ] cd / && devsync start dl02 ./nonexistent --no-ssh
    → exit 2 with "No such repo: ./nonexistent"
[ ] devsync start --no-ssh    (in repo with default_server in .devsync.toml)
    → 0 args 也能跑、server 從 toml 補
[ ] devsync start --no-ssh    (in repo without default_server)
    → exit 2 with "No server specified..."
```

---

## Acceptance Criteria

### AC-001 — Cwd default

- **Given** 在 `~/Desktop/code/foo` 目錄
- **When** `devsync start dl02 --no-ssh`
- **Then** 建立 session `foo--dl02`、Local = `~/Desktop/code/foo`、Remote = `dl02:/<remote_base>/foo`，exit 0。

### AC-002 — Absolute path

- **Given** 任意 cwd
- **When** `devsync start dl02 /abs/path/foo --no-ssh`（路徑存在）
- **Then** 建立 session `foo--dl02`、Local = `/abs/path/foo`，exit 0。

### AC-003 — Relative path

- **Given** cwd = `~/Desktop/code`
- **When** `devsync start dl02 ./foo --no-ssh`
- **Then** Local = `~/Desktop/code/foo`（resolved absolute），exit 0。

### AC-004 — Tilde expansion

- **Given** 任意 cwd
- **When** `devsync start dl02 ~/Desktop/code/foo --no-ssh`
- **Then** Local = `<expanded home>/Desktop/code/foo`，exit 0。

### AC-005 — Non-existent path

- **Given** `~/Desktop/code/bogus` 不存在
- **When** `devsync start dl02 ~/Desktop/code/bogus --no-ssh`
- **Then** Exit 2 with stderr message starting with `✗ No repo matching '~/Desktop/code/bogus'`. 不建立 session。

### AC-006 — Default server from `.devsync.toml`

- **Given** `~/Desktop/code/foo/.devsync.toml` 含 `default_server = "dl02"`
- **When** `cd ~/Desktop/code/foo && devsync start --no-ssh`
- **Then** 同 AC-001（session `foo--dl02`）。

### AC-007 — Missing server, no default

- **Given** cwd 內 `.devsync.toml` 不存在或沒有 `default_server`
- **When** `devsync start --no-ssh`
- **Then** Exit 2 with stderr `✗ No server specified and no default_server in .devsync.toml`.

### AC-008 — Unknown server

- **When** `devsync start ghost --no-ssh`（`ghost` 不在 `[servers.*]`）
- **Then** Exit 2 with stderr `✗ Unknown server 'ghost'. Known: dl01, dl02, dl03, dl04`.

### AC-009 — Old config with `code_root` is rejected cleanly

- **Given** `~/.config/devsync/config.toml` 仍含 `code_root = "..."` 行
- **When** 任何 `devsync` 指令啟動
- **Then** Pydantic ValidationError → 統一錯誤訊息（`load_global_config` wrap），告知 user 移除 `code_root` 那行。

### AC-010 — Non-start commands unchanged

- **Given** Active session `foo--dl02`
- **When** `devsync stop foo` / `devsync status foo` / `devsync flush foo` / `devsync ls` / `devsync ssh foo`
- **Then** 行為與輸出與 v0.1 完全相同。

### AC-011 — Version bump

- **When** `devsync --version`
- **Then** prints `0.2.0`.

### AC-012 — `rapidfuzz` dep removed

- **When** `grep rapidfuzz pyproject.toml` 與 `grep -r "import rapidfuzz" src/`
- **Then** 0 hit each.

---

## Implementation Roadmap

5 個 milestone。

| # | Milestone | 驗收 |
|---|---|---|
| M1 | `repo.py` 重寫 + `tests/test_repo.py` 改寫 | AC-002~005, pytest `test_repo.py` 全綠 |
| M2 | `config.py` 拔 `code_root` + `errors.py` 拔 `AmbiguousRepo` + `pyproject.toml` 拔 `rapidfuzz` + 改 `test_config_*.py` | AC-009, AC-012, pytest `test_config_*.py` 全綠 |
| M3 | `cli.py::start` 改寫 + `test_cli_start.py` 改寫 + bump `__version__` | AC-001, 006, 007, 008, AC-011, pytest `test_cli_start.py` 全綠 |
| M4 | 改 `ai_system/devsync/config.toml` + `~/.config/devsync/config.toml` 拔 `code_root` 行 + README migration note | AC-009 (real-world) |
| M5 | `uv tool install -e ... --force` + live smoke + commit + push | Smoke checklist 全綠 |

---

## Out of Scope (v0.2)

- ❌ `claudecode-discord` 的 `/devsync` slash command 適配（另開 issue 修）
- ❌ v0.1 → v0.2 自動 migration tool（手動刪一行夠了）
- ❌ Path 帶 fuzzy match（不再有 code_root 可以掃）
- ❌ 多 `code_root` 支援
- ❌ `server` 進一步的 fuzzy（精準比對足夠）
- ❌ Re-export `AmbiguousRepo` for backward compat（已知無外部 consumer）

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `claudecode-discord` bot 立刻壞掉 | 另開 issue。Discord `/devsync` 暫時無法用、但 CLI 直接用 OK |
| 多台 Mac 的 `~/.config/devsync/config.toml` 還帶 `code_root`，v0.2 一律 reject | M4 提供 `sed` 命令 + README migration note；reject 訊息明示「Remove the `code_root = ...` line」 |
| 其他人腳本 import `AmbiguousRepo` | Internal-only。grep 確認 0 hit、刪即可 |
| `~/.local/bin/devsync` 沒重指向 v0.2 | M5 跑 `uv tool install -e ... --force` 強制重指向 |
| Tests 改起來牽動多個檔 | M1-M3 各自獨立可驗收 |

---

## Open Questions

None at brainstorm completion. 4 段 design walkthrough 全 OK。
