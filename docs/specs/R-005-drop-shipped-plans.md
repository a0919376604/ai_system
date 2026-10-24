---
date: 2026-10-24
updated: 2026-10-24
type: spec
id: R-005
status: draft
tags: [ship-workflow, ship-compound, docs, plans]
ai-first: true
brainstorm: docs/brainstorms/R-005-drop-shipped-plans.md
supersedes: null
---

## For future Claude
> A plan is the executor's input. Its last reader is ship-compound (step 2–4), which
> reads it to write the learning. After that it is dead weight: on langlive-line-oa
> 321 plans (13.5 MB) had piled up with zero references. ship-compound step 9 now
> `git rm`s this ship's own plan files in the same commit as the learning, in both
> merge modes. Specs, brainstorms and learnings are untouched.

## §1 Problem

Every `/ship-next` commits `docs/plans/${ID}-${slug}.md` (and one
`-review-fix-N.md` per Phase 6 fix round) and nothing ever removes them. On
langlive-line-oa that was 134 ship plans plus 187 superpowers plans, average 44 KB,
mostly code that is now in the repo. They add grep noise to every agent session.
One-off cleanup: line-oa MR !306.

## §2 Goals and non-goals

**Goals**
- G1. After ship-compound step 9, `docs/plans/` holds no `${ID}-${slug}.md` and no
  `${ID}-${slug}-review-fix-*.md`, in `squash` and `mr` mode.
- G2. Removal is part of step 9's existing commit; no new commit.
- G3. A ship with no plan file (or no fix-plans) runs step 9 exactly as before.

**Non-goals**
- Other ships' plans, including in-flight ones on the base branch.
- `docs/superpowers/plans/` (written by superpowers outside ship-workflow).
- Specs, brainstorms, learnings.

## §3 Design

In `commands/ship-compound.md` step 9, once, after the mr-mode branch guard and
before `ship_log`:

```bash
git rm -q -f --ignore-unmatch -- "docs/plans/${ID}-${slug}.md" "docs/plans/${ID}-${slug}-review-fix-*.md" || exit 1
```

- **Before `ship_log`:** a failure must leave no log row behind, or a rerun records
  it twice. `ship_log` commits with `--only`, so in mr mode the staged removal is not
  swept into the Ship-Log commit; it rides the compound commit.
- **`-f`:** the plan may carry an uncommitted `## Execution log` note (ship-next
  Failure modes says to write one there). Steps 2–4 have already read it; without
  `-f` git refuses and step 9 aborts. (Found in review; reproduced.)
- `--ignore-unmatch` keeps G3: no plan, no error.
- Quoted globs are git pathspecs, matched against the index, so they need no shell
  globbing and match `-review-fix-2`, `-review-fix-10`, ….
- `${ID}-${slug}` prefixes keep R-095's removal from touching R-095.1's plan.
- `mr` mode: the deletion is a path carrying this ship's ID, so the "review branch
  touches only its own paths" rule (R-001) holds. The plan leaves the MR's net diff;
  ship-next Phase 7's body says so on its `Plan:` line.
- Step 2 ("most recent `docs/plans/R-*.md`") still finds the current ship's plan: it
  is removed only at step 9.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| ship-compound step 9 | the step's bash block, run with `ID`, `slug` set, on a `ship/*` branch (mr) or the base branch (squash) | The commit it makes deletes `docs/plans/${ID}-${slug}.md` and every `docs/plans/${ID}-${slug}-review-fix-*.md` that was tracked, uncommitted edits included; it deletes no other plan and writes the log row once. With none tracked, it commits what it committed before R-005. |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | mr repo, `ship/R-1-x` branch with tracked `docs/plans/R-1-x.md`, `R-1-x-review-fix-2.md`, and another ship's `R-2-y.md` | step 9 with `ID=R-1 slug=x` | exit 0; HEAD deletes both R-1 plans; `R-2-y.md` is still tracked |
| AC-2 | squash repo on main with tracked `docs/plans/R-1-x.md` and `R-1.1-z.md`, plus learning/ROADMAP/proposals/_log | step 9 with `ID=R-1 slug=x` | exit 0; HEAD deletes `R-1-x.md`; `R-1.1-z.md` is still tracked |
| AC-3 | the existing step 9 tests (no plan files) | run unchanged | still pass |
| AC-4 | mr repo, `ship/R-1-x` with a committed `docs/plans/R-1-x.md` that has an uncommitted `## Execution log` line | step 9 with `ID=R-1 slug=x` | exit 0; the plan is no longer tracked; exactly one `log:` commit |
