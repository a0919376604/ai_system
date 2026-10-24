# R-007 review fix 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** clear the review-attempt-1 blocker and the run-plan instance of the same defect.
**Spec:** `docs/specs/R-007-strip-positional-params.md`

## Global Constraints
- Edit files in THIS worktree only (not ~/.claude). No `$` immediately followed by a digit may remain in `claude-skills/ship-workflow/commands/*.md` or `claude-skills/*/SKILL.md`.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all` (linked worktree). Ignore it.

---

### Task 1: ship-init takes the first non-flag argument; run-plan uses no positionals; prose fixes

**Files:** `claude-skills/ship-workflow/commands/ship-init.md`, `claude-skills/run-plan/SKILL.md`, `claude-skills/ship-workflow/commands/ship-next.md`, `claude-skills/ship-workflow/tests/test_no-positional-params.bats`, `claude-skills/ship-workflow/tests/test_command-blocks.bats`

- [x] **Step 1: failing tests**
  - In `tests/test_no-positional-params.bats`, add `@test "no skill file contains a positional parameter"`: `run grep -nE '\$[0-9]' "$SHIP_SKILL_ROOT"/../*/SKILL.md`; `[ "$status" -eq 1 ] || { echo "$output"; return 1; }`.
  - In `tests/test_command-blocks.bats`, add `@test "ship-init step 1 ignores flags when picking the target"`: extract the step-1 bash block of `ship-init.md` with the file's existing `block` helper (start anchor `^1\. \*\*Resolve target directory`, end anchor `^2\. `), keep only the lines up to and including the line that sets `ARG` (cut the block after the first line matching `^ *ARG=`), then run it as `bash -c "ARGUMENTS='--upgrade'; $(cat that file); printf '%s' \"\$ARG\""` — hmm: simpler and exact: write the extracted lines to `$SCRATCH/s1.sh`, prepend the line `ARGUMENTS='--upgrade /tmp/x'` with `sed`, append `printf '%s' "$ARG"`, run `bash $SCRATCH/s1.sh` and assert output is `/tmp/x`; repeat with `ARGUMENTS='--upgrade'` → empty output.
    (The command loader substitutes `$ARGUMENTS` with the literal text, so emulating it as a shell variable assignment is equivalent for unquoted word splitting.)
- [x] **Step 2:** run both files → the two new tests FAIL.
- [x] **Step 3: edits**
  - ship-init step 1: replace `ARG="$ARGUMENTS"   # may be empty, a bare word, or an absolute path` with:
    ```bash
    # The first argument that is not a --flag: empty, a bare word, or an absolute path.
    ARG=""; for A in $ARGUMENTS; do case "$A" in --*) ;; *) ARG="$A"; break ;; esac; done
    ```
  - run-plan/SKILL.md:
    - `resolve_slot()`: `local ARG="$1"` → `local ARG=""; for ARG in "$@"; do break; done`
    - Step 1 `PLAN_ARG="$1"` → `read -r PLAN_ARG _ <<< "$ARGUMENTS"   # first token; Claude Code substitutes ARGUMENTS`
    - Step 5 `ARG="$1"` → `read -r _SUB ARG _ <<< "$ARGUMENTS"   # token after "status"`
    - Step 6 `ARG="$1"` → `read -r _SUB ARG _ <<< "$ARGUMENTS"   # token after "kill"`
    - `do_kill()`: `local SLOT="$1"` → `local SLOT=""; for SLOT in "$@"; do break; done`
    - Any other `$<digit>` the new skill-file test reports: same treatment (function arg → the `for … in "$@"; do break; done` form; top-level → `read -r … <<< "$ARGUMENTS"`).
  - ship-next Phase 1 step 0 prose: replace the sentence `Set \`AUTO=1\` for \`--auto:yes\` or \`--auto\`.` with `\`--auto:yes\` or \`--auto\` anywhere in the arguments sets \`AUTO=1\`.` and replace `(an adhoc description runs to the end of the arguments)` with `(an adhoc description runs to the end of the arguments, minus a trailing \`--auto\` / \`--auto:yes\`)`; and replace `Then run:` with `Write the values you parsed as assignments at the top of this block, then run it:`.
- [x] **Step 4:** `cd claude-skills/ship-workflow && bats tests/` → green except the known cwd-guard failure; `grep -nE '\$[0-9]' claude-skills/ship-workflow/commands/*.md claude-skills/*/SKILL.md` prints nothing.
- [x] **Step 5:** commit `fix(R-007): ship-init skips flags; run-plan has no positional params — review attempt 2`

## Execution log

- Task 1: implemented the prescribed changes without deviations.
- RED: `bats tests/test_no-positional-params.bats tests/test_command-blocks.bats` — 33 passed; both new tests failed as expected before implementation.
- GREEN: `cd claude-skills/ship-workflow && bats tests/` — 645 passed; only the documented pre-existing `cwd-guard: exits 0 when not in a git repo at all` failed (646 total).
- Positional-parameter grep over commands and skill files printed nothing (exit 1); `git diff --check` passed.
- Independent read-only review found no concrete bugs or departures from the plan.
- Task 1 changes committed with the prescribed message; no remote push.
