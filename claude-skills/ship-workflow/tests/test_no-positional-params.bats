#!/usr/bin/env bats
load helpers
# Claude Code replaces $0..$9 in a command file with the invocation's arguments
# before the agent reads it (R-007). Shell/awk positionals belong in lib/.
@test "no command file contains a positional parameter" {
  run grep -nE '\$[0-9]' "$SHIP_SKILL_ROOT"/commands/*.md
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "no skill file contains a positional parameter" {
  run grep -nE '\$[0-9]' "$SHIP_SKILL_ROOT"/../*/SKILL.md
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}
