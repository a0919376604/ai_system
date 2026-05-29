---
description: Add a task to the right kanban board with inferred priority and due date
category: vault
triggers_en: ["add task", "new todo", "track this", "remind me"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-task $ARGUMENTS`:

The optional argument is the task description, with optional flags (`--project=<name>`, `--due=YYYY-MM-DD`, `--priority=🔴|🟡|🟢`).

## Project routing

Tasks are always project-scoped. Resolve project name from `$ARGUMENTS` (`--project=<name>`), then from vault `_CLAUDE.md` `## Active main project`, then from codebase CLAUDE.md. If unresolvable, ASK the user — do not write to a default location.

Target paths:
- Task note: `Projects/<P>/Tasks/T-<seq>-<slug>.md` (where `<seq>` is the next zero-padded sequence number from existing tasks in that folder; e.g., `T-007-add-rag-context.md`)
- Board card: appended to `Projects/<P>/board.md` `## 待辦` section, linking the task note

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Parse the task from the argument, or pull from recent conversation context if no argument given
3. Infer: priority (🔴/🟡/🟢), due date, linked project, linked person
4. Resolve project (see Project routing above)
5. Compute next task sequence: `ls Projects/<P>/Tasks/T-*.md 2>/dev/null | sort | tail -1` → increment the number; if none, start at `T-001`
6. Add the task card to `Projects/<P>/board.md` `## 待辦` section (or `## 🔥 This Week` → `### Next` if the user signals urgency)
7. Create the task note at `Projects/<P>/Tasks/T-<seq>-<slug>.md` if the task is substantial (more than a one-liner). Use this frontmatter:
   ```
   ---
   date: YYYY-MM-DD
   type: task
   project: "[[<P>]]"
   status: backlog
   priority: 🔴|🟡|🟢
   due: YYYY-MM-DD or null
   spec_path: ""        # filled by Checkpoint 1 after superpowers/brainstorming runs
   ai-first: true
   ---
   ```
8. Link the task from the relevant project note and today's daily note

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
