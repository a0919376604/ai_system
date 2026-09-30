#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

# Extract every bash fence in Phase 8.5, at ANY indentation. The previous extractor
# required exactly three leading spaces, so a fence at column 0 was silently skipped
# and whatever it contained was never checked.
p85_bash() {
  awk '/^[[:space:]]*## Phase 8\.5/,/^[[:space:]]*## Phase 8\.7/' "$CMD" \
  | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' \
  | sed 's/^[[:space:]]*//'
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

@test "Phase 8.5 executes nothing but sourcing the lib and calling it" {
  # The logic now lives in lib/prune-report.sh, which is unit-tested directly. What is
  # left here is three lines, and three lines can be checked exhaustively — unlike the
  # twenty that preceded them, which needed an extraction harness that leaked for four
  # review rounds.
  body=$(p85_bash | grep -vE '^[[:space:]]*(#.*)?$')
  [ -n "$body" ]
  while IFS= read -r line; do
    case "$line" in
      'source ~/.claude/skills/ship-workflow/lib/prune-report.sh') ;;
      'PRUNE_STATUS=$(prune_report "$ORIG_BRANCH" "$BRANCH" "$TEST_BUDGET_VERDICT")') ;;
      *) echo "Phase 8.5 runs an unexpected statement: $line"; return 1 ;;
    esac
  done <<< "$body"
}

@test "Phase 8.5 sources the lib before calling it" {
  body=$(p85_bash | grep -vE '^[[:space:]]*(#.*)?$')
  src=$(echo "$body" | grep -n 'prune-report.sh' | head -1 | cut -d: -f1)
  call=$(echo "$body" | grep -n 'prune_report "' | head -1 | cut -d: -f1)
  [ -n "$src" ] && [ -n "$call" ]
  [ "$src" -lt "$call" ]
}

@test "Phase 8.5 instructs proposals only, in the CANDIDATE line format" {
  run grep -F 'Propose only; change no test file.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CANDIDATE: <test file>::<test name>' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 records why the coverage gate was abandoned" {
  run grep -F 'not whether an assertion' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'mutation testing' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 9 log row carries the prune status, not only the summary" {
  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
  [ -n "$row" ]
  [[ "$row" == *'prune: ${PRUNE_STATUS}'* ]]
}

@test "no coverage-gate machinery survives anywhere in the skill" {
  run grep -rlF 'coverage-diff.py' "$SHIP_SKILL_ROOT/lib" "$SHIP_SKILL_ROOT/commands"
  [ "$status" -ne 0 ]
  run grep -rlF 'tb_coverage_ok' "$SHIP_SKILL_ROOT/lib" "$SHIP_SKILL_ROOT/commands"
  [ "$status" -ne 0 ]
}

@test "no shipped document still claims Phase 8.5 deletes or commits" {
  DOCS="$SHIP_SKILL_ROOT/../../docs/superpowers"
  for f in "$CMD" \
           "$DOCS/specs/2026-09-28-ship-next-context-and-test-discipline-design.md" \
           "$DOCS/plans/2026-09-28-ship-next-context-and-test-discipline-impl.md"; do
    [ -f "$f" ] || continue
    # Only prescriptive text counts; the Execution log quotes these while recording
    # that they were wrong.
    body=$(awk '/^## Execution log/{exit} {print}' "$f")
    for claim in 'coverage-gated' 'pruning commit' 'test: prune'; do
      if echo "$body" | grep -qF -- "$claim"; then
        echo "$f prescribes: $claim"
        return 1
      fi
    done
  done
}

@test "spec prescribes a behavioural P8.5 check, not a rollback simulation" {
  SPEC="$SHIP_SKILL_ROOT/../../docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md"
  [ -f "$SPEC" ]
  run grep -F 'P8.5 destroys nothing' "$SPEC"
  [ "$status" -eq 0 ]
  run grep -F 'Simulate a prune that drops coverage' "$SPEC"
  [ "$status" -ne 0 ]
}
