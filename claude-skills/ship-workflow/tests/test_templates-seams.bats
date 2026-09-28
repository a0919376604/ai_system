#!/usr/bin/env bats
load helpers

@test "SPEC template declares the Seams section" {
  run grep -F '## Seams' "$SHIP_SKILL_ROOT/templates/repo/SPEC.md"
  [ "$status" -eq 0 ]
}

@test "SPEC template states the seam assertion rule" {
  run grep -F 'nothing inside it' "$SHIP_SKILL_ROOT/templates/repo/SPEC.md"
  [ "$status" -eq 0 ]
}

@test "PLAN template carries a Seam label line" {
  run grep -E '^Seam: ' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
}

@test "PLAN template points executors at both .ship rule files" {
  run grep -F 'Read .ship/tdd-rules.md' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
  run grep -F 'Read .ship/ponytail-rules.md' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
}

@test "example global config documents the ponytail block" {
  run grep -F 'ponytail:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'pinned_version:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'ruleset_sha256:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
}

@test "example global config documents the test budget multipliers" {
  run grep -F 'test_budget:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'major_multiplier:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
}

@test "example global config does NOT store a per-repo ship counter" {
  run grep -iE 'shipped_count|ship_count' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -ne 0 ]
}

@test "SKILL.md global config section mentions ponytail" {
  run grep -F 'ponytail' "$SHIP_SKILL_ROOT/SKILL.md"
  [ "$status" -eq 0 ]
}
