#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-land.md"; }

@test "ship-land exists with frontmatter and a description" {
  [ -f "$CMD" ]
  head -1 "$CMD" | grep -q -- '---'
  grep -q '^description:' "$CMD"
}

@test "ship-land refuses to run before the review has actually merged" {
  # The whole point is that it finishes what mr mode deferred. Doing that on
  # an unmerged review would mark Done and delete the branch the review needs.
  grep -qiF 'merged' "$CMD" || { echo "no merge check"; return 1; }
  grep -qF 'land_is_merged "$BRANCH" "origin/${BASE}"' "$CMD" || { echo "merge state is never verified"; return 1; }
}

@test "ship-land moves the row to Done and clears in-review" {
  grep -qF 'in-review' "$CMD" || { echo "the in-review status is never cleared"; return 1; }
  grep -qiF 'Done' "$CMD" || { echo "the row is never moved to Done"; return 1; }
}

@test "ship-land cleans up what Phase 9 deliberately kept" {
  grep -qF 'git worktree remove' "$CMD" || { echo "worktree is never removed"; return 1; }
  grep -qF 'git branch -D "$BRANCH"' "$CMD" || { echo "branch is never deleted"; return 1; }
}

@test "ship-land folds deferred CONTEXT.md entries through the lib" {
  grep -qF 'lib/ship-land.sh' "$CMD" || { echo "lib not sourced"; return 1; }
  grep -qF 'land_context "$ID" "$BASE"' "$CMD" || { echo "deferred entries are never landed"; return 1; }
}

@test "ship-land never writes _log.md or pulls the operator's checkout" {
  # Both were in the first version: a local-only commit on the base branch that
  # was never pushed, and a pull on a checkout that may be dirty or behind.
  code=$(awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' "$CMD")
  if echo "$code" | grep -qF '_log.md'; then echo "ship-land writes _log.md"; return 1; fi
  if echo "$code" | grep -qE 'git pull'; then echo "ship-land pulls the operator checkout"; return 1; fi
}

@test "ship-land is registered as a ship-* command" {
  grep -qF 'ship-land' "$SHIP_SKILL_ROOT/SKILL.md" || { echo "not listed in SKILL.md"; return 1; }
}

@test "ship-land bash parses" {
  blk=$(awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' "$CMD")
  [ -n "$blk" ]
  echo "$blk" > "$BATS_TEST_TMPDIR/l.sh"
  run bash -n "$BATS_TEST_TMPDIR/l.sh"
  [ "$status" -eq 0 ]
}

@test "ship-land refuses to run from inside a worktree" {
  grep -qF 'git rev-parse --path-format=absolute --git-common-dir' "$CMD" || { echo "no main-checkout guard"; return 1; }
}
