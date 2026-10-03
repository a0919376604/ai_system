#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-compound.md"; }

@test "ship-compound resolves the merge mode and sources the lib" {
  grep -qF 'lib/merge-mode.sh' "$CMD" || { echo "never sourced"; return 1; }
  grep -qF 'MERGE_MODE=$(merge_mode)' "$CMD" || { echo "mode not resolved"; return 1; }
}

@test "ship-compound does not mark Done while a review is open" {
  # Marking Done before the MR merges makes the ROADMAP claim something that
  # has not happened. mr mode uses --mark-review instead.
  grep -qF -- '--mark-review' "$CMD" || { echo "no in-review path"; return 1; }
  sec=$(awk '/^7\. \*\*Update ROADMAP/,/^7b\./' "$CMD")
  echo "$sec" | grep -qF 'MERGE_MODE' || { echo "the Done move is unconditional"; return 1; }
}

@test "ship-compound commits on the review branch, not the base, in mr mode" {
  sec=$(awk '/^9\. \*\*Log \+ commit/,0' "$CMD")
  echo "$sec" | grep -qF 'MERGE_MODE' \
    || { echo "learnings land on the base branch while the work is unmerged"; return 1; }
}
