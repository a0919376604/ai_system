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
- **`/ship-land [R-NNN]`** — Finish an item shipped via `merge_mode: mr`: verify the review merged, move the row to Done, remove the branch + worktree Phase 9 kept

**Knowledge bridges (3):**
- **`/ship-research <topic>`** — Vault-first deep research (thin wrapper over `/obsidian-research-deep`)
- **`/ship-propose [R-NNN]`** — Produce **prescriptive** proposal doc for a Roadmap item; orchestrates ship-research as sub-step; Self-FAQ pattern is the forcing function
- **`/ship-explain [R-NNN | --all-now]`** — Generate plain-language explainer note for a ROADMAP row (so non-domain readers understand what a row actually does); auto-invoked during decompose and `/ship-next` pre-flight

- **UA integration**: `/ship-next` auto-detects `.ua/knowledge-graph.json` in the target repo and injects UA blast-radius context into Phase 3 (brainstorm), Phase 6 (review), and Phase 8 (compound). Silent no-op when UA absent. See `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.

## Dual-Brain Architecture

- **Obsidian Product Brain** at AIR-OS `10 Projects/<repo-name>/`:
  - VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS (manual + ship-roadmap)
  - `Architecture/` (hand-written POCKET/JOURNEY/GLOSSARY/REMINDERS + cases/; optional `.ua/knowledge-graph.json` in target repo for descriptive code graph via UA plugin)
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

- `ponytail:` configures mode, pinned version, and ruleset SHA-256.
- `test_budget:` configures the major and blocking multipliers against each repo's baseline.

The shadow-mode ship count is derived from `docs/learnings/_log.md` and is deliberately not stored in config.

**Per-repo** (`.claude/ship-config.yml`, optional, only on `--custom` init).

## Standing rule: background agents do not survive a session boundary

Measured on this machine, not assumed. Across two sampled sessions, nine
dispatched background agents produced nothing: a `/ship-research` run lost two
full research rounds at Phase 3 and had to redo them inline, and a
`subagent-driven-development` run lost six agents, twice re-dispatching the
*identical* fix before the work was finally done inline. Every one of them
reported `didn't finish before the previous session ended`.

So, before dispatching any background agent:

1. **Ask whether the task writes anything.** Read-only fan-out (search, review,
   research gathering) is cheap to lose and fine to dispatch. Work that must
   produce a commit, a file, or a decision is not — run it inline.
2. **Never re-dispatch after a loss.** If an agent is reported lost, verify
   what landed (`git log`, the expected file, the test count) and then do the
   work inline. A second dispatch of the same task is the single most expensive
   mistake in the sampled history.
3. **Checkpoint multi-phase work to disk after every phase**, not at the end.
   The `/ship-research` loss was two completed phases thrown away because
   nothing was written until Phase 4.

`/ship-next` Phase 5 executor 1 (`subagent-driven-development`) is subject to
this rule. Its per-task ledger at `.superpowers/sdd/<plan>/progress.md` is the
checkpoint — write the ruling and the commit SHA to it as each task closes, so
a lost agent costs one task rather than the run.

## Reference

See `references/flow-diagrams.md` for the full lifecycle diagram, `references/escape-hatches.md` for `--adhoc` behavior, and `references/ce-skill-mapping.md` for which `ce-*` skill each `ship-*` delegates to.

Full spec: `docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
