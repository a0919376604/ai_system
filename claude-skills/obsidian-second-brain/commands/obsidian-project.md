---
description: Create or update a project note — adds to board and daily note automatically
category: vault
triggers_en: ["new project", "create project note", "project setup", "start a project"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-project $ARGUMENTS`:

The argument is a project name. Handle typos and partial matches.

## Project routing

Creating a project ALWAYS uses the sub-folder layout - there is no flat-mode for new projects.

Created structure:
- `Projects/<project-name>/<project-name>.md` (hub note)
- `Projects/<project-name>/board.md` (kanban board, using the same template as `/obsidian-graduate`)
- `Projects/<project-name>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` (empty skeleton folders)

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Search the vault for an existing project matching the name (fuzzy - handle typos)
3. If found: show what was found, confirm with user, then update with new info from conversation
4. If not found: create `Projects/<project-name>/<project-name>.md` (with the sub-folder skeleton `Projects/<project-name>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/`) and full frontmatter schema (`date`, `tags: [project]`, `status: active`, `job`, `notion: { main_page_id: "", weekly_recaps_db_id: "", decisions_archive_page_id: "" }`, `local-path: ""`)
5. Fill in everything inferable from the conversation: description, goals, key people, current status
6. Add a card to `Projects/<project-name>/board.md` in the `## 待辦` section (creating the board file via the same template as `/obsidian-graduate` if it doesn't exist)
7. Link from today's daily note

If the name has a typo or is approximate, search the vault, show what was found, and confirm before proceeding. Never silently create a note with a misspelled name.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
