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
- `--auto:yes` (alias `--auto`) — **fire-and-forget mode**. Runs the entire 9-phase cycle without interactive prompts: brainstorm clarifying questions auto-pick option 1; spec/plan review gates auto-approve; executor auto = codex /run-plan (subagent-driven if the `codex` CLI is missing, never inline); review loop iterates fix-plans automatically up to cap=3; major findings auto-forwarded to `IDEA-NNN` follow-ups. On cap=3 failure: abort with worktree retained + Discord push. Requires the ROADMAP row to have a `↳ done when:` annotation. Records every auto decision to `.claude/.ship-auto-decisions.md` (gitignored) in the worktree.

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
     ua_get_pre_brainstorm_context "$ID" > .ship/ua-context.md
     [ -s .ship/ua-context.md ] && echo "UA pre-context saved to .ship/ua-context.md — Read this before brainstorm dialog."
   fi
   ```

   When the brainstorming skill kicks off, it should Read `.ship/ua-context.md` (if present) as part of its opening context — this gives the design dialog concrete grounding in how the target files actually connect.

   **CONTEXT.md (project vocabulary):**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/context-md.sh
   if [ -n "$(context_md_path)" ]; then
     echo "CONTEXT.md present — Read it before brainstorm dialog."
   fi
   ```

   When present, Read `CONTEXT.md` before the brainstorm dialog. It is the
   project's shared domain vocabulary; using its terms verbatim avoids
   re-deriving jargon and keeps naming consistent with what teammates read.

   **Past learnings (what this project already got wrong here):**

   Until now `docs/learnings/` was write-only — Phase 8 wrote it and nothing in
   the flow ever read it. On one real repo that is 67 files and ~9,900 lines of
   hard-won detail that never reached a single brainstorm.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/learnings-lookup.sh

   LEARN_CAP=3
   # Terms come from the slug: specific enough to hit, cheap to derive. Generic
   # verbs are dropped because they match almost every learning.
   LEARN_TERMS=$(printf '%s' "$SLUG" | tr '-' '\n' \
     | awk 'length($0) >= 4' \
     | grep -vxE 'fix|add|update|remove|improve|unify|polish|show|make|into' || true)
   LEARN_HITS=$(learnings_match $LEARN_TERMS)
   # `grep -c . || echo 0` prints 0 AND exits 1, giving "00". Use `|| true`.
   LEARN_N=$(printf '%s' "$LEARN_HITS" | grep -c . || true)
   [ -n "$LEARN_N" ] || LEARN_N=0

   if [ "$LEARN_N" -eq 0 ]; then
     echo "learnings: no prior work matched ${LEARN_TERMS}"
   elif [ "$LEARN_N" -le "$LEARN_CAP" ]; then
     echo "learnings: $LEARN_N match(es) — Read each before the dialog:"
     printf '%s\n' "$LEARN_HITS"
   else
     # Measured: a broad term like `bucket` matches 32 of 67 learnings and
     # opening them costs ~100k tokens. Show titles; let the dialog pick.
     echo "learnings: $LEARN_N matches — too many to open. Paths only:"
     printf '%s\n' "$LEARN_HITS" | sed 's|^|  |'
   fi
   ```

   At or under the cap, Read each hit before the dialog. Over the cap, the
   filenames carry the slug of what each ship was about; open at most one that
   is clearly about this change. The grep
   itself returns filenames only and costs ~31 tokens — less than CONTEXT.md.

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

   Also pass a **required output section: `## Seams`** — a three-column table
   (Seam | Interface | Guaranteed behavior) declaring every boundary this work
   introduces or changes. Tests may assert a seam's behavior and nothing inside
   it. This instruction travels in the invocation context; no `superpowers`
   file is modified.

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

**Plan-authoring guidance (learned from R-084.1, 2026-07-30):**

- **Verification/acceptance steps MUST run scoped pytest, not the full
  suite.** `pytest tests/ -q` in developer/codex environments without
  `env.json` + PG credentials hits pre-existing baseline timeouts that
  can stall 30+ min with no natural termination. Instead, list the
  specific test files/directories the plan touched:
  `pytest tests/domain/test_foo.py tests/api/test_bar.py -q`. If you
  genuinely need a broader run, prefer `pytest tests/domain/ tests/api/ -q`
  (or whatever module scopes are relevant) over `tests/`.

- **Reader-untouched grep guards MUST use three-dot diff:**
  `git diff <base>...HEAD -- <paths>`, NOT `<base>..HEAD`. Two-dot
  leaks commits that landed on `<base>` after this branch forked and
  makes them show up as reverse-diff pollution when you compare.

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
   - **In auto mode (`AUTO=1`):** auto-pick `3` (codex /run-plan). Fall back to `1`
     only when the `codex` CLI is missing. Do **not** downgrade to `2` (inline) on
     plan-size or cost grounds — that override is what made inline the de-facto
     auto default.
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
   # In auto mode, the log entry from step 5.4 already captured the choice.
   ```

2.5. **Render executor rule files.**

   ```bash
   mkdir -p .ship

   # TDD discipline: universal rules + this repo's learned rules + this
   # ship's seams. The rules used to be hardcoded here, which made the layer
   # that shapes what the executor writes the only one that could not
   # compound — and shipped one repo's evidence to every other repo.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/tdd-rules.sh
   tdd_rules_render "${ID}" "docs/specs/${ID}-${SLUG}.md" > .ship/tdd-rules.md

   # ponytail ladder (silent no-op when ponytail is not installed)
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ponytail-integration.sh
   ponytail_render_rules .ship/ponytail-rules.md

   # Version pin + drift detection (spec §8.4). Drift NEVER blocks: we use the
   # new ruleset and surface the change, because a stale pin nobody bumps is the
   # failure mode this project already has.
   PONYTAIL_CURRENT=$(ponytail_version)
   PONYTAIL_SHA=$(ponytail_ruleset_sha256)
   PONYTAIL_PINNED=$(grep -A3 '^ponytail:' ~/.claude/ship-workflow.yml 2>/dev/null \
                     | grep 'pinned_version:' | sed 's/.*: *//' | tr -d '"' )
   PONYTAIL_PINNED_SHA=$(grep -A3 '^ponytail:' ~/.claude/ship-workflow.yml 2>/dev/null \
                     | grep 'ruleset_sha256:' | sed 's/.*: *//' | tr -d '"' )
   PONYTAIL_DRIFT=0
   if [ -n "$PONYTAIL_SHA" ] && [ -n "$PONYTAIL_PINNED_SHA" ] \
      && [ "$PONYTAIL_SHA" != "$PONYTAIL_PINNED_SHA" ]; then
     PONYTAIL_DRIFT=1
   fi

   # An absent ponytail is a legitimate state, but a SILENT one misleads. The
   # lib no-ops by design (spec 8.4) — correct for a missing optional
   # dependency, wrong for one the operator asked for and believes is active.
   # Measured on this machine: check_installed false, render_rules 0 lines,
   # Phase 5 said nothing, so every executor ran with no ladder at all.
   if ponytail_check_installed; then
     PONYTAIL_STATUS="v${PONYTAIL_CURRENT} ladder rendered"
   else
     PONYTAIL_STATUS="not installed — no ladder enforced this run"
     # Printed here, not only in Phase 9: the SUMMARY is built only when
     # AUTO=1, and interactive is the mode the operator is actually watching.
     echo "ponytail: not installed — no ladder enforced this run" >&2
   fi
   ```

   **On drift (`PONYTAIL_DRIFT=1`):**
   - `--auto:yes`: proceed with the new ruleset, log it, and let Phase 9 surface it.
     ```bash
     [ "$AUTO" = "1" ] && ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh \
       "$WORKTREE" "P5" "ponytail ruleset drift" "${PONYTAIL_PINNED} -> ${PONYTAIL_CURRENT}, using new"
     ```
   - Interactive: show the version delta and a `diff` of the ruleset against the pin,
     then offer `[A]ccept and re-pin / [S]kip / [C]ontinue without re-pinning`.
     `[A]` rewrites `pinned_version` and `ruleset_sha256` in `~/.claude/ship-workflow.yml`.

   The plan's task template already instructs executors to read both files.
   Rendering to `.ship/` rather than relying on skill activation is deliberate:
   Phase 5 spawns a fresh subagent per task, and ponytail documents that
   subagent-start hooks cannot inject its ruleset.

3. **Invoke the chosen sub-skill.**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → the supervise loop in step 4 below.

4. **Executor 3 only — supervise the codex run.**

   `/run-plan` detaches codex and returns. It does not finish the work. Across 19
   real runs it stopped 13 times with a `BLOCKED` verdict, and every one of those
   stops was correct. This step does the routing a human did by hand 16 times.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-verdict.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh

   CODEX_ATTEMPT_CAP=3
   PLAN="docs/plans/${ID}-${SLUG}.md"
   # Same derivation /run-plan uses, so this agrees with its /tmp state files.
   # (It appends a trailing _ because tr -c converts basename's newline too.
   # /run-plan does the identical thing, so the paths match. Do not "fix" it
   # here in isolation — that would break the interop it exists to preserve.)
   SLOT=$(basename "$PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')

   # Resume before relaunching. A session restart kills the supervisor but not
   # codex, and a state file from a different ship must not be inherited.
   if codex_state_matches "$WORKTREE" "$PLAN"; then
     CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
     if codex_state_alive "$WORKTREE"; then
       echo "codex is still running for $PLAN — attaching, not relaunching."
     fi
   else
     CODEX_ATTEMPT=0
   fi
   ```

   **Launch** with `/run-plan "$PLAN"`, then record the run so a later re-entry can
   tell a live run from a dead one:

   ```bash
   # Pid authority: /run-plan owns /tmp/run-plan-codex-$SLOT.pid and deletes it.
   # .ship/codex.pid is a durable mirror that survives a /tmp wipe, and is what
   # codex_state_alive reads. A stale mirror is tolerable because that function
   # also confirms the live pid is actually codex before trusting it.
   mkdir -p "$WORKTREE/.ship"
   cp "/tmp/run-plan-codex-${SLOT}.pid" "$WORKTREE/.ship/codex.pid" 2>/dev/null || true

   # Write state NOW, not at the first BLOCKED. A session restart during the
   # first run would otherwise leave no state, so codex_state_matches would be
   # false, the live-process check inside that branch would never run, and the
   # supervisor would relaunch over a live executor.
   codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" running "n/a" "n/a"
   ```

   Carry all five hardening items in the prompt — each is here because a run
   failed without it:

   - **Scope override.** `/run-plan`'s template tells the agent to ignore anything
     under `.claude/skills/`. When the plan's target *is* a skill directory, the
     agent refuses the entire plan.
   - **`--auto:yes` requirement.** Codex cannot answer an interactive prompt. A plan
     step invoking `/ship-next` without it hangs until the cap expires.
   - **Engineering vocabulary.** A prompt written as "attack it", "payloads", "try to
     make it delete" tripped a provider content filter and crashed the run. The same
     review, phrased as input validation, completed. Request the same content; do not
     phrase it as offensive security.
   - **Resume context.** Which tasks are committed, which task to start at, and which
     conclusions from earlier rounds are settled and must not be re-litigated.
   - **Round history.** `.ship/codex-rounds.md`, so the executor does not rediscover
     what the previous round already found.

   **When codex exits**, classify before judging:

   ```bash
   CODEX_LOG="/tmp/run-plan-codex-${SLOT}.log"
   CODEX_FINAL_VERDICT=$(codex_verdict "$CODEX_LOG")
   CODEX_REASON=$(codex_verdict_reason "$CODEX_LOG")

   # Extract the report by the same whole-log rule codex_verdict uses. An empty
   # extraction is an error, never an empty round: preserving the executor's
   # bullet-list report verbatim is the point of this loop.
   CODEX_REPORT="/tmp/codex-report-${SLOT}.md"
   if ! codex_report_extract "$CODEX_LOG" "$CODEX_REPORT"; then
     echo "codex: no report could be extracted from $CODEX_LOG" >&2
     CODEX_FINAL_VERDICT=infra
     CODEX_REASON="no extractable report — $CODEX_REASON"
   fi

   case "$CODEX_FINAL_VERDICT" in
     done|done_with_concerns) CODEX_ROUTE=continue ;;
     blocked)                 CODEX_ROUTE=classify ;;
     infra)                   CODEX_ROUTE=stop_infra ;;
     *)                       CODEX_ROUTE=stop_infra ;;
   esac
   ```

   Then route on `$CODEX_ROUTE`:

   - **`continue`** (verdict `done` / `done_with_concerns`) → record the round, mark
     the run finished, and continue to Phase 6.

     ```bash
     codex_round_append "$WORKTREE" "$((CODEX_ATTEMPT + 1))" "$CODEX_FINAL_VERDICT" \
       "$CODEX_REPORT" "n/a" "executor completed"
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     # Clear the blocked state. Phase 6 re-enters this loop for fix-plans and
     # must not inherit a verdict from a round that has already been resolved.
     codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" \
       "$CODEX_FINAL_VERDICT" "n/a" "n/a"
     rm -f "$WORKTREE/.ship/codex.pid"
     ```

   - **`stop_infra`** (verdict `infra`) → STOP and notify. Do **not** relaunch, and
     leave the **attempt count unchanged**: two of the 19 runs ended this way, and
     retrying them would have burned the budget real defects needed. Use Phase 9's
     notification routing with `$CODEX_REASON`. The worktree and branch are retained.

   - **`classify`** (verdict `blocked`) → read the executor's report and classify it
     into exactly one of three, then act:

     | Class | Signal | Action |
     |---|---|---|
     | **plan defect** | the prescribed step is wrong, ambiguous or impossible as written | repair `$PLAN`, relaunch from the blocked task |
     | **executor error** | the plan is right and the executor deviated — a transcription slip, an edit in the wrong place | relaunch with a correction note, plan unchanged |
     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | **STOP and notify the operator** |

     **When the classification is unclear, treat it as spec-level and escalate.** The
     cost of a needless escalation is one message. The cost of silently redesigning
     the software overnight is a morning spent reading commits to find out what it
     decided. Changing what the software is supposed to do is not the executor's call
     and it is not yours.

     **Set these three yourself from the classification above** — they are the
     judgement's output and nothing computes them:

     ```bash
     CODEX_CLASS="plan defect"          # or "executor error" — spec-level stops instead
     CODEX_NOTE="repaired Task 7 step 3; the prescribed grep lacked --"
     CODEX_BLOCKED_AT="Task 7"          # the task the executor stopped at
     ```

     Record the round, then relaunch or stop:

     ```bash
     CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))
     codex_round_append "$WORKTREE" "$CODEX_ATTEMPT" blocked \
       "$CODEX_REPORT" "$CODEX_CLASS" "$CODEX_NOTE"
     codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" \
       blocked "$CODEX_CLASS" "$CODEX_BLOCKED_AT"
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     if [ "$CODEX_ATTEMPT" -ge "$CODEX_ATTEMPT_CAP" ]; then
       CODEX_ROUTE=stop_exhausted
       echo "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted — stopping." >&2
       echo "worktree retained at $WORKTREE; history in .ship/codex-rounds.md" >&2
     else
       CODEX_ROUTE=relaunch
     fi
     ```

     On `relaunch`, go back to **Launch** above with the repaired plan or the
     correction note, reusing the same `$SLOT`. On `stop_exhausted`, stop and notify.
     A run that burns three attempts is a signal the plan was not ready, not a
     budget to raise.

5. **Wait for the executor to finish.** For options 1 and 2 this is the sub-skill
   returning. For option 3 it is the loop above reaching `continue`, an escalation,
   or the cap. Either way the branch carries ≥ 1 commit per completed task.

## Phase 6 — Code review loop (strict gate)

0. **UA blast-radius report + REMINDERS cross-ref (auto-detect, silent if UA absent):**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ua-integration.sh
   ua_check_installed && echo "UA present — run the blast-radius step below." || true
   ```

   When UA is present, **invoke `/understand-anything:understand-diff`** with
   `${ORIG_BRANCH}` as the base, and write its analysis to `.ship/ua-diff-report.md`.

   This used to be `ua_get_diff_report`, ~90 lines of bash walking
   `.ua/knowledge-graph.json` by hand. It produced Changed and Affected components
   only. `/understand-diff` reads the same graph and additionally gives **affected
   layers**, a **risk assessment** derived from node complexity and cross-layer edge
   count, and a **dashboard overlay** (`.ua/diff-overlay.json`). Its staleness check is
   also stricter: it inspects staged, unstaged and untracked state, not just the
   committed diff. Reimplementing a worse subset in shell was the duplication; the
   output feeds an LLM reviewer and a template, so nothing parses it as a contract.

   Then cross-reference the vault's architecture reminders — this part is independent
   of UA's output format and stays as plain bash:

   ```bash
   if [ -s .ship/ua-diff-report.md ]; then
     PROJECT_PATH=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path 2>/dev/null || echo "")
     REMINDERS_PATH="$PROJECT_PATH/Architecture/REMINDERS.md"
     if [ -n "$PROJECT_PATH" ] && [ -f "$REMINDERS_PATH" ]; then
       git diff --name-only "${ORIG_BRANCH}...HEAD" | while IFS= read -r f; do
         [ -z "$f" ] && continue
         base=$(basename "$f" | sed 's/\.[^.]*$//')
         if grep -q "$base" "$REMINDERS_PATH" 2>/dev/null; then
           echo "> ℹ REMINDERS.md has a rule mentioning \`$base\` — review before merge." >> .ship/ua-diff-report.md
         fi
       done
     fi
     echo "UA blast-radius report → .ship/ua-diff-report.md"
   fi
   ```

   code-review-skill should Read `.ship/ua-diff-report.md` when present, treating it as
   pre-computed review context alongside the diff itself.

0.5. **Mechanical test gates (pure git + shell, before the LLM review).**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/test-budget.sh

   # (a) Refactor violation: a `Seam: none` task must not add test lines.
   MECH_BLOCKERS=0
   PLAN_FILE="docs/plans/${ID}-${SLUG}.md"
   if [ -f "$PLAN_FILE" ] && grep -qF 'Seam: none' "$PLAN_FILE"; then
     for sha in $(git log --format=%H "${ORIG_BRANCH}..HEAD"); do
       SUBJ=$(git log -1 --format=%s "$sha")
       TASK_NO=$(echo "$SUBJ" | grep -oE 'Task [0-9]+' | head -1)
       [ -z "$TASK_NO" ] && continue
       grep -A6 "### ${TASK_NO}:" "$PLAN_FILE" | grep -qF 'Seam: none' || continue
       ADDED=$(git diff --numstat "${sha}^" "$sha" -- '*test*' 'tests/' 2>/dev/null \
               | awk '{s+=$1} END {print s+0}')
       if [ "${ADDED:-0}" -gt 0 ]; then
         echo "🛑 blocking: refactor task added test lines (${TASK_NO}, +${ADDED} in tests)" >&2
         MECH_BLOCKERS=$((MECH_BLOCKERS + 1))
       fi
     done
   fi

   # (b) Test budget, relative to this repo's own baseline.
   BASELINE_RATIO_BP=$(tb_baseline_ratio)
   SHIP_RATIO_BP=$(tb_ship_ratio "$ORIG_BRANCH" HEAD)
   set -- $(tb_ship_lines "$ORIG_BRANCH" HEAD)
   TEST_LINES_ADDED="$1"; SRC_LINES_ADDED="$2"
   TEST_BUDGET_VERDICT=$(tb_verdict "$SHIP_RATIO_BP" "$BASELINE_RATIO_BP")

   if tb_shadow_active; then
     echo "Test budget: ship=${SHIP_RATIO_BP}bp baseline=${BASELINE_RATIO_BP}bp verdict=${TEST_BUDGET_VERDICT} (shadow mode — reporting only)"
     TEST_BUDGET_VERDICT=pass
   else
     echo "Test budget: ship=${SHIP_RATIO_BP}bp baseline=${BASELINE_RATIO_BP}bp verdict=${TEST_BUDGET_VERDICT}"
     [ "$TEST_BUDGET_VERDICT" = "blocking" ] && MECH_BLOCKERS=$((MECH_BLOCKERS + 1))
   fi

   # (c) Extra review checks handed to the LLM reviewer.
   mkdir -p .ship
   cat > .ship/review-extra-checks.md <<'CHECKS'
In addition to your normal findings, tag any finding that matches one of these
categories by appending the literal tag to the finding line:

- `[seam-violation]` — a test asserts something not declared in the spec's `## Seams`
- `[assertion-roulette]` — one test bundles multiple unrelated assertions
- `[weak-assertion]` — an assertion that cannot fail for any valid input
- `[pre-existing]` — the defect exists on the base branch already, and this diff
  neither introduces nor worsens it. Put the tag right after the severity tag and add
  an indented line `Base evidence: <file>:<line> exists unchanged on <base branch>`.
  A pre-existing finding is reported but never blocks this ship.

Keep your usual severity tag as well; these categories are orthogonal to severity.
CHECKS
   ```

   `MECH_BLOCKERS > 0` feeds the same fix-plan loop as LLM blockers in step 2.

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

1.5. **Security pass (every review attempt)** — a separate review, next to
   code-review-skill, as in Anthropic's own pipeline (R-003). It is a vendored copy of
   Anthropic's open-source `/security-review` prompt, rendered for this ship's diff, with
   prompt-injection and LLM-output checks added. Its HIGH findings block exactly like
   code-review blockers. Run this block inside the loop below, after code-review-skill
   has written `$REVIEW_OUT`:

   ```bash
   # Each block runs in its own shell: these come from the surrounding phase.
   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${ID:?ID is not set}" "${attempt:?attempt is not set}"
   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
   # A report left by an earlier run must never stand in for this one: removing it
   # first, on every exit path, means step 1.6 catches a pass that produced nothing.
   rm -f "$SEC_OUT"
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/security-review.sh || {
     echo "ERROR: the security-review lib is missing (stale ship-workflow checkout?) — not skipping the review." >&2
     exit 1
   }
   mkdir -p .ship
   if security_review_enabled "$ORIG_BRANCH"; then
     echo on > .ship/security-review-state
     security_review_render "$ORIG_BRANCH" .ship/security-review-prompt.md >/dev/null || {
       echo "ERROR: the security review could not be rendered — not skipping it." >&2
       echo "       A missing lib or template usually means the local ship-workflow checkout is stale." >&2
       exit 1
     }
     echo "security review: follow .ship/security-review-prompt.md and write its report to $SEC_OUT"
   else
     echo off > .ship/security-review-state
     echo "No security findings." > "$SEC_OUT"
     echo "security review: off (ship-config on $ORIG_BRANCH)"
   fi
   ```

   Then **follow `.ship/security-review-prompt.md`**: one finder sub-task, one parallel
   filter sub-task per candidate, drop anything below confidence 8. Write the final
   report, and nothing else, to `$SEC_OUT`. Before accepting a `[pre-existing]`
   finding from either review, confirm with `git show ${ORIG_BRANCH}:<file>` that the
   cited code exists there; if it does not, delete the tag so the finding counts.

1.6. **Check the security report** — the pass must never fail open:

   ```bash
   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${REVIEW_OUT:?REVIEW_OUT is not set}" \
     "${ID:?ID is not set}" "${attempt:?attempt is not set}"
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/security-review.sh || { echo "ERROR: security-review lib missing" >&2; exit 1; }
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh || { echo "ERROR: pre-existing lib missing" >&2; exit 1; }
   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
   if ! security_review_output_check "$SEC_OUT"; then
     echo "security report is not in the required format: $SEC_OUT" >&2
     echo "Re-run step 1.5 once. If this check fails again, stop Phase 6 here." >&2
     exit 3
   fi
   # A file this diff created cannot hold a pre-existing defect: drop the tag from
   # any [pre-existing] finding whose cited file does not exist on the base branch,
   # in both reports, so it counts as this ship's own.
   pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"
   ```

   An upstream-format report (`# Vuln 1 … * Severity: High`), or any line outside the
   ship-next finding format, could hold a finding that parses as zero and passes the
   gate silently. This check exists to stop that.

2. **Loop:**
   ```
   # Phase 6 is a different shell from Phase 5 — Phase 7 cd's back to the main
   # repo between them, and nothing Phase 5 sourced is in scope here. Executor 3
   # calls codex_verdict, codex_report_extract and codex_round_append below, so
   # source them. Sourcing is harmless for executors 1 and 2.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-verdict.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE

   attempt=1
   while [ "$attempt" -le 3 ]; do
     # Three-dot diff: shows only what this branch added relative to the
     # merge-base. Two-dot (..HEAD) leaks commits that landed on ORIG_BRANCH
     # after this worktree forked — those are NOT this branch's changes and
     # would pollute the review with reverse-showing "removed" lines.
     # See R-084.1 learning (2026-07-30) for the burn.
     REVIEW_TARGET=$(git diff ${ORIG_BRANCH}...HEAD)
     REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
     SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
     rm -f "$REVIEW_OUT" "$SEC_OUT"   # never parse a report left by an earlier run
     # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT
     # Read .ship/review-extra-checks.md alongside .ship/ua-diff-report.md when present.
     # Then run steps 1.5 and 1.6 (the security pass); they write SEC_OUT.

     # A failed parse (a missing report) must stop the gate, not pass it: eval of an
     # empty string succeeds and leaves BLOCKING_COUNT unset.
     PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT") \
       || { echo "review parse failed — not passing the gate" >&2; exit 1; }
     eval "$PARSED"
     BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))

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
       # Drop each pre-existing finding together with its indented detail lines (ENVIRON,
       # not awk -v, which mangles the \[ escapes), then print the blockers with context.
       PE="$PRE_EXISTING_RE" awk '$0 ~ ENVIRON["PE"] {skip=1; next} skip && /^[[:space:]]+[^[:space:]]/ {next} {skip=0; print}' "$REVIEW_OUT" "$SEC_OUT" \
         | grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)'
     fi

     attempt=$((attempt + 1))
     if [ "$attempt" -gt 3 ]; then break; fi  # fall through to abort below

     # Build inline fix-plan
     FIX_PLAN=docs/plans/${ID}-${SLUG}-review-fix-${attempt}.md
     # ... (existing logic: write fix-plan, invoke subagent on it)
     # The fix-plan covers the blocking findings from both $REVIEW_OUT and $SEC_OUT,
     # never the [pre-existing] ones.

     if [ "$AUTO" = "1" ]; then
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
         "building fix-plan attempt $attempt" \
         "$FIX_PLAN with $BLOCKING_COUNT blockers"
     fi

     EXECUTOR=$(cat .claude/.ship-executor)
     case "$EXECUTOR" in
       1) invoke superpowers:subagent-driven-development on $FIX_PLAN ;;
       2) invoke superpowers:executing-plans on $FIX_PLAN ;;
       3) # Supervise this run the same way Phase 5 does. A fix-plan run can be
          # BLOCKED or hit infrastructure exactly as the original run can, and
          # firing-and-forgetting here would silently drop the reason.
          invoke /run-plan "$FIX_PLAN"

          # The fix-plan gets its OWN slot: /run-plan derives the slot from the
          # plan filename it was handed, so docs/plans/R-001-x-review-fix-1.md
          # logs to run-plan-codex-R-001-x-review-fix-1_.log, NOT to Phase 5's
          # slot. Reusing $SLOT here would classify the ORIGINAL run's log and
          # record its report again as though it were this fix's result.
          FIX_SLOT=$(basename "$FIX_PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')
          FIX_LOG="/tmp/run-plan-codex-${FIX_SLOT}.log"

          # /run-plan DETACHES and returns immediately. Phase 5 handles that with
          # the prose "When codex exits"; here the next statement would run
          # milliseconds after launch, read a log that does not exist yet, and
          # classify infra — breaking the review loop on a false infrastructure
          # failure while codex is still committing unsupervised.
          # Deliberately NOT writing supervise state here. Every reader of
          # .ship/codex-supervise.md and .ship/codex.pid lives in Phase 5, and
          # both files hold ONE record — so a write here is read by nothing and
          # destroys the plan identity and attempt count Phase 5 depends on.
          # Verified: after a Phase 6 write, codex_state_matches against the
          # original plan returns false and Phase 5 resets CODEX_ATTEMPT to 0.
          # Making Phase 6 resumable needs a reader and its own record, not a
          # second writer into Phase 5's slot. Tracked as a follow-up.
          codex_wait_for_exit "/tmp/run-plan-codex-${FIX_SLOT}.pid"

          FIX_VERDICT=$(codex_verdict "$FIX_LOG")
          FIX_REPORT="/tmp/codex-fix-${FIX_SLOT}.md"
          if ! codex_report_extract "$FIX_LOG" "$FIX_REPORT"; then
            echo "codex: no report extractable from $FIX_LOG" >&2
            FIX_VERDICT=infra
          else
            codex_round_append "$WORKTREE" "fix-${attempt}" "$FIX_VERDICT" \
              "$FIX_REPORT" "review fix-plan" \
              "attempt ${attempt} of the Phase 6 review loop"
          fi
          # Phase 9 reports CODEX_FINAL_VERDICT and CODEX_ROUNDS. Leaving them at
          # Phase 5's values would tell the operator the ship ended on the
          # original run's verdict and hide every fix round from the count.
          CODEX_FINAL_VERDICT="$FIX_VERDICT"
          CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
          if [ "$FIX_VERDICT" = "infra" ]; then
            echo "codex infrastructure failure during the fix-plan run — stopping." >&2
            break
          fi
          ;;
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
       # shellcheck disable=SC1091
       source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE
       # Majors from BOTH reports (security MEDIUMs are importants), minus the
       # pre-existing ones — MAJOR_COUNT excludes those, and step 4.5 files them.
       MAJOR_LINES=$(grep -h -B0 -A2 -E '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' "$REVIEW_OUT" "$SEC_OUT" \
                     | grep -vE "$PRE_EXISTING_RE")

       # Parse each finding into a 1-line description
       IFS=$'\n'
       # Finding lines only: a removed pre-existing finding leaves its detail lines
       # (`Base evidence: …`) behind, and none of those is a major.
       for finding in $(echo "$MAJOR_LINES" | awk '/^[🟡]|\[major\]|\*\*Severity/' | head -$MAJOR_COUNT); do
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

4.5. **Pre-existing findings** — reported by either review, tagged `[pre-existing]`.
   They never block and are never asked about as this ship's own importants. Each
   becomes one follow-up, and a defect that is already tracked is not filed again:

   ```bash
   : "${REVIEW_OUT:?REVIEW_OUT is not set}" "${SEC_OUT:?SEC_OUT is not set}"
   # shellcheck disable=SC1091
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

   For each `new pre-existing` line, make the description end with
   `(pre-existing-key: <key>)` so the next ship that meets the same defect skips it:
   - **Auto (`AUTO=1`):** `/ship-idea --during-build "P6 pre-existing from $ID: <finding> (pre-existing-key: <key>)" --source "ship-next Phase 6" --related-roadmap-item "$ID"`.
   - **Interactive (`AUTO=0`):** ask per finding `[I]dea-NNN-followup / [S]kip`.

## Phase 7 — Land the branch (squash merge, or open a review)

`merge_mode` in `.claude/ship-config.yml` decides. Default `squash` — the
behaviour every repo had before this existed. A repo whose work goes through
review sets `merge_mode: mr`.

1. **Build the body.** Both paths carry the same content: a squash commit
   message, or an MR/PR description. Build it once.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)

   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ROW=$(grep "\*\*${ID}\*\*" "$ROADMAP_PATH" | head -1)
   DONE_WHEN=$(grep -A1 "\*\*${ID}\*\*" "$ROADMAP_PATH" | grep "↳ done when:" | sed 's/.*↳ done when: //' | head -1)
   # DESCRIPTION = the row text after the ** id ** part.

   SHIP_TITLE="feat: ${ID} ${DESCRIPTION}"
   SHIP_BODY="/tmp/ship-body-${ID}.md"
   cat > "$SHIP_BODY" <<EOF
   ↳ done when: ${DONE_WHEN}

   Tasks (from docs/plans/${ID}-${SLUG}.md):
   $(grep -E '^### Task [0-9]+:' "docs/plans/${ID}-${SLUG}.md" | sed 's/^### /  - /')

   Code review (awesome-skills/code-review-skill):
   - blocking: 0 ✓
   - major:    ${MAJOR_COUNT} (see plan §Execution log)
   - minor:    ${MINOR_COUNT}
   - praise:   ${PRAISE_COUNT}

   Security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})"; fi)

   Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
   Spec:  docs/specs/${ID}-${SLUG}.md
   Plan:  docs/plans/${ID}-${SLUG}.md
   Notes: docs/roadmap-notes/${ID}-${SLUG}.md (if exists)

   🤖 ${BRANCH}
   Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
   EOF
   ```

2. **Land it.**

   ```bash
   cd "$REPO"
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)

   case "$MERGE_MODE" in
     squash)
       git checkout "$ORIG_BRANCH"
       git merge --squash "$BRANCH"
       git commit -m "$(printf '%s\n\n%s' "$SHIP_TITLE" "$(cat "$SHIP_BODY")")"
       SHIP_REVIEW_URL=""
       ;;

     mr)
       # The branch must exist on the remote before a review can point at it.
       git push -u origin "$BRANCH" || {
         echo "push failed — not opening a review for a branch the remote cannot see" >&2
         exit 1
       }
       MR_CMD=$(forge_mr_cmd "$BRANCH" "$ORIG_BRANCH" "$SHIP_TITLE" "$SHIP_BODY") || {
         echo "unknown forge for origin — push succeeded, open the review by hand" >&2
         exit 1
       }
       echo "opening review: $MR_CMD"
       SHIP_REVIEW_URL=$(eval "$MR_CMD" | grep -oE 'https?://[^[:space:]]+' | tail -1)
       [ -n "$SHIP_REVIEW_URL" ] || {
         echo "the review command produced no URL — check it by hand before continuing" >&2
         exit 1
       }
       echo "review open: $SHIP_REVIEW_URL"
       ;;
   esac
   ```

   **`mr` does not move `$ORIG_BRANCH`.** The work is shipped but not landed, so
   Phase 8 marks the ROADMAP row `in-review` rather than Done, and Phase 9 keeps
   the branch and worktree the review depends on. `/ship-land` finishes the job
   once the review merges.

## Phase 8 — /ship-compound

1. **Invoke `/ship-compound`** for this R-NNN. It writes the learning, promotes patterns to AIR-OS, marks the ROADMAP row ✅.

   Where it runs depends on the merge mode. `squash`: from the original repo cwd
   (Phase 7 already cd'd back), on `$ORIG_BRANCH`. `mr`: from `$WORKTREE`, on the
   review branch — the learning and the queued `CONTEXT.md` entries belong to the
   review, and `/ship-compound` refuses to run its mr path anywhere else. Either way
   it edits the canonical ROADMAP in the vault directly.

   `/ship-compound` now also updates `CONTEXT.md` and exports `CONTEXT_MD_STATUS`.

## Phase 8.5 — Test prune report

**Report-only. This phase deletes nothing.**

0. **Churn report.** The test budget counts ADDED lines only, so a ship that
   rewrote forty existing tests and added none scores perfectly. Measured over
   200 real commits: test files were added 376 times and **modified 456** —
   more editing than writing, and nothing reported it.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/test-churn.sh
   tc_report "$ORIG_BRANCH" HEAD
   ```

   **Reading it.** A test edited alongside its source is tracking a real
   behaviour change — that is correct and costs nothing to explain. A test
   edited while its source stood still is the **change-detector** smell: it was
   coupled to an implementation detail, or it was asserting something untrue.
   On the real repo 32% of modifications are unpaired.

   Lines-per-test is the volume signal. Counting tests points at the wrong
   thing: that repo has only 1.92 tests per product function, which is thin,
   but averages 24 lines per test. The bulk is setup, not test count.

   **Report only.** Deciding whether a specific unpaired edit was wrong needs a
   human, for the same reason the prune list below is a proposal: no mechanical
   signal distinguishes a brittle test from a correctly-updated one.

It was designed to prune redundant tests behind a coverage gate. Six review rounds found
fourteen defects in that gate, and the last three established why: coverage records which
lines and branches *executed*, not whether an assertion *observed* them. A test stripped
of its assertions produces coverage identical to one that checks everything, so no
coverage-derived value can establish that deleting a test is safe. Proving assertion
strength needs mutation testing, which is its own roadmap item. See spec §7.1.

1. **Identify candidates.** When `TEST_BUDGET_VERDICT` is `major`, read the tests
   covering the modules this ship touched and list, for each one you would propose
   removing, the file, the test name, the category and one line of reasoning. Three
   categories:

   1. duplicate coverage — two tests asserting the same behavior
   2. seam violations — a test asserting inside a seam rather than at it
   3. never-failing tests — an assertion too weak to discriminate any input

   Write them to `.ship/prune-candidates.md`, one line each, in exactly this form:

   ```
   CANDIDATE: <test file>::<test name> — <category> — <one line of reasoning>
   ```

   **Propose only; change no test file.** The prefix matters: an earlier Markdown table
   made the header indistinguishable from data, so one candidate counted as two.

2. **Compute the status.**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/prune-report.sh
   PRUNE_STATUS=$(prune_report "$ORIG_BRANCH" "$BRANCH" "$TEST_BUDGET_VERDICT")
   ```

   The mechanical half — trigger, scope resolution, counting — lives in
   `lib/prune-report.sh` so it is unit-tested like every other function here. It was
   previously inline bash in this file, and proving it destroyed nothing meant extracting
   these fences and executing them; four review rounds then found holes in that
   *extraction harness* rather than in the code. `prune_report` is read-only by
   construction: its only write is `mkdir -p .ship`, and its git subcommands are `diff`,
   `rev-parse` and `merge-base`, all of which read. It returns exit 2 when it cannot
   evaluate its input — a malformed ref, an unknown verdict, two commits with no merge
   base — so "could not tell" never reads as "nothing to do". The command substitution
   below does not abort on that, so the reason lands in the Phase 9 summary.

3. **Surface it.** Phase 9 puts `PRUNE_STATUS` in the summary and in the `_log.md` row,
   so the count appears whether or not you open the file. Acting on the list is yours.

   There is no rollback path and no commit, because nothing changes. The `--auto:yes`
   question disappears with the destructive act: a report is safe to produce unattended.

## Phase 8.7 — UA knowledge graph rebuild

Runs after Phase 8.5. That phase is report-only and commits nothing, so this ordering is
no longer load-bearing for correctness; it is kept so the rebuilt graph reflects the tree
as Phase 9 will leave it.

```bash
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/ua-integration.sh
UA_STATUS="n/a"
if ua_check_installed; then
  # ua_check_drift already computes the count against the KG's baseline commit;
  # re-deriving it here would risk the two disagreeing.
  DRIFT_COUNT=$(ua_check_drift | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' | head -1)
  DRIFT_COUNT=${DRIFT_COUNT:-0}
  if [ "$DRIFT_COUNT" -gt 50 ]; then
    UA_STATUS="rebuilt (drift ${DRIFT_COUNT}/50)"
  else
    UA_STATUS="drift ${DRIFT_COUNT}/50"
  fi
fi
```

When `UA_STATUS` starts with `rebuilt`, **Invoke `/understand`** to do a full
rebuild. There is no incremental refresh in the UA plugin: `understand-diff` reads
the graph rather than writing it, so the options are a full rebuild or nothing.
The `> 50` threshold is reused verbatim from `ua_check_drift`'s own severity
boundary, not re-derived, and it doubles as the rate limiter.

Rebuilding is non-destructive — it writes a new graph and touches no source — so it
runs in `--auto:yes`. Because it is expensive, Phase 9 flags it explicitly.

## Phase 9 — Cleanup

0a. **Resolve the merge mode.** Phase 9 is a different shell from Phase 7.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   ```

0. **Capture anything inside the worktree the summary needs.** Step 1 removes the
   worktree, so `.ship/` is gone by the time steps 3 and 4 run. Read it first —
   this is the step that makes the round history survive cleanup.

   ```bash
   # Phase 9 is a different shell from Phase 5: nothing sourced there is in
   # scope here. Source what this phase calls.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh

   # Whether Phase 6 ran the security review (step 1.5 wrote it). Step 4 is its own
   # shell and runs after step 1 removed the worktree, so copy the file out — a shell
   # variable set here would be gone by then. No state → no copy, never a stale one.
   cp "$WORKTREE/.ship/security-review-state" "/tmp/ship-${ID}-security-review-state" 2>/dev/null \
     || rm -f "/tmp/ship-${ID}-security-review-state"

   CODEX_ROUNDS_ARCHIVE=""
   CODEX_LAST_FINDINGS=""
   if [ -f "$WORKTREE/.ship/codex-rounds.md" ]; then
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     CODEX_LAST_FINDINGS=$(codex_round_last_findings "$WORKTREE")
     # Bound what goes into the notification. A report with a long bullet list
     # would otherwise be interpolated whole into $SUMMARY and can exceed a
     # Discord message limit — at which point the operator gets nothing at all
     # rather than a truncated list. The archive has the full text.
     CODEX_FINDINGS_TOTAL=$(printf '%s\n' "$CODEX_LAST_FINDINGS" | grep -c '^- ' || true)
     if [ "${CODEX_FINDINGS_TOTAL:-0}" -gt 12 ] 2>/dev/null; then
       CODEX_LAST_FINDINGS="$(printf '%s\n' "$CODEX_LAST_FINDINGS" | head -12)
   ... and $((CODEX_FINDINGS_TOTAL - 12)) more — see the archive below"
     fi
     # Copy it out. `.ship/` dies with the worktree, and a post-mortem of an
     # unattended overnight run has nothing else to read.
     CODEX_ROUNDS_ARCHIVE="/tmp/ship-${ID}-codex-rounds.md"
     cp "$WORKTREE/.ship/codex-rounds.md" "$CODEX_ROUNDS_ARCHIVE" 2>/dev/null \
       || CODEX_ROUNDS_ARCHIVE=""
   fi
   ```

1. **Remove worktree** — only when the work has actually landed.

   ```bash
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     echo "review open — the worktree is kept at $WORKTREE"
   else
     git worktree remove "$WORKTREE"
   fi
   ```

   In `mr` mode the worktree is kept: the review can come back with changes,
   and rebuilding it costs more than the disk it occupies. `/ship-land` removes
   it after the review merges.

   If this fails (e.g. uncommitted changes in worktree), print:
   ```
   WARN: worktree at $WORKTREE has uncommitted changes; not removed.
         Inspect with: cd $WORKTREE && git status
         When ready: git worktree remove --force $WORKTREE
   ```

2. **Delete worktree branch** — never while a review points at it.

   ```bash
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     echo "review open — branch $BRANCH is kept (the remote review needs it)"
   else
     git branch -d "$BRANCH"
   fi
   ```

   This guard is the reason the mode is resolved in this phase at all. The
   squash path's note below says to use `-D` when `-d` complains, which on an
   unmerged review branch would throw the work away.

   The squash merge in Phase 7 doesn't update branch reachability, so `-d` may complain. Use `-D` if needed; the work is already squashed onto $ORIG_BRANCH.

3. **Log + commit.** `squash`: in `$REPO`, on `$ORIG_BRANCH`. `mr`: in
   `$WORKTREE`, on the review branch — `ship_log` turns the row into a
   `Ship-Log:` commit trailer there, so it reaches the base branch's history with
   the review and parallel MRs never touch a shared file (R-001).

   ```bash
   # Only ships that actually ran codex carry a codex fragment. Ships that ran
   # executor 1 or 2 have no codex state, and an empty "codex:  round(s)" on
   # every row is noise that hides the rows where it means something.
   CODEX_LOG_FRAGMENT=""
   if [ "${CODEX_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
     CODEX_LOG_FRAGMENT=", codex: ${CODEX_ROUNDS} round(s) ${CODEX_FINAL_VERDICT}"
   fi
   SHIP_LOG_ROW="| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp, prune: ${PRUNE_STATUS}${CODEX_LOG_FRAGMENT}) | n |"
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     # Log and push from the review branch only. `cd ""` succeeds silently in
     # bash and zsh, so an unset $WORKTREE would otherwise leave this in $REPO on
     # the base branch — and the push would send the base branch to origin.
     (
       [ -n "$WORKTREE" ] && cd "$WORKTREE" \
         || { echo "Phase 9: WORKTREE is not set — nothing logged or pushed" >&2; exit 1; }
       CUR=$(git branch --show-current)
       # This ship's branch only: a WORKTREE left over from an earlier ship in the
       # same session would otherwise push this row into that ship's review.
       case "$CUR" in
         "ship/${ID}-"*) : ;;
         *) echo "Phase 9: refusing to log or push from '$CUR' — expected ship/${ID}-*" >&2
            exit 1 ;;
       esac
       ship_log "$SHIP_LOG_ROW" && git push origin "$CUR"
     )
   else
     ship_log "$SHIP_LOG_ROW"
     git add docs/learnings/_log.md
     git commit -m "log: ship ${ID}"
   fi
   ```

4. **Auto-mode success notification** (only if `AUTO=1`):

   Build the success message body:
   ```bash
   if [ "$AUTO" = "1" ]; then
     # Built from what step 0 captured, so it survives the worktree removal.
     CODEX_SUMMARY_BLOCK=""
     if [ "${CODEX_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
       CODEX_SUMMARY_BLOCK="
   • codex: ${CODEX_ROUNDS} round(s), final ${CODEX_FINAL_VERDICT}
${CODEX_LAST_FINDINGS}
   • full round history: ${CODEX_ROUNDS_ARCHIVE:-(not archived)}"
     fi
     SUMMARY="✅ ${ID} ${DESCRIPTION} shipped (squash ${MERGE_SHA})
   • blocking: 0 ✓
   • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
   • minor: ${MINOR_COUNT}
   • praise: ${PRAISE_COUNT}
   • security review: $(if [ "$(cat "/tmp/ship-${ID}-security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
   • CONTEXT.md: ${CONTEXT_MD_STATUS}
   • Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
   • Test pruning: ${PRUNE_STATUS}
   • ponytail: ${PONYTAIL_STATUS}
   • UA: ${UA_STATUS}${CODEX_SUMMARY_BLOCK}
   • decisions log: ${WORKTREE}/.claude/.ship-auto-decisions.md (kept in worktree pre-cleanup; copy if you want post-mortem)"

     case "$UA_STATUS" in
       rebuilt*) SUMMARY="${SUMMARY/• UA:/• 🔄 UA KG rebuilt UA:}" ;;
     esac
     if [ "$PONYTAIL_DRIFT" = "1" ]; then
       SUMMARY="${SUMMARY}
   ⚠ ponytail ${PONYTAIL_PINNED} -> ${PONYTAIL_CURRENT}, ruleset changed, this ship used the new version"
     fi

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

   The summary carries the **last round's bullets verbatim**, not a paraphrase. That
   list is the operator's only window into an unattended run, and its fifth element —
   the statement of what was *not* changed — is the blast radius of a failed round.
   Summarising destroys exactly the part that makes it scannable.

   `.ship/` dies with the worktree at step 1 of this phase, which is why step 0 reads
   it first and **copies it out** to `${CODEX_ROUNDS_ARCHIVE}` — the same caveat that
   already applies to `.ship-auto-decisions.md`, except here it is handled rather
   than warned about.

## Failure modes

- **Worktree create fails (dirty index)** → abort, hint `git stash; /ship-next ${ID}`
- **Brainstorm abandoned mid-flow** → user Ctrl-C; worktree remains. Resume via `/ship-next ${ID}` or destroy via `/ship-next --discard ${ID}`.
- **Executor fails mid-run** → log to plan's `## Execution log` (existing pattern); worktree remains.
- **code-review-skill not installed** → ERROR with install hint (Phase 6 step 1).
- **Merge conflict to original branch** → shouldn't happen (worktree forked from $ORIG_BRANCH and squash merges onto same fork point). If it does, abort merge, worktree intact, hint user to rebase.
- **Cleanup fails** → print worktree path, instruction to remove manually.
