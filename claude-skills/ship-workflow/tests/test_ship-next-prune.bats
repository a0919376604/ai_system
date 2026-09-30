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

@test "Phase 8.5 bash mutates nothing — executed, on a fixture that reaches the work" {
  # Textual guards were written here twice and defeated twice, so this one runs the
  # code. But a behavioural guard is only worth the path it exercises: the first
  # version stubbed both refs to HEAD, so the diff was empty, TEST_TARGETS was empty,
  # and the phase returned before its report branch. Injections placed inside that
  # branch were dead code and "passed". The fixture below drives the phase all the
  # way in, and the guard asserts it got there before trusting the result.
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/tests/src" "$repo/src"
  cd "$repo"
  git init -q .
  git config user.email t@t
  git config user.name t
  printf 'def f():\n    return 1\n' > src/a.py
  printf 'def test_f():\n    assert f() == 1\n' > tests/src/test_a.py
  git add -A
  git commit -q -m base
  base=$(git rev-parse HEAD)

  # A real diff on a NON-test source file, so MODULES resolves to src and
  # TEST_TARGETS maps to tests/src/*.py. Without this the report branch never runs.
  printf 'def f():\n    return 2\n' > src/a.py
  git add -A
  git commit -q -m change
  head=$(git rev-parse HEAD)

  # Dirty, because on a clean tree git add / checkout / restore / stash are no-ops.
  printf 'def test_f():\n    assert f() == 2\n    assert f() != 9\n' > tests/src/test_a.py
  printf 'def test_g():\n    assert True\n' > tests/src/test_b.py
  git add tests/src/test_b.py
  # .ship/ exists in a real run, so `.ship/../tests/x.py` traversal resolves.
  mkdir -p .ship

  snapshot() {
    git status --porcelain -- . ':(exclude).ship' | sort
    git diff --cached --name-status | sort
    git stash list
    find tests -type f | sort | while IFS= read -r f; do shasum "$f"; done
    git rev-parse HEAD
  }
  before=$(snapshot)

  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD" \
          | awk '/^   ```bash/{f=1;next}/^   ```/{f=0}f' | sed 's/^   //')
  [ -n "$block" ]
  out=$(TEST_BUDGET_VERDICT=major ORIG_BRANCH="$base" BRANCH="$head" \
        bash -c "$block; echo \"PRUNE_STATUS=\$PRUNE_STATUS\"" 2>&1) || true

  # Prove the report branch actually ran. If this ever regresses to "no scoped test
  # targets", the guard is vacuous again and must fail loudly rather than pass.
  if echo "$out" | grep -q 'no scoped test targets'; then
    echo "guard is vacuous: fixture never reached the report branch"
    echo "$out"
    return 1
  fi
  echo "$out" | grep -q 'prune candidate' || {
    echo "guard did not reach the candidate step; got: $out"; return 1; }

  after=$(snapshot)
  if [ "$before" != "$after" ]; then
    echo "Phase 8.5 changed the tree:"
    diff <(echo "$before") <(echo "$after") || true
    return 1
  fi
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

@test "Phase 8.5 counts candidates by a prefix a header cannot match" {
  run grep -F "grep -c '^CANDIDATE: '" "$CMD"
  [ "$status" -eq 0 ]
  # A Markdown table's header and separator are indistinguishable from data when
  # counting: one candidate read as two, an empty report read as one.
  run grep -F "grep -c '^| '" "$CMD"
  [ "$status" -ne 0 ]
}

@test "Phase 9 log row carries the prune status, not only the summary" {
  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
  [ -n "$row" ]
  [[ "$row" == *'prune: ${PRUNE_STATUS}'* ]]
}

@test "no shipped document still claims Phase 8.5 deletes or commits" {
  DOCS="$SHIP_SKILL_ROOT/../../docs/superpowers"
  SPEC="$DOCS/specs/2026-09-28-ship-next-context-and-test-discipline-design.md"
  PLAN="$DOCS/plans/2026-09-28-ship-next-context-and-test-discipline-impl.md"
  for f in "$CMD" "$SPEC" "$PLAN"; do
    [ -f "$f" ] || continue
    for claim in 'coverage-gated' 'pruning commit' 'test: prune'; do
      # The plan's Execution log quotes these strings while recording that they were
      # wrong. Only prescriptive text counts: the log starts at "## Execution log".
      body=$(awk '/^## Execution log/{exit} {print}' "$f")
      if echo "$body" | grep -qF -- "$claim"; then
        echo "$f prescribes: $claim"
        return 1
      fi
    done
  done
}

@test "Phase 8.5 candidate count cannot render as 00" {
  # `grep -c` prints 0 AND exits 1 when it matches nothing, so `|| echo 0` appended a
  # second zero and an empty report displayed as `00`.
  run grep -F "|| echo 0)" "$CMD"
  [ "$status" -ne 0 ]
  run grep -F "grep -c '^CANDIDATE: ' .ship/prune-candidates.md 2>/dev/null || true" "$CMD"
  [ "$status" -eq 0 ]
}

@test "spec prescribes a behavioural P8.5 check, not a rollback simulation" {
  SPEC="$SHIP_SKILL_ROOT/../../docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md"
  [ -f "$SPEC" ]
  run grep -F 'P8.5 destroys nothing' "$SPEC"
  [ "$status" -eq 0 ]
  run grep -F 'Simulate a prune that drops coverage' "$SPEC"
  [ "$status" -ne 0 ]
}
