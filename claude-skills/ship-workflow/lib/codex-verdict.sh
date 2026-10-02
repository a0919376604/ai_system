#!/usr/bin/env bash
# ship-workflow/lib/codex-verdict.sh
# Classify how a `/run-plan` codex run ended, from its log.
#
# Echoes exactly one of: done | done_with_concerns | blocked | infra
# Always exits 0 — the classification IS the result; a missing or unreadable
# log classifies as infra rather than failing.
#
# Why `infra` is separate from `blocked`:
#   Across 19 real runs, two ended without producing any verdict — credits ran
#   out, and a content filter crashed the process. Retrying those is pointless,
#   and counting them against a repair budget burns attempts that real defects
#   need. A run that produced no verdict produced no information.
#
# Why infrastructure beats a verdict already printed:
#   Credits can run out after the report is emitted. The report describes work
#   that then did not finish, so the run is not trustworthy.
#
# Why the verdict must be the executor's own:
#   The prompt itself contains the words "report BLOCKED". Matching that
#   substring anywhere in the log reads the instructions back as a result, so a
#   verdict only counts at the start of a line, optionally bold.

CODEX_INFRA_SIGNATURES='out of credits|flagged for possible|UnknownProcessId|failed to record rollout items'

# One definition of what a verdict marker looks like, shared by the classifier
# and the report extractor. Two copies of this rule is how a run ends up
# classified `done` while its report comes out empty.
CODEX_VERDICT_MARKER_RE='^\*{0,2}(DONE_WITH_CONCERNS|DONE|BLOCKED)\b'

# _codex_marker <logfile> — echo the last line-anchored verdict marker, or nothing.
_codex_marker() {
  grep -aoE "$CODEX_VERDICT_MARKER_RE" "$1" 2>/dev/null \
    | tr -d '*' | tail -1
}

# codex_verdict <logfile>
codex_verdict() {
  local log="$1" marker
  [ -f "$log" ] || { echo infra; return 0; }
  if grep -aqE "$CODEX_INFRA_SIGNATURES" "$log" 2>/dev/null; then
    echo infra; return 0
  fi
  marker=$(_codex_marker "$log")
  case "$marker" in
    DONE_WITH_CONCERNS) echo done_with_concerns ;;
    DONE)               echo done ;;
    BLOCKED)            echo blocked ;;
    *)                  echo infra ;;
  esac
}

# codex_verdict_reason <logfile> — one line explaining the classification.
codex_verdict_reason() {
  local log="$1" hit marker
  [ -f "$log" ] || { echo "no log file at $log"; return 0; }
  hit=$(grep -aoE "$CODEX_INFRA_SIGNATURES" "$log" 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    echo "infrastructure failure: $hit"
    return 0
  fi
  marker=$(_codex_marker "$log")
  if [ -z "$marker" ]; then
    echo "no verdict marker in the log — the run produced no result"
    return 0
  fi
  echo "executor reported $marker"
}

# codex_report_extract <logfile> <outfile>
# Write the executor's report — the last line-anchored verdict marker through
# end of file — to <outfile>. Exit 2 and leave no file when there is no report.
#
# Scans the WHOLE log, by the same rule codex_verdict uses. An earlier draft
# took `tail -40` and sliced from the first marker inside that window. On a
# 109-line log whose marker sat 49 lines from the end that produced a ZERO-line
# report while codex_verdict returned `done` — i.e. it destroyed the report
# precisely when the report was long enough to be worth keeping, and said
# nothing. Preserving the executor's report verbatim is the point of this
# feature, so an empty extraction is an error, never an empty round.
codex_report_extract() {
  local log="$1" out="$2" start
  [ -f "$log" ] || return 2
  [ -n "$out" ] || return 2
  start=$(grep -anE "$CODEX_VERDICT_MARKER_RE" "$log" 2>/dev/null | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 2
  tail -n "+$start" "$log" > "$out" || return 2
  [ -s "$out" ] || { rm -f "$out"; return 2; }
  return 0
}
