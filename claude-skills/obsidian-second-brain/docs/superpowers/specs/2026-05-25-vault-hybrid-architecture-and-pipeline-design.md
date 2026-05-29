---
date: 2026-05-25
type: spec
status: draft
owner: Eugeniu
ai-first: true
tags:
  - spec
  - vault-architecture
  - workflow
  - obsidian-second-brain
  - langlive
related-projects:
  - "[[langlive-line-oa]]"
---

## For future Claude

This spec defines (1) a hybrid vault architecture where the user's main project `langlive-line-oa` lives in a project-scoped sub-folder while cross-project artifacts stay at vault root, (2) the slash-command modifications required to support project-scoped routing, and (3) the end-to-end knowledge-and-development pipeline that bridges three loops (daily intake, dev cycle, weekly recap) using Tier 1 (CLAUDE.md proactive rules) and Tier 3 (cron + Discord + Notion MCP) automation. Driver: Eugeniu is a solo dev who owns langlive-line-oa (LINE OA smart-customer-service, 622 commits, 43 specs, 51 plans as of 2026-05-24); the goal is to compound research, decisions, and learnings into a long-lived knowledge base while keeping the existing `superpowers/brainstorming → writing-plans → executing-plans` development loop intact. Vault path: `~/Documents/SecondBrain` (multi-project, not git-tracked). Source repo for slash commands: `/Users/leric/Desktop/code/obsidian-second-brain`. Discord channel + bot + Notion MCP already configured.

---

## Background

- **Owner:** Eugeniu, solo dev
- **Primary project:** `langlive-line-oa` — web admin for LangLive LINE Official Account (user blocking + session tracking + RAG-powered customer service). Local: `/Users/leric/Desktop/code/langlive-line-oa` (+ worktrees `-wt-3`, `-wt-4`).
- **Vault state (as of 2026-05-25):** `~/Documents/SecondBrain` initialized via `/obsidian-init`. Flat type-based folders (`Projects/`, `Boards/`, `Ideas/`, `Decisions/`, `Logs/`, `Daily/`, `Research/`, `Knowledge/`, `People/`, `Companies/`, `Goals/`, `Mentions/`, `Tasks/`, `Reviews/`, `Dev Logs/`, `Templates/`). Real cross-project traces exist (Ideas/2026-05-24-llm-query-rewrite-langlive-rag → Projects/langlive-query-rewrite + Decisions/2026-05-24-langlive-query-rewrite-approach).
- **Dev loop:** `superpowers/brainstorming → writing-plans → executing-plans`, with brainstorm branches, spec/plan files at `docs/superpowers/{specs,plans}/`. Mature — do not disturb.
- **Notion + Discord:** Notion MCP available (all `mcp__notion__API-*` tools). Discord bot + `#langlive-line-oa` channel configured.
- **Pain points (driving this spec):**
  1. Daily research / competitor intel / feature ideas have no disciplined intake into the vault.
  2. Alternatives considered during `superpowers/brainstorming` (the 2-3 approaches) are lost to git history — no decision log.
  3. Project status sits in two places (Boards/langlive-line-oa.md auto-generated from commits + Projects/langlive-line-oa.md hub note) without a unified weekly snapshot for stakeholders.
  4. No Chinese-language Notion archive for retrospective viewing.
  5. Current flat folder layout makes "show me everything about langlive-line-oa" a search task instead of a folder walk.

---

## Goals

1. Vault architecture that makes the main project self-contained (folder walk) without sacrificing cross-project artifacts (Daily, Logs, People, Knowledge).
2. Slash-command set that defaults to current behavior for cross-project commands and accepts project routing for project-scoped commands.
3. Four checkpoints that distill intake → graduate → decide → learn into a closed loop, with Tier 1 automation (CLAUDE.md proactive rules) so Claude reminds the user at the right moment.
4. Weekly recap pipeline (Saturday 12:00 cron → Chinese translation → Discord channel → Notion via MCP) that runs without manual paste.
5. Notion three-layer structure (overwritten main page + append-only Weekly Recaps database + append-only Decisions Archive) that preserves history.
6. Migration path that wipes legacy / unused vault folders, rebuilds the langlive-line-oa sub-tree, and leaves other (currently empty) projects to be redone later.

## Non-goals

- Automating Checkpoint 1 (graduate handoff to codebase) beyond a copy-pasted prompt — the cross-session boundary is real.
- Building a custom Discord bot button UI — channel reply with text keyword (`ok` / `edit:` / `redo`) is sufficient.
- Migrating other projects (`langlive-query-rewrite`, `claudecode-discord`, `obsidian-second-brain`) right now — those will be deleted and redone later under the same scheme.
- Modifying every slash command — only those that need project-scoped routing.

---

## Design

### Part 1 — Vault hybrid architecture

```
~/Documents/SecondBrain/
│
├─ _CLAUDE.md, index.md, log.md          ← vault system files (unchanged)
│
├─ Daily/                                 ← /obsidian-daily         (cross-project journal)
├─ Logs/YYYY-MM-DD.md                     ← audit trail             (every command appends, cross-project)
├─ Dev Logs/                              ← /obsidian-log           (per-day-per-project, filename carries project)
├─ Templates/                             ← templates (read-only)
├─ People/                                ← /obsidian-person        (cross-project)
├─ Knowledge/                             ← long-lived vault knowledge + /vault-deep-synthesis + /obsidian-ingest
├─ Reviews/                               ← /obsidian-recap         (vault-wide weekly/monthly, when no --project)
├─ Ideas/                                 ← /obsidian-capture default landing — "unclassified inbox"
├─ Research/Web/Deep/YouTube/Threads/Pulse/  ← /research, /research-deep, /youtube, /thread-read, /discourse-pulse  (default: cross-project)
│
└─ Projects/
    └─ langlive-line-oa/                  ← project-scoped sub-tree (the new pattern)
        ├─ langlive-line-oa.md            ← hub note (includes inline ## Key Decisions section)
        ├─ board.md                       ← kanban (replaces old Boards/langlive-line-oa.md)
        ├─ Ideas/                         ← project-scoped ideas (after triage from root Ideas/)
        ├─ Tasks/                         ← project tasks (T-XXX-<slug>.md)
        ├─ Decisions/                     ← project ADRs (independent files for architectural decisions)
        ├─ Learnings/                     ← project-scoped lessons (traps, patterns, post-PR insights)
        ├─ Research/                      ← project-specific deep research (when --project=langlive-line-oa passed to research commands)
        ├─ Competitors/                   ← competitor watch (one file per competitor, refreshed periodically)
        └─ Recaps/                        ← project-scoped weekly recaps (when --project passed to /obsidian-recap)
```

#### Folders to DELETE from vault root

| Folder | Reason |
|---|---|
| `Goals/` | empty / legacy; no slash command writes here |
| `Companies/` | legacy; cross-project entity notes can live in `People/` (with `type: company`) or `Knowledge/` |
| `Mentions/` | legacy; unclear purpose |
| `Tasks/` | empty at root; project tasks live in `Projects/<name>/Tasks/` |
| `Boards/` | replaced by `Projects/<name>/board.md` |
| `Decisions/` | root version unused by any command; per-project ADRs live in `Projects/<name>/Decisions/` |

#### Other-project cleanup

Files to delete (to be redone later when those projects are revived):
- `Projects/langlive-query-rewrite.md`
- `Projects/claudecode-discord.md`
- `Projects/obsidian-second-brain.md`
- `Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md`
- `Decisions/2026-05-24-langlive-query-rewrite-approach.md`

Anything else in `Ideas/`, `Research/`, `Knowledge/` that's not langlive-line-oa-relevant: keep (root level is for cross-project / unclassified content; those don't need to be tied to a project).

---

### Part 2 — Slash command modifications

#### Convention

A command supports `--project=<name>` (or detects project from CLAUDE.md context) when it has both a "cross-project default" mode and a "project-specific" mode. When `--project` is set, the write target moves into `Projects/<name>/<TypeFolder>/`. When not set, the command writes to vault root (default behavior preserved).

#### Commands to MODIFY (in `/Users/leric/Desktop/code/obsidian-second-brain/commands/`)

| Command | Current target | New default | New `--project=<name>` target |
|---|---|---|---|
| `obsidian-capture.md` | `Ideas/Title.md` | unchanged (root `Ideas/`) | `Projects/<name>/Ideas/<title>.md` |
| `obsidian-emerge.md` | `Ideas/` | unchanged | `Projects/<name>/Ideas/` |
| `obsidian-graduate.md` | `Projects/<name>.md` | `Projects/<name>/<name>.md` + sub-folder skeleton | (always project-scoped) |
| `obsidian-project.md` | `Projects/<name>.md` | `Projects/<name>/<name>.md` + initial folders | (always project-scoped) |
| `obsidian-board.md` | `Boards/<name>.md` | `Projects/<name>/board.md` | (always project-scoped) — also gains a **refresh-from-history** mode (see below) |
| `obsidian-task.md` | `Tasks/T-XXX.md` (root) | `Projects/<name>/Tasks/T-XXX.md` (requires project context) | (always project-scoped) |
| `obsidian-adr.md` | `Knowledge/ADR-YYYY-MM-DD — Title.md` | `Projects/<name>/Decisions/YYYY-MM-DD-<slug>.md` (requires project) | (always project-scoped) — **S2 alignment with industry convention** |
| `obsidian-learn.md` | no file written (only manages) | extend to write file: `Projects/<name>/Learnings/YYYY-MM-DD-<slug>.md` | (project-scoped when context known) |
| `obsidian-recap.md` | `Reviews/YYYY-MM-DD — Weekly Review.md` | unchanged | `Projects/<name>/Recaps/YYYY-WXX.md` |
| `research.md` | `Research/Web/YYYY-MM-DD-<slug>.md` | unchanged | `Projects/<name>/Research/YYYY-MM-DD-<slug>.md` |
| `research-deep.md` | `Research/Deep/YYYY-MM-DD-<slug>.md` | unchanged | `Projects/<name>/Research/<slug>.md` (with `source-type: deep` frontmatter) |
| `youtube.md` | `Research/YouTube/...` | unchanged | `Projects/<name>/Research/<slug>-yt.md` |
| `thread-read.md` | `Research/Threads/...` | unchanged | `Projects/<name>/Research/<slug>-thread.md` |
| `discourse-pulse.md` | `Research/Pulse/...` | unchanged | `Projects/<name>/Research/<slug>-pulse.md` |

#### `/obsidian-board` refresh-from-history mode (new behavior)

`obsidian-board.md` currently fuzzy-matches a board name and lets the user dialogue-edit it. The new mode formalizes the auto-generated board pattern already used to produce the existing `Boards/langlive-line-oa.md` (topic-clustered, 8 buckets, ✅/🔨/📋 status, generated from commits + spec/plan files).

Invocation:
```
/obsidian-board <name>                  # interactive, dialogue-edit (current behavior)
/obsidian-board <name> --refresh        # regenerate from history, no dialogue
```

Refresh logic (run when `--refresh` flag set, or invoked from cron):
1. Resolve project from `<name>`, locate codebase via `Projects/<name>/<name>.md` frontmatter (`local-path:` field; auto-set during graduate).
2. Scan `<local-path>/docs/superpowers/specs/*.md` and `<local-path>/docs/superpowers/plans/*.md` for items since last refresh (or full scan if `--full`).
3. `git log --all --since=<last-refresh>` inside `<local-path>`. Detect `brainstorm/*` branches and their tip commits.
4. Cluster items into topic buckets — preserve existing bucket names from `Projects/<name>/board.md` if present; otherwise group by spec/plan title keywords.
5. Within each bucket, classify each item: ✅ Done (merged to main / shipped), 🔨 In Progress (active brainstorm branch or in-flight spec without merge), 📋 Backlog (planned but not started).
6. Write `Projects/<name>/board.md` preserving the For-future-Claude preamble, frontmatter, and any manual `## 🔥 This Week` overlay section (do not overwrite manual sections).
7. Append one line to `Logs/YYYY-MM-DD.md`: `**HH:MM** - board | <name> refreshed - N done, M in-flight, P backlog across K buckets`.
8. Update `last-refresh:` timestamp in board frontmatter for next incremental run.

Idempotency: safe to run multiple times per day. Incremental by default (only scans since `last-refresh`); pass `--full` to rebuild from scratch.

Manual sections preserved: the hub's `## 🔥 This Week` overlay (if user added one to `board.md` directly), the For-future-Claude preamble, and any `## Patterns observed` / `## Bucket summary` sections (re-computed if present).

#### Commands NOT modified

`obsidian-daily`, `obsidian-decide` (inline append to hub stays — **S1.i**), `obsidian-log`, `obsidian-person`, `obsidian-review`, all read-only / cross-cutting commands (`obsidian-find`, `obsidian-connect`, `obsidian-visualize`, `obsidian-health`, `obsidian-export`, `obsidian-reconcile`, `obsidian-challenge`, `obsidian-synthesize`, `obsidian-ingest`, `idea-discovery`, `vault-deep-synthesis`).

#### Project context detection (so `--project` doesn't always need to be typed)

Three layers, in priority order:
1. **Explicit flag:** `/obsidian-capture --project=langlive-line-oa "..."`
2. **Vault `_CLAUDE.md` active-project hint:** add a section `## Active project: langlive-line-oa` — commands read this when no flag is set.
3. **Codebase `CLAUDE.md` declaration:** when Claude is running inside `/Users/leric/Desktop/code/langlive-line-oa`, its CLAUDE.md states the vault project name; commands honor this.

#### Adapter rebuild

After modifying any command in `commands/`, run `bash scripts/build.sh` to regenerate `dist/` for all four platforms (claude-code, codex-cli, gemini-cli, opencode).

---

### Part 3 — The four checkpoints

The CLAUDE.md proactive rules (Part 4) make Claude remind the user at each checkpoint without manual recall.

#### CP1 — Vault → Code (graduate handoff)

**When:** weekly triage; an idea in `Ideas/` (root) graduates into a langlive-line-oa task.

**Flow:**
1. `/obsidian-graduate <idea-slug> --project=langlive-line-oa`
2. Command creates `Projects/langlive-line-oa/Tasks/T-XXX-<slug>.md` (the "task brief": what + why + acceptance criteria) and adds an entry to `board.md`.
3. User copies the task-brief content into a Claude Code session running in `/Users/leric/Desktop/code/langlive-line-oa`, seeding `superpowers/brainstorming`.
4. `superpowers/brainstorming` produces `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md` in the codebase.
5. Spec path is written back to the task brief's frontmatter (`spec_path:`).

**Outcome:** vault holds the "why," codebase holds the "how," both linked.

#### CP2 — Decision distillation (brainstorm-time ADR) ⭐ core new habit

**When:** `superpowers/brainstorming` proposes 2-3 approaches and the user picks one — before `writing-plans` begins.

**Flow:**
1. User accepts an approach in brainstorming.
2. CLAUDE.md rule fires: Claude proactively offers `/obsidian-adr --project=langlive-line-oa`, pre-filling subject + options + choice + reasoning + falsification trigger from the brainstorm transcript.
3. User confirms; command writes `Projects/langlive-line-oa/Decisions/YYYY-MM-DD-<slug>.md`.
4. Claude offers to also sync this ADR to Notion's Decisions Archive (via `mcp__notion__API-post-page`).
5. `writing-plans` proceeds.

**ADR note shape:**
```yaml
---
date: 2026-05-25
type: adr
project: "[[langlive-line-oa]]"
related-task: "[[T-007-add-rag-context]]"
related-spec: "docs/superpowers/specs/2026-05-25-rag-context-design.md"
tags: [decision, langlive, adr]
ai-first: true
---

## For future Claude
[one-line summary of decision + why future-Claude would care]

## Subject
[the question being decided]

## Options considered
- A. ...
- B. ... (CHOSEN)
- C. ...

## Decision
B. ...

## Reasoning
[2-4 sentences]

## What would change my mind
[the falsification condition; this turns the decision from belief into testable hypothesis]
```

#### CP3 — Post-ship learning capture

**When:** `superpowers/finishing-a-development-branch` completes; PR merged.

**Flow:**
1. CLAUDE.md rule fires: Claude asks "What did you learn during this task that you didn't know before?"
2. If anything: `/obsidian-learn --project=langlive-line-oa` writes `Projects/langlive-line-oa/Learnings/YYYY-MM-DD-<slug>.md`.
3. If a NEW architectural decision emerged mid-implementation (not in brainstorm): `/obsidian-adr` again.
4. Board card moves to Done; spec path stays linked.

#### CP4 — Saturday recap → Discord → Notion

**When:** Saturday 12:00 local time (Asia/Taipei), via `/schedule` cron.

**Flow:** see Part 5.

#### Checkpoint priority (when time is short)

CP4 > CP2 > CP1 > CP3. If the week is too busy, skip CP3 (learnings can be added at the next recap from memory). Never skip CP4 (the recap is the spine; missing one breaks continuity).

---

### Part 4 — Tier 1 automation: CLAUDE.md proactive rules

Two CLAUDE.md files get the rules. Both files are NEW additions, appended to existing CLAUDE.md content (do not replace).

#### A. Vault `_CLAUDE.md` (at `~/Documents/SecondBrain/_CLAUDE.md`)

Append section:

```markdown
## Active main project

`langlive-line-oa` — when a slash command supports `--project` but no flag is given, default to `langlive-line-oa` unless the conversation context clearly references another project.

## Project-scoped folder routing

For commands that support `--project=<name>` (see Part 2 of `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md` in the obsidian-second-brain repo):

| Type | Without `--project` | With `--project=<name>` |
|---|---|---|
| Idea | `Ideas/` | `Projects/<name>/Ideas/` |
| Task | (n/a — always project-scoped) | `Projects/<name>/Tasks/` |
| ADR  | (n/a — always project-scoped) | `Projects/<name>/Decisions/` |
| Learning | (n/a — always project-scoped) | `Projects/<name>/Learnings/` |
| Research | `Research/<sub>/` | `Projects/<name>/Research/` |
| Recap | `Reviews/` | `Projects/<name>/Recaps/` |

## Proactive prompts

PROACTIVE behavior — when these conditions hit, suggest the vault command WITHOUT being asked:

1. **After `superpowers/brainstorming` presents 2-3 approaches and the user picks one** (before `writing-plans` begins):
   → Offer `/obsidian-adr --project=langlive-line-oa`, pre-filling Subject + Options + Choice + Reasoning from the brainstorm transcript. Include the "What would change my mind" field.
   → After ADR is written, offer to sync to Notion Decisions Archive via `mcp__notion__API-post-page`.

2. **After `superpowers/finishing-a-development-branch` completes** (PR opened or merged):
   → Ask: "What did you learn during this task that you didn't know before?"
   → If anything substantial: `/obsidian-learn --project=langlive-line-oa`.
   → If a new architectural decision emerged mid-stream: `/obsidian-adr --project=langlive-line-oa`.

3. **When the user says "ship", "deploy", "PR merged"** (or these events are otherwise detected):
   → Check `Projects/langlive-line-oa/Tasks/` for a task whose spec_path matches this work; offer to move the corresponding `board.md` card to Done.

4. **When the user captures an idea via `/obsidian-capture` without `--project`**:
   → If the idea text mentions langlive / LINE OA / smart customer service keywords, ask: "This looks like a langlive-line-oa idea — write to `Projects/langlive-line-oa/Ideas/` instead of root `Ideas/`?"
```

#### B. Codebase `CLAUDE.md` (at `/Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md`)

Append section:

```markdown
## Vault integration (obsidian-second-brain)

Vault root: `~/Documents/SecondBrain/`
This project's vault home: `~/Documents/SecondBrain/Projects/langlive-line-oa/`

When inside this codebase, treat `langlive-line-oa` as the implicit `--project` for any obsidian-second-brain slash command that supports project routing.

PROACTIVE: see vault `_CLAUDE.md` for the four proactive rules — they apply here too. Specifically:
- After `superpowers/brainstorming` selects an approach → suggest `/obsidian-adr`
- After `superpowers/finishing-a-development-branch` → ask about learnings
```

---

### Part 5 — Tier 3 automation: Saturday cron → Discord → Notion MCP

#### Cron setup (one-time)

```
/schedule create
  cron: 0 12 * * 6              # Saturday 12:00 Asia/Taipei
  name: langlive-line-oa-weekly-recap
  prompt: |
    Run the langlive-line-oa weekly recap pipeline.
    See docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md
    Section 5 for the full flow.
```

#### Pipeline (what the cron-triggered Claude session does)

```
Step 1 — Vault recap
  /obsidian-recap --project=langlive-line-oa --weekly
  → writes Projects/langlive-line-oa/Recaps/2026-WXX.md
  Sections: shipped, in-flight, decisions made, learnings, board diff (Now/Next/Later delta)

Step 2 — Board regenerate (REQUIRED — recap reads from board)
  /obsidian-board langlive-line-oa --refresh
  Re-scans codebase commits + docs/superpowers/{specs,plans}/ since last refresh
  Refresh in-flight + done items in Projects/langlive-line-oa/board.md
  (Saturday pipeline runs an incremental refresh; weekly delta is small unless
   daily cron has been failing.)

Step 3 — Chinese translation
  Read the recap; produce a Notion-ready Chinese version:
  - Strip technical noise (T-XXX codes, file paths, API names) where it doesn't aid clarity
  - Reframe in product/business language
  - Preserve Now/Next/Later structure
  - Cap at ~400 words

Step 4 — Discord channel post
  Bot posts to #langlive-line-oa (NOT a thread — message in main channel timeline):
  
  📊 langlive-line-oa W21 週報（5/18–5/24）
  
  [Chinese recap content]
  
  回覆：ok / edit: <...> / redo
  
  Bot waits for user reply.

Step 5 — User reply handling
  ok        → proceed to Step 6
  edit: X   → rewrite Step 3 output with adjustment X; loop back to Step 4
  redo      → restart Step 3 (possibly with a new angle)
  silence   → wait until reply; if no reply by Monday, post a nudge

Step 6 — Notion sync (via MCP)
  See Part 6 for the three-layer Notion structure.
  
  a) Resolve main_page_id:
     - Look up notion.main_page_id in Projects/langlive-line-oa/langlive-line-oa.md frontmatter
     - If missing: mcp__notion__API-post-search title="langlive-line-oa"
     - If still missing: mcp__notion__API-post-page parent=workspace title="langlive-line-oa"
     - Save resolved ID back to frontmatter
  
  b) Resolve weekly_recaps_db_id:
     - Look up notion.weekly_recaps_db_id in frontmatter
     - If missing: mcp__notion__API-create-a-data-source parent=main_page_id title="Weekly Recaps"
       Properties: Week (title), Period (date range), Shipped (multi-select), Decisions (relation→Decisions Archive), Learnings (rich-text), Recap (page-link)
     - Save resolved ID back to frontmatter
  
  c) Overwrite main page Current Roadmap section:
     mcp__notion__API-patch-block-children main_page_id
     Replace blocks under "Current Roadmap" heading with: Now / Next / Later from board.md
  
  d) Append new Weekly Recap entry:
     mcp__notion__API-post-page parent=weekly_recaps_db_id
     Title: "2026 W21 (5/18–5/24)"
     Body: full Chinese recap content
  
Step 7 — Discord confirmation reply
  Bot posts:
  ✅ 已同步：
  📄 主頁：notion.so/...
  📊 W21 entry：notion.so/...
```

---

### Part 5.5 — Daily board refresh cron

A second `/schedule` cron, separate from the Saturday recap, refreshes the board every morning so the user opens a fresh view of in-flight work each day.

```
/schedule create
  cron: 0 9 * * 1-5             # Mon-Fri 09:00 Asia/Taipei (weekdays)
  name: langlive-line-oa-board-refresh
  prompt: |
    Run /obsidian-board langlive-line-oa --refresh
    Then post a one-line summary to Discord #langlive-line-oa:
    "☀️ Board refreshed: N done, M in-flight, K bucket(s) changed since yesterday"
    Suppress the Discord post if no change since last refresh (i.e. no new commits + no new spec/plan files).
```

Rationale:
- Weekdays only — weekends have the Saturday recap covering ground.
- 09:00 — before the user typically starts dev work; opens with a clean state.
- Suppress on no-op — avoids Discord noise on quiet days.
- Cheap — incremental git log + spec/plan diff is sub-second.

Saturday Step 2 runs the same command (incremental), so a daily cron failure is recoverable on the weekend without data loss; weekly summary just runs a wider diff.

Manual trigger: `/obsidian-board langlive-line-oa --refresh` any time. Use `--full` if the incremental result looks suspicious (e.g., bucket misclassification after a big merge).

### Part 6 — Notion three-layer structure

| Notion entity | Lifecycle | Source-of-truth for |
|---|---|---|
| **Main page "langlive-line-oa"** | overwritten weekly (Current Roadmap section); rest unchanged | "what's the project doing right now" — Now / Next / Later + 3-5 most recent ADRs (links) |
| **Weekly Recaps (database)** | append-only, one row per ISO week | historical record of shipped + decided + learned per week |
| **Decisions Archive (sub-pages)** | append-only, one page per ADR | long-term decision provenance; mirrors `Projects/langlive-line-oa/Decisions/` |

#### ID storage

Stored in `Projects/langlive-line-oa/langlive-line-oa.md` frontmatter:

```yaml
notion:
  main_page_id: ""              # auto-discovered/created on first cron run
  weekly_recaps_db_id: ""       # auto-created if missing on first cron run
  decisions_archive_page_id: "" # auto-created on first ADR-sync request
```

First cron run on Saturday auto-discovers main page (via `mcp__notion__API-post-search title="langlive-line-oa"`) or creates it at workspace root if missing. Same pattern for the database and archive page.

#### What gets posted, what doesn't

| vault artifact | Notion destination | Why |
|---|---|---|
| Weekly recap (Recaps/) | Weekly Recaps DB row + main page Current Roadmap overwrite | both stakeholder snapshot + history |
| ADR (Decisions/) | Decisions Archive sub-page | long-term provenance; explicit user opt-in per ADR |
| Learning (Learnings/) | — | too low-level for Notion; stays in vault |
| Task brief (Tasks/) | — | stays in vault |
| Idea (Ideas/) | — | stays in vault |
| Research dossier | — | stays in vault |

---

### Part 7 — Migration plan (executed by `writing-plans` skill)

Phases, with rollback points:

**Phase 0 — Backup (5 minutes)**
- Copy `~/Documents/SecondBrain/` to `~/Documents/SecondBrain.bak-2026-05-25/`
- Snapshot of obsidian-second-brain repo state (current commit SHA recorded)

**Phase 1 — Vault cleanup (10 minutes, destructive)**
- Delete root folders: `Goals/`, `Companies/`, `Mentions/`, `Tasks/`, `Boards/`, `Decisions/`
- Delete other-project files: `Projects/langlive-query-rewrite.md`, `Projects/claudecode-discord.md`, `Projects/obsidian-second-brain.md`, `Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md`, `Decisions/2026-05-24-langlive-query-rewrite-approach.md`

**Phase 2 — Build langlive-line-oa sub-tree (5 minutes)**
- `mkdir -p Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}`
- `mv Projects/langlive-line-oa.md Projects/langlive-line-oa/langlive-line-oa.md`
- `mv Boards/langlive-line-oa.md Projects/langlive-line-oa/board.md` (Boards/ folder deletes after this)
- Update wikilinks inside hub and board: `[[Projects/langlive-line-oa]]` → `[[langlive-line-oa]]`, `[[Boards/langlive-line-oa]]` → `[[board]]`
- Add `notion: { main_page_id: "", weekly_recaps_db_id: "", decisions_archive_page_id: "" }` block to hub frontmatter
- Add `## 🔥 This Week` section to hub (template, populated by first weekly recap)

**Phase 3 — Modify slash commands (30-45 minutes)**

Edit files in `/Users/leric/Desktop/code/obsidian-second-brain/commands/`:
- `obsidian-capture.md`: add `--project` handling
- `obsidian-emerge.md`: add `--project` handling
- `obsidian-graduate.md`: write to `Projects/<name>/<name>.md` + create sub-folders
- `obsidian-project.md`: same as graduate
- `obsidian-board.md`: write to `Projects/<name>/board.md` + add `--refresh` / `--full` flags + implement refresh-from-history logic (scan codebase git log + spec/plan files, classify into buckets + statuses, preserve manual sections). See Part 2 for full spec.
- `obsidian-task.md`: write to `Projects/<name>/Tasks/`
- `obsidian-adr.md`: write to `Projects/<name>/Decisions/` (was `Knowledge/`)
- `obsidian-learn.md`: extend to write `Projects/<name>/Learnings/<slug>.md`
- `obsidian-recap.md`: add `--project` for `Projects/<name>/Recaps/`
- `research.md`, `research-deep.md`, `youtube.md`, `thread-read.md`, `discourse-pulse.md`: add `--project` flag

Then `bash scripts/build.sh` to regenerate `dist/`. Reinstall to user's `~/.claude/skills/obsidian-second-brain/` (existing symlink should auto-pick up).

Bump `CHANGELOG.md` under "Unreleased".

**Phase 4 — CLAUDE.md updates (10 minutes)**
- Append Part 4-A content to `~/Documents/SecondBrain/_CLAUDE.md`
- Append Part 4-B content to `/Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md`

**Phase 5 — Notion structure setup (5 minutes)**
- Confirm main page `langlive-line-oa` exists in Notion (or let first cron create it)
- No other manual action — Weekly Recaps DB and Decisions Archive are auto-created on first use

**Phase 6 — Schedule crons (10 minutes)**
- Run `/schedule create` for Saturday recap (Part 5)
- Run `/schedule create` for daily board refresh, Mon-Fri 09:00 (Part 5.5)

**Phase 7 — Dry-run (15 minutes)**
- Manually trigger the Saturday recap path once to verify Discord post + Notion MCP write end-to-end
- Adjust prompt template / Chinese style as needed

**Phase 8 — First-week startup SOP** (see Part 8)

---

### Part 8 — Startup checklist

Kanban shape: **待辦 / 進行中 / 已完成**. These are infrastructure setup items (one-shot), not product features, so no problem-domain tags — order roughly follows Phase 0 → 7. Work at your own pace.

(Problem-domain tags like UI / UX / KB / Performance / Infra apply to the long-term project board `Projects/langlive-line-oa/board.md` maintained by `/obsidian-board --refresh` per Part 2 — they don't apply here.)

#### 待辦

- [ ] Phase 0 — Backup vault to `~/Documents/SecondBrain.bak-2026-05-25/`
- [ ] Phase 1 — Delete root `Goals/`, `Companies/`, `Mentions/`, `Tasks/`, `Boards/`, `Decisions/`
- [ ] Phase 1 — Delete other-project files: `Projects/langlive-query-rewrite.md`, `Projects/claudecode-discord.md`, `Projects/obsidian-second-brain.md`, `Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md`, `Decisions/2026-05-24-langlive-query-rewrite-approach.md`
- [ ] Phase 2 — `mkdir -p Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}`
- [ ] Phase 2 — Move hub + board into sub-tree; update wikilinks `[[Projects/langlive-line-oa]]` → `[[langlive-line-oa]]`, `[[Boards/langlive-line-oa]]` → `[[board]]`
- [ ] Phase 2 — Add `notion: { main_page_id, weekly_recaps_db_id, decisions_archive_page_id }` block + `## 🔥 This Week` template section to hub
- [ ] Phase 3 — Modify 14 slash commands per Part 2 table (capture, emerge, graduate, project, board, task, adr, learn, recap, research, research-deep, youtube, thread-read, discourse-pulse)
- [ ] Phase 3 — Implement `/obsidian-board <name> --refresh` from-history logic per Part 2 sub-section
- [ ] Phase 3 — `bash scripts/build.sh` to rebuild dist for all four platforms
- [ ] Phase 3 — Smoke-test each modified command on a throwaway note
- [ ] Phase 3 — Bump `CHANGELOG.md` under "Unreleased"
- [ ] Phase 4 — Append vault `_CLAUDE.md` rules (Part 4-A: active project + routing + 4 proactive prompts)
- [ ] Phase 4 — Append codebase `CLAUDE.md` rules (Part 4-B: vault integration + proactive)
- [ ] Phase 5 — Confirm Notion main page `langlive-line-oa` exists (or let first cron auto-create)
- [ ] Phase 6 — `/schedule create` Saturday 12:00 recap cron (Part 5)
- [ ] Phase 6 — `/schedule create` Mon-Fri 09:00 board-refresh cron (Part 5.5)
- [ ] Phase 7 — Manually trigger Saturday pipeline; verify Discord post + Notion MCP writes end-to-end (main page overwrite + Weekly Recaps DB row)
- [ ] Run system normally for one full week — capture, decide, learn — log any friction back into this checklist as new items

#### 進行中

(empty until work starts)

#### 已完成

(empty until work ships)

---

## Decisions made during brainstorm (2026-05-25 session)

- **Approach B** (two-loop with handoff) chosen over A (vault-leading, too heavy) and C (codebase-leading, loses intake value).
- **Board WIP = 3** (default was 2; user override for solo dev with parallel work via worktrees).
- **Saturday 12:00** cron time (was Friday 16:00 in earlier draft; user changed).
- **Discord interaction:** channel message (no thread), text reply with `ok` / `edit:` / `redo` keywords (no buttons — claude-discord plugin lacks Components API; threads add navigation overhead user didn't want).
- **Notion structure:** three layers (main page overwrite + Weekly Recaps DB append-only + Decisions Archive append-only). Preserves history while keeping main page clean for stakeholder viewing.
- **Notion IDs:** auto-discover + auto-create on first run. No manual ID setup.
- **Notion sync:** full MCP automation. Zero manual paste.
- **Vault architecture:** hybrid γ — `langlive-line-oa` as project-scoped sub-tree; cross-project artifacts (Daily, Logs, People, Knowledge, Templates, Reviews) stay flat at root; root `Ideas/` and `Research/<sub>/` remain as cross-project defaults.
- **Decisions vs ADRs (S1 + S2):** small decisions append inline to hub note's `## Key Decisions` section (`/obsidian-decide` unchanged); architectural decisions get standalone files in `Projects/<name>/Decisions/` (`/obsidian-adr` retargeted from `Knowledge/`).
- **Vault cleanup (S3):** delete legacy folders `Goals/`, `Companies/`, `Mentions/`, `Tasks/`, `Boards/`, `Decisions/`. Delete files for other projects (`langlive-query-rewrite`, `claudecode-discord`, `obsidian-second-brain`) — to be redone later under the new scheme.
- **Spec location:** this file lives in the obsidian-second-brain source repo (`docs/superpowers/specs/`) because implementation requires modifying that repo's slash commands. Vault is not git-tracked.
- **Board refresh in scope (added 2026-05-25 mid-review):** `/obsidian-board` gains an explicit `--refresh` mode with from-history logic (commits + spec/plan scan + bucket classification + status). A second cron runs the refresh Mon-Fri 09:00 so each weekday opens with a fresh board. Saturday recap reuses the same command incrementally. Suppresses Discord notification on no-op days.
- **Startup checklist shape (Part 8):** kanban-style 待辦 / 進行中 / 已完成 without topic tags. Problem-domain tags (UI / UX / KB / Performance / Infra) belong to the long-term `Projects/langlive-line-oa/board.md`, not to one-shot infrastructure setup work. No prescriptive day-by-day timeline — items worked at user's own pace.

---

## Open questions / future work

- **Other projects migration:** when `langlive-query-rewrite` (or any other project) is revived, re-create under `Projects/<name>/` with the same sub-tree pattern. No spec needed — same recipe.
- **Decisions Archive pruning:** after 6 months, consider archiving Notion sub-pages older than 12 months into a "Decisions Archive — Historical" sub-page to keep the main archive scannable.
- **Cross-project ADRs:** rare but possible (e.g., "use TypeScript everywhere"). Current spec puts these nowhere; if needed, restore a root `Decisions/` folder for that case.
- **Mobile capture via Discord:** `#langlive-line-oa` channel could receive ad-hoc messages from the user; a separate cron / hook could route them into `Projects/langlive-line-oa/Ideas/`. Out of scope here; revisit if friction observed.
- **Tier 2 hooks:** Claude Code SessionStart / PostToolUse hooks could enforce CP2 reminders if Tier 1 CLAUDE.md proves unreliable. Not needed initially.
- **Notion API drift:** Notion MCP tools may change. Re-verify on each obsidian-second-brain version bump.
- **Board generator script location:** the refresh logic is specified in Part 2 (inside `obsidian-board.md` command body). If complexity grows, extract into `scripts/refresh_board.py` and have the command shell out — defer until lines-of-prompt becomes unwieldy.

---

## References

- Repo: `/Users/leric/Desktop/code/obsidian-second-brain`
- Vault: `~/Documents/SecondBrain`
- Project codebase: `/Users/leric/Desktop/code/langlive-line-oa`
- AI-first rule: `/Users/leric/Desktop/code/obsidian-second-brain/references/ai-first-rules.md`
- Industry pattern references:
  - PARA + CODE (Tiago Forte) — Capture / Organize / Distill / Express
  - Shape Up (Basecamp) — pitch → bet → cycle (maps to idea → graduate → cycle)
  - Linear "Now / Next / Later" roadmap
  - ADR (Architecture Decision Records) — Michael Nygard 2011
  - GTD inbox → triage → engage
