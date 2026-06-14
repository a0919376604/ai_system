---
name: ship-arch
description: Refresh AIR-OS Architecture/ docs for current repo (wraps /obsidian-architect)
argument-hint: "[<repo>]"
discord-visible: true
---

# /ship-arch

You are refreshing the architecture documentation for the current repo.

## Argument

`[<repo>]` — optional. Defaults to `.` (current repo). Accepts a local path or GitHub URL. Pass extra flags through to `/obsidian-architect`.

## When to invoke

| Phase | Why |
|---|---|
| Just after `/ship-init` | Snapshot initial architecture so STRATEGY/ROADMAP can reference real module structure |
| After `/ship-compound` for a refactor / new-module R-NNN | Refresh AIR-OS Architecture/ so it doesn't drift |
| Before a `/ship-next` on a non-trivial item | Give Claude up-to-date module understanding before brainstorm |

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Resolve project name:**
   ```bash
   PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)
   ```

3. **Delegate to `/obsidian-architect`** with the resolved project, passing through any extra flags. Typical invocation:
   ```
   /obsidian-architect . --project=$PROJECT
   ```
   (Or with the explicit repo path if the user provided one.)
   The architect command will:
   - Scan the codebase (Phase 1)
   - Write architecture overview + module notes + decisions + features + AI flows (when detected) into AIR-OS `10 Projects/<PROJECT>/Architecture/`
   - Honor `--refresh`, `--dry-run`, `--no-features`, etc. flags

4. **Append log line:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-arch | - | refresh architecture for $PROJECT | n |" >> docs/learnings/_log.md
   ```

5. **Commit the log line** (architect itself writes only to AIR-OS, not the repo):
   ```bash
   git add docs/learnings/_log.md
   git commit -m "chore: ship-arch refresh for $PROJECT"
   ```

6. **Report:** Tell the user
   - Architecture file count in `AIR-OS/10 Projects/$PROJECT/Architecture/`
   - Whether AI flows / features.md / memory.md / rag.md were produced
   - Next suggested actions: `/ship-roadmap` (use fresh architecture for prioritization) or `/ship-next` (start work with current architecture in mind)

## Failure modes

- `/obsidian-architect` skill is not installed → fall back: tell user to install obsidian-second-brain skill (kept exactly for architect + research-deep per the skills-cleanup decision)
- Repo doesn't have a `10 Projects/<name>/` folder in AIR-OS → run `/ship-init` first
- Architect aborts because no real codebase detected → ask the user for the repo path explicitly
