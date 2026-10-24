# R-004 Refactor around ship-next — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ai_system becomes ship-workflow's home: `claude-skills/` holds ship-workflow, run-plan and code-review-skill only; ship-workflow keeps the five commands ship-next uses; `sync.sh` installs by symlink; no project needs a command copy.

**Architecture:** Deletions are explicit `git rm` lists; code-review-skill is vendored with `git archive` of upstream `17267ff`. Every other change is a `git apply` patch generated from a working prototype and replayed task by task against this base. New behaviour lives in three small libs (`live-checkout.sh`, `command-copies.sh`, the `airos-binding.sh` fix) and the rewritten `sync.sh`, each pinned by a bats file that executes it in a scratch HOME.

**Tech Stack:** bash (sync.sh must run on macOS's bash 3.2) + zsh (sourced libs), git ≥ 2.38, bats 1.13.

**Spec:** `docs/specs/R-004-refactor-around-ship-next.md` (Task 8 syncs it with what the build found).

## Global Constraints

- **Scope.** Edit only this repository. `claude-skills/` is this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/` or the operator's home directory — the new tests set their own `HOME` to a scratch dir. Do not run `./sync.sh restore` or `./sync.sh backup` against the real home.
- **Not part of this plan:** `.ship/` (scratch state; `.ship/proto` is a nested git repository). Stage only the paths each commit step names; never `git add -A`.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise.
- **Patches and commands are the code.** Each code step is a command list or a `git apply` heredoc, generated from and replayed against this exact base (`3a9a4fc`). They apply cleanly in order. If one does not apply, STOP — do not hand-edit around it.
- **Network.** Task 1 Step 3 clones `https://github.com/awesome-skills/code-review-skill`. If the clone fails, STOP and report it; do not vendor from anywhere else.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 9.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** no `local` inside a loop body; no unquoted globs that may match nothing; no `for x in $LIST` word-splitting in sourced libs.
- **Commits.** One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

Failure modes a person is most likely to hit, each pinned by a test in the owning task:

1. `restore` meeting a real directory where a link belongs (today's `run-plan` copy and `code-review-skill` clone) — it must move it aside, never delete it. → Task 6.
2. `restore` run a second time, or after an interrupted first run — nothing may change. → Task 6.
3. `restore` meeting a global CLAUDE.md that is newer than the repo's backup — it must ask, and a "no" keeps the live file. → Task 6.
4. A project whose tracked command copy carries local edits — it must be kept and reported, not force-removed. → Task 5.
5. `/ship-next` run inside its own worktree — the vault project must be the main checkout's, while test fixtures nested in a worktree keep their own names. → Task 3.

---
### Task 1: The repo holds ship-workflow, run-plan and code-review-skill — nothing else

Seam: repo contents

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.1, §3.2, §3.5, G1, G6, AC-1/AC-12/AC-13. The 53 other skill directories (gstack and its family, the gstack leftovers, the Obsidian family, `update-specification`) are not used by ship-next. run-plan gains the REPAIR RULE from `f2fd23f` — it reached ship/ship-brief but never main. code-review-skill, a live-only clone until now, is vendored from upstream `17267ff`.

**Files:**
- Delete: 53 directories under `claude-skills/` (exact list in Step 3)
- Create: `claude-skills/code-review-skill/` (38 files from upstream `17267ff`, plus `VENDORED.md`)
- Modify: `claude-skills/run-plan/SKILL.md` (the REPAIR RULE)
- Test: `claude-skills/ship-workflow/tests/test_repo-layout.bats` (new)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_repo-layout.bats b/claude-skills/ship-workflow/tests/test_repo-layout.bats
new file mode 100644
index 0000000..d31da86
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_repo-layout.bats
@@ -0,0 +1,25 @@
+#!/usr/bin/env bats
+# R-004: ai_system is ship-workflow's home. It holds ship-workflow and the two skills
+# ship-next needs — run-plan and code-review-skill — and nothing else.
+load helpers
+
+setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }
+
+@test "claude-skills holds exactly ship-workflow, run-plan and code-review-skill" {
+  run bash -c "ls -1 '$REPO_ROOT/claude-skills' | sort | tr '\n' ' '"
+  [ "$output" = "code-review-skill run-plan ship-workflow " ]
+}
+
+@test "run-plan carries the REPAIR RULE" {
+  grep -qF 'REPAIR RULE — small plan defects are yours to fix; do NOT stop for them:' \
+    "$REPO_ROOT/claude-skills/run-plan/SKILL.md"
+}
+
+@test "code-review-skill is vendored with its license and its source, without .git" {
+  d="$REPO_ROOT/claude-skills/code-review-skill"
+  [ -f "$d/SKILL.md" ] || return 1
+  [ -f "$d/LICENSE" ] || return 1
+  grep -qF 'https://github.com/awesome-skills/code-review-skill' "$d/VENDORED.md" || return 1
+  grep -qF '17267ff' "$d/VENDORED.md" || return 1
+  [ ! -e "$d/.git" ]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..3`, 0 ok, these 3 fail:
  - `not ok 1 claude-skills holds exactly ship-workflow, run-plan and code-review-skill`
  - `not ok 2 run-plan carries the REPAIR RULE`
  - `not ok 3 code-review-skill is vendored with its license and its source, without .git`

- [ ] **Step 3: Run the removal and vendoring commands**

````bash
git rm -r -q \
  claude-skills/autoplan claude-skills/benchmark claude-skills/benchmark-models \
  claude-skills/browse claude-skills/canary claude-skills/careful claude-skills/codex \
  claude-skills/connect-chrome claude-skills/context-restore claude-skills/context-save \
  claude-skills/cso claude-skills/defuddle claude-skills/design-consultation \
  claude-skills/design-html claude-skills/design-review claude-skills/design-shotgun \
  claude-skills/devex-review claude-skills/document-release claude-skills/freeze \
  claude-skills/gstack claude-skills/gstack-upgrade claude-skills/guard claude-skills/health \
  claude-skills/investigate claude-skills/json-canvas claude-skills/land-and-deploy \
  claude-skills/landing-report claude-skills/learn claude-skills/make-pdf \
  claude-skills/obsidian-bases claude-skills/obsidian-cli claude-skills/obsidian-markdown \
  claude-skills/obsidian-second-brain claude-skills/office-hours \
  claude-skills/open-gstack-browser claude-skills/pair-agent claude-skills/plan-ceo-review \
  claude-skills/plan-design-review claude-skills/plan-devex-review claude-skills/plan-eng-review \
  claude-skills/plan-tune claude-skills/qa claude-skills/qa-only claude-skills/retro \
  claude-skills/review claude-skills/scrape claude-skills/setup-browser-cookies \
  claude-skills/setup-deploy claude-skills/setup-gbrain claude-skills/ship claude-skills/skillify \
  claude-skills/unfreeze claude-skills/update-specification
rm -rf /tmp/r004-code-review-skill
git clone -q https://github.com/awesome-skills/code-review-skill /tmp/r004-code-review-skill
mkdir -p claude-skills/code-review-skill
git -C /tmp/r004-code-review-skill archive 17267ff | tar -x -C claude-skills/code-review-skill
````

- [ ] **Step 4: Apply the edits**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/run-plan/SKILL.md b/claude-skills/run-plan/SKILL.md
index 7928aa3..6f4a538 100644
--- a/claude-skills/run-plan/SKILL.md
+++ b/claude-skills/run-plan/SKILL.md
@@ -197,13 +197,23 @@ IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claud
 Your task: implement the plan below. Execute tasks in numerical order; within each task, execute steps in order.
 
 WORKFLOW:
-1. Use the exact code/text shown in each step. Do not improvise.
+1. Use the exact code/text shown in each step. Do not improvise beyond the REPAIR RULE below.
 2. Use TDD discipline where the plan asks for it: write failing test, confirm fail, then implement.
-3. After each task, verify tests are green before moving on. If they cannot be made green within the task, STOP and write a status note to the end of the plan file (append a "## Execution log" section if absent).
+3. After each task, verify tests are green before moving on. If they cannot be made green within the task (including via the REPAIR RULE), STOP and write a status note to the end of the plan file (append a "## Execution log" section if absent).
 4. Run tests with the commands the plan shows.
 5. Commit per the plan's commit messages — one commit per task unless the plan groups otherwise.
 6. At the end, report DONE / DONE_WITH_CONCERNS / BLOCKED with a summary.
 
+REPAIR RULE — small plan defects are yours to fix; do NOT stop for them:
+When the prescribed code fails a check, or breaks a requirement the plan itself states, and the fix is small and local, apply the smallest fix and continue. Typical cases:
+- a referenced file or test path does not exist, and exactly one obvious replacement does
+- an existing guard / registry / allow-list test needs the new item added (as its message or docstring instructs)
+- a lint rule rejects the prescribed structure (e.g. move a helper into its own module)
+- a missing null / empty guard is needed to keep output unchanged where the plan says it must not change
+- a grep or search the plan relies on misses a call site of the same pattern
+Record each one in the plan's "## Execution log" as "Deviation: <what> — <why>", and finish with DONE_WITH_CONCERNS listing them.
+STOP with BLOCKED only if the fix would change the approach or the behaviour the plan specifies, touch modules the task does not involve (other than the guard or test the failing check names), or delete, skip or loosen an assertion to make it pass.
+
 CONSTRAINTS:
 - Stay on branch \`$BRANCH\`. Do NOT switch branches.
 - Do NOT push to any remote.
@@ -213,6 +223,7 @@ CONSTRAINTS:
 - If a "fail first" test passes immediately (e.g., the test mirrors production logic), that's acceptable — just note it and move on.
 - If exact line numbers in the plan don't match the file, use surrounding context to locate the correct spot.
 - Pre-existing baseline failures (failing before your changes) are NOT yours to fix — note them and continue.
+- If you invoke \`/ship-next\` from a plan task, ALWAYS include \`--auto:yes\`. Codex cannot answer interactive prompts; \`/ship-next\` without \`--auto:yes\` will hang waiting for user input.
 
 PLAN ($PLAN_ABS):
 
@@ -243,13 +254,34 @@ pwd > "$CWD_FILE"
   echo "branch=$BRANCH"
   echo "cwd=$CWD"
   echo "started=$(date +%Y-%m-%dT%H:%M:%S)"
+  # Record the Discord channel that launched this run so the wakeup
+  # legacy adapter can route the done marker back. Injected by
+  # claudecode-discord's SessionManager via env. Empty when the skill
+  # is run from the terminal — legacy adapter degrades gracefully.
+  echo "channel_id=${WAKEUP_CHANNEL_ID:-}"
 } > "$META_FILE"
 
+# ALSO write a separate, stable channel file that manual retry logic
+# won't clobber. The meta file above is sometimes rewritten by Claude
+# during "resume from BLOCKED" retries with `>` (truncate) — losing
+# the channel_id line. The legacy adapter falls back to this file when
+# meta lacks channel_id. Only written when the env var is set — no
+# empty file when the skill is run from the terminal.
+if [ -n "$WAKEUP_CHANNEL_ID" ]; then
+  echo "$WAKEUP_CHANNEL_ID" > "/tmp/run-plan-channel-$SLOT.txt"
+fi
+
 # Pass the prompt via stdin (`-` reads prompt from stdin) instead of argv —
 # avoids macOS ARG_MAX (~256KB) limits if a plan ever gets very large.
+#
+# NO `-c model_reasoning_effort=...` here. This used to hardcode "high",
+# which silently overrode ~/.codex/config.toml — `-c` beats the config file,
+# so a user who deliberately set "low" globally still paid for high on every
+# run and had no way to see why except reading this skill. Model/effort is
+# the user's global setting; the skill does not get a vote. Override for one
+# run by appending `-c 'model_reasoning_effort="high"'` by hand.
 nohup codex exec - \
   --dangerously-bypass-approvals-and-sandbox \
-  -c 'model_reasoning_effort="high"' \
   < "$PROMPT_FILE" > "$LOG_FILE" 2>&1 &
 CODEX_PID=$!
 echo "$CODEX_PID" > "$PID_FILE"
@@ -273,7 +305,7 @@ even after codex finishes successfully.
 
 ```
 ScheduleWakeup(
-  delaySeconds=1800,
+  delaySeconds=270,
   reason="run-plan <slot> fallback poll — checks done marker, re-arms if still running",
   prompt="/run-plan status"
 )
@@ -291,7 +323,9 @@ Behavior when the wakeup fires:
    surface that and stop re-arming.
 
 This gives belt-and-suspenders coverage: Monitor wakes Claude in ~seconds
-when it works; ScheduleWakeup catches it within 30 min when it doesn't.
+when it works; ScheduleWakeup catches it within ~4.5 min when it doesn't
+(270s — stays inside the 5-min prompt cache TTL, so the wake-up doesn't
+pay a cache miss).
 
 ## Step 4: Heartbeat watcher
 
@@ -341,6 +375,30 @@ DONE_FILE=/tmp/run-plan-done-$SLOT.txt
   echo "status=$FINAL_STATUS"
 } > "$DONE_FILE"
 
+# Primary Discord wake-up: drop an atomic JSON into the bot's wake-up
+# directory. claudecode-discord's WakeupWatcher (fs.watch) picks it up
+# and re-invokes Claude on the originating channel with `/run-plan
+# status $SLOT`. Backward-compatible: silently skips if env vars aren't
+# set (skill run from terminal, or bot not present).
+if [ -n "$WAKEUP_CHANNEL_ID" ] && [ -n "$WAKEUP_DIR" ] && [ -d "$WAKEUP_DIR" ]; then
+  WAKEUP_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N)
+  WAKEUP_FILE="$WAKEUP_DIR/$WAKEUP_UUID.json"
+  # Escape backslashes and double quotes in FINAL_STATUS so it's JSON-safe.
+  # $FINAL_STATUS can contain quotes when a "DONE_WITH_CONCERNS: reason" line
+  # is captured from the log.
+  SAFE_STATUS=$(printf '%s' "$FINAL_STATUS" | sed 's/\\/\\\\/g; s/"/\\"/g')
+  cat > "$WAKEUP_FILE.tmp" << WAKEUP_JSON_END
+{
+  "channel_id": "$WAKEUP_CHANNEL_ID",
+  "prompt": "/run-plan status $SLOT",
+  "source": "run-plan",
+  "metadata": {"slot": "$SLOT", "status": "$SAFE_STATUS", "commits": "+$FINAL_COMMITS"},
+  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
+}
+WAKEUP_JSON_END
+  mv "$WAKEUP_FILE.tmp" "$WAKEUP_FILE"
+fi
+
 # Native OS notification — this is the reliable wake-up channel for the
 # human. The harness may or may not re-invoke Claude when this background
 # shell exits; the human always sees this popup.
diff --git a/claude-skills/code-review-skill/VENDORED.md b/claude-skills/code-review-skill/VENDORED.md
new file mode 100644
index 0000000..01d9794
--- /dev/null
+++ b/claude-skills/code-review-skill/VENDORED.md
@@ -0,0 +1,5 @@
+# Vendored
+
+Source: https://github.com/awesome-skills/code-review-skill @ `17267ff` (2026-06-05), copied with `git archive` — no `.git`, no local edits. License: `LICENSE` in this directory.
+
+ship-next Phase 6 runs this skill as its code review. To update it, replace this directory with `git archive <commit>` of the upstream repo and change the commit above.
R004_PATCH
````

- [ ] **Step 5: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..3`, all 3 ok, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add claude-skills
git commit -m "refactor(repo): R-004 Task 1 — the repo holds ship-workflow, run-plan and code-review-skill, nothing else"
```

### Task 2: ship-workflow keeps only ship-next and the commands it calls

Seam: repo contents

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.2, G2, AC-1/AC-11. Deletes ship-propose, ship-explain, ship-research, ship-decision, ship-roadmap and the files only they use; removes ship-next's dead proposal/explain checks; every kept command and doc now names only the five commands. ship-init is left to Task 5, which removes its copy step.

**Files:**
- Delete: 5 commands + 7 files only they used (exact list in Step 3)
- Modify: `commands/ship-next.md`, `commands/ship-idea.md`, `SKILL.md`, `README.md`, `references/*.md`, `templates/repo/BRAINSTORM.md` (all under `claude-skills/ship-workflow/`)
- Test: `claude-skills/ship-workflow/tests/test_repo-layout.bats` (two tests added)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_repo-layout.bats b/claude-skills/ship-workflow/tests/test_repo-layout.bats
index d31da86..c01754f 100644
--- a/claude-skills/ship-workflow/tests/test_repo-layout.bats
+++ b/claude-skills/ship-workflow/tests/test_repo-layout.bats
@@ -23,3 +23,17 @@ setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }
   grep -qF '17267ff' "$d/VENDORED.md" || return 1
   [ ! -e "$d/.git" ]
 }
+
+@test "ship-workflow keeps exactly the five commands ship-next uses" {
+  run bash -c "ls -1 '$SHIP_SKILL_ROOT/commands' | sort | tr '\n' ' '"
+  [ "$output" = "ship-compound.md ship-idea.md ship-init.md ship-land.md ship-next.md " ]
+}
+
+@test "no kept file sends anyone to a removed command or the old devsync install" {
+  # ship-init.md is pinned separately: its copy step goes away with the copies (R-004 §3.4).
+  cd "$SHIP_SKILL_ROOT"
+  run bash -c "grep -rnE '/ship-(propose|explain|research|decision|roadmap|brief|arch)([^a-z-]|$)|devsync push' \
+    commands/ship-next.md commands/ship-compound.md commands/ship-idea.md commands/ship-land.md \
+    SKILL.md README.md references templates lib"
+  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..5`, 3 ok, these 2 fail:
  - `not ok 4 ship-workflow keeps exactly the five commands ship-next uses`
  - `not ok 5 no kept file sends anyone to a removed command or the old devsync install`

- [ ] **Step 3: Run the removal commands**

````bash
git rm -q \
  claude-skills/ship-workflow/commands/ship-propose.md \
  claude-skills/ship-workflow/commands/ship-explain.md \
  claude-skills/ship-workflow/commands/ship-research.md \
  claude-skills/ship-workflow/commands/ship-decision.md \
  claude-skills/ship-workflow/commands/ship-roadmap.md \
  claude-skills/ship-workflow/lib/propose-helpers.sh \
  claude-skills/ship-workflow/tests/test_propose-helpers.bats \
  claude-skills/ship-workflow/templates/obsidian/PROPOSAL.md \
  claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md \
  claude-skills/ship-workflow/templates/repo/DECISION.md \
  claude-skills/ship-workflow/examples/example-proposal-R-001-full.md \
  claude-skills/ship-workflow/examples/example-proposal-R-006-lite.md
````

- [ ] **Step 4: Apply the edits**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/README.md b/claude-skills/ship-workflow/README.md
index 683ddea..2555852 100644
--- a/claude-skills/ship-workflow/README.md
+++ b/claude-skills/ship-workflow/README.md
@@ -1,6 +1,6 @@
 # Ship Workflow
 
-A Claude Code skill that installs a 10-command product development workflow into any repo.
+A Claude Code skill: a product development workflow built around `/ship-next`, with five commands installed once per machine.
 
 ## What it gives you
 
@@ -14,9 +14,15 @@ Roadmap → /ship-next mega-command → Worktree → Brainstorm → Spec → Pla
 
 ## Installation
 
-This skill is distributed via `ai_system/claude-skills/`. After `devsync`, it lives at `~/.claude/skills/ship-workflow/`.
+This skill lives in `ai_system/claude-skills/ship-workflow/`. In the ai_system checkout,
+on `main`, run once per machine:
 
-Bootstrap in any repo:
+```bash
+./sync.sh restore   # links ship-workflow, run-plan, code-review-skill and the 5 commands
+./sync.sh status    # every line should say ok
+```
+
+Bootstrap a repo (folders and vault stub only — no command copies):
 ```bash
 cd /path/to/your/repo
 /ship-init
@@ -24,23 +30,13 @@ cd /path/to/your/repo
 
 ## Commands
 
-**Core lifecycle (6):**
-
 | Command | Purpose |
 |---|---|
-| `/ship-init` | Scaffold workflow in current repo |
-| `/ship-idea` | Capture idea (IDEA-NNN) |
-| `/ship-decision` | Record decision (D-NNN) |
-| `/ship-roadmap` | Refresh ROADMAP.md |
 | `/ship-next` | End-to-end ship cycle: worktree → brainstorm → spec → plan → execute → review → merge |
-| `/ship-compound` | Learnings + promote patterns + close |
-
-**Knowledge-input bridges (2):**
-
-| Command | Purpose |
-|---|---|
-| `/ship-research <topic>` | Vault-first deep research via `/obsidian-research-deep` |
-| `/ship-propose [R-NNN]` | Produce prescriptive proposal docs for roadmap items |
+| `/ship-compound` | Learning + promote patterns + close (ship-next Phase 8) |
+| `/ship-idea` | Capture idea (IDEA-NNN); ship-next files review findings with it |
+| `/ship-land` | Finish an item shipped with `merge_mode: mr` |
+| `/ship-init` | Scaffold a repo; `--upgrade` removes old per-repo command copies |
 
 **UA integration** — `/ship-next` auto-picks up `.ua/knowledge-graph.json` if present in the target repo. See spec `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.
 
@@ -79,12 +75,8 @@ filters also see that category, and it may report pre-existing issues tagged
 cd claude-skills/ship-workflow
 bats tests/
 
-# Local install for development
-ln -sf $(pwd) ~/.claude/skills/ship-workflow
-# Link every command. Re-run after adding one — /ship-land existed for weeks
-# without a link and so could not be invoked.
-mkdir -p ~/.claude/commands
-for f in commands/*.md; do ln -sf ~/.claude/skills/ship-workflow/"$f" ~/.claude/commands/; done
+# Install for development: the links point at this checkout, so edits are live
+cd ../.. && ./sync.sh restore
 ```
 
 ## Specification
diff --git a/claude-skills/ship-workflow/SKILL.md b/claude-skills/ship-workflow/SKILL.md
index 66c1421..02f8384 100644
--- a/claude-skills/ship-workflow/SKILL.md
+++ b/claude-skills/ship-workflow/SKILL.md
@@ -1,50 +1,41 @@
 ---
 name: ship-workflow
-description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Installs 9 ship-* slash commands. Use when starting product development in a new repo, capturing ideas/decisions, planning roadmap, or shipping features through the /ship-next mega-command (worktree → brainstorm → spec → plan → execute → review → merge).
+description: Per-repo product development workflow integrating Superpowers (brainstorm/spec/plan/build) with Compound Engineering (roadmap/decision/learnings). Five ship-* slash commands, installed once per machine. Use when bootstrapping a repo for it, capturing an idea, or shipping a ROADMAP row through the /ship-next mega-command (worktree → brainstorm → spec → plan → execute → review → merge).
 ---
 
 # Ship Workflow
 
-Per-repo product development workflow. Installs 9 slash commands into a target repo's `.claude/commands/`:
+Product development workflow built around one mega-command, `/ship-next`. Its five
+commands are installed **once per machine** — `ai_system`'s `./sync.sh restore` links
+them into `~/.claude/commands/` — and every repo uses those. A repo carries no copies.
 
-**Core lifecycle (6):**
-- **`/ship-init`** — Bootstrap workflow (folders, commands, AIR-OS Product Brain stub)
-- **`/ship-idea <description>`** — Capture an idea (IDEA-NNN)
-- **`/ship-decision <topic>`** — Record an architectural decision (D-NNN)
-- **`/ship-roadmap`** — Refresh ROADMAP.md via ce-strategy
-- **`/ship-next [R-NNN] | --adhoc <desc> | --discard R-NNN`** — End-to-end ship cycle: open worktree → brainstorm → spec → plan → execute → strict code-review gate → squash-merge → cleanup
-- **`/ship-compound`** — Write learning + promote patterns + close Roadmap item
+- **`/ship-next [R-NNN] | --adhoc <desc> | --discard R-NNN`** — End-to-end ship cycle: open worktree → brainstorm → spec → plan → execute → strict code-review + security gate → squash-merge (or open an MR) → cleanup
+- **`/ship-compound`** — Write learning + promote patterns + close the Roadmap item (ship-next Phase 8 runs it)
+- **`/ship-idea <description>`** — Capture an idea (IDEA-NNN); ship-next Phase 6 files major and pre-existing findings with it
 - **`/ship-land [R-NNN]`** — Finish an item shipped via `merge_mode: mr`: verify the review merged, move the row to Done, remove the branch + worktree Phase 9 kept
-
-**Knowledge bridges (3):**
-- **`/ship-research <topic>`** — Vault-first deep research (thin wrapper over `/obsidian-research-deep`)
-- **`/ship-propose [R-NNN]`** — Produce **prescriptive** proposal doc for a Roadmap item; orchestrates ship-research as sub-step; Self-FAQ pattern is the forcing function
-- **`/ship-explain [R-NNN | --all-now]`** — Generate plain-language explainer note for a ROADMAP row (so non-domain readers understand what a row actually does); auto-invoked during decompose and `/ship-next` pre-flight
+- **`/ship-init`** — Bootstrap a repo (folders, AIR-OS Product Brain stub); `--upgrade` removes old per-repo command copies
 
 - **UA integration**: `/ship-next` auto-detects `.ua/knowledge-graph.json` in the target repo and injects UA blast-radius context into Phase 3 (brainstorm), Phase 6 (review), and Phase 8 (compound). Silent no-op when UA absent. See `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.
 
 ## Dual-Brain Architecture
 
 - **Obsidian Product Brain** at AIR-OS `10 Projects/<repo-name>/`:
-  - VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS (manual + ship-roadmap)
+  - VISION / STRATEGY / ROADMAP / QUARTERLY_GOALS (edited by hand; `--adhoc` inserts ROADMAP rows)
   - `Architecture/` (hand-written POCKET/JOURNEY/GLOSSARY/REMINDERS + cases/; optional `.ua/knowledge-graph.json` in target repo for descriptive code graph via UA plugin)
-  - `Proposals/` (ship-propose, prescriptive)
-  - `Research/` (ship-research, external grounding)
 - **Repo Execution Brain** at `<repo>/docs/`:
   - `ideas/` `decisions/` `brainstorms/` `specs/` `plans/` `learnings/`
   - `product/` (mirror of vault strategy + roadmap)
-  - `proposals/` (mirror of vault Proposals/)
 - One-way sync (Obsidian → repo) on every ship-* command invocation, with 60-second freshness window
 
 ## Usage
 
 ```bash
-# Install (once, in ai_system repo via devsync)
-$ devsync push          # makes ~/.claude/skills/ship-workflow/ available
+# Install (once per machine, in the ai_system checkout, on main)
+$ ./sync.sh restore     # links ship-workflow, run-plan, code-review-skill + the 5 commands
 
 # Per-repo init
 $ cd /path/to/your/repo
-$ /ship-init            # adds .claude/commands/ + docs/ + AIR-OS strategy files
+$ /ship-init            # adds docs/ + AIR-OS strategy files (no command copies)
 
 # Daily flow
 $ /ship-next            # pick from Roadmap → end-to-end ship cycle (auto-calls /ship-compound at Phase 8)
@@ -71,7 +62,7 @@ The shadow-mode ship count is derived from `docs/learnings/_log.md` and is delib
 ## Standing rule: background agents do not survive a session boundary
 
 Measured on this machine, not assumed. Across two sampled sessions, nine
-dispatched background agents produced nothing: a `/ship-research` run lost two
+dispatched background agents produced nothing: a research run lost two
 full research rounds at Phase 3 and had to redo them inline, and a
 `subagent-driven-development` run lost six agents, twice re-dispatching the
 *identical* fix before the work was finally done inline. Every one of them
@@ -87,7 +78,7 @@ So, before dispatching any background agent:
    work inline. A second dispatch of the same task is the single most expensive
    mistake in the sampled history.
 3. **Checkpoint multi-phase work to disk after every phase**, not at the end.
-   The `/ship-research` loss was two completed phases thrown away because
+   The research-run loss was two completed phases thrown away because
    nothing was written until Phase 4.
 
 `/ship-next` Phase 5 executor 1 (`subagent-driven-development`) is subject to
diff --git a/claude-skills/ship-workflow/commands/ship-idea.md b/claude-skills/ship-workflow/commands/ship-idea.md
index 979bab2..2acca76 100644
--- a/claude-skills/ship-workflow/commands/ship-idea.md
+++ b/claude-skills/ship-workflow/commands/ship-idea.md
@@ -85,7 +85,7 @@ You are capturing a new idea into `docs/ideas/IDEA-NNN-<slug>.md`.
    git commit -m "idea: $ID $description"
    ```
 
-9. **Report:** Tell the user the ID + file path + 1-line summary, and offer "Want to graduate this into a Roadmap item via /ship-roadmap?" if confidence is medium+ or impact is high.
+9. **Report:** Tell the user the ID + file path + 1-line summary, and offer to add it to ROADMAP.md as a Roadmap item if confidence is medium+ or impact is high.
 
 ## Failure modes
 
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 10ae6ca..6dbdddd 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -169,21 +169,14 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
       if [ -z "$DONE_WHEN" ]; then
         echo "ERROR: --auto:yes refused — R-NNN $ID has no ↳ done when: annotation." >&2
         echo "       fire-and-forget mode requires an explicit success criterion." >&2
-        echo "       Run /ship-roadmap (or edit ROADMAP.md to add ↳ done when: <criterion>)," >&2
+        echo "       Add a ↳ done when: <criterion> line under the row in ROADMAP.md," >&2
         echo "       then re-invoke /ship-next $ID --auto:yes." >&2
         exit 2
       fi
-
-      # Recommended (warn only): explainer + proposal
-      EXPLAIN=$(echo "$ROW" | grep "↳ explain:" || true)
-      [ -z "$EXPLAIN" ] && echo "WARN: $ID has no ↳ explain: annotation — brainstorm may pick defaults that don't match your intent" >&2
-
-      PROPOSAL=$(ls "$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Proposals/"*"${ID}"*"-proposal.md" 2>/dev/null | head -1)
-      [ -z "$PROPOSAL" ] && echo "WARN: $ID has no proposal — brainstorm design space is less constrained" >&2
     fi
     ```
 
-5. **Derive slug.** From ROADMAP row description, kebab-case English slug 3-5 words, leading imperative verb when possible. Example: "Wire SceneEngine into dialogue.py..." → `wire-scene-engine`. Same convention as `/ship-explain`.
+5. **Derive slug.** From ROADMAP row description, kebab-case English slug 3-5 words, leading imperative verb when possible. Example: "Wire SceneEngine into dialogue.py..." → `wire-scene-engine`.
 
 6. **Compute worktree path:**
    ```bash
@@ -311,9 +304,7 @@ When UA plugin + repo KG are both present and the KG's baseline commit differs f
    - `ls docs/plans/${ID}-${SLUG}.md` exists → skip to Phase 5 (executor).
    - `git log --oneline ${ORIG_BRANCH}..HEAD | wc -l` > 2 → executor has committed; skip to Phase 6 (review).
 
-1. **Proposal check** (same as existing /ship-next pre-step): look for `<vault>/Proposals/*-${ID}-*-proposal.md`. If `status: accepted`, load §1-§7 as brainstorm context.
-
-2. **Invoke `superpowers:brainstorming`** with context: spec target `docs/specs/${ID}-${SLUG}.md`, project `<project_name>`, proposal context (if loaded).
+1. **Invoke `superpowers:brainstorming`** with context: spec target `docs/specs/${ID}-${SLUG}.md`, project `<project_name>`.
 
    Also pass a **required output section: `## Seams`** — a three-column table
    (Seam | Interface | Guaranteed behavior) declaring every boundary this work
@@ -333,9 +324,9 @@ When UA plugin + repo KG are both present and the KG's baseline commit differs f
    ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P3" "spec review → auto-approved"
    ```
 
-3. **Verify outputs**: `docs/brainstorms/${ID}-${SLUG}.md` + `docs/specs/${ID}-${SLUG}.md` exist.
+2. **Verify outputs**: `docs/brainstorms/${ID}-${SLUG}.md` + `docs/specs/${ID}-${SLUG}.md` exist.
 
-3.5. **Dual-write spec to vault** (Obsidian visibility):
+2.5. **Dual-write spec to vault** (Obsidian visibility):
 
     ```bash
     VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
@@ -354,7 +345,7 @@ When UA plugin + repo KG are both present and the KG's baseline commit differs f
     fi
     ```
 
-4. **Commit:**
+3. **Commit:**
    ```bash
    git add docs/brainstorms/${ID}-${SLUG}.md docs/specs/${ID}-${SLUG}.md
    git commit -m "brainstorm+spec: ${ID} ${SLUG}"
diff --git a/claude-skills/ship-workflow/references/ce-skill-mapping.md b/claude-skills/ship-workflow/references/ce-skill-mapping.md
index 11c6c65..6d6ecc3 100644
--- a/claude-skills/ship-workflow/references/ce-skill-mapping.md
+++ b/claude-skills/ship-workflow/references/ce-skill-mapping.md
@@ -4,11 +4,8 @@
 |---|---|---|
 | `ship-init` | (none) | n/a |
 | `ship-idea` | optional `compound-engineering:ce-ideate` (only on user request) | Skip ideation; just capture |
-| `ship-decision` | optional `compound-engineering:ce-doc-review` | Write decision manually |
-| `ship-roadmap` | `compound-engineering:ce-strategy` (preferred) or `ce-plan` | Re-rank in conversation, show reasoning |
 | `ship-next` | `superpowers:brainstorming` + `superpowers:writing-plans` + user-chosen executor + code-review-skill | Required — no fallback for brainstorm/spec/plan/review |
 | `ship-compound` | `compound-engineering:ce-compound` + `ce-promote` | Hand-write learning sections |
-| `ship-research` | `obsidian-second-brain:/obsidian-research-deep` | Same — tell user to keep that skill |
 
 `/ship-next` now spans the former brainstorm/spec plus plan/execute range: it opens the worktree, produces brainstorm/spec artifacts, writes the plan, runs the chosen executor, enforces the strict code-review gate, squash-merges, and then invokes `/ship-compound`.
 
diff --git a/claude-skills/ship-workflow/references/discord-integration.md b/claude-skills/ship-workflow/references/discord-integration.md
index cff7efb..7798958 100644
--- a/claude-skills/ship-workflow/references/discord-integration.md
+++ b/claude-skills/ship-workflow/references/discord-integration.md
@@ -13,11 +13,7 @@ Not every ship-* command makes sense from Discord. Frontmatter `discord-visible:
 | Command | Discord-visible | Why |
 |---|---|---|
 | `/ship-idea <description>` | ✅ true | Fast capture, perfect for mobile |
-| `/ship-decision <topic>` | ✅ true | Record ADR from any conversation |
-| `/ship-roadmap` | ✅ true | Bounded, async-friendly |
 | `/ship-compound` | ✅ true | One-shot wrap-up |
-| `/ship-research <topic>` | ✅ true | Async, perfect for Discord |
-| `/ship-propose [R-NNN]` | ✅ true | Async proposal drafting before implementation |
 | `/ship-init` | ❌ false | Filesystem bootstrap; do on terminal |
 | `/ship-next` | ❌ false | Interactive brainstorming; doesn't fit Discord roundtrips |
 
@@ -86,7 +82,7 @@ After updating ship-workflow:
 2. **Restart the bot.** It re-runs discovery on startup.
 
 3. **In Discord, type `/`.** You should see:
-   - `/ship-idea`, `/ship-decision`, `/ship-roadmap`, `/ship-compound`, `/ship-research`, `/ship-propose` (6 visible)
+   - `/ship-idea`, `/ship-compound` (2 visible)
    - NOT `/ship-init`, `/ship-next` (2 hidden by `discord-visible: false`)
 
 4. **In a registered channel, try `/ship-idea test from discord`.** Bot should respond with streaming Claude Code output, and `docs/ideas/IDEA-NNN-test-from-discord.md` should appear in the repo.
diff --git a/claude-skills/ship-workflow/references/escape-hatches.md b/claude-skills/ship-workflow/references/escape-hatches.md
index 1794e15..c1ff0b2 100644
--- a/claude-skills/ship-workflow/references/escape-hatches.md
+++ b/claude-skills/ship-workflow/references/escape-hatches.md
@@ -28,10 +28,9 @@ While `/ship-next` is running:
 
 ```
 /ship-idea --during-ship-next "Maybe rich menu can use templated variants"
-/ship-decision --during-ship-next "Switch to celery-task for retries"
 ```
 
-Both produce normal IDEA-NNN / D-NNN files but with extra frontmatter:
+It produces a normal IDEA-NNN file, but with extra frontmatter:
 
 ```yaml
 related-roadmap-item: R-018          # the current ship cycle's ID
@@ -40,13 +39,11 @@ created-during: ship-next            # the phase
 
 This lets `/ship-compound` later sweep up all captures from this ship cycle into the learning.
 
-## Worktree-cwd-block (3 commands)
+## Worktree-cwd-block
 
 The following commands refuse to run inside a ship/* worktree because they modify cross-cutting state on main:
 
-- `/ship-roadmap` — modifies ROADMAP.md (canonical)
 - `/ship-init` — scaffolds repo + vault state
-- `/ship-propose` — writes to Proposals/
 
 If you invoke any of these inside a worktree, you'll see:
 
diff --git a/claude-skills/ship-workflow/references/flow-diagrams.md b/claude-skills/ship-workflow/references/flow-diagrams.md
index 981edca..343315a 100644
--- a/claude-skills/ship-workflow/references/flow-diagrams.md
+++ b/claude-skills/ship-workflow/references/flow-diagrams.md
@@ -17,22 +17,11 @@
         │ /ship-idea      │───▶│ docs/ideas/     │
         └─────────────────┘    │ IDEA-NNN-*.md   │
                                └────────┬────────┘
-                                        │ (some graduate)
-                                        ▼
-        ┌─────────────────┐    ┌─────────────────┐
-        │ /ship-decision  │───▶│ docs/decisions/ │
-        └─────────────────┘    │ D-NNN-*.md      │
-                               └────────┬────────┘
-                                        │
+                                        │ (some graduate into ROADMAP.md rows)
                                         ▼
                             ┌─────────────────┐
-                            │ /ship-roadmap   │ (refresh ranking)
-                            └────────┬────────┘
-                                     │
-                                     ▼
-                            ┌─────────────────┐
-                            │ /ship-next      │ ◀── /ship-research <topic>
-                            │ (mega)          │     (fill gap before brainstorm or implementation)
+                            │ /ship-next      │
+                            │ (mega)          │
                             └────────┬────────┘
                                      │
                                      ▼
@@ -43,16 +32,10 @@
                                      └─▶ back to /ship-next
 ```
 
-## Knowledge-input bridge commands
-
-`/ship-research` (external grounding) and UA's `/understand` / `/understand-explain` (code understanding) are **optional inputs**:
-
-```
-   /ship-research  ────▶ │ AIR-OS 10 Projects/<P>/Research/         │
-   UA /understand  ────▶ │ target-repo/.ua/knowledge-graph.json    │
-```
+## Optional input
 
-These commands DELEGATE to the underlying obsidian-second-brain skill commands (`/obsidian-architect` and `/obsidian-research-deep`) but add ship housekeeping (sync, _log.md, commit).
+UA's `/understand` (code understanding) is an optional input: when
+`target-repo/.ua/knowledge-graph.json` exists, ship-next reads it in Phases 3, 6 and 8.
 
 ## Dual-brain sync
 
diff --git a/claude-skills/ship-workflow/templates/repo/BRAINSTORM.md b/claude-skills/ship-workflow/templates/repo/BRAINSTORM.md
index 921442f..feb2ae3 100644
--- a/claude-skills/ship-workflow/templates/repo/BRAINSTORM.md
+++ b/claude-skills/ship-workflow/templates/repo/BRAINSTORM.md
@@ -18,7 +18,7 @@ parent: null   # if this is a child of an epic R-NNN, set to that R-NNN
 #   them against. Re-sync this string back to ROADMAP after the spec lands.
 success-criteria: "<one observable line — CI green, metric threshold, or user-visible behavior>"
 # estimated-effort: rough size. d = days, w = weeks. If > 1w, the item is
-#   probably still too big and should be decomposed (see /ship-roadmap step 6).
+#   probably still too big and should be decomposed into several ROADMAP rows.
 estimated-effort: "<Nd | Nw>"
 ---
 
R004_PATCH
````

- [ ] **Step 5: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..5`, all 5 ok, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "refactor(ship-workflow): R-004 Task 2 — keep only ship-next and the commands it calls"
```

### Task 3: `airos-binding.sh` names a linked worktree after its main checkout

Seam: `airos-binding.sh project_name`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.8, AC-15. At a ship-next worktree's root, `basename $(pwd)` was the worktree's own name, so R-001's and R-003's spec mirrors went to bogus `10 Projects/R-00N-…/` vault folders. Only that case changes: a plain directory nested inside a worktree (the suite's fixtures) keeps its own name.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/airos-binding.sh`
- Test: `claude-skills/ship-workflow/tests/test_airos-binding.bats` (two tests added)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_airos-binding.bats b/claude-skills/ship-workflow/tests/test_airos-binding.bats
index 2905414..78d1988 100644
--- a/claude-skills/ship-workflow/tests/test_airos-binding.bats
+++ b/claude-skills/ship-workflow/tests/test_airos-binding.bats
@@ -79,3 +79,26 @@ EOF
   result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" code_root)"
   [ -z "$result" ]
 }
+
+# --- R-004 §3.8: a ship-next worktree is named after its main checkout ---------
+
+@test "airos-binding: at a linked worktree's root the project is the main checkout" {
+  # basename(pwd) there is the worktree's own name, so R-001/R-003 mirrored their specs
+  # into bogus "10 Projects/R-00N-…" vault folders.
+  mkdir -p "$SCRATCH/my-repo" && cd "$SCRATCH/my-repo" || return 1
+  git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
+  git worktree add -q -b ship/R-9-x "$SCRATCH/my-repo-worktrees/R-9-x"
+  cd "$SCRATCH/my-repo-worktrees/R-9-x" || return 1
+  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_name)" = "my-repo" ] || return 1
+  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)" = "$AIROS/10 Projects/my-repo" ]
+}
+
+@test "airos-binding: a plain directory inside a linked worktree keeps its own name" {
+  # The fixtures above live in non-git dirs nested in whatever checkout runs the suite —
+  # often a ship-next worktree. They must not inherit that checkout's name.
+  mkdir -p "$SCRATCH/outer" && cd "$SCRATCH/outer" || return 1
+  git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
+  git worktree add -q -b ship/R-9-y "$SCRATCH/outer-wt"
+  mkdir -p "$SCRATCH/outer-wt/fixture/my-repo" && cd "$SCRATCH/outer-wt/fixture/my-repo" || return 1
+  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_name)" = "my-repo" ]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_airos-binding.bats; cd - >/dev/null`

Expected: `1..9`, 8 ok, these 1 fail:
  - `not ok 8 airos-binding: at a linked worktree's root the project is the main checkout`

- [ ] **Step 3: Implement**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/lib/airos-binding.sh b/claude-skills/ship-workflow/lib/airos-binding.sh
index 517c7ba..bb42d19 100755
--- a/claude-skills/ship-workflow/lib/airos-binding.sh
+++ b/claude-skills/ship-workflow/lib/airos-binding.sh
@@ -60,7 +60,25 @@ if [ -f "$PER_REPO_CFG" ]; then
   ROADMAP_MODE_OVERRIDE="$(read_yaml_key "$PER_REPO_CFG" roadmap_mode)"
 fi
 
-PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(basename "$(pwd)")}"
+# At the root of a linked worktree (ship-next's ship/R-NNN-* checkouts), basename(pwd)
+# is the worktree's own name, and R-001/R-003 mirrored their specs into bogus
+# "10 Projects/R-00N-…" vault folders that way (R-004 §3.8). There, name the project
+# after the main checkout. Anywhere else — the main checkout, a subdirectory, a plain
+# directory nested inside some checkout — keep basename(pwd).
+_project_dir_name() {
+  local top gd common
+  top=$(git rev-parse --show-toplevel 2>/dev/null) || { basename "$(pwd)"; return; }
+  gd=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)
+  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
+  if [ "$top" = "$(pwd -P)" ] && [ -n "$common" ] && [ "$gd" != "$common" ] \
+     && [ "$(basename "$common")" = .git ]; then
+    basename "$(dirname "$common")"
+  else
+    basename "$(pwd)"
+  fi
+}
+
+PROJECT_NAME="${PROJECT_NAME_OVERRIDE:-$(_project_dir_name)}"
 ROADMAP_MODE="${ROADMAP_MODE_OVERRIDE:-$ROADMAP_MODE_GLOBAL}"
 
 case "${1:-}" in
R004_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_airos-binding.bats; cd - >/dev/null`

Expected: `1..9`, all 9 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(airos-binding): R-004 Task 3 — a linked worktree is named after its main checkout"
```

### Task 4: ship-next warns when the live ship-workflow checkout is off main or dirty

Seam: `live_checkout_warning`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.7, G5, AC-10. Every session on the machine runs the checkout behind `~/.claude/skills/ship-workflow`; the operator's sat on `ship/ship-brief`, which lacked R-001. New Phase 1 step 0.5 warns, never blocks.

**Files:**
- Create: `claude-skills/ship-workflow/lib/live-checkout.sh`
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 1 step 0.5)
- Test: `claude-skills/ship-workflow/tests/test_live-checkout.bats` (new)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_live-checkout.bats b/claude-skills/ship-workflow/tests/test_live-checkout.bats
new file mode 100644
index 0000000..cc464d6
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_live-checkout.bats
@@ -0,0 +1,64 @@
+#!/usr/bin/env bats
+# R-004 §3.7: every session on a machine runs the checkout behind
+# ~/.claude/skills/ship-workflow, uncommitted edits included. ship-next warns when that
+# checkout is not on main, or is dirty — the machine is not running what shipped.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch live-checkout)"
+  export HOME="$SCRATCH/home"
+  mkdir -p "$HOME/.claude/skills" "$SCRATCH/ai"
+  cd "$SCRATCH/ai" || return 1
+  git init -q -b main
+  mkdir -p claude-skills/ship-workflow && echo x > claude-skills/ship-workflow/SKILL.md
+  git add -A && git -c user.email=t@t -c user.name=t commit -q -m base
+  ln -s "$SCRATCH/ai/claude-skills/ship-workflow" "$HOME/.claude/skills/ship-workflow"
+  source "$SHIP_LIB/live-checkout.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+@test "live_checkout_warning: names the branch when the live checkout is off main" {
+  git checkout -q -b ship/R-9-x
+  run live_checkout_warning
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"ship/R-9-x"* ]]
+}
+
+@test "live_checkout_warning: on main, warns about uncommitted changes to tracked files" {
+  echo y >> claude-skills/ship-workflow/SKILL.md
+  run live_checkout_warning
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"uncommitted"* ]]
+}
+
+@test "live_checkout_warning: silent on a clean main, and an untracked file does not count" {
+  echo scratch > untracked.txt
+  run live_checkout_warning
+  [ "$status" -eq 0 ]
+  [ -z "$output" ]
+}
+
+@test "live_checkout_warning: silent when the live skill is not a link into a checkout" {
+  rm "$HOME/.claude/skills/ship-workflow" && mkdir -p "$HOME/.claude/skills/ship-workflow"
+  run live_checkout_warning
+  [ "$status" -eq 0 ]
+  [ -z "$output" ]
+}
+
+@test "ship-next Phase 1 runs the live-checkout warning, from the lib it sources" {
+  CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
+  blk=$(awk '/^0\.5\. \*\*Which ship-workflow is live/{f=1} /^1\. \*\*Handle `--discard`/{f=0} f' "$CMD" \
+        | awk '/^[[:space:]]*```bash[[:space:]]*$/{b=1;next} /^[[:space:]]*```[[:space:]]*$/{b=0} b')
+  [ -n "$blk" ] || { echo "no Phase 1 step 0.5 block"; return 1; }
+  # Run the block itself. The live checkout carries the lib and sits off main, so the
+  # block must print exactly the warning the function prints.
+  mkdir -p claude-skills/ship-workflow/lib
+  cp "$SHIP_LIB/live-checkout.sh" claude-skills/ship-workflow/lib/
+  git add -A && git -c user.email=t@t -c user.name=t commit -q -m lib
+  git checkout -q -b ship/R-9-z
+  printf '%s\n' "$blk" > "$SCRATCH/p1.sh"
+  run bash "$SCRATCH/p1.sh"
+  [ "$status" -eq 0 ] || return 1
+  [[ "$output" == *"ship/R-9-z"* ]] || return 1
+  [ "$output" = "$(live_checkout_warning 2>&1)" ]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_live-checkout.bats; cd - >/dev/null`

Expected: `1..5`, 0 ok, these 5 fail:
  - `not ok 1 live_checkout_warning: names the branch when the live checkout is off main`
  - `not ok 2 live_checkout_warning: on main, warns about uncommitted changes to tracked files`
  - `not ok 3 live_checkout_warning: silent on a clean main, and an untracked file does not count`
  - `not ok 4 live_checkout_warning: silent when the live skill is not a link into a checkout`
  - `not ok 5 ship-next Phase 1 runs the live-checkout warning, from the lib it sources`

- [ ] **Step 3: Implement**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 6dbdddd..7cce7da 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -95,6 +95,15 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    fi
    ```
 
+0.5. **Which ship-workflow is live?** Every session on this machine runs the checkout
+   behind `~/.claude/skills/ship-workflow`, uncommitted edits included. Off `main`, or
+   dirty, that is not what shipped (R-004). This only warns:
+
+   ```bash
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/live-checkout.sh && live_checkout_warning
+   ```
+
 1. **Handle `--discard`** (now safely after mutex check):
 
    ```bash
diff --git a/claude-skills/ship-workflow/lib/live-checkout.sh b/claude-skills/ship-workflow/lib/live-checkout.sh
new file mode 100644
index 0000000..8c2e33a
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/live-checkout.sh
@@ -0,0 +1,23 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/live-checkout.sh
+# Every session on this machine runs the checkout behind ~/.claude/skills/ship-workflow
+# — a symlink into the ai_system working tree — uncommitted edits included. When that
+# checkout sits on a feature branch, the whole machine runs the branch: langlive ran a
+# /ship-land that predated R-001 that way (R-004 §1, §3.7).
+
+# live_checkout_warning — print one warning line when the live checkout is off main or
+# has uncommitted changes to tracked files. Silent otherwise, and when the live skill is
+# not a link into a git checkout. Always exits 0: it informs, it never blocks.
+live_checkout_warning() {
+  local link="$HOME/.claude/skills/ship-workflow" dir top branch
+  [ -L "$link" ] || return 0
+  dir=$(cd "$link" 2>/dev/null && pwd -P) || return 0
+  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
+  branch=$(git -C "$top" branch --show-current 2>/dev/null)
+  if [ "$branch" != "main" ]; then
+    echo "WARN: the live ship-workflow runs from ${top} on branch '${branch:-detached HEAD}', not main — every session on this machine runs that branch." >&2
+  elif [ -n "$(git -C "$top" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
+    echo "WARN: the live ship-workflow (${top}, main) has uncommitted changes — every session on this machine runs them." >&2
+  fi
+  return 0
+}
R004_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_live-checkout.bats; cd - >/dev/null`

Expected: `1..5`, all 5 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-next): R-004 Task 4 — warn when the live ship-workflow checkout is off main or dirty"
```

### Task 5: No project carries a command copy: `remove_command_copies`, and ship-init stops copying

Seam: `remove_command_copies`, `ship-init`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.4, G4, AC-7/AC-8/AC-8b/AC-9. ship-init copied the commands into every repo; 60 copies in 6 repos went stale. The removal is a standalone lib so rollout can run it from ai_system — each repo's old ship-init.md copy would re-copy instead.

**Files:**
- Create: `claude-skills/ship-workflow/lib/command-copies.sh`
- Modify: `claude-skills/ship-workflow/commands/ship-init.md`
- Test: `claude-skills/ship-workflow/tests/test_command-copies.bats` (new)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-copies.bats b/claude-skills/ship-workflow/tests/test_command-copies.bats
new file mode 100644
index 0000000..297151e
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_command-copies.bats
@@ -0,0 +1,78 @@
+#!/usr/bin/env bats
+# R-004 §3.4: ship-workflow commands are installed once per machine, so no project
+# carries a copy. ship-init used to copy commands/*.md into every repo, and on
+# 2026-10-23 six repos held 60 copies, none current. remove_command_copies clears them.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch command-copies)"
+  export HOME="$SCRATCH/home"
+  mkdir -p "$HOME/.claude/commands" "$SCRATCH/live"
+  echo live > "$SCRATCH/live/ship-next.md"
+  ln -s "$SCRATCH/live/ship-next.md" "$HOME/.claude/commands/ship-next.md"
+  mkdir -p "$SCRATCH/repo/.claude/commands" && cd "$SCRATCH/repo" || return 1
+  git init -q -b main
+  git config user.email t@t && git config user.name t
+  printf '%s\n' '.claude/commands/ship-build.md' > .gitignore
+  for f in ship-next ship-propose my-own ship-build; do echo "$f" > ".claude/commands/$f.md"; done
+  git add .gitignore .claude/commands/ship-next.md .claude/commands/ship-propose.md .claude/commands/my-own.md
+  git commit -q -m base
+  source "$SHIP_LIB/command-copies.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+@test "remove_command_copies: tracked copies are git rm'd and staged, ignored ones deleted, others kept" {
+  head_before=$(git rev-parse HEAD)
+  run remove_command_copies "$SCRATCH/repo"
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [ ! -e .claude/commands/ship-next.md ] && [ ! -e .claude/commands/ship-propose.md ] || return 1
+  [ ! -e .claude/commands/ship-build.md ] || { echo "ignored copy kept"; return 1; }
+  [ -f .claude/commands/my-own.md ] || { echo "removed a non-ship command"; return 1; }
+  [ "$(git diff --cached --name-status | sort | tr '\n' ' ')" = "D	.claude/commands/ship-next.md D	.claude/commands/ship-propose.md " ] || return 1
+  [ "$(git rev-parse HEAD)" = "$head_before" ] || { echo "it committed"; return 1; }
+}
+
+@test "remove_command_copies: refuses, removing nothing, when the user-level ship-next does not resolve" {
+  rm "$SCRATCH/live/ship-next.md"   # the link now dangles
+  run remove_command_copies "$SCRATCH/repo"
+  [ "$status" -ne 0 ] || return 1
+  [[ "$output" == *"ship-next.md"* ]] || return 1
+  [ "$(ls .claude/commands | sort | tr '\n' ' ')" = "my-own.md ship-build.md ship-next.md ship-propose.md " ]
+}
+
+@test "remove_command_copies: works in a linked worktree" {
+  git worktree add -q -b wt "$SCRATCH/repo-wt"
+  echo ship-build > "$SCRATCH/repo-wt/.claude/commands/ship-build.md"
+  run remove_command_copies "$SCRATCH/repo-wt"
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  cd "$SCRATCH/repo-wt" || return 1
+  [ "$(git diff --cached --name-status | sort | tr '\n' ' ')" = "D	.claude/commands/ship-next.md D	.claude/commands/ship-propose.md " ] || return 1
+  [ ! -e .claude/commands/ship-build.md ] && [ -f .claude/commands/my-own.md ]
+}
+
+@test "remove_command_copies: a tracked copy with local edits is left alone and reported" {
+  echo "my local tweak" >> .claude/commands/ship-next.md
+  run remove_command_copies "$SCRATCH/repo"
+  [ "$status" -eq 0 ] || return 1
+  grep -qF 'my local tweak' .claude/commands/ship-next.md || { echo "local edits lost"; return 1; }
+  [[ "$output" == *"ship-next.md"* ]] || return 1
+  [ ! -e .claude/commands/ship-propose.md ]
+}
+
+@test "ship-init no longer copies commands, and its --upgrade step removes the copies" {
+  CMD="$SHIP_SKILL_ROOT/commands/ship-init.md"
+  if grep -nE 'cp [^ ]*ship-workflow/commands|git add [^|]*\.claude/commands' "$CMD"; then
+    echo "ship-init still copies or commits commands"; return 1
+  fi
+  if grep -nE '/ship-(propose|explain|research|decision|roadmap|brief|arch)([^a-z-]|$)' "$CMD"; then
+    echo "ship-init points at a removed command"; return 1
+  fi
+  blk=$(awk '/^2\. \*\*`--upgrade`/{f=1} /^3\. \*\*Scaffold repo side/{f=0} f' "$CMD" \
+        | awk '/^[[:space:]]*```bash[[:space:]]*$/{b=1;next} /^[[:space:]]*```[[:space:]]*$/{b=0} b')
+  [ -n "$blk" ] || { echo "no --upgrade block"; return 1; }
+  mkdir -p "$HOME/.claude/skills" && ln -s "$SHIP_SKILL_ROOT" "$HOME/.claude/skills/ship-workflow"
+  printf '%s\n' "$blk" > "$SCRATCH/upgrade.sh"
+  run bash "$SCRATCH/upgrade.sh"
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [ ! -e .claude/commands/ship-next.md ] && [ -f .claude/commands/my-own.md ]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-copies.bats; cd - >/dev/null`

Expected: `1..5`, 0 ok, these 5 fail:
  - `not ok 1 remove_command_copies: tracked copies are git rm'd and staged, ignored ones deleted, others kept`
  - `not ok 2 remove_command_copies: refuses, removing nothing, when the user-level ship-next does not resolve`
  - `not ok 3 remove_command_copies: works in a linked worktree`
  - `not ok 4 remove_command_copies: a tracked copy with local edits is left alone and reported`
  - `not ok 5 ship-init no longer copies commands, and its --upgrade step removes the copies`

- [ ] **Step 3: Implement**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-init.md b/claude-skills/ship-workflow/commands/ship-init.md
index b400767..76f0e5c 100644
--- a/claude-skills/ship-workflow/commands/ship-init.md
+++ b/claude-skills/ship-workflow/commands/ship-init.md
@@ -1,6 +1,6 @@
 ---
 name: ship-init
-description: Bootstrap Ship Workflow in current repo (folders + commands + AIR-OS Product Brain stub)
+description: Bootstrap Ship Workflow in current repo (folders + AIR-OS Product Brain stub)
 argument-hint: "[<repo>]"
 discord-visible: true
 ---
@@ -16,7 +16,7 @@ You are bootstrapping the Ship Workflow in the user's current repo.
   - **Absolute path** (starts with `/`) — `cd` there, use basename as project name.
   - **Omitted** — use current working directory; project name = basename(pwd) or `.claude/ship-config.yml` override.
 - `--custom` — interactively prompt for per-repo config overrides and write `.claude/ship-config.yml`
-- `--upgrade` — only re-copy `.claude/commands/ship-*.md` from the skill (preserves docs/ and Obsidian content)
+- `--upgrade` — only remove this repo's old `.claude/commands/ship-*.md` copies (preserves docs/ and Obsidian content). The commands are installed once per machine by ai_system's `./sync.sh restore`; a repo needs no copy.
 - `--with-ua` — after scaffolding completes, if Understand-Anything plugin is detected at `~/.claude/plugins/cache/understand-anything/`, prompt to run `/understand` in the target repo (or skip prompt with this flag). Recommended when initializing on a mature repo (≥ 10 source files). For a brand new / empty repo, this is a no-op (no code to index yet).
 
 ## Steps
@@ -62,12 +62,18 @@ You are bootstrapping the Ship Workflow in the user's current repo.
 
    If the global config (`~/.claude/ship-workflow.yml`) is missing, STOP and ask the user to create it with `airos_vault: /path/to/SecondBrain` and `code_root: /path/to/code/workspace`.
 
-2. **`--upgrade` short-circuit.** If `--upgrade`:
-   - `cp ~/.claude/skills/ship-workflow/commands/*.md .claude/commands/`
-   - Done. Skip the rest.
+2. **`--upgrade` short-circuit.** If `--upgrade`, remove the old copies, then stop:
+
+   ```bash
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/command-copies.sh || exit 1
+   remove_command_copies "$(pwd)"
+   ```
+
+   Tracked copies are left staged as deletions: commit them, or open an MR in an
+   mr-mode repo. Skip the rest.
 
 3. **Scaffold repo side.** Create:
-   - `.claude/commands/` and copy all 9 `ship-*.md` from `~/.claude/skills/ship-workflow/commands/` (7 core + 2 bridges: ship-research, **ship-propose**)
    - `docs/ideas/`, `docs/decisions/`, `docs/brainstorms/`, `docs/specs/`, `docs/plans/`, `docs/learnings/`, `docs/product/`, `docs/proposals/`
    - `docs/learnings/_log.md` with header:
      ```markdown
@@ -97,15 +103,14 @@ You are bootstrapping the Ship Workflow in the user's current repo.
 
 7. **Verify.** Run:
    ```bash
-   ls .claude/commands/   # should have 9 ship-*.md files
    ls docs/               # should have 8 subdirs
    ls "<project_path>"    # should have 4 strategy .md files
    ```
 
 8. **Commit.** Run:
    ```bash
-   git add .claude/commands .claude/.gitignore docs/
-   git commit -m "chore: initialize ship-workflow (9 commands + 7 folders)"
+   git add .claude/.gitignore docs/
+   git commit -m "chore: initialize ship-workflow (folders)"
    ```
    If the user is in a worktree on a feature branch, mention it. Don't push.
 
@@ -161,7 +166,6 @@ EOF
 10. **Report.** Tell the user:
     - Project name resolved
     - AIR-OS project path
-    - Number of commands installed
     - Whether VISION / R-001 were seeded
     - **Repo-state hint** — count source files quickly:
       ```bash
@@ -171,14 +175,14 @@ EOF
     - Next suggested commands (in priority order):
       - **If source count ≥ 10**: recommend running `/understand src/<core-module>` (scoped) in a fresh Claude Code session to build a KG. Skip if UA plugin not installed.
       - **If source count < 10** (new / empty repo): no code understanding action — write code first, revisit UA when the codebase has structure worth indexing.
-      - `/ship-roadmap` to plan items
+      - add rows to ROADMAP.md, or start one with `/ship-next --adhoc "<description>"`
       - `/ship-next` to start work
 
 ## Idempotency
 
 Every step must be safe to re-run:
 - Creating an existing directory: silently skip
-- Copying a file that exists in target: skip (unless `--upgrade`, then overwrite commands only)
+- Copying a file that exists in target: skip
 - AIR-OS strategy files: NEVER overwrite
 
 ## Failure modes
diff --git a/claude-skills/ship-workflow/lib/command-copies.sh b/claude-skills/ship-workflow/lib/command-copies.sh
new file mode 100644
index 0000000..f7a5887
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/command-copies.sh
@@ -0,0 +1,38 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/command-copies.sh
+# ship-workflow's commands are installed once per machine: ai_system's
+# `./sync.sh restore` links them into ~/.claude/commands/. ship-init used to copy
+# commands/*.md into every repo's .claude/commands/ as well, and those copies went
+# stale — on 2026-10-23 six repos held 60 of them, none current (R-004 §3.4).
+
+# remove_command_copies <repo-path> — remove the repo's copies of the 13 current and
+# former ship-workflow commands; leave every other file in .claude/commands/ alone.
+#   tracked copy   → `git rm` (staged, never committed: the operator commits or opens an MR)
+#   untracked copy → `rm`
+#   a tracked copy with local edits is left in place and reported, so no edit is lost.
+# Refuses, removing nothing, unless ~/.claude/commands/ship-next.md resolves: a repo
+# must never be left with no working /ship-next. Works in a linked worktree.
+remove_command_copies() {
+  local repo="${1:-}" name rel
+  [ -n "$repo" ] && [ -d "$repo" ] || { echo "usage: remove_command_copies <repo-path>" >&2; return 2; }
+  if [ ! -f "$HOME/.claude/commands/ship-next.md" ]; then
+    echo "refusing: ~/.claude/commands/ship-next.md does not resolve — run ./sync.sh restore in ai_system first. Nothing removed." >&2
+    return 1
+  fi
+  for name in ship-next ship-compound ship-idea ship-land ship-init ship-propose \
+              ship-explain ship-brief ship-research ship-decision ship-roadmap \
+              ship-arch ship-build; do
+    rel=".claude/commands/${name}.md"
+    [ -e "$repo/$rel" ] || [ -L "$repo/$rel" ] || continue
+    if git -C "$repo" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
+      if git -C "$repo" rm -q -- "$rel" >/dev/null 2>&1; then
+        echo "removed (staged): $rel"
+      else
+        echo "kept: $rel has local edits — remove it by hand once you no longer need them" >&2
+      fi
+    else
+      rm -f "$repo/$rel" && echo "removed (untracked): $rel"
+    fi
+  done
+  return 0
+}
R004_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-copies.bats; cd - >/dev/null`

Expected: `1..5`, all 5 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-init): R-004 Task 5 — remove_command_copies; ship-init no longer copies commands into repos"
```

### Task 6: `sync.sh` installs by symlink and backs up two config files

Seam: `sync.sh restore` / `backup` / `status`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.3, G3, AC-2..AC-6. The rsync mirror of `~/.claude/skills` is gone. restore links 3 skills + 5 commands, moves a real file or directory aside rather than deleting it, removes only ship-workflow's dangling command links, asks before overwriting a differing config file, and is idempotent. `config/claude/CLAUDE.md` is the new backup of the global file.

**Files:**
- Modify: `sync.sh` (rewritten)
- Create: `config/claude/CLAUDE.md` (backup of the global CLAUDE.md, as of 2026-10-24)
- Test: `claude-skills/ship-workflow/tests/test_sync-install.bats` (new)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_sync-install.bats b/claude-skills/ship-workflow/tests/test_sync-install.bats
new file mode 100644
index 0000000..4827b72
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_sync-install.bats
@@ -0,0 +1,100 @@
+#!/usr/bin/env bats
+# R-004 §3.3: sync.sh installs ship-workflow's three skills and five commands as
+# symlinks into this checkout, and backs up the two config files the repo keeps. The
+# old sync.sh mirrored all of ~/.claude/skills with rsync: its restore would have
+# reinstalled 40 removed skills and overwritten a newer global CLAUDE.md.
+# Each test runs a copy of sync.sh inside a scratch "ai_system", so neither the real
+# repo nor the real ~/.claude is touched.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch sync-install)"
+  export HOME="$SCRATCH/home"
+  export AI_SYSTEM_SKIP_DEVSYNC=1
+  R="$SCRATCH/ai_system"; export R
+  mkdir -p "$R/claude-skills/ship-workflow/commands" "$R/claude-skills/run-plan" \
+           "$R/claude-skills/code-review-skill" "$R/config/claude" "$R/devsync"
+  cp "$SHIP_SKILL_ROOT/../../sync.sh" "$R/sync.sh"
+  for c in ship-next ship-compound ship-idea ship-land ship-init; do
+    echo "$c" > "$R/claude-skills/ship-workflow/commands/$c.md"
+  done
+  echo "global rules" > "$R/config/claude/CLAUDE.md"
+  echo "[defaults]" > "$R/devsync/config.toml"
+  # A machine as it stood on 2026-10-23: a real run-plan copy, no code-review-skill,
+  # a dangling ship-arch link, and a skill the repo has nothing to do with.
+  mkdir -p "$HOME/.claude/skills/run-plan" "$HOME/.claude/skills/other" "$HOME/.claude/commands"
+  echo "old copy" > "$HOME/.claude/skills/run-plan/SKILL.md"
+  echo keep > "$HOME/.claude/skills/other/SKILL.md"
+  ln -s "$HOME/.claude/skills/ship-workflow/commands/ship-arch.md" "$HOME/.claude/commands/ship-arch.md"
+  ln -s "$SCRATCH/elsewhere/ship-x.md" "$HOME/.claude/commands/ship-x.md"   # dangling, not ours
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+snapshot() {  # every path under HOME, with link targets
+  (cd "$HOME" && find . -print | sort | while IFS= read -r p; do
+     if [ -L "$p" ]; then echo "$p -> $(readlink "$p")"; else echo "$p"; fi
+   done)
+}
+
+@test "restore links the 3 skills and 5 commands, moves a real dir aside, clears only our dangling links" {
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  for s in ship-workflow run-plan code-review-skill; do
+    [ "$(readlink "$HOME/.claude/skills/$s")" = "$R/claude-skills/$s" ] || { echo "skill $s"; return 1; }
+  done
+  for c in ship-next ship-compound ship-idea ship-land ship-init; do
+    [ "$(readlink "$HOME/.claude/commands/$c.md")" = "$HOME/.claude/skills/ship-workflow/commands/$c.md" ] || { echo "cmd $c"; return 1; }
+    [ -f "$HOME/.claude/commands/$c.md" ] || return 1
+  done
+  moved=$(ls -d "$HOME/.claude/.ai_system-displaced/run-plan-"* 2>/dev/null | head -1)
+  [ -n "$moved" ] && grep -qF "old copy" "$moved/SKILL.md" || { echo "run-plan copy not kept"; return 1; }
+  [ ! -L "$HOME/.claude/commands/ship-arch.md" ] || { echo "our dangling link kept"; return 1; }
+  [ -L "$HOME/.claude/commands/ship-x.md" ] || { echo "removed a link that is not ours"; return 1; }
+  [ "$(cat "$HOME/.claude/skills/other/SKILL.md")" = keep ]
+}
+
+@test "restore twice changes nothing the second time" {
+  bash "$R/sync.sh" restore --yes >/dev/null
+  before=$(snapshot)
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || return 1
+  [ "$(snapshot)" = "$before" ]
+}
+
+@test "restore --dry-run changes nothing and names each planned action" {
+  before=$(snapshot)
+  run bash "$R/sync.sh" restore --dry-run
+  [ "$status" -eq 0 ] || return 1
+  [ "$(snapshot)" = "$before" ] || { echo "dry run changed files"; return 1; }
+  [[ "$output" == *"code-review-skill"* ]] || return 1
+  [[ "$output" == *"run-plan"* ]] || return 1
+  [[ "$output" == *"ship-arch.md"* ]]
+}
+
+@test "restore without --yes asks before overwriting a differing config file" {
+  mkdir -p "$HOME/.claude" && echo "newer live rules" > "$HOME/.claude/CLAUDE.md"
+  run bash -c "echo n | bash '$R/sync.sh' restore"
+  [ "$(cat "$HOME/.claude/CLAUDE.md")" = "newer live rules" ] || { echo "overwrote without consent"; return 1; }
+  [ "$(readlink "$HOME/.claude/skills/run-plan")" = "$R/claude-skills/run-plan" ]
+}
+
+@test "backup copies the two config files into the repo and touches nothing else" {
+  mkdir -p "$HOME/.claude" "$HOME/.config/devsync"
+  echo "live global rules" > "$HOME/.claude/CLAUDE.md"
+  echo "[live]" > "$HOME/.config/devsync/config.toml"
+  run bash "$R/sync.sh" backup
+  [ "$status" -eq 0 ] || return 1
+  [ "$(cat "$R/config/claude/CLAUDE.md")" = "live global rules" ] || return 1
+  [ "$(cat "$R/devsync/config.toml")" = "[live]" ] || return 1
+  [ "$(ls "$R/claude-skills" | sort | tr '\n' ' ')" = "code-review-skill run-plan ship-workflow " ]
+}
+
+@test "status exits 0 when every link is right and 1 naming a missing one" {
+  bash "$R/sync.sh" restore --yes >/dev/null
+  run bash "$R/sync.sh" status
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  rm "$HOME/.claude/commands/ship-land.md"
+  run bash "$R/sync.sh" status
+  [ "$status" -eq 1 ] || return 1
+  [[ "$output" == *"ship-land"*"missing"* ]]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_sync-install.bats; cd - >/dev/null`

Expected: `1..6`, 0 ok, these 6 fail:
  - `not ok 1 restore links the 3 skills and 5 commands, moves a real dir aside, clears only our dangling links`
  - `not ok 2 restore twice changes nothing the second time`
  - `not ok 3 restore --dry-run changes nothing and names each planned action`
  - `not ok 4 restore without --yes asks before overwriting a differing config file`
  - `not ok 5 backup copies the two config files into the repo and touches nothing else`
  - `not ok 6 status exits 0 when every link is right and 1 naming a missing one`

- [ ] **Step 3: Implement**

````bash
git apply <<'R004_PATCH'
diff --git a/config/claude/CLAUDE.md b/config/claude/CLAUDE.md
new file mode 100644
index 0000000..4db78b8
--- /dev/null
+++ b/config/claude/CLAUDE.md
@@ -0,0 +1,123 @@
+# Global Claude operating notes
+
+These notes apply across all projects. Per-project `CLAUDE.md` / `AGENTS.md`
+files override anything here. Keep this file short — it loads into every
+session.
+
+## Specification edits
+
+When a project has a `spec/` directory and the current task modifies or adds
+content to any file inside it, prefer the `update-specification` skill to
+guide the edit. The skill enforces an AI-friendly format: explicit
+`REQ-NNN` / `SEC-NNN` / `CON-NNN` / `PAT-NNN` / `AC-NNN` IDs,
+Given-When-Then acceptance criteria, and the 11-section template documented
+inside the skill itself.
+
+Do **not** invoke the skill for:
+
+- Projects without a `spec/` directory (most small scripts, experiments,
+  frontend-only repos, learning projects).
+- Read-only spec lookups — only when writing or updating a spec.
+- Surgical typo / wording fixes inside an existing spec that already
+  conforms to the format.
+
+The skill's template includes some .NET-flavored test-framework defaults
+(MSTest, FluentAssertions, Moq). Substitute the project's actual test
+stack (pytest / vitest / jest / etc.) when applying.
+
+## Research output language
+
+All research artifacts (research-deep, research-brief, ce-web-researcher
+output, in-vault `Research/*.md` files, any "find prior art / synthesize
+findings" task output) MUST be written in **Traditional Chinese (繁體中文)**.
+
+This applies to:
+- Documents saved into the AIR-OS vault `Research/` directory
+- Discussion briefs, synthesis docs, prior-art summaries
+- Anything dispatched via `/ship-research`, `/obsidian-research-deep`,
+  or `ce-web-researcher` subagents
+
+Citation URLs, code snippets, technical proper nouns (`flag.X`, `entry_when`,
+class names, library names, papers' English titles) stay in their original
+form. Only the prose narrative, section headings, summaries, and rationale
+text translates to Chinese.
+
+When dispatching a research subagent, include this constraint explicitly
+in the prompt (e.g. "Output language: Traditional Chinese; technical
+identifiers and citations stay verbatim").
+
+## Project mockups go to the vault as HTML
+
+When asked for a mockup / proposal mockup for a project, write a single
+self-contained HTML file to
+`/Users/leric/Documents/SecondBrain/10 Projects/<name>/Proposals/mockups/`
+— never markdown or ASCII art. Read and follow **Project Mockup Convention**
+in `/Users/leric/Documents/SecondBrain/_CLAUDE.md` first (structure, base
+styles, linking, headless-Chrome verification).
+
+## Feature flags default ON
+
+When shipping a new user-facing feature behind a kill-switch flag
+(`FEATURE_X_ENABLED`, `VITE_ENABLE_FEATURE_X`, config `feature_x.enabled`,
+GrowthBook `feature-x`, etc.), **default it to ON** — in prod config,
+in code (`os.getenv("...", "true") != "false"`, not `... == "true"`),
+and in whatever schema drives the runtime.
+
+Rationale: the person who asked for the feature wants to use / see /
+test it the moment it deploys. Shipping default-off hides the thing
+they built from themselves and delays every downstream signal (does it
+even render? does it break other pages? do CS reports come in?) until
+someone remembers to flip it. The kill switch's job is being a kill
+switch — it doesn't need to also be a rollout gate. Two different jobs.
+
+**Exceptions — genuinely default OFF:**
+- **Safety / security-critical mutation surfaces** (delete-everything
+  button, bulk mailer, mass-refund tool): default off until manually
+  verified in prod.
+- **Auth / authz / quota / tenant-isolation gates**: deny by default is
+  the pattern (see `opt-in-gate-when-retrofitting-a-cross-cutting-governor`
+  in AIR-OS 30 Engineering — this is that pattern's stated exception).
+- **Expensive-per-invocation features** (paid third-party API burn,
+  large-model inference costs) where enabling on every pod immediately
+  is a spend risk.
+- **Explicitly staged rollouts** the user asked for ("prod default off,
+  ramp 10% → 50% → 100%"). If the user asks for staging, do staging.
+
+**Read-only observability / admin-visibility / display features are
+never in these exceptions.** They pay no per-request cost, they can't
+break user data, they can't leak secrets past their auth gate. Ship on.
+
+If a spec says "prod default false, staged rollout" and it's a read-only
+display feature, push back once before implementing that way. If the
+user re-affirms, do what they asked — but the pushback happens.
+
+## Code review feedback: verify before agreeing
+
+When someone points at review feedback — a PR/MR number plus "look at this",
+in any language — reproduce the claim yourself before accepting or implementing
+it. State what you observed, then whether the feedback was right, too weak, or
+wrong.
+
+This is not politeness about disagreement; it is about being wrong in both
+directions. A real case: feedback was accepted and the fix applied, and the
+reproduction showed the defect was *worse* than reported — and a test written
+three tasks earlier had pinned the broken behaviour as the spec. Neither fact
+surfaces if you just do what the comment says.
+
+## Clarifying questions: ask, then commit
+
+Cap clarifying questions at roughly three rounds. After that, state the
+assumption you are proceeding on and continue; the person can correct you.
+
+Rationale: a past session asked eleven rounds for one slash command. Seven were
+answered with a bare "Ok", then two interrupts and "什麼狀況". Past about three,
+questions stop gathering information and start transferring your uncertainty to
+someone with less context than you.
+
+## langlive VPN: reconnect it yourself
+
+When langlive infra (k8s `*_ll_eks`, bastion, internal hosts, `61.216.4.193`)
+hangs or times out, or the VPN looks down, run `~/vpn.sh status`. If it prints
+`DOWN`, use the `langlive-vpn-login` skill to connect, then retry the original
+command. Don't ask the user to click FortiClient, and ignore `scutil --nc
+status` (it always says Disconnected). Never disconnect unless asked.
diff --git a/sync.sh b/sync.sh
index 2e4e77d..87bf543 100755
--- a/sync.sh
+++ b/sync.sh
@@ -1,198 +1,225 @@
 #!/usr/bin/env bash
+# sync.sh — install ai_system on this machine, and back up the two config files it keeps.
 #
-# sync.sh — Bidirectional sync for Claude skills
+# ai_system is ship-workflow's home (R-004). `restore` links its three skills and
+# ship-workflow's five commands into ~/.claude, so every session runs this checkout;
+# `backup` copies the global CLAUDE.md and the devsync config into the repo.
+#
+# It used to mirror all of ~/.claude/skills with rsync. That mirror drifted: its
+# restore would have reinstalled 40 removed skills, overwritten a newer global
+# CLAUDE.md with an old copy, and replaced the ship-workflow symlink with a copy.
 #
 # Usage:
-#   ./sync.sh backup            # ~/.claude/skills/  ->  ./claude-skills/
-#   ./sync.sh restore           # ./claude-skills/   ->  ~/.claude/skills/
-#   ./sync.sh status            # show diff summary between the two
-#   ./sync.sh backup --dry-run  # preview without copying
+#   ./sync.sh restore [--yes] [--dry-run]   links + config files + devsync bootstrap
+#   ./sync.sh backup                         ~/.claude/CLAUDE.md, devsync config -> repo
+#   ./sync.sh status                         link and config state; exit 1 if a link is wrong
 #
+# Tests set AI_SYSTEM_SKIP_DEVSYNC=1 to skip the devsync bootstrap.
 
 set -euo pipefail
 
-# ---------- Config ----------
 SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
-LOCAL_DIR="$SCRIPT_DIR/claude-skills"
-CLAUDE_DIR="$HOME/.claude/skills"
-
-# Single-file syncs: source -> repo path
-declare -a SYNC_FILES=(
-  "$HOME/.claude/CLAUDE.md::$SCRIPT_DIR/CLAUDE.md"
+CLAUDE_HOME="$HOME/.claude"
+DISPLACED="$CLAUDE_HOME/.ai_system-displaced"
+SKILLS=(ship-workflow run-plan code-review-skill)
+COMMANDS=(ship-next ship-compound ship-idea ship-land ship-init)
+# live::repo
+CONFIG_FILES=(
+  "$HOME/.claude/CLAUDE.md::$SCRIPT_DIR/config/claude/CLAUDE.md"
   "$HOME/.config/devsync/config.toml::$SCRIPT_DIR/devsync/config.toml"
 )
 
-EXCLUDES=(
-  --exclude='node_modules'
-  --exclude='.git'
-  --exclude='dist'
-  --exclude='build'
-  --exclude='.DS_Store'
-  --exclude='*.log'
-  --exclude='bin/'
-  --exclude='.cache'
-  --exclude='.next'
-  --exclude='__pycache__'
-)
-
-# ---------- Colors ----------
 if [[ -t 1 ]]; then
   C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
   C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
 else
   C_RESET=''; C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BLUE=''
 fi
-
 log()  { printf "%s\n" "$*"; }
 info() { printf "%b\n" "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
 ok()   { printf "%b\n" "${C_GREEN}✓${C_RESET} $*"; }
 warn() { printf "%b\n" "${C_YELLOW}!${C_RESET} $*"; }
 err()  { printf "%b\n" "${C_RED}✗${C_RESET} $*" >&2; }
-
-# ---------- Helpers ----------
 confirm() {
-  local prompt="$1"
-  read -r -p "$(printf "%b" "${C_YELLOW}?${C_RESET} ${prompt} [y/N] ")" reply
+  local reply
+  read -r -p "$(printf "%b" "${C_YELLOW}?${C_RESET} $1 [y/N] ")" reply || return 1
   [[ "$reply" =~ ^[Yy]$ ]]
 }
 
-ensure_dir() {
-  local dir="$1"
-  if [[ ! -d "$dir" ]]; then
-    err "Directory does not exist: $dir"
-    exit 1
+DRY=0
+YES=0
+
+# The links restore manages, as "link::target" lines.
+links() {
+  local s c
+  for s in "${SKILLS[@]}"; do
+    echo "$CLAUDE_HOME/skills/$s::$SCRIPT_DIR/claude-skills/$s"
+  done
+  for c in "${COMMANDS[@]}"; do
+    echo "$CLAUDE_HOME/commands/$c.md::$CLAUDE_HOME/skills/ship-workflow/commands/$c.md"
+  done
+}
+
+# link_state <link> <target> — ok | missing | wrong target | blocked by a real file
+link_state() {
+  if [[ -L "$1" ]]; then
+    [[ "$(readlink "$1")" == "$2" ]] && echo ok || echo "wrong target"
+  elif [[ -e "$1" ]]; then
+    echo "blocked by a real file"
+  else
+    echo missing
+  fi
+}
+
+# Move a real file or directory out of a link's way — never delete it.
+displace() {
+  local path="$1" dest
+  dest="$DISPLACED/$(basename "$path")-$(date -u +%Y%m%dT%H%M%SZ)"
+  while [[ -e "$dest" ]]; do dest="${dest}-1"; done
+  mkdir -p "$DISPLACED"
+  mv "$path" "$dest"
+  warn "moved $path -> $dest (not deleted)"
+}
+
+ensure_link() {
+  local link="$1" target="$2" state
+  state=$(link_state "$link" "$target")
+  [[ "$state" == ok ]] && return 0
+  if (( DRY )); then
+    log "would link $link -> $target ($state)"
+    return 0
   fi
+  case "$state" in
+    "blocked by a real file") displace "$link" ;;
+    "wrong target")           rm "$link" ;;
+  esac
+  mkdir -p "$(dirname "$link")"
+  ln -s "$target" "$link"
+  ok "linked $link"
 }
 
-post_restore_hook() {
-  # Re-install npm deps for skills that need them
-  local gstack="$CLAUDE_DIR/gstack"
-  if [[ -f "$gstack/package.json" ]] && [[ ! -d "$gstack/node_modules" ]]; then
-    warn "gstack has no node_modules"
-    if confirm "Run 'npm install' in $gstack now?"; then
-      ( cd "$gstack" && npm install ) && ok "gstack npm install complete"
+# Remove ~/.claude/commands/ship-*.md links that point into ship-workflow's commands/
+# at a file that no longer exists (a removed command). Nothing else is touched.
+remove_dangling() {
+  local f t
+  [[ -d "$CLAUDE_HOME/commands" ]] || return 0
+  for f in "$CLAUDE_HOME/commands"/ship-*.md; do
+    [[ -L "$f" && ! -e "$f" ]] || continue
+    t=$(readlink "$f")
+    [[ "$t" == */ship-workflow/commands/* ]] || continue
+    if (( DRY )); then
+      log "would remove dangling $f -> $t"
     else
-      warn "Skipped. Run manually later: cd $gstack && npm install"
+      rm "$f"
+      ok "removed dangling $f"
     fi
-  fi
+  done
+}
 
-  devsync_post_restore "$@"
+restore_configs() {
+  local entry live repo
+  for entry in "${CONFIG_FILES[@]}"; do
+    live="${entry%%::*}"; repo="${entry##*::}"
+    [[ -f "$repo" ]] || { warn "skip: $repo (not in the repo)"; continue; }
+    [[ -f "$live" ]] && cmp -s "$live" "$repo" && continue
+    if (( DRY )); then
+      log "would restore $repo -> $live"
+      continue
+    fi
+    if [[ -f "$live" ]]; then
+      diff -u "$live" "$repo" | head -40 || true
+    fi
+    if (( ! YES )) && ! confirm "Overwrite $live with the repo copy?"; then
+      warn "kept $live"
+      continue
+    fi
+    mkdir -p "$(dirname "$live")"
+    cp "$repo" "$live"
+    ok "restored $live"
+  done
 }
 
-devsync_post_restore() {
+devsync_bootstrap() {
   local bootstrap="$SCRIPT_DIR/devsync/bootstrap.sh"
+  if (( DRY )) || [[ "${AI_SYSTEM_SKIP_DEVSYNC:-0}" == 1 ]]; then return 0; fi
   if [[ ! -x "$bootstrap" ]]; then
     warn "devsync/bootstrap.sh missing or not executable — skip"
-    return
+    return 0
   fi
   info "Running devsync bootstrap..."
-  log ""
-  if [[ " $* " =~ " --yes " ]]; then
-    "$bootstrap" --yes
-  else
-    "$bootstrap"
-  fi
+  if (( YES )); then "$bootstrap" --yes; else "$bootstrap"; fi
 }
 
-# ---------- Commands ----------
-sync_files() {
-  # direction: "backup" (src->dst) or "restore" (dst->src)
-  local direction="$1"; shift
-  local extra_flags=("${@:-}")
-  for entry in "${SYNC_FILES[@]}"; do
-    local src="${entry%%::*}"
-    local dst="${entry##*::}"
-    if [[ "$direction" == "backup" ]]; then
-      [[ -f "$src" ]] || { warn "Skip: $src (not found)"; continue; }
-      rsync -av ${extra_flags[*]:-} "$src" "$dst"
-    else
-      [[ -f "$dst" ]] || { warn "Skip: $dst (not found)"; continue; }
-      rsync -av ${extra_flags[*]:-} "$dst" "$src"
-    fi
+cmd_restore() {
+  local arg pair
+  for arg in "$@"; do
+    case "$arg" in
+      --yes) YES=1 ;;
+      --dry-run) DRY=1 ;;
+      *) err "unknown option: $arg"; exit 2 ;;
+    esac
   done
+  info "Links: ~/.claude -> $SCRIPT_DIR"
+  while IFS= read -r pair; do
+    ensure_link "${pair%%::*}" "${pair##*::}"
+  done < <(links)
+  remove_dangling
+  info "Config files"
+  restore_configs
+  devsync_bootstrap
+  if (( DRY )); then ok "Dry run — nothing changed"; else ok "Restore complete"; fi
 }
 
 cmd_backup() {
-  ensure_dir "$CLAUDE_DIR"
-  mkdir -p "$LOCAL_DIR"
-  info "Backup: $CLAUDE_DIR  ->  $LOCAL_DIR"
-  # -L: follow symlinks and copy the actual target files (so the repo is
-  #     portable across machines — local symlinks point to absolute paths
-  #     like ~/.claude/plugins/... that don't exist on other machines).
-  rsync -avL --delete "${EXCLUDES[@]}" "$@" "$CLAUDE_DIR/" "$LOCAL_DIR/"
-  info "Backup config files"
-  sync_files backup "$@"
-  ok "Backup complete ($(du -sh "$LOCAL_DIR" | awk '{print $1}'))"
-}
-
-cmd_restore() {
-  ensure_dir "$LOCAL_DIR"
-  mkdir -p "$CLAUDE_DIR"
-  info "Restore: $LOCAL_DIR  ->  $CLAUDE_DIR"
-  warn "This will OVERWRITE files in $CLAUDE_DIR and ~/.claude/CLAUDE.md (preserves node_modules, bin/, etc.)"
-  if [[ ! " $* " =~ " --dry-run " ]] && [[ ! " $* " =~ " --yes " ]]; then
-    confirm "Continue?" || { log "Aborted."; exit 0; }
-  fi
-  local restore_flags=()
-  local arg
-  for arg in "$@"; do
-    [[ "$arg" == "--yes" ]] && continue
-    restore_flags+=("$arg")
+  local entry live repo
+  for entry in "${CONFIG_FILES[@]}"; do
+    live="${entry%%::*}"; repo="${entry##*::}"
+    [[ -f "$live" ]] || { warn "skip: $live (not found)"; continue; }
+    mkdir -p "$(dirname "$repo")"
+    cp "$live" "$repo"
+    ok "backed up $live -> ${repo#"$SCRIPT_DIR"/}"
   done
-  # Note: no --delete here so we don't nuke node_modules/bin/ on the target
-  if [[ ${#restore_flags[@]} -gt 0 ]]; then
-    rsync -av "${EXCLUDES[@]}" "${restore_flags[@]}" "$LOCAL_DIR/" "$CLAUDE_DIR/"
-  else
-    rsync -av "${EXCLUDES[@]}" "$LOCAL_DIR/" "$CLAUDE_DIR/"
-  fi
-  info "Restore config files"
-  if [[ ${#restore_flags[@]} -gt 0 ]]; then
-    sync_files restore "${restore_flags[@]}"
-  else
-    sync_files restore
-  fi
-  ok "Restore complete"
-  if [[ ! " $* " =~ " --dry-run " ]]; then
-    post_restore_hook "$@"
-  fi
 }
 
 cmd_status() {
-  ensure_dir "$LOCAL_DIR"
-  ensure_dir "$CLAUDE_DIR"
-  info "Diff summary (excludes node_modules, bin/, etc.)"
-  log ""
-  log "${C_BOLD}Files only in ~/.claude/skills/ (would be backed up):${C_RESET}"
-  rsync -avn --delete "${EXCLUDES[@]}" "$CLAUDE_DIR/" "$LOCAL_DIR/" \
-    | grep -E '^(>|<|\*deleting)' || log "  (none)"
-  log ""
-  log "${C_BOLD}Sizes:${C_RESET}"
-  log "  local:   $(du -sh "$LOCAL_DIR"  2>/dev/null | awk '{print $1}')  $LOCAL_DIR"
-  log "  source:  $(du -sh "$CLAUDE_DIR" 2>/dev/null | awk '{print $1}')  $CLAUDE_DIR"
+  local pair link target state bad=0 entry live repo
+  while IFS= read -r pair; do
+    link="${pair%%::*}"; target="${pair##*::}"
+    state=$(link_state "$link" "$target")
+    log "${link#"$CLAUDE_HOME"/}: $state"
+    [[ "$state" == ok ]] || bad=1
+  done < <(links)
+  for entry in "${CONFIG_FILES[@]}"; do
+    live="${entry%%::*}"; repo="${entry##*::}"
+    if [[ ! -f "$live" || ! -f "$repo" ]]; then
+      log "$live: missing"
+    elif cmp -s "$live" "$repo"; then
+      log "$live: same"
+    else
+      log "$live: differs (./sync.sh backup to save it)"
+    fi
+  done
+  return "$bad"
 }
 
 usage() {
   cat <<EOF
-${C_BOLD}sync.sh${C_RESET} — Bidirectional sync for Claude skills
+${C_BOLD}sync.sh${C_RESET} — install ai_system (ship-workflow + run-plan + code-review-skill)
 
-${C_BOLD}Usage:${C_RESET}
-  $(basename "$0") backup  [--dry-run]         Push ~/.claude/skills -> ./claude-skills
-  $(basename "$0") restore [--dry-run] [--yes] Pull ./claude-skills  -> ~/.claude/skills
-  $(basename "$0") status                      Show what's different
+  $(basename "$0") restore [--yes] [--dry-run]  link the skills and commands into ~/.claude,
+                                              restore the config files, run devsync bootstrap
+  $(basename "$0") backup                       copy ~/.claude/CLAUDE.md and the devsync config here
+  $(basename "$0") status                       show link and config state (exit 1 if a link is wrong)
 
-${C_BOLD}Notes:${C_RESET}
-  • Excludes node_modules, bin/, dist, build, .git, *.log, .DS_Store, .cache
-  • 'backup' uses --delete (mirrors source); 'restore' does NOT (keeps local node_modules)
-  • After 'restore', will offer to run 'npm install' in skills that need it (e.g. gstack)
+A real file or directory in a link's way is moved to $DISPLACED, never deleted.
 EOF
 }
 
-# ---------- Main ----------
 cmd="${1:-}"; shift || true
 case "$cmd" in
-  backup)  cmd_backup  "$@" ;;
   restore) cmd_restore "$@" ;;
-  status)  cmd_status  "$@" ;;
+  backup)  cmd_backup ;;
+  status)  cmd_status ;;
   ""|-h|--help|help) usage ;;
   *) err "Unknown command: $cmd"; usage; exit 1 ;;
 esac
R004_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_sync-install.bats; cd - >/dev/null`

Expected: `1..6`, all 6 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add sync.sh config claude-skills/ship-workflow
git commit -m "feat(sync): R-004 Task 6 — sync.sh installs by symlink and backs up two config files"
```

### Task 7: Docs: the repo CLAUDE.md, the root README, ship-next's install hint

Seam: repo contents (docs)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.2, §3.6. The root CLAUDE.md was a stale copy of the global notes plus a rule to run the old restore after every pull; it becomes this repo's own rules. The README describes the new install; ship-next's missing-code-review-skill hint points at `./sync.sh restore`.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `claude-skills/ship-workflow/commands/ship-next.md` (Phase 6 step 1)
- Test: `claude-skills/ship-workflow/tests/test_repo-layout.bats` (two tests added)

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R004_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_repo-layout.bats b/claude-skills/ship-workflow/tests/test_repo-layout.bats
index c01754f..db48e3e 100644
--- a/claude-skills/ship-workflow/tests/test_repo-layout.bats
+++ b/claude-skills/ship-workflow/tests/test_repo-layout.bats
@@ -37,3 +37,20 @@ setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }
     SKILL.md README.md references templates lib"
   [ "$status" -eq 1 ] || { echo "$output"; return 1; }
 }
+
+@test "ship-next's missing-code-review-skill hint installs it from this repo" {
+  step=$(awk '/^1\. \*\*Verify code-review-skill installed/,/^1\.5\. /' "$SHIP_SKILL_ROOT/commands/ship-next.md")
+  [ -n "$step" ] || return 1
+  echo "$step" | grep -qF './sync.sh restore' || { echo "hint does not point at sync.sh restore"; return 1; }
+  if echo "$step" | grep -qF 'git clone'; then echo "hint still clones by hand"; return 1; fi
+}
+
+@test "the repo CLAUDE.md holds this repo's rules; the global one is backed up separately" {
+  # The root CLAUDE.md used to double as the backup of ~/.claude/CLAUDE.md — six sections
+  # behind it, and sync.sh restore would have copied it over the newer global file.
+  if grep -nE '^# Global Claude operating notes|^## (Post-pull sync|Research output language|langlive VPN)' "$REPO_ROOT/CLAUDE.md"; then
+    echo "the repo CLAUDE.md is still a copy of the global notes"; return 1
+  fi
+  grep -qF './sync.sh backup' "$REPO_ROOT/CLAUDE.md" || { echo "no rule for backing up the global file"; return 1; }
+  [ -s "$REPO_ROOT/config/claude/CLAUDE.md" ]
+}
R004_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..7`, 5 ok, these 2 fail:
  - `not ok 6 ship-next's missing-code-review-skill hint installs it from this repo`
  - `not ok 7 the repo CLAUDE.md holds this repo's rules; the global one is backed up separately`

- [ ] **Step 3: Implement**

````bash
git apply <<'R004_PATCH'
diff --git a/CLAUDE.md b/CLAUDE.md
index 0ee02b1..241a49c 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -1,40 +1,31 @@
-# Global Claude operating notes
+# ai_system — repo rules
 
-These notes apply across all projects. Per-project `CLAUDE.md` / `AGENTS.md`
-files override anything here. Keep this file short — it loads into every
-session.
+This repo is ship-workflow's home: `claude-skills/` holds `ship-workflow`, plus the two
+skills `/ship-next` needs, `run-plan` and `code-review-skill`, and nothing else (R-004).
+`devsync/` is the separate remote-dev tool; leave it as it is.
 
-## Specification edits
-
-When a project has a `spec/` directory and the current task modifies or adds
-content to any file inside it, prefer the `update-specification` skill to
-guide the edit. The skill enforces an AI-friendly format: explicit
-`REQ-NNN` / `SEC-NNN` / `CON-NNN` / `PAT-NNN` / `AC-NNN` IDs,
-Given-When-Then acceptance criteria, and the 11-section template documented
-inside the skill itself.
+## The main checkout stays on `main`
 
-Do **not** invoke the skill for:
+`./sync.sh restore` links `~/.claude/skills/{ship-workflow,run-plan,code-review-skill}`
+and the five ship-* commands into this checkout's working tree. Every session on the
+machine therefore runs whatever this checkout holds, uncommitted edits included.
 
-- Projects without a `spec/` directory (most small scripts, experiments,
-  frontend-only repos, learning projects).
-- Read-only spec lookups — only when writing or updating a spec.
-- Surgical typo / wording fixes inside an existing spec that already
-  conforms to the format.
+- Keep the main checkout on `main` and clean. `/ship-next` warns when it is not.
+- Do all work through `/ship-next`, which builds in its own worktree under
+  `../ai_system-worktrees/`.
 
-The skill's template includes some .NET-flavored test-framework defaults
-(MSTest, FluentAssertions, Moq). Substitute the project's actual test
-stack (pytest / vitest / jest / etc.) when applying.
+## Commands
 
-## Post-pull sync
+- Tests: `cd claude-skills/ship-workflow && bats tests/`. In a linked worktree, the
+  `cwd-guard: exits 0 when not in a git repo at all` test fails. That failure is
+  pre-existing and known.
+- After a pull that changes `sync.sh` or the set of directories in `claude-skills/`, run
+  `./sync.sh restore`. Then `./sync.sh status` must print `ok` for every link.
+- After editing `~/.claude/CLAUDE.md`, run `./sync.sh backup`. It copies the file to
+  `config/claude/CLAUDE.md`. That file is the backup of the global rules, not this
+  repo's rules.
 
-After every `git pull` (or any operation that fast-forwards / merges remote
-changes into the working tree), immediately run:
-
-```bash
-./sync.sh restore
-```
+## Specification edits
 
-This applies the project's restore step so the local environment stays in
-sync with what was just pulled. Run it even if the pull reported "Already
-up to date" only when the user explicitly asks; otherwise run it whenever
-the pull actually updated files.
+Specs live in `docs/specs/R-NNN-<slug>.md`. They follow the ship-next format: a
+`## Seams` table and Given-When-Then acceptance rows.
diff --git a/README.md b/README.md
index 38114df..0718661 100644
--- a/README.md
+++ b/README.md
@@ -26,7 +26,7 @@
 
 **附帶的功能**
 
-- **一行裝回整套環境**：換新電腦時，所有 AI 工具和設定一次還原。
+- **一行裝好**：換新電腦時，ship-workflow 和它需要的 skill、全域設定一次裝好。
 - **遠端開發**：在公司的 GPU server 上跑程式時，本機寫的 code 會即時同步過去。
 
 ## 2. Quick start
@@ -41,38 +41,40 @@ cd ~/Desktop/code/ai_system
 
 | repo 內 | 安裝到 | 內容 |
 |---|---|---|
-| `claude-skills/` | `~/.claude/skills/` | ship-workflow、gstack（`/browse`、`/qa`、`/review` 等 40 多個）、`run-plan`、Obsidian 工具 |
-| `CLAUDE.md` | `~/.claude/CLAUDE.md` | 每個 session 都會載入的全域規則 |
+| `claude-skills/` | `~/.claude/skills/`（symlink） | ship-workflow、`run-plan`（codex 執行器）、`code-review-skill`（Phase 6 的 review） |
+| `claude-skills/ship-workflow/commands/` | `~/.claude/commands/`（symlink） | `/ship-next`、`/ship-compound`、`/ship-idea`、`/ship-land`、`/ship-init` |
+| `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | 全域規則的備份；內容不同時會先問你 |
 | `devsync/` | `~/.local/bin/devsync` | 同步到 dl01–dl04 的 CLI，連同 mutagen、uv、SSH 設定 |
 
-> 已經在用的機器請加 `--update`，否則本機比較新的檔案（例如升級過的 gstack）會被 repo 的舊版蓋掉。
+> 全部用 symlink 接上，所以本機跑的永遠是這個 checkout。擋路的實體目錄會搬到 `~/.claude/.ai_system-displaced/`，不會被刪掉；重跑不會多改任何東西。
 
 **啟用 ship-workflow：**
 
 ```bash
 cp ~/.claude/skills/ship-workflow/examples/ship-workflow.example.yml ~/.claude/ship-workflow.yml   # 填入 vault 路徑
-git clone https://github.com/awesome-skills/code-review-skill ~/.claude/skills/code-review-skill
 ```
 
 再安裝 [superpowers](https://github.com/obra/superpowers) plugin，然後在目標 repo 執行 `/ship-init`。
 
 ## 3. 使用範例
 
-### 同步 skills
+### 安裝與備份
 
 ```bash
-./sync.sh status     # 看差異
-./sync.sh backup     # 本機 → repo（鏡像，會刪除本機已刪的檔案）
-./sync.sh restore    # repo → 本機
+./sync.sh status     # 每個連結、設定檔的狀態；有連結不對時 exit 1
+./sync.sh backup     # 全域 CLAUDE.md、devsync 設定 → repo
+./sync.sh restore    # 接好連結、還原設定檔（--dry-run 只顯示會做什麼）
 ```
 
+主 checkout 要停在 `main`：本機每個 session 跑的都是這個 checkout，連未提交的修改也算。不在 `main` 或有未提交修改時，`/ship-next` 會警告。
+
 ### 用 Roadmap 開發功能
 
 **R-xxx 是什麼**
 
 Roadmap 上每個要做的項目都有一個編號 `R-NNN`（例如 `R-012`），從目前最大的號碼往上加。太大的項目會拆成 `R-012.1`、`R-012.2` 這樣的子項目，原本的 `R-012` 變成 epic，`/ship-next` 自動挑選時會跳過它。
 
-這個編號會貫穿整個流程：worktree、branch、spec、plan、learning 都用它命名，事後從任何一個檔案都能追回同一個項目。另外還有兩種編號：`IDEA-NNN` 是還沒排進 Roadmap 的想法（多半是 review 時延後處理的問題），`D-NNN` 是架構決策。
+這個編號會貫穿整個流程：worktree、branch、spec、plan、learning 都用它命名，事後從任何一個檔案都能追回同一個項目。另外還有一種編號：`IDEA-NNN` 是還沒排進 Roadmap 的想法（多半是 review 時延後處理的問題）。
 
 **Roadmap 長什麼樣**
 
@@ -111,22 +113,18 @@ Claude 會配一個新的 R-NNN 並寫進 Roadmap。順便說清楚怎樣算做
 「幫我把 XXX 加到 Roadmap」
   │ 配一個新的 R-NNN
   ▼
-Later → Next → Now     ← /ship-roadmap 排序；太大的標 ⚠️ 並建議拆成子項目
-  │ （選用）/ship-explain 寫白話說明、/ship-propose 寫提案
+Later → Next → Now     ← 順序由你決定；brainstorm 會建議把太大的項目拆成幾列
   ▼
 /ship-next R-NNN       ← brainstorm → spec → plan → 實作 → review → merge
   │
   ▼
-✅ Done                ← review 延後處理的問題變成 IDEA，下次 /ship-roadmap 會建議排進來
+✅ Done                ← review 延後處理的問題變成 IDEA，要不要排進 Roadmap 由你決定
 ```
 
-`/ship-roadmap` 每次都會重新讀策略文件、還沒擱置的 IDEA、已接受的決策和最近 30 天的 learning，依「影響 × 相依性」重新排序。Now 最多放 5 項，缺少 `↳ done when:` 的項目會被特別標出來。
-
 **實際操作**
 
 ```text
 幫我把「客服批次關閉工單」加到 Roadmap  # 配好 R-NNN
-/ship-roadmap                           # 重新排序
 /ship-next                              # 取 Now 第一項，做到 merge
 /ship-next R-012 --auto:yes             # 指定項目，全自動
 /ship-next --adhoc "修 token 外洩"      # 臨時插單
@@ -147,9 +145,9 @@ Later → Next → Now     ← /ship-roadmap 排序；太大的標 ⚠️ 並建
 | 好處 | 缺點 |
 |---|---|
 | 一個編號追到底：從想法、spec、commit 到 learning 都能用 R-NNN 串起來 | 很吃紀律：描述和 done-when 寫得越模糊，brainstorm 和全自動模式就越容易做偏 |
-| 「做完」有明確定義：done-when 讓你和 AI 用同一個標準驗收，全自動模式也有依據 | 排序品質看 `ce-strategy`：沒裝 compound-engineering 時改由 Claude 在對話中排序，結果比較不穩定 |
-| 項目會被逼著變小：太大的會被標 ⚠️，拆出來的每個子項目都必須能驗收 | IDEA 會越積越多：review 自動開的 IDEA 需要定期整理，或標成 `shelved` 擱置 |
-| 問題不會被遺忘：延後處理的 review 問題會變成 IDEA，下次排 Roadmap 時再被看到 | 編號在本機分配：兩台機器在 Roadmap 同步之前各自開新項目，可能拿到同一個號碼 |
+| 「做完」有明確定義：done-when 讓你和 AI 用同一個標準驗收，全自動模式也有依據 | 排序靠你自己：沒有自動排序，Now 的順序就是你寫的順序 |
+| 項目會被逼著變小：brainstorm 會建議拆開太大的項目，拆出來的每一列都必須能驗收 | IDEA 會越積越多：review 自動開的 IDEA 需要定期整理，或標成 `shelved` 擱置 |
+| 問題不會被遺忘：延後處理的 review 問題會變成 IDEA，留在 `docs/ideas/` 等你決定 | 編號在本機分配：兩台機器在 Roadmap 同步之前各自開新項目，可能拿到同一個號碼 |
 
 ### 遠端開發
 
@@ -173,22 +171,22 @@ devsync stop my-repo   # 結束
 **缺點**
 
 - **小改動也要走全套**：一行修正一樣會經過 brainstorm、spec、plan、review，花的時間和 token 都多。
-- **依賴多**：Obsidian vault、superpowers、code-review-skill 少一個就跑不起來。
+- **依賴多**：Obsidian vault、superpowers 少一個就跑不起來。
 - **綁我的環境**：只支援 macOS，範例設定寫死我的路徑，devsync 也只連內部的 dl01–dl04。
 - **流程由模型執行**：helper script 有 bats 測試，但指令本身是給 Claude 讀的 markdown，每一步有沒有照做，取決於模型。
-- **全自動的品質看 Roadmap 寫得多清楚**：`--auto:yes` 遇到問題一律選建議選項，沒有寫 `↳ explain:` 或提案時，做出來的可能和你想的不一樣。
+- **全自動的品質看 Roadmap 寫得多清楚**：`--auto:yes` 遇到問題一律選建議選項，Roadmap 寫得越模糊，做出來的就越可能和你想的不一樣。
 - **策略只能在 Obsidian 改**：同步是單向的，直接在 repo 改 ROADMAP 會被擋下來。
 - **Knowledge graph 很貴**：大型 repo 第一次跑 `/understand` 會消耗大量 token。
 
 ## 5. 需求
 
-**必要**：macOS + Homebrew、Claude Code、Obsidian vault、[superpowers](https://github.com/obra/superpowers)、[code-review-skill](https://github.com/awesome-skills/code-review-skill)、bun（gstack 用）、dl01–dl04 的 SSH 帳號（devsync 用）
+**必要**：macOS + Homebrew、Claude Code、Obsidian vault、[superpowers](https://github.com/obra/superpowers)、dl01–dl04 的 SSH 帳號（devsync 用）。[code-review-skill](https://github.com/awesome-skills/code-review-skill) 已經收在 repo 裡。
 
 **選用**：
 
 | 項目 | 用途 |
 |---|---|
-| compound-engineering（`ce-*`） | `/ship-roadmap`、`/ship-compound` 的自動化 |
+| compound-engineering（`ce-*`） | `/ship-compound` 的自動化 |
 | [understand-anything](https://github.com/Lum1104/Understand-Anything) | 影響範圍分析、knowledge graph 自動重建（見第 6 節） |
 | [ponytail](https://github.com/DietrichGebert/ponytail) | executor 的寫碼規則 |
 | codex CLI | 第 3 種 executor |
@@ -207,7 +205,7 @@ devsync stop my-repo   # 結束
 | 3 | 讀過去的 learning 和 `CONTEXT.md`，brainstorm 出 spec（必須有 `## Seams`） |
 | 4 | 寫 plan |
 | 5 | 執行 plan |
-| 6 | Code review，blocking 必須歸零，最多修 3 輪 |
+| 6 | Code review 加獨立的 security review，blocking 必須歸零，最多修 3 輪 |
 | 7 | Squash merge，或開 PR/MR |
 | 8 | 寫 learning、Roadmap 移到 Done |
 | 9 | 刪除 worktree 和 branch |
@@ -227,7 +225,6 @@ devsync stop my-repo   # 結束
 | 時機 | 做什麼 |
 |---|---|
 | `/ship-init --with-ua` | 提示你對 repo 跑 `/understand`，建立 knowledge graph |
-| `/ship-roadmap` | 用 graph 輔助排序，並判斷項目是否太大（橫跨 3 個以上模組） |
 | Phase 1.5 | graph 比 HEAD 舊時發出警告 |
 | Phase 6 | 用 `/understand-diff` 產出影響範圍報告（受影響的模組、層級、風險評估），再比對 vault 的 `REMINDERS.md`，一起交給 reviewer |
 | Phase 8 | `/ship-compound` 用影響範圍草擬一份 case 筆記，並問你要不要新增 REMINDERS 規則 |
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 7cce7da..0c45bc9 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -779,10 +779,9 @@ CHECKS
 1. **Verify code-review-skill installed:**
    ```bash
    if [ ! -f ~/.claude/skills/code-review-skill/SKILL.md ]; then
-     echo "ERROR: awesome-skills/code-review-skill not installed."
-     echo "Install: git clone https://github.com/awesome-skills/code-review-skill \\"
-     echo "         ~/.claude/skills/code-review-skill"
-     echo "Then re-invoke /ship-next ${ID} to resume from this phase."
+     echo "ERROR: code-review-skill is not installed."
+     echo "It ships with ai_system: run ./sync.sh restore in the ai_system checkout (on main),"
+     echo "then re-invoke /ship-next ${ID} to resume from this phase."
      exit 1
    fi
    ```
R004_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..7`, all 7 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md claude-skills/ship-workflow
git commit -m "docs(repo): R-004 Task 7 — repo CLAUDE.md, README and ship-next's install hint match the new layout"
```

### Task 8: Sync the spec with what the build found

Seam: none (documentation only)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** two decisions changed while building. `airos-binding` changes only at a linked worktree's root (the broader rule renamed every nested test fixture), and `remove_command_copies` keeps a tracked copy that has local edits. The Phase 6 install hint gains "no `git clone`".

**Files:**
- Modify: `docs/specs/R-004-refactor-around-ship-next.md`

- [ ] **Step 1: Apply the spec update**

````bash
git apply <<'R004_PATCH'
diff --git a/docs/specs/R-004-refactor-around-ship-next.md b/docs/specs/R-004-refactor-around-ship-next.md
index e680628..75ce50d 100644
--- a/docs/specs/R-004-refactor-around-ship-next.md
+++ b/docs/specs/R-004-refactor-around-ship-next.md
@@ -139,7 +139,8 @@ docs/                unchanged, apart from this item's files
     - delete the step 4.5 `↳ explain` / proposal warnings;
     - in the step 4.5 refusal and the slug note, replace `/ship-roadmap` and
       `/ship-explain` with plain instructions such as "edit ROADMAP.md";
-    - make the Phase 6 step 1 install hint say `./sync.sh restore` in ai_system.
+    - make the Phase 6 step 1 install hint say `./sync.sh restore` in ai_system, with
+      no `git clone`.
   - **ship-idea, ship-init, `SKILL.md`, `README.md`:** list the five commands and
     nothing else. Drop the stale `devsync push` install line.
 - **The old `CLAUDE.md` sync entry.** The `SYNC_FILES` pairing of `~/.claude/CLAUDE.md`
@@ -189,6 +190,8 @@ The skills rsync, in both directions, is removed.
     commits, or opens an MR in mr-mode repos.
   - An **untracked or gitignored** copy is deleted with plain `rm`. 3 of the 6 repos hold
     their copies this way.
+  - A tracked copy **with local edits** is left in place and reported, so no edit is
+    lost.
   - It works on any checkout path, a linked worktree included, and does not use
     `cwd-guard.sh`.
   - It refuses, and removes nothing, unless `~/.claude/commands/ship-next.md` resolves
@@ -240,10 +243,14 @@ The skills rsync, in both directions, is removed.
 - **The cost.** Phase 3.5 then mirrored R-001's and R-003's specs into two bogus vault
   folders, `10 Projects/R-00N-…/Specs/`. Claude has moved them, by hand, to
   `10 Projects/ai_system/Specs/`.
-- **Fix.** Derive the name from the main checkout:
+- **Fix.** At the root of a linked worktree, derive the name from the main checkout:
   `git rev-parse --path-format=absolute --git-common-dir` → its parent directory →
   `basename`.
-  - Outside a git repo, fall back to `basename "$(pwd)"`.
+  - Everywhere else, the name stays `basename "$(pwd)"`, as before: the main checkout,
+    a subdirectory, and a plain directory nested inside some checkout.
+  - The narrowing was found while building. The suite's fixtures are non-git
+    directories under `tests/.tmp/`, often inside a ship-next worktree. "Use the main
+    checkout whenever inside git" gave every one of them the enclosing checkout's name.
   - `PROJECT_NAME_OVERRIDE` keeps winning.
 
 ## Seams
@@ -254,9 +261,9 @@ The skills rsync, in both directions, is removed.
 | `sync.sh backup` | `./sync.sh backup` | Copies `~/.claude/CLAUDE.md` → `config/claude/CLAUDE.md` and the devsync config → `devsync/config.toml`; writes nothing else. |
 | `sync.sh status` | `./sync.sh status` | One line per link and config file with its state. Exit 1 when any link is not `ok`. |
 | `ship-init` | `/ship-init`, `/ship-init --upgrade` | Init writes no `.claude/commands/ship-*.md`. `--upgrade` calls `remove_command_copies` on the current repo. |
-| `remove_command_copies` | `remove_command_copies <repo-path>` | Removes only the 13 names in 3.4: tracked → `git rm`, staged and not committed; untracked or ignored → `rm`. Other files are untouched. Refuses and removes nothing when the user-level `ship-next.md` does not resolve. Works in a linked worktree. |
+| `remove_command_copies` | `remove_command_copies <repo-path>` | Removes only the 13 names in 3.4: tracked → `git rm`, staged and not committed; untracked or ignored → `rm`; a tracked copy with local edits → kept and reported. Other files are untouched. Refuses and removes nothing when the user-level `ship-next.md` does not resolve. Works in a linked worktree. |
 | `live_checkout_warning` | shell function | One warning line when the checkout behind `~/.claude/skills/ship-workflow` is off `main` or dirty; nothing otherwise; exit 0 always. |
-| `airos-binding.sh project_name` | CLI | The main checkout's directory name, whether run in the checkout, a subdirectory or a linked worktree of it. Outside git: `basename "$(pwd)"`. `PROJECT_NAME_OVERRIDE` wins. |
+| `airos-binding.sh project_name` | CLI | At a linked worktree's root: the main checkout's directory name. Anywhere else, including a plain directory nested inside a worktree: `basename "$(pwd)"`. `PROJECT_NAME_OVERRIDE` wins. |
 | repo contents | the tree | `claude-skills/` holds exactly `ship-workflow`, `run-plan`, `code-review-skill`. `commands/` holds exactly the five kept commands. |
 
 ## §4 Acceptance
@@ -277,7 +284,7 @@ The skills rsync, in both directions, is removed.
 | AC-11 | the R-004 tree | grep the kept commands, `SKILL.md`, `README.md` | no `/ship-propose`, `/ship-explain`, `/ship-research`, `/ship-decision`, `/ship-roadmap`, `/ship-brief`, `devsync push` |
 | AC-12 | the R-004 tree | `claude-skills/run-plan/SKILL.md` | contains the REPAIR RULE text from `f2fd23f` |
 | AC-13 | the R-004 tree | inspect `claude-skills/code-review-skill/` | `SKILL.md`, `LICENSE` and `VENDORED.md` (upstream URL + `17267ff`) present; no `.git` |
-| AC-15 | a repo `proj` and a linked worktree of it at `…/proj-worktrees/R-9-x` | `airos-binding.sh project_name` in each | `proj` in both |
+| AC-15 | a repo `proj` and a linked worktree of it at `…/proj-worktrees/R-9-x` / a plain dir `fixture/my-repo` inside a linked worktree | `airos-binding.sh project_name` | `proj` at the worktree root / `my-repo` |
 | AC-14 | the full ship-workflow suite | `bats tests/` | passes, apart from the known linked-worktree `cwd-guard` failure |
 
 ## §5 Rollout (in this order)
R004_PATCH
````

- [ ] **Step 2: Check the patch applied**

Run: `git diff --stat`

Expected: only `docs/specs/R-004-refactor-around-ship-next.md` changed.

- [ ] **Step 3: Commit**

```bash
git add docs/specs
git commit -m "docs(spec): R-004 Task 8 — spec matches the build (worktree-root naming, locally edited copies kept)"
```

### Task 9: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..621`, 620 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Check the layout**

Run: `ls claude-skills; ls claude-skills/ship-workflow/commands; bash -n sync.sh && echo ok`

Expected: `code-review-skill run-plan ship-workflow`; the five `ship-{compound,idea,init,land,next}.md`; `ok`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 counts.
