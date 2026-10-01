#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "P3 sources context-md.sh and announces CONTEXT.md" {
  run grep -F 'lib/context-md.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CONTEXT.md present — Read it before brainstorm dialog.' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P3 tells brainstorming that ## Seams is a required section" {
  run grep -F 'required output section: `## Seams`' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P4 refuses in auto mode when the spec has no ## Seams" {
  run grep -F 'refused — spec has no' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P4 only warns about missing Seams in interactive mode" {
  run grep -F 'WARN: spec has no' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 renders both rule files into .ship/" {
  run grep -F '.ship/tdd-rules.md' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'ponytail_render_rules .ship/ponytail-rules.md' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 detects ponytail ruleset drift against the global pin" {
  run grep -F 'PONYTAIL_DRIFT=1' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F '[A]ccept and re-pin' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 drift never blocks the ship" {
  run grep -F 'Drift NEVER blocks' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 tdd-rules carries the three governing rules" {
  run grep -F 'Tests attach only to the seams listed below.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'Behavior unchanged => tests unchanged.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'One test, one behavior.' "$CMD"
  [ "$status" -eq 0 ]
}
