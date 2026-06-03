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

# Single-file syncs: source -> repo path
declare -a SYNC_FILES=(
  "$HOME/.claude/CLAUDE.md::$SCRIPT_DIR/CLAUDE.md"
  "$HOME/.config/devsync/config.toml::$SCRIPT_DIR/devsync/config.toml"
)

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

  devsync_post_restore
}

devsync_post_restore() {
  # Verify devsync is bootstrappable on this machine.
  # config.toml is already in place (sync_files restore put it at
  # ~/.config/devsync/config.toml). Walk the rest of the chain and report
  # exactly what's missing. Each step is independent — the user can do them
  # in any order. Intentionally non-interactive: ssh-copy-id needs a password
  # prompt and "uv tool install" wants the user to pick a clone location;
  # we just instruct.

  info "devsync bootstrap check"

  local snippet="$SCRIPT_DIR/devsync/ssh-config-snippet.txt"
  local missing=0

  # 1. mutagen
  if command -v mutagen >/dev/null 2>&1; then
    ok "mutagen: $(mutagen version 2>/dev/null | head -1)"
    mutagen daemon start >/dev/null 2>&1 || true
  else
    warn "mutagen not installed — brew install mutagen-io/mutagen/mutagen"
    missing=$((missing+1))
  fi

  # 2. SSH key
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    ok "ssh key: ~/.ssh/id_ed25519"
  else
    warn "no SSH key — ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N \"\" -C \"$(whoami)@$(hostname -s) devsync\""
    missing=$((missing+1))
  fi

  # 3. ~/.ssh/config has dl01..dl04?
  if grep -q "^Host dl01$" "$HOME/.ssh/config" 2>/dev/null; then
    ok "ssh config: dl01..dl04 hosts present"
  else
    warn "~/.ssh/config has no dl01 host. Append the snippet:"
    log "    cat $snippet >> ~/.ssh/config && chmod 600 ~/.ssh/config"
    missing=$((missing+1))
  fi

  # 4. Passwordless SSH to each server (probe)
  local unreachable=()
  for h in dl01 dl02 dl03 dl04; do
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "$h" true 2>/dev/null; then
      :  # ok
    else
      unreachable+=("$h")
    fi
  done
  if [[ ${#unreachable[@]} -eq 0 ]]; then
    ok "ssh: 4/4 servers reachable without password"
  else
    warn "ssh probe failed for: ${unreachable[*]}"
    warn "  → If VPN is down: connect first, retry"
    warn "  → If first time on this machine: ssh-copy-id <host> per server"
    # Don't count as missing — VPN may simply be down right now
  fi

  # 5. devsync CLI
  if command -v devsync >/dev/null 2>&1; then
    ok "devsync CLI: $(devsync --version 2>/dev/null)"
  else
    warn "devsync CLI not installed. Clone and install:"
    log "    git clone git@github.com:a0919376604/devsync.git ~/Desktop/code/devsync"
    log "    cd ~/Desktop/code/devsync && uv tool install -e ."
    missing=$((missing+1))
  fi

  # 6. config.toml — should already be there because sync_files restore ran
  if [[ -f "$HOME/.config/devsync/config.toml" ]]; then
    ok "config: ~/.config/devsync/config.toml"
  else
    err "config: ~/.config/devsync/config.toml MISSING — sync may have failed"
    missing=$((missing+1))
  fi

  if [[ $missing -eq 0 ]] && [[ ${#unreachable[@]} -eq 0 ]]; then
    ok "devsync bootstrap complete — try: devsync doctor"
  else
    info "devsync bootstrap: $missing item(s) need manual install; see README.md in devsync/"
  fi
}

# ---------- Commands ----------
sync_files() {
  # direction: "backup" (src->dst) or "restore" (dst->src)
  local direction="$1"; shift
  local extra_flags=("${@:-}")
  for entry in "${SYNC_FILES[@]}"; do
    local src="${entry%%::*}"
    local dst="${entry##*::}"
    if [[ "$direction" == "backup" ]]; then
      [[ -f "$src" ]] || { warn "Skip: $src (not found)"; continue; }
      rsync -av ${extra_flags[*]:-} "$src" "$dst"
    else
      [[ -f "$dst" ]] || { warn "Skip: $dst (not found)"; continue; }
      rsync -av ${extra_flags[*]:-} "$dst" "$src"
    fi
  done
}

cmd_backup() {
  ensure_dir "$CLAUDE_DIR"
  mkdir -p "$LOCAL_DIR"
  info "Backup: $CLAUDE_DIR  ->  $LOCAL_DIR"
  # -L: follow symlinks and copy the actual target files (so the repo is
  #     portable across machines — local symlinks point to absolute paths
  #     like ~/.claude/plugins/... that don't exist on other machines).
  rsync -avL --delete "${EXCLUDES[@]}" "$@" "$CLAUDE_DIR/" "$LOCAL_DIR/"
  info "Backup config files"
  sync_files backup "$@"
  ok "Backup complete ($(du -sh "$LOCAL_DIR" | awk '{print $1}'))"
}

cmd_restore() {
  ensure_dir "$LOCAL_DIR"
  mkdir -p "$CLAUDE_DIR"
  info "Restore: $LOCAL_DIR  ->  $CLAUDE_DIR"
  warn "This will OVERWRITE files in $CLAUDE_DIR and ~/.claude/CLAUDE.md (preserves node_modules, bin/, etc.)"
  if [[ ! " $* " =~ " --dry-run " ]] && [[ ! " $* " =~ " --yes " ]]; then
    confirm "Continue?" || { log "Aborted."; exit 0; }
  fi
  # Note: no --delete here so we don't nuke node_modules/bin/ on the target
  rsync -av "${EXCLUDES[@]}" "$@" "$LOCAL_DIR/" "$CLAUDE_DIR/"
  info "Restore config files"
  sync_files restore "$@"
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
