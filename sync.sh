#!/usr/bin/env bash
#
# sync.sh — Bidirectional sync for Claude skills
#
# Usage:
#   ./sync.sh backup            # ~/.claude/skills/  ->  ./claude-skills/
#   ./sync.sh restore           # ./claude-skills/   ->  ~/.claude/skills/
#   ./sync.sh status            # show diff summary between the two
#   ./sync.sh backup --dry-run  # preview without copying
#

set -euo pipefail

# ---------- Config ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$SCRIPT_DIR/claude-skills"
CLAUDE_DIR="$HOME/.claude/skills"

EXCLUDES=(
  --exclude='node_modules'
  --exclude='.git'
  --exclude='dist'
  --exclude='build'
  --exclude='.DS_Store'
  --exclude='*.log'
  --exclude='bin/'
  --exclude='.cache'
  --exclude='.next'
  --exclude='__pycache__'
)

# ---------- Colors ----------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=''; C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''
fi

log()  { printf "%s\n" "$*"; }
info() { printf "%b\n" "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { printf "%b\n" "${C_GREEN}✓${C_RESET} $*"; }
warn() { printf "%b\n" "${C_YELLOW}!${C_RESET} $*"; }
err()  { printf "%b\n" "${C_RED}✗${C_RESET} $*" >&2; }

# ---------- Helpers ----------
confirm() {
  local prompt="$1"
  read -r -p "$(printf "%b" "${C_YELLOW}?${C_RESET} ${prompt} [y/N] ")" reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    err "Directory does not exist: $dir"
    exit 1
  fi
}

post_restore_hook() {
  # Re-install npm deps for skills that need them
  local gstack="$CLAUDE_DIR/gstack"
  if [[ -f "$gstack/package.json" ]] && [[ ! -d "$gstack/node_modules" ]]; then
    warn "gstack has no node_modules"
    if confirm "Run 'npm install' in $gstack now?"; then
      ( cd "$gstack" && npm install ) && ok "gstack npm install complete"
    else
      warn "Skipped. Run manually later: cd $gstack && npm install"
    fi
  fi
}

# ---------- Commands ----------
cmd_backup() {
  ensure_dir "$CLAUDE_DIR"
  mkdir -p "$LOCAL_DIR"
  info "Backup: $CLAUDE_DIR  ->  $LOCAL_DIR"
  # -L: follow symlinks and copy the actual target files (so the repo is
  #     portable across machines — local symlinks point to absolute paths
  #     like ~/.claude/plugins/... that don't exist on other machines).
  rsync -avL --delete "${EXCLUDES[@]}" "$@" "$CLAUDE_DIR/" "$LOCAL_DIR/"
  ok "Backup complete ($(du -sh "$LOCAL_DIR" | awk '{print $1}'))"
}

cmd_restore() {
  ensure_dir "$LOCAL_DIR"
  mkdir -p "$CLAUDE_DIR"
  info "Restore: $LOCAL_DIR  ->  $CLAUDE_DIR"
  warn "This will OVERWRITE files in $CLAUDE_DIR (preserves node_modules, bin/, etc.)"
  if [[ ! " $* " =~ " --dry-run " ]] && [[ ! " $* " =~ " --yes " ]]; then
    confirm "Continue?" || { log "Aborted."; exit 0; }
  fi
  # Note: no --delete here so we don't nuke node_modules/bin/ on the target
  rsync -av "${EXCLUDES[@]}" "$@" "$LOCAL_DIR/" "$CLAUDE_DIR/"
  ok "Restore complete"
  if [[ ! " $* " =~ " --dry-run " ]]; then
    post_restore_hook
  fi
}

cmd_status() {
  ensure_dir "$LOCAL_DIR"
  ensure_dir "$CLAUDE_DIR"
  info "Diff summary (excludes node_modules, bin/, etc.)"
  log ""
  log "${C_BOLD}Files only in ~/.claude/skills/ (would be backed up):${C_RESET}"
  rsync -avn --delete "${EXCLUDES[@]}" "$CLAUDE_DIR/" "$LOCAL_DIR/" \
    | grep -E '^(>|<|\*deleting)' || log "  (none)"
  log ""
  log "${C_BOLD}Sizes:${C_RESET}"
  log "  local:   $(du -sh "$LOCAL_DIR"  2>/dev/null | awk '{print $1}')  $LOCAL_DIR"
  log "  source:  $(du -sh "$CLAUDE_DIR" 2>/dev/null | awk '{print $1}')  $CLAUDE_DIR"
}

usage() {
  cat <<EOF
${C_BOLD}sync.sh${C_RESET} — Bidirectional sync for Claude skills

${C_BOLD}Usage:${C_RESET}
  $(basename "$0") backup  [--dry-run]         Push ~/.claude/skills -> ./claude-skills
  $(basename "$0") restore [--dry-run] [--yes] Pull ./claude-skills  -> ~/.claude/skills
  $(basename "$0") status                      Show what's different

${C_BOLD}Notes:${C_RESET}
  • Excludes node_modules, bin/, dist, build, .git, *.log, .DS_Store, .cache
  • 'backup' uses --delete (mirrors source); 'restore' does NOT (keeps local node_modules)
  • After 'restore', will offer to run 'npm install' in skills that need it (e.g. gstack)
EOF
}

# ---------- Main ----------
cmd="${1:-}"; shift || true
case "$cmd" in
  backup)  cmd_backup  "$@" ;;
  restore) cmd_restore "$@" ;;
  status)  cmd_status  "$@" ;;
  ""|-h|--help|help) usage ;;
  *) err "Unknown command: $cmd"; usage; exit 1 ;;
esac
