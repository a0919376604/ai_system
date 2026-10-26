# R-016 Spec review + grilling rounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:**
- Every ship-next Phase 6 review attempt runs a Spec review, a sub-agent that compares the diff with the spec, in parallel with code-review-skill.
- Its report is format-checked (failing closed), counted, logged and summarized.
- Phase 3 asks clarifying questions in grilling rounds.

**Architecture:**
- Two new functions in `lib/ship-next.sh`:
  - `sn_spec_review_render` renders the sub-agent's prompt.
  - `sn_spec_review_check` validates its report with awk.
- `code-review-parse.sh` gains one counter.
- `commands/ship-next.md` changes in two places:
  - Phase 6 wires the report into every place that reads the code review's report.
  - Phase 3's invocation context requires grilling rounds.
- Nothing outside this repo changes.

**Tech Stack:** bash and zsh (command blocks run in Claude Code's zsh, where `grep` is an ugrep wrapper), BSD awk on macOS, bats.

**Spec:** `docs/specs/R-016-add-spec-review-grilling.md`. Read it first. Its Design, Seams and §4 Acceptance sections are the contract.

## Global Constraints
- The exact strings below come from the spec. Use them verbatim:
  - the tags `[spec:missing]`, `[spec:wrong]`, `[spec:extra]`, `[ponytail:yagni]`
  - the detail-line prefix `Spec:`
  - the sentinel `No spec gaps.`
  - `SPEC_GAP_COUNT`, `SPEC_GAPS_FOUND`, `spec_gaps=`
  - `SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md`
  - `.ship/spec-review-prompt.md`
  - the summary line `• spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed`
  - the log text `brainstorm Q${N} auto-picked recommended answer`
- New lib functions must behave the same under bash and zsh.
  - Use awk or `command grep`, never bare `grep -v…q` (R-003: the ugrep wrapper's `grep -vq` exits 1 regardless).
  - In awk, match emoji with `index($0, "🔴") == 1` or string comparison, never a bracket expression like `/^[🔴]/`, which matches single bytes in BSD awk.
- `commands/*.md` must contain no `$0`–`$9` (`tests/test_no-positional-params.bats`). `${N}`, `${ID}` and the like are fine.
- No new dependencies. Do not edit superpowers, code-review-skill or anything outside this repo.
- Run tests scoped per task: `cd claude-skills/ship-workflow && bats tests/<file>.bats`. Only Task 6 runs the full suite. In a linked worktree, `cwd-guard: exits 0 when not in a git repo at all` fails; that failure is known and pre-existing.

## Review Focus
These are inputs a real Spec sub-agent will produce that the ACs don't name. Each line has a test in Task 2.
1. The sentinel with a trailing space or a CRLF line ending (`No spec gaps. \r`) should still be accepted.
2. A report with both a finding and `No spec gaps.` is contradictory and must be rejected.
3. A `**Severity:** blocking [spec:missing] …` bullet line, which is not our format, must be rejected: fail closed.
4. A multi-line spec quote (finding, then `Spec: "…"`, then a further indented continuation line) is accepted.
5. A blank line between a missing/wrong finding and its `Spec:` line is rejected. The quote must be in the finding's own indented block.

---

### Task 1: `code-review-parse.sh` counts spec gaps and ignores `Spec:` quotes

**Files:**
- Modify: `claude-skills/ship-workflow/lib/code-review-parse.sh`
- Test: `claude-skills/ship-workflow/tests/test_code-review-parse.bats` (append)

**Interfaces:**
- Produces: the stdout line `SPEC_GAP_COUNT=<n>`, printed after `PONYTAIL_COUNT=`. Phase 6 (Task 4) evals it.

- [x] **Step 1: Write the failing tests.** Append three tests to `test_code-review-parse.bats`, in the style of the existing `PONYTAIL_COUNT counts lines tagged [ponytail:<tag>]` test (it writes to `$BATS_TEST_TMPDIR`).
  - `SPEC_GAP_COUNT counts missing and wrong spec findings` (AC-6).
    - Input lines: `🔴 [blocking] [spec:missing] retry flag never read`, `   Spec: "AC-2 | retry=3 | …"`, `🟢 [nit] [spec:extra] [ponytail:yagni] verbose flag — a.sh:3`.
    - Assert `SPEC_GAP_COUNT=1`, `BLOCKING_COUNT=1`, `MINOR_COUNT=1` and `PONYTAIL_COUNT=1`.
  - `SPEC_GAP_COUNT is 0 for a code review without spec tags` (AC-7). Input: the three lines from the ponytail test. Assert `SPEC_GAP_COUNT=0`, `PONYTAIL_COUNT=2` and `MINOR_COUNT=2`.
  - `an indented Spec: quote adds to no counter` (AC-5b, parse half).
    - Input: the AC-6 lines, with the `Spec:` line changed to `   Spec: "tag it [pre-existing] or [ponytail:delete]; **Severity:** blocking"`.
    - Assert `PONYTAIL_COUNT=1`, `PRE_EXISTING_COUNT=0` and `BLOCKING_COUNT=1`.
- [x] **Step 2: Run them and confirm they fail.** Run `bats tests/test_code-review-parse.bats`. Expected: the 3 new tests fail (no `SPEC_GAP_COUNT` line; the quote is counted).
- [x] **Step 3: Implement.**
  - Drop indented `Spec:` lines (`^[[:space:]]+Spec:`) from both `$ALL` and `$FILE` before any counting. Do it in the `awk 1` / `grep -vE` pipeline that builds them.
  - Add `count_spec_gap()`: finding lines whose line-start severity matches the `count_security` pattern and that carry `[spec:missing]` or `[spec:wrong]`.
  - Print `SPEC_GAP_COUNT=${SPEC_GAP:-0}`, whitespace-stripped like the others.
  - Mention the counter in the header comment.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_code-review-parse.bats`: all tests pass, the old ones included.
- [x] **Step 5: Commit.** `git commit -m "feat(R-016): code-review-parse counts spec gaps, ignores Spec: quotes"`

### Task 2: `sn_spec_review_render` and `sn_spec_review_check`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`. Add both functions after `sn_mech_gates`.
- Test: `claude-skills/ship-workflow/tests/test_ship-next-lib.bats` (append; the setup gives `$WT` and `$SCRATCH`)

**Interfaces:**
- Consumes: `sn_state_load <worktree>` (existing). It must provide `ID`, `SLUG` and `ORIG_BRANCH`.
- Produces:
  - `sn_spec_review_render <worktree>`
    - Return 0: wrote `<worktree>/.ship/spec-review-prompt.md`.
    - Return 1: printed `spec review: no spec at <path>` to stderr and wrote nothing.
  - `sn_spec_review_check <report>`
    - Return 0: valid report.
    - Non-zero: invalid; prints `spec report: <reason>: <offending line>` to stderr.

- [x] **Step 1: Write the failing tests** (AC-1 to AC-5b plus the Review Focus).
  - Helper: a function that writes a state file. Call `sn_state_set "$WT" ID R-9`, `SLUG x` and `ORIG_BRANCH main`, then create `$WT/docs/specs/R-9-x.md`.
  - `spec review prompt names the spec, the diff and the format` (AC-1).
    - Run `bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_spec_review_render "$WT"'`. Assert status 0.
    - The prompt file contains each of: `docs/specs/R-9-x.md`, `git diff main...HEAD`, `[spec:missing]`, `[spec:wrong]`, `[spec:extra]`, `[ponytail:yagni]`, `Spec:` and `No spec gaps.`.
  - `spec review prompt refuses without a spec` (AC-2). With no spec file, the status is non-zero and the prompt file does not exist.
  - `spec check accepts a well-formed report` (AC-3).
  - `spec check accepts the no-gaps sentinel` (AC-4). Cover `No spec gaps.`, and `No spec gaps. ` with a trailing space and CRLF (Review Focus 1).
  - `spec check rejects malformed reports` (AC-5). Loop over these cases, each written to its own file, and assert non-zero for every one:
    - a missing file
    - an empty file
    - `Looks fine to me.`
    - `🟢 [nit] [spec:missing] X` followed by `   Spec: "a"`
    - `🔴 [blocking] [spec:wrong] X — a.sh:1` with no `Spec:` line
    - `🟢 [nit] [spec:extra] X — a.sh:1`
    - `🔴 [blocking] [spec:extra] [ponytail:yagni] X — a.sh:1`
    - `🔴 [blocking] [pre-existing] [spec:missing] X` followed by `   Spec: "a"`
    - `   🟢 [nit] [spec:missing] X`, indented
    - `- **Severity:** blocking [spec:missing] X` (Review Focus 3)
    - the AC-3 report plus a `No spec gaps.` line (Review Focus 2)
    - `🔴 [blocking] [spec:missing] X`, a blank line, then `   Spec: "a"` (Review Focus 5)
  - Run the AC-5 loop twice, under `bash -c` and `zsh -c`. For zsh, define `grep() { ugrep "$@"; }` only if `ugrep` exists; otherwise the zsh run alone is enough.
  - `spec check accepts a multi-line quote and a quote containing tags` (Review Focus 4, AC-5b check half). The finding is followed by `   Spec: "line one`, then `     line two [pre-existing] [ponytail:delete]"`. Status 0.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-next-lib.bats`: the new tests fail with "command not found".
- [x] **Step 3: Implement `sn_spec_review_render <worktree>`.**
  - Load the state, then check the spec file `"$1/docs/specs/${ID}-${SLUG}.md"`.
  - Write the prompt with a **quoted** heredoc, and put the spec path and the base branch in with `printf`, so nothing in the text is command-substituted.
  - The prompt says, in the spec's words (Design → Spec review):
    - the inputs;
    - which criteria to check;
    - the three finding forms with their severities, and the indented `Spec: "<quoted spec line>"` line under missing/wrong;
    - search the worktree before calling something missing;
    - never use `[pre-existing]`;
    - `No spec gaps.` when nothing is found;
    - write only the report, to the path you are given, and edit nothing else.
- [x] **Step 4: Implement `sn_spec_review_check <report>`** as one awk program. Strip a trailing CR and trailing whitespace from each line first. The rules:
  - **A blank line** closes the current finding's detail block.
  - **An indented line:**
    - Reject it if it comes before any finding.
    - Reject it if its first non-space text is 🔴, 🟡, 🟢, 🎉 or `[`.
    - If it starts with `Spec:`, mark the current finding as quoted.
  - **A non-indented line** is one of these:
    - exactly `No spec gaps.`;
    - a finding: it starts with a severity (🔴, 🟡, 🟢, `[blocking]`, `[important]`, `[major]`, `[minor]` or `[nit]`, optionally after one emoji and a space) and carries exactly one `[spec:missing|wrong|extra]` tag;
    - anything else, which is rejected.
  - **Blocking** means the line starts with 🔴 or `[blocking]`.
    - missing/wrong must be blocking and quoted (checked when the block closes).
    - extra must not be blocking and must carry `[ponytail:yagni]`.
    - Any `[pre-existing]` on a finding line is rejected.
  - **At end of file:**
    - close the last block;
    - reject if both findings and the sentinel are present;
    - reject if neither is present.
- [x] **Step 5: Run the tests and confirm they pass.** `bats tests/test_ship-next-lib.bats`: all tests pass.
- [x] **Step 6: Commit.** `git commit -m "feat(R-016): spec review prompt render + fail-closed report check"`

### Task 3: Phase 9 log row and summary carry the spec gap count

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`. In `sn_log`, the default `SHIP_LOG_ROW`; in `sn_summary`, the `SUMMARY` text.
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (append; use its repo setup and `p9_log_block`)

**Interfaces:**
- Consumes: `SPEC_GAPS_FOUND`, from `.ship/state.env` or its archive. Task 4 writes it.

- [x] **Step 1: Write the failing tests** (AC-8).
  - `ship-next P9 (squash): the log row carries spec_gaps`.
    - Squash mode, the default. `sn_state_set "$SCRATCH/wt" SPEC_GAPS_FOUND 2` on a worktree dir with `.ship/`.
    - Run `p9_log_block` with `WORKTREE="$SCRATCH/wt" ID=R-T16`.
    - Assert that `docs/learnings/_log.md` has a row containing `ponytail=0, spec_gaps=2`.
    - Mirror the existing squash P9 test at line ~292 for setup.
  - `ship-next P9: the auto summary reports the spec gaps`.
    - Same state. Run `sn_summary "$WORKTREE" "$ID"` with `AUTO=1`.
    - Assert the output contains `spec review: 2 gap(s) found on attempt 1, all closed`.
    - Clean up `/tmp/ship-R-T16-*` as the existing summary test does.
- [x] **Step 2: Run them and confirm they fail.** `bats tests/test_command-blocks.bats`: the 2 new tests fail.
- [x] **Step 3: Implement.**
  - In `sn_log`, insert `, spec_gaps=${SPEC_GAPS_FOUND:-0}` right after `ponytail=${PONYTAIL_COUNT:-0}`.
  - In `sn_summary`, add the line `• spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed` right after the `• security review:` line.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_command-blocks.bats tests/test_ponytail-integration.bats`: all pass.
- [x] **Step 5: Commit.** `git commit -m "feat(R-016): ship log row and summary carry spec_gaps"`

### Task 4: Phase 6 runs the Spec review every attempt

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`, the Phase 6 section only
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-security.bats`, lines that pin the old two-report strings (15, 61–64, 69)
- Create: `claude-skills/ship-workflow/tests/test_ship-next-spec-review.bats`
- Modify: `claude-skills/ship-workflow/README.md` (one paragraph under the Security review section) and the root `README.md` Phase 6 table row (line ~217)

**Interfaces:**
- Consumes:
  - `sn_spec_review_render`, `sn_spec_review_check` (Task 2)
  - `SPEC_GAP_COUNT` from `code-review-parse.sh` (Task 1)
  - `sn_state_set`
- Produces: `SPEC_GAPS_FOUND` in `.ship/state.env`, written once (Task 3 reads it).

- [x] **Step 1: Write the failing tests** in `test_ship-next-spec-review.bats`. Define `load helpers` and `p6() { awk '/^## Phase 6/,/^## Phase 7/' "$SHIP_SKILL_ROOT/commands/ship-next.md"; }`. AC-9:
  - **`a numbered step renders the prompt and checks the report`.**
    - Phase 6 has a step whose header matches `^1\.4\. \*\*Spec review`.
    - Its bash block contains `SPEC_OUT="/tmp/ship-next-spec-${ID}-${attempt}.md"`, `sn_spec_review_render` and `sn_spec_review_check "$SPEC_OUT"`.
  - **`the loop clears, parses and prints the spec report`.** `p6` contains each of:
    - `SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md`
    - `rm -f "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`
    - `code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT")`
    - `code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT")`
    - `pre_existing_drop "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`
  - **`step 4 files spec majors`.** The step-4 `MAJOR_LINES=` line contains `"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`.
  - **`SPEC_GAPS_FOUND is written once`.** Execute the real line instead of grepping it.
    - Extract the single `p6` line containing `SPEC_GAPS_FOUND="$SPEC_GAP_COUNT"`.
    - Run it in `bash -c` after `source ship-next.sh; WORKTREE=$WT; sn_state_load "$WT"; SPEC_GAP_COUNT=2`.
    - Then run it again in a fresh shell, with `SPEC_GAP_COUNT=0` and the state reloaded.
    - Assert that the state file still has `SPEC_GAPS_FOUND=2`.
  - **`the blocker print shows spec blockers`.** Copy the existing print test in `test_ship-next-security.bats`, adding a third file with `🔴 [blocking] [spec:missing] NEW-SPEC`. Assert that `NEW-SPEC` is printed.
- [x] **Step 2: Update the pinned strings in `test_ship-next-security.bats`.**
  - The `"$REVIEW_OUT" "$SEC_OUT"` pins become `"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"` for the post-security parse, the `rm -f` line and `MAJOR_LINES`.
  - The pre-security parse pin at line 63 becomes `code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT")`.
  - Keep each test's intent. Run `bats tests/test_ship-next-spec-review.bats tests/test_ship-next-security.bats` and confirm the new and updated tests fail.
- [x] **Step 3: Edit Phase 6 of `ship-next.md`.**
  - **New step `1.4. **Spec review (every attempt, in parallel with code review)**`**, before 1.5. Its bash block:
    - starts with `: "${ID:?ID is not set}" "${attempt:?attempt is not set}" "${WORKTREE:?WORKTREE is not set}"`;
    - sources `ship-next.sh`;
    - sets `SPEC_OUT="/tmp/ship-next-spec-${ID}-${attempt}.md"`;
    - runs `sn_spec_review_render "$WORKTREE" || exit 1`.
  - One prose line follows: give `.ship/spec-review-prompt.md` to a read-only sub-agent in the same message as the code review, with `$SPEC_OUT` as its output path.
  - A second bash block runs `sn_spec_review_check "$SPEC_OUT" || { echo "spec report malformed: re-run step 1.4 once; a second failure stops Phase 6" >&2; exit 3; }`.
  - **In the loop:**
    - add `SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md` after the `SEC_OUT=` line;
    - make the `rm -f` line remove all three reports;
    - after the code-review comment, add `# Step 1.4 runs the Spec review in parallel; it writes and checks $SPEC_OUT.`;
    - make the first parse `"$REVIEW_OUT" "$SPEC_OUT"`;
    - after its `eval`, add the write-once line `[ -n "${SPEC_GAPS_FOUND:-}" ] || { SPEC_GAPS_FOUND="$SPEC_GAP_COUNT"; sn_state_set "$WORKTREE" SPEC_GAPS_FOUND "$SPEC_GAPS_FOUND"; }`;
    - make the post-security parse `"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`;
    - make `pre_existing_drop` take all three files;
    - make the fix-plan comment say the fix-plan covers blocking findings from `$REVIEW_OUT`, `$SPEC_OUT` and `$SEC_OUT`.
  - **In step 4,** make `MAJOR_LINES` grep all three files.
- [x] **Step 4: Docs.**
  - `claude-skills/ship-workflow/README.md`: under "Security review (ship-next Phase 6)", add a short `Spec review` paragraph.
    - Content: every attempt also compares the diff with the spec; missing/wrong criteria block; extras are `[ponytail:yagni]`; the report is format-checked.
    - Include the source, Matt Pocock's two-axis `code-review`.
  - Root `README.md`, the Phase 6 row: add "Spec review（逐條對照 spec）" next to the security review.
- [x] **Step 5: Run the tests and confirm they pass.** `bats tests/test_ship-next-spec-review.bats tests/test_ship-next-security.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats`: all pass.
- [x] **Step 6: Commit.** `git commit -m "feat(R-016): Phase 6 runs the Spec review every attempt"`

### Task 5: Phase 3 asks in grilling rounds

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`. Change the `--auto:yes` line in `## Arguments`, and Phase 3 step 1.
- Create: `claude-skills/ship-workflow/tests/test_ship-next-grilling.bats`
- Modify: root `README.md`, the Phase 3 table row (line ~214)

- [x] **Step 1: Write the failing tests** (AC-10). `p3() { awk '/^## Phase 3/,/^## Phase 4/' "$CMD"; }`.
  - `Phase 3 requires grilling rounds`. `p3` contains `recommended answer`, `numbered` and `sub-agent`, and the text `"yes" accepts`.
  - `auto mode takes the recommended answer`. `p3` contains `auto-picked recommended answer`.
  - `option 1 is gone from Phase 3 and --auto:yes`.
    - `p3` does not contain `option 1`.
    - The `## Arguments` line that starts with `` - `--auto:yes` `` does not contain `option 1` and does contain `recommended answer`.
- [x] **Step 2: Run them and confirm they fail.** `bats tests/test_ship-next-grilling.bats`.
- [x] **Step 3: Edit.**
  - **Phase 3 step 1:** after the `## Decisions` requirement, add a `Require grilling rounds` paragraph that carries the spec's Design → Grilling rounds bullets. That covers:
    - each round asks every question whose prerequisites are settled, numbered, each with a recommended answer worded so "yes" accepts it;
    - a dependent question waits a round;
    - facts are found by a sub-agent, never asked;
    - this overrides the skill's one-question-per-message habit, and no superpowers file is modified.
  - **Auto-mode paragraph:** every question is auto-answered with its recommended answer. The log call becomes `auto-decision-log.sh "$WORKTREE" "P3" "brainstorm Q${N} auto-picked recommended answer" "<question → answer, truncated to 80 chars>"`.
  - **The `--auto:yes` argument line:** "brainstorm clarifying questions auto-pick their recommended answer".
  - **Root README Phase 3 row:** add 「問題一次問完、每題附建議答案」.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_ship-next-grilling.bats tests/test_no-positional-params.bats tests/test_ship-next-learnings.bats`: all pass.
- [x] **Step 5: Commit.** `git commit -m "feat(R-016): Phase 3 asks in grilling rounds"`

### Task 6: Full suite

- [x] **Step 1: Run.** `cd claude-skills/ship-workflow && bats tests/`. Expected: everything passes except `cwd-guard: exits 0 when not in a git repo at all`, which is known in a linked worktree (AC-11).
- [x] **Step 2: Fix what fails.** If any other test fails, fix it within this plan's scope. If it is unrelated and also fails on `main`, report it instead. Commit any fix with `fix(R-016): …`.

## Execution log

- Task 1: three new tests confirmed failing; all 29 parser tests pass.
- Task 2: six new tests confirmed failing; all 45 library tests pass, including bash/zsh report validation.
- Task 3: both new tests confirmed failing; all 63 command-block and ponytail integration tests pass.
- Deviation: Initialize the library and SPEC_OUT in step 1.4's check block — command blocks run in fresh shells; the prescribed block rejected a valid report with command not found. Added a bash/zsh regression test.
- Deviation: Update the security stale-report assertion to inspect two preceding lines and supply empty Spec reports to existing print/major tests — the third report adds an assignment and a required input; the original assertions remain intact.
- Task 4: new and updated wiring tests confirmed failing; all 70 scoped tests pass after the documented local repairs.
- Task 5: all three new tests confirmed failing; all 11 grilling, positional-parameter and learnings tests pass.
- Task 6: `cd claude-skills/ship-workflow && bats tests/` completed: 636 passed, 1 failed out of 637. The only failure is the explicitly exempted baseline `cwd-guard: exits 0 when not in a git repo at all`. No unrelated baseline fixes made.
- Final review: read-only reviewer found no implementation defect requiring repair and confirmed all five Review Focus cases. Plan-prescribed limitation retained: multiline Spec quote continuations can inflate unanchored tag counters; Task 1 explicitly filters only the initial indented Spec: line. This limitation is reported rather than changing the prescribed parser behavior.
- Final verification: `git diff HEAD~5..HEAD --check` passed. Five implementation commits were created in task order; branch remained `ship/R-016-add-spec-review-grilling`. No remote push or commit amendment.
