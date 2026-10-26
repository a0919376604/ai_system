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
- `--adhoc <description>` — allocate next R-NNN, insert into "Now", continue.
- `--discard R-NNN` — force-remove the worktree + branch for this R-NNN, exit.
- `--resume R-NNN` — explicit "I know the worktree exists, just continue". Equivalent to invoking `/ship-next R-NNN` and answering `Y` to the resume prompt.
- `--auto:yes` (alias `--auto`) — **fire-and-forget mode**. Runs the entire 9-phase cycle without interactive prompts: brainstorm clarifying questions auto-pick their recommended answer; spec/plan review gates auto-approve; executor auto = codex /run-plan (subagent-driven if the `codex` CLI is missing, never inline); review loop iterates fix-plans automatically up to cap=3; major findings auto-forwarded to `IDEA-NNN` follow-ups. On cap=3 failure: abort with worktree retained + Discord push. Requires the ROADMAP row to have a `↳ done when:` annotation. Records every auto decision to `.claude/.ship-auto-decisions.md` (gitignored) in the worktree.
  **Mutually exclusive with `--discard`** (deletion is destructive; auto must never delete).

## Pre-flight invariants

- Run from the **main repo root** (cwd = repo). Do not invoke from the target worktree.
- `~/.claude/skills/code-review-skill/SKILL.md` must exist by Phase 6 or the command halts with an install hint.

## Phase 1 — Pre-flight + R-NNN resolution

0. **Parse all args FIRST** (before any destructive operation, so mutex checks run before discard):
   Parse the arguments yourself — they arrive as text, not as shell positionals. `--auto:yes` or `--auto` anywhere in the arguments sets `AUTO=1`. `--discard <R-NNN>`, `--adhoc <description>` and `--resume <R-NNN>` set `MODE` to discard / adhoc / resume and `TARGET` to the value after the flag (an adhoc description runs to the end of the arguments, minus a trailing `--auto` / `--auto:yes`). Any other `--flag` is an error (exit 2). The first bare token is `POSITIONAL` (an R-NNN). Write the values you parsed as assignments at the top of this block, then run it:
   ```bash
   AUTO=${AUTO:-0}; MODE=${MODE:-}; TARGET=${TARGET:-}; POSITIONAL=${POSITIONAL:-}
   if [ "$MODE" = "discard" ] && [ "$AUTO" = "1" ]; then
     echo "ERROR: --auto:yes and --discard are mutually exclusive." >&2
     echo "       --discard is destructive — never auto." >&2
     exit 2
   fi
   if [ "$MODE" = "discard" ] && [ -z "$TARGET" ]; then echo "ERROR: --discard requires an R-NNN argument." >&2; exit 2; fi
   if [ "$MODE" = "resume" ] && [ -z "$TARGET" ]; then echo "ERROR: --resume requires an R-NNN argument." >&2; exit 2; fi
   if [ "$MODE" = "adhoc" ] && [ -z "$TARGET" ]; then echo "ERROR: --adhoc requires a description argument." >&2; exit 2; fi
   if [ "$AUTO" = "1" ]; then
     echo "🤖 Auto:yes mode — no interactive prompts. Decision log: <worktree>/.claude/.ship-auto-decisions.md"
   fi
   ```
0.5. **Which ship-workflow is live?** Warn if the live checkout behind `~/.claude/skills/ship-workflow` is dirty or off `main`:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/live-checkout.sh && live_checkout_warning
   ```
1. **Handle `--discard`** (now safely after mutex check):
   ```bash
   if [ "$MODE" = "discard" ]; then
     ID="$TARGET"; REPO="$(pwd)"
     WT_ROOT="$(dirname "$REPO")/$(basename "$REPO")-worktrees"
     WT=$(ls -d "$WT_ROOT/${ID}-"* 2>/dev/null | head -1)
     if [ -n "$WT" ]; then
       BRANCH=$(cd "$WT" && git branch --show-current)
       git worktree remove --force "$WT"
       git branch -D "$BRANCH" 2>/dev/null || true
       VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
       rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
       echo "Discarded worktree at $WT and branch $BRANCH"
     else echo "No worktree found for $ID"; fi
     # The Roadmap 檢視 status file goes even when the worktree is already gone.
     case "$ID" in
       R-*[!A-Za-z0-9.-]*) ;;
       R-[0-9]*) PROJ_DIR=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path 2>/dev/null) \
                   && rm -f "$PROJ_DIR/ship-status/${ID}.json" ;;
     esac
     exit 0
   fi
   ```
1.6. **Self-heal repo root `.gitignore`** (auto mode only, idempotent):
    The decision log lives at `<worktree>/.claude/.ship-auto-decisions.md` (under `.claude/` so the existing `.claude/.gitignore` rule covers it):
    ```bash
    if [ "$AUTO" = "1" ] && [ -f .claude/.gitignore ]; then
      if ! grep -qF ".ship-auto-decisions.md" .claude/.gitignore; then
        echo ".ship-auto-decisions.md" >> .claude/.gitignore
      fi
    fi
    ```
2. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```
3. **Handle `--adhoc`** (uses pre-parsed `TARGET` as description):
   ```bash
   SUMMARY_ZH="…"   # one zh-TW sentence for a person: what changes and for whom, no file names
   if [ "$MODE" = "adhoc" ]; then
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
     ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
     ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "$TARGET" --adhoc --summary "$SUMMARY_ZH"
     ~/.claude/skills/ship-workflow/lib/sync.sh --force
   fi
   ```
4. **Resolve R-NNN:**
   - If `MODE == "resume"`: `ID="$TARGET"`. (Skip auto-pick; user explicitly named the row.)
   - Elif `MODE == "adhoc"`: `ID` already set by Step 3.
   - Elif `$POSITIONAL` is set: `ID="$POSITIONAL"`.
   - Else: read `docs/product/ROADMAP.md` "## 🔥 Now" section; rank by existing logic (epics skipped, children ascending by .M, impact/dependency tie-breakers). Pick top.
   **Critical:** never take `ID` from the first raw argument — that pattern captures flags like `--auto:yes` as the row ID. Always use the parsed variables.
4.5. **Auto pre-flight gate** (only in `--auto:yes` mode):
    ```bash
    if [ "$AUTO" = "1" ]; then
      ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
      ROW=$(grep -A2 "\*\*${ID}\*\*" "$ROADMAP_PATH" || true)
      DONE_WHEN=$(echo "$ROW" | grep "↳ done when:" || true)
      if [ -z "$DONE_WHEN" ]; then
        echo "ERROR: --auto:yes refused — R-NNN $ID has no ↳ done when: annotation." >&2
        echo "       fire-and-forget mode requires an explicit success criterion." >&2
        echo "       Add a ↳ done when: <criterion> line under the row in ROADMAP.md," >&2
        echo "       then re-invoke /ship-next $ID --auto:yes." >&2
        exit 2
      fi
    fi
    ```
5. **Derive slug and DESCRIPTION.** `DESCRIPTION` is the ROADMAP row text after the `**R-NNN**` part, without trailing `· key=value` annotations; it titles the landed commit or review. Slug: from that description, kebab-case English slug 3-5 words, leading imperative verb when possible. Example: "Wire SceneEngine into dialogue.py..." → `wire-scene-engine`.
6. **Compute worktree path:**
   ```bash
   REPO=$(pwd)
   REPO_NAME=$(basename "$REPO")
   PARENT=$(dirname "$REPO")
   WORKTREE="$PARENT/${REPO_NAME}-worktrees/${ID}-${SLUG}"
   BRANCH="ship/${ID}-${SLUG}"
   ORIG_BRANCH=$(git branch --show-current)
   DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
   [ -n "$DEFAULT_BRANCH" ] && [ "$ORIG_BRANCH" != "$DEFAULT_BRANCH" ] && echo "WARN: this ship will land on '$ORIG_BRANCH', not '$DEFAULT_BRANCH' — fast-forward $DEFAULT_BRANCH yourself afterwards" >&2 || true
   ```
7. **Detect existing worktree:**
   - If `$WORKTREE` exists:
     - **In auto mode** (`AUTO=1`): auto-continue. Log:
       Run `~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P1" "existing worktree detected — auto-continuing" "branch=$BRANCH"`.
       Refresh state below, then jump to Phase 3.
     - **Interactive**: prompt `"Continue ${ID} in existing worktree? [Y/n/discard]"`.
       - `Y` (or `--resume` was passed): refresh state below, then jump to Phase 3, but auto-skip phases already done (detect via commit count + file presence — see Phase 3 step 0).
       - `discard`: `git worktree remove --force "$WORKTREE"; git branch -D "$BRANCH"`, fall through to Phase 2.
       - `n`: exit 0.
   On either accepted continue path, refresh resolved inputs; retain accumulated phase results:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_set "$WORKTREE" ID "$ID"; sn_state_set "$WORKTREE" SLUG "$SLUG"; sn_state_set "$WORKTREE" WORKTREE "$WORKTREE"
   sn_state_set "$WORKTREE" BRANCH "$BRANCH"; sn_state_set "$WORKTREE" ORIG_BRANCH "$ORIG_BRANCH"; sn_state_set "$WORKTREE" AUTO "$AUTO"
   sn_state_set "$WORKTREE" REPO "$REPO"; if [ -n "$DESCRIPTION" ]; then sn_state_set "$WORKTREE" DESCRIPTION "$DESCRIPTION"; fi
   ```

## Phase 2 — Open worktree

1. **Invoke `superpowers:using-git-worktrees`** with parameters:
   - `path=$WORKTREE`
   - `branch=$BRANCH`
   - `base=$ORIG_BRANCH`
   Persist the resolved values immediately after the worktree is created:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_set "$WORKTREE" ID "$ID"
   sn_state_set "$WORKTREE" SLUG "$SLUG"
   sn_state_set "$WORKTREE" WORKTREE "$WORKTREE"
   sn_state_set "$WORKTREE" BRANCH "$BRANCH"
   sn_state_set "$WORKTREE" ORIG_BRANCH "$ORIG_BRANCH"
   sn_state_set "$WORKTREE" AUTO "$AUTO"
   sn_state_set "$WORKTREE" REPO "$REPO"
   if [ -n "$DESCRIPTION" ]; then sn_state_set "$WORKTREE" DESCRIPTION "$DESCRIPTION"; fi
   sn_status "$WORKTREE" brainstorm   # R-013: the phase the Roadmap 檢視 plugin shows
   ```
2. **cd into the worktree.** Tell the user explicitly:
   ```
   📁 cd'd into ship/${ID}-${SLUG} worktree at ${WORKTREE}.
      All subsequent commands run there until merge.
   ```

## Phase 3 — Brainstorm

0. **CONTEXT.md (project vocabulary):**
   ```bash
   source ~/.claude/skills/ship-workflow/lib/context-md.sh
   if [ -n "$(context_md_path)" ]; then
     echo "CONTEXT.md present — Read it before brainstorm dialog."
   fi
   ```
   Read `CONTEXT.md` when present and use its project vocabulary.
   **Past learnings:** look up relevant prior work before the dialog.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/learnings-lookup.sh
   LEARN_CAP=3
   LEARN_TERMS=$(learnings_terms "$SLUG")   # words of 4+ chars minus generic verbs
   LEARN_HITS=$(learnings_match $LEARN_TERMS)
   LEARN_N=$(printf '%s' "$LEARN_HITS" | grep -c . || true)
   [ -n "$LEARN_N" ] || LEARN_N=0
   if [ "$LEARN_N" -eq 0 ]; then
     echo "learnings: no prior work matched ${LEARN_TERMS}"
   elif [ "$LEARN_N" -le "$LEARN_CAP" ]; then
     echo "learnings: $LEARN_N match(es) — Read each before the dialog:"
     printf '%s\n' "$LEARN_HITS"
   else
     echo "learnings: $LEARN_N matches — too many to open. Paths only:"
     printf '%s\n' "$LEARN_HITS" | sed 's|^|  |'
   fi
   ```
   At or under the cap, Read each hit before the dialog. Over the cap, inspect filenames and open at most one clearly relevant learning.
0. **Resume detection.** Check what's already done in the worktree:
   - `ls docs/specs/${ID}-${SLUG}.md` exists → **first re-mirror spec to vault** (catch any post-write edits), then skip to Phase 4 (plan stage):
     ```bash
     VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
     ~/.claude/skills/ship-workflow/lib/spec-mirror.sh docs/specs/${ID}-${SLUG}.md "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
     ```
   - `ls docs/plans/${ID}-${SLUG}.md` exists → skip to Phase 5 (executor).
   - `git log --oneline ${ORIG_BRANCH}..HEAD | wc -l` > 2 → executor has committed; skip to Phase 6 (review).
1. **Invoke `superpowers:brainstorming`** with context: spec target `docs/specs/${ID}-${SLUG}.md`, project `<project_name>`.
   Require `## Seams`: a table (Seam | Interface | Guaranteed behavior) for every boundary introduced or changed. Tests may assert only declared seam behavior. Pass this in invocation context; do not modify a `superpowers` file.
   Require `## Decisions`: operator decisions and reasons, with your own calls marked as yours. Do not create a separate brainstorm file; `/ship-compound` copies these into the learning and mirrors the spec before removing it.
   **Require grilling rounds:** Each round asks every question whose prerequisites are settled, numbered. Each question carries your recommended answer and is worded so "yes" accepts it. A question that depends on one still open in this round waits for the next round. Facts are yours to find: dispatch a sub-agent rather than asking the operator anything you could look up. Only decisions go to the operator. This invocation context overrides the skill's one-question-per-message habit; do not modify any superpowers file.
   **In auto mode (`AUTO=1`):** the brainstorming skill is still invoked, but **every clarifying question is auto-answered with its recommended answer**.
   After each auto-answered question, log:
   Run `~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "brainstorm Q${N} auto-picked recommended answer" "<question → answer, truncated to 80 chars>"`.
   When the brainstorming skill reaches the "Review spec first?" gate, auto-approve:
   Run `~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "spec review → auto-approved"`.
2. **Verify output**: `docs/specs/${ID}-${SLUG}.md` exists and has `## Decisions`.
2.5. **Dual-write spec to vault** (Obsidian visibility):
    ```bash
    VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
    ~/.claude/skills/ship-workflow/lib/spec-mirror.sh docs/specs/${ID}-${SLUG}.md "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
    ```
    Do not commit the vault file. The repo spec is canonical; the vault is a one-way mirror.
    **Auto-mode log:**
    ```bash
    if [ "$AUTO" = "1" ]; then
      ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "spec mirrored to vault" "$VAULT_SPECS_DIR/${ID}-${SLUG}.md"
    fi
    ```
3. **Commit:**
   ```bash
   git add docs/specs/${ID}-${SLUG}.md
   git commit -m "spec: ${ID} ${SLUG}"
   ```

## Phase 4 — Writing plans

**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" plan`.
**Small-change lane.** When the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" build`, then implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, then go to Phase 6. Log the choice in auto mode. Set `EXECUTOR_CHOICE=2` and record it via Phase 5 step 2 and render the rule files via step 2.5 before implementing, so review fixes retain the inline executor.
**Plan-authoring guidance:**
- Verification/acceptance steps MUST run scoped pytest, not the full suite: list affected files or relevant module directories, e.g. `pytest tests/domain/test_foo.py tests/api/test_bar.py -q`. Missing environment credentials can leave a broad run hanging.
- Reader-untouched grep guards MUST use `git diff <base>...HEAD -- <paths>`: three-dot excludes unrelated base-branch commits.
0. **Seam gate.**
   ```bash
   SPEC_FILE="docs/specs/${ID}-${SLUG}.md"
   if ! grep -qF '## Seams' "$SPEC_FILE"; then
     if [ "$AUTO" = "1" ]; then
       echo "ERROR: --auto:yes refused — spec has no \`## Seams\` section." >&2
       echo "       Add it to $SPEC_FILE, then re-invoke /ship-next ${ID} --auto:yes." >&2
       exit 2
     else
       echo "WARN: spec has no \`## Seams\` — tests will have no declared boundary to attach to." >&2
     fi
   fi
   ```
1. **Invoke `superpowers:writing-plans`** with the spec from Phase 3.
   **In auto mode (`AUTO=1`):** the writing-plans skill's "Review plan first?" gate is auto-approved.
   Run `~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P4" "plan review → auto-approved"`.
2. **Verify output**: `docs/plans/${ID}-${SLUG}.md` exists.
3. **Commit:**
   ```bash
   git add docs/plans/${ID}-${SLUG}.md
   git commit -m "plan: ${ID} ${SLUG}"
   ```

## Phase 5 — Choose executor + run

**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" build`.
1. **Choose executor.**
   - **In auto mode (`AUTO=1`):** auto-pick `3` (codex /run-plan). Fall back to `1` only when the `codex` CLI is missing. Do **not** downgrade to `2` (inline) on plan-size or cost grounds.
     ```bash
     if command -v codex >/dev/null 2>&1; then
       EXECUTOR_CHOICE=3
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P5" "executor → auto-picked: 3 (codex /run-plan)"
     else
       EXECUTOR_CHOICE=1
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P5" "executor → auto-picked: 1 (subagent-driven)" "codex CLI not found"
     fi
     ```
   - **Interactive:** prompt
     ```
     Plan ready at docs/plans/${ID}-${SLUG}.md. Choose executor:
       1. Subagent-driven — fresh subagent per task, review between
       2. Inline executing-plans — sequential in this session, batch with checkpoints
       3. Codex /run-plan (recommended) — autonomous in background
     ```
2. **Record executor choice** to a stash file in the worktree (used by Phase 6 fix-plan re-invoke):
   ```bash
   echo "$EXECUTOR_CHOICE" > .claude/.ship-executor
   ```
2.5. **Render executor rule files.**
   ```bash
   mkdir -p .ship
   source ~/.claude/skills/ship-workflow/lib/tdd-rules.sh
   tdd_rules_render "${ID}" "docs/specs/${ID}-${SLUG}.md" > .ship/tdd-rules.md
   source ~/.claude/skills/ship-workflow/lib/ponytail-integration.sh
   ponytail_render_rules .ship/ponytail-rules.md
   if ponytail_check_installed; then
     PONYTAIL_STATUS="ladder rendered"
   else
     PONYTAIL_STATUS="not installed — no ladder enforced this run"
     echo "ponytail: not installed — no ladder enforced this run" >&2
   fi
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_set "$WORKTREE" PONYTAIL_STATUS "$PONYTAIL_STATUS"
   ```
   Require executors to read both rendered files; subagent-start hooks cannot inject the ponytail ruleset.
3. **Invoke the chosen sub-skill.**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → the supervise loop in step 4 below.
4. **Executor 3 only — supervise the codex run.**
   `/run-plan` detaches codex; supervise until it finishes. Preserve the slot derivation, including its trailing underscore, to match `/run-plan`.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/codex-verdict.sh
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
   source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
   CODEX_ATTEMPT_CAP=3
   PLAN="docs/plans/${ID}-${SLUG}.md"
   SLOT=$(basename "$PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')
   if codex_state_matches "$WORKTREE" "$PLAN"; then
     CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
     if codex_state_alive "$WORKTREE"; then
       echo "codex is still running for $PLAN — attaching, not relaunching."
     fi
   else
     CODEX_ATTEMPT=0
   fi
   ```
   **Pid authority:** `/run-plan` owns the `/tmp` pid file; `.ship/codex.pid` is the durable mirror checked by `codex_state_alive`. Write state at launch, before a run can block.
   **Launch** with `/run-plan "$PLAN"`, then record the run so a later re-entry can tell a live run from a dead one:
   ```bash
   mkdir -p "$WORKTREE/.ship"
   cp "/tmp/run-plan-codex-${SLOT}.pid" "$WORKTREE/.ship/codex.pid" 2>/dev/null || true
   codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" running "n/a" "n/a"
   ```
   Carry all five hardening items in the prompt:
   - **Scope override.** If the plan targets a skill directory, explicitly authorize it despite `/run-plan`'s default exclusion of `.claude/skills/`.
   - **`--auto:yes` requirement.** Every plan step invoking `/ship-next` must include it; codex cannot answer interactive prompts.
   - **Engineering vocabulary.** Describe input validation and other engineering checks without offensive-security phrasing.
   - **Resume context.** Name committed tasks, the starting task, and settled conclusions that must not be re-litigated.
   - **Round history.** Include `.ship/codex-rounds.md`.
   **When codex exits**, classify before judging:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   sn_codex_after_exit "$WORKTREE" "$PLAN" "$SLOT"
   ```
   Then route on `$CODEX_ROUTE`:
   - **`continue`** (verdict `done` / `done_with_concerns`) → the helper has recorded the round and marked the run finished; continue to Phase 6.
   - **`stop_infra`** (verdict `infra`) → `sn_codex_after_exit` has already recorded the ship as `blocked` with `$CODEX_REASON`. STOP and notify using Phase 9 routing with `$CODEX_REASON`; do not relaunch, leave the **attempt count unchanged**, and retain the worktree and branch.
   - **`classify`** (verdict `blocked`) → read the executor's report and classify it into exactly one of three, then act:
     | Class | Signal | Action |
     |---|---|---|
     | **plan defect** | the prescribed step is wrong, ambiguous or impossible as written | repair `$PLAN`, relaunch from the blocked task |
     | **executor error** | the plan is right and the executor deviated — a transcription slip, an edit in the wrong place | relaunch with a correction note, plan unchanged |
     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "spec-level: <the finding>"`, then **STOP and notify the operator** |
     **When the classification is unclear, treat it as spec-level and escalate.** Do not redesign the approach.
     **Set these three yourself from the classification above** — they are the judgement's output and nothing computes them:
     ```bash
     CODEX_CLASS="plan defect"          # or "executor error" — spec-level stops instead
     CODEX_NOTE="repaired Task 7 step 3; the prescribed grep lacked --"
     CODEX_BLOCKED_AT="Task 7"          # the task the executor stopped at
     ```
     Record the round, then relaunch or stop:
     ```bash
     source ~/.claude/skills/ship-workflow/lib/ship-next.sh
     source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
     source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
     sn_state_load "$WORKTREE"
     # A fresh shell: rebuild what the launch block set — never write an empty plan or slot.
     CODEX_ATTEMPT_CAP=3
     PLAN="docs/plans/${ID}-${SLUG}.md"
     SLOT=$(basename "$PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')
     CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
     CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))
     codex_round_append "$WORKTREE" "$CODEX_ATTEMPT" blocked "$CODEX_REPORT" "$CODEX_CLASS" "$CODEX_NOTE"
     codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" blocked "$CODEX_CLASS" "$CODEX_BLOCKED_AT"
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     if [ "$CODEX_ATTEMPT" -ge "$CODEX_ATTEMPT_CAP" ]; then
       CODEX_ROUTE=stop_exhausted
       sn_status "$WORKTREE" blocked "codex: repair attempts exhausted"
       echo "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted — stopping." >&2
       echo "worktree retained at $WORKTREE; history in .ship/codex-rounds.md" >&2
     else
       CODEX_ROUTE=relaunch
     fi
     ```
     On `relaunch`, go back to **Launch** above with the repaired plan or the correction note, reusing the same `$SLOT`. On `stop_exhausted`, stop and notify. Do not raise the attempt cap.
5. **Wait for the executor to finish.** For options 1 and 2 this is the sub-skill returning. For option 3 it is the loop above reaching `continue`, an escalation, or the cap. Either way the branch carries ≥ 1 commit per completed task.

## Phase 6 — Code review loop (strict gate)

**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" review`.
0.5. **Mechanical test gates (pure git + shell, before the LLM review).**
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   sn_mech_gates "$WORKTREE" "$ORIG_BRANCH" "docs/plans/${ID}-${SLUG}.md"
   ```
   `MECH_BLOCKERS > 0` feeds the same fix-plan loop as LLM blockers in step 2.
1. **Verify code-review-skill installed:**
   ```bash
   if [ ! -f ~/.claude/skills/code-review-skill/SKILL.md ]; then
     echo "ERROR: code-review-skill is not installed."
     echo "It ships with ai_system: run ./sync.sh restore in the ai_system checkout (on main),"
     echo "then re-invoke /ship-next ${ID} to resume from this phase."
     exit 1
   fi
   ```
1.4. **Spec review (every attempt, in parallel with code review)**
   ```bash
   : "${ID:?ID is not set}" "${attempt:?attempt is not set}" "${WORKTREE:?WORKTREE is not set}"
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   SPEC_OUT="/tmp/ship-next-spec-${ID}-${attempt}.md"
   sn_spec_review_render "$WORKTREE" || exit 1
   ```
   Give `.ship/spec-review-prompt.md` to a read-only sub-agent in the same message as the code review, with `$SPEC_OUT` as its output path.
   ```bash
   : "${ID:?ID is not set}" "${attempt:?attempt is not set}"
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   SPEC_OUT="/tmp/ship-next-spec-${ID}-${attempt}.md"
   sn_spec_review_check "$SPEC_OUT" || { echo "spec report malformed: re-run step 1.4 once; a second failure stops Phase 6" >&2; exit 3; }
   ```
1.5. **Security pass (once code review clears the attempt)** — run this separate review inside the loop after code review reports 0 blockers, including mechanical blockers. HIGH security findings block like code-review blockers.
   ```bash
   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${ID:?ID is not set}" "${attempt:?attempt is not set}"
   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
   rm -f "$SEC_OUT"
   source ~/.claude/skills/ship-workflow/lib/security-review.sh || { echo "ERROR: the security-review lib is missing (stale ship-workflow checkout?) — not skipping the review." >&2; exit 1; }
   mkdir -p .ship
   if security_review_enabled "$ORIG_BRANCH"; then
     echo on > .ship/security-review-state
     security_review_render "$ORIG_BRANCH" .ship/security-review-prompt.md >/dev/null || { echo "ERROR: the security review could not be rendered — not skipping it." >&2; echo "       A missing lib or template usually means the local ship-workflow checkout is stale." >&2; exit 1; }
     echo "security review: follow .ship/security-review-prompt.md and write its report to $SEC_OUT"
   else
     echo off > .ship/security-review-state
     echo "No security findings." > "$SEC_OUT"
     echo "security review: off (ship-config on $ORIG_BRANCH)"
   fi
   ```
   Then **follow `.ship/security-review-prompt.md`**: one finder sub-task, one parallel filter sub-task per candidate, drop anything below confidence 8. Write the final report, and nothing else, to `$SEC_OUT`. Before accepting a `[pre-existing]` finding from either review, confirm with `git show ${ORIG_BRANCH}:<file>` that the cited code exists there; if it does not, delete the tag so the finding counts.
1.6. **Check the security report** — the pass must never fail open:
   ```bash
   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${REVIEW_OUT:?REVIEW_OUT is not set}" "${ID:?ID is not set}" "${attempt:?attempt is not set}"
   source ~/.claude/skills/ship-workflow/lib/security-review.sh || { echo "ERROR: security-review lib missing" >&2; exit 1; }
   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh || { echo "ERROR: pre-existing lib missing" >&2; exit 1; }
   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
   if ! security_review_output_check "$SEC_OUT"; then
     echo "security report is not in the required format: $SEC_OUT" >&2
     echo "Re-run step 1.5 once. If this check fails again, stop Phase 6 here." >&2
     exit 3
   fi
   pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"
   ```
   Reject upstream-format or malformed reports: a finding must not silently parse as zero.
2. **Loop:** Never write Phase 5's supervise state or pid mirror from the fix-plan loop; it has a different plan identity.
   ```
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   source ~/.claude/skills/ship-workflow/lib/codex-verdict.sh
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
   source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE
   attempt=1
   while [ "$attempt" -le 3 ]; do
     REVIEW_TARGET=$(git diff ${ORIG_BRANCH}...HEAD)
     REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
     SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
     SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md
     rm -f "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"   # never parse a report left by an earlier run
     # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT
     # Step 1.4 runs the Spec review in parallel; it writes and checks $SPEC_OUT.
     # Read .ship/review-extra-checks.md when present.
     PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT") || { echo "review parse failed — not passing the gate" >&2; exit 1; }
     eval "$PARSED"
     [ -n "${SPEC_GAPS_FOUND:-}" ] || { SPEC_GAPS_FOUND="$SPEC_GAP_COUNT"; sn_state_set "$WORKTREE" SPEC_GAPS_FOUND "$SPEC_GAPS_FOUND"; }
     BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))
     if [ "$BLOCKING_COUNT" -eq 0 ]; then
       # Only once code review reports 0 blockers, run steps 1.5 and 1.6.
       # They write and validate SEC_OUT; any failure stops here, never passes.
       PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT") || { echo "review parse failed — not passing the gate" >&2; exit 1; }
       eval "$PARSED"
       BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))
     fi
     if [ "$AUTO" = "1" ]; then
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" "review attempt $attempt" "blocking=$BLOCKING_COUNT major=$MAJOR_COUNT minor=$MINOR_COUNT praise=$PRAISE_COUNT"
     fi
     if [ "$BLOCKING_COUNT" -eq 0 ]; then break; fi
     if [ "$AUTO" = "0" ]; then
       echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
       pre_existing_drop "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT" | grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)'
     fi
     attempt=$((attempt + 1))
     if [ "$attempt" -gt 3 ]; then break; fi  # fall through to abort below
     # Build inline fix-plan
     FIX_PLAN=docs/plans/${ID}-${SLUG}-review-fix-${attempt}.md
     # ... (existing logic: write fix-plan, invoke subagent on it)
     # The fix-plan covers the blocking findings from $REVIEW_OUT, $SPEC_OUT and $SEC_OUT,
     # never the [pre-existing] ones.
     if [ "$AUTO" = "1" ]; then
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" "building fix-plan attempt $attempt" "$FIX_PLAN with $BLOCKING_COUNT blockers"
     fi
     EXECUTOR=$(cat .claude/.ship-executor)
     case "$EXECUTOR" in
       1) invoke superpowers:subagent-driven-development on $FIX_PLAN ;;
       2) invoke superpowers:executing-plans on $FIX_PLAN ;;
       3) # Supervise this run the same way Phase 5 does. A fix-plan run can be
          invoke /run-plan "$FIX_PLAN"
          FIX_SLOT=$(basename "$FIX_PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')
          FIX_LOG="/tmp/run-plan-codex-${FIX_SLOT}.log"
          codex_wait_for_exit "/tmp/run-plan-codex-${FIX_SLOT}.pid"
          FIX_VERDICT=$(codex_verdict "$FIX_LOG")
          FIX_REPORT="/tmp/codex-fix-${FIX_SLOT}.md"
          if ! codex_report_extract "$FIX_LOG" "$FIX_REPORT"; then
            echo "codex: no report extractable from $FIX_LOG" >&2
            FIX_VERDICT=infra
          else
            codex_round_append "$WORKTREE" "fix-${attempt}" "$FIX_VERDICT" "$FIX_REPORT" "review fix-plan" "attempt ${attempt} of the Phase 6 review loop"
          fi
          CODEX_FINAL_VERDICT="$FIX_VERDICT"
          CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
          if [ "$FIX_VERDICT" = "infra" ]; then
            echo "codex infrastructure failure during the fix-plan run — stopping." >&2
            break
          fi
          ;;
     esac
   done
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_set "$WORKTREE" MAJOR_COUNT "${MAJOR_COUNT:-0}"
   sn_state_set "$WORKTREE" MINOR_COUNT "${MINOR_COUNT:-0}"
   sn_state_set "$WORKTREE" PRAISE_COUNT "${PRAISE_COUNT:-0}"
   sn_state_set "$WORKTREE" SECURITY_COUNT "${SECURITY_COUNT:-0}"
   sn_state_set "$WORKTREE" PRE_EXISTING_COUNT "${PRE_EXISTING_COUNT:-0}"
   sn_state_set "$WORKTREE" PONYTAIL_COUNT "${PONYTAIL_COUNT:-0}"
   sn_state_set "$WORKTREE" CODEX_FINAL_VERDICT "${CODEX_FINAL_VERDICT:-0}"
   sn_state_set "$WORKTREE" CODEX_ROUNDS "${CODEX_ROUNDS:-0}"
   ```
3. **If still blocking after 3 attempts:**
   - **In auto mode (`AUTO=1`):** **ABORT** the cycle. Send `$SUMMARY` by Discord reply if a chat_id is in scope; otherwise use PushNotification subject `/ship-next ${ID} aborted`. Do not cd to the original branch, remove the worktree, or delete the branch.
     ```bash
     ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" "cap=3 exhausted — aborting" "blocking=$BLOCKING_COUNT main untouched, worktree retained at $WORKTREE"
     source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "review: $BLOCKING_COUNT blockers left after 3 attempts"
     SUMMARY="🛑 ${ID} ${DESCRIPTION} aborted at P6 — 3 attempts didn't clear blockers.
   • blocking remaining: ${BLOCKING_COUNT}
   • last attempt review: /tmp/ship-next-review-${ID}-3.md
   • worktree retained: ${WORKTREE}
   • branch retained: ${BRANCH}
   • resume: cd ${WORKTREE} && /ship-next --resume ${ID}"
     osascript -e "display notification \"${ID} aborted — see Discord/log\" with title \"/ship-next abort\" sound name \"Sosumi\"" 2>/dev/null || true
     printf '\a' >&2
     exit 1
     ```
   - **Interactive (`AUTO=0`):** pause and prompt:
     ```
     3 review attempts didn't clear blockers. Options:
       [Y] Auto-fix one more cycle (loop continues)
       [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
       [abort] Discard everything — /ship-next --discard ${ID}
     ```
     On `[n]`, first run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "review: paused after 3 attempts"`.
4. **Major findings handling** (only after `BLOCKING_COUNT == 0`):
   - **In auto mode (`AUTO=1`):** every major finding becomes an `IDEA-NNN` follow-up (NEVER skip; quality-debt must be visible).
     ```bash
     if [ "$MAJOR_COUNT" -gt 0 ]; then
       source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE
       MAJOR_LINES=$(grep -h -B0 -A2 -E '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' "$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE")
       IFS=$'\n'
       for finding in $(echo "$MAJOR_LINES" | awk '/^[🟡]|\[major\]|\*\*Severity/' | head -$MAJOR_COUNT); do
         finding_desc=$(echo "$finding" | sed 's/^[🟡[:space:]]*//' | head -c 120)
         /ship-idea --during-build "P6 major from $ID: $finding_desc" --severity major --source "code-review-skill auto-run during $ID" --related-roadmap-item "$ID"
       done
       unset IFS
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" "majors → IDEAs created" "$MAJOR_COUNT IDEA-NNN follow-ups via /ship-idea --during-build"
     fi
     ```
   - **Interactive (`AUTO=0`):** list majors and ask per-finding `[F]ix-now / [I]dea-NNN-followup / [S]kip`.
4.5. **Pre-existing findings** — reported by either review, tagged `[pre-existing]`. They never block and are never asked about as this ship's own importants. Each becomes one follow-up, and a defect that is already tracked is not filed again:
   ```bash
   : "${REVIEW_OUT:?REVIEW_OUT is not set}" "${SEC_OUT:?SEC_OUT is not set}"
   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh || { echo "ERROR: pre-existing lib missing" >&2; exit 1; }
   pre_existing_lines "$REVIEW_OUT" "$SEC_OUT" | while IFS= read -r finding; do
     key=$(pre_existing_key "$finding") || continue
     if pre_existing_tracked "$key"; then
       echo "already tracked: $key"
     else
       echo "new pre-existing: $key — $finding"
     fi
   done
   ```
   For each `new pre-existing` line, make the description end with `(pre-existing-key: <key>)` so the next ship that meets the same defect skips it:
   - **Auto (`AUTO=1`):** `/ship-idea --during-build "P6 pre-existing from $ID: <finding> (pre-existing-key: <key>)" --source "ship-next Phase 6" --related-roadmap-item "$ID"`.
   - **Interactive (`AUTO=0`):** ask per finding `[I]dea-NNN-followup / [S]kip`.

## Phase 7 — Land the branch (squash merge, or open a review)

Read `merge_mode` from `.claude/ship-config.yml`: default `squash`, or `mr` for review.
**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" landing`.
1. **Build the body.** Both paths carry the same content: a squash commit message, or an MR/PR description. Build it once.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   SHIP_BODY="/tmp/ship-body-${ID}.md"
   sn_ship_body "$WORKTREE" "$ID" "$SLUG" "$SHIP_BODY"
   ```
2. **Land it.**
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   sn_land "$WORKTREE" "$ID" "$BRANCH" "$ORIG_BRANCH" "$SHIP_TITLE" "$SHIP_BODY"
   ```
   **`mr` does not move `$ORIG_BRANCH`.** The review carries only the work. Phase 8 marks the row in-review and drafts the learning, Phase 9 keeps the branch and worktree, and `/ship-land` runs `/ship-compound` on the base branch once the review merges.

## Phase 8 — /ship-compound (squash) · in-review + learning draft (mr)

**`squash`:** invoke `/ship-compound` with `ID` set to this R-NNN from the original repo cwd on `$ORIG_BRANCH` (Phase 7 already cd'd back). It writes the learning, updates `CONTEXT.md` (exports `CONTEXT_MD_STATUS`), moves the row to Done and removes the spec and plan. Then run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" done`.
**`mr`:** do not run `/ship-compound` — every file it writes is shared or belongs on the base branch, and parallel reviews must not touch them. `/ship-land` runs it after the merge. `/ship-idea --during-build` rows wait in `$WORKTREE/.ship/ship-log-rows` too; `/ship-land` replays them. Here:
1. Mark the row in review:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_state_load "$WORKTREE"
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" --mark-review "$SHIP_REVIEW_URL"
   sn_status "$WORKTREE" in-review
   ```
2. While the context is fresh, draft the learning from `templates/repo/LEARNING.md` into `$WORKTREE/.ship/learning-draft.md`: Key Decisions from the spec's `## Decisions`, What Changed From Plan from the plan and `.ship/codex-rounds.md`. It is not committed; `/ship-land` starts from it. Set `CONTEXT_MD_STATUS="deferred to /ship-land"`.
After either path, persist the CONTEXT.md result for cleanup:
```bash
source ~/.claude/skills/ship-workflow/lib/ship-next.sh
sn_state_set "$WORKTREE" CONTEXT_MD_STATUS "$CONTEXT_MD_STATUS"
```

## Phase 8.5 — Test churn report

**Report-only. This phase deletes nothing.**
0. **Churn report.** Report test modifications as well as added lines:
   ```bash
   source ~/.claude/skills/ship-workflow/lib/test-churn.sh
   tc_report "$ORIG_BRANCH" HEAD
   ```
   Paired test/source edits track behavior changes. Unpaired test edits may indicate a change-detector coupled to implementation. Use lines-per-test to assess setup volume. Report only; a human judges whether an unpaired edit is wrong.

## Phase 9 — Cleanup

0a. **Resolve the merge mode.** Each helper also resolves it independently.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   ```
0. **Capture anything inside the worktree the summary needs.** Capture state and round history before cleanup; the helper copies it out so later shells can read it.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_capture "$WORKTREE" "$ID"
   ```
1. **Remove worktree** — only when the work has actually landed.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_cleanup "$WORKTREE" "$BRANCH"
   ```
   In `mr` mode the worktree is kept for review changes; `/ship-land` removes it after merge.
   If this fails (e.g. uncommitted changes in worktree), print:
   ```
   WARN: worktree at $WORKTREE has uncommitted changes; not removed.
         Inspect with: cd $WORKTREE && git status
         When ready: git worktree remove --force $WORKTREE
   ```
2. **Delete worktree branch** — never while a review points at it.
   `sn_cleanup` performs this step after removing the worktree.
   The squash merge in Phase 7 doesn't update branch reachability, so `-d` may complain. Use `-D` if needed; the work is already squashed onto $ORIG_BRANCH.
3. **Log + commit.** `squash`: in `$REPO`, on `$ORIG_BRANCH`. `mr`: nothing is committed now — rows wait in `$WORKTREE/.ship/ship-log-rows` and `/ship-land` replays them with the compound commit after the merge.
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_log "$WORKTREE" "$ID" "${SHIP_LOG_ROW:-}"
   ```
4. **Auto-mode success notification** (only if `AUTO=1`):
   ```bash
   source ~/.claude/skills/ship-workflow/lib/ship-next.sh
   sn_summary "$WORKTREE" "$ID"
   if [ "$AUTO" = "1" ]; then
     osascript -e "display notification \"${ID} shipped: squash ${MERGE_SHA}\" with title \"/ship-next done\" sound name \"Glass\"" 2>/dev/null || true
     printf '\a' >&2
   fi
   ```
   Send `$SUMMARY` via Discord reply when the incoming message has `channel source="discord"` and a `chat_id` is in scope; include `files=[$WORKTREE/.claude/.ship-auto-decisions.md]`. Otherwise call PushNotification with subject `/ship-next ${ID} shipped` and body `$SUMMARY`. Always fire the local OS notification and bell above.
   Keep the **last round's bullets verbatim**, including what was not changed. Point to the archived history at `${CODEX_ROUNDS_ARCHIVE}` after worktree removal.

## Failure modes

- **Worktree create fails (dirty index)** → abort, hint `git stash; /ship-next ${ID}`
- **Brainstorm abandoned mid-flow** → user Ctrl-C; worktree remains. Resume via `/ship-next ${ID}` or destroy via `/ship-next --discard ${ID}`.
- **Executor fails mid-run** → log to plan's `## Execution log` (existing pattern); worktree remains.
- **code-review-skill not installed** → ERROR with install hint (Phase 6 step 1).
- **Merge conflict to original branch** → abort merge, retain worktree, hint user to rebase.
- **Cleanup fails** → print worktree path, instruction to remove manually.
