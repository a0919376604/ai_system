---
description: Extract transcript + metadata from a YouTube URL, summarize, save to vault
category: research
triggers_en: ["youtube video", "summarize this video", "yt extract"]
---

Use the obsidian-second-brain skill. Execute `/youtube $ARGUMENTS`:

The argument is the YouTube URL. Optional flag `--project=<name>` routes output into a project folder.

## Project routing

Without a project: write to default cross-project research folder (`Research/YouTube/YYYY-MM-DD-<slug>.md`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-yt.md`.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, yt]`.

1. Read `_CLAUDE.md`.

2. Run fetcher (no API key required):

   ```bash
   uv run -m scripts.research.youtube_extract "<url>"
   ```

3. Parse JSON. Shape:
   ```json
   {
     "video_id": "...",
     "url": "...",
     "metadata": {"title": "...", "channel": "...", "published_at": "...", "view_count": 12345, "description": "..."},
     "transcript": [{"text": "...", "start": 0.0, "duration": 1.5}, ...],
     "transcript_available": true
   }
   ```

4. If `transcript_available: false`, write a stub note with metadata only + frontmatter flag `transcript-available: false` + tell the user.

5. Otherwise, synthesize from the transcript:
   - `## For future Claude` preamble (with `[[wikilink]]` to channel if known)
   - `## Summary` - 5-7 sentence summary
   - `## Key Topics Covered` - bullet list grouped by approximate timestamps from transcript
   - `## Notable Quotes` - 3-5 verbatim quotes with timestamps
   - `## Action Items / Ideas` - what's actionable for the user (link to relevant `[[Projects/]]` if any)
   - `## Metadata` - verbatim from the JSON (title, channel, published, views)
   - `## Sources` - the YouTube URL

   Frontmatter `type: youtube` + `transcript-available: true`.

6. Save to:
   - `Research/YouTube/YYYY-MM-DD-<slug>.md` (default, no project)
   - OR `Projects/<P>/Research/<slug>-yt.md` (if `--project=<P>` was passed)

7. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
