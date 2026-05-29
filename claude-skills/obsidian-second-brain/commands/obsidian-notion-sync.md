---
description: Sync a vault note (recap or decision) to Notion via MCP — auto-discovers/creates IDs, updates main page roadmap, appends DB entries
category: vault
triggers_en: ["sync to notion", "push to notion", "notion sync", "publish to notion"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-notion-sync $ARGUMENTS`:

The argument selects what to sync:
- `--recap <YYYY-WXX>` — sync the weekly recap file for that ISO week (default: most recent)
- `--decision <slug>` — sync a single ADR file by slug (file under `Projects/<P>/Decisions/`)
- `--all-pending` — find all unsynced notes (frontmatter `notion-synced: false` or missing) and sync each

A `--project=<name>` flag scopes which project's notes to sync. Defaults to `langlive-line-oa`.

## Project routing

Project resolves from `--project=<name>` flag, then vault `_CLAUDE.md` active project, then codebase CLAUDE.md. The project's `Projects/<name>/<name>.md` hub note is the source for Notion IDs (frontmatter `notion:` block).

## Modes

### Recap mode (`--recap`)

1. Resolve the recap file path: `Projects/<P>/Recaps/YYYY-WXX.md` (use most recent if `<YYYY-WXX>` not given)
2. Resolve Notion IDs via Patterns A and B (see Patterns block below):
   - **main_page_id**: read from hub frontmatter; if empty, search Notion for project title; if not found, create page at workspace root; persist id back to frontmatter
   - **weekly_recaps_db_id**: read from hub frontmatter; if empty, create database under main_page_id with properties (Week title, Period date, Shipped/Decisions/Learnings rich_text); persist id back
3. Parse the recap markdown. Extract:
   - Week label (frontmatter `week:`)
   - Period range (frontmatter `range:`)
   - Each section: `## Shipped`, `## In flight`, `## Decisions made`, `## Learnings`, `## Board diff`, `## Open questions for next week`
   - The Now/Next/Later snapshot from `Projects/<P>/<P>.md` `## 🔥 This Week` (this is what overwrites Notion main page)
4. Overwrite main page Current Roadmap (Pattern D):
   - Get main page block children
   - Find or create a `Current Roadmap` H2 heading
   - Replace all blocks between that heading and the next H1/H2 with new Now/Next/Later sections (Chinese, formatted as bulleted lists)
5. Append a new Weekly Recap database entry (Pattern E):
   - Properties: Week, Period, Shipped (rich text from recap section), Decisions (rich text + page links to Decisions Archive entries), Learnings (rich text)
   - Children: full recap body as blocks (preserve `## headings`)
6. Update the recap file frontmatter: `notion-synced: true`, `notion-page-url: <new page url>`
7. Append to today's `Logs/YYYY-MM-DD.md`: `**HH:MM** - notion-sync | recap W21 → main + db row, urls: <main_url>, <recap_url>`
8. Report: two Notion URLs (main page section + new DB row) and any errors

### Decision mode (`--decision`)

1. Resolve decision file path: `Projects/<P>/Decisions/<slug>.md`
2. Resolve Notion IDs via Patterns A and C:
   - main_page_id (as above)
   - **decisions_archive_page_id**: read from hub frontmatter; if empty, create sub-page under main_page_id titled "Decisions Archive"; persist id back
3. Parse the ADR markdown. Extract:
   - Title (from filename or frontmatter)
   - Sections: Subject, Options considered, Decision, Reasoning, What would change my mind, Related
4. Create a new sub-page under decisions_archive_page_id (Pattern F):
   - Title: `YYYY-MM-DD <slug>` (use the file's date prefix and a humanized slug)
   - Children: ADR content as blocks, preserving section structure
5. Update the ADR file frontmatter: `notion-synced: true`, `notion-page-url: <url>`
6. Append to today's `Logs/YYYY-MM-DD.md`: `**HH:MM** - notion-sync | decision <slug> → archive, url: <url>`
7. Report: Notion URL of the new archive entry

### All-pending mode (`--all-pending`)

1. Scan `Projects/<P>/{Recaps,Decisions}/*.md` for files where frontmatter `notion-synced` is missing or `false`
2. For each: run Recap mode or Decision mode depending on the path
3. Report a summary table: file → URL or error

## Patterns (Notion MCP call reference)

### Pattern A — Find or create main page

```
1. mcp__notion__API-post-search query="<project-name>" filter={"value":"page","property":"object"}
2. If exactly one match with title "<project-name>": use its id as main_page_id
3. If zero matches: mcp__notion__API-post-page parent={"workspace":true} properties={"title":[{"text":{"content":"<project-name>"}}]}
4. If multiple matches: ASK user which one (don't auto-pick)
5. Write the resolved id back to `Projects/<P>/<P>.md` frontmatter `notion.main_page_id`
```

### Pattern B — Find or create Weekly Recaps database

```
1. Read notion.weekly_recaps_db_id from hub frontmatter
2. If non-empty: use it; skip to step 5
3. If empty: mcp__notion__API-create-a-data-source
     parent_page_id=main_page_id
     title="Weekly Recaps"
     properties:
       Week: {title: {}}
       Period: {date: {}}
       Shipped: {rich_text: {}}
       Decisions: {rich_text: {}}
       Learnings: {rich_text: {}}
4. Write returned db_id back to frontmatter
5. Use db_id for subsequent calls
```

### Pattern C — Find or create Decisions Archive sub-page

```
1. Read notion.decisions_archive_page_id from hub frontmatter
2. If non-empty: use it; skip to step 5
3. If empty: mcp__notion__API-post-page parent={"page_id":main_page_id} title="Decisions Archive"
4. Write returned page_id back to frontmatter
5. Use page_id as parent for ADR sub-pages
```

### Pattern D — Overwrite Current Roadmap on main page

```
1. mcp__notion__API-get-block-children block_id=main_page_id
2. Find the block whose content is "Current Roadmap" heading (or create one if missing — append an H2 block)
3. For each subsequent block until next H1/H2: collect into blocks_to_delete
4. mcp__notion__API-delete-a-block for each in blocks_to_delete
5. mcp__notion__API-patch-block-children parent=main_page_id (after the heading) — append new Now/Next/Later sections from vault hub's `## 🔥 This Week`
```

### Pattern E — Append Weekly Recap entry

```
mcp__notion__API-post-page
  parent={"database_id":weekly_recaps_db_id}
  properties:
    Week: "2026 W21"
    Period: {"start":"2026-05-18","end":"2026-05-24"}
    Shipped: <rich text>
    Decisions: <rich text>
    Learnings: <rich text>
  children: <blocks for full Chinese recap body>
```

### Pattern F — Append a Decision Archive sub-page

```
mcp__notion__API-post-page
  parent={"page_id":decisions_archive_page_id}
  title="2026-05-25 選 Pinecone 不選 pgvector"
  children: <blocks: Subject / Options / Decision / Reasoning / What would change my mind>
```

## Idempotency

Before doing any Notion write, check the source file's frontmatter for `notion-synced: true`. If set, SKIP this sync (treat as already done). User can force re-sync with `--force` flag — when set, the previous `notion-page-url` is replaced rather than appended (for recaps) or a new archive page is added (for decisions, since archive is append-only).

## Error handling

If any MCP call fails:
- Log the error to today's `Logs/YYYY-MM-DD.md`
- Post a Discord message to `#langlive-line-oa`: `❌ Notion sync failed for <file>: <error>`
- Set frontmatter `notion-sync-error: <message>` on the source file so a retry can pick it up
- STOP — don't try to recover automatically

If a Notion ID resolves but the underlying page/db has been deleted (404 from a write):
- Treat the cached id as stale
- Re-run discovery from Patterns A/B/C
- If still 404 after re-discovery, ask the user

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
