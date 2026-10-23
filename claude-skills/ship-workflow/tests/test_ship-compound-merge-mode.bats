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

@test "ship-compound's mr branch of step 9 stages no shared file" {
  # _log.md, the vault mirror and CONTEXT.md are what made parallel MRs conflict.
  sec=$(awk '/^9\. \*\*Log \+ commit/,/^10\. \*\*Report/' "$CMD")
  mr=$(echo "$sec" | awk '/if \[ "\$MERGE_MODE" = "mr" \]; then/{f=1;next} /^[[:space:]]*else$/{f=0} f')
  [ -n "$mr" ] || { echo "no mr branch in step 9"; return 1; }
  for shared in docs/product docs/proposals _log.md CONTEXT.md; do
    if echo "$mr" | grep -qF "$shared"; then echo "mr branch stages $shared"; return 1; fi
  done
  echo "$sec" | grep -qF 'ship_log "|' || { echo "the row bypasses ship_log"; return 1; }
}

@test "ship-compound queues CONTEXT.md entries instead of editing them in mr mode" {
  sec=$(awk '/^### Step 6/,/^6\. \*\*Delegate/' "$CMD")
  echo "$sec" | grep -qF 'context_pending_add "$ID"' || { echo "no queue in mr mode"; return 1; }
  echo "$sec" | grep -qF 'MERGE_MODE=$(merge_mode)' || { echo "step 6 cannot tell the mode"; return 1; }
}
