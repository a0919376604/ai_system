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

@test "Phase 8.5 records a machine-readable coverage report before and after" {
  run grep -F 'coverage json -q -o .ship/cov-before.json' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'coverage json -q -o .ship/cov-after.json' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 rolls back on a coverage regression or a failing test run" {
  run grep -F 'git checkout -- tests/' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'rolled back (coverage regression)' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'rolled back (tests failed)' "$CMD"
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

@test "Phase 8.5 gates on exact per-file coverage, not a rounded percentage" {
  run grep -F 'lib/coverage-diff.py' "$CMD"
  [ "$status" -eq 0 ]
  # The percentage gate is gone: it hid a 903 -> 902 statement loss behind `90`.
  run grep -F 'coverage report --format=total' "$CMD"
  [ "$status" -ne 0 ]
}

@test "Phase 8.5 requires fresh coverage exports, not leftovers from an earlier run" {
  run grep -F 'rm -f .ship/cov-before.json' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'rm -f .ship/cov-after.json' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'rolled back (coverage export failed after pruning)' "$CMD"
  [ "$status" -eq 0 ]
  # `|| true` swallowed the export failure and let a stale report be compared.
  run grep -F 'coverage json -q -o .ship/cov-after.json 2>/dev/null || true' "$CMD"
  [ "$status" -ne 0 ]
}
