# Ship Workflow

A Claude Code skill that installs a 7-command product development workflow into any repo.

## What it gives you

```
Roadmap → Brainstorm → Plan → Build → Compound → Roadmap update
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

| Command | Purpose |
|---|---|
| `/ship-init` | Scaffold workflow in current repo |
| `/ship-idea` | Capture idea (IDEA-NNN) |
| `/ship-decision` | Record decision (D-NNN) |
| `/ship-roadmap` | Refresh ROADMAP.md |
| `/ship-next` | Pick next item → brainstorm + spec |
| `/ship-build` | Plan + execute |
| `/ship-compound` | Learnings + promote patterns + close |

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
