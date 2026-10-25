---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-008
status: draft
tags: [ship-workflow, merge-mode, mr, ship-land, ship-compound]
ai-first: true
supersedes: R-002
---

## For future Claude
> In `merge_mode: mr` the review now carries only the work (code, tests, spec, plan).
> Everything that writes a shared file — learning, CONTEXT.md, the `_log.md` row,
> removing spec and plan, the ROADMAP Done move — runs in `/ship-land` after the review
> merges, as `/ship-compound` in a throwaway worktree at `origin/<base>`, pushed in one
> `[skip ci]` push. R-001's deferral machinery (Ship-Log trailers, the ship-pending queue,
> `land_context`) is deleted: in practice it was never exercised. `land_is_merged` asks
> the forge first, so GitLab squash merges are recognised (closes R-002).

## Decisions
- leric, 2026-10-25: keep MRs (MR-only CI jobs: test-migrations, static antipatterns,
  migrations/SQL integration; shane.lin caught P1s on !243 and !271); compound after merge.
- Evidence the old design was unused: line-oa had 0 Ship-Log trailers on any ref, 0
  `docs/ship-pending` in any ref, 0 `context: land` commits; MRs carried no compound
  commits and compound happened on main after merge (e.g. `log: ship R-246`).
- My call: ship-next Phase 8 (mr) still drafts the learning, into the ship worktree's
  `.ship/learning-draft.md`, while the context is fresh; Phase 9 (mr) writes its log row
  to `.ship/ship-log-row`. `/ship-land` uses both.
- My call (review attempt 1): `/ship-idea --during-build` rows also wait in `.ship/ship-log-rows`; `ship_log` defers on a review branch instead of R-001's trailer.
- Known limit: two `/ship-land` runs racing on a repo that tracks the vault mirror can still conflict on `docs/product/`; `land_push` then pushes nothing and says how to retry.
- My call: `/ship-land` keeps "run from the main checkout" (existing guard + test) and
  resolves everything per block via `land_resolve`, because blocks do not share a shell.
- My call: squash step 9 requires only the learning and `_log.md`; the vault mirror
  (`docs/product/ROADMAP.md`, `docs/proposals/`) and `docs/tdd-rules.d/` are added when
  present — ai_system has no mirror and step 9 always failed there.
- My call: `land_push` rebases onto a moved `origin/<base>` and retries (3 attempts);
  any other rejection fails at once.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `ship_log` | `ship_log "<row>"` | Never commits. In mr mode on a `ship/*` branch, appends the row to `<toplevel>/.ship/ship-log-rows` (untracked; `/ship-land` replays it after the merge); otherwise appends to `docs/learnings/_log.md`. Exit 2 on an empty row or outside git. |
| `ship_log_ratio_count` | `ship_log_ratio_count` | Number of `_log.md` lines containing `ratio `. |
| `land_is_merged` | `land_is_merged <branch> <base>` | Exit 0 when the forge (glab / gh) reports a merged review from `<branch>` into `<base>` whose head contains the local branch tip (fetched as `refs/merge-requests/<iid>/head` / `refs/pull/<n>/head`), or when the tip is an ancestor of `origin/<base>`; else 1; 2 on usage. Containment is what makes `git branch -D` lose nothing. |
| `land_push` | `land_push <base>` (cwd: a worktree with commits on top of `origin/<base>`) | Pushes HEAD to `origin/<base>`. If rejected and `origin/<base>` moved, rebases onto it and retries, up to `LAND_PUSH_ATTEMPTS`. Any other rejection, or a rebase conflict, exits 1 with nothing pushed. |
| `land_resolve` | `land_resolve <R-NNN>` (cwd: anywhere in the repo) | Prints shell assignments `REPO BASE BRANCH SHIP_WT LAND_WT` for `eval`; `REPO` is the main checkout; `BRANCH` empty when no `ship/<R-NNN>-*` branch exists; `SHIP_WT` blank when the branch is checked out in the main checkout; `LAND_WT` includes the repo name. |
| ship-compound step 9 | its bash block, with `ID`, `slug` | One commit containing the learning and `_log.md` (+ mirror paths and `docs/tdd-rules.d/` when present) and the removal of spec/plan/fix-plans/brainstorm; message `compound: <ID> — shipped + learning<SHIP_COMMIT_SUFFIX>`; never pushes; exits non-zero without committing when the learning is missing. |
| ship-next Phase 9 step 3 (mr) | its bash block | Runs `ship_log` inside `$WORKTREE`, so the row lands in `$WORKTREE/.ship/ship-log-rows`; commits nothing, pushes nothing; with `WORKTREE` unset or on another ship's branch, exits non-zero and writes nothing. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | mr repo on a `ship/*` branch / on the base branch | `ship_log "<row>"` | row in `.ship/ship-log-rows`, `_log.md` untouched / row appended to `_log.md`; no new commit either way |
| AC-2 | fake `glab` on PATH answering one merged MR for `ship/R-1-x`; branch tip NOT in origin/main | `land_is_merged ship/R-1-x main` | exit 0 |
| AC-3 | no forge CLI answer; tip in origin/main / not in it | `land_is_merged` | 0 / 1 |
| AC-4 | temp worktree with one commit; origin/main moved by another clone meanwhile | `land_push main` | origin/main contains both commits |
| AC-5 | origin rejects every push (pre-receive hook exit 1) | `land_push main` | exit 1, origin unchanged |
| AC-6 | squash repo with no `docs/product`, no `docs/proposals` | step 9 | exit 0, compound commit made |
| AC-7 | learning file missing | step 9 | exit ≠ 0, HEAD unchanged |
| AC-8 | ship-next P9 step 3 (mr) with WORKTREE set / unset | run | row in `.ship/ship-log-rows`, HEAD and origin unchanged / exit ≠ 0, nothing written |
| AC-11 | forge reports a merged MR whose head is a child of the local tip | `land_is_merged` | exit 0 |
| AC-12 | `/ship-land` re-run after its compound commit reached origin | step 1 | prints `already compounded`, points to step 5 |
| AC-9 | `commands/ship-compound.md` | read | no `MERGE_MODE`, `ship_log_defers`, `context_pending`, `ship-pending` |
| AC-10 | suite | `bats tests/` | green except the known cwd-guard failure |
