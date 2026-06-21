---
name: ship-init
description: Bootstrap Ship Workflow in current repo (folders + commands + AIR-OS Product Brain stub)
argument-hint: "[<repo>]"
discord-visible: true
---

# /ship-init

You are bootstrapping the Ship Workflow in the user's current repo.

## Arguments

- `<repo>` (optional) — accepts three forms:
  - **Bare word** (e.g. `langlive-line-oa`) — resolves to `<code_root>/<repo>` (where `code_root` comes from `~/.claude/ship-workflow.yml`). If that directory exists, `cd` there and use `<repo>` as the AIR-OS project name. This is the mobile-friendly form.
  - **Absolute path** (starts with `/`) — `cd` there, use basename as project name.
  - **Omitted** — use current working directory; project name = basename(pwd) or `.claude/ship-config.yml` override.
- `--custom` — interactively prompt for per-repo config overrides and write `.claude/ship-config.yml`
- `--upgrade` — only re-copy `.claude/commands/ship-*.md` from the skill (preserves docs/ and Obsidian content)
- `--with-arch` — after scaffolding completes, automatically invoke `/ship-arch` so AIR-OS Architecture/ is populated before the first `/ship-roadmap`. Recommended when initializing on a mature repo (≥ 10 source files). For a brand new / empty repo, leave it off — running ship-arch on a near-empty codebase produces no value.

## Steps

0. **Refuse if inside a worktree.** This command scaffolds repo + vault state which must land on main, not a per-R-NNN worktree.
   ```bash
   ~/.claude/skills/ship-workflow/lib/cwd-guard.sh || exit $?
   ```
   On failure, the user sees an ERROR pointing them back to main repo and exits non-zero immediately.

1. **Resolve target directory + project name.** Order of checks:

   ```bash
   ARG="$1"   # may be empty, a bare word, or an absolute path
   CODE_ROOT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh code_root)

   if [ -z "$ARG" ]; then
     # No arg → use current cwd
     TARGET_DIR="$(pwd)"
   elif [[ "$ARG" == /* ]]; then
     # Absolute path
     TARGET_DIR="$ARG"
   elif [ -d "$CODE_ROOT/$ARG" ]; then
     # Bare word + code_root has matching subdir
     TARGET_DIR="$CODE_ROOT/$ARG"
   else
     # Bare word but no matching code_root subdir → treat as project-name override only
     TARGET_DIR="$(pwd)"
     PROJECT_NAME_OVERRIDE="$ARG"   # used to write .claude/ship-config.yml
   fi

   cd "$TARGET_DIR"
   ```

   Then resolve identity:
   ```bash
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh vault
   ```

   If `PROJECT_NAME_OVERRIDE` was set (rare path-mismatch case), persist into `.claude/ship-config.yml` with `airos_project: <name>` so subsequent ship-* commands resolve the same way.

   If the global config (`~/.claude/ship-workflow.yml`) is missing, STOP and ask the user to create it with `airos_vault: /path/to/SecondBrain` and `code_root: /path/to/code/workspace`.

2. **`--upgrade` short-circuit.** If `--upgrade`:
   - `cp ~/.claude/skills/ship-workflow/commands/*.md .claude/commands/`
   - Done. Skip the rest.

3. **Scaffold repo side.** Create:
   - `.claude/commands/` and copy all 10 `ship-*.md` from `~/.claude/skills/ship-workflow/commands/` (7 core + 3 bridges: ship-arch, ship-research, **ship-propose**)
   - `docs/ideas/`, `docs/decisions/`, `docs/brainstorms/`, `docs/specs/`, `docs/plans/`, `docs/learnings/`, `docs/product/`, `docs/proposals/`
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
   - **Language rule:** AIR-OS templates are already written in zh-TW prose (per the vault's `output-lang: zh-TW` rule from `_CLAUDE.md`). Any further user-facing content the command writes into Obsidian (e.g. the seeded VISION one-liner) must also be in zh-TW unless the user explicitly wrote it in English.

6. **Interactive seed prompts.** Ask the user (each skippable):
   - "What's the one-line vision for `<project_name>`?" → write into VISION.md
   - "What's the first Roadmap item description (R-001)?" → if provided, run `lib/roadmap-insert.sh "<roadmap_path>" R-001 "<desc>"`

7. **Verify.** Run:
   ```bash
   ls .claude/commands/   # should have 10 ship-*.md files
   ls docs/               # should have 8 subdirs
   ls "<project_path>"    # should have 4 strategy .md files
   ```

8. **Commit.** Run:
   ```bash
   git add .claude/commands .claude/.gitignore docs/
   git commit -m "chore: initialize ship-workflow (9 commands + 7 folders)"
   ```
   If the user is in a worktree on a feature branch, mention it. Don't push.

9. **`--with-arch` follow-on.** If the flag was passed, invoke `/ship-arch` now (with the resolved project name) before the report. Stream its output through to the user.

10. **Report.** Tell the user:
    - Project name resolved
    - AIR-OS project path
    - Number of commands installed
    - Whether VISION / R-001 were seeded
    - **Repo-state hint** — count source files quickly:
      ```bash
      find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -o -name "*.rb" -o -name "*.rs" \) \
        -not -path "./node_modules/*" -not -path "./.git/*" | wc -l
      ```
    - Next suggested commands (in priority order):
      - **If source count ≥ 10 AND `--with-arch` was NOT used**: `/ship-arch` to capture initial architecture — this materially improves the next `/ship-roadmap` ranking by giving ce-strategy a module dependency graph
      - **If source count < 10** (new / empty repo): skip ship-arch suggestion — code first, then `/ship-arch` after you've shipped enough to have architecture worth capturing
      - `/ship-roadmap` to plan items
      - `/ship-next` to start work

## Idempotency

Every step must be safe to re-run:
- Creating an existing directory: silently skip
- Copying a file that exists in target: skip (unless `--upgrade`, then overwrite commands only)
- AIR-OS strategy files: NEVER overwrite

## Failure modes

- Global config missing → stop with clear message
- Not in a git repo → warn but continue (vault folder still useful)
- AIR-OS vault path doesn't exist → ERROR, ask user to fix
