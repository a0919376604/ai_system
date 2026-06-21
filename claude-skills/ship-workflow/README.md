# Ship Workflow

A Claude Code skill that installs a 9-command product development workflow into any repo.

## What it gives you

```
Roadmap → /ship-next mega-command → Worktree → Brainstorm → Spec → Plan → Execute → Review → Merge
```

- Strategy lives in Obsidian (AIR-OS `10 Projects/<repo>/`)
- Per-Roadmap-item artifacts live in the repo (`docs/{ideas,decisions,brainstorms,specs,plans,learnings}/`)
- Auto-pull strategy from Obsidian into repo on every command

## Installation

This skill is distributed via `ai_system/claude-skills/`. After `devsync`, it lives at `~/.claude/skills/ship-workflow/`.

Bootstrap in any repo:
```bash
cd /path/to/your/repo
/ship-init
```

## Commands

**Core lifecycle (6):**

| Command | Purpose |
|---|---|
| `/ship-init` | Scaffold workflow in current repo |
| `/ship-idea` | Capture idea (IDEA-NNN) |
| `/ship-decision` | Record decision (D-NNN) |
| `/ship-roadmap` | Refresh ROADMAP.md |
| `/ship-next` | End-to-end ship cycle: worktree → brainstorm → spec → plan → execute → review → merge |
| `/ship-compound` | Learnings + promote patterns + close |

**Knowledge-input bridges (3):**

| Command | Purpose |
|---|---|
| `/ship-arch` | Refresh AIR-OS Architecture/ via `/obsidian-architect` |
| `/ship-research <topic>` | Vault-first deep research via `/obsidian-research-deep` |
| `/ship-propose [R-NNN]` | Produce prescriptive proposal docs for roadmap items |

## Development

```bash
# Run tests
cd claude-skills/ship-workflow
bats tests/

# Local install for development
ln -sf $(pwd) ~/.claude/skills/ship-workflow
```

## Specification

`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
