---
date: 2026-10-15
updated: 2026-10-15
type: learning
id: R-001
tags: [learning, ai_system, ship-workflow, merge-mode, mr, codex]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-001
shipped: true
shipped-date: 2026-10-15
---

## For future Claude
> R-001: parallel `merge_mode: mr` ships no longer conflict, and `/ship-land` works.
> The headline lesson is not the design — it is that **every command-level defect
> this ship had was invisible to grep-based tests and visible the moment a block
> was executed.** Five of them were "a variable set in an earlier block".

## What Shipped
- Review branches write only paths carrying their own R-NNN:
  - `_log.md` rows → `Ship-Log:` trailers on empty commits (`lib/ship-log.sh`).
  - TDD rules → per-ship fragments, `docs/tdd-rules.d/<R-NNN>.md`.
  - The ROADMAP/proposals vault mirror is not committed on review branches.
  - `CONTEXT.md` entries are queued in `docs/ship-pending/<R-NNN>-context.md`.
- `/ship-land` rewritten on `lib/ship-land.sh`. `land_context` folds the queue
  onto `origin/<base>` in a throwaway worktree, in one `[skip ci]` commit. It
  redoes the fold only when it lost a push race, and otherwise fails with git's
  own error.
- `tests/test_command-blocks.bats` runs the real bash blocks of the command files
  in scratch repos under bash and zsh, with HOME pointing at the tree under test.
- Prior art consulted: towncrier/changesets (fragments), reno (permanent
  fragments), GitLab's move to `Changelog:` trailers. GitLab went from fragments
  to trailers, which is why `_log.md` became trailers, not fragments.

## What Changed From Plan
- The operator asked "is this flow good — how do others do it?" mid-brainstorm.
  The answer replaced a uniform "defer everything to /ship-land" design with a
  per-file mix, so most lands make no commit at all.
- codex added `git commit --only` to `ship_log`. `--allow-empty` alone swept
  already-staged files into the log commit. The supervisor reproduced it before
  accepting it, and it was a real plan defect.
- Review: 3 rounds, 1 blocking + 9 important, all fixed. 2 nits declined.

## Bugs
- **Phase 9 could push the base branch to origin.** `cd "$WORKTREE"` with an
  empty WORKTREE succeeds silently in bash and zsh, so `git push origin HEAD`
  ran from `$REPO` on main. The reviewer's suggested `( cd "$WORKTREE" || exit 1 )`
  did not close it, for the same reason. Fix: require a non-empty WORKTREE and
  a `ship/${ID}-*` branch.
- **Blocks do not share a shell.** `$MERGE_MODE` was read in 5 blocks that never
  set it:
  - ship-compound step 9
  - ship-next Phase 7 step 2
  - ship-next Phase 9 steps 1–3

  With it unset, mr mode silently took the squash path. A structural test now
  enforces "every block that reads MERGE_MODE resolves it".
- `merge_mode` read config only from the cwd. An uncommitted config (from
  `/ship-init --custom`) turned mr into squash inside worktrees. It now falls
  back to the main checkout's copy.
- `codex_verdict` misclassifies a run as `infra` whenever the log contains its
  own test names ("out of credits is infra"). This happens on ships that modify
  ship-workflow itself. Overridden by hand twice. Not fixed here.

## Reusable Patterns
- **Test prose-embedded shell by executing it.** Extract the fenced block, run it
  in a scratch repo with HOME redirected to the tree under test, and do it under
  both shells. A grep can prove a line exists, but never what it does.
- **Prototype, then generate the plan from the prototype.** The plan's code steps
  were `git apply` patches generated from a working prototype, replayed task by
  task to record exact red/green counts. This caught a plan defect (a test placed
  in the wrong task) before codex ran. Round 1 then had zero BLOCKED stops.
- **Per-file treatment of shared append-only files:** trailers for audit logs,
  fragments for read-by-tooling lists, a post-merge fold only for curated docs.

## Technical Debt
- `land_context` has no cleanup trap, so an interrupt leaves its temp worktree
  registered (`git worktree prune` clears it).
- Squash-mode `/ship-compound` step 9 still requires `docs/proposals/`. That is
  pre-existing; this repo has none, so this ship's own compound ran by hand.
- `code-review-parse.sh` emits `BLOCKING_COUNT=00` (the `grep -c || echo 0`
  pattern).

## Future Follow-ups
- `codex_verdict`: match infra signatures only in codex's own error lines.
- IDEA-NNN / D-NNN id collisions across parallel branches (spec §8 R2).
- ship-next learnings lookup: Claude Code substitutes `$0` in `awk 'length($0) >= 4'`
  with the argument, which disables the lookup on every `/ship-next R-NNN`.
  Fix: use bare `length`.
