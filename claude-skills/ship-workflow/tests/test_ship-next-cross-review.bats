#!/usr/bin/env bats
load helpers

setup() {
  export SHIP_LIB
  export SCRATCH="$(make_scratch cross-review)"
  mkdir -p "$SCRATCH/real/.claude" "$SCRATCH/bin"
  ln -s "$SCRATCH/real" "$SCRATCH/wt"
  export WT="$SCRATCH/wt" REVIEW_OUT="$SCRATCH/review" CALLS="$SCRATCH/calls"
  export PATH="$SCRATCH/bin:$PATH"
  source "$SHIP_LIB/ship-next.sh"
  sn_state_set "$WT" ORIG_BRANCH main
  echo 2 > "$WT/.claude/.ship-executor"
  echo '🟢 [nit] pay.py:4 — style' > "$REVIEW_OUT"
  cp "$REVIEW_OUT" "$SCRATCH/before"
  : > "$CALLS"
  cat > "$SCRATCH/bin/codex" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
printf '%s' "$STUB_OUT"
exit "${STUB_EXIT:-0}"
STUB
  chmod +x "$SCRATCH/bin/codex"
  fixture "$WT"
}
teardown() { rm -rf "$SCRATCH"; }
fixture() {
  export STUB_OUT
  STUB_OUT=$(cat <<'FIXTURE'
Both changed functions introduce verified behavioral regressions: totals omit the first item, and refunds can produce negative balances.

Full review comments:

- [P1] Include the first item in the cart total — <WT>/pay.py:3-3
  For any nonempty cart, `items[1:]` excludes the first item's price, undercounting the total whenever that price is nonzero. For example, `total([{"price": 10}])` now returns `0` instead of `10`. Sum all items to preserve the documented behavior.

- [P2] Restore the zero floor for refund balances — <WT>/pay.py:8-8
  When `amount` exceeds `balance`, the subtraction now returns a negative balance, violating the function's documented invariant. For example, `refund(15, 10)` returns `-5` instead of `0`. Restore the zero clamp.
FIXTURE
)
  STUB_OUT="${STUB_OUT//<WT>/$1}"
}
cross_review() {
  run "${1:-bash}" -c 'grep() { return 1; }; source "$SHIP_LIB/ship-next.sh"; sn_cross_review "$WT" "$REVIEW_OUT"'
}
assert_findings() {
  [ "$status" -eq 0 ]
  cat "$SCRATCH/before" > "$SCRATCH/expected"
  cat >> "$SCRATCH/expected" <<'EXPECTED'
🔴 [blocking] [codex] [both] Include the first item in the cart total — pay.py:3
   For any nonempty cart, `items[1:]` excludes the first item's price, undercounting the total whenever that price is nonzero. For example, `total([{"price": 10}])` now returns `0` instead of `10`. Sum all items to preserve the documented behavior.
🟡 [important] [codex] Restore the zero floor for refund balances — pay.py:8
   When `amount` exceeds `balance`, the subtraction now returns a negative balance, violating the function's documented invariant. For example, `refund(15, 10)` returns `-5` instead of `0`. Restore the zero clamp.
EXPECTED
  diff -u "$SCRATCH/expected" "$REVIEW_OUT"
  sn_state_load "$WT"
  [ "$CROSS_REVIEW" = ran ]
  [ "$CROSS_REVIEW_COUNT" = 2 ]
  [ "$CROSS_REVIEW_BOTH" = 1 ]
  [ "$(cat "$CALLS")" = 'review --base main -c model_reasoning_effort="high"' ]
}
assert_unavailable() {
  [ "$status" -eq 0 ]
  [[ "$output" == *'WARN: cross-review unavailable — '* ]] || return 1
  cmp "$SCRATCH/before" "$REVIEW_OUT"
  sn_state_load "$WT"
  [ "$CROSS_REVIEW" = unavailable ]
  [ "$CROSS_REVIEW_COUNT" = 0 ]
  [ "$CROSS_REVIEW_BOTH" = 0 ]
}
@test "AC-1 exact findings and nearby overlap" { cross_review; assert_findings; }
@test "AC-1 zsh" { cross_review zsh; assert_findings; }
@test "AC-2 physical worktree paths" {
  fixture "$(cd "$WT" && pwd -P)"
  cross_review
  assert_findings
}
@test "AC-3 no findings preserves review" {
  export STUB_OUT='No actionable regressions were identified in the diff. All 44 targeted tests passed, and the generated API command uses supported glab flags. Live GitLab behavior was not tested.'
  cross_review
  [ "$status" -eq 0 ]
  cmp "$SCRATCH/before" "$REVIEW_OUT"
  sn_state_load "$WT"
  [ "$CROSS_REVIEW" = ran ]
  [ "$CROSS_REVIEW_COUNT" = 0 ]
}
@test "AC-4 codex executor skips invocation" {
  echo 3 > "$WT/.claude/.ship-executor"
  cross_review
  [ "$status" -eq 0 ]
  [[ "$output" == *'skipped — codex wrote this code'* ]] || return 1
  [ ! -s "$CALLS" ]
  cmp "$SCRATCH/before" "$REVIEW_OUT"
  sn_state_load "$WT"
  [ "$CROSS_REVIEW" = skipped ]
}
@test "AC-5 missing codex" {
  rm "$SCRATCH/bin/codex"
  for tool in mkdir grep mv; do ln -s "$(command -v "$tool")" "$SCRATCH/bin/$tool"; done
  run /bin/bash -c 'export PATH="$SCRATCH/bin"; source "$SHIP_LIB/ship-next.sh"; sn_cross_review "$WT" "$REVIEW_OUT"'
  assert_unavailable
}
@test "AC-5 nonzero exit discards stdout" {
  export STUB_EXIT=1
  cross_review
  assert_unavailable
}
@test "AC-5 empty stdout" {
  export STUB_OUT=''
  cross_review
  assert_unavailable
}
@test "AC-6 codex P1 blocks in existing parser" {
  cross_review
  [ "$status" -eq 0 ]
  run "$SHIP_LIB/code-review-parse.sh" "$REVIEW_OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'BLOCKING_COUNT=1'* ]] || return 1
}
@test "description prose is not a finding" {
  export STUB_OUT="$STUB_OUT
  Description — x.py:9 with [P1] in prose."
  cross_review
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$REVIEW_OUT")" = '   Description — x.py:9 with [P1] in prose.' ]
  sn_state_load "$WT"
  [ "$CROSS_REVIEW_COUNT" = 2 ]
}
@test "outside worktree paths are preserved" {
  fixture /elsewhere
  cross_review
  [ "$status" -eq 0 ]
  grep -qF ' — /elsewhere/pay.py:3' "$REVIEW_OUT"
  grep -qF ' — /elsewhere/pay.py:8' "$REVIEW_OUT"
}

presentation_state() {
  sn_state_set "$WT" CROSS_REVIEW "$1"
  sn_state_set "$WT" CROSS_REVIEW_COUNT 2
  sn_state_set "$WT" CROSS_REVIEW_BOTH 1
  sn_state_set "$WT" AUTO 1
  sn_state_set "$WT" SHIP_MERGE_MODE squash
}
log_row() {
  cd "$WT"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p docs/learnings
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_log "$WT" R-9 ""'
  [ "$status" -eq 0 ]
  grep -qF "$1" docs/learnings/_log.md
}
@test "AC-7 log ran" { presentation_state ran; log_row 'xreview=2/1'; }
@test "AC-7 log skipped" { presentation_state skipped; log_row 'xreview=skipped'; }
summary_line() {
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_summary "$WT" R-9'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "• cross-review (codex): $1"
}
@test "AC-7 summary ran" {
  presentation_state ran
  summary_line '2 finding(s), 1 also found by code review'
}
@test "AC-7 summary skipped" {
  presentation_state skipped
  summary_line 'skipped — codex wrote this code'
}
@test "AC-7 summary unavailable" {
  presentation_state unavailable
  summary_line unavailable
}
@test "AC-8 step 1.3 executes in fresh bash and zsh" {
  block=$(awk '/^1\.3\./{step=1} step && /```bash/{code=1;next} code && /```/{exit} code{print}' "$SHIP_SKILL_ROOT/../pr-review/SKILL.md")
  [[ "$block" == *'sn_cross_review "$WORKTREE" "$REVIEW_OUT"'* ]] || return 1
  block="${block//\~\/.claude\/skills\/ship-workflow\/lib/$SHIP_LIB}"
  export ID="R-019-test-$$" attempt=1 WORKTREE="$WT"
  for shell in bash zsh; do
    run "$shell" -c "$block"
    [ "$status" -eq 0 ]
    grep -qF '[codex]' "/tmp/ship-next-review-${ID}-${attempt}.md"
    rm "/tmp/ship-next-review-${ID}-${attempt}.md"
  done
}
@test "AC-8 loop names cross-review before parse" {
  awk '
    /# pr-review step 1.3 appends codex\047s cross-review to \$REVIEW_OUT \(Claude-written ships only\)\./ {found=1}
    /PARSED=.*code-review-parse.sh/ {exit !found}
    END {if (!found) exit 1}
  ' "$SHIP_SKILL_ROOT/commands/ship-next.md"
}
