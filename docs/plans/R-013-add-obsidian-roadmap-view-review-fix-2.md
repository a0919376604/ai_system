# R-013 review fix 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding of R-013's first code review, each reproduced first: 5 blocking, 8 important, 11 nits (`/tmp/ship-next-review-R-013-1.md`).

**Architecture:** Same method as the main plan (`docs/plans/R-013-add-obsidian-roadmap-view.md`, already executed on this branch): every code step is a `git apply` patch from the prototype, replayed red/green, task by task, in a linked worktree of this branch.

**Tech Stack:** bash + zsh (sourced libs), bats 1.13, jq, Node ≥ 22 (`node:test`), Obsidian plugin API.

**Spec:** `docs/specs/R-013-add-obsidian-roadmap-view.md` (its "Review attempt 1" decisions).

## Global Constraints

The main plan's Global Constraints all apply. In short:
- Edit only this repository; never `~/.claude/`, `~/.agents/`, the home directory or the vault. `obsidian-roadmap-view/test/local-vault.test.js` reads the vault read-only — run it, do not change it.
- Do not run `./sync.sh restore` / `backup` against the real home; do not touch Obsidian.
- `.ship/` is not part of this plan. Stage only the paths each commit step names; never `git add -A`.
- Run every command from the repository (worktree) root. Patches are the code, generated against this exact base (`a5b5929` plus this plan's commit): if one does not apply, STOP.
- `main.js` may `require` only `"obsidian"`. No `package.json`, no `npm install`.
- Read `.ship/tdd-rules.md` before tests and `.ship/ponytail-rules.md` before code, if present.
- Known pre-existing failure in a linked worktree: `cwd-guard: exits 0 when not in a git repo at all`. It must stay the ONLY failure.
- One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

1. A command block that calls `sn_status` in a fresh shell — every call site must source `lib/ship-next.sh` itself. → Task 1.
2. A live refresh while the person is reading, searching or has a fold open — nothing moves, closes or collapses. → Task 3.
3. `- [~]` and `- [X]` rows in a real ROADMAP — every one is an item. → Task 4.
4. Obsidian calling the view's lifecycle (`View.open` → `Component.load`) — the view replaces none of it. → Task 4.
5. Fixture text in a public repo — invented, never copied from a company ROADMAP. → Task 2.

---
### Task 1: Every `sn_status` call runs in a shell that sourced the lib; `--discard` and `--summary` edge cases

Seam: `sn_status` (its call sites) / `roadmap-insert --summary`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1, blocking: four new `sn_status` calls (small lane, `stop_infra`, spec-level, the stop_exhausted block) ran in a fresh shell without `lib/ship-next.sh`, so `blocked` was never recorded on 3 of the 4 Phase 5 stops. A test now checks every call site. `stop_infra` is recorded inside `sn_codex_after_exit`, the only place that knows the reason. Also: `--discard` removes the status file even when the worktree is already gone (and never for an ID that is not a plain `R-…`); `--summary` passes through `ENVIRON`, so a typed `\n` stays text; two test-hygiene fixes; the restore trigger in CLAUDE.md names `obsidian-roadmap-view/`.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Modify: `claude-skills/ship-workflow/lib/roadmap-insert.sh`
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`
- Modify: `claude-skills/ship-workflow/tests/test_command-blocks.bats`
- Modify: `claude-skills/ship-workflow/tests/test_repo-layout.bats`
- Modify: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-lib.bats`
- Modify: `claude-skills/ship-workflow/tests/test_sync-install.bats`

**Interfaces:**
- Consumes: Task 2 of the main plan (`sn_status`, `sn_codex_after_exit`).
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index d4731f3..c0c3da2 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -644,3 +644,19 @@ land_case() {
     [ "$(jq -r .phase "$vault/10 Projects/repo-$shell/ship-status/R-1.json")" = done ] || return 1
   done
 }
+
+@test "ship-next --discard deletes the status file even when the worktree is already gone" {
+  vault=$(make_fake_airos "$SCRATCH" repo)
+  write_global_config "$HOME" "$vault"
+  st="$vault/10 Projects/repo/ship-status"
+  mkdir -p "$st"
+  echo '{}' > "$st/R-1.json"
+  echo '{}' > "$vault/10 Projects/repo/x.json"
+  block ship-next.md '^1\. \*\*Handle `--discard`' '^1\.6\. ' > "$SCRATCH/d.sh"
+  run env MODE=discard TARGET=R-1 bash "$SCRATCH/d.sh"
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [[ "$output" == *"No worktree found for R-1"* ]] || return 1
+  [ ! -e "$st/R-1.json" ] || return 1
+  run env MODE=discard TARGET=../x bash "$SCRATCH/d.sh"
+  [ -e "$vault/10 Projects/repo/x.json" ]
+}
diff --git a/claude-skills/ship-workflow/tests/test_roadmap-insert.bats b/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
index 9e717fc..cd9f460 100644
--- a/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
+++ b/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
@@ -340,3 +340,10 @@ EOF
   "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9.1 "child" --child R-9 --summary "子項目的一句話"
   grep -qxF '      ↳ explain: 子項目的一句話' "$ROADMAP"
 }
+
+@test "roadmap-insert: --summary keeps a typed backslash as text, on one line" {
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9 "desc" --summary 'a\nb'
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9.1 "child" --child R-9 --summary 'c\td'
+  grep -qxF '    ↳ explain: a\nb' "$ROADMAP" || return 1
+  grep -qxF '      ↳ explain: c\td' "$ROADMAP"
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
index 3186b37..bc5b933 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
@@ -330,7 +330,7 @@ section() { awk -v h="## Phase $1 " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f
     section "${pair%%:*}" | grep -qF "sn_status \"\$WORKTREE\" ${pair#*:}" || { echo "Phase ${pair%%:*} does not record ${pair#*:}"; return 1; }
   done
   section 4 | grep -F 'Small-change lane' | grep -qF 'sn_status "$WORKTREE" build'
-  for anchor in '**`stop_infra`**' 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted'; do
+  for anchor in 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted'; do
     grep -F -A2 -- "$anchor" "$SHIP_SKILL_ROOT/commands/ship-next.md" | grep -qF 'sn_status "$WORKTREE" blocked' \
       || { echo "no blocked status at: $anchor"; return 1; }
   done
@@ -340,3 +340,34 @@ section() { awk -v h="## Phase $1 " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f
   section 1 | grep -F 'roadmap-insert.sh' | grep -qF -- '--adhoc --summary "$SUMMARY_ZH"'
   section 1 | grep -qE '^ *SUMMARY_ZH=.*zh-TW'
 }
+
+@test "a codex infra stop records the ship as blocked, with the reason" {
+  status_fixture
+  echo 'ERROR: Your workspace is out of credits.' > "/tmp/run-plan-codex-${SLOT}.log"
+  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_codex_after_exit "$WT" "$PLAN" "$SLOT"'
+  [ "$status" -eq 0 ]
+  [[ "$output" == *'CODEX_ROUTE=stop_infra'* ]] || return 1
+  [ "$(jq -r .phase "$PROJ/ship-status/R-9.json")" = blocked ] || return 1
+  [[ "$(jq -r .note "$PROJ/ship-status/R-9.json")" == "codex infra: "* ]]
+}
+
+# Each fenced block runs in a fresh shell, so a block — or an inline `…` command —
+# that calls sn_status must source lib/ship-next.sh itself.
+@test "every sn_status call in a command file sources lib/ship-next.sh in its own shell" {
+  for f in "$SHIP_SKILL_ROOT"/commands/*.md; do
+    run awk '
+      /^[[:space:]]*```bash[[:space:]]*$/ { inb = 1; blk = ""; calls = 0; next }
+      inb && /^[[:space:]]*```[[:space:]]*$/ {
+        inb = 0
+        if (calls && blk !~ /lib\/ship-next\.sh/) print FILENAME ": a block calls sn_status without sourcing lib/ship-next.sh"
+        next
+      }
+      inb { blk = blk "\n" $0; if ($0 ~ /sn_status "/) calls = 1; next }
+      /sn_status "/ && $0 !~ /source ~\/\.claude\/skills\/ship-workflow\/lib\/ship-next\.sh && sn_status "/ {
+        print FILENAME ":" FNR ": an inline sn_status call does not source lib/ship-next.sh"
+      }
+    ' "$f"
+    [ -z "$output" ] || { echo "$output"; return 1; }
+  done
+  sed -n '/^sn_codex_after_exit()/,/^}/p' "$SHIP_LIB/ship-next.sh" | grep -qF 'sn_status "$WORKTREE" blocked'
+}
R013_FIX2_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_roadmap-insert.bats tests/test_ship-next-lib.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats tests/test_sync-install.bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..144`, 140 ok, these 4 fail:
  - `not ok 38 roadmap-insert: --summary keeps a typed backslash as text, on one line`
  - `not ok 66 a codex infra stop records the ship as blocked, with the reason`
  - `not ok 67 every sn_status call in a command file sources lib/ship-next.sh in its own shell`
  - `not ok 115 ship-next --discard deletes the status file even when the worktree is already gone`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/CLAUDE.md b/CLAUDE.md
index 74eac11..1b68a46 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -23,8 +23,8 @@ machine therefore runs whatever this checkout holds, uncommitted edits included.
   `node --test obsidian-roadmap-view/test/`.
 - `./sync.sh restore` copies the plugin into `<airos_vault>/.obsidian/plugins/roadmap-view/`
   when it changed. It never enables it: that is a one-time click in Obsidian.
-- After a pull that changes `sync.sh` or the set of directories in `claude-skills/`, run
-  `./sync.sh restore`. Then `./sync.sh status` must print `ok` for every link.
+- After a pull that changes `sync.sh`, `obsidian-roadmap-view/` or the set of directories
+  in `claude-skills/`, run `./sync.sh restore`. Then `./sync.sh status` must print `ok` for every link.
 - After editing `~/.claude/CLAUDE.md`, run `./sync.sh backup`. It copies the file to
   `config/claude/CLAUDE.md`. That file is the backup of the global rules, not this
   repo's rules.
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index df85aee..82866b3 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -57,9 +57,14 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
        git branch -D "$BRANCH" 2>/dev/null || true
        VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
        rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
-       rm -f "${VAULT_SPECS_DIR%/Specs}/ship-status/${ID}.json"
        echo "Discarded worktree at $WT and branch $BRANCH"
      else echo "No worktree found for $ID"; fi
+     # The Roadmap 檢視 status file goes even when the worktree is already gone.
+     case "$ID" in
+       R-*[!A-Za-z0-9.-]*) ;;
+       R-[0-9]*) PROJ_DIR=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path 2>/dev/null) \
+                   && rm -f "$PROJ_DIR/ship-status/${ID}.json" ;;
+     esac
      exit 0
    fi
    ```
@@ -229,7 +234,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
 ## Phase 4 — Writing plans
 
 **Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" plan`.
-**Small-change lane.** When the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: run `sn_status "$WORKTREE" build`, then implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, then go to Phase 6. Log the choice in auto mode. Set `EXECUTOR_CHOICE=2` and record it via Phase 5 step 2 and render the rule files via step 2.5 before implementing, so review fixes retain the inline executor.
+**Small-change lane.** When the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" build`, then implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, then go to Phase 6. Log the choice in auto mode. Set `EXECUTOR_CHOICE=2` and record it via Phase 5 step 2 and render the rule files via step 2.5 before implementing, so review fixes retain the inline executor.
 **Plan-authoring guidance:**
 - Verification/acceptance steps MUST run scoped pytest, not the full suite: list affected files or relevant module directories, e.g. `pytest tests/domain/test_foo.py tests/api/test_bar.py -q`. Missing environment credentials can leave a broad run hanging.
 - Reader-untouched grep guards MUST use `git diff <base>...HEAD -- <paths>`: three-dot excludes unrelated base-branch commits.
@@ -341,13 +346,13 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    ```
    Then route on `$CODEX_ROUTE`:
    - **`continue`** (verdict `done` / `done_with_concerns`) → the helper has recorded the round and marked the run finished; continue to Phase 6.
-   - **`stop_infra`** (verdict `infra`) → run `sn_status "$WORKTREE" blocked "codex infra: $CODEX_REASON"`, then STOP and notify using Phase 9 routing with `$CODEX_REASON`; do not relaunch, leave the **attempt count unchanged**, and retain the worktree and branch.
+   - **`stop_infra`** (verdict `infra`) → `sn_codex_after_exit` has already recorded the ship as `blocked` with `$CODEX_REASON`. STOP and notify using Phase 9 routing with `$CODEX_REASON`; do not relaunch, leave the **attempt count unchanged**, and retain the worktree and branch.
    - **`classify`** (verdict `blocked`) → read the executor's report and classify it into exactly one of three, then act:
      | Class | Signal | Action |
      |---|---|---|
      | **plan defect** | the prescribed step is wrong, ambiguous or impossible as written | repair `$PLAN`, relaunch from the blocked task |
      | **executor error** | the plan is right and the executor deviated — a transcription slip, an edit in the wrong place | relaunch with a correction note, plan unchanged |
-     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | `sn_status "$WORKTREE" blocked "spec-level: <the finding>"`, then **STOP and notify the operator** |
+     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "spec-level: <the finding>"`, then **STOP and notify the operator** |
      **When the classification is unclear, treat it as spec-level and escalate.** Do not redesign the approach.
      **Set these three yourself from the classification above** — they are the judgement's output and nothing computes them:
      ```bash
@@ -357,13 +362,17 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
      ```
      Record the round, then relaunch or stop:
      ```bash
+     source ~/.claude/skills/ship-workflow/lib/ship-next.sh
+     source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
+     source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
+     sn_state_load "$WORKTREE"
      CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))
      codex_round_append "$WORKTREE" "$CODEX_ATTEMPT" blocked "$CODEX_REPORT" "$CODEX_CLASS" "$CODEX_NOTE"
      codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" blocked "$CODEX_CLASS" "$CODEX_BLOCKED_AT"
      CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
      if [ "$CODEX_ATTEMPT" -ge "$CODEX_ATTEMPT_CAP" ]; then
        CODEX_ROUTE=stop_exhausted
-       sn_status "$WORKTREE" blocked "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted"
+       sn_status "$WORKTREE" blocked "codex: repair attempts exhausted"
        echo "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted — stopping." >&2
        echo "worktree retained at $WORKTREE; history in .ship/codex-rounds.md" >&2
      else
diff --git a/claude-skills/ship-workflow/lib/roadmap-insert.sh b/claude-skills/ship-workflow/lib/roadmap-insert.sh
index 584e245..cfce378 100755
--- a/claude-skills/ship-workflow/lib/roadmap-insert.sh
+++ b/claude-skills/ship-workflow/lib/roadmap-insert.sh
@@ -115,7 +115,9 @@ case "$MODE" in
     [ -n "$SUMMARY" ]   && EXPLAIN_LINE="    ↳ explain: ${SUMMARY}"
     [ -n "$DONE_WHEN" ] && DONE_LINE="    ↳ done when: ${DONE_WHEN}"
 
-    awk -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
+    # The explain line goes through ENVIRON: `awk -v` would turn a typed `\n` into a break.
+    EXPLAIN_LINE="$EXPLAIN_LINE" awk -v line="$NEW_LINE" -v done_line="$DONE_LINE" '
+      BEGIN { explain = ENVIRON["EXPLAIN_LINE"] }
       { print }
       /^## 🔥 Now/ && !inserted {
         print line
@@ -151,7 +153,8 @@ case "$MODE" in
     # parent regex. This is more robust than grepping for $RID afterwards,
     # which false-positives when the child ID happens to appear elsewhere
     # in the file (e.g. as a wikilink in a comment).
-    if awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
+    if EXPLAIN_LINE="$EXPLAIN_LINE" awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" -v done_line="$DONE_LINE" '
+      BEGIN { explain = ENVIRON["EXPLAIN_LINE"] }
       {
         print
         if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
diff --git a/claude-skills/ship-workflow/lib/ship-next.sh b/claude-skills/ship-workflow/lib/ship-next.sh
index f28989e..2729bfc 100644
--- a/claude-skills/ship-workflow/lib/ship-next.sh
+++ b/claude-skills/ship-workflow/lib/ship-next.sh
@@ -166,6 +166,10 @@ sn_codex_after_exit() {
     rm -f "$WORKTREE/.ship/codex.pid"
 
   fi
+  # R-013: the Roadmap 檢視 plugin shows the stop; the reason is only known here.
+  if [ "$CODEX_ROUTE" = stop_infra ]; then
+    sn_status "$WORKTREE" blocked "codex infra: $CODEX_REASON"
+  fi
   sn_state_set "$WORKTREE" CODEX_FINAL_VERDICT "$CODEX_FINAL_VERDICT"
   sn_state_set "$WORKTREE" CODEX_ROUNDS "${CODEX_ROUNDS:-0}"
   sn_state_set "$WORKTREE" CODEX_REPORT "$CODEX_REPORT"
diff --git a/claude-skills/ship-workflow/tests/test_repo-layout.bats b/claude-skills/ship-workflow/tests/test_repo-layout.bats
index e27482b..d523f7a 100644
--- a/claude-skills/ship-workflow/tests/test_repo-layout.bats
+++ b/claude-skills/ship-workflow/tests/test_repo-layout.bats
@@ -62,7 +62,10 @@ setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }
 # R-013: the Roadmap 檢視 plugin is plain JS with node:test, outside claude-skills/.
 @test "the Roadmap view plugin's node tests pass, so one bats run covers them" {
   command -v node >/dev/null || skip "node not installed"
-  run node --test "$REPO_ROOT/obsidian-roadmap-view/test/"
+  # A scratch HOME: the real-vault test (AC-4b) skips here and runs under plain node --test.
+  scratch=$(make_scratch repo-layout)
+  run env HOME="$scratch" node --test "$REPO_ROOT/obsidian-roadmap-view/test/"
+  rm -rf "$scratch"
   [ "$status" -eq 0 ] || { echo "$output" | tail -30; return 1; }
 }
 
diff --git a/claude-skills/ship-workflow/tests/test_sync-install.bats b/claude-skills/ship-workflow/tests/test_sync-install.bats
index c438430..a96a312 100644
--- a/claude-skills/ship-workflow/tests/test_sync-install.bats
+++ b/claude-skills/ship-workflow/tests/test_sync-install.bats
@@ -188,7 +188,7 @@ plugin_fixture() {
   [ "$status" -eq 0 ] || { echo "$output"; return 1; }
   for f in manifest.json main.js styles.css; do cmp -s "$R/obsidian-roadmap-view/$f" "$P/$f" || { echo "$f"; return 1; }; done
   [ "$(ls "$P" | tr '\n' ' ')" = "main.js manifest.json styles.css " ]
-  [ ! -L "$P" ] && [ ! -L "$P/main.js" ]
+  [ ! -L "$P" ] && [ ! -L "$P/main.js" ] || return 1
   [[ "$output" == *"Roadmap 檢視"* ]] || return 1
   touch -t 200001010000 "$P"/* && touch -t 200101010000 "$SCRATCH/ref"
   run bash "$R/sync.sh" restore --yes
R013_FIX2_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_roadmap-insert.bats tests/test_ship-next-lib.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats tests/test_sync-install.bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..144`, all 144 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md claude-skills/ship-workflow/commands/ship-next.md claude-skills/ship-workflow/lib/roadmap-insert.sh claude-skills/ship-workflow/lib/ship-next.sh claude-skills/ship-workflow/tests/test_command-blocks.bats claude-skills/ship-workflow/tests/test_repo-layout.bats claude-skills/ship-workflow/tests/test_roadmap-insert.bats claude-skills/ship-workflow/tests/test_ship-next-lib.bats claude-skills/ship-workflow/tests/test_sync-install.bats
git commit -m "fix(ship-next): R-013 review 1 — sn_status call sites source the lib; discard and summary edge cases"
```

### Task 2: Fixture text is invented, not copied from the langlive ROADMAP

Seam: `parseRoadmap` (its fixture)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1, blocking: `test/parse.test.js` copied real headlines, commit hashes, a component name and mockup file names from a company ROADMAP into this public repo. The row formats stay exactly as they were; only the words, hashes and file names are invented. Test-only change: there is no red step.

**Files:**
- Modify: `obsidian-roadmap-view/test/parse.test.js`

**Interfaces:**
- Consumes: Task 3 of the main plan.
- Produces: nothing later tasks use.

- [ ] **Step 1: Apply the test change**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/test/parse.test.js b/obsidian-roadmap-view/test/parse.test.js
index 4e694be..2b85007 100644
--- a/obsidian-roadmap-view/test/parse.test.js
+++ b/obsidian-roadmap-view/test/parse.test.js
@@ -9,33 +9,33 @@ const MD = `# ROADMAP
 
 ## 🔥 Now (3-5 items)
 
-- [ ] **R-094.3** [FEATURE · P2 · UIUX · blocked: prod LIFF channel · 接續 R-094.2] 推播連結追蹤＋點擊貼標 —— 推播裡的網址換成追蹤連結
-    ↳ mockup 同上（方案 A）· 代價：第一次點會看到許可畫面
-    ↳ done when: 推播網址自動換成追蹤連結（可關）
-- [x] **R-248** [FEATURE · P2 · UIUX · mockup 定案 B · ✅ merged 2026-10-19 · main \`7fe542a1\`（squash 直接 push，未開 MR）· 尚未部署 test · learning \`docs/learnings/R-248-x.md\`] 總覽分頁下方「問題主題／問題細節」列表調整 —— 拿掉解決率欄
-  ↳ done when: 列表沒有解決率欄
-  ↳ explain: mockup \`Proposals/mockups/insights-overview-list-polish-mockup.html\` 方案 B（以人為主版）。
-
-- [x] **R-256** [FEATURE · P2 · UIUX · mockup 定案 A · ✅ 2026-10-22～24 · squash 直接 push main：第 1 步 \`60b4da26\` · 第 2 步 \`d7cbc584\`] 對話面板改良（\`LeafTimelinePanel\`，四個分頁共用）—— 圖片可放大
+- [ ] **R-094.3** [FEATURE · P2 · UIUX · blocked: 等待正式環境的金鑰 · 接續 R-094.2] 分享連結追蹤＋點擊後自動分類 —— 訊息裡的網址換成追蹤連結
+    ↳ mockup 同上（方案 A）· 代價：第一次點會多一個確認畫面
+    ↳ done when: 訊息網址自動換成追蹤連結（可關）
+- [x] **R-248** [FEATURE · P2 · UIUX · mockup 定案 B · ✅ merged 2026-10-19 · main \`a1b2c3d4\`（squash 直接 push，未開 MR）· 尚未部署 test · learning \`docs/learnings/R-248-x.md\`] 首頁「熱門分類／分類細節」清單調整 —— 拿掉比例欄
+  ↳ done when: 清單沒有比例欄
+  ↳ explain: mockup \`Proposals/mockups/home-list-polish-mockup.html\` 方案 B（以人為主版）。
+
+- [x] **R-256** [FEATURE · P2 · UIUX · mockup 定案 A · ✅ 2026-10-22～24 · squash 直接 push main：第 1 步 \`0f1e2d3c\` · 第 2 步 \`4b5a6978\`] 訊息面板改良（\`MessagePanel\`，四個分頁共用）—— 圖片可放大
 - [ ] **R-014** 審查中的項目 · status=in-review · mr=https://gitlab.example.com/g/p/-/merge_requests/285
 
 ## 🔜 Next
 
-- [ ] **R-231** [EPIC · P2 · needs-brainstorm] 客戶標籤：從工單與對話自動長出可篩選的 tag —— **來源：** 使用者討論。
-    ↳ done when: 行銷能用 tag 篩出名單
-    ↳ done when: 每個 tag 點得到來源對話
-    ↳ explain: 精準推播要先知道誰對什麼有興趣，這個 epic 把聊天紀錄變成可以篩選的標籤。
+- [ ] **R-231** [EPIC · P2 · needs-brainstorm] 使用者標籤：從紀錄自動長出可篩選的 tag —— **來源：** 使用者討論。
+    ↳ done when: 能用 tag 篩出名單
+    ↳ done when: 每個 tag 點得到來源紀錄
+    ↳ explain: 要先知道誰對什麼有興趣，這個 epic 把紀錄變成可以篩選的標籤。
   - [ ] **R-231.2** [FEATURE · P3] 子項目 **來源：** 討論
 - [ ] ⚠️ **R-300** (epic) 大項目
 
 ## ✅ Done
 
-- [x] **R-094.2** [FEATURE · P2 · UIUX · ✅ 2026-10-23 · squash \`3a8d0ebe\` 直接 push main · 接續 R-094.1] 推播成效：收到後 7 天儲值率 —— 每則推播顯示儲值率
-    ↳ mockup [[Proposals/mockups/liff-push-click-tracking-mockup.html|推播成效 mockup（方案 D）]] · 建議對照組預設 10%
+- [x] **R-094.2** [FEATURE · P2 · UIUX · ✅ 2026-10-23 · squash \`9e8d7c6b\` 直接 push main · 接續 R-094.1] 分享成效：收到後 7 天回訪率 —— 每則訊息顯示回訪率
+    ↳ mockup [[Proposals/mockups/share-link-tracking-mockup.html|分享成效 mockup（方案 D）]] · 建議對照組預設 10%
 - [x] **R-012** vault 自動備份範例同步實機修正 · ✅ 2026-10-25
 - [x] **R-001 (epic)** 劇情 pipeline · ✅ shipped · merged 2026-09-01
-- [x] ~~**R-093** 客戶流失預測~~ —— **superseded by [[R-206]]**
-- [x] **R-193.3a-2.1** [FIX · P3 · ✅ 34405dee] 子項 · MR !288
+- [x] ~~**R-093** 流失預測~~ —— **superseded by [[R-206]]**
+- [x] **R-193.3a-2.1** [FIX · P3 · ✅ 7c8d9e0f] 子項 · MR !288
 - [x] ✅ **R-193 號碼衝突已結案** —— not an item
 `;
 const items = P.parseRoadmap(MD);
@@ -52,41 +52,41 @@ test("parseRoadmap: one item per R row, children and odd ids included, notes exc
 
 test("parseRoadmap: R-248 — headline, done date, undeployed env, picked option, commit, no explain", () => {
   const r = by("R-248");
-  assert.equal(r.headline, "總覽分頁下方「問題主題／問題細節」列表調整");
+  assert.equal(r.headline, "首頁「熱門分類／分類細節」清單調整");
   assert.equal(r.checked, true);
   assert.equal(r.done, "2026-10-19");
   assert.equal(r.undeployed, "test");
   assert.equal(r.picked, "B");
-  assert.equal(r.commit, "7fe542a1");
+  assert.equal(r.commit, "a1b2c3d4");
   assert.equal(r.explain, null);
-  assert.deepEqual(r.refs, ["Proposals/mockups/insights-overview-list-polish-mockup.html"]);
-  assert.deepEqual(r.doneWhen, ["列表沒有解決率欄"]);
+  assert.deepEqual(r.refs, ["Proposals/mockups/home-list-polish-mockup.html"]);
+  assert.deepEqual(r.doneWhen, ["清單沒有比例欄"]);
   assert.match(r.tags, /^FEATURE · P2 · UIUX · mockup 定案 B/);
 });
 
 test("parseRoadmap: R-094.3 — blocked reason, mockup 同上", () => {
   const r = by("R-094.3");
-  assert.equal(r.blocked, "prod LIFF channel");
+  assert.equal(r.blocked, "等待正式環境的金鑰");
   assert.equal(r.sameAsAbove, true);
   assert.equal(r.checked, false);
   assert.equal(r.done, null);
-  assert.equal(r.headline, "推播連結追蹤＋點擊貼標");
+  assert.equal(r.headline, "分享連結追蹤＋點擊後自動分類");
 });
 
 test("parseRoadmap: R-231 — explain kept, needs-brainstorm, epic, headline stops at **來源", () => {
   const r = by("R-231");
-  assert.equal(r.explain, "精準推播要先知道誰對什麼有興趣，這個 epic 把聊天紀錄變成可以篩選的標籤。");
+  assert.equal(r.explain, "要先知道誰對什麼有興趣，這個 epic 把紀錄變成可以篩選的標籤。");
   assert.equal(r.needsBrainstorm, true);
   assert.equal(r.epic, true);
-  assert.equal(r.headline, "客戶標籤：從工單與對話自動長出可篩選的 tag");
-  assert.deepEqual(r.doneWhen, ["行銷能用 tag 篩出名單", "每個 tag 點得到來源對話"]);
+  assert.equal(r.headline, "使用者標籤：從紀錄自動長出可篩選的 tag");
+  assert.deepEqual(r.doneWhen, ["能用 tag 篩出名單", "每個 tag 點得到來源紀錄"]);
   assert.equal(by("R-231.2").headline, "子項目");
 });
 
 test("parseRoadmap: date range, trailing annotations, wikilink mockup ref, MR numbers, epic markers", () => {
   assert.equal(by("R-256").done, "2026-10-22");
-  assert.equal(by("R-256").commit, "60b4da26");
-  assert.equal(by("R-256").headline, "對話面板改良（`LeafTimelinePanel`，四個分頁共用）");
+  assert.equal(by("R-256").commit, "0f1e2d3c");
+  assert.equal(by("R-256").headline, "訊息面板改良（`MessagePanel`，四個分頁共用）");
   assert.equal(by("R-012").headline, "vault 自動備份範例同步實機修正");
   assert.equal(by("R-012").done, "2026-10-25");
   assert.equal(by("R-012").tags, "");
@@ -96,11 +96,11 @@ test("parseRoadmap: date range, trailing annotations, wikilink mockup ref, MR nu
   assert.equal(by("R-193.3a-2.1").mr, "!288");
   assert.equal(by("R-193.3a-2.1").commit, null);
   assert.equal(by("R-193.3a-2.1").done, null);
-  assert.deepEqual(by("R-094.2").refs, ["Proposals/mockups/liff-push-click-tracking-mockup.html"]);
+  assert.deepEqual(by("R-094.2").refs, ["Proposals/mockups/share-link-tracking-mockup.html"]);
   assert.equal(by("R-001").done, "2026-09-01");
   assert.equal(by("R-001").epic, true);
   assert.equal(by("R-300").epic, true);
-  assert.equal(by("R-093").headline, "客戶流失預測");
+  assert.equal(by("R-093").headline, "流失預測");
   assert.equal(by("R-248").epic, false);
 });
 
@@ -114,15 +114,15 @@ test("parseRoadmap: an unknown tag format degrades to no status, never throws",
 
 test("mockupsFor: own <id>- files, then refs, de-duplicated; R-248 never takes R-2480's", () => {
   const files = ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/R-2480-x-mockup.html",
-    "Proposals/mockups/insights-overview-list-polish-mockup.html", "Proposals/mockups/R-248-notes.md"];
+    "Proposals/mockups/home-list-polish-mockup.html", "Proposals/mockups/R-248-notes.md"];
   const r = { ...by("R-248"), refs: [...by("R-248").refs, "Proposals/mockups/R-248-a-mockup.html"] };
   assert.deepEqual(P.mockupsFor(r, items, files),
-    ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/insights-overview-list-polish-mockup.html"]);
+    ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/home-list-polish-mockup.html"]);
 });
 
 test("mockupsFor: 同上 takes the nearest same-base id that has a mockup, not the nearest line (AC-2)", () => {
   assert.deepEqual(P.mockupsFor(by("R-094.3"), items, []),
-    ["Proposals/mockups/liff-push-click-tracking-mockup.html"]);
+    ["Proposals/mockups/share-link-tracking-mockup.html"]);
   const it = (id, refs, same = false) => ({ id, refs, sameAsAbove: same });
   const list = [it("R-5.4", [], true), it("R-5.1", ["a.html"]), it("R-5.3", [], true), it("R-5.2", ["b.html"]),
     it("R-50", ["c.html"]), it("R-5.9", ["d.html"])];
R013_FIX2_PATCH
````

- [ ] **Step 2: Run the scoped tests — they still pass** (the row formats did not change)

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 31`, `ℹ pass 31`, `ℹ fail 0`.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 3: Commit**

```bash
git add obsidian-roadmap-view/test/parse.test.js
git commit -m "test(roadmap-view): R-013 review 1 — invented fixture text"
```

### Task 3: Live refreshes keep the reader in place; timers and thumbnails survive re-renders

Seam: `RoadmapViewPlugin` (its registered `roadmap-view` view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1: every re-render jumped the list to an old scroll position (blocking). Also fixed: open folds and the big 現況's height survive a refresh; a refresh waits while the search box has focus (it would close the phone keyboard); the search timer no longer wipes a newer screen's thumbnails; two quick taps on 待做 do not cancel out; the big 現況 is lazy too and the observer watches the pane; the iframe is sandboxed before insertion; closing the view stops a render in flight; a new project's ROADMAP.md refreshes the picker.

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/fake-obsidian.js`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Task 4 of the main plan.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/test/fake-obsidian.js b/obsidian-roadmap-view/test/fake-obsidian.js
index 8b70ffd..582ff3e 100644
--- a/obsidian-roadmap-view/test/fake-obsidian.js
+++ b/obsidian-roadmap-view/test/fake-obsidian.js
@@ -9,6 +9,7 @@ class El {
     if (o.value !== undefined) this.value = o.value;
     for (const k of ["type", "placeholder"]) if (o[k] !== undefined) this.attrs[k] = o[k];
     if (o.attr) Object.assign(this.attrs, o.attr);
+    this.initialAttrs = { ...(o.attr || {}) };   // what was set before the element was inserted
   }
   createEl(tag, o) { const e = new El(tag, o); e.parentElement = this; this.children.push(e); return e; }
   createDiv(o) { return this.createEl("div", o); }
@@ -39,6 +40,7 @@ class El {
     return out;
   }
   querySelectorAll(tag) { return this.findAll((e) => e.tag === tag); }
+  matches(sel) { return sel.startsWith(".") && this.classes.has(sel.slice(1)); }
 }
 
 class Plugin {
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index ee2d319..90a8478 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -89,7 +89,7 @@ const byText = (el, t) => el.findAll((e) => e.text === t)[0];
 
 let observed = [];
 global.IntersectionObserver = class {
-  constructor(cb) { this.cb = cb; }
+  constructor(cb, opts) { this.cb = cb; this.opts = opts; }
   observe(el) { observed.push({ el, io: this }); }
   unobserve() {}
   disconnect() {}
@@ -300,3 +300,140 @@ test("after a re-render, the old render's thumbnails neither hold nor add slots"
   await flush();
   assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
 });
+
+// --- R-013 review attempt 1 -------------------------------------------------------
+
+test("a re-render keeps the reader's place; the detail page opens at the top; back returns", async () => {
+  const { view } = await setup();
+  const root = view.contentEl;
+  root.scrollTop = 600;
+  await view.render();                       // a live refresh
+  assert.equal(root.scrollTop, 600);
+  root.findAll((e) => e.hasClass("rv-group"))[2].fire("click");   // expand 待做
+  await flush();
+  assert.equal(root.scrollTop, 600);
+  root.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
+  await flush();
+  assert.equal(root.scrollTop, 0);
+  byText(root, "← 返回").fire("click");
+  await flush();
+  assert.equal(root.scrollTop, 600);
+  byText(root, "全部").fire("click");
+  await flush();
+  assert.equal(root.scrollTop, 0);
+});
+
+test("two quick taps on 待做, before it redraws, still leave it open", async () => {
+  const { view } = await setup();
+  const h = () => view.contentEl.findAll((e) => e.hasClass("rv-group"))[2];
+  h().fire("click");
+  h().fire("click");
+  await flush();
+  assert.equal(view.todoExpanded, true);
+  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3", "R-1", "R-5"]);
+});
+
+test("a refresh on the detail page keeps open folds and the 現況's height", async () => {
+  observed = [];
+  const { view } = await setup();
+  const card = view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3"));
+  card.fire("click");
+  await flush();
+  const fold = () => view.contentEl.findAll((e) => e.tag === "details")[1];
+  fold().open = true;
+  fold().fire("toggle");
+  const big = () => view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
+  observed.filter((o) => o.el === big()).forEach(seen);
+  await flush();
+  const frame = big().findAll((e) => e.tag === "iframe")[0];
+  frame.contentDocument = { body: { scrollHeight: 400 } };
+  frame.fire("load");
+  await flush();
+  const height = big().style.height;
+  assert.ok(height && height !== "0px", height);
+  observed = [];
+  await view.render();
+  assert.equal(fold().open, true);
+  assert.equal(big().style.height, height);
+  byText(view.contentEl, "← 返回").fire("click");
+  await flush();
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
+  await flush();
+  assert.equal(fold().open, false);   // another visit starts closed
+});
+
+test("the detail page's big 現況 waits until it is in view", async () => {
+  observed = [];
+  const { view } = await setup();
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
+  await flush();
+  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
+  assert.equal(big.findAll((e) => e.tag === "iframe").length, 0);
+  assert.ok(observed.some((o) => o.el === big));
+  assert.equal(observed[0].io.opts.root, view.contentEl);
+});
+
+test("the iframe is sandboxed before it is inserted", async () => {
+  observed = [];
+  const { view } = await setup();
+  observed.forEach(seen);
+  await flush();
+  const f = view.contentEl.findAll((e) => e.tag === "iframe")[0];
+  assert.equal(f.initialAttrs.sandbox, "allow-same-origin");
+  assert.ok(f.initialAttrs.srcdoc.includes("panel now"));
+});
+
+test("a refresh waits while the search box has focus", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });
+  const { view, plugin, app } = await setup();
+  const leaves = [{ view }];
+  app.workspace.getLeavesOfType = () => leaves;
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  let n = 0;
+  view.render = async () => { n++; };
+  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
+  view.contentEl.ownerDocument = { activeElement: input };
+  plugin.refresh();
+  assert.equal(n, 0);
+  view.contentEl.ownerDocument = { activeElement: null };
+  t.mock.timers.tick(500);
+  assert.equal(n, 1);
+});
+
+test("a search typed just before a re-render does not wipe the new screen's thumbnails", async () => {
+  observed = [];
+  const { view } = await setup();
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
+  input.value = "R-";
+  input.fire("input");
+  observed = [];
+  await view.render();
+  await new Promise((r) => setTimeout(r, 250));   // the old search timer would have fired
+  observed.forEach(seen);
+  await flush();
+  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
+});
+
+test("closing the view stops a render in flight from drawing", async () => {
+  const { view } = await setup();
+  view.contentEl.empty();
+  const p = view.render();
+  await view.onClose();
+  await p;
+  assert.equal(view.contentEl.children.length, 0);
+});
+
+test("a new project's ROADMAP.md refreshes the picker, even with no project shown", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });
+  const { plugin, app } = await setup({ "10 Projects/x/README.md": "x" });
+  let n = 0;
+  plugin.refresh = () => { n++; };
+  assert.equal(plugin.current, null);
+  app.handlers.create.forEach((f) => f({ path: "10 Projects/new/ROADMAP.md" }));
+  app.handlers.create.forEach((f) => f({ path: "10 Projects/new/notes/ROADMAP.md" }));
+  t.mock.timers.tick(500);
+  assert.equal(n, 1);
+});
R013_FIX2_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 40`, `ℹ pass 31`, `ℹ fail 9` — these fail:
  - `✖ a re-render keeps the reader's place; the detail page opens at the top; back returns`
  - `✖ two quick taps on 待做, before it redraws, still leave it open`
  - `✖ a refresh on the detail page keeps open folds and the 現況's height`
  - `✖ the detail page's big 現況 waits until it is in view`
  - `✖ the iframe is sandboxed before it is inserted`
  - `✖ a refresh waits while the search box has focus`
  - `✖ a search typed just before a re-render does not wipe the new screen's thumbnails`
  - `✖ closing the view stops a render in flight from drawing`
  - `✖ a new project's ROADMAP.md refreshes the picker, even with no project shown`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index d6f475b..4de5fbf 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -220,10 +220,8 @@ function isWatched(path, projectDir) {
 // An iframe showing `srcdoc` at width W, scaled by `scale`. No scripts run in it; it is
 // same-origin only so its height can be read. It ignores touches, so its box scrolls.
 function frameIn(box, srcdoc, scale, onHeight) {
-  const frame = box.createEl("iframe");
-  frame.setAttr("srcdoc", srcdoc);
-  frame.setAttr("sandbox", "allow-same-origin");
-  frame.setAttr("scrolling", "no");
+  // Set before the frame is inserted, so even its first document is sandboxed.
+  const frame = box.createEl("iframe", { attr: { sandbox: "allow-same-origin", scrolling: "no", srcdoc } });
   Object.assign(frame.style, { width: `${W}px`, height: "800px", border: "0", transformOrigin: "0 0",
     transform: `scale(${scale})`, pointerEvents: "none", background: "#fff" });
   frame.addEventListener("load", () => {
@@ -235,15 +233,24 @@ function frameIn(box, srcdoc, scale, onHeight) {
   return frame;
 }
 
-// Resolves true once drawn, false when it never loaded within 3 s (the box is marked).
+const scaleOf = (box) => (box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 300) / W;
+
+// Size `box` for a document `h` px tall at width W.
+function fitBox(box, h, maxHeight) {
+  const px = h * scaleOf(box);
+  box.style.height = `${maxHeight ? Math.min(px, maxHeight) : px}px`;
+}
+
+// Resolves with the document's height once drawn, or 0 when it has not loaded within
+// 3 s (the box is marked until it does).
 function thumb(box, srcdoc, maxHeight) {
   return new Promise((resolve) => {
-    const scale = (box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 300) / W;
-    const timer = setTimeout(() => { box.addClass("rv-slow"); resolve(false); }, 3000);
-    frameIn(box, srcdoc, scale, (h) => {
-      box.style.height = `${maxHeight ? Math.min(h * scale, maxHeight) : h * scale}px`;
+    const timer = setTimeout(() => { box.addClass("rv-slow"); resolve(0); }, 3000);
+    frameIn(box, srcdoc, scaleOf(box), (h) => {
+      fitBox(box, h, maxHeight);
+      box.removeClass("rv-slow");
       clearTimeout(timer);
-      resolve(true);
+      resolve(h);
     });
   });
 }
@@ -283,7 +290,9 @@ class RoadmapView extends ItemView {
     this.detail = null;         // id of the item on the detail page
     this.query = "";
     this.todoExpanded = false;
-    this.listScroll = 0;
+    this.folds = new Set();     // titles of the detail page's open folds
+    this.listScroll = 0;        // the list's scroll position when a card was opened
+    this.shown = null;          // the screen last drawn: a tab, or `detail:<id>`
     this.docs = new Map();      // mockup path → { mtime, doc }
     this.renders = 0;
     this.gen = 0;
@@ -293,7 +302,11 @@ class RoadmapView extends ItemView {
   getDisplayText() { return "Roadmap 檢視"; }
   getIcon() { return "layout-list"; }
   async onOpen() { await this.render(); }
-  async onClose() { this.resetThumbs(); }
+  async onClose() {
+    this.renders++;   // a render still loading must not draw into the closed view
+    clearTimeout(this.typing);
+    this.resetThumbs();
+  }
 
   async render() {
     const n = ++this.renders;
@@ -301,10 +314,16 @@ class RoadmapView extends ItemView {
     try {
       const data = await this.load();
       if (n !== this.renders) return;   // a newer render started meanwhile
+      clearTimeout(this.typing);        // a pending search would redraw the old list
+      // A redraw of the same screen (a live refresh, 待做 opening) keeps the reader's place.
+      const screen = this.detail ? `detail:${this.detail}` : this.tab;
+      const top = this.shown === screen ? root.scrollTop || 0 : this.detail ? 0 : this.listScroll;
       root.empty();
       root.addClass("rv");
       this.resetThumbs();
       this.draw(root, data);
+      root.scrollTop = top;
+      this.shown = screen;
     } catch (e) {
       if (n !== this.renders) return;
       root.empty();
@@ -353,6 +372,7 @@ class RoadmapView extends ItemView {
     sel.addEventListener("change", async () => {
       this.plugin.settings.project = sel.value;
       this.detail = null;
+      this.listScroll = 0;
       await this.plugin.saveSettings();
       await this.render();
     });
@@ -360,13 +380,12 @@ class RoadmapView extends ItemView {
     for (const [k, label] of [["near", "近況"], ["all", "全部"]]) {
       const b = tabs.createEl("button", { text: label });
       if (this.tab === k && !this.detail) b.addClass("is-on");
-      b.addEventListener("click", () => { this.tab = k; this.detail = null; this.render(); });
+      b.addEventListener("click", () => { this.tab = k; this.detail = null; this.listScroll = 0; this.render(); });
     }
     const row = this.detail && d.rows.find((r) => r.item.id === this.detail);
     if (row) return this.drawDetail(root, d, row);
     if (this.tab === "all") this.drawAll(root, d);
     else this.drawNear(root, d);
-    root.scrollTop = this.listScroll;
   }
 
   drawNear(root, d) {
@@ -377,7 +396,8 @@ class RoadmapView extends ItemView {
       const h = root.createDiv({ cls: "rv-group", text: `${label} · ${rows.length}` });
       if (g === "todo") {
         h.addClass("rv-foldable");
-        h.addEventListener("click", () => { this.todoExpanded = !this.todoExpanded; this.render(); });
+        const shown = this.todoExpanded;   // two taps before the redraw must not cancel out
+        h.addEventListener("click", () => { this.todoExpanded = !shown; this.render(); });
         if (!this.todoExpanded) { h.setText(`${label} · ${rows.length}（點開）`); continue; }
       }
       if (!rows.length) root.createDiv({ cls: "rv-none", text: "沒有" });
@@ -423,6 +443,7 @@ class RoadmapView extends ItemView {
     c.addEventListener("click", () => {
       this.listScroll = this.contentEl.scrollTop || 0;
       this.detail = r.item.id;
+      this.folds.clear();
       this.render();
     });
   }
@@ -430,14 +451,14 @@ class RoadmapView extends ItemView {
   drawDetail(root, d, r) {
     const { item, status } = r;
     const back = root.createEl("button", { cls: "rv-back", text: "← 返回" });
-    back.addEventListener("click", () => { this.detail = null; this.render(); });
+    back.addEventListener("click", () => { this.detail = null; this.folds.clear(); this.render(); });
     this.chips(root, item, status);
     root.createDiv({ cls: "rv-title rv-headline", text: item.headline });
     root.createDiv({ cls: item.explain ? "rv-exp rv-full" : "rv-exp rv-faint", text: item.explain || "還沒有白話說明" });
     if (r.mockups.length) {
       root.createDiv({ cls: "rv-lbl", text: "MOCKUP · 現況" });
       const big = root.createDiv({ cls: "rv-big" });
-      this.enqueue(() => this.drawThumb(big, `${d.dir}/${r.mockups[0]}`, item.id, 0));
+      this.lazyThumb(big, `${d.dir}/${r.mockups[0]}`, item.id, 0);
       root.createDiv({ cls: "rv-cap", text: "點圖放大" });
     }
     root.createDiv({ cls: "rv-lbl", text: "相關文件" });
@@ -460,6 +481,8 @@ class RoadmapView extends ItemView {
     const fold = (title, lines) => {
       const det = root.createEl("details", { cls: "rv-fold" });
       det.createEl("summary", { text: title });
+      det.open = this.folds.has(title);   // a live refresh keeps what the reader opened
+      det.addEventListener("toggle", () => { if (det.open) this.folds.add(title); else this.folds.delete(title); });
       for (const l of lines) det.createDiv({ cls: "rv-raw", text: l });
     };
     if (item.doneWhen.length) fold("完成條件", item.doneWhen);
@@ -492,6 +515,8 @@ class RoadmapView extends ItemView {
   }
 
   lazyThumb(box, path, id, maxHeight) {
+    const hit = this.docs.get(path);
+    if (hit && hit.h) fitBox(box, hit.h, maxHeight);   // a redraw does not collapse to 0 px first
     const job = () => this.drawThumb(box, path, id, maxHeight);
     if (typeof IntersectionObserver === "undefined") { this.enqueue(job); return; }
     if (!this.io) {
@@ -503,7 +528,7 @@ class RoadmapView extends ItemView {
           this.jobs.delete(e.target);
           this.enqueue(j);
         }
-      }, { rootMargin: "200px" });
+      }, { root: this.contentEl, rootMargin: "200px" });
     }
     this.jobs.set(box, job);
     this.io.observe(box);
@@ -529,7 +554,9 @@ class RoadmapView extends ItemView {
       e.stopPropagation();   // a thumbnail tap zooms; it does not open the card
       new ZoomModal(this.app, `${id} · 現況`, doc).open();
     });
-    await thumb(box, doc, maxHeight);
+    const h = await thumb(box, doc, maxHeight);
+    const hit = this.docs.get(path);
+    if (h && hit) hit.h = h;
   }
 
   async docFor(path) {
@@ -555,10 +582,17 @@ class RoadmapViewPlugin extends Plugin {
     this.addCommand({ id: "open", name: "打開 Roadmap 檢視", callback: () => this.activate() });
     // After layout-ready, so the vault's start-up `create` burst is not replayed at us.
     this.app.workspace.onLayoutReady(() => {
-      const changed = (f, oldPath) => {
-        if (isWatched(f && f.path, this.current) || isWatched(oldPath, this.current)) this.refreshSoon();
-      };
-      for (const ev of ["modify", "create", "delete", "rename"]) this.registerEvent(this.app.vault.on(ev, changed));
+      // A project's ROADMAP.md appearing, going or moving changes the picker, even when
+      // no project is on screen yet (the phone's first sync).
+      const pre = () => `${this.settings.projectsDir}/`;
+      const isRoadmap = (p) => !!p && p.startsWith(pre()) && /^[^/]+\/ROADMAP\.md$/.test(p.slice(pre().length));
+      for (const ev of ["modify", "create", "delete", "rename"]) {
+        this.registerEvent(this.app.vault.on(ev, (f, oldPath) => {
+          const p = f && f.path;
+          if (isWatched(p, this.current) || isWatched(oldPath, this.current)
+            || (ev !== "modify" && (isRoadmap(p) || isRoadmap(oldPath)))) this.refreshSoon();
+        }));
+      }
     });
   }
   onunload() { clearTimeout(this.timer); }
@@ -569,7 +603,15 @@ class RoadmapViewPlugin extends Plugin {
     this.timer = setTimeout(() => this.refresh(), 500);
   }
   refresh() {
-    for (const leaf of this.app.workspace.getLeavesOfType(VIEW)) if (leaf.view instanceof RoadmapView) leaf.view.render();
+    for (const leaf of this.app.workspace.getLeavesOfType(VIEW)) {
+      const v = leaf.view;
+      if (!(v instanceof RoadmapView)) continue;
+      // Redrawing would remove the focused search box and close the phone's keyboard: wait.
+      const doc = v.contentEl.ownerDocument;
+      const a = doc && doc.activeElement;
+      if (a && a.matches && a.matches(".rv-search")) { this.refreshSoon(); continue; }
+      v.render();
+    }
   }
   async activate() {
     const { workspace } = this.app;
R013_FIX2_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 40`, `ℹ pass 40`, `ℹ fail 0`.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/fake-obsidian.js obsidian-roadmap-view/test/view.test.js
git commit -m "fix(roadmap-view): R-013 review 1 — refreshes keep scroll, folds and heights; timer and thumbnail races"
```

### Task 4: `[~]` rows, no `load()` override, whole ✅ annotations, sorted mockups

Seam: `parseRoadmap` / `RoadmapViewPlugin` (its view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1, blocking: `- [~]` (in progress) rows were dropped — the real vault has 10 — and AC-4b's counter shared the blind spot; the view's `async load()` replaced Obsidian's `Component.load()`, which `View.open()` calls (checked in Obsidian's app.js). Also: a trailing `· ✅ shipped · merged <date>` is stripped whole from the headline; mockups are sorted, since `adapter.list` order differs by platform; the interactive `[n] Pause` after the review cap records `blocked`.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-lib.bats`
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/fake-obsidian.js`
- Modify: `obsidian-roadmap-view/test/local-vault.test.js`
- Modify: `obsidian-roadmap-view/test/parse.test.js`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Tasks 3–4 of the main plan; F3.
- Produces: `item.inProgress` (true for `[~]`), which `statusOf` counts as active.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
index bc5b933..a42b787 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
@@ -330,8 +330,8 @@ section() { awk -v h="## Phase $1 " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f
     section "${pair%%:*}" | grep -qF "sn_status \"\$WORKTREE\" ${pair#*:}" || { echo "Phase ${pair%%:*} does not record ${pair#*:}"; return 1; }
   done
   section 4 | grep -F 'Small-change lane' | grep -qF 'sn_status "$WORKTREE" build'
-  for anchor in 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted'; do
-    grep -F -A2 -- "$anchor" "$SHIP_SKILL_ROOT/commands/ship-next.md" | grep -qF 'sn_status "$WORKTREE" blocked' \
+  for anchor in 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted' '[n] Pause indefinitely'; do
+    grep -F -A6 -- "$anchor" "$SHIP_SKILL_ROOT/commands/ship-next.md" | grep -qF 'sn_status "$WORKTREE" blocked' \
       || { echo "no blocked status at: $anchor"; return 1; }
   done
 }
diff --git a/obsidian-roadmap-view/test/fake-obsidian.js b/obsidian-roadmap-view/test/fake-obsidian.js
index 582ff3e..f7382b9 100644
--- a/obsidian-roadmap-view/test/fake-obsidian.js
+++ b/obsidian-roadmap-view/test/fake-obsidian.js
@@ -54,10 +54,14 @@ class Plugin {
   async loadData() { return this.stored; }
   async saveData(d) { this.stored = JSON.parse(JSON.stringify(d)); }
 }
-// Obsidian's View has an `open` method; a subclass field of that name shadows it.
+// Obsidian's View.open() runs Component.load() and then onOpen(); a subclass field or
+// method with one of these names silently replaces them.
 class ItemView {
   constructor(leaf) { this.leaf = leaf; this.app = leaf.app; this.contentEl = new El("div"); }
   open() { return "View.open"; }
+  load() { this._loaded = true; }
+  unload() { this._loaded = false; }
+  close() {}
 }
 class Modal {
   constructor(app) { this.app = app; this.contentEl = new El("div"); this.titleEl = new El("div"); this.modalEl = new El("div"); }
diff --git a/obsidian-roadmap-view/test/local-vault.test.js b/obsidian-roadmap-view/test/local-vault.test.js
index 54e968f..8fc0169 100644
--- a/obsidian-roadmap-view/test/local-vault.test.js
+++ b/obsidian-roadmap-view/test/local-vault.test.js
@@ -17,7 +17,7 @@ function vault() {
 const V = vault();
 const projects = V ? fs.readdirSync(path.join(V, "10 Projects"))
   .map((p) => path.join(V, "10 Projects", p)).filter((p) => fs.existsSync(path.join(p, "ROADMAP.md"))) : [];
-const ROW = /^\s*- \[[ xX]\] [^*]{0,6}\*\*R-\d[\w.-]*(?: \([^)*]*\))?\*\*/;
+const ROW = /^\s*- \[[^\]]\] [^*]{0,6}\*\*R-\d[\w.-]*(?: \([^)*]*\))?\*\*/;   // any checkbox state
 
 test("the real ROADMAPs: every **R-…** row is parsed", { skip: !V && "no vault on this machine" }, () => {
   for (const p of projects) {
diff --git a/obsidian-roadmap-view/test/parse.test.js b/obsidian-roadmap-view/test/parse.test.js
index 2b85007..3cbccb0 100644
--- a/obsidian-roadmap-view/test/parse.test.js
+++ b/obsidian-roadmap-view/test/parse.test.js
@@ -192,3 +192,20 @@ test("currentStateDoc: drops scripts, and returns null for no html", () => {
   assert.equal(P.currentStateDoc(null), null);
   assert.equal(P.currentStateDoc("<html><head></head></html>"), null);
 });
+
+test("parseRoadmap: [~] (in progress) and [X] rows are items too; [~] is active", () => {
+  const [a, b] = P.parseRoadmap("- [~] **R-170** [FEATURE · shipped-in-branch] 做到一半的事\n- [X] **R-171** 大寫 X 的完成列");
+  assert.equal(a.id, "R-170");
+  assert.equal(a.checked, false);
+  assert.equal(a.inProgress, true);
+  assert.equal(P.statusOf(a, null, new Date("2026-10-25T12:00:00Z"), 14).group, "active");
+  assert.equal(b.id, "R-171");
+  assert.equal(b.checked, true);
+  assert.equal(b.inProgress, false);
+});
+
+test("parseRoadmap: a trailing ✅ annotation is stripped whole, words before its date included", () => {
+  assert.equal(by("R-001").headline, "劇情 pipeline");
+  const [r] = P.parseRoadmap("- [x] **R-8** 一件事 · ✅ shipped · merged 2026-09-01 · status=done");
+  assert.equal(r.headline, "一件事");
+});
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index 90a8478..5c536a8 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -437,3 +437,27 @@ test("a new project's ROADMAP.md refreshes the picker, even with no project show
   t.mock.timers.tick(500);
   assert.equal(n, 1);
 });
+
+test("the view overrides none of Obsidian's View lifecycle methods", async () => {
+  const { view } = await setup();
+  const own = Object.getOwnPropertyNames(Object.getPrototypeOf(view));
+  for (const k of ["open", "load", "unload", "close"]) {
+    assert.ok(!own.includes(k) && !Object.prototype.hasOwnProperty.call(view, k), k);
+  }
+});
+
+test("an item's mockups come in name order, whatever order the vault lists them in", async () => {
+  const files = { ...FILES, [`${D}/Proposals/mockups/R-2-b-mockup.html`]: MOCK("乙") };
+  const app = fakeApp(vault(files));
+  const list = app.vault.adapter.list;
+  app.vault.adapter.list = async (p) => { const r = await list(p); return { ...r, files: [...r.files].reverse() }; };
+  const plugin = new P(app, { id: "roadmap-view" });
+  plugin.now = () => NOW;
+  await plugin.onload();
+  const view = plugin.views["roadmap-view"]({ app });
+  await view.onOpen();
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-2")).fire("click");
+  await flush();
+  const links = view.contentEl.findAll((e) => e.hasClass("rv-link")).map((e) => e.text).filter((t) => t.startsWith("mockup"));
+  assert.deepEqual(links, ["mockup · Proposals/mockups/R-2-a-mockup.html", "mockup · Proposals/mockups/R-2-b-mockup.html"]);
+});
R013_FIX2_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/; (cd claude-skills/ship-workflow && bats tests/test_ship-next-lib.bats)`

Expected: `ℹ tests 44`, `ℹ pass 39`, `ℹ fail 5` — these fail:
  - `✖ the real ROADMAPs: every **R-…** row is parsed`
  - `✖ parseRoadmap: [~] (in progress) and [X] rows are items too; [~] is active`
  - `✖ parseRoadmap: a trailing ✅ annotation is stripped whole, words before its date included`
  - `✖ the view overrides none of Obsidian's View lifecycle methods`
  - `✖ an item's mockups come in name order, whatever order the vault lists them in`

  Then the bats run: `1..29`, 28 ok, these 1 fail:
  - `not ok 26 ship-next records every phase where it starts, and blocked on each stop path`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_FIX2_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 82866b3..d97e235 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -534,6 +534,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
        [n] Pause indefinitely (user fixes manually, then re-invoke /ship-next ${ID})
        [abort] Discard everything — /ship-next --discard ${ID}
      ```
+     On `[n]`, first run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "review: paused after 3 attempts"`.
 4. **Major findings handling** (only after `BLOCKING_COUNT == 0`):
    - **In auto mode (`AUTO=1`):** every major finding becomes an `IDEA-NNN` follow-up (NEVER skip; quality-debt must be visible).
      ```bash
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index 4de5fbf..6892a39 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -7,8 +7,8 @@ const { Plugin, ItemView, Modal, Notice } = require("obsidian");
 // ---------------------------------------------------------------- parsing (pure)
 
 // A ROADMAP item row. Real rows seen 2026-10-25: `**R-001 (epic)**`, `**R-193.3a-2.1**`,
-// `~~**R-093** …~~`, `⚠️ **R-300** (epic)`.
-const ROW = /^(\s*)- \[( |x)\] (⚠️ )?(~~)?\*\*(R-\d[\w.-]*)((?: \([^)*]*\))?)\*\*( \(epic\))?/;
+// `~~**R-093** …~~`, `⚠️ **R-300** (epic)`, and `- [~]` for work in progress.
+const ROW = /^(\s*)- \[( |x|X|~)\] (⚠️ )?(~~)?\*\*(R-\d[\w.-]*)((?: \([^)*]*\))?)\*\*( \(epic\))?/;
 
 // Index of the `]` closing the `[` at s[0], counting nested brackets; -1 if unbalanced.
 function closeBracket(s) {
@@ -29,8 +29,9 @@ function itemFrom(row, m, ann, section, line) {
     if (end > 0) { tags = rest.slice(1, end); body = rest.slice(end + 1).trim(); }
   }
   let headline = body.split(/\s*——|\*\*來源/)[0].replace(/~~/g, "")
-    // trailing ` · ✅ <date>` / ` · status=…` / ` · mr=…` written by ship-workflow
-    .replace(/(\s*·\s*(?:✅[^·]*|[a-z][\w-]*=\S*))+\s*$/, "").trim();
+    // trailing annotations written by ship-workflow: ` · ✅ …` to the end, then ` · status=…` / ` · mr=…`
+    .replace(/\s*·\s*✅.*$/, "")
+    .replace(/(\s*·\s*[a-z][\w-]*=\S*)+\s*$/, "").trim();
   if (!headline) headline = body.replace(/^[\s—]+/, "").slice(0, 120);
   const explainLine = ann.find((a) => a.startsWith("↳ explain:"));
   const explain = explainLine ? explainLine.replace(/^↳ explain:\s*/, "").trim() : null;
@@ -44,7 +45,8 @@ function itemFrom(row, m, ann, section, line) {
   const undeployed = row.match(/尚未部署\s*([A-Za-z][\w／/-]*)?/);
   return {
     id: m[5],
-    checked: m[2] === "x",
+    checked: m[2] === "x" || m[2] === "X",
+    inProgress: m[2] === "~",
     section,
     line,
     tags,
@@ -148,11 +150,12 @@ function statusOf(item, phaseFile, now = new Date(), recentDays = 14) {
     chips.push({ kind: "wait", text: `尚未部署${item.undeployed ? ` ${item.undeployed}` : ""}` });
   }
   if (item.inReview && !phase) chips.push({ kind: "phase", text: PHASE_TEXT["in-review"] });
+  if (item.inProgress && !phase && !isDone) chips.push({ kind: "phase", text: "進行中" });
   if (item.needsBrainstorm) chips.push({ kind: "wait", text: "待討論" });
   if (item.picked) chips.push({ kind: "pick", text: `方案 ${item.picked}` });
   if (item.epic) chips.push({ kind: "epic", text: "epic" });
   let group;
-  if ((phase && phase !== "done") || item.blocked || (item.inReview && !isDone)) group = "active";
+  if ((phase && phase !== "done") || item.blocked || ((item.inReview || item.inProgress) && !isDone)) group = "active";
   else if (isDone) group = doneAt && now - doneAt <= recentDays * 864e5 ? "recent" : "done";
   else group = "todo";
   return { group, chips, phase };
@@ -312,7 +315,7 @@ class RoadmapView extends ItemView {
     const n = ++this.renders;
     const root = this.contentEl;
     try {
-      const data = await this.load();
+      const data = await this.readProject();
       if (n !== this.renders) return;   // a newer render started meanwhile
       clearTimeout(this.typing);        // a pending search would redraw the old list
       // A redraw of the same screen (a live refresh, 待做 opening) keeps the reader's place.
@@ -333,7 +336,8 @@ class RoadmapView extends ItemView {
     }
   }
 
-  async load() {
+  // Not `load`: View.open() calls Component.load(), and overriding it breaks the view.
+  async readProject() {
     const s = this.plugin.settings;
     const adapter = this.app.vault.adapter;
     const all = this.app.vault.getFiles().map((f) => f.path);
@@ -346,7 +350,8 @@ class RoadmapView extends ItemView {
     this.plugin.current = dir;
     const items = parseRoadmap(await adapter.read(`${dir}/ROADMAP.md`));
     const list = async (sub) => { try { return (await adapter.list(`${dir}/${sub}`)).files; } catch (e) { return []; } };
-    const mockups = (await list("Proposals/mockups")).filter((p) => /\.html$/i.test(p)).map((p) => p.slice(dir.length + 1));
+    const mockups = (await list("Proposals/mockups")).filter((p) => /\.html$/i.test(p))
+      .map((p) => p.slice(dir.length + 1)).sort();   // list order differs by platform
     const phases = {};
     // ponytail: reads every status file on each render; index them if hundreds get slow
     await Promise.all((await list("ship-status")).filter((p) => /\/R-[^/]+\.json$/.test(p)).map(async (p) => {
R013_FIX2_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/; (cd claude-skills/ship-workflow && bats tests/test_ship-next-lib.bats)`

Expected: `ℹ tests 44`, `ℹ pass 44`, `ℹ fail 0`. Then the bats run: `1..29`, all 29 ok, 0 failures.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md claude-skills/ship-workflow/tests/test_ship-next-lib.bats obsidian-roadmap-view/main.js obsidian-roadmap-view/test/fake-obsidian.js obsidian-roadmap-view/test/local-vault.test.js obsidian-roadmap-view/test/parse.test.js obsidian-roadmap-view/test/view.test.js
git commit -m "fix(roadmap-view): R-013 review 1 — [~] rows, no load() override, sorted mockups"
```

### Task 5: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole bats suite** (it includes the plugin's `node --test`)

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..604`, 603 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Run the plugin tests on their own**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 44`, `ℹ fail 0`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 and Step 2 counts.
