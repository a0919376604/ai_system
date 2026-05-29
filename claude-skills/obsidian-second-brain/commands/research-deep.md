---
description: Vault-first deep research - Claude scans vault, identifies gaps, fetches per-gap free sources, synthesizes a delta, propagates updates
category: research
triggers_en: ["deep research", "thorough research", "vault-first research"]
---

Use the obsidian-second-brain skill. Execute `/research-deep $ARGUMENTS`:

The argument is the topic. Optional flag `--project=<name>` routes output into a project folder.

## Project routing

Without a project: write to default cross-project research folder (`Research/Deep/YYYY-MM-DD-<slug>.md`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-deep.md`.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, deep]`.

1. Read `_CLAUDE.md` first.

2. **Phase 1 - vault baseline** (you do this directly, no script):
   - Search `Research/`, `Projects/`, `Knowledge/`, `Ideas/` for any note mentioning the topic
   - List what's already known vs unknown
   - List wikilinks pointing into the topic from elsewhere

3. **Phase 2 - gap analysis** (you reason directly):
   - Based on the baseline, formulate 3-5 specific sub-queries that would fill the gaps
   - Each sub-query should be 3-8 words, retrieval-friendly
   - Make at least one academic-leaning and one discourse-leaning if both are relevant

4. **Phase 3 - fetch** (run the Python fetcher):

   ```bash
   uv run -m scripts.research.research_deep "<sub-q1>" "<sub-q2>" "<sub-q3>" ...
   ```

5. Parse stdout JSON. Shape:

   ```json
   {
     "sub_queries": ["...", "...", "..."],
     "per_query": [
       { "topic": "...", "results": [...], "stats": {...}, "warnings": [...] },
       ...
     ]
   }
   ```

6. **Phase 4 - synthesize delta** and save to:
   - `Research/Deep/YYYY-MM-DD-<slug>.md` (default, no project)
   - OR `Projects/<P>/Research/<slug>-deep.md` (if `--project=<P>` was passed)

   Sections:

   - `## For future Claude` preamble
   - `## Vault Baseline` - what we already knew (with `[[wikilinks]]` to existing notes)
   - `## Gap Queries` - the 3-5 sub-queries you generated and why
   - `## New Findings` - grouped per sub-query, each finding with recency marker + source
   - `## Confirmed` - things the new fetch confirmed about the baseline
   - `## Contradictions` - places where new findings conflict with vault baseline (flag for user attention)
   - `## Recommended Vault Updates` - bullet list of: "Update [[Projects/X]] Open Questions to add ..."
   - `## Open Questions` - what's still not filled
   - `## Sources` - every URL deduped

   Frontmatter:
   ```yaml
   ---
   date: YYYY-MM-DD
   type: research-deep
   tags: [research, deep, <slug-tag>]
   topic: "<topic>"
   model: claude-via-self
   sources: [<all urls>]
   ai-first: true
   ---
   ```

7. **Propagation** - after the deep note is saved, dispatch parallel sub-agents (one per People / Projects / Tasks / Decisions / Ideas) to apply each "Recommended Vault Update" bullet. Each update follows AI-first rules. Treat the deep note's body as the conversation context input.

8. Append `Logs/YYYY-MM-DD.md` entry and update `index.md`.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md`.
