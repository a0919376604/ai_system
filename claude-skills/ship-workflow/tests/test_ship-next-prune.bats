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

@test "Phase 8.5 never falls back to pruning the whole tests/ directory" {
  run grep -F 'TEST_TARGETS="tests/"' "$CMD"
  [ "$status" -ne 0 ]
  run grep -F 'skipped (no scoped test targets' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 uses the fail-closed coverage helper, not inline integer compare" {
  run grep -F 'tb_coverage_ok "$COV_AFTER" "$COV_BEFORE"' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'COV_AFTER:-0}" -lt' "$CMD"
  [ "$status" -ne 0 ]
}

@test "Phase 8.5 sources test-budget.sh before calling tb_coverage_ok" {
  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD")
  src_line=$(echo "$block" | grep -n 'lib/test-budget.sh' | head -1 | cut -d: -f1)
  call_line=$(echo "$block" | grep -n 'tb_coverage_ok "\$COV_AFTER"' | head -1 | cut -d: -f1)
  [ -n "$src_line" ]
  [ -n "$call_line" ]
  [ "$src_line" -lt "$call_line" ]
}

@test "Phase 8.5 pins the coverage measurement scope with --source" {
  run grep -cF 'coverage run --source="$COV_SOURCE" -m pytest' "$CMD"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  # A bare run would let a deleted module fall out of the report and the average rise.
  run grep -F 'coverage run -m pytest' "$CMD"
  [ "$status" -ne 0 ]
}

@test "Phase 8.5 checks the baseline pytest exit code before trusting coverage" {
  run grep -F 'skipped (baseline tests not green)' "$CMD"
  [ "$status" -eq 0 ]
  # The `;` form discarded pytest's exit status.
  run grep -F '>/dev/null 2>&1; coverage report' "$CMD"
  [ "$status" -ne 0 ]
}

@test "Phase 8.5 bash blocks parse as valid shell" {
  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD" \
          | awk '/^   ```bash/{f=1;next}/^   ```/{f=0}f' | sed 's/^   //')
  [ -n "$block" ]
  echo "$block" > "$BATS_TEST_TMPDIR/p85.sh"
  run bash -n "$BATS_TEST_TMPDIR/p85.sh"
  [ "$status" -eq 0 ]
}
