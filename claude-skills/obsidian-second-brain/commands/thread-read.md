---
description: Read a single HN or Reddit thread, summarize OP + top arguments
category: research
triggers_en: ["read thread", "summarize this thread", "what's in this discussion"]
---

Use the obsidian-second-brain skill. Execute `/thread-read $ARGUMENTS`:

The argument is the thread URL. Optional flag `--project=<name>` routes output into a project folder.

## Project routing

Without a project: write to default cross-project research folder (`Research/Threads/YYYY-MM-DD-<slug>.md`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-thread.md`.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, thread]`.

1. Read `_CLAUDE.md`.

2. Run fetcher:

   ```bash
   uv run -m scripts.research.thread_read "<url>"
   ```

3. Parse JSON. Shape: `{"url": "...", "host": "hackernews|reddit", "data": <raw>}`.

4. Write to:
   - `Research/Threads/YYYY-MM-DD-<slug>.md` (default, no project)
   - OR `Projects/<P>/Research/<slug>-thread.md` (if `--project=<P>` was passed)

   Contents:
   - `## For future Claude` preamble (note the source URL prominently)
   - `## OP Summary` - TL;DR of the OP
   - `## Top Arguments` - 3-5 grouped by stance, each with verbatim quote + commenter handle
   - `## Notable Counter-takes` - minority views worth knowing
   - `## Sources` - original URL + each cited comment permalink

   Frontmatter `type: thread`.

5. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
