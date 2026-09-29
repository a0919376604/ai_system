#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "Phase 8.5 exists and sits between Phase 8 and Phase 9" {
  run grep -n '^## Phase 8.5 — Test prune report' "$CMD"
  [ "$status" -eq 0 ]
  p85=$(grep -n '^## Phase 8.5' "$CMD" | cut -d: -f1)
  p8=$(grep -n '^## Phase 8 ' "$CMD" | cut -d: -f1)
  p9=$(grep -n '^## Phase 9' "$CMD" | cut -d: -f1)
  [ "$p8" -lt "$p85" ]
  [ "$p85" -lt "$p9" ]
}

@test "Phase 8.5 reports only on the major verdict" {
  run grep -F 'TEST_BUDGET_VERDICT" != "major"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 scopes its report to modules this ship touched" {
  run grep -F 'git diff --name-only "${ORIG_BRANCH}...${BRANCH}"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 deletes nothing — no test edits, no rollback, no commit" {
  # Scan the executable bash only. The prose deliberately says "there is no
  # coverage run", and a scan of the whole section would match its own explanation.
  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD" \
          | awk '/^   ```bash/{f=1;next}/^   ```/{f=0}f')
  [ -n "$block" ]
  # A rollback path only exists if something was destroyed first. A coverage run
  # only exists to gate a destruction. None of these may appear.
  for forbidden in \
    'git checkout -- tests/' \
    'git add tests/' \
    'test: prune redundant tests' \
    'coverage run' \
    'coverage json'
  do
    if echo "$block" | grep -qF -- "$forbidden"; then
      echo "Phase 8.5 still contains destructive machinery: $forbidden"
      return 1
    fi
  done
}

@test "Phase 8.5 states the candidates are proposals" {
  run grep -F 'Propose only; change no test file.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F '(nothing deleted)' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 writes the candidate list where Phase 9 can surface it" {
  run grep -F '.ship/prune-candidates.md' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'PRUNE_STATUS=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 records why the coverage gate was abandoned" {
  run grep -F 'not whether an assertion' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'mutation testing' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 needs no auto-mode exception now that nothing is destroyed" {
  run grep -F 'a report is' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 bash blocks parse as valid shell" {
  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD" \
          | awk '/^   ```bash/{f=1;next}/^   ```/{f=0}f' | sed 's/^   //')
  [ -n "$block" ]
  echo "$block" > "$BATS_TEST_TMPDIR/p85.sh"
  run bash -n "$BATS_TEST_TMPDIR/p85.sh"
  [ "$status" -eq 0 ]
}

@test "no coverage-gate machinery survives anywhere in the skill" {
  run grep -rlF 'coverage-diff.py' "$SHIP_SKILL_ROOT/lib" "$SHIP_SKILL_ROOT/commands"
  [ "$status" -ne 0 ]
  run grep -rlF 'tb_coverage_ok' "$SHIP_SKILL_ROOT/lib" "$SHIP_SKILL_ROOT/commands"
  [ "$status" -ne 0 ]
}
