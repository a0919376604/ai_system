---
description: Show or update a kanban board — flags overdue items, updates from conversation
category: vault
triggers_en: ["show board", "kanban", "what is on my board", "update board"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-board $ARGUMENTS`:

The first argument is a board name (project name). Optional second flag: `--refresh` (regenerate from git history) or `--full` (force full rebuild, default is incremental). Without `--refresh`, this is interactive: read the board and ask what changes to make.

## Project routing

The board name resolves to a project. Boards always live at `Projects/<name>/board.md` (the legacy `Boards/<name>.md` flat location is no longer used - migrate if found).

To locate the codebase for `--refresh`: read `Projects/<name>/<name>.md` frontmatter for `local-path:`. If missing, ask the user once and persist it back to the frontmatter.

## Modes

### Interactive mode (no `--refresh`)

1. Read `_CLAUDE.md` first if it exists in the vault root
2. If a board name is given, look for `Projects/<name>/board.md`; if not found, search `Projects/*/board.md` (fuzzy match)
3. If no name given, list available boards (one per `Projects/*/board.md`) and ask which one
4. Read and display the current board state: 🔥 This Week (Now/Next/Later), 待辦, 進行中, 已完成, plus any topic buckets
5. Ask if the user wants to make updates - if yes, infer changes from conversation context
6. Move completed items to ✅ 已完成 with strikethrough, add new items in the right column
7. Flag any items that are overdue (`@{date}` past) or stuck (in same column > 1 week per `last-moved:` timestamp)

### Refresh mode (`--refresh` flag set)

The deterministic refresh logic is implemented in `scripts/board/refresh.py:refresh_board()`. Invocation:

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument. Usage: /obsidian-board <repo> --refresh [--full]")
repo_token = tokens[0]
flags = tokens[1:]

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=False,
)
if resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state != "project":
    abort(resolution.message)

from scripts.board.refresh import refresh_board
result = refresh_board(
    project_dir=resolution.project_dir,
    signals=None,
    full=("--full" in flags),
)

if result.status == "skipped":
    print(result.message)
    return  # nothing to do
```

After helper returns:

1. Append activity log line to `Logs/YYYY-MM-DD.md ## Activity` (idempotent - only if today's log doesn't already have a matching `**HH:MM** - board | <P> refreshed` line for the same minute):
   ```
   **HH:MM** - board | <P> refreshed - <done> done, <in-flight> in-flight, <backlog> backlog across <N> buckets
   ```

2. Return a one-line summary to the caller (used by cron Discord notification):
   `board refreshed | <P> | <done>D <in-flight>P <backlog>B | <N> buckets`

3. The LLM (Claude executing this command body) is then responsible for regenerating the topic-bucket body sections in `board.md` based on `result.new_items` and `result.buckets`. The helper has already updated frontmatter `last-refresh` + totals; the LLM step is purely about prose-level reformatting of the bucket bodies (preserving the SYNTHESIZE rule for `## 🔥 This Week` / `## 待辦` / `## 進行中` / `## 已完成` if those sections don't exist yet).

If `--full` flag was passed, force full rebuild ignoring last-refresh. The helper handles this via its `full=True` parameter.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
