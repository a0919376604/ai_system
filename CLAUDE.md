# ai_system — repo rules

This repo is ship-workflow's home: `claude-skills/` holds `ship-workflow`, plus `run-plan`,
`code-review-skill` and `pr-review`, and nothing else (R-004).
ship-next Phase 6's review steps live in `pr-review` (R-027).
`devsync/` is the separate remote-dev tool; leave it as it is. `obsidian-roadmap-view/` is
the Roadmap 檢視 Obsidian plugin (R-013): plain JS, no build, no npm dependencies.

## The main checkout stays on `main`

`./sync.sh restore` links `~/.claude/skills/{ship-workflow,run-plan,code-review-skill,pr-review}`
and the seven ship-* commands into this checkout's working tree. Every session on the
machine therefore runs whatever this checkout holds, uncommitted edits included.

- Keep the main checkout on `main` and clean. `/ship-next` warns when it is not.
- Do all work through `/ship-next`, which builds in its own worktree under
  `../ai_system-worktrees/`.

## Commands

- Tests: `cd claude-skills/ship-workflow && bats tests/` (includes pr-review). In a linked worktree, the
  `cwd-guard: exits 0 when not in a git repo at all` test fails. That failure is
  pre-existing and known. The bats run includes the plugin's tests; alone they are
  `node --test obsidian-roadmap-view/test/`.
- `./sync.sh restore` copies the plugin into `<airos_vault>/.obsidian/plugins/roadmap-view/`
  when it changed. It never enables it: that is a one-time click in Obsidian.
- After a pull that changes `sync.sh`, `obsidian-roadmap-view/` or the set of directories
  in `claude-skills/`, run `./sync.sh restore`. Then `./sync.sh status` must print `ok` for every link.
- After editing `~/.claude/CLAUDE.md`, run `./sync.sh backup`. It copies the file to
  `config/claude/CLAUDE.md`. That file is the backup of the global rules, not this
  repo's rules.

## Specification edits

Specs live in `docs/specs/R-NNN-<slug>.md`. They follow the ship-next format: a
`## Seams` table and Given-When-Then acceptance rows.
