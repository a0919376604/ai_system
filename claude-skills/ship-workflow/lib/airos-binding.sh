#!/usr/bin/env bash
# airos-binding.sh — resolve AIR-OS vault + per-repo project path.
#
# Canonical direction for strategy docs (VISION/STRATEGY/ROADMAP/QUARTERLY_GOALS.md):
#   vault → repo (vault is source of truth; repo mirror is for cwd-local tooling)
#
# When repo docs/product/*.md have committed changes that vault has not caught
# up on, sync.sh will detect the divergence and abort (R-087). To carry repo
# edits back to vault, the user updates vault manually (or via obsidian sync)
# BEFORE re-running sync.sh. See lib/sync.sh for the divergence-detection
# implementation and CLI flags.
#
# Usage:
#   airos-binding.sh vault          # prints vault root
#   airos-binding.sh project_path   # prints AIR-OS 10 Projects/<name>/ path
#   airos-binding.sh project_name   # prints just the project name
#   airos-binding.sh roadmap_mode   # prints "soft" | "strict"
#   airos-binding.sh code_root      # prints local code workspace root
#                                     (e.g. /Users/leric/Desktop/code)
#                                     /ship-init <repo> resolves to <code_root>/<repo>

set -euo pipefail

GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
PER_REPO_CFG="$(pwd)/.claude/ship-config.yml"

if [ ! -f "$GLOBAL_CFG" ]; then
  echo "ERROR: ${GLOBAL_CFG##*/} not found at $GLOBAL_CFG" >&2
  echo "Hint: create it with at least 'airos_vault: /path/to/SecondBrain'" >&2
  exit 1
fi

# Minimal YAML key reader (assumes simple key: value lines; no nesting).
# Strips trailing `# comment` and trailing whitespace.
read_yaml_key() {
  local file="$1"
  local key="$2"
  awk -v k="$key" -F': *' '$1==k {
    sub(/[\r\n]+$/, "", $2)
    sub(/[ \t]*#.*$/, "", $2)
    sub(/[ \t]+$/, "", $2)
    gsub(/^"|"$/, "", $2)
    print $2
    exit
  }' "$file"
}

VAULT="$(read_yaml_key "$GLOBAL_CFG" airos_vault)"
PROJECTS_DIR="$(read_yaml_key "$GLOBAL_CFG" airos_projects_dir)"
PROJECTS_DIR="${PROJECTS_DIR:-10 Projects}"
ROADMAP_MODE_GLOBAL="$(read_yaml_key "$GLOBAL_CFG" default_roadmap_mode)"
ROADMAP_MODE_GLOBAL="${ROADMAP_MODE_GLOBAL:-soft}"
CODE_ROOT="$(read_yaml_key "$GLOBAL_CFG" code_root)"

# Per-repo overrides
PROJECT_NAME_OVERRIDE=""
ROADMAP_MODE_OVERRIDE=""
if [ -f "$PER_REPO_CFG" ]; then
  PROJECT_NAME_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" airos_project)"
  ROADMAP_MODE_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" roadmap_mode)"
fi

# At the root of a linked worktree (ship-next's ship/R-NNN-* checkouts), basename(pwd)
# is the worktree's own name, and R-001/R-003 mirrored their specs into bogus
# "10 Projects/R-00N-…" vault folders that way (R-004 §3.8). There, name the project
# after the main checkout. Anywhere else — the main checkout, a subdirectory, a plain
# directory nested inside some checkout — keep basename(pwd).
# _at_linked_worktree_root — exit 0 when the cwd is the root of a linked worktree whose
# main checkout has an ordinary .git directory.
_at_linked_worktree_root() {
  local top gd common
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ "$top" = "$(pwd -P)" ] || return 1
  gd=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] && [ "$gd" != "$common" ] && [ "$(basename "$common")" = .git ]
}

_project_dir_name() {
  if _at_linked_worktree_root; then
    basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  else
    basename "$(pwd)"
  fi
}

PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(_project_dir_name)}"
ROADMAP_MODE="${ROADMAP_MODE_OVERRIDE:-$ROADMAP_MODE_GLOBAL}"

case "${1:-}" in
  vault)         echo "$VAULT" ;;
  project_path)  echo "$VAULT/$PROJECTS_DIR/$PROJECT_NAME" ;;
  project_name)  echo "$PROJECT_NAME" ;;
  roadmap_mode)  echo "$ROADMAP_MODE" ;;
  code_root)     echo "$CODE_ROOT" ;;
  in_linked_worktree) _at_linked_worktree_root ;;
  *)
    echo "Usage: $0 {vault|project_path|project_name|roadmap_mode|code_root|in_linked_worktree}" >&2
    exit 2
    ;;
esac
