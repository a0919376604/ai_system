#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "P6 flags refactor tasks that added test lines as blocking" {
  run grep -F 'Seam: none' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'refactor task added test lines' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 sources test-budget.sh and exports the verdict" {
  run grep -F 'lib/test-budget.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'TEST_BUDGET_VERDICT=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 suppresses the budget finding while shadow mode is active" {
  run grep -F 'tb_shadow_active' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'shadow mode — reporting only' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 asks the reviewer for the three category tags" {
  run grep -F '.ship/review-extra-checks.md' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F '[seam-violation]' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 derives the raw added-line counts for the P7 message" {
  run grep -F 'tb_ship_lines "$ORIG_BRANCH" HEAD' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'TEST_LINES_ADDED=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P7 commit message carries the test ratio line" {
  run grep -F 'Tests: +' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'vs baseline' "$CMD"
  [ "$status" -eq 0 ]
}
