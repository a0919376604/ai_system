#!/usr/bin/env bats
# run-plan Step 2 builds the codex prompt. R-014: it must point codex at the rule
# files ship-next renders, instead of relying on each plan to mention them.
load helpers

setup() { export SCRATCH="$(make_scratch run-plan-prompt)"; }
teardown() { rm -rf "$SCRATCH" "/tmp/run-plan-prompt-r014test.txt"; }

step2() {
  awk '/^## Step 2/{f=1} /^## Step 3/{f=0} f' "$SHIP_SKILL_ROOT/../run-plan/SKILL.md" \
    | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

@test "the codex prompt tells codex to read the .ship rule files before the plan" {
  printf '# Plan\n### Task 1: x\n' > "$SCRATCH/plan.md"
  step2 > "$SCRATCH/step2.sh"
  [ -s "$SCRATCH/step2.sh" ]
  run env SLOT=r014test BRANCH=ship/R-1-x PLAN_ABS="$SCRATCH/plan.md" bash "$SCRATCH/step2.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  P=/tmp/run-plan-prompt-r014test.txt
  rules=$(grep -n '\.ship/ponytail-rules\.md' "$P" | head -1 | cut -d: -f1)
  tdd=$(grep -n '\.ship/tdd-rules\.md' "$P" | head -1 | cut -d: -f1)
  plan=$(grep -n '^PLAN (' "$P" | head -1 | cut -d: -f1)
  [ -n "$rules" ] && [ -n "$tdd" ] && [ -n "$plan" ] || { cat "$P"; return 1; }
  [ "$rules" -lt "$plan" ] && [ "$tdd" -lt "$plan" ]
}
