---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-007
tags: [learning, ai_system, ship-workflow, commands, arguments]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-007
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> Claude Code rewrites `$0`…`$9` in a command or skill file with the invocation's
> arguments before the agent reads it. Any bash/awk positional inside `commands/*.md`
> or `*/SKILL.md` is corrupted on every call with arguments (36 of 37 recorded
> /ship-next calls). Keep positionals in `lib/*.sh`; read arguments in a command via
> `$ARGUMENTS` or prose rules. `tests/test_no-positional-params.bats` guards both globs.

## What Shipped
- lib: `learnings_terms`, `tb_test_lines_added`, `pre_existing_drop`, `land_worktree_for_branch`.
- ship-next: argument parsing is prose; Phase 3 / Phase 6 call the lib functions.
- ship-land `ID="$ARGUMENTS"`; ship-init takes the first non-`--flag` token of `$ARGUMENTS`.
- run-plan: `read -r … <<< "$ARGUMENTS"` at top level, `for X in "$@"; do break; done` in functions.
- Regression test over `commands/*.md` and `claude-skills/*/SKILL.md`.

## Key Decisions
- Move snippets to lib rather than `$(1)` tricks — testable, and R-010 moves the rest anyway (my call).
- ship-init must skip flags: `$ARGUMENTS` is the whole string, so `--upgrade` became the project name (review attempt 1 blocker).
- Fix run-plan in the same ship though pre-existing — same defect, same test (auto-mode call).

## What Changed From Plan
- Review fix 2 added run-plan, the skill-file test glob, and two prose fixes (`--auto` anywhere; write parsed values as assignments).

## Bugs
- Before: Phase 3 learnings lookup matched 35 files for an R-NNN call (filter disabled → over cap → none read) and 0 for `--adhoc`; Phase 6 test-line counts held argument text.
- Found while shipping: `codex_verdict` classified a DONE run as `infra` because the bats test name "out of credits is infra" appeared in the executor's output. Any ai_system ship whose executor runs the suite is affected.

## Reusable Patterns
- **Text that an argument loader rewrites is not code.** Treat command/skill markdown as a template: no `$<digit>`, read inputs via the documented placeholder, keep logic in sourced files.

## Technical Debt
- run-plan `${ALIVE[0]}` reads index 0, which is empty in zsh (the Bash tool's shell): `/run-plan status|kill` with no argument misses the only live run (pre-existing).
- run-plan `resolve_slot` has no caller.
- `codex_verdict` infra signatures match anywhere in the log, test output included.

## Future Follow-ups
- R-009: fix codex_verdict false positive and run-plan zsh indexing; drop resolve_slot.
