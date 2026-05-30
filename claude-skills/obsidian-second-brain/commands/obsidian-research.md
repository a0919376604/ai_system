---
description: Free-source web + academic research with citations — dossier saved to vault (renamed from /research in v4.5)
argument-hint: <repo> <topic>
category: research
triggers_en: ["research this", "look up", "find info on", "web research", "obsidian research"]
param-autocomplete:
  - name: repo
    source: vault-projects-plus-global
  - name: topic
    source: freetext
---

Use the obsidian-second-brain skill. Execute `/obsidian-research $ARGUMENTS`:

The first positional argument is `<repo>` — accepts (a) a project name like `langlive-line-oa`, (b) an absolute path that matches a project hub's `local-path` frontmatter, or (c) the sentinel `global` (also `_` or `-`) for vault-wide research. The rest of `$ARGUMENTS` is the research topic. Optional flag `--academic` restricts to arXiv / Semantic Scholar / OpenAlex / CrossRef only.

## Phase 0: Resolve <repo>

Parse the first whitespace-delimited token from `$ARGUMENTS`:

```python
import shlex
tokens = shlex.split(args, posix=True)
if len(tokens) < 2:
    abort("missing arguments. Usage: /obsidian-research <repo> <topic> [--academic]")
repo_token = tokens[0]
remaining = " ".join(tokens[1:])

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=True,
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "global":
    project_dir = None
    project_slug = None
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
    # After user picks, re-resolve with the picked name as repo_token.
elif resolution.state == "unknown":
    abort(resolution.message)

# remaining is now the topic + optional flags.
```

## Output routing

When `state == "global"` (sentinel was given): write to vault-wide `Research/Web/YYYY-MM-DD-<slug>.md` (or `Research/Academic/` if `--academic`).

When `state == "project"`: write to `Projects/<project_slug>/Research/<slug>-web.md`.

Frontmatter additions when project-scoped: `project: "[[<project_slug>]]"` and `tags: [research, <project_slug>, web]`.

## Phase 1 onward (unchanged from /research)

1. Read `_CLAUDE.md` first if it exists in the vault root.

2. Run the Python fetcher:
   ```bash
   uv run -m scripts.research.research "<topic>" [--academic]
   ```

3. Parse the stdout JSON. Shape:
   ```json
   {
     "topic": "...",
     "academic_mode": false,
     "results": [{"source": "...", "title": "...", "url": "...", "snippet": "...", "abstract": "...", "authors": [...], "year": 2024, "points": 47, "comments": 12, "posted_at": "..."}, ...],
     "stats": {"sources_attempted": 6, "sources_succeeded": 5, "results_total": 38, "success": true},
     "warnings": []
   }
   ```

4. Synthesize an AI-first dossier. Sections:
   - `## For future Claude` preamble
   - `## Summary` (3-5 sentences)
   - `## Key Facts` with `(as of YYYY-MM, source-domain.com)` recency markers
   - `## Timeline` (if temporally significant)
   - `## Key Players`
   - `## Contrarian Views`
   - `## Open Questions`
   - `## Sources` (every URL, deduped, grouped by source name)

5. Save to:
   - `Research/Web/YYYY-MM-DD-<slug>.md` (state=global, no --academic)
   - `Research/Academic/YYYY-MM-DD-<slug>.md` (state=global, --academic)
   - `Projects/<P>/Research/<slug>-web.md` (state=project)

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

   When `state=project`, add `project: "[[<project_slug>]]"` to frontmatter.

6. Append one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** — research | <topic> — N sources, saved to [[Research/Web/<file>]]
   ```

7. Update `index.md` Research section.

8. If `stats.success` is false (< 3 sources returned), tell user plainly and suggest a narrower query before saving.

---

**AI-first rule:** Every note follows `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter, recency markers, mandatory `[[wikilinks]]`, sources verbatim with URLs inline, confidence levels.
