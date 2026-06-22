---
name: ship-next
description: Pick next R-NNN and ship end-to-end (worktree → brainstorm → spec → plan → execute → review → squash merge)
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
- `--auto:yes` (alias `--auto`) — **fire-and-forget mode**. Runs the entire 9-phase cycle without interactive prompts: brainstorm clarifying questions auto-pick option 1; spec/plan review gates auto-approve; executor auto = subagent; review loop iterates fix-plans automatically up to cap=3; major findings auto-forwarded to `IDEA-NNN` follow-ups. On cap=3 failure: abort with worktree retained + Discord push. Requires the ROADMAP row to have a `↳ done when:` annotation. Records every auto decision to `docs/.ship-auto-decisions.md` (gitignored) in the worktree.

  **Mutually exclusive with `--discard`** (deletion is destructive; auto must never delete).

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
