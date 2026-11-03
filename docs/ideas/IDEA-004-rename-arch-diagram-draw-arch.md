---
date: 2026-11-03
updated: 2026-11-03
type: idea
id: IDEA-004
tags: [idea, ai_system]
ai-first: true
project: "[[ai_system]]"
status: captured
impact: low
confidence: high
target-user: "repo owner invoking the skill"
dependencies: []
related-roadmap-item: null
---

## For future Claude
> IDEA-004: rename the `arch-diagram` skill to `draw-arch`.
> The owner wants a verb-first name that says at a glance it draws architecture diagrams.

## Summary
Rename `claude-skills/arch-diagram` to `claude-skills/draw-arch`. Users invoke it as `/draw-arch`.

## Problem
The noun-only name `arch-diagram` doesn't say what the skill does. The owner wants it to start with a verb.
`ship-arch-diagram` was rejected. The `ship-*` prefix belongs to the seven ship-flow commands, and this skill
isn't a ship-flow step.

## Target User
The repo owner, typing the skill name in any session on this machine.

## Evidence
2026-11-03: the owner asked which skill made the langlive-line-oa diagrams. After seeing the name, they asked for
a verb-first rename and chose `draw-arch` over `draw-architecture`.

## Impact
Low magnitude, but the skill is invoked often. The name is easier to recall and to pick from the skill list.

## Confidence
High. The owner stated the name directly.

## Dependencies
None.

## Risks
- The old `~/.claude/skills/arch-diagram` symlink would be left dangling. `sync.sh restore` must remove it, or the
  rename must clean it up.
- Leave historical docs as they are: R-029/R-030 learnings, `docs/tdd-rules.d/R-030.md`, IDEA-001 through IDEA-003
  and the `_log.md` lines.
- R-004/R-029 list the allowed skill set, so `test_repo-layout.bats` must accept the new name.

## Possible Roadmap Item
R-NNN: rename the arch-diagram skill to draw-arch.
- `git mv claude-skills/arch-diagram claude-skills/draw-arch`
- Update the SKILL.md `name:`, the `/arch-diagram` usage and the self-references.
- Update `sync.sh`: the link list, plus removing the stale `arch-diagram` link.
- Update `CLAUDE.md` and `CONTEXT.md`.
- Update the tests: rename `test_arch-diagram.bats` to `test_draw-arch.bats`, and update `test_sync-install.bats`
  and `test_repo-layout.bats`.
- AC: after `./sync.sh restore`, `./sync.sh status` prints `ok` for `draw-arch`, no `arch-diagram` link remains,
  and `bats tests/` passes, apart from the known worktree cwd-guard failure.
