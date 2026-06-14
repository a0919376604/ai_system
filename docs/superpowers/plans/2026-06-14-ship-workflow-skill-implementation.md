# Ship Workflow Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable Claude Code skill at `ai_system/claude-skills/ship-workflow/` that installs 7 `ship-*` slash commands into any repo, wraps `superpowers:*` and `compound-engineering:ce-*` skills, and integrates with AIR-OS at `/Users/leric/Documents/SecondBrain` for product strategy storage.

**Architecture:** Bash for lib glue (4 scripts: airos-binding, sync, id-gen, roadmap-insert). Markdown for 7 slash commands and 10 templates. Bats for shell-script TDD. Plain copy (not symlink) on `ship-init` so repos can commit their `.claude/commands/` to git without depending on the skill being installed locally.

**Tech Stack:** Bash 5, Bats (bash testing), Markdown, YAML, Python 3 (for any YAML parsing inside scripts — already present from AIR-OS work).

**Spec:** `docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`

---

## File Structure

All work happens inside `/Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow/`. The `ai_system` repo gets one commit per task. No files outside this folder are touched until Task 14 (AIR-OS `_CLAUDE.md` update) and Task 15 (test repo smoke test).

```
ai_system/claude-skills/ship-workflow/
├── SKILL.md                          [Task 1]
├── README.md                         [Task 1]
├── .gitignore                        [Task 1]
├── commands/                         [Tasks 9-12]
│   ├── ship-init.md                  [Task 9]
│   ├── ship-idea.md                  [Task 10]
│   ├── ship-decision.md              [Task 10]
│   ├── ship-roadmap.md               [Task 11]
│   ├── ship-next.md                  [Task 11]
│   ├── ship-build.md                 [Task 12]
│   └── ship-compound.md              [Task 12]
├── templates/
│   ├── obsidian/                     [Task 7]
│   │   ├── VISION.md
│   │   ├── STRATEGY.md
│   │   ├── ROADMAP.md
│   │   └── QUARTERLY_GOALS.md
│   └── repo/                         [Task 8]
│       ├── IDEA.md
│       ├── DECISION.md
│       ├── BRAINSTORM.md
│       ├── SPEC.md
│       ├── PLAN.md
│       └── LEARNING.md
├── lib/
│   ├── airos-binding.sh              [Task 3]
│   ├── sync.sh                       [Task 4]
│   ├── id-gen.sh                     [Task 5]
│   └── roadmap-insert.sh             [Task 6]
├── tests/                            [Task 2 setup, populated in Tasks 3-6]
│   ├── helpers.bash
│   ├── test_airos-binding.bats       [Task 3]
│   ├── test_sync.bats                [Task 4]
│   ├── test_id-gen.bats              [Task 5]
│   └── test_roadmap-insert.bats      [Task 6]
├── references/                       [Task 13]
│   ├── flow-diagrams.md
│   ├── escape-hatches.md
│   └── ce-skill-mapping.md
└── examples/
    └── ship-workflow.example.yml     [Task 14]

External:
- /Users/leric/Documents/SecondBrain/_CLAUDE.md          [Task 14 — append note types]
- /Users/leric/Desktop/code/claudecode-discord/          [Task 15 — smoke-test target]
```

---

## Task 1: Skill Scaffold

**Files:**
- Create: `ai_system/claude-skills/ship-workflow/SKILL.md`
- Create: `ai_system/claude-skills/ship-workflow/README.md`
- Create: `ai_system/claude-skills/ship-workflow/.gitignore`
- Create: `ai_system/claude-skills/ship-workflow/{commands,templates/obsidian,templates/repo,lib,tests,references,examples}/.gitkeep` (placeholder until populated)

- [ ] **Step 1: Create directory tree**

Run:
```bash
cd /Users/leric/Desktop/code/ai_system
mkdir -p claude-skills/ship-workflow/{commands,templates/obsidian,templates/repo,lib,tests,references,examples}
touch claude-skills/ship-workflow/{commands,templates/obsidian,templates/repo,lib,tests,references,examples}/.gitkeep
```

Verify:
```bash
find claude-skills/ship-workflow -type d | sort
```

Expected output:
```
claude-skills/ship-workflow
claude-skills/ship-workflow/commands
claude-skills/ship-workflow/examples
claude-skills/ship-workflow/lib
claude-skills/ship-workflow/references
claude-skills/ship-workflow/templates
claude-skills/ship-workflow/templates/obsidian
claude-skills/ship-workflow/templates/repo
claude-skills/ship-workflow/tests
```

- [ ] **Step 2: Write `SKILL.md`**

Write `claude-skills/ship-workflow/SKILL.md`:

```markdown
---
name: ship-workflow
description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Installs 7 ship-* slash commands. Use when starting product development in a new repo, capturing ideas/decisions, planning roadmap, or shipping features through the brainstorm → spec → plan → build → compound loop.
---

# Ship Workflow

Per-repo product development workflow. Installs 7 slash commands into a target repo's `.claude/commands/`:

- **`/ship-init`** — Bootstrap workflow (folders, commands, AIR-OS Product Brain stub)
- **`/ship-idea <description>`** — Capture an idea (IDEA-NNN)
- **`/ship-decision <topic>`** — Record an architectural decision (D-NNN)
- **`/ship-roadmap`** — Refresh ROADMAP.md via ce-strategy
- **`/ship-next [--adhoc <desc>]`** — Pick next Roadmap item, brainstorm + spec
- **`/ship-build [--from-spec <path>]`** — Plan + execute via superpowers + executor
- **`/ship-compound`** — Write learning + promote patterns + close Roadmap item

## Dual-Brain Architecture

- **Obsidian Product Brain** at AIR-OS `10 Projects/<repo-name>/` holds VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS
- **Repo Execution Brain** at `<repo>/docs/` holds ideas / decisions / brainstorms / specs / plans / learnings
- One-way sync (Obsidian → repo) on every ship-* command invocation, with 60-second freshness window

## Usage

```bash
# Install (once, in ai_system repo via devsync)
$ devsync push          # makes ~/.claude/skills/ship-workflow/ available

# Per-repo init
$ cd /path/to/your/repo
$ /ship-init            # adds .claude/commands/ + docs/ + AIR-OS strategy files

# Daily flow
$ /ship-next            # pick from Roadmap → brainstorm → spec
$ /ship-build           # plan → execute
$ /ship-compound        # learn → promote → close
```

## Configuration

**Global** (`~/.claude/ship-workflow.yml`):
```yaml
airos_vault: /Users/leric/Documents/SecondBrain
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft
default_id_pad: 3
auto_pull_freshness_window: 60
```

**Per-repo** (`.claude/ship-config.yml`, optional, only on `--custom` init).

## Reference

See `references/flow-diagrams.md` for the full lifecycle diagram, `references/escape-hatches.md` for `--adhoc` behavior, and `references/ce-skill-mapping.md` for which `ce-*` skill each `ship-*` delegates to.

Full spec: `docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
```

- [ ] **Step 3: Write `README.md`**

Write `claude-skills/ship-workflow/README.md`:

```markdown
# Ship Workflow

A Claude Code skill that installs a 7-command product development workflow into any repo.

## What it gives you

```
Roadmap → Brainstorm → Plan → Build → Compound → Roadmap update
```

- Strategy lives in Obsidian (AIR-OS `10 Projects/<repo>/`)
- Per-Roadmap-item artifacts live in the repo (`docs/{ideas,decisions,brainstorms,specs,plans,learnings}/`)
- Auto-pull strategy from Obsidian into repo on every command

## Installation

This skill is distributed via `ai_system/claude-skills/`. After `devsync`, it lives at `~/.claude/skills/ship-workflow/`.

Bootstrap in any repo:
```bash
cd /path/to/your/repo
/ship-init
```

## Commands

| Command | Purpose |
|---|---|
| `/ship-init` | Scaffold workflow in current repo |
| `/ship-idea` | Capture idea (IDEA-NNN) |
| `/ship-decision` | Record decision (D-NNN) |
| `/ship-roadmap` | Refresh ROADMAP.md |
| `/ship-next` | Pick next item → brainstorm + spec |
| `/ship-build` | Plan + execute |
| `/ship-compound` | Learnings + promote patterns + close |

## Development

```bash
# Run tests
cd claude-skills/ship-workflow
bats tests/

# Local install for development
ln -sf $(pwd) ~/.claude/skills/ship-workflow
```

## Specification

`docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md`
```

- [ ] **Step 4: Write `.gitignore`**

Write `claude-skills/ship-workflow/.gitignore`:
```
# Test artifacts
tests/.tmp/
tests/*.log

# Local install symlinks
.installed
```

- [ ] **Step 5: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add claude-skills/ship-workflow/
git commit -m "feat(ship-workflow): scaffold skill directory + SKILL.md + README.md"
```

Verify:
```bash
git log --oneline -1
ls claude-skills/ship-workflow/
```

Expected: one new commit + 9 entries in `ls` (SKILL.md, README.md, .gitignore, 6 directories with `.gitkeep`).

---

## Task 2: Bats Testing Setup

**Files:**
- Create: `claude-skills/ship-workflow/tests/helpers.bash`
- Create: `claude-skills/ship-workflow/tests/test_smoke.bats`

- [ ] **Step 1: Verify bats is installed**

Run:
```bash
which bats || brew install bats-core
bats --version
```

Expected: prints `Bats X.Y.Z`. If missing, install via `brew install bats-core`.

- [ ] **Step 2: Write `tests/helpers.bash`**

This is sourced by every test file. Provides `setup()` / `teardown()` and helpers.

Write `claude-skills/ship-workflow/tests/helpers.bash`:

```bash
#!/usr/bin/env bash
# Test helpers shared across all .bats files.

# Absolute path to the skill root (one level above tests/)
SHIP_SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIP_LIB="$SHIP_SKILL_ROOT/lib"

# Create per-test scratch directory under tests/.tmp/<test-name>/
make_scratch() {
  local test_name="${1:-default}"
  local d="$SHIP_SKILL_ROOT/tests/.tmp/$test_name-$$"
  rm -rf "$d"
  mkdir -p "$d"
  echo "$d"
}

# Build a fake AIR-OS vault under <scratch>/airos with a 10 Projects/<name>/ project folder
make_fake_airos() {
  local scratch="$1"
  local project_name="${2:-test-project}"
  local airos="$scratch/airos"
  local proj="$airos/10 Projects/$project_name"
  mkdir -p "$proj"
  cat > "$proj/VISION.md" <<EOF
---
type: vision
project: "[[$project_name]]"
---
Test vision.
EOF
  cat > "$proj/STRATEGY.md" <<EOF
---
type: strategy
project: "[[$project_name]]"
---
Test strategy.
EOF
  cat > "$proj/ROADMAP.md" <<EOF
---
type: roadmap
project: "[[$project_name]]"
---

## 🔥 Now (3-5 items)

## 🔜 Next

## 🕐 Later

## ✅ Done
EOF
  cat > "$proj/QUARTERLY_GOALS.md" <<EOF
---
type: quarterly-goal
project: "[[$project_name]]"
---
Test goals.
EOF
  echo "$airos"
}

# Build a fake repo under <scratch>/repo
make_fake_repo() {
  local scratch="$1"
  local repo="$scratch/repo"
  mkdir -p "$repo/.claude" "$repo/docs/product" "$repo/docs/ideas" \
           "$repo/docs/decisions" "$repo/docs/brainstorms" \
           "$repo/docs/specs" "$repo/docs/plans" "$repo/docs/learnings"
  echo "$repo"
}

# Write a global config file at $HOME-override (caller sets HOME to scratch)
write_global_config() {
  local home="$1"
  local airos_vault="$2"
  mkdir -p "$home/.claude"
  cat > "$home/.claude/ship-workflow.yml" <<EOF
airos_vault: $airos_vault
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft
default_id_pad: 3
auto_pull_freshness_window: 60
EOF
}
```

- [ ] **Step 3: Write `tests/test_smoke.bats` (proves bats works)**

Write `claude-skills/ship-workflow/tests/test_smoke.bats`:

```bash
#!/usr/bin/env bats
load helpers

@test "bats is wired up" {
  result="$(echo hello)"
  [ "$result" = "hello" ]
}

@test "helpers expose SHIP_SKILL_ROOT" {
  [ -n "$SHIP_SKILL_ROOT" ]
  [ -d "$SHIP_SKILL_ROOT/lib" ]
}

@test "make_scratch creates a fresh directory" {
  scratch="$(make_scratch smoke)"
  [ -d "$scratch" ]
  rm -rf "$scratch"
}

@test "make_fake_airos creates 4 strategy files" {
  scratch="$(make_scratch smoke-airos)"
  airos="$(make_fake_airos "$scratch" foo)"
  [ -f "$airos/10 Projects/foo/VISION.md" ]
  [ -f "$airos/10 Projects/foo/STRATEGY.md" ]
  [ -f "$airos/10 Projects/foo/ROADMAP.md" ]
  [ -f "$airos/10 Projects/foo/QUARTERLY_GOALS.md" ]
  rm -rf "$scratch"
}
```

- [ ] **Step 4: Run smoke tests**

Run:
```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow
bats tests/test_smoke.bats
```

Expected output:
```
test_smoke.bats
 ✓ bats is wired up
 ✓ helpers expose SHIP_SKILL_ROOT
 ✓ make_scratch creates a fresh directory
 ✓ make_fake_airos creates 4 strategy files

4 tests, 0 failures
```

- [ ] **Step 5: Add `tests/.tmp/` to .gitignore (in skill folder)**

Already covered in Task 1 Step 4 (`tests/.tmp/`). Verify:
```bash
grep -q "tests/.tmp/" claude-skills/ship-workflow/.gitignore && echo OK
```

- [ ] **Step 6: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add claude-skills/ship-workflow/tests/
git commit -m "test(ship-workflow): bats setup + smoke tests"
```

---

## Task 3: `lib/airos-binding.sh` — Resolve Config + Project Path

**Files:**
- Create: `claude-skills/ship-workflow/lib/airos-binding.sh`
- Create: `claude-skills/ship-workflow/tests/test_airos-binding.bats`

This script resolves: given a repo's cwd, what AIR-OS project path should sync target? Reads global config + optional per-repo override.

- [ ] **Step 1: Write the failing test**

Write `claude-skills/ship-workflow/tests/test_airos-binding.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch airos-binding)"
  export AIROS="$(make_fake_airos "$SCRATCH" "my-repo")"
  export REPO="$(make_fake_repo "$SCRATCH")"
  export HOME_OVERRIDE="$SCRATCH/home"
  write_global_config "$HOME_OVERRIDE" "$AIROS"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "airos-binding: auto-detect by basename when no per-repo override" {
  cd "$REPO" || exit 1
  # Rename the repo dir to 'my-repo' so basename matches
  mv "$REPO" "$SCRATCH/my-repo"
  cd "$SCRATCH/my-repo" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)"
  [ "$result" = "$AIROS/10 Projects/my-repo" ]
}

@test "airos-binding: per-repo override wins over basename" {
  cd "$REPO" || exit 1
  mkdir -p .claude
  cat > .claude/ship-config.yml <<EOF
airos_project: my-repo
EOF
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)"
  [ "$result" = "$AIROS/10 Projects/my-repo" ]
}

@test "airos-binding: emits vault path" {
  cd "$REPO" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" vault)"
  [ "$result" = "$AIROS" ]
}

@test "airos-binding: errors out when global config missing" {
  cd "$REPO" || exit 1
  run env HOME="$SCRATCH/nonexistent" "$SHIP_LIB/airos-binding.sh" vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"ship-workflow.yml not found"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail (no script yet)**

Run:
```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow
bats tests/test_airos-binding.bats
```

Expected: all 4 tests FAIL with "No such file or directory" pointing at `airos-binding.sh`.

- [ ] **Step 3: Write `lib/airos-binding.sh`**

Write `claude-skills/ship-workflow/lib/airos-binding.sh`:

```bash
#!/usr/bin/env bash
# airos-binding.sh — resolve AIR-OS vault + per-repo project path.
#
# Usage:
#   airos-binding.sh vault          # prints vault root
#   airos-binding.sh project_path   # prints AIR-OS 10 Projects/<name>/ path
#   airos-binding.sh project_name   # prints just the project name
#   airos-binding.sh roadmap_mode   # prints "soft" | "strict"

set -euo pipefail

GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
PER_REPO_CFG="$(pwd)/.claude/ship-config.yml"

if [ ! -f "$GLOBAL_CFG" ]; then
  echo "ERROR: ${GLOBAL_CFG##*/} not found at $GLOBAL_CFG" >&2
  echo "Hint: create it with at least 'airos_vault: /path/to/SecondBrain'" >&2
  exit 1
fi

# Minimal YAML key reader (assumes simple key: value lines; no nesting).
read_yaml_key() {
  local file="$1"
  local key="$2"
  awk -v k="$key" -F': *' '$1==k { sub(/[\r\n]+$/, "", $2); gsub(/^"|"$/, "", $2); print $2; exit }' "$file"
}

VAULT="$(read_yaml_key "$GLOBAL_CFG" airos_vault)"
PROJECTS_DIR="$(read_yaml_key "$GLOBAL_CFG" airos_projects_dir)"
PROJECTS_DIR="${PROJECTS_DIR:-10 Projects}"
ROADMAP_MODE_GLOBAL="$(read_yaml_key "$GLOBAL_CFG" default_roadmap_mode)"
ROADMAP_MODE_GLOBAL="${ROADMAP_MODE_GLOBAL:-soft}"

# Per-repo overrides
PROJECT_NAME_OVERRIDE=""
ROADMAP_MODE_OVERRIDE=""
if [ -f "$PER_REPO_CFG" ]; then
  PROJECT_NAME_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" airos_project)"
  ROADMAP_MODE_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" roadmap_mode)"
fi

PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(basename "$(pwd)")}"
ROADMAP_MODE="${ROADMAP_MODE_OVERRIDE:-$ROADMAP_MODE_GLOBAL}"

case "${1:-}" in
  vault)         echo "$VAULT" ;;
  project_path)  echo "$VAULT/$PROJECTS_DIR/$PROJECT_NAME" ;;
  project_name)  echo "$PROJECT_NAME" ;;
  roadmap_mode)  echo "$ROADMAP_MODE" ;;
  *)
    echo "Usage: $0 {vault|project_path|project_name|roadmap_mode}" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Make executable**

```bash
chmod +x claude-skills/ship-workflow/lib/airos-binding.sh
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
bats tests/test_airos-binding.bats
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd /Users/leric/Desktop/code/ai_system
git add claude-skills/ship-workflow/lib/airos-binding.sh \
        claude-skills/ship-workflow/tests/test_airos-binding.bats
git commit -m "feat(ship-workflow): lib/airos-binding.sh — resolve config + paths"
```

---

## Task 4: `lib/sync.sh` — Obsidian → Repo One-Way Sync

**Files:**
- Create: `claude-skills/ship-workflow/lib/sync.sh`
- Create: `claude-skills/ship-workflow/tests/test_sync.bats`

Per spec §6: copy 4 strategy files from AIR-OS project folder to repo `docs/product/`. Skip if `.claude/.ship-last-pull` is fresher than freshness window.

- [ ] **Step 1: Write the failing tests**

Write `claude-skills/ship-workflow/tests/test_sync.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch sync)"
  export AIROS="$(make_fake_airos "$SCRATCH" "test-repo")"
  export REPO="$(make_fake_repo "$SCRATCH")"
  mv "$REPO" "$SCRATCH/test-repo"
  export REPO="$SCRATCH/test-repo"
  export HOME_OVERRIDE="$SCRATCH/home"
  write_global_config "$HOME_OVERRIDE" "$AIROS"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "sync: copies 4 strategy files to docs/product/" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ -f "$REPO/docs/product/VISION.md" ]
  [ -f "$REPO/docs/product/STRATEGY.md" ]
  [ -f "$REPO/docs/product/ROADMAP.md" ]
  [ -f "$REPO/docs/product/QUARTERLY_GOALS.md" ]
}

@test "sync: writes .ship-last-pull timestamp" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ -f "$REPO/.claude/.ship-last-pull" ]
}

@test "sync: skips when within freshness window" {
  cd "$REPO"
  # First sync
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  # Modify AIR-OS source
  echo "MODIFIED" >> "$AIROS/10 Projects/test-repo/ROADMAP.md"
  # Second sync within window — should NOT pick up the change
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  ! grep -q "MODIFIED" "$REPO/docs/product/ROADMAP.md"
}

@test "sync: re-syncs when window expired" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  echo "MODIFIED" >> "$AIROS/10 Projects/test-repo/ROADMAP.md"
  # Backdate last-pull beyond freshness window (60s default)
  touch -t "$(date -v-2M +%Y%m%d%H%M)" "$REPO/.claude/.ship-last-pull"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  grep -q "MODIFIED" "$REPO/docs/product/ROADMAP.md"
}

@test "sync: warns but does not abort when an AIR-OS file is missing" {
  rm "$AIROS/10 Projects/test-repo/QUARTERLY_GOALS.md"
  cd "$REPO"
  run env HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUARTERLY_GOALS.md not found"* ]]
}

@test "sync: uses atomic write (no half-written files on race)" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  # After sync no .tmp files should remain
  ! ls "$REPO/docs/product/"*.tmp 2>/dev/null
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
bats tests/test_sync.bats
```

Expected: all 6 tests FAIL ("No such file or directory: lib/sync.sh").

- [ ] **Step 3: Write `lib/sync.sh`**

Write `claude-skills/ship-workflow/lib/sync.sh`:

```bash
#!/usr/bin/env bash
# sync.sh — one-way sync of 4 strategy files from AIR-OS to repo/docs/product/.
# Skipped if the freshness window has not yet expired since the last pull.
#
# Usage:
#   sync.sh                # honor freshness window (default 60s)
#   sync.sh --force        # force resync regardless of freshness

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VAULT="$("$LIB_DIR/airos-binding.sh" vault)"
PROJECT_PATH="$("$LIB_DIR/airos-binding.sh" project_path)"
REPO_ROOT="$(pwd)"
LAST_PULL="$REPO_ROOT/.claude/.ship-last-pull"

GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
FRESHNESS=$(awk -F': *' '$1=="auto_pull_freshness_window" { print $2; exit }' "$GLOBAL_CFG" 2>/dev/null || true)
FRESHNESS="${FRESHNESS:-60}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ "$FORCE" -ne 1 ] && [ -f "$LAST_PULL" ]; then
  # macOS-compatible stat
  if command -v gstat >/dev/null 2>&1; then
    last_mtime=$(gstat -c %Y "$LAST_PULL")
  else
    last_mtime=$(stat -f %m "$LAST_PULL" 2>/dev/null || stat -c %Y "$LAST_PULL")
  fi
  age=$(( $(date +%s) - last_mtime ))
  if [ "$age" -lt "$FRESHNESS" ]; then
    exit 0
  fi
fi

mkdir -p "$REPO_ROOT/docs/product"
for f in VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md; do
  src="$PROJECT_PATH/$f"
  dst="$REPO_ROOT/docs/product/$f"
  if [ -f "$src" ]; then
    # Atomic write: cp to .tmp then mv
    cp "$src" "$dst.tmp"
    mv "$dst.tmp" "$dst"
  else
    echo "WARN: $f not found at $src — skipping" >&2
  fi
done

# Update freshness marker
mkdir -p "$REPO_ROOT/.claude"
date +%s > "$LAST_PULL"
```

- [ ] **Step 4: Make executable**

```bash
chmod +x claude-skills/ship-workflow/lib/sync.sh
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bats tests/test_sync.bats
```

Expected: `6 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/ship-workflow/lib/sync.sh \
        claude-skills/ship-workflow/tests/test_sync.bats
git commit -m "feat(ship-workflow): lib/sync.sh — Obsidian → repo sync + freshness window"
```

---

## Task 5: `lib/id-gen.sh` — Next NNN Allocator with flock

**Files:**
- Create: `claude-skills/ship-workflow/lib/id-gen.sh`
- Create: `claude-skills/ship-workflow/tests/test_id-gen.bats`

Per spec §9 risks: handle concurrent worktrees via `flock` on a temp lockfile.

- [ ] **Step 1: Write the failing tests**

Write `claude-skills/ship-workflow/tests/test_id-gen.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch id-gen)"
  export REPO="$(make_fake_repo "$SCRATCH")"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "id-gen: returns IDEA-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" idea)"
  [ "$result" = "IDEA-001" ]
}

@test "id-gen: returns D-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" decision)"
  [ "$result" = "D-001" ]
}

@test "id-gen: returns R-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" roadmap)"
  [ "$result" = "R-001" ]
}

@test "id-gen: returns next IDEA after existing" {
  cd "$REPO"
  touch docs/ideas/IDEA-005-foo.md
  touch docs/ideas/IDEA-002-bar.md
  result="$("$SHIP_LIB/id-gen.sh" idea)"
  [ "$result" = "IDEA-006" ]
}

@test "id-gen: returns next D after existing" {
  cd "$REPO"
  touch docs/decisions/D-003-xyz.md
  result="$("$SHIP_LIB/id-gen.sh" decision)"
  [ "$result" = "D-004" ]
}

@test "id-gen: returns next R across all R-NNN folders" {
  cd "$REPO"
  touch docs/brainstorms/R-007-a.md
  touch docs/specs/R-009-b.md
  touch docs/plans/R-002-c.md
  result="$("$SHIP_LIB/id-gen.sh" roadmap)"
  [ "$result" = "R-010" ]
}

@test "id-gen: errors on unknown type" {
  cd "$REPO"
  run "$SHIP_LIB/id-gen.sh" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown type"* ]]
}

@test "id-gen: serializes concurrent invocations (no duplicates)" {
  cd "$REPO"
  # Spawn 5 concurrent calls
  declare -a results
  for i in 1 2 3 4 5; do
    "$SHIP_LIB/id-gen.sh" idea --reserve > "$REPO/.tmp-$i" &
  done
  wait
  # Collect outputs; expect 5 unique IDEA-NNN values
  ids=$(cat "$REPO"/.tmp-* | sort -u | wc -l | tr -d ' ')
  [ "$ids" -eq 5 ]
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
bats tests/test_id-gen.bats
```

Expected: all 8 tests FAIL.

- [ ] **Step 3: Write `lib/id-gen.sh`**

Write `claude-skills/ship-workflow/lib/id-gen.sh`:

```bash
#!/usr/bin/env bash
# id-gen.sh — allocate the next ID for IDEA / D / R sequences.
#
# Usage:
#   id-gen.sh idea            # next IDEA-NNN
#   id-gen.sh decision        # next D-NNN
#   id-gen.sh roadmap         # next R-NNN
#   id-gen.sh <type> --reserve  # next + create a reservation marker so concurrent
#                                callers can't pick the same NNN

set -euo pipefail

TYPE="${1:-}"
RESERVE=0
[ "${2:-}" = "--reserve" ] && RESERVE=1

REPO_ROOT="$(pwd)"
LOCKFILE="$REPO_ROOT/.claude/.id-gen.lock"
mkdir -p "$REPO_ROOT/.claude"

# Pad width (read from global config, default 3)
GLOBAL_CFG="${HOME}/.claude/ship-workflow.yml"
PAD=$(awk -F': *' '$1=="default_id_pad" { print $2; exit }' "$GLOBAL_CFG" 2>/dev/null || true)
PAD="${PAD:-3}"

case "$TYPE" in
  idea)
    prefix="IDEA-"
    search_dirs=("$REPO_ROOT/docs/ideas")
    ;;
  decision)
    prefix="D-"
    search_dirs=("$REPO_ROOT/docs/decisions")
    ;;
  roadmap)
    prefix="R-"
    search_dirs=("$REPO_ROOT/docs/brainstorms"
                 "$REPO_ROOT/docs/specs"
                 "$REPO_ROOT/docs/plans"
                 "$REPO_ROOT/docs/learnings")
    ;;
  *)
    echo "ERROR: unknown type '$TYPE' (expected idea|decision|roadmap)" >&2
    exit 2
    ;;
esac

next_id() {
  local max=0
  for d in "${search_dirs[@]}"; do
    [ -d "$d" ] || continue
    # find ${prefix}NNN-*.md, extract NNN as number
    while IFS= read -r f; do
      local n
      n=$(basename "$f" | sed -E "s/^${prefix}([0-9]+).*/\1/")
      n=$((10#$n))
      [ "$n" -gt "$max" ] && max=$n
    done < <(find "$d" -maxdepth 1 -type f -name "${prefix}*.md" 2>/dev/null)
  done

  # Also account for reservations
  if [ -f "$REPO_ROOT/.claude/.id-reservations" ]; then
    while IFS= read -r line; do
      if [[ "$line" == "${prefix}"* ]]; then
        local n
        n="${line#${prefix}}"
        n=$((10#$n))
        [ "$n" -gt "$max" ] && max=$n
      fi
    done < "$REPO_ROOT/.claude/.id-reservations"
  fi

  printf "%s%0*d" "$prefix" "$PAD" "$((max + 1))"
}

# Serialize with flock so concurrent invocations don't collide.
exec 9>"$LOCKFILE"
flock 9

new_id="$(next_id)"

if [ "$RESERVE" -eq 1 ]; then
  echo "$new_id" >> "$REPO_ROOT/.claude/.id-reservations"
fi

echo "$new_id"
```

- [ ] **Step 4: Make executable**

```bash
chmod +x claude-skills/ship-workflow/lib/id-gen.sh
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bats tests/test_id-gen.bats
```

Expected: `8 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/ship-workflow/lib/id-gen.sh \
        claude-skills/ship-workflow/tests/test_id-gen.bats
git commit -m "feat(ship-workflow): lib/id-gen.sh — next NNN allocator with flock"
```

---

## Task 6: `lib/roadmap-insert.sh` — Insert R-NNN into ROADMAP "Now"

**Files:**
- Create: `claude-skills/ship-workflow/lib/roadmap-insert.sh`
- Create: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`

Used by `/ship-next --adhoc` to atomically insert a new R-NNN into the AIR-OS ROADMAP.md "🔥 Now" section.

- [ ] **Step 1: Write the failing tests**

Write `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch roadmap-insert)"
  export AIROS="$(make_fake_airos "$SCRATCH" "demo")"
  export ROADMAP="$AIROS/10 Projects/demo/ROADMAP.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "roadmap-insert: appends to empty Now section" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-018 "Fix langfuse leak"
  grep -q "R-018" "$ROADMAP"
  # Confirm it's under the Now heading
  awk '/^## 🔥 Now/,/^## /' "$ROADMAP" | grep -q "R-018"
}

@test "roadmap-insert: marks adhoc-inserted=true" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-019 "Quick fix" --adhoc
  grep -q "adhoc-inserted=true" "$ROADMAP"
}

@test "roadmap-insert: skips adhoc marker when --adhoc absent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-020 "Planned work"
  ! awk '/R-020/' "$ROADMAP" | grep -q "adhoc-inserted=true"
}

@test "roadmap-insert: preserves existing Now items" {
  # Pre-populate
  sed -i.bak '/^## 🔥 Now/a\
- [ ] **R-001** Existing item' "$ROADMAP" && rm "$ROADMAP.bak"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-002 "New item"
  grep -q "R-001" "$ROADMAP"
  grep -q "R-002" "$ROADMAP"
}

@test "roadmap-insert: writes atomically (no .tmp left)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-021 "Atomic test"
  ! ls "$AIROS/10 Projects/demo/"*.tmp 2>/dev/null
}

@test "roadmap-insert: errors when ROADMAP.md missing" {
  run "$SHIP_LIB/roadmap-insert.sh" "$AIROS/nonexistent/ROADMAP.md" R-099 "x"
  [ "$status" -ne 0 ]
}

@test "roadmap-insert: errors when no Now heading found" {
  echo "no headings here" > "$ROADMAP"
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-099 "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Now"* ]]
}
```

- [ ] **Step 2: Run tests to verify failure**

```bash
bats tests/test_roadmap-insert.bats
```

Expected: all 7 tests FAIL.

- [ ] **Step 3: Write `lib/roadmap-insert.sh`**

Write `claude-skills/ship-workflow/lib/roadmap-insert.sh`:

```bash
#!/usr/bin/env bash
# roadmap-insert.sh — insert a new R-NNN line into ROADMAP.md "🔥 Now" section.
#
# Usage:
#   roadmap-insert.sh <ROADMAP.md path> <R-NNN> <description> [--adhoc]

set -euo pipefail

ROADMAP="${1:-}"
RID="${2:-}"
DESC="${3:-}"
ADHOC=0
[ "${4:-}" = "--adhoc" ] && ADHOC=1

if [ -z "$ROADMAP" ] || [ -z "$RID" ] || [ -z "$DESC" ]; then
  echo "Usage: $0 <ROADMAP.md> <R-NNN> <description> [--adhoc]" >&2
  exit 2
fi
if [ ! -f "$ROADMAP" ]; then
  echo "ERROR: ROADMAP not found: $ROADMAP" >&2
  exit 1
fi

if ! grep -q "^## 🔥 Now" "$ROADMAP"; then
  echo "ERROR: no '## 🔥 Now' heading found in $ROADMAP" >&2
  exit 1
fi

# Build the new line
suffix=""
if [ "$ADHOC" -eq 1 ]; then
  suffix=" · adhoc-inserted=true · status=in-progress"
else
  suffix=" · status=in-progress"
fi
NEW_LINE="- [ ] **${RID}** ${DESC}${suffix}"

# Insert after the Now heading. Atomic write via .tmp + mv.
TMP="${ROADMAP}.tmp"
awk -v line="$NEW_LINE" '
  { print }
  /^## 🔥 Now/ && !inserted {
    print line
    inserted = 1
  }
' "$ROADMAP" > "$TMP"
mv "$TMP" "$ROADMAP"
```

- [ ] **Step 4: Make executable**

```bash
chmod +x claude-skills/ship-workflow/lib/roadmap-insert.sh
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bats tests/test_roadmap-insert.bats
```

Expected: `7 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/ship-workflow/lib/roadmap-insert.sh \
        claude-skills/ship-workflow/tests/test_roadmap-insert.bats
git commit -m "feat(ship-workflow): lib/roadmap-insert.sh — atomic Now-section insert"
```

---

## Task 7: Obsidian Strategy Templates (4 files)

**Files:**
- Create: `claude-skills/ship-workflow/templates/obsidian/VISION.md`
- Create: `claude-skills/ship-workflow/templates/obsidian/STRATEGY.md`
- Create: `claude-skills/ship-workflow/templates/obsidian/ROADMAP.md`
- Create: `claude-skills/ship-workflow/templates/obsidian/QUARTERLY_GOALS.md`

Each template uses AIR-OS frontmatter (ai-first, project wikilink) and a "For future Claude" preamble. `{{project}}` is a literal token that `ship-init` replaces.

- [ ] **Step 1: Write `templates/obsidian/VISION.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: vision
tags: [vision, {{project}}]
ai-first: true
project: "[[{{project}}]]"
maintained-via: hand
---

## For future Claude
> Long-term vision for {{project}}. Why does this product exist?
> What does the world look like 3-5 years out if we succeed?
> This file is mostly stable — updates are rare and significant.

## Vision Statement
<one paragraph: where we're headed>

## Why Now
<what makes this the right moment>

## Who It's For
<the target user, with enough specificity to choose between trade-offs>

## What It Looks Like When Done
<concrete imagery: pages, flows, interactions, outcomes>
```

- [ ] **Step 2: Write `templates/obsidian/STRATEGY.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: strategy
tags: [strategy, {{project}}]
ai-first: true
project: "[[{{project}}]]"
maintained-via: hand
---

## For future Claude
> Current strategic direction for {{project}}. Reviewed quarterly.
> This is how vision becomes a sequence of bets.

## Current Bet
<one sentence: the single most important thing we believe right now>

## Why This Bet
<2-3 sentences: the reasoning>

## What Would Change The Bet
<concrete observations that would flip our direction>

## Adjacent Bets We're NOT Making
<the strategic "no" list — what we're consciously choosing not to do>

## Constraints
<budget, time, team, technical limits>
```

- [ ] **Step 3: Write `templates/obsidian/ROADMAP.md`**

````markdown
---
date: {{date}}
updated: {{date}}
type: roadmap
tags: [roadmap, {{project}}]
ai-first: true
project: "[[{{project}}]]"
maintained-via: both
---

## For future Claude
> Active Roadmap for {{project}}.
> "Now" = 3-5 items currently in motion.
> "Next" = brainstormed and ready to start.
> "Later" = ideas with merit but not scheduled.
> "Done" = shipped, kept for history.
> Items inserted via `/ship-next --adhoc` carry the marker `adhoc-inserted=true` until they ship.

## 🔥 Now (3-5 items)
<!-- /ship-next --adhoc inserts here -->

## 🔜 Next

## 🕐 Later

## ✅ Done
````

- [ ] **Step 4: Write `templates/obsidian/QUARTERLY_GOALS.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: quarterly-goal
tags: [quarterly-goal, {{project}}]
ai-first: true
project: "[[{{project}}]]"
maintained-via: hand
---

## For future Claude
> Quarterly goals for {{project}}. Reviewed at the start of each quarter
> and used as a forcing function when picking Roadmap "Now" items.

## Q? YYYY — <theme>

### Goal 1
<concrete outcome with metric>

### Goal 2

### Goal 3

## Retrospective (filled at end of quarter)
<what shipped, what slipped, why>
```

- [ ] **Step 5: Verify all 4 files**

```bash
cd /Users/leric/Desktop/code/ai_system
for f in claude-skills/ship-workflow/templates/obsidian/*.md; do
  echo "=== $f ==="
  head -3 "$f"
  grep -c "## For future Claude" "$f"
  grep -c "ai-first: true" "$f"
done
```

Expected: 4 files; each prints `1` and `1` for the two greps.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/ship-workflow/templates/obsidian/
git commit -m "feat(ship-workflow): Obsidian Product Brain templates (4 files)"
```

---

## Task 8: Repo Per-Roadmap-Item Templates (6 files)

**Files:**
- Create: `claude-skills/ship-workflow/templates/repo/IDEA.md`
- Create: `claude-skills/ship-workflow/templates/repo/DECISION.md`
- Create: `claude-skills/ship-workflow/templates/repo/BRAINSTORM.md`
- Create: `claude-skills/ship-workflow/templates/repo/SPEC.md`
- Create: `claude-skills/ship-workflow/templates/repo/PLAN.md`
- Create: `claude-skills/ship-workflow/templates/repo/LEARNING.md`

- [ ] **Step 1: Write `templates/repo/IDEA.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: idea
id: {{id}}
tags: [idea, {{project}}]
ai-first: true
project: "[[{{project}}]]"
status: captured
impact: medium
confidence: medium
target-user: ""
dependencies: []
related-roadmap-item: null
---

## For future Claude
> {{id}}: <one-line summary>
> Why this might matter, who it's for, and the evidence that supports it.

## Summary
## Problem
## Target User
## Evidence
<observations, support tickets, user quotes — with dates>

## Impact
<expected magnitude + reasoning>

## Confidence
<stated | high | medium | speculation — and why>

## Dependencies
<technical or organizational>

## Risks
## Possible Roadmap Item
<what an R-NNN version of this would look like>
```

- [ ] **Step 2: Write `templates/repo/DECISION.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: decision
id: {{id}}
tags: [decision, adr, {{project}}]
ai-first: true
project: "[[{{project}}]]"
decision-status: proposed
options: []
chosen: ""
supersedes: null
superseded-by: null
affected-roadmap-items: []
ship-context: true
confidence: high
---

## For future Claude
> {{id}}: <one-line summary of the decision>
> What were the alternatives, what was chosen, and why.

## Context
## Options Considered
- Option A: ...
- Option B: ...

## Decision
## Reasoning
## Consequences
## Affected Roadmap Items
## What would change my mind
```

- [ ] **Step 3: Write `templates/repo/BRAINSTORM.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: brainstorm
id: {{id}}
tags: [brainstorm, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-item: {{id}}
spec-path: docs/specs/{{id}}-{{slug}}.md
plan-path: docs/plans/{{id}}-{{slug}}.md
---

## For future Claude
> {{id}}: brainstorm session for <topic>.
> Captures the design exploration before formal spec.

## Problem Framing
## Approaches Considered
## Selected Approach + Why
## Open Questions Carried Into Spec
```

- [ ] **Step 4: Write `templates/repo/SPEC.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: spec
id: {{id}}
tags: [spec, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-item: {{id}}
---

## For future Claude
> {{id}}: spec for <topic>.
> The contract that the plan + build implement.

(Use superpowers:brainstorming's spec format from here onward.)
```

- [ ] **Step 5: Write `templates/repo/PLAN.md`**

```markdown
# {{id}} Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** <one sentence>

**Architecture:** <2-3 sentences>

**Tech Stack:** <libraries>

**Spec:** `docs/specs/{{id}}-{{slug}}.md`

---

(Use superpowers:writing-plans's plan format from here onward.)
```

- [ ] **Step 6: Write `templates/repo/LEARNING.md`**

```markdown
---
date: {{date}}
updated: {{date}}
type: learning
id: {{id}}
tags: [learning, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-item: {{id}}
shipped: true
shipped-date: {{date}}
---

## For future Claude
> {{id}}: post-ship learning for <topic>.
> What worked, what didn't, what to remember next time.

## What Shipped
## What Changed From Plan
## Bugs
## Reusable Patterns
> Patterns worth promoting to 40 Knowledge/ or 30 Engineering/ (handled by `/ship-compound`).

## Technical Debt
## Future Follow-ups
```

- [ ] **Step 7: Verify all 6 files**

```bash
ls claude-skills/ship-workflow/templates/repo/ | wc -l
for f in claude-skills/ship-workflow/templates/repo/*.md; do
  grep -c "{{id}}" "$f" || true
done
```

Expected: `6`. Each file has `{{id}}` (or 0 for PLAN.md which uses literal "id" in the header — that's fine, PLAN.md still has `{{id}}` in frontmatter? Actually PLAN.md as written uses `{{id}}` in title — verify).

- [ ] **Step 8: Commit**

```bash
git add claude-skills/ship-workflow/templates/repo/
git commit -m "feat(ship-workflow): repo per-Roadmap-item templates (6 files)"
```

---

## Task 9: `commands/ship-init.md`

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-init.md`

This is the slash command markdown that Claude Code reads when the user types `/ship-init`. It's a prompt that tells Claude how to scaffold the workflow into the current repo.

- [ ] **Step 1: Write `commands/ship-init.md`**

````markdown
---
name: ship-init
description: Bootstrap Ship Workflow in the current repo. Creates .claude/commands/ ship-* slash commands, docs/ subfolders for ideas/decisions/brainstorms/specs/plans/learnings/product, and AIR-OS Product Brain folder with VISION/STRATEGY/ROADMAP/QUARTERLY_GOALS templates. Idempotent. Use --custom to write a per-repo override config. Use --upgrade to refresh just the .claude/commands/ files from the latest skill version.
---

# /ship-init

You are bootstrapping the Ship Workflow in the user's current repo.

## Arguments

- `--custom` — interactively prompt for per-repo config overrides and write `.claude/ship-config.yml`
- `--upgrade` — only re-copy `.claude/commands/ship-*.md` from the skill (preserves docs/ and Obsidian content)

## Steps

1. **Identify project name and AIR-OS path.** Run:
   ```bash
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path
   ~/.claude/skills/ship-workflow/lib/airos-binding.sh vault
   ```
   If the global config (`~/.claude/ship-workflow.yml`) is missing, STOP and ask the user to create it with `airos_vault: /path/to/SecondBrain`.

2. **`--upgrade` short-circuit.** If `--upgrade`:
   - `cp ~/.claude/skills/ship-workflow/commands/*.md .claude/commands/`
   - Done. Skip the rest.

3. **Scaffold repo side.** Create:
   - `.claude/commands/` and copy all 7 `ship-*.md` from `~/.claude/skills/ship-workflow/commands/`
   - `docs/ideas/`, `docs/decisions/`, `docs/brainstorms/`, `docs/specs/`, `docs/plans/`, `docs/learnings/`, `docs/product/`
   - `docs/learnings/_log.md` with header:
     ```markdown
     # Ship Workflow Log

     | Date | Command | R-NNN | Note | Adhoc? |
     |---|---|---|---|---|
     ```
   - `.claude/.gitignore` adding `.ship-last-pull` and `.id-gen.lock` and `.id-reservations`

4. **`--custom` interactive config.** If `--custom`:
   - Ask: "Override AIR-OS project name? (default: <basename>)"
   - Ask: "Roadmap mode (soft/strict, default: <global>)"
   - Write answers to `.claude/ship-config.yml` (only the keys the user customized)

5. **Scaffold AIR-OS side.** If `<project_path>` does not exist:
   - Create `<project_path>/`
   - For each of VISION.md / STRATEGY.md / ROADMAP.md / QUARTERLY_GOALS.md:
     - If absent, copy from `~/.claude/skills/ship-workflow/templates/obsidian/<name>`
     - Substitute `{{project}}` with `<project_name>` and `{{date}}` with today's date (YYYY-MM-DD)
   - **NEVER overwrite an existing file in AIR-OS.**

6. **Interactive seed prompts.** Ask the user (each skippable):
   - "What's the one-line vision for `<project_name>`?" → write into VISION.md
   - "What's the first Roadmap item description (R-001)?" → if provided, run `lib/roadmap-insert.sh "<roadmap_path>" R-001 "<desc>"`

7. **Verify.** Run:
   ```bash
   ls .claude/commands/   # should have 7 ship-*.md files
   ls docs/               # should have 7 subdirs
   ls "<project_path>"    # should have 4 strategy .md files
   ```

8. **Commit.** Run:
   ```bash
   git add .claude/commands .claude/.gitignore docs/
   git commit -m "chore: initialize ship-workflow (7 commands + 7 folders)"
   ```
   If the user is in a worktree on a feature branch, mention it. Don't push.

9. **Report.** Tell the user:
   - Project name resolved
   - AIR-OS project path
   - Number of commands installed
   - Whether VISION / R-001 were seeded
   - Next suggested command: `/ship-roadmap` to plan further items

## Idempotency

Every step must be safe to re-run:
- Creating an existing directory: silently skip
- Copying a file that exists in target: skip (unless `--upgrade`, then overwrite commands only)
- AIR-OS strategy files: NEVER overwrite

## Failure modes

- Global config missing → stop with clear message
- Not in a git repo → warn but continue (vault folder still useful)
- AIR-OS vault path doesn't exist → ERROR, ask user to fix
````

- [ ] **Step 2: Verify file**

```bash
grep -c "^# /ship-init" claude-skills/ship-workflow/commands/ship-init.md
grep -c "lib/airos-binding.sh" claude-skills/ship-workflow/commands/ship-init.md
```

Expected: `1` and `≥3`.

- [ ] **Step 3: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-init.md
git commit -m "feat(ship-workflow): commands/ship-init.md"
```

---

## Task 10: Capture Commands (`ship-idea` + `ship-decision`)

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-idea.md`
- Create: `claude-skills/ship-workflow/commands/ship-decision.md`

- [ ] **Step 1: Write `commands/ship-idea.md`**

````markdown
---
name: ship-idea
description: Capture a new product idea as IDEA-NNN with AIR-OS-conformant frontmatter. Optionally delegates depth-of-thought to compound-engineering:ce-ideate. Use when an idea worth recording arises during conversation, slack scroll, user feedback, or competitor scan.
---

# /ship-idea

You are capturing a new idea into `docs/ideas/IDEA-NNN-<slug>.md`.

## Argument

`<description>` — one-line natural description (Claude generates the slug from it)

## Steps

1. **Sync product brain** (cheap if fresh):
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Allocate ID:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh idea)
   ```

3. **Generate slug.** Take `<description>`, lowercase, kebab-case, strip stopwords, cap 6 words. Example: "Multimodal feedback loop for support agents" → `multimodal-feedback-loop-agents`.

4. **(Optional, on user request)** Invoke `compound-engineering:ce-ideate` with `<description>` to deepen the Problem / Evidence / Impact sections before writing the file.

5. **Render template.** Read `~/.claude/skills/ship-workflow/templates/repo/IDEA.md` and substitute `{{date}}` (today), `{{id}}` ($ID), `{{project}}` ($(./lib/airos-binding.sh project_name)). Write the result to `docs/ideas/${ID}-${slug}.md`.

6. **Fill the For future Claude preamble + Summary + Problem.** Use `<description>` and any extra context the user provided. Leave Target User / Evidence / Impact / Confidence / Dependencies / Risks / Possible Roadmap Item as section headers with `_to-fill_` placeholders only if the user is explicit that they want a quick capture; otherwise drive a short interactive fill-in.

7. **Append log line:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-idea | $ID | $description | n |" >> docs/learnings/_log.md
   ```

8. **Commit:**
   ```bash
   git add docs/ideas/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "idea: $ID $description"
   ```

9. **Report:** Tell the user the ID + file path + 1-line summary, and offer "Want to graduate this into a Roadmap item via /ship-roadmap?" if confidence is medium+ or impact is high.

## Failure modes

- Global config missing → run `/ship-init` first
- `docs/ideas/` doesn't exist → run `/ship-init` first
````

- [ ] **Step 2: Write `commands/ship-decision.md`**

````markdown
---
name: ship-decision
description: Record an architectural or product decision as D-NNN with options/chosen/reasoning. Optionally invokes compound-engineering:ce-doc-review for an independent read. Use when a meaningful trade-off has been made — switching libraries, refactoring boundaries, deciding scope, etc.
---

# /ship-decision

You are recording a decision into `docs/decisions/D-NNN-<slug>.md`.

## Argument

`<topic>` — short identifier (Claude infers the rest from conversation)

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Allocate ID:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh decision)
   ```

3. **Generate slug** from `<topic>` (same rules as ship-idea).

4. **Read ROADMAP** (`docs/product/ROADMAP.md`) to determine `affected-roadmap-items`. Look at R-NNN entries in "Now" and "Next" and pick the ones plausibly impacted by this decision. If none, leave empty.

5. **Infer Context / Options / Chosen / Reasoning / Consequences** from the last 20-50 conversation messages. If the user wants more rigor, invoke `compound-engineering:ce-doc-review` on the draft.

6. **Render template** with `{{date}}` / `{{id}}` / `{{project}}` and write to `docs/decisions/${ID}-${slug}.md`. Make sure `ship-context: true` is set.

7. **Append log:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-decision | $ID | $topic | n |" >> docs/learnings/_log.md
   ```

8. **Commit:**
   ```bash
   git add docs/decisions/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "decision: $ID $topic"
   ```

9. **Report** to the user: ID, file, affected R-NNN items, and ask "Do you want to mark `decision-status: accepted`?" — if yes, edit frontmatter and commit a follow-up.

## Failure modes

- `docs/decisions/` doesn't exist → run `/ship-init` first
- Cannot reasonably infer Context — too little conversation history → ask user to paste context
````

- [ ] **Step 3: Verify**

```bash
ls claude-skills/ship-workflow/commands/ | wc -l
grep -c "id-gen.sh" claude-skills/ship-workflow/commands/ship-idea.md
grep -c "id-gen.sh" claude-skills/ship-workflow/commands/ship-decision.md
```

Expected: `3` (init + idea + decision), and each grep returns `≥1`.

- [ ] **Step 4: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-idea.md \
        claude-skills/ship-workflow/commands/ship-decision.md
git commit -m "feat(ship-workflow): commands/ship-idea + ship-decision"
```

---

## Task 11: Planning Commands (`ship-roadmap` + `ship-next`)

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-roadmap.md`
- Create: `claude-skills/ship-workflow/commands/ship-next.md`

- [ ] **Step 1: Write `commands/ship-roadmap.md`**

````markdown
---
name: ship-roadmap
description: Refresh the AIR-OS ROADMAP.md by reviewing ideas, decisions, learnings, and strategy via compound-engineering:ce-strategy. Reorders Now/Next/Later/Done sections per PRD rules (Now: 3-5 items; sorted by Impact × Dependency). Use when starting a sprint, after several ideas/decisions accumulate, or after a major learning shifts priorities.
---

# /ship-roadmap

You are running the Roadmap refresh ritual.

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```
   (Force here so the latest Obsidian edit lands before we read.)

2. **Resolve AIR-OS Roadmap path:**
   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ```

3. **Gather inputs.** Read:
   - `docs/product/STRATEGY.md`
   - `docs/product/ROADMAP.md` (current state)
   - `docs/ideas/IDEA-*.md` where `status != shelved`
   - `docs/decisions/D-*.md` where `decision-status: accepted`
   - `docs/learnings/R-*.md` modified within last 30 days

4. **Delegate to `compound-engineering:ce-strategy`** with all inputs concatenated. Ask it to:
   - Identify Roadmap items that should change status
   - Suggest new R-NNN items derived from accepted ideas/decisions
   - Re-rank by Impact × Dependency

5. **Apply PRD §6 rules:**
   - Cap "Now" at 3-5 items
   - Preserve Done section verbatim (don't lose history)
   - Move shipped items from "Now" → "Done" with `✅ <YYYY-MM-DD>` marker
   - Strip `adhoc-inserted=true` markers from any item now in Done
   - Sort "Next" and "Later" by Impact × Dependency

6. **Show diff.** Render a unified diff between current ROADMAP.md and proposed, ask the user to confirm.

7. **On confirm: write to AIR-OS, then sync back to repo:**
   ```bash
   # Edit $ROADMAP_PATH (atomic write — .tmp then mv)
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

8. **Log + commit (repo side):**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-roadmap | - | refresh | n |" >> docs/learnings/_log.md
   git add docs/product/ROADMAP.md docs/learnings/_log.md
   git commit -m "chore: refresh ROADMAP.md"
   ```

9. **Report:** Count of items moved between sections, top 3 "Now" priorities, next suggested action (`/ship-next`).

## Fallback

If `compound-engineering:ce-strategy` is unavailable, do the re-ranking yourself in-conversation and explain your reasoning before showing the diff.
````

- [ ] **Step 2: Write `commands/ship-next.md`**

````markdown
---
name: ship-next
description: Pick the next Roadmap item and enter superpowers:brainstorming to produce brainstorm + spec. With --adhoc <description>, allocates a new R-NNN immediately and inserts into ROADMAP "Now" with adhoc-inserted=true. Use to start the brainstorm → spec → build → compound loop.
---

# /ship-next

You are picking the next item and entering the brainstorm flow.

## Arguments

- `--adhoc <description>` — skip Roadmap selection; allocate next R-NNN and insert into "Now"

## Steps

### Branch A: Default (pick from Roadmap)

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Read** `docs/product/ROADMAP.md` "🔥 Now" section. Parse R-NNN items not marked `✅`.

3. **Rank** by:
   - Explicit `impact=high` markers first
   - Dependencies satisfied (no unresolved `dep:` references)
   - `adhoc-inserted=true` items deprioritized vs planned items (planned > emergency)

4. **Present top 1-2** to the user, get confirmation. Capture the chosen `R-NNN` and `<slug>`.

5. **Skip to "Common: Enter brainstorming" below.**

### Branch B: `--adhoc <description>`

1. **Sync product brain (forced)**:
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

2. **Allocate R-NNN:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
   ```

3. **Resolve ROADMAP path + insert:**
   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "<description>" --adhoc
   ```

4. **Re-sync** so the repo mirror picks up the insert:
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

5. **Continue below with $ID and slug derived from `<description>`.**

### Common: Enter brainstorming

6. **Invoke `superpowers:brainstorming`** with context: spec target = `docs/specs/${ID}-${slug}.md`, project = `<project_name>`.

7. **brainstorming will produce** a spec file. Confirm it landed at `docs/specs/${ID}-${slug}.md`.

8. **Also write the brainstorm note** at `docs/brainstorms/${ID}-${slug}.md` (Claude can do this inline or have brainstorming output the file). Use `templates/repo/BRAINSTORM.md` with substitutions.

9. **Log + commit:**
   ```bash
   adhoc_flag=$([ "$ADHOC" = "1" ] && echo y || echo n)
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | $ID | $description | $adhoc_flag |" >> docs/learnings/_log.md
   git add docs/brainstorms/${ID}-${slug}.md docs/specs/${ID}-${slug}.md docs/learnings/_log.md docs/product/ROADMAP.md
   git commit -m "brainstorm+spec: $ID $description"
   ```

10. **Report:** ID, slug, brainstorm path, spec path, next suggested command: `/ship-build`.

## Failure modes

- "Now" empty in default branch → ask user to either `/ship-roadmap` first or use `--adhoc`
- brainstorming returns no spec file → ERROR, halt before commit
````

- [ ] **Step 3: Verify**

```bash
ls claude-skills/ship-workflow/commands/ | wc -l
grep -c "roadmap-insert.sh" claude-skills/ship-workflow/commands/ship-next.md
grep -c "ce-strategy" claude-skills/ship-workflow/commands/ship-roadmap.md
```

Expected: `5`, `≥1`, `≥1`.

- [ ] **Step 4: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-roadmap.md \
        claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-workflow): commands/ship-roadmap + ship-next"
```

---

## Task 12: Execution Commands (`ship-build` + `ship-compound`)

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-build.md`
- Create: `claude-skills/ship-workflow/commands/ship-compound.md`

- [ ] **Step 1: Write `commands/ship-build.md`**

````markdown
---
name: ship-build
description: Take the most recent spec (or --from-spec <path>), generate a plan via superpowers:writing-plans, then offer the user three executors (subagent-driven / inline executing-plans / codex run-plan). Mid-build, /ship-idea --during-build and /ship-decision --during-build can be used to capture without leaving the flow.
---

# /ship-build

You are taking a spec to a shipped feature.

## Arguments

- `--from-spec <path>` — use this exact spec path; otherwise pick most recent `docs/specs/R-*.md`

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Stale-snapshot warning.** Check `docs/product/ROADMAP.md`'s git age:
   ```bash
   if [ $(($(date +%s) - $(git log -1 --format=%ct docs/product/ROADMAP.md))) -gt 604800 ]; then
     echo "WARN: docs/product/ROADMAP.md hasn't been refreshed in >7 days. Consider /ship-roadmap first."
   fi
   ```

3. **Resolve spec path.** If `--from-spec` provided, use it. Otherwise, find `docs/specs/R-*.md` modified most recently. Extract `$ID` and `$SLUG` from filename.

4. **Invoke `superpowers:writing-plans`** with the spec. It produces `docs/plans/${ID}-${slug}.md`.

5. **Offer executor choice.** Ask the user:
   ```
   Plan ready at docs/plans/${ID}-${slug}.md. Choose executor:
     1. Subagent-driven (recommended) — fresh subagent per task, review between
     2. Inline executing-plans — sequential in this session, batch with checkpoints
     3. Codex run-plan — hand off to codex exec, runs autonomously in background
   ```

6. **Invoke the chosen sub-skill:**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → `/run-plan docs/plans/${ID}-${slug}.md` (the gstack skill)

7. **During execution, allow escape hatches:**
   - If user runs `/ship-idea --during-build "X"` → capture as IDEA-NNN with `related-roadmap-item: ${ID}`
   - If user runs `/ship-decision --during-build "Y"` → capture as D-NNN with `affected-roadmap-items: [${ID}]`

8. **After executor finishes**, log + commit (only the plan file — code commits come from sub-skill):
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-build | $ID | exec=$executor_choice | n |" >> docs/learnings/_log.md
   git add docs/plans/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "plan: $ID $description"
   ```

9. **Report:** plan path, executor used, count of commits made by executor, next suggested command: `/ship-compound`.

## Failure modes

- No spec found → ask user to run `/ship-next` first
- writing-plans fails to produce a plan → halt before commit, surface error
- Sub-skill executor fails mid-run → log it in `## Execution log` section of the plan file, surface to user
````

- [ ] **Step 2: Write `commands/ship-compound.md`**

````markdown
---
name: ship-compound
description: Wrap up a shipped Roadmap item — generate learning via compound-engineering:ce-compound, promote reusable patterns to AIR-OS 40 Knowledge or 30 Engineering via ce-promote, and move the R-NNN from ROADMAP "Now" to "Done". Strips adhoc-inserted=true markers.
---

# /ship-compound

You are wrapping up a Roadmap item.

## Argument

(none — operates on the most recent plan in `docs/plans/R-*.md`)

## Steps

1. **Sync:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Identify the plan.** Find the most recent `docs/plans/R-*.md`. Extract `$ID` and `$SLUG`.

3. **Gather inputs:**
   - The plan: `docs/plans/${ID}-${slug}.md`
   - All decisions tagged `affected-roadmap-items: ... ${ID} ...`
   - All ideas tagged `related-roadmap-item: ${ID}`
   - Git log from plan's first commit timestamp to HEAD on this branch

4. **Delegate to `compound-engineering:ce-compound`** to draft the learning content:
   - What Shipped
   - What Changed From Plan
   - Bugs
   - Reusable Patterns
   - Technical Debt
   - Future Follow-ups

5. **Render** `templates/repo/LEARNING.md` with `{{date}}` / `{{id}}` / `{{project}}` and the ce-compound output. Write to `docs/learnings/${ID}-${slug}.md`.

6. **Delegate to `compound-engineering:ce-promote`** to look at the "Reusable Patterns" section. For each pattern, ask the user:
   - "Promote `<pattern title>` to AIR-OS `40 Knowledge/Concepts/<slug>.md` or `30 Engineering/<slug>.md`?"
   - On confirm, write the promoted note with AIR-OS frontmatter (`type: concept` or `type: engineering`, ai-first preamble, related-projects wikilink back to current project).

7. **Update ROADMAP.** Edit the AIR-OS ROADMAP.md:
   - Find the `${ID}` line under "🔥 Now"
   - Strip `adhoc-inserted=true` if present
   - Strip `status=in-progress`
   - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
   - Atomic write via `.tmp` + `mv`

8. **Re-sync:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

9. **Log + commit:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | shipped | n |" >> docs/learnings/_log.md
   git add docs/learnings/${ID}-${slug}.md docs/product/ROADMAP.md docs/learnings/_log.md
   git commit -m "compound: $ID — shipped + learning + ROADMAP update"
   ```

10. **Report:**
    - Learning path
    - Patterns promoted to AIR-OS (paths, if any)
    - ROADMAP item moved to Done
    - Next suggested command: `/ship-next`

## Failure modes

- No plan found → ask user to run `/ship-build` first
- `ce-compound` unavailable → fall back to user-driven structured prompt for each section
- ROADMAP doesn't contain `${ID}` → ERROR, ask user to inspect
````

- [ ] **Step 3: Verify all 7 commands**

```bash
ls claude-skills/ship-workflow/commands/*.md | wc -l
for f in claude-skills/ship-workflow/commands/ship-*.md; do
  echo "=== $f ==="
  head -3 "$f"
done
```

Expected: `7`. Each file starts with `---` frontmatter + name + description.

- [ ] **Step 4: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-build.md \
        claude-skills/ship-workflow/commands/ship-compound.md
git commit -m "feat(ship-workflow): commands/ship-build + ship-compound"
```

---

## Task 13: References (3 files)

**Files:**
- Create: `claude-skills/ship-workflow/references/flow-diagrams.md`
- Create: `claude-skills/ship-workflow/references/escape-hatches.md`
- Create: `claude-skills/ship-workflow/references/ce-skill-mapping.md`

- [ ] **Step 1: Write `references/flow-diagrams.md`**

````markdown
# Ship Workflow — Flow Diagrams

## Daily flow

```
                            ┌─────────────────┐
                            │ /ship-init      │ (once per repo)
                            └────────┬────────┘
                                     │
                                     ▼
        ┌─────────────────┐    ┌─────────────────┐
        │ /ship-idea      │───▶│ docs/ideas/     │
        └─────────────────┘    │ IDEA-NNN-*.md   │
                               └────────┬────────┘
                                        │ (some graduate)
                                        ▼
        ┌─────────────────┐    ┌─────────────────┐
        │ /ship-decision  │───▶│ docs/decisions/ │
        └─────────────────┘    │ D-NNN-*.md      │
                               └────────┬────────┘
                                        │
                                        ▼
                            ┌─────────────────┐
                            │ /ship-roadmap   │ (refresh ranking)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-next      │ (pick + brainstorm + spec)
                            └────────┬────────┘
                                     │ also accepts --adhoc
                                     ▼
                            ┌─────────────────┐
                            │ /ship-build     │ (plan + execute)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-compound  │ (learn + promote + close)
                            └────────┬────────┘
                                     │
                                     └─▶ back to /ship-next
```

## Dual-brain sync

```
Obsidian AIR-OS (source of truth)              Repo (mirror + execution)
─────────────────────────────────              ─────────────────────────
10 Projects/<repo>/                            <repo>/
  ├── VISION.md          ───── sync ─────▶     docs/product/VISION.md
  ├── STRATEGY.md        ───── sync ─────▶     docs/product/STRATEGY.md
  ├── ROADMAP.md         ───── sync ─────▶     docs/product/ROADMAP.md
  ├── QUARTERLY_GOALS.md ───── sync ─────▶     docs/product/QUARTERLY_GOALS.md
  └── (other AIR-OS notes — not synced)

                                               <repo>/docs/
                                                 ├── ideas/IDEA-NNN-*.md
                                                 ├── decisions/D-NNN-*.md
                                                 ├── brainstorms/R-NNN-*.md
                                                 ├── specs/R-NNN-*.md
                                                 ├── plans/R-NNN-*.md
                                                 └── learnings/R-NNN-*.md
```

Sync direction is **strictly one-way** (Obsidian → repo). To edit strategy, edit in Obsidian.
````

- [ ] **Step 2: Write `references/escape-hatches.md`**

````markdown
# Escape Hatches

## `--adhoc` for urgent work

```
/ship-next --adhoc "Fix langfuse token leak"
```

What happens:

1. id-gen.sh allocates next R-NNN (same namespace as planned items — no separate ADHOC)
2. roadmap-insert.sh appends a line to AIR-OS ROADMAP.md "🔥 Now":
   ```
   - [ ] **R-018** Fix langfuse token leak · adhoc-inserted=true · status=in-progress
   ```
3. sync.sh mirrors the updated ROADMAP back to repo
4. Continue with normal brainstorm + spec flow

When `/ship-compound` ships R-018:
- The line moves to "✅ Done" section
- The `adhoc-inserted=true` marker is stripped (no longer relevant)
- Dataview queries on `tags: roadmap` can filter on `adhoc-inserted` history if needed
  by reading the Done-section history (markers are NOT preserved post-ship)

## Mid-build capture

While `/ship-build` is running:

```
/ship-idea --during-build "Maybe rich menu can use templated variants"
/ship-decision --during-build "Switch to celery-task for retries"
```

Both produce normal IDEA-NNN / D-NNN files but with extra frontmatter:

```yaml
related-roadmap-item: R-018          # the current build's ID
created-during: build                # the phase
```

This lets `/ship-compound` later sweep up all captures from this build into the learning.

## Skipping init

`/ship-init` is idempotent. Re-running:
- Skips existing files
- Re-copies `.claude/commands/ship-*.md` (use `--upgrade` for an explicit refresh)
- Doesn't overwrite AIR-OS strategy files

## Forcing fresh sync

```bash
~/.claude/skills/ship-workflow/lib/sync.sh --force
```

Ignores the freshness window. Use after editing strategy in Obsidian without waiting 60 seconds.
````

- [ ] **Step 3: Write `references/ce-skill-mapping.md`**

````markdown
# Ship → Compound Engineering Skill Mapping

| Ship command | Primary delegation | Fallback when ce-* unavailable |
|---|---|---|
| `ship-init` | (none) | n/a |
| `ship-idea` | optional `compound-engineering:ce-ideate` (only on user request) | Skip ideation; just capture |
| `ship-decision` | optional `compound-engineering:ce-doc-review` | Write decision manually |
| `ship-roadmap` | `compound-engineering:ce-strategy` (preferred) or `ce-plan` | Re-rank in conversation, show reasoning |
| `ship-next` | `superpowers:brainstorming` | Required — no fallback |
| `ship-build` | `superpowers:writing-plans` + user-chosen executor | Required for plan generation |
| `ship-compound` | `compound-engineering:ce-compound` + `ce-promote` | Hand-write learning sections |

## Detection

Each `ship-*` command, before delegating, should probe whether the target ce-* skill is available:

```
# In Claude prompt logic:
1. Check that compound-engineering:ce-X is in the available skills list
2. If yes → delegate via Skill tool
3. If no → emit a warning ("ce-X not available, proceeding with manual flow")
   and execute the fallback path inline
```

## Interface contract

When delegating, ship-* passes:
- Project name (from airos-binding.sh)
- Relevant input files (already mirror-synced via sync.sh)
- The ship-* command's specific question (e.g. "rank these roadmap items by Impact × Dependency")

The ce-* skill returns its standard output; ship-* takes that output and applies the ship-side housekeeping (frontmatter, log line, commit message).

## Versioning

If a ce-* skill's interface changes (different argument names, different output schema), the ship-* wrapper either:

1. Adapts to the new interface inline, or
2. Pins to a known-good version in `~/.claude/ship-workflow.yml`:
   ```yaml
   ce_skill_versions:
     ce-compound: "1.2"
     ce-strategy: "0.8"
   ```

v1 ships with no version pinning — Claude is expected to adapt at call time.
````

- [ ] **Step 4: Verify**

```bash
ls claude-skills/ship-workflow/references/*.md | wc -l
```

Expected: `3`.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/references/
git commit -m "docs(ship-workflow): references (flow / escape-hatches / ce-mapping)"
```

---

## Task 14: Global Config Example + AIR-OS `_CLAUDE.md` Update

**Files:**
- Create: `claude-skills/ship-workflow/examples/ship-workflow.example.yml`
- Modify: `/Users/leric/Documents/SecondBrain/_CLAUDE.md`

- [ ] **Step 1: Write the example global config**

Write `claude-skills/ship-workflow/examples/ship-workflow.example.yml`:

```yaml
# Copy to ~/.claude/ship-workflow.yml and edit.

# Required
airos_vault: /Users/leric/Documents/SecondBrain

# Optional (defaults shown)
airos_projects_dir: "10 Projects"
default_roadmap_mode: soft           # soft | strict
default_id_pad: 3                    # IDEA-001 vs IDEA-1
auto_pull_freshness_window: 60       # seconds; sync.sh skip threshold
```

- [ ] **Step 2: Verify AIR-OS `_CLAUDE.md` exists**

```bash
ls /Users/leric/Documents/SecondBrain/_CLAUDE.md
```

Expected: file exists. If not, STOP — AIR-OS migration hasn't completed and ship-workflow has nothing to extend.

- [ ] **Step 3: Append note types to AIR-OS `_CLAUDE.md`**

Find the "Frontmatter Requirements" section in `_CLAUDE.md`. It currently lists 13 note types ending with `index`. Append the 7 new types added by Ship Workflow.

Specifically, after the existing line:
```
Note types: `research` | `concept` | `project` | `decision` | `task`
          | `journal` | `moc` | `prompt` | `mcp` | `synthesis`
          | `engineering` | `note` | `index`
```

Replace it with:
```
Note types: `research` | `concept` | `project` | `decision` | `task`
          | `journal` | `moc` | `prompt` | `mcp` | `synthesis`
          | `engineering` | `note` | `index`
          | `idea` | `brainstorm` | `learning` | `vision`
          | `strategy` | `roadmap` | `quarterly-goal`
```

Use the Edit tool with `old_string` matching the existing line and `new_string` matching the expanded line.

- [ ] **Step 4: Append a Ship Workflow section to `_CLAUDE.md`**

After the existing "Do Not Touch" section but before the trailing initialization comment, insert:

````markdown

---

## Ship Workflow (when project uses it)

If a `10 Projects/<name>/` folder has VISION.md / STRATEGY.md / ROADMAP.md /
QUARTERLY_GOALS.md, that project is using the **Ship Workflow** skill
(installed per-repo via `/ship-init`).

- ROADMAP.md is auto-edited by the skill on `/ship-next --adhoc` and `/ship-compound` — atomic writes only, but be aware Obsidian may need a moment to re-read
- Items with `adhoc-inserted=true` were added mid-emergency; the marker is stripped when they ship
- Decisions with `ship-context: true` came from `/ship-decision`; legacy ad-hoc ADRs without that flag came from earlier workflows
- Patterns promoted via `/ship-compound` land in `40 Knowledge/Concepts/` or `30 Engineering/` with backlinks to the originating `<repo-name>` project
````

Use the Edit tool to insert this block.

- [ ] **Step 5: Commit (AIR-OS git, not ai_system)**

```bash
cd /Users/leric/Documents/SecondBrain
git add _CLAUDE.md
git commit -m "docs(_CLAUDE): add Ship Workflow integration notes + 7 new note types

- idea / brainstorm / learning / vision / strategy / roadmap / quarterly-goal
- New section explains how ship-* skill modifies AIR-OS Projects
- Ref: ai_system spec docs/superpowers/specs/2026-06-14-ship-workflow-skill-design.md"
```

- [ ] **Step 6: Commit (ai_system)**

```bash
cd /Users/leric/Desktop/code/ai_system
git add claude-skills/ship-workflow/examples/
git commit -m "feat(ship-workflow): example global config + AIR-OS _CLAUDE.md note types"
```

---

## Task 15: End-to-End Smoke Test (claudecode-discord)

**Files:**
- Modify: `/Users/leric/Desktop/code/claudecode-discord/` (per-repo `/ship-init` artifacts)
- AIR-OS side: `/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/` (4 strategy files)

- [ ] **Step 1: Ensure global config exists**

```bash
ls ~/.claude/ship-workflow.yml 2>/dev/null || \
  cp /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow/examples/ship-workflow.example.yml \
     ~/.claude/ship-workflow.yml
cat ~/.claude/ship-workflow.yml
```

Expected: file exists with `airos_vault: /Users/leric/Documents/SecondBrain`.

- [ ] **Step 2: Install skill locally for testing**

If devsync hasn't run yet:
```bash
ln -sfn /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow \
        ~/.claude/skills/ship-workflow
ls -l ~/.claude/skills/ship-workflow
```

Expected: symlink pointing to the source.

- [ ] **Step 3: Run library tests one more time**

```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow
bats tests/
```

Expected: all bats tests pass (4 + 4 + 6 + 8 + 7 = 29 total).

- [ ] **Step 4: cd to test repo + run `/ship-init`**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
git status   # confirm clean working tree
```

Then in Claude Code, invoke the slash command:
```
/ship-init
```

When prompted:
- VISION one-liner: "Chat-driven remote agent — control Claude Code from any phone."
- First Roadmap R-001: "Persist Discord channel mappings across restarts"

- [ ] **Step 5: Verify repo side**

```bash
cd /Users/leric/Desktop/code/claudecode-discord
ls .claude/commands/   # expect 7 ship-*.md
ls docs/               # expect 7 subdirs
cat .claude/.gitignore # contains .ship-last-pull etc.
```

- [ ] **Step 6: Verify AIR-OS side**

```bash
ls "/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/"
# expect: VISION.md STRATEGY.md ROADMAP.md QUARTERLY_GOALS.md
grep "Chat-driven remote agent" \
  "/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/VISION.md"
grep "R-001" \
  "/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/ROADMAP.md"
```

Expected: both greps match.

- [ ] **Step 7: Verify sync ran**

```bash
ls /Users/leric/Desktop/code/claudecode-discord/docs/product/
# expect 4 strategy files mirrored
diff /Users/leric/Desktop/code/claudecode-discord/docs/product/ROADMAP.md \
     "/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/ROADMAP.md"
# expect: no diff
```

- [ ] **Step 8: Smoke-test `/ship-idea`**

In Claude Code:
```
/ship-idea "Multimodal voice replies in Discord channels"
```

Verify:
```bash
ls docs/ideas/   # expect IDEA-001-*.md
cat docs/ideas/IDEA-001-*.md | head -25
# expect: frontmatter with type:idea, id:IDEA-001, ai-first:true
grep "IDEA-001" docs/learnings/_log.md
# expect: log line present
git log --oneline -1
# expect: "idea: IDEA-001 ..."
```

- [ ] **Step 9: Smoke-test `/ship-next --adhoc`**

```
/ship-next --adhoc "Investigate Discord rate limiting"
```

Verify the AIR-OS ROADMAP.md got a new line with `adhoc-inserted=true`:

```bash
grep "adhoc-inserted=true" \
  "/Users/leric/Documents/SecondBrain/10 Projects/claudecode-discord/ROADMAP.md"
# expect: 1 match
ls docs/brainstorms/   # expect R-002-*.md (or whatever ID was allocated)
ls docs/specs/         # same
```

- [ ] **Step 10: Cleanup (optional)**

If smoke test passed and you want to keep the test artifacts, leave them. Otherwise, in claudecode-discord:
```bash
git reset --hard HEAD~N   # where N = number of ship-* commits
```

And in AIR-OS:
```bash
cd /Users/leric/Documents/SecondBrain
git reset --hard HEAD~1
rm -rf "10 Projects/claudecode-discord"
```

- [ ] **Step 11: Final commit in ai_system documenting smoke test**

```bash
cd /Users/leric/Desktop/code/ai_system
echo "" >> docs/superpowers/plans/2026-06-14-ship-workflow-skill-implementation.md
cat >> docs/superpowers/plans/2026-06-14-ship-workflow-skill-implementation.md <<'EOF'

## Execution log

- $(date +%Y-%m-%d): smoke test in claudecode-discord — 7 commands installed, 4 AIR-OS strategy files created, /ship-idea and /ship-next --adhoc both passed acceptance.
EOF
git add docs/superpowers/plans/2026-06-14-ship-workflow-skill-implementation.md
git commit -m "docs(plan): record ship-workflow smoke-test pass"
```

---

## Acceptance Criteria Recap (mapped from spec §8)

After all 15 tasks complete, the following spec ACs should all be green:

| Tier | AC | Task that satisfies it |
|---|---|---|
| 1 | AC-001 to AC-006 | Tasks 1, 2 (skill scaffold + dirs + lib files) |
| 2 | AC-007 to AC-012 | Task 9 (ship-init) + Task 15 (smoke test) |
| 3 | AC-013, AC-014 | Task 10 + Task 15 |
| 3 | AC-015 | Task 11 (ship-roadmap) |
| 3 | AC-016, AC-017 | Task 11 (ship-next) + Task 15 |
| 3 | AC-018 | Task 12 (ship-build) |
| 3 | AC-019 | Task 12 (ship-compound) |
| 4 | AC-020, AC-021 | Task 4 (sync.sh tests) + Task 15 |
| 4 | AC-022, AC-023 | Tasks 7, 8 (templates) + Task 15 |
| 4 | AC-024 | Task 14 (_CLAUDE.md update) |
| 4 | AC-025 | Task 12 (ship-build stale-snapshot warning) |
| 5 | AC-026 to AC-029 | Smoke-tested manually during Task 15 (transcript inspection) |

---

*End of plan.*

## Execution log

- 2026-06-14: All 15 tasks executed inline via superpowers:executing-plans.
- 2026-06-14: Smoke test on claudecode-discord caught 2 real bugs:
  1. YAML parser in airos-binding.sh / sync.sh / id-gen.sh didn't strip trailing
     `# comment` from config values — example config had inline comments,
     production tests used comment-free fixture.
  2. id-gen.sh scanned only on-disk R-* files, missing R-NNN markers in
     ROADMAP.md that were inserted via /ship-init seed or /ship-next --adhoc.
- 2026-06-14: Both bugs fixed with regression tests. Final bats count: 31/31.
- 2026-06-14: Smoke test artifacts committed:
  - claudecode-discord: docs/ideas, docs/learnings, docs/product (.claude/ gitignored locally).
  - AIR-OS 10 Projects/claudecode-discord/: 4 strategy files seeded.
- 2026-06-14: ship-workflow skill operational. ROADMAP carries R-001 (planned)
  and R-002 (adhoc-inserted=true) in claudecode-discord's Now section.
- Task 15 manual Obsidian verification (rendering, Dataview) still pending —
  Obsidian app behavior is owner's responsibility.
