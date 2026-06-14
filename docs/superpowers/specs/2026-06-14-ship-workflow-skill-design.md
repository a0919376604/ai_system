# Ship Workflow Skill — Design Spec

**Spec ID:** 2026-06-14-ship-workflow-skill-design
**PRD Source:** `Ship Workflow（Superpowers + Compound Engineering）` (uploaded 2026-06-14)
**Status:** Draft, pending user review
**Owner:** Leric
**Last updated:** 2026-06-14
**Depends on:** `2026-06-14-obsidian-air-os-vault-design.md` (AIR-OS vault structure)

---

## 1. Background

Owner has just built AIR-OS — an AI-First Obsidian vault at
`/Users/leric/Documents/SecondBrain` with strict 8-folder PRD structure,
mandatory frontmatter, and "For future Claude" preamble on every note.
Owner explicitly rejected the `obsidian-second-brain` 33-command skill
ecosystem and chose pure Obsidian + Templates + Dataview + manual workflow.

The newly uploaded PRD ("Ship Workflow") proposes a **per-repo product
development workflow** that integrates:

- **Superpowers**: brainstorming → writing-plans → execution
- **Compound Engineering**: roadmap → decision → learnings → knowledge

The PRD describes 7 `ship-*` slash commands and a dual-brain architecture
(Product Brain in Obsidian + Execution Brain in each repo).

### Why this is compatible with AIR-OS's "no skill commands" rule

The AIR-OS rule applies to **personal knowledge management** in Obsidian.
The Ship Workflow operates on a **different layer** — per-repo product
development. The two layers can coexist:

- **AIR-OS (Obsidian)**: pure manual + Templates + Dataview
- **Ship Workflow (repo `.claude/commands/`)**: slash commands triggered
  from within Claude Code while working in a specific repo

The Ship Workflow does write to Obsidian (`10 Projects/<name>/`), but
only the 4 strategy files (VISION/STRATEGY/ROADMAP/QUARTERLY_GOALS),
following AIR-OS frontmatter rules.

### Brainstorm decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Skill plugin, any repo can install | Reuse across 11 active repos |
| Plugin location | `ai_system/claude-skills/ship-workflow/` | Same pattern as existing skills, devsync-deployed |
| Product Brain location | AIR-OS `10 Projects/<repo-name>/` | Reuse AIR-OS structure, no new vault |
| ship-build relation to Superpowers | Wrapper, not reimplementation | Avoid duplicating brainstorming/writing-plans logic |
| Compound Engineering | Reuse `ce-*` plugin skills | Don't reinvent strategy/promote/compound |
| Sync mechanism | Auto-pull on ship-* invoke, Obsidian → repo | Obsidian is single source of truth |
| Roadmap rigidity | Soft + `--adhoc` flag | Don't block quick-fixes |
| Note convention | Fully follow AIR-OS rules | Vault consistency |
| Architecture | Hybrid config (auto-detect + optional override) | Zero-config for 90%, escape hatch for 10% |

---

## 2. Goals

### Primary

1. **Reusable across repos** — `ship-init` bootstraps any repo with the same workflow
2. **Compose, don't reinvent** — Wrap existing `superpowers:*` and `compound-engineering:*` skills
3. **AIR-OS-conformant** — All produced notes follow AIR-OS rules (ai-first, preamble, wikilinks, frontmatter)
4. **Dual-brain integration** — Obsidian holds strategy, repo holds execution; auto-sync on demand
5. **Low friction** — Zero-config in 90% of cases; soft Roadmap requirement with escape hatch

### Non-Goals

- ❌ Bidirectional sync (repo → Obsidian) — Obsidian is canonical
- ❌ Multi-vault support — single AIR-OS path
- ❌ Web UI / Dashboard
- ❌ Cross-repo R-XXX numbering coordination — each repo has its own namespace
- ❌ Separate ADHOC namespace — `--adhoc` allocates a real R-NNN immediately (Roadmap = source of truth, including emergency work)
- ❌ AIR-OS Dashboard MOC for Ship workflow — defer to v2
- ❌ Slack / Discord notifications
- ❌ Reimplementation of any logic that already lives in superpowers or ce-* plugins

---

## 3. Architecture

### Plugin Layout

```
ai_system/claude-skills/ship-workflow/
├── SKILL.md                          # skill metadata + entry point
├── README.md
├── commands/                         # ship-init copies these to repo .claude/commands/
│   ├── ship-init.md
│   ├── ship-idea.md
│   ├── ship-decision.md
│   ├── ship-roadmap.md
│   ├── ship-next.md
│   ├── ship-build.md
│   └── ship-compound.md
├── templates/
│   ├── obsidian/                     # AIR-OS Project Brain templates
│   │   ├── VISION.md
│   │   ├── STRATEGY.md
│   │   ├── ROADMAP.md
│   │   └── QUARTERLY_GOALS.md
│   └── repo/                         # Per-roadmap-item note templates
│       ├── IDEA.md
│       ├── DECISION.md
│       ├── BRAINSTORM.md
│       ├── SPEC.md                   # alias to superpowers spec format
│       ├── PLAN.md                   # alias to superpowers plan format
│       └── LEARNING.md
├── lib/
│   ├── sync.sh                       # Obsidian → repo sync
│   ├── id-gen.sh                     # next IDEA-NNN / D-NNN / R-NNN
│   ├── airos-binding.sh              # resolve AIR-OS project folder
│   └── roadmap-insert.sh             # insert new R-NNN into ROADMAP "Now"
└── references/
    ├── flow-diagrams.md
    ├── escape-hatches.md
    └── ce-skill-mapping.md           # which ce-* skill each ship-* delegates to
```

### Dual-Brain Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│ Obsidian: AIR-OS (/Users/leric/Documents/SecondBrain)                │
│                                                                       │
│ 10 Projects/<repo-name>/                                              │
│   ├── <repo-name>.md         (type: project, existing AIR-OS file)    │
│   ├── VISION.md              (type: vision, NEW — ship-init creates)  │
│   ├── STRATEGY.md            (type: strategy, NEW)                    │
│   ├── ROADMAP.md             (type: roadmap, NEW)                     │
│   ├── QUARTERLY_GOALS.md     (type: quarterly-goal, NEW)              │
│   ├── adr-NNN-*.md           (type: decision, AIR-OS legacy ADRs)     │
│   └── task-*.md              (type: task, AIR-OS legacy tasks)        │
│                                                                       │
│ ↓ ship-* command auto-pull (Obsidian = source of truth)               │
└─────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────┐
│ Repo: /Users/leric/Desktop/code/<repo>/                               │
│                                                                       │
│ .claude/                                                              │
│   ├── commands/ship-*.md             (7 slash commands; in git)       │
│   ├── ship-config.yml                (optional per-repo override)     │
│   └── .ship-last-pull                (gitignored; freshness cache)    │
│                                                                       │
│ docs/                                                                 │
│   ├── product/                       (mirror of Obsidian, in git)     │
│   │   ├── VISION.md                                                   │
│   │   ├── STRATEGY.md                                                 │
│   │   ├── ROADMAP.md                                                  │
│   │   └── QUARTERLY_GOALS.md                                          │
│   ├── ideas/IDEA-NNN-<slug>.md       (type: idea)                     │
│   ├── decisions/D-NNN-<slug>.md      (type: decision; ship-context)   │
│   ├── brainstorms/R-NNN-<slug>.md    (type: brainstorm)               │
│   ├── specs/R-NNN-<slug>.md          (superpowers spec format)        │
│   ├── plans/R-NNN-<slug>.md          (superpowers plan format)        │
│   ├── learnings/R-NNN-<slug>.md      (type: learning)                 │
│   └── learnings/_log.md              (meta log: every ship-* call)    │
└─────────────────────────────────────────────────────────────────────┘
```

### Config Model

**Global** (`~/.claude/ship-workflow.yml`):
```yaml
airos_vault: /Users/leric/Documents/SecondBrain
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft           # soft | strict
default_id_pad: 3                    # IDEA-001 vs IDEA-1
auto_pull_freshness_window: 60       # seconds
```

**Per-repo** (`.claude/ship-config.yml`, optional, only on `--custom` init):
```yaml
airos_project: langlive-line-oa      # override basename(pwd)
roadmap_mode: strict                  # override default
```

### Resolution Order

```
1. Read ~/.claude/ship-workflow.yml
2. Read $(pwd)/.claude/ship-config.yml (may not exist)
3. project_name = config.airos_project OR basename(pwd)
4. airos_path = <airos_vault>/<airos_projects_dir>/<project_name>/
```

### Distribution / Update Mechanism

- Source: `ai_system/claude-skills/ship-workflow/`
- Deploy: existing `devsync` mechanism syncs to `~/.claude/skills/ship-workflow/`
- Per-repo install: `/ship-init` copies `commands/*.md` to `.claude/commands/`
- Update repo commands after skill change: `/ship-init --upgrade`
- Why copy not symlink: repo commits go to git → other contributors / CI need files present without local skill install

---

## 4. The 7 Ship Commands

### Common Skeleton

Every `ship-*` command follows:

```
1. Resolve config (global + per-repo)
2. Sync 4 strategy files from Obsidian → repo/docs/product/ (skip if fresh)
3. Run command-specific logic (often delegating to ce-* or superpowers:*)
4. Write outputs with AIR-OS frontmatter (ai-first: true, preamble, wikilinks)
5. Append a line to docs/learnings/_log.md
```

### `/ship-init [--custom] [--upgrade]`

**Purpose:** Bootstrap Ship workflow in current repo. **Idempotent.**

**Reads:**
- `$(pwd)` → infer project_name via basename
- `~/.claude/ship-workflow.yml`
- `--custom` flag → prompt for overrides, write `.claude/ship-config.yml`
- `--upgrade` flag → re-copy `commands/*.md` only (preserve user-edited config)

**Writes (repo side):**
- `.claude/commands/ship-*.md` (7 slash commands)
- `docs/{ideas,decisions,brainstorms,specs,plans,learnings,product}/` (7 folders)
- `docs/product/.gitignore` (empty — strategy mirrors DO commit)
- `.claude/.gitignore` (adds `.ship-last-pull`)
- `docs/learnings/_log.md` (header line only)

**Writes (AIR-OS side):**
- Create `10 Projects/<project_name>/` if missing
- Copy `templates/obsidian/{VISION,STRATEGY,ROADMAP,QUARTERLY_GOALS}.md` only if absent
- Never overwrite existing files

**Interaction:**
- Prompt user for VISION one-liner + first R-001 Roadmap Item description
- Each prompt is skippable (defaults to empty placeholder)

**Output git commit (in repo):** `chore: initialize ship-workflow (7 commands + 7 folders)`

### `/ship-idea <description>`

**Purpose:** Capture a new idea.

**Reads:**
- `docs/ideas/IDEA-*.md` → compute next ID via id-gen.sh
- `docs/product/STRATEGY.md` (post-sync) → check alignment

**Writes:** `docs/ideas/IDEA-NNN-<slug>.md` (see Section 5 for schema)

**Optional delegation:** `compound-engineering:ce-ideate` for depth

**Output git commit:** `idea: IDEA-NNN <description>`

### `/ship-decision <topic>`

**Purpose:** Record a major requirement change or architectural decision.

**Reads:**
- `docs/decisions/D-*.md` → next ID
- `docs/product/ROADMAP.md` → determine which R-XXX this affects
- Last N conversation messages → infer Context / Options / Chosen

**Writes:** `docs/decisions/D-NNN-<slug>.md` with `ship-context: true` and `affected-roadmap-items: [R-NNN, R-MMM]`

**Optional delegation:** `compound-engineering:ce-doc-review`

**Output git commit:** `decision: D-NNN <topic>`

### `/ship-roadmap`

**Purpose:** Refresh ROADMAP.md based on current ideas, decisions, learnings, and strategy.

**Reads (from AIR-OS Project folder):**
- `STRATEGY.md`
- `ROADMAP.md` (current)
- All `docs/ideas/IDEA-*.md` where `status != shelved`
- All `docs/decisions/D-*.md` where `decision-status = accepted`
- Recent `docs/learnings/R-*.md` (last 30 days)

**Execution:**
1. Delegate to `compound-engineering:ce-strategy` (or `ce-plan`) for strategic review
2. Apply PRD rules:
   - "Now" section holds 3-5 items
   - Completed items preserved with ✅ + completed-date
   - Sort by Impact × Dependency
3. Output diff for user confirmation
4. Write back to AIR-OS `10 Projects/<name>/ROADMAP.md`
5. Auto-sync mirror to repo

**Output:** Updated AIR-OS `ROADMAP.md` + repo `docs/product/ROADMAP.md`

### `/ship-next [--adhoc <description>]`

**Purpose:** Pick the next item, run brainstorm → produce spec. Two flows differ only at the "where does the R-NNN come from" step.

**Default (pick from Roadmap):**
1. Read `docs/product/ROADMAP.md` "Now" section
2. Rank items by priority × dependency satisfaction
3. Present top 1-2 to user, get confirmation → pick R-NNN
4. Invoke `superpowers:brainstorming` (which cascades to `writing-plans`)
5. Brainstorm output → `docs/brainstorms/R-NNN-<slug>.md`
6. Spec output → `docs/specs/R-NNN-<slug>.md`

**Adhoc mode (`--adhoc <description>`):**
1. Allocate next R-NNN via id-gen.sh (same namespace as planned items — no separate ADHOC namespace)
2. Insert a new line into AIR-OS `ROADMAP.md` "🔥 Now" section:
   ```
   - [ ] **R-NNN** <description> · adhoc-inserted=true · status=in-progress
   ```
3. Sync ROADMAP back to repo `docs/product/`
4. Continue exactly like default flow from step 4 onward (brainstorm + spec)

**Why no separate ADHOC namespace:** Roadmap is the canonical record of work
that gets done, including emergency firefighting. Splitting "planned" vs
"adhoc" into different ID spaces creates reconciliation debt later. Better
to inject the item into the Roadmap at the moment of decision and treat
the rest of the lifecycle uniformly.

**Output git commit:** `brainstorm: R-NNN <slug>` and `spec: R-NNN <slug>`

### `/ship-build [--from-spec <path>]`

**Purpose:** Execute spec → plan → build → test.

**Reads:** `docs/specs/R-NNN-*.md` (latest or `--from-spec`-flagged)

**Execution (wraps Superpowers):**
1. Invoke `superpowers:writing-plans` → produces `docs/plans/<ID>-<slug>.md`
2. Interactive choice: `subagent-driven` (default) / `inline-executing-plans` / `codex run-plan`
3. Invoke the chosen sub-skill
4. Monitor execution + collect commit log

**Mid-build escape hatches:**
- User runs `/ship-idea --during-build "X"` → IDEA captured + linked back to current R-NNN
- User runs `/ship-decision --during-build "Y"` → D-NNN captured + linked back to current R-NNN

**Output:**
- `docs/plans/<ID>-<slug>.md`
- Repo code commits (from sub-skill)
- Optional ADR `D-NNN` and/or IDEA `IDEA-NNN` if mid-build escape hatches fire

### `/ship-compound`

**Purpose:** Wrap up — write learnings + update Roadmap.

**Reads:**
- Most recent `docs/plans/<ID>-*.md`
- Decisions and ideas captured during the build (filter by `created-during: <ID>` or git log timespan)
- `git log` from plan start to HEAD

**Execution:**
1. Delegate to `compound-engineering:ce-compound` to generate learning content (per PRD §"Compound" section structure):
   - What Shipped
   - What Changed From Plan
   - Bugs
   - Reusable Patterns
   - Technical Debt
   - Future Follow-ups
2. Write `docs/learnings/<ID>-<slug>.md` with AIR-OS frontmatter
3. Delegate to `compound-engineering:ce-promote` for patterns worth promoting:
   - Programming patterns → AIR-OS `30 Engineering/`
   - Concept abstractions → AIR-OS `40 Knowledge/Concepts/`
   - User confirms each promotion (no silent writes to AIR-OS knowledge layer)
4. Auto-invoke `/ship-roadmap`:
   - Move completed R-NNN from "Now" to ✅ Done section
   - Strip `adhoc-inserted=true` marker (item has shipped — no longer relevant)
   - Resort remaining items

**Output:**
- `docs/learnings/R-NNN-<slug>.md`
- Updated `ROADMAP.md` (in AIR-OS + repo mirror)
- 0+ new `40 Knowledge/Concepts/` and/or `30 Engineering/` files

### Command-to-Delegation Mapping (`references/ce-skill-mapping.md`)

| Ship command | Delegates to | Why |
|---|---|---|
| `ship-init` | (none) | Pure scaffolding |
| `ship-idea` | optional: `ce-ideate` | Optional depth |
| `ship-decision` | optional: `ce-doc-review` | Optional review pass |
| `ship-roadmap` | `ce-strategy` or `ce-plan` | Strategic re-prioritization |
| `ship-next` | `superpowers:brainstorming` | Cascades to writing-plans |
| `ship-build` | `superpowers:writing-plans` + user-chosen executor | Don't reinvent |
| `ship-compound` | `ce-compound` + `ce-promote` | Existing knowledge-promote logic |

---

## 5. Frontmatter Schema

### 7 New Note Types

Add to AIR-OS `_CLAUDE.md` Frontmatter Requirements (13 → 20 types):

| Type | Folder | Purpose |
|---|---|---|
| `idea` | repo `docs/ideas/` | Captured ideas |
| `brainstorm` | repo `docs/brainstorms/` | Brainstorm-phase notes |
| `learning` | repo `docs/learnings/` | Post-build retrospective |
| `vision` | AIR-OS `10 Projects/<name>/VISION.md` | Long-term vision |
| `strategy` | AIR-OS `10 Projects/<name>/STRATEGY.md` | Strategic direction |
| `roadmap` | AIR-OS `10 Projects/<name>/ROADMAP.md` | Roadmap |
| `quarterly-goal` | AIR-OS `10 Projects/<name>/QUARTERLY_GOALS.md` | Quarterly goals |

`decision` is reused (existing AIR-OS ADR type) with new fields. `spec` and `plan` reuse the superpowers format and do not introduce new types.

### Schema Details

#### `IDEA-NNN-<slug>.md`

```yaml
---
date: YYYY-MM-DD
updated: YYYY-MM-DD
type: idea
id: IDEA-NNN
tags: [idea, <project-tag>]
ai-first: true
project: "[[<project-name>]]"
status: captured              # captured | exploring | graduated | shelved
impact: medium                # low | medium | high
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: null    # filled when promoted to R-NNN
---

## For future Claude
> One-line summary of the idea and its strategic angle.

## Summary
## Problem
## Target User
## Evidence
## Impact
## Confidence
## Dependencies
## Risks
## Possible Roadmap Item
```

#### `D-NNN-<slug>.md`

```yaml
---
date: YYYY-MM-DD
updated: YYYY-MM-DD
type: decision
id: D-NNN
tags: [decision, adr, <project-tag>]
ai-first: true
project: "[[<project-name>]]"
decision-status: proposed     # proposed | accepted | superseded | rejected
options: []
chosen: ""
supersedes: null
superseded-by: null
affected-roadmap-items: []
ship-context: true            # distinguishes from legacy adr-NNN files
confidence: high
---

## For future Claude
> Decision summary + why + what would change my mind.

## Context
## Options Considered
## Decision
## Reasoning
## Consequences
## Affected Roadmap Items
## What would change my mind
```

#### `R-NNN-<slug>.md` (brainstorm and learning)

```yaml
---
date: YYYY-MM-DD
updated: YYYY-MM-DD
type: brainstorm              # or learning
id: R-NNN
tags: [<type>, <project-tag>]
ai-first: true
project: "[[<project-name>]]"
roadmap-item: R-NNN
spec-path: docs/specs/R-NNN-<slug>.md
plan-path: docs/plans/R-NNN-<slug>.md
shipped: false                # learning only
shipped-date: null
---

## For future Claude
> What this R-NNN item is about (brainstorm) OR what was shipped (learning).
```

For `learning` notes, sections follow PRD § Compound:

```markdown
## What Shipped
## What Changed From Plan
## Bugs
## Reusable Patterns
## Technical Debt
## Future Follow-ups
```

#### Strategy Files (`VISION.md` / `STRATEGY.md` / `ROADMAP.md` / `QUARTERLY_GOALS.md`)

```yaml
---
date: YYYY-MM-DD
updated: YYYY-MM-DD
type: vision | strategy | roadmap | quarterly-goal
tags: [<type>, <project-tag>]
ai-first: true
project: "[[<project-name>]]"
maintained-via: hand           # ROADMAP: both (hand + ship-roadmap auto-sort)
---

## For future Claude
> One-line statement of what this file tracks.
```

### ROADMAP.md Body Structure

```markdown
## 🔥 Now (3-5 items)
- [ ] **R-012** LINE rich menu redesign · impact=high · est=1w
- [ ] **R-014** Webhook retry rework · impact=high · est=3d
- [x] ~~**R-011** Blacklist admin tool~~ ✅ 2026-06-13

## 🔜 Next
- **R-017** Concurrent operation conflict handling · impact=high · dep: R-014

## 🕐 Later
- **R-020** Image upload optimization

## ✅ Done (累積)
- **R-001** Project init · ✅ 2026-05-15
```

### Filename Conventions

| Type | Pattern | Example |
|---|---|---|
| Idea | `IDEA-NNN-<kebab-slug>.md` | `IDEA-007-multimodal-feedback-loop.md` |
| Decision | `D-NNN-<kebab-slug>.md` | `D-004-switch-celery-to-arq.md` |
| Brainstorm | `R-NNN-<kebab-slug>.md` | `R-012-line-rich-menu-redesign.md` |
| Spec | `R-NNN-<same-slug>.md` | (same filename as brainstorm) |
| Plan | `R-NNN-<same-slug>.md` | (same) |
| Learning | `R-NNN-<same-slug>.md` | (same) |
| Strategy | Fixed name | `VISION.md`, `STRATEGY.md`, etc. |

ID padding default 3 (IDEA-001) — configurable via global config.

---

## 6. Sync Mechanism

### Rules

- **Direction:** one-way (Obsidian → repo). Obsidian is canonical.
- **Trigger:** every `ship-*` command at step 2; skip if `.claude/.ship-last-pull` is fresher than `freshness_window` (default 60s).
- **Files:** exactly 4 (VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS).
- **Failure fallback:** if Obsidian source file absent, warn but don't abort (lets `/ship-init` bootstrap).

### `lib/sync.sh`

```bash
sync_product_brain() {
  local airos_path="$1"
  local repo_path="$2"
  local freshness_sec="${3:-60}"

  local last_pull="$repo_path/.claude/.ship-last-pull"
  if [ -f "$last_pull" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$last_pull") ))
    [ "$age" -lt "$freshness_sec" ] && return 0
  fi

  mkdir -p "$repo_path/docs/product"
  for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
    if [ -f "$airos_path/$f" ]; then
      cp "$airos_path/$f" "$repo_path/docs/product/$f"
    else
      echo "WARN: $airos_path/$f not found — skipping" >&2
    fi
  done
  date +%s > "$last_pull"
}
```

### Git Treatment

- `docs/product/*.md` **enters git** — repo collaborators see strategy snapshot
- `.claude/.ship-last-pull` is **gitignored** — local freshness cache
- **Stale snapshot warning:** if `docs/product/ROADMAP.md` is ≥ 7 days older than git remote `main`, `/ship-build` warns "Roadmap snapshot is stale, run /ship-roadmap to refresh"

---

## 7. Escape Hatches

### `--adhoc` Flow (uniform with planned work)

| Scenario | Default | `--adhoc <description>` |
|---|---|---|
| `/ship-next` | Pick R-NNN from "Now" | Allocate next R-NNN + insert into "Now" with `adhoc-inserted=true` marker, then continue normally |
| `/ship-build` | Reads `docs/specs/R-NNN-*.md` | Same — no separate flag needed |
| `/ship-compound` | Move R-NNN from "Now" → "Done" | Same — also strips `adhoc-inserted=true` marker |

**Design principle:** ADHOC is not a separate namespace; it's a flag on
how an R-NNN got created. The flag survives in the ROADMAP entry's
metadata so future-Claude can answer "which items were planned vs
firefighting" via Dataview.

### Meta Log

| File | Purpose |
|---|---|
| `docs/learnings/_log.md` | Single-line entry per ship-* command call: date · command · R-NNN · note · adhoc?(y/n) |

Cross-repo Dataview querying deferred to v2 (would need to mirror `_log.md` into AIR-OS).

---

## 8. Acceptance Criteria

### Tier 1: Skill Installation

| AC | Verification |
|---|---|
| AC-001 | `~/.claude/skills/ship-workflow/` exists after devsync |
| AC-002 | `SKILL.md` describes the skill's purpose and command list |
| AC-003 | `commands/` contains 7 files (ship-init/idea/decision/roadmap/next/build/compound) |
| AC-004 | `templates/obsidian/` contains 4 strategy templates |
| AC-005 | `templates/repo/` contains 6 templates (IDEA / DECISION / BRAINSTORM / SPEC / PLAN / LEARNING) |
| AC-006 | `lib/` contains sync.sh / id-gen.sh / airos-binding.sh / roadmap-insert.sh |

### Tier 2: ship-init Behavior

| AC | Verification |
|---|---|
| AC-007 | Running `/ship-init` in a test repo creates `.claude/commands/ship-*.md` × 7 |
| AC-008 | 7 doc folders created (ideas/decisions/brainstorms/specs/plans/learnings/product) |
| AC-009 | AIR-OS `10 Projects/<repo>/` created with 4 strategy files |
| AC-010 | Existing AIR-OS Project folder content NOT overwritten |
| AC-011 | Re-running `ship-init` is idempotent (no duplicate creates, no errors) |
| AC-012 | `ship-init --upgrade` re-copies commands but preserves `.claude/ship-config.yml` |

### Tier 3: Core Commands End-to-End

| AC | Verification |
|---|---|
| AC-013 | `/ship-idea "X"` produces `IDEA-001-x.md` with `ai-first: true` and preamble |
| AC-014 | `/ship-decision "Y"` produces `D-001-y.md` with `affected-roadmap-items` populated |
| AC-015 | `/ship-roadmap` reorders ROADMAP.md (Now: 3-5 items; Done preserved) |
| AC-016 | `/ship-next` enters brainstorming → produces brainstorm + spec |
| AC-017 | `/ship-next --adhoc "Z"` allocates next R-NNN, inserts into ROADMAP "Now" with `adhoc-inserted=true`, then enters brainstorm |
| AC-018 | `/ship-build --from-spec` enters writing-plans, produces plan, runs executor |
| AC-019 | `/ship-compound` produces learning + moves R-NNN from "Now" → "Done" + strips adhoc marker |

### Tier 4: Sync + Frontmatter Compliance

| AC | Verification |
|---|---|
| AC-020 | First ship-* mirrors 4 strategy files to `docs/product/` |
| AC-021 | Second ship-* within 60s skips sync (freshness window) |
| AC-022 | All ship-* outputs have `ai-first: true` + `## For future Claude` |
| AC-023 | All ship-* outputs use `R-NNN-<kebab-slug>.md` naming (no ADHOC namespace) |
| AC-024 | AIR-OS `_CLAUDE.md` updated to include 7 new note types (idea, brainstorm, learning, vision, strategy, roadmap, quarterly-goal) |
| AC-025 | `docs/product/ROADMAP.md` stale-snapshot warning fires after 7-day drift |

### Tier 5: Delegation

| AC | Verification |
|---|---|
| AC-026 | `ship-roadmap` actually invokes `ce-strategy` or `ce-plan` (visible in transcript) |
| AC-027 | `ship-next` actually invokes `superpowers:brainstorming` |
| AC-028 | `ship-build` actually invokes `superpowers:writing-plans` and lets user pick executor |
| AC-029 | `ship-compound` actually invokes `ce-compound` and `ce-promote` |

---

## 9. Open Questions / Risks

| Topic | Concern | Mitigation |
|---|---|---|
| AIR-OS legacy ADRs (`adr-NNN-*.md`) coexisting with Ship decisions (`D-NNN-*.md`) | Two ADR systems in same Project folder | Spec explicitly defines: `D-NNN` is ship-context (frontmatter `ship-context: true`), `adr-NNN` is ad-hoc; Dataview differentiates via `ship-context` |
| Worktree mapping | `langlive-line-oa-wt-3` and `langlive-line-oa-wt-4` should map to one AIR-OS Project | Each worktree needs `.claude/ship-config.yml` with `airos_project: langlive-line-oa` |
| ce-* skill interface drift | `ce-strategy` or `ce-compound` upgrade may change inputs/outputs | Each `ship-*` wrapping a `ce-*` includes a try/catch fallback message: "ce-X not available, run manually" |
| Concurrent number allocation | Two worktrees running `/ship-idea` or `/ship-next --adhoc` simultaneously may both pick the same NNN | id-gen.sh uses `flock` on a small temp lockfile; collisions detected → second worktree retries with NNN+1 |
| Sync race | User edits ROADMAP.md in Obsidian while sync is running | Atomic write in sync.sh (`cp` to `.tmp` + `mv`) |
| ROADMAP insertion race | `/ship-next --adhoc` modifies AIR-OS ROADMAP.md while user has it open in Obsidian | `roadmap-insert.sh` reads, modifies in-memory, writes via temp + mv; Obsidian re-reads on file change |
| Spec ↔ brainstorm filename divergence | If user renames the brainstorm, the spec/plan/learning fall out of sync | id-gen.sh enforces same slug across the 4 R-NNN files; `/ship-build` reads only by ID prefix, not exact filename |

---

## 10. Migration Considerations

This spec is greenfield. No existing `.claude/commands/ship-*`, no FounderOS/Flora,
no existing strategy files anywhere. Implementation steps (next: writing-plans):

1. Build the skill at `ai_system/claude-skills/ship-workflow/`
2. devsync to `~/.claude/skills/ship-workflow/`
3. Pick one test repo (suggested: `claudecode-discord` — small, low-stakes) and run `/ship-init`
4. Iterate against acceptance criteria
5. Roll out to other repos as they need it

The current `ai_system` repo itself is a candidate for self-hosting (it's a meta-tooling repo so it'd benefit from its own Roadmap), but that decision is for v1.1.

---

*End of spec.*
