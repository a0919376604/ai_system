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

@test "P5 tdd-rules carries the governing rules" {
  # Asserted against the RENDERED output, not against ship-next.md. The rules
  # moved into lib/tdd-rules.sh so a repo can add its own; pinning them to the
  # command file pinned them to one location rather than to their effect.
  run bash -c "cd '$BATS_TEST_TMPDIR' && git init -q && \
    source '$SHIP_LIB/tdd-rules.sh' && tdd_rules_render R-001 /dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'Tests attach only to the seams listed below.' || return 1
  echo "$output" | grep -qF 'Behavior unchanged => tests unchanged.' || return 1
  echo "$output" | grep -qF 'One test, one behavior.' || return 1
}
