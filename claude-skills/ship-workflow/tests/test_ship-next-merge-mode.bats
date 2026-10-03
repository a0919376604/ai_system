#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }

p7() { awk '/^## Phase 7/,/^## Phase 8 /' "$CMD"; }
p9() { awk '/^## Phase 9/,0' "$CMD"; }
code() { sed 's/[[:space:]]*#.*$//' | grep -v '^[[:space:]]*$'; }

@test "Phase 7 sources merge-mode and branches on it" {
  s=$(p7)
  echo "$s" | grep -qF 'lib/merge-mode.sh' || { echo "Phase 7 never sources merge-mode"; return 1; }
  echo "$s" | grep -qF 'MERGE_MODE=$(merge_mode)' || { echo "mode is not resolved"; return 1; }
  echo "$s" | grep -qF 'case "$MERGE_MODE" in' || { echo "no branch on the mode"; return 1; }
}

@test "Phase 7 squash path is unchanged" {
  p7 | grep -qF 'git merge --squash "$BRANCH"' || { echo "the squash path is gone"; return 1; }
}

@test "Phase 7 mr path pushes and opens a review, and never merges" {
  # Everything between the mr) arm and the esac.
  arm=$(p7 | awk '/^[[:space:]]*mr\)/,/^[[:space:]]*esac/')
  [ -n "$arm" ] || { echo "no mr) arm"; return 1; }
  echo "$arm" | grep -qF 'git push -u origin' || { echo "the branch is never pushed"; return 1; }
  echo "$arm" | grep -qF 'forge_mr_cmd' || { echo "no MR is opened"; return 1; }
  # The whole point: main must not move.
  ! echo "$arm" | code | grep -qF 'git merge' || { echo "the mr path merges anyway"; return 1; }
}

@test "Phase 7 builds the review body once and reuses it for both paths" {
  # The squash commit message and the MR description are the same content.
  p7 | grep -qF 'SHIP_BODY=' || { echo "the body is not captured for reuse"; return 1; }
}

@test "Phase 9 does not delete the branch while a review is open" {
  s=$(p9 | code)
  echo "$s" | grep -qF 'MERGE_MODE' || { echo "Phase 9 ignores the merge mode"; return 1; }
  # The deletion must sit inside a MERGE_MODE conditional, not at top level.
  # Asserting on the literal word "squash" was the wrong shape: the guard keys
  # off mr, which is the mode that must NOT delete.
  before=$(echo "$s" | grep -B6 'git branch -d "\$BRANCH"')
  echo "$before" | grep -qF 'MERGE_MODE' || { echo "branch deletion is unguarded"; return 1; }
  echo "$before" | grep -qF 'else' || { echo "deletion is not in the non-mr branch"; return 1; }
}

@test "Phase 9 keeps the worktree when a review is open" {
  p9 | grep -qiF 'worktree is kept' || { echo "nothing says the worktree survives mr mode"; return 1; }
}

@test "Phase 9 sources merge-mode itself" {
  # Phases do not share a shell.
  p9 | grep -qF 'lib/merge-mode.sh' || { echo "Phase 9 uses MERGE_MODE without sourcing"; return 1; }
}

@test "Phase 7 and 9 bash still parse" {
  for f in p7 p9; do
    blk=$($f | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f')
    [ -n "$blk" ] || { echo "$f: no bash"; return 1; }
    echo "$blk" > "$BATS_TEST_TMPDIR/$f.sh"
    bash -n "$BATS_TEST_TMPDIR/$f.sh" || { echo "$f does not parse"; return 1; }
  done
}
