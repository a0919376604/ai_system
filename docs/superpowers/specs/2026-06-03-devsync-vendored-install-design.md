# Vendored devsync + One-Command Bootstrap

**日期**: 2026-06-03
**作者**: brainstorm with Claude
**狀態**: approved, ready for implementation plan
**Implementation plan**: (to be created via `writing-plans` skill)

---

## Problem

`devsync` v0.1.0 已經完成，但要在另一台 Mac 上裝起來目前需要使用者跑 ~6
個獨立指令、外加 4 次 `ssh-copy-id` 互動：

```bash
brew install mutagen-io/mutagen/mutagen
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ssh-snippet >> ~/.ssh/config && chmod 600 ~/.ssh/config
for h in dl01 dl02 dl03 dl04; do ssh-copy-id $h; done
git clone <devsync repo> && cd <devsync> && uv tool install -e .
devsync doctor
```

而且 `devsync` 源碼目前只在本機 `~/Desktop/code/devsync/`，沒有 GitHub
remote，新機器拿不到。

理想：使用者 clone `ai_system` repo，跑 `./sync.sh restore`，就完成所有
事情（除了 4 個 server 密碼 — 那個沒辦法自動化）。

## Root cause

兩件事缺著：

1. **devsync 源碼沒有可被新機器拿到的位置**（沒 push GitHub，沒 PyPI 發布，沒 Homebrew tap）
2. **`ai_system/sync.sh` 既有的 `devsync_post_restore` 只印「該裝什麼」、沒真的裝**

## Solution

兩個動作：

1. **Vendor** —— 把 `~/Desktop/code/devsync/` 的當下檔案（v0.1.0）拷貝到
   `ai_system/devsync/src/`。`ai_system` push 時這份源碼就一起上 GitHub，
   新機器 clone ai_system 就同時拿到 devsync。

2. **`bootstrap.sh`** —— 在 `ai_system/devsync/` 新增一支獨立可跑的 bash
   腳本，把目前所有手動步驟封裝成 7 個 idempotent step。`sync.sh restore`
   結尾呼叫它；也可以單獨 `./ai_system/devsync/bootstrap.sh` 跑。

---

## Requirements

### Functional

- **REQ-001** — Vendor `~/Desktop/code/devsync/` 內容（不含 `.git/`、`.venv/`、`dist/`、`build/`、`*.egg-info/`、`__pycache__/`）至 `ai_system/devsync/src/`。
- **REQ-002** — Vendored source 必須通過 `pytest -q` 全 67 tests（與原本一致）。
- **REQ-003** — 新增 `ai_system/devsync/bootstrap.sh`，獨立可執行。
- **REQ-004** — `bootstrap.sh` 是 idempotent：再跑一次所有已完成的 step 直接 ✓ skip，不要求互動。
- **REQ-005** — `bootstrap.sh` 包含 7 個 step：mutagen / uv / devsync CLI / SSH key / ssh config / key trust / verify。順序固定。
- **REQ-006** — 每個 step 先檢查狀態；缺則 prompt `[Y/n]` 後行動。
- **REQ-007** — Step 3（devsync CLI）使用 `uv tool install -e "$SCRIPT_DIR/src"` 並 `--force` 覆寫既有安裝，確保 PATH 上的 `devsync` 指向 vendored 源碼。
- **REQ-008** — Step 6（key trust）對 4 台 server 分別執行 `ssh-copy-id`；連不到（VPN down）的 server skip 並印 hint，**不 abort** 整個 bootstrap。
- **REQ-009** — Step 7（verify）跑 `devsync doctor`；4/4 reachable 為完整成功，部分 unreachable 為 warn 不算 fail。
- **REQ-010** — 支援 `--yes`（同義 `-y`）旗標，跳過所有 `[Y/n]` 確認（仍 prompt ssh-copy-id 密碼，無法迴避）。
- **REQ-011** — `sync.sh` 的 `devsync_post_restore` 改為直接 invoke `bootstrap.sh`，並把 `--yes` 旗標傳遞下去。
- **REQ-012** — 刪除 `~/Desktop/code/devsync/`（migration 完成後不再需要）。

### Non-Functional

- **REQ-020** — `bootstrap.sh` 只支援 macOS。Linux / Windows 不在 v0.1 範圍。
- **REQ-021** — 不引入新依賴（cargo / pipenv / poetry 等不准）；只用 `brew`、`uv`、`ssh`、`ssh-copy-id`、`mutagen`、`devsync`。
- **REQ-022** — 任何 step 失敗預設 prompt「continue anyway? [y/N]」；`--yes` 模式則直接 exit 1。
- **REQ-023** — 所有輸出走既有 `info / ok / warn / err` log helpers（與 `sync.sh` 同款）。Color codes 在非 TTY 自動關閉。

---

## Constraints

- **CON-001** — `ai_system` 預期 clone 在 `~/Desktop/code/ai_system/`。`bootstrap.sh` 透過 `$BASH_SOURCE` 取得自身路徑，理論上位置無關，但 README 與測試文件假設此標準位置。
- **CON-002** — `brew` 必須先存在。新 Mac 若沒裝 Homebrew，bootstrap Step 1 失敗並印 https://brew.sh 連結。
- **CON-003** — `uv` 若不存在，Step 2 走 `brew install uv`（不主動 `curl | bash`，避免信任邊界）。
- **CON-004** — `ssh-copy-id` 一定要使用者打密碼，沒有自動化空間（除非用 sshpass + 明文密碼，明確不採用）。
- **CON-005** — `~/Desktop/code/devsync/` 內容必須先完整轉移到 vendored 位置才能刪。Migration Task 1 完成後 Task X 才能刪。

---

## Architecture

### File layout

```
ai_system/
├── sync.sh                          ← 修改：devsync_post_restore 改 invoke bootstrap.sh
├── CLAUDE.md
├── claude-skills/                   ← 既有
└── devsync/
    ├── config.toml                  ← 既有
    ├── ssh-config-snippet.txt       ← 既有
    ├── README.md                    ← 既有，更新一段「現在一指令裝完」
    ├── bootstrap.sh                 ← 【新】
    └── src/                          ← 【新】vendored devsync v0.1.0
        ├── pyproject.toml
        ├── src/devsync/
        │   ├── __init__.py
        │   ├── cli.py
        │   ├── config.py
        │   ├── errors.py
        │   ├── mutagen.py
        │   ├── repo.py
        │   ├── server.py
        │   ├── session.py
        │   └── ui.py
        ├── tests/
        ├── README.md
        └── docs/superpowers/specs/2026-06-02-devsync-design.md
```

### Data flow

```
                User runs ./sync.sh restore
                            │
                            ▼
    ┌──────────────────────────────────────────────────┐
    │ sync.sh::cmd_restore                              │
    │  ├─ rsync claude-skills → ~/.claude/skills/       │
    │  └─ sync_files restore   (incl. config.toml)      │
    │      └─ post_restore_hook "$@"                    │
    │          ├─ existing gstack node_modules check    │
    │          └─ devsync_post_restore "$@"             │
    │              └─ exec bootstrap.sh [--yes]         │
    └──────────────────────────────────────────────────┘
                            │
                            ▼
    ┌──────────────────────────────────────────────────┐
    │ ai_system/devsync/bootstrap.sh                    │
    │   Step 1: mutagen      (brew install + register) │
    │   Step 2: uv           (brew install if missing) │
    │   Step 3: devsync CLI  (uv tool install -e src)  │
    │   Step 4: SSH key      (ssh-keygen if missing)   │
    │   Step 5: ssh config   (append if no dl01 host)  │
    │   Step 6: key trust    (ssh-copy-id × 4)         │
    │   Step 7: verify       (devsync doctor)          │
    └──────────────────────────────────────────────────┘
```

### Single sources of authority

| Concern | Authority |
|---|---|
| devsync source code | `ai_system/devsync/src/` (vendored, ai_system git history) |
| Server list + remote_base | `ai_system/devsync/config.toml` → synced to `~/.config/devsync/config.toml` |
| SSH config blocks | `ai_system/devsync/ssh-config-snippet.txt` → appended to `~/.ssh/config` |
| Installer logic | `ai_system/devsync/bootstrap.sh` |
| Installed binary | `~/.local/bin/devsync` (uv tool install -e link → `ai_system/devsync/src`) |

---

## Detailed Design

### §5.1 `bootstrap.sh` skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
SNIPPET="$SCRIPT_DIR/ssh-config-snippet.txt"
SERVERS=(dl01 dl02 dl03 dl04)

AUTO=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && AUTO=1

# log helpers (colors honor isatty)
# confirm() helper that auto-Y if $AUTO=1

step_1_mutagen()      { ... }
step_2_uv()           { ... }
step_3_devsync_cli()  { ... }
step_4_ssh_key()      { ... }
step_5_ssh_config()   { ... }
step_6_key_trust()    { ... }
step_7_verify()       { ... }

main "$@"
```

### §5.2 Per-step contract

| Step | Detect (already done iff…) | Action if missing | Failure handling |
|---|---|---|---|
| 1 mutagen | `command -v mutagen` | `brew install mutagen-io/mutagen/mutagen` + `mutagen daemon register` | brew missing → exit 1 with brew.sh link |
| 2 uv | `command -v uv` | `brew install uv` | brew missing → exit 1 |
| 3 devsync CLI | `command -v devsync` succeeds AND `uv tool list 2>/dev/null` shows devsync's editable source equal to `$SRC_DIR` (resolved absolute path) | `uv tool install -e "$SRC_DIR" --force` | non-zero exit from uv → prompt "continue anyway?" |
| 4 SSH key | `[[ -f ~/.ssh/id_ed25519 ]]` | `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "$(whoami)@$(hostname -s) devsync"` | ssh-keygen non-zero → prompt |
| 5 ssh config | `grep -q "^Host dl01$" ~/.ssh/config 2>/dev/null` | `[[ -f ~/.ssh/config ]] \|\| touch ~/.ssh/config; cat "$SNIPPET" >> ~/.ssh/config; chmod 600 ~/.ssh/config` | grep error → treat as missing |
| 6 key trust | per-server: `ssh -o BatchMode=yes -o ConnectTimeout=3 $h true` exit 0 | for each failing: `ssh-copy-id $h` (interactive password) | unreachable (timeout, 255) → skip with "VPN?" hint; auth fail → real failure, prompt |
| 7 verify | (always runs) | `devsync doctor` | doctor errors → print + warn |

### §5.3 `sync.sh` change

Replace `devsync_post_restore`:

```bash
devsync_post_restore() {
  local bootstrap="$SCRIPT_DIR/devsync/bootstrap.sh"
  if [[ ! -x "$bootstrap" ]]; then
    warn "devsync/bootstrap.sh missing or not executable — skip"
    return
  fi
  info "Running devsync bootstrap..."
  if [[ " $* " =~ " --yes " ]]; then
    "$bootstrap" --yes
  else
    "$bootstrap"
  fi
}
```

And in `cmd_restore`, change `post_restore_hook` to forward args:

```bash
post_restore_hook "$@"
```

### §5.4 Migration order (Implementation only)

1. Vendor source (copy + verify pytest passes in new location)
2. Build bootstrap.sh framework (printable detection, no actions yet)
3. Wire step actions (install commands)
4. Wire step 6 (interactive) + step 7 (verify)
5. Update sync.sh + delete `~/Desktop/code/devsync/`
6. Commit + push ai_system

---

## Test Strategy

Bash installer; **no automated test framework**. Use manual verification:

1. **Idempotency check on current Mac**:
   - `./ai_system/devsync/bootstrap.sh` — every step should ✓ skip (everything's already installed). 0 prompts.
   - Re-run after `uv tool uninstall devsync` — Step 3 should reinstall.
2. **Each step independently**:
   - `step_3_devsync_cli` after `uv tool uninstall devsync` → reinstalls + binary at right path.
   - `step_5_ssh_config` after backing up `~/.ssh/config` and emptying it → appends snippet, `chmod 600`.
3. **End-to-end check**: `pytest -q` from `ai_system/devsync/src/` still passes 67 tests.
4. **Fresh-Mac scenario**: skip until you next install on a new Mac. Document the expected flow in README.

### Smoke checklist (manual)

```
[ ] cd ai_system && ./sync.sh restore (re-run on current Mac → no prompts)
[ ] devsync doctor → 4/4 reachable
[ ] pytest -q in ai_system/devsync/src/ → 67 passed
[ ] which devsync → ~/.local/bin/devsync
[ ] (uv tool list | grep devsync) → points at ai_system/devsync/src
[ ] ~/.config/devsync/config.toml matches ai_system/devsync/config.toml
[ ] ~/Desktop/code/devsync/ is gone
```

---

## Acceptance Criteria

### AC-001 — Vendor preserves devsync v0.1.0 behavior

- **Given** `~/Desktop/code/devsync/` at commit `7f785aa` (v0.1.0)
- **When** the source is copied to `ai_system/devsync/src/`
- **Then** `pytest -q` from the new directory passes all 67 tests.

### AC-002 — `bootstrap.sh` runs to ✓ on a fully-installed Mac

- **Given** mutagen, uv, devsync are already installed; SSH key + config in place; VPN connected
- **When** `./ai_system/devsync/bootstrap.sh` runs (no `--yes`)
- **Then** all 7 steps print ✓ with zero `[Y/n]` prompts; exit 0.

### AC-003 — Step 3 forces devsync to point at vendored source

- **Given** `devsync` was previously installed from `~/Desktop/code/devsync/`
- **When** `step_3_devsync_cli` runs
- **Then** `uv tool list | grep devsync` shows `Edit: /Users/.../ai_system/devsync/src` and `which devsync` resolves successfully.

### AC-004 — Step 6 handles VPN-down gracefully

- **Given** VPN is disconnected (dl01..dl04 unreachable)
- **When** `step_6_key_trust` runs
- **Then** each server is reported as "unreachable (VPN?)"; the step ends with warn, does **not** abort bootstrap, and Step 7 still runs.

### AC-005 — `sync.sh restore` invokes bootstrap automatically

- **Given** a fresh clone of `ai_system` on a new Mac
- **When** the user runs `./sync.sh restore`
- **Then** after file sync completes, `bootstrap.sh` runs through Steps 1–7 (with `[Y/n]` prompts on missing items + 4 password prompts on Step 6).

### AC-006 — `--yes` flag propagates through

- **Given** `./sync.sh restore --yes` is run
- **When** `bootstrap.sh` is invoked
- **Then** `bootstrap.sh` runs with `--yes` (no `[Y/n]` prompts; ssh-copy-id still prompts for passwords).

### AC-007 — Old devsync directory removed

- **Given** vendor + verification complete
- **When** the migration task deletes `~/Desktop/code/devsync/`
- **Then** `ls ~/Desktop/code/devsync` returns "No such file"; `devsync --version` still prints `0.1.0` (because Step 3 reinstalled from vendored source).

### AC-008 — Idempotent re-run

- **Given** bootstrap has been run once successfully
- **When** `./bootstrap.sh` runs again
- **Then** every step detects "already done" and prints ✓ without prompting; exit 0.

### AC-009 — README updated

- **Given** the migration is done
- **When** the user reads `ai_system/devsync/README.md`
- **Then** the manual install instructions are replaced by "Run `./sync.sh restore` (or `./bootstrap.sh` directly); only your 4 server passwords are needed."

### AC-010 — claudecode-discord still works

- **Given** vendor + delete complete
- **When** Discord user runs `/devsync doctor`
- **Then** bot replies with the 4-server table (the bot spawns `devsync` from PATH, no path dependency).

---

## Implementation Roadmap

| # | Milestone | Verifies AC |
|---|---|---|
| M1 | Vendor source: `cp -r` + `pytest -q` 67 pass + `uv tool install -e ai_system/devsync/src --force` | AC-001, AC-003 |
| M2 | `bootstrap.sh` framework: 7-step skeleton + idempotent state detection + log helpers | AC-002 (steps print, no action) |
| M3 | Wire install actions: Step 1 (mutagen), Step 2 (uv), Step 3 (devsync), Step 4 (sshkey), Step 5 (sshconfig) | AC-002, AC-008 |
| M4 | Step 6 (key trust) + Step 7 (verify) + `--yes` flag | AC-004, AC-006 |
| M5 | sync.sh wires `post_restore_hook → bootstrap.sh`; delete `~/Desktop/code/devsync/`; README update; commit + push | AC-005, AC-007, AC-009, AC-010 |

---

## Out of Scope (v0.1)

- ❌ Linux / WSL / Windows support
- ❌ Bash unit test framework (bats / shunit2)
- ❌ Automated provisioning (Ansible / chef / puppet)
- ❌ Rollback / uninstall script
- ❌ Multi-version pin (vendored src is the current state; no `v0.1.x` branches)
- ❌ GitHub Actions CI for bootstrap.sh
- ❌ Publishing devsync to PyPI / Homebrew tap
- ❌ Devsync versioning beyond v0.1.0 (re-tag if you bump)

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `uv tool install -e` paths are absolute; moving `ai_system` directory breaks the link | Document `~/Desktop/code/ai_system` as expected location in README. If moved, re-run `bootstrap.sh` |
| `~/Desktop/code/devsync/` deleted before vendor verified | M1 task explicitly tests `pytest -q` in new location *before* M5 deletes the old one |
| Step 6 ssh-copy-id silently fails because hostkey accepted but auth method differs | `ssh -o BatchMode=yes ... true` after copy-id confirms; on failure, prompt user manually |
| `brew install uv` not available (older Homebrew) | Step 2 fallback: print `curl -LsSf https://astral.sh/uv/install.sh \| sh` and exit; user runs once and re-invokes |
| User runs `bootstrap.sh` from an unexpected cwd | `SCRIPT_DIR` is computed from `$BASH_SOURCE`, robust to cwd |
| `~/.ssh/config` has dl01 alias but with different `HostName` / `User` | Step 5 only checks `Host dl01` line presence; existing user-tuned entries preserved (won't re-append) |

---

## Open Questions

None at brainstorm completion. All decisions closed during §1–§5.
