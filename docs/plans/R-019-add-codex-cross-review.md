# R-019 Codex cross-review for Claude-written ships — Implementation Plan

**Goal:** When Claude wrote the code (executor 1 or 2), Phase 6 also runs
`codex review --base <base>`. The findings are converted to ship's severity format,
tagged `[codex]` (`[both]` when code review hit the same lines), and appended to the
code review report.

**Spec:** `docs/specs/R-019-add-codex-cross-review.md`. Read it first. Its Facts section
comes from real runs of codex-cli 0.162.1.

## Global Constraints
- **Exact strings:**
  - tags `[codex]` and `[both]`;
  - state keys `CROSS_REVIEW` (`skipped|unavailable|ran`), `CROSS_REVIEW_COUNT` and
    `CROSS_REVIEW_BOTH`;
  - the log fragment `xreview=<count>/<both>`, or `xreview=skipped|unavailable`;
  - the summary line `• cross-review (codex): <count> finding(s), <both> also found by code review`,
    or `• cross-review (codex): skipped — codex wrote this code`, or
    `• cross-review (codex): unavailable`;
  - the WARN prefix `WARN: cross-review unavailable — `.
- **Severity mapping:** `[P0]`/`[P1]` → `🔴 [blocking]`, `[P2]` → `🟡 [important]`,
  `[P3]` → `🟢 [nit]`.
- **The codex separator is ` — `** (space, U+2014 em dash, space). Match it literally.
- **Shell behaviour:** it must work when sourced from zsh. Use awk for parsing; use
  `command grep` where an exit status matters; use no glob that can match nothing.
- **Never pass a custom prompt to `codex review`.** codex-cli 0.162.1 rejects it with
  `--base`.
- **Run tests scoped:** `cd claude-skills/ship-workflow && bats tests/<file>.bats`. Only
  Task 3 runs the full suite. The known `cwd-guard` failure is pre-existing.

## The real codex output, the stub's fixture
Reproduce it byte for byte, with `<WT>` replaced by the test worktree path:
```
Both changed functions introduce verified behavioral regressions: totals omit the first item, and refunds can produce negative balances.

Full review comments:

- [P1] Include the first item in the cart total — <WT>/pay.py:3-3
  For any nonempty cart, `items[1:]` excludes the first item's price, undercounting the total whenever that price is nonzero. For example, `total([{"price": 10}])` now returns `0` instead of `10`. Sum all items to preserve the documented behavior.

- [P2] Restore the zero floor for refund balances — <WT>/pay.py:8-8
  When `amount` exceeds `balance`, the subtraction now returns a negative balance, violating the function's documented invariant. For example, `refund(15, 10)` returns `-5` instead of `0`. Restore the zero clamp.
```
The no-findings output is the single line
`No actionable regressions were identified in the diff. All 44 targeted tests passed, and the generated API command uses supported glab flags. Live GitLab behavior was not tested.`

## Review Focus
1. A finding whose path is outside the worktree, e.g. an absolute path elsewhere. Keep
   it as given; never produce a path that starts with `/` after a failed strip, unless
   it was outside.
2. A description that contains ` — ` or `[P1]` in its prose must not be read as a new
   finding. Only lines starting with `- [P` are headers.
3. Two findings on the same file, one near a code-review line and one far from it.
   Only the near one gets `[both]`.
4. A review run whose stdout is non-empty but whose exit status is non-zero means
   unavailable. Nothing is appended.

---

### Task 1: `sn_cross_review`
**Files:** `claude-skills/ship-workflow/lib/ship-next.sh` (add `sn_cross_review`,
plus a private `_sn_codex_findings` helper if you want one). Create
`claude-skills/ship-workflow/tests/test_ship-next-cross-review.bats`.

**Interfaces:** `sn_cross_review <worktree> <review_out>` → 0. It persists the three
state keys. It reads `ORIG_BRANCH` from state and the executor from
`<worktree>/.claude/.ship-executor`.

- [ ] **Failing tests:**
  - Setup: a scratch worktree dir with `.ship/` state (`ORIG_BRANCH=main`), executor
    file `2`, and a stub `codex` on PATH.
    - The stub prints `$STUB_OUT` (the fixture with `<WT>` replaced by the worktree's
      path) and exits `${STUB_EXIT:-0}`.
    - It appends `$*` to `$CALLS`.
  - **AC-1, Review Focus 3:** review_out = `🟢 [nit] pay.py:4 — style`. The appended
    lines equal exactly:
    ```
    🔴 [blocking] [codex] [both] Include the first item in the cart total — pay.py:3
       For any nonempty cart, `items[1:]` excludes the first item's price, undercounting the total whenever that price is nonzero. For example, `total([{"price": 10}])` now returns `0` instead of `10`. Sum all items to preserve the documented behavior.
    🟡 [important] [codex] Restore the zero floor for refund balances — pay.py:8
       When `amount` exceeds `balance`, the subtraction now returns a negative balance, violating the function's documented invariant. For example, `refund(15, 10)` returns `-5` instead of `0`. Restore the zero clamp.
    ```
    The state has `CROSS_REVIEW=ran`, `CROSS_REVIEW_COUNT=2` and `CROSS_REVIEW_BOTH=1`.
    `$CALLS` holds `review --base main -c model_reasoning_effort="high"`.
  - **AC-2:** same as AC-1, but the fixture uses `$(cd "$WT" && pwd -P)`. The paths are
    still `pay.py:3` and `pay.py:8`.
  - **AC-3:** the no-findings line → review_out unchanged, `CROSS_REVIEW=ran`,
    `CROSS_REVIEW_COUNT=0`.
  - **AC-4:** executor file `3` → `$CALLS` is empty, review_out unchanged,
    `CROSS_REVIEW=skipped`, output has `skipped — codex wrote this code`.
  - **AC-5,** three cases, each returning 0 with output containing
    `cross-review unavailable`, review_out unchanged and `CROSS_REVIEW=unavailable`:
    - PATH without `codex`;
    - `STUB_EXIT=1` with fixture output (Review Focus 4);
    - empty `STUB_OUT`.
  - **AC-6:** after AC-1, `code-review-parse.sh review_out` gives `BLOCKING_COUNT=1`.
  - **Review Focus 2:** a description line containing ` — x.py:9` and `[P1]` stays a
    description.
  - Run AC-1 under `zsh -c` too.
- [ ] **Run them and confirm they fail.**
- [ ] **Implement.**
  - Executor check first.
  - Then `command -v codex`.
  - Then, in the worktree: `codex review --base "$ORIG_BRANCH" -c 'model_reasoning_effort="high"' </dev/null >out 2>err`,
    prefixed by `timeout 600` when `command -v timeout`.
  - Non-zero exit or empty out → unavailable.
  - **Parse with awk.** Only lines after `Full review comments:` count. A header is
    `^- \[P[0-3]\] (title) — (path):(a)-(b)$`; following indented lines belong to it,
    until a blank line or the next header.
  - **Strip `<wt>/` and `<wt -P>/`** from the path.
  - **`[both]`:** any line already in review_out containing `<relpath>:<n>` with
    `a-3 ≤ n ≤ b+3`.
  - **Append** with `>>` and persist the state keys.
- [ ] **Run** `bats tests/test_ship-next-cross-review.bats`. All green.
- [ ] **Commit:** `feat(R-019): sn_cross_review — codex reviews Claude-written ships`

### Task 2: Phase 6 step, log row and summary
**Files:**
- `commands/ship-next.md` (Phase 6)
- `lib/ship-next.sh` (`sn_log`, `sn_summary`)
- the tests in `tests/test_ship-next-cross-review.bats`

- [ ] **Failing tests:**
  - **AC-7 (log row):** in a squash default row, with state
    `CROSS_REVIEW=ran CROSS_REVIEW_COUNT=2 CROSS_REVIEW_BOTH=1`, the row contains
    `xreview=2/1`. With `CROSS_REVIEW=skipped` it contains `xreview=skipped`. Reuse
    `tests/test_command-blocks.bats`'s `p9_log_block` pattern, or the R-021 door tests'
    log-row setup.
  - **AC-7 (summary):** `sn_summary` with `AUTO=1` has the exact summary line for each
    of `ran`, `skipped` and `unavailable`.
  - **AC-8:** Phase 6 has a line starting `1.3.`, and its block contains
    `sn_cross_review "$WORKTREE" "$REVIEW_OUT"`. The loop holds the comment
    `# Step 1.3 appends codex's cross-review to $REVIEW_OUT (Claude-written ships only).`
    before the first `code-review-parse.sh` line.
- [ ] **Run them and confirm they fail.**
- [ ] **Implement.**
  - **`sn_log`:** add `, xreview=…` after `door=…`.
  - **`sn_summary`:** add the line after the `• door:` line.
  - **ship-next.md:**
    - Add step `1.3. **Cross-model review (Claude-written ships)**` before step 1.4,
      with the prose "runs after code review writes `$REVIEW_OUT`, before the parse;
      every attempt".
    - Its bash block: `: "${ID:?}" "${attempt:?}" "${WORKTREE:?}"`; source
      `ship-next.sh`; `REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md`;
      `sn_cross_review "$WORKTREE" "$REVIEW_OUT"`.
    - Add the loop comment above.
- [ ] **Run** `bats tests/test_ship-next-cross-review.bats tests/test_ship-next-door.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats tests/test_block-endings.bats`. All green.
- [ ] **Commit:** `feat(R-019): Phase 6 step 1.3; xreview in log and summary`

### Task 3: Full suite
`cd claude-skills/ship-workflow && bats tests/` → only the known cwd-guard failure. Fix
any in-scope failure, and commit it as `fix(R-019): …`.

## Execution log

- Task 1: confirmed all 11 new tests fail before implementation, then pass; committed as `a705ca7`.
- Task 2: confirmed the seven new tests fail before implementation; all 100 prescribed scoped tests pass; committed as `50314e9`.
- Deviation: added explicit `|| return 1` to new `[[ ... ]]` test assertions — the full-suite hygiene guard identified assertions Bats could silently ignore; assertions were strengthened, not removed or loosened.
- Task 3 initial full suite: 718 tests, with the known pre-existing cwd-guard failure and the repaired assertion-hygiene failure.
- Task 3 verification after repair: all 19 cross-review/hygiene tests pass; full `bats tests/` completes with 717 passing and only the known pre-existing cwd-guard failure (test 198). No product fix was needed in Task 3.
