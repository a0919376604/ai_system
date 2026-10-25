# R-010 move-bash-to-lib Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** behavior-preserving refactor: ship-next.md's phase glue → `claude-skills/ship-workflow/lib/ship-next.sh`; cross-block state → `<worktree>/.ship/state.env`; history prose out. Read the spec's Seams first.
**Spec:** `docs/specs/R-010-move-bash-to-lib.md`

## Global Constraints
- Edit files in THIS worktree only. No `$<digit>` in `commands/*.md` / `*/SKILL.md` (positionals are fine in `lib/`).
- **Behavior is frozen.** Do not change what any step does, prints on failure, or exits with. Every behavioral test assertion must still hold; a test may change how it reaches the code (extracted block → lib function) but not what it asserts. Tests that only assert explanatory prose may be deleted — list each in the Execution log.
- New lib functions must work under bash and zsh (the Bash tool's shell is zsh): no `${arr[0]}`, no unquoted globs that may match nothing, `local` only inside functions.
- Commands keep sourcing libs via `~/.claude/skills/ship-workflow/lib/<name>.sh`; inside libs use the existing `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}` pattern.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all`.

## Review Focus
- zsh vs bash differences in moved code (arrays, `read`, word splitting, `local` at top level).
- Variables a later phase needs that previously leaked through the agent's memory: they must now be in state.env.
- mr-mode paths of Phase 7 and 9 (keep worktree/branch, defer log row, refuse another ship's worktree).

---

### Task 1: state file + Phase 6 mechanical gates + Phase 5 codex glue

- [x] Tests first (`tests/test_ship-next-lib.bats`, new): AC-1 round-trip (bash and zsh); `sn_state_set` replaces an existing key; `sn_state_load` on a worktree without state is a no-op (exit 0); `sn_mech_gates` — move the assertions of the existing tests that exercise Phase 6 step 0.5 (in `tests/test_ship-next-test-gates.bats` and `tests/test_command-blocks.bats`) to call `sn_mech_gates`, plus one test that the six keys land in state.env; `sn_codex_after_exit` on logs ending DONE / BLOCKED / infra prints the matching `CODEX_ROUTE`; it records rounds exactly as the current Phase 5 text does — a round is appended (and supervise state written) only on the `continue` route (done / done_with_concerns); a BLOCKED round is appended later by the agent after it classifies the report (unchanged prose); an infra run with no extractable report appends nothing. Reuse fixtures from `tests/test_ship-next-codex-loop.bats`.
- [x] Implement `lib/ship-next.sh` (header: what lives here and why — blocks don't share a shell) with `sn_state_set`, `sn_state_load`, `sn_mech_gates`, `sn_codex_after_exit` by moving the current block bodies verbatim, adjusting only for function scope and state writes.
- [x] Replace the Phase 6 step 0.5 block and Phase 5's "When codex exits" classification block in ship-next.md with short calls (`source …/ship-next.sh; sn_state_load "$WORKTREE"; sn_mech_gates "$WORKTREE" "$ORIG_BRANCH" "docs/plans/${ID}-${SLUG}.md"` etc.). Phase 1 step 6 (worktree path computed) additionally runs `sn_state_set` for `ID SLUG WORKTREE BRANCH ORIG_BRANCH AUTO` right after Phase 2 creates the worktree.
- [x] `bats tests/` → green except the known failure. Commit `refactor(R-010): state file, Phase 5/6 glue into lib/ship-next.sh — Task 1`

### Task 2: Phase 7 and Phase 9 into the lib

- [x] Tests first: move the assertions of the existing Phase 7 / Phase 9 block tests (`tests/test_command-blocks.bats` P9 tests incl. zsh variants, `tests/test_ship-next-merge-mode.bats` behavioral ones, the security-state capture test) to call `sn_ship_body`, `sn_land`, `sn_capture`, `sn_cleanup`, `sn_log`, `sn_summary`; add `sn_ship_body works without a plan file` (small-change lane).
- [x] Implement those functions by moving the block bodies. Signatures: `sn_ship_body <worktree> <id> <slug> <out>`; `sn_land <worktree> <id> <branch> <orig_branch> <title> <body_file>` (stores `SHIP_REVIEW_URL`, `MERGE_SHA`); `sn_capture <worktree> <id>` (security-review state + codex rounds archive → state + /tmp copies, exactly as step 0 does now); `sn_cleanup <worktree> <branch>` (steps 1–2 incl. mr keep); `sn_log <worktree> <id> <row>` (step 3 incl. mr defer and every guard); `sn_summary <worktree> <id>` (prints the step-4 SUMMARY from state). Merge mode is resolved inside each function (`merge_mode`), never passed between shells.
- [x] Replace Phase 7 and Phase 9 blocks in ship-next.md with short calls; keep the prose that tells the agent what to do with the results (notifications, Discord/PushNotification routing).
- [x] `bats tests/` → green except the known failure. Commit `refactor(R-010): Phase 7 and 9 into lib/ship-next.sh — Task 2`

### Task 3: prose diet

- [x] Rewrite the remaining prose of ship-next.md to instructions: keep every rule an agent must follow; keep a one-line why only where it prevents a known mistake; delete incident narratives, measurements, "this used to…", R-NNN histories, duplicated explanations (they live in docs/learnings). Keep headings and step numbers stable where tests anchor on them (grep tests for `^## Phase`, `^[0-9]+\. \*\*` anchors before renaming anything).
- [x] Structural tests that assert removed explanatory prose: delete them (list in Execution log). Tests that assert rules (e.g. "Phase 9 does not delete the branch while a review is open", security fail-closed wording, auto-mode rules): keep, adjusting only the grep to the new wording if the rule's wording changed.
- [x] Verify: `wc -l commands/ship-next.md` ≤ 650; longest bash block ≤ 15 lines (`awk '/^[[:space:]]*```bash/{f=1;n=0;next} /^[[:space:]]*```[[:space:]]*$/{if(f&&n>m)m=n;f=0;next} f{n++} END{print m}'`); `grep -nE '\$[0-9]' commands/*.md` nothing; `bats tests/` green except the known failure.
- [x] Commit `docs(R-010): ship-next instructions without history prose — Task 3`
- [x] Finally, review the whole branch for integration gaps between tasks (state keys written vs read, functions sourced where called) and note any in the Execution log.

## Execution log

- Task 1 RED: nine new seam tests failed because the new library/functions did not exist; all nine passed after extraction.
- Deviation: updated the security reviewer structural test to read the moved extra-checks text from `lib/ship-next.sh` — the full suite identified this additional consumer of the extracted Phase 6 block; its assertion is unchanged.
- Deviation: added explicit `|| return 1` to new nonfinal `[[ ... ]]` assertions — the suite-hygiene guard requires them so failures cannot be ignored.
- Task 1 complete: `bats tests/` ran 559 tests: 558 passed; only the declared pre-existing `cwd-guard: exits 0 when not in a git repo at all` failed. Bash/zsh syntax checks passed.
- Task 2 RED: body/land and migrated Phase 9 behavioral tests failed on the missing helpers; after extraction, all 19 seam/Phase 9 tests and 72 targeted structural/integration tests passed.
- Deviation: strengthened the existing mr cleanup test with an exit-status assertion — its directory-only assertion also passed when the helper was missing.
- Deviation: persisted DESCRIPTION, REPO, review counters, final Codex results, ponytail status, and CONTEXT.md status at their producers, and archived state before cleanup — the specified consumers need these values after the producing shell or worktree is gone.
- Deviation: retargeted the Codex capture-order guard to the helper call order and the ponytail summary guard to `sn_summary` — these additional structural consumers still inspected the removed inline bodies.
- Task 2 complete: `bats tests/` ran 562 tests: 561 passed; only the declared cwd-guard baseline failure remained.
- Deviation: compacted shell line continuations and simple error branches in the remaining Markdown blocks — deleting prose alone left four bash blocks above the specified 15-line limit. Commands, failure strings, and exit codes are unchanged.
- Task 3: retained all structural tests; none asserted prose that had to be deleted without a shorter equivalent instruction. Targeted suite: 112/112 passed.
- Task 3 structural wording update: the required-Seams guard now matches `Require ## Seams: a table` (with Markdown backticks); the requirement and assertion remain intact.
- Task 3 checks passed: 644 command lines, longest bash block 15 lines, no positional substitutions in commands. `bats tests/`: 561/562 passed; only the declared cwd-guard baseline failure remained. Final integration review pending.
- Final review: one Important integration regression, no Critical or Minor findings. Accepted resumes skipped Phase 2's state writer, so later state loads restored the previous invocation's AUTO mode.
- Deviation: refresh resolved inputs with the existing state setter on both accepted resume paths — preserves the current invocation's mode and initializes older worktrees without erasing accumulated phase results. The new regression test failed before the repair and passed afterward under both bash and zsh, for both AUTO transitions.
- Final ruling: preserve the existing MR success text saying "squash", baseline squash failure handling, and agent-mediated variables/source calls in unextracted Phase 5 instructions — the reviewer confirmed these predate this refactor; changing them would violate frozen behavior. Cost: those existing limitations remain.
- Deviation: make one additional integration-repair commit after the three prescribed task commits — the plan orders final review after the Task 3 commit, and existing commits must not be amended.
- Final integration repair verified: `bats tests/` ran 563 tests, 562 passed; only `cwd-guard: exits 0 when not in a git repo at all` failed (declared baseline). Command: 650 lines, longest bash block 15 lines, no `$<digit>` in command Markdown. Bash and zsh syntax checks passed. No new review findings remain; no assertions or shared fixtures were deleted or loosened.
