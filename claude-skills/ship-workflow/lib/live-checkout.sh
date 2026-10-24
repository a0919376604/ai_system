#!/usr/bin/env bash
# ship-workflow/lib/live-checkout.sh
# Every session on this machine runs the checkout behind ~/.claude/skills/ship-workflow
# — a symlink into the ai_system working tree — uncommitted edits included. When that
# checkout sits on a feature branch, the whole machine runs the branch: langlive ran a
# /ship-land that predated R-001 that way (R-004 §1, §3.7).

# live_checkout_warning — print one warning line when the live checkout is off main or
# has uncommitted changes to tracked files. Silent otherwise, and when the live skill is
# not a link into a git checkout. Always exits 0: it informs, it never blocks.
live_checkout_warning() {
  local link="$HOME/.claude/skills/ship-workflow" dir top branch
  [ -L "$link" ] || return 0
  dir=$(cd "$link" 2>/dev/null && pwd -P) || return 0
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  branch=$(git -C "$top" branch --show-current 2>/dev/null)
  if [ "$branch" != "main" ]; then
    echo "WARN: the live ship-workflow runs from ${top} on branch '${branch:-detached HEAD}', not main — every session on this machine runs that branch." >&2
  elif [ -n "$(git -C "$top" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "WARN: the live ship-workflow (${top}, main) has uncommitted changes — every session on this machine runs them." >&2
  fi
  return 0
}
