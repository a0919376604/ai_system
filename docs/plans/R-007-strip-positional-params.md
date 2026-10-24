# R-007 strip-positional-params Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** no `$<digit>` in `claude-skills/ship-workflow/commands/*.md`; the snippets that needed them live in lib functions with tests.

**Architecture:** four small lib functions + call-site edits in three command files + one regression test. Libs under `claude-skills/ship-workflow/lib/` are sourced at runtime and are never argument-substituted, so awk fields are fine there.

**Tech Stack:** bash, awk, git, bats (`cd claude-skills/ship-workflow && bats tests/`).

**Spec:** `docs/specs/R-007-strip-positional-params.md`

## Global Constraints
- Edit files in THIS worktree only. `~/.claude/skills/ship-workflow` is a symlink to a different checkout — never edit through it.
- After this ship, `grep -nE '\$[0-9]' claude-skills/ship-workflow/commands/*.md` prints nothing — prose included.
- Known pre-existing failure: `cwd-guard: exits 0 when not in a git repo at all` fails in a linked worktree. Ignore it.

## Review Focus
- `learnings_terms` keeps slug order and drops stopwords only as whole words.
- ship-land step 5 must still never resolve to the main checkout (existing guard stays).
- `tb_ship_lines` output is `"<test> <src>"`; the split must not use positionals.

---

### Task 1: lib functions with unit tests

**Files:**
- Modify: `claude-skills/ship-workflow/lib/learnings-lookup.sh`, `lib/test-budget.sh`, `lib/pre-existing.sh`, `lib/ship-land.sh`
- Test: `tests/test_learnings-lookup.bats`, `tests/test_test-budget.bats`, `tests/test_pre-existing.bats`, `tests/test_ship-land-lib.bats` (append; follow each file's existing setup/helpers)

- [x] **Step 1: failing tests** (one `@test` per AC, names as below)
  - `learnings_terms: keeps words of 4+ chars minus stopwords, in slug order` — `run learnings_terms show-churn-warning-in-chat`; `[ "$output" = "$(printf 'churn\nwarning\nchat')" ]`.
  - `tb_test_lines_added: sums added lines in test paths of one commit` — scratch repo; one commit adding 3 lines to `tests/a.bats` and 5 to `src/a.sh`; `[ "$(tb_test_lines_added HEAD)" = 3 ]`; a commit touching no test path → `0`.
  - `pre_existing_drop: removes pre-existing findings and their detail lines` — file with lines `🟡 [important] [pre-existing] a.sh:1 — old`, `   Base evidence: a.sh:1 exists unchanged on main`, `🔴 [blocking] b.sh:2 — new`, `   detail of new`; output contains `b.sh:2` and `detail of new`, not `a.sh:1` nor `Base evidence`.
  - `land_worktree_for_branch: finds the worktree of a branch` — scratch repo + `git worktree add -b ship/R-1-x <path>`; output equals `<path>` (compare with `cd <path> && pwd -P` form git prints); unknown branch → empty output, exit 0.
- [x] **Step 2:** run the four files with `bats` → the new tests FAIL (functions missing).
- [x] **Step 3: implement**
  - `learnings_terms() { printf '%s' "$1" | tr '-' '\n' | awk 'length($0) >= 4' | grep -vxE 'fix|add|update|remove|improve|unify|polish|show|make|into' || true; }`
  - `tb_test_lines_added() { git diff --numstat "$1^" "$1" -- '*test*' 'tests/' 2>/dev/null | awk '{s+=$1} END {print s+0}'; }`
  - `pre_existing_drop() { PE="$PRE_EXISTING_RE" awk '$0 ~ ENVIRON["PE"] {skip=1; next} skip && /^[[:space:]]+[^[:space:]]/ {next} {skip=0; print}' "$@"; }`
  - `land_worktree_for_branch() { git worktree list --porcelain | awk -v b="refs/heads/$1" '/^worktree /{w=substr($0,10)} /^branch /{if ($2==b) print w}'; }` (substr keeps paths with spaces whole)
  - One header comment line each, matching the file's style.
- [x] **Step 4:** the four test files pass.
- [x] **Step 5:** commit `feat(R-007): lib helpers for the snippets that used positional params — Task 1`

### Task 2: call sites + regression test

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`, `commands/ship-land.md`, `commands/ship-init.md`
- Create: `claude-skills/ship-workflow/tests/test_no-positional-params.bats`

- [x] **Step 1: failing test** `tests/test_no-positional-params.bats`:
  ```bash
  #!/usr/bin/env bats
  load helpers
  # Claude Code replaces $0..$9 in a command file with the invocation's arguments
  # before the agent reads it (R-007). Shell/awk positionals belong in lib/.
  @test "no command file contains a positional parameter" {
    run grep -nE '\$[0-9]' "$SHIP_SKILL_ROOT"/commands/*.md
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  }
  ```
- [x] **Step 2:** run it → FAIL listing the 11 lines.
- [x] **Step 3: edit call sites**
  - ship-next Phase 1 step 0: replace the bash block from `# Initialize flag state` through the end of the `while … done` loop with prose (keep the mutex / required-arg / auto echo bash that follows, unchanged):
    > Parse the arguments yourself — they arrive as text, not as shell positionals. Set `AUTO=1` for `--auto:yes` or `--auto`. `--discard <R-NNN>`, `--adhoc <description>` and `--resume <R-NNN>` set `MODE` to discard / adhoc / resume and `TARGET` to the value after the flag (an adhoc description runs to the end of the arguments). Any other `--flag` is an error (exit 2). The first bare token is `POSITIONAL` (an R-NNN). Then run:
    and start that bash block with `AUTO=${AUTO:-0}; MODE=${MODE:-}; TARGET=${TARGET:-}; POSITIONAL=${POSITIONAL:-}` followed by the existing `# Mutex:` lines.
  - ship-next Phase 1 step 4 "Critical" line: replace ``never assign `ID="$1"` directly`` with ``never take `ID` from the first raw argument``.
  - ship-next Phase 3 learnings block: replace the three-line `LEARN_TERMS=$(printf … || true)` assignment (and its two comment lines above) with `LEARN_TERMS=$(learnings_terms "$SLUG")   # words of 4+ chars minus generic verbs`.
  - ship-next Phase 6 step 0.5 (a): replace the two-line `ADDED=$(git diff --numstat … | awk '{s+=$1} …')` with `ADDED=$(tb_test_lines_added "$sha")`.
  - ship-next Phase 6 step 0.5 (b): replace `set -- $(tb_ship_lines "$ORIG_BRANCH" HEAD)` and `TEST_LINES_ADDED="$1"; SRC_LINES_ADDED="$2"` with:
    ```bash
    TB_LINES=$(tb_ship_lines "$ORIG_BRANCH" HEAD)
    TEST_LINES_ADDED=${TB_LINES% *}; SRC_LINES_ADDED=${TB_LINES#* }
    ```
  - ship-next Phase 6 loop (interactive blocker print): replace the `PE="$PRE_EXISTING_RE" awk '…' "$REVIEW_OUT" "$SEC_OUT" \` line (and the two comment lines above it) with `pre_existing_drop "$REVIEW_OUT" "$SEC_OUT" \` keeping the following `| grep -B1 -A3 …` line.
  - ship-land step 1: `ID="$1"` → `ID="$ARGUMENTS"   # the R-NNN argument; Claude Code substitutes it`.
  - ship-land step 5: replace the two-line `WORKTREE=$(git worktree list --porcelain | awk …)` with `WORKTREE=$(land_worktree_for_branch "$BRANCH")`; if that bash block does not already `source ~/.claude/skills/ship-workflow/lib/ship-land.sh`, add it at the block's top (blocks do not share a shell; `tests/test_command-blocks.bats` checks this).
  - ship-init step 1: `ARG="$1"   # may be empty…` → `ARG="$ARGUMENTS"   # may be empty, a bare word, or an absolute path`.
- [x] **Step 4:** `cd claude-skills/ship-workflow && bats tests/` → all green except the known cwd-guard failure; `grep -nE '\$[0-9]' commands/*.md` prints nothing.
- [x] **Step 5:** commit `fix(R-007): no positional params in command files — Task 2`

## Execution log

- Task 1: all four new tests failed for missing helpers; after implementation, all 51 tests in the four prescribed files passed.
- Task 2: regression test failed on exactly 11 lines before edits. Full `bats tests/`: 643 passed, only the documented linked-worktree cwd-guard baseline failed. Positional-parameter grep returned no matches (exit 1).
- Final review: independent read-only review found no material issues; `git diff --check` passed. No plan deviations.
