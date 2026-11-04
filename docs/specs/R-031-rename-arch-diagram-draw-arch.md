---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-031
status: draft
tags: [spec, ai_system, draw-arch, rename]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-031
related-specs: [R-029, R-030]
supersedes: null
mirror-source: docs/specs/R-031-rename-arch-diagram-draw-arch.md
---

## For future Claude
> R-031 renames the `arch-diagram` skill to `draw-arch`; users invoke it as `/draw-arch`.
> Behavior is unchanged. `sync.sh restore` now also removes a `~/.claude/skills/<name>` link that dangles into
> this repo's `claude-skills/`, so the old `arch-diagram` link goes away by itself.

## §1 Problem
The owner wants the name to say what the skill does. From IDEA-004: 「改一個我比較知道是在生架構圖的名字 第一個單字應該要 draw」.
They chose 「叫做 draw-arch吧」. `ship-arch-diagram` was rejected because the `ship-*` prefix belongs to the ship-flow commands.

Renaming the directory leaves a link behind. `~/.claude/skills/arch-diagram` points at `claude-skills/arch-diagram`, and today
`remove_dangling` only cleans `~/.claude/commands/ship-*.md`. The old link would stay as a dangling entry in every session's skill list.

## §2 Goals, non-goals
**Goals**
- G1. `git mv claude-skills/arch-diagram claude-skills/draw-arch`. In `SKILL.md`, `name:` and the usage line say `draw-arch`.
- G2. `sync.sh`'s `SKILLS` list and its usage text name `draw-arch`.
- G3. `remove_dangling` also removes any `~/.claude/skills/*` symlink that is dangling and whose target is under
  `$SCRIPT_DIR/claude-skills/`. It leaves every other entry alone.
- G4. `CLAUDE.md` and `CONTEXT.md` use the new name.
- G5. Tests: `test_arch-diagram.bats` becomes `test_draw-arch.bats`, and `tests/fixtures/arch-diagram/` becomes
  `tests/fixtures/draw-arch/`. `test_sync-install.bats` and `test_repo-layout.bats` expect `draw-arch`.
- G6. The enforcer path in `docs/tdd-rules.d/R-030.md` names `tests/test_draw-arch.bats`. That file is a live rule.

**Non-goals**
- Editing history: `docs/learnings/*`, `docs/learnings/_log.md` and IDEA-001 through IDEA-004 keep the old name.
- Changing what the skill does.
- Fixing the Node 26 `node --test <dir>` failure (test 368). That gets its own IDEA.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| installed skill | `./sync.sh restore` / `./sync.sh status` | links `~/.claude/skills/draw-arch` → `<repo>/claude-skills/draw-arch`; status lists `draw-arch` and no `arch-diagram` |
| dangling skill links | `remove_dangling` inside `./sync.sh restore` | a `~/.claude/skills/<n>` symlink whose target is missing **and** under `<repo>/claude-skills/` is removed (`--dry-run` prints `would remove dangling …` and keeps it); a dangling link pointing elsewhere, a live link and a real directory stay |
| repo layout | `ls claude-skills` | exactly `code-review-skill draw-arch pr-review run-plan ship-workflow weekly-report` |
| skill identity | `claude-skills/draw-arch/SKILL.md` | front matter `name: draw-arch`; usage `/draw-arch [<topic>…] [--out <dir>]` |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | the repo after the change | `ls claude-skills` | `code-review-skill draw-arch pr-review run-plan ship-workflow weekly-report` |
| AC-2 | a scratch HOME with `~/.claude/skills/arch-diagram` linked to a missing `<repo>/claude-skills/arch-diagram` | `./sync.sh restore --yes` | that link is gone and `~/.claude/skills/draw-arch` is linked |
| AC-3 | a scratch HOME with a dangling `~/.claude/skills/other` → `/elsewhere/other` | `./sync.sh restore --yes` | that link is kept |
| AC-4 | AC-2's setup | `./sync.sh restore --dry-run` | prints `would remove dangling` for the arch-diagram link and leaves it in place |
| AC-5 | `SKILL.md` | read | `name: draw-arch` and `/draw-arch` usage |
| AC-6 | the bats suite | `bats tests/` | everything passes except the known worktree `cwd-guard` test and the Node 26 test 368 |
| AC-7 | the main checkout after landing | `./sync.sh restore` then `./sync.sh status` | `ok` for `draw-arch`; `~/.claude/skills/arch-diagram` does not exist |

## Decisions
- **Operator.** Chose the name `draw-arch` (「叫做 draw-arch吧」) and said yes to all five brainstorm recommendations (「好」):
  1. Rename the test file and the fixtures too.
  2. Make the dangling-link cleanup general instead of hard-coding `arch-diagram`.
  3. Update the live R-030 rule path, and leave history alone.
  4. Two-way door.
  5. Track Node 26 in a separate IDEA.
- **Door: two-way.** A rename plus a narrower link cleanup. `git revert` and `./sync.sh restore` undo it, and no data or user-facing messages are involved.
- **Claude's calls:**
  - The cleanup only removes a link whose target is under this repo's `claude-skills/`. The owner's other skill links,
    such as gstack and superpowers, are never touched.
  - Small-change lane: one task, about 40 changed lines, and no new seam beyond `remove_dangling`.
