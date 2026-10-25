# R-008 land-after-merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** mr-mode reviews carry only the work; `/ship-land` runs `/ship-compound` on the base branch after the merge; R-001's deferral machinery is removed.

**Architecture:** libs first (ship-log, context-md, ship-land), then ship-compound becomes single-path, then ship-next Phase 7–9 mr wording/blocks, then a rewritten ship-land.md plus docs. Each task updates or deletes the tests that pinned the removed behavior.

**Tech Stack:** bash, git, bats (`cd claude-skills/ship-workflow && bats tests/`).

**Spec:** `docs/specs/R-008-land-after-merge.md`

## Global Constraints
- Edit files in THIS worktree only, never through `~/.claude/skills` (a symlink to another checkout).
- No `$` immediately followed by a digit in `commands/*.md` or `*/SKILL.md` (`tests/test_no-positional-params.bats`). Inside `lib/*.sh` positionals are fine.
- Blocks in command files run in separate shells: every block sources the libs it calls and recomputes what it needs.
- **Deleting tests is authorized only where this plan names them.** They pin behavior this ship removes on purpose.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all` (linked worktree).

## Review Focus
- A rewritten ship-land block must still never resolve the ship worktree to the main checkout.
- `land_push` must not push when the rebase conflicts.
- ship-compound step 2 must find the plan/spec by `ID` when `/ship-land` sets it (another ship's plan may be newer on main).
- Phase 9 (mr) with WORKTREE unset or pointing at another ship's worktree must write nothing.

---

### Task 1: libs — ship_log always appends; no pending queue; land_is_merged / land_push / land_resolve

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-log.sh`, `lib/context-md.sh`, `lib/ship-land.sh`
- Delete: `tests/test_parallel-mr.bats`, `tests/test_context-pending.bats`
- Modify tests: `tests/test_ship-log.bats`, `tests/test_ship-land-lib.bats`, `tests/test_test-budget.bats`

- [x] **Step 1: tests**
  - `test_ship-log.bats`: delete `ship_log: mr mode on a ship/* branch makes one empty commit with a Ship-Log trailer`, `ship_log: mr mode on the base branch still appends`, `ship_log: defers from a subdirectory too`. Rename `ship_log: squash mode appends the row and makes no commit` → `ship_log: appends the row and makes no commit`; add `ship_log: appends on a ship/* branch in mr mode too` (repo with `.claude/ship-config.yml` `merge_mode: mr`, on branch `ship/R-1-x`: row appended to `_log.md`, `git rev-list --count HEAD` unchanged). Change `ship_log_ratio_count: counts file rows and trailers together` to `ship_log_ratio_count: counts file rows` (2 `ratio ` rows in the file + an empty commit carrying a `Ship-Log:` trailer with `ratio ` → `2`).
  - `test_test-budget.bats`: delete `tb_shadow_active: Ship-Log trailers count, so an mr-only repo leaves shadow mode`.
  - `test_ship-land-lib.bats`: delete the five `land_context: …` tests. Change the two `land_is_merged` tests to the new signature `land_is_merged <branch> main` (branch name, not `origin/main`; they must run with no forge CLI answering — put a `glab`/`gh` stub that exits 1 first on PATH). Add:
    - `land_is_merged: a forge-reported merge counts even when the tip is not in origin/<base>` — origin is a local bare repo; `git remote set-url origin` to a value containing `gitlab` is not possible for a path, so instead stub `forge_cli` by defining a shell function `forge_cli() { echo glab; }` after sourcing the lib, and put a fake `glab` script first on PATH that prints `[{"iid":7,"state":"merged"}]` when its args contain `state=merged` and `source_branch=ship%2FR-1-x`; branch `ship/R-1-x` has a commit not in origin/main → `run land_is_merged ship/R-1-x main` → status 0.
    - `land_is_merged: gh reports merged` — same with `forge_cli() { echo gh; }` and a fake `gh` that prints `1` for `pr list … --state merged`.
    - `land_push: pushes when origin has not moved` → origin/main gains the commit.
    - `land_push: rebases and retries when another push landed first` — clone B pushes a commit touching a different file after the temp worktree was created; `land_push main` exits 0; `git log origin/main` contains both subjects.
    - `land_push: a rejection that is not a race fails at once` — bare origin with a `hooks/pre-receive` that `exit 1`; status 1; origin/main unchanged.
    - `land_resolve: prints REPO BASE BRANCH SHIP_WT LAND_WT` — repo with `ship/R-1-x` checked out in a worktree; `eval "$(land_resolve R-1)"`; `BRANCH=ship/R-1-x`, `SHIP_WT` = that worktree path (as git prints it), `BASE=main`, `LAND_WT` ends with `/ship-land-R-1/wt`; for `R-9` `BRANCH` is empty.
- [x] **Step 2:** run the three files → new/changed tests FAIL.
- [x] **Step 3: implement**
  - `lib/ship-log.sh`: remove `ship_log_defers`, the trailer branch inside `ship_log`, the `merge-mode.sh` sourcing, and the trailer half of `ship_log_ratio_count`. Rewrite the header comment to: the single writer of `_log.md` rows; it appends and never commits (R-008 moved mr-mode bookkeeping after the merge, so no review branch writes this file).
  - `lib/context-md.sh`: delete `context_pending_add`, `context_pending_apply` and anything only they use, with their comments.
  - `lib/ship-land.sh`: delete `land_context`; source `merge-mode.sh` the same way the file sourced context-md (`command -v forge_cli >/dev/null 2>&1 || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"`) and `ship-log.sh` is NOT needed. New header comment: the mechanical half of /ship-land (R-008). Functions:
    ```bash
    LAND_PUSH_ATTEMPTS=3

    # land_is_merged <branch> <base> — exit 0 iff the review for <branch> merged into
    # <base>. The forge is asked first: a squash merge leaves the branch tip outside
    # origin/<base>, so ancestry alone reads a merged review as open (R-002). With no
    # forge answer, fall back to ancestry. Exit 2 on usage.
    land_is_merged() {
      local branch="$1" base="$2" n
      [ -n "$branch" ] && [ -n "$base" ] || return 2
      case "$(forge_cli 2>/dev/null)" in
        glab)
          n=$(glab api "projects/:id/merge_requests?state=merged&target_branch=${base}&source_branch=$(printf '%s' "$branch" | sed 's#/#%2F#g')" 2>/dev/null \
              | grep -o '"iid"' | wc -l | tr -d ' ')
          [ "${n:-0}" -gt 0 ] && return 0 ;;
        gh)
          n=$(gh pr list --head "$branch" --base "$base" --state merged --json number --jq length 2>/dev/null)
          [ "${n:-0}" -gt 0 ] 2>/dev/null && return 0 ;;
      esac
      git merge-base --is-ancestor "$branch" "origin/$base" 2>/dev/null
    }

    # land_push <base> — push HEAD to origin/<base>. When another push landed first,
    # rebase onto it and retry, LAND_PUSH_ATTEMPTS times. Any other rejection, or a
    # rebase conflict, fails at once with nothing pushed. Exit 1 on failure, 2 on usage.
    land_push() {
      local base="$1" attempt=0 before err
      [ -n "$base" ] || return 2
      err=$(mktemp) || return 1
      while [ "$attempt" -lt "$LAND_PUSH_ATTEMPTS" ]; do
        attempt=$((attempt + 1))
        before=$(git rev-parse -q --verify "origin/$base" 2>/dev/null)
        if git push -q origin "HEAD:$base" 2>"$err"; then rm -f "$err"; return 0; fi
        git fetch -q origin "$base" 2>/dev/null || { cat "$err" >&2; rm -f "$err"; return 1; }
        if [ "$(git rev-parse -q --verify "origin/$base")" = "$before" ]; then
          cat "$err" >&2; rm -f "$err"
          echo "land_push: push to origin/$base rejected, and not by a concurrent push" >&2
          return 1
        fi
        git rebase -q "origin/$base" >/dev/null 2>&1 || {
          git rebase --abort >/dev/null 2>&1; rm -f "$err"
          echo "land_push: rebasing onto the new origin/$base conflicted — nothing pushed" >&2
          return 1
        }
      done
      rm -f "$err"
      echo "land_push: lost the race to origin/$base $LAND_PUSH_ATTEMPTS times" >&2
      return 1
    }

    # land_resolve <R-NNN> — print REPO BASE BRANCH SHIP_WT LAND_WT as shell
    # assignments for eval. Run from the main checkout. Blocks in ship-land.md run in
    # separate shells, so each one re-resolves instead of sharing variables.
    land_resolve() {
      local id="$1" repo base branch wt
      [ -n "$id" ] || return 2
      repo=$(git rev-parse --show-toplevel) || return 1
      base=$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
      [ -n "$base" ] || base=main
      branch=$(git -C "$repo" branch --list "ship/${id}-*" --format='%(refname:short)' | head -1)
      wt=""; [ -n "$branch" ] && wt=$(cd "$repo" && land_worktree_for_branch "$branch")
      printf 'REPO=%q\nBASE=%q\nBRANCH=%q\nSHIP_WT=%q\nLAND_WT=%q\n' \
        "$repo" "$base" "$branch" "$wt" "${TMPDIR:-/tmp}/ship-land-${id}/wt"
    }
    ```
    Keep `land_worktree_for_branch` unchanged.
- [x] **Step 4:** the three files pass; also run `bats tests/` (other files still reference removed functions — note which fail; Tasks 2–4 fix them; do not delete other tests here).
- [x] **Step 5:** commit `feat(R-008): ship_log always appends; land_is_merged asks the forge; land_push, land_resolve — Task 1`

### Task 2: ship-compound has one path

**Files:** `claude-skills/ship-workflow/commands/ship-compound.md`; tests `tests/test_ship-compound-merge-mode.bats` (delete), `tests/test_command-blocks.bats`

- [x] **Step 1: tests**
  - Delete `tests/test_ship-compound-merge-mode.bats`; create `tests/test_ship-compound-single-path.bats` with `@test "ship-compound has no merge-mode branches (R-008)"`: `for w in MERGE_MODE ship_log_defers context_pending ship-pending; do ! grep -qF "$w" "$SHIP_SKILL_ROOT/commands/ship-compound.md" || { echo "still mentions $w"; return 1; }; done`.
  - `test_command-blocks.bats`: delete `ship-compound step 9 (mr) refuses to run on the base branch` and `ship-compound step 9 (mr) commits only this ship's own paths and pushes its branch`. Replace `ship-compound step 9 (squash) stops before committing when a required path is missing` with `ship-compound step 9 stops before committing when the learning is missing` (no `docs/learnings/R-1-x.md`; status ≠ 0; HEAD unchanged). Add `ship-compound step 9 commits in a repo with no vault mirror` (remove `docs/product` from the scratch repo and commit that; write the learning; run; status 0; HEAD subject is `compound: R-1 — shipped + learning`; `git show --name-only --format= HEAD` includes `docs/learnings/R-1-x.md` and `docs/learnings/_log.md`). Add `ship-compound step 9 appends SHIP_COMMIT_SUFFIX to the subject` (env `SHIP_COMMIT_SUFFIX=" [skip ci]"` → subject ends with ` [skip ci]`). In the remaining step-9 tests drop `(mr)` / `(squash)` from titles only if the title would otherwise be misleading; do not change their assertions. **Exception (authorized):** in `ship-compound step 9 … removes a plan with uncommitted edits and logs the row once`, the last assertion counts `log:` commits — R-008 removes that commit kind. Replace it with `[ "$(grep -c '| ship-compound | R-1 |' docs/learnings/_log.md)" -eq 1 ]` (the row is still written exactly once).
- [x] **Step 2:** run → new tests FAIL.
- [x] **Step 3: edit `commands/ship-compound.md`**
  - Frontmatter `description:` → `Wrap up R-NNN once its work is on the base branch — write the learning, update CONTEXT.md, move the ROADMAP row to Done, remove spec and plan (squash: ship-next Phase 8; mr: /ship-land)`.
  - `## Argument` body → `(none — uses \`ID\` when the caller set it, as /ship-land does; otherwise the most recent plan in \`docs/plans/R-*.md\`)`.
  - Step 2 → `**Identify the ship.** If \`ID\` is already set (by \`/ship-land\`), use \`docs/plans/${ID}-*.md\` — or \`docs/specs/${ID}-*.md\` when the plan is gone — and take \`slug\` from that filename. Otherwise find the most recent \`docs/plans/R-*.md\` and extract \`$ID\` and \`$SLUG\`.`
  - Step 5: append the sentence `When \`/ship-land\` points at a learning draft (\`<ship worktree>/.ship/learning-draft.md\`, written by ship-next Phase 8 in mr mode), start from it.`
  - Step 6: in the first bash block keep only the `context-md.sh` source (drop the merge-mode source and `MERGE_MODE=` line). Delete from the paragraph starting `**\`mr\` mode: queue, do not edit.**` through the paragraph ending `Sub-steps 2–4 below are the \`squash\` path.` inclusive.
  - Step 7: replace the whole step body with: the work is on the base branch (squash: Phase 7 landed it; mr: `/ship-land` runs this after the merge). Edit the AIR-OS ROADMAP.md: find the `${ID}` line under "🔥 Now"; strip `adhoc-inserted=true`, `status=in-progress`, `status=in-review` and the ` · mr=<url>` annotation if present; move it to "✅ Done" with `· ✅ $(date +%Y-%m-%d)`; atomic write via `.tmp` + `mv`.
  - Step 9: replace the two intro paragraphs and the whole bash block with:
    > 9. **Log + commit.** One commit, on whatever branch this runs on: the base branch in squash mode, `/ship-land`'s throwaway worktree at `origin/<base>` in mr mode. It never pushes.

    ```bash
    # shellcheck disable=SC1091
    source ~/.claude/skills/ship-workflow/lib/ship-log.sh

    <keep the existing spec-mirror `if [ -f "docs/specs/${ID}-${slug}.md" ]; then … fi` block verbatim>
    <keep the existing comment + `git rm -q -f --ignore-unmatch -- …` command verbatim>

    ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | shipped | n |"

    # Required: the learning and the log row. Missing either → stop rather than commit
    # a partial set under a title that claims both.
    git add "docs/learnings/${ID}-${slug}.md" docs/learnings/_log.md || exit 1
    # The vault mirror and this ship's TDD rule fragment, when the repo has them.
    for p in docs/product/ROADMAP.md docs/proposals docs/tdd-rules.d; do
      if [ -e "$p" ]; then git add "$p" || exit 1; fi
    done
    git commit -m "compound: $ID — shipped + learning${SHIP_COMMIT_SUFFIX:-}" || exit 1
    ```
    and rewrite the two trailing paragraphs to: this commit removes the plan, fix-plans, spec and (legacy) brainstorm (`ship_log` only appends, so the staged removal rides this commit); only the learning stays; the spec's full text is in the vault `Specs/`. `docs/tdd-rules.d/` is staged when present: step 6b writes this ship's rule fragment there. `/ship-land` sets `SHIP_COMMIT_SUFFIX=" [skip ci]"`.
  - Step 10: drop the `squash:` / `mr:` bullets; keep `ROADMAP item moved to Done`.
- [x] **Step 4:** `bats tests/test_ship-compound-single-path.bats tests/test_command-blocks.bats -f 'ship-compound'` pass.
- [x] **Step 5:** commit `feat(R-008): ship-compound has one path; squash step 9 needs only learning + log — Task 2`

### Task 3: ship-next — mr reviews carry only the work

**Files:** `claude-skills/ship-workflow/commands/ship-next.md`; tests `tests/test_ship-next-merge-mode.bats`, `tests/test_command-blocks.bats`

- [x] **Step 1: tests**
  - `test_command-blocks.bats`: replace `ship-next P9 (mr): logs on the review branch and pushes only that branch` with `ship-next P9 (mr): writes the row to the worktree's .ship/ship-log-row, commits and pushes nothing` (worktree on `ship/R-1-x` with a `.ship/` dir; env `WORKTREE`, `ID=R-1`, `SHIP_LOG_ROW='| d | ship-next | R-1 | shipped | n |'`; status 0; file content equals the row; HEAD of both checkouts and origin unchanged). Keep `an unset WORKTREE pushes nothing and writes nothing` (bash and zsh) and `refuses another ship's worktree left over in WORKTREE` — adjust only setup lines if the new block needs `.ship/`; assertions stay.
  - `test_ship-next-merge-mode.bats`: change `Phase 8 says where /ship-compound runs in each mode` to assert the Phase 8 section (between `^## Phase 8 ` and `^## Phase 8.5`) contains `--mark-review`, `learning-draft.md` and `/ship-land`, and does not contain `cd into` the worktree to run /ship-compound (i.e. does not contain `from \`$WORKTREE\``).
- [x] **Step 2:** run → FAIL.
- [x] **Step 3: edit `commands/ship-next.md`**
  - Phase 7, the paragraph starting `**\`mr\` does not move \`$ORIG_BRANCH\`.**` → `**\`mr\` does not move \`$ORIG_BRANCH\`.** The review carries only the work. Phase 8 marks the row in-review and drafts the learning, Phase 9 keeps the branch and worktree, and \`/ship-land\` runs \`/ship-compound\` on the base branch once the review merges (R-008).`
  - Replace the whole `## Phase 8 — /ship-compound` section (heading through the line before `## Phase 8.5`) with:
    ````markdown
    ## Phase 8 — /ship-compound (squash) · in-review + learning draft (mr)

    **`squash`:** invoke `/ship-compound` for this R-NNN from the original repo cwd on
    `$ORIG_BRANCH` (Phase 7 already cd'd back). It writes the learning, updates
    `CONTEXT.md` (exports `CONTEXT_MD_STATUS`), moves the row to Done and removes the
    spec and plan.

    **`mr`:** do not run `/ship-compound` — every file it writes is shared or belongs on
    the base branch, and parallel reviews must not touch them (R-001, R-008).
    `/ship-land` runs it after the merge. Here:

    1. Mark the row in review:

       ```bash
       ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
       ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" --mark-review "$SHIP_REVIEW_URL"
       ```

    2. While the context is fresh, draft the learning from `templates/repo/LEARNING.md`
       into `$WORKTREE/.ship/learning-draft.md`: Key Decisions from the spec's
       `## Decisions`, What Changed From Plan from the plan and `.ship/codex-rounds.md`.
       It is not committed; `/ship-land` starts from it. Set
       `CONTEXT_MD_STATUS="deferred to /ship-land"`.
    ````
  - Phase 9 step 3: rewrite the prose before the block to: `squash`: in `$REPO`, on `$ORIG_BRANCH`. `mr`: nothing is committed now — the row goes to `$WORKTREE/.ship/ship-log-row` and `/ship-land` appends it with the compound commit after the merge. In the block, replace the whole `if [ "$MERGE_MODE" = "mr" ]; then ( … ) else` branch body with:
    ```bash
       (
         [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ] \
           || { echo "Phase 9: WORKTREE is not set — nothing logged" >&2; exit 1; }
         CUR=$(git -C "$WORKTREE" branch --show-current)
         case "$CUR" in
           "ship/${ID}-"*) : ;;
           *) echo "Phase 9: refusing to log into '$CUR' — expected ship/${ID}-*" >&2; exit 1 ;;
         esac
         mkdir -p "$WORKTREE/.ship"
         printf '%s\n' "$SHIP_LOG_ROW" > "$WORKTREE/.ship/ship-log-row"
       )
    ```
    keeping the existing `else` squash path (`ship_log`, `git add`, `git commit -m "log: ship ${ID}"`) unchanged.
- [x] **Step 4:** `bats tests/test_command-blocks.bats tests/test_ship-next-merge-mode.bats` pass.
- [x] **Step 5:** commit `feat(R-008): mr reviews carry only the work; Phase 8 drafts the learning — Task 3`

### Task 4: ship-land rewrite + docs

**Files:** `claude-skills/ship-workflow/commands/ship-land.md`; `tests/test_ship-land.bats`, `tests/test_command-blocks.bats`; docs: `claude-skills/ship-workflow/SKILL.md`, `claude-skills/ship-workflow/README.md`, root `README.md`, root `CONTEXT.md`, `claude-skills/ship-workflow/references/*.md`

- [x] **Step 1: tests**
  - `test_ship-land.bats`: replace `ship-land folds deferred CONTEXT.md entries through the lib` with `ship-land runs /ship-compound on the base branch in a throwaway worktree` (file contains `land_resolve`, `worktree add`, `/ship-compound`, `SHIP_COMMIT_SUFFIX`, `land_push`); replace `ship-land never writes _log.md or pulls the operator's checkout` with `ship-land never pulls or commits in the operator's checkout` (no `git pull`; no `git commit` line in the file; contains `ship-log-row`). Keep the others; update `ship-land refuses to run before the review has actually merged` only if its grep targets text that changed (it must still find `land_is_merged`).
  - `test_command-blocks.bats`: the three ship-land block tests (`removes a worktree whose vault mirror sync dirtied`, `every ship-land block that calls the lib sources it`, `worktree guard: allows a subdirectory of the main checkout, refuses a worktree`, `step 5 never cleans the operator's own checkout`) keep their assertions; update only how they invoke the block if the new step 5 needs `ID`/`land_resolve` (e.g. run with `ARGUMENTS=R-1` exported, since the loader would have substituted it).
- [x] **Step 2:** run → FAIL where expected.
- [x] **Step 3: rewrite `commands/ship-land.md`** — frontmatter `name: ship-land`, `description: Finish an R-NNN shipped with merge_mode=mr once its review merged — run /ship-compound on the base branch, push it, then remove the branch and worktree`, `discord-visible: true`. Body:
  - Intro (≤ 8 lines): in mr mode the review carries only the work; everything that writes a shared file runs here after the merge as `/ship-compound` in a throwaway worktree at `origin/<base>` (R-008). squash mode never needs this.
  - `## Usage` ```` ``` ```` `/ship-land R-NNN`.
  - `1. **Resolve.**` block: `ID="$ARGUMENTS"   # the R-NNN argument; Claude Code substitutes it`; usage check; the existing "run from the main checkout, not from a worktree" guard verbatim; `source ~/.claude/skills/ship-workflow/lib/ship-land.sh`; `eval "$(land_resolve "$ID")"`; `ROADMAP_PATH=…`; the existing "no branch → already landed? exit 0 : exit 1" logic using `$BRANCH`.
  - `2. **Verify the review merged.**` block: `ID="$ARGUMENTS"`; source lib; `eval "$(land_resolve "$ID")"`; `git -C "$REPO" fetch -q origin --prune`; `(cd "$REPO" && land_is_merged "$BRANCH" "$BASE") || { echo "ERROR: the review for $BRANCH has not merged into $BASE — nothing changed." >&2; exit 1; }`. One sentence: the forge is asked first, so squash merges count (R-002).
  - `3. **Compound on the base branch, in a throwaway worktree.**` block: `ID="$ARGUMENTS"`; source `ship-land.sh` and `ship-log.sh`; `eval "$(land_resolve "$ID")"`; if `$LAND_WT` exists, `git -C "$REPO" worktree remove --force "$LAND_WT"`; `mkdir -p "$(dirname "$LAND_WT")"`; `git -C "$REPO" worktree add -q --detach "$LAND_WT" "origin/$BASE" || exit 1`; `cd "$LAND_WT" || exit 1`; if `$SHIP_WT/.ship/ship-log-row` exists, `ship_log "$(cat "$SHIP_WT/.ship/ship-log-row")"`; echo the worktree and the learning-draft path. Then prose: run **`/ship-compound`** for `$ID` with `$LAND_WT` as the working directory, `ID` set, `SHIP_COMMIT_SUFFIX=" [skip ci]"`, starting step 5 from the learning draft; its step 7 moves the row to Done and its step 9 commits.
  - `4. **Push.**` block: `ID="$ARGUMENTS"`; source lib; `eval "$(land_resolve "$ID")"`; `(cd "$LAND_WT" && land_push "$BASE") || { echo "ERROR: could not push — the compound commit is left in $LAND_WT" >&2; exit 1; }`; `git -C "$REPO" worktree remove --force "$LAND_WT"`; `rm -rf "$(dirname "$LAND_WT")"`.
  - `5. **Clean up what Phase 9 kept.**` block: `ID="$ARGUMENTS"`; source lib; `eval "$(land_resolve "$ID")"`; `cd "$REPO"`; then the existing step-5 body with `WORKTREE` replaced by `SHIP_WT` (keep the never-the-main-checkout guard, the mirror restore loop, `git worktree remove` with its WARN, `git branch -D "$BRANCH"`, remote delete).
  - `6. **Report:**` the compound commit, the row now in Done, branch and worktree removed.
- [x] **Step 4: docs** — update every mention of `Ship-Log` trailers, `ship-pending`, `land_context`, `context_pending`, "fold" of CONTEXT entries, or "/ship-land folds…" in `claude-skills/ship-workflow/SKILL.md`, `claude-skills/ship-workflow/README.md`, `claude-skills/ship-workflow/references/*.md` and root `README.md` to the R-008 behavior (one line each). In root `CONTEXT.md`, delete the entries `**Ship-Log trailer**`, `**ship-pending queue**`, `**land commit**` and add `- **land (mr mode)** — \`/ship-land R-NNN\` after the review merges: runs \`/ship-compound\` in a throwaway worktree at \`origin/<base>\` and pushes one \`[skip ci]\` push; review branches never write shared files (R-008).` Do NOT edit `docs/learnings/*` (history).
- [x] **Step 5:** `cd claude-skills/ship-workflow && bats tests/` → green except the known cwd-guard failure; `grep -rnE 'ship_log_defers|context_pending|land_context|ship-pending' claude-skills/ship-workflow --include=*.sh --include=*.md --include=*.bats` prints nothing.
- [x] **Step 6:** commit `feat(R-008): /ship-land runs /ship-compound on the base branch after the merge — Task 4`

## Execution log

- Task 1 RED: the three prescribed test files failed on the new append/count, forge, push and resolve cases.
- Deviation: updated the existing zsh ship_log test to assert unchanged HEAD and the appended row — it still required the removed trailer commit, contrary to Task 1's new behavior.
- Task 1 GREEN: all 34 targeted tests pass. Full suite: 625 tests, 7 failures: the known cwd-guard baseline and six test_command-blocks cases for ship-next P9 / ship-compound step 9, scheduled for Tasks 2–3.

- Task 1 committed as `837e8e7` with the prescribed message.
- Task 2 RED: prescribed filtered command failed on the single-path, no-vault, suffix and retained mr cases before implementation.
- Task 2 BLOCKED at Step 4: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-single-path.bats tests/test_command-blocks.bats -f 'ship-compound'` passes 9/10. The retained test `ship-compound step 9 removes a plan with uncommitted edits and logs the row once` fails at test_command-blocks.bats:141: `[ "$(git log --format=%s | grep -c '^log: ')" -eq 1 ]`. The prescribed implementation creates only `compound: R-1 — shipped + learning`, and Task 1 makes ship_log never commit. Producing the expected separate log commit would change the specified behavior; replacing the assertion conflicts with Task 2 Step 1's explicit instruction not to change retained assertions. No assertion was removed, skipped or loosened for this failure.
- Task 2 implementation and test changes remain uncommitted; Task 2 is not complete. Tasks 3 and 4 were not started. To resume, the plan needs to authorize replacing this obsolete commit-count assertion with an assertion that the compound log row appears exactly once.

- Task 2 resumed: applied the authorized row-count assertion repair; all 10 prescribed ship-compound tests pass. Earlier blocker resolved.

- Task 3 RED: the new row-file and Phase 8 assertions failed before implementation; after the prescribed edit, the exact row-content assertion still failed.
- Deviation: preserve a supplied SHIP_LOG_ROW and generate it only when empty — the existing unconditional assignment overwrote the row required by Task 3’s prescribed test.
- Task 3 GREEN: all 42 tests in the two prescribed files pass.

- Task 4 RED: the updated merge-signature, throwaway-compound and saved-row tests failed against the old command.
- Deviation: updated the block-source guard’s function matcher to land_resolve/land_is_merged/land_push — its removed-function matcher both missed new callers and failed the required zero-reference scan. The source assertion is unchanged.
- Deviation: split removed identifier literals with adjacent shell quotes in the single-path regression test — the prescribed zero-reference grep otherwise matches the test’s own forbidden-word list; runtime strings and assertions are unchanged.
- Final review: independent read-only review found no blocking implementation issues; all four Review Focus requirements pass inspection.
- Final review limitations: restarting prescribed step 3 removes an existing landing worktree; rebase-conflict handling is verified by inspection, without a dedicated conflict regression test.
- Final review minor (deferred): existing SKILL.md/README.md descriptions call ship-compound Phase 8 without qualifying squash mode; left outside the explicitly requested wording edits.
- Task 4 GREEN (baseline exception): full `cd claude-skills/ship-workflow && bats tests/` ran 621 tests, 620 passed; only known `cwd-guard: exits 0 when not in a git repo at all` failed. All 43 targeted command/land/single-path tests passed after the guard repairs. Required obsolete-reference grep printed nothing; git diff --check passed.
- Completion: Tasks 2–4 implemented in order, one new commit per task; no branch switch, remote push, amend, hook bypass, history-learning edits or changes to the real ~/.claude.
