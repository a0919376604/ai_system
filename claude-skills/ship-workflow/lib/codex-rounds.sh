#!/usr/bin/env bash
# ship-workflow/lib/codex-rounds.sh
# Accumulate one entry per codex round in <worktree>/.ship/codex-rounds.md.
#
# The executor's report is stored BYTE-IDENTICAL, inside a fence. Its shape is
# load-bearing for an operator who was not present: a verdict line, a framing
# count, concrete bullets, evidence with numbers, a statement of what was NOT
# changed, and the required next action. That fifth element is the blast radius
# of a failed run and is exactly what summarising destroys.
#
# Fencing matters: a report can begin a line with `#`, which would otherwise
# become a heading in the surrounding document and break round counting.

# codex_round_append <worktree> <n> <verdict> <reportfile> <classification> <note>
# Exit 2 if the report file is missing — a round with no report is not a round.
codex_round_append() {
  local wt="$1" n="$2" verdict="$3" report="$4" cls="$5" note="$6" out
  [ -d "$wt" ] || return 2
  [ -f "$report" ] || return 2
  mkdir -p "$wt/.ship" || return 2
  out="$wt/.ship/codex-rounds.md"
  {
    printf '## Round %s — %s — %s\n\n' "$n" "$verdict" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '~~~text\n'
    cat "$report"
    printf '\n~~~\n\n'
    printf '**Supervisor:** classified as %s. %s\n\n' "$cls" "$note"
  } >> "$out"
}

# codex_round_count <worktree>
codex_round_count() {
  local f="$1/.ship/codex-rounds.md" n
  [ -f "$f" ] || { echo 0; return 0; }
  n=$(grep -c '^## Round ' "$f" 2>/dev/null || true)
  n=$(echo "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# codex_round_last_findings <worktree> — the bullet lines of the final round.
codex_round_last_findings() {
  local f="$1/.ship/codex-rounds.md" start
  [ -f "$f" ] || return 0
  start=$(grep -n '^## Round ' "$f" | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 0
  tail -n "+$start" "$f" | grep -E '^- ' || true
}
