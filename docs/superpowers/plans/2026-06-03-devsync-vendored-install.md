# Vendored devsync + One-Command Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor `~/Desktop/code/devsync/` into `ai_system/devsync/src/` and add a 7-step idempotent `bootstrap.sh` that `sync.sh restore` invokes — so installing devsync on a fresh Mac becomes a single command plus 4 server passwords.

**Architecture:** Pure bash for the installer (no test framework, idempotent state detection). Vendored Python source untouched (still uses `uv tool install -e`). `sync.sh` gets a 3-line edit to forward args + invoke `bootstrap.sh`. Migration is one-direction: vendor, verify, delete the old `~/Desktop/code/devsync/`.

**Tech Stack:** Bash 4+, `brew`, `uv`, `ssh`/`ssh-copy-id`, `mutagen`, `rsync`. Python 3.11+ (only for running devsync itself, not bootstrap).

**Spec:** `docs/superpowers/specs/2026-06-03-devsync-vendored-install-design.md` (REQ-NNN / CON-NNN / AC-NNN IDs referenced).

**Working directory throughout:** `/Users/leric/Desktop/code/ai_system`

---

## File Map (created/modified)

| File | Action | Tasks |
|---|---|---|
| `devsync/src/` | CREATE (vendored copy) | Task 1 |
| `devsync/bootstrap.sh` | CREATE | Tasks 2, 3, 4, 5, 6, 7 |
| `sync.sh` | MODIFY (devsync_post_restore + post_restore_hook forwards `$@`) | Task 8 |
| `devsync/README.md` | MODIFY (point at bootstrap.sh) | Task 9 |
| `~/Desktop/code/devsync/` | DELETE | Task 9 |

---

## Task 1: Vendor devsync source into `ai_system/devsync/src/`

**Files:**
- Create: `/Users/leric/Desktop/code/ai_system/devsync/src/` (full source tree copy)

- [ ] **Step 1: Copy source tree excluding env/build artifacts**

```bash
cd /Users/leric/Desktop/code/ai_system
mkdir -p devsync/src

rsync -av \
  --exclude='.git' \
  --exclude='.venv' \
  --exclude='.pytest_cache' \
  --exclude='.ruff_cache' \
  --exclude='dist' \
  --exclude='build' \
  --exclude='*.egg-info' \
  --exclude='__pycache__' \
  /Users/leric/Desktop/code/devsync/ \
  devsync/src/
```

Expected: ~30 files copied (no `.git`, no `.venv`, no caches).

- [ ] **Step 2: Verify file list**

```bash
ls devsync/src/
ls devsync/src/src/devsync/
ls devsync/src/tests/
```

Expected:
- Top level: `pyproject.toml`, `README.md`, `docs/`, `src/`, `tests/`, `.gitignore`
- `src/devsync/`: 8 .py files (__init__, cli, config, errors, mutagen, repo, server, session, ui)
- `tests/`: 15+ test files

- [ ] **Step 3: Install fresh in vendored location**

```bash
# Replace the existing install (which points at ~/Desktop/code/devsync)
uv tool install -e /Users/leric/Desktop/code/ai_system/devsync/src --force
which devsync
devsync --version
```

Expected:
- `which devsync` prints `/Users/leric/.local/bin/devsync`
- `devsync --version` prints `0.1.0`

- [ ] **Step 4: Verify vendored source is what uv now points at**

```bash
uv tool list 2>&1 | grep -A1 "^devsync"
```

Expected output contains `/Users/leric/Desktop/code/ai_system/devsync/src` (the Edit:/source path).

- [ ] **Step 5: Run the full test suite from the new location**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
uv venv --quiet 2>/dev/null || true
uv pip install -e ".[dev]" --quiet 2>&1 | tail -3
.venv/bin/pytest -q
```

Expected: `67 passed in <1s` (matches the original repo's test count). **This satisfies AC-001.**

- [ ] **Step 6: Live smoke `devsync doctor` (VPN must be up; skip if down)**

```bash
~/bin/vpn-status.sh
devsync doctor
```

Expected: 4-server reachable table OR VPN down (acceptable to defer).

- [ ] **Step 7: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/src/
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync): vendor v0.1.0 source into ai_system/devsync/src

Copy of ~/Desktop/code/devsync/ at v0.1.0 (commit 7f785aa), excluding
.git/.venv/caches. 67 tests pass from the new location. uv tool install
-e --force updates ~/.local/bin/devsync to point at the vendored source."
```

---

## Task 2: `bootstrap.sh` skeleton (log helpers + step framework)

**Files:**
- Create: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Create executable skeleton**

```bash
cat > /Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh << 'BOOTSTRAP_EOF'
#!/usr/bin/env bash
#
# bootstrap.sh — Idempotent installer for devsync on a fresh macOS.
# Re-running on a fully-installed Mac prints all ✓ with no prompts.
#
# Usage:
#   ./bootstrap.sh           # interactive ([Y/n] for each missing piece)
#   ./bootstrap.sh --yes     # auto-confirm everything except ssh-copy-id passwords
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
SNIPPET="$SCRIPT_DIR/ssh-config-snippet.txt"
SERVERS=(dl01 dl02 dl03 dl04)

AUTO=0
case "${1:-}" in
  --yes|-y) AUTO=1 ;;
  --help|-h)
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  "") ;;
  *) echo "unknown arg: $1 (try --help)" >&2; exit 2 ;;
esac

# ---------- Colors ----------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=''; C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''
fi

log()  { printf "%s\n" "$*"; }
info() { printf "%b\n" "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { printf "%b\n" "  ${C_GREEN}✓${C_RESET} $*"; }
warn() { printf "%b\n" "  ${C_YELLOW}!${C_RESET} $*"; }
err()  { printf "%b\n" "  ${C_RED}✗${C_RESET} $*" >&2; }

# Returns 0 if user said yes (or AUTO=1), 1 otherwise.
confirm() {
  local prompt="$1"
  if [[ $AUTO -eq 1 ]]; then
    log "  ? $prompt [Y/n] (auto-yes)"
    return 0
  fi
  local reply
  read -r -p "  ? $prompt [Y/n] " reply
  case "$reply" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# After a fatal-ish failure, ask whether to keep walking through remaining steps.
# In AUTO mode, propagate failure (exit 1).
continue_on_failure() {
  if [[ $AUTO -eq 1 ]]; then
    err "Aborting (--yes mode does not skip failures)."
    exit 1
  fi
  local reply
  read -r -p "  ? Continue to next step anyway? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) exit 1 ;;
  esac
}

# Step stubs — actions wired in later tasks.
step_1_mutagen()     { info "Step 1/7: mutagen"; ok "(stub)"; }
step_2_uv()          { info "Step 2/7: uv"; ok "(stub)"; }
step_3_devsync_cli() { info "Step 3/7: devsync CLI"; ok "(stub)"; }
step_4_ssh_key()     { info "Step 4/7: SSH key"; ok "(stub)"; }
step_5_ssh_config()  { info "Step 5/7: ssh config"; ok "(stub)"; }
step_6_key_trust()   { info "Step 6/7: key trust"; ok "(stub)"; }
step_7_verify()      { info "Step 7/7: verify"; ok "(stub)"; }

main() {
  info "devsync bootstrap"
  log  "  vendored src: $SRC_DIR"
  log  "  --yes mode:   $([[ $AUTO -eq 1 ]] && echo on || echo off)"
  log  ""

  step_1_mutagen
  step_2_uv
  step_3_devsync_cli
  step_4_ssh_key
  step_5_ssh_config
  step_6_key_trust
  step_7_verify

  log ""
  info "Bootstrap complete."
}

main "$@"
BOOTSTRAP_EOF

chmod +x /Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh
```

- [ ] **Step 2: Smoke test the skeleton**

```bash
cd /Users/leric/Desktop/code/ai_system
./devsync/bootstrap.sh
```

Expected output: header + 7 step lines each printing `(stub)`, then "Bootstrap complete." Exit 0.

- [ ] **Step 3: Smoke `--yes` and `--help`**

```bash
./devsync/bootstrap.sh --yes
./devsync/bootstrap.sh --help
./devsync/bootstrap.sh --bogus  # should exit 2
```

Expected:
- `--yes` runs through stubs without prompting (no prompts happen yet since stubs do nothing)
- `--help` prints the Usage block from the file header
- `--bogus` prints "unknown arg" and exits 2

- [ ] **Step 4: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync): bootstrap.sh skeleton with log helpers and 7-step framework"
```

---

## Task 3: Wire Step 1 (mutagen) and Step 2 (uv)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Replace `step_1_mutagen` stub**

Open `bootstrap.sh` and replace the entire `step_1_mutagen()` line with:

```bash
step_1_mutagen() {
  info "Step 1/7: mutagen"
  if command -v mutagen >/dev/null 2>&1; then
    ok "mutagen present: $(mutagen --version 2>/dev/null | head -1)"
    # Daemon is benign to start repeatedly; ignore errors (e.g., already running)
    mutagen daemon start >/dev/null 2>&1 || true
    return 0
  fi
  warn "mutagen not installed."
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew is required to install mutagen. See https://brew.sh"
    continue_on_failure
    return 0
  fi
  if confirm "Install mutagen via 'brew install mutagen-io/mutagen/mutagen'?"; then
    if brew install mutagen-io/mutagen/mutagen; then
      ok "mutagen installed"
      if confirm "Register mutagen daemon to auto-start on login?"; then
        mutagen daemon register >/dev/null 2>&1 && ok "daemon registered" || warn "daemon register returned non-zero (may already be registered)"
      fi
      mutagen daemon start >/dev/null 2>&1 || true
    else
      err "brew install failed"
      continue_on_failure
    fi
  else
    warn "Skipped — devsync needs mutagen to work."
  fi
}
```

- [ ] **Step 2: Replace `step_2_uv` stub**

```bash
step_2_uv() {
  info "Step 2/7: uv"
  if command -v uv >/dev/null 2>&1; then
    ok "uv present: $(uv --version 2>/dev/null)"
    return 0
  fi
  warn "uv not installed."
  if ! command -v brew >/dev/null 2>&1; then
    err "Install uv manually: curl -LsSf https://astral.sh/uv/install.sh | sh"
    continue_on_failure
    return 0
  fi
  if confirm "Install uv via 'brew install uv'?"; then
    if brew install uv; then
      ok "uv installed: $(uv --version 2>/dev/null)"
    else
      err "brew install uv failed"
      continue_on_failure
    fi
  else
    warn "Skipped — devsync CLI install will fail without uv."
  fi
}
```

- [ ] **Step 3: Smoke (current Mac already has both)**

```bash
./devsync/bootstrap.sh
```

Expected: Step 1 and Step 2 print ✓ (already installed), no prompts. Steps 3-7 remain stubs.

- [ ] **Step 4: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync/bootstrap): wire steps 1-2 (mutagen + uv install)"
```

---

## Task 4: Wire Step 3 (devsync CLI install, force when source path mismatches)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Replace `step_3_devsync_cli` stub**

```bash
step_3_devsync_cli() {
  info "Step 3/7: devsync CLI"

  # Resolve the expected source dir to an absolute, symlink-free path.
  local expected
  expected=$(cd "$SRC_DIR" && pwd -P 2>/dev/null) || expected="$SRC_DIR"

  local installed_at=""
  if command -v uv >/dev/null 2>&1; then
    # `uv tool list` shows "Edit: <path>" for editable installs. Find devsync's.
    installed_at=$(uv tool list 2>/dev/null | awk '
      /^devsync / { in_devsync = 1; next }
      in_devsync && /^Edit:/ { print $2; exit }
      /^[A-Za-z]/ && in_devsync { in_devsync = 0 }
    ')
  fi

  if [[ -n "$installed_at" ]]; then
    # Compare resolved paths (handles symlink differences)
    local installed_real
    installed_real=$(cd "$installed_at" && pwd -P 2>/dev/null) || installed_real="$installed_at"
    if [[ "$installed_real" == "$expected" ]]; then
      ok "devsync CLI installed and points at vendored src: $(devsync --version 2>/dev/null)"
      return 0
    else
      warn "devsync installed but points at: $installed_at"
      warn "  (we want: $expected)"
    fi
  else
    warn "devsync CLI not installed."
  fi

  if ! command -v uv >/dev/null 2>&1; then
    err "uv missing — cannot install devsync. Re-run Step 2 first."
    continue_on_failure
    return 0
  fi

  if confirm "Run 'uv tool install -e $SRC_DIR --force'?"; then
    if uv tool install -e "$SRC_DIR" --force; then
      ok "devsync installed: $(devsync --version 2>/dev/null)"
    else
      err "uv tool install failed"
      continue_on_failure
    fi
  else
    warn "Skipped."
  fi
}
```

- [ ] **Step 2: Smoke test (current Mac already has correct install)**

```bash
./devsync/bootstrap.sh
```

Expected: Step 3 prints `✓ devsync CLI installed and points at vendored src: 0.1.0` with no prompt.

- [ ] **Step 3: Smoke test the reinstall path (simulate mismatched source)**

```bash
# Temporarily uninstall to force the reinstall branch
uv tool uninstall devsync
./devsync/bootstrap.sh
# Expected: Step 3 prompts "Run uv tool install...?" then installs.

which devsync
devsync --version
```

Expected after reinstall:
- `which devsync` = `/Users/leric/.local/bin/devsync`
- `devsync --version` = `0.1.0`

**This satisfies AC-003.**

- [ ] **Step 4: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync/bootstrap): wire step 3 (devsync CLI install with source-path check)"
```

---

## Task 5: Wire Step 4 (SSH key) and Step 5 (ssh config)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Replace `step_4_ssh_key` stub**

```bash
step_4_ssh_key() {
  info "Step 4/7: SSH key"
  if [[ -f "$HOME/.ssh/id_ed25519" && -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    ok "~/.ssh/id_ed25519 already exists"
    return 0
  fi
  warn "no ed25519 key at ~/.ssh/id_ed25519"
  if confirm "Generate one now (no passphrase, comment=\"$(whoami)@$(hostname -s) devsync\")?"; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "$(whoami)@$(hostname -s) devsync"; then
      ok "ed25519 key generated"
    else
      err "ssh-keygen failed"
      continue_on_failure
    fi
  else
    warn "Skipped — Step 6 (key trust) will fail."
  fi
}
```

- [ ] **Step 2: Replace `step_5_ssh_config` stub**

```bash
step_5_ssh_config() {
  info "Step 5/7: ssh config"
  if [[ ! -f "$SNIPPET" ]]; then
    err "ssh-config-snippet.txt missing at $SNIPPET — Cannot proceed."
    continue_on_failure
    return 0
  fi
  # Ensure config file exists so grep+append work uniformly.
  if [[ ! -f "$HOME/.ssh/config" ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
  fi
  if grep -q "^Host dl01$" "$HOME/.ssh/config" 2>/dev/null; then
    ok "~/.ssh/config already has dl01..dl04 hosts"
    return 0
  fi
  warn "~/.ssh/config has no dl01 host block"
  if confirm "Append the dl01..dl04 host blocks from $SNIPPET?"; then
    cat "$SNIPPET" >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    ok "appended; chmod 600"
  else
    warn "Skipped — ssh dl0N hostnames won't resolve without /etc/hosts or config."
  fi
}
```

- [ ] **Step 3: Smoke test (current Mac already has both)**

```bash
./devsync/bootstrap.sh
```

Expected: Step 4 ✓ "already exists", Step 5 ✓ "already has dl01..dl04 hosts". No prompts.

- [ ] **Step 4: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync/bootstrap): wire steps 4-5 (SSH key + ssh config)"
```

---

## Task 6: Wire Step 6 (key trust via ssh-copy-id, VPN-tolerant)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Replace `step_6_key_trust` stub**

```bash
step_6_key_trust() {
  info "Step 6/7: server key trust"
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    err "no ed25519 key found — Step 4 should have generated one. Skipping."
    continue_on_failure
    return 0
  fi

  local reachable=()
  local need_copy=()
  local unreachable=()

  for h in "${SERVERS[@]}"; do
    # Probe: BatchMode rejects password prompts. ConnectTimeout caps the wait.
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
           "$h" true 2>/dev/null; then
      reachable+=("$h")
      continue
    fi
    # Distinguish "host unreachable" (no TCP) vs "key not trusted" (auth required).
    # ssh -v output is verbose; use a simple TCP check first.
    if ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
           -o PreferredAuthentications=none "$h" true 2>&1 | \
           grep -q "Permission denied"; then
      need_copy+=("$h")
    else
      unreachable+=("$h")
    fi
  done

  for h in "${reachable[@]}"; do ok "$h: key already trusted"; done

  for h in "${unreachable[@]}"; do
    warn "$h: unreachable (VPN down? wrong network?). Skipping."
  done

  if [[ ${#need_copy[@]} -gt 0 ]]; then
    log ""
    info "Need to push key to: ${need_copy[*]}"
    log "  Each prompt asks for that server's password (one-time per machine)."
    log ""
    for h in "${need_copy[@]}"; do
      if confirm "Run 'ssh-copy-id $h'?"; then
        if ssh-copy-id "$h"; then
          ok "$h: key pushed"
        else
          err "$h: ssh-copy-id failed"
          continue_on_failure
        fi
      else
        warn "$h: skipped"
      fi
    done
  fi
}
```

- [ ] **Step 2: Smoke test on current Mac (4/4 already trusted if VPN up)**

```bash
~/bin/vpn-status.sh
./devsync/bootstrap.sh
```

Expected (VPN up): Step 6 prints `✓ dl01: key already trusted` × 4.
Expected (VPN down): Step 6 prints `! dl0N: unreachable` × 4, no prompts, no abort.

**The VPN-down path satisfies AC-004.**

- [ ] **Step 3: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync/bootstrap): wire step 6 (key trust, VPN-tolerant)"
```

---

## Task 7: Wire Step 7 (verify via `devsync doctor`)

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/bootstrap.sh`

- [ ] **Step 1: Replace `step_7_verify` stub**

```bash
step_7_verify() {
  info "Step 7/7: verify"
  if ! command -v devsync >/dev/null 2>&1; then
    err "devsync not on PATH — earlier steps failed. Skipping verify."
    return 0
  fi
  log ""
  if devsync doctor; then
    log ""
    ok "devsync doctor passed — bootstrap complete!"
  else
    warn "devsync doctor returned non-zero (some servers may be unreachable)."
    log "  Try 'devsync doctor' manually after fixing VPN / SSH issues."
  fi
}
```

- [ ] **Step 2: Smoke test full flow**

```bash
./devsync/bootstrap.sh
```

Expected (VPN up): Step 7 prints the 4-server table from `devsync doctor`, ends with `✓ devsync doctor passed — bootstrap complete!`. **Confirms AC-002 + AC-008.**

- [ ] **Step 3: `--yes` smoke**

```bash
./devsync/bootstrap.sh --yes
```

Expected: same output, no prompts (everything already done).

- [ ] **Step 4: Commit**

```bash
git add devsync/bootstrap.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(devsync/bootstrap): wire step 7 (verify via devsync doctor)"
```

---

## Task 8: `sync.sh` invokes `bootstrap.sh` + forwards `--yes`

**Files:**
- Modify: `/Users/leric/Desktop/code/ai_system/sync.sh`

- [ ] **Step 1: Replace `devsync_post_restore`**

Open `sync.sh` and find the current `devsync_post_restore()` function (added in commit `eec8cbf`). Replace its entire body with:

```bash
devsync_post_restore() {
  local bootstrap="$SCRIPT_DIR/devsync/bootstrap.sh"
  if [[ ! -x "$bootstrap" ]]; then
    warn "devsync/bootstrap.sh missing or not executable — skip"
    return
  fi
  info "Running devsync bootstrap..."
  log ""
  if [[ " $* " =~ " --yes " ]]; then
    "$bootstrap" --yes
  else
    "$bootstrap"
  fi
}
```

- [ ] **Step 2: Forward `$@` from `cmd_restore` to `post_restore_hook`**

In `sync.sh`, find this block inside `cmd_restore()`:

```bash
  if [[ ! " $* " =~ " --dry-run " ]]; then
    post_restore_hook
  fi
```

Change the `post_restore_hook` call to forward args:

```bash
  if [[ ! " $* " =~ " --dry-run " ]]; then
    post_restore_hook "$@"
  fi
```

- [ ] **Step 3: Forward `$@` from `post_restore_hook` to `devsync_post_restore`**

In `sync.sh`, find the `post_restore_hook()` function. At the bottom of its body the existing code is:

```bash
  devsync_post_restore
}
```

Change to:

```bash
  devsync_post_restore "$@"
}
```

- [ ] **Step 4: Syntax check**

```bash
bash -n /Users/leric/Desktop/code/ai_system/sync.sh && echo "sync.sh OK"
```

Expected: `sync.sh OK`.

- [ ] **Step 5: Dry-run smoke (no actual restore)**

```bash
cd /Users/leric/Desktop/code/ai_system
./sync.sh restore --dry-run --yes
```

Expected: prints `Restore complete` (rsync dry-run mode); does NOT invoke bootstrap (the `--dry-run` gate skips `post_restore_hook`). Working tree untouched.

- [ ] **Step 6: Real restore smoke (current Mac — everything already in place)**

```bash
./sync.sh restore --yes
```

Expected: rsync runs (no-op since files identical); config files synced; `devsync_post_restore` invokes bootstrap.sh `--yes`; all 7 steps ✓; final `devsync doctor` 4/4 (VPN up) or 0/4 (VPN down). **This satisfies AC-005 + AC-006.**

- [ ] **Step 7: Commit**

```bash
git add sync.sh
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "feat(sync.sh): invoke devsync/bootstrap.sh from devsync_post_restore + forward --yes"
```

---

## Task 9: Delete old `~/Desktop/code/devsync/` + update README + final commit

**Files:**
- Delete: `/Users/leric/Desktop/code/devsync/`
- Modify: `/Users/leric/Desktop/code/ai_system/devsync/README.md`

- [ ] **Step 1: Final safety check before delete**

```bash
# Confirm the vendored install is what's on PATH (NOT the old location).
uv tool list 2>&1 | awk '/^devsync / {p=1; next} p && /^Edit:/ {print $2; exit}'
```

Expected output: `/Users/leric/Desktop/code/ai_system/devsync/src` (or its symlink-resolved equivalent).

If output points at `/Users/leric/Desktop/code/devsync/` → STOP. Re-run Task 1 Step 3 (`uv tool install -e ai_system/devsync/src --force`).

- [ ] **Step 2: Verify devsync still runs**

```bash
devsync --version
devsync doctor 2>&1 | head -3
```

Expected: `0.1.0` and the daemon-status line. If `devsync` exits with "No such file or directory" tied to the old path → STOP and fix Step 1 first.

- [ ] **Step 3: Delete the old directory**

```bash
rm -rf /Users/leric/Desktop/code/devsync
ls /Users/leric/Desktop/code/devsync 2>&1
```

Expected: `ls: ... No such file or directory` (or just nothing if `ls` is silent).

- [ ] **Step 4: Re-verify devsync still works after delete**

```bash
which devsync
devsync --version
devsync doctor 2>&1 | head -1
```

Expected: still finds `/Users/leric/.local/bin/devsync`, prints `0.1.0`. **Satisfies AC-007.**

- [ ] **Step 5: Update `ai_system/devsync/README.md` install section**

Open `/Users/leric/Desktop/code/ai_system/devsync/README.md`. Find the "Manual fallback" section header.

Replace the entire content from the top of the file up to (but not including) the line that starts with `## What's not in this repo` with:

```markdown
# devsync bootstrap

Static config + automated installer for the devsync CLI on a fresh Mac.
The Python source lives at `src/` (vendored from upstream v0.1.0). The
runtime config (`~/.config/devsync/config.toml`) is bidirectionally synced
by the parent `sync.sh`. The 7-step installer (`bootstrap.sh`) handles
the rest.

## One-command install on a new Mac

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore
# Walk through [Y/n] prompts (~5).
# Type each server's password once when ssh-copy-id runs (~4 prompts).
# Done.
```

You can also run the installer directly without `sync.sh`:

```bash
./devsync/bootstrap.sh         # interactive
./devsync/bootstrap.sh --yes   # auto-confirm everything except passwords
```

`bootstrap.sh` is idempotent — re-running on a fully-installed Mac prints
all ✓ with no prompts.

## Layout

| Path | What it is |
|---|---|
| `src/` | Vendored devsync v0.1.0 source. `uv tool install -e src` is what's on `~/.local/bin/devsync`. |
| `config.toml` | Runtime config, bidirectionally synced with `~/.config/devsync/config.toml`. |
| `ssh-config-snippet.txt` | Appended to `~/.ssh/config` if no `dl01` host block exists. |
| `bootstrap.sh` | 7-step installer (mutagen / uv / devsync / sshkey / sshconfig / keytrust / verify). |

## What `bootstrap.sh` does

1. **mutagen** — `brew install mutagen-io/mutagen/mutagen` if missing; register daemon for auto-start.
2. **uv** — `brew install uv` if missing.
3. **devsync CLI** — `uv tool install -e src --force` to ensure `~/.local/bin/devsync` points at the vendored source.
4. **SSH key** — `ssh-keygen -t ed25519` if `~/.ssh/id_ed25519` is missing.
5. **ssh config** — Append `ssh-config-snippet.txt` if `~/.ssh/config` has no `Host dl01` line.
6. **server key trust** — `ssh-copy-id dl0N` for each server not yet trusting your key (interactive password prompt, one per server).
7. **verify** — `devsync doctor` — should show all 4 servers reachable.

Every step first checks state and skips if already done. Re-running is safe.

```

(Leave the `## What's not in this repo` section and below untouched.)

- [ ] **Step 6: Verify README**

```bash
head -50 /Users/leric/Desktop/code/ai_system/devsync/README.md
```

Expected: "# devsync bootstrap" + "One-command install on a new Mac" section visible. **Satisfies AC-009.**

- [ ] **Step 7: Live smoke claudecode-discord still works**

```bash
# Check claudecode-discord can still find devsync (it spawns via PATH).
~/.local/bin/devsync --version
# Optional: smoke an actual claudecode-discord /devsync call by running the bot
# and trying `/devsync doctor` in Discord. This is the AC-010 check.
```

Expected: `0.1.0` printed. claudecode-discord's `/devsync` slash command is unchanged because it spawns `devsync` from PATH (location-independent). **Satisfies AC-010 at the code level; live Discord smoke is optional.**

- [ ] **Step 8: Commit + push**

```bash
cd /Users/leric/Desktop/code/ai_system
git add devsync/README.md
git -c user.email=a0919376604@gmail.com -c user.name=leric commit -m "docs(devsync): README — one-command install via sync.sh / bootstrap.sh

Migration of devsync v0.1.0 source from ~/Desktop/code/devsync/ to
ai_system/devsync/src/ is now complete. The old directory has been
removed; the only devsync source on disk is the vendored copy."
git push origin main
git log --oneline -5
```

Expected: push succeeds, top 5 commits show this task's commit + the 7 commits from Tasks 1-8.

---

## Task 10: Final integration smoke + run-plan-complete checkpoint

**Files:** none new

- [ ] **Step 1: Full re-run of `./sync.sh restore` on a fully-bootstrapped Mac**

```bash
cd /Users/leric/Desktop/code/ai_system
./sync.sh restore --yes
```

Expected:
- rsync runs (no-op or minor file diffs)
- bootstrap.sh runs through all 7 steps printing ✓
- Final line: `✓ devsync doctor passed — bootstrap complete!` (if VPN up)
- Exit 0
- No prompts (because of `--yes` and everything is already in place)

**This is the canonical AC-008 (idempotent re-run) verification.**

- [ ] **Step 2: Verify no orphan files**

```bash
ls /Users/leric/Desktop/code/devsync 2>&1                 # should be "No such file"
ls ~/.local/bin/devsync                                    # should exist
uv tool list 2>&1 | grep -A1 "^devsync"                    # Edit: ~/Desktop/code/ai_system/devsync/src
find /Users/leric/Desktop/code/ai_system/devsync -name '*.py' | head -5
ls /Users/leric/Desktop/code/ai_system/devsync/src/        # full vendored tree
```

Expected:
- old dir absent
- binary present
- uv tool pointed at vendored src
- python files exist under vendored src

- [ ] **Step 3: Run the vendored test suite one last time**

```bash
cd /Users/leric/Desktop/code/ai_system/devsync/src
.venv/bin/pytest -q
```

Expected: `67 passed in <1s`.

- [ ] **Step 4: Note completion + tag (optional)**

```bash
cd /Users/leric/Desktop/code/ai_system
git tag -a devsync-vendored-v1 -m "devsync vendored install workflow v1

ai_system/devsync/ now holds: src (vendored devsync v0.1.0), config.toml
(synced), ssh-config-snippet.txt, bootstrap.sh (7-step installer), README.

./sync.sh restore on a fresh Mac → 5 [Y/n] prompts + 4 ssh-copy-id
passwords → devsync doctor reports 4/4 reachable.

Acceptance criteria AC-001..AC-010 all satisfied per
docs/superpowers/specs/2026-06-03-devsync-vendored-install-design.md."
git tag --list | grep devsync
```

(Skip if you don't want a tag for this milestone — it's optional polish.)

---

## Out of Scope (deferred to future versions)

Per the spec §11:

- ❌ Linux / WSL / Windows support — bootstrap.sh is macOS-specific
- ❌ Bash unit test framework (bats / shunit2)
- ❌ Automated provisioning (Ansible / chef / puppet / etc.)
- ❌ Rollback / uninstall script
- ❌ Version pinning beyond v0.1.0 (vendored is current snapshot)
- ❌ Publishing devsync to PyPI / Homebrew tap
- ❌ GitHub Actions CI for bootstrap.sh

---

## Acceptance Criteria Coverage

| Spec AC | Verified by | Task(s) |
|---|---|---|
| AC-001 (vendor preserves v0.1.0) | Task 1 Step 5: `pytest -q` → 67 passed | 1 |
| AC-002 (bootstrap idempotent ✓ on installed Mac) | Task 7 Step 2 (full run all ✓) + Task 10 Step 1 | 7, 10 |
| AC-003 (Step 3 forces source path) | Task 4 Step 3 (uninstall → reinstall) | 4 |
| AC-004 (Step 6 VPN-down graceful) | Task 6 Step 2 (VPN-down path) | 6 |
| AC-005 (sync.sh invokes bootstrap) | Task 8 Step 6 (real restore) | 8 |
| AC-006 (`--yes` propagates) | Task 8 Step 6 (`./sync.sh restore --yes`) | 8 |
| AC-007 (old dir removed) | Task 9 Step 3-4 (`rm -rf` + verify devsync still runs) | 9 |
| AC-008 (idempotent re-run) | Task 7 Step 3 + Task 10 Step 1 (`./bootstrap.sh --yes` → all ✓) | 7, 10 |
| AC-009 (README updated) | Task 9 Step 5-6 | 9 |
| AC-010 (claudecode-discord still works) | Task 9 Step 7 (`devsync --version` after migration) | 9 |
