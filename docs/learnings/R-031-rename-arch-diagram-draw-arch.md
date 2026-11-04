---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-031
tags: [learning, ai_system, draw-arch, rename, sync]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-031
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-031: renamed the `arch-diagram` skill to `draw-arch` (`/draw-arch`).
> `sync.sh restore` now also removes a `~/.claude/skills/*` link that dangles into this repo's `claude-skills/`.

## What Shipped
- `git mv claude-skills/arch-diagram claude-skills/draw-arch`. The test file and fixtures moved the same way, to
  `tests/test_draw-arch.bats` and `tests/fixtures/draw-arch/`. `SKILL.md` now has `name: draw-arch` and the
  `/draw-arch` usage.
- `sync.sh`: `SKILLS` and the usage text name `draw-arch`. `remove_dangling` gained a skills loop, which removes a
  link only when all three hold:
  - it is dangling;
  - its target is under `$SCRIPT_DIR/claude-skills/`;
  - its name is not kept (`SKILLS` plus `run-plan-model`).
- `CLAUDE.md`, `CONTEXT.md` and the live R-030 rule's enforcer path use the new name. History was left alone:
  learnings, IDEA-001 through IDEA-004 and `_log.md`.
- Tests: 3 new `test_sync-install.bats` cases, 819 tests in all. The only failures are two known ones: the worktree
  `cwd-guard` test and test 368 under Node 26.

## Key Decisions
- The operator chose the name `draw-arch`, which starts with a verb. `ship-arch-diagram` was rejected because
  `ship-*` names the ship-flow commands and this skill isn't one.
- The test file and fixtures were renamed with the skill so the names stay consistent.
- The cleanup is general and not hard-coded to `arch-diagram`, so any future rename or removal is covered.
- The live R-030 rule path was updated because it is rendered for executors every ship. History docs keep the old name.
- Door: two-way. It is a rename plus a narrow link cleanup, undone with `git revert` and `./sync.sh restore`.
- The Node 26 `node --test <dir>` failure goes to a separate IDEA.
- Claude's call: the cleanup touches only links into this repo's `claude-skills/`, never gstack or superpowers links.

## What Changed From Plan
This was a small-change lane with no plan. Review attempt 1 added the kept-name guard; see Bugs.

## Bugs
- The first version of the skills loop removed a kept skill's link when its target directory was missing. One run
  printed `linked …/pr-review` and then `removed dangling …/pr-review`, after which `status` said `missing` instead of
  `target missing`. The commands loop already had the guard. Review attempt 1 found it, and the fix was 7394a70.

## Lessons → checks
- A cleanup loop over links that another step creates must skip the names that step manages, so one run never links
  and then removes the same path — enforced by `bats tests/test_sync-install.bats -f 'kept skill'` · proof: red at
  d1f85b3 (exit 1) · green at 409a145

## Reusable Patterns
- When you add a second loop next to an existing one, copy its guards as well as its shape. The commands loop's
  `case " ${COMMANDS[*]} "` skip was the part left out.

## Technical Debt
- Test 368 fails under Node 26 because `node --test obsidian-roadmap-view/test/` no longer accepts a directory.
  Tracked as a follow-up IDEA.

## Future Follow-ups
- The Node 26 `node --test` invocation, in `test_repo-layout.bats` and in the CLAUDE.md command.
