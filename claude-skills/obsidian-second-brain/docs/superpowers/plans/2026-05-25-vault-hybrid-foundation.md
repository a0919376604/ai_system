# Vault Hybrid Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the user's Obsidian vault into a hybrid layout where `langlive-line-oa` lives in a project-scoped sub-tree, and modify 14 slash commands plus 2 CLAUDE.md files so they route writes correctly. Covers Phases 0-4 of `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md`.

**Architecture:** Vault becomes hybrid — `Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` is self-contained; cross-project artifacts (`Daily/`, `Logs/`, `People/`, `Knowledge/`, `Templates/`, `Reviews/`) stay flat at vault root. Slash commands gain `--project=<name>` routing or are retargeted (e.g., `obsidian-adr` moves from `Knowledge/` to `Projects/<name>/Decisions/`). `obsidian-board` gains an explicit `--refresh` mode that scans codebase git log + spec/plan files. CLAUDE.md proactive rules in both vault and codebase make Claude suggest the right vault command at the right moment (after brainstorm → ADR, after ship → learning).

**Tech Stack:** Markdown slash-command prompts (in `commands/`), Bash for vault filesystem operations, `scripts/build.sh` adapter rebuild, Obsidian wiki-links, AI-first frontmatter (per `references/ai-first-rules.md`).

**Spec:** `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md` — read this before starting if any task feels under-specified.

---

## File Structure

### Files created

- `~/Documents/SecondBrain.bak-2026-05-25/` — backup (Phase 0)
- `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md` — relocated hub
- `~/Documents/SecondBrain/Projects/langlive-line-oa/board.md` — relocated board
- `~/Documents/SecondBrain/Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/.gitkeep` — folder skeleton

### Files modified (in repo `commands/`)

- `commands/obsidian-capture.md`
- `commands/obsidian-emerge.md`
- `commands/obsidian-graduate.md`
- `commands/obsidian-project.md`
- `commands/obsidian-board.md` ← biggest change (adds `--refresh` mode)
- `commands/obsidian-task.md`
- `commands/obsidian-adr.md` ← retarget from `Knowledge/` to `Projects/<name>/Decisions/`
- `commands/obsidian-learn.md` ← extend to write `Projects/<name>/Learnings/`
- `commands/obsidian-recap.md`
- `commands/research.md`
- `commands/research-deep.md`
- `commands/youtube.md`
- `commands/thread-read.md`
- `commands/discourse-pulse.md`
- `CHANGELOG.md` — bump under "Unreleased"

### Files modified (outside repo)

- `~/Documents/SecondBrain/_CLAUDE.md` — append Part 4-A rules
- `/Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md` — append Part 4-B rules

### Files deleted

- Vault root folders: `Goals/`, `Companies/`, `Mentions/`, `Tasks/`, `Boards/`, `Decisions/`
- Vault root files: `Projects/langlive-query-rewrite.md`, `Projects/claudecode-discord.md`, `Projects/obsidian-second-brain.md`, `Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md`, `Decisions/2026-05-24-langlive-query-rewrite-approach.md`

---

## Routing helper specification

Every modified command needs a consistent way to resolve the project name and target folder. This pattern is referenced by all command modifications below — implement once mentally, repeat per command.

**Project resolution (priority order):**

1. Explicit flag in `$ARGUMENTS`: detect `--project=<name>` or `--project <name>`
2. Vault `_CLAUDE.md` active-project line: read `## Active main project` section, take the first word
3. Codebase `CLAUDE.md` declaration: if the current working directory matches a codebase declared in vault `_CLAUDE.md` `local-path:` mappings, use that project name
4. If none resolved: fall back to default (root folder) — do NOT prompt; the user will explicitly use the flag when they want routing

**Path mapping (once project is resolved):**

| Note kind | Without project | With project `<P>` |
|---|---|---|
| Idea | `Ideas/<title>.md` | `Projects/<P>/Ideas/<title>.md` |
| Task | (legacy `Tasks/`; deprecated by this plan) | `Projects/<P>/Tasks/T-<seq>-<slug>.md` |
| ADR | (was `Knowledge/ADR-...`; deprecated) | `Projects/<P>/Decisions/YYYY-MM-DD-<slug>.md` |
| Learning | (was `wiki/concepts/`; deprecated for project-scoped use) | `Projects/<P>/Learnings/YYYY-MM-DD-<slug>.md` |
| Research | `Research/<sub>/...` | `Projects/<P>/Research/<slug>.md` |
| Recap | `Reviews/<...>.md` | `Projects/<P>/Recaps/YYYY-WXX.md` |
| Board | (root `Boards/<P>.md` — deprecated) | `Projects/<P>/board.md` |
| Project hub | `Projects/<P>.md` (deprecated) | `Projects/<P>/<P>.md` |

**Where to embed this:** Each modified command file gains a `## Project routing` section near the top of the numbered steps, with a 4-line summary of the resolution order and a one-line note about its target folder under each mode. Keep it short — the command file is a prompt, not documentation.

---

## Phase 0 — Backup

### Task 1: Snapshot the vault

**Files:**
- Create: `~/Documents/SecondBrain.bak-2026-05-25/`

- [ ] **Step 1: Confirm vault path exists**

Run:
```bash
ls -d ~/Documents/SecondBrain && echo "VAULT_OK"
```
Expected: a directory listing line, then `VAULT_OK`.

- [ ] **Step 2: Create a full copy as backup**

Run:
```bash
cp -R ~/Documents/SecondBrain ~/Documents/SecondBrain.bak-2026-05-25
```

- [ ] **Step 3: Verify backup integrity**

Run:
```bash
diff -rq ~/Documents/SecondBrain ~/Documents/SecondBrain.bak-2026-05-25 | head
```
Expected: no output (no differences).

- [ ] **Step 4: Snapshot current repo commit**

Run (in repo):
```bash
git rev-parse HEAD > /tmp/obsidian-sb-pre-migration-sha.txt && cat /tmp/obsidian-sb-pre-migration-sha.txt
```
Expected: a 40-char SHA (this is `82335ba...` or similar after the spec commit).

- [ ] **Step 5: No commit needed for this task** (vault operations are outside the repo; the SHA file is local-only).

---

## Phase 1 — Vault cleanup (destructive)

### Task 2: Delete legacy root folders

**Files:**
- Delete: `~/Documents/SecondBrain/{Goals,Companies,Mentions,Tasks,Boards,Decisions}/`

- [ ] **Step 1: List what's about to be deleted**

Run:
```bash
ls ~/Documents/SecondBrain/Goals/ ~/Documents/SecondBrain/Companies/ ~/Documents/SecondBrain/Mentions/ ~/Documents/SecondBrain/Tasks/ ~/Documents/SecondBrain/Boards/ ~/Documents/SecondBrain/Decisions/ 2>&1
```
Expected: only `langlive-line-oa.md` under `Boards/` and `2026-05-24-langlive-query-rewrite-approach.md` under `Decisions/`; the other folders are empty.

- [ ] **Step 2: Verify the two non-empty ones are about to be relocated/deleted in later tasks**

The `Boards/langlive-line-oa.md` will be relocated in Task 5. The `Decisions/...langlive-query-rewrite...md` will be deleted in Task 3 (other-project cleanup). So both removals are accounted for — proceed.

- [ ] **Step 3: Move `Boards/langlive-line-oa.md` to a temp location**

Run:
```bash
mv ~/Documents/SecondBrain/Boards/langlive-line-oa.md /tmp/langlive-line-oa-board.md
```

- [ ] **Step 4: Delete the six legacy folders**

Run:
```bash
rm -rf ~/Documents/SecondBrain/{Goals,Companies,Mentions,Tasks,Boards,Decisions}
```

- [ ] **Step 5: Verify deletion**

Run:
```bash
for d in Goals Companies Mentions Tasks Boards Decisions; do test -e ~/Documents/SecondBrain/$d && echo "STILL_EXISTS: $d" || echo "deleted: $d"; done
```
Expected: 6 lines of `deleted: <folder>`.

### Task 3: Delete other-project files

**Files:**
- Delete: `Projects/{langlive-query-rewrite,claudecode-discord,obsidian-second-brain}.md`, `Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md`

- [ ] **Step 1: List what's about to be deleted**

Run:
```bash
ls ~/Documents/SecondBrain/Projects/langlive-query-rewrite.md ~/Documents/SecondBrain/Projects/claudecode-discord.md ~/Documents/SecondBrain/Projects/obsidian-second-brain.md ~/Documents/SecondBrain/Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md 2>&1
```
Expected: 4 file paths printed (no errors).

- [ ] **Step 2: Delete the 4 files**

Run:
```bash
rm ~/Documents/SecondBrain/Projects/langlive-query-rewrite.md ~/Documents/SecondBrain/Projects/claudecode-discord.md ~/Documents/SecondBrain/Projects/obsidian-second-brain.md ~/Documents/SecondBrain/Ideas/2026-05-24-llm-query-rewrite-langlive-rag.md
```

- [ ] **Step 3: Verify deletion**

Run:
```bash
ls ~/Documents/SecondBrain/Projects/ ~/Documents/SecondBrain/Ideas/
```
Expected: `Projects/` should contain only `langlive-line-oa.md` (which Task 4 relocates); `Ideas/` should be empty or contain only items unrelated to deleted projects.

---

## Phase 2 — Build langlive-line-oa sub-tree

### Task 4: Create folder skeleton

**Files:**
- Create: `~/Documents/SecondBrain/Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/`

- [ ] **Step 1: Create the sub-tree**

Run:
```bash
mkdir -p ~/Documents/SecondBrain/Projects/langlive-line-oa/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}
```

- [ ] **Step 2: Add `.gitkeep` placeholders** (vault isn't git-tracked but this keeps tools happy and signals "this folder is intentional"):

Run:
```bash
for d in Ideas Tasks Decisions Learnings Research Competitors Recaps; do touch ~/Documents/SecondBrain/Projects/langlive-line-oa/$d/.gitkeep; done
```

- [ ] **Step 3: Verify structure**

Run:
```bash
find ~/Documents/SecondBrain/Projects/langlive-line-oa -maxdepth 2 -type d | sort
```
Expected: 8 lines — the parent plus 7 sub-folders.

### Task 5: Relocate hub + board, update wikilinks

**Files:**
- Move: `~/Documents/SecondBrain/Projects/langlive-line-oa.md` → `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md`
- Move: `/tmp/langlive-line-oa-board.md` → `~/Documents/SecondBrain/Projects/langlive-line-oa/board.md`

- [ ] **Step 1: Move hub note into sub-tree**

Run:
```bash
mv ~/Documents/SecondBrain/Projects/langlive-line-oa.md ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md
```

- [ ] **Step 2: Move board into sub-tree (from /tmp where Task 2 staged it)**

Run:
```bash
mv /tmp/langlive-line-oa-board.md ~/Documents/SecondBrain/Projects/langlive-line-oa/board.md
```

- [ ] **Step 3: Update wikilinks inside the board**

Open `~/Documents/SecondBrain/Projects/langlive-line-oa/board.md`. Replace every occurrence of `[[Projects/langlive-line-oa]]` with `[[langlive-line-oa]]`.

Run:
```bash
sed -i.bak 's|\[\[Projects/langlive-line-oa\]\]|[[langlive-line-oa]]|g' ~/Documents/SecondBrain/Projects/langlive-line-oa/board.md && rm ~/Documents/SecondBrain/Projects/langlive-line-oa/board.md.bak
```

- [ ] **Step 4: Update wikilinks inside the hub**

Open `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md`. Replace every occurrence of `[[Boards/langlive-line-oa]]` with `[[board]]`.

Run:
```bash
sed -i.bak 's|\[\[Boards/langlive-line-oa\]\]|[[board]]|g' ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md && rm ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md.bak
```

- [ ] **Step 5: Verify links resolve**

Run:
```bash
grep -n "\[\[" ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md ~/Documents/SecondBrain/Projects/langlive-line-oa/board.md | head -20
```
Expected: no `[[Projects/langlive-line-oa]]` or `[[Boards/langlive-line-oa]]` appear; only `[[langlive-line-oa]]`, `[[board]]`, and unrelated wikilinks (e.g., `[[Companies/LangLive]]` which we'll fix in Step 6) remain.

- [ ] **Step 6: Fix dangling links to deleted entities**

The hub references `[[Companies/LangLive]]` which no longer exists (we deleted `Companies/` in Task 2). Update to `[[LangLive]]` or `[[People/LangLive]]` depending on where you want LangLive to live going forward. For now, downgrade to plain text so the link doesn't dangle:

Open `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md` and replace `[[Companies/LangLive]]` with `LangLive (TBD — see Open Questions)`. Update the `## Open Questions` section to add a bullet: `Decide where LangLive (the company) lives — probably People/ with a 'type: company' frontmatter field, or revive a Companies/ folder if multiple companies accumulate.`

- [ ] **Step 7: No commit needed** (vault is not git-tracked).

### Task 6: Add notion frontmatter + This Week section to hub

**Files:**
- Modify: `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md`

- [ ] **Step 1: Read the current hub frontmatter**

Open `~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md`. The current frontmatter ends at line 15 (the `---` after `ai-first: true`).

- [ ] **Step 2: Insert Notion ID block into frontmatter**

Just before the closing `---` of the frontmatter, add:

```yaml
notion:
  main_page_id: ""
  weekly_recaps_db_id: ""
  decisions_archive_page_id: ""
local-path: "/Users/leric/Desktop/code/langlive-line-oa"
```

(`local-path` is used by `/obsidian-board --refresh` and project-resolution logic; without it the routing helper can't find the codebase.)

- [ ] **Step 3: Add a `## 🔥 This Week` section after `## Overview`**

Insert this block after the `## Overview` section (before `## Recent Activity`):

```markdown
## 🔥 This Week

> Updated weekly by the Saturday recap cron (Plan 2). Manual edits OK between runs.

### Now (≤3)
_(none yet — populated by first Saturday recap)_

### Next
_(none yet)_

### Later
_(none yet)_
```

- [ ] **Step 4: Verify the file still parses as valid frontmatter + markdown**

Run:
```bash
head -25 ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md
```
Expected: frontmatter block (with the new notion + local-path) closes cleanly with `---`, then markdown body begins.

- [ ] **Step 5: No commit needed** (vault not git-tracked).

---

## Phase 3 — Modify slash commands

Each command modification is a small, focused task. Commit after each logical group so rollback is easy.

### Task 7: Modify `commands/obsidian-capture.md`

**Files:**
- Modify: `commands/obsidian-capture.md`

- [ ] **Step 1: Open the file and read current step 4**

The current step 4 reads:
```
4. If new: create `Ideas/Title.md` with minimal frontmatter (`date`, `tags: [idea]`)
```

- [ ] **Step 2: Add `## Project routing` block after the `$ARGUMENTS` description**

Insert after line 9 (the line that starts `The optional argument is the idea text...`):

```markdown

## Project routing

Resolve project name in priority order: (1) `--project=<name>` flag in `$ARGUMENTS`; (2) `## Active main project` line in vault `_CLAUDE.md`; (3) codebase CLAUDE.md `local-path` match for the current working directory; (4) none — write to root `Ideas/` (default).

Target folder:
- No project resolved → `Ideas/<title>.md`
- Project `<P>` resolved → `Projects/<P>/Ideas/<title>.md`
```

- [ ] **Step 3: Update step 3 and step 4 to use the resolved path**

Replace:
```
3. Search `Ideas/` for a related existing note — if found, append to it
4. If new: create `Ideas/Title.md` with minimal frontmatter (`date`, `tags: [idea]`)
```
With:
```
3. Search the resolved Ideas folder (root `Ideas/` or `Projects/<P>/Ideas/`) for a related existing note — if found, append to it
4. If new: create `<resolved-Ideas-path>/Title.md` with minimal frontmatter (`date`, `tags: [idea]` + `project: "[[<P>]]"` if project resolved)
```

- [ ] **Step 4: Verify the file still has the AI-first rule footer** (do not touch it).

- [ ] **Step 5: Smoke test logic by reading the file end-to-end**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-capture.md
```
Expected: file reads coherently with new `## Project routing` section and updated steps. AI-first footer still present.

- [ ] **Step 6: No individual commit yet** (commit at end of capture+emerge group, Task 8).

### Task 8: Modify `commands/obsidian-emerge.md` and commit Idea-family group

**Files:**
- Modify: `commands/obsidian-emerge.md`

- [ ] **Step 1: Read current content**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-emerge.md
```

- [ ] **Step 2: Add `## Project routing` block (same shape as Task 7)** after the argument description.

Use this content (adapted from Task 7):

```markdown

## Project routing

Resolve project name in priority order: (1) `--project=<name>` flag in `$ARGUMENTS`; (2) `## Active main project` line in vault `_CLAUDE.md`; (3) codebase CLAUDE.md `local-path` match for cwd; (4) none — read/write root `Ideas/` (default).

Target folder:
- No project resolved → `Ideas/`
- Project `<P>` resolved → `Projects/<P>/Ideas/`
```

- [ ] **Step 3: Update the steps that read/write `Ideas/`** to use the resolved path. Specifically, replace any literal `Ideas/` reference with "the resolved Ideas folder".

- [ ] **Step 4: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-emerge.md
```
Expected: routing section present, steps reference resolved path.

- [ ] **Step 5: Commit Idea-family group**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/obsidian-capture.md commands/obsidian-emerge.md
git commit -m "feat(commands): add --project routing to capture + emerge"
```

### Task 9: Modify `commands/obsidian-graduate.md`

**Files:**
- Modify: `commands/obsidian-graduate.md`

- [ ] **Step 1: Read current step 5 (project note creation) and step 6 (board entries)**

The current step 5 reads:
```
5. Generate a full project spec:
   - **Project note** in `Projects/` with complete frontmatter ...
```

The current step 6 reads:
```
6. Create board entries:
   - Add a card to the relevant kanban board in `Backlog` or `This Week`
   - Add individual task cards if multiple phases
```

- [ ] **Step 2: Add `## Project routing` block** (graduate is unique — it always creates a project, so the project name comes from the argument or from the idea being graduated):

```markdown

## Project routing

The project name comes from `$ARGUMENTS` (if it's a project name) or is inferred from the idea title. Once resolved, graduate ALWAYS uses the sub-folder layout — there is no flat-mode for new projects.

Created structure:
- `Projects/<P>/<P>.md` (hub note)
- `Projects/<P>/board.md` (kanban; created with empty Now/Next/Later sections + a `## 待辦` section)
- `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` (empty skeleton folders)
```

- [ ] **Step 3: Replace step 5 with project-scoped creation**

Replace step 5 with:

```markdown
5. Generate a full project spec:
   - **Hub note** at `Projects/<P>/<P>.md` with complete frontmatter (`date`, `tags: [project]`, `status: planning`, `linked-idea: [[<idea-title>]]`, `notion: { main_page_id: "", weekly_recaps_db_id: "", decisions_archive_page_id: "" }`, `local-path: "<TBD — ask user>"`)
   - **Description**: what this project is and why it matters
   - **Goals**: 3-5 concrete outcomes
   - **Open Questions**: what still needs answering
   - **Related notes**: links to everything relevant found in step 4
   - **Sub-folder skeleton**: create `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` and add a `.gitkeep` in each
```

- [ ] **Step 4: Replace step 6 with the new board path**

Replace step 6 with:

```markdown
6. Create the project's board:
   - Create `Projects/<P>/board.md` with a `For future Claude` preamble, frontmatter (`type: board`, `project: "[[<P>]]"`, `ai-first: true`), and skeleton sections:
     ```
     ## 🔥 This Week
     ### Now (≤3)
     ### Next
     ### Later

     ## 待辦

     ## 進行中

     ## 已完成
     ```
   - The board's topic buckets (UI / UX / KB / Performance, etc.) populate later via `/obsidian-board <P> --refresh` once the project accumulates work.
```

- [ ] **Step 5: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-graduate.md
```
Expected: routing section + updated steps 5 and 6.

- [ ] **Step 6: Commit after Task 10** (graduate+project group).

### Task 10: Modify `commands/obsidian-project.md` and commit group

**Files:**
- Modify: `commands/obsidian-project.md`

- [ ] **Step 1: Replace step 4 (currently writes to `Projects/Project Name.md`)** with sub-folder layout.

Old step 4:
```
4. If not found: create `Projects/Project Name.md` with full frontmatter schema (`date`, `tags: [project]`, `status: active`, `job`)
```

New step 4:
```
4. If not found: create `Projects/<project-name>/<project-name>.md` (with the sub-folder skeleton `Projects/<project-name>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/`) and full frontmatter schema (`date`, `tags: [project]`, `status: active`, `job`, `notion: { main_page_id: "", weekly_recaps_db_id: "", decisions_archive_page_id: "" }`, `local-path: ""`)
```

- [ ] **Step 2: Update step 6 (currently writes board card)** to reference the new board path.

Old step 6:
```
6. Add a card to the relevant kanban board in the `📥 Backlog` or `🔨 In Progress` column
```

New step 6:
```
6. Add a card to `Projects/<project-name>/board.md` in the `## 待辦` section (creating the board file via the same template as `/obsidian-graduate` if it doesn't exist)
```

- [ ] **Step 3: Smoke read both files**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-graduate.md /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-project.md
```

- [ ] **Step 4: Commit project-creation group**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/obsidian-graduate.md commands/obsidian-project.md
git commit -m "feat(commands): graduate + project create sub-folder layout"
```

### Task 11: Modify `commands/obsidian-board.md` — biggest change

**Files:**
- Modify: `commands/obsidian-board.md`

- [ ] **Step 1: Read current file**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-board.md
```

- [ ] **Step 2: Rewrite the entire command body** (preserving frontmatter and AI-first footer) to support two modes.

Replace lines 7-18 (everything between the frontmatter `---` and the AI-first separator `---`) with this body:

```
Use the obsidian-second-brain skill. Execute `/obsidian-board $ARGUMENTS`:

The first argument is a board name (project name). Optional second flag: `--refresh` (regenerate from git history) or `--full` (force full rebuild, default is incremental). Without `--refresh`, this is interactive: read the board and ask what changes to make.

## Project routing

The board name resolves to a project. Boards always live at `Projects/<name>/board.md` (the legacy `Boards/<name>.md` flat location is no longer used — migrate if found).

To locate the codebase for `--refresh`: read `Projects/<name>/<name>.md` frontmatter for `local-path:`. If missing, ask the user once and persist it back to the frontmatter.

## Modes

### Interactive mode (no `--refresh`)

1. Read `_CLAUDE.md` first if it exists in the vault root
2. If a board name is given, look for `Projects/<name>/board.md`; if not found, search `Projects/*/board.md` (fuzzy match)
3. If no name given, list available boards (one per `Projects/*/board.md`) and ask which one
4. Read and display the current board state: 🔥 This Week (Now/Next/Later), 待辦, 進行中, 已完成, plus any topic buckets
5. Ask if the user wants to make updates — if yes, infer changes from conversation context
6. Move completed items to ✅ 已完成 with strikethrough, add new items in the right column
7. Flag any items that are overdue (`@{date}` past) or stuck (in same column > 1 week per `last-moved:` timestamp)

### Refresh mode (`--refresh` flag set)

1. Resolve `local-path` from `Projects/<name>/<name>.md` frontmatter
2. Read `Projects/<name>/board.md` frontmatter for `last-refresh:` timestamp (full rebuild if missing or `--full` passed)
3. Scan codebase for new work since `last-refresh`:
   - `cd <local-path> && git log --all --since=<last-refresh> --pretty=format:"%H %s %D"` — capture commits + branch names
   - `ls -t <local-path>/docs/superpowers/specs/*.md <local-path>/docs/superpowers/plans/*.md` — list spec/plan files; keep those modified since `last-refresh`
4. Cluster discovered items into topic buckets:
   - Preserve existing bucket names from the current `board.md` if present (`## Customer Service tools`, `## Chat / LINE messaging`, etc.)
   - For items not matching any existing bucket: group by spec/plan title keywords; if uncertain, create or extend an "## Misc / Untriaged" bucket
5. Classify each item's status:
   - ✅ Done: a commit referencing the item landed on the trunk branch (main/master)
   - 🔨 In Progress: an active `brainstorm/*` branch references it, or a spec/plan exists without a trunk merge
   - 📋 Backlog: spec exists but no implementation activity
6. Write the regenerated board to `Projects/<name>/board.md`:
   - **PRESERVE** these sections from the existing file (do not overwrite):
     - `## For future Claude` preamble
     - Frontmatter (just update `last-refresh:` timestamp and totals)
     - `## 🔥 This Week` section (manually maintained)
     - `## Patterns observed` section, if present (only re-compute totals)
     - `## Bucket summary` table (recompute counts)
   - **REGENERATE** the topic bucket sections (Done / In Progress / Backlog within each)
7. Append one line to `Logs/YYYY-MM-DD.md`:
   `**HH:MM** - board | <name> refreshed - N done, M in-flight, P backlog across K buckets`
8. Update `last-refresh:` timestamp in board frontmatter to now (for next incremental run)
9. Report a one-line summary to the caller (used by the daily-cron prompt to decide whether to post Discord notification — see Plan 2)
```

- [ ] **Step 3: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-board.md
```
Expected: file has two clear mode sections (Interactive + Refresh), frontmatter unchanged, AI-first footer present.

- [ ] **Step 4: Commit standalone**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/obsidian-board.md
git commit -m "feat(commands): /obsidian-board gains --refresh mode + sub-folder path"
```

### Task 12: Modify `commands/obsidian-task.md`

**Files:**
- Modify: `commands/obsidian-task.md`

- [ ] **Step 1: Read current step 4-6**

Current:
```
4. Search for the right kanban board — use `_CLAUDE.md` board list or search `Boards/`
5. Add the task card to the correct column (`📋 This Week` or `📥 Backlog` depending on due date)
6. Create a task note in `Tasks/` if the task is substantial (more than a one-liner)
```

- [ ] **Step 2: Add `## Project routing` block** (task is always project-scoped — there's no cross-project task list):

```markdown

## Project routing

Tasks are always project-scoped. Resolve project name from `$ARGUMENTS` (`--project=<name>`), then from vault `_CLAUDE.md` `## Active main project`, then from codebase CLAUDE.md. If unresolvable, ASK the user — do not write to a default location.

Target paths:
- Task note: `Projects/<P>/Tasks/T-<seq>-<slug>.md` (where `<seq>` is the next zero-padded sequence number from existing tasks in that folder; e.g., `T-007-add-rag-context.md`)
- Board card: appended to `Projects/<P>/board.md` `## 待辦` section, linking the task note
```

- [ ] **Step 3: Replace steps 4-6** with:

```
4. Resolve project (see Project routing above)
5. Compute next task sequence: `ls Projects/<P>/Tasks/T-*.md 2>/dev/null | sort | tail -1` → increment the number; if none, start at `T-001`
6. Add the task card to `Projects/<P>/board.md` `## 待辦` section (or `## 🔥 This Week` → `### Next` if the user signals urgency)
7. Create the task note at `Projects/<P>/Tasks/T-<seq>-<slug>.md` if the task is substantial (more than a one-liner). Use this frontmatter:
   ```
   ---
   date: YYYY-MM-DD
   type: task
   project: "[[<P>]]"
   status: backlog
   priority: 🔴|🟡|🟢
   due: YYYY-MM-DD or null
   spec_path: ""        # filled by Checkpoint 1 after superpowers/brainstorming runs
   ai-first: true
   ---
   ```
```

(The original step 7, "Link the task from the relevant project note and today's daily note", becomes step 8.)

- [ ] **Step 4: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-task.md
```

- [ ] **Step 5: Commit after Task 13** (task+adr+learn group).

### Task 13: Modify `commands/obsidian-adr.md` — retarget to Decisions/

**Files:**
- Modify: `commands/obsidian-adr.md`

- [ ] **Step 1: Replace step 3 (current target is `Knowledge/ADR-YYYY-MM-DD — Title.md`)** with the new project-scoped target.

Old step 3:
```
3. Create a decision record at `Knowledge/ADR-YYYY-MM-DD — Title.md`:
```

New step 3 (preserve the YAML+sections block underneath; only the path changes):
```
3. Create a decision record at `Projects/<P>/Decisions/YYYY-MM-DD-<slug>.md`:

   (Where `<P>` is the resolved project name — see Project routing block below.
   If no project resolves, ASK the user which project — never write ADRs to root.)
```

- [ ] **Step 2: Add `## Project routing` block** above the numbered steps:

```markdown

## Project routing

ADRs are project-scoped. Resolve project name in priority: (1) `--project=<name>` in `$ARGUMENTS`; (2) vault `_CLAUDE.md` active project; (3) codebase CLAUDE.md. If none resolves: ASK the user — never default to `Knowledge/` (legacy) or root.

Target: `Projects/<P>/Decisions/YYYY-MM-DD-<slug>.md`
```

- [ ] **Step 3: Update step 4 to use the new path**

Old:
```
4. Update the relevant project note's Key Decisions section with a link to the ADR
```

New (more explicit):
```
4. Append to the resolved project hub's `## Key Decisions` section (`Projects/<P>/<P>.md`) with a one-line entry: `- YYYY-MM-DD [[<adr-title>]] — <one-line summary>`
```

- [ ] **Step 4: Extend the ADR template to include "What would change my mind"**

Find the YAML+sections block in step 3. After "Consequences" and before "Related", insert:

```
- **What would change my mind**: the falsification condition — what evidence would make us reverse this decision. Without this, the ADR is belief; with it, it's a testable hypothesis.
```

- [ ] **Step 5: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-adr.md
```

- [ ] **Step 6: Commit at Task 14** (with learn).

### Task 14: Modify `commands/obsidian-learn.md` — extend to write project Learnings/

**Files:**
- Modify: `commands/obsidian-learn.md`

- [ ] **Step 1: Read current command**

Current behavior: spawns parallel subagents to review learnings vault-wide, writes a report to `wiki/concepts/YYYY-MM-DD — Learnings Review.md`.

We want to ADD a second mode: capture a single learning at write time (Checkpoint 3 in the spec) — i.e., "I just learned X, write it to Projects/<P>/Learnings/".

- [ ] **Step 2: Update the description in frontmatter**

Old description:
```
description: Review vault learnings, prune stale ones, surface active patterns — the vault's lessons compound or expire
```

New:
```
description: Review vault learnings (default), OR capture a single learning at write time (--capture flag) — the vault's lessons compound or expire
```

- [ ] **Step 3: Add `## Modes` block above the numbered steps**

Insert after the `$ARGUMENTS` description:

```markdown

## Modes

### Capture mode (`--capture` flag)

Use when the user has JUST learned something during dev (Checkpoint 3: post-PR or post-implementation). Write a single learning note.

1. Resolve project (see Project routing below). If unresolvable, ASK.
2. Parse the learning from `$ARGUMENTS` (after the `--capture` flag) or from recent conversation context.
3. Write `Projects/<P>/Learnings/YYYY-MM-DD-<slug>.md`:
   ```
   ---
   date: YYYY-MM-DD
   type: learning
   project: "[[<P>]]"
   tags: [learning, <P>]
   related-task: "[[T-XXX]]"   # if known
   ai-first: true
   ---

   ## For future Claude
   [one-line summary of what was learned + why future-Claude would care]

   ## What I learned
   [the lesson, 2-4 sentences]

   ## How I learned it
   [the trigger — a bug, a successful pattern, a colleague's comment]

   ## When this applies
   [pattern recognition — what situations will hit this again]

   ## Source
   [task / spec / commit SHA]
   ```
4. Append a one-line entry to today's `Logs/YYYY-MM-DD.md`: `**HH:MM** - learn-capture | <P>/<slug> - <one-line>`
5. STOP. Do not run review mode.

### Review mode (no `--capture` flag — default, original behavior)

The existing numbered steps below apply unchanged. They survey the vault.

## Project routing

For capture mode: resolve project name in priority: (1) `--project=<name>` in `$ARGUMENTS`; (2) vault `_CLAUDE.md` active project; (3) codebase CLAUDE.md. If none resolves: ASK — never default.

Target (capture mode): `Projects/<P>/Learnings/YYYY-MM-DD-<slug>.md`
```

- [ ] **Step 4: Leave the existing numbered steps (1-9) unchanged** — they are review mode.

- [ ] **Step 5: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-learn.md
```
Expected: Modes block added; original review steps still present below.

- [ ] **Step 6: Commit task+adr+learn group**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/obsidian-task.md commands/obsidian-adr.md commands/obsidian-learn.md
git commit -m "feat(commands): task/adr/learn → project sub-folder routing"
```

### Task 15: Modify `commands/obsidian-recap.md` — add --project flag

**Files:**
- Modify: `commands/obsidian-recap.md`

- [ ] **Step 1: Read current command**

The current command reads daily notes for a period and synthesizes a recap. Cross-project by default.

- [ ] **Step 2: Add `## Project routing` block**

Insert after the argument description (after line 9):

```markdown

## Project routing

Without a project: vault-wide recap (default behavior — reads all daily notes).
With `--project=<name>` flag: project-scoped recap, output goes to `Projects/<name>/Recaps/YYYY-WXX.md` (ISO week number).

In project mode, also:
- Filter daily-note content to lines tagged or referencing the project
- Read `Projects/<name>/board.md` diff (compare `last-refresh:` boundaries to detect Now/Next/Later changes)
- Read `Projects/<name>/Decisions/` for any ADRs written in the period
- Read `Projects/<name>/Learnings/` for any captures in the period
```

- [ ] **Step 3: Add a step at the end (after current step 7) that writes the recap file**

Append step 8:

```
8. **If `--project=<P>` was used**: save the synthesized recap to `Projects/<P>/Recaps/YYYY-WXX.md` (where WXX is the ISO week number — compute from the period start). Frontmatter:
   ```
   ---
   date: YYYY-MM-DD
   type: recap
   project: "[[<P>]]"
   period: "weekly"
   week: "YYYY-WXX"
   range: "YYYY-MM-DD to YYYY-MM-DD"
   ai-first: true
   ---
   ```
   Sections: `## For future Claude` preamble, `## Shipped`, `## In flight`, `## Decisions made`, `## Learnings`, `## Board diff (Now/Next/Later changes)`, `## Open questions for next week`.

   **If no `--project`**: save to `Reviews/YYYY-MM-DD — Weekly Review.md` (the original location).
```

- [ ] **Step 4: Smoke read**

Run:
```bash
cat /Users/leric/Desktop/code/obsidian-second-brain/commands/obsidian-recap.md
```

- [ ] **Step 5: Commit standalone**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/obsidian-recap.md
git commit -m "feat(commands): /obsidian-recap gains --project flag → Projects/<P>/Recaps/"
```

### Task 16: Modify the 5 research commands

**Files:**
- Modify: `commands/research.md`, `commands/research-deep.md`, `commands/youtube.md`, `commands/thread-read.md`, `commands/discourse-pulse.md`

These all share the same pattern: add a `## Project routing` block, redirect the write path when `--project=<name>` is set.

- [ ] **Step 1: For each of the 5 files, add `## Project routing` block** after the argument/description block. Use this template (adapt the "Default target" to the file's existing path):

```markdown

## Project routing

Without a project: write to default cross-project research folder (`Research/<sub>/YYYY-MM-DD-<slug>.md`).
With `--project=<name>` flag: write to `Projects/<name>/Research/<slug>-<source>.md`, where `<source>` is `web` / `deep` / `yt` / `thread` / `pulse` to distinguish source type.

Frontmatter additions when project-scoped: add `project: "[[<name>]]"` and `tags: [research, <name>, <source-type>]`.
```

- [ ] **Step 2: Per-file path mapping table** (use this when updating each):

| File | Default path (cross-project) | Project mode path |
|---|---|---|
| `research.md` | `Research/Web/YYYY-MM-DD-<slug>.md` | `Projects/<P>/Research/<slug>-web.md` |
| `research-deep.md` | `Research/Deep/YYYY-MM-DD-<slug>.md` | `Projects/<P>/Research/<slug>-deep.md` |
| `youtube.md` | `Research/YouTube/YYYY-MM-DD-<slug>.md` | `Projects/<P>/Research/<slug>-yt.md` |
| `thread-read.md` | `Research/Threads/YYYY-MM-DD-<slug>.md` | `Projects/<P>/Research/<slug>-thread.md` |
| `discourse-pulse.md` | `Research/Pulse/YYYY-MM-DD-<slug>.md` | `Projects/<P>/Research/<slug>-pulse.md` |

- [ ] **Step 3: In each file, update the "save to" step to use the conditional path**

For example, in `research.md` (step 5 reads `Save to Research/Web/...`), replace with:
```
5. Save to:
   - `Research/Web/YYYY-MM-DD-<slug>.md` (default, no project)
   - OR `Projects/<P>/Research/<slug>-web.md` (if `--project=<P>` was passed)
```

Apply the same shape to the other 4 files using the path mapping table above.

- [ ] **Step 4: Smoke read all 5**

Run:
```bash
for f in research research-deep youtube thread-read discourse-pulse; do
  echo "=== $f ==="
  cat /Users/leric/Desktop/code/obsidian-second-brain/commands/$f.md | grep -A 3 "Project routing\|Save to\|save to"
done
```
Expected: each file has the routing block + the updated save-to step.

- [ ] **Step 5: Commit research family**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add commands/research.md commands/research-deep.md commands/youtube.md commands/thread-read.md commands/discourse-pulse.md
git commit -m "feat(commands): research family gains --project routing"
```

### Task 17: Rebuild adapter dist for all platforms

**Files:**
- Modify: `dist/{claude-code,codex-cli,gemini-cli,opencode}/...` (regenerated)

- [ ] **Step 1: Run the adapter build**

Run:
```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
bash scripts/build.sh
```
Expected: no errors. Output mentions each platform's adapter ran.

- [ ] **Step 2: Verify dist was regenerated**

Run:
```bash
ls -la dist/ 2>/dev/null | head -10
```
Expected: 4 platform directories present (or whichever the build emits).

- [ ] **Step 3: Spot-check that one of the modified commands made it through to claude-code dist**

Run:
```bash
grep -l "Project routing" dist/claude-code/.claude/commands/*.md 2>/dev/null | head -5
```
Expected: at least 5 files match (capture, emerge, graduate, project, board — among others).

- [ ] **Step 4: Commit dist refresh** (if dist/ is committed in this repo; check first):

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git status dist/ 2>&1 | head -5
```

If dist/ is gitignored (per the repo CLAUDE.md, it should be), no commit needed for this step.

If dist/ is tracked, commit:
```bash
git add dist/
git commit -m "build: regenerate dist for all platforms after command updates"
```

### Task 18: Bump CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read current CHANGELOG**

Run:
```bash
head -30 /Users/leric/Desktop/code/obsidian-second-brain/CHANGELOG.md
```

- [ ] **Step 2: Add an "Unreleased" section (or append to the existing one)** with this entry:

```markdown
## Unreleased

### Changed
- **Project-scoped vault routing**: 14 slash commands now accept `--project=<name>` and route writes to `Projects/<name>/{Ideas,Tasks,Decisions,Learnings,Research,Recaps}/` sub-folders. Without the flag, default behavior is preserved (writes to vault root). See `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md` for the design rationale.
- **`/obsidian-adr` retargeted**: ADRs now write to `Projects/<P>/Decisions/` (was `Knowledge/ADR-...`). Aligns with industry convention. ADR template now includes "What would change my mind" field.
- **`/obsidian-learn` gains `--capture` mode**: write a single learning at the moment of insight (Checkpoint 3 in the spec). The original review-mode is still the default.
- **`/obsidian-board` gains `--refresh` mode**: regenerates the board from codebase git log + spec/plan scan + bucket classification. Preserves manual sections (`## 🔥 This Week`, `## For future Claude` preamble, frontmatter).
- **`/obsidian-graduate` and `/obsidian-project`**: create projects in sub-folder layout (`Projects/<name>/<name>.md` + sub-folder skeleton) instead of flat `Projects/<name>.md`.

### Added
- Plan 1 implementation reference: `docs/superpowers/plans/2026-05-25-vault-hybrid-foundation.md`.
```

- [ ] **Step 3: Smoke read**

Run:
```bash
head -30 /Users/leric/Desktop/code/obsidian-second-brain/CHANGELOG.md
```

- [ ] **Step 4: Commit changelog**

```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git add CHANGELOG.md
git commit -m "docs(changelog): note vault hybrid routing changes"
```

### Task 19: Smoke test each modified command (read-only verification)

Since slash commands are prompt templates, "tests" here mean: render the file, verify the routing block is present, verify the path mappings match the spec.

**Files:**
- Read: all 14 modified command files

- [ ] **Step 1: Routing-block sanity check**

Run:
```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
for f in obsidian-capture obsidian-emerge obsidian-graduate obsidian-project obsidian-board obsidian-task obsidian-adr obsidian-learn obsidian-recap research research-deep youtube thread-read discourse-pulse; do
  echo "=== $f ==="
  grep -c "Project routing" commands/$f.md || echo "MISSING"
done
```
Expected: each command file shows `1` (one `## Project routing` block). If any shows `0` or `MISSING`, return to the corresponding task and add it.

- [ ] **Step 2: Path mapping consistency check**

Run:
```bash
grep "Projects/<P>" commands/*.md | head -30
```
Expected: multiple commands reference `Projects/<P>/<sub>/...` with consistent sub-folder names (`Ideas`, `Tasks`, `Decisions`, `Learnings`, `Research`, `Recaps`). No typos like `Projects/<P>/Idea/` (singular) or `Projects/<P>/Tasks/Tasks/`.

- [ ] **Step 3: AI-first footer still present**

Run:
```bash
for f in commands/*.md; do
  grep -L "AI-first rule" "$f"
done
```
Expected: no output (every file still has the AI-first footer). If any file appears, restore the footer.

- [ ] **Step 4: Verify `commands/obsidian-decide.md` was NOT modified** (it's intentionally untouched — small decisions stay inline in the hub):

Run:
```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git log --oneline commands/obsidian-decide.md | head -3
```
Expected: most recent commit on this file is from before this plan's first commit. (It's untouched, per spec decision S1.i.)

- [ ] **Step 5: No commit** (this is read-only verification).

---

## Phase 4 — CLAUDE.md proactive rules

### Task 20: Append vault `_CLAUDE.md` rules

**Files:**
- Modify: `~/Documents/SecondBrain/_CLAUDE.md`

- [ ] **Step 1: Read current `_CLAUDE.md`**

Run:
```bash
cat ~/Documents/SecondBrain/_CLAUDE.md
```

- [ ] **Step 2: Append the rules block** to the file (at the very end). The block is verbatim from spec Part 4-A:

```markdown

## Active main project

`langlive-line-oa` — when a slash command supports `--project` but no flag is given, default to `langlive-line-oa` unless the conversation context clearly references another project.

## Project-scoped folder routing

For commands that support `--project=<name>` (see spec `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md` Part 2 in the obsidian-second-brain repo):

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
   → If anything substantial: `/obsidian-learn --capture --project=langlive-line-oa`.
   → If a new architectural decision emerged mid-stream: `/obsidian-adr --project=langlive-line-oa`.

3. **When the user says "ship", "deploy", "PR merged"** (or these events are otherwise detected):
   → Check `Projects/langlive-line-oa/Tasks/` for a task whose `spec_path:` matches this work; offer to move the corresponding `board.md` card to ✅ 已完成.

4. **When the user captures an idea via `/obsidian-capture` without `--project`**:
   → If the idea text mentions langlive / LINE OA / smart customer service keywords, ask: "This looks like a langlive-line-oa idea — write to `Projects/langlive-line-oa/Ideas/` instead of root `Ideas/`?"

## Codebase ↔ project mappings

| Project | Codebase local path |
|---|---|
| langlive-line-oa | `/Users/leric/Desktop/code/langlive-line-oa` (worktrees `-wt-3`, `-wt-4`) |
```

- [ ] **Step 3: Verify append**

Run:
```bash
tail -50 ~/Documents/SecondBrain/_CLAUDE.md
```
Expected: the appended rules block is at the end.

- [ ] **Step 4: No commit** (vault not git-tracked).

### Task 21: Append codebase `CLAUDE.md` rules

**Files:**
- Modify: `/Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md`

- [ ] **Step 1: Verify the file exists**

Run:
```bash
ls /Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md
```
Expected: file exists. If not, create an empty one with a single H1: `# CLAUDE.md` before proceeding.

- [ ] **Step 2: Append the rules block** at the end of the file:

```markdown

## Vault integration (obsidian-second-brain)

Vault root: `~/Documents/SecondBrain/`
This project's vault home: `~/Documents/SecondBrain/Projects/langlive-line-oa/`

When inside this codebase, treat `langlive-line-oa` as the implicit `--project` for any obsidian-second-brain slash command that supports project routing.

PROACTIVE: see vault `_CLAUDE.md` "Proactive prompts" section — those four rules apply here. Specifically:

- After `superpowers/brainstorming` selects an approach → proactively suggest `/obsidian-adr --project=langlive-line-oa` with pre-filled Options + Choice + Reasoning + "What would change my mind" from the brainstorm transcript.
- After `superpowers/finishing-a-development-branch` completes → ask "What did you learn?" and offer `/obsidian-learn --capture --project=langlive-line-oa` if anything substantial.
- When the user says "ship" / "PR merged" → look for the matching task in `~/Documents/SecondBrain/Projects/langlive-line-oa/Tasks/` (where `spec_path:` frontmatter points back at this codebase's spec) and offer to move the board card to ✅ 已完成.
```

- [ ] **Step 3: Verify append**

Run:
```bash
tail -30 /Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md
```

- [ ] **Step 4: Commit in the langlive-line-oa repo** (a separate git repo from this one):

```bash
cd /Users/leric/Desktop/code/langlive-line-oa
git add CLAUDE.md
git commit -m "docs(claude): integrate vault routing + proactive checkpoint rules"
```

---

## Phase 4 sanity check — full system smoke test

### Task 22: End-to-end verification

This is a dry-run verification that all 4 phases hang together.

**Files:**
- Read-only: verify state of vault + repo + langlive-line-oa CLAUDE.md

- [ ] **Step 1: Vault structure sanity check**

Run:
```bash
find ~/Documents/SecondBrain -maxdepth 3 -type d | sort | head -30
```
Expected to see:
- Top-level: `Daily, Dev Logs, Ideas, Knowledge, Logs, People, Projects, Research, Reviews, Templates` (10 folders)
- Inside `Projects/langlive-line-oa/`: 7 sub-folders (`Ideas, Tasks, Decisions, Learnings, Research, Competitors, Recaps`)
- NOT present: `Goals, Companies, Mentions, Tasks, Boards, Decisions` at root

- [ ] **Step 2: Hub note has new frontmatter**

Run:
```bash
head -25 ~/Documents/SecondBrain/Projects/langlive-line-oa/langlive-line-oa.md
```
Expected: frontmatter includes `notion:` block (with 3 empty IDs) and `local-path: "/Users/leric/Desktop/code/langlive-line-oa"`.

- [ ] **Step 3: Board has updated wikilinks**

Run:
```bash
grep -c "\[\[Projects/langlive-line-oa\]\]" ~/Documents/SecondBrain/Projects/langlive-line-oa/board.md
```
Expected: `0` (all old-style links rewritten).

- [ ] **Step 4: Repo commit history shows the 7 expected commits**

Run:
```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
git log --oneline | head -10
```
Expected: 7-9 new commits since the spec commit (`82335ba`), covering:
- capture+emerge
- graduate+project
- board (--refresh mode)
- task+adr+learn
- recap (--project)
- research family
- changelog
- (possibly dist if tracked)

- [ ] **Step 5: All 14 modified commands have routing blocks**

Run:
```bash
cd /Users/leric/Desktop/code/obsidian-second-brain
grep -L "Project routing\|## Modes" commands/{obsidian-capture,obsidian-emerge,obsidian-graduate,obsidian-project,obsidian-board,obsidian-task,obsidian-adr,obsidian-learn,obsidian-recap,research,research-deep,youtube,thread-read,discourse-pulse}.md
```
Expected: no output (every listed file contains `Project routing` or `## Modes`).

- [ ] **Step 6: CLAUDE.md files have the rules**

Run:
```bash
grep -c "Proactive prompts\|Project-scoped folder routing" ~/Documents/SecondBrain/_CLAUDE.md
grep -c "Vault integration\|PROACTIVE" /Users/leric/Desktop/code/langlive-line-oa/CLAUDE.md
```
Expected: both > 0.

- [ ] **Step 7: Plan 1 complete — declare done**

Mark Phase 4 done in your tracking. Plan 2 (Phases 5-7: Notion + crons + dry-run) can now start cleanly because all the routing logic exists.

---

## Notes for the executing agent

- **Vault is not git-tracked.** Filesystem ops on `~/Documents/SecondBrain/` won't show up in `git status`. The Phase 0 backup is your safety net for Phases 1-2.
- **Codebase langlive-line-oa is a separate git repo.** Phase 4 Task 21 commits there, not in obsidian-second-brain.
- **`dist/` is gitignored** per repo CLAUDE.md. Step 4 of Task 17 should usually be a no-op commit.
- **AI-first rule** at the bottom of every command file is sacred — never strip it. If a command file ends without it, restore from a sibling.
- **Test the obsidian-board.md change manually** by running `/obsidian-board langlive-line-oa --refresh` after Task 11 against the migrated board. The expected outcome: incremental git log + spec/plan scan runs without error; existing topic-bucket sections (Customer Service tools, Chat / LINE messaging, etc.) are preserved; ✅ Done counts roughly match the pre-migration count of 59 (give or take a few based on the `--since` cutoff). If counts are wildly off, run with `--full` to force a full rebuild from scratch.
- **If you discover the existing command file already references new sub-folder paths** (because someone else already started this work), do NOT duplicate. Diff carefully before editing.

---

## What Plan 2 will cover (preview, do not implement here)

- Task: Confirm Notion main page `langlive-line-oa` exists (or create on first cron run)
- Task: `/schedule create` Saturday 12:00 recap cron
- Task: `/schedule create` Mon-Fri 09:00 board-refresh cron
- Task: Dry-run the full Saturday pipeline end-to-end (recap → Chinese translation → Discord channel → Notion MCP writes)
- Task: One-week soak test, log friction into the spec's startup checklist

End of Plan 1.
