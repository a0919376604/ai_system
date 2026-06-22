# /ship-next --auto:yes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--auto:yes` (alias `--auto`) flag to `/ship-next` that runs the full 9-phase mega flow without any user interaction — for fire-and-forget night/away use.

**Architecture:** One new TDD bash helper (`auto-decision-log.sh`) writes append-only audit log. Existing `ship-next.md` (9-phase, ~310 lines) gains arg-parsing for the flag, a pre-flight done-when gate, conditional auto branches per phase, P6 cap=3 abort + Discord push, major-finding → IDEA-NNN auto-forward, success/abort notifications. `ship-idea.md` extends to support `--during-build / --severity / --source` flags. `.claude/.gitignore` gains `.ship-auto-decisions.md` rule. `/run-plan` skill gets a prompt-template constraint.

**Tech Stack:** Bash + awk (lib helpers), bats (helper tests), markdown (slash command files), existing `code-review-parse.sh` + `cwd-guard.sh` (Tasks 1-2 of parent plan, already shipped).

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-22-ship-next-auto-yes-design.md`:

- **`--auto:yes` is the main name; `--auto` is the alias.** Semantically identical. No `--auto=no`.
- **Pre-flight gate:** missing `↳ done when:` annotation → ERROR exit 2; missing explainer / proposal → WARN only.
- **Strict review gate unchanged:** `blocking=0` required for merge in auto mode too. Auto = "auto-fix until blocking=0", not "ship anyway."
- **Cap=3 failure:** abort + worktree retained + branch retained + Discord push + exit 1. **Never** silently ships blockers.
- **Major findings in auto:** never silently skip; each becomes an `IDEA-NNN` via `/ship-idea --during-build`.
- **Decision log:** `docs/.ship-auto-decisions.md` (in worktree), append-only, gitignored.
- **`--auto:yes` + `--discard` mutually exclusive** → ERROR.
- **Test gate:** all current 83 bats tests must remain green after every task.
- **Slash-command frontmatter contract**: `name`, `description` (≤ 100 char), `argument-hint`, `discord-visible: true`.
- **Atomic write**: scripts that mutate tracked files use `<dst>.tmp` then `mv`.
- **Tooling baseline**: bats 1.x, bash 5.x, macOS-compatible. No new system dependencies.

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/auto-decision-log.sh` | Append timestamped audit line: `auto-decision-log.sh <worktree> <phase> <decision> [detail]` |
| `claude-skills/ship-workflow/tests/test_auto-decision-log.bats` | TDD coverage for above |

### Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | Frontmatter `argument-hint` gains `\| --auto:yes`; arg parsing detects `--auto:yes` / `--auto`; pre-flight gate; per-phase auto branches; P6 cap=3 abort + IDEA-NNN forward; notification integration |
| `claude-skills/ship-workflow/commands/ship-idea.md` | Add `--during-build`, `--severity <level>`, `--source <hint>`, `--related-roadmap-item <R-NNN>` flags to argument-hint + steps |
| `claude-skills/ship-workflow/commands/ship-init.md` | `.claude/.gitignore` line list gains `.ship-auto-decisions.md` |

### Out-of-tree (documented; user applies manually)
| Path | Change |
|---|---|
| `~/.claude/skills/run-plan/SKILL.md` | Prompt template (Step 2) gains: "If you invoke `/ship-next` from a plan task, always include `--auto:yes`" |

### Unchanged
- `lib/cwd-guard.sh`, `lib/code-review-parse.sh` — Tasks 1-2 of parent plan, no changes needed for auto mode
- All bats fixtures + tests for prior helpers

---

## Task Right-Sizing Notes

10 tasks. Task 1 is pure bash + bats (strict TDD). Task 2 extends ship-idea.md (markdown + manual smoke). Tasks 3-7 are slices of `ship-next.md` (markdown — split for review granularity since the file becomes ~450 lines after additions). Task 8 is notification integration. Task 9 is out-of-tree documentation. Task 10 is the live acceptance smoke test (AC-001 through AC-015).

---

## Task 1: `lib/auto-decision-log.sh` + bats tests

**Files:**
- Create: `claude-skills/ship-workflow/lib/auto-decision-log.sh`
- Create: `claude-skills/ship-workflow/tests/test_auto-decision-log.bats`

**Interfaces:**
- Consumes: nothing (standalone)
- Produces:
  - Executable taking 3 required + 1 optional arg:
    `auto-decision-log.sh <worktree_dir> <phase> <decision> [detail]`
  - Side effect: append to `<worktree_dir>/docs/.ship-auto-decisions.md` one timestamped line:
    `<ISO-8601 UTC> <phase> <decision>[ — <detail>]`
  - Exit `0` on success; `2` if worktree_dir missing or doesn't exist; `0` (creating file) if log file doesn't yet exist.
  - Auto-creates parent `docs/` dir if absent.

### Step 1.1: Write failing tests

- [ ] Create `tests/test_auto-decision-log.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch auto-decision-log)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT/docs"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "auto-decision-log: appends timestamped line to docs/.ship-auto-decisions.md" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P3" "auto-picked: option 1"
  [ "$status" -eq 0 ]
  [ -f "$WT/docs/.ship-auto-decisions.md" ]
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z P3 auto-picked: option 1' "$WT/docs/.ship-auto-decisions.md"
}

@test "auto-decision-log: optional detail appended with em-dash" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P6" "review attempt 1" "blocking=2 (handler.py:45, cache.py:12)"
  [ "$status" -eq 0 ]
  grep -qF "P6 review attempt 1 — blocking=2 (handler.py:45, cache.py:12)" "$WT/docs/.ship-auto-decisions.md"
}

@test "auto-decision-log: multiple calls append in order" {
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P3" "first" > /dev/null
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P4" "second" > /dev/null
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P5" "third" > /dev/null
  lines=$(wc -l < "$WT/docs/.ship-auto-decisions.md" | tr -d ' ')
  [ "$lines" -eq 3 ]
  # Verify in order
  first_phase=$(head -1 "$WT/docs/.ship-auto-decisions.md" | awk '{print $2}')
  last_phase=$(tail -1 "$WT/docs/.ship-auto-decisions.md" | awk '{print $2}')
  [ "$first_phase" = "P3" ]
  [ "$last_phase" = "P5" ]
}

@test "auto-decision-log: creates docs/ if missing" {
  rm -rf "$WT/docs"
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P1" "pre-flight pass"
  [ "$status" -eq 0 ]
  [ -f "$WT/docs/.ship-auto-decisions.md" ]
}

@test "auto-decision-log: exits 2 when worktree dir missing" {
  run "$SHIP_LIB/auto-decision-log.sh" "$SCRATCH/nonexistent" "P1" "test"
  [ "$status" -eq 2 ]
}

@test "auto-decision-log: requires 3 args minimum" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P1"
  [ "$status" -ne 0 ]
}
```

### Step 1.2: Run tests to verify they fail

```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow && \
  bats tests/test_auto-decision-log.bats 2>&1 | tail -15
```

Expected: 6 failures (script doesn't exist).

### Step 1.3: Implement `auto-decision-log.sh`

Create `lib/auto-decision-log.sh`:

```bash
#!/usr/bin/env bash
# auto-decision-log.sh — append a single audit line to a worktree's auto-decision log.
#
# Usage:
#   auto-decision-log.sh <worktree_dir> <phase> <decision> [detail]
#
# Side effect: append `<ISO-8601 UTC> <phase> <decision>[ — <detail>]` to
# <worktree_dir>/docs/.ship-auto-decisions.md (creates docs/ if absent).
#
# Exit codes:
#   0  on success (or if log file is created fresh)
#   2  if worktree_dir doesn't exist
#   non-zero  if too few args

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <worktree_dir> <phase> <decision> [detail]" >&2
  exit 1
fi

WORKTREE="$1"
PHASE="$2"
DECISION="$3"
DETAIL="${4:-}"

if [ ! -d "$WORKTREE" ]; then
  echo "ERROR: worktree dir not found: $WORKTREE" >&2
  exit 2
fi

mkdir -p "$WORKTREE/docs"

LOG="$WORKTREE/docs/.ship-auto-decisions.md"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ -n "$DETAIL" ]; then
  echo "${TS} ${PHASE} ${DECISION} — ${DETAIL}" >> "$LOG"
else
  echo "${TS} ${PHASE} ${DECISION}" >> "$LOG"
fi
```

### Step 1.4: Make executable + run tests

```bash
chmod +x claude-skills/ship-workflow/lib/auto-decision-log.sh
bats tests/test_auto-decision-log.bats 2>&1 | tail -10
```

Expected: 6 tests pass.

### Step 1.5: Run full bats suite (regression)

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 89 ok lines (83 + 6 new), 0 not-ok.

### Step 1.6: Commit

```bash
git add claude-skills/ship-workflow/lib/auto-decision-log.sh \
        claude-skills/ship-workflow/tests/test_auto-decision-log.bats
git commit -m "feat(auto-decision-log): append-only audit helper for /ship-next --auto:yes (6 tests)"
```

---

## Task 2: Extend `ship-idea.md` with `--during-build` / `--severity` / `--source` / `--related-roadmap-item` flags

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-idea.md`

**Interfaces:**
- Consumes: existing `lib/id-gen.sh idea`, `lib/sync.sh`, `lib/airos-binding.sh`
- Produces:
  - New flags on `/ship-idea`:
    - `--during-build` — non-interactive mode (no questions; just take everything from args + write IDEA-NNN)
    - `--severity <level>` — `major | minor | nit` (stored in IDEA frontmatter `severity:`)
    - `--source <hint>` — short context like `code-review-skill auto-run` (stored in `source:`)
    - `--related-roadmap-item <R-NNN>` — cross-link to parent R-NNN (stored in `related-roadmap-item:`)
  - Invocation example:
    ```
    /ship-idea --during-build \
      "P6 major: N+1 query in scene fetch" \
      --severity major \
      --source "code-review-skill auto-run during R-001.3" \
      --related-roadmap-item R-001.3
    ```
  - Behavior: write IDEA-NNN-<slug>.md with the 3 extra frontmatter keys; skip interactive fill (step 6 of existing flow); auto-commit.

### Step 2.1: Update frontmatter `argument-hint`

- [ ] In `commands/ship-idea.md`, replace the frontmatter `argument-hint` line:

Before:
```yaml
argument-hint: <description>
```

After:
```yaml
argument-hint: "<description> [--during-build --severity <level> --source <hint> --related-roadmap-item <R-NNN>]"
```

(stays ≤ 100 char per Global Constraints check — verify with `awk -F: '/^argument-hint:/ {sub(/^[^"]*"/, "", $0); sub(/"[^"]*$/, "", $0); print length($0)}' commands/ship-idea.md` → expect ~80 chars OK.)

### Step 2.2: Add new "Arguments" section explaining the flags

- [ ] In `commands/ship-idea.md`, replace the existing "## Argument" section (singular) with:

```markdown
## Arguments

- **`<description>`** (required) — one-line natural description (Claude generates the slug from it)

### Optional flags (used by /ship-next --auto:yes; not normally typed by hand)

- `--during-build` — non-interactive capture mode. Skips the interactive fill-in (existing step 6). Combine with the 3 flags below to provide context.
- `--severity <level>` — `major | minor | nit`. Stored in frontmatter `severity:`. Used when the idea is captured from a code-review finding that was deferred to follow-up.
- `--source <hint>` — short string like `code-review-skill auto-run during R-001.3`. Stored in frontmatter `source:`.
- `--related-roadmap-item <R-NNN>` — explicit cross-link to the R-NNN this idea was discovered while shipping. Stored in frontmatter `related-roadmap-item:`.
```

### Step 2.3: Add `--during-build` branch logic to the Steps section

- [ ] In `commands/ship-idea.md`, locate the existing **Step 6** (which begins "Fill the For future Claude preamble..."). Replace it with:

```markdown
6. **Fill the For future Claude preamble + Summary + Problem.** Two paths:

   - **Interactive mode (default)**: Use `<description>` and any extra context the user provided. Leave Target User / Evidence / Impact / Confidence / Dependencies / Risks / Possible Roadmap Item as section headers with `_to-fill_` placeholders only if the user is explicit that they want a quick capture; otherwise drive a short interactive fill-in.

   - **`--during-build` mode**: Skip interactive fill entirely. Write only the `<description>` into Summary + Problem. Other sections stay as `_to-fill_` placeholders. Add three extra frontmatter keys at the top (after existing keys, before the closing `---`):
     ```yaml
     severity: <severity-arg-value>           # major | minor | nit
     source: <source-arg-value>               # free-form
     related-roadmap-item: <R-NNN-arg-value>  # cross-link to parent
     ```
     These are emitted only when the corresponding flag was provided. Missing flag → omit the key entirely (do not write `null`).
```

### Step 2.4: Smoke test — verify flags parse and IDEA file lands

- [ ] Manual smoke test (in a fresh scratch repo or ai_system itself):

```bash
# In a scratch ship-workflow repo
/ship-idea --during-build \
  "Test idea from auto plan" \
  --severity minor \
  --source "test-smoke" \
  --related-roadmap-item R-999
```

Verify:
- `docs/ideas/IDEA-NNN-test-idea-from-auto-plan.md` exists.
- Frontmatter contains `severity: minor`, `source: test-smoke`, `related-roadmap-item: R-999`.
- No interactive prompts appeared.

### Step 2.5: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-idea.md
git commit -m "feat(ship-idea): --during-build + 3 metadata flags for auto-mode follow-ups"
```

---

## Task 3: `ship-next.md` arg parsing + frontmatter update for `--auto:yes`

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: none new
- Produces:
  - Frontmatter `argument-hint` includes `| --auto:yes` as a recognized variant.
  - Arg-parsing logic (early in Phase 1) detects either `--auto:yes` or `--auto` anywhere in `$@` and sets `AUTO=1`. Otherwise `AUTO=0`.
  - Mutual exclusion: if `--discard` and `--auto:yes` both present → ERROR exit 2 with hint.

### Step 3.1: Update frontmatter `argument-hint`

- [ ] Edit `commands/ship-next.md` frontmatter line:

Before:
```yaml
argument-hint: "[R-NNN] | --adhoc <desc> | --discard R-NNN | --resume R-NNN"
```

After:
```yaml
argument-hint: "[R-NNN] | --adhoc <desc> | --discard R-NNN | --resume R-NNN | --auto:yes"
```

(Still ≤ 100 char — verify: ~88.)

### Step 3.2: Add `--auto:yes` to the "## Arguments" section

- [ ] In the "## Arguments" section of `ship-next.md`, after the existing `--resume` bullet, append:

```markdown
- `--auto:yes` (alias `--auto`) — **fire-and-forget mode**. Runs the entire 9-phase cycle without interactive prompts: brainstorm clarifying questions auto-pick option 1; spec/plan review gates auto-approve; executor auto = subagent; review loop iterates fix-plans automatically up to cap=3; major findings auto-forwarded to `IDEA-NNN` follow-ups. On cap=3 failure: abort with worktree retained + Discord push. Requires the ROADMAP row to have a `↳ done when:` annotation. Records every auto decision to `docs/.ship-auto-decisions.md` (gitignored) in the worktree.

  **Mutually exclusive with `--discard`** (deletion is destructive; auto must never delete).
```

### Step 3.3: Add arg-parsing pre-flight at the top of Phase 1

- [ ] In `commands/ship-next.md`, in **Phase 1**, right after the existing handle-`--discard` block (Phase 1 step 1) and before the `sync.sh` invocation (step 2), insert a new step **Step 1.5: Detect --auto:yes**:

```markdown
1.5. **Detect `--auto:yes`** (anywhere in the arg list):
    ```bash
    AUTO=0
    for arg in "$@"; do
      case "$arg" in
        --auto:yes|--auto) AUTO=1 ;;
      esac
    done

    # Mutual exclusion with --discard
    if [ "$AUTO" = "1" ] && [[ "$1" == "--discard" ]]; then
      echo "ERROR: --auto:yes and --discard are mutually exclusive." >&2
      echo "       --discard is destructive — never auto." >&2
      exit 2
    fi

    if [ "$AUTO" = "1" ]; then
      echo "🤖 Auto:yes mode — no interactive prompts. Decision log: <worktree>/docs/.ship-auto-decisions.md"
    fi
    ```

    The `AUTO` variable is referenced throughout the rest of this command file — every interactive prompt has an `if [ "$AUTO" = "1" ]` branch.
```

### Step 3.4: Smoke test arg parsing

- [ ] Manual verification — read the file and confirm:

```bash
grep -nE "(AUTO=|--auto:yes|--auto[\)\|])" claude-skills/ship-workflow/commands/ship-next.md | head -10
```

Expected: 4-6 hits showing the flag is referenced.

### Step 3.5: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): --auto:yes arg parsing + frontmatter + Phase 1 detection"
```

---

## Task 4: Pre-flight `done-when` gate for `--auto:yes`

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `AUTO` variable from Task 3; `ROADMAP_PATH` from existing Phase 1
- Produces:
  - In auto mode: if ROADMAP row for `$ID` lacks `↳ done when:` annotation → ERROR exit 2 with install hint to run `/ship-roadmap`.
  - In auto mode: missing `↳ explain:` or proposal → WARN to stderr, proceed.

### Step 4.1: Insert done-when gate in Phase 1

- [ ] In `commands/ship-next.md`, after Phase 1's `Resolve R-NNN` step (currently around step 4) and BEFORE the `Derive slug` step (step 5), insert a new step **Step 4.5: Auto pre-flight gate**:

```markdown
4.5. **Auto pre-flight gate** (only in `--auto:yes` mode):
    ```bash
    if [ "$AUTO" = "1" ]; then
      ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"

      # Required: done-when annotation on the row
      ROW=$(grep -A2 "\*\*${ID}\*\*" "$ROADMAP_PATH" || true)
      DONE_WHEN=$(echo "$ROW" | grep "↳ done when:" || true)
      if [ -z "$DONE_WHEN" ]; then
        echo "ERROR: --auto:yes refused — R-NNN $ID has no ↳ done when: annotation." >&2
        echo "       fire-and-forget mode requires an explicit success criterion." >&2
        echo "       Run /ship-roadmap (or edit ROADMAP.md to add ↳ done when: <criterion>)," >&2
        echo "       then re-invoke /ship-next $ID --auto:yes." >&2
        exit 2
      fi

      # Recommended (warn only): explainer + proposal
      EXPLAIN=$(echo "$ROW" | grep "↳ explain:" || true)
      [ -z "$EXPLAIN" ] && echo "WARN: $ID has no ↳ explain: annotation — brainstorm may pick defaults that don't match your intent" >&2

      PROPOSAL=$(ls "$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Proposals/"*"${ID}"*"-proposal.md" 2>/dev/null | head -1)
      [ -z "$PROPOSAL" ] && echo "WARN: $ID has no proposal — brainstorm design space is less constrained" >&2
    fi
    ```
```

### Step 4.2: Smoke test

- [ ] Verify behavior on an R-NNN with done-when annotation (e.g., R-002 in ai-eden-service which we annotated earlier) — should pass gate, print warnings if explain missing.

- [ ] Verify behavior on a manufactured row WITHOUT done-when — should error exit 2.

(This is a manual test deferred to Task 10 end-to-end smoke. Tick this step on plan execution.)

### Step 4.3: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): auto pre-flight gate refuses if row lacks ↳ done when:"
```

---

## Task 5: Per-phase auto branches + decision-log writes (P1-P5)

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `AUTO` variable (Task 3); `auto-decision-log.sh` (Task 1)
- Produces:
  - Phase 1 worktree-exists prompt → in auto: auto continue + log entry
  - Phase 3 brainstorm clarifying questions → in auto: pick option 1 per question + log entry per question
  - Phase 3 spec review gate → in auto: auto-approve + log entry
  - Phase 4 plan review gate → in auto: auto-approve + log entry
  - Phase 5 executor choice → in auto: auto-pick 1 + log entry
  - Each decision log entry calls `lib/auto-decision-log.sh "$WORKTREE" "P<N>" "<decision>" "<detail>"`

### Step 5.1: Phase 1 — auto continue on existing worktree

- [ ] In `commands/ship-next.md` Phase 1, find the "Detect existing worktree" step (currently step 7 of Phase 1). After the existing `Continue ${ID} in existing worktree? [Y/n/discard]` prompt, wrap the choice handling with an auto branch:

Before (the resume prompt body):
```markdown
    - If `$WORKTREE` exists: prompt `"Continue ${ID} in existing worktree? [Y/n/discard]"`.
      - `Y` (or `--resume` was passed): jump to Phase 3...
      - `discard`: ...
      - `n`: exit 0.
```

After — prepend an auto branch:
```markdown
    - If `$WORKTREE` exists:
      - **In auto mode** (`AUTO=1`): auto-continue. Log:
        ```bash
        ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P1" "existing worktree detected — auto-continuing" "branch=$BRANCH"
        ```
        Jump to Phase 3.
      - **Interactive**: prompt `"Continue ${ID} in existing worktree? [Y/n/discard]"`.
        - `Y` (or `--resume` was passed): jump to Phase 3...
        - `discard`: ...
        - `n`: exit 0.
```

### Step 5.2: Phase 3 — brainstorming skill auto-answer

- [ ] In `commands/ship-next.md` Phase 3 step 2 (currently invokes `superpowers:brainstorming`), append a sub-step describing auto-mode handling:

After the existing `Invoke superpowers:brainstorming with context:` paragraph, append:

```markdown
   **In auto mode (`AUTO=1`):** the brainstorming skill is still invoked, but **every clarifying question is auto-answered by picking option 1**. The brainstorming skill convention is to lead with the recommended option, so option 1 = recommended.

   After each auto-answered question, log:
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "brainstorm Q${N} auto-picked option 1" "<question summary truncated to 80 chars>"
   ```

   When the brainstorming skill reaches the "Review spec first?" gate, auto-approve:
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "spec review → auto-approved"
   ```
```

### Step 5.3: Phase 4 — writing-plans skill auto-answer

- [ ] In `commands/ship-next.md` Phase 4 (after the existing `Invoke superpowers:writing-plans` step), append:

```markdown
   **In auto mode (`AUTO=1`):** the writing-plans skill's "Review plan first?" gate is auto-approved.
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P4" "plan review → auto-approved"
   ```
```

### Step 5.4: Phase 5 — executor auto-pick

- [ ] In `commands/ship-next.md` Phase 5 step 1 (the "Ask the user: 1. Subagent-driven..." menu), wrap with auto branch:

Before:
```markdown
1. **Ask the user:**
   ```
   Plan ready at docs/plans/${ID}-${SLUG}.md. Choose executor:
     1. Subagent-driven (recommended) — fresh subagent per task, review between
     2. Inline executing-plans — sequential in this session, batch with checkpoints
     3. Codex /run-plan — autonomous in background
   ```
```

After:
```markdown
1. **Choose executor.**
   - **In auto mode (`AUTO=1`):** auto-pick `1` (subagent-driven). Log:
     ```bash
     ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P5" "executor → auto-picked: 1 (subagent-driven)"
     ```
   - **Interactive:** prompt
     ```
     Plan ready at docs/plans/${ID}-${SLUG}.md. Choose executor:
       1. Subagent-driven (recommended) — fresh subagent per task, review between
       2. Inline executing-plans — sequential in this session, batch with checkpoints
       3. Codex /run-plan — autonomous in background
     ```
```

### Step 5.5: Update Phase 5 step 2 (executor choice recording)

- [ ] The existing step 2 writes the executor choice to `.claude/.ship-executor`. Keep that, but add log line right after:

```bash
echo "$EXECUTOR_CHOICE" > .claude/.ship-executor
# In auto mode, the log entry from step 5.4 already captured the choice.
```

(No change needed to existing recording — it's compatible.)

### Step 5.6: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): P1-P5 auto branches + decision log writes"
```

---

## Task 6: P6 review loop auto-iterate + cap=3 abort

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `AUTO`, `auto-decision-log.sh`, existing `code-review-parse.sh` parsing in P6
- Produces:
  - In auto mode: P6 loop runs **without printing blockers to the user**; it just builds fix-plan and re-invokes executor up to cap=3.
  - Every attempt logs a line.
  - On cap=3 still-blocking: ABORT — don't cd back to main, don't cleanup, exit 1. (Notification fires from Task 8.)

### Step 6.1: Wrap P6 loop body with auto branch

- [ ] In `commands/ship-next.md` Phase 6, find the existing pseudocode loop:

```
attempt=1
while attempt <= 3:
  ...
  REVIEW_OUT=...
  eval "$(code-review-parse.sh $REVIEW_OUT)"
  if [ "$BLOCKING_COUNT" -eq 0 ]; then break; fi
  echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
  ...
  attempt=$((attempt + 1))
  ...
```

Replace with the following extended pseudocode that branches on AUTO:

```markdown
2. **Loop:**
   ```
   attempt=1
   while [ "$attempt" -le 3 ]; do
     REVIEW_TARGET=$(git diff ${ORIG_BRANCH}..HEAD)
     REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
     # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT

     eval "$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh $REVIEW_OUT)"

     # Auto mode: log every attempt
     if [ "$AUTO" = "1" ]; then
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
         "review attempt $attempt" \
         "blocking=$BLOCKING_COUNT major=$MAJOR_COUNT minor=$MINOR_COUNT praise=$PRAISE_COUNT"
     fi

     if [ "$BLOCKING_COUNT" -eq 0 ]; then break; fi

     # Print blockers ONLY in interactive mode (auto mode keeps quiet)
     if [ "$AUTO" = "0" ]; then
       echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' $REVIEW_OUT
     fi

     attempt=$((attempt + 1))
     if [ "$attempt" -gt 3 ]; then break; fi  # fall through to abort below

     # Build inline fix-plan
     FIX_PLAN=docs/plans/${ID}-${SLUG}-review-fix-${attempt}.md
     # ... (existing logic: write fix-plan, invoke subagent on it)

     if [ "$AUTO" = "1" ]; then
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
         "building fix-plan attempt $attempt" \
         "$FIX_PLAN with $BLOCKING_COUNT blockers"
     fi

     EXECUTOR=$(cat .claude/.ship-executor)
     case "$EXECUTOR" in
       1) invoke superpowers:subagent-driven-development on $FIX_PLAN ;;
       2) invoke superpowers:executing-plans on $FIX_PLAN ;;
       3) invoke /run-plan $FIX_PLAN ;;
     esac
   done
   ```
```

### Step 6.2: Replace the "If still blocking after 3 attempts" interactive pause with auto-abort branch

- [ ] In `commands/ship-next.md` Phase 6, find the existing block:

```markdown
3. **If still blocking after 3 attempts**, pause:
   ```
   3 review attempts didn't clear blockers. Options:
     [Y] Auto-fix one more cycle (loop continues)
     [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
     [abort] Discard everything — /ship-next --discard ${ID}
   ```
```

Replace with:

```markdown
3. **If still blocking after 3 attempts:**

   - **In auto mode (`AUTO=1`):** **ABORT** the cycle.
     ```bash
     ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
       "cap=3 exhausted — aborting" \
       "blocking=$BLOCKING_COUNT main untouched, worktree retained at $WORKTREE"

     # DO NOT cd back to ORIG_BRANCH.
     # DO NOT remove worktree.
     # DO NOT delete branch.
     # Notification will fire from Task 8 abort path.
     # Exit 1 so callers (codex /run-plan, automation) see failure.
     exit 1
     ```

   - **Interactive (`AUTO=0`):** pause and prompt:
     ```
     3 review attempts didn't clear blockers. Options:
       [Y] Auto-fix one more cycle (loop continues)
       [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
       [abort] Discard everything — /ship-next --discard ${ID}
     ```
```

### Step 6.3: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): P6 auto-iterate review loop + cap=3 abort path"
```

---

## Task 7: P6 major findings → IDEA-NNN auto-create

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `AUTO`, parsed `MAJOR_COUNT` from existing P6, `/ship-idea --during-build` (Task 2)
- Produces:
  - When `BLOCKING_COUNT == 0` (loop exit) and `MAJOR_COUNT > 0`: in auto mode, iterate the major findings and create one IDEA-NNN per finding via `/ship-idea --during-build`.
  - Each IDEA creation logs to decision log.
  - In interactive mode: existing per-finding `[F]ix-now / [I]dea-NNN / [S]kip` prompt unchanged.

### Step 7.1: Add the major-handling branch right before Phase 7

- [ ] In `commands/ship-next.md`, between Phase 6 step 4 (the existing "Major findings handling" block) and Phase 7, insert a fully auto-branched version:

Before:
```markdown
4. **Major findings handling** (only after BLOCKING_COUNT reaches 0): list them and ask per-finding `[F]ix-now / [I]dea-NNN-followup / [S]kip`.
```

After:
```markdown
4. **Major findings handling** (only after `BLOCKING_COUNT == 0`):

   - **In auto mode (`AUTO=1`):** every major finding becomes an `IDEA-NNN` follow-up (NEVER skip; quality-debt must be visible).
     ```bash
     if [ "$MAJOR_COUNT" -gt 0 ]; then
       # Extract major findings from $REVIEW_OUT — grab the line + 1-2 lines context
       MAJOR_LINES=$(grep -B0 -A2 -E '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' $REVIEW_OUT)

       # Parse each finding into a 1-line description
       IFS=$'\n'
       for finding in $(echo "$MAJOR_LINES" | awk 'NR==1 || /^[🟡]|\[major\]|\*\*Severity/' | head -$MAJOR_COUNT); do
         finding_desc=$(echo "$finding" | sed 's/^[🟡[:space:]]*//' | head -c 120)
         /ship-idea --during-build \
           "P6 major from $ID: $finding_desc" \
           --severity major \
           --source "code-review-skill auto-run during $ID" \
           --related-roadmap-item "$ID"
       done
       unset IFS

       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
         "majors → IDEAs created" \
         "$MAJOR_COUNT IDEA-NNN follow-ups via /ship-idea --during-build"
     fi
     ```

   - **Interactive (`AUTO=0`):** list majors and ask per-finding `[F]ix-now / [I]dea-NNN-followup / [S]kip`.
```

### Step 7.2: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): P6 majors auto-forwarded to IDEA-NNN in auto mode"
```

---

## Task 8: Notification integration (success + abort paths)

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `AUTO`, parsed counts, `$WORKTREE`, sha (after Phase 7 merge)
- Produces:
  - **Success path** (after Phase 9 cleanup, only in auto mode): send Discord push if in Discord session; else `PushNotification`; always also call `osascript` for OS notification + bell.
  - **Abort path** (from Task 6 cap=3 fail, only in auto mode): same channel selection logic, different message body.

### Step 8.1: Add success notification block at end of Phase 9

- [ ] In `commands/ship-next.md`, AFTER Phase 9's existing "Log + commit (repo side)" step, append a new step **Phase 9 step 4: Auto-mode success notification**:

```markdown
4. **Auto-mode success notification** (only if `AUTO=1`):

   Build the success message body:
   ```bash
   if [ "$AUTO" = "1" ]; then
     SUMMARY="✅ ${ID} ${DESCRIPTION} shipped (squash ${MERGE_SHA})
   • blocking: 0 ✓
   • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
   • minor: ${MINOR_COUNT}
   • praise: ${PRAISE_COUNT}
   • decisions log: ${WORKTREE}/docs/.ship-auto-decisions.md (kept in worktree pre-cleanup; copy if you want post-mortem)"

     # Channel routing (per /run-plan skill convention):
     # - Discord session (incoming message tag has channel source="discord"): use Discord reply
     # - Else: use PushNotification
     # - Always also fire osascript + bell for local presence

     # Scan conversation context for a discord chat_id (Claude does this at invocation time).
     # If a chat_id is in scope: call Discord reply with $SUMMARY, chat_id, files=[$WORKTREE/docs/.ship-auto-decisions.md]
     # Else: call PushNotification subject="/ship-next ${ID} shipped" body=$SUMMARY

     # Local OS notification + bell — fires regardless of channel
     osascript -e "display notification \"${ID} shipped: squash ${MERGE_SHA}\" with title \"/ship-next done\" sound name \"Glass\"" 2>/dev/null || true
     printf '\a' >&2
   fi
   ```
```

### Step 8.2: Add abort notification block to Task 6's cap=3 path

- [ ] Edit `commands/ship-next.md` Phase 6 step 3 (the auto-mode ABORT branch added in Task 6.2). After the `exit 1` line, insert before it the abort notification logic. The block becomes:

```markdown
   - **In auto mode (`AUTO=1`):** **ABORT** the cycle.
     ```bash
     ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
       "cap=3 exhausted — aborting" \
       "blocking=$BLOCKING_COUNT main untouched, worktree retained at $WORKTREE"

     SUMMARY="🛑 ${ID} ${DESCRIPTION} aborted at P6 — 3 attempts didn't clear blockers.
   • blocking remaining: ${BLOCKING_COUNT}
   • last attempt review: /tmp/ship-next-review-${ID}-3.md
   • worktree retained: ${WORKTREE}
   • branch retained: ${BRANCH}
   • resume: cd ${WORKTREE} && /ship-next --resume ${ID}"

     # Channel routing — same as success path
     # Discord session: call reply with $SUMMARY, chat_id
     # Else: PushNotification subject="/ship-next ${ID} aborted" body=$SUMMARY

     osascript -e "display notification \"${ID} aborted — see Discord/log\" with title \"/ship-next abort\" sound name \"Sosumi\"" 2>/dev/null || true
     printf '\a' >&2

     # DO NOT cd back to ORIG_BRANCH. DO NOT remove worktree. DO NOT delete branch.
     exit 1
     ```
```

### Step 8.3: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): auto-mode success + abort notifications (Discord / PushNotification / osascript)"
```

---

## Task 9: `/run-plan` skill prompt-template update (out-of-tree)

**Files:**
- **None modified in this repo.** This task documents an out-of-tree change that the user must apply manually.

**Interfaces:**
- Consumes: nothing
- Produces:
  - Documentation entry in this plan + a follow-up TodoWrite item for the user.

### Step 9.1: Document the constraint to add to `~/.claude/skills/run-plan/SKILL.md`

- [ ] No file edit. Print to the user:

```
Manual follow-up: edit ~/.claude/skills/run-plan/SKILL.md "Step 2: Build the prompt" section,
in the "WORKFLOW:" or "CONSTRAINTS:" block, add this line:

  - If you invoke `/ship-next` from a plan task, ALWAYS include `--auto:yes`. Codex cannot answer interactive prompts; /ship-next without --auto:yes will hang waiting for user input.

This is out-of-tree (lives under ~/.claude/, not this repo) so codex / agents avoid touching it.
```

### Step 9.2: Append to plan execution log (no commit)

- [ ] Add an entry to the plan's `## Execution log` section noting "Task 9 deferred — user applies manually to ~/.claude/skills/run-plan/SKILL.md".

(No git commit for this task — it's a documentation-only step.)

---

## Task 10: `.claude/.gitignore` update (in ship-init template)

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-init.md`

**Interfaces:**
- Consumes: existing `ship-init.md` step that writes `.claude/.gitignore`
- Produces:
  - New repos via `/ship-init` get `.ship-auto-decisions.md` in `.claude/.gitignore`.
  - Existing repos: must add the line manually OR re-run `/ship-init --upgrade` (which copies commands but not the gitignore — that's why we also have `ship-next.md` auto-append in step 10.2).

### Step 10.1: Update `ship-init.md` gitignore line

- [ ] In `commands/ship-init.md` step 3 (the scaffold block), find the line:

```markdown
   - `.claude/.gitignore` adding `.ship-last-pull` and `.id-gen.lock` and `.id-reservations`
```

Replace with:

```markdown
   - `.claude/.gitignore` adding `.ship-last-pull`, `.id-gen.lock`, `.id-reservations`, and `.ship-auto-decisions.md`
```

### Step 10.2: Make `ship-next.md` self-heal for existing repos

- [ ] In `commands/ship-next.md`, in **Phase 1** (right after the `--auto:yes` detection block from Task 3 step 3.3, before the `sync.sh` call), insert a step that adds the gitignore line if missing:

```markdown
1.6. **Self-heal `.claude/.gitignore`** (auto mode only, idempotent):
    ```bash
    if [ "$AUTO" = "1" ] && [ -f .claude/.gitignore ]; then
      if ! grep -qF ".ship-auto-decisions.md" .claude/.gitignore; then
        echo ".ship-auto-decisions.md" >> .claude/.gitignore
        # Note: this edit happens in main repo BEFORE Phase 2 opens the worktree.
        # Worktree inherits the gitignore.
      fi
    fi
    ```
```

### Step 10.3: Smoke test gitignore

- [ ] Manual: in ai-eden-service repo, before first `/ship-next --auto:yes`, check `.claude/.gitignore` doesn't contain `.ship-auto-decisions.md`. After first auto run, verify it's been added.

### Step 10.4: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-init.md \
        claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-workflow): .claude/.gitignore covers .ship-auto-decisions.md (new + self-heal)"
```

---

## Task 11: End-to-end smoke test in `ai-eden-service`

**Files:**
- None modified (acceptance check).

**Interfaces:**
- Consumes: everything from Tasks 1-10 + parent plan's shipped `/ship-next` mega flow + installed `code-review-skill`
- Produces: AC-001 through AC-015 verified observable.

### Step 11.1: Pre-conditions

- [ ] Verify `awesome-skills/code-review-skill` installed at `~/.claude/skills/code-review-skill/SKILL.md` (done in earlier session).

- [ ] Verify ai-eden-service repo clean:

```bash
cd /Users/leric/Desktop/code/ai-eden-service && git status
```

Expected: clean tree (modulo pre-existing untracked `.claude-uploads/`, `docs/proposals/`, `docs/research/`).

- [ ] Verify a target R-NNN has `↳ done when:` annotation (for the gate to pass). Recommended target for smoke: **R-002** (Next section, effort=S, already done-when annotated by us via earlier rewrite).

### Step 11.2: Happy path — auto run

Invoke:
```
/ship-next R-002 --auto:yes
```

(Must pre-move R-002 from "Next" to "Now" first, OR use `--adhoc "Smoke auto test (DELETE AFTER)" --auto:yes`.)

Observe — tick each AC:

- [ ] **AC-001**: zero keypresses required between invocation and completion.
- [ ] **AC-002**: alternate flag `--auto` works the same (test with a second adhoc to verify).
- [ ] **AC-003**: try `/ship-next --discard R-002 --auto:yes` — ERROR exit 2 mutually exclusive.
- [ ] **AC-004**: try `/ship-next R-009 --auto:yes` (R-009 has no done-when in current ROADMAP) — ERROR exit 2 with hint.
- [ ] **AC-005**: try an R-NNN missing explainer — WARN to stderr, proceeds.
- [ ] **AC-006**: verify decision log contains "auto-picked option 1" for brainstorm + "auto-approved" for spec/plan gates.
- [ ] **AC-007**: decision log contains "executor → auto-picked: 1 (subagent-driven)".
- [ ] **AC-008**: P6 attempts iterate without prompts (visible in log).
- [ ] **AC-010**: if review produces ≥1 major, verify a `docs/ideas/IDEA-NNN-*.md` file is created with `severity: major`, `source: code-review-skill auto-run...`, `related-roadmap-item: R-002`.
- [ ] **AC-011**: open `<worktree>/docs/.ship-auto-decisions.md` — verify it has one line per P1..P9 transition.
- [ ] **AC-012**: verify the decision log file is gitignored:
  ```bash
  cd /Users/leric/Desktop/code/ai-eden-service
  git check-ignore -v docs/.ship-auto-decisions.md  # may not exist on main if cleanup happened; check in a fresh adhoc test
  ```
- [ ] **AC-013**: if invoked from Discord, verify Discord reply with sha + IDEA links arrives.

### Step 11.3: Abort path — force cap=3 failure

To verify AC-009 + AC-014, force review to keep blocking. One way: in mid-cycle, manually inject a security-flavored line into the worktree's code (e.g., `eval(user_input)` in a python file). Then let auto-mode try to fix it 3 times. Expected: abort, worktree retained.

- [ ] **AC-009**: after intentional 3-fail abort, verify:
  - `git status` on main = clean (no new commit)
  - `git worktree list` still shows the worktree
  - `git branch --list 'ship/*'` still shows the branch
  - exit code was 1
- [ ] **AC-014**: Discord push contains: failure phase, blocker count, worktree path, resume hint.

### Step 11.4: AC-015 — `/run-plan` template

- [ ] Manual: check `~/.claude/skills/run-plan/SKILL.md` after applying Task 9's instructions. Verify the "always --auto:yes" constraint is now in the prompt template.

### Step 11.5: AC checklist final report

Print summary:

```
✓ AC-001  zero keypresses (happy path)
✓ AC-002  --auto alias works
✓ AC-003  --discard + --auto:yes errors
✓ AC-004  missing done-when refused exit 2
✓ AC-005  missing explainer warns but proceeds
✓ AC-006  brainstorm Q's + spec/plan gates auto-handled
✓ AC-007  executor auto = 1
✓ AC-008  P6 iterates silently
✓ AC-009  cap=3 abort: main untouched, worktree retained
✓ AC-010  majors → IDEA-NNN
✓ AC-011  decision log has all P1..P9 entries
✓ AC-012  decision log is gitignored
✓ AC-013  Discord success push
✓ AC-014  Discord abort push
✓ AC-015  /run-plan template has --auto:yes constraint
```

### Step 11.6: Cleanup smoke artifacts

If the smoke happened via `--adhoc`, the smoke R-NNN is shipped to main + ROADMAP marked ✅. Clean up:
- Reverse-edit ROADMAP to remove the smoke R-NNN (or move to Done with note "smoke test, ignore")
- `git revert` the smoke squashed commit if desired
- Delete generated brainstorm/spec/plan files for the smoke R-NNN
- Commit "chore: remove ship-next --auto:yes smoke artifacts"

No code commit needed for Task 11 (acceptance verification only).

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 Flag syntax `--auto:yes` / `--auto` | Task 3 (arg parsing + frontmatter) |
| §3.2 Pre-flight done-when gate | Task 4 |
| §3.3 Per-phase auto matrix (P1-P5) | Task 5 |
| §3.3 P6 review loop + cap=3 abort | Task 6 |
| §3.3 P6 major findings → IDEA-NNN | Task 7 |
| §3.4 Decision log file + format | Task 1 (helper) + Tasks 5/6/7 (call sites) |
| §3.5 Cap=3 abort details | Task 6 step 6.2 |
| §3.6 Major findings auto-handling | Task 7 |
| §3.7 Notifications (success + abort) | Task 8 |
| §3.8 /run-plan template constraint | Task 9 |
| §4.1 Modified files | Tasks 3, 4, 5, 6, 7, 8, 10 (all modify ship-next.md or ship-idea.md or ship-init.md) |
| §4.2 New helper files | Task 1 |
| §4.3 Frontmatter argument-hint update | Task 3 step 3.1 |
| §4.4 Out-of-tree run-plan SKILL.md | Task 9 |
| §6 AC-001..AC-015 | Task 11 acceptance smoke |
| §9 Phase 0..9 | Phase 0 done (spec commit 4dd47c3); Phase 1 → Task 1; Phase 2 → Task 2; Phase 3 → Task 3, 5; Phase 4 → Task 4; Phase 5 → Task 6; Phase 6 → Task 7; Phase 7 → Task 8; Phase 8 → Task 9; Phase 9 → Task 11 |
| §10.2 .claude/.gitignore update | Task 10 |

All spec sections covered. §7.2 open questions remain as deferred items per spec.

**2. Placeholder scan:**
- No `TBD`, `TODO`, `fill in later`, `similar to Task N`.
- All bash, bats, and markdown code blocks are complete and runnable.
- Every Edit step shows the exact text replacement (before → after).

**3. Type consistency:**
- `auto-decision-log.sh <worktree> <phase> <decision> [detail]` signature consistent across Task 1 (definition) and Tasks 5/6/7 (callers).
- `AUTO` variable: declared in Task 3 step 3.3; consumed in Tasks 4, 5, 6, 7, 8, 10 — same `if [ "$AUTO" = "1" ]` pattern throughout.
- `/ship-idea --during-build --severity X --source Y --related-roadmap-item Z` invocation pattern: defined in Task 2 step 2.3, called in Task 7 step 7.1 — identical flag set.
- Worktree-retained-on-abort invariant (no cleanup, no cd, exit 1) consistent across Task 6 step 6.2 and Task 8 step 8.2.

All consistent.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-22-ship-next-auto-yes-implementation.md`. Three execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks. Best fit because Task 1 is TDD-ideal for disposable subagent; Tasks 2-10 are mostly markdown edits to 3 specific files (ship-next.md / ship-idea.md / ship-init.md) — sequential dependency on Task 3 (arg parsing) so can't go fully parallel, but each task is clean review unit.

**2. Inline Execution** — sequential in this session with checkpoints. Live review each Edit.

**3. Codex `/run-plan`** — autonomous background. Worked well for prior plans (DONE_WITH_CONCERNS, 8-of-9 tasks). Expect Codex to skip Task 9 (out-of-tree to ~/.claude/) and Task 11 (interactive smoke) — same defer pattern as before.

Which approach?
