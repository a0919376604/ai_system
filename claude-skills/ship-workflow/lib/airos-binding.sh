#!/usr/bin/env bash
# airos-binding.sh — resolve AIR-OS vault + per-repo project path.
#
# Usage:
#   airos-binding.sh vault          # prints vault root
#   airos-binding.sh project_path   # prints AIR-OS 10 Projects/<name>/ path
#   airos-binding.sh project_name   # prints just the project name
#   airos-binding.sh roadmap_mode   # prints "soft" | "strict"

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

# Per-repo overrides
PROJECT_NAME_OVERRIDE=""
ROADMAP_MODE_OVERRIDE=""
if [ -f "$PER_REPO_CFG" ]; then
  PROJECT_NAME_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" airos_project)"
  ROADMAP_MODE_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" roadmap_mode)"
fi

PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(basename "$(pwd)")}"
ROADMAP_MODE="${ROADMAP_MODE_OVERRIDE:-$ROADMAP_MODE_GLOBAL}"

case "${1:-}" in
  vault)         echo "$VAULT" ;;
  project_path)  echo "$VAULT/$PROJECTS_DIR/$PROJECT_NAME" ;;
  project_name)  echo "$PROJECT_NAME" ;;
  roadmap_mode)  echo "$ROADMAP_MODE" ;;
  *)
    echo "Usage: $0 {vault|project_path|project_name|roadmap_mode}" >&2
    exit 2
    ;;
esac
