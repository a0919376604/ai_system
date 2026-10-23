---
date: 2026-10-23
updated: 2026-10-23
type: learning
id: R-003
tags: [learning, ai_system, ship-workflow, security-review, prompt-injection, pre-existing, codex]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-003
shipped: true
shipped-date: 2026-10-23
---

## For future Claude
> R-003 adds a separate security pass to ship-next Phase 6 and a `[pre-existing]`
> finding class, following Anthropic's own code-review pipeline.
>
> The headline lesson: **the environment that runs a command block is not the one
> that tests it.** Claude Code runs blocks in zsh, where `grep` is a shell function
> wrapping an embedded ugrep, and `grep -vq` exits 1 even when a line fails to match.
> bats runs bash. The security gate's format check passed every test and never fired
> in production. It was found only because round 2's reviewer was told to verify in
> both shells.

## What Shipped
- **Security pass** (`lib/security-review.sh`, `templates/security-review/`): a
  vendored copy of Anthropic's MIT `/security-review` prompt @ `0c6a49f1fa56`, with
  changes C1–C5.
  - It diffs `${ORIG_BRANCH}...HEAD` and writes ship-next's severity line format.
  - It drops exclusion 14 and adds an LLM / AI input-safety category. The trigger
    was the operator's worry about LINE end-users steering the bot.
  - Its false-positive filter sub-tasks also see that category.
  - It may tag pre-existing issues.
  - Config (`security_review: off`, `docs/SECURITY_REVIEW.md`) is read from the
    base branch, so a ship cannot relax its own review.
- **It never fails open:**
  - stale reports are removed first (both reports, every attempt);
  - a missing lib halts instead of reading as "off";
  - a failed parse stops the gate;
  - `security_review_output_check` rejects any line that is not a finding, an
    indented detail line carrying no severity, or a blank line.
- **`[pre-existing]`** counts only in its anchored position (`PRE_EXISTING_RE`).
  - Step 1.6 drops the tag mechanically when the cited file is absent on the base.
  - These findings never block.
  - Step 4.5 files each one once, keyed by `(pre-existing-key: <key>)`.
- `code-review-parse.sh` takes several files (joined with `awk 1`) and no longer
  prints `00`.
- The landed commit and the auto summary say `off` when the review did not run.

## What Changed From Plan
- The operator first worried about deploy/crash risk, then chose injection. That
  became the C3 category, and crash risk became a non-goal.
- Review took 3 rounds:
  - round 1: 2 blocking + 6 important + 7 nits;
  - round 2: 1 blocking + 4 important + 3 nits;
  - round 3: 0 blocking. Its 2 importants and 3 nits were fixed inline after the gate.
- Every round-1 and round-2 fix plan was generated from a prototype as `git apply`
  patches and replayed red/green before codex ran. Both codex runs finished DONE
  with zero deviations.
- The security finder found no candidates at confidence ≥ 7 in all three rounds, so
  no filter sub-tasks were needed.

## Bugs
- **Claude Code's grep wrapper.** `grep -vq` under the ugrep wrapper exits 1 whether
  or not a line fails to match.
  - The strict output check (`grep -vqE … && return 3`) was therefore a no-op where
    step 1.6 actually runs. A bulleted HIGH next to a good nit passed, and parsed as
    `BLOCKING_COUNT=0`.
  - Fix: `command grep`. The test emulates the wrapper with a `grep` function.
  - Other flags probed (`-c`, `-q`, `-v`, `-oE`, `-h`, `-rqF`) behave like grep.
- **Grep-the-text tests passed over real bugs.** Step 4's extraction, the blocker
  printing and the Phase 9 state were each "tested" by grepping a line of the
  command file. Each was wrong when run:
  - a pre-existing finding's `Base evidence:` line was filed as a major;
  - two-file `grep` output was prefixed with file names, so the anchored filter
    removed nothing;
  - step 4 read a variable that step 0 set in another shell.
- **The cross-shell variable, again** (R-001's lesson). Phase 9 step 0 set
  `SECURITY_REVIEW_STATE` in a shell variable, but step 4 is its own block. The state
  is now copied to `/tmp/ship-<ID>-security-review-state`.
- `cat "$@"` glued a report without a trailing newline onto the next report's first
  finding. Fix: `awk 1`.
- Under a UTF-8 locale macOS `cut -c` counts characters. The non-ASCII key test
  therefore passed before the fix, until it exported `LC_ALL=C`.

## Reusable Patterns
- **Verify in the shell that runs the code.** For anything a command block sources,
  check behaviour in Claude Code's zsh (`type grep` shows the wrapper) as well as in
  bash. Tell reviewers to do the same; that instruction is what surfaced the blocker.
- **Execute the whole block, located by a unique anchor.** A test that extracts one
  line of a multi-line pipeline breaks or lies when the pipeline grows. Extract from
  a unique header to its closing `fi`, or use the `block` helper. Stub slash
  commands (`/ship-idea`) with a recording shell function via `sed`.
- **Prototype → generated patches → replay → codex** worked a third and fourth time,
  with zero BLOCKED stops.
- **Main-session orchestrated security pass:** finder agent, then one parallel filter
  agent per candidate, then a confidence ≥ 8 cutoff. Cheap when the finder returns
  nothing.

## Technical Debt
- Step 4's awk filter `/^[🟡]/` matches single bytes in macOS awk. A nit or blocker
  inside a major's context can be filed as a major and push a real one out. Majors
  written as bare `[important]` are counted but never filed. This is pre-existing on
  main and not fixed here.
- Phase 9's `CODEX_ROUNDS` / `CODEX_LAST_FINDINGS` rely on step 0's shell variables
  surviving into step 4, the same defect class just fixed for the security state.
- `codex_verdict` still misclassifies ship-workflow ships as `infra`, because of test
  names in the log. Overridden by hand twice more.

## Future Follow-ups
- ai_system has no `docs/ideas/`, so `/ship-idea` and step 4.5 cannot file
  follow-ups in this repo. The round-3 pre-existing finding could not be filed.
- A finding's text, including a key with backticks (`` `/^[🟡]/` ``), flows into
  `/ship-idea`, which ends in `git commit -m "…$description…"`. The finder rated this
  about 5/10; quote it or pass it through a file.
- `airos-binding.sh project_path` derives the project from the toplevel directory
  name, which is wrong inside a worktree.
- `~/.claude/skills/ship-workflow` points at the main checkout, which is on
  `ship/ship-brief` and lacks R-001/R-003. ship-next there runs stale libs
  (`test-budget.sh` sources a missing `ship-log.sh`).
- langlive: `docs/SECURITY_REVIEW.md`, and the KB stored-injection item.
