# R-009 trim-ship-next Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** see `docs/specs/R-009-trim-ship-next.md` (read its Decisions — they say what and why).
**Spec:** `docs/specs/R-009-trim-ship-next.md`

## Global Constraints
- Edit files in THIS worktree only. No `$<digit>` in `commands/*.md` / `*/SKILL.md`. Blocks run in separate shells.
- **Deleting tests is authorized only for the files and tests this plan names.** Changing other assertions is not.
- Do not edit `docs/learnings/*` (history) or `docs/superpowers/*`.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all`.

## Review Focus
- After deletions, nothing in commands/libs/tests/SKILL.md/READMEs references a removed lib, function, variable, template or test.
- Phase 9's summary and log row still render with the removed variables gone (no `${PRUNE_STATUS}` / `${UA_STATUS}` left).
- The security pass still never fails open when it does run.

---

### Task 1: executor tooling fixes

**Files:** `claude-skills/ship-workflow/lib/codex-verdict.sh`, `tests/test_codex-verdict.bats`, `claude-skills/run-plan/SKILL.md`, `claude-skills/ship-workflow/tests/test_command-blocks.bats` (or a new `tests/test_run-plan-blocks.bats`)
- [ ] Failing tests: `codex_verdict: an infra signature in test output is not infra` (log lines `ok 102 codex_verdict: out of credits is infra, not a verdict`, `DONE` → `done`); `codex_verdict_reason` likewise reports the marker. A zsh test that extracts run-plan's Step 5 status block, fakes one live slot (`/tmp/run-plan-codex-<test-slot>.pid` holding the PID of a `sleep 30` started by the test, cleaned in teardown) and asserts the block targets it when `ARGUMENTS='status'`.
- [ ] Implement: in `codex-verdict.sh` add `CODEX_INFRA_LINE_RE='^[[:space:]]*([0-9][0-9TZ:.+-]*[[:space:]]+)?ERROR'` and use `grep -aE "$CODEX_INFRA_LINE_RE" "$log" | grep -aqE "$CODEX_INFRA_SIGNATURES"` (and the same for the reason's `hit`); comment why (R-008: a test name in executor output). In run-plan, replace `SLOT="${ALIVE[0]}"` and `do_kill "${ALIVE[0]}"` with `for SLOT in "${ALIVE[@]}"; do break; done` (then `do_kill "$SLOT"`), comment: zsh arrays start at 1; delete `resolve_slot` and the sentence introducing it.
- [ ] Run the touched tests → pass. Commit `fix(R-009): codex_verdict reads infra only from ERROR lines; run-plan zsh first slot — Task 1`

### Task 2: delete features with no payoff

**Files:** `commands/ship-next.md`, `commands/ship-compound.md`, `commands/ship-init.md`, `lib/`, `templates/`, `tests/`, `SKILL.md`, `README.md` (skill), root `README.md`, `references/*.md`
- [ ] **UA:** remove ship-next `## Phase 1.5`, Phase 3 step 0's "UA pre-brainstorm context" sub-block (keep CONTEXT.md and learnings sub-blocks), Phase 6 step 0 (UA blast-radius + REMINDERS cross-ref) and any "Read `.ship/ua-diff-report.md`" mentions, `## Phase 8.7`, `UA_STATUS` in Phase 9 (summary line and the `rebuilt*` case); ship-compound step 5.5 (UA case stub) and step 5.6 (REMINDERS prompt); ship-init `--with-ua` (flag line and its step). Delete `lib/ua-integration.sh`, `templates/repo/CASE_ELI5.md`, and `lib/render-template.sh` if nothing else uses it. Delete tests: `test_ua-integration.bats`, `test_ua-understand-diff-wiring.bats`, `test_ua-zsh-portability.bats`, `test_ua-command-wiring.bats`, `test_ship-next-no-ua.bats`, `test_ship-next-ua-rebuild.bats`, `test_ship-compound-case-stub.bats`, `test_case-eli5-render.bats`; and individual tests elsewhere whose name or assertion is about UA.
- [ ] **Prune report:** remove Phase 8.5 steps 1–3 and the prose about the coverage gate; keep step 0 (test-churn report) under a heading `## Phase 8.5 — Test churn report`. Remove `PRUNE_STATUS` from Phase 9's log row and summary. Delete `lib/prune-report.sh`, `tests/test_prune-report.bats`, `tests/test_prune-report-boundary.bats`, `tests/test_prune-report-review.bats`, `tests/test_ship-next-prune.bats` (move any test-churn assertions from the last into `tests/test_ship-next-test-churn.bats` if they are not already there).
- [ ] **ship-compound delegation:** step 4 becomes "Draft the learning yourself" with the same section list; delete step `6. **Delegate to compound-engineering:ce-promote**`; step 10 drops "Patterns promoted to AIR-OS"; Failure modes drops the `ce-compound unavailable` line. Renumber nothing else.
- [ ] **ponytail pin:** in Phase 5 step 2.5 keep `ponytail_render_rules` and `PONYTAIL_STATUS`; delete `PONYTAIL_CURRENT/SHA/PINNED/PINNED_SHA/DRIFT`, the "On drift" section, and Phase 9's drift warning. In `lib/ponytail-integration.sh` delete `ponytail_version` / `ponytail_ruleset_sha256` if unused afterwards (and their tests). SKILL.md: `ponytail:` line → `ponytail: when installed, its ladder is rendered into .ship/ponytail-rules.md for the executor.`
- [ ] Docs: drop UA / prune / pin mentions from SKILL.md, the skill README, root README (the Understand-Anything bullet and table row), `references/*.md`.
- [ ] Verify: `grep -rnE 'ua_|ua-integration|understand-diff|prune_report|PRUNE_STATUS|ponytail_version|PONYTAIL_DRIFT|ce-compound|ce-promote|CASE_ELI5' claude-skills/ship-workflow README.md` → nothing (tests/.tmp excluded). `bats tests/` green except the known failure. Commit `refactor(R-009): drop UA integration, prune report, ce delegation, ponytail pin — Task 2`

### Task 3: review cost, small-change lane, landing-branch warning

**Files:** `commands/ship-next.md`, tests `tests/test_ship-next-security.bats`, `tests/test_command-blocks.bats`
- [ ] Failing tests: `ship-next P1 warns when the ship would land off the default branch` (scratch repo with origin and `origin/HEAD` → main, on branch `x`; run Phase 1 step 6's block with `ID=R-1 SLUG=x`; stderr contains `WARN`, `x`, `main`; exit 0). Structural: Phase 6 says the security pass runs once code review reports 0 blockers on the attempt; Phase 3 or 4 contains `Small-change lane`.
- [ ] Phase 1 step 6 block: after `ORIG_BRANCH=…` add `DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')` and `[ -n "$DEFAULT_BRANCH" ] && [ "$ORIG_BRANCH" != "$DEFAULT_BRANCH" ] && echo "WARN: this ship will land on '$ORIG_BRANCH', not '$DEFAULT_BRANCH' — fast-forward $DEFAULT_BRANCH yourself afterwards" >&2`.
- [ ] Phase 6: heading of step 1.5 → `Security pass (once code review clears the attempt)`; in the loop pseudo-code, parse `$REVIEW_OUT` alone first; only when that `BLOCKING_COUNT` (plus `MECH_BLOCKERS`) is 0 run steps 1.5–1.6 and re-parse with both files; a security blocker then starts the next attempt like any blocker. Keep steps 1.5/1.6 blocks unchanged otherwise (their fail-closed checks stay).
- [ ] Phase 4 top: add a `**Small-change lane.**` paragraph — when the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, go to Phase 6; log the choice in auto mode. Phase 7's task-list line: guard with `[ -f "docs/plans/${ID}-${SLUG}.md" ]` so a lane ship's body has no error.
- [ ] `bats tests/` green except the known failure. Commit `feat(R-009): security once per cleared attempt; small-change lane; landing-branch warning — Task 3`

### Task 4: ai_system .gitignore

**Files:** create root `.gitignore`
- [ ] Content:
  ```
  # ship-next scratch — per worktree, never committed
  .ship/
  .superpowers/
  .claude/.ship-*
  .claude/.id-reservations
  # vault mirror written by sync.sh; ai_system does not track it
  docs/product/
  ```
  Check `git ls-files` first: if any tracked file matches a pattern, stop and record it in the Execution log instead of committing.
- [ ] Commit `chore(R-009): ignore ship scratch and the untracked vault mirror — Task 4`

## Execution log

- Task 1: complete. Both verdict regressions and the isolated zsh status regression failed before the fixes; touched tests pass (27/27). The status fixture masks other live processes from its liveness check without modifying their slots.
- Deviation: removed the obsolete ponytail configuration example and its pin-specific test — leaving them would document deleted configuration and reference the removed hash function.
- Deviation: removed the two unused UA fixture helpers — the required no-reference check includes tests/helpers.bash; their only callers were deleted UA tests, and no retained shared fixture was changed.
- Deviation: changed the test-churn section extractor's end marker from Phase 8.7 to Phase 9 — Phase 8.7 is deleted, so the old extractor would include cleanup blocks instead of just the churn report.
- Task 2: complete. Removed-name grep has no matches (tests/.tmp excluded). `bats tests/`: 543 passed, only the declared pre-existing cwd-guard failure. The first suite overlapped edits and is not used as baseline evidence; this completed task suite is authoritative.
- Deviation: made the landing warning chain and default-branch lookup tolerate a missing/default-matching branch — the prescribed final `&&` chain returned 1 when no warning was needed, violating the non-blocking requirement (regression observed, then fixed).
- Deviation: the small-change lane explicitly records executor 2 and renders Phase 5's rule files — skipping the choice otherwise leaves Phase 6's fix-plan dispatcher without an executor and the inline implementation without its rendered rules.
- Task 3: complete. Required regressions observed failing then passing; warning/no-warning behavior verified in bash and zsh. `bats tests/`: 547 passed, only the declared pre-existing cwd-guard failure. Security steps 1.5/1.6 executable blocks remain unchanged.
- Task 4: complete. `git ls-files` matched none of the requested patterns; created the exact `.gitignore` and verified all five patterns with `git check-ignore`. No product behavior changed after Task 3's full-suite check.

### Final review — BLOCKED

This supersedes the completion status above: four task commits exist, but integration review found two defects the task suites do not cover. Do not treat the plan as fully complete.

- Task 4 blocker: `.gitignore` now ignores the untracked vault mirror, while `commands/ship-compound.md` step 9 explicitly stages an existing `docs/product` with `git add "$p" || exit 1`. Reproduced in an isolated scratch repo with the exact new ignore file and an untracked `docs/product/ROADMAP.md`: `git add docs/product` exits 1. Fixing compound's optional-path staging touches a module Task 4 does not involve, so the REPAIR RULE requires stopping. No assertions were loosened and no force-add workaround was applied.
- Task 3 integration finding: the small-change lane omits a plan, but Phase 8 invokes ship-compound, whose input list requires the plan and its first-commit timestamp and whose failure modes say “No plan found → ask user to run /ship-next first”. The lane needs explicit spec/implementation-commit fallback guidance. Not repaired after the Task 4 stop condition was established.
- Final verification: required removed-name grep has no matches; security steps 1.5/1.6 shell blocks match the original byte-for-byte; Task 3 suite had 547 passing tests plus the known cwd-guard failure. These checks do not cover the integration defects above.
- Stayed on `ship/R-009-trim-ship-next`; no remote push, amended commit, or hook bypass. This final status note is intentionally uncommitted: all four prescribed task commits already exist, and the workflow requires stopping and appending the note rather than creating another task commit.
