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

# ============================ Task 5: Phase 9 ===============================

p9_section() { awk '/^## Phase 9/,0' "$CMD"; }
p9_bash() {
  p9_section | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

@test "Phase 9 log row records the codex round count and verdict" {
  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
  [ -n "$row" ]
  [[ "$row" == *'${CODEX_LOG_FRAGMENT}'* ]]
  frag=$(p9_bash | grep -F 'CODEX_LOG_FRAGMENT=", codex:')
  [[ "$frag" == *'${CODEX_ROUNDS}'* ]]
  [[ "$frag" == *'${CODEX_FINAL_VERDICT}'* ]]
}

@test "Phase 9 omits the codex fragment on ships that never ran codex" {
  # Auto mode picks executor 1, so most ships have no codex state at all.
  # An unguarded "codex:  round(s)" on every row hides the rows that matter.
  body=$(p9_bash)
  echo "$body" | grep -qF 'CODEX_LOG_FRAGMENT=""' || { echo "fragment is not defaulted empty"; return 1; }
  echo "$body" | grep -qF 'CODEX_SUMMARY_BLOCK=""' || { echo "summary block is not defaulted empty"; return 1; }
  [ "$(echo "$body" | grep -cF 'if [ "${CODEX_ROUNDS:-0}" -gt 0 ]')" -eq 2 ]
}

@test "Phase 9 summary carries the last round's findings, not a paraphrase" {
  p9_section | grep -qF 'codex_round_last_findings' \
    || { echo "the summary does not pull the last round's bullets"; return 1; }
  p9_section | grep -qF '${CODEX_LAST_FINDINGS}' \
    || { echo "the captured findings are never interpolated"; return 1; }
}

@test "Phase 9 sources the lib it calls — phases do not share a shell" {
  p9_bash | grep -qF 'lib/codex-rounds.sh' \
    || { echo "Phase 9 calls codex_round_* without sourcing the lib"; return 1; }
}

@test "the round history is read and copied out BEFORE the worktree is removed" {
  # The ordering is the whole point: step 1 removes the worktree, so a read at
  # step 4 returns nothing. Compare line positions rather than trusting prose.
  sec=$(p9_section)
  read_at=$(echo "$sec" | grep -n 'codex_round_last_findings' | head -1 | cut -d: -f1)
  copy_at=$(echo "$sec" | grep -n 'cp "\$WORKTREE/.ship/codex-rounds.md"' | head -1 | cut -d: -f1)
  rm_at=$(echo "$sec" | grep -n 'git worktree remove "\$WORKTREE"' | head -1 | cut -d: -f1)
  [ -n "$read_at" ] && [ -n "$copy_at" ] && [ -n "$rm_at" ]
  [ "$read_at" -lt "$rm_at" ] || { echo "findings are read after the worktree is removed"; return 1; }
  [ "$copy_at" -lt "$rm_at" ] || { echo "history is copied out after the worktree is removed"; return 1; }
}

@test "Phase 9 points at an archive that outlives the worktree" {
  sec=$(p9_section)
  echo "$sec" | grep -qiF 'copies it out' \
    || { echo "nothing says the round history is preserved"; return 1; }
  # The summary must not point inside the removed worktree.
  echo "$sec" | grep -qF 'full round history: ${CODEX_ROUNDS_ARCHIVE' \
    || { echo "the summary points at a path that no longer exists"; return 1; }
  ! echo "$sec" | grep -qF 'full round history: ${WORKTREE}' \
    || { echo "the summary points inside the removed worktree"; return 1; }
}

@test "Phase 9 bash blocks parse as valid shell" {
  block=$(p9_bash)
  [ -n "$block" ]
  echo "$block" > "$BATS_TEST_TMPDIR/p9.sh"
  run bash -n "$BATS_TEST_TMPDIR/p9.sh"
  [ "$status" -eq 0 ]
}

# ============================ Task 6: Phase 6 ===============================

p6_section() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }

@test "Phase 6's fix-plan re-invoke supervises rather than firing and forgetting" {
  section=$(p6_section)
  echo "$section" | grep -qF 'codex_verdict' \
    || { echo "the fix-plan re-invoke does not classify codex's verdict"; return 1; }
  if echo "$section" | grep -qE '^[[:space:]]*3\) invoke /run-plan \$FIX_PLAN ;;[[:space:]]*$'; then
    echo "the fix-plan case still fires and forgets"
    return 1
  fi
}

@test "Phase 6's fix-plan rounds land in the same history file" {
  p6_section | grep -qF 'codex_round_append' \
    || { echo "fix-plan rounds are not recorded"; return 1; }
}

@test "Phase 6 sources the libs it calls — phases do not share a shell" {
  section=$(p6_section)
  for lib in codex-verdict.sh codex-rounds.sh; do
    echo "$section" | grep -qF "lib/$lib" \
      || { echo "Phase 6 calls into $lib without sourcing it"; return 1; }
  done
}

@test "Phase 6 reads the fix-plan's own slot, not Phase 5's" {
  # /run-plan derives its slot from the plan filename it was handed, so the
  # fix-plan logs to its own path. Reusing $SLOT would classify the ORIGINAL
  # run's log and re-record its report as this fix's result.
  section=$(p6_section)
  echo "$section" | grep -qF 'FIX_SLOT=$(basename "$FIX_PLAN" .md' \
    || { echo "the fix-plan slot is not derived from the fix-plan"; return 1; }
  echo "$section" | grep -qF 'FIX_LOG="/tmp/run-plan-codex-${FIX_SLOT}.log"' \
    || { echo "the fix log path is not built from the fix slot"; return 1; }
  ! echo "$section" | grep -qF '/tmp/run-plan-codex-${SLOT}.log' \
    || { echo "Phase 6 still reads Phase 5's log"; return 1; }
}

@test "Phase 6 uses the shared report extractor, not a tail window" {
  section=$(p6_section)
  echo "$section" | grep -qF 'codex_report_extract' \
    || { echo "the fix-plan run does not use the shared extractor"; return 1; }
  ! echo "$section" | grep -qE 'tail -[0-9]+ "?/tmp/run-plan-codex' \
    || { echo "a fixed-size tail window is back in Phase 6"; return 1; }
}

@test "Phase 6 does not record a round it could not extract a report for" {
  section=$(p6_section)
  echo "$section" | grep -qF 'if ! codex_report_extract' \
    || { echo "extraction failure is not checked before appending a round"; return 1; }
}

@test "Phase 6 waits for codex to exit before classifying its log" {
  # /run-plan detaches. Classifying on the next statement reads a log that does
  # not exist yet: infra, zero rounds, and a break on a false failure while
  # codex keeps committing.
  section=$(p6_section)
  wait_at=$(echo "$section" | grep -n 'codex_wait_for_exit' | head -1 | cut -d: -f1)
  verdict_at=$(echo "$section" | grep -n 'FIX_VERDICT=$(codex_verdict' | head -1 | cut -d: -f1)
  [ -n "$wait_at" ] || { echo "Phase 6 never waits for codex to exit"; return 1; }
  [ -n "$verdict_at" ]
  [ "$wait_at" -lt "$verdict_at" ] || { echo "Phase 6 classifies before waiting"; return 1; }
}

@test "Phase 6 propagates the final verdict and round count to Phase 9" {
  # Phase 9 reports CODEX_FINAL_VERDICT and CODEX_ROUNDS. Left at Phase 5's
  # values, the operator is told the ship ended on the original run's verdict
  # and every fix round is missing from the count.
  section=$(p6_section)
  echo "$section" | grep -qF 'CODEX_FINAL_VERDICT="$FIX_VERDICT"' \
    || { echo "the fix-plan verdict never reaches Phase 9"; return 1; }
  echo "$section" | grep -qF 'CODEX_ROUNDS=$(codex_round_count "$WORKTREE")' \
    || { echo "fix rounds are missing from the count Phase 9 reports"; return 1; }
}

@test "Phase 6 does not write state that only Phase 5 reads" {
  # Every reader of the supervise state and the pid mirror is in Phase 5, and
  # each file holds one record. A write from Phase 6 is read by nothing and
  # clobbers the plan identity Phase 5 resumes from: after one,
  # codex_state_matches against the original plan returns false and the
  # attempt count resets to 0. An earlier version of this test asserted the
  # write EXISTED, pinning machinery that could only do harm.
  # Scan EXECUTABLE lines only. The first version of this guard matched the
  # comment that explains the rule — the fourth time that defect has appeared
  # in this repo. Strip comments and blank lines before asserting.
  code=$(p6_section | sed 's/[[:space:]]*#.*$//' | grep -v '^[[:space:]]*$')
  ! echo "$code" | grep -qF 'codex_state_write' \
    || { echo "Phase 6 clobbers Phase 5's supervise state"; return 1; }
  ! echo "$code" | grep -qF '.ship/codex.pid' \
    || { echo "Phase 6 clobbers Phase 5's pid mirror"; return 1; }
  # And the guard must be able to see a violation when there is one.
  echo "$code" | grep -qF 'codex_wait_for_exit' \
    || { echo "the code extraction produced nothing to scan"; return 1; }
}

@test "Phase 9 bounds the findings it interpolates into the notification" {
  body=$(p9_bash)
  echo "$body" | grep -qF 'CODEX_FINDINGS_TOTAL' \
    || { echo "the findings block is unbounded"; return 1; }
  echo "$body" | grep -qF 'head -12' \
    || { echo "no cap on the findings block"; return 1; }
  echo "$body" | grep -qF 'more — see the archive' \
    || { echo "truncation is silent — the operator cannot tell"; return 1; }
}
