---
description: Vault-first deep research — Claude scans vault, identifies gaps, fetches per-gap free sources, synthesizes delta, propagates updates (renamed from /research-deep in v4.5)
argument-hint: <repo> <topic>
category: research
triggers_en: ["deep research", "thorough research", "vault-first research", "obsidian research deep"]
param-autocomplete:
  - name: repo
    source: vault-projects-plus-global
  - name: topic
    source: freetext
---

Use the obsidian-second-brain skill. Execute `/obsidian-research-deep $ARGUMENTS`:

The first positional argument is `<repo>` — accepts (a) a project name, (b) an absolute path matching a hub's `local-path` frontmatter, or (c) the sentinel `global` (also `_` or `-`) for vault-wide research. The rest is the research topic.

## Phase 0: Resolve <repo>

Parse the first token; call `scripts.commands.repo_resolver.resolve_repo_arg(token, vault_root, allow_global=True)`.

```python
import shlex
tokens = shlex.split(args, posix=True)
if len(tokens) < 2:
    abort("missing arguments. Usage: /obsidian-research-deep <repo> <topic>")
repo_token = tokens[0]
topic = " ".join(tokens[1:])

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
elif resolution.state == "unknown":
    abort(resolution.message)
```

## Output routing

When `state == "global"`: write to `Research/Deep/YYYY-MM-DD-<slug>.md`.
When `state == "project"`: write to `Projects/<P>/Research/<slug>-deep.md`.

## Phases 1-4 (unchanged from /research-deep)

1. Read `_CLAUDE.md` first.

2. **Phase 1 — vault baseline:**
   - Search `Research/`, `Projects/`, `Knowledge/`, `Ideas/` for any note mentioning the topic
   - List what's already known vs unknown
   - List wikilinks pointing into the topic from elsewhere

3. **Phase 2 — gap analysis:**
   - Based on baseline, formulate 3-5 specific sub-queries that would fill the gaps
   - Each 3-8 words, retrieval-friendly
   - At least one academic-leaning + one discourse-leaning when relevant

4. **Phase 3 — fetch:**
   ```bash
   uv run -m scripts.research.research_deep "<sub-q1>" "<sub-q2>" "<sub-q3>" ...
   ```

5. Parse stdout JSON:
   ```json
   {
     "sub_queries": ["...", "...", "..."],
     "per_query": [
       {"topic": "...", "results": [...], "stats": {...}, "warnings": [...]},
       ...
     ]
   }
   ```

6. **Phase 4 — synthesize delta** and save:
   - `Research/Deep/YYYY-MM-DD-<slug>.md` (state=global)
   - `Projects/<P>/Research/<slug>-deep.md` (state=project)

   Frontmatter when project-scoped includes `project: "[[<project_slug>]]"`.

7. Append one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** — research-deep | <topic> — N sub-queries, M total sources, saved to [[<file>]]
   ```

8. If propagation needed (decisions/ADRs/learnings/ideas surfaced from findings), follow `references/ai-first-rules.md` propagation chain.

---

**AI-first rule:** Same as /obsidian-research — `## For future Claude` preamble, rich frontmatter, recency markers, mandatory wikilinks, sources verbatim.
