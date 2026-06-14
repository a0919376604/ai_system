#!/usr/bin/env bash
# sync.sh — one-way sync of 4 strategy files from AIR-OS to repo/docs/product/.
# Skipped if the freshness window has not yet expired since the last pull.
#
# Usage:
#   sync.sh                # honor freshness window (default 60s)
#   sync.sh --force        # force resync regardless of freshness

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VAULT="$("$LIB_DIR/airos-binding.sh" vault)"
PROJECT_PATH="$("$LIB_DIR/airos-binding.sh" project_path)"
REPO_ROOT="$(pwd)"
LAST_PULL="$REPO_ROOT/.claude/.ship-last-pull"

GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
FRESHNESS=$(awk -F': *' '$1=="auto_pull_freshness_window" {
  sub(/[ \t]*#.*$/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit
}' "$GLOBAL_CFG" 2>/dev/null || true)
FRESHNESS="${FRESHNESS:-60}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ "$FORCE" -ne 1 ] && [ -f "$LAST_PULL" ]; then
  # macOS-compatible stat
  if command -v gstat >/dev/null 2>&1; then
    last_mtime=$(gstat -c %Y "$LAST_PULL")
  else
    last_mtime=$(stat -f %m "$LAST_PULL" 2>/dev/null || stat -c %Y "$LAST_PULL")
  fi
  age=$(( $(date +%s) - last_mtime ))
  if [ "$age" -lt "$FRESHNESS" ]; then
    exit 0
  fi
fi

mkdir -p "$REPO_ROOT/docs/product"
for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
  src="$PROJECT_PATH/$f"
  dst="$REPO_ROOT/docs/product/$f"
  if [ -f "$src" ]; then
    # Atomic write: cp to .tmp then mv
    cp "$src" "$dst.tmp"
    mv "$dst.tmp" "$dst"
  else
    echo "WARN: $f not found at $src — skipping" >&2
  fi
done

# Update freshness marker
mkdir -p "$REPO_ROOT/.claude"
date +%s > "$LAST_PULL"
