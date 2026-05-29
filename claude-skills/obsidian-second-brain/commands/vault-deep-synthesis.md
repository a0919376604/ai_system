---
description: Cross-vault synthesis on a topic - reads all matching notes, cross-references, writes unified view
category: research
triggers_en: ["vault synthesis", "what does my vault say about", "synthesize what I know"]
---

Use the obsidian-second-brain skill. Execute `/vault-deep-synthesis $ARGUMENTS`:

The argument is the topic. NO external network call. NO Python script. Pure vault operation.

1. Read `_CLAUDE.md`.

2. Grep the vault for all notes mentioning the topic (case-insensitive). Scan `Research/`, `Knowledge/`, `Projects/`, `Ideas/`, `Logs/`, `Decisions/`, `People/`.

3. Read each matching note in full.

4. Cross-reference:
   - Which notes claim the same fact but differ in detail? List the discrepancies.
   - Which claims repeat across multiple notes (high confidence)?
   - Which claims appear only once (isolated)?
   - Are any claims clearly stale (older `(as of YYYY-MM)` markers)?

5. Write `Knowledge/YYYY-MM-DD-synthesis-<slug>.md` with:
   - `## For future Claude` preamble
   - `## Unified View` - the integrated picture
   - `## Cross-Note Agreements` - high-confidence consensus claims
   - `## Contradictions` - list the conflicts with `[[wikilinks]]` to both sides
   - `## Stale Claims Flagged` - claims with old recency markers that should be re-verified
   - `## Coverage Gaps` - what the vault doesn't say
   - `## Source Notes` - every input note as `[[wikilink]]`

   Frontmatter `type: synthesis`.

6. **Do NOT mutate any existing note.** Synthesis is a derivative; provenance stays in the originals.

7. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
