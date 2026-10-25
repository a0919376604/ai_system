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
  grep -qF 'land_is_merged "$BRANCH" "$BASE"' "$CMD" || { echo "merge state is never verified"; return 1; }
}

@test "ship-land moves the row to Done and clears in-review" {
  grep -qF 'in-review' "$CMD" || { echo "the in-review status is never cleared"; return 1; }
  grep -qiF 'Done' "$CMD" || { echo "the row is never moved to Done"; return 1; }
}

@test "ship-land cleans up what Phase 9 deliberately kept" {
  grep -qF 'git worktree remove' "$CMD" || { echo "worktree is never removed"; return 1; }
  grep -qF 'git branch -D "$BRANCH"' "$CMD" || { echo "branch is never deleted"; return 1; }
}

@test "ship-land runs /ship-compound on the base branch in a throwaway worktree" {
  for word in land_resolve 'worktree add' /ship-compound SHIP_COMMIT_SUFFIX land_push; do
    grep -qF "$word" "$CMD" || return 1
  done
}

@test "ship-land never pulls or commits in the operator's checkout" {
  ! grep -qF 'git pull' "$CMD"
  ! grep -qE '^[[:space:]]*git commit' "$CMD"
  grep -qF 'ship-log-rows' "$CMD"
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

@test "ship-compound step 2 picks the plan, not a review-fix plan" {
  step=$(sed -n '/^2\. \*\*Identify/,/^3\. /p' "$SHIP_SKILL_ROOT/commands/ship-compound.md")
  printf '%s\n' "$step" | grep -qF "grep -v -- '-review-fix-'"
}
