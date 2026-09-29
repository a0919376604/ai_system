#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "Phase 8.5 exists and sits between Phase 8 and Phase 9" {
  run grep -n '^## Phase 8.5 — Test pruning' "$CMD"
  [ "$status" -eq 0 ]
  p85=$(grep -n '^## Phase 8.5' "$CMD" | cut -d: -f1)
  p8=$(grep -n '^## Phase 8 ' "$CMD" | cut -d: -f1)
  p9=$(grep -n '^## Phase 9' "$CMD" | cut -d: -f1)
  [ "$p8" -lt "$p85" ]
  [ "$p85" -lt "$p9" ]
}

@test "Phase 8.5 triggers only on the major verdict" {
  run grep -F 'TEST_BUDGET_VERDICT" != "major"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 scopes pruning to modules this ship touched" {
  run grep -F 'git diff --name-only "${ORIG_BRANCH}...${BRANCH}"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 records coverage before and after" {
  run grep -F 'COV_BEFORE' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'COV_AFTER' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 rolls back when coverage drops or tests fail" {
  run grep -F 'git checkout -- tests/' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'coverage dropped' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 commits separately from the R-NNN squash" {
  run grep -F 'test: prune redundant tests' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 runs in auto mode" {
  run grep -F 'because its invariants are machine-checked' "$CMD"
  [ "$status" -eq 0 ]
}
