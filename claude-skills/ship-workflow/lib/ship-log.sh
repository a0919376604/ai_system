#!/usr/bin/env bash
# ship-workflow/lib/ship-log.sh
# The single writer of _log.md rows; it appends and never commits.
# On a review branch rows wait in .ship/ship-log-rows (untracked) and /ship-land
# replays them after the merge, so no review branch writes _log.md (R-001, R-008).
# This also covers /ship-idea --during-build.

command -v merge_mode >/dev/null 2>&1 || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"

SHIP_LOG_REL="docs/learnings/_log.md"

ship_log_defers() {
  [ "$(merge_mode)" = mr ] || return 1
  case "$(git branch --show-current)" in ship/*) return 0 ;; *) return 1 ;; esac
}

# ship_log "<row>" — record one log row. Exit 2 on an empty row or outside git.
ship_log() {
  local row="$1" root
  [ -n "$row" ] || { echo "ship_log: empty row" >&2; return 2; }
  root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { echo "ship_log: not in a git repo" >&2; return 2; }
  if ship_log_defers; then
    mkdir -p "$root/.ship"
    printf '%s\n' "$row" >> "$root/.ship/ship-log-rows"
  else
    mkdir -p "$root/docs/learnings"
    printf '%s\n' "$row" >> "$root/$SHIP_LOG_REL"
  fi
}

# ship_log_ratio_count — how many ships recorded a test ratio: `ratio ` rows in
# the file.
ship_log_ratio_count() {
  local root f
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 0; return 0; }
  f=0
  if [ -f "$root/$SHIP_LOG_REL" ]; then
    f=$(grep -cF "ratio " "$root/$SHIP_LOG_REL" 2>/dev/null || true)
  fi
  f=$(printf '%s' "$f" | tr -d '[:space:]')
  echo "${f:-0}"
}
