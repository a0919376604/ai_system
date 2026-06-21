#!/usr/bin/env bash
# cwd-guard.sh — refuse to proceed if cwd is inside a git worktree.
#
# Usage (from a slash command's bash block):
#   ~/.claude/skills/ship-workflow/lib/cwd-guard.sh || exit $?
#
# Detection: `git rev-parse --git-dir` returns the .git path.
#   - In the main work tree, this is `.git` (or resolved absolute path ending in `/.git`).
#   - In a worktree, it points into `<main>/.git/worktrees/<branch>` — contains "/worktrees/".
# This is unambiguous and doesn't rely on branch naming.

set -euo pipefail

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)

if [ -z "$GIT_DIR" ]; then
  # Not in a git repo — no worktree concept, allow.
  exit 0
fi

# Resolve to absolute path before string-matching (handles `.git` short form)
GIT_DIR_ABS=$(cd "$(dirname "$GIT_DIR")" 2>/dev/null && pwd)/$(basename "$GIT_DIR")

case "$GIT_DIR_ABS" in
  */worktrees/*)
    echo "ERROR: this command cannot run inside a ship/* worktree." >&2
    echo "       cd back to the main repo (the parent project) first." >&2
    exit 1
    ;;
esac

exit 0
