---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-010
tags: [learning, ai_system, ship-workflow, refactor]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-010
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> ship-next.md is now instructions (650 lines); its glue lives in `lib/ship-next.sh`
> (unit-tested, bash + zsh). Values a later phase needs are in `<worktree>/.ship/state.env`
> (`sn_state_set` / `sn_state_load`); after Phase 9 removes the worktree they are read from
> `$(git rev-parse --git-common-dir)/ship-<ID>-state.env`. History lives in learnings, not
> in the command.

## What Shipped
- `lib/ship-next.sh`: state helpers, `sn_mech_gates`, `sn_codex_after_exit`, `sn_ship_body`, `sn_land`, `sn_capture`, `sn_cleanup`, `sn_log`, `sn_summary`.
- ship-next.md 1288 → 650 lines; longest bash block 15; Phase 1 step 5 now derives DESCRIPTION.

## Key Decisions
- One phase-glue lib + one state file instead of re-resolving in every block (my call; it also fixed Phase 7 reading Phase 6 variables across shells).
- Behavior frozen: tests changed how they reach code, not what they assert.

## What Changed From Plan
- Round 1 BLOCKED: the plan's test bullet contradicted today's codex round recording — plan repaired.
- Review fixes inline: `sn_land` used the main checkout instead of the invoking one (a linked-worktree ship squash-committed onto main and reported success); DESCRIPTION's only rule had been a comment inside a block; moved heredocs/strings kept markdown's 3-space fence indent; state archive moved out of shared /tmp.

## Bugs
- **Moving bash out of a markdown fence changes its text.** The agent dedents fenced code before running it; a lib keeps the indentation — commit bodies and notifications gained 3 leading spaces. Dedent heredoc bodies and multi-line strings when extracting.
- **Comments in transcribed blocks are instructions.** "DESCRIPTION = …" lived in a code comment the agent followed; moved into a lib, nobody read it.

## Reusable Patterns
- **Extracting agent-run code: check three things** — indentation inside strings/heredocs, comments that were really instructions, and variables that crossed blocks through the agent's memory.

## Technical Debt
- The security MEDIUM fix (state archive path) was not re-reviewed by a security pass.

## Future Follow-ups
- none planned; the auto run (R-007…R-010) is complete.
