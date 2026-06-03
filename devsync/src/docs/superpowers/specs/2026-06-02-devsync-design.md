# devsync — Design Spec

- **Date**: 2026-06-02
- **Status**: Approved (brainstorm phase)
- **Author**: leric (with Claude)
- **Implementation plan**: (to be created via `writing-plans` skill)
- **Project-level spec**: not yet created; this document is the seed for a future `~/Desktop/code/devsync/spec/architecture-devsync.md` that will be generated via `update-specification` once v0.1 lands.

---

## 1. Context & Problem Statement

leric has 4 internal Linux servers (`dl01`–`dl04`, `192.168.90.31`–`34`, user `leric`) primarily used for GPU/CPU workloads. The current workflow is:

1. Develop on macOS (`~/Desktop/code/<repo>`).
2. Pick a server today based on availability.
3. Get the code over to that server.
4. Run the program there (interactive SSH session).

Today this is done with ad-hoc `rsync` / manual `scp`, which:
- Breaks the edit-test-rerun loop (no live sync; manual push every iteration).
- Has no concept of "which session is mine, on which server, for which repo".
- Leaves stale code on servers after work is done.

**Goal**: a single CLI (`devsync`) that makes the edit-sync-run loop feel local — pick a server, work normally on the Mac, the server stays in sync, clean up explicitly when done.

The mechanism is [Mutagen](https://mutagen.io/) (already installed in §0 setup).

---

## 2. Requirements

### Functional

- **REQ-001** — Sync a single repo from macOS to one of 4 named servers, selected manually per invocation.
- **REQ-002** — Sync is continuous (file-watcher based), not one-shot. Edit on Mac → server reflects change within 1 second under normal LAN conditions.
- **REQ-003** — Sync is one-way (Mac → server). Server-side modifications are overwritten on the next sync cycle (typically within seconds of detection). Mac is the single source of truth.
- **REQ-004** — A single invocation (`devsync <repo> <server>`) starts the sync AND drops the user into an SSH shell on the server at the repo's remote path.
- **REQ-005** — Sync sessions persist after the SSH shell exits. They are terminated explicitly via `devsync stop <repo>`.
- **REQ-006** — `devsync ls` lists all currently active sessions managed by this tool.
- **REQ-007** — `devsync status <repo>` / `devsync flush <repo>` / `devsync logs <repo>` provide visibility and control over a specific session.
- **REQ-008** — `devsync doctor` verifies the mutagen daemon, server SSH reachability, and config validity.
- **REQ-009** — Fuzzy match repo and server names with disambiguation when ambiguous (e.g., `devsync ai-eden dl02` should fail clearly when both `ai-eden-service` and `ai-eden-service-wt-1` exist).
- **REQ-010** — Git worktrees are treated as independent repos (each maps to its own remote directory). No special worktree consolidation.
- **REQ-011** — Mutagen labels (`managed-by=devsync`, `repo=<name>`, `server=<name>`, `worktree=<name|none>`, `created-at=<ISO8601>`) are attached to every session for filtering and batch operations.

### Non-Functional

- **REQ-020** — Tool has zero persistent state of its own; all session state is derived from `mutagen sync list --label-selector=managed-by=devsync`.
- **REQ-021** — Configuration is human-editable TOML, never contains secrets.
- **REQ-022** — Authentication to servers uses SSH key only (no passwords, no `sshpass`).
- **REQ-023** — Installation is single-command (`uv tool install devsync` or `pipx install devsync`) and does not pollute the system Python.
- **REQ-024** — Tool runs on macOS (Apple Silicon and Intel), Python ≥ 3.11.

---

## 3. Constraints

- **CON-001** — Servers are on a private network (192.168.90.x); user may need to be on the corporate VPN. Tool surfaces clear errors but does not manage VPN itself (delegates to `/vpn` skill in error hints).
- **CON-002** — Initial server passwords (`a1478520`, `Lang@2024`, `Lang@2024`, `Lang@2023`) are weak / partially shared. Tool's design must not require passwords beyond a one-time `ssh-copy-id` during Milestone 0; passwords must never be persisted in any file managed by this tool.
- **CON-003** — Mutagen daemon is per-user, already installed and registered with launchd (see prior session). Tool may start it on demand but should not assume sudo / system-wide install.
- **CON-004** — User has many git worktrees (e.g., `ai-eden-service-wt-1`, `langlive-line-oa-wt-3/4`). Name resolution must handle these without ambiguity bugs.
- **CON-005** — User typically works on one repo × one server at a time, but the tool must not preclude having multiple sessions active (e.g., `repo-A on dl01` + `repo-B on dl02` simultaneously).
- **CON-006** — Tool depends on `mutagen` CLI v0.18+ being on `$PATH`.

---

## 4. Architecture Overview

### High-Level Components

```
                    ┌──────────────────────────────────────┐
                    │  devsync CLI (Typer-based Python)    │
                    │                                      │
                    │  cli.py ── command dispatch          │
                    │  config.py ── TOML load + merge      │
                    │  repo.py ── path / fuzzy / worktree  │
                    │  server.py ── ServerSpec, SSH probe  │
                    │  session.py ── name + label assembly │
                    │  mutagen.py ── subprocess wrapper    │
                    │  ui.py ── rich tables, prompts       │
                    │  errors.py ── typed exceptions       │
                    └──────────────┬───────────────────────┘
                                   │ subprocess
                ┌──────────────────┴──────────────────────┐
                ▼                                         ▼
        ┌──────────────────┐                    ┌────────────────┐
        │ mutagen daemon   │                    │   ssh (system) │
        │ (per-user, lan-  │                    │   ~/.ssh/config│
        │  chd-registered) │                    │   key auth     │
        └────────┬─────────┘                    └────────┬───────┘
                 │ sync sessions                         │ interactive
                 ▼                                       ▼
        ┌───────────────────────────────────────────────────────┐
        │     dl01 / dl02 / dl03 / dl04 (192.168.90.31-34)      │
        │     leric@dlNN:/home/leric/code/<repo>                │
        └───────────────────────────────────────────────────────┘
```

### Single Source of Truth

`devsync` keeps **no local state file**. Every operation reads from `mutagen sync list` using labels. This eliminates state-divergence bugs between tool restarts, mutagen daemon restarts, or concurrent devsync invocations.

---

## 5. Detailed Design

### 5.1 CLI Surface

| Command | Behavior |
|---|---|
| `devsync start <repo> <server>` | Create sync session, optionally auto-SSH. |
| `devsync <repo> <server>` | Alias for `start`. |
| `devsync ls` | Table of active sessions (name, server, status, staged files, last sync). |
| `devsync ssh <repo>` | SSH into the server at the session's remote path. |
| `devsync stop <repo>` | Terminate the named session (uses `repo=` label selector). |
| `devsync stop --all` | Terminate all `managed-by=devsync` sessions. |
| `devsync status <repo>` | Detailed status: problems, staged files, conflicts. |
| `devsync flush <repo>` | Force an immediate sync cycle. |
| `devsync logs <repo>` | Tail mutagen logs for this session. |
| `devsync doctor` | Health check: daemon, 4 servers, config schema. |

**UX rules**:
- `<repo>` is optional and inferred from cwd if omitted.
- `<server>` accepts fuzzy match; ambiguity → list candidates and exit non-zero.
- Mutagen daemon is auto-started silently before any operation.

### 5.2 Configuration

#### Global: `~/.config/devsync/config.toml`

```toml
[defaults]
code_root = "/Users/leric/Desktop/code"
remote_base = "/home/leric/code"
sync_mode = "one-way-replica"
ignore_vcs = true
ignore = [
  ".DS_Store", "*.pyc", "__pycache__/", ".venv/", "node_modules/",
  ".pytest_cache/", ".ruff_cache/",
  "*.ckpt", "*.pt", "*.bin", "*.safetensors", "*.parquet"
]
ssh_after_start = true

[servers.dl01]
host = "dl01"  # resolved via ~/.ssh/config

[servers.dl02]
host = "dl02"

[servers.dl03]
host = "dl03"

[servers.dl04]
host = "dl04"
```

#### Per-repo (optional): `<repo>/.devsync.toml`

```toml
default_server = "dl02"
remote_path = "/data/leric/eden/service"   # overrides <remote_base>/<repo_name>
ignore = ["models/", "datasets/"]          # additive to defaults.ignore
```

#### Override Precedence (highest → lowest)

1. CLI flags
2. `<repo>/.devsync.toml`
3. `[servers.<name>]`
4. `[defaults]`

### 5.3 SSH Setup (Milestone 0, performed once manually)

`~/.ssh/config`:

```ssh-config
Host dl01
  HostName 192.168.90.31
  User leric
  IdentityFile ~/.ssh/id_ed25519

Host dl02
  HostName 192.168.90.32
  User leric
  IdentityFile ~/.ssh/id_ed25519

Host dl03
  HostName 192.168.90.33
  User leric
  IdentityFile ~/.ssh/id_ed25519

Host dl04
  HostName 192.168.90.34
  User leric
  IdentityFile ~/.ssh/id_ed25519
```

Public key is pushed once per host via `ssh-copy-id`. Passwords are entered exactly four times (one per host) during Milestone 0 and never again.

### 5.4 Mutagen Invocation

```bash
mutagen sync create \
  --name=<repo-slug>--<server> \
  --label managed-by=devsync \
  --label repo=<repo-slug> \
  --label server=<server-name> \
  --label worktree=<wt-name-or-none> \
  --label created-at=<ISO8601> \
  --sync-mode=one-way-replica \
  --ignore-vcs \
  --ignore=<each-pattern> ... \
  --default-file-mode-beta=0644 \
  --default-directory-mode-beta=0755 \
  <local-absolute-path> \
  <server>:<remote-absolute-path>
```

Symlink mode is left at Mutagen's default `portable`. Per-repo override available via `.devsync.toml` (`symlink_mode = "ignore"`).

### 5.5 Session Naming

`<repo-slug>--<server>` — chosen for grep-ability and to avoid colon-quoting issues in shell.

Example: `ai-eden-service-wt-1--dl02`.

### 5.6 Repo Resolution Algorithm

```python
def resolve_repo(arg: str | None, cwd: Path) -> RepoSpec:
    if arg is None:
        return RepoSpec.from_path(cwd)

    exact = code_root / arg
    if exact.is_dir():
        return RepoSpec.from_path(exact)

    candidates = [p.name for p in code_root.iterdir() if p.is_dir()]
    matches = fuzzy_filter(arg, candidates, cutoff=70)

    if len(matches) == 1:
        return RepoSpec.from_path(code_root / matches[0])
    if len(matches) > 1:
        raise AmbiguousRepo(arg, matches)
    raise NoSuchRepo(arg, candidates)
```

`RepoSpec` carries: `local_path`, `name`, `is_worktree`, `parent_repo` (if worktree).

### 5.7 Error Handling Cases

| Case | Behavior |
|---|---|
| Mutagen daemon down | Silent start; on failure print recovery hint. |
| Server unreachable | Pre-flight probe with `ssh -o BatchMode=yes -o ConnectTimeout=5`. Hint: VPN, ping, key. |
| Session name already exists | Prompt: `[r]euse / [R]estart / [c]ancel`. Default = reuse. |
| Remote parent dir missing | Pre-create via `ssh <server> "mkdir -p <remote_base>"`. |
| Mutagen reports `problem` | Surface in `devsync status`; refuse to claim healthy. |
| Initial scan > 100 MB | Print top files, 3-second cancellable countdown. |
| Multiple worktrees → same server | Land in distinct remote dirs; `devsync ls` shows local path column. |
| Config file invalid / missing keys | Pydantic surfaces field path + reason; non-zero exit. |

---

## 6. Test Strategy

Adapted from the `update-specification` template — substituting pytest for the .NET defaults.

### 6.1 Unit Tests (pytest, `tests/test_*.py`)

| Module | Coverage targets |
|---|---|
| `config.py` | 4-layer override merge; missing-key errors; type coercion. |
| `repo.py` | fuzzy match cutoff; worktree detection; cwd inference. |
| `session.py` | Label assembly; name generation with worktree names. |
| `mutagen.py` | Argv assembly; path escaping; multi-ignore flags. |

### 6.2 Subprocess Integration Tests (pytest-mock)

`subprocess.run` is patched to return canned outputs:

- `mutagen sync list` returning empty → `devsync ls` shows "No active sessions".
- `mutagen sync list` returning malformed JSON → graceful error, no crash.
- `ssh ... true` returning non-zero → `ServerUnreachable` raised with hostname.
- `mutagen sync create` returning non-zero → error surfaced with stderr.

### 6.3 Smoke Checklist (manual, documented in README)

```
[ ] devsync doctor               → 4/4 servers reachable
[ ] devsync start <repo> dl01    → mutagen sync list shows the session
[ ] echo "x" > foo.txt           → ssh dl01 sees foo.txt within 1s
[ ] rm foo.txt                   → ssh dl01 sees foo.txt gone
[ ] devsync stop <repo>          → session removed from mutagen sync list
```

Run after every release (5 minutes).

### 6.4 Explicit Non-Goals

- Mutagen's own behavior is not tested (out of scope).
- Real SSH against real servers in CI (no CI for v0.1).
- Coverage % targets (anti-pattern for personal tools).

---

## 7. Acceptance Criteria

### AC-001 — SSH base infrastructure (Milestone 0)

- **Given** a fresh macOS environment with no key trust to dl01–dl04
- **When** the user follows the Milestone 0 procedure
- **Then** `for h in dl01 dl02 dl03 dl04; do ssh -o BatchMode=yes $h hostname; done` succeeds for all four hosts without password prompts.

### AC-002 — Tool installs cleanly

- **Given** Python ≥ 3.11 and `uv` (or `pipx`) installed
- **When** the user runs `uv tool install ~/Desktop/code/devsync`
- **Then** the `devsync` command is on `$PATH` and `devsync --version` prints a semantic version.

### AC-003 — Doctor reports green

- **Given** Milestone 0 complete and config file written
- **When** the user runs `devsync doctor`
- **Then** the output shows mutagen daemon running, all 4 servers reachable, and config valid.

### AC-004 — Start → edit → server sees change

- **Given** `devsync doctor` is green
- **When** the user runs `devsync start ai-eden-service dl02`, then edits a file locally
- **Then** within 1 second, `ssh dl02 ls <remote_path>/<changed_file>` reflects the change.

### AC-005 — Session persists across SSH disconnect

- **Given** an active session created via `devsync start`
- **When** the user exits the auto-spawned SSH shell
- **Then** `devsync ls` still shows the session, and subsequent edits still sync.

### AC-006 — Stop cleanly removes session

- **Given** an active session
- **When** the user runs `devsync stop ai-eden-service`
- **Then** `mutagen sync list` no longer lists the session, and `devsync ls` shows it gone.

### AC-007 — Ambiguous repo name fails loudly

- **Given** both `ai-eden-service` and `ai-eden-service-wt-1` exist in `code_root`
- **When** the user runs `devsync ai-eden dl02`
- **Then** the tool exits non-zero with a message listing both candidates and no session is created.

### AC-008 — Server-side mutation is overwritten

- **Given** a sync session is active in `one-way-replica` mode
- **When** the user edits a file on the server side
- **Then** the next sync cycle restores the file to its Mac state.

### AC-009 — Worktrees are isolated

- **Given** active sessions for both `ai-eden-service` and `ai-eden-service-wt-1` on the same server
- **When** edits are made to either
- **Then** the changes land in distinct remote directories and do not interfere.

### AC-010 — Large file warning fires

- **Given** initial scan finds files totalling > 100 MB
- **When** `devsync start` runs
- **Then** the user sees the top largest files and a 3-second countdown before sync proceeds.

---

## 8. Implementation Roadmap (high level)

Concrete steps will be produced by the `writing-plans` skill. Milestones:

| # | Milestone | Verification |
|---|---|---|
| 0 | SSH key infrastructure | AC-001 |
| 1 | Project skeleton + config loading | AC-002 |
| 2 | `devsync doctor` | AC-003 |
| 3 | `start` / `stop` / `ls` core trio | AC-004, AC-005, AC-006, AC-007, AC-008, AC-009 |
| 4 | UX polish (auto-ssh, warnings, status, flush, logs) | AC-010 + smoke checklist |
| 5 | Tests + README + tag v0.1.0 | Full test suite green, smoke checklist passes from cold install |

---

## 9. Out of Scope (v0.1)

Documented features intentionally **not** implemented in v0.1:

- `devsync run <repo> <server> -- <cmd>` (non-interactive execution mode).
- `devsync switch <repo> <serverA→serverB>` (session migration).
- `devsync gpu-status` (cross-server GPU occupancy query).
- Post-sync hooks (defined in TOML schema but not executed).
- Idle-timeout auto-termination of sessions.
- Two-way sync mode.
- CI / GitHub Actions.
- Auto-discovery of servers (DNS / mDNS).

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Lateral-movement risk on internal network due to weak / shared server passwords | Strongly recommended (and noted in Milestone 0 hand-off) to rotate passwords and disable password login after SSH key trust is established. |
| Mutagen CLI / label format changes across versions | All `mutagen` calls funnel through `mutagen.py`; version-pin compatibility matrix in README. |
| User edits server-side and loses work | Documented behavior: `one-way-replica` mode is destructive on the beta side. `devsync ls` table makes session targets visible. |
| VPN drops mid-sync | Mutagen retries automatically; `devsync doctor` and `devsync status` surface stuck sessions. |
| Large model files (`.ckpt`, `.parquet`) accidentally pushed | Baseline ignore list pre-empts common cases; initial-scan warning catches the rest with 3-second cancel window. |

---

## 11. Open Questions

None at brainstorm completion. All decisions were closed during the §1–§9 walkthrough.

If new questions surface during planning or implementation, append them here with a date stamp and resolution.
