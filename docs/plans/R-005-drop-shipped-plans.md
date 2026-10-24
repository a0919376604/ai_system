# R-005 drop-shipped-plans Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ship-compound step 9 removes this ship's own plan files in the commit it already makes.

**Architecture:** One `git rm --ignore-unmatch` line before `git commit` in both merge-mode branches of `commands/ship-compound.md` step 9. Tested by executing the real step 9 bash block in a scratch repo, as `tests/test_command-blocks.bats` already does.

**Tech Stack:** bash, git, bats.

**Spec:** `docs/specs/R-005-drop-shipped-plans.md`

## Global Constraints

- Removal scope: exactly `docs/plans/${ID}-${slug}.md` and `docs/plans/${ID}-${slug}-review-fix-*.md`.
- No new commit; the deletion rides step 9's existing commit.
- No plan tracked → step 9 behaves exactly as before (`--ignore-unmatch`).

## Review Focus

- A sibling ship's plan with a shared prefix (`R-1.1-z.md` vs `ID=R-1 slug=x`) must survive — covered by AC-2.
- Another ship's plan on the same branch (`R-2-y.md`) must survive — covered by AC-1.
- Several fix-plans (`-review-fix-2`, `-review-fix-3`) all go — AC-1 uses `-2`; the pathspec glob covers any N.
- The existing mr test asserts HEAD's exact file list; with no plan present it must not change — AC-3.

---

### Task 1: ship-compound step 9 removes this ship's plans

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md` (step 9 bash block, both branches)
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (after the existing step 9 tests, ~line 128)

**Interfaces:**
- Consumes: `compound_step9` helper and the scratch-repo `setup()` already in that file (mr mode, `docs/learnings/_log.md`, `docs/product/ROADMAP.md`, origin remote).

- [ ] **Step 1: Write the failing tests**

`@test "ship-compound step 9 (mr) removes this ship's plan and fix-plans, not another ship's"`
- `git worktree add -q -b ship/R-1-x "$SCRATCH/wt"`; cd there.
- Create and commit `docs/plans/R-1-x.md`, `docs/plans/R-1-x-review-fix-2.md`, `docs/plans/R-2-y.md`; write `docs/learnings/R-1-x.md`.
- Run the block with `ID=R-1 slug=x`. Assert: status 0; `git show --name-status --format= HEAD` contains `D	docs/plans/R-1-x.md` and `D	docs/plans/R-1-x-review-fix-2.md`; `git ls-files docs/plans` is exactly `docs/plans/R-2-y.md`.

`@test "ship-compound step 9 (squash) removes this ship's plan, not a sibling R-1.1 plan"`
- Switch config to `merge_mode: squash`; `mkdir -p docs/proposals` with one file; create and commit `docs/plans/R-1-x.md`, `docs/plans/R-1.1-z.md`; write `docs/learnings/R-1-x.md`.
- Run the block with `ID=R-1 slug=x`. Assert: status 0; HEAD deletes `docs/plans/R-1-x.md`; `git ls-files docs/plans` is exactly `docs/plans/R-1.1-z.md`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats -f 'plan'`
Expected: both new tests FAIL (plans still tracked).

- [ ] **Step 3: Add the removal line in both branches of step 9, immediately before each `git commit`**

```bash
git rm -q --ignore-unmatch -- "docs/plans/${ID}-${slug}.md" "docs/plans/${ID}-${slug}-review-fix-*.md" || exit 1
```

Add one sentence after the block: the plan's last reader is step 2–4, so step 9 removes it; specs, brainstorms and learnings stay (R-005).

- [ ] **Step 4: Run tests**

Run: `cd claude-skills/ship-workflow && bats tests/`
Expected: all pass except the known `cwd-guard: exits 0 when not in a git repo at all` failure in a linked worktree.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-compound.md claude-skills/ship-workflow/tests/test_command-blocks.bats
git commit -m "feat(R-005): ship-compound removes this ship's plan files — Task 1"
```
