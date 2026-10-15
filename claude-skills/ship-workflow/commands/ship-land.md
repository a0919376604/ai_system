---
name: ship-land
description: Finish an R-NNN that shipped via merge_mode=mr — verify the review merged, fold its deferred CONTEXT.md entries onto the base branch, move the ROADMAP row to Done, then clean up the branch and worktree
discord-visible: true
---

# /ship-land

Closes the loop that `merge_mode: mr` deliberately leaves open.

In `mr` mode Phase 7 pushes the branch and opens a review instead of merging.
Phase 8 marks the ROADMAP row `status=in-review` rather than Done, queues any new
`CONTEXT.md` entries in `docs/ship-pending/<R-NNN>-context.md` instead of editing
`CONTEXT.md`, and Phase 9 keeps the branch and worktree the review depends on. All
of that is correct while the review is open and stale once it merges. This command
is the "once it merges" half.

The review branch never writes a file another ship also writes — that is what made
parallel MRs conflict (R-001). `CONTEXT.md` is the one shared file that cannot be
split per ship, so it is the one this command writes, after the merge, on the base
branch. A land with no queued entries makes no commit at all.

Nothing here is needed in `squash` mode — Phase 7 already landed the work and
Phase 9 already cleaned up.

## Usage

```
/ship-land R-NNN
```

## Steps

1. **Resolve the row, the base and the branch.** Run from the main repo root.

   ```bash
   ID="$1"
   [ -n "$ID" ] || { echo "usage: /ship-land R-NNN" >&2; exit 2; }

   # From the main checkout, never from the ship's worktree: step 5 removes
   # that worktree, and git refuses to remove the one you are standing in.
   if [ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
     echo "run /ship-land from the main checkout, not from a worktree" >&2
     exit 2
   fi
   REPO=$(git rev-parse --show-toplevel)
   cd "$REPO"
   BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
   [ -n "$BASE" ] || BASE=main
   BRANCH=$(git branch --list "ship/${ID}-*" --format='%(refname:short)' | head -1)
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"

   if [ -z "$BRANCH" ]; then
     if awk '/✅ Done/{d=1} d' "$ROADMAP_PATH" 2>/dev/null | grep -qF "**${ID}**"; then
       echo "$ID is already landed — nothing to do."
       exit 0
     fi
     echo "no local ship branch found for $ID" >&2
     exit 1
   fi
   ```

2. **Verify the review actually merged.** This is the gate. Marking Done and
   deleting a branch whose review is still open is how the work disappears.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   git fetch origin --prune

   if ! land_is_merged "$BRANCH" "origin/${BASE}"; then
     echo "ERROR: $BRANCH is not merged into origin/$BASE." >&2
     echo "       The review is still open, or it was closed without merging." >&2
     echo "       If it was squash-merged or rebase-merged (GitHub \"Rebase and merge\"," >&2
     echo "       GitLab fast-forward / semi-linear), the branch tip is not in" >&2
     echo "       origin/$BASE and this check cannot see the merge." >&2
     echo "       Nothing has been changed." >&2
     exit 1
   fi
   ```

   The **local** branch is checked against `origin/<base>`: Phase 7 opens the review
   with `--remove-source-branch`, so the remote branch is usually gone by now, and a
   stale local base would answer the wrong question.

3. **Fold the deferred CONTEXT.md entries onto the base branch.**

   ```bash
   # Each block runs in its own shell — source what this one calls.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   LAND_RESULT=$(land_context "$ID" "$BASE") || {
     echo "ERROR: could not land CONTEXT.md for $ID — ROADMAP and branch untouched." >&2
     exit 1
   }
   echo "$LAND_RESULT"
   ```

   `land_context` works in a throwaway worktree at `origin/<base>`, so the
   operator's checkout — often behind origin, sometimes dirty — is never pulled,
   switched or committed to. It makes one commit, `context: land <R-NNN> [skip ci]`,
   and pushes it. `[skip ci]` keeps a docs-only bookkeeping commit from starting a
   pipeline. If another push wins the race it redoes the fold on the new tip.

   When `$LAND_RESULT` starts with `landed`, mirror the result to the vault and run
   the cap check:

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh   # CONTEXT_MD_MAX_* live in context-md.sh, which it loads
   case "$LAND_RESULT" in
     landed*)
       VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
       git show "origin/${BASE}:CONTEXT.md" > "/tmp/ship-land-CONTEXT-${ID}.md"
       ~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
         "/tmp/ship-land-CONTEXT-${ID}.md" "$VAULT_DIR/CONTEXT.md"
       LINES=$(wc -l < "/tmp/ship-land-CONTEXT-${ID}.md" | tr -d ' ')
       ENTRIES=$(grep -cE '^- \*\*[^*]+\*\*' "/tmp/ship-land-CONTEXT-${ID}.md" || true)
       if [ "$LINES" -gt "$CONTEXT_MD_MAX_LINES" ] || [ "$ENTRIES" -gt "$CONTEXT_MD_MAX_ENTRIES" ]; then
         echo "WARN: CONTEXT.md over cap (${LINES} lines / ${ENTRIES} entries) — prune it" >&2
       fi
       ;;
   esac
   ```

   Over cap: prune as `/ship-compound` step 6.3 describes, as its own change that
   goes through review like any other — in `mr` mode, an MR. Pruning deletes
   vocabulary, so it is never automatic and never folded into this command's
   bookkeeping commit.

4. **Move the ROADMAP row to Done.** Edit `$ROADMAP_PATH` (skip if already Done):
   - Find the `${ID}` line under "🔥 Now"
   - Strip `status=in-review` and the `mr=<url>` annotation Phase 8 added
   - Strip `adhoc-inserted=true` if present
   - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
   - Atomic write via `.tmp` + `mv`

   The vault is the source of truth; nothing is committed for this step.

5. **Clean up what Phase 9 kept.**

   ```bash
   WORKTREE=$(git worktree list --porcelain \
              | awk -v b="refs/heads/$BRANCH" '/^worktree /{w=$2} /^branch /{if ($2==b) print w}')
   # Never the main checkout: if $BRANCH is checked out there, the lookup above
   # resolves to it, and the clean below would delete the operator's own files.
   if [ -n "$WORKTREE" ] && [ "$WORKTREE" != "$(git rev-parse --show-toplevel)" ]; then
     # sync.sh rewrites the vault mirror in every working tree it runs in. Those
     # files are regenerated from the vault, never review content — restore them
     # so they do not block the removal.
     for p in docs/product docs/proposals docs/roadmap-notes; do
       # One path at a time: `checkout --` aborts on the first untracked path.
       # `clean` removes mirror files synced after the branch point, which
       # checkout cannot.
       git -C "$WORKTREE" checkout -- "$p" 2>/dev/null || true
       git -C "$WORKTREE" clean -fdq -- "$p"
     done
     git worktree remove "$WORKTREE" || {
       echo "WARN: worktree at $WORKTREE has uncommitted changes; not removed." >&2
       echo "      Inspect, then: git worktree remove --force $WORKTREE" >&2
     }
   fi

   git branch -D "$BRANCH"
   git push origin --delete "$BRANCH" 2>/dev/null || true
   ```

   `-D` is safe **because** step 2 proved the branch tip is in `origin/<base>`. `-d`
   would compare against the local base, which is routinely behind origin, and
   refuse a branch that is in fact merged.

6. **Report:** the land commit (or "no CONTEXT.md changes"), the row's new state,
   and the branch and worktree removed.

There is no `_log.md` write and no `git pull` here. The ship's log rows reached the
base branch's history as `Ship-Log:` trailers when the review merged.
