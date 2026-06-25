# Spec Vault Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `/ship-next` Phase 3 writes a spec, also dual-write it to `<vault>/<project>/Specs/R-NNN-<slug>.md` with a `mirror-source:` frontmatter key, so the spec is viewable in Obsidian without leaving the canonical source in repo.

**Architecture:** One new TDD bash helper (`lib/spec-mirror.sh`) handles the copy + frontmatter injection. `commands/ship-next.md` Phase 3 gains a dual-write call after the existing spec write. Phase 3 resume re-mirrors. Phase 1 `--discard` block also globs-and-removes the vault file. No `sync.sh` changes — this is a one-way `/ship-next` → vault write, not a sync.

**Tech Stack:** Bash + awk (lib helper), bats (helper tests), markdown (slash command file).

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-22-spec-vault-mirror-design.md`:

- **Repo is canonical, vault is mirror.** Engineers edit specs in repo; vault is read-only by convention.
- **Scope = spec only.** Brainstorm / plan / learning / idea / decision stay repo-only.
- **Trigger = /ship-next P3 dual-write.** Plus P3 resume re-mirror (per spec §7.2-Q1 resolution: "lean yes for safety").
- **Vault path**: `<vault>/10 Projects/<project>/Specs/R-NNN-<slug>.md` (flat, no epic nesting).
- **Filename**: identical to repo side: `R-NNN-<slug>.md`.
- **Frontmatter injection**: `mirror-source: docs/specs/R-NNN-<slug>.md` inserted inside the frontmatter block (before closing `---`). Idempotent — if already present, do not duplicate.
- **Atomic write**: `<dst>.tmp` then `mv` (matches existing sync.sh pattern).
- **`--discard R-NNN`** cleanup: glob-remove `<vault>/<project>/Specs/R-NNN-*.md` alongside worktree/branch cleanup.
- **No reverse sync.** `lib/sync.sh` stays purely vault→repo. The vault Specs/ write happens only from /ship-next P3.
- **Test gate**: all current 89 bats tests must remain green. New tests added inline.
- **Tooling baseline**: bats 1.x, bash 5.x, macOS-compatible. No new system dependencies.
- **Slash-command frontmatter contract**: `name`, `description` (≤ 100 char), `argument-hint`, `discord-visible: true` — `ship-next.md` already conforms; no frontmatter changes in this plan.

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/lib/spec-mirror.sh` | Copy repo spec → vault Specs/ with `mirror-source:` frontmatter injected; atomic write via `.tmp + mv`; idempotent |
| `claude-skills/ship-workflow/tests/test_spec-mirror.bats` | TDD coverage for above |

### Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/commands/ship-next.md` | Phase 3 step (after spec write, before commit): invoke `spec-mirror.sh`. Phase 3 resume detection: also re-mirror if spec exists. Phase 1 `--discard` block: glob-remove vault spec. |

### Unchanged
- `lib/sync.sh` — no reverse sync added.
- `lib/airos-binding.sh` — `project_path` already gives vault project root; Specs/ subpath computed inline.
- `commands/ship-init.md` — no pre-create Specs/ dir; /ship-next P3 handles it lazily via `mkdir -p`.
- All other ship-* commands — orthogonal.

---

## Task Right-Sizing Notes

4 tasks. Task 1 is pure bash + bats (strict TDD with fixtures). Task 2 is one focused markdown edit in `ship-next.md` Phase 3. Task 3 is two more small markdown edits (Phase 1 discard + Phase 3 resume re-mirror). Task 4 is the live acceptance smoke test (AC-001..010).

---

## Task 1: `lib/spec-mirror.sh` + bats tests

**Files:**
- Create: `claude-skills/ship-workflow/lib/spec-mirror.sh`
- Create: `claude-skills/ship-workflow/tests/test_spec-mirror.bats`

**Interfaces:**
- Consumes: nothing (standalone)
- Produces:
  - Executable: `spec-mirror.sh <src-spec-path> <dst-vault-path>`
  - Side effect: write `<dst>` with body identical to `<src>` + `mirror-source: <src>` injected inside frontmatter block (before closing `---`).
  - Idempotent: if `<src>` already contains `mirror-source:` key, don't duplicate; if `<src>` has no frontmatter, copy as-is (no injection).
  - Atomic via `<dst>.tmp` + `mv`.
  - Auto-creates `<dst>` parent dir via `mkdir -p` if absent.
  - Exit codes: `0` on success; `2` if `<src>` doesn't exist; `1` if fewer than 2 args.

### Step 1.1: Write failing tests

- [ ] Create `tests/test_spec-mirror.bats` with full content:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch spec-mirror)"
  export SRC="$SCRATCH/src/docs/specs/R-001.3-wire-scene-engine.md"
  export DST="$SCRATCH/dst/Specs/R-001.3-wire-scene-engine.md"
  mkdir -p "$(dirname "$SRC")"
  cat > "$SRC" <<'EOF'
---
date: 2026-06-22
type: spec
status: draft
id: R-001.3
tags: [spec]
ai-first: true
---

## For future Claude
> Test spec body.

## §1 Problem
Spec body content goes here.
EOF
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "spec-mirror: writes destination file with body preserved" {
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  [ "$status" -eq 0 ]
  [ -f "$DST" ]
  grep -q "## §1 Problem" "$DST"
  grep -q "Spec body content goes here." "$DST"
}

@test "spec-mirror: injects mirror-source key inside frontmatter" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  grep -qF "mirror-source: $SRC" "$DST"
  # Verify it's INSIDE frontmatter (between the two --- lines), not in body
  awk '
    /^---$/ { fm++ ; next }
    fm == 1 && /^mirror-source:/ { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$DST"
}

@test "spec-mirror: idempotent — running twice produces same content" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  cp "$DST" "$DST.first"
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  diff -q "$DST" "$DST.first"
  # Verify only ONE mirror-source: line
  count=$(grep -c "^mirror-source:" "$DST")
  [ "$count" -eq 1 ]
}

@test "spec-mirror: idempotent on src that already has mirror-source" {
  # Pre-seed src with the key
  sed -i.bak '/^ai-first: true$/a\
mirror-source: docs/specs/R-001.3-wire-scene-engine.md' "$SRC" && rm "$SRC.bak"
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  count=$(grep -c "^mirror-source:" "$DST")
  [ "$count" -eq 1 ]
}

@test "spec-mirror: creates parent dir via mkdir -p" {
  nested="$SCRATCH/dst/deeply/nested/Specs/R-001.3-x.md"
  rm -rf "$SCRATCH/dst/deeply"
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$nested"
  [ "$status" -eq 0 ]
  [ -f "$nested" ]
}

@test "spec-mirror: atomic write — no .tmp leftover on success" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  ! ls "$DST.tmp" 2>/dev/null
}

@test "spec-mirror: exits 2 when src doesn't exist" {
  run "$SHIP_LIB/spec-mirror.sh" "$SCRATCH/nonexistent.md" "$DST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "spec-mirror: exits 1 (or non-zero) when fewer than 2 args" {
  run "$SHIP_LIB/spec-mirror.sh" "$SRC"
  [ "$status" -ne 0 ]
}

@test "spec-mirror: src without frontmatter is copied as-is" {
  cat > "$SRC" <<'EOF'
# Plain markdown without frontmatter

Some content.
EOF
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  [ "$status" -eq 0 ]
  # mirror-source NOT injected (no frontmatter to inject into)
  ! grep -q "^mirror-source:" "$DST"
  # Body content still copied
  grep -q "Some content." "$DST"
}
```

### Step 1.2: Run tests to verify they fail

```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow && \
  bats tests/test_spec-mirror.bats 2>&1 | tail -15
```

Expected: 9 failures — script doesn't exist yet.

### Step 1.3: Implement `lib/spec-mirror.sh`

Create `claude-skills/ship-workflow/lib/spec-mirror.sh`:

```bash
#!/usr/bin/env bash
# spec-mirror.sh — copy a spec from repo to vault with mirror-source: key injected.
#
# Usage:
#   spec-mirror.sh <src-spec-path> <dst-vault-path>
#
# Side effects:
#   - Auto-creates <dst> parent dir via mkdir -p
#   - Writes to <dst>.tmp then atomically mv to <dst>
#   - Injects `mirror-source: <src>` inside the frontmatter block (before
#     the closing `---`), unless already present (idempotent).
#   - If <src> has no frontmatter, body is copied verbatim with no injection.
#
# Exit codes:
#   0  success
#   1  fewer than 2 args
#   2  src file not found

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <src-spec-path> <dst-vault-path>" >&2
  exit 1
fi

SRC="$1"
DST="$2"

if [ ! -f "$SRC" ]; then
  echo "ERROR: source spec not found: $SRC" >&2
  exit 2
fi

mkdir -p "$(dirname "$DST")"
TMP="${DST}.tmp"

awk -v src="$SRC" '
  BEGIN { state = "pre"; injected = 0 }

  # First --- enters frontmatter
  state == "pre" && /^---$/ { state = "fm"; print; next }

  # While inside frontmatter, watch for existing mirror-source
  state == "fm" && /^mirror-source:/ { injected = 1; print; next }

  # Second --- exits frontmatter — inject before printing it
  state == "fm" && /^---$/ {
    if (!injected) print "mirror-source: " src
    state = "body"
    print; next
  }

  # All other lines: print as-is
  { print }
' "$SRC" > "$TMP"

mv "$TMP" "$DST"
```

### Step 1.4: Make executable + run tests

```bash
chmod +x claude-skills/ship-workflow/lib/spec-mirror.sh
bats tests/test_spec-mirror.bats 2>&1 | tail -15
```

Expected: 9 tests pass.

### Step 1.5: Run full bats suite (regression gate)

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 98 ok lines (89 prior + 9 new), 0 not-ok.

### Step 1.6: Commit

```bash
git add claude-skills/ship-workflow/lib/spec-mirror.sh \
        claude-skills/ship-workflow/tests/test_spec-mirror.bats
git commit -m "feat(spec-mirror): atomic copy + mirror-source frontmatter injection (9 tests)"
```

---

## Task 2: `ship-next.md` Phase 3 dual-write integration

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `lib/spec-mirror.sh` (Task 1), existing `lib/airos-binding.sh project_path`
- Produces:
  - In `/ship-next` Phase 3, after the spec file exists at `docs/specs/${ID}-${SLUG}.md` (and before the `git commit` for "brainstorm+spec"), a new step copies the spec into vault `Specs/`.
  - In auto:yes mode, this step also writes one decision log entry.

### Step 2.1: Locate the Phase 3 spec write site

- [ ] Read `commands/ship-next.md` Phase 3 to confirm the structure. The existing flow (per the parent plan that shipped) has these steps in Phase 3:
  1. Resume detection (commit count / file presence)
  2. Proposal check
  3. Invoke `superpowers:brainstorming` (produces brainstorm + spec files)
  4. Verify outputs exist
  5. `git commit -m "brainstorm+spec: ${ID} ${SLUG}"`

  We insert a new step **between 4 and 5**: dual-write to vault.

### Step 2.2: Add the dual-write step in Phase 3

- [ ] In `commands/ship-next.md`, locate the Phase 3 block. Find the existing "Verify outputs" step (the one before the `git commit` for brainstorm+spec). After it, insert:

```markdown
3.5. **Dual-write spec to vault** (Obsidian visibility):

    ```bash
    VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
    ~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
      docs/specs/${ID}-${SLUG}.md \
      "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
    ```

    The helper handles `mkdir -p`, atomic write, and `mirror-source:` frontmatter injection. The vault file is NOT committed to git (repo is canonical; vault is one-way write target).

    **Auto-mode log:**
    ```bash
    if [ "$AUTO" = "1" ]; then
      ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" \
        "spec mirrored to vault" "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
    fi
    ```
```

### Step 2.3: Smoke check (deferred to Task 4)

- [ ] No bats test for ship-next.md (markdown). Real verification deferred to Task 4 end-to-end smoke.

### Step 2.4: Run full bats suite (no regression)

```bash
cd claude-skills/ship-workflow && bats tests/ 2>&1 | tail -3
```

Expected: still 98 green (markdown edit doesn't affect bats).

### Step 2.5: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): P3 dual-write spec to vault Specs/ (Obsidian visibility)"
```

---

## Task 3: `--discard` vault cleanup + P3 resume re-mirror

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `lib/spec-mirror.sh` (Task 1) for resume re-mirror; existing Phase 1 `--discard` block
- Produces:
  - Phase 1 `--discard` block also removes `<vault>/<project>/Specs/R-NNN-*.md`
  - Phase 3 resume detection: if spec already exists (skip-to-Phase-4 path), still call `spec-mirror.sh` once to bring vault to current state (catches any post-write edits in repo)

### Step 3.1: Add vault cleanup to `--discard` block

- [ ] In `commands/ship-next.md` Phase 1, locate the `--discard` handler (which currently does `git worktree remove --force` + `git branch -D ship/<branch>`). After those two lines, add:

```markdown
   ```bash
   # Also clean vault mirror (no orphan)
   VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
   rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
   ```
```

Glob match by ID prefix because slug derivation may have varied between sessions; sweep all matching files for this ID.

### Step 3.2: Add re-mirror to Phase 3 resume detection

- [ ] In `commands/ship-next.md` Phase 3, locate the resume detection step (the one that checks `ls docs/specs/${ID}-${SLUG}.md` etc. and decides which phase to skip to). When the path "spec exists → skip to Phase 4" is taken, insert a re-mirror call BEFORE skipping:

```markdown
0. **Resume detection.** Check what's already done in the worktree:
   - `ls docs/specs/${ID}-${SLUG}.md` exists → **first re-mirror spec to vault** (catch any post-write edits), then skip to Phase 4 (plan stage):
     ```bash
     VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
     ~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
       docs/specs/${ID}-${SLUG}.md \
       "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
     ```
   - `ls docs/plans/${ID}-${SLUG}.md` exists → skip to Phase 5 (executor).
   - `git log --oneline ${ORIG_BRANCH}..HEAD | wc -l` > 2 → executor has committed; skip to Phase 6 (review).
```

### Step 3.3: Smoke check (deferred to Task 4)

- [ ] Verify via Task 4 manual smoke.

### Step 3.4: Run full bats suite

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 98 green.

### Step 3.5: Commit

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): --discard cleans vault Specs/ + P3 resume re-mirrors"
```

---

## Task 4: End-to-end smoke in `ai-eden-service`

**Files:**
- None modified (acceptance verification).

**Interfaces:**
- Consumes: everything from Tasks 1-3 + existing /ship-next mega flow
- Produces: AC-001 through AC-010 verified observable.

### Step 4.1: Pre-conditions

- [ ] Verify the helper exists and is executable:

```bash
ls -la /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow/lib/spec-mirror.sh
```

Expected: file present, executable bit set.

- [ ] Verify `~/.claude/skills/code-review-skill/` installed (parent plan dep).

- [ ] Verify ai-eden-service repo clean (or only pre-existing untracked):

```bash
cd /Users/leric/Desktop/code/ai-eden-service && git status --short
```

- [ ] Confirm vault project path:

```bash
~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path
```

Expected: `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service`.

- [ ] Check whether vault `Specs/` already exists (it should NOT yet):

```bash
ls "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/" 2>&1
```

Expected: directory not found.

### Step 4.2: Happy path — invoke /ship-next with --adhoc

- [ ] In ai-eden-service repo cwd, run:

```
/ship-next --adhoc "Smoke test spec vault mirror (DELETE AFTER VERIFICATION)" --auto:yes
```

(Use `--auto:yes` to skip interactive prompts.)

### Step 4.3: Verify AC-001..AC-010

Tick each:

- [ ] **AC-005**: spec exists at BOTH:
  - `/Users/leric/Desktop/code/ai-eden-service/docs/specs/R-XXX-smoke-test-spec-vault-mirror.md`
  - `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-smoke-test-spec-vault-mirror.md`

  And the body content is identical (`diff -q` produces no output for the body — frontmatter will differ by the `mirror-source:` key).

- [ ] **AC-006**: vault file frontmatter contains `mirror-source: docs/specs/R-XXX-smoke-test-spec-vault-mirror.md`:

  ```bash
  head -20 "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-smoke-test-spec-vault-mirror.md" | grep "mirror-source:"
  ```

  Expected: one line of output matching the pattern.

- [ ] **AC-008**: vault `Specs/` directory was auto-created (it didn't exist before this run):

  ```bash
  ls "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/"
  ```

  Expected: at least 1 file (the smoke spec).

- [ ] **AC-001 + AC-004**: by inference, the helper wrote to the new location with mkdir-p. Verified by AC-005 + AC-008.

- [ ] **AC-002 (idempotency)**: manually invoke the helper a second time on the same src/dst:

  ```bash
  ~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
    /Users/leric/Desktop/code/ai-eden-service/docs/specs/R-XXX-smoke-test-spec-vault-mirror.md \
    "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-smoke-test-spec-vault-mirror.md"
  ```

  Then verify still only 1 `mirror-source:` line:

  ```bash
  grep -c "^mirror-source:" "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-smoke-test-spec-vault-mirror.md"
  ```

  Expected: `1`.

- [ ] **AC-003 (src missing)**: verify exit 2 on bogus src:

  ```bash
  ~/.claude/skills/ship-workflow/lib/spec-mirror.sh /nonexistent/foo.md /tmp/bar.md
  echo "exit: $?"
  ```

  Expected: `ERROR: source spec not found: ...` + `exit: 2`.

- [ ] **AC-007 (--discard cleanup)**: from main repo, run:

  ```
  /ship-next --discard R-XXX
  ```

  Then verify:

  ```bash
  ls "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-"*.md 2>&1
  ```

  Expected: "No such file or directory" or empty.

- [ ] **AC-009 (regression)**: re-run full bats:

  ```bash
  cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow && bats tests/
  ```

  Expected: 98/98 ok.

- [ ] **AC-010 (ship-init unchanged)**: read `commands/ship-init.md` and confirm no Specs/ pre-create step was added:

  ```bash
  grep -i "specs" /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow/commands/ship-init.md
  ```

  Expected: zero matches related to vault Specs/ scaffolding.

### Step 4.4: Test P3 resume re-mirror (optional)

To verify the resume re-mirror behavior (Task 3 step 3.2):

- [ ] After a successful /ship-next R-XXX, manually edit the repo spec:

  ```bash
  echo "## §99 Late-added section" >> /Users/leric/Desktop/code/ai-eden-service/docs/specs/R-XXX-smoke-test-spec-vault-mirror.md
  ```

- [ ] Re-invoke `/ship-next R-XXX` (resume mode):

- [ ] Verify vault file now contains the new section (proves re-mirror happened):

  ```bash
  grep "## §99 Late-added section" "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Specs/R-XXX-smoke-test-spec-vault-mirror.md"
  ```

  Expected: one match.

### Step 4.5: AC checklist final report

Print summary:

```
✓ AC-001  spec-mirror.sh writes destination atomically (verified by AC-005 + Task 1 tests)
✓ AC-002  idempotent on repeat invocation
✓ AC-003  exits 2 if src missing
✓ AC-004  mkdir -p creates parent (verified by AC-008)
✓ AC-005  spec at both repo and vault paths with identical body
✓ AC-006  vault frontmatter has mirror-source: key
✓ AC-007  --discard removes vault Specs/R-NNN-*.md
✓ AC-008  vault Specs/ auto-created on first /ship-next
✓ AC-009  98/98 bats green
✓ AC-010  /ship-init unchanged (no Specs/ pre-create)
```

### Step 4.6: Cleanup smoke artifacts

After AC verification:

- [ ] Delete the smoke R-XXX:
  - Remove the ROADMAP row (or move to Done)
  - Remove the brainstorm/spec/plan files in ai-eden-service
  - The squashed commit on dev may need to be `git revert`ed if it was meaningless
  - Vault Specs/R-XXX-*.md already cleaned by AC-007 step

No code commit needed for Task 4 (acceptance only).

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 Vault path convention | Task 2 (computes path inline) + Task 4 (verifies) |
| §3.2 Dual-write at /ship-next P3 | Task 2 |
| §3.3 `--discard` cleanup | Task 3 step 3.1 |
| §3.4 `mirror-source:` frontmatter | Task 1 (awk implementation) + Task 4 AC-006 |
| §3.5 Edge cases (resume, abort, hand-edit) | Task 3 step 3.2 (resume re-mirror) + accepted per spec (hand-edit stale-window) |
| §4.1 New files (spec-mirror.sh + bats) | Task 1 |
| §4.2 Modified files (ship-next.md) | Tasks 2, 3 |
| §4.3 Unchanged (sync.sh, etc.) | None — verified by not modifying them |
| §4.4 `spec-mirror.sh` interface | Task 1 (matches exactly) |
| §6 AC-001..AC-010 | Tasks 1, 2, 3, 4 (AC-001..004 → Task 1; AC-005..008 → Task 2+3+4; AC-009..010 → Task 4) |
| §7.2-Q1 P3 resume re-mirror | Task 3 step 3.2 (resolved: yes, re-mirror) |

All sections covered. §7.2-Q2..Q4 remain explicitly deferred per spec.

**2. Placeholder scan:**
- No `TBD`, `TODO`, `fill in later`, `similar to Task N`.
- All bash, bats, and markdown code blocks are complete and runnable.
- Every Edit/Write step shows exact content.

**3. Type consistency:**
- `spec-mirror.sh <src> <dst>` signature consistent across Task 1 (definition), Task 2 (P3 call), Task 3 (resume call), Task 4 (smoke).
- `VAULT_SPECS_DIR` variable name + computation (`$(airos-binding.sh project_path)/Specs`) identical in Tasks 2, 3, 4.
- Exit codes (0 success / 1 fewer args / 2 src missing) consistent between Task 1 implementation and tests.
- Idempotency invariant ("only 1 mirror-source: line") tested in Task 1 step 1.1 + verified in Task 4 AC-002.
- The `mirror-source: <src>` key value uses the raw `<src>` path passed in — Task 1 awk does `"mirror-source: " src` with no transformation; Task 2 P3 call passes `docs/specs/${ID}-${SLUG}.md` (relative) so vault frontmatter shows the repo-relative path. Consistent.

All consistent.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-22-spec-vault-mirror-implementation.md`. Three execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks. Task 1 is TDD-ideal for disposable subagent; Tasks 2-3 are mechanical markdown edits to the same file (sequential dependency); Task 4 is interactive smoke (I drive here).

**2. Inline Execution** — sequential in this session with checkpoints. Live-review each Edit.

**3. Codex `/run-plan`** — autonomous background. Tasks 1-3 are full execution (file system + repo only — no `~/.claude/` to dodge). Task 4 (interactive smoke) is the only defer. Best fit for a small plan like this (~1.5h, no skill-tool blockers).

Which approach?
