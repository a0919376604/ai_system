#!/usr/bin/env bats
load helpers
setup() { CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }
p3() { awk '/^## Phase 3/,/^## Phase 4/' "$CMD"; }

@test "Phase 3 requires grilling rounds" {
  text=$(p3)
  for expected in 'recommended answer' 'numbered' 'sub-agent' '"yes" accepts'; do
    [[ "$text" == *"$expected"* ]] || { echo "missing $expected"; return 1; }
  done
}

@test "auto mode takes the recommended answer" {
  p3 | command grep -qF 'auto-picked recommended answer'
}

@test "option 1 is gone from Phase 3 and --auto:yes" {
  [[ "$(p3)" != *"option 1"* ]] || return 1
  line=$(awk '/^## Arguments/{f=1;next} /^## /{f=0} f' "$CMD" | command grep -F -- '- `--auto:yes`')
  [[ "$line" != *"option 1"* ]] || return 1
  [[ "$line" == *"recommended answer"* ]]
}
