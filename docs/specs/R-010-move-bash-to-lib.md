---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-010
status: draft
tags: [ship-workflow, ship-next, refactor]
ai-first: true
---

## For future Claude
> ship-next.md was ~1,300 lines, half of it bash glue an agent transcribes into separate
> shells that share nothing — hence the re-sourcing and re-resolving in every block and
> variables silently lost between phases. R-010 moves that glue into `lib/ship-next.sh`
> (unit-tested functions), carries state between blocks in `<worktree>/.ship/state.env`,
> and strips history narrative from the instructions (it lives in learnings). Behavior is
> unchanged.

## Decisions
- leric approved "bash → lib, history prose out" as the last item of the auto run.
- My call: one new lib, `lib/ship-next.sh`, holding phase glue; existing libs keep their roles.
- My call: state file `<worktree>/.ship/state.env` (KEY=VALUE, `%q`-quoted), written by `sn_state_set`, read by `sn_state_load`; blocks call `sn_state_load` first. This also fixes Phase 7's body reading Phase 6 variables from another shell.
- My call: prose rule — keep instructions and one-line "why" only where it prevents a mistake; incident stories, "measured on…", "this used to…" go (they are in docs/learnings).
- Behavior-preserving: every behavioral test assertion stays; tests may switch from extracting a markdown block to calling the lib function. Tests that only pin explanatory prose may be deleted (listed in the plan's execution log).

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_state_set` / `sn_state_load` | `sn_state_set <worktree> KEY VALUE`; `sn_state_load <worktree>` | set: replace-or-append `KEY=<%q value>` in `<worktree>/.ship/state.env`; load: source it if present (no-op otherwise). Values with spaces/quotes round-trip. |
| `sn_mech_gates` | `sn_mech_gates <worktree> <orig_branch> <plan_file>` | Runs Phase 6 step 0.5 (refactor-violation check, test budget incl. shadow mode, review-extra-checks file); stores `MECH_BLOCKERS TEST_BUDGET_VERDICT SHIP_RATIO_BP BASELINE_RATIO_BP TEST_LINES_ADDED SRC_LINES_ADDED` in state; prints the same report lines as before. |
| `sn_ship_body` | `sn_ship_body <worktree> <id> <slug> <out_file>` | Writes Phase 7's squash/MR body from state + ROADMAP + plan (plan optional). |
| `sn_land` | `sn_land <worktree> <id> <branch> <orig_branch> <title> <body_file>` | squash: checkout orig, `merge --squash`, commit; mr: push branch, open review via `forge_mr_cmd`, store `SHIP_REVIEW_URL`; same failures/exits as before. |
| Phase 9 helpers | `sn_capture`, `sn_cleanup`, `sn_log`, `sn_summary` (signatures in the plan) | Same effects as the current Phase 9 steps 0–4, including mr-mode keep-worktree/branch, refusal of another ship's worktree, and an unset WORKTREE writing/pushing nothing. |
| Phase 5 helper | `sn_codex_after_exit <worktree> <plan> <slot>` | Classifies the run (`codex_verdict`), extracts the report, prints `CODEX_ROUTE=continue|classify|stop_infra` and `CODEX_REASON`; on `continue` only, appends the round and writes supervise state (as today). |
| `commands/ship-next.md` | file | ≤ 650 lines; no bash block > 15 lines; no `$<digit>`. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | worktree | `sn_state_set wt A 'x y "z"'`; new shell `sn_state_load wt; echo "$A"` | `x y "z"` |
| AC-2 | existing behavioral tests for P6 gates, P7, P9 (bash + zsh) | run against the lib functions | same assertions pass |
| AC-3 | ship-next.md | `wc -l`; longest bash block | ≤ 650; ≤ 15 |
| AC-4 | suite | `bats tests/` | green except the known cwd-guard failure |
