#!/usr/bin/env bats
load helpers

@test "bats is wired up" {
  result="$(echo hello)"
  [ "$result" = "hello" ]
}

@test "helpers expose SHIP_SKILL_ROOT" {
  [ -n "$SHIP_SKILL_ROOT" ]
  [ -d "$SHIP_SKILL_ROOT/lib" ]
}

@test "make_scratch creates a fresh directory" {
  scratch="$(make_scratch smoke)"
  [ -d "$scratch" ]
  rm -rf "$scratch"
}

@test "make_fake_airos creates 4 strategy files" {
  scratch="$(make_scratch smoke-airos)"
  airos="$(make_fake_airos "$scratch" foo)"
  [ -f "$airos/10 Projects/foo/VISION.md" ]
  [ -f "$airos/10 Projects/foo/STRATEGY.md" ]
  [ -f "$airos/10 Projects/foo/ROADMAP.md" ]
  [ -f "$airos/10 Projects/foo/QUARTERLY_GOALS.md" ]
  rm -rf "$scratch"
}
