#!/usr/bin/env bats
load helpers
setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }
p85() { awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD"; }
p5()  { awk '/^## Phase 5 /,/^## Phase 6 /' "$CMD"; }

@test "Phase 8.5 reports churn, not only growth" {
  # The phase stays two statements: its body is guarded by an exhaustive
  # allowlist in test_ship-next-prune.bats, which only works while the body is
  # short enough to enumerate. What tc_report actually emits is pinned in
  # test_test-churn.bats against a real git history.
  s=$(p85)
  echo "$s" | grep -qF 'lib/test-churn.sh' || { echo "lib not sourced"; return 1; }
  echo "$s" | grep -qF 'tc_report "$ORIG_BRANCH" HEAD' || { echo "report never called"; return 1; }
}

@test "Phase 8.5 stays report-only for churn too" {
  # The prune phase deletes nothing; churn must not become a gate either.
  # Measured: 32% of real modifications are unpaired, and judging whether a
  # given one is wrong needs a human.
  s=$(p85 | sed 's/[[:space:]]*#.*$//')
  ! echo "$s" | grep -qE '(rm|git rm|sed -i) .*test' || { echo "churn phase mutates tests"; return 1; }
  p85 | grep -qiF 'report' || { echo "not labelled report-only"; return 1; }
}

@test "Phase 8.5 explains what an unpaired edit means" {
  p85 | grep -qiE 'change.detector|coupled' \
    || { echo "the operator is given a number with no interpretation"; return 1; }
}

@test "Phase 5 tdd-rules forbids editing shared fixtures" {
  # conftest.py was the single most-churned test file in the real repo at 31
  # edits; one fixture change ripples to every test using it.
  p5 | grep -qiF 'fixture' || { echo "no fixture rule reaches the executor"; return 1; }
}

@test "Phase 8.5 bash parses" {
  blk=$(p85 | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f')
  [ -n "$blk" ]
  echo "$blk" > "$BATS_TEST_TMPDIR/p85.sh"
  run bash -n "$BATS_TEST_TMPDIR/p85.sh"
  [ "$status" -eq 0 ]
}
