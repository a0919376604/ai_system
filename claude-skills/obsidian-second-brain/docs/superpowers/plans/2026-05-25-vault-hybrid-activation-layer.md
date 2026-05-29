# Vault Hybrid Activation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the langlive-line-oa knowledge pipeline on top of the Plan 1 foundation: create a `/obsidian-notion-sync` slash command for MCP-based Notion writes, schedule two crons (Mon-Fri 09:00 board refresh + Saturday 12:00 weekly recap), and dry-run the full pipeline end-to-end. Covers Phases 5-7 of `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md`.

**Architecture:** A new `/obsidian-notion-sync` slash command wraps the Notion MCP calls (auto-discover/create main page + Weekly Recaps DB + Decisions Archive, then write/append). Two **macOS launchd** routines (NOT `/schedule` — see amendment below): a lightweight Mon-Fri 09:00 board refresh that runs `/obsidian-board langlive-line-oa --refresh` and posts a one-line Discord summary on change; a Saturday 12:00 weekly-recap pipeline that runs `/obsidian-recap --project=langlive-line-oa --weekly`, translates the recap to Chinese, posts to Discord channel, and (on `ok` reply) calls `/obsidian-notion-sync` to push Current Roadmap + Weekly Recap entry to Notion. Reply handling uses the claude-discord plugin's channel-watch behavior — user replies trigger downstream sync in a follow-up Claude session.

**Architecture amendment (2026-05-25 mid-execution):** Originally designed around `/schedule` (Anthropic Cloud remote agents), but those agents have NO access to the user's local vault (`~/Documents/SecondBrain`) and NO access to local MCP servers (Notion MCP + claude-discord plugin are installed locally on the user's Mac). Switched to **macOS launchd** so the cron-fired Claude session runs locally with full access to vault + local MCP. User confirmed their Mac is awake at the relevant times (Mon-Fri 09:00 + Sat 12:00 = working hours).

**Tech Stack:** macOS launchd (`.plist` in `~/Library/LaunchAgents/`), Claude Code CLI (`claude -p`) for headless prompt execution, claude-discord plugin (`react`, `reply`, `fetch_messages`, `edit_message`), Notion MCP (`mcp__notion__API-post-search`, `mcp__notion__API-post-page`, `mcp__notion__API-patch-block-children`, `mcp__notion__API-create-a-data-source`, `mcp__notion__API-query-data-source`), Markdown slash-command prompts, shell scripts for launchd → Claude bridging.

**Prerequisites:**
- Plan 1 COMPLETE — vault is at hybrid layout, 14 commands routed, CLAUDE.md rules in place
- `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md` has `notion: { ... }` block with empty IDs
- Discord bot configured for `#langlive-line-oa` channel (confirmed by user)
- Notion MCP available in Claude sessions (confirmed by deferred tool list)

---

## File Structure

### Files created (in repo `commands/`)

- `commands/obsidian-notion-sync.md` — new slash command for MCP-based Notion writes
- (optional) `commands/obsidian-notion-sync-decision.md` — variant for ADR-to-Decisions-Archive sync, OR a `--mode` flag on the main command

### Files modified

- `CHANGELOG.md` — Unreleased section, document the new command + crons

### Files created (in repo `scripts/cron/`)

- `scripts/cron/board-refresh-prompt.txt` — the prompt passed to `claude -p` by the daily launchd trigger
- `scripts/cron/weekly-recap-prompt.txt` — the prompt passed to `claude -p` by the Saturday launchd trigger
- `scripts/cron/trigger-board-refresh.sh` — wrapper script (sets cwd, env, pipes prompt to `claude -p`)
- `scripts/cron/trigger-weekly-recap.sh` — same shape, for Saturday recap

### Files created outside the repo

- 2 launchd plists in `~/Library/LaunchAgents/`:
  - `com.langlive.board-refresh.plist` (Mon-Fri 09:00 local time)
  - `com.langlive.weekly-recap.plist` (Saturday 12:00 local time)
- Notion structure (auto-created by first runs):
  - Main page `langlive-line-oa` — **EXISTS** as of 2026-05-25 (id `36a5749a-ca1c-8142-b05b-f3ff80b712cf`, parent: a Notion database row in the user's Project Tracker)
  - Weekly Recaps database (auto-create on first run as child of main page)
  - Decisions Archive sub-page (auto-create on first ADR sync)

### Files NOT modified

- Anything in vault: the hub frontmatter Notion IDs get filled by `/obsidian-notion-sync` at runtime, not by this plan's steps
- Other slash commands

---

## Notion MCP call patterns (reference for Task 1)

This section is a quick reference. Tasks below cite it.

### Pattern A — Find or create main page

```
1. mcp__notion__API-post-search query="langlive-line-oa" filter={"value":"page","property":"object"}
   → returns matching pages
2. If exactly one match with title "langlive-line-oa": use its id as main_page_id
3. If zero matches: mcp__notion__API-post-page parent={"workspace":true} properties={"title":[{"text":{"content":"langlive-line-oa"}}]}
   → returns new page id
4. If multiple matches: ASK user which one (don't auto-pick)
5. Write the resolved id back to ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md frontmatter notion.main_page_id
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
2. Find the block whose content is "Current Roadmap" (or create one if missing — append a heading block)
3. For each subsequent block until next H1/H2: collect into "blocks_to_delete"
4. mcp__notion__API-delete-a-block for each in blocks_to_delete
5. mcp__notion__API-patch-block-children parent=main_page_id (or the heading block) — append new Now/Next/Later sections from vault hub's ## 🔥 This Week
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

---

## Phase 5 — Notion structure verification

### Task 1: Verify Notion main page or document its creation

**Files:**
- Read: `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md` frontmatter

- [ ] **Step 1: Check vault frontmatter for an existing `notion.main_page_id`**

```bash
grep -A 5 "^notion:" ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md
```

Expected: shows `notion:` block with all three IDs empty (from Plan 1 Task 6).

- [ ] **Step 2: Search Notion for an existing `langlive-line-oa` page**

In a Claude session with Notion MCP available, run:

```
mcp__notion__API-post-search with query="langlive-line-oa" filter={"value":"page","property":"object"}
```

- [ ] **Step 3: Three outcomes**

| Result | Action |
|---|---|
| Exactly one page found titled "langlive-line-oa" | Use it; record id. **No file edit yet** — `/obsidian-notion-sync` (Task 2) will persist it on first sync. |
| Zero pages | Document: first cron run will auto-create at workspace root via Pattern A step 3. Acceptable. |
| Multiple pages | STOP. Ask the user which to use (resolves manually before crons fire). |

- [ ] **Step 4: Document the chosen path in the spec's Open Questions** if Step 3 hit the "multiple" branch.

- [ ] **Step 5: No commit** — this is verification only.

## Phase 6 — Author `/obsidian-notion-sync` slash command

### Task 2: Create `commands/obsidian-notion-sync.md`

**Files:**
- Create: `commands/obsidian-notion-sync.md`

- [ ] **Step 1: Create the command file**

Write the following content to `/Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-notion-sync.md`:

```markdown
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
2. Resolve Notion IDs via Patterns A and B (see spec Part 6 reference, or below):
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
   - Children: full recap body as blocks (preserve ## headings)
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
```

- [ ] **Step 2: Rebuild dist**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
bash scripts/build.sh
```

Expected: all 4 platforms built without errors. `dist/claude-code/commands/obsidian-notion-sync.md` exists.

- [ ] **Step 3: Smoke read**

```bash
cat commands/obsidian-notion-sync.md | head -40
grep -c "mcp__notion__" commands/obsidian-notion-sync.md
```

Expected: file reads coherently. The grep count is just a sanity check that the body mentions the MCP tools by name.

- [ ] **Step 4: Commit**

```bash
git add commands/obsidian-notion-sync.md
git commit -m "feat(commands): /obsidian-notion-sync — Notion MCP sync for recaps + ADRs"
```

## Phase 6 — Schedule the two crons

### Task 3: Author the daily board-refresh prompt file

**Files:**
- Create: `scripts/cron/board-refresh-prompt.txt`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron
```

- [ ] **Step 2: Write the prompt to a text file**

The launchd-triggered `claude -p` session will receive this text as its sole input.

Create `scripts/cron/board-refresh-prompt.txt` with this content:

```
Mon-Fri 09:00 langlive-line-oa board refresh (triggered by launchd).

Steps:
1. Run /obsidian-board langlive-line-oa --refresh (incremental from last-refresh timestamp in board frontmatter).
2. The command reports a one-line summary like "59 done, 6 in-flight, 8 buckets" and updates board.md.
3. Read the previous board state's totals from frontmatter to compare. If no commits or spec/plan files have been added since the previous refresh (i.e., `git log --since=<last-refresh>` is empty AND no new specs/plans), DO NOT post to Discord — exit silently.
4. Otherwise, post to Discord #langlive-line-oa: "☀️ Board refreshed: N done (+M new), K in-flight, P backlog across J buckets" (use the diff vs. yesterday's totals).
5. Append a one-line entry to today's Logs/YYYY-MM-DD.md.

If anything fails, post "❌ Daily board refresh failed: <error>" to Discord and exit.

You are running as a non-interactive `claude -p` invocation. Do not ask clarifying questions. Execute the steps and exit when done.
```

- [ ] **Step 3: Smoke check**

```bash
wc -l /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/board-refresh-prompt.txt
cat /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/board-refresh-prompt.txt | head -3
```
Expected: ~14 lines, opens with "Mon-Fri 09:00 langlive-line-oa board refresh".

- [ ] **Step 4: Defer commit** — group with Tasks 4-6 file changes in Task 6's commit.

### Task 4: Author the Saturday weekly-recap prompt file

**Files:**
- Create: `scripts/cron/weekly-recap-prompt.txt`

- [ ] **Step 1: Write the prompt to a text file**

Create `scripts/cron/weekly-recap-prompt.txt` with this content:

```
Saturday 12:00 langlive-line-oa weekly recap (triggered by launchd).

Steps:
1. Run /obsidian-board langlive-line-oa --refresh (incremental). This ensures the recap reads a fresh board.
2. Run /obsidian-recap --project=langlive-line-oa --weekly. The command writes Projects/langlive-line-oa/Recaps/<YYYY-WXX>.md.
3. Read the just-written recap file. Translate its content to Notion-ready Chinese:
   - Strip technical noise (T-XXX codes, commit SHAs, file paths) where it doesn't aid clarity
   - Reframe in product/business language for the user's future-self review
   - Preserve the section structure: ## Shipped → 本週 ship 的東西; ## In flight → 進行中; ## Decisions made → 重大決策; ## Learnings → 學到的事; ## Board diff → Now/Next/Later 變動; ## Open questions → 下週要想的問題
   - Cap at ~400 words
4. Post to Discord #langlive-line-oa (in main channel timeline, NOT a thread):
   "📊 langlive-line-oa <YYYY-WXX> 週報 (<date-range>)
   
   <Chinese recap content>
   
   回覆: ok / edit: <說明> / redo"
5. STOP. Do not attempt to wait for the reply or call /obsidian-notion-sync here — the reply triggers a separate Claude session via the discord plugin's channel watcher (see Task 7's reply-handler routine).
6. Append to today's Logs/YYYY-MM-DD.md: "**HH:MM** - weekly-recap | W<NN> posted, awaiting approval".

If translation fails (LLM error, empty input), post "❌ Weekly recap translation failed: <error>" to Discord and STOP — don't post a half-baked recap.

You are running as a non-interactive `claude -p` invocation. Do not ask clarifying questions. Execute the steps and exit when done.
```

- [ ] **Step 2: Smoke check**

```bash
wc -l /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/weekly-recap-prompt.txt
```
Expected: ~22 lines.

- [ ] **Step 3: Idempotency note** — running this prompt twice on the same Saturday is safe: second run regenerates the recap (overwrites the file), reposts to Discord. The Discord channel gets two posts — user picks the most recent.

- [ ] **Step 4: Defer commit** — group with other cron files in Task 6's commit.

### Task 5: Write trigger script + launchd plist for daily board-refresh

**Files:**
- Create: `scripts/cron/trigger-board-refresh.sh`
- Create: `~/Library/LaunchAgents/com.langlive.board-refresh.plist`

- [ ] **Step 1: Write the trigger script**

Create `scripts/cron/trigger-board-refresh.sh` with this content:

```bash
#!/bin/bash
# Triggered by launchd Mon-Fri 09:00 local time.
# Pipes the prompt to `claude -p` for non-interactive execution.

set -euo pipefail

REPO=/Users/leric/Desktop/code/obsidian-second-brain
PROMPT=$REPO/scripts/cron/board-refresh-prompt.txt
LOG=/tmp/langlive-board-refresh.log

# Pick up the user's shell environment (claude CLI, PATH, etc.)
source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

cd "$REPO"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') board-refresh fired ===="
  claude -p "$(cat "$PROMPT")" --output-format text
  echo "==== exit code: $? ===="
} >> "$LOG" 2>&1
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-board-refresh.sh
```

- [ ] **Step 3: Write the launchd plist**

Create `~/Library/LaunchAgents/com.langlive.board-refresh.plist` with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.langlive.board-refresh</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-board-refresh.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>5</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/langlive-board-refresh.stdout</string>
    <key>StandardErrorPath</key>
    <string>/tmp/langlive-board-refresh.stderr</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

(launchd Weekday: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri. Hour/Minute are LOCAL time on macOS.)

- [ ] **Step 4: Load the plist**

```bash
launchctl unload ~/Library/LaunchAgents/com.langlive.board-refresh.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.langlive.board-refresh.plist
launchctl list | grep langlive
```
Expected: `launchctl list` shows `com.langlive.board-refresh` with PID `-` (not running yet) and exit code `0`.

- [ ] **Step 5: Defer commit** — group with Task 6 (Saturday cron).

### Task 6: Write trigger script + launchd plist for Saturday weekly-recap + commit cron files

**Files:**
- Create: `scripts/cron/trigger-weekly-recap.sh`
- Create: `~/Library/LaunchAgents/com.langlive.weekly-recap.plist`
- Commit: all 4 cron files (2 prompts + 2 trigger scripts) in this repo

- [ ] **Step 1: Write the trigger script**

Create `scripts/cron/trigger-weekly-recap.sh` with this content:

```bash
#!/bin/bash
# Triggered by launchd Saturday 12:00 local time.

set -euo pipefail

REPO=/Users/leric/Desktop/code/obsidian-second-brain
PROMPT=$REPO/scripts/cron/weekly-recap-prompt.txt
LOG=/tmp/langlive-weekly-recap.log

source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null || true

cd "$REPO"

{
  echo "==== $(date '+%Y-%m-%d %H:%M:%S') weekly-recap fired ===="
  claude -p "$(cat "$PROMPT")" --output-format text
  echo "==== exit code: $? ===="
} >> "$LOG" 2>&1
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-weekly-recap.sh
```

- [ ] **Step 3: Write the launchd plist**

Create `~/Library/LaunchAgents/com.langlive.weekly-recap.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.langlive.weekly-recap</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-weekly-recap.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>6</integer>
        <key>Hour</key><integer>12</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/langlive-weekly-recap.stdout</string>
    <key>StandardErrorPath</key>
    <string>/tmp/langlive-weekly-recap.stderr</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

(Weekday: 6=Saturday on launchd.)

- [ ] **Step 4: Load the plist**

```bash
launchctl unload ~/Library/LaunchAgents/com.langlive.weekly-recap.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.langlive.weekly-recap.plist
launchctl list | grep langlive
```
Expected: both `com.langlive.board-refresh` AND `com.langlive.weekly-recap` listed.

- [ ] **Step 5: Commit all 4 cron files** (2 prompts + 2 trigger scripts) to the repo. The plists outside the repo are NOT committed.

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add scripts/cron/
git commit -m "feat(cron): launchd-fired trigger scripts + prompts for board-refresh + weekly-recap"
```

### Task 7: Author the Discord reply-handler routine (decoupled sync)

**Files:**
- (Optional) Modify: vault `_CLAUDE.md` to add a "Discord reply handling" section that future sessions read when they get an incoming Discord message.

The Discord plugin delivers user replies as channel-source messages to a Claude session. When that session sees a reply in `#langlive-line-oa` that responds to a recent weekly-recap post, it needs to know how to handle `ok` / `edit: ...` / `redo`.

- [ ] **Step 1: Append the following section to `~/Documents/SecondBrain/_CLAUDE.md`**

```markdown

## Discord reply handling for `#langlive-line-oa` channel

When a Discord message arrives in `#langlive-line-oa` channel and the most recent prior message is a "📊 langlive-line-oa ... 週報" bot post (within the last 48 hours):

**Reply: `ok`** (case-insensitive)
1. Find the most recent recap file in `Projects/langlive-line-oa/Recaps/` (highest week number, frontmatter `notion-synced: false` or missing)
2. Run `/obsidian-notion-sync --recap <YYYY-WXX>` to push to Notion
3. Reply to the Discord thread: "✅ 已同步：\n📄 主頁：<main_url>\n📊 <YYYY-WXX> entry：<recap_url>"
4. If sync fails: reply "❌ <error>" and STOP

**Reply: `edit: <text>` or `edit <text>`**
1. Find the most recent unsynced recap file
2. Re-translate the recap to Chinese, incorporating the user's edit hint (e.g., "less technical", "add cost context", "focus on Y")
3. Post a new Discord message with the revised recap content + "回覆: ok / edit: ... / redo"
4. The original message can be left as-is (preserves history) or edited via `edit_message` tool — prefer new message for cleaner audit trail

**Reply: `redo`**
1. Re-run /obsidian-recap --project=langlive-line-oa --weekly (this overwrites the existing recap file)
2. Re-translate
3. Post a new Discord message
4. Same flow as edit

**Reply: anything else, or in any other channel**
- Treat as normal conversation — do not trigger sync logic.

**Reply older than 48 hours after the bot post:** ignore (assume stale).
```

- [ ] **Step 2: Verify the section landed**

```bash
tail -40 ~/Documents/SecondBrain/_CLAUDE.md
```

Expected: section ends with the "Reply older than 48 hours" line.

- [ ] **Step 3: No commit** — vault not git-tracked.

## Phase 7 — Dry-run + verification

### Task 8: End-to-end dry-run of the Saturday pipeline

This task simulates a real Saturday cron firing, end-to-end. Catches integration issues before the actual cron runs.

**Files:**
- Read-only verification + a manual invocation of the recap pipeline

- [ ] **Step 1: Manually trigger the Saturday cron path**

Two options:
- (a) Run the trigger script directly: `bash /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-weekly-recap.sh`. Watch `/tmp/langlive-weekly-recap.log` with `tail -f`.
- (b) Open a Claude session in this repo's directory and paste the contents of `scripts/cron/weekly-recap-prompt.txt` verbatim. Useful for debugging since you see Claude's intermediate output live.

Option (a) tests the full launchd → script → claude-CLI path. Option (b) tests just the prompt logic.

Verify:
- `/obsidian-board langlive-line-oa --refresh` runs without error
- `/obsidian-recap --project=langlive-line-oa --weekly` produces a file at `~/Documents/SecondBrain/Projects/langlive-line-oa/Recaps/<YYYY-WXX>.md`
- Chinese translation reads naturally (no untranslated tech jargon left, no garbled output)
- Discord post lands in `#langlive-line-oa` channel

- [ ] **Step 2: Manually reply `ok` in the Discord channel**

In Discord, send `ok` as a regular message in `#langlive-line-oa`. Wait for the reply-handler routine to fire.

Verify:
- A Claude session picks up the reply (visible as a new message coming through claude-discord)
- `/obsidian-notion-sync --recap <YYYY-WXX>` runs
- Notion main page's `Current Roadmap` section now shows the new Now/Next/Later (open the Notion page in browser to verify)
- A new entry exists in the Weekly Recaps database (open Notion to verify)
- Discord receives the confirmation `✅ 已同步` message with URLs
- Vault recap file frontmatter now has `notion-synced: true` and `notion-page-url: <url>`

- [ ] **Step 3: Check the hub note frontmatter**

```bash
grep -A 5 "^notion:" ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md
```

Expected: `main_page_id` and `weekly_recaps_db_id` are now populated (filled by first sync). `decisions_archive_page_id` is still empty (will populate on first ADR sync).

- [ ] **Step 4: Test the edit flow**

In Discord, after a fresh recap post, reply with `edit: 用更口語的中文`. Verify a new translated version posts. Verify it sounds different (less formal).

- [ ] **Step 5: Test the daily board-refresh cron**

```bash
bash /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-board-refresh.sh
tail -50 /tmp/langlive-board-refresh.log
```

Verify:
- `/obsidian-board langlive-line-oa --refresh` runs and updates `board.md`
- A Discord post appears ONLY IF there were new commits/specs since the prior refresh (which there should be from this plan's commits)
- Logs/YYYY-MM-DD.md has the new line

- [ ] **Step 6: Trigger a no-op refresh**

```bash
bash /Users/leric/Desktop/code/obsidian-second-brain/scripts/cron/trigger-board-refresh.sh
```

Immediately after Step 5. Verify:
- `/obsidian-board` runs but reports no changes (incremental diff is empty)
- NO Discord post (the cron suppresses on no-op per Task 3's prompt)
- Logs/YYYY-MM-DD.md still gets the entry (so we know it ran)

- [ ] **Step 7: Test an ADR sync end-to-end**

In a Claude session in `/Users/leric/Desktop/code/langlive-line-oa`, run:

```
/obsidian-adr --project=langlive-line-oa
```

Use a fake test decision (e.g., subject: "test ADR sync", options: A/B, choice: A). After the ADR is written to `Projects/langlive-line-oa/Decisions/`, when prompted to sync to Notion, accept.

Verify:
- A new sub-page appears under Notion's Decisions Archive page
- Vault ADR file gets `notion-synced: true` + URL
- Hub note `decisions_archive_page_id` is now populated (was empty until first ADR sync)

- [ ] **Step 8: Document any friction** in the spec's "Open questions / future work" section. Expected friction points:
- Chinese translation occasionally awkward (LLM stylistic issues)
- Notion `Current Roadmap` block replacement may need refinement if main page has unexpected block layouts
- The Discord channel-watcher's reply-trigger latency (how long after the user replies does Claude pick up?)

- [ ] **Step 9: No commit** for the dry-run itself, but if Steps 1-7 revealed bugs in any command file or the new `obsidian-notion-sync.md`, fix and commit those.

### Task 9: One-week soak test

This isn't a code task — it's a runtime observation period.

- [ ] **Step 1: Mark the start date**

Append to today's `Logs/YYYY-MM-DD.md`:

```
**HH:MM** - soak-test | Plan 2 activated. Soak test starts <YYYY-MM-DD>, review on <YYYY-MM-DD + 7>.
```

- [ ] **Step 2: Use the system normally for one week**

- Capture ideas via `/obsidian-capture --project=langlive-line-oa "..."`
- Make at least one decision via `/obsidian-adr --project=langlive-line-oa` and let it sync to Notion
- Let the daily 09:00 board refresh fire (check Discord for the post)
- Approve next Saturday's recap (or edit it) and verify Notion sync
- Note any friction in the spec or in a freshly-captured `/obsidian-learn --capture` note

- [ ] **Step 3: After 7 days, review and append findings**

Append to today's `Logs/YYYY-MM-DD.md`:

```
**HH:MM** - soak-test-review | Plan 2 soak test complete. <N> friction items captured. <K> command tweaks proposed for follow-up plan.
```

If significant tweaks emerged, write a Plan 3 spec (or extend the existing spec's Open Questions).

### Task 10: Bump CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append to the Unreleased section**

Under `### Added`:

```markdown
- `/obsidian-notion-sync` — new command that syncs vault recaps + ADRs to Notion via MCP, with auto-discovery and creation of Notion main page / Weekly Recaps DB / Decisions Archive sub-page.
- Two `/schedule` cron routines documented: `langlive-line-oa-board-refresh` (Mon-Fri 09:00) and `langlive-line-oa-weekly-recap` (Saturday 12:00).
- Plan 2 implementation reference: `docs/superpowers/plans/2026-05-25-vault-hybrid-activation-layer.md`.
```

Under `### Changed` (if needed): nothing new — this plan adds rather than modifies.

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): note Plan 2 activation layer changes"
```

---

## Notes for the executing agent

- **Crons execute in remote sessions.** When you write the cron prompts (Tasks 3, 4), assume the Claude session that fires has NO context other than the prompt text. It must work standalone. That's why the prompts are verbose — they tell Claude exactly which commands to run and how to handle errors.
- **Notion MCP tool names** are case-sensitive: `mcp__notion__API-post-search`, `mcp__notion__API-create-a-data-source`, etc. Don't typo.
- **The daily cron's no-op suppression** (Task 3 Step 1, point 3) is critical — without it, the user gets 5 Discord posts per week with identical "no change" content, training them to ignore the channel. Verify this suppression works in Task 8 Step 6.
- **Reply handler depends on the discord plugin's channel-watcher behavior.** If the plugin doesn't auto-fire a Claude session on user channel messages, the reply flow breaks. Test in Task 8 Step 2 — if the session doesn't fire, the user can manually invoke `/obsidian-notion-sync --recap <YYYY-WXX>` instead. Note in spec Open Questions.
- **The `notion-synced: true` frontmatter flag** is the idempotency signal. If you re-run `/obsidian-notion-sync --recap W21` after a sync succeeded, it should detect this and SKIP rather than duplicate the Notion entry. Make sure `obsidian-notion-sync.md` checks this flag at the start of its modes.
- **No worktree for this plan** — Plan 1 didn't use one, and the changes here are narrower (1 new command + 2 cron registrations). Working on `main` per project CLAUDE.md.

---

## What this plan does NOT cover

- **Notion API direct calls without MCP.** If the user later wants webhook-based reactive sync, that's a separate spec.
- **Multi-project Notion sync.** This plan only handles langlive-line-oa. When the user revives langlive-query-rewrite or starts a new project, `/obsidian-notion-sync --project=<new>` should work because the command is project-parameterized — but it hasn't been tested against multiple projects.
- **Notion → Vault sync (reverse direction).** If the user edits the Notion main page manually, the vault doesn't pick that up. Spec Part 6 made the vault source-of-truth — reverse sync is not in scope.
- **Decisions Archive pruning.** When the archive grows past ~50 entries, scannability degrades. Spec Open Questions mentions this — handle in a future plan.
- **Tier 2 hooks** (Claude Code SessionStart/PostToolUse hooks). Tier 1 CLAUDE.md proactive rules cover the four checkpoints; if those prove unreliable, write a Plan 3 to add Tier 2 hooks.

End of Plan 2.
