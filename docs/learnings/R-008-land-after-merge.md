---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-008
tags: [learning, ai_system, ship-workflow, merge-mode, mr, ship-land]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-008
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> In `merge_mode: mr` the review carries only the work. `/ship-land R-NNN`, after the
> merge, runs `/ship-compound` in a throwaway worktree at `origin/<base>` and pushes one
> `[skip ci]` push: learning, `_log.md` rows (replayed from the ship worktree's
> `.ship/ship-log-rows`), CONTEXT.md, spec/plan removal, ROADMAP Done. R-001's trailers,
> ship-pending queue and `land_context` are gone — they were never exercised in practice.

## What Shipped
- `ship_log`: on a `ship/*` branch in mr mode, rows go to `.ship/ship-log-rows` (covers `/ship-idea --during-build`); elsewhere they append to `_log.md`. Never commits.
- `land_is_merged <branch> <base>`: asks glab/gh for merged reviews and requires one whose head (fetched as `refs/merge-requests/<iid>/head` / `refs/pull/<n>/head`) contains the local tip; else ancestry. Squash merges count (closes R-002); `git branch -D` loses nothing.
- `land_push <base>`: rebase-and-retry on a real race (ancestry decides), union driver for `_log.md` via `core.attributesFile`; any other rejection or conflict pushes nothing and says how to retry.
- `land_resolve <R-NNN>`: per-block re-resolution (blocks do not share a shell); REPO is the main checkout; SHIP_WT never the main checkout; LAND_WT keyed by repo + ID.
- ship-compound: one path; step 2 finds the ship by ID (spec first, never a review-fix plan); step 7 skips an already-Done row; step 9 requires only learning + `_log.md`, stages the whole vault mirror and `tdd-rules.d` when present, honors `SHIP_COMMIT_SUFFIX`.
- ship-next: Phase 8 (mr) marks in-review and drafts `.ship/learning-draft.md`; Phase 9 (mr) defers its row.
- `/ship-land` rewritten (176 → ~150 lines): re-runnable (already compounded → cleanup), refuses an empty push, refuses to discard unpushed land work.
- `sync.sh` honors `SHIP_SYNC_IN_WORKTREE=1` so the land worktree refreshes the tracked mirror.

## Key Decisions
- Keep MRs (MR-only CI jobs; teammates occasionally catch P1s) but compound after merge (leric).
- Rows wait in the ship worktree's `.ship/`, not in commit trailers (review attempt 1: `/ship-idea --during-build` reopened the shared-file write).
- Merge check = containment of the local tip, not equality (attempt 2: forge-side "Apply suggestion" commits).

## What Changed From Plan
- Three review fix rounds: deferred rows; tip pinning → containment; re-runnable/guarded ship-land; clean land worktree.
- One codex BLOCKED: the plan forgot to authorize updating a test that counted `log:` commits.

## Bugs
- `codex_verdict` flagged a DONE run as infra (R-007); still open → R-009.

## Reusable Patterns
- **Count before you design.** "0 trailers, 0 ship-pending, 0 land commits on any ref" decided this ship in one query; the machinery it removed had 6 review rounds behind it.
- **A land step needs a "did the thing I'm about to publish actually happen" guard** — an empty push succeeds silently.

## Technical Debt
- Two `/ship-land` runs racing on a repo that tracks the vault mirror can conflict on `docs/product/`; they push nothing and print a retry recipe.
- Without jq, the glab JSON fallback also reads milestone iids (harmless unless MR !<that number> contains the tip).
- Review attempt 3 was self-verified (operator interrupted a 15-min reviewer).

## Future Follow-ups
- R-009: codex_verdict false positive, run-plan zsh `ALIVE[0]`, review cost (security pass once).
