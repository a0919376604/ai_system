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

@test "Phase 8.5 deletes nothing — structural, not a denylist" {
  # Scan the executable bash only. The prose deliberately says "there is no coverage
  # run", and scanning the whole section would match its own explanation.
  block=$(awk '/^## Phase 8.5/,/^## Phase 8.7/' "$CMD" \
          | awk '/^   ```bash/{f=1;next}/^   ```/{f=0}f')
  [ -n "$block" ]

  # 1. The ONLY git subcommand allowed here is `diff`. One rule kills add, rm, commit,
  #    checkout, restore and stash, including forms like `git add -- tests/x.py` that
  #    a literal denylist of `git add tests/` misses.
  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    if [ "$sub" != "diff" ]; then
      echo "Phase 8.5 runs a mutating git subcommand: git $sub"
      return 1
    fi
  done <<< "$(echo "$block" | grep -oE '\bgit +[a-z][a-z-]*' | awk '{print $2}')"

  # 2. No file-mutating command at all.
  for verb in rm mv cp truncate tee install chmod 'sed -i' shred unlink; do
    if echo "$block" | grep -qE "(^|[|;&(]|[[:space:]])${verb}([[:space:]]|$)"; then
      echo "Phase 8.5 runs a file-mutating command: $verb"
      return 1
    fi
  done

  # 3. Every redirect must target .ship/ or /dev/null. Truncating a test file with
  #    `> tests/x.py` writes nothing recognisable as a command.
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$target" in
      .ship/*|/dev/null) ;;
      *) echo "Phase 8.5 redirects outside .ship/: $target"; return 1 ;;
    esac
  done <<< "$(echo "$block" | grep -oE '>>?[[:space:]]*[^[:space:];|)]+' | sed -E 's/^>>?[[:space:]]*//')"
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
  SPEC="$SHIP_SKILL_ROOT/../../docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md"
  for f in "$CMD" "$SPEC"; do
    [ -f "$f" ] || continue
    for claim in 'coverage-gated' 'pruning commit' 'test: prune'; do
      if grep -qF -- "$claim" "$f"; then
        echo "$f still claims: $claim"
        return 1
      fi
    done
  done
}
