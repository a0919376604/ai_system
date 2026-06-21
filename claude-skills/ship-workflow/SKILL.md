---
name: ship-workflow
description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Installs 9 ship-* slash commands. Use when starting product development in a new repo, capturing ideas/decisions, planning roadmap, or shipping features through the /ship-next mega-command (worktree → brainstorm → spec → plan → execute → review → merge).
---

# Ship Workflow

Per-repo product development workflow. Installs 9 slash commands into a target repo's `.claude/commands/`:

**Core lifecycle (6):**
- **`/ship-init`** — Bootstrap workflow (folders, commands, AIR-OS Product Brain stub)
- **`/ship-idea <description>`** — Capture an idea (IDEA-NNN)
- **`/ship-decision <topic>`** — Record an architectural decision (D-NNN)
- **`/ship-roadmap`** — Refresh ROADMAP.md via ce-strategy
- **`/ship-next [R-NNN] | --adhoc <desc> | --discard R-NNN`** — End-to-end ship cycle: open worktree → brainstorm → spec → plan → execute → strict code-review gate → squash-merge → cleanup
- **`/ship-compound`** — Write learning + promote patterns + close Roadmap item

**Knowledge bridges (3):**
- **`/ship-arch`** — Refresh AIR-OS Architecture/ docs (thin wrapper over `/obsidian-architect`) — **descriptive** snapshot of current state
- **`/ship-research <topic>`** — Vault-first deep research (thin wrapper over `/obsidian-research-deep`)
- **`/ship-propose [R-NNN]`** — Produce **prescriptive** proposal doc for a Roadmap item (orthogonal to ship-arch); orchestrates ship-research as sub-step; Self-FAQ pattern is the forcing function

## Dual-Brain Architecture

- **Obsidian Product Brain** at AIR-OS `10 Projects/<repo-name>/`:
  - VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS (manual + ship-roadmap)
  - `Architecture/` (ship-arch, descriptive)
  - `Proposals/` (ship-propose, prescriptive)
  - `Research/` (ship-research, external grounding)
- **Repo Execution Brain** at `<repo>/docs/`:
  - `ideas/` `decisions/` `brainstorms/` `specs/` `plans/` `learnings/`
  - `product/` (mirror of vault strategy + roadmap)
  - `proposals/` (mirror of vault Proposals/)
- One-way sync (Obsidian → repo) on every ship-* command invocation, with 60-second freshness window

## Usage

```bash
# Install (once, in ai_system repo via devsync)
$ devsync push          # makes ~/.claude/skills/ship-workflow/ available

# Per-repo init
$ cd /path/to/your/repo
$ /ship-init            # adds .claude/commands/ + docs/ + AIR-OS strategy files

# Daily flow
$ /ship-next            # pick from Roadmap → end-to-end ship cycle (auto-calls /ship-compound at Phase 8)
```

## Configuration

**Global** (`~/.claude/ship-workflow.yml`):
```yaml
airos_vault: /Users/leric/Documents/SecondBrain
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft
default_id_pad: 3
auto_pull_freshness_window: 60
```

**Per-repo** (`.claude/ship-config.yml`, optional, only on `--custom` init).

## Reference

See `references/flow-diagrams.md` for the full lifecycle diagram, `references/escape-hatches.md` for `--adhoc` behavior, and `references/ce-skill-mapping.md` for which `ce-*` skill each `ship-*` delegates to.

Full spec: `docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
