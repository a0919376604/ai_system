---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-007
status: draft
tags: [ship-workflow, commands, arguments, bugfix]
ai-first: true
---

## For future Claude
> Claude Code substitutes `$0`…`$9` in a command file with the invocation's arguments
> before the agent reads it. Every bash/awk `$N` inside `commands/*.md` was therefore
> rewritten on any call with arguments (36 of 37 recorded `/ship-next` calls). Phase 3's
> learnings filter, Phase 6's test-line counts and refactor check, and ship-land's
> worktree lookup all ran on garbage. R-007 moves those snippets into `lib/` (which is
> never substituted), parses ship-next's arguments in prose, and adds a regression test
> that no command file contains `$` followed by a digit.

## Decisions
- leric, 2026-10-25: 「auto 做完全部」— fix this first, as the smallest urgent item.
- My call: snippets that need awk fields move to lib functions, not to `$(1)` tricks —
  they become unit-testable, and R-010 moves the rest of the bash into lib anyway.
- My call: ship-next's argument parsing becomes prose rules. The old `while/case` loop
  over shell positionals never had real positionals in the agent's shell.
- My call: ship-land and ship-init read their single argument from `$ARGUMENTS`, the
  placeholder Claude Code substitutes on purpose. Read without substitution it is an
  unset variable, so they fail with the usage error.

## Evidence
- Delivered text in a 2026-10-24 session: `case "ship-compound" in`,
  `awk 'length(--adhoc) >= 4'`, `TEST_LINES_ADDED="ship-compound"`.
- Phase 3 on slug `show-churn-warning-in-chat`: as written, terms churn/warning/chat →
  9 learnings; as delivered with `$0`→`R-240`, every word passes (`in` too) → 35 hits →
  over the cap of 3 → none read. With `$0`→`--adhoc`, zero terms → zero hits.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `learnings_terms` | `learnings_terms <slug>` | One term per line: the slug's `-`-separated words of length ≥ 4, minus fix/add/update/remove/improve/unify/polish/show/make/into, in slug order. |
| `tb_test_lines_added` | `tb_test_lines_added <sha>` | Echo the integer sum of added lines in `*test*` / `tests/` paths in that commit (0 when none). |
| `pre_existing_drop` | `pre_existing_drop <file>…` | Print the files' lines except each `[pre-existing]` finding line (per `PRE_EXISTING_RE`) and the indented detail lines that follow it. |
| `land_worktree_for_branch` | `land_worktree_for_branch <branch>` | Echo the path of the worktree that has `refs/heads/<branch>` checked out; nothing when none. |
| command files | `commands/*.md` | Contain no `$` immediately followed by a digit. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | slug `show-churn-warning-in-chat` | `learnings_terms` | exactly `churn`, `warning`, `chat` |
| AC-2 | a commit adding 3 lines to `tests/a.bats` and 5 to `src/a.sh` | `tb_test_lines_added <sha>` | `3` |
| AC-3 | a report with one pre-existing finding (+1 detail line) and one blocking finding | `pre_existing_drop` | the blocking finding is printed; the pre-existing finding and its detail are not |
| AC-4 | a repo with a worktree on branch `ship/R-1-x` | `land_worktree_for_branch ship/R-1-x` / `… nope` | its path / empty |
| AC-5 | `commands/*.md` | `grep -nE '\$[0-9]'` | no match |
| AC-6 | existing suite | `bats tests/` | green except the known cwd-guard failure in a linked worktree |
