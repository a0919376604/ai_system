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

# _codex_marker <logfile> — echo the last line-anchored verdict marker, or nothing.
_codex_marker() {
  grep -aoE '^\*{0,2}(DONE_WITH_CONCERNS|DONE|BLOCKED)\b' "$1" 2>/dev/null \
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
