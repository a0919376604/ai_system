---
description: Generate a decision record when the vault structure changes — the vault knows why it knows what it does
category: thinking
triggers_en: ["log this decision", "ADR", "record decision", "decision record"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-adr $ARGUMENTS`:

The optional argument is the decision topic, with optional flag `--project=<name>`. If not provided, infer from recent conversation context.

## Project routing

ADRs are project-scoped. Resolve project name in priority: (1) `--project=<name>` in `$ARGUMENTS`; (2) vault `_CLAUDE.md` active project; (3) codebase CLAUDE.md. If none resolves: ASK the user — never default to `Knowledge/` (legacy) or root.

Target: `Projects/<P>/Decisions/YYYY-MM-DD-<slug>.md`

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Identify the structural decision:
   - From the argument, or from recent conversation (e.g., a project was graduated, a folder was reorganized, a new convention was adopted, a concept was promoted to hub status)
3. Create a decision record at `Projects/<P>/Decisions/YYYY-MM-DD-<slug>.md`:

   (Where `<P>` is the resolved project name — see Project routing block above.
   If no project resolves, ASK the user which project — never write ADRs to root.)

   ```yaml
   ---
   date: YYYY-MM-DD
   type: decision
   project: "[[<P>]]"
   tags:
     - decision-record
   status: accepted
   ai-first: true
   ---
   ```

   Structure:
   - **Decision**: one-line summary of what was decided
   - **Context**: what prompted this decision — the problem or trigger
   - **Options Considered**: 2-3 alternatives that were evaluated
   - **Rationale**: why this option was chosen over the others
   - **Consequences**: what changes as a result — what notes were created, moved, or restructured
   - **What would change my mind**: the falsification condition — what evidence would make us reverse this decision. Without this, the ADR is belief; with it, it's a testable hypothesis.
   - **Related**: links to affected project notes, people, or ideas

4. Append to the resolved project hub's `## Key Decisions` section (`Projects/<P>/<P>.md`) with a one-line entry: `- YYYY-MM-DD [[<adr-title>]] — <one-line summary>`
5. Update `index.md` with the new ADR
6. Append to the operation log: if `Logs/` exists write `**HH:MM** - adr | Title - decision recorded` to `Logs/YYYY-MM-DD.md`; otherwise append `## [YYYY-MM-DD] adr | Title — decision recorded` to `log.md`
7. Link from today's daily note

Decision records prevent the vault from becoming a black box. When the user (or a future Claude session) asks "why is the vault structured this way?" — the ADR has the answer.

This command can also be triggered automatically by other commands: when `/obsidian-graduate` promotes an idea, when `/obsidian-health` recommends a structural fix, or when the user reorganizes folders. In those cases, offer to create an ADR — don't force it.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
