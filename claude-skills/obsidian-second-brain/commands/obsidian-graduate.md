---
description: Promote an idea fragment into a full project spec with tasks, board entries, and structure
category: thinking
triggers_en: ["promote idea", "graduate this to project", "make a project from this", "elevate idea"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-graduate $ARGUMENTS`:

The optional argument is the idea title, tag, or keyword. If not provided, scan recent notes for ideas tagged `#idea` or in the `Ideas/` folder and present them for selection.

## Project routing

The project name comes from `$ARGUMENTS` (if it's a project name) or is inferred from the idea title. Once resolved, graduate ALWAYS uses the sub-folder layout - there is no flat-mode for new projects.

Created structure:
- `Projects/<P>/<P>.md` (hub note)
- `Projects/<P>/board.md` (kanban; created with empty Now/Next/Later sections + a `## 待辦` section)
- `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` (empty skeleton folders)

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Find the idea to graduate:
   - If argument given: search `Ideas/`, daily notes, and captures for a matching idea (fuzzy match)
   - If no argument: list recent ideas (last 14 days) and ask the user to pick one
3. Read the full idea note and any linked notes for context
4. Research the vault for related content:
   - Existing projects that overlap
   - People who were mentioned in connection with this idea
   - Past decisions that relate
   - Similar ideas that were previously explored (to avoid reinventing)
5. Generate a full project spec:
   - **Hub note** at `Projects/<P>/<P>.md` with complete frontmatter (`date`, `tags: [project]`, `status: planning`, `linked-idea: [[<idea-title>]]`, `notion: { main_page_id: "", weekly_recaps_db_id: "", decisions_archive_page_id: "" }`, `local-path: "<TBD - ask user>"`)
   - **Description**: what this project is and why it matters
   - **Goals**: 3-5 concrete outcomes
   - **Open Questions**: what still needs answering
   - **Related notes**: links to everything relevant found in step 4
   - **Sub-folder skeleton**: create `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` and add a `.gitkeep` in each
6. Create the project's board:
   - Create `Projects/<P>/board.md` with a `For future Claude` preamble, frontmatter (`type: board`, `project: "[[<P>]]"`, `ai-first: true`), and skeleton sections:
     ```
     ## 🔥 This Week
     ### Now (≤3)
     ### Next
     ### Later

     ## 待辦

     ## 進行中

     ## 已完成
     ```
   - The board's topic buckets (UI / UX / KB / Performance, etc.) populate later via `/obsidian-board <P> --refresh` once the project accumulates work.
7. Update the original idea note:
   - Add `status: graduated` to frontmatter
   - Add a link to the new project note
8. Link the new project from today's daily note
9. Report: what was created, what was linked, what needs the user's input

The idea doesn't die — it evolves. The original note stays as the origin story, the project note becomes the execution plan.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
