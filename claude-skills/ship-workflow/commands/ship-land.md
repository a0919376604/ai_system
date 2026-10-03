---
name: ship-land
description: Finish an R-NNN that shipped via merge_mode=mr — verify the review merged, move the ROADMAP row to Done, then clean up the branch and worktree
discord-visible: true
---

# /ship-land

Closes the loop that `merge_mode: mr` deliberately leaves open.

In `mr` mode Phase 7 pushes the branch and opens a review instead of merging.
Phase 8 marks the ROADMAP row `status=in-review` rather than Done, and Phase 9
keeps the branch and worktree the review depends on. All of that is correct
while the review is open and all of it is stale once it merges. This command is
the "once it merges" half.

Nothing here is needed in `squash` mode — Phase 7 already landed the work and
Phase 9 already cleaned up.

## Usage

```
/ship-land R-NNN
```

## Steps

1. **Resolve the row and the branch.**

   ```bash
   ID="$1"
   [ -n "$ID" ] || { echo "usage: /ship-land R-NNN" >&2; exit 2; }

   REPO=$(git rev-parse --show-toplevel)
   cd "$REPO"
   ORIG_BRANCH=$(git symbolic-ref --short HEAD)
   BRANCH=$(git branch --list "ship/${ID}-*" --format='%(refname:short)' | head -1)
   [ -n "$BRANCH" ] || { echo "no ship branch found for $ID" >&2; exit 1; }
   ```

2. **Verify the review actually merged.** This is the gate. Marking Done and
   deleting a branch whose review is still open is how the work disappears.

   ```bash
   git fetch origin --prune

   if ! git branch --merged "origin/${ORIG_BRANCH}" --format='%(refname:short)' \
        | grep -qx "$BRANCH"; then
     echo "ERROR: $BRANCH is not merged into origin/$ORIG_BRANCH." >&2
     echo "       The review is still open, or it was closed without merging." >&2
     echo "       Nothing has been changed." >&2
     exit 1
   fi
   ```

   `--merged origin/<base>` is checked rather than the local base: the review
   merged on the remote, and a stale local base would answer the wrong
   question.

3. **Move the ROADMAP row to Done.**

   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ```

   Edit `$ROADMAP_PATH`:
   - Find the `${ID}` line under "🔥 Now"
   - Strip `status=in-review` and the `mr=<url>` annotation Phase 8 added
   - Strip `adhoc-inserted=true` if present
   - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
   - Atomic write via `.tmp` + `mv`

   Then re-sync so the repo mirror matches:

   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

4. **Clean up what Phase 9 kept.**

   ```bash
   git pull --ff-only origin "$ORIG_BRANCH"

   WORKTREE=$(git worktree list --porcelain \
              | awk -v b="refs/heads/$BRANCH" '/^worktree /{w=$2} /^branch /{if ($2==b) print w}')
   if [ -n "$WORKTREE" ]; then
     git worktree remove "$WORKTREE" || {
       echo "WARN: worktree at $WORKTREE has uncommitted changes; not removed." >&2
       echo "      Inspect, then: git worktree remove --force $WORKTREE" >&2
     }
   fi

   git branch -d "$BRANCH"
   git push origin --delete "$BRANCH" 2>/dev/null || true
   ```

   `-d` not `-D`: by this point the branch IS merged, so `-d` succeeds. If it
   refuses, the step-2 check was wrong and the work must not be discarded.

5. **Log it.**

   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-land | ${ID} | landed | n |" >> docs/learnings/_log.md
   git add docs/learnings/_log.md docs/product/ROADMAP.md
   git commit -m "land: ${ID} — review merged, roadmap closed"
   ```

6. **Report:** the row's new state, the branch and worktree removed, and the
   merge commit on the base branch.
