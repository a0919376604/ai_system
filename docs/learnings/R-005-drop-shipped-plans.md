---
date: 2026-10-24
updated: 2026-10-24
type: learning
id: R-005
tags: [learning, ai_system, ship-workflow, ship-compound, docs, plans]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-005
shipped: true
shipped-date: 2026-10-24
---

## For future Claude
> R-005: a ship now removes its own plan files in ship-compound step 9.
> The trigger was the operator asking why langlive-line-oa had so many docs. The answer
> was plans: 321 of them (13.5 MB, 0 readers) out of 861 files. A plan's last reader is
> ship-compound steps 2–4. After that it is the code it described, which git already has.
> Specs, brainstorms and learnings stay: those have readers.

## What Shipped
- `commands/ship-compound.md` step 9 runs one line after the mr-mode guard and before
  `ship_log`, in both merge modes:
  `git rm -q -f --ignore-unmatch -- "docs/plans/${ID}-${slug}.md" "docs/plans/${ID}-${slug}-review-fix-*.md"`.
- ship-next Phase 7 body: the `Plan:` line says the plan is removed by `/ship-compound`
  and kept in the `plan: <ID>` commit. In mr mode the plan leaves the MR's net diff.
- Three block-executing tests in `tests/test_command-blocks.bats`:
  - mr: this ship's plan and fix-plan go; another ship's plan stays.
  - mr: a plan with uncommitted edits goes, and the log row is written once.
  - squash: this ship's plan goes; the sibling `R-1.1` plan stays.
- One-off cleanup in langlive-line-oa, MR !306. It removed 342 files. Plans of the 10
  ROADMAP rows not yet ticked were kept, because they are `/ship-next` resume points.

## What Changed From Plan
- The plan put one `git rm` before each `git commit` (two lines). Review found that
  ordering wrong. It became one line, before `ship_log`, with `-f`. See Bugs.
- The chat proposal said "remove in ship-next Phase 9". It moved to ship-compound step 9
  instead. That is the single commit both merge modes pass through after the plan's last
  reader. In mr mode the plan then never reaches the base branch.

## Bugs
- **`git rm` after `ship_log` duplicated the log row.**
  - When a plan has uncommitted edits (an Execution log note), `git rm` refuses without
    `-f` and the step exits 1.
  - By then `ship_log` had already written the row. A rerun wrote it again.
  - Fix: any step that can fail goes before the first side effect.
  - `ship_log` commits with `--only`, so a staged removal is not swept into the Ship-Log
    commit. It waits for the compound commit.

## Reusable Patterns
- **Delete scratch artifacts at their last reader.** Find the last step that reads a
  generated input, and remove the input in that step's commit. Don't clean it up in a
  separate pass later. A cleanup that waits for later never comes: 321 files of evidence.
- **Before cutting a pile of docs, ask who reads each kind.** Count code references per
  folder with `git grep -hoE 'docs/…' -- ':!docs'`. Folders with 0 references are the
  candidates. Folders with readers stay, even if they are big.

## Technical Debt
- `templates/repo/BRAINSTORM.md` still writes `plan-path: docs/plans/…`. That path now
  dangles after compound.
- ship-compound step 3's CONTEXT prune rule ranks terms by citations under
  `docs/plans/`, which now only holds in-flight plans.
- In ai_system, step 9's squash `git add` names `docs/product/ROADMAP.md` and
  `docs/proposals/`. Neither exists here, so the block cannot run verbatim in this repo.
  This is pre-existing; R-004 and R-005 both committed the existing paths by hand.

## Future Follow-ups
- Pin G2 ("no new commit") and the push of the deletion in the mr test. (Deferred review
  nit.)
- Rerunning ship-compound after step 9 committed picks another ship's plan as the "most
  recent". Add a Failure-modes note: pass the ID explicitly.
- `docs/superpowers/plans/` is written by superpowers outside ship-next. It still
  accumulates in line-oa. ship-workflow does not own that path.
