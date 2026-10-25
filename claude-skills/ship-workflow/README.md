# Ship Workflow

A Claude Code skill: a product development workflow built around `/ship-next`, with five commands installed once per machine.

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
./sync.sh restore   # links ship-workflow, run-plan, code-review-skill and the 5 commands
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
| `/ship-land` | After an mr review merges, run `/ship-compound` at `origin/<base>` in a throwaway worktree, push with `[skip ci]`, then clean up (R-008) |
| `/ship-init` | Scaffold a repo; `--upgrade` removes old per-repo command copies |

**UA integration** — `/ship-next` auto-picks up `.ua/knowledge-graph.json` if present in the target repo. See spec `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.

## Security review (ship-next Phase 6)

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
