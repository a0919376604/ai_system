#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "Phase 8.7 sits between Phase 8.5 and Phase 9" {
  p85=$(grep -n '^## Phase 8.5' "$CMD" | cut -d: -f1)
  p87=$(grep -n '^## Phase 8.7' "$CMD" | cut -d: -f1)
  p9=$(grep -n '^## Phase 9' "$CMD" | cut -d: -f1)
  [ "$p85" -lt "$p87" ]
  [ "$p87" -lt "$p9" ]
}

@test "Phase 8.7 reuses the existing 50-file drift threshold" {
  run grep -F 'DRIFT_COUNT" -gt 50' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.7 runs /understand only above the threshold" {
  run grep -F 'Invoke `/understand`' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.7 is a silent no-op when UA is absent" {
  run grep -F 'ua_check_installed' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P9 summary reports CONTEXT, test budget, prune, ponytail drift and UA" {
  run grep -F 'CONTEXT.md: ${CONTEXT_MD_STATUS}' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'Test pruning: ${PRUNE_STATUS}' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'ruleset changed, this ship used the new version' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'UA KG rebuilt' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P9 log row carries the ratio field that drives shadow mode" {
  run grep -F 'ratio ${SHIP_RATIO_BP}bp' "$CMD"
  [ "$status" -eq 0 ]
}
