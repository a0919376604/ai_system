---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-006
status: draft
tags: [ship-workflow, ship-next, ship-compound, docs, specs, brainstorms]
ai-first: true
supersedes: null
related-specs:
  - docs/specs/R-005-drop-shipped-plans.md
---

## For future Claude
> After R-006 a shipped R-NNN leaves exactly one doc in the repo:
> `docs/learnings/<ID>-<slug>.md`. The brainstorm record is no longer a separate file —
> the dialogue's decisions go into the spec's `## Decisions` section, and the learning
> carries them forward as `## Key Decisions`. ship-compound step 9 re-mirrors the spec
> to the vault and then removes it, together with the plan (R-005) and any legacy
> brainstorm. Full specs stay readable in the vault `Specs/` folder and in git history.

## Decisions
- leric, 2026-10-24: 「有需要這麼多文件麼」—— the concern is AI grep landing on stale
  design docs, not file count. Evidence from line-oa sessions: past-ship reads were
  brainstorm 8, spec 46, learning 34 (learning is read on purpose by Phase 3). One topic
  carried four generations of design (churn: R-206 / R-222 / R-233.1 / R-233.2).
- leric approved: keep only the learning after a ship; fold brainstorm into spec; remove
  spec at compound; full versions in vault. One-off line-oa cleanup is MR !307.
- My call: the spec is re-mirrored to the vault in step 9 before removal, because review
  rounds edit the spec after Phase 3's first mirror (R-005's did).
- My call: the mirror is best-effort. A repo with no vault binding still removes the spec;
  git history holds it.
- My call: `templates/repo/BRAINSTORM.md` is deleted — no command reads it.

## §1 Problem
Every ship leaves three docs on main (brainstorm, spec, learning). Only the learning has
a reader after the ship. The other two are design snapshots that later ships supersede,
and AI greps treat them as current.

## §2 Goals and non-goals
**Goals**
- G1. Phase 3 writes no `docs/brainstorms/` file. Spec carries `## Decisions`.
- G2. After ship-compound step 9, `docs/specs/${ID}-${slug}.md` and
  `docs/brainstorms/${ID}-${slug}.md` are not tracked (both modes). The plan removal
  from R-005 still happens. Other ships' files are untouched.
- G3. Before removal the spec is copied to `<vault project>/Specs/${ID}-${slug}.md`.
  Mirror failure does not stop step 9.
- G4. The learning template has `## Key Decisions`.

**Non-goals**
- `docs/superpowers/specs/` written outside ship-next.
- Existing repos' old specs (line-oa: MR !307).
- id-gen still scans `docs/brainstorms/` and `docs/specs/` for legacy IDs.

## §3 Design
- `commands/ship-next.md` Phase 3: step 1 tells brainstorming the spec needs a
  `## Decisions` section (what the operator decided, and why) and that there is no
  separate brainstorm file; step 2 verifies only the spec; step 3 commits only the spec
  (`spec: ${ID} ${SLUG}`). Phase 7 body's `Spec:` line says it is removed by
  `/ship-compound` and mirrored to the vault.
- `commands/ship-compound.md` step 9, in the existing pre-`ship_log` block:
  mirror the spec if it exists (`spec-mirror.sh … || echo WARN`), then one `git rm -q -f
  --ignore-unmatch` for plan, fix-plans, spec and legacy brainstorm. Step 3's CONTEXT
  prune rule cites `docs/learnings/` instead of `docs/specs/` / `docs/plans/`.
- `templates/repo/SPEC.md` gains `## Decisions`; `templates/repo/LEARNING.md` gains
  `## Key Decisions`; `templates/repo/BRAINSTORM.md` is deleted.
- `commands/ship-init.md`, `SKILL.md`, `README.md`, `references/flow-diagrams.md`: stop
  listing `brainstorms/` as a per-ship folder.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| ship-compound step 9 | the step's bash block, run with `ID`, `slug` set, on a `ship/*` branch (mr) or the base branch (squash) | The commit it makes leaves none of `docs/specs/${ID}-${slug}.md`, `docs/brainstorms/${ID}-${slug}.md`, `docs/plans/${ID}-${slug}.md`, `docs/plans/${ID}-${slug}-review-fix-*.md` tracked, uncommitted edits included; other ships' files stay; the log row is written once. When a vault project path resolves, `Specs/${ID}-${slug}.md` there equals the removed spec's content (plus the `mirror-source:` key). With no vault binding, step 9 still exits 0. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | mr repo, `ship/R-1-x` with tracked spec, legacy brainstorm and plan for R-1-x, and another ship's spec `R-2-y` | step 9, `ID=R-1 slug=x` | exit 0; R-1-x spec/brainstorm/plan untracked; `R-2-y` spec tracked |
| AC-2 | AC-1, with a vault project path bound and the spec edited and committed after Phase 3 | step 9 | vault `Specs/R-1-x.md` contains the edited text |
| AC-3 | squash repo, no vault binding, tracked R-1-x spec | step 9 | exit 0; spec untracked |
| AC-4 | ship-next.md Phase 3 | read | no `docs/brainstorms/` path in steps 2–3; step 1 names `## Decisions` |
| AC-5 | the R-005 step 9 tests | run unchanged | still pass |
