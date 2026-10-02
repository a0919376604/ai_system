#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }

p5_section() { awk '/^## Phase 5/,/^## Phase 6/' "$CMD"; }

p5_bash() {
  p5_section | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

@test "Phase 5 sources all three supervise libs" {
  for lib in codex-verdict.sh codex-rounds.sh codex-supervise-state.sh; do
    p5_bash | grep -qF "lib/$lib" || { echo "Phase 5 does not source $lib"; return 1; }
  done
}

@test "Phase 5 resumes from state before relaunching" {
  p5_bash | grep -qF 'codex_state_matches' || { echo "no plan-identity check on resume"; return 1; }
  p5_bash | grep -qF 'codex_state_alive'   || { echo "no live-process check"; return 1; }
}

@test "Phase 5 routes on the classified verdict, not on raw log text" {
  # Ruling 9: the plan's version grepped the BASH for the words done/blocked/infra
  # while its implementation put them only in prose, so it could not pass. The
  # routing is now an actual case statement, which is both checkable here and
  # deterministic at run time.
  body=$(p5_bash)
  echo "$body" | grep -qF 'codex_verdict' || { echo "verdict is not classified"; return 1; }
  echo "$body" | grep -qF 'case "$CODEX_FINAL_VERDICT" in' || { echo "no routing switch"; return 1; }
  echo "$body" | grep -qF 'done|done_with_concerns)' || { echo "no branch for done"; return 1; }
  echo "$body" | grep -qE '^[[:space:]]*blocked\)' || { echo "no branch for blocked"; return 1; }
  echo "$body" | grep -qE '^[[:space:]]*infra\)' || { echo "no branch for infra"; return 1; }
}

@test "Phase 5 has no fallthrough: an unknown verdict stops rather than continuing" {
  p5_bash | grep -qE '^[[:space:]]*\*\)[[:space:]]*CODEX_ROUTE=stop_infra' \
    || { echo "an unrecognised verdict does not stop"; return 1; }
}

@test "Phase 5 does not consume an attempt on an infrastructure failure" {
  p5_section | grep -qF 'attempt count unchanged' \
    || { echo "the infra branch does not state that the attempt is preserved"; return 1; }
}

@test "Phase 5 documents the three-way BLOCKED routing" {
  section=$(p5_section)
  for cls in 'plan defect' 'executor error' 'spec-level'; do
    echo "$section" | grep -qF "$cls" || { echo "missing BLOCKED class: $cls"; return 1; }
  done
}

@test "Phase 5 escalates a spec-level finding instead of designing around it" {
  section=$(p5_section)
  echo "$section" | grep -qiF 'escalate' || { echo "no escalation path"; return 1; }
  echo "$section" | grep -qF 'When the classification is unclear' \
    || { echo "no bias toward escalation on an unclear call"; return 1; }
}

@test "Phase 5 caps repair attempts at 3 and retains the worktree" {
  section=$(p5_section)
  echo "$section" | grep -qF 'CODEX_ATTEMPT_CAP=3' || { echo "no cap of 3"; return 1; }
  echo "$section" | grep -qiF 'worktree retained' || { echo "exhaustion discards the worktree"; return 1; }
  # The cap must gate the relaunch, not merely print a message.
  p5_bash | grep -qF 'CODEX_ROUTE=stop_exhausted' || { echo "the cap does not gate relaunch"; return 1; }
}

@test "Phase 5 carries all five prompt-hardening items" {
  section=$(p5_section)
  for item in 'Scope override' 'auto:yes' 'Engineering vocabulary' 'Resume context' 'Round history'; do
    echo "$section" | grep -qF "$item" || { echo "prompt hardening missing: $item"; return 1; }
  done
}

@test "Phase 5 records every round before acting on it" {
  p5_bash | grep -qF 'codex_round_append' || { echo "rounds are not recorded"; return 1; }
}

# --- Ruling 6: the report must survive a long log ---------------------------

@test "Phase 5 extracts the report with the shared whole-log rule" {
  body=$(p5_bash)
  echo "$body" | grep -qF 'codex_report_extract' \
    || { echo "report extraction is not the shared rule"; return 1; }
  # The tail -40 window is what silently emptied long reports.
  ! echo "$body" | grep -qE 'tail -[0-9]+ "\$CODEX_LOG"' \
    || { echo "a fixed-size tail window is back"; return 1; }
}

@test "Phase 5 treats an unextractable report as infra, not as an empty round" {
  body=$(p5_bash)
  echo "$body" | grep -qF 'if ! codex_report_extract' \
    || { echo "extraction failure is not checked"; return 1; }
  echo "$body" | grep -qF 'CODEX_FINAL_VERDICT=infra' \
    || { echo "a failed extraction does not downgrade the verdict"; return 1; }
}

# --- Ruling 7: state exists from launch, not from the first failure ---------

@test "Phase 5 writes supervise state at launch, before anything can block" {
  # The first run is the one a restart is most likely to interrupt, and the
  # plan's version wrote state only in the blocked branch.
  launch=$(p5_section | awk '/\*\*Launch\*\*/,/\*\*When codex exits\*\*/')
  echo "$launch" | grep -qF 'codex_state_write' \
    || { echo "no state is written at launch"; return 1; }
  echo "$launch" | grep -qF 'codex.pid' \
    || { echo "the pid is not recorded at launch"; return 1; }
}

@test "Phase 5 states which pid file is authoritative" {
  p5_section | grep -qiF 'pid authority' \
    || { echo "two pid files exist with no stated authority"; return 1; }
}

# --- Ruling 8: success must not leave blocked state behind ------------------

@test "Phase 5 clears the blocked state when the run completes" {
  cont=$(p5_section | awk '/- \*\*`continue`\*\*/,/- \*\*`stop_infra`\*\*/')
  echo "$cont" | grep -qF 'codex_state_write' \
    || { echo "the success branch leaves stale blocked state for Phase 6"; return 1; }
}

@test "Phase 5 bash blocks parse as valid shell" {
  block=$(p5_bash)
  [ -n "$block" ]
  echo "$block" > "$BATS_TEST_TMPDIR/p5.sh"
  run bash -n "$BATS_TEST_TMPDIR/p5.sh"
  [ "$status" -eq 0 ]
}

@test "Phase 5 options 1 and 2 are untouched" {
  section=$(p5_section)
  echo "$section" | grep -qF 'superpowers:subagent-driven-development' || return 1
  echo "$section" | grep -qF 'superpowers:executing-plans' || return 1
}
