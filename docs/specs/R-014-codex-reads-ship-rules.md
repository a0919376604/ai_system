---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-014
status: draft
tags: [run-plan, codex, ponytail, tdd-rules]
ai-first: true
---

## For future Claude
> ship-next Phase 5 renders `.ship/tdd-rules.md` and `.ship/ponytail-rules.md` into the
> worktree for the executor. codex read them only when the plan happened to say so: the
> run-plan prompt header never mentioned them, and 27 of 122 line-oa plans did. R-014 adds
> one instruction to that header so codex reads them whenever they exist.

## Decisions
- leric, 2026-10-26: 「好」to adding the line after asking whether codex uses ponytail.
- Evidence: codex has no ponytail plugin (`~/.codex/plugins/cache` holds superpowers and discord only); recent codex logs show `cat .ship/tdd-rules.md .ship/ponytail-rules.md` because those plans carried the line.
- Small-change lane (my call): one header line + one block test.
- The line is conditional ("if they exist") so /run-plan stays usable outside ship-next.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| run-plan Step 2 | the prompt file it writes | Before the plan, the prompt tells codex to read `.ship/tdd-rules.md` and `.ship/ponytail-rules.md` when they exist in the working directory, before the first task. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a plan file | run run-plan Step 2's block | the prompt contains both paths, before the `PLAN (` line |
