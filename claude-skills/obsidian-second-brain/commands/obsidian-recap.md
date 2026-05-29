---
description: Summarize a time period from the vault — today, week, or month
category: vault
triggers_en: ["recap today", "recap the week", "summarize the week", "month recap"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-recap $ARGUMENTS`:

The argument is the period: `today`, `week`, or `month`. Default to `week` if not specified.

## Project routing

Without a project: vault-wide recap (default behavior - reads all daily notes).
With `--project=<name>` flag: project-scoped recap, output goes to `Projects/<name>/Recaps/YYYY-WXX.md` (ISO week number).

In project mode, also:
- Filter daily-note content to lines tagged or referencing the project
- Read `Projects/<name>/board.md` diff (compare `last-refresh:` boundaries to detect Now/Next/Later changes)
- Read `Projects/<name>/Decisions/` for any ADRs written in the period
- Read `Projects/<name>/Learnings/` for any captures in the period

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Determine the date range from the argument
3. List all daily notes in the range with `list_files_in_dir("Daily/")`
4. Spawn parallel subagents — one per daily note — to read and extract key points from each simultaneously
5. Also spawn parallel agents to read dev logs and completed kanban tasks from the same period
6. Synthesize all agent results: what was worked on, decisions made, people interacted with, tasks completed, ideas captured
7. Present as a clean narrative summary — not a raw dump of note content
8. **If `--project=<P>` was used**: save the synthesized recap to `Projects/<P>/Recaps/YYYY-WXX.md` (where WXX is the ISO week number - compute from the period start). Frontmatter:
   ```
   ---
   date: YYYY-MM-DD
   type: recap
   project: "[[<P>]]"
   period: "weekly"
   week: "YYYY-WXX"
   range: "YYYY-MM-DD to YYYY-MM-DD"
   ai-first: true
   ---
   ```
   Sections: `## For future Claude` preamble, `## Shipped`, `## In flight`, `## Decisions made`, `## Learnings`, `## Board diff (Now/Next/Later changes)`, `## Open questions for next week`.

   **If no `--project`**: save to `Reviews/YYYY-MM-DD - Weekly Review.md` (the original location).

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
