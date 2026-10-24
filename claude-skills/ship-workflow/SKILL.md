---
name: ship-workflow
description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Five ship-* slash commands, installed once per machine. Use when bootstrapping a repo for it, capturing an idea, or shipping a ROADMAP row through the /ship-next mega-command (worktree → brainstorm → spec → plan → execute → review → merge).
---

# Ship Workflow

Product development workflow built around one mega-command, `/ship-next`. Its five
commands are installed **once per machine** — `ai_system`'s `./sync.sh restore` links
them into `~/.claude/commands/` — and every repo uses those. A repo carries no copies.

- **`/ship-next [R-NNN] | --adhoc <desc> | --discard R-NNN`** — End-to-end ship cycle: open worktree → brainstorm → spec → plan → execute → strict code-review + security gate → squash-merge (or open an MR) → cleanup
- **`/ship-compound`** — Write learning + promote patterns + close the Roadmap item (ship-next Phase 8 runs it)
- **`/ship-idea <description>`** — Capture an idea (IDEA-NNN); ship-next Phase 6 files major and pre-existing findings with it
- **`/ship-land [R-NNN]`** — Finish an item shipped via `merge_mode: mr`: verify the review merged, move the row to Done, remove the branch + worktree Phase 9 kept
- **`/ship-init`** — Bootstrap a repo (folders, AIR-OS Product Brain stub); `--upgrade` removes old per-repo command copies

- **UA integration**: `/ship-next` auto-detects `.ua/knowledge-graph.json` in the target repo and injects UA blast-radius context into Phase 3 (brainstorm), Phase 6 (review), and Phase 8 (compound). Silent no-op when UA absent. See `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.

## Dual-Brain Architecture

- **Obsidian Product Brain** at AIR-OS `10 Projects/<repo-name>/`:
  - VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS (edited by hand; `--adhoc` inserts ROADMAP rows)
  - `Architecture/` (hand-written POCKET/JOURNEY/GLOSSARY/REMINDERS + cases/; optional `.ua/knowledge-graph.json` in target repo for descriptive code graph via UA plugin)
- **Repo Execution Brain** at `<repo>/docs/`:
  - `ideas/` `decisions/` `brainstorms/` `specs/` `plans/` `learnings/`
  - `product/` (mirror of vault strategy + roadmap)
- One-way sync (Obsidian → repo) on every ship-* command invocation, with 60-second freshness window

## Usage

```bash
# Install (once per machine, in the ai_system checkout, on main)
$ ./sync.sh restore     # links ship-workflow, run-plan, code-review-skill + the 5 commands

# Per-repo init
$ cd /path/to/your/repo
$ /ship-init            # adds docs/ + AIR-OS strategy files (no command copies)

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
dispatched background agents produced nothing: a research run lost two
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
   The research-run loss was two completed phases thrown away because
   nothing was written until Phase 4.

`/ship-next` Phase 5 executor 1 (`subagent-driven-development`) is subject to
this rule. Its per-task ledger at `.superpowers/sdd/<plan>/progress.md` is the
checkpoint — write the ruling and the commit SHA to it as each task closes, so
a lost agent costs one task rather than the run.

## Reference

See `references/flow-diagrams.md` for the full lifecycle diagram, `references/escape-hatches.md` for `--adhoc` behavior, and `references/ce-skill-mapping.md` for which `ce-*` skill each `ship-*` delegates to.

Full spec: `docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
