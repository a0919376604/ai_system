# R-017 Encode lessons as checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Rule lines record what enforces them.
- The executor reads only the judgment rules.
- A new `tdd_rules_prove` shows a check is red on the mistake and green on the fix.
- `/ship-compound` step 6b turns mechanical lessons into proven checks.

**Architecture:**
- All code goes in `claude-skills/ship-workflow/lib/tdd-rules.sh`:
  - one extended function: `tdd_rules_append`;
  - two filtered functions: `tdd_rules_render` and `tdd_rules_count`;
  - two new functions: `tdd_rules_table` and `tdd_rules_prove`.
- Prose changes: `commands/ship-compound.md` steps 4 and 6b, and `templates/repo/LEARNING.md`.

**Tech Stack:** bash and zsh (the lib is sourced from Claude Code's zsh, where `grep` is an ugrep wrapper), BSD awk, git worktrees, bats.

**Spec:** `docs/specs/R-017-encode-lessons-as-checks.md`. Read it first. Its Design, Seams and §4 Acceptance are the contract.

## Global Constraints
- Exact strings from the spec:
  - the marker ` · enforced by ` (space, U+00B7 middle dot, space)
  - the table header `| Rule | Enforced by | Source |`
  - the cell values `judgment` and `—`
  - the proof line `proof: red at <sha7> (exit <n>) · green at <sha7>`
  - the errors `check does not fail on the mistake` and `check fails on the fix`
  - the commit subject `lesson: ${ID} — <n> check(s), <m> judgment rule(s)`
  - the section `## Lessons → checks`
- Match rule text literally, never as a regex. Use awk `index()` or string equality, or `grep -F`. Rule text holds `[`, `*`, `&`, `/` and `.`.
- Where an exit status matters in lib code, use `command grep`, not `grep`. Under Claude Code's zsh, `grep -vq` exits 1 regardless.
- Use no shell glob that can match nothing (zsh aborts), and no `$0`–`$9` in `commands/*.md`.
- No new dependencies. Edit only this repo.
- Run tests scoped: `cd claude-skills/ship-workflow && bats tests/<file>.bats`. Only Task 5 runs the full suite. The known `cwd-guard: exits 0 when not in a git repo at all` failure in a linked worktree is pre-existing.

## Review Focus
These inputs are not named in the ACs but will occur. Each has a test in the owning task.
1. Rule text with regex and sed metacharacters, e.g. `Tag it [ponytail:yagni] & quote a/b.*`. In-place promotion must match it literally (Task 1).
2. An enforcer holding `|`, e.g. `tests/t.bats::a|b`. The table escapes it as `\|`, so the row keeps 3 cells (Task 2).
3. A judgment rule whose prose says "enforced by" without the middle-dot marker, e.g. `- Say who it is enforced by. ← R-5`. It stays judgment (Task 2).
4. A check path in a directory that does not exist at the red ref, e.g. `tests/new/check.sh`. `tdd_rules_prove` creates the parent directory (Task 3).
5. Uncommitted changes elsewhere in the working tree do not leak into the red run. Only the named paths are overlaid (Task 3).

---

### Task 1: `tdd_rules_append` records an enforcer and promotes in place

**Files:**
- Modify: `claude-skills/ship-workflow/lib/tdd-rules.sh` (`tdd_rules_append`)
- Test: `claude-skills/ship-workflow/tests/test_tdd-rules.bats` (append; reuse `setup` and `mkrules`)

**Interfaces:**
- Produces: `tdd_rules_append <R-NNN> <text> [<enforcer>]`. Returns 0, or 2 on a bad id or empty text.
- Produces: the constant `TDD_RULES_ENFORCED_MARK=' · enforced by '`, which Task 2 uses.

- [x] **Step 1: Write the failing tests.**
  - **`tdd_rules_append: an enforcer is recorded on the rule line` (AC-1).**
    - Call `tdd_rules_append R-9 "Quote X." "tests/t.bats::quotes"` twice.
    - `grep -qxF -- '- Quote X. ← R-9 · enforced by tests/t.bats::quotes' docs/tdd-rules.d/R-9.md`.
    - The file has exactly 1 line.
  - **`tdd_rules_append: an enforcer promotes an existing judgment rule in place` (AC-1b).**
    - `mkdir -p docs/tdd-rules.d; printf '%s\n' '- Quote X. ← R-3' > docs/tdd-rules.d/R-3.md`.
    - Call `tdd_rules_append R-9 "Quote X." "tests/t.bats::quotes"` twice.
    - `R-3.md` is exactly `- Quote X. ← R-3 · enforced by tests/t.bats::quotes`.
    - `docs/tdd-rules.d/R-9.md` does not exist.
  - **`tdd_rules_append: promotion matches rule text literally` (Review Focus 1).**
    - `R-3.md` holds `- Tag it [ponytail:yagni] & quote a/b.* ← R-3` and `- Tag it X ← R-3`.
    - Promote the first with enforcer `e1`.
    - Only the first line gains ` · enforced by e1`, and the text is unchanged byte for byte.
  - **`tdd_rules_append: promotes a legacy-file rule in place`.** `mkrules '- Old rule. ← R-001'`, then append with enforcer `e2`. `docs/tdd-rules.md` is now `- Old rule. ← R-001 · enforced by e2`.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_tdd-rules.bats`: the 4 new tests fail; the existing ones pass.
- [x] **Step 3: Implement.**
  - Without an enforcer, behaviour is unchanged.
  - With one:
    - If an existing bullet's text equals `<text>` (the part between `- ` and ` ← `, compared literally) and has no marker: rewrite that line in its file to append the marker plus the enforcer. Use awk with string equality, write to a temp file, then `mv`.
    - If such a bullet already has a marker: leave it.
    - Otherwise: append `- <text> ← <id> · enforced by <enforcer>` to this ship's fragment.
  - Update the function's header comment.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_tdd-rules.bats`: all pass.
- [x] **Step 5: Commit.** `git commit -m "feat(R-017): tdd_rules_append records enforcers, promotes in place"`

### Task 2: the executor reads judgment rules; `tdd_rules_table`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/tdd-rules.sh`. In `tdd_rules_render` and `tdd_rules_count`, filter on `TDD_RULES_ENFORCED_MARK`. Add `tdd_rules_table`.
- Test: `claude-skills/ship-workflow/tests/test_tdd-rules.bats` (append)

**Interfaces:**
- Consumes: `TDD_RULES_ENFORCED_MARK` and `tdd_rules_bullets` (existing).
- Produces: `tdd_rules_table`, which prints a markdown table on stdout, or nothing.

- [x] **Step 1: Write the failing tests.**
  - **`render and count skip enforced rules` (AC-2).**
    - Fragments: `R-1.md` = `- Judge me. ← R-1`; `R-2.md` = `- Checked. ← R-2 · enforced by tests/a.bats::x`.
    - `tdd_rules_render R-9 /dev/null` contains `- Judge me. ← R-1` and not `Checked.`.
    - `tdd_rules_count` is `1`.
  - **`tdd_rules_table lists every rule with its enforcer` (AC-3).**
    - Add `mkrules '- Legacy rule.'` to the AC-2 fragments.
    - The output's line 1 is `| Rule | Enforced by | Source |`.
    - Line 2 is a separator row.
    - Then, in this order:
      - `| Legacy rule. | judgment | — |`
      - `| Judge me. | judgment | R-1 |`
      - `| Checked. | tests/a.bats::x | R-2 |`
  - **`tdd_rules_table prints nothing without rules`.** The output is empty.
  - **`a pipe in an enforcer is escaped` (Review Focus 2).** With enforcer `tests/t.bats::a|b`, the row's enforcer cell is `tests/t.bats::a\|b`.
  - **`prose saying enforced by stays judgment` (Review Focus 3).** `- Say who it is enforced by. ← R-5` is counted, and is shown as `judgment` in the table.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_tdd-rules.bats`.
- [x] **Step 3: Implement.**
  - **Filtering:** a bullet is enforced iff it contains `TDD_RULES_ENFORCED_MARK`, matched with `command grep -F` or awk `index`. `tdd_rules_render`'s learned section and `tdd_rules_count` keep only non-enforced bullets.
  - **`tdd_rules_table` row values:**
    - text: strip the leading `- `, then everything from ` ← `;
    - source: after `← `, up to the marker or the end of line; `—` when there is no `←`;
    - enforcer: after the marker, or `judgment`.
  - **`tdd_rules_table` formatting:** escape `|` in cells as `\|`. Print nothing when `tdd_rules_bullets` is empty.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_tdd-rules.bats tests/test_ship-next-tdd-rules.bats`: all pass, the existing render and count tests included.
- [x] **Step 5: Commit.** `git commit -m "feat(R-017): executor reads judgment rules; tdd_rules_table"`

### Task 3: `tdd_rules_prove`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/tdd-rules.sh` (add `tdd_rules_prove`)
- Create: `claude-skills/ship-workflow/tests/test_tdd-rules-prove.bats`

**Interfaces:**
- Produces: `tdd_rules_prove <red-ref> <check-command> <check-path>...`, run from the repo root.
  - Exit 0 and the proof line on stdout, then the red run's last 3 output lines, each indented 2 spaces.
  - Non-zero with a reason on stderr otherwise.

- [x] **Step 1: Write the failing tests.**
  - **Setup:** `load helpers`.
    - A scratch repo with commit A: `f.sh` = `echo bad`. Commit B: `f.sh` = `echo good`.
    - `export A B` (full SHAs). Source `$SHIP_LIB/tdd-rules.sh`.
    - Write an uncommitted `check.sh` = `[ "$(sh f.sh)" = good ]`.
    - Keep `before=$(git worktree list | wc -l)` for the leak checks.
  - **`proof: red on the mistake, green on the fix` (AC-4).**
    - `run tdd_rules_prove "$A" "sh check.sh" check.sh`. Status 0.
    - Line 1 is `proof: red at ${A:0:7} (exit 1) · green at ${B:0:7}`.
  - **`a check that passes on the mistake is refused` (AC-5).** `check.sh` = `true`. Non-zero; the output contains `check does not fail on the mistake`.
  - **`a check that fails on the fix is refused` (AC-6).** `check.sh` = `false`. Non-zero; the output contains `check fails on the fix`.
  - **`bad input gives usage and no worktree is left` (AC-7).**
    - Run with `no-such-ref`, then with no path.
    - Both are non-zero with output containing `usage`.
    - After every test in this file, `git worktree list | wc -l` equals `before`. Assert it in each test.
  - **`a check path in a new directory works` (Review Focus 4).** Use `tests/new/check.sh`. Status 0.
  - **`only the named paths reach the red run` (Review Focus 5).**
    - Modify `f.sh` in the working tree to `echo good` without committing, with HEAD at A.
    - `tdd_rules_prove "$A" "sh check.sh" check.sh` must report red, i.e. status 0, because the red run uses A's `f.sh`.
  - **`zsh gives the same result` (AC-8).** The AC-4 case, run via `zsh -c 'source "$SHIP_LIB/tdd-rules.sh"; tdd_rules_prove "$A" "sh check.sh" check.sh'`. Status 0.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_tdd-rules-prove.bats`.
- [x] **Step 3: Implement.**
  - **Validate:** `git rev-parse --verify --quiet "<red-ref>^{commit}"` must succeed, and at least one path must be given. Otherwise print a `usage: tdd_rules_prove <red-ref> <check-command> <check-path>...` line and return 2.
  - **Red run:**
    - `tmp=$(mktemp -d "${TMPDIR:-/tmp}/tdd-prove.XXXXXX")`, then `git worktree add --detach -q "$tmp/wt" "<red-ref>"`.
    - For each path: `mkdir -p` its parent under `$tmp/wt`, then `cp` it from the working tree.
    - Run `(cd "$tmp/wt" && bash -c "<cmd>") >"$tmp/red.out" 2>&1` and capture the exit code.
  - **Cleanup:** `git worktree remove --force "$tmp/wt"` and `rm -rf "$tmp"` on every path. A subshell or explicit calls both work; never leave the worktree registered.
  - **Results:**
    - Red exit 0 → `check does not fail on the mistake`, non-zero.
    - Otherwise run `bash -c "<cmd>"` in the cwd. A non-zero exit → `check fails on the fix`, non-zero.
    - Otherwise print the proof line using `git rev-parse --short=7`, then `tail -3 "$tmp/red.out" | sed 's/^/  /'`.
  - Add a `# ponytail:` comment naming the ceiling: an environmental red, such as a missing dependency in the bare worktree, looks like a red. The tail shown is the guard.
- [x] **Step 4: Run the tests and confirm they pass.** `bats tests/test_tdd-rules-prove.bats tests/test_tdd-rules.bats`.
- [x] **Step 5: Commit.** `git commit -m "feat(R-017): tdd_rules_prove — red on the mistake, green on the fix"`

### Task 4: compound step 6b promotes lessons into checks

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md`. Add the section to step 4's list, and replace step 6b's heading and body.
- Modify: `claude-skills/ship-workflow/templates/repo/LEARNING.md`. Add `## Lessons → checks` after `## Bugs`.
- Create: `claude-skills/ship-workflow/tests/test_ship-compound-lessons.bats`

**Interfaces:**
- Consumes: `tdd_rules_prove`, three-argument `tdd_rules_append`, `tdd_rules_table` (Tasks 1–3); `tdd_rules_over_cap`, `tdd_rules_unsourced` (existing).

- [x] **Step 1: Write the failing tests** (AC-9, AC-10).
  - `s6b() { awk '/^6b\./,/^7\./' "$SHIP_SKILL_ROOT/commands/ship-compound.md"; }`
  - **`step 6b turns mechanical lessons into proven checks`.** `s6b` contains each of: `tdd_rules_prove`, `tdd_rules_table`, `enforced`, `judgment`, `lesson: ${ID}`, and a line matching `tdd_rules_append "\$ID" "[^"]*" "[^"]*"`.
  - **`step 6b checks the over-cap and unsourced warnings still run`.** It contains `tdd_rules_over_cap` and `tdd_rules_unsourced`.
  - **`step 6b's bash block runs under bash and zsh`.**
    - Extract step 6b's bash fences with the `block`-style awk from `test_command-blocks.bats`. Drop comment lines.
    - Run them in a scratch git repo with `ID=R-9` and `SHIP_LIB`'s path substituted, under `bash` and `zsh`.
    - Status 0, and the output contains no `command not found`.
  - **`the learning template and step 4 name Lessons → checks`.**
    - `templates/repo/LEARNING.md` has the line `## Lessons → checks`.
    - Step 4's list (`awk '/^4\./,/^5\./'`) contains `Lessons → checks`.
- [x] **Step 2: Run the tests and confirm they fail.** `bats tests/test_ship-compound-lessons.bats`.
- [x] **Step 3: Edit step 6b.**
  - Heading: `6b. **Promote lessons into checks.**`
  - The body says, in the spec's Design → "Compound step 6b" order:
    - **Candidates:** blocking/major findings from `/tmp/ship-next-{review,spec,security}-${ID}-*.md` when present, plus the learning's Bugs. Recurring classes only.
    - **The mechanical/judgment split**, with the repeat-promotion rule.
    - **Levels:** architecture first, then a check in this repo (test or lint), with a failure message naming the fix. An `sn_mech_gates` gate only when the repo is ai_system, proven through its bats test.
    - **Prove, then record:** prove with `tdd_rules_prove`; record with `tdd_rules_append "$ID" "<rule>" "<check>"`. A failed proof becomes a judgment rule; in auto mode, log `auto-decision-log.sh "$WORKTREE" "P8" "lesson kept as judgment — proof failed" "<rule>"`.
    - **Judgment rules:** `tdd_rules_append "$ID" "<rule>"`.
  - **Bash block, runnable as is** (lesson calls stay as commented examples):
    - `source ~/.claude/skills/ship-workflow/lib/tdd-rules.sh`
    - the commented example calls
    - the existing over-cap and unsourced warnings
    - `tdd_rules_table`
  - **Commit block:**
    - `git add -- <check files> docs/tdd-rules.d`, plus `docs/tdd-rules.md` when it changed, guarded so an absent path is skipped.
    - `git diff --cached --quiet || git commit -m "lesson: ${ID} — <n> check(s), <m> judgment rule(s)"`.
  - **One closing line:** the learning's `## Lessons → checks` gets one line per lesson, `- <rule> — enforced by <check> · proof: <proof line>` or `- <rule> — judgment`.
- [x] **Step 4: Add `Lessons → checks` to step 4's section list and the template.**
  - In step 4's list, it goes after "Bugs".
  - In the template, add `## Lessons → checks` with a one-line `>` hint: "Each lesson: the check that enforces it, with its proof, or `judgment`."
- [x] **Step 5: Run the tests and confirm they pass.** `bats tests/test_ship-compound-lessons.bats tests/test_ship-compound-single-path.bats tests/test_ship-compound-context.bats tests/test_no-positional-params.bats`.
- [x] **Step 6: Commit.** `git commit -m "feat(R-017): compound step 6b promotes lessons into proven checks"`

### Task 5: Full suite

- [x] **Step 1: Run.** `cd claude-skills/ship-workflow && bats tests/`. Expected: all pass except the known `cwd-guard: exits 0 when not in a git repo at all` (AC-11).
- [x] **Step 2: Fix what fails.** Fix any other failure within this plan's scope. A failure that is unrelated and also fails on `main` is reported, not fixed. Commit any fix as `fix(R-017): …`.

## Execution log

- Task 1: four new tests failed, then all 20 passed. Enforcer recording and literal in-place promotion implemented.
- Task 2: five new tests failed, then all 30 scoped tests passed. Judgment filtering and escaped table output implemented.
- Task 3: seven proof tests failed, then all 32 scoped tests passed, including zsh and worktree leak assertions.
- Task 4: three new tests failed and the existing-warning assertion passed before implementation; all 15 scoped tests passed afterward.
- Deviation: replaced the unsourced-warning trailing AND-list with an if block — the prescribed runnable block otherwise returned failure when there were no unsourced rules; warnings are preserved.
- Task 5 initial suite: 658 tests; known cwd-guard failure plus the new table separator assertion failed suite hygiene.
- Deviation: added an explicit failure return to the table separator assertion — the suite hygiene guard requires non-final double-bracket assertions to propagate failure; no assertion was loosened.
- Deviation: strip the enforcement marker before literal comparison for unsourced legacy rules — final review found repeated promotion created a duplicate fragment. Added a regression test and confirmed it failed before the local fix.
- Task 5 final verification: bats tests/ ran 659 tests: 658 passed; only the explicitly allowed pre-existing cwd-guard linked-worktree failure remains. Scoped repair verification: all 27 tests passed.
- Final review: one idempotence issue repaired with a red-to-green regression; no other findings. git diff --check passed. Stayed on ship/R-017-encode-lessons-as-checks; no remote push or commit amendment.
