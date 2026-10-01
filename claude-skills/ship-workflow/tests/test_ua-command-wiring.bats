#!/usr/bin/env bats
load helpers

@test "ship-next Phase 6 calls airos-binding CLI instead of sourcing it" {
  local command_file="$SHIP_SKILL_ROOT/commands/ship-next.md"
  # The intent is "invoke it as a CLI, never source it". Which subcommand Phase 6
  # happens to need is not the point — it now needs project_path only.
  run grep -F '~/.claude/skills/ship-workflow/lib/airos-binding.sh project_' "$command_file"
  [ "$status" -eq 0 ]
  run grep -F 'source ~/.claude/skills/ship-workflow/lib/airos-binding.sh' "$command_file"
  [ "$status" -eq 1 ]
}

@test "ship-compound resolves PROJECT before rendering the UA case stub" {
  run grep -F 'PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)' \
    "$SHIP_SKILL_ROOT/commands/ship-compound.md"
  [ "$status" -eq 0 ]
}

@test "ship-init seeds Architecture using airos-binding CLI" {
  local command_file="$SHIP_SKILL_ROOT/commands/ship-init.md"
  run grep -F 'PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)' "$command_file"
  [ "$status" -eq 0 ]
  run grep -F 'PROJECT_PATH=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)' "$command_file"
  [ "$status" -eq 0 ]
}
