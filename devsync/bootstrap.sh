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
    if [[ -z "$installed_at" && -f "$HOME/.local/share/uv/tools/devsync/uv-receipt.toml" ]]; then
      installed_at=$(awk -F'editable = "' '/editable =/ { split($2, a, "\""); print a[1]; exit }' "$HOME/.local/share/uv/tools/devsync/uv-receipt.toml")
    fi
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
