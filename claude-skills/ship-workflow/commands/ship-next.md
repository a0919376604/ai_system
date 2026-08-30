---
name: ship-next
description: Pick next R-NNN and ship end-to-end via worktree + strict review + squash merge
argument-hint: "[R-NNN] | --adhoc <desc> | --discard R-NNN | --resume R-NNN | --auto:yes"
discord-visible: true
---

# /ship-next

You are taking a ROADMAP row from "Now" all the way to a squashed commit on the original branch. The work happens in an isolated sibling worktree; an external code-review-skill gates the merge.

## Arguments

- `R-NNN[.M]` — explicit row. If omitted, auto-pick top of "Now" by existing rank logic (epics skipped; children ascending by `.M`).
- `--adhoc <description>` — same as today: allocate next R-NNN, insert into "Now", continue.
- `--discard R-NNN` — force-remove the worktree + branch for this R-NNN, exit. Use when brainstorm went off the rails.
- `--resume R-NNN` — explicit "I know the worktree exists, just continue". Equivalent to invoking `/ship-next R-NNN` and answering `Y` to the resume prompt.
- `--auto:yes` (alias `--auto`) — **fire-and-forget mode**. Runs the entire 9-phase cycle without interactive prompts: brainstorm clarifying questions auto-pick option 1; spec/plan review gates auto-approve; executor auto = subagent; review loop iterates fix-plans automatically up to cap=3; major findings auto-forwarded to `IDEA-NNN` follow-ups. On cap=3 failure: abort with worktree retained + Discord push. Requires the ROADMAP row to have a `↳ done when:` annotation. Records every auto decision to `.claude/.ship-auto-decisions.md` (gitignored) in the worktree.

  **Mutually exclusive with `--discard`** (deletion is destructive; auto must never delete).

## Pre-flight invariants

- This command must run from the **main repo root** (cwd = repo). It does NOT have a `cwd-guard.sh` check at the top, because `/ship-next` itself is what cd's into the worktree. (But it DOES verify that the worktree-target path is not the cwd already — see Phase 1 step 4.)
- `~/.claude/skills/code-review-skill/SKILL.md` must exist by Phase 6 or the command halts with an install hint.

## Phase 1 — Pre-flight + R-NNN resolution

0. **Parse all args FIRST** (before any destructive operation, so mutex checks run before discard):

   ```bash
   # Initialize flag state
   AUTO=0
   MODE=""              # one of: discard | adhoc | resume | "" (positional)
   TARGET=""            # ID for discard/resume, or description for adhoc
   POSITIONAL=""        # R-NNN if user typed `/ship-next R-NNN` plain

   # Walk args once, consuming flags
   while [ $# -gt 0 ]; do
     case "$1" in
       --auto:yes|--auto)
         AUTO=1
         shift
         ;;
       --discard)
         MODE="discard"
         TARGET="${2:-}"
         shift 2 || shift  # robust against missing arg
         ;;
       --adhoc)
         MODE="adhoc"
         TARGET="${2:-}"
         shift 2 || shift
         ;;
       --resume)
         MODE="resume"
         TARGET="${2:-}"
         shift 2 || shift
         ;;
       --*)
         echo "ERROR: unknown flag: $1" >&2
         exit 2
         ;;
       *)
         # First non-flag positional = R-NNN
         [ -z "$POSITIONAL" ] && POSITIONAL="$1"
         shift
         ;;
     esac
   done

   # Mutex: --discard + --auto are incompatible (auto must never delete)
   if [ "$MODE" = "discard" ] && [ "$AUTO" = "1" ]; then
     echo "ERROR: --auto:yes and --discard are mutually exclusive." >&2
     echo "       --discard is destructive — never auto." >&2
     exit 2
   fi

   # Required-arg checks for modes that take a value
   if [ "$MODE" = "discard" ] && [ -z "$TARGET" ]; then
     echo "ERROR: --discard requires an R-NNN argument." >&2
     exit 2
   fi
   if [ "$MODE" = "resume" ] && [ -z "$TARGET" ]; then
     echo "ERROR: --resume requires an R-NNN argument." >&2
     exit 2
   fi
   if [ "$MODE" = "adhoc" ] && [ -z "$TARGET" ]; then
     echo "ERROR: --adhoc requires a description argument." >&2
     exit 2
   fi

   if [ "$AUTO" = "1" ]; then
     echo "🤖 Auto:yes mode — no interactive prompts. Decision log: <worktree>/.claude/.ship-auto-decisions.md"
   fi
   ```

1. **Handle `--discard`** (now safely after mutex check):

   ```bash
   if [ "$MODE" = "discard" ]; then
     ID="$TARGET"
     # Quote repo path computations against spaces
     REPO="$(pwd)"
     WT_ROOT="$(dirname "$REPO")/$(basename "$REPO")-worktrees"
     # Locate worktree by ID prefix (slug may vary)
     WT=$(ls -d "$WT_ROOT/${ID}-"* 2>/dev/null | head -1)
     if [ -n "$WT" ]; then
       BRANCH=$(cd "$WT" && git branch --show-current)
       git worktree remove --force "$WT"
       git branch -D "$BRANCH" 2>/dev/null || true
       # Also clean vault mirror (no orphan)
       VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
       rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
       echo "Discarded worktree at $WT and branch $BRANCH"
     else
       echo "No worktree found for $ID"
     fi
     exit 0
   fi
   ```

1.6. **Self-heal repo root `.gitignore`** (auto mode only, idempotent):

    The decision log lives at `<worktree>/.claude/.ship-auto-decisions.md` (under `.claude/` so the existing `.claude/.gitignore` rule covers it):
    ```bash
    if [ "$AUTO" = "1" ] && [ -f .claude/.gitignore ]; then
      if ! grep -qF ".ship-auto-decisions.md" .claude/.gitignore; then
        echo ".ship-auto-decisions.md" >> .claude/.gitignore
        # Note: this edit happens in main repo BEFORE Phase 2 opens the worktree.
        # Worktree inherits the gitignore.
      fi
    fi
    ```

2. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

3. **Handle `--adhoc`** (uses pre-parsed `TARGET` as description):
   ```bash
   if [ "$MODE" = "adhoc" ]; then
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
     ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
     ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "$TARGET" --adhoc
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
     # Continue with $ID, slug derived from "$TARGET"
   fi
   ```

4. **Resolve R-NNN:**
   - If `MODE == "resume"`: `ID="$TARGET"`. (Skip auto-pick; user explicitly named the row.)
   - Elif `MODE == "adhoc"`: `ID` already set by Step 3.
   - Elif `$POSITIONAL` is set: `ID="$POSITIONAL"`.
   - Else: read `docs/product/ROADMAP.md` "## 🔥 Now" section; rank by existing logic (epics skipped, children ascending by .M, impact/dependency tie-breakers). Pick top.

   **Critical:** never assign `ID="$1"` directly — that pattern captures flags like `--auto:yes` as the row ID. Always use the parsed variables.

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
   - If `$WORKTREE` exists:
     - **In auto mode** (`AUTO=1`): auto-continue. Log:
       ```bash
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P1" "existing worktree detected — auto-continuing" "branch=$BRANCH"
       ```
       Jump to Phase 3.
     - **Interactive**: prompt `"Continue ${ID} in existing worktree? [Y/n/discard]"`.
       - `Y` (or `--resume` was passed): jump to Phase 3, but auto-skip phases already done (detect via commit count + file presence — see Phase 3 step 0).
       - `discard`: `git worktree remove --force "$WORKTREE"; git branch -D "$BRANCH"`, fall through to Phase 2.
       - `n`: exit 0.

## Phase 1.5 — UA drift check (auto-detect, silent no-op if UA absent)

```bash
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/ua-integration.sh
DRIFT_WARN=$(ua_check_drift)
[ -n "$DRIFT_WARN" ] && echo "$DRIFT_WARN"
```

When UA plugin + repo KG are both present and the KG's baseline commit differs from HEAD by any project files, this prints a warning block. It does NOT gate; the phase proceeds. See `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.

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

0. **UA pre-brainstorm context (auto-detect, silent if UA absent):**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ua-integration.sh
   if ua_check_installed; then
     mkdir -p .ship
     ua_get_pre_brainstorm_context "$RID" > .ship/ua-context.md
     [ -s .ship/ua-context.md ] && echo "UA pre-context saved to .ship/ua-context.md — Read this before brainstorm dialog."
   fi
   ```

   When the brainstorming skill kicks off, it should Read `.ship/ua-context.md` (if present) as part of its opening context — this gives the design dialog concrete grounding in how the target files actually connect.

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

1. **Proposal check** (same as existing /ship-next pre-step): look for `<vault>/Proposals/*-${ID}-*-proposal.md`. If `status: accepted`, load §1-§7 as brainstorm context.

2. **Invoke `superpowers:brainstorming`** with context: spec target `docs/specs/${ID}-${SLUG}.md`, project `<project_name>`, proposal context (if loaded).

   **In auto mode (`AUTO=1`):** the brainstorming skill is still invoked, but **every clarifying question is auto-answered by picking option 1**. The brainstorming skill convention is to lead with the recommended option, so option 1 = recommended.

   After each auto-answered question, log:
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "brainstorm Q${N} auto-picked option 1" "<question summary truncated to 80 chars>"
   ```

   When the brainstorming skill reaches the "Review spec first?" gate, auto-approve:
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "spec review → auto-approved"
   ```

3. **Verify outputs**: `docs/brainstorms/${ID}-${SLUG}.md` + `docs/specs/${ID}-${SLUG}.md` exist.

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

4. **Commit:**
   ```bash
   git add docs/brainstorms/${ID}-${SLUG}.md docs/specs/${ID}-${SLUG}.md
   git commit -m "brainstorm+spec: ${ID} ${SLUG}"
   ```

## Phase 4 — Writing plans

1. **Invoke `superpowers:writing-plans`** with the spec from Phase 3.

   **In auto mode (`AUTO=1`):** the writing-plans skill's "Review plan first?" gate is auto-approved.
   ```bash
   ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P4" "plan review → auto-approved"
   ```

2. **Verify output**: `docs/plans/${ID}-${SLUG}.md` exists.

3. **Commit:**
   ```bash
   git add docs/plans/${ID}-${SLUG}.md
   git commit -m "plan: ${ID} ${SLUG}"
   ```

## Phase 5 — Choose executor + run

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

2. **Record executor choice** to a stash file in the worktree (used by Phase 6 fix-plan re-invoke):
   ```bash
   echo "$EXECUTOR_CHOICE" > .claude/.ship-executor
   # In auto mode, the log entry from step 5.4 already captured the choice.
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

3. **If still blocking after 3 attempts:**

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

   - **Interactive (`AUTO=0`):** pause and prompt:
     ```
     3 review attempts didn't clear blockers. Options:
       [Y] Auto-fix one more cycle (loop continues)
       [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
       [abort] Discard everything — /ship-next --discard ${ID}
     ```

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

4. **Auto-mode success notification** (only if `AUTO=1`):

   Build the success message body:
   ```bash
   if [ "$AUTO" = "1" ]; then
     SUMMARY="✅ ${ID} ${DESCRIPTION} shipped (squash ${MERGE_SHA})
   • blocking: 0 ✓
   • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
   • minor: ${MINOR_COUNT}
   • praise: ${PRAISE_COUNT}
   • decisions log: ${WORKTREE}/.claude/.ship-auto-decisions.md (kept in worktree pre-cleanup; copy if you want post-mortem)"

     # Channel routing (per /run-plan skill convention):
     # - Discord session (incoming message tag has channel source="discord"): use Discord reply
     # - Else: use PushNotification
     # - Always also fire osascript + bell for local presence

     # Scan conversation context for a discord chat_id (Claude does this at invocation time).
     # If a chat_id is in scope: call Discord reply with $SUMMARY, chat_id, files=[$WORKTREE/.claude/.ship-auto-decisions.md]
     # Else: call PushNotification subject="/ship-next ${ID} shipped" body=$SUMMARY

     # Local OS notification + bell — fires regardless of channel
     osascript -e "display notification \"${ID} shipped: squash ${MERGE_SHA}\" with title \"/ship-next done\" sound name \"Glass\"" 2>/dev/null || true
     printf '\a' >&2
   fi
   ```

## Failure modes

- **Worktree create fails (dirty index)** → abort, hint `git stash; /ship-next ${ID}`
- **Brainstorm abandoned mid-flow** → user Ctrl-C; worktree remains. Resume via `/ship-next ${ID}` or destroy via `/ship-next --discard ${ID}`.
- **Executor fails mid-run** → log to plan's `## Execution log` (existing pattern); worktree remains.
- **code-review-skill not installed** → ERROR with install hint (Phase 6 step 1).
- **Merge conflict to original branch** → shouldn't happen (worktree forked from $ORIG_BRANCH and squash merges onto same fork point). If it does, abort merge, worktree intact, hint user to rebase.
- **Cleanup fails** → print worktree path, instruction to remove manually.
