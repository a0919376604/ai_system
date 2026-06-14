# AIR-OS Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `/Users/leric/Documents/SecondBrain` from Life OS into AI Research OS (AIR-OS) per PRD v1.0, preserving 15 deep research dossiers.

**Architecture:** Big-bang switch. Archive old vault to `SecondBrain.archive-2026-06-14/` (kept on disk, outside new vault). Build fresh AIR-OS at original path with 8 PRD folders, 11 templates, 7 MOCs, dashboard, and operating manual. Migrate 15 research notes via `cp` + frontmatter rewrite script. Pure Obsidian + Templates + Dataview + manual workflow — no `obsidian-second-brain` skill commands.

**Tech Stack:** Filesystem (`mkdir`, `cp`, `git`), Python 3 (frontmatter rewrite via `yaml` stdlib), Obsidian Dataview plugin.

**Spec:** `docs/superpowers/specs/2026-06-14-obsidian-air-os-vault-design.md`

---

## File Structure

All implementation work produces files at `/Users/leric/Documents/SecondBrain/`. The `ai_system` repo only holds this plan; no implementation code commits go here.

```
/Users/leric/Documents/SecondBrain/                    [new vault]
├── .gitignore                                          [Task 2]
├── .git/                                               [Task 2 — vault has its own git]
├── _CLAUDE.md                                          [Task 8]
├── index.md                                            [Task 9]
├── 00 Inbox/                                           [Task 2 — empty]
├── 10 Projects/
│   └── _archive/                                       [Task 2 — empty]
├── 20 Research/
│   ├── LLM/                                            [Task 2 — empty]
│   ├── Agents/                                         [Task 10 — 15 migrated files]
│   ├── MCP/                                            [Task 2 — empty]
│   ├── RAG/                                            [Task 2 — empty]
│   ├── Prompt Engineering/                             [Task 2 — empty]
│   ├── Evaluation/                                     [Task 2 — empty]
│   └── _cross-domain/                                  [Task 2 — empty]
├── 30 Engineering/                                     [Task 2 — empty]
├── 40 Knowledge/
│   ├── Concepts/                                       [Task 2 — empty]
│   ├── Prompt Library/                                 [Task 2 — empty]
│   ├── MCP Catalog/                                    [Task 2 — empty]
│   └── Synthesis/                                      [Task 2 — empty]
├── 50 Journal/                                         [Task 2 — empty]
├── 90 MOCs/                                            [Task 7 — 7 MOC stubs]
│   ├── AI MOC.md
│   ├── Agent MOC.md                                    [+seeded in Task 12]
│   ├── MCP MOC.md
│   ├── RAG MOC.md
│   ├── Architecture MOC.md
│   ├── Prompt Engineering MOC.md
│   └── Evaluation MOC.md
├── 99 Archive/                                         [Task 2 — empty]
├── _assets/                                            [Task 2 — gitignored]
└── _templates/                                         [Tasks 3-6 — 11 templates]
    ├── research-template.md                            [Task 3]
    ├── concept-template.md                             [Task 3]
    ├── project-template.md                             [Task 3]
    ├── decision-template.md                            [Task 4]
    ├── task-template.md                                [Task 4]
    ├── journal-template.md                             [Task 5]
    ├── moc-template.md                                 [Task 5]
    ├── synthesis-template.md                           [Task 5]
    ├── prompt-template.md                              [Task 6]
    ├── mcp-template.md                                 [Task 6]
    └── engineering-template.md                         [Task 6]

/Users/leric/Documents/SecondBrain.archive-2026-06-14/  [Task 1 — renamed from old]
~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14/      [Task 1 — cold backup]
```

**Migration helper script (temporary, not committed)**:
- `/tmp/air-os-migrate-frontmatter.py` — Task 10

---

## Task 1: Pre-flight Backup + Archive Old Vault

**Files:**
- Source: `/Users/leric/Documents/SecondBrain` (old vault, 132 notes)
- Backup: `~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14/`
- Archive: `/Users/leric/Documents/SecondBrain.archive-2026-06-14/`

- [ ] **Step 1: Verify the two existing snapshots are intact**

Run:
```bash
ls -la /Users/leric/Documents/SecondBrain.bak-2026-05-25 | head -3
ls -la /Users/leric/Documents/SecondBrain | head -3
```

Expected: Both directories exist and are populated. If either is missing, STOP and ask the user.

- [ ] **Step 2: Create cold backup in Dropbox (or alternate cloud target)**

Run:
```bash
mkdir -p ~/Dropbox/_archive
cp -R /Users/leric/Documents/SecondBrain ~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14
```

Verify:
```bash
ls ~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14 | wc -l
```

Expected: same number of top-level entries as source (≥ 14 — Daily, Dev Logs, Ideas, Knowledge, Logs, People, Projects, Research, Reviews, Templates, lukalabs, _CLAUDE.md, index.md, log.md plus assets).

If Dropbox is not available, substitute another path the user provides. **Do NOT skip this step.**

- [ ] **Step 3: Confirm Obsidian app is closed**

Manually: ensure Obsidian.app is not running (Cmd+Q). The next step renames the vault path, which corrupts open vault state if Obsidian holds the directory.

- [ ] **Step 4: Archive (rename) old vault**

Run:
```bash
mv /Users/leric/Documents/SecondBrain \
   /Users/leric/Documents/SecondBrain.archive-2026-06-14
```

Verify:
```bash
ls -d /Users/leric/Documents/SecondBrain 2>/dev/null && echo "ERROR: path still exists"
ls -d /Users/leric/Documents/SecondBrain.archive-2026-06-14
```

Expected: First line prints nothing or "ERROR" (it should NOT exist). Second line prints the archive path.

- [ ] **Step 5: No commit (no new vault repo yet)**

The new vault's git repo is initialized in Task 2. The archived old vault's git history (if any) stays inside `SecondBrain.archive-2026-06-14/.git/`.

---

## Task 2: Scaffold New AIR-OS Directory Tree

**Files:**
- Create: `/Users/leric/Documents/SecondBrain/` (new root)
- Create: 22 subdirectories
- Create: `/Users/leric/Documents/SecondBrain/.gitignore`
- Initialize: `/Users/leric/Documents/SecondBrain/.git/`

- [ ] **Step 1: Define the verification (run BEFORE doing work)**

Run:
```bash
ls -d /Users/leric/Documents/SecondBrain 2>/dev/null && echo "exists" || echo "missing"
```

Expected: "missing" (Task 1 archived it).

- [ ] **Step 2: Create root + all 22 subdirectories**

Run:
```bash
mkdir -p /Users/leric/Documents/SecondBrain
cd /Users/leric/Documents/SecondBrain

mkdir -p "00 Inbox"
mkdir -p "10 Projects/_archive"
mkdir -p "20 Research"/{LLM,Agents,MCP,RAG,"Prompt Engineering",Evaluation,_cross-domain}
mkdir -p "30 Engineering"
mkdir -p "40 Knowledge"/{Concepts,"Prompt Library","MCP Catalog",Synthesis}
mkdir -p "50 Journal"
mkdir -p "90 MOCs"
mkdir -p "99 Archive"
mkdir -p _templates _assets
```

- [ ] **Step 3: Verify directory tree**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
find . -maxdepth 2 -type d | sort
```

Expected (22 directories + root, exact set):
```
.
./_assets
./_templates
./00 Inbox
./10 Projects
./10 Projects/_archive
./20 Research
./20 Research/Agents
./20 Research/Evaluation
./20 Research/LLM
./20 Research/MCP
./20 Research/Prompt Engineering
./20 Research/RAG
./20 Research/_cross-domain
./30 Engineering
./40 Knowledge
./40 Knowledge/Concepts
./40 Knowledge/MCP Catalog
./40 Knowledge/Prompt Library
./40 Knowledge/Synthesis
./50 Journal
./90 MOCs
./99 Archive
```

- [ ] **Step 4: Create `.gitignore`**

Write `/Users/leric/Documents/SecondBrain/.gitignore`:
```
# Obsidian local state
.obsidian/workspace*
.obsidian/cache
.trash/

# Large assets (attachments — not version-controlled)
_assets/

# OS noise
.DS_Store
```

- [ ] **Step 5: Initialize git**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
git init -b main
git add .gitignore
git commit -m "init: AIR-OS scaffold (8 PRD folders + .gitignore)"
```

Verify:
```bash
git log --oneline
```

Expected: 1 commit, "init: AIR-OS scaffold...".

---

## Task 3: Main Templates (research / concept / project)

**Files:**
- Create: `_templates/research-template.md`
- Create: `_templates/concept-template.md`
- Create: `_templates/project-template.md`

- [ ] **Step 1: Write `_templates/research-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: research
source: paper                    # paper | repository | blog | youtube | podcast | docs | tweet
tags: [research]
ai-first: true
title: ""
url: ""
domain: ""                       # LLM | Agent | MCP | RAG | Prompt | Eval
read-status: skimmed             # skimmed | read | deep
confidence: high
related-concepts: []
moc: []
sources: []
# source-conditional fields (fill those that apply):
authors: []
venue: ""
year:
code: ""
stars:
language: ""
key-files: []
last-checked:
duration: ""
---

## For future Claude
> 2-3 句白話：這份 source 在解什麼？我學到什麼？為何收藏？

## Summary
## Key Insights / Interesting Ideas
## How It Works / Method / Architecture
## Limitations / What's Missing
## Quotes / Code Snippets
## My Take
## Related Concepts
- [[Concept A]]
- [[Concept B]]
```

- [ ] **Step 2: Write `_templates/concept-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: concept
tags: [concept]
ai-first: true
name: ""
domain: ""                       # LLM | Agent | MCP | RAG | Prompt | Eval | Architecture | Engineering
maturity: nascent                # nascent | maturing | established
first-seen: {{date}}
related-concepts: []
moc: []
confidence: high
---

## For future Claude
> 一句話：這個概念是什麼？為何重要？

## Definition
## Why Important
## How It Works
## Examples
- [[Research X]] — how it's used
- [[Repository Y]] — implementation
## Advantages
## Limitations
## Related Concepts
```

- [ ] **Step 3: Write `_templates/project-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: project
tags: [project]
ai-first: true
status: active                   # active | paused | archived
start-date: {{date}}
archetype: ""
repo: ""
local-path: ""
related-concepts: []
moc: []
---

## For future Claude
> 這個專案在做什麼？為什麼存在？當前 status？

## Goal
## Success Criteria
## Scope
## Architecture
## Milestones
## Tasks
> 詳見資料夾內 `task-*.md`
## Decisions
> 詳見資料夾內 `adr-*.md`
## Risks
```

- [ ] **Step 4: Verify all 3 templates contain `ai-first: true` + `## For future Claude`**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in _templates/research-template.md _templates/concept-template.md _templates/project-template.md; do
  echo "=== $f ==="
  grep -c "ai-first: true" "$f"
  grep -c "## For future Claude" "$f"
done
```

Expected: each file prints `1` and `1` (one match per pattern per file).

- [ ] **Step 5: Commit**

```bash
cd /Users/leric/Documents/SecondBrain
git add _templates/
git commit -m "init: main templates (research, concept, project)"
```

---

## Task 4: Project-Scoped Templates (decision / task)

**Files:**
- Create: `_templates/decision-template.md`
- Create: `_templates/task-template.md`

- [ ] **Step 1: Write `_templates/decision-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: decision
tags: [decision, adr]
ai-first: true
decision-status: proposed        # proposed | accepted | superseded | rejected
project: ""                      # [[Project Name]] wikilink
options: []
chosen: ""
supersedes: ""
superseded-by: ""
confidence: high
---

## For future Claude
> 這個決策在解什麼問題？我選了什麼？為什麼？

## Context
## Options
- Option A: ...
- Option B: ...
## Decision
## Reasoning
## Consequences
## What would change my mind
## Related Concepts
```

- [ ] **Step 2: Write `_templates/task-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: task
tags: [task]
ai-first: true
task-status: backlog             # backlog | in-progress | done | cancelled
project: ""                      # [[Project Name]] wikilink
priority: medium                 # low | medium | high | critical
due:
spec-path: ""
---

## For future Claude
> 這個 task 在做什麼？驗收條件？

## Goal
## Acceptance
- [ ] Criterion 1
- [ ] Criterion 2
## Subtasks
- [ ] Subtask 1
## Notes
## Related Concepts
```

- [ ] **Step 3: Verify both files**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in _templates/decision-template.md _templates/task-template.md; do
  grep -c "ai-first: true" "$f"
  grep -c "## For future Claude" "$f"
done
```

Expected: four `1` lines.

- [ ] **Step 4: Commit**

```bash
git add _templates/decision-template.md _templates/task-template.md
git commit -m "init: project-scoped templates (decision, task)"
```

---

## Task 5: Knowledge Templates (journal / moc / synthesis)

**Files:**
- Create: `_templates/journal-template.md`
- Create: `_templates/moc-template.md`
- Create: `_templates/synthesis-template.md`

- [ ] **Step 1: Write `_templates/journal-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: journal
tags: [journal]
ai-first: true
---

## For future Claude
> {{date}} 的工作 / 學習紀錄。

## Done today
## Learned
## Decisions
## Tomorrow
```

- [ ] **Step 2: Write `_templates/moc-template.md`**

````markdown
---
date: {{date}}
updated: {{date}}
type: moc
tags: [moc]
ai-first: true
domain: ""                       # LLM | Agent | MCP | RAG | Architecture | Prompt | Eval
maintained-via: both             # hand | dataview | both
---

## For future Claude
> <Domain> 領域的入口。
> 我目前對 <domain> 的判斷：（待填一句 stance）

## 🧠 核心概念（hand-curated）
- 

## 📚 必讀研究（hand-curated, in reading order）
1. 

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "<domain-tag>") OR domain = "<Domain>"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "<Domain>"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[<Domain> MOC]])
```
````

- [ ] **Step 3: Write `_templates/synthesis-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: synthesis
tags: [synthesis]
ai-first: true
synthesizes: []                  # list of wikilinks to source notes
timeframe: ""                    # e.g., "Week of 2026-06-14" or "May 2026"
confidence: high
---

## For future Claude
> 這份 synthesis 整合了哪些 source？得出什麼跨域結論？

## Synthesizes
- [[Source A]]
- [[Source B]]

## Convergent Insights
## Divergent Views
## My Current Take
## Related Concepts
```

- [ ] **Step 4: Verify all 3 files**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in _templates/journal-template.md _templates/moc-template.md _templates/synthesis-template.md; do
  grep -c "ai-first: true" "$f"
  grep -c "## For future Claude" "$f"
done
```

Expected: six `1` lines.

- [ ] **Step 5: Commit**

```bash
git add _templates/journal-template.md _templates/moc-template.md _templates/synthesis-template.md
git commit -m "init: knowledge templates (journal, moc, synthesis)"
```

---

## Task 6: Catalog Templates (prompt / mcp / engineering)

**Files:**
- Create: `_templates/prompt-template.md`
- Create: `_templates/mcp-template.md`
- Create: `_templates/engineering-template.md`

- [ ] **Step 1: Write `_templates/prompt-template.md`**

````markdown
---
date: {{date}}
updated: {{date}}
type: prompt
tags: [prompt]
ai-first: true
use-case: ""
models-tested: []
prompt-type: system              # system | user | function-calling | other
---

## For future Claude
> 這個 prompt 解什麼？用在什麼情境？哪個 model 跑過？

## Use case
## Models tested
- 

## Prompt body
```
<prompt content here>
```

## Variations
## Failure modes
## Related Concepts
````

- [ ] **Step 2: Write `_templates/mcp-template.md`**

````markdown
---
date: {{date}}
updated: {{date}}
type: mcp
tags: [mcp]
ai-first: true
name: ""
url: ""
transport: stdio                 # stdio | sse | http
maturity: experimental           # experimental | stable
last-checked: {{date}}
---

## For future Claude
> 這個 MCP server 提供什麼？我為何收藏？目前 maturity？

## Purpose
## Transport
## Setup
```bash
<setup commands>
```

## Tools provided
- 

## My evaluation
## Related Concepts
````

- [ ] **Step 3: Write `_templates/engineering-template.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: engineering
tags: [engineering]
ai-first: true
technology: ""
category: pattern                # pattern | debug | learning | comparison
confidence: high
---

## For future Claude
> 這個技術筆記在講什麼？什麼 stack？

## Context
## Pattern or Solution
## Trade-offs
## References
## Related Concepts
```

- [ ] **Step 4: Verify all 3 files**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in _templates/prompt-template.md _templates/mcp-template.md _templates/engineering-template.md; do
  grep -c "ai-first: true" "$f"
  grep -c "## For future Claude" "$f"
done
```

Expected: six `1` lines.

- [ ] **Step 5: Verify total template count = 11**

Run:
```bash
ls _templates/*.md | wc -l
```

Expected: `11`.

- [ ] **Step 6: Commit**

```bash
git add _templates/prompt-template.md _templates/mcp-template.md _templates/engineering-template.md
git commit -m "init: catalog templates (prompt, mcp, engineering)"
```

---

## Task 7: Create 7 MOC Stubs

**Files:**
- Create: `90 MOCs/AI MOC.md`
- Create: `90 MOCs/Agent MOC.md`
- Create: `90 MOCs/MCP MOC.md`
- Create: `90 MOCs/RAG MOC.md`
- Create: `90 MOCs/Architecture MOC.md`
- Create: `90 MOCs/Prompt Engineering MOC.md`
- Create: `90 MOCs/Evaluation MOC.md`

Each MOC follows the same template, only `domain`, tag, and Dataview filter changing.

- [ ] **Step 1: Write `90 MOCs/AI MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, ai]
ai-first: true
domain: AI
maintained-via: both
---

## For future Claude
> AI / LLM 領域的入口。涵蓋 LLM 基礎、訓練、推理、評估。
> 我目前對 AI 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "ai") OR domain = "LLM" OR domain = "AI"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "LLM" OR domain = "AI"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[AI MOC]])
```
````

- [ ] **Step 2: Write `90 MOCs/Agent MOC.md`**

Same template with these substitutions (everything else identical to Step 1):
- `tags: [moc, agent]`
- `domain: Agent`
- Header comment: "Agent 領域的入口。AI agents、multi-agent system、agent architecture。"
- Dataview WHERE clauses: `contains(tags, "agent") OR domain = "Agent"` (Research + Concept queries) and `contains(moc, [[Agent MOC]])` (Projects query)

Full file:

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, agent]
ai-first: true
domain: Agent
maintained-via: both
---

## For future Claude
> Agent 領域的入口。AI agents、multi-agent system、agent architecture。
> 我目前對 Agent 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補 — Task 12 會 seed 4 個 stub）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補 — Task 12 會 seed 4 篇）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "agent") OR domain = "Agent"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "Agent"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[Agent MOC]])
```
````

- [ ] **Step 3: Write `90 MOCs/MCP MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, mcp]
ai-first: true
domain: MCP
maintained-via: both
---

## For future Claude
> MCP（Model Context Protocol）生態的入口。Server / Client / Tool 設計。
> 我目前對 MCP 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "mcp") OR domain = "MCP"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "MCP"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[MCP MOC]])
```
````

- [ ] **Step 4: Write `90 MOCs/RAG MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, rag]
ai-first: true
domain: RAG
maintained-via: both
---

## For future Claude
> RAG（Retrieval-Augmented Generation）領域的入口。Retrieval / Reranking / Chunking / Eval。
> 我目前對 RAG 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "rag") OR domain = "RAG"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "RAG"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[RAG MOC]])
```
````

- [ ] **Step 5: Write `90 MOCs/Architecture MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, architecture]
ai-first: true
domain: Architecture
maintained-via: both
---

## For future Claude
> Architecture 領域的入口。系統設計模式、跨專案架構抉擇。
> 我目前對 Architecture 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "architecture") OR domain = "Architecture"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "Architecture"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[Architecture MOC]])
```
````

- [ ] **Step 6: Write `90 MOCs/Prompt Engineering MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, prompt]
ai-first: true
domain: Prompt
maintained-via: both
---

## For future Claude
> Prompt Engineering 領域的入口。Prompt 設計、CoT、few-shot、role-play。
> 我目前對 Prompt Engineering 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "prompt") OR domain = "Prompt"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "Prompt"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[Prompt Engineering MOC]])
```
````

- [ ] **Step 7: Write `90 MOCs/Evaluation MOC.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, eval]
ai-first: true
domain: Eval
maintained-via: both
---

## For future Claude
> Evaluation 領域的入口。LLM / agent / RAG eval 方法、framework、benchmark。
> 我目前對 Evaluation 的判斷：（待填）

## 🧠 核心概念（hand-curated）
- （待補）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補）

## 🔬 全部相關研究（Dataview auto）
```dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "eval") OR domain = "Eval"
SORT file.mtime DESC
```

## 💡 全部相關 Concept（Dataview auto）
```dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "Eval"
SORT maturity DESC, first-seen DESC
```

## 🛠 使用此 MOC 的專案（Dataview auto）
```dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[Evaluation MOC]])
```
````

- [ ] **Step 8: Verify all 7 MOCs exist + carry mandatory fields**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
ls "90 MOCs/" | wc -l
for f in "90 MOCs/"*.md; do
  echo "=== $f ==="
  grep -c "ai-first: true" "$f"
  grep -c "## For future Claude" "$f"
  grep -c "type: moc" "$f"
done
```

Expected: `7` from `wc -l`. Each file prints three `1` lines.

- [ ] **Step 9: Commit**

```bash
git add "90 MOCs/"
git commit -m "init: 7 MOC stubs (AI, Agent, MCP, RAG, Architecture, Prompt Engineering, Evaluation)"
```

---

## Task 8: `_CLAUDE.md` Operating Manual

**Files:**
- Create: `_CLAUDE.md`

- [ ] **Step 1: Write `_CLAUDE.md` (verbatim from spec §10)**

````markdown
# Claude Operating Manual — Leric's AIR-OS Vault

> Read this file before doing anything in this vault.
> This is the single source of truth for how Claude operates here.

## Vault settings

- output-lang: zh-TW
- vault-name: AIR-OS (AI Research OS)
- vault-version: 1.0 (PRD v1.0)

All commands that write notes use Traditional Chinese (zh-TW) for prose.
Code identifiers, frontmatter keys, enum values, wikilink paths, and sentinel
comments remain English regardless. Per-call override via `--lang=en`.

---

## Section 0 — AI-First Vault Rule (read first, applies to every note)

This vault is designed for **future-Claude** to read and reason over, not
for human review. The owner rarely reads notes directly — they call Claude
to retrieve, synthesize, and connect dots across years of accumulated knowledge.

**Every note Claude writes must follow:**

1. **Self-contained context** — Each note must explain itself. Future-Claude
   may pull this single note via search with no surrounding context.
2. **"For future Claude" preamble** — Every note begins with a 2-3 sentence
   summary in plain language under a `## For future Claude` header.
3. **Rich, consistent frontmatter** — `type`, `date`, `updated`, `tags`,
   `ai-first: true`, plus type-specific fields per Frontmatter Requirements below.
4. **Recency markers per claim** — When stating external facts, attach the date:
   `Mem0 raised $24M (as of 2026-04)`.
5. **Sources preserved verbatim** — Every external claim has its source URL inline.
6. **Cross-links are mandatory** — Every person, project, idea, decision, or
   concept referenced uses `[[wikilinks]]`. Create stub notes for missing targets.
7. **Confidence levels** — Mark claims as `stated | high | medium | speculation`.

---

## Section 0.5 — Verify Live State Before Acting

Before declaring a fact, drafting a fix, or writing architecture: verify the
live state. Speculation from stale context burns hours.

Specific cues:
- Fetch live time, dates, and rates (never infer from training data)
- Read the actual repo / paper before summarizing — don't reconstruct from memory
- Re-check stars, last release, last commit on `last-checked` refresh

---

## Vault Identity

- **Owner:** Leric
- **Primary purpose:** AI Research OS — 個人知識作業系統，AI 研究 + Agent
  Engineering + MCP 生態 + 軟體開發 + 架構設計 + 技術學習 + PKM
- **Vault root:** `/Users/leric/Documents/SecondBrain`
- **Prior vault archived at:** `/Users/leric/Documents/SecondBrain.archive-2026-06-14`
- **Last updated:** 2026-06-14

---

## Folder Map

| Folder | Purpose | Note types |
|---|---|---|
| `00 Inbox/` | Unsorted capture (3-day decay) | `note` |
| `10 Projects/<name>/` | My own projects (ADR, task scattered inside) | `project`, `decision`, `task`, `note` |
| `20 Research/<domain>/` | Research-source notes (paper/repo/blog/youtube) | `research` |
| `30 Engineering/` | Cross-project tech notes | `engineering` |
| `40 Knowledge/Concepts/` | Concept Notes (PRD core: one concept one note) | `concept` |
| `40 Knowledge/Prompt Library/` | Prompt collection | `prompt` |
| `40 Knowledge/MCP Catalog/` | MCP server records | `mcp` |
| `40 Knowledge/Synthesis/` | Cross-research syntheses | `synthesis` |
| `50 Journal/` | Per-day notes + weekly review | `journal` |
| `90 MOCs/` | 7 knowledge-domain MOCs | `moc` |
| `99 Archive/` | Retired projects / concepts / research | (preserves type) |
| `_templates/` | Templates (do not auto-modify) | — |
| `_assets/` | Images, attachments | — |

`20 Research/` subfolders: LLM / Agents / MCP / RAG / Prompt Engineering /
Evaluation / _cross-domain

---

## Key Files

- **Catalog + Dashboard:** [[index]] — read FIRST to navigate the vault
- **This manual:** [[_CLAUDE]]

---

## Active Context

> Update this section at the start of each major focus period.

**Current top priority:** TBD
**Local code workspace:** `/Users/leric/Desktop/code/`

---

## Frontmatter Requirements

Every note minimum:
```yaml
---
date: YYYY-MM-DD
updated: YYYY-MM-DD
type: <note-type>
tags: [<type>]
ai-first: true
---
```

Note types: `research` | `concept` | `project` | `decision` | `task`
          | `journal` | `moc` | `prompt` | `mcp` | `synthesis`
          | `engineering` | `note` | `index`

Type-specific schemas: see each template in `_templates/`.

---

## Naming Conventions

- Journal: `50 Journal/YYYY-MM-DD.md` or `YYYY-WXX.md` (weekly review)
- Research: `<descriptive-kebab-case>.md` (no date prefix; date in frontmatter)
- Concept: `<Concept Name>.md` (Title Case with spaces)
- Project: `10 Projects/<repo-name>/<repo-name>.md`
- ADR: `10 Projects/<name>/adr-NNN-<topic>.md`
- Task: `10 Projects/<name>/task-<topic>.md`
- MOC: `<Domain> MOC.md`

---

## Concept Note Workflow (PRD §10 + operational rules)

```
Research source → Research Note → Concept Note → MOC → Project → Output
```

**Concept extraction triggers**:
- Same concept appears in ≥ 2 research notes
- You've used the concept to explain ≥ 2 other things
- Research surfaces a core term you don't fully understand (create as stub)

**Concept Maturity evolution**:
- `nascent`: stub + Definition + source wikilink
- `maturing`: + How It Works + Examples + Related Concepts
- `established`: all 7 sections + your judgment (you can teach in 5 min)

**MOC update timing**: new Concept created, Concept upgrades maturity, research
graduates to "recommend-to-others", weekly review health check.

**Concept ↔ Project backflow**: when concept used in project, add wikilinks
in both directions.

---

## Auto-Save Behavior (no skill commands — Claude proactively suggests)

When in conversation Claude detects the following, **proactively suggest** saving:

| Signal | Save destination |
|---|---|
| I mention a new paper / repo / blog / video | `20 Research/<domain>/` |
| I explain a concept | `40 Knowledge/Concepts/` (stub or update) |
| I decide a project's tech choice | `10 Projects/<name>/adr-NNN-*.md` |
| I find a stack-level pattern | `30 Engineering/` |
| Undigested idea | `00 Inbox/` |

**Ask before saving**:
- Anything financial / explicitly private
- Any delete / archive action

---

## Weekly Review Convention

Every Sunday evening, create `50 Journal/YYYY-WXX.md`:
- What I Learned (3-5 key insights)
- New Concepts (promoted / created)
- Research This Week (Dataview auto)
- Repositories Studied (Dataview auto)
- Projects Progress (hand: 3-5 sentences)
- Decisions Made (Dataview auto ADRs)
- MOC Health Check (which MOCs to update)
- Next Week Focus (3 items)

---

## Inbox Hygiene Rule

`00 Inbox/` notes older than 3 days appear in Dashboard's Inbox Aging.

Weekly review **must clear Inbox**:
- Unread source → promote to Research Note
- Idea → Concept stub or task
- No value → delete

---

## Do Not Touch

- `_templates/` — Do not modify in normal operations
- `99 Archive/` — Read-only history
- Any `_archived_` prefixed file

---

*Initialized 2026-06-14 from PRD v1.0. Vault was previously SecondBrain
(Life OS + multi-project dev log) — full prior vault preserved at
`/Users/leric/Documents/SecondBrain.archive-2026-06-14`.*
````

- [ ] **Step 2: Verify `_CLAUDE.md` has key sections**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
grep -c "Section 0 — AI-First Vault Rule" _CLAUDE.md
grep -c "Section 0.5 — Verify Live State Before Acting" _CLAUDE.md
grep -c "Concept Note Workflow" _CLAUDE.md
grep -c "Inbox Hygiene Rule" _CLAUDE.md
wc -l _CLAUDE.md
```

Expected: each `grep -c` returns `1`. Line count ~165-180.

- [ ] **Step 3: Commit**

```bash
git add _CLAUDE.md
git commit -m "init: _CLAUDE.md operating manual (AI-First rules + workflows)"
```

---

## Task 9: `index.md` Dashboard

**Files:**
- Create: `index.md`

- [ ] **Step 1: Write `index.md`**

````markdown
---
date: 2026-06-14
updated: 2026-06-14
type: index
tags: [meta, index, dashboard]
ai-first: true
---

## For future Claude
> AIR-OS vault entry point. Read this first to know the current state.
> Lists active projects, recent research, concept bank, inbox status.

## 🧭 Navigation

- [[_CLAUDE]] — Operating manual (read at the start of every Claude session)
- **90 MOCs:** [[AI MOC]] · [[Agent MOC]] · [[MCP MOC]] · [[RAG MOC]] · [[Architecture MOC]] · [[Prompt Engineering MOC]] · [[Evaluation MOC]]

---

## 1️⃣ Active Projects

```dataview
TABLE status, archetype, file.mtime as "Updated", related-concepts
FROM "10 Projects"
WHERE type = "project" AND status = "active"
SORT file.mtime DESC
```

---

## 2️⃣ Recent Research (last 14 days)

```dataview
TABLE source, domain, read-status, confidence
FROM "20 Research"
WHERE type = "research" AND date >= date(today) - dur(14 days)
SORT date DESC
```

---

## 3️⃣ Concept Bank (grouped by domain)

```dataview
TABLE maturity, first-seen, length(related-concepts) as "Links"
FROM "40 Knowledge/Concepts"
WHERE type = "concept"
GROUP BY domain
SORT domain ASC, maturity DESC
```

---

## 4️⃣ Recently Studied Repositories (last 30 days)

```dataview
TABLE language, stars, last-checked, read-status
FROM "20 Research"
WHERE type = "research" AND source = "repository" AND last-checked >= date(today) - dur(30 days)
SORT last-checked DESC
```

---

## 5️⃣ Inbox Aging (≥ 3 days)

```dataview
LIST "📥 " + file.name + " (" + (date(today) - file.ctime).days + " days)"
FROM "00 Inbox"
WHERE (date(today) - file.ctime).days >= 3
SORT file.ctime ASC
```

---

## 6️⃣ Recent ADRs (last 30 days)

```dataview
TABLE decision-status, project, chosen
FROM "10 Projects"
WHERE type = "decision" AND date >= date(today) - dur(30 days)
SORT date DESC
```
````

- [ ] **Step 2: Verify `index.md` has 6 Dataview blocks + Navigation**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
grep -c '^```dataview$' index.md
grep -c "## 🧭 Navigation" index.md
grep -c "ai-first: true" index.md
```

Expected: `6`, `1`, `1`.

- [ ] **Step 3: Commit**

```bash
git add index.md
git commit -m "init: index.md dashboard (6 Dataview blocks + navigation)"
```

---

## Task 10: Migrate 15 Deep Research Dossiers

**Files:**
- Create (temp): `/tmp/air-os-migrate-frontmatter.py`
- Create: 15 files under `20 Research/Agents/` (see table below)
- Source: 15 files under `/Users/leric/Documents/SecondBrain.archive-2026-06-14/`

**Migration table** (old path → new filename, all under `20 Research/Agents/`):

| # | Source (under `SecondBrain.archive-2026-06-14/`) | New filename |
|---|---|---|
| 1 | `Research/Web/2026-05-25-agent-memory-short-long-term-design.md` | `agent-memory-short-long-term-design.md` |
| 2 | `Research/Web/2026-05-29-lunatalk-story-ai-rpg-core-tech.md` | `lunatalk-story-ai-rpg-core-tech.md` |
| 3 | `Research/Web/2026-05-29-companion-chat-vs-story-rpg-retention.md` | `companion-chat-vs-story-rpg-retention.md` |
| 4 | `Projects/ai-eden-service/Research/replika-deep-tech-and-companion-architecture-deep.md` | `replika-deep-tech.md` |
| 5 | `Projects/ai-eden-service/Research/miramind-replika-framework-and-langgraph-fit-deep.md` | `miramind-replika-langgraph.md` |
| 6 | `Projects/ai-eden-service/Research/lukalabs-replika-research-deep.md` | `lukalabs-replika.md` |
| 7 | `Projects/ai-eden-service/Research/memory-storyline-interaction-deep.md` | `memory-storyline-interaction.md` |
| 8 | `Projects/ai-eden-service/Research/character-storyline-mismatch-deep.md` | `character-storyline-mismatch.md` |
| 9 | `Projects/ai-eden-service/Research/world-storyline-desync-deep.md` | `world-storyline-desync.md` |
| 10 | `Projects/ai-eden-service/Research/memory-character-lore-conflict-deep.md` | `memory-character-lore-conflict.md` |
| 11 | `Projects/ai-eden-service/Research/memory-storyline-temporal-violation-deep.md` | `memory-storyline-temporal-violation.md` |
| 12 | `Projects/ai-eden-service/Research/memory-for-storyline-progression-deep.md` | `memory-for-storyline-progression.md` |
| 13 | `Projects/ai-eden-service/Research/procedural-story-generation-pipeline-deep.md` | `procedural-story-generation-pipeline.md` |
| 14 | `Projects/ai-eden-service/Research/hybrid-authoring-uiux-deep.md` | `hybrid-authoring-uiux.md` |
| 15 | `Projects/ai-eden-service/Research/intimacy-storyline-product-philosophy-deep.md` | `intimacy-storyline-product-philosophy.md` |

- [ ] **Step 1: Write the migration script `/tmp/air-os-migrate-frontmatter.py`**

```python
#!/usr/bin/env python3
"""Migrate 15 deep research dossiers from archived SecondBrain into AIR-OS.

For each source file:
1. Read content + parse existing YAML frontmatter (if any)
2. Build new AIR-OS-conformant frontmatter (merge selected old fields)
3. Write to new vault path under `20 Research/Agents/`
4. Leave archived source untouched (this is a copy, not a move)
"""
import re
import sys
from pathlib import Path

import yaml  # stdlib via PyYAML — install with `pip install pyyaml` if missing

ARCHIVE = Path("/Users/leric/Documents/SecondBrain.archive-2026-06-14")
NEW_VAULT = Path("/Users/leric/Documents/SecondBrain")
MIGRATION_DATE = "2026-06-14"

MIGRATIONS = [
    ("Research/Web/2026-05-25-agent-memory-short-long-term-design.md",
     "agent-memory-short-long-term-design.md"),
    ("Research/Web/2026-05-29-lunatalk-story-ai-rpg-core-tech.md",
     "lunatalk-story-ai-rpg-core-tech.md"),
    ("Research/Web/2026-05-29-companion-chat-vs-story-rpg-retention.md",
     "companion-chat-vs-story-rpg-retention.md"),
    ("Projects/ai-eden-service/Research/replika-deep-tech-and-companion-architecture-deep.md",
     "replika-deep-tech.md"),
    ("Projects/ai-eden-service/Research/miramind-replika-framework-and-langgraph-fit-deep.md",
     "miramind-replika-langgraph.md"),
    ("Projects/ai-eden-service/Research/lukalabs-replika-research-deep.md",
     "lukalabs-replika.md"),
    ("Projects/ai-eden-service/Research/memory-storyline-interaction-deep.md",
     "memory-storyline-interaction.md"),
    ("Projects/ai-eden-service/Research/character-storyline-mismatch-deep.md",
     "character-storyline-mismatch.md"),
    ("Projects/ai-eden-service/Research/world-storyline-desync-deep.md",
     "world-storyline-desync.md"),
    ("Projects/ai-eden-service/Research/memory-character-lore-conflict-deep.md",
     "memory-character-lore-conflict.md"),
    ("Projects/ai-eden-service/Research/memory-storyline-temporal-violation-deep.md",
     "memory-storyline-temporal-violation.md"),
    ("Projects/ai-eden-service/Research/memory-for-storyline-progression-deep.md",
     "memory-for-storyline-progression.md"),
    ("Projects/ai-eden-service/Research/procedural-story-generation-pipeline-deep.md",
     "procedural-story-generation-pipeline.md"),
    ("Projects/ai-eden-service/Research/hybrid-authoring-uiux-deep.md",
     "hybrid-authoring-uiux.md"),
    ("Projects/ai-eden-service/Research/intimacy-storyline-product-philosophy-deep.md",
     "intimacy-storyline-product-philosophy.md"),
]


def split_frontmatter(text: str):
    """Return (old_yaml_dict, body). If no frontmatter, returns ({}, full_text)."""
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
    if not m:
        return {}, text
    try:
        data = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        data = {}
    return data, m.group(2)


def build_new_frontmatter(old: dict) -> dict:
    """Build AIR-OS-conformant frontmatter, preserving useful old fields."""
    return {
        "date": str(old.get("date", MIGRATION_DATE)),
        "updated": MIGRATION_DATE,
        "type": "research",
        "source": "docs",
        "tags": ["research", "agent"],
        "ai-first": True,
        "title": old.get("title", "") or "",
        "url": old.get("url", "") or "",
        "domain": "Agent",
        "read-status": "deep",
        "related-concepts": [],
        "moc": ["[[Agent MOC]]"],
        "confidence": "high",
        "sources": old.get("sources", []) or [],
    }


def migrate_one(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"Source missing: {src}")
    text = src.read_text(encoding="utf-8")
    old_fm, body = split_frontmatter(text)
    new_fm = build_new_frontmatter(old_fm)
    yaml_block = yaml.safe_dump(
        new_fm, sort_keys=False, allow_unicode=True, default_flow_style=False
    )
    new_text = f"---\n{yaml_block}---\n{body}"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(new_text, encoding="utf-8")


def main() -> int:
    target_dir = NEW_VAULT / "20 Research" / "Agents"
    if not target_dir.exists():
        print(f"ERROR: target dir missing: {target_dir}", file=sys.stderr)
        return 1
    for old_rel, new_name in MIGRATIONS:
        src = ARCHIVE / old_rel
        dst = target_dir / new_name
        try:
            migrate_one(src, dst)
            print(f"✓ {new_name}")
        except FileNotFoundError as e:
            print(f"✗ {e}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Verify Python + PyYAML available**

Run:
```bash
python3 -c "import yaml; print('yaml ok:', yaml.__version__)"
```

Expected: prints `yaml ok: <version>`. If `ModuleNotFoundError`, install:
```bash
pip3 install pyyaml
```

- [ ] **Step 3: Run the migration script**

Run:
```bash
python3 /tmp/air-os-migrate-frontmatter.py
```

Expected output: 15 lines starting with `✓`, one per migration.

If any line starts with `✗`, STOP and investigate (source file likely renamed in archive).

- [ ] **Step 4: Verify 15 files exist in target**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
ls "20 Research/Agents/" | wc -l
ls "20 Research/Agents/"
```

Expected: `15`. The 15 filenames match the "New filename" column above.

- [ ] **Step 5: Verify archive untouched**

Run:
```bash
ls /Users/leric/Documents/SecondBrain.archive-2026-06-14/Projects/ai-eden-service/Research/ | wc -l
```

Expected: original count (≥ 12) — script copied, did not move.

- [ ] **Step 6: Commit (without the temp script)**

```bash
cd /Users/leric/Documents/SecondBrain
git add "20 Research/Agents/"
git commit -m "init: migrate 15 deep research dossiers from archived vault

Copied from /Users/leric/Documents/SecondBrain.archive-2026-06-14/
with AIR-OS-conformant frontmatter (type:research, source:docs,
domain:Agent, moc:[[Agent MOC]], ai-first:true).

Old body content preserved verbatim — internal wikilinks pointing to
archived vault paths are accepted as broken (non-goal to repair)."
```

---

## Task 11: Verify Migration Schema Compliance

**Files:**
- Read-only: `20 Research/Agents/*.md` (the 15 migrated files)

- [ ] **Step 1: Verify every migrated file has `ai-first: true`**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
missing=0
for f in "20 Research/Agents/"*.md; do
  if ! grep -q "^ai-first: true$" "$f"; then
    echo "MISSING ai-first: $f"
    missing=$((missing+1))
  fi
done
echo "Missing count: $missing"
```

Expected: `Missing count: 0`.

- [ ] **Step 2: Verify every migrated file has `type: research`**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in "20 Research/Agents/"*.md; do
  head -20 "$f" | grep -q "^type: research$" || echo "MISSING type:research: $f"
done
```

Expected: no output (all files have it).

- [ ] **Step 3: Verify every migrated file has `domain: Agent` and `source: docs`**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in "20 Research/Agents/"*.md; do
  head -20 "$f" | grep -q "^domain: Agent$" || echo "MISSING domain:Agent: $f"
  head -20 "$f" | grep -q "^source: docs$" || echo "MISSING source:docs: $f"
done
```

Expected: no output.

- [ ] **Step 4: Verify `moc` field references Agent MOC**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
for f in "20 Research/Agents/"*.md; do
  head -25 "$f" | grep -q "Agent MOC" || echo "MISSING [[Agent MOC]]: $f"
done
```

Expected: no output.

- [ ] **Step 5: No commit** (verification only — Task 10 already committed)

---

## Task 12: Seed Agent MOC's Hand-Curated Section

**Files:**
- Modify: `90 MOCs/Agent MOC.md`

- [ ] **Step 1: Read current Agent MOC**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
cat "90 MOCs/Agent MOC.md"
```

Confirm it has the placeholder lines:
```
## 🧠 核心概念（hand-curated）
- （待補 — Task 12 會 seed 4 個 stub）

## 📚 必讀研究（hand-curated, in reading order）
1. （待補 — Task 12 會 seed 4 篇）
```

- [ ] **Step 2: Replace "核心概念" placeholder block**

Replace:
```
## 🧠 核心概念（hand-curated）
- （待補 — Task 12 會 seed 4 個 stub）
```

With:
```
## 🧠 核心概念（hand-curated）
> stub wikilinks — concept files don't exist yet; create them organically
> as Section 8 Rule 2 triggers fire.
- [[Long-Term Memory Store]] — agent cross-session memory storage
- [[AI Companion Architecture]] — Replika-style 5-layer companion design
- [[Procedural Story Generation]] — dynamic story generation pipeline
- [[Memory-Storyline Coordination]] — memory-driven storyline progression
```

- [ ] **Step 3: Replace "必讀研究" placeholder block**

Replace:
```
## 📚 必讀研究（hand-curated, in reading order）
1. （待補 — Task 12 會 seed 4 篇）
```

With:
```
## 📚 必讀研究（hand-curated, in reading order）
1. [[agent-memory-short-long-term-design]] — memory landscape (start here)
2. [[lunatalk-story-ai-rpg-core-tech]] — story-RPG 5-layer architecture
3. [[replika-deep-tech]] — companion benchmark implementation
4. [[procedural-story-generation-pipeline]] — World → Arc → Storylet → Scene
```

- [ ] **Step 4: Verify seeds are in place**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
grep -c "Long-Term Memory Store" "90 MOCs/Agent MOC.md"
grep -c "agent-memory-short-long-term-design" "90 MOCs/Agent MOC.md"
grep -c "procedural-story-generation-pipeline" "90 MOCs/Agent MOC.md"
```

Expected: each prints `1`.

- [ ] **Step 5: Commit**

```bash
git add "90 MOCs/Agent MOC.md"
git commit -m "init: seed Agent MOC with 4 concept stubs + 4 reading-order picks

Concept wikilinks are intentionally red (unresolved) — concept notes
will be created organically as the Section 8 Rule 2 triggers fire."
```

---

## Task 13: Smoke Test + Verification

**Files:** None modified. Verification only.

- [ ] **Step 1: Confirm full directory tree**

Run:
```bash
cd /Users/leric/Documents/SecondBrain
find . -maxdepth 2 -type d | sort | grep -v "^\./\.git" | wc -l
```

Expected: 23 (1 root + 22 subdirectories).

- [ ] **Step 2: Confirm template count**

Run:
```bash
ls _templates/*.md | wc -l
```

Expected: `11`.

- [ ] **Step 3: Confirm MOC count**

Run:
```bash
ls "90 MOCs/"*.md | wc -l
```

Expected: `7`.

- [ ] **Step 4: Confirm research migration count**

Run:
```bash
ls "20 Research/Agents/"*.md | wc -l
```

Expected: `15`.

- [ ] **Step 5: Confirm key files**

Run:
```bash
ls _CLAUDE.md index.md .gitignore
```

Expected: all three filenames listed (no "No such file").

- [ ] **Step 6: Confirm git history**

Run:
```bash
git log --oneline
```

Expected (newest first):
```
init: seed Agent MOC with 4 concept stubs + 4 reading-order picks
init: migrate 15 deep research dossiers from archived vault
init: index.md dashboard (6 Dataview blocks + navigation)
init: _CLAUDE.md operating manual (AI-First rules + workflows)
init: 7 MOC stubs (AI, Agent, MCP, RAG, Architecture, Prompt Engineering, Evaluation)
init: catalog templates (prompt, mcp, engineering)
init: knowledge templates (journal, moc, synthesis)
init: project-scoped templates (decision, task)
init: main templates (research, concept, project)
init: AIR-OS scaffold (8 PRD folders + .gitignore)
```

10 commits total.

- [ ] **Step 7: Open Obsidian and add the vault**

Manually:
1. Open Obsidian.app
2. "Open another vault" → "Open folder as vault" → select `/Users/leric/Documents/SecondBrain`
3. Confirm the file tree displays all 8 top-level folders + `_templates` + `_assets`
4. Open `index.md`

- [ ] **Step 8: Install + verify Dataview plugin**

Manually inside Obsidian:
1. Settings → Community plugins → Browse → search "Dataview" → Install → Enable
2. Re-open `index.md`
3. Section §2 "Recent Research" should show **0 rows** (no notes in last 14 days based on `date` frontmatter, which is `2026-05-25` to `2026-05-31` for the migrated 15 — older than 14 days from `2026-06-14`).
4. Section §3 "Concept Bank" — empty (no concepts yet)
5. Section §5 "Inbox Aging" — empty
6. Open `90 MOCs/Agent MOC.md`
7. "🔬 全部相關研究" Dataview section should show **15 rows** (all migrated research)
8. "💡 全部相關 Concept" — empty
9. "🛠 使用此 MOC 的專案" — empty

If §2 returns rows: check `date` field formatting in migrated files (must be ISO date, not quoted string). Fix by editing one file's frontmatter and re-running Dataview.

If Agent MOC §🔬 returns 0 rows: check `domain: Agent` frontmatter value (case-sensitive) and `contains(tags, "agent")` — at least one match required.

- [ ] **Step 9: Install Templates plugin (built-in core plugin)**

Manually:
1. Settings → Core plugins → Templates → Enable
2. Settings → Templates → set "Template folder location" to `_templates`
3. Test: in any folder, Ctrl/Cmd-P → "Templates: Insert template" → see the 11 templates listed

- [ ] **Step 10: Optional — push to GitHub private repo**

If desired:
```bash
cd /Users/leric/Documents/SecondBrain
gh repo create air-os-vault --private --source=. --remote=origin --push
```

- [ ] **Step 11: Final cleanup**

Run:
```bash
rm /tmp/air-os-migrate-frontmatter.py
```

The temp migration script is no longer needed (one-shot use).

- [ ] **Step 12: Done — record vault status**

The AIR-OS vault is operational. Acceptance criteria AC-001 through AC-016 should all be green (verified above). Tier 4 AC-017 through AC-019 (Week 1 workflow validation) verify after the first week of use.

---

## Post-Implementation Notes

**Rollback** (if needed before Week 1 ends and no new notes have been added):

```bash
rm -rf /Users/leric/Documents/SecondBrain
mv /Users/leric/Documents/SecondBrain.archive-2026-06-14 \
   /Users/leric/Documents/SecondBrain
```

Once the owner starts writing new notes into AIR-OS, rollback cost rises — new content lives only in AIR-OS. Backup at `~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14/` remains as a recovery option for the original 132 notes.

**Spec reference:** `docs/superpowers/specs/2026-06-14-obsidian-air-os-vault-design.md`
