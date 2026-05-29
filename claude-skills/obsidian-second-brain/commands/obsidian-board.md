---
description: Show or update a kanban board — flags overdue items, updates from conversation
category: vault
triggers_en: ["show board", "kanban", "what is on my board", "update board"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-board $ARGUMENTS`:

The first argument is a board name (project name). Optional second flag: `--refresh` (regenerate from git history) or `--full` (force full rebuild, default is incremental). Without `--refresh`, this is interactive: read the board and ask what changes to make.

## Project routing

The board name resolves to a project. Boards always live at `Projects/<name>/board.md` (the legacy `Boards/<name>.md` flat location is no longer used - migrate if found).

To locate the codebase for `--refresh`: read `Projects/<name>/<name>.md` frontmatter for `local-path:`. If missing, ask the user once and persist it back to the frontmatter.

## Modes

### Interactive mode (no `--refresh`)

1. Read `_CLAUDE.md` first if it exists in the vault root
2. If a board name is given, look for `Projects/<name>/board.md`; if not found, search `Projects/*/board.md` (fuzzy match)
3. If no name given, list available boards (one per `Projects/*/board.md`) and ask which one
4. Read and display the current board state: 🔥 This Week (Now/Next/Later), 待辦, 進行中, 已完成, plus any topic buckets
5. Ask if the user wants to make updates - if yes, infer changes from conversation context
6. Move completed items to ✅ 已完成 with strikethrough, add new items in the right column
7. Flag any items that are overdue (`@{date}` past) or stuck (in same column > 1 week per `last-moved:` timestamp)

### Refresh mode (`--refresh` flag set)

1. Resolve `local-path` from `Projects/<name>/<name>.md` frontmatter
2. Read `Projects/<name>/board.md` frontmatter for `last-refresh:` timestamp (full rebuild if missing or `--full` passed)
3. Scan codebase for new work since `last-refresh`:
   - `cd <local-path> && git log --all --since=<last-refresh> --pretty=format:"%H %s %D"` - capture commits + branch names
   - `ls -t <local-path>/docs/superpowers/specs/*.md <local-path>/docs/superpowers/plans/*.md` - list spec/plan files; keep those modified since `last-refresh`
4. Cluster discovered items into topic buckets:
   - Preserve existing bucket names from the current `board.md` if present (`## Customer Service tools`, `## Chat / LINE messaging`, etc.)
   - For items not matching any existing bucket: group by spec/plan title keywords; if uncertain, create or extend an "## Misc / Untriaged" bucket
5. Classify each item's status:
   - ✅ Done: a commit referencing the item landed on the trunk branch (main/master)
   - 🔨 In Progress: an active `brainstorm/*` branch references it, or a spec/plan exists without a trunk merge
   - 📋 Backlog: spec exists but no implementation activity
6. Write the regenerated board to `Projects/<name>/board.md`:
   - **PRESERVE** these sections from the existing file (do not overwrite):
     - `## For future Claude` preamble
     - Frontmatter (just update `last-refresh:` timestamp and totals)
     - `## 🔥 This Week` section (manually maintained Now/Next/Later overlay)
     - `## 待辦` / `## 進行中` / `## 已完成` synthesis sections (if user has manually customized them; if they look auto-synthesized — see SYNTHESIZE rule below — re-synthesize on each refresh)
     - `## Patterns observed` section, if present (only re-compute totals)
     - `## Bucket summary` table (recompute counts)
   - **SYNTHESIZE if missing** — if any of `## 🔥 This Week`, `## 待辦`, `## 進行中`, `## 已完成` sections do NOT exist in the current board, ADD them at the top (after the preamble + horizontal rule, before the first topic bucket). Synthesize content from the regenerated topic buckets:
     - `## 🔥 This Week → Now (≤3)`: pick the 1–3 highest-priority In Progress items across all topic buckets (priority signal: most recent commit activity, or topic-bucket recency)
     - `## 🔥 This Week → Next`: items with a spec but no impl commits yet (effectively the first Backlog → Next promotion)
     - `## 🔥 This Week → Later`: remaining Backlog items
     - `## 待辦`: union of all 📋 Backlog from topic buckets (empty placeholder text if none)
     - `## 進行中`: union of all 🔨 In Progress from topic buckets, each item prefixed with `[<bucket-name>]`
     - `## 已完成 (本週)`: union of last 7 days of ✅ Done items from topic buckets (date-sorted desc)
   - **REGENERATE** the topic bucket sections (Done / In Progress / Backlog within each)
7. Append one line to `Logs/YYYY-MM-DD.md`:
   `**HH:MM** - board | <name> refreshed - N done, M in-flight, P backlog across K buckets`
8. Update `last-refresh:` timestamp in board frontmatter to now (for next incremental run)
9. Report a one-line summary to the caller (used by the daily-cron prompt to decide whether to post Discord notification - see Plan 2)

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
