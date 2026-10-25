# R-008 review fix 3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** the two remaining importants from `/tmp/ship-next-review-R-008-2.md` (read it): merge check accepts a forge head that contains the local tip; racing/dirty land worktrees fail cleanly and are retryable.
**Spec:** `docs/specs/R-008-land-after-merge.md` (seams `land_is_merged`, AC-11, AC-12 updated).

## Global Constraints
- Edit files in THIS worktree only. No `$<digit>` in `commands/*.md` / `*/SKILL.md`.
- Changing an existing assertion is authorized only where named here.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all`.

---

### Task 1: land_is_merged — containment, not equality

**Files:** `claude-skills/ship-workflow/lib/ship-land.sh`; `tests/test_ship-land-lib.bats`

- [x] **Step 1: failing tests** (fake `glab`/`gh` scripts first on PATH as the existing tests do; the bare origin gets the review head ref via `git push origin <sha>:refs/merge-requests/7/head` or `…:refs/pull/7/head`)
  - `land_is_merged (glab): merged head that is a child of the local tip counts` — fake glab prints `[{"iid":7,"sha":"<child>"}]`; origin has `refs/merge-requests/7/head` = child; local branch tip = parent → 0.
  - `land_is_merged (glab): merged head that does not contain the local tip is refused` — local branch has an extra commit not in the MR head → 1.
  - `land_is_merged (gh): merged PR head that contains the tip counts` — fake gh prints `7` for `pr list … --json number --jq .[].number`; origin has `refs/pull/7/head` → 0.
  - `land_is_merged (glab): a milestone iid in the JSON is not read as a review` — JSON `[{"iid":7,"milestone":{"iid":99},"sha":"<sha>"}]`, origin has only `refs/merge-requests/7/head` → still 0, and the fake records that only `7` was fetched (or simply: no failure from fetching 99).
  - Existing tip-equality tests: keep their assertions; adjust setup only to also create the head ref on origin (authorized).
- [x] **Step 2:** run → FAIL.
- [x] **Step 3: implement** in `land_is_merged`:
  ```bash
  tip=$(git rev-parse -q --verify "$branch") || return 1
  case "$(forge_cli 2>/dev/null)" in
    glab)
      json=$(glab api "projects/:id/merge_requests?state=merged&target_branch=${base}&source_branch=$(printf '%s' "$branch" | sed 's#/#%2F#g')" 2>/dev/null)
      if command -v jq >/dev/null 2>&1; then ids=$(printf '%s' "$json" | jq -r '.[].iid' 2>/dev/null)
      else ids=$(printf '%s' "$json" | grep -oE '\{"id":[0-9]+,"iid":[0-9]+' | grep -oE '[0-9]+$'); fi
      for n in $ids; do
        git fetch -q origin "refs/merge-requests/$n/head" 2>/dev/null \
          && git merge-base --is-ancestor "$tip" FETCH_HEAD && return 0
      done ;;
    gh)
      for n in $(gh pr list --head "$branch" --base "$base" --state merged --json number --jq '.[].number' 2>/dev/null); do
        git fetch -q origin "refs/pull/$n/head" 2>/dev/null \
          && git merge-base --is-ancestor "$tip" FETCH_HEAD && return 0
      done ;;
  esac
  git merge-base --is-ancestor "$tip" "origin/$base" 2>/dev/null
  ```
  Comment: the review head must CONTAIN the local tip — equal, or with forge-side commits on top ("Apply suggestion"). That is what keeps `git branch -D` from losing local work. `refs/merge-requests/<iid>/head` / `refs/pull/<n>/head` survive `--remove-source-branch`.
- [x] **Step 4:** test file passes.
- [x] **Step 5:** commit `fix(R-008): a merged review counts when its head contains the local tip — review attempt 3, Task 1`

### Task 2: clean, retryable land worktree

**Files:** `commands/ship-compound.md`, `commands/ship-land.md`, `lib/ship-land.sh`; tests `tests/test_command-blocks.bats`, `tests/test_ship-land-lib.bats`

- [x] **Step 1: failing tests**
  - `ship-compound step 9 stages the whole vault mirror` — repo with tracked `docs/product/ROADMAP.md` and `docs/product/VISION.md`; modify both (as sync would); run step 9 → `git status --porcelain docs/product` empty afterwards.
  - `land_push: a rebase conflict prints how to retry` — both sides change the same line of `docs/product/ROADMAP.md` → status 1, stderr contains `re-run /ship-land` and `git worktree remove --force`.
  - Structural: ship-compound step 7 text says to skip when the `${ID}` row is already under "✅ Done".
- [x] **Step 2:** run → FAIL.
- [x] **Step 3: edits**
  - ship-compound step 9: in the optional-paths loop replace `docs/product/ROADMAP.md` with `docs/product` (the mirror is regenerated whole by sync.sh; staging part of it leaves the worktree dirty and blocks a rebase).
  - ship-compound step 7: add `If the \`${ID}\` row is already under "✅ Done" (a re-run of \`/ship-land\`), leave the ROADMAP as it is.`
  - `land_push` rebase-conflict message: `land_push: rebasing onto the new origin/$base conflicted — nothing pushed. Another land changed the same lines (usually the vault mirror). Retry: git worktree remove --force <this worktree>, then re-run /ship-land.` (print the worktree path via `git rev-parse --show-toplevel`).
  - ship-land step 3's refusal for a land worktree with unpushed commits: append the same retry instruction.
- [x] **Step 4:** `cd claude-skills/ship-workflow && bats tests/` → green except the known failure.
- [x] **Step 5:** commit `fix(R-008): land worktree stays clean; conflicts say how to retry — review attempt 3, Task 2`

## Execution log

- Task 1: containment tests failed before implementation; `bats tests/test_ship-land-lib.bats` passed 18/18 afterwards. Existing refusal test covers the non-containing head; assertions preserved.
- Task 2: new mirror staging, Done-row instruction, and conflict retry checks failed before implementation. `cd claude-skills/ship-workflow && bats tests/`: 642/643 passed; only the documented pre-existing `cwd-guard: exits 0 when not in a git repo at all` failed.
- Final review: independent read-only reviewer found no blocking implementation issues. Corrected an incidental checkbox-example edit in this plan. `git diff --check` passed. No plan deviations.
