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
