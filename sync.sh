#!/usr/bin/env bash
# sync.sh — install ai_system on this machine, and back up the two config files it keeps.
#
# ai_system is ship-workflow's home (R-004). `restore` links its three skills and
# ship-workflow's five commands into ~/.claude, so every session runs this checkout;
# `backup` copies the global CLAUDE.md and the devsync config into the repo.
#
# It used to mirror all of ~/.claude/skills with rsync. That mirror drifted: its
# restore would have reinstalled 40 removed skills, overwritten a newer global
# CLAUDE.md with an old copy, and replaced the ship-workflow symlink with a copy.
#
# Usage:
#   ./sync.sh restore [--yes] [--dry-run]   links + config files + devsync bootstrap
#   ./sync.sh backup [--dry-run]             ~/.claude/CLAUDE.md, devsync config -> repo
#   ./sync.sh status                         link and config state; exit 1 if a link is wrong
#
# Tests set AI_SYSTEM_SKIP_DEVSYNC=1 to skip the devsync bootstrap.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
DISPLACED="$CLAUDE_HOME/.ai_system-displaced"
SKILLS=(ship-workflow run-plan code-review-skill)
COMMANDS=(ship-next ship-compound ship-idea ship-land ship-init)
# live::repo
CONFIG_FILES=(
  "$HOME/.claude/CLAUDE.md::$SCRIPT_DIR/config/claude/CLAUDE.md"
  "$HOME/.config/devsync/config.toml::$SCRIPT_DIR/devsync/config.toml"
)

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
confirm() {
  local reply
  read -r -p "$(printf "%b" "${C_YELLOW}?${C_RESET} $1 [y/N] ")" reply || return 1
  [[ "$reply" =~ ^[Yy]$ ]]
}

DRY=0
YES=0

# The links restore manages, as "link::target" lines.
links() {
  local s c
  for s in "${SKILLS[@]}"; do
    echo "$CLAUDE_HOME/skills/$s::$SCRIPT_DIR/claude-skills/$s"
  done
  for c in "${COMMANDS[@]}"; do
    echo "$CLAUDE_HOME/commands/$c.md::$CLAUDE_HOME/skills/ship-workflow/commands/$c.md"
  done
}

# link_state <link> <target> — ok | target missing | missing | wrong target | blocked by a real file
link_state() {
  if [[ -L "$1" ]]; then
    if [[ "$(readlink "$1")" != "$2" ]]; then echo "wrong target"
    elif [[ -e "$1" ]]; then echo ok
    else echo "target missing"
    fi
  elif [[ -e "$1" ]]; then
    echo "blocked by a real file"
  else
    echo missing
  fi
}

# Move a real file or directory out of a link's way — never delete it.
displace() {
  local path="$1" dest
  dest="$DISPLACED/$(basename "$path")-$(date -u +%Y%m%dT%H%M%SZ)"
  while [[ -e "$dest" ]]; do dest="${dest}-1"; done
  mkdir -p "$DISPLACED"
  mv "$path" "$dest"
  warn "moved $path -> $dest (not deleted)"
}

ensure_link() {
  local link="$1" target="$2" state
  state=$(link_state "$link" "$target")
  [[ "$state" == ok ]] && return 0
  if [[ "$state" == "target missing" ]]; then
    # The link is right; what it points at is not there (yet). Relinking cannot help.
    (( DRY )) || warn "$link: target missing ($target)"
    return 0
  fi
  if (( DRY )); then
    log "would link $link -> $target ($state)"
    return 0
  fi
  case "$state" in
    "blocked by a real file") displace "$link" ;;
    "wrong target")           rm "$link" ;;
  esac
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link"
  ok "linked $link"
}

# Remove ~/.claude/commands/ship-*.md links that point into ship-workflow's commands/
# at a file that no longer exists (a removed command). Nothing else is touched.
remove_dangling() {
  local f t
  [[ -d "$CLAUDE_HOME/commands" ]] || return 0
  for f in "$CLAUDE_HOME/commands"/ship-*.md; do
    [[ -L "$f" && ! -e "$f" ]] || continue
    # A kept command's link only dangles until its skill link is fixed; ensure_link owns it.
    case " ${COMMANDS[*]} " in *" $(basename "$f" .md) "*) continue ;; esac
    t=$(readlink "$f")
    [[ "$t" == */ship-workflow/commands/* ]] || continue
    if (( DRY )); then
      log "would remove dangling $f -> $t"
    else
      rm "$f"
      ok "removed dangling $f"
    fi
  done
}

restore_configs() {
  local entry live repo n
  for entry in "${CONFIG_FILES[@]}"; do
    live="${entry%%::*}"; repo="${entry##*::}"
    [[ -f "$repo" ]] || { warn "skip: $repo (not in the repo)"; continue; }
    [[ -f "$live" ]] && cmp -s "$live" "$repo" && continue
    if (( DRY )); then
      log "would restore $repo -> $live"
      continue
    fi
    if [[ -f "$live" ]]; then
      n=$( { diff -u "$live" "$repo" || true; } | wc -l | tr -d ' ')   # diff exits 1 when they differ
      diff -u "$live" "$repo" | head -40 || true
      if (( n > 40 )); then log "… ($((n - 40)) more diff lines)"; fi
    fi
    if (( ! YES )) && ! confirm "Overwrite $live with the repo copy? (the live file is kept under $DISPLACED)"; then
      warn "kept $live"
      continue
    fi
    # The live file may hold edits the last backup missed: move it aside, never lose it.
    if [[ -f "$live" ]]; then displace "$live"; fi
    mkdir -p "$(dirname "$live")"
    cp "$repo" "$live"
    ok "restored $live"
  done
}

devsync_bootstrap() {
  local bootstrap="$SCRIPT_DIR/devsync/bootstrap.sh"
  if (( DRY )) || [[ "${AI_SYSTEM_SKIP_DEVSYNC:-0}" == 1 ]]; then return 0; fi
  if [[ ! -x "$bootstrap" ]]; then
    warn "devsync/bootstrap.sh missing or not executable — skip"
    return 0
  fi
  info "Running devsync bootstrap..."
  if (( YES )); then "$bootstrap" --yes; else "$bootstrap"; fi
}

# Links point at this checkout. A ship-next worktree is removed after it lands, so links
# into one would dangle machine-wide: refuse. Off main, every session runs that branch.
checkout_guard() {
  local top gd common branch
  top=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || return 0
  [[ "$top" == "$(cd "$SCRIPT_DIR" && pwd -P)" ]] || return 0   # not a checkout root
  gd=$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-dir)
  common=$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir)
  if [[ "$gd" != "$common" ]]; then
    err "refusing: $SCRIPT_DIR is a linked worktree — run ./sync.sh restore from the main checkout"
    exit 2
  fi
  branch=$(git -C "$SCRIPT_DIR" branch --show-current)
  [[ "$branch" == main ]] || warn "this checkout is on '${branch:-detached HEAD}', not main — every session on this machine will run it"
}

cmd_restore() {
  local arg pair
  for arg in "$@"; do
    case "$arg" in
      --yes) YES=1 ;;
      --dry-run) DRY=1 ;;
      *) err "unknown option: $arg"; exit 2 ;;
    esac
  done
  checkout_guard
  info "Links: ~/.claude -> $SCRIPT_DIR"
  while IFS= read -r pair; do
    ensure_link "${pair%%::*}" "${pair##*::}"
  done < <(links)
  remove_dangling
  info "Config files"
  restore_configs
  devsync_bootstrap
  if (( DRY )); then ok "Dry run — nothing changed"; else ok "Restore complete"; fi
}

cmd_backup() {
  local entry live repo arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY=1 ;;
      *) err "unknown option: $arg"; exit 2 ;;
    esac
  done
  for entry in "${CONFIG_FILES[@]}"; do
    live="${entry%%::*}"; repo="${entry##*::}"
    [[ -f "$live" ]] || { warn "skip: $live (not found)"; continue; }
    if (( DRY )); then log "would back up $live -> ${repo#"$SCRIPT_DIR"/}"; continue; fi
    mkdir -p "$(dirname "$repo")"
    cp "$live" "$repo"
    ok "backed up $live -> ${repo#"$SCRIPT_DIR"/}"
  done
}

cmd_status() {
  local pair link target state bad=0 entry live repo
  while IFS= read -r pair; do
    link="${pair%%::*}"; target="${pair##*::}"
    state=$(link_state "$link" "$target")
    log "${link#"$CLAUDE_HOME"/}: $state"
    [[ "$state" == ok ]] || bad=1
  done < <(links)
  for entry in "${CONFIG_FILES[@]}"; do
    live="${entry%%::*}"; repo="${entry##*::}"
    if [[ ! -f "$live" || ! -f "$repo" ]]; then
      log "$live: missing"
    elif cmp -s "$live" "$repo"; then
      log "$live: same"
    else
      log "$live: differs (./sync.sh backup to save it)"
    fi
  done
  return "$bad"
}

usage() {
  cat <<EOF
${C_BOLD}sync.sh${C_RESET} — install ai_system (ship-workflow + run-plan + code-review-skill)

  $(basename "$0") restore [--yes] [--dry-run]  link the skills and commands into ~/.claude,
                                              restore the config files, run devsync bootstrap
  $(basename "$0") backup [--dry-run]           copy ~/.claude/CLAUDE.md and the devsync config here
  $(basename "$0") status                       show link and config state (exit 1 if a link is wrong)

A real file or directory in a link's way is moved to $DISPLACED, never deleted.
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  restore) cmd_restore "$@" ;;
  backup)  cmd_backup "$@" ;;
  status)  cmd_status ;;
  ""|-h|--help|help) usage ;;
  *) err "Unknown command: $cmd"; usage; exit 1 ;;
esac
