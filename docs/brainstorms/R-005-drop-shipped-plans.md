---
date: 2026-10-24
type: brainstorm
id: R-005
status: complete
spec: docs/specs/R-005-drop-shipped-plans.md
---

# R-005 brainstorm — a ship removes its own plan when it closes

## Trigger

2026-10-24, leric：「以 langlive-line-oa 來說，用這個 ship 體系開發留下來的 docs 超多，
很多是不是不太需要？」

## What the audit found (langlive-line-oa, origin/main)

- `docs/` = 861 files, 24.8 MB.
- `docs/plans/` 134 files (5.8 MB, 14 of them `-review-fix-N`) and
  `docs/superpowers/plans/` 187 files (7.7 MB): **0** references from code, CLAUDE.md
  or README, apart from 2 superpowers plans cited by code comments. Average plan 44 KB;
  R-238's is 3,468 lines, mostly the code it was about to write.
- `docs/learnings/` is read by ship-next Phase 3; `docs/specs/` and
  `docs/superpowers/specs/` are cited by 35 `Spec:` code comments; brainstorms are the
  only record of why a decision went the way it did. Those stay.
- One-off cleanup shipped separately as line-oa MR !306 (342 files removed; plans of
  the 10 ROADMAP rows not yet ticked were kept).

## Who reads a plan, and when

| Reader | When | After compound? |
|---|---|---|
| ship-next Phase 3 resume check (`ls docs/plans/…`) | before execution | no |
| Phase 5 executor, Phase 6 mechanical gate + fix-plans | during the ship | no |
| Phase 7 squash body / MR description (task list) | landing | no |
| ship-compound step 2–4 (find ID, "What Changed From Plan") | Phase 8 | **this is the last reader** |
| `id-gen.sh` | allocating R-NNN | also scans specs, brainstorms, learnings, ROADMAP — no plan needed |

So the plan is dead the moment ship-compound has written the learning.

## Decision

- leric approved "both": the one-off cleanup (!306) and a workflow change so plans stop
  piling up again.
- **My call:** remove the plan in ship-compound step 9's own commit, not in ship-next
  Phase 9 as first proposed in chat. Step 9 is the one commit both merge modes pass
  through after the last reader. In `mr` mode the plan then never reaches the base
  branch; in `squash` mode it lands with the feature commit and leaves in the compound
  commit right after, so `git show <feat sha>` still has it.
- Scope is this ship's own files only: `docs/plans/${ID}-${slug}.md` and
  `docs/plans/${ID}-${slug}-review-fix-*.md`. Never another ship's plan (an in-flight
  ship's plan on main is its resume point).

## Not doing

- `docs/superpowers/plans/` written by superpowers outside ship-next — ship-workflow
  does not own that path.
- Rewriting the Phase 7 body's `Plan:` line. It names the path as it existed in the
  landed commit, which stays true in history.
