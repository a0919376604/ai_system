---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-009
status: draft
tags: [ship-workflow, ship-next, simplification]
ai-first: true
---

## For future Claude
> R-009 removes ship-next features that never paid off in real ships, makes review
> cheaper, adds a small-change lane, warns when a ship would land off the default
> branch, fixes two executor-tooling bugs found while shipping R-007/R-008, and gives
> ai_system a .gitignore. Evidence for each removal is in Decisions.

## Decisions
- leric (2026-10-25) approved the review list; asked for everything in auto mode; found the run slow → planned R-009 and R-011 merged into this ship (my call).
- Delete Phase 8.5's prune report: ~20 recorded runs, 3 proposed candidates, report-only. Keep its test-churn report (one call).
- Delete UA integration: `.ua/` is untracked, so it is absent from every ship worktree — Phase 3/6 always no-op'd (rc=2); `understand-diff` called 0 times.
- ship-compound writes the learning directly from the template: `ce-compound` and `ce-promote` were called 0 times in all sessions. Drop the UA case stub and the REMINDERS prompt with them.
- ponytail: keep rendering `.ship/ponytail-rules.md`; drop version pin / SHA / drift / re-pin.
- Security pass runs once per attempt that code review clears (was: every attempt). 6 runs → 0 findings; each costs a finder + filters.
- Small-change lane (my call on the threshold): one task, ≤ ~50 changed lines, no new seam → skip Phase 4's plan file and Phase 5's executor choice; implement inline with TDD; review gate unchanged. R-005 (2 lines) loaded 4 process skills + 2 reviewers.
- Landing branch: warn (not refuse) when `ORIG_BRANCH` is not the remote default branch (my call: refusing would break worktree-hosted sessions; silence lands work on the wrong branch, as happened in R-005–R-008).
- `codex_verdict`: infra signatures count only on `ERROR` lines (a bats test NAME "out of credits is infra" in executor output made a DONE run infra).
- run-plan: zsh arrays start at 1, so `${ALIVE[0]}` is empty in the Bash tool's shell; take the first element with a loop. Delete `resolve_slot` (no caller).

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `codex_verdict` | `codex_verdict <log>` | `infra` when a line starting with optional whitespace/timestamp then `ERROR` contains an infra signature, or no verdict marker; otherwise the last line-anchored marker. A signature inside any other line (e.g. test output) does not count. |
| run-plan status/kill (no arg) | `/run-plan status`, `/run-plan kill` | With exactly one live run, target it in bash and zsh. |
| ship-next Phase 1 | step 6 block | Prints `WARN` naming both branches when `ORIG_BRANCH` differs from `origin/HEAD`'s branch; never exits for it. |
| commands | `commands/*.md` | No `ua_`, `prune_report`, `PRUNE_STATUS`, `ponytail_version`, `PONYTAIL_DRIFT`, `ce-compound`, `ce-promote`. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | log with `ok 102 codex_verdict: out of credits is infra` then `DONE` | `codex_verdict` | `done` |
| AC-2 | log with `ERROR: … out of credits` | `codex_verdict` | `infra` (existing tests stay green) |
| AC-3 | one live slot, zsh | run-plan status block without an argument | targets that slot |
| AC-4 | repo on branch `x`, origin/HEAD → main | Phase 1 step 6 block | stderr has `WARN` with `x` and `main`, exit 0 |
| AC-5 | commands/*.md | grep the removed names | no match |
| AC-6 | suite | `bats tests/` | green except the known cwd-guard failure |
