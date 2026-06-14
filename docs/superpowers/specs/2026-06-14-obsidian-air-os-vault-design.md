# AIR-OS Vault Restructure — Design Spec

**Spec ID:** 2026-06-14-obsidian-air-os-vault-design
**PRD Source:** `Obsidian_AI_Research_OS_PRD_v1.txt`
**Status:** Draft, pending user review
**Owner:** Leric
**Last updated:** 2026-06-14

---

## 1. Background

Owner currently runs an Obsidian vault at `/Users/leric/Documents/SecondBrain`
(132 notes) as a **Life OS** — multi-project dev logs, decisions, daily logs,
people, ideas. The vault is tightly coupled to a 33-command
`obsidian-second-brain` skill ecosystem with Discord / Notion auto-sync and
project-scoped folder routing.

Owner wants to restructure this vault into an **AI Research OS (AIR-OS)** per
the attached PRD v1.0 — a long-term (3-10 year) personal knowledge OS centered
on AI research, agent engineering, MCP ecosystem study, software development,
architecture design, technical learning, and PKM.

### Decisions taken during brainstorm

| Decision point | Choice | Rationale |
|---|---|---|
| Migration approach | Fresh vault, copy research over | Owner wants clean start |
| Old vault fate | Frozen as archive | One canonical vault going forward |
| Migration scope | All 15 deep research dossiers | 3 from `Research/Web/` + 12 from `Projects/ai-eden-service/Research/` |
| Life OS folders | Hidden inside `10 Projects/<name>/` | Strict PRD; per-project notes share folder, typed via frontmatter |
| Skill ecosystem | AIR-OS does NOT use `obsidian-second-brain` skill | Pure Obsidian + Templates + Dataview + manual |
| AI-First rules | Fully carried over | Preamble + frontmatter + confidence + cross-link mandatory |
| Vault location | Replaces `/Users/leric/Documents/SecondBrain` path | Old vault moves to `SecondBrain.archive-2026-06-14` |
| Migration strategy | Big Bang switch | No skill coupling, only 15 notes to migrate, low parallel-vault risk |
| Research type unification | Single `research` type + `source` field | Resolves PRD §4/§10 inconsistency (paper/repo/blog/youtube all → "Research Note") |
| Research folder split | By `domain` (not by `source`) | LLM / Agents / MCP / RAG / Prompt Engineering / Evaluation / _cross-domain |
| MOC count | 7 (PRD 5 + Prompt Engineering + Evaluation) | Two extra MOCs for actually-used domains |
| MOC maintenance | Hybrid: hand-curated section + Dataview auto | Forces cognitive work; avoids stale & avoids "directory not entry-point" |
| MOC personal commentary section | Dropped | Owner declined "我的演變思考" segment |
| Concept extraction trigger | Same concept in ≥ 2 research notes | Prevents premature abstraction |
| Inbox aging threshold | 3 days | Weekly review clears Inbox |
| Auto-backup | Obsidian Git plugin (recommended) | UI-visible, no cron needed |
| Old vault archive location | Outside new vault (`/Users/leric/Documents/SecondBrain.archive-2026-06-14`) | Avoid polluting new Dataview with old schema |

---

## 2. Goals

### Primary

1. **PRD compliance** — AIR-OS implements PRD v1.0 §3-§12 exactly.
2. **AI-First continuity** — Every note remains optimized for future-Claude
   retrieval (preamble, frontmatter, confidence, cross-links).
3. **Concept-First execution** — Provide workflow rules that make
   "Concept Note as the destination of all knowledge" actionable, not aspirational.
4. **15-note migration** — All deep research dossiers land in AIR-OS with
   conformant frontmatter.
5. **Big-bang switch** — Owner stops writing to old vault and starts writing to
   AIR-OS on the same day.

### Non-Goals

- ❌ Migrating the 33 `obsidian-second-brain` skill commands
- ❌ Maintaining Discord / Notion / langlive auto-sync logic
- ❌ Designing the 4 future AI Agents (PRD §13 — deferred to v2)
- ❌ Repairing wikilinks inside archived old-vault notes
- ❌ Mobile workflow / Obsidian Sync setup
- ❌ Batch-generation tooling for Concept Notes (workflow is human-driven)
- ❌ Migrating 117 non-research notes (project notes, decisions, daily logs,
  people, ideas) — these stay in archived old vault

---

## 3. Folder Structure

```
/Users/leric/Documents/SecondBrain/        ← new vault, original path
├── 00 Inbox/                              ← capture queue (3-day decay)
├── 10 Projects/
│   ├── <project-name>/
│   │   ├── <project-name>.md              ← type: project (PRD §5 sections)
│   │   ├── adr-NNN-<topic>.md             ← type: decision
│   │   ├── task-<topic>.md                ← type: task
│   │   └── note-<topic>.md                ← type: note
│   └── _archive/                          ← finished projects
├── 20 Research/
│   ├── LLM/
│   ├── Agents/
│   ├── MCP/
│   ├── RAG/
│   ├── Prompt Engineering/
│   ├── Evaluation/
│   └── _cross-domain/                     ← spans multiple domains
├── 30 Engineering/                        ← cross-project tech notes
├── 40 Knowledge/
│   ├── Concepts/                          ← Concept Notes (PRD core)
│   ├── Prompt Library/                    ← PRD §8
│   ├── MCP Catalog/                       ← PRD §9
│   └── Synthesis/                         ← cross-research conclusions
├── 50 Journal/                            ← per-day + weekly review
├── 90 MOCs/
│   ├── AI MOC.md
│   ├── Agent MOC.md
│   ├── MCP MOC.md
│   ├── RAG MOC.md
│   ├── Architecture MOC.md
│   ├── Prompt Engineering MOC.md
│   └── Evaluation MOC.md
├── 99 Archive/                            ← future retirees (currently empty)
├── _templates/                            ← 11 templates
├── _assets/                               ← gitignored
├── _CLAUDE.md                             ← AIR-OS operating manual
└── index.md                               ← catalog + dashboard
```

### Design interpretations (where PRD is silent)

| Decision | Interpretation |
|---|---|
| `10 Projects/<name>/` internal layout | No predefined subfolders. ADR / task / note all live in the project folder, typed via frontmatter + filename prefix (`adr-NNN-`, `task-`). Honors PRD's "Link Over Folder". |
| `30 Engineering/` content | Cross-project technical notes: stack learning, debug patterns, architecture comparisons. NOT bound to a single project. |
| `40 Knowledge/Concepts/` location | Concepts live in `40 Knowledge/Concepts/` (not `90 MOCs/`). MOCs are hubs; Concepts are atoms. |
| `99 Archive/` initial state | **Empty**. The old SecondBrain vault goes OUTSIDE the new vault (`SecondBrain.archive-2026-06-14/`) to avoid polluting Dataview with old schema. `99 Archive/` is reserved for future retirees. |
| `_archive/` inside `10 Projects/` | For projects you finish but want to keep visible in this vault. |

### Domain enum (Research vs Concept)

PRD §3 lists `20 Research/` subfolders. We extend the enum slightly because
Concepts are more abstract than Research sources.

| Surface | Enum |
|---|---|
| `20 Research/` subfolders | `LLM` · `Agents` · `MCP` · `RAG` · `Prompt Engineering` · `Evaluation` · `_cross-domain` |
| `research.domain` frontmatter | `LLM` · `Agent` · `MCP` · `RAG` · `Prompt` · `Eval` (singular form; matches folder by mapping) |
| `concept.domain` frontmatter | `LLM` · `Agent` · `MCP` · `RAG` · `Prompt` · `Eval` · `Architecture` · `Engineering` (adds two for cross-cutting concepts) |
| MOC `domain` frontmatter | One per MOC: `AI` · `Agent` · `MCP` · `RAG` · `Architecture` · `Prompt` · `Eval` (PRD's "AI MOC" covers LLM + general AI) |

Folder-to-frontmatter mapping:

| Folder | research.domain | MOC routed to |
|---|---|---|
| `20 Research/LLM/` | `LLM` | `AI MOC` |
| `20 Research/Agents/` | `Agent` | `Agent MOC` |
| `20 Research/MCP/` | `MCP` | `MCP MOC` |
| `20 Research/RAG/` | `RAG` | `RAG MOC` |
| `20 Research/Prompt Engineering/` | `Prompt` | `Prompt Engineering MOC` |
| `20 Research/Evaluation/` | `Eval` | `Evaluation MOC` |
| `20 Research/_cross-domain/` | (any, multi-tag) | (multi-MOC) |

Notes:
- Folder name is plural / verbose for legibility; frontmatter is singular / terse for Dataview queries.
- Concept-only domains (Architecture, Engineering) have no Research subfolder — research about them lives in `_cross-domain/` and gets tagged appropriately.

---

## 4. Frontmatter Schema

### Baseline (every note)

```yaml
---
date: YYYY-MM-DD           # created
updated: YYYY-MM-DD        # last edited
type: <note-type>
tags: [<type>, ...]
ai-first: true             # mandatory
---
```

### Note types and their specific fields

| Type | Folder | Type-specific fields |
|---|---|---|
| `research` | `20 Research/<domain>/` | `source` (paper\|repository\|blog\|youtube\|podcast\|docs\|tweet), `title`, `url`, `domain` (LLM\|Agent\|MCP\|RAG\|Prompt\|Eval), `read-status` (skimmed\|read\|deep), `confidence`, `related-concepts`, `moc`, `sources`. Source-conditional: `authors`, `venue`, `year`, `code`, `stars`, `language`, `key-files`, `last-checked`, `duration` |
| `concept` | `40 Knowledge/Concepts/` | `name`, `domain` (LLM\|Agent\|MCP\|RAG\|Architecture\|Engineering\|Prompt\|Eval), `maturity` (nascent\|maturing\|established), `first-seen`, `related-concepts`, `moc`, `confidence` |
| `project` | `10 Projects/<name>/` | `status` (active\|paused\|archived), `start-date`, `archetype`, `repo`, `local-path`, `related-concepts`, `moc` |
| `decision` | `10 Projects/<name>/` | `decision-status` (proposed\|accepted\|superseded\|rejected), `project` (wikilink), `options`, `chosen`, `supersedes`, `superseded-by` |
| `task` | `10 Projects/<name>/` | `task-status` (backlog\|in-progress\|done\|cancelled), `project`, `priority`, `due`, `spec-path` |
| `journal` | `50 Journal/` | (baseline only) |
| `moc` | `90 MOCs/` | `domain`, `maintained-via` (hand\|dataview\|both) |
| `prompt` | `40 Knowledge/Prompt Library/` | `models-tested`, `use-case`, `prompt-type` |
| `mcp` | `40 Knowledge/MCP Catalog/` | `name`, `url`, `transport` (stdio\|sse\|http), `maturity`, `last-checked` |
| `synthesis` | `40 Knowledge/Synthesis/` | `synthesizes` (list of wikilinks), `timeframe` |
| `engineering` | `30 Engineering/` | `technology`, `category` (pattern\|debug\|learning\|comparison), `confidence` |
| `note` | any | `project` (if project-bound) |
| `index` | vault root | (baseline only) |

### AI-First rules (extending baseline)

| Rule | Detail |
|---|---|
| `confidence` markers | Any external factual claim labeled: `stated` (from source) / `high` / `medium` / `speculation` |
| Recency markers | External facts include date: `Mem0 raised $24M (as of 2026-04)` |
| Sources verbatim | Every external claim has its source URL inline |
| Wikilink mandatory | Mentioned concepts/papers/projects/repos → `[[wikilink]]`; create stub if missing |

---

## 5. Templates

Located in `_templates/`. 11 total.

### Main Templates (PRD §5, with AI-First additions)

#### `research-template.md` (replaces PRD's paper + repository templates)

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

#### `concept-template.md` (PRD §5)

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

#### `project-template.md` (PRD §5)

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

### Secondary Templates (8)

| Template | Purpose | Main sections |
|---|---|---|
| `decision-template.md` | ADR inside projects | For future Claude / Context / Options / Decision / Reasoning / Consequences / What would change my mind |
| `task-template.md` | Task notes inside projects | For future Claude / Goal / Acceptance / Subtasks / Notes |
| `journal-template.md` | `50 Journal/` daily / weekly | For future Claude / Done today / Learned / Decisions / Tomorrow |
| `moc-template.md` | `90 MOCs/` | For future Claude / Core Concepts (hand) / Key Research (hand) / All Research (dv) / Concepts (dv) / Projects (dv) |
| `synthesis-template.md` | `40 Knowledge/Synthesis/` | For future Claude / Synthesizes / Convergent / Divergent / Current Take |
| `prompt-template.md` | Prompt Library | For future Claude / Use case / Models tested / Prompt body / Variations / Failure modes |
| `mcp-template.md` | MCP Catalog | For future Claude / Purpose / Transport / Setup / Tools provided / Evaluation |
| `engineering-template.md` | `30 Engineering/` | For future Claude / Context / Pattern or Solution / Trade-offs / References |

### Universal template requirements

Every template enforces:

1. ✅ `ai-first: true` frontmatter
2. ✅ `## For future Claude` preamble (2-3 sentences)
3. ✅ Related Concepts section at end (wikilinks; stubs OK)
4. ✅ External claims include `confidence` + inline source URL

---

## 6. MOC System

### Maintenance model: Hybrid (hand-curated + Dataview)

Each MOC = **hand-curated section** + **Dataview auto-listing**. The hand
section forces cognitive work (curation, ordering, priority); the Dataview
section guarantees freshness.

### 7 MOCs

| MOC | Domain coverage |
|---|---|
| `AI MOC.md` | Broad AI/ML/DL fundamentals |
| `Agent MOC.md` | AI agents, multi-agent systems, agent architectures |
| `MCP MOC.md` | Model Context Protocol ecosystem |
| `RAG MOC.md` | Retrieval-augmented generation |
| `Architecture MOC.md` | System design patterns |
| `Prompt Engineering MOC.md` | Prompt design, chain-of-thought, etc. |
| `Evaluation MOC.md` | LLM/agent evaluation methodology |

### MOC structure (each MOC)

```markdown
---
date: 2026-06-14
updated: 2026-06-14
type: moc
tags: [moc, <domain-tag>]
ai-first: true
domain: <Domain>
maintained-via: both
---

## For future Claude
> <Domain> 領域的入口。
> 我目前對 <domain> 的判斷：<一句話 stance>

## 🧠 核心概念（hand-curated）
- [[Concept A]] — one-line description
- [[Concept B]] — one-line description

## 📚 必讀研究（hand-curated, in reading order）
1. [[Research X]] — why first
2. [[Research Y]] — why next

## 🔬 全部相關研究（Dataview auto）
\`\`\`dataview
TABLE source, read-status, confidence, file.mtime as "Updated"
FROM "20 Research"
WHERE contains(tags, "<domain-tag>") OR domain = "<Domain>"
SORT file.mtime DESC
\`\`\`

## 💡 全部相關 Concept（Dataview auto）
\`\`\`dataview
TABLE maturity, first-seen
FROM "40 Knowledge/Concepts"
WHERE domain = "<Domain>"
SORT maturity DESC, first-seen DESC
\`\`\`

## 🛠 使用此 MOC 的專案（Dataview auto）
\`\`\`dataview
LIST status
FROM "10 Projects"
WHERE type = "project" AND contains(moc, [[<Domain> MOC]])
\`\`\`
```

### Curation discipline

- **Don't auto-promote everything** — only hand-add a concept if it's central.
- **Reading order matters** — "必讀研究" is ordered, not alphabetical.
- **Domain tag must match** — domain attribute in note frontmatter must
  match MOC domain exactly, otherwise Dataview misses it.

---

## 7. Dashboard (`index.md`)

`index.md` is both vault catalog and dashboard.

### 6 Dashboard sections

#### 1. Active Projects

```dataview
TABLE status, archetype, file.mtime as "Updated", related-concepts
FROM "10 Projects"
WHERE type = "project" AND status = "active"
SORT file.mtime DESC
```

#### 2. Recent Research (last 14 days)

```dataview
TABLE source, domain, read-status, confidence
FROM "20 Research"
WHERE type = "research" AND date >= date(today) - dur(14 days)
SORT date DESC
```

#### 3. Concept Bank (grouped by domain)

```dataview
TABLE maturity, first-seen, length(related-concepts) as "Links"
FROM "40 Knowledge/Concepts"
WHERE type = "concept"
GROUP BY domain
SORT domain ASC, maturity DESC
```

#### 4. Recently Studied Repositories (last 30 days)

```dataview
TABLE language, stars, last-checked, read-status
FROM "20 Research"
WHERE type = "research" AND source = "repository" AND last-checked >= date(today) - dur(30 days)
SORT last-checked DESC
```

#### 5. Inbox Aging (≥ 3 days)

```dataview
LIST "📥 " + file.name + " (" + (date(today) - file.ctime).days + " days)"
FROM "00 Inbox"
WHERE (date(today) - file.ctime).days >= 3
SORT file.ctime ASC
```

#### 6. Recent ADRs (last 30 days)

```dataview
TABLE decision-status, project, chosen
FROM "10 Projects"
WHERE type = "decision" AND date >= date(today) - dur(30 days)
SORT date DESC
```

### `index.md` structure

```markdown
---
date: 2026-06-14
updated: 2026-06-14
type: index
tags: [meta, index, dashboard]
ai-first: true
---

## For future Claude
> AIR-OS vault entry point. Read this first to know current state.

## 🧭 Navigation
- [[_CLAUDE]] — Operating manual
- 90 MOCs: [[AI MOC]] · [[Agent MOC]] · [[MCP MOC]] · [[RAG MOC]] · [[Architecture MOC]] · [[Prompt Engineering MOC]] · [[Evaluation MOC]]

---

## 1️⃣ Active Projects
<Dataview>

## 2️⃣ Recent Research
<Dataview>

## 3️⃣ Concept Bank
<Dataview>

## 4️⃣ Recently Studied Repositories
<Dataview>

## 5️⃣ Inbox Aging
<Dataview>

## 6️⃣ Recent ADRs
<Dataview>
```

---

## 8. Concept Note Workflow

PRD §10 high-level flow:

```
Paper / Blog / YouTube / GitHub Repo → Research Note → Concept Note → MOC → Project → Output
```

### 5 operational rules

#### Rule 1: Research Note is interpretation, not transcription

Don't copy the source. Capture **your understanding + extracted insights**.

✅ "mem0 uses 3-layer architecture: LLM extraction → vector store → graph
relationships. The graph layer is novel — solves temporal ordering."
❌ "mem0 is a memory layer for LLM agents, developed by Mem0.ai, released..."

#### Rule 2: Concept extraction triggers

Create or update a Concept Note when:

| Trigger | Action |
|---|---|
| Same concept appears in ≥ 2 research notes | Create Concept Note linking back to both |
| You've used the concept to explain ≥ 2 other things | Promote to formal Concept Note |
| Research surfaces a core term you don't fully understand | Create as `nascent` stub |

**Don't extract** when concept is unique to one paper or too foundational
(e.g., "neural network" textbook definition).

#### Rule 3: Maturity evolution

| Maturity | Conditions | Expected content |
|---|---|---|
| `nascent` | First creation | Definition + source wikilink only |
| `maturing` | Appears in ≥ 3 research | + How It Works + Examples + Related Concepts |
| `established` | You can teach it in 5 minutes | All 7 sections + your judgment (Why Important / Limitations) |

#### Rule 4: MOC update timing

Don't touch MOCs every time you write a research note. Update when:

- New Concept Note created → add to MOC's "核心概念" hand section
- Concept upgraded to `established` → reorder in MOC
- Research becomes "would recommend to others" → add to MOC's "必讀研究"
- Weekly review → MOC health check

#### Rule 5: Concept ↔ Project bidirectional linking

When a concept is used in a project:

1. Project note's `related-concepts:` adds `[[Concept Name]]`
2. Concept Note's Examples section adds "→ used in [[Project Name]]"
3. If it's a key decision, write an ADR (`type: decision`) referencing the concept

This turns the vault from "research log" into "research ↔ practice bidirectional graph".

### Worked example: mem0 flow

```
Step 1: Read mem0 GitHub repo
Step 2: Create 20 Research/Agents/mem0-repo.md (type:research, source:repository)
        → For future Claude: 3-layer memory architecture
        → Related Concepts: [[Long-Term Memory Store]] (stub link)
Step 3: Extract concept (because Letta also has this concept)
        → 40 Knowledge/Concepts/Long-Term Memory Store.md (maturity: nascent)
        → Examples: [[mem0-repo]], [[letta-paper]]
Step 4: Update Agent MOC's 核心概念 hand section
        → - [[Long-Term Memory Store]] — agent cross-session memory
Step 5: Apply to project
        → 10 Projects/ai-eden-service/<name>.md adds [[Long-Term Memory Store]] to related-concepts
        → 10 Projects/ai-eden-service/adr-008-memory-architecture.md (if decision)
Step 6: Backflow to Concept Note
        → Examples adds: "→ used in [[ai-eden-service]] (mem0-style, PostgreSQL Recursive CTE for graph)"
```

### Weekly Review (PRD §11)

Every Sunday evening, create `50 Journal/YYYY-WXX.md`:

```markdown
## For future Claude
> Week XX research / learning / decision recap.

## What I Learned
(3-5 key insights from this week's research)

## New Concepts (promoted / created)
- [[Concept A]] — nascent → maturing (3rd source this week)
- [[Concept B]] — newly created

## Research This Week
(Dataview auto)

## Repositories Studied
(Dataview auto)

## Projects Progress
(hand: 3-5 sentences)

## Decisions Made
(Dataview auto ADRs)

## MOC Health Check
- [ ] AI MOC: [[Concept X]] now established — reorder
- [ ] RAG MOC: added [[Y]] to hand section

## Next Week Focus
(hand: 3 items)
```

### Inbox Hygiene

`00 Inbox/` notes must clear by weekly review:

| Content type | Disposition |
|---|---|
| Unread source (URL) | Promote to Research Note in `20 Research/<domain>/` |
| Idea | Concept stub in `40 Knowledge/Concepts/` or task in project |
| Uncertain but valuable | Stay in Inbox + revisit next week |
| No value | Delete |

Dashboard §5 Inbox Aging surfaces overdue notes automatically.

---

## 9. Migration Plan

### Phase 0: Backup + Confirm

```bash
ls -la /Users/leric/Documents/SecondBrain.bak-2026-05-25
ls -la /Users/leric/Documents/SecondBrain

# Extra cold storage backup before destructive moves
cp -R /Users/leric/Documents/SecondBrain \
      ~/Dropbox/_archive/SecondBrain-pre-AIR-2026-06-14
```

### Phase 1: Archive old vault

```bash
mv /Users/leric/Documents/SecondBrain \
   /Users/leric/Documents/SecondBrain.archive-2026-06-14
```

Old vault disappears from Obsidian but remains on disk. Rollback possible
until Phase 7 starts producing new content.

### Phase 2: Build AIR-OS scaffold

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
mkdir -p "_templates" "_assets"

git init
cat > .gitignore <<EOF
.obsidian/workspace*
.obsidian/cache
.trash/
_assets/
.DS_Store
EOF
```

### Phase 3: Create 11 Templates

In `_templates/`: `research-template.md`, `concept-template.md`,
`project-template.md`, `decision-template.md`, `task-template.md`,
`journal-template.md`, `moc-template.md`, `synthesis-template.md`,
`prompt-template.md`, `mcp-template.md`, `engineering-template.md`.

Each template per Section 5 content.

### Phase 4: Create 7 MOC stubs + `index.md` + `_CLAUDE.md`

Each MOC starts with: frontmatter + For future Claude + empty hand sections
+ working Dataview queries.

`index.md` per Section 7.
`_CLAUDE.md` per Section 10.

### Phase 5: Migrate 15 deep research notes

| Old path | New path | source | domain |
|---|---|---|---|
| `Research/Web/2026-05-25-agent-memory-short-long-term-design.md` | `20 Research/Agents/agent-memory-short-long-term-design.md` | docs | Agent |
| `Research/Web/2026-05-29-lunatalk-story-ai-rpg-core-tech.md` | `20 Research/Agents/lunatalk-story-ai-rpg-core-tech.md` | docs | Agent |
| `Research/Web/2026-05-29-companion-chat-vs-story-rpg-retention.md` | `20 Research/Agents/companion-chat-vs-story-rpg-retention.md` | docs | Agent |
| `Projects/ai-eden-service/Research/replika-deep-tech-and-companion-architecture-deep.md` | `20 Research/Agents/replika-deep-tech.md` | docs | Agent |
| `Projects/ai-eden-service/Research/miramind-replika-framework-and-langgraph-fit-deep.md` | `20 Research/Agents/miramind-replika-langgraph.md` | docs | Agent |
| `Projects/ai-eden-service/Research/lukalabs-replika-research-deep.md` | `20 Research/Agents/lukalabs-replika.md` | docs | Agent |
| `Projects/ai-eden-service/Research/memory-storyline-interaction-deep.md` | `20 Research/Agents/memory-storyline-interaction.md` | docs | Agent |
| `Projects/ai-eden-service/Research/character-storyline-mismatch-deep.md` | `20 Research/Agents/character-storyline-mismatch.md` | docs | Agent |
| `Projects/ai-eden-service/Research/world-storyline-desync-deep.md` | `20 Research/Agents/world-storyline-desync.md` | docs | Agent |
| `Projects/ai-eden-service/Research/memory-character-lore-conflict-deep.md` | `20 Research/Agents/memory-character-lore-conflict.md` | docs | Agent |
| `Projects/ai-eden-service/Research/memory-storyline-temporal-violation-deep.md` | `20 Research/Agents/memory-storyline-temporal-violation.md` | docs | Agent |
| `Projects/ai-eden-service/Research/memory-for-storyline-progression-deep.md` | `20 Research/Agents/memory-for-storyline-progression.md` | docs | Agent |
| `Projects/ai-eden-service/Research/procedural-story-generation-pipeline-deep.md` | `20 Research/Agents/procedural-story-generation-pipeline.md` | docs | Agent |
| `Projects/ai-eden-service/Research/hybrid-authoring-uiux-deep.md` | `20 Research/Agents/hybrid-authoring-uiux.md` | docs | Agent |
| `Projects/ai-eden-service/Research/intimacy-storyline-product-philosophy-deep.md` | `20 Research/Agents/intimacy-storyline-product-philosophy.md` | docs | Agent |

**Frontmatter rewrite for each migrated note**:

```yaml
---
date: <original date, preserved>
updated: 2026-06-14
type: research
source: docs
tags: [research, agent, ai-companion]
ai-first: true
title: <original title>
url: ""
domain: Agent
read-status: deep
related-concepts: []
moc: ["[[Agent MOC]]"]
confidence: high
sources: [<original source URLs from the dossier>]
---
```

**Notes**:

- Strip `-deep` suffix (type already encodes depth)
- Strip date prefix from filename (date stays in frontmatter)
- Body content unchanged — these are time-snapshot dossiers; old wikilinks
  inside body may break (accepted; non-goal to repair them)
- Use **`cp`** from `/Users/leric/Documents/SecondBrain.archive-2026-06-14/...`
  to new vault path (NOT `mv` — preserve archive integrity for rollback)
- Frontmatter rewrite happens **after** copy: in-place edit on the new-vault
  copy only; archived copy stays untouched

### Phase 6: Seed Agent MOC's hand-curated section

```markdown
## 🧠 核心概念（stubs to fill later）
- [[Long-Term Memory Store]] — agent cross-session memory
- [[AI Companion Architecture]] — Replika-style 5-layer
- [[Procedural Story Generation]] — dynamic story generation
- [[Memory-Storyline Coordination]] — memory-driven storyline progression

## 📚 必讀研究（reading order）
1. [[agent-memory-short-long-term-design]] — memory landscape
2. [[lunatalk-story-ai-rpg-core-tech]] — 5-layer architecture
3. [[replika-deep-tech]] — companion benchmark
4. [[procedural-story-generation-pipeline]] — World → Arc → Storylet → Scene
```

Concept stub files are NOT created in Phase 6 — they get built organically
post-migration following Section 8 Rule 2 triggers. The wikilinks above
will appear as red/unresolved until then.

### Phase 7: Smoke test + first commit

1. Open new vault in Obsidian; verify folder tree.
2. Install Dataview plugin (copy from old `.obsidian/plugins/dataview/`,
   or reinstall from community plugins).
3. Verify `index.md` Dashboard's 6 sections render without errors.
4. Verify 7 MOCs' Dataview sections find their research.
5. Verify Templates plugin points to `_templates/`.
6. Git commit: `init: AIR-OS vault initialized from PRD v1.0`.
7. Optional: Push to GitHub private repo (`gh repo create air-os-vault --private`).

---

## 10. `_CLAUDE.md` Operating Manual

Lives at vault root. Read first in every Claude session.

### Verbatim content

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

### Removed from old `_CLAUDE.md`

- Kanban Convention (not used in AIR-OS)
- Propagation Rules (no skill automation)
- People to Know / Projects Currently Active (handled by Dashboard)
- Active main project default (no default project in AIR-OS)
- Project-scoped folder routing (was for 33 commands)
- Proactive prompts (was for skill triggers)
- Discord reply handling (no Discord integration)

---

## 11. Git Setup

```bash
cd /Users/leric/Documents/SecondBrain
git init
```

**`.gitignore`** (per Phase 2 above).

**`.obsidian/` versioning**: Plugin configs (`dataview/data.json`, hotkeys,
themes) ARE version-controlled — they're part of vault UX. Only `workspace*`
and `cache` are excluded.

**Remote** (recommended):

```bash
gh repo create air-os-vault --private --source=. --remote=origin --push
```

**Auto-backup**: Obsidian Git plugin (auto-commit + push every N minutes,
configurable). Alternatives: launchd cron job; or manual.

**Commit conventions**:

- `init: <description>` — Phase 0-7 migration commits
- `add: <research/concept/project/...> <name>`
- `update: <name> — <reason>`
- `archive: <name>`
- `auto: YYYY-MM-DD-HHMM` — Obsidian Git plugin auto commits

---

## 12. Acceptance Criteria

### Tier 1: Structural (migration complete)

| # | Condition | Verification |
|---|---|---|
| AC-001 | 8 top-level folders exist | `ls` shows 00 Inbox, 10 Projects, 20 Research, 30 Engineering, 40 Knowledge, 50 Journal, 90 MOCs, 99 Archive |
| AC-002 | `20 Research/` has 7 domain subfolders | LLM, Agents, MCP, RAG, Prompt Engineering, Evaluation, _cross-domain |
| AC-003 | `40 Knowledge/` has 4 subfolders | Concepts, Prompt Library, MCP Catalog, Synthesis |
| AC-004 | 11 templates exist in `_templates/` | `ls _templates/` shows 11 .md files |
| AC-005 | 7 MOCs exist | `ls 90\ MOCs/` shows 7 .md files |
| AC-006 | `index.md` and `_CLAUDE.md` exist in vault root | both files present |
| AC-007 | 15 deep research migrated | `ls 20\ Research/Agents/` has at least 15 files |

### Tier 2: Schema (AI-First)

| # | Condition | Verification |
|---|---|---|
| AC-008 | All migrated notes have `ai-first: true` | Dataview `LIST FROM "20 Research" WHERE !ai-first` returns empty |
| AC-009 | All research notes have `type:research` + `source` + `domain` | Dataview all fields populated |
| AC-010 | All research notes have `## For future Claude` section | grep `## For future Claude` matches all 15 |
| AC-011 | Templates contain `ai-first: true` + preamble + Related Concepts | grep verifies |

### Tier 3: Dashboard / Dataview

| # | Condition | Verification |
|---|---|---|
| AC-012 | Dataview plugin installed and enabled | Obsidian plugin list |
| AC-013 | `index.md` 6 Dashboard sections execute without error | open `index.md` |
| AC-014 | Active Projects section shows empty (no active project yet) | empty table |
| AC-015 | Recent Research section shows 15 entries | Dataview result has 15 rows |
| AC-016 | Agent MOC's Dataview section finds 15 research notes | open `Agent MOC.md` |

### Tier 4: Workflow (post-week-1 validation)

| # | Condition | Verification |
|---|---|---|
| AC-017 | Week 1 weekly review written | `50 Journal/YYYY-W24.md` exists |
| AC-018 | At least 1 Concept Note created in Week 1 | `40 Knowledge/Concepts/` has ≥ 1 file |
| AC-019 | Inbox cleared at end of Week 1 | `00 Inbox/` has no note older than 3 days |

---

## 13. Deferred (PRD §13 — Future AI Agent Integration)

NOT in scope for this spec. Recorded as future direction:

| Agent | Expected role | Implementation trigger |
|---|---|---|
| **Knowledge Agent** | Cross-vault retrieval + reasoning | When Concept Notes ≥ 50 and manual search is slow |
| **Research Agent** | Auto-runs web research, writes to `20 Research/` | When weekly research ≥ 5 sources and quality is stable |
| **MCP Agent** | Auto-updates MCP Catalog `maturity` / `last-checked` | When MCP ecosystem changes frequently |
| **Repo Agent** | Watches important repos and pings on updates | When tracking ≥ 10 important repos simultaneously |

These will be designed in PRD v2 / v3, each as an independent spec.

---

## 14. Rollback Plan

Any time before Phase 7 generates new content:

```bash
# Discard AIR-OS, restore old vault
rm -rf /Users/leric/Documents/SecondBrain
mv /Users/leric/Documents/SecondBrain.archive-2026-06-14 \
   /Users/leric/Documents/SecondBrain
```

After Phase 7 starts (new notes written, MOCs/Concepts created), rollback
cost rises (new content lives only in AIR-OS).

---

## 15. Open Questions / Risks

| Topic | Question | Mitigation |
|---|---|---|
| Concept curation drift | Will owner actually follow Section 8 Rule 2 triggers, or will Concepts accumulate as nascent stubs forever? | Dashboard could add "Stale nascent concepts" section in a future iteration |
| 15 research all in `Agents/` | Are all 15 dossiers really Agent-domain? Some (procedural-story, hybrid-authoring) might be `_cross-domain/`. | Owner confirmed during brainstorm: keep all in `Agents/` for simplicity |
| Wikilinks broken in dossier body | Old internal links (e.g., `[[Projects/ai-eden-service/...]]`) will be red in AIR-OS | Accepted as non-goal; dossiers are time snapshots |
| Auto-backup choice | Owner has not picked between Obsidian Git plugin / launchd / manual | Spec recommends Obsidian Git plugin; owner can switch later |
| Domain enum stability | PRD lists 7 domains; will new domains emerge (Storytelling, Game AI)? | Domains can be added later; just update `_CLAUDE.md` Frontmatter Requirements |

---

*End of spec.*
