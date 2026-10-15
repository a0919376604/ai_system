#!/usr/bin/env bash
# ship-workflow/lib/ship-log.sh
# The single writer of docs/learnings/_log.md rows.
#
# In merge_mode=mr every ship appended its row to the same file on its review
# branch, so whenever one MR merged, every other open MR conflicted on the
# file's tail (langlive !285–!288, 2026-10-14). On a review branch the row now
# travels as a `Ship-Log:` commit trailer instead: it reaches the base
# branch's history with the MR and touches no shared file. Everywhere else —
# squash mode, or on the base branch — it is appended to the file as before.

SHIP_LOG_REL="docs/learnings/_log.md"

command -v merge_mode >/dev/null 2>&1 \
  || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"

# ship_log_defers — exit 0 when a row must become a trailer, not a line:
# merge_mode is mr AND the current branch is a ship/* review branch.
ship_log_defers() {
  local root mode branch
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  mode=$(cd "$root" && merge_mode 2>/dev/null)
  [ "$mode" = "mr" ] || return 1
  branch=$(git branch --show-current 2>/dev/null)
  case "$branch" in
    ship/*) return 0 ;;
    *)      return 1 ;;
  esac
}

# ship_log "<row>" — record one log row. Exit 2 on an empty row or outside git.
ship_log() {
  local row="$1" root subject
  [ -n "$row" ] || { echo "ship_log: empty row" >&2; return 2; }
  root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { echo "ship_log: not in a git repo" >&2; return 2; }
  if ship_log_defers; then
    subject=$(printf '%s\n' "$row" | awk -F'|' '{
      c=$3; i=$4
      gsub(/^[ \t]+|[ \t]+$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", i)
      print "log: " c " " i }')
    git commit --allow-empty --only -q -m "$subject" -m "Ship-Log: $row"
    return $?
  fi
  mkdir -p "$root/docs/learnings"
  printf '%s\n' "$row" >> "$root/$SHIP_LOG_REL"
}

# ship_log_ratio_count — how many ships recorded a test ratio: `ratio ` rows in
# the file plus `ratio ` Ship-Log trailers reachable from HEAD.
ship_log_ratio_count() {
  local root f t
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 0; return 0; }
  f=0
  if [ -f "$root/$SHIP_LOG_REL" ]; then
    f=$(grep -cF "ratio " "$root/$SHIP_LOG_REL" 2>/dev/null || true)
  fi
  t=$(git log --format='%(trailers:key=Ship-Log,valueonly)' HEAD 2>/dev/null \
      | grep -cF "ratio " || true)
  f=$(printf '%s' "$f" | tr -d '[:space:]')
  t=$(printf '%s' "$t" | tr -d '[:space:]')
  echo $(( ${f:-0} + ${t:-0} ))
}
