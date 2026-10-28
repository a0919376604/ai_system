---
name: weekly-report
description: |
  Generate a concise English weekly report from a project's git history.
  Reads git log within a date range (defaults to last 7 days), groups commits
  by theme (chat/media, KB/AI, UI/UX, frontend architecture, infra, etc.),
  and outputs a markdown checklist in the user's preferred format.
  Use when asked to "weekly report", "週報", "整理這週做的事", "整理 X 到 Y 做的事",
  or "summarize work between <date> and <date>".
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Weekly Report

Generate a concise English weekly report from project git history, grouped by theme.

## When to use

- User asks for a weekly report (週報 / weekly summary / "整理這週做的事").
- User provides a date range and asks to summarize work in that range.
- User wants a status update for sharing with their team / manager.

## Output format (strict)

Always output in this exact markdown shape:

```markdown
1. Improve the <project> system:
   a. <Theme A>:
      - <task one-liner>
      - <task one-liner>
   b. <Theme B>:
      - <task one-liner>
      - <task one-liner>
```

Rules:
- **English only** in the final output (commits / docs may be Chinese — translate).
- Group similar commits into themes. Don't list every commit.
- Each bullet is one short line starting with a verb: `add X`, `fix X`, `redesign X`, `migrate X`.
- Merge spec/plan/refactor/test commits into the feature they belong to (don't list them separately).
- Skip noise: `chore`, `WIP`, `merge`, lint, format, version bumps.
- Keep the whole report under ~20 lines if possible.

## Procedure

1. **Determine date range.** If user didn't give one, default to the last 7 days. Convert relative dates (e.g. "上週", "this week") to absolute YYYY-MM-DD using today's date.

2. **Detect project root.**
   - If user named a project, `cd` into it.
   - Otherwise use the current working directory.
   - If not a git repo, ask for the path.

3. **Pull git history** for the range. Use `--all` to include merged branches. Run:

   ```bash
   git log --since="<from>" --until="<to> 23:59:59" --pretty=format:"%h %ai %s" --all
   ```

   For large outputs (>200 commits), also skim commit bodies of merges to understand scope.

4. **Optionally read planning docs.** If `docs/superpowers/plans/` or `docs/superpowers/specs/` exists, list files whose date prefix falls in the range — these give cleaner one-liner descriptions than raw commit messages.

5. **Cluster commits into themes.** Typical theme buckets (pick what fits the actual work — don't force all of these):
   - Feature expansion (chat / media / messaging / etc.)
   - Observability & dashboards
   - Data / KB / AI pipeline
   - UI/UX & cross-platform compatibility
   - Frontend architecture & performance
   - Backend infra / jobs / cronjobs
   - Bug fixes (only if substantial; otherwise fold into the related feature)

6. **Write each bullet as one short line.** Prefer the feature name over the implementation detail. E.g. `add chat media display (image lightbox, audio player, file/video upload)` not `feat(chat): inline image lightbox and audio player + feat(line_service): build VideoMessage…`.

7. **Output the markdown block.** No preamble, no trailing summary — just the report inside a fenced ```markdown block so the user can copy it.

## Style examples

Good bullet:
- `add LINE quote reply (inbound display + outbound sidecar mapping + right-click menu)`
- `redesign question analysis sub-tabs (4 granularities, KB Miss / KB Error views)`
- `migrate frontend state to TanStack Query + Zustand`

Bad bullet (too granular / too vague):
- `feat(chat): inline image lightbox` ← too narrow, missing siblings
- `improve chat` ← too vague
- `add UserAvatar component` ← internal detail, not user-facing

## Variations the user may ask for

- **Lettered top level only** (no sub-bullets): flatten themes, each line is one task with `: finished`.
- **All-Chinese output**: only if explicitly asked.
- **Numbered top level** (multiple projects): `1. Project A: …` `2. Project B: …`.
- **Per-day breakdown**: skip themes, group by date instead.

Default to the lettered + sub-bullet form above unless the user specifies otherwise.
