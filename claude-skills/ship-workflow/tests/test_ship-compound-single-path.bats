#!/usr/bin/env bats
load helpers

@test "ship-compound has no merge-mode branches (R-008)" {
  for w in MERGE_MODE ship_log_""defers context_""pending ship-""pending; do
    ! grep -qF "$w" "$SHIP_SKILL_ROOT/commands/ship-compound.md" || { echo "still mentions $w"; return 1; }
  done
}
