#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-compound.md"
}

@test "ship-compound sources context-md.sh" {
  run grep -F 'lib/context-md.sh' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound documents the CONTEXT.md entry format" {
  run grep -F -- '- **<term>** — <definition>' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound mirrors CONTEXT.md to the vault" {
  run grep -F 'spec-mirror.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CONTEXT.md' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound prunes to the 150-line target in interactive mode" {
  run grep -F 'prune to <= 150 lines' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound does NOT prune in auto mode" {
  run grep -F 'pruning is skipped in --auto:yes' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound exports CONTEXT_MD_STATUS for the P9 summary" {
  run grep -F 'CONTEXT_MD_STATUS=' "$CMD"
  [ "$status" -eq 0 ]
}
