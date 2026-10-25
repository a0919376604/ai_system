---
name: ship-land
description: Finish an R-NNN shipped with merge_mode=mr once its review merged — run /ship-compound on the base branch, push it, then remove the branch and worktree
discord-visible: true
---

# /ship-land

In mr mode the review carries only the work. Everything that writes a shared
file runs here after the merge as `/ship-compound` in a throwaway worktree at
`origin/<base>` (R-008). Squash mode never needs this.

## Usage

```
/ship-land R-NNN
```

## Steps

1. **Resolve.** Run from the main checkout.

   ```bash
   ID="$ARGUMENTS"   # the R-NNN argument; Claude Code substitutes it
   [ -n "$ID" ] || { echo "usage: /ship-land R-NNN" >&2; exit 2; }

   # From the main checkout, never from the ship's worktree: step 5 removes
   # that worktree, and git refuses to remove the one you are standing in.
   if [ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
     echo "run /ship-land from the main checkout, not from a worktree" >&2
     exit 2
   fi
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   RESOLVED=$(land_resolve "$ID") || exit 1
   eval "$RESOLVED" || exit 1
   git -C "$REPO" fetch -q origin || exit 1
   if [ -n "$(git -C "$REPO" log "origin/$BASE" --format=%s --grep "^compound: $ID —" -1)" ]; then
     echo "$ID already compounded on origin/$BASE — go to step 5"
     exit 0
   fi
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

2. **Verify the review merged.**

   ```bash
   ID="$ARGUMENTS"
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   RESOLVED=$(land_resolve "$ID") || exit 1
   eval "$RESOLVED" || exit 1
   [ -n "$BRANCH" ] || { echo "no ship branch for $ID" >&2; exit 1; }
   git -C "$REPO" fetch -q origin --prune
   (cd "$REPO" && land_is_merged "$BRANCH" "$BASE") || { echo "ERROR: the review for $BRANCH has not merged into $BASE — nothing changed." >&2; exit 1; }
   ```

   The forge is asked first, so squash merges count (R-002).

3. **Compound on the base branch, in a throwaway worktree.**

   ```bash
   ID="$ARGUMENTS"
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
   RESOLVED=$(land_resolve "$ID") || exit 1
   eval "$RESOLVED" || exit 1
   [ -n "$BRANCH" ] || { echo "no ship branch for $ID" >&2; exit 1; }
   if [ -d "$LAND_WT" ]; then
     if [ "$(git -C "$LAND_WT" rev-list --count "origin/$BASE..HEAD")" -gt 0 ]; then
       echo "ERROR: $LAND_WT has unpushed commits — push it with step 4 or remove it by hand. Retry: git worktree remove --force \"$LAND_WT\", then re-run /ship-land." >&2
       exit 1
     fi
     git -C "$REPO" worktree remove --force "$LAND_WT"
   fi
   mkdir -p "$(dirname "$LAND_WT")"
   git -C "$REPO" worktree add -q --detach "$LAND_WT" "origin/$BASE" || exit 1
   cd "$LAND_WT" || exit 1
   if [ -z "$SHIP_WT" ] || [ ! -d "$SHIP_WT" ]; then
     echo "WARN: the ship worktree is gone — its log rows and learning draft are lost; write the learning from the spec, plan and git log" >&2
   elif [ -f "$SHIP_WT/.ship/ship-log-rows" ]; then
     while IFS= read -r row; do
       ship_log "$row" || exit 1
     done < "$SHIP_WT/.ship/ship-log-rows"
   fi
   echo "Compound worktree: $LAND_WT"
   echo "Learning draft: $SHIP_WT/.ship/learning-draft.md"
   ```

   Run **`/ship-compound`** for `$ID` with `$LAND_WT` as the working directory,
   `ID` set, `SHIP_COMMIT_SUFFIX=" [skip ci]"`, and export `SHIP_SYNC_IN_WORKTREE=1`
   so step 8 refreshes the tracked vault mirror, starting step 5 from the learning
   draft. Its step 7 clears in-review and moves the row to Done; its step 9 commits.

4. **Push.**

   ```bash
   ID="$ARGUMENTS"
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   RESOLVED=$(land_resolve "$ID") || exit 1
   eval "$RESOLVED" || exit 1
   [ -n "$BRANCH" ] || { echo "no ship branch for $ID" >&2; exit 1; }
   [ "$(git -C "$LAND_WT" rev-list --count "origin/$BASE..HEAD")" -gt 0 ] && git -C "$LAND_WT" log -1 --format=%s | grep -q "^compound: $ID " || { echo "ERROR: no compound commit for $ID in $LAND_WT — nothing pushed" >&2; exit 1; }
   (cd "$LAND_WT" && land_push "$BASE") || { echo "ERROR: could not push — the compound commit is left in $LAND_WT" >&2; exit 1; }
   git -C "$REPO" worktree remove --force "$LAND_WT"
   rm -rf "$(dirname "$LAND_WT")"
   # R-013: the Roadmap 檢視 plugin shows the ship as done. $ID is the one given.
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$REPO" done
   ```

5. **Clean up what Phase 9 kept.**

   ```bash
   ID="$ARGUMENTS"
   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
   RESOLVED=$(land_resolve "$ID") || exit 1
   eval "$RESOLVED" || exit 1
   [ -n "$BRANCH" ] || { echo "no ship branch for $ID" >&2; exit 1; }
   cd "$REPO"
   # Never the main checkout: if $BRANCH is checked out there, the lookup above
   # resolves to it, and the clean below would delete the operator's own files.
   if [ -n "$SHIP_WT" ] && [ "$SHIP_WT" != "$(git rev-parse --show-toplevel)" ]; then
     # sync.sh rewrites the vault mirror in every working tree it runs in. Those
     # files are regenerated from the vault, never review content — restore them
     # so they do not block the removal.
     for p in docs/product docs/proposals docs/roadmap-notes; do
       # One path at a time: `checkout --` aborts on the first untracked path.
       # `clean` removes mirror files synced after the branch point, which
       # checkout cannot.
       git -C "$SHIP_WT" checkout -- "$p" 2>/dev/null || true
       git -C "$SHIP_WT" clean -fdq -- "$p"
     done
     rm -rf "$SHIP_WT/.ship"
     git worktree remove "$SHIP_WT" || {
       echo "WARN: worktree at $SHIP_WT has uncommitted changes; not removed." >&2
       echo "      Inspect, then: git worktree remove --force $SHIP_WT" >&2
     }
   fi

   git branch -D "$BRANCH"
   git push origin --delete "$BRANCH" 2>/dev/null || true
   ```

   `-D` is safe because step 2 proved the local tip is exactly what merged.

6. **Report:** the compound commit, the row now in Done, branch and worktree removed.
