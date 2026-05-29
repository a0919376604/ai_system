---
description: Pulse on a topic from HN, Reddit, Lobsters, dev.to - what builders are saying this week
category: research
triggers_en: ["discourse pulse", "what are people saying", "trending discussion"]
---

Use the obsidian-second-brain skill. Execute `/discourse-pulse $ARGUMENTS`:

The argument is the topic. Optional flag `--project=<name>` routes output into a project folder.

## Project routing

Without a project: write to default cross-project research folder (`Research/Pulse/YYYY-MM-DD-<slug>.md`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-pulse.md`.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, pulse]`.

1. Read `_CLAUDE.md`.

2. Run fetcher:

   ```bash
   uv run -m scripts.research.discourse_pulse "<topic>"
   ```

3. Parse JSON (same shape as `/research`).

4. Write to:
   - `Research/Pulse/YYYY-MM-DD-<slug>.md` (default, no project)
   - OR `Projects/<P>/Research/<slug>-pulse.md` (if `--project=<P>` was passed)

   Sections:
   - `## For future Claude` preamble
   - `## Hot Threads` - top 5-10 by `points` * recency, with source + URL
   - `## Key Voices` - recurring authors/handles across threads (cite their thread)
   - `## Counter-takes` - minority views in the comments
   - `## Post Angle Ideas` - 2-3 angles for a writeup based on what's missing in the discourse
   - `## Sources` - verbatim URLs

   Frontmatter `type: pulse`.

5. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
