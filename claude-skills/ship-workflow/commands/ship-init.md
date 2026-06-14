---
name: ship-init
description: Bootstrap Ship Workflow in the current repo. Creates .claude/commands/ ship-* slash commands, docs/ subfolders for ideas/decisions/brainstorms/specs/plans/learnings/product, and AIR-OS Product Brain folder with VISION/STRATEGY/ROADMAP/QUARTERLY_GOALS templates. Idempotent. Use --custom to write a per-repo override config. Use --upgrade to refresh just the .claude/commands/ files from the latest skill version.
---

# /ship-init

You are bootstrapping the Ship Workflow in the user's current repo.

## Arguments

- `--custom` — interactively prompt for per-repo config overrides and write `.claude/ship-config.yml`
- `--upgrade` — only re-copy `.claude/commands/ship-*.md` from the skill (preserves docs/ and Obsidian content)

## Steps

1. **Identify project name and AIR-OS path.** Run:
   ```bash
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh vault
   ```
   If the global config (`~/.claude/ship-workflow.yml`) is missing, STOP and ask the user to create it with `airos_vault: /path/to/SecondBrain`.

2. **`--upgrade` short-circuit.** If `--upgrade`:
   - `cp ~/.claude/skills/ship-workflow/commands/*.md .claude/commands/`
   - Done. Skip the rest.

3. **Scaffold repo side.** Create:
   - `.claude/commands/` and copy all 7 `ship-*.md` from `~/.claude/skills/ship-workflow/commands/`
   - `docs/ideas/`, `docs/decisions/`, `docs/brainstorms/`, `docs/specs/`, `docs/plans/`, `docs/learnings/`, `docs/product/`
   - `docs/learnings/_log.md` with header:
     ```markdown
     # Ship Workflow Log

     | Date | Command | R-NNN | Note | Adhoc? |
     |---|---|---|---|---|
     ```
   - `.claude/.gitignore` adding `.ship-last-pull` and `.id-gen.lock` and `.id-reservations`

4. **`--custom` interactive config.** If `--custom`:
   - Ask: "Override AIR-OS project name? (default: <basename>)"
   - Ask: "Roadmap mode (soft/strict, default: <global>)"
   - Write answers to `.claude/ship-config.yml` (only the keys the user customized)

5. **Scaffold AIR-OS side.** If `<project_path>` does not exist:
   - Create `<project_path>/`
   - For each of VISION.md / STRATEGY.md / ROADMAP.md / QUARTERLY_GOALS.md:
     - If absent, copy from `~/.claude/skills/ship-workflow/templates/obsidian/<name>`
     - Substitute `{{project}}` with `<project_name>` and `{{date}}` with today's date (YYYY-MM-DD)
   - **NEVER overwrite an existing file in AIR-OS.**

6. **Interactive seed prompts.** Ask the user (each skippable):
   - "What's the one-line vision for `<project_name>`?" → write into VISION.md
   - "What's the first Roadmap item description (R-001)?" → if provided, run `lib/roadmap-insert.sh "<roadmap_path>" R-001 "<desc>"`

7. **Verify.** Run:
   ```bash
   ls .claude/commands/   # should have 7 ship-*.md files
   ls docs/               # should have 7 subdirs
   ls "<project_path>"    # should have 4 strategy .md files
   ```

8. **Commit.** Run:
   ```bash
   git add .claude/commands .claude/.gitignore docs/
   git commit -m "chore: initialize ship-workflow (7 commands + 7 folders)"
   ```
   If the user is in a worktree on a feature branch, mention it. Don't push.

9. **Report.** Tell the user:
   - Project name resolved
   - AIR-OS project path
   - Number of commands installed
   - Whether VISION / R-001 were seeded
   - Next suggested command: `/ship-roadmap` to plan further items

## Idempotency

Every step must be safe to re-run:
- Creating an existing directory: silently skip
- Copying a file that exists in target: skip (unless `--upgrade`, then overwrite commands only)
- AIR-OS strategy files: NEVER overwrite

## Failure modes

- Global config missing → stop with clear message
- Not in a git repo → warn but continue (vault folder still useful)
- AIR-OS vault path doesn't exist → ERROR, ask user to fix
