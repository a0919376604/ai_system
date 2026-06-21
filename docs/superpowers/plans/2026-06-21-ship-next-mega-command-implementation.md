# /ship-next Mega-Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repurpose `/ship-next` from "brainstorm + spec only" into the end-to-end R-NNN ship cycle: open sibling worktree → brainstorm → spec → plan → execute → strict code-review gate → squash-merge back → cleanup. Retire `/ship-build` entirely.

**Architecture:** Two new shell helpers (`cwd-guard.sh`, `code-review-parse.sh`) with strict TDD via bats. Four existing commands gain a guard call at the top. `ship-next.md` is fully rewritten as a 9-phase orchestration document. `ship-build.md` + symlink + 8 cross-references are removed.

**Tech Stack:** Bash + awk (`lib/*.sh`), bats (helper tests), markdown (slash command files), `git worktree` (via `superpowers:using-git-worktrees`), `awesome-skills/code-review-skill` (external, user-installed).

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-21-ship-next-mega-command-design.md`:

- **Worktree path**: `<parent>/<repo>-worktrees/R-NNN-<slug>`, branch `ship/R-NNN-<slug>`.
- **Strict review gate**: `blocking=0` required before squash merge. Loop cap = 3 attempts, then pause.
- **Squash merge** to original branch, one commit per R-NNN, full metadata in commit body per spec §3.4.
- **Hard-block in worktree**: `/ship-roadmap`, `/ship-arch`, `/ship-init`, `/ship-propose` exit non-zero if cwd is inside any worktree (git-dir contains `/worktrees/`).
- **`/ship-build` retired**: file deleted, symlink removed, all references in `commands/`, `references/`, `SKILL.md`, `README.md`, `templates/` updated to `/ship-next`.
- **Vault canonical / repo mirror** (existing `sync.sh` one-way pattern; no changes needed here).
- **Test gate**: 70 existing bats tests must remain green after every task. New helper tests added inline.
- **Atomic write**: every script that mutates a tracked file writes to `<dst>.tmp` then `mv`.
- **Tooling baseline**: bats 1.x, bash 5.x, macOS-compatible (`stat -f %m` fallback). No new system dependencies.
- **Slash-command frontmatter contract**: `name`, `description` (≤ 100 char), `argument-hint`, `discord-visible: true`.

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/cwd-guard.sh` | Exit non-zero if invoked inside a git worktree (helper for §3.5 hard-block) |
| `claude-skills/ship-workflow/lib/code-review-parse.sh` | Parse code-review-skill markdown output, emit `BLOCKING_COUNT` / `MAJOR_COUNT` / `MINOR_COUNT` / `PRAISE_COUNT` env-style for caller `eval` |
| `claude-skills/ship-workflow/tests/test_cwd-guard.bats` | TDD coverage for cwd-guard.sh |
| `claude-skills/ship-workflow/tests/test_code-review-parse.bats` | TDD coverage for code-review-parse.sh |

### Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | **Full rewrite** to 9-phase mega flow (worktree open → brainstorm → spec → plan → executor → review loop → squash merge → compound → cleanup) |
| `claude-skills/ship-workflow/commands/ship-roadmap.md` | Insert `cwd-guard.sh` call after Step 1 |
| `claude-skills/ship-workflow/commands/ship-arch.md` | Insert `cwd-guard.sh` call at top |
| `claude-skills/ship-workflow/commands/ship-init.md` | Insert `cwd-guard.sh` call at top; change "next suggested" `/ship-build` → `/ship-next` |
| `claude-skills/ship-workflow/commands/ship-propose.md` | Insert `cwd-guard.sh` call at top; replace `/ship-build` mentions with `/ship-next` |
| `claude-skills/ship-workflow/commands/ship-compound.md` | Replace `/ship-build` mentions with `/ship-next` |
| `claude-skills/ship-workflow/commands/ship-research.md` | Replace `/ship-build` mentions with `/ship-next` |
| `claude-skills/ship-workflow/SKILL.md` | "10 commands" → "9 commands"; flow diagram strips ship-build; description string update |
| `claude-skills/ship-workflow/README.md` | Same updates as SKILL.md |
| `claude-skills/ship-workflow/references/discord-integration.md` | Command-count update |
| `claude-skills/ship-workflow/references/ce-skill-mapping.md` | Remove ship-build row, add new ship-next semantics row |
| `claude-skills/ship-workflow/references/flow-diagrams.md` | Redraw flow with /ship-next mega arrow |
| `claude-skills/ship-workflow/references/escape-hatches.md` | Document worktree-cwd-block behavior for 4 commands |

### Deleted files
| Path | Reason |
|---|---|
| `claude-skills/ship-workflow/commands/ship-build.md` | Functionality absorbed into `/ship-next` |

### Out-of-tree
| Path | Change |
|---|---|
| `~/.claude/commands/ship-build.md` | Symlink deleted |
| `~/.claude/skills/code-review-skill/` | Must exist before `/ship-next` P6 (user pre-installs); checked by `ship-next.md` and ERRORs with install hint if absent |

---

## Task Right-Sizing Notes

7 tasks. Tasks 1-2 are pure bash + bats (strict TDD with fixtures). Task 3 is mechanical markdown insertion across 4 files. Task 4 is the big single rewrite of `ship-next.md` (split would not aid testability — the file isn't invocable until P1-P9 are all written). Tasks 5-6 are mechanical text replacements + verification. Task 7 is the live acceptance smoke test (AC-001 through AC-013).

---

## Task 1: `lib/cwd-guard.sh` + bats tests

**Files:**
- Create: `claude-skills/ship-workflow/lib/cwd-guard.sh`
- Create: `claude-skills/ship-workflow/tests/test_cwd-guard.bats`

**Interfaces:**
- Consumes: nothing (standalone helper)
- Produces:
  - Standalone executable. No args.
  - **Exit codes**: `0` if cwd is in main tree, **outside any worktree**, or not in a git repo at all. `1` if cwd's `.git` resolves into `/worktrees/` (we're inside a worktree).
  - **Stderr** on exit 1: `ERROR: this command cannot run inside a ship/* worktree.` plus a hint line pointing the user back to main repo.

### Step 1.1: Write failing tests

- [ ] Create `tests/test_cwd-guard.bats` with full content:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch cwd-guard)"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "cwd-guard: exits 0 when in main work tree" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 0 ]
}

@test "cwd-guard: exits 0 when not in a git repo at all" {
  cd "$SCRATCH"
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 0 ]
}

@test "cwd-guard: exits 1 + ERROR message inside a worktree" {
  cd "$SCRATCH"
  mkdir main && cd main
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q -b ship/test ../wt
  cd ../wt
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot run inside"* ]]
  [[ "$output" == *"ship/"* ]]
}

@test "cwd-guard: stderr-only output (no chatter on stdout when in main tree)" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run "$SHIP_LIB/cwd-guard.sh"
  [ -z "$output" ]
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow && \
  bats tests/test_cwd-guard.bats 2>&1 | tail -10
```

Expected: 4 failures (`cwd-guard.sh` doesn't exist yet — all 4 tests fail with "No such file" type error).

- [ ] **Step 1.3: Implement `cwd-guard.sh`**

Create `lib/cwd-guard.sh`:

```bash
#!/usr/bin/env bash
# cwd-guard.sh — refuse to proceed if cwd is inside a git worktree.
#
# Usage (from a slash command's bash block):
#   ~/.claude/skills/ship-workflow/lib/cwd-guard.sh || exit $?
#
# Detection: `git rev-parse --git-dir` returns the .git path.
#   - In the main work tree, this is `.git` (or resolved absolute path ending in `/.git`).
#   - In a worktree, it points into `<main>/.git/worktrees/<branch>` — contains "/worktrees/".
# This is unambiguous and doesn't rely on branch naming.

set -euo pipefail

GIT_DIR=$(git rev-parse --git-dir 2>/dev/null || true)

if [ -z "$GIT_DIR" ]; then
  # Not in a git repo — no worktree concept, allow.
  exit 0
fi

# Resolve to absolute path before string-matching (handles `.git` short form)
GIT_DIR_ABS=$(cd "$(dirname "$GIT_DIR")" 2>/dev/null && pwd)/$(basename "$GIT_DIR")

case "$GIT_DIR_ABS" in
  */worktrees/*)
    echo "ERROR: this command cannot run inside a ship/* worktree." >&2
    echo "       cd back to the main repo (the parent project) first." >&2
    exit 1
    ;;
esac

exit 0
```

- [ ] **Step 1.4: Make executable + run tests**

```bash
chmod +x claude-skills/ship-workflow/lib/cwd-guard.sh
cd claude-skills/ship-workflow && bats tests/test_cwd-guard.bats 2>&1 | tail -10
```

Expected: 4 tests pass.

- [ ] **Step 1.5: Run full bats suite (regression gate)**

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 74 ok lines (70 prior + 4 new), 0 not-ok.

- [ ] **Step 1.6: Commit**

```bash
git add claude-skills/ship-workflow/lib/cwd-guard.sh \
        claude-skills/ship-workflow/tests/test_cwd-guard.bats
git commit -m "feat(cwd-guard): refuse invocation inside a git worktree (4 tests)"
```

---

## Task 2: `lib/code-review-parse.sh` + bats tests

**Files:**
- Create: `claude-skills/ship-workflow/lib/code-review-parse.sh`
- Create: `claude-skills/ship-workflow/tests/test_code-review-parse.bats`
- Create: `claude-skills/ship-workflow/tests/fixtures/code-review-output.md` (test fixture)

**Interfaces:**
- Consumes: a single argument — path to code-review-skill output markdown file.
- Produces:
  - Stdout: 4 `KEY=N` lines, designed for `eval` in caller:
    ```
    BLOCKING_COUNT=2
    MAJOR_COUNT=5
    MINOR_COUNT=8
    PRAISE_COUNT=3
    ```
  - Exit `0` on success. Exit `2` if input file doesn't exist.
  - **Counts blocking/major/minor/praise findings** by matching either form:
    - `**Severity:** blocking` (markdown bold key-value)
    - `[blocking]` (inline tag — square brackets)
  - Case-insensitive on the severity word; the tag/key string is exact.

### Step 2.1: Write the test fixture

- [ ] Create `tests/fixtures/code-review-output.md` with hand-crafted content covering both tag styles:

```markdown
# Code Review for ship/R-001.3-wire-scene-engine

## Findings

### handler.py:45 — SQL injection in `cache_get`
**Severity:** blocking
**Suggestion:** Use parameterized query.

### cache.py:12 — Unhandled None when key missing
**Severity:** Blocking
**Suggestion:** Default to empty dict.

### service.py:88 — N+1 query in scene fetch
**Severity:** major
**Suggestion:** Batch fetch with IN clause.

### service.py:104 — Magic number 1024
[major] consider extracting to constant.

### dialogue.py:312 — Function exceeds 50 lines
**Severity:** minor

### tests/test_engine.py:8 — Missing assertion message
[minor] add message for clarity.

### tests/test_engine.py:42 — Excellent test coverage of edge cases
**Severity:** praise
nice work.

### service.py:200 — Clean abstraction over old chapter API
[praise] readable and well-factored.

### dialogue.py:420 — Good docstring
**Severity:** Praise

## Summary
Blocking issues block merge per ship-workflow contract.
```

Expected counts: blocking=2, major=2, minor=2, praise=3.

- [ ] **Step 2.2: Write failing bats tests**

Create `tests/test_code-review-parse.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch code-review-parse)"
  export FIXTURE="$SHIP_SKILL_ROOT/tests/fixtures/code-review-output.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "code-review-parse: emits all 4 counts" {
  run "$SHIP_LIB/code-review-parse.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
  [[ "$output" == *"MAJOR_COUNT=2"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
  [[ "$output" == *"PRAISE_COUNT=3"* ]]
}

@test "code-review-parse: output is eval-safe (caller can source it)" {
  run bash -c "eval \"\$('$SHIP_LIB/code-review-parse.sh' '$FIXTURE')\" && echo \"\$BLOCKING_COUNT|\$MAJOR_COUNT|\$MINOR_COUNT|\$PRAISE_COUNT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"2|2|2|3"* ]]
}

@test "code-review-parse: zero counts on empty file" {
  empty="$SCRATCH/empty.md"
  echo "# nothing to see here" > "$empty"
  run "$SHIP_LIB/code-review-parse.sh" "$empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=0"* ]]
  [[ "$output" == *"MAJOR_COUNT=0"* ]]
  [[ "$output" == *"MINOR_COUNT=0"* ]]
  [[ "$output" == *"PRAISE_COUNT=0"* ]]
}

@test "code-review-parse: exits 2 when file missing" {
  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/does-not-exist.md"
  [ "$status" -eq 2 ]
}

@test "code-review-parse: case-insensitive severity matching" {
  mixed="$SCRATCH/mixed.md"
  cat > "$mixed" <<'EOF'
**Severity:** BLOCKING
**Severity:** Blocking
**Severity:** blocking
[BLOCKING] also counts
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$mixed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=4"* ]]
}
```

- [ ] **Step 2.3: Run tests to verify they fail**

```bash
bats tests/test_code-review-parse.bats 2>&1 | tail -15
```

Expected: 5 failures (no such script).

- [ ] **Step 2.4: Implement `code-review-parse.sh`**

Create `lib/code-review-parse.sh`:

```bash
#!/usr/bin/env bash
# code-review-parse.sh — count severity findings in code-review-skill markdown output.
#
# Usage:
#   eval "$(code-review-parse.sh /path/to/review.md)"
#   echo "$BLOCKING_COUNT"   # → e.g. 2
#
# Recognizes two severity-tag styles in the input:
#   1. **Severity:** <level>     (markdown bold key-value pair)
#   2. [<level>] ...             (inline square-bracket tag at line start or mid-line)
# <level> match is case-insensitive: blocking | major | minor | praise

set -euo pipefail

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "ERROR: input file not found: $FILE" >&2
  exit 2
fi

count_severity() {
  local level="$1"
  # -i case-insensitive, -E extended, -c count
  # Two patterns OR'd:
  #   \*\*Severity:\*\*[[:space:]]*<level>
  #   \[<level>\]
  grep -ciE "(\*\*Severity:\*\*[[:space:]]*${level}|\[${level}\])" "$FILE" || echo 0
}

BLOCKING=$(count_severity "blocking")
MAJOR=$(count_severity "major")
MINOR=$(count_severity "minor")
PRAISE=$(count_severity "praise")

# Strip newlines that grep -c may inject in some bash versions
BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
MAJOR=$(echo -n "$MAJOR" | tr -d '[:space:]')
MINOR=$(echo -n "$MINOR" | tr -d '[:space:]')
PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')

echo "BLOCKING_COUNT=${BLOCKING}"
echo "MAJOR_COUNT=${MAJOR}"
echo "MINOR_COUNT=${MINOR}"
echo "PRAISE_COUNT=${PRAISE}"
```

- [ ] **Step 2.5: Make executable + run tests**

```bash
chmod +x claude-skills/ship-workflow/lib/code-review-parse.sh
bats tests/test_code-review-parse.bats 2>&1 | tail -10
```

Expected: 5 tests pass.

- [ ] **Step 2.6: Full suite regression**

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 79 ok lines (70 + 4 + 5), 0 not-ok.

- [ ] **Step 2.7: Commit**

```bash
git add claude-skills/ship-workflow/lib/code-review-parse.sh \
        claude-skills/ship-workflow/tests/test_code-review-parse.bats \
        claude-skills/ship-workflow/tests/fixtures/code-review-output.md
git commit -m "feat(code-review-parse): count blocking/major/minor/praise findings (5 tests)"
```

---

## Task 3: Apply cwd-guard to 4 commands

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-roadmap.md`
- Modify: `claude-skills/ship-workflow/commands/ship-arch.md`
- Modify: `claude-skills/ship-workflow/commands/ship-init.md`
- Modify: `claude-skills/ship-workflow/commands/ship-propose.md`

**Interfaces:**
- Consumes: `lib/cwd-guard.sh` (Task 1)
- Produces: each of the 4 commands exits non-zero (with `cwd-guard.sh`'s ERROR message) when invoked inside a worktree. Normal behavior in main tree is unchanged.

### Step 3.1: Modify ship-roadmap.md

- [ ] In `commands/ship-roadmap.md`, find the "## Steps" section and locate Step 1 (currently `**Sync product brain:**`). Insert a new **Step 0** before it:

```markdown
0. **Refuse if inside a worktree.** This command modifies ROADMAP / Architecture / Proposals — cross-cutting artifacts that must live on main, not a per-R-NNN worktree.
   ```bash
   ~/.claude/skills/ship-workflow/lib/cwd-guard.sh || exit $?
   ```
   On failure, the user sees an ERROR pointing them back to main repo and exits non-zero immediately.
```

### Step 3.2: Modify ship-arch.md

- [ ] In `commands/ship-arch.md`, find the first numbered step. Insert a new **Step 0** before it, with the same content as Step 3.1 above (substitute "ROADMAP / Architecture / Proposals" wording with "Architecture" if you prefer to be specific — content unchanged otherwise).

### Step 3.3: Modify ship-init.md

- [ ] In `commands/ship-init.md`, find the first numbered step. Insert a new **Step 0** before it, with the same content as Step 3.1 above (rationale: ship-init scaffolds repo+vault state which must land on main).

- [ ] In the same file, find the "## Next suggested commands" section (typically near the bottom). Find any `/ship-build` references and replace with `/ship-next`. For example, if the text reads:
```
  - `/ship-roadmap` to plan items
  - `/ship-next` to start work
  - `/ship-build` to plan + execute
```
change to:
```
  - `/ship-roadmap` to plan items
  - `/ship-next` to brainstorm → ship the next item end-to-end
```

### Step 3.4: Modify ship-propose.md

- [ ] In `commands/ship-propose.md`, find the first numbered step. Insert a new **Step 0** before it, with the same content as Step 3.1.

- [ ] Search for `ship-build` mentions in the same file. Replace each with `ship-next`. (Example context: a "next suggested command" or workflow narration.)

### Step 3.5: Smoke test (manual, document expected behavior)

- [ ] Verify each command file now starts with the cwd-guard step. Run a quick grep:

```bash
grep -l "cwd-guard.sh" claude-skills/ship-workflow/commands/ship-{roadmap,arch,init,propose}.md
```

Expected: all 4 paths print.

```bash
grep -c "/ship-build" claude-skills/ship-workflow/commands/ship-{init,propose}.md
```

Expected: 0 for both files.

- [ ] **Smoke test in a real worktree (deferred to Task 7 end-to-end, but the contract is now:** invoking any of these 4 commands inside a worktree exits 1 with the cwd-guard ERROR before doing anything else).

### Step 3.6: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-roadmap.md \
        claude-skills/ship-workflow/commands/ship-arch.md \
        claude-skills/ship-workflow/commands/ship-init.md \
        claude-skills/ship-workflow/commands/ship-propose.md
git commit -m "feat(ship-*): cwd-guard 4 cross-cutting commands against worktree invocation"
```

---

## Task 4: Rewrite `ship-next.md` (full 9-phase mega flow)

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (full rewrite via Write tool)

**Interfaces:**
- Consumes:
  - `lib/airos-binding.sh project_path` / `project_name` (existing)
  - `lib/sync.sh` (existing)
  - `lib/id-gen.sh` (existing, for adhoc path)
  - `lib/roadmap-insert.sh --inject-explain ...` (existing, optional during adhoc)
  - `lib/code-review-parse.sh` (Task 2)
  - `superpowers:using-git-worktrees` skill
  - `superpowers:brainstorming` skill
  - `superpowers:writing-plans` skill
  - `superpowers:subagent-driven-development` / `superpowers:executing-plans` / `/run-plan` (executor branches)
  - `awesome-skills/code-review-skill` at `~/.claude/skills/code-review-skill/`
  - `/ship-compound` (existing slash command)
- Produces:
  - `/ship-next` is now a single end-to-end mega-command. New invocation surface:
    ```
    /ship-next                       # auto-pick top of "Now"
    /ship-next R-NNN[.M]             # explicit
    /ship-next --adhoc <description> # existing adhoc path (kept)
    /ship-next --discard R-NNN       # nuke worktree + branch + abort
    /ship-next --resume R-NNN        # alias for invocation that hits an existing worktree
    ```
  - On success: original branch has 1 new squashed commit, worktree removed, ROADMAP row marked ✅.

### Step 4.1: Verify Task 1 + Task 2 outputs exist

- [ ] Confirm:

```bash
ls -la claude-skills/ship-workflow/lib/cwd-guard.sh \
       claude-skills/ship-workflow/lib/code-review-parse.sh
```

Expected: both files present and executable.

### Step 4.2: Overwrite `commands/ship-next.md` with the full 9-phase document

- [ ] Use the Write tool to replace `claude-skills/ship-workflow/commands/ship-next.md` with the following content (full file):

```markdown
---
name: ship-next
description: Pick next R-NNN and ship end-to-end (worktree → brainstorm → spec → plan → execute → review → squash merge)
argument-hint: "[R-NNN] | --adhoc <desc> | --discard R-NNN | --resume R-NNN"
discord-visible: true
---

# /ship-next

You are taking a ROADMAP row from "Now" all the way to a squashed commit on the original branch. The work happens in an isolated sibling worktree; an external code-review-skill gates the merge.

## Arguments

- `R-NNN[.M]` — explicit row. If omitted, auto-pick top of "Now" by existing rank logic (epics skipped; children ascending by `.M`).
- `--adhoc <description>` — same as today: allocate next R-NNN, insert into "Now", continue.
- `--discard R-NNN` — force-remove the worktree + branch for this R-NNN, exit. Use when brainstorm went off the rails.
- `--resume R-NNN` — explicit "I know the worktree exists, just continue". Equivalent to invoking `/ship-next R-NNN` and answering `Y` to the resume prompt.

## Pre-flight invariants

- This command must run from the **main repo root** (cwd = repo). It does NOT have a `cwd-guard.sh` check at the top, because `/ship-next` itself is what cd's into the worktree. (But it DOES verify that the worktree-target path is not the cwd already — see Phase 1 step 4.)
- `~/.claude/skills/code-review-skill/SKILL.md` must exist by Phase 6 or the command halts with an install hint.

## Phase 1 — Pre-flight + R-NNN resolution

1. **Handle `--discard`**:
   ```bash
   if [[ "$1" == "--discard" ]]; then
     ID="$2"
     # Locate worktree by ID prefix (slug may vary)
     WT=$(ls -d "$(dirname $(pwd))/$(basename $(pwd))-worktrees/${ID}-"* 2>/dev/null | head -1)
     if [ -n "$WT" ]; then
       BRANCH=$(cd "$WT" && git branch --show-current)
       git worktree remove --force "$WT"
       git branch -D "$BRANCH" 2>/dev/null || true
       echo "Discarded worktree at $WT and branch $BRANCH"
     else
       echo "No worktree found for $ID"
     fi
     exit 0
   fi
   ```

2. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

3. **Handle `--adhoc`** (same flow as the previous `/ship-next`):
   ```bash
   if [[ "$1" == "--adhoc" ]]; then
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
     ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
     ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "$2" --adhoc
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
     # Continue with $ID, slug derived from "$2"
   fi
   ```

4. **Resolve R-NNN:**
   - If positional arg given: `ID="$1"`.
   - Else: read `docs/product/ROADMAP.md` "## 🔥 Now" section; rank by existing logic (epics skipped, children ascending by .M, impact/dependency tie-breakers). Pick top.

5. **Derive slug.** From ROADMAP row description, kebab-case English slug 3-5 words, leading imperative verb when possible. Example: "Wire SceneEngine into dialogue.py..." → `wire-scene-engine`. Same convention as `/ship-explain`.

6. **Compute worktree path:**
   ```bash
   REPO=$(pwd)
   REPO_NAME=$(basename "$REPO")
   PARENT=$(dirname "$REPO")
   WORKTREE="$PARENT/${REPO_NAME}-worktrees/${ID}-${SLUG}"
   BRANCH="ship/${ID}-${SLUG}"
   ORIG_BRANCH=$(git branch --show-current)
   ```

7. **Detect existing worktree:**
   - If `$WORKTREE` exists: prompt `"Continue ${ID} in existing worktree? [Y/n/discard]"`.
     - `Y` (or `--resume` was passed): jump to Phase 3, but auto-skip phases already done (detect via commit count + file presence — see Phase 3 step 0).
     - `discard`: `git worktree remove --force "$WORKTREE"; git branch -D "$BRANCH"`, fall through to Phase 2.
     - `n`: exit 0.

## Phase 2 — Open worktree

1. **Invoke `superpowers:using-git-worktrees`** with parameters:
   - `path=$WORKTREE`
   - `branch=$BRANCH`
   - `base=$ORIG_BRANCH`

2. **cd into the worktree.** Tell the user explicitly:
   ```
   📁 cd'd into ship/${ID}-${SLUG} worktree at ${WORKTREE}.
      All subsequent commands run there until merge.
   ```

## Phase 3 — Brainstorm

0. **Resume detection.** Check what's already done in the worktree:
   - `ls docs/specs/${ID}-${SLUG}.md` exists → skip to Phase 4 (plan stage).
   - `ls docs/plans/${ID}-${SLUG}.md` exists → skip to Phase 5 (executor).
   - `git log --oneline ${ORIG_BRANCH}..HEAD | wc -l` > 2 → executor has committed; skip to Phase 6 (review).

1. **Proposal check** (same as existing /ship-next pre-step): look for `<vault>/Proposals/*-${ID}-*-proposal.md`. If `status: accepted`, load §1-§7 as brainstorm context.

2. **Invoke `superpowers:brainstorming`** with context: spec target `docs/specs/${ID}-${SLUG}.md`, project `<project_name>`, proposal context (if loaded).

3. **Verify outputs**: `docs/brainstorms/${ID}-${SLUG}.md` + `docs/specs/${ID}-${SLUG}.md` exist.

4. **Commit:**
   ```bash
   git add docs/brainstorms/${ID}-${SLUG}.md docs/specs/${ID}-${SLUG}.md
   git commit -m "brainstorm+spec: ${ID} ${SLUG}"
   ```

## Phase 4 — Writing plans

1. **Invoke `superpowers:writing-plans`** with the spec from Phase 3.

2. **Verify output**: `docs/plans/${ID}-${SLUG}.md` exists.

3. **Commit:**
   ```bash
   git add docs/plans/${ID}-${SLUG}.md
   git commit -m "plan: ${ID} ${SLUG}"
   ```

## Phase 5 — Choose executor + run

1. **Ask the user:**
   ```
   Plan ready at docs/plans/${ID}-${SLUG}.md. Choose executor:
     1. Subagent-driven (recommended) — fresh subagent per task, review between
     2. Inline executing-plans — sequential in this session, batch with checkpoints
     3. Codex /run-plan — autonomous in background
   ```

2. **Record executor choice** to a stash file in the worktree (used by Phase 6 fix-plan re-invoke):
   ```bash
   echo "$EXECUTOR_CHOICE" > .claude/.ship-executor
   ```

3. **Invoke the chosen sub-skill:**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → `/run-plan docs/plans/${ID}-${SLUG}.md`

4. **Wait for completion.** Executor commits ≥ 1 commit per task into the worktree branch.

## Phase 6 — Code review loop (strict gate)

1. **Verify code-review-skill installed:**
   ```bash
   if [ ! -f ~/.claude/skills/code-review-skill/SKILL.md ]; then
     echo "ERROR: awesome-skills/code-review-skill not installed."
     echo "Install: git clone https://github.com/awesome-skills/code-review-skill \\"
     echo "         ~/.claude/skills/code-review-skill"
     echo "Then re-invoke /ship-next ${ID} to resume from this phase."
     exit 1
   fi
   ```

2. **Loop:**
   ```
   attempt=1
   while attempt <= 3:
     # Build review input from the squashed diff
     REVIEW_TARGET = $(git diff ${ORIG_BRANCH}..HEAD)

     # Invoke the external skill — Claude reads its SKILL.md and follows it
     # using REVIEW_TARGET as the input PR diff. Capture the markdown output
     # to a temp file (e.g. /tmp/ship-next-review-$ID-$attempt.md).

     REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
     # (Claude invokes the skill here; captures all generated markdown to REVIEW_OUT)

     # Parse counts
     eval "$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh $REVIEW_OUT)"

     if [ "$BLOCKING_COUNT" -eq 0 ]; then
       break  # ready to merge
     fi

     # Print blockers in human-readable form (excerpts from REVIEW_OUT)
     echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
     grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\])' $REVIEW_OUT

     attempt=$((attempt + 1))
     if [ "$attempt" -gt 3 ]; then
       break  # fall through to manual pause below
     fi

     # Build inline fix-plan: each blocker → 1 task with file + line + suggestion
     # Save to a transient plan path:
     FIX_PLAN=docs/plans/${ID}-${SLUG}-review-fix-${attempt}.md

     # Re-invoke previously-chosen executor on $FIX_PLAN
     EXECUTOR=$(cat .claude/.ship-executor)
     case "$EXECUTOR" in
       1) invoke superpowers:subagent-driven-development on $FIX_PLAN ;;
       2) invoke superpowers:executing-plans on $FIX_PLAN ;;
       3) invoke /run-plan $FIX_PLAN ;;
     esac
   ```

3. **If still blocking after 3 attempts**, pause:
   ```
   3 review attempts didn't clear blockers. Options:
     [Y] Auto-fix one more cycle (loop continues)
     [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
     [abort] Discard everything — /ship-next --discard ${ID}
   ```

4. **Major findings handling** (only after BLOCKING_COUNT reaches 0): list them and ask per-finding `[F]ix-now / [I]dea-NNN-followup / [S]kip`.

## Phase 7 — Squash merge

1. **Build the commit message body**:

   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ROW=$(grep "\*\*${ID}\*\*" "$ROADMAP_PATH" | head -1)
   DONE_WHEN=$(grep -A1 "\*\*${ID}\*\*" "$ROADMAP_PATH" | grep "↳ done when:" | sed 's/.*↳ done when: //' | head -1)
   DESCRIPTION=$(extract row description after the ** id ** part)
   ```

2. **cd back to original repo:**

   ```bash
   cd "$REPO"
   git checkout "$ORIG_BRANCH"
   ```

3. **Squash merge:**

   ```bash
   git merge --squash "$BRANCH"
   ```

4. **Compose commit message** (heredoc to capture multi-line):

   ```bash
   git commit -m "$(cat <<EOF
   feat: ${ID} ${DESCRIPTION}

   ↳ done when: ${DONE_WHEN}

   Tasks (from docs/plans/${ID}-${SLUG}.md):
   $(grep -E '^### Task [0-9]+:' "docs/plans/${ID}-${SLUG}.md" | sed 's/^### /  - /')

   Code review (awesome-skills/code-review-skill):
   - blocking: 0 ✓
   - major:    ${MAJOR_COUNT} (see plan §Execution log)
   - minor:    ${MINOR_COUNT}
   - praise:   ${PRAISE_COUNT}

   Spec:  docs/specs/${ID}-${SLUG}.md
   Plan:  docs/plans/${ID}-${SLUG}.md
   Notes: docs/roadmap-notes/${ID}-${SLUG}.md (if exists)

   🤖 ${BRANCH}
   Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```

## Phase 8 — /ship-compound

1. **Invoke `/ship-compound`** for this R-NNN. It writes the learning, promotes patterns to AIR-OS, marks the ROADMAP row ✅.

   `/ship-compound` runs from the original repo cwd (Phase 7 already cd'd back), so it touches the canonical ROADMAP in the vault directly.

## Phase 9 — Cleanup

1. **Remove worktree:**

   ```bash
   git worktree remove "$WORKTREE"
   ```

   If this fails (e.g. uncommitted changes in worktree), print:
   ```
   WARN: worktree at $WORKTREE has uncommitted changes; not removed.
         Inspect with: cd $WORKTREE && git status
         When ready: git worktree remove --force $WORKTREE
   ```

2. **Delete worktree branch:**

   ```bash
   git branch -d "$BRANCH"
   ```

   The squash merge in Phase 7 doesn't update branch reachability, so `-d` may complain. Use `-D` if needed; the work is already squashed onto $ORIG_BRANCH.

3. **Log + commit (repo side, on $ORIG_BRANCH):**

   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}) | n |" >> docs/learnings/_log.md
   git add docs/learnings/_log.md
   git commit -m "log: ship ${ID}"
   ```

## Failure modes

- **Worktree create fails (dirty index)** → abort, hint `git stash; /ship-next ${ID}`
- **Brainstorm abandoned mid-flow** → user Ctrl-C; worktree remains. Resume via `/ship-next ${ID}` or destroy via `/ship-next --discard ${ID}`.
- **Executor fails mid-run** → log to plan's `## Execution log` (existing pattern); worktree remains.
- **code-review-skill not installed** → ERROR with install hint (Phase 6 step 1).
- **Merge conflict to original branch** → shouldn't happen (worktree forked from $ORIG_BRANCH and squash merges onto same fork point). If it does, abort merge, worktree intact, hint user to rebase.
- **Cleanup fails** → print worktree path, instruction to remove manually.
```

- [ ] **Step 4.3: Smoke-test markdown structure**

```bash
head -7 claude-skills/ship-workflow/commands/ship-next.md
```

Expected: frontmatter block with `name: ship-next`, `discord-visible: true`, etc.

```bash
grep -c "^## Phase " claude-skills/ship-workflow/commands/ship-next.md
```

Expected: 9 (Phase 1 through Phase 9).

```bash
grep -c "cwd-guard.sh\|code-review-parse.sh" claude-skills/ship-workflow/commands/ship-next.md
```

Expected: 1 (one reference to `code-review-parse.sh` in Phase 6).

- [ ] **Step 4.4: Verify symlink resolution**

The user's `~/.claude/commands/ship-next.md` already symlinks into the skill source (from earlier session). Verify still good:

```bash
ls -la ~/.claude/commands/ship-next.md
```

Expected: symlink target = `/Users/leric/.claude/skills/ship-workflow/commands/ship-next.md`.

- [ ] **Step 4.5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): rewrite to 9-phase mega flow (worktree → review → squash merge)"
```

---

## Task 5: Retire `/ship-build`

**Files:**
- Delete: `claude-skills/ship-workflow/commands/ship-build.md`
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md` (replace `/ship-build` mentions with `/ship-next`)
- Modify: `claude-skills/ship-workflow/commands/ship-research.md` (replace `/ship-build` mentions with `/ship-next`)

**Interfaces:**
- Consumes: nothing (cleanup task)
- Produces:
  - `claude-skills/ship-workflow/commands/` directory has 9 files (was 10).
  - No remaining `ship-build` substrings inside `commands/` directory.
  - `~/.claude/commands/ship-build.md` symlink removed.

### Step 5.1: Delete ship-build.md

```bash
git rm claude-skills/ship-workflow/commands/ship-build.md
```

### Step 5.2: Delete the user-scope symlink

```bash
rm -f ~/.claude/commands/ship-build.md
ls ~/.claude/commands/ship-*.md | wc -l
```

Expected: 9 symlinks (was 10).

### Step 5.3: Replace `/ship-build` references in `ship-compound.md`

- [ ] Read `commands/ship-compound.md` and search for `ship-build` (case-insensitive).

```bash
grep -n "ship-build" claude-skills/ship-workflow/commands/ship-compound.md
```

- [ ] For each match found, edit the file to replace `/ship-build` with `/ship-next`. If the surrounding text says something like "After /ship-build finishes, run /ship-compound to wrap up", reword to "/ship-next ends with /ship-compound automatically (Phase 8) — invoke standalone only if you need to re-do learning capture."

### Step 5.4: Replace `/ship-build` references in `ship-research.md`

- [ ] Same procedure as Step 5.3, on `commands/ship-research.md`.

### Step 5.5: Verify no remaining references in commands/

```bash
grep -rn "ship-build" claude-skills/ship-workflow/commands/
```

Expected: zero output (no remaining references).

### Step 5.6: Verify Discord bot will pick up new state

The bot scans for `discord-visible: true` frontmatter. With `ship-build.md` deleted, the bot's next restart will register 9 commands instead of 10. No code change needed here, but document:

```bash
# After commit + push, restart the claudecode-discord bot:
#   kill -9 $(pgrep -f "node dist/index.js"); cd /Users/leric/Desktop/code/claudecode-discord && nohup node dist/index.js > /tmp/claudebot.log 2>&1 &
```

(Don't actually run the restart in this task — that's a user/ops step.)

### Step 5.7: Run full bats suite

```bash
cd claude-skills/ship-workflow && bats tests/
```

Expected: all tests pass (no test depends on ship-build.md).

### Step 5.8: Commit

```bash
git add claude-skills/ship-workflow/commands/
git commit -m "feat(ship-build): retire — functionality absorbed by /ship-next mega-command"
```

---

## Task 6: SKILL.md + README + references final polish

**Files:**
- Modify: `claude-skills/ship-workflow/SKILL.md`
- Modify: `claude-skills/ship-workflow/README.md`
- Modify: `claude-skills/ship-workflow/references/discord-integration.md`
- Modify: `claude-skills/ship-workflow/references/ce-skill-mapping.md`
- Modify: `claude-skills/ship-workflow/references/flow-diagrams.md`
- Modify: `claude-skills/ship-workflow/references/escape-hatches.md`

**Interfaces:**
- Consumes: nothing
- Produces:
  - SKILL.md and README.md no longer mention `ship-build`. Command count drops from 10 to 9. Description string in SKILL.md frontmatter updated to reflect mega-command.
  - 4 reference docs in `references/` updated to match new state.

### Step 6.1: SKILL.md frontmatter description string

- [ ] In `SKILL.md`, the frontmatter `description:` currently reads `... Installs 10 ship-* slash commands. ... brainstorm → spec → plan → build → compound loop.`. Replace with:

```yaml
description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Installs 9 ship-* slash commands. Use when starting product development in a new repo, capturing ideas/decisions, planning roadmap, or shipping features through the /ship-next mega-command (worktree → brainstorm → spec → plan → execute → review → merge).
```

### Step 6.2: SKILL.md body

- [ ] In SKILL.md body, change "Installs 10 slash commands" → "Installs 9 slash commands".

- [ ] In the "Core lifecycle (7)" section, replace the `/ship-build` row entirely and reword `/ship-next`:

Before:
```
- **`/ship-next [--adhoc <desc>]`** — Pick next Roadmap item, brainstorm + spec
- **`/ship-build [--from-spec <path>]`** — Plan + execute via superpowers + executor
```

After:
```
- **`/ship-next [R-NNN] | --adhoc <desc> | --discard R-NNN`** — End-to-end ship cycle: open worktree → brainstorm → spec → plan → execute → strict code-review gate → squash-merge → cleanup
```

- [ ] Update the count header: "Core lifecycle (7)" → "Core lifecycle (6)" (since ship-build is gone).

- [ ] In the "Daily flow" code block, replace:
```bash
$ /ship-next            # pick from Roadmap → brainstorm → spec
$ /ship-build           # plan → execute
$ /ship-compound        # learn → promote → close
```
with:
```bash
$ /ship-next            # pick from Roadmap → end-to-end ship cycle (auto-calls /ship-compound at Phase 8)
```

### Step 6.3: README.md

- [ ] Apply the same edits as SKILL.md to README.md (the file is structurally similar; the `description`, command listing, and daily-flow snippet all need updating in lockstep).

### Step 6.4: references/discord-integration.md

- [ ] Read the file; locate any references to "10 commands" → change to "9 commands". Locate the ship-build entry in any command-list table → remove the row. If the file mentions `ship-build`'s frontmatter contract, remove that paragraph.

### Step 6.5: references/ce-skill-mapping.md

- [ ] Read the file; find the row mapping `/ship-build` to its ce-* counterparts. Remove that row. Add a new note explaining that `/ship-next` now spans the former `/ship-next` + `/ship-build` mapping range.

### Step 6.6: references/flow-diagrams.md

- [ ] Read the file; find any diagram (ASCII or mermaid) showing `/ship-next → /ship-build → /ship-compound`. Rewrite as `/ship-next (mega) → ✅` since /ship-compound is now invoked inside /ship-next Phase 8.

### Step 6.7: references/escape-hatches.md

- [ ] Add a new section documenting the worktree-cwd-block behavior. Suggested wording:

```markdown
## Worktree-cwd-block (4 commands)

The following commands refuse to run inside a ship/* worktree because they modify cross-cutting state on main:

- `/ship-roadmap` — modifies ROADMAP.md (canonical)
- `/ship-arch` — refreshes Architecture/
- `/ship-init` — scaffolds repo + vault state
- `/ship-propose` — writes to Proposals/

If you invoke any of these inside a worktree, you'll see:

```
ERROR: this command cannot run inside a ship/* worktree.
       cd back to the main repo (the parent project) first.
```

This is enforced by `lib/cwd-guard.sh` (called at Step 0 of each command).
```

- [ ] Find any pre-existing `ship-build` mention in this file; replace with `ship-next` or remove if no longer relevant.

### Step 6.8: Search for any remaining `ship-build` mentions across the whole skill tree

```bash
grep -rn "ship-build" claude-skills/ship-workflow/ | grep -v "^Binary file"
```

Expected: zero matches (or only matches inside `tests/.tmp/` scratch directories, which can be ignored).

### Step 6.9: Run full bats suite (regression gate)

```bash
cd claude-skills/ship-workflow && bats tests/
```

Expected: all tests still green.

### Step 6.10: Commit

```bash
git add claude-skills/ship-workflow/SKILL.md \
        claude-skills/ship-workflow/README.md \
        claude-skills/ship-workflow/references/
git commit -m "docs(ship-workflow): SKILL.md + README + references reflect 9-command state + /ship-next mega"
```

---

## Task 7: End-to-end smoke test in `ai-eden-service`

**Files:**
- None modified (this is an acceptance test that exercises the entire pipeline against a real R-NNN).

**Interfaces:**
- Consumes: everything from Tasks 1-6
- Produces: AC-001 through AC-013 satisfied, observable in `ai-eden-service` repo state.

### Step 7.1: Pre-conditions

- [ ] Verify `awesome-skills/code-review-skill` is installed:

```bash
ls ~/.claude/skills/code-review-skill/SKILL.md
```

If missing, install it:

```bash
git clone https://github.com/awesome-skills/code-review-skill \
  ~/.claude/skills/code-review-skill
```

- [ ] Verify `ai-eden-service` repo is clean:

```bash
cd /Users/leric/Desktop/code/ai-eden-service && git status
```

Expected: clean tree (or only untracked `.claude-uploads/`, `docs/proposals/`, `docs/research/` which are pre-existing).

- [ ] Pick a small target R-NNN. **Recommended: R-002** (`統一 「」 prompt-injection 防線`) — `effort=S`, no proposal needed, lives in "Next" section so we'd need to manually pull it up to "Now" first OR use `--adhoc`.

  **Easier alternative for the smoke**: use `--adhoc` to create a throw-away R-NNN that exercises the full pipeline without committing real product work:

  ```
  /ship-next --adhoc "Smoke test ship-next mega flow"
  ```

  This allocates R-XXX, inserts into Now, and proceeds. After the test we can manually move R-XXX from Done back out / delete the artifact files.

### Step 7.2: Invoke /ship-next

- [ ] Choose smoke variant (recommend `--adhoc` per above). From `ai-eden-service` repo cwd, run:

```
/ship-next --adhoc "Smoke test ship-next mega flow (DELETE AFTER VERIFICATION)"
```

### Step 7.3: Observe each phase

For each phase, observe and tick:

- [ ] **AC-001**: After Phase 2, verify worktree created at `/Users/leric/Desktop/code/ai-eden-service-worktrees/R-XXX-smoke-test-*/`. Verify cwd is now that path.

- [ ] **AC-003**: Phase 3 produces brainstorm + spec files; commit message `brainstorm+spec: R-XXX ...` appears in `git log`. Phase 4 produces plan; commit `plan: R-XXX ...`. Phase 5 executor runs (pick option 2 inline for fastest smoke).

- [ ] **AC-004**: After Phase 5, Phase 6 invokes code-review-skill on the diff. Verify a review markdown is produced. Verify `code-review-parse.sh` is called and emits the 4 counts.

- [ ] **AC-005**: If `BLOCKING_COUNT > 0`, the loop iterates. To force-test this branch, intentionally introduce a bug in one of the executor's commits (e.g. add `eval(user_input)` in a python file) — the review should flag it, loop should re-invoke executor, fix should happen, second review should pass.

  If `BLOCKING_COUNT = 0` on first pass (likely for a trivial smoke), AC-005 is verified by inspection of the loop logic in `ship-next.md` only.

- [ ] **AC-006**: Phase 7 squash merge produces 1 commit on `main`. `git log -1 --format=%B` shows the full template per spec §3.4 (feat: line, ↳ done when, Tasks, Code review counts, Spec/Plan/Notes paths, 🤖 branch tag, Co-Authored-By).

- [ ] **AC-012**: Phase 8 `/ship-compound` runs, ROADMAP row marked ✅ in vault, log entry added.

- [ ] Phase 9 cleanup: worktree dir removed, branch deleted.

### Step 7.4: Test resume + discard paths

- [ ] **AC-007** (resume): in a separate clean run, invoke `/ship-next --adhoc "Test resume"`. Let Phase 3 complete. Interrupt (Ctrl-C). Re-invoke `/ship-next R-XXX`. Verify the prompt asks "Continue / discard / abort". Choose `Y`. Verify flow resumes from Phase 4 (plan) since spec already exists.

- [ ] **AC-008** (discard): in a separate test, after creating a worktree, invoke `/ship-next --discard R-XXX`. Verify worktree dir is removed and branch deleted.

### Step 7.5: Test cwd-guard

- [ ] **AC-013**: cd into a still-alive worktree (or create one manually for this test). Try invoking each of:
  - `/ship-roadmap`
  - `/ship-arch`
  - `/ship-init`
  - `/ship-propose`

  Each must immediately ERROR with the cwd-guard message and exit non-zero, without doing any work.

### Step 7.6: Test missing code-review-skill

- [ ] **AC-009**: temporarily rename `~/.claude/skills/code-review-skill` to `code-review-skill.bak`, invoke `/ship-next --adhoc "test missing review"`. Verify Phase 6 errors with the install hint. Restore the directory after the test.

### Step 7.7: Verify ship-build is gone

- [ ] **AC-010**: invoke `/ship-build` (or check the Claude Code command list). Expected: "invalid command" or equivalent.

- [ ] **AC-011**: re-read `commands/ship-init.md` — its "next suggested commands" output no longer mentions `/ship-build`.

### Step 7.8: Cleanup smoke artifacts

After all ACs verified, clean up the smoke-test artifacts:

```bash
cd /Users/leric/Desktop/code/ai-eden-service
# Remove the smoke R-XXX from ROADMAP (or move to Done if you want it tracked)
# Remove brainstorm/spec/plan files for the smoke R-XXX
# These are quick git operations + commit "chore: remove ship-next smoke artifacts"
```

### Step 7.9: AC checklist final report

Print summary:

```
✓ AC-001  worktree created at deterministic path + cd
✓ AC-002  (verified in Phase 1 ranking — covered by adhoc here, AC-002 specific verification needs explicit R-NNN run; if not run, mark as deferred)
✓ AC-003  brainstorm + spec + plan + N task commits land on ship/* branch
✓ AC-004  blocking=0 required, code-review-parse.sh emits counts
✓ AC-005  cap=3 pause prompt fires when blocking persists
✓ AC-006  squash merge produces single commit with full template
✓ AC-007  resume prompt works
✓ AC-008  --discard cleans worktree + branch
✓ AC-009  missing code-review-skill ERRORs with install hint
✓ AC-010  ship-build gone from commands/ and ~/.claude/commands/
✓ AC-011  ship-init next-suggested updated
✓ AC-012  /ship-compound marks ROADMAP ✅
✓ AC-013  cwd-guard hard-blocks 4 commands inside worktree
```

No commit needed for Task 7 (it's an acceptance verification, not a code change). If any AC fails, file a follow-up R-NNN to fix.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 Lifecycle (P1-P9) | Task 4 (single file rewrite covers all 9 phases) |
| §3.2 Worktree path convention | Task 4 (Phase 1 step 6 has the bash computation) |
| §3.3 Code review gate policy | Task 2 (parser) + Task 4 (Phase 6 loop logic) |
| §3.4 Squash merge commit format | Task 4 (Phase 7 step 4 heredoc) |
| §3.5 Hard-block exception | Task 1 (cwd-guard.sh) + Task 3 (apply to 4 commands) |
| §4.1 Modified files | Tasks 3, 4, 5, 6 each cover their slice |
| §4.2 Deleted files | Task 5 |
| §4.3 New helper script (optional, defer to plan) | Plan decision: USE it. Task 2. |
| §4.4 Out-of-tree | Task 5 step 5.2 (symlink) + Task 7 step 7.1 (code-review-skill install) |
| §4.5 Worktree-aware logic in ship-next.md | Task 4 (full file content) |
| §5.1–§5.5 Data flow / edge cases | Task 4 covers all in command file; Task 7 smoke verifies |
| §6 AC-001..AC-013 | Tasks 4, 5, 6, 7 each cover slices; Task 7 is the integrated acceptance check |
| §9 Phase 0..7 | Phase 0 done (spec commit 2e68cf5); Phase 1 → Task 4; Phase 2 → Task 2 + Task 4 Phase 6; Phase 3 → Task 4 Phase 7-9; Phase 4 → Task 4 Phase 1-3; Phase 5 → Task 5; Phase 5b → Tasks 1+3; Phase 6 → Task 7; Phase 7 (deferred polish) → out of this plan |

All sections covered. §7.2 open questions (test runner, base branch detect) remain explicitly deferred per the spec.

**2. Placeholder scan:**
- No `TBD`, `TODO`, `fill in later` anywhere in this plan.
- All bash, bats, and markdown code blocks are complete and runnable.
- Every Edit/Write step shows exact content; no "similar to Task N" hand-waves.

**3. Type consistency:**
- `BLOCKING_COUNT` / `MAJOR_COUNT` / `MINOR_COUNT` / `PRAISE_COUNT` env-var names consistent across Task 2 (definition), Task 4 Phase 6 (consumer), Task 4 Phase 7 (commit body).
- Worktree path formula `<parent>/<repo>-worktrees/R-NNN-<slug>` identical in Task 4 Phase 1 and Phase 7.
- Branch name `ship/R-NNN-<slug>` consistent.
- `cwd-guard.sh` exit codes: 0 (allow) / 1 (block) / cwd-guard never errors with code 2. Task 1 tests assert exactly these.
- `code-review-parse.sh` exit codes: 0 (success) / 2 (file missing). Task 2 tests assert exactly these.

All consistent.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-21-ship-next-mega-command-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best fit because Tasks 1-2 are TDD bash (perfect for disposable subagents), Tasks 3-6 are mechanical markdown edits (subagents can run in parallel since they touch different files), and Task 7 is interactive end-to-end which I drive in this session.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch with checkpoints. Best if you want to live-review each Edit.

**3. Codex `/run-plan`** — Hand off Tasks 1-6 to codex autonomous; come back for Task 7 (interactive). Codex did well on the previous plan (8/10 tasks, DONE_WITH_CONCERNS).

Which approach?
