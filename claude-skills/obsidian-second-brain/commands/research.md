---
description: Free-source web + academic research with citations - dossier saved to vault
category: research
triggers_en: ["research this", "look up", "find info on", "web research"]
---

Use the obsidian-second-brain skill. Execute `/research $ARGUMENTS`:

The argument is the research topic. Optional flag `--academic` restricts to arXiv / Semantic Scholar / OpenAlex / CrossRef only. Optional flag `--project=<name>` routes output into a project folder.

## Project routing

Without a project: write to default cross-project research folder (`Research/Web/YYYY-MM-DD-<slug>.md`; `Research/Academic/` if `--academic`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-web.md`.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, web]`.

1. Read `_CLAUDE.md` first if it exists in the vault root.

2. Run the Python fetcher (from the repo root `~/.claude/skills/obsidian-second-brain/`):

   ```bash
   uv run -m scripts.research.research "<topic>" [--academic]
   ```

3. Parse the stdout JSON. Shape:

   ```json
   {
     "topic": "...",
     "academic_mode": false,
     "results": [{ "source": "...", "title": "...", "url": "...", "snippet": "...", "abstract": "...", "authors": [...], "year": 2024, "points": 47, "comments": 12, "posted_at": "..."}, ...],
     "stats": {"sources_attempted": 6, "sources_succeeded": 5, "results_total": 38, "success": true},
     "warnings": [...]
   }
   ```

4. Synthesize an AI-first dossier from the JSON. Follow `references/ai-first-rules.md`. Sections:

   - `## For future Claude` preamble (2-3 sentences explaining what this note is, when researched, by what method)
   - `## Summary` (3-5 sentences, current state of the topic)
   - `## Key Facts` - each fact carries `(as of YYYY-MM, source-domain.com)` recency marker, source URL kept verbatim
   - `## Timeline` if temporally significant events exist
   - `## Key Players` - people/companies, role, why they matter
   - `## Contrarian Views` - counter-arguments with source attribution
   - `## Open Questions` - gaps the JSON didn't fill
   - `## Sources` - every URL from the JSON, deduped, grouped by source name

5. Save to:
   - `Research/Web/YYYY-MM-DD-<slug>.md` (default, no project; use `Research/Academic/` if `--academic`)
   - OR `Projects/<P>/Research/<slug>-web.md` (if `--project=<P>` was passed)

   Frontmatter:

   ```yaml
   ---
   date: YYYY-MM-DD
   type: research
   tags: [research, <slug-tag>, <source-tags>]
   topic: "<topic>"
   model: claude-via-self
   sources: [<all urls>]
   ai-first: true
   ---
   ```

6. Append a one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** - research | <topic> - N sources, saved to [[Research/Web/<file>]]
   ```

7. Update `index.md` Research section to include the new note.

8. If `stats.success` is false (fewer than 3 sources returned results), tell the user plainly and suggest a narrower or different query before saving.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` - `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval - not human reading.
