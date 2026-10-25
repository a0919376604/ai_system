# R-008 review fix 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** clear review attempt 1's two blockers and its important findings (`/tmp/ship-next-review-R-008-1.md` — read it first; each item below cites its finding).
**Spec:** `docs/specs/R-008-land-after-merge.md`

## Global Constraints
- Edit files in THIS worktree only. No `$<digit>` in `commands/*.md` or `*/SKILL.md`. Blocks run in separate shells.
- Deleting or loosening an existing assertion is authorized only where this plan says so.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all`.

---

### Task 1: libs — deferred log rows, merge check pins the tip, race-safe push, land_resolve hardening

**Files:** `claude-skills/ship-workflow/lib/ship-log.sh`, `lib/ship-land.sh`, `lib/sync.sh`; tests `tests/test_ship-log.bats`, `tests/test_ship-land-lib.bats`, `tests/test_sync.bats` (or the file that tests sync.sh's worktree no-op)

- [x] **Step 1: failing tests**
  - ship-log: `ship_log: on a ship/* branch in mr mode, writes .ship/ship-log-rows, not _log.md` (repo with `merge_mode: mr`, branch `ship/R-1-x`: two `ship_log` calls → `.ship/ship-log-rows` at the toplevel has both rows in order; `_log.md` unchanged; no commit). Replace the Task-1 test `ship_log: appends on a ship/* branch in mr mode too` with this one (authorized). `ship_log: squash mode on a ship/* branch still appends to _log.md`. `ship_log: mr mode on the base branch appends to _log.md`.
  - ship-land-lib:
    - `land_is_merged: refuses when the local branch has commits the merged review did not include` — fake glab returns `[{"iid":7,"sha":"<old tip sha>"}]`; local branch has one more commit → status 1.
    - Update the existing glab/gh merged tests so the fake forge reports the local tip (`"sha":"<tip>"` / `headRefOid` `<tip>`) — authorized.
    - `land_push: a race seen through an earlier fetch still rebases` — after creating the land commit, `git fetch` in the main repo picks up another clone's push; `land_push main` → 0, both commits on origin.
    - `land_push: two lands appending to _log.md both land` — both sides append a row to `docs/learnings/_log.md`; second `land_push` → 0; origin's `_log.md` has both rows.
    - `land_resolve: REPO is the main checkout even when run from a worktree`; `land_resolve: SHIP_WT is blank when the branch is checked out in the main checkout`; `land_resolve: LAND_WT includes the repo name`.
  - sync: `sync.sh writes the mirror at a linked worktree root when SHIP_SYNC_IN_WORKTREE=1` (and still no-ops without it).
- [x] **Step 2:** run → FAIL.
- [x] **Step 3: implement**
  - `ship-log.sh`: source `merge-mode.sh` (same `command -v … || .` pattern as before R-008). Add `ship_log_defers` back with the same predicate (merge_mode is mr AND current branch is `ship/*`). In `ship_log`, when it defers: `mkdir -p "$root/.ship"; printf '%s\n' "$row" >> "$root/.ship/ship-log-rows"`; else append to `_log.md`. Header comment: on a review branch rows wait in `.ship/ship-log-rows` (untracked) and `/ship-land` replays them after the merge, so no review branch writes `_log.md` (R-001, R-008) — this also covers `/ship-idea --during-build`.
  - `ship-land.sh`:
    - `land_is_merged <branch> <base>`: glab — query as now, then require that some MR's head `"sha"` equals `git rev-parse "$branch"`: `… | grep -o '"sha":"[0-9a-f]*"' | grep -qF "\"sha\":\"$tip\""` (the leading quote keeps `merge_commit_sha` / `squash_commit_sha` out). gh — `gh pr list --head "$branch" --base "$base" --state merged --json headRefOid --jq '.[].headRefOid'` contains `$tip`. Fallback unchanged (ancestry). Comment: equal tips make `git branch -D` safe — nothing local is lost.
    - `land_push`: after a rejected push and a successful fetch, decide by ancestry: if `git merge-base --is-ancestor "origin/$base" HEAD` → not a race → print git's error, return 1. Else rebase with a union driver for the log: `attr=$(mktemp)`; `printf 'docs/learnings/_log.md merge=union\n' > "$attr"`; `git -c core.attributesFile="$attr" rebase -q "origin/$base"`; remove `$attr`. Drop the `before` variable.
    - `land_resolve`: `repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")` (fail → return 1); blank `wt` when it equals `repo`; `LAND_WT="${TMPDIR:-/tmp}/ship-land-$(basename "$repo")-${id}/wt"`.
  - `sync.sh`: the linked-worktree guard becomes `if [ "${SHIP_SYNC_IN_WORKTREE:-0}" != 1 ] && "$LIB_DIR/airos-binding.sh" in_linked_worktree 2>/dev/null; then exit 0; fi`, comment: /ship-land's throwaway worktree opts in — it is committed and removed, so a dirty mirror cannot block anything.
- [x] **Step 4:** the touched test files pass.
- [x] **Step 5:** commit `fix(R-008): review rows wait in .ship; merge check pins the tip; race-safe land_push — review attempt 2, Task 1`

### Task 2: ship-land, ship-compound, ship-next call sites

**Files:** `commands/ship-land.md`, `commands/ship-compound.md`, `commands/ship-next.md`; tests `tests/test_command-blocks.bats`, `tests/test_ship-land.bats`

- [x] **Step 1: failing tests**
  - `ship-land step 4 refuses to push when the land worktree has no compound commit for the ID` (block test: LAND_WT at origin/main with no new commit → status ≠ 0, origin unchanged, the ship branch and worktree still exist after also running step 5? — no: assert only step 4's status and origin).
  - `ship-land step 5 removes a ship worktree that still holds .ship/` (fixture worktree with untracked `.ship/learning-draft.md` → removed, branch deleted).
  - `ship-land step 3 replays every deferred row` (SHIP_WT/.ship/ship-log-rows with two rows → both in LAND_WT `_log.md`).
  - `ship-land step 3 warns when the ship worktree is gone` (SHIP_WT blank → stderr contains `WARN`).
  - `ship-land step 3 refuses to discard a land worktree that has unpushed commits`.
  - `ship-land skips to cleanup when origin/<base> already has the compound commit` (structural or block test of step 1: origin/main has a commit `compound: R-1 — shipped + learning` → step 1 prints `already compounded` and exits 0 with a `go to step 5` message).
  - `ship-compound step 2 picks the plan, not a review-fix plan` — structural: step 2 text contains `-review-fix-` exclusion.
  - Update `ship-next P9 (mr): writes the row to the worktree's .ship/ship-log-row…` → it now asserts the row in `$WORKTREE/.ship/ship-log-rows` (authorized).
- [x] **Step 2:** run → FAIL.
- [x] **Step 3: edits**
  - ship-land every block: `eval "$(land_resolve "$ID")" || exit 1`; blocks 2–5: `[ -n "$BRANCH" ] || { echo "no ship branch for $ID" >&2; exit 1; }`.
  - ship-land step 1, after resolving: if `git -C "$REPO" log "origin/$BASE" --format=%s --grep "^compound: $ID —" -1` prints something → `echo "$ID already compounded on origin/$BASE — go to step 5"; exit 0` (needs a `git -C "$REPO" fetch -q origin` first).
  - ship-land step 3: if `$LAND_WT` exists and `git -C "$LAND_WT" rev-list --count "origin/$BASE..HEAD"` > 0 → refuse (`push it with step 4 or remove it by hand`), else remove it as now. Replay `$SHIP_WT/.ship/ship-log-rows` line by line through `ship_log` (read loop) — rename all `ship-log-row` mentions to `ship-log-rows`. If `$SHIP_WT` is blank or missing, print `WARN: the ship worktree is gone — its log rows and learning draft are lost; write the learning from the spec, plan and git log` to stderr. Export `SHIP_SYNC_IN_WORKTREE=1` in the prose for running /ship-compound (so its step 8 refreshes the tracked vault mirror).
  - ship-land step 4, before `land_push`: `[ "$(git -C "$LAND_WT" rev-list --count "origin/$BASE..HEAD")" -gt 0 ] && git -C "$LAND_WT" log -1 --format=%s | grep -q "^compound: $ID " || { echo "ERROR: no compound commit for $ID in $LAND_WT — nothing pushed" >&2; exit 1; }`.
  - ship-land step 5: before `git worktree remove`, `rm -rf "$SHIP_WT/.ship"` (step 3 consumed it). Restore the sentence that `-D` is safe because step 2 proved the local tip is exactly what merged.
  - ship-compound step 2: `ls docs/specs/${ID}-*.md docs/plans/${ID}-*.md 2>/dev/null | grep -v -- '-review-fix-' | head -1` and take the slug from that file name; say so in the prose.
  - ship-next Phase 9 step 3 (mr branch): keep the WORKTREE / branch guards, then `(cd "$WORKTREE" && ship_log "$SHIP_LOG_ROW")` instead of the printf to `.ship/ship-log-row`; update the prose (rows wait in `.ship/ship-log-rows`; `/ship-land` replays them). Phase 8 (mr) prose: mention `/ship-idea --during-build` rows wait there too.
- [x] **Step 4:** `cd claude-skills/ship-workflow && bats tests/` → green except the known failure; `grep -rn 'ship-log-row[^s]' claude-skills/ship-workflow` prints nothing.
- [x] **Step 5:** commit `fix(R-008): ship-land is re-runnable and refuses empty or unsafe lands — review attempt 2, Task 2`

## Execution log

- Task 1 RED: touched files ran 34 tests; 9 expected failures cover the new behavior.
- Deviation: split git-common-dir lookup and dirname into checked assignments — dirname masks a failed nested git command, contrary to the required failure return.
- Deviation: updated the existing zsh row-location and LAND_WT path assertions to the newly specified destinations, retaining exact comparisons and adding an unchanged-log check — the plan omitted these two obsolete expectations; neither assertion was deleted, skipped, or loosened.
- Task 1 GREEN: 34/34 tests passed in test_ship-log.bats, test_ship-land-lib.bats, and test_sync.bats.
- Task 2 RED: command-block and ship-land tests reproduce all requested missing behaviors; one old compound test also fails because it runs on an mr review branch.
- Deviation: use a checked RESOLVED assignment before eval in every ship-land block — eval of an empty failed command substitution returns success, so the prescribed eval guard cannot propagate land_resolve failure.
- Deviation: run the existing compound retry test in a detached landing worktree — compounding now runs there; all assertions, including the exactly-once row assertion, remain intact.
- Deviation: added explicit failure returns to three new double-bracket assertions — the full-suite hygiene guard requires them so Bats cannot silently ignore an assertion.
- Task 2 GREEN: 49/49 targeted tests passed; final `cd claude-skills/ship-workflow && bats tests/` passed 636/637, with only the documented pre-existing `cwd-guard: exits 0 when not in a git repo at all` failure. The test-hygiene guard passed after the repair.
- Final checks: no singular ship-log-row references remain under claude-skills/ship-workflow; no positional dollar-digit references in command markdown or SKILL.md; git diff --check passed.
- Final read-only review: no implementation blockers relative to the supplied plan. Corrected the reviewer's minor finding in the plan's explanatory checkbox syntax.
- Both tasks complete. Stayed on ship/R-008-land-after-merge; no repository remote push, amendment, or hook bypass. Test pushes used only scratch local bare repositories.
