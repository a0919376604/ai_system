#!/usr/bin/env bash
# auto-decision-log.sh — append a single audit line to a worktree's auto-decision log.
#
# Usage:
#   auto-decision-log.sh <worktree_dir> <phase> <decision> [detail]
#
# Side effect: append `<ISO-8601 UTC> <phase> <decision>[ — <detail>]` to
# <worktree_dir>/.claude/.ship-auto-decisions.md (creates .claude/ if absent).
#
# Why .claude/ and not docs/:
#   .gitignore files only apply to entries within their own directory tree.
#   The existing `.claude/.gitignore` rule `.ship-auto-decisions.md` only
#   matches files inside `.claude/`. Writing under `docs/` would leave the
#   log file untracked-but-unignored, breaking `git worktree remove`.
#   Keeping the log under `.claude/` is consistent with other ship-workflow
#   state files (.ship-last-pull, .id-gen.lock, .id-reservations).
#
# Exit codes:
#   0  on success (or if log file is created fresh)
#   2  if worktree_dir doesn't exist
#   non-zero  if too few args

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <worktree_dir> <phase> <decision> [detail]" >&2
  exit 1
fi

WORKTREE="$1"
PHASE="$2"
DECISION="$3"
DETAIL="${4:-}"

if [ ! -d "$WORKTREE" ]; then
  echo "ERROR: worktree dir not found: $WORKTREE" >&2
  exit 2
fi

mkdir -p "$WORKTREE/.claude"

LOG="$WORKTREE/.claude/.ship-auto-decisions.md"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ -n "$DETAIL" ]; then
  echo "${TS} ${PHASE} ${DECISION} — ${DETAIL}" >> "$LOG"
else
  echo "${TS} ${PHASE} ${DECISION}" >> "$LOG"
fi
