---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-009
tags: [learning, ai_system, ship-workflow, simplification]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-009
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> R-009 deleted what never paid off (UA integration, prune report, ce-compound/ce-promote
> delegation, ponytail pinning), made review cheaper (security pass once per attempt that
> code review clears; one scoped reviewer), added a small-change lane (no plan file) and a
> landing-branch WARN, fixed codex_verdict's test-name false positive and run-plan's zsh
> first-slot bug, and gave ai_system a .gitignore. −2,056 lines.

## What Shipped
- See the squash commit body; ship-next.md 1496 → 1288 lines, ship-compound.md 343 → 206.

## Key Decisions
- Delete on evidence: UA no-op'd in every worktree (`.ua/` untracked), prune report 3/20 runs with candidates, ce-* 0 calls (leric approved the list).
- Merged the planned R-009 and R-011 into one ship after the operator found the run slow.
- Landing branch: WARN, not refuse — worktree-hosted sessions must still work.

## What Changed From Plan
- codex finished all four tasks, then reported BLOCKED on two integration gaps its own review found (ignored mirror vs step-9 staging; lane ships have no plan for compound). Fixed inline.
- Review found a zsh `nomatch` abort in compound's ship lookup → `find` instead of a glob.

## Bugs
- zsh aborts a command when a glob matches nothing; the Bash tool's shell is zsh. Prefer `find` or `ls dir | grep` in command blocks.

## Reusable Patterns
- **Scope the reviewer.** A reviewer told "≤ ~25 tool calls, real defects only, these 6 checks" finished in 4 minutes vs 13–20 for an open brief, and still found the one real issue.
- **Ask the executor to review integration at the end.** codex's own final pass caught two cross-task gaps no task's tests covered.

## Technical Debt
- Phase 7's commit body still reads Phase 6 variables across shells (pre-existing).

## Future Follow-ups
- R-010: move ship-next's remaining bash into lib and strip history prose from the instructions.
