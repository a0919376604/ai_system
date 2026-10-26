#!/usr/bin/env bats
load helpers

p6() { awk '/^## Phase 6/,/^## Phase 7/' "$SHIP_SKILL_ROOT/commands/ship-next.md"; }

@test "a numbered step renders the prompt and checks the report" {
  p6 | command grep -qE '^1\.4\. \*\*Spec review' || return 1
  step=$(p6 | awk '/^1\.4\./,/^1\.5\./')
  for text in 'SPEC_OUT="/tmp/ship-next-spec-${ID}-${attempt}.md"' 'sn_spec_review_render' 'sn_spec_review_check "$SPEC_OUT"'; do
    [[ "$step" == *"$text"* ]] || return 1
  done
}

@test "the loop clears, parses and prints the spec report" {
  text=$(p6)
  for expected in 'SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md' \
    'rm -f "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"' \
    'code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT")' \
    'code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT")' \
    'pre_existing_drop "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"'; do
    [[ "$text" == *"$expected"* ]] || { echo "missing $expected"; return 1; }
  done
}

@test "step 4 files spec majors" {
  p6 | command grep -F 'MAJOR_LINES=' | command grep -qF '"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"'
}

@test "SPEC_GAPS_FOUND is written once" {
  export SHIP_LIB WT="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$WT"
  line=$(p6 | command grep -F 'SPEC_GAPS_FOUND="$SPEC_GAP_COUNT"')
  [ -n "$line" ] || return 1
  [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" = 1 ] || return 1
  export SAVE_SPEC_COUNT="$line"
  for count in 2 0; do
    run env SPEC_GAP_COUNT="$count" bash -c 'source "$SHIP_LIB/ship-next.sh"; WORKTREE=$WT; sn_state_load "$WT"; eval "$SAVE_SPEC_COUNT"'
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  done
  command grep -qx 'SPEC_GAPS_FOUND=2' "$WT/.ship/state.env"
}

@test "the blocker print shows spec blockers" {
  p6 | awk 'index($0, "echo \"🛑 ${BLOCKING_COUNT}") {f=1; next} f && /^[[:space:]]*fi[[:space:]]*$/ {exit} f' > "$BATS_TEST_TMPDIR/print.sh"
  [ -s "$BATS_TEST_TMPDIR/print.sh" ] || return 1
  d="$BATS_TEST_TMPDIR"
  printf '%s\n' '🔴 [blocking] [pre-existing] old.sh:1 — OLD-DEFECT' \
                '   Base evidence: old.sh:1 exists unchanged on main' '' \
                '🔴 [blocking] a.sh:2 — NEW-CODE' > "$d/rev.md"
  printf '%s\n' '🔴 [blocking] [security:sqli] b.sh:3 — NEW-SEC' > "$d/sec.md"
  printf '%s\n' '🔴 [blocking] [spec:missing] NEW-SPEC' > "$d/spec.md"
  run bash -c "source '$SHIP_LIB/pre-existing.sh'; REVIEW_OUT='$d/rev.md'; SPEC_OUT='$d/spec.md'; SEC_OUT='$d/sec.md'; . '$d/print.sh'"
  [[ "$output" == *NEW-SPEC* ]] || return 1
  [[ "$output" == *NEW-CODE* ]] || return 1
  [[ "$output" == *NEW-SEC* ]] || return 1
  [[ "$output" != *OLD-DEFECT* ]] || return 1
  [[ "$output" != *"Base evidence"* ]]
}

@test "spec report check runs in a fresh command-block shell" {
  export SHIP_LIB ID="R-T16-spec-$$" attempt=1
  report="/tmp/ship-next-spec-${ID}-${attempt}.md"
  p6 | awk '/^1\.4\./{f=1} /^1\.5\./{f=0} f' \
    | awk '/^[[:space:]]*```bash/{n++; f=1; next} /^[[:space:]]*```/{f=0} f && n==2' \
    | sed 's#~/.claude/skills/ship-workflow/lib/#"$SHIP_LIB"/#g' > "$BATS_TEST_TMPDIR/check.sh"
  printf '%s\n' 'No spec gaps.' > "$report"
  for shell in bash zsh; do
    run "$shell" "$BATS_TEST_TMPDIR/check.sh"
    [ "$status" -eq 0 ] || { rm -f "$report"; echo "$output"; return 1; }
  done
  rm -f "$report"
}
