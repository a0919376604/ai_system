---
description: Surface 3-5 next-direction candidates by reading Ideas/, Project Open Questions, and orphan Research notes
category: research
triggers_en: ["what should I work on next", "idea discovery", "what are my gaps"]
---

Use the obsidian-second-brain skill. Execute `/idea-discovery $ARGUMENTS`:

The argument is optional. If given, use it as seed direction (filter scope).

1. Read `_CLAUDE.md`.

2. **Vault scan** (you do this):
   - Read all `Ideas/*.md` where `status != graduated`
   - Read all `Projects/*.md` and extract the **Open Questions** sections
   - Read `Research/**/*.md` and find ones with no matching `Projects/` note (orphan research)

3. Form a candidate list - each candidate is one of:
   - An ungraduated idea
   - An open question in an active project
   - An orphan research note that suggests a project

4. **External quick scan** - for each candidate (up to 5), pick a 3-8 word query and run:

   ```bash
   uv run -m scripts.research.idea_discovery "<candidate 1>" "<candidate 2>" ...
   ```

5. Parse JSON. Shape:
   ```json
   {"gaps": ["..."], "per_gap": [{"topic": "...", "results": [...], "stats": {...}}, ...]}
   ```

6. **Rank** by a simple heuristic:
   - Score = (recency-of-last-vault-touch) × (orphan_research_count) × (signal-from-external-scan: n_arxiv_results + n_hn_results)
   - Top 3-5 get included.

7. Write `Ideas/YYYY-MM-DD-discovery.md` with:
   - `## For future Claude` preamble
   - `## Top 3-5 Next Directions` - each: title, rationale (why this gap matters now), vault refs (`[[wikilinks]]`), external signal (1-2 cited results), suggested next action (research / graduate / discuss)
   - `## Other Candidates Considered` - short list with rejection reason
   - `## Method` - your scan window, ranking heuristic snapshot

   Frontmatter `type: idea-discovery`.

8. **Do NOT auto-graduate.** Wait for user explicit `/obsidian-graduate <name>`.

9. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
