#!/usr/bin/env bats
# R-003: how the security pass is wired into ship-next Phase 6. The behaviour of
# the new blocks is exercised in test_command-blocks.bats; these pin the wiring.
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }

p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }

@test "the reviewer is told about the [pre-existing] tag" {
  p6 | grep -qF -- '- `[pre-existing]` — the defect exists on' || { echo "extra checks lack [pre-existing]"; return 1; }
}

@test "the loop parses the code review and the security review together" {
  p6 | grep -qF 'code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT"' || { echo "security findings are not counted"; return 1; }
}

@test "blockers from both reviews are printed, minus the anchored pre-existing ones" {
  # Run the loop's own print line. With two files grep prefixes each line with its
  # file name unless -h, and the anchored pre-existing filter then removes nothing.
  # The whole interactive print: from the 🛑 header to the closing `fi`.
  p6 | awk 'index($0, "echo \"🛑 ${BLOCKING_COUNT}") {f=1; next} f && /^[[:space:]]*fi[[:space:]]*$/ {exit} f' > "$BATS_TEST_TMPDIR/print.sh"
  [ -s "$BATS_TEST_TMPDIR/print.sh" ] || return 1
  d="$BATS_TEST_TMPDIR"
  printf '%s\n' '🔴 [blocking] [pre-existing] old.sh:1 — OLD-DEFECT' \
                '   Base evidence: old.sh:1 exists unchanged on main' '' \
                '🔴 [blocking] a.sh:2 — NEW-CODE' > "$d/rev.md"
  printf '%s\n' '🔴 [blocking] [security:sqli] b.sh:3 — NEW-SEC' > "$d/sec.md"
  run bash -c "source '$SHIP_LIB/pre-existing.sh'; REVIEW_OUT='$d/rev.md'; SEC_OUT='$d/sec.md'; . '$d/print.sh'"
  [[ "$output" == *NEW-CODE* ]] || return 1
  [[ "$output" == *NEW-SEC* ]] || return 1
  [[ "$output" != *OLD-DEFECT* ]] || { echo "printed a pre-existing finding as a blocker"; return 1; }
  [[ "$output" != *"Base evidence"* ]] || { echo "printed a pre-existing finding's detail lines"; return 1; }
}

@test "pre-existing findings get their own step and never feed BLOCKING_COUNT" {
  step=$(awk '/^4\.5\. \*\*Pre-existing findings/,/^## Phase 7/' "$CMD")
  [ -n "$step" ] || { echo "no step 4.5"; return 1; }
  echo "$step" | grep -qF 'pre_existing_tracked' || return 1
  if echo "$step" | grep -qE 'BLOCKING_COUNT[[:space:]]*='; then echo "step 4.5 changes BLOCKING_COUNT"; return 1; fi
}

@test "the landed commit and the auto summary report the security review" {
  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'Security review:' || { echo "Phase 7 body has no security line"; return 1; }
  awk '/^## Phase 9/,0' "$CMD" | grep -qF '• security review:' || { echo "Phase 9 summary has no security line"; return 1; }
}

@test "new Phase 6 blocks use no positional parameters (Claude Code substitutes them)" {
  # Claude Code replaces $0, $1, … in a command file with the invocation's
  # arguments, so `$1` inside a block becomes the user's first argument.
  blocks=$(awk '/^1\.5\. \*\*Security pass/,/^2\. \*\*Loop/' "$CMD"; awk '/^4\.5\. \*\*Pre-existing findings/,/^## Phase 7/' "$CMD")
  [ -n "$blocks" ]
  if echo "$blocks" | grep -qE '\$[0-9@#*]|(^|[[:space:]])shift([[:space:]]|$)|set --'; then
    echo "a new block uses a positional parameter"; return 1
  fi
}

@test "the loop clears the previous code-review report and refuses a failed parse" {
  # Both reports, at the top of every attempt: if step 1.5 is skipped, an earlier
  # run's "No security findings." must not be what the parse reads.
  p6 | grep -B1 -F 'rm -f "$REVIEW_OUT" "$SEC_OUT"' | grep -qF 'SEC_OUT=/tmp/ship-next-security-' \
    || { echo "a stale report can be reused"; return 1; }
  p6 | grep -A1 -F 'PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")' \
    | grep -qF '|| {' || { echo "a failed parse passes the gate"; return 1; }
}

@test "step 4 files majors from both reports, minus pre-existing ones" {
  step=$(awk '/^4\. \*\*Major findings handling/,/^4\.5\. \*\*Pre-existing findings/' "$CMD")
  echo "$step" | grep -F 'MAJOR_LINES=' | grep -qF '"$REVIEW_OUT" "$SEC_OUT"' || { echo "security importants are not filed"; return 1; }
  echo "$step" | grep -qF 'grep -vE "$PRE_EXISTING_RE"' || { echo "pre-existing findings are filed as majors"; return 1; }
}

@test "the landed commit and the auto summary say when the security review was off" {
  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'security-review-state' || return 1
  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'off (ship-config on' || return 1
  awk '/^## Phase 9/,0' "$CMD" | grep -qF 'security-review-state'
}

@test "security runs once code review reports zero blockers on the attempt" {
  p6 | grep -qF 'Security pass (once code review clears the attempt)'
  p6 | grep -qF 'code review reports 0 blockers'
}

@test "ship-next offers a Small-change lane before planning" {
  awk '/^## Phase 3 /,/^## Phase 5 /' "$CMD" | grep -qF 'Small-change lane'
}
