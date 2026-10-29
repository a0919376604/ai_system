# Ship Workflow

A Claude Code skill: a product development workflow built around `/ship-next`, with seven commands installed once per machine.

## What it gives you

```
Roadmap → /ship-next mega-command → Worktree → Brainstorm → Spec → Plan → Execute → Review → Merge
```

- Strategy lives in Obsidian (AIR-OS `10 Projects/<repo>/`)
- Per-Roadmap-item artifacts live in the repo (`docs/{ideas,decisions,specs,plans,learnings}/`)
- Auto-pull strategy from Obsidian into repo on every command

## Installation

This skill lives in `ai_system/claude-skills/ship-workflow/`. In the ai_system checkout,
on `main`, run once per machine:

```bash
./sync.sh restore   # links ship-workflow, run-plan, code-review-skill, pr-review and the 7 commands
./sync.sh status    # every line should say ok
```

Bootstrap a repo (folders and vault stub only — no command copies):
```bash
cd /path/to/your/repo
/ship-init
```

## Commands

| Command | Purpose |
|---|---|
| `/ship-next` | End-to-end ship cycle: worktree → brainstorm → spec → plan → execute → review → merge |
| `/ship-compound` | Learning + promote patterns + close (ship-next Phase 8) |
| `/ship-idea` | Capture idea (IDEA-NNN); ship-next files review findings with it |
| `/ship-refactor-scan [<direction>]` | Scan for deepening opportunities with Pocock's improve-codebase-architecture (churn × lines hotspots, HTML report in the vault); picked candidates become 🔜 Next rows for /ship-next (R-025) |
| `/ship-refactor-brand [<direction>]` | Scan brand consistency and duplicate UI; propose integration and migration order in linked reports; selected candidates enter Next for `/ship-next` |
| `/ship-land` | After an mr review merges, run `/ship-compound` at `origin/<base>` in a throwaway worktree, push with `[skip ci]`, then clean up (R-008) |
| `/ship-init` | Scaffold a repo; `--upgrade` removes old per-repo command copies |


## Security review (ship-next Phase 6)

Phase 6's review steps (code review, codex cross-review, Spec review, security pass) live in the `pr-review` skill (§ Ship mode, R-027): ship-next runs them each attempt, and `/pr-review` runs the same four axes on any GitHub PR, GitLab MR or branch.

**Spec review:** Every attempt also compares the diff with the spec, following Matt Pocock's two-axis `code-review`. Missing or wrong criteria block; extras carry `[ponytail:yagni]`. The report is format-checked before counting.

Every review attempt runs a **separate security pass** next to code-review-skill, as in
Anthropic's own pipeline. It is a vendored copy of Anthropic's open-source
`/security-review` prompt (MIT; `templates/security-review/`) with five changes: it
reviews this ship's diff (`<base>...HEAD`), it writes ship-next's severity format, it
**includes prompt injection and unsafe handling of LLM output**, its false-positive
filters also see that category, and it may report pre-existing issues tagged
`[pre-existing]`.

- HIGH findings block like code-review blockers (same fix-plan loop, cap 3). MEDIUM is
  important; LOW is a nit.
- `[pre-existing]` findings, from either review, never block. Each becomes one IDEA
  follow-up, and an already-tracked one is not filed again.
- **Turn it off** with `security_review: off` in `.claude/ship-config.yml`. The value
  is read **from the base branch**, so a ship cannot switch off its own review.
- **Repo notes:** an optional `docs/SECURITY_REVIEW.md`, also read from the base
  branch, is appended to the prompt. Say where prompts are built, which markers are
  internal, and what the trust boundaries are. For example:

  ```markdown
  - LLM prompts are assembled in `backend/engines/langgraph/prompts/`; end-user LINE
    text arrives as `{question}`.
  - `[系統提醒]` and `[客服上一輪回覆]` are internal markers a user must not be able to forge.
  - Anything written by `qa_to_kb` becomes knowledge-base content that every user's
    answer reads.
  ```

## Development

```bash
# Run tests
cd claude-skills/ship-workflow
bats tests/

# Install for development, from the main checkout on main (it refuses in a worktree);
# the links point at this checkout, so edits are live
cd ../.. && ./sync.sh restore
```

## Specification

`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`

### Door routing (ship-next Phase 7)

Each ship takes its door from the spec's Decisions and mechanical diff signals.
Missing doors, migrations, new dependencies, deploy files and base-branch
`one_way_paths` force one-way. Two-way reviews enable auto-merge only once a
pipeline or check exists; otherwise they warn and wait for a human.

| repo `merge_mode` | door | this ship lands by |
|---|---|---|
| squash | two-way | squash merge, as today |
| squash | one-way | push + PR/MR, in review, `/ship-land` after a human merges |
| mr | two-way | push + MR, then auto-merge once the MR has a pipeline |
| mr | one-way | push + MR, in review, waits for a human |

The same brand workflow is installed in Codex as `$ship-refactor-brand`. Both entry points use `skills/ship-refactor-brand/` in this checkout. `sync.sh restore` preserves any existing personal copy before linking it.
