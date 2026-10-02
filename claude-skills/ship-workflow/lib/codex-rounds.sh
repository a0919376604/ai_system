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
# STRUCTURE IS KEYED OFF A SENTINEL, NOT OFF THE HEADING.
# An earlier version counted rounds with `grep '^## Round '`. That was wrong:
# a fence changes how a body RENDERS, it does nothing to stop grep matching
# inside it. Reports routinely quote the previous round — Phase 5 hands
# .ship/codex-rounds.md to the executor on purpose — so a quoted heading both
# inflated the round count and, worse, moved the "last round" boundary forward
# so that the current round's real findings were silently dropped in favour of
# a stale quoted one.
#
# So each round is delimited by `<!-- codex-round N -->` at column 0, and both
# readers key off that. A report body cannot forge one: codex_round_append is
# the only writer, and it neutralises look-alikes on the way in (see below).

# One definition of the round delimiter, shared by both readers. It was
# originally digits-only, and Phase 6 passes `fix-${attempt}` — so three real
# rounds counted as one and the "last round" boundary swallowed all of them.
# Round ids are sanitised to this charset on write, so a written sentinel always
# matches this pattern no matter what a caller passes.
CODEX_ROUND_SENTINEL_RE='^<!-- codex-round [A-Za-z0-9._-][A-Za-z0-9._-]* -->$'

# codex_round_id <raw> — the id as it will appear in a sentinel.
_codex_round_id() {
  local id
  id=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
  [ -n "$id" ] || id=unknown
  printf '%s' "$id"
}

# The one documented exception to byte-identical storage: a body line that would
# itself parse as a round delimiter is indented one space inside the fence. The
# text stays legible; it just stops being structure. Without this, feeding the
# round history back to the executor lets its own quoting forge a round.
_codex_round_neutralise() {
  sed 's/^\(<!-- codex-round \)/ \1/' "$1"
}

# Pick a fence longer than the longest run of ~ at column 0 in the body, so a
# report that contains a fence line cannot terminate ours early and spill the
# rest of itself into the surrounding document.
_codex_round_fence() {
  local longest width
  longest=$(grep -o '^~\{1,\}' "$1" 2>/dev/null \
            | awk '{ if (length($0) > m) m = length($0) } END { print m+0 }')
  [ -n "$longest" ] || longest=0
  width=$((longest + 1))
  [ "$width" -lt 3 ] && width=3
  printf '%*s' "$width" '' | tr ' ' '~'
}

# codex_round_append <worktree> <n> <verdict> <reportfile> <classification> <note>
# Exit 2 if the report file is missing — a round with no report is not a round.
codex_round_append() {
  local wt="$1" n="$2" verdict="$3" report="$4" cls="$5" note="$6" out fence id
  [ -d "$wt" ] || return 2
  [ -f "$report" ] || return 2
  mkdir -p "$wt/.ship" || return 2
  out="$wt/.ship/codex-rounds.md"
  fence=$(_codex_round_fence "$report")
  id=$(_codex_round_id "$n")
  {
    printf '<!-- codex-round %s -->\n' "$id"
    printf '## Round %s — %s — %s\n\n' "$n" "$verdict" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%stext\n' "$fence"
    _codex_round_neutralise "$report"
    # Close the body's final line only if it is not already closed. Emitting an
    # unconditional newline here would put a blank line inside the fence, which
    # is not what "stored byte-identical" is supposed to mean.
    if [ -s "$report" ] && [ "$(tail -c 1 "$report" | wc -l | tr -d '[:space:]')" = "0" ]; then
      printf '\n'
    fi
    printf '%s\n\n' "$fence"
    printf '**Supervisor:** classified as %s. %s\n\n' "$cls" "$note"
  } >> "$out"
}

# codex_round_count <worktree>
codex_round_count() {
  local f="$1/.ship/codex-rounds.md" n
  [ -f "$f" ] || { echo 0; return 0; }
  # `grep -c` prints 0 AND exits 1 on no match; `|| true` keeps the 0 without
  # appending a second one (the `|| echo 0` form yields "00").
  n=$(grep -c "$CODEX_ROUND_SENTINEL_RE" "$f" 2>/dev/null || true)
  n=$(echo "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# codex_round_last_findings <worktree> — the bullet lines of the final round.
# Includes bullets the final report quoted from an earlier round: those bytes
# are genuinely part of what this round reported, and nothing in the text
# reliably distinguishes a quotation from a fresh finding. Dropping the current
# round's own findings to avoid showing a quoted one is the worse trade.
codex_round_last_findings() {
  local f="$1/.ship/codex-rounds.md" start
  [ -f "$f" ] || return 0
  start=$(grep -n "$CODEX_ROUND_SENTINEL_RE" "$f" | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 0
  tail -n "+$start" "$f" | grep -E '^- ' || true
}
