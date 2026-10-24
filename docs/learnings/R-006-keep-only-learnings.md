---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-006
tags: [learning, ai_system, ship-workflow, ship-compound, docs, specs]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-006
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> R-006: a shipped R-NNN now leaves one doc in the repo, its learning.
> - The brainstorm record is gone. Decisions live in the spec's `## Decisions` and are
>   carried into this file's `## Key Decisions`.
> - ship-compound step 9 mirrors the spec to the vault `Specs/`, then removes it, along
>   with the plan (R-005) and any legacy brainstorm.
>
> The trigger was AI greps picking up superseded designs as if they were current.

## What Shipped
- **ship-compound step 9**, before `ship_log`:
  - Mirrors the spec to the vault (best-effort: no binding → WARN, continue).
  - One `git rm -q -f --ignore-unmatch` covers plan, fix-plans, spec and legacy brainstorm.
- **ship-compound step 4** lists Key Decisions.
- **ship-compound step 3**: the CONTEXT prune rule cites `docs/learnings/`.
- **ship-next Phase 3**:
  - Requires `## Decisions` in the spec.
  - Verifies and commits only the spec (`spec: <ID> <slug>`).
- **ship-next Phase 7**: the `Spec:` line names the `spec: <ID>` commit and the vault.
- **Templates**:
  - SPEC.md gains `## Decisions`.
  - LEARNING.md gains `## Key Decisions`.
  - BRAINSTORM.md is deleted (nothing read it).
- **Docs**: the root README, SKILL.md, the skill README, ship-init and flow-diagrams no
  longer promise per-ship brainstorm/spec/plan files.
- **Tests**: 3 new step-9 block tests (spec removal in mr and squash; vault gets the
  post-review text) and 3 structural template/Phase-3 tests. Suite: 638 ok, plus 1 known
  cwd-guard failure.
- **One-off line-oa cleanup**: MR !307.
  - Removed 321 brainstorms/specs.
  - All of them were mirrored to the vault first (`Specs/`, `Specs/superpowers/`,
    `Brainstorms/`).
  - Kept 35 files cited by code and the specs of 11 unticked R rows.

## Key Decisions
- Keep only the learning after a ship (leric, 2026-10-24).
  - Why: past-ship reads in line-oa sessions were brainstorm 8, spec 46, learning 34,
    and only the learning is read on purpose.
  - Why: one topic carried four generations of design (churn: R-206 / R-222 /
    R-233.1 / R-233.2).
- Fold the brainstorm into the spec (leric). There is one "why" record during the ship
  and it travels into the learning.
- Re-mirror the spec at step 9 (my call). Review rounds edit the spec after Phase 3's
  first mirror.
- The mirror is best-effort (my call). Without a vault, git history still holds the spec.
- In mr mode the spec leaves the MR diff during review (accepted). The MR body points at
  the `spec: <ID>` commit.

## What Changed From Plan
- Added Key Decisions to ship-compound step 4's section list. The plan missed it, and
  without it compound would never fill the template section.
- The review fix pass reworded the MR body's `Spec:` line and the root README and
  `ce-skill-mapping.md`.

## Bugs
- None shipped. Review attempt 1 found two importants:
  - mr reviewers lose the spec from the diff.
  - The README still promised per-ship brainstorms.

## Reusable Patterns
- **Count reads per artifact before deciding what to keep.** A transcript scan of
  `Read`/`cat` calls, split into own-ship vs other-ship, settled "do we need this file"
  in one query. For files that would otherwise all look equally important, that split
  is the deciding number.
- **Mirror, then delete.** When a repo file leaves for a canonical store, copy its latest
  text in the same step that removes it. Copying at creation time misses later edits.

## Technical Debt
Deferred review minors:
- **Phase 8.5 seam check.** Its seam-violation category needs the spec's `## Seams`
  after step 9 removed it. Read it from the vault or git.
- **Failure ordering in step 9.**
  - `git rm` runs before squash mode's required-path `git add`, so a failure there leaves
    spec and plan deleted in the worktree.
  - ai_system always hits that failure, because it has no `docs/product/`. R-004/5/6
    ran step 9 by hand.
- **Mirror warning edge cases.**
  - The WARN says "stays in git history", but `-f` drops uncommitted spec edits when the
    mirror also failed.
  - A vault `Specs/` entry that is a symlink to the repo spec dangles after removal.
- **Auto mode wording.** It records auto-picked answers under "what the operator
  decided".
- **Ships already in flight.** A ship begun before R-006 has no `## Decisions`, and its
  legacy brainstorm is removed without being read.
- **Weak tests.** The step-9 tests assert the index, not the compound commit.
- **Pre-existing:** an empty `airos_vault` resolves the project path to `/10 Projects/…`.

## Future Follow-ups
- Give ai_system the shared paths its own squash step 9 expects, or make that `git add`
  skip absent paths. Then compound can run verbatim here.
- `docs/superpowers/specs/` from direct superpowers use still lands in git in line-oa
  (non-goal here). `docs/superpowers/plans/` is gitignored by !306.
