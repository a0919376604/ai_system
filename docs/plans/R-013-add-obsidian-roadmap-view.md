# R-013 Roadmap 檢視 (Obsidian plugin) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A live, read-only, phone-first Obsidian view of one project's ROADMAP — Chinese headline, status, ship-next phase, a zoomable 現況 thumbnail and links per item — plus ship-next recording each ship's phase in the vault, and `sync.sh` installing the plugin.

**Architecture:** The plugin is one plain-CommonJS `main.js` (no build, no npm) in a new top-level `obsidian-roadmap-view/`; its pure functions are static members, tested with `node --test` against a fake `obsidian` module. ship-next gains `sn_status` in `lib/ship-next.sh`, called at each phase from `commands/ship-next.md`, `--discard` and `/ship-land`. `sync.sh restore` copies the three plugin files into the vault. Every code step is a `git apply` patch generated from a working prototype and replayed red/green, task by task, in a linked worktree of this branch.

**Tech Stack:** bash + zsh (sourced libs), bats 1.13, jq, Node ≥ 22 (`node:test`, its mock timers), Obsidian plugin API (desktop and mobile).

**Spec:** `docs/specs/R-013-add-obsidian-roadmap-view.md`

## Global Constraints

- **Scope.** Edit only this repository. `claude-skills/` and `obsidian-roadmap-view/` are this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/`, the operator's home directory or the Obsidian vault. The tests set their own `HOME` to a scratch dir. One test, `obsidian-roadmap-view/test/local-vault.test.js`, reads the real vault read-only when there is one: run it, do not change it.
- **Do not run** `./sync.sh restore` or `./sync.sh backup` against the real home, and do not enable or install anything in Obsidian.
- **Not part of this plan:** `.ship/` (scratch state; `.ship/proto` is a nested git repository). Stage only the paths each commit step names; never `git add -A`.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise.
- **Patches are the code.** Each code step is a `git apply` heredoc, generated from and replayed against this exact base (`9a3269f` plus the plan commit). They apply cleanly in order. If one does not apply, STOP — do not hand-edit around it.
- **No dependencies.** No `package.json`, no `npm install`. `main.js` may `require` only `"obsidian"`: the phone has no Node APIs.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped command each task names. The full suite runs once, in Task 7.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** sourced libs use `command grep`, no `local` inside a loop body, and no variable named `status` or `path`.
- **Commits.** One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

Failure modes a person is most likely to hit, each pinned by a test in the owning task:

1. A status file that Obsidian Sync has only half-written reaches the phone — the view skips it and still renders. → Task 4 (the fixture's `ship-status/R-9.json`).
2. ROADMAP.md cannot be read (mid-sync, permissions) — the pane shows the error, never a black or blank pane. → Task 4.
3. `sn_status` runs with no vault, an unwritable vault, a missing project folder or a bad ID — one WARN, exit 0, nothing written anywhere. → Task 2.
4. The vault changes while thumbnails are still loading — the re-render's thumbnails still get both slots, and late finishers from the old render add none. → Task 4.
5. `restore` meets an older copy of the plugin with its `data.json` settings — it updates the three files in place and keeps the settings. → Task 5.

---
### Task 1: `roadmap-insert.sh --summary` writes a plain `↳ explain:` line

Seam: `roadmap-insert --summary`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.6, G6, AC-7. `/ship-next --adhoc` inserts a row with no line a person can read; `--summary` adds one zh-TW `↳ explain:` sentence as the row's first annotation. The legacy `--explain <slug>` (a `[[link]]`) is unchanged.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/roadmap-insert.sh`
- Modify: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`

**Interfaces:**
- Consumes: `lib/roadmap-insert.sh` as it is.
- Produces: `roadmap-insert.sh <file> <id> <desc> … --summary "<text>"` — Task 2's Phase 1 step 3 passes it.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_roadmap-insert.bats b/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
index b84f6eb..9e717fc 100644
--- a/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
+++ b/claude-skills/ship-workflow/tests/test_roadmap-insert.bats
@@ -312,3 +312,31 @@ EOF
     esac
   done
 }
+
+# --- R-013: --summary writes a human-readable line ----------------------------
+
+@test "roadmap-insert: --summary adds a plain ↳ explain line, before done-when" {
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9 "desc" --adhoc --summary "客服可以一次關掉多張工單" --done-when "50 張都成功"
+  row=$(grep -n '\*\*R-9\*\*' "$ROADMAP" | cut -d: -f1)
+  [ "$(sed -n "$((row + 1))p" "$ROADMAP")" = "    ↳ explain: 客服可以一次關掉多張工單" ] || return 1
+  [ "$(sed -n "$((row + 2))p" "$ROADMAP")" = "    ↳ done when: 50 張都成功" ]
+}
+
+@test "roadmap-insert: --summary is one line — newlines fold to spaces" {
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9 "desc" --summary "$(printf 'first\nsecond')"
+  grep -qxF '    ↳ explain: first second' "$ROADMAP"
+}
+
+@test "roadmap-insert: --summary wins over --explain, which stays a [[link]] on its own" {
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9 "desc" --explain some-slug --summary "給人看的一句話"
+  grep -qxF '    ↳ explain: 給人看的一句話' "$ROADMAP" || return 1
+  if grep -qF '[[some-slug]]' "$ROADMAP"; then return 1; fi
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-10 "desc" --explain other-slug
+  grep -qxF '    ↳ explain: [[other-slug]]' "$ROADMAP"
+}
+
+@test "roadmap-insert: --summary on a child row is indented one level deeper" {
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9 "parent"
+  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-9.1 "child" --child R-9 --summary "子項目的一句話"
+  grep -qxF '      ↳ explain: 子項目的一句話' "$ROADMAP"
+}
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_roadmap-insert.bats; cd - >/dev/null`

Expected: `1..37`, 33 ok, these 4 fail:
  - `not ok 34 roadmap-insert: --summary adds a plain ↳ explain line, before done-when`
  - `not ok 35 roadmap-insert: --summary is one line — newlines fold to spaces`
  - `not ok 36 roadmap-insert: --summary wins over --explain, which stays a [[link]] on its own`
  - `not ok 37 roadmap-insert: --summary on a child row is indented one level deeper`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/lib/roadmap-insert.sh b/claude-skills/ship-workflow/lib/roadmap-insert.sh
index cc4fdc3..584e245 100755
--- a/claude-skills/ship-workflow/lib/roadmap-insert.sh
+++ b/claude-skills/ship-workflow/lib/roadmap-insert.sh
@@ -8,6 +8,7 @@
 #       --epic       → add (epic) suffix to RID (marks parent of decomposition)
 #       --done-when  → add a "done when" annotation on a second line
 #       --explain    → add ↳ explain: [[<slug>]] annotation (positioned BEFORE done-when)
+#       --summary    → add a plain ↳ explain: <text> line for a person (R-013); wins over --explain
 #       --est        → add est=<duration> to the line (e.g. "3d", "1w")
 #
 #   roadmap-insert.sh <ROADMAP.md> <R-NNN.M> <description> --child <parent> [--done-when ...] [--est ...]
@@ -57,6 +58,7 @@ WARN_REASON=""
 REVIEW_URL=""
 DONE_WHEN=""
 EXPLAIN=""
+SUMMARY=""
 EST=""
 
 # Pull arg at position 3 if it is not a flag → it is DESC
@@ -82,6 +84,7 @@ while [ $# -gt 0 ]; do
     --mark-epic)    MODE="mark-epic"; shift ;;
     --done-when)    DONE_WHEN="${2:-}"; shift "$(_sh2 $#)" ;;
     --explain)      EXPLAIN="${2:-}"; shift "$(_sh2 $#)" ;;
+    --summary)      SUMMARY=$(printf '%s' "${2:-}" | tr '\n' ' '); shift "$(_sh2 $#)" ;;
     --inject-explain) MODE="inject-explain"; EXPLAIN="${2:-}"; shift "$(_sh2 $#)" ;;
     --est)          EST="${2:-}"; shift "$(_sh2 $#)" ;;
     *)              shift ;;
@@ -109,6 +112,7 @@ case "$MODE" in
     EXPLAIN_LINE=""
     DONE_LINE=""
     [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="    ↳ explain: [[${EXPLAIN}]]"
+    [ -n "$SUMMARY" ]   && EXPLAIN_LINE="    ↳ explain: ${SUMMARY}"
     [ -n "$DONE_WHEN" ] && DONE_LINE="    ↳ done when: ${DONE_WHEN}"
 
     awk -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
@@ -140,6 +144,7 @@ case "$MODE" in
     EXPLAIN_LINE=""
     DONE_LINE=""
     [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="      ↳ explain: [[${EXPLAIN}]]"
+    [ -n "$SUMMARY" ]   && EXPLAIN_LINE="      ↳ explain: ${SUMMARY}"
     [ -n "$DONE_WHEN" ] && DONE_LINE="      ↳ done when: ${DONE_WHEN}"
 
     # awk's `END { exit !inserted }` returns non-zero if no row matched the
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_roadmap-insert.bats; cd - >/dev/null`

Expected: `1..37`, all 37 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/roadmap-insert.sh claude-skills/ship-workflow/tests/test_roadmap-insert.bats
git commit -m "feat(roadmap-insert): R-013 Task 1 — --summary writes a plain ↳ explain line"
```

### Task 2: `sn_status` records each ship's phase; ship-next, `--discard` and `/ship-land` call it

Seam: `sn_status`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.5, G5, AC-5, AC-6, AC-9. Which phase a ship is in lived only in its worktree's `.ship/`. `sn_status` writes `<vault project>/ship-status/<ID>.json`; it is observability only, so every failure is one WARN and exit 0. It never creates the project folder, refuses an unknown phase or a non-`R-…` ID, and leaves a file it cannot parse as it is.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-land.md`
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Modify: `claude-skills/ship-workflow/lib/ship-next.sh`
- Modify: `claude-skills/ship-workflow/tests/test_command-blocks.bats`
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-lib.bats`

**Interfaces:**
- Consumes: `sn_state_load` and `airos-binding.sh project_path`; Task 1's `--summary`.
- Produces: `sn_status <worktree> <phase> [note]` in `lib/ship-next.sh`; the JSON format `{id, phase, updated, branch, note, phases:[{phase, at, note}]}` that Task 3's `statusOf` reads.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index a425a47..d4731f3 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -614,3 +614,33 @@ land_case() {
     [ "$status" -eq 0 ]
   done
 }
+
+@test "ship-next --discard deletes that ship's status file, not a sibling's" {
+  vault=$(make_fake_airos "$SCRATCH" repo)
+  write_global_config "$HOME" "$vault"
+  st="$vault/10 Projects/repo/ship-status"
+  mkdir -p "$st"
+  echo '{}' > "$st/R-1.json"
+  echo '{}' > "$st/R-10.json"
+  git worktree add -q -b ship/R-1-x "$SCRATCH/repo-worktrees/R-1-x"
+  block ship-next.md '^1\. \*\*Handle `--discard`' '^1\.6\. ' > "$SCRATCH/d.sh"
+  [ -s "$SCRATCH/d.sh" ]
+  run env MODE=discard TARGET=R-1 bash "$SCRATCH/d.sh"
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [ ! -e "$st/R-1.json" ]
+  [ -e "$st/R-10.json" ]
+}
+
+@test "ship-land step 4 records the ship as done once the compound is pushed" {
+  for shell in bash zsh; do
+    land_case "$shell"
+    vault=$(make_fake_airos "$SCRATCH" "repo-$shell")
+    write_global_config "$HOME" "$vault"
+    git worktree add -q --detach "$LAND_WT" origin/main
+    git -C "$LAND_WT" commit -q --allow-empty -m 'compound: R-1 — shipped + learning'
+    block ship-land.md '^4\. \*\*Push' '^5\. ' > "$SCRATCH/s4.sh"
+    run env ARGUMENTS=R-1 "$shell" "$SCRATCH/s4.sh"
+    [ "$status" -eq 0 ] || { echo "$shell: $output"; return 1; }
+    [ "$(jq -r .phase "$vault/10 Projects/repo-$shell/ship-status/R-1.json")" = done ] || return 1
+  done
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
index 20cc929..3186b37 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-lib.bats
@@ -224,3 +224,119 @@ mech_fixture() {
   [ "$output" = "$(git rev-parse --path-format=absolute --git-common-dir)/ship-R-1-state.env" ]
   ! grep -qE '/tmp/ship-[^ ]*state\.env' "$SHIP_LIB/ship-next.sh" || { grep -nE '/tmp/ship-[^ ]*state\.env' "$SHIP_LIB/ship-next.sh"; return 1; }
 }
+
+# R-013: sn_status records the ship's phase for the Roadmap 檢視 plugin.
+status_fixture() {
+  export HOME="$SCRATCH/home"
+  vault=$(make_fake_airos "$SCRATCH" wt)
+  write_global_config "$HOME" "$vault"
+  export PROJ="$vault/10 Projects/wt"
+  bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-9; sn_state_set "$WT" BRANCH ship/R-9-x'
+}
+
+# warns_once <shell> <script> — the script exits 0 and prints exactly one WARN line.
+warns_once() {
+  run "$1" -c "source \"\$SHIP_LIB/ship-next.sh\"; $2"
+  [ "$status" -eq 0 ] && [ "${#lines[@]}" -eq 1 ] && [[ "$output" == WARN:* ]] || { echo "$1: $output"; return 1; }
+}
+
+@test "sn_status records each phase in the vault project's ship-status file" {
+  status_fixture
+  for shell in bash zsh; do
+    rm -rf "$PROJ/ship-status"
+    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_status "$WT" plan && sn_status "$WT" blocked "codex: 3 attempts"'
+    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$shell: $output"; return 1; }
+    f="$PROJ/ship-status/R-9.json"
+    [ "$(jq -r .id "$f")" = R-9 ]
+    [ "$(jq -r .phase "$f")" = blocked ]
+    [ "$(jq -r .note "$f")" = "codex: 3 attempts" ]
+    [ "$(jq -r .branch "$f")" = ship/R-9-x ]
+    [ "$(jq -r '[.phases[].phase] | join(",")' "$f")" = plan,blocked ]
+    [ "$(jq -r '.phases[1].note' "$f")" = "codex: 3 attempts" ]
+    [ "$(jq -r '.updated, .phases[].at' "$f" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')" -eq 3 ]
+    [ "$(ls -A "$PROJ/ship-status")" = R-9.json ]
+  done
+}
+
+@test "sn_status without a vault config warns once and writes nothing" {
+  export HOME="$SCRATCH/home"
+  mkdir -p "$HOME"
+  bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-9'
+  for shell in bash zsh; do
+    warns_once "$shell" 'sn_status "$WT" plan'
+  done
+  [ -z "$(find "$SCRATCH" -name 'R-9*.json')" ]
+}
+
+@test "sn_status with an unwritable project dir warns once and writes nothing" {
+  status_fixture
+  chmod 555 "$PROJ"
+  for shell in bash zsh; do
+    warns_once "$shell" 'sn_status "$WT" plan' || { chmod 755 "$PROJ"; return 1; }
+  done
+  chmod 755 "$PROJ"
+  [ ! -e "$PROJ/ship-status" ]
+}
+
+@test "sn_status never creates a vault project folder that is not there" {
+  status_fixture
+  rm -rf "$PROJ"
+  for shell in bash zsh; do
+    warns_once "$shell" 'sn_status "$WT" plan'
+  done
+  [ ! -e "$PROJ" ]
+}
+
+@test "sn_status leaves a status file it cannot parse as it is" {
+  status_fixture
+  mkdir -p "$PROJ/ship-status"
+  echo 'not json' > "$PROJ/ship-status/R-9.json"
+  for shell in bash zsh; do
+    warns_once "$shell" 'sn_status "$WT" review'
+  done
+  [ "$(cat "$PROJ/ship-status/R-9.json")" = 'not json' ]
+  [ "$(ls -A "$PROJ/ship-status")" = R-9.json ]
+}
+
+@test "sn_status refuses a phase outside the list and an ID that is not a plain R-NNN" {
+  status_fixture
+  for shell in bash zsh; do
+    warns_once "$shell" 'sn_status "$WT" planning'
+    warns_once "$shell" 'sn_status "$WT"'
+  done
+  rm -rf "$WT/.ship"
+  for shell in bash zsh; do
+    warns_once "$shell" 'ID="../../x"; sn_status "$WT" done'
+  done
+  [ ! -e "$PROJ/ship-status" ]
+  [ -z "$(find "$SCRATCH" -name '*.json')" ]
+}
+
+@test "sn_status takes the caller's ID and BRANCH when the dir has no ship state (/ship-land)" {
+  status_fixture
+  rm -rf "$WT/.ship"
+  for shell in bash zsh; do
+    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; ID=R-9; BRANCH=ship/R-9-y; sn_status "$WT" done'
+    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$shell: $output"; return 1; }
+  done
+  [ "$(jq -r '.phase + " " + .branch' "$PROJ/ship-status/R-9.json")" = 'done ship/R-9-y' ]
+}
+
+# section <N> — the body of `## Phase N — …` in ship-next.md.
+section() { awk -v h="## Phase $1 " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f' "$SHIP_SKILL_ROOT/commands/ship-next.md"; }
+
+@test "ship-next records every phase where it starts, and blocked on each stop path" {
+  for pair in 2:brainstorm 4:plan 5:build 6:review 7:landing 8:done 8:in-review; do
+    section "${pair%%:*}" | grep -qF "sn_status \"\$WORKTREE\" ${pair#*:}" || { echo "Phase ${pair%%:*} does not record ${pair#*:}"; return 1; }
+  done
+  section 4 | grep -F 'Small-change lane' | grep -qF 'sn_status "$WORKTREE" build'
+  for anchor in '**`stop_infra`**' 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted'; do
+    grep -F -A2 -- "$anchor" "$SHIP_SKILL_ROOT/commands/ship-next.md" | grep -qF 'sn_status "$WORKTREE" blocked' \
+      || { echo "no blocked status at: $anchor"; return 1; }
+  done
+}
+
+@test "ship-next --adhoc passes a human summary to roadmap-insert" {
+  section 1 | grep -F 'roadmap-insert.sh' | grep -qF -- '--adhoc --summary "$SUMMARY_ZH"'
+  section 1 | grep -qE '^ *SUMMARY_ZH=.*zh-TW'
+}
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-lib.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats; cd - >/dev/null`

Expected: `1..76`, 65 ok, these 11 fail:
  - `not ok 19 sn_status records each phase in the vault project's ship-status file`
  - `not ok 20 sn_status without a vault config warns once and writes nothing`
  - `not ok 21 sn_status with an unwritable project dir warns once and writes nothing`
  - `not ok 22 sn_status never creates a vault project folder that is not there`
  - `not ok 23 sn_status leaves a status file it cannot parse as it is`
  - `not ok 24 sn_status refuses a phase outside the list and an ID that is not a plain R-NNN`
  - `not ok 25 sn_status takes the caller's ID and BRANCH when the dir has no ship state (/ship-land)`
  - `not ok 26 ship-next records every phase where it starts, and blocked on each stop path`
  - `not ok 27 ship-next --adhoc passes a human summary to roadmap-insert`
  - `not ok 73 ship-next --discard deletes that ship's status file, not a sibling's`
  - `not ok 74 ship-land step 4 records the ship as done once the compound is pushed`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-land.md b/claude-skills/ship-workflow/commands/ship-land.md
index 65206cd..ea98811 100644
--- a/claude-skills/ship-workflow/commands/ship-land.md
+++ b/claude-skills/ship-workflow/commands/ship-land.md
@@ -111,6 +111,8 @@ file runs here after the merge as `/ship-compound` in a throwaway worktree at
    (cd "$LAND_WT" && land_push "$BASE") || { echo "ERROR: could not push — the compound commit is left in $LAND_WT" >&2; exit 1; }
    git -C "$REPO" worktree remove --force "$LAND_WT"
    rm -rf "$(dirname "$LAND_WT")"
+   # R-013: the Roadmap 檢視 plugin shows the ship as done. $ID is the one given.
+   source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$REPO" done
    ```
 
 5. **Clean up what Phase 9 kept.**
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 5f50810..df85aee 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -57,6 +57,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
        git branch -D "$BRANCH" 2>/dev/null || true
        VAULT_SPECS_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/Specs"
        rm -f "$VAULT_SPECS_DIR/${ID}-"*.md
+       rm -f "${VAULT_SPECS_DIR%/Specs}/ship-status/${ID}.json"
        echo "Discarded worktree at $WT and branch $BRANCH"
      else echo "No worktree found for $ID"; fi
      exit 0
@@ -77,11 +78,12 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    ```
 3. **Handle `--adhoc`** (uses pre-parsed `TARGET` as description):
    ```bash
+   SUMMARY_ZH="…"   # one zh-TW sentence for a person: what changes and for whom, no file names
    if [ "$MODE" = "adhoc" ]; then
      ~/.claude/skills/ship-workflow/lib/sync.sh --force
      ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
      ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
-     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "$TARGET" --adhoc
+     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "$TARGET" --adhoc --summary "$SUMMARY_ZH"
      ~/.claude/skills/ship-workflow/lib/sync.sh --force
    fi
    ```
@@ -152,6 +154,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    sn_state_set "$WORKTREE" AUTO "$AUTO"
    sn_state_set "$WORKTREE" REPO "$REPO"
    if [ -n "$DESCRIPTION" ]; then sn_state_set "$WORKTREE" DESCRIPTION "$DESCRIPTION"; fi
+   sn_status "$WORKTREE" brainstorm   # R-013: the phase the Roadmap 檢視 plugin shows
    ```
 2. **cd into the worktree.** Tell the user explicitly:
    ```
@@ -225,7 +228,8 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
 
 ## Phase 4 — Writing plans
 
-**Small-change lane.** When the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, then go to Phase 6. Log the choice in auto mode. Set `EXECUTOR_CHOICE=2` and record it via Phase 5 step 2 and render the rule files via step 2.5 before implementing, so review fixes retain the inline executor.
+**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" plan`.
+**Small-change lane.** When the spec's Decisions size the work as one task, about ≤ 50 changed lines and no new seam beyond one function, skip this phase and Phase 5's executor choice: run `sn_status "$WORKTREE" build`, then implement it yourself in the worktree with TDD (failing test first), commit `feat(<ID>): …`, then go to Phase 6. Log the choice in auto mode. Set `EXECUTOR_CHOICE=2` and record it via Phase 5 step 2 and render the rule files via step 2.5 before implementing, so review fixes retain the inline executor.
 **Plan-authoring guidance:**
 - Verification/acceptance steps MUST run scoped pytest, not the full suite: list affected files or relevant module directories, e.g. `pytest tests/domain/test_foo.py tests/api/test_bar.py -q`. Missing environment credentials can leave a broad run hanging.
 - Reader-untouched grep guards MUST use `git diff <base>...HEAD -- <paths>`: three-dot excludes unrelated base-branch commits.
@@ -254,6 +258,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
 
 ## Phase 5 — Choose executor + run
 
+**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" build`.
 1. **Choose executor.**
    - **In auto mode (`AUTO=1`):** auto-pick `3` (codex /run-plan). Fall back to `1` only when the `codex` CLI is missing. Do **not** downgrade to `2` (inline) on plan-size or cost grounds.
      ```bash
@@ -336,13 +341,13 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    ```
    Then route on `$CODEX_ROUTE`:
    - **`continue`** (verdict `done` / `done_with_concerns`) → the helper has recorded the round and marked the run finished; continue to Phase 6.
-   - **`stop_infra`** (verdict `infra`) → STOP and notify using Phase 9 routing with `$CODEX_REASON`; do not relaunch, leave the **attempt count unchanged**, and retain the worktree and branch.
+   - **`stop_infra`** (verdict `infra`) → run `sn_status "$WORKTREE" blocked "codex infra: $CODEX_REASON"`, then STOP and notify using Phase 9 routing with `$CODEX_REASON`; do not relaunch, leave the **attempt count unchanged**, and retain the worktree and branch.
    - **`classify`** (verdict `blocked`) → read the executor's report and classify it into exactly one of three, then act:
      | Class | Signal | Action |
      |---|---|---|
      | **plan defect** | the prescribed step is wrong, ambiguous or impossible as written | repair `$PLAN`, relaunch from the blocked task |
      | **executor error** | the plan is right and the executor deviated — a transcription slip, an edit in the wrong place | relaunch with a correction note, plan unchanged |
-     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | **STOP and notify the operator** |
+     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | `sn_status "$WORKTREE" blocked "spec-level: <the finding>"`, then **STOP and notify the operator** |
      **When the classification is unclear, treat it as spec-level and escalate.** Do not redesign the approach.
      **Set these three yourself from the classification above** — they are the judgement's output and nothing computes them:
      ```bash
@@ -358,6 +363,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
      CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
      if [ "$CODEX_ATTEMPT" -ge "$CODEX_ATTEMPT_CAP" ]; then
        CODEX_ROUTE=stop_exhausted
+       sn_status "$WORKTREE" blocked "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted"
        echo "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted — stopping." >&2
        echo "worktree retained at $WORKTREE; history in .ship/codex-rounds.md" >&2
      else
@@ -369,6 +375,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
 
 ## Phase 6 — Code review loop (strict gate)
 
+**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" review`.
 0.5. **Mechanical test gates (pure git + shell, before the LLM review).**
    ```bash
    source ~/.claude/skills/ship-workflow/lib/ship-next.sh
@@ -500,6 +507,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
    - **In auto mode (`AUTO=1`):** **ABORT** the cycle. Send `$SUMMARY` by Discord reply if a chat_id is in scope; otherwise use PushNotification subject `/ship-next ${ID} aborted`. Do not cd to the original branch, remove the worktree, or delete the branch.
      ```bash
      ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" "cap=3 exhausted — aborting" "blocking=$BLOCKING_COUNT main untouched, worktree retained at $WORKTREE"
+     source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" blocked "review: $BLOCKING_COUNT blockers left after 3 attempts"
      SUMMARY="🛑 ${ID} ${DESCRIPTION} aborted at P6 — 3 attempts didn't clear blockers.
    • blocking remaining: ${BLOCKING_COUNT}
    • last attempt review: /tmp/ship-next-review-${ID}-3.md
@@ -553,6 +561,7 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
 ## Phase 7 — Land the branch (squash merge, or open a review)
 
 Read `merge_mode` from `.claude/ship-config.yml`: default `squash`, or `mr` for review.
+**Record the phase:** `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" landing`.
 1. **Build the body.** Both paths carry the same content: a squash commit message, or an MR/PR description. Build it once.
    ```bash
    source ~/.claude/skills/ship-workflow/lib/ship-next.sh
@@ -570,7 +579,7 @@ Read `merge_mode` from `.claude/ship-config.yml`: default `squash`, or `mr` for
 
 ## Phase 8 — /ship-compound (squash) · in-review + learning draft (mr)
 
-**`squash`:** invoke `/ship-compound` with `ID` set to this R-NNN from the original repo cwd on `$ORIG_BRANCH` (Phase 7 already cd'd back). It writes the learning, updates `CONTEXT.md` (exports `CONTEXT_MD_STATUS`), moves the row to Done and removes the spec and plan.
+**`squash`:** invoke `/ship-compound` with `ID` set to this R-NNN from the original repo cwd on `$ORIG_BRANCH` (Phase 7 already cd'd back). It writes the learning, updates `CONTEXT.md` (exports `CONTEXT_MD_STATUS`), moves the row to Done and removes the spec and plan. Then run `source ~/.claude/skills/ship-workflow/lib/ship-next.sh && sn_status "$WORKTREE" done`.
 **`mr`:** do not run `/ship-compound` — every file it writes is shared or belongs on the base branch, and parallel reviews must not touch them. `/ship-land` runs it after the merge. `/ship-idea --during-build` rows wait in `$WORKTREE/.ship/ship-log-rows` too; `/ship-land` replays them. Here:
 1. Mark the row in review:
    ```bash
@@ -578,6 +587,7 @@ Read `merge_mode` from `.claude/ship-config.yml`: default `squash`, or `mr` for
    sn_state_load "$WORKTREE"
    ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
    ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" --mark-review "$SHIP_REVIEW_URL"
+   sn_status "$WORKTREE" in-review
    ```
 2. While the context is fresh, draft the learning from `templates/repo/LEARNING.md` into `$WORKTREE/.ship/learning-draft.md`: Key Decisions from the spec's `## Decisions`, What Changed From Plan from the plan and `.ship/codex-rounds.md`. It is not committed; `/ship-land` starts from it. Set `CONTEXT_MD_STATUS="deferred to /ship-land"`.
 After either path, persist the CONTEXT.md result for cleanup:
diff --git a/claude-skills/ship-workflow/lib/ship-next.sh b/claude-skills/ship-workflow/lib/ship-next.sh
index ce0fe95..f28989e 100644
--- a/claude-skills/ship-workflow/lib/ship-next.sh
+++ b/claude-skills/ship-workflow/lib/ship-next.sh
@@ -28,6 +28,45 @@ sn_state_load() {
   fi
 }
 
+# sn_status <worktree> <phase> [note] — record this ship's phase for the Roadmap 檢視
+# plugin (R-013) in <vault project>/ship-status/<ID>.json. ID and BRANCH come from
+# <worktree>/.ship/state.env, else from the caller's ID/BRANCH (/ship-land passes the
+# main checkout). Observability only: any failure prints one WARN and returns 0.
+sn_status() {
+  local wt="${1:-}" phase="${2:-}" note="${3:-}" id branch proj dir tmp now
+  case "$phase" in
+    brainstorm|plan|build|review|landing|in-review|done|blocked) ;;
+    *) echo "WARN: sn_status: unknown phase '$phase' — not recorded" >&2; return 0 ;;
+  esac
+  id=$(sn_state_load "$wt"; printf '%s' "${ID:-}")
+  branch=$(sn_state_load "$wt"; printf '%s' "${BRANCH:-}")
+  case "$id" in
+    R-[0-9]*) case "$id" in *[!A-Za-z0-9.-]*) id="" ;; esac ;;
+    *) id="" ;;
+  esac
+  [ -n "$id" ] || { echo "WARN: sn_status: no R-NNN ID for '$wt' — $phase not recorded" >&2; return 0; }
+  command -v jq >/dev/null 2>&1 || { echo "WARN: sn_status: jq not found — $phase not recorded" >&2; return 0; }
+  proj=$(cd "$wt" 2>/dev/null && "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/airos-binding.sh" project_path 2>/dev/null) || proj=""
+  # Never mkdir the project itself: a wrong name would plant a bogus vault folder (R-004).
+  if [ -z "$proj" ] || [ ! -d "$proj" ]; then
+    echo "WARN: sn_status: no vault project for '$wt' — $phase not recorded" >&2; return 0
+  fi
+  dir="$proj/ship-status"
+  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
+  if mkdir -p "$dir" 2>/dev/null && tmp=$(mktemp "$dir/.$id.XXXXXX" 2>/dev/null); then
+    if { cat "$dir/$id.json" 2>/dev/null || echo '{}'; } \
+        | jq --arg id "$id" --arg phase "$phase" --arg at "$now" --arg branch "$branch" --arg note "$note" \
+            '.id = $id | .phase = $phase | .updated = $at | .branch = $branch | .note = $note
+             | .phases = ((.phases // []) + [{phase: $phase, at: $at, note: $note}])' > "$tmp" 2>/dev/null \
+        && mv "$tmp" "$dir/$id.json" 2>/dev/null; then
+      return 0
+    fi
+    rm -f "$tmp"
+  fi
+  echo "WARN: sn_status: could not write $dir/$id.json — $phase not recorded" >&2
+  return 0
+}
+
 sn_mech_gates() {
   local WORKTREE="$1" ORIG_BRANCH="$2" PLAN_FILE
   cd "$WORKTREE" || return
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-lib.bats tests/test_command-blocks.bats tests/test_no-positional-params.bats; cd - >/dev/null`

Expected: `1..76`, all 76 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-land.md claude-skills/ship-workflow/commands/ship-next.md claude-skills/ship-workflow/lib/ship-next.sh claude-skills/ship-workflow/tests/test_command-blocks.bats claude-skills/ship-workflow/tests/test_ship-next-lib.bats
git commit -m "feat(ship-next): R-013 Task 2 — sn_status records each phase in ship-status/<ID>.json"
```

### Task 3: The plugin's pure core: `parseRoadmap`, `mockupsFor`, `statusOf`, `currentStateDoc`

Seam: `parseRoadmap` / `mockupsFor` / `statusOf` / `currentStateDoc`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.1–§3.3, AC-1..AC-4, AC-4b. Plain CommonJS with no build: the pure functions are static members of the plugin class so `node --test` reaches them, with `obsidian` answered by `test/fake-obsidian.js` through `test/load.js`. `currentStateDoc` is a string scanner, not `DOMParser`. `test/local-vault.test.js` reads the real vault read-only when this machine has one (AC-4b) and is skipped elsewhere.

**Files:**
- Create: `obsidian-roadmap-view/main.js`
- Create: `obsidian-roadmap-view/test/fake-obsidian.js`
- Create: `obsidian-roadmap-view/test/load.js`
- Create: `obsidian-roadmap-view/test/local-vault.test.js`
- Create: `obsidian-roadmap-view/test/parse.test.js`

**Interfaces:**
- Consumes: Task 2's status-file format.
- Produces: `RoadmapViewPlugin.parseRoadmap(md) → Item[]`, `.mockupsFor(item, items, files) → string[]`, `.statusOf(item, phaseFile, now, recentDays) → {group, chips, phase}`, `.currentStateDoc(html) → string | null`; `test/load.js` and `test/fake-obsidian.js`.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/obsidian-roadmap-view/test/fake-obsidian.js b/obsidian-roadmap-view/test/fake-obsidian.js
new file mode 100644
index 0000000..f0af3f0
--- /dev/null
+++ b/obsidian-roadmap-view/test/fake-obsidian.js
@@ -0,0 +1,6 @@
+// A stand-in for the `obsidian` module, which exists only inside the app.
+class Plugin { constructor(app, manifest) { this.app = app; this.manifest = manifest; } }
+class ItemView { constructor(leaf) { this.leaf = leaf; this.app = leaf && leaf.app; } }
+class Modal { constructor(app) { this.app = app; } }
+class Notice { constructor(text) { this.text = text; } }
+module.exports = { Plugin, ItemView, Modal, Notice };
diff --git a/obsidian-roadmap-view/test/load.js b/obsidian-roadmap-view/test/load.js
new file mode 100644
index 0000000..4db2c43
--- /dev/null
+++ b/obsidian-roadmap-view/test/load.js
@@ -0,0 +1,9 @@
+// Loads ../main.js with `require("obsidian")` answered by the fake.
+const Module = require("module");
+const path = require("path");
+const fake = require("./fake-obsidian");
+const load = Module._load;
+Module._load = function (request, ...rest) {
+  return request === "obsidian" ? fake : load.call(this, request, ...rest);
+};
+module.exports = require(path.join(__dirname, "..", "main.js"));
diff --git a/obsidian-roadmap-view/test/local-vault.test.js b/obsidian-roadmap-view/test/local-vault.test.js
new file mode 100644
index 0000000..54e968f
--- /dev/null
+++ b/obsidian-roadmap-view/test/local-vault.test.js
@@ -0,0 +1,38 @@
+// R-013 AC-4b: the real vault, when this machine has one. Skipped elsewhere (CI, other
+// machines); the fixtures in parse.test.js cover the formats.
+const test = require("node:test");
+const assert = require("node:assert/strict");
+const fs = require("fs");
+const os = require("os");
+const path = require("path");
+const P = require("./load");
+
+function vault() {
+  try {
+    const cfg = fs.readFileSync(path.join(os.homedir(), ".claude", "ship-workflow.yml"), "utf8");
+    const m = cfg.match(/^airos_vault:\s*"?([^"#\n]+?)"?\s*(#.*)?$/m);
+    return m && fs.existsSync(path.join(m[1], "10 Projects")) ? m[1] : null;
+  } catch { return null; }
+}
+const V = vault();
+const projects = V ? fs.readdirSync(path.join(V, "10 Projects"))
+  .map((p) => path.join(V, "10 Projects", p)).filter((p) => fs.existsSync(path.join(p, "ROADMAP.md"))) : [];
+const ROW = /^\s*- \[[ xX]\] [^*]{0,6}\*\*R-\d[\w.-]*(?: \([^)*]*\))?\*\*/;
+
+test("the real ROADMAPs: every **R-…** row is parsed", { skip: !V && "no vault on this machine" }, () => {
+  for (const p of projects) {
+    const md = fs.readFileSync(path.join(p, "ROADMAP.md"), "utf8");
+    const want = md.split("\n").filter((l) => ROW.test(l)).length;
+    assert.equal(P.parseRoadmap(md).length, want, path.basename(p));
+  }
+});
+
+test("the real mockups: each R-NNN mockup yields a 現況 document", { skip: !V && "no vault on this machine" }, () => {
+  for (const p of projects) {
+    const dir = path.join(p, "Proposals", "mockups");
+    if (!fs.existsSync(dir)) continue;
+    for (const f of fs.readdirSync(dir).filter((f) => /^R-.*\.html$/.test(f))) {
+      assert.ok(P.currentStateDoc(fs.readFileSync(path.join(dir, f), "utf8")), f);
+    }
+  }
+});
diff --git a/obsidian-roadmap-view/test/parse.test.js b/obsidian-roadmap-view/test/parse.test.js
new file mode 100644
index 0000000..4e694be
--- /dev/null
+++ b/obsidian-roadmap-view/test/parse.test.js
@@ -0,0 +1,194 @@
+// R-013 AC-1..AC-4. Fixture rows copy the exact formats of langlive's R-248, R-256,
+// R-094.2/.3 and R-231 and of ai_system's trailing annotations; the text is synthetic
+// (this repo is public, langlive's roadmap is company data).
+const test = require("node:test");
+const assert = require("node:assert/strict");
+const P = require("./load");
+
+const MD = `# ROADMAP
+
+## 🔥 Now (3-5 items)
+
+- [ ] **R-094.3** [FEATURE · P2 · UIUX · blocked: prod LIFF channel · 接續 R-094.2] 推播連結追蹤＋點擊貼標 —— 推播裡的網址換成追蹤連結
+    ↳ mockup 同上（方案 A）· 代價：第一次點會看到許可畫面
+    ↳ done when: 推播網址自動換成追蹤連結（可關）
+- [x] **R-248** [FEATURE · P2 · UIUX · mockup 定案 B · ✅ merged 2026-10-19 · main \`7fe542a1\`（squash 直接 push，未開 MR）· 尚未部署 test · learning \`docs/learnings/R-248-x.md\`] 總覽分頁下方「問題主題／問題細節」列表調整 —— 拿掉解決率欄
+  ↳ done when: 列表沒有解決率欄
+  ↳ explain: mockup \`Proposals/mockups/insights-overview-list-polish-mockup.html\` 方案 B（以人為主版）。
+
+- [x] **R-256** [FEATURE · P2 · UIUX · mockup 定案 A · ✅ 2026-10-22～24 · squash 直接 push main：第 1 步 \`60b4da26\` · 第 2 步 \`d7cbc584\`] 對話面板改良（\`LeafTimelinePanel\`，四個分頁共用）—— 圖片可放大
+- [ ] **R-014** 審查中的項目 · status=in-review · mr=https://gitlab.example.com/g/p/-/merge_requests/285
+
+## 🔜 Next
+
+- [ ] **R-231** [EPIC · P2 · needs-brainstorm] 客戶標籤：從工單與對話自動長出可篩選的 tag —— **來源：** 使用者討論。
+    ↳ done when: 行銷能用 tag 篩出名單
+    ↳ done when: 每個 tag 點得到來源對話
+    ↳ explain: 精準推播要先知道誰對什麼有興趣，這個 epic 把聊天紀錄變成可以篩選的標籤。
+  - [ ] **R-231.2** [FEATURE · P3] 子項目 **來源：** 討論
+- [ ] ⚠️ **R-300** (epic) 大項目
+
+## ✅ Done
+
+- [x] **R-094.2** [FEATURE · P2 · UIUX · ✅ 2026-10-23 · squash \`3a8d0ebe\` 直接 push main · 接續 R-094.1] 推播成效：收到後 7 天儲值率 —— 每則推播顯示儲值率
+    ↳ mockup [[Proposals/mockups/liff-push-click-tracking-mockup.html|推播成效 mockup（方案 D）]] · 建議對照組預設 10%
+- [x] **R-012** vault 自動備份範例同步實機修正 · ✅ 2026-10-25
+- [x] **R-001 (epic)** 劇情 pipeline · ✅ shipped · merged 2026-09-01
+- [x] ~~**R-093** 客戶流失預測~~ —— **superseded by [[R-206]]**
+- [x] **R-193.3a-2.1** [FIX · P3 · ✅ 34405dee] 子項 · MR !288
+- [x] ✅ **R-193 號碼衝突已結案** —— not an item
+`;
+const items = P.parseRoadmap(MD);
+const by = (id) => items.find((i) => i.id === id);
+
+test("parseRoadmap: one item per R row, children and odd ids included, notes excluded", () => {
+  assert.deepEqual(items.map((i) => i.id), ["R-094.3", "R-248", "R-256", "R-014", "R-231", "R-231.2", "R-300",
+    "R-094.2", "R-012", "R-001", "R-093", "R-193.3a-2.1"]);
+  assert.equal(by("R-248").section, "🔥 Now (3-5 items)");
+  assert.equal(by("R-094.2").section, "✅ Done");
+  assert.equal(by("R-094.3").line, 4);
+  assert.equal(by("R-248").raw, MD.split("\n")[by("R-248").line]);
+});
+
+test("parseRoadmap: R-248 — headline, done date, undeployed env, picked option, commit, no explain", () => {
+  const r = by("R-248");
+  assert.equal(r.headline, "總覽分頁下方「問題主題／問題細節」列表調整");
+  assert.equal(r.checked, true);
+  assert.equal(r.done, "2026-10-19");
+  assert.equal(r.undeployed, "test");
+  assert.equal(r.picked, "B");
+  assert.equal(r.commit, "7fe542a1");
+  assert.equal(r.explain, null);
+  assert.deepEqual(r.refs, ["Proposals/mockups/insights-overview-list-polish-mockup.html"]);
+  assert.deepEqual(r.doneWhen, ["列表沒有解決率欄"]);
+  assert.match(r.tags, /^FEATURE · P2 · UIUX · mockup 定案 B/);
+});
+
+test("parseRoadmap: R-094.3 — blocked reason, mockup 同上", () => {
+  const r = by("R-094.3");
+  assert.equal(r.blocked, "prod LIFF channel");
+  assert.equal(r.sameAsAbove, true);
+  assert.equal(r.checked, false);
+  assert.equal(r.done, null);
+  assert.equal(r.headline, "推播連結追蹤＋點擊貼標");
+});
+
+test("parseRoadmap: R-231 — explain kept, needs-brainstorm, epic, headline stops at **來源", () => {
+  const r = by("R-231");
+  assert.equal(r.explain, "精準推播要先知道誰對什麼有興趣，這個 epic 把聊天紀錄變成可以篩選的標籤。");
+  assert.equal(r.needsBrainstorm, true);
+  assert.equal(r.epic, true);
+  assert.equal(r.headline, "客戶標籤：從工單與對話自動長出可篩選的 tag");
+  assert.deepEqual(r.doneWhen, ["行銷能用 tag 篩出名單", "每個 tag 點得到來源對話"]);
+  assert.equal(by("R-231.2").headline, "子項目");
+});
+
+test("parseRoadmap: date range, trailing annotations, wikilink mockup ref, MR numbers, epic markers", () => {
+  assert.equal(by("R-256").done, "2026-10-22");
+  assert.equal(by("R-256").commit, "60b4da26");
+  assert.equal(by("R-256").headline, "對話面板改良（`LeafTimelinePanel`，四個分頁共用）");
+  assert.equal(by("R-012").headline, "vault 自動備份範例同步實機修正");
+  assert.equal(by("R-012").done, "2026-10-25");
+  assert.equal(by("R-012").tags, "");
+  assert.equal(by("R-014").headline, "審查中的項目");
+  assert.equal(by("R-014").inReview, true);
+  assert.equal(by("R-014").mr, "!285");
+  assert.equal(by("R-193.3a-2.1").mr, "!288");
+  assert.equal(by("R-193.3a-2.1").commit, null);
+  assert.equal(by("R-193.3a-2.1").done, null);
+  assert.deepEqual(by("R-094.2").refs, ["Proposals/mockups/liff-push-click-tracking-mockup.html"]);
+  assert.equal(by("R-001").done, "2026-09-01");
+  assert.equal(by("R-001").epic, true);
+  assert.equal(by("R-300").epic, true);
+  assert.equal(by("R-093").headline, "客戶流失預測");
+  assert.equal(by("R-248").epic, false);
+});
+
+test("parseRoadmap: an unknown tag format degrades to no status, never throws", () => {
+  const [r] = P.parseRoadmap("- [ ] **R-7** [ODD · ✅ soon · blocked:] 文字");
+  assert.equal(r.done, null);
+  assert.equal(r.blocked, null);
+  assert.equal(r.headline, "文字");
+  assert.deepEqual(P.parseRoadmap(""), []);
+});
+
+test("mockupsFor: own <id>- files, then refs, de-duplicated; R-248 never takes R-2480's", () => {
+  const files = ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/R-2480-x-mockup.html",
+    "Proposals/mockups/insights-overview-list-polish-mockup.html", "Proposals/mockups/R-248-notes.md"];
+  const r = { ...by("R-248"), refs: [...by("R-248").refs, "Proposals/mockups/R-248-a-mockup.html"] };
+  assert.deepEqual(P.mockupsFor(r, items, files),
+    ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/insights-overview-list-polish-mockup.html"]);
+});
+
+test("mockupsFor: 同上 takes the nearest same-base id that has a mockup, not the nearest line (AC-2)", () => {
+  assert.deepEqual(P.mockupsFor(by("R-094.3"), items, []),
+    ["Proposals/mockups/liff-push-click-tracking-mockup.html"]);
+  const it = (id, refs, same = false) => ({ id, refs, sameAsAbove: same });
+  const list = [it("R-5.4", [], true), it("R-5.1", ["a.html"]), it("R-5.3", [], true), it("R-5.2", ["b.html"]),
+    it("R-50", ["c.html"]), it("R-5.9", ["d.html"])];
+  assert.deepEqual(P.mockupsFor(list[0], list, []), ["b.html"]);
+  assert.deepEqual(P.mockupsFor(it("R-5.0", [], true), list, []), ["a.html"]);
+  assert.deepEqual(P.mockupsFor(it("R-6", [], true), list, []), []);
+});
+
+test("statusOf: active / recent / done / todo (AC-3)", () => {
+  const now = new Date("2026-10-25T12:00:00Z");
+  const plain = by("R-300");
+  assert.equal(P.statusOf(plain, { phase: "review", updated: "2026-10-25T08:00:00Z" }, now, 14).group, "active");
+  assert.equal(P.statusOf(by("R-248"), null, now, 14).group, "recent");
+  assert.equal(P.statusOf(by("R-001"), null, now, 14).group, "done");
+  assert.equal(P.statusOf(plain, null, now, 14).group, "todo");
+  assert.equal(P.statusOf(by("R-094.3"), null, now, 14).group, "active");
+  assert.equal(P.statusOf(by("R-014"), null, now, 14).group, "active");
+  assert.equal(P.statusOf(by("R-093"), null, now, 14).group, "done");
+});
+
+test("statusOf: a status file wins only when it is newer than the tags", () => {
+  const now = new Date("2026-10-25T12:00:00Z");
+  const stale = P.statusOf(by("R-248"), { phase: "landing", updated: "2026-10-18T09:00:00Z" }, now, 14);
+  assert.equal(stale.group, "recent");
+  assert.equal(stale.phase, null);
+  const s = P.statusOf(by("R-300"), { phase: "blocked", updated: "2026-10-25T09:00:00Z", note: "codex: 3 attempts" }, now, 14);
+  assert.equal(s.group, "active");
+  assert.equal(s.phase, "blocked");
+  assert.ok(s.chips.some((c) => c.kind === "blocked" && c.text.includes("codex: 3 attempts")));
+  const d = P.statusOf(by("R-300"), { phase: "done", updated: "2026-10-24T09:00:00Z" }, now, 14);
+  assert.equal(d.group, "recent");
+  assert.equal(P.statusOf(by("R-300"), { phase: "nonsense", updated: "2026-10-25T09:00:00Z" }, now, 14).group, "todo");
+  assert.equal(P.statusOf(by("R-300"), { phase: "done", updated: "2026-01-01T00:00:00Z" }, now, 14).group, "done");
+});
+
+test("statusOf: chips carry what the row says", () => {
+  const c = P.statusOf(by("R-248"), null, new Date("2026-10-25T12:00:00Z"), 14).chips.map((x) => x.text);
+  assert.deepEqual(c, ["完成 10/19", "尚未部署 test", "方案 B"]);
+});
+
+const PAGE = (body) => `<!DOCTYPE html><html><head><style>.a{color:red}</style>
+<style media="screen">.panel{border:1px}</style></head><body>${body}</body></html>`;
+
+test("currentStateDoc: the whole .panel.now with nested divs, every style kept (AC-4)", () => {
+  const now = '<div class="panel now"><div><div>現況</div></div><p>y</p></div>';
+  const doc = P.currentStateDoc(PAGE(`<div class="panel facts">F</div>${now}<div class="panel">later</div>`));
+  assert.ok(doc.startsWith("<!DOCTYPE html>"));
+  assert.ok(doc.includes(now));
+  assert.ok(doc.includes(".a{color:red}") && doc.includes(".panel{border:1px}"));
+  assert.ok(!doc.includes(">F<") && !doc.includes("later"));
+});
+
+test("currentStateDoc: no .panel.now → first non-facts panel; no panel → body; panel-title is not a panel", () => {
+  const a = P.currentStateDoc(PAGE('<div class="panel-title">T</div><div class="panel facts">F</div><section class=\'optA panel\'>A<section>in</section></section>'));
+  assert.ok(a.includes("<section class='optA panel'>A<section>in</section></section>"));
+  assert.ok(!a.includes(">F<") && !a.includes(">T<"));
+  const b = P.currentStateDoc(PAGE("<h1>hi</h1>"));
+  assert.ok(b.includes("<h1>hi</h1>"));
+  const c = P.currentStateDoc(PAGE('<div class="now panel" id=x>N</div>'));
+  assert.ok(c.includes('<div class="now panel" id=x>N</div>'));
+});
+
+test("currentStateDoc: drops scripts, and returns null for no html", () => {
+  const doc = P.currentStateDoc(PAGE('<div class="panel now">ok<script>alert(1)</script></div><script>x()</script>'));
+  assert.ok(doc.includes("ok") && !/<script/i.test(doc));
+  assert.equal(P.currentStateDoc(""), null);
+  assert.equal(P.currentStateDoc(null), null);
+  assert.equal(P.currentStateDoc("<html><head></head></html>"), null);
+});
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 2`, `ℹ pass 0`, `ℹ fail 2` — these fail:
  - `✖ obsidian-roadmap-view/test/local-vault.test.js`
  - `✖ obsidian-roadmap-view/test/parse.test.js`

  Both files fail to load with `Cannot find module …/obsidian-roadmap-view/main.js` — main.js does not exist yet.

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
new file mode 100644
index 0000000..737546f
--- /dev/null
+++ b/obsidian-roadmap-view/main.js
@@ -0,0 +1,211 @@
+// Roadmap 檢視 (R-013) — a live, read-only, phone-first view of one project's ROADMAP.
+// ROADMAP.md stays written for AI; this picks what a person needs and shows it.
+// Plain CommonJS, no build: Obsidian loads this one file. The pure functions are static
+// members of the plugin class so `node --test test/` can reach them.
+const { Plugin } = require("obsidian");
+
+// ---------------------------------------------------------------- parsing (pure)
+
+// A ROADMAP item row. Real rows seen 2026-10-25: `**R-001 (epic)**`, `**R-193.3a-2.1**`,
+// `~~**R-093** …~~`, `⚠️ **R-300** (epic)`.
+const ROW = /^(\s*)- \[( |x)\] (⚠️ )?(~~)?\*\*(R-\d[\w.-]*)((?: \([^)*]*\))?)\*\*( \(epic\))?/;
+
+// Index of the `]` closing the `[` at s[0], counting nested brackets; -1 if unbalanced.
+function closeBracket(s) {
+  let depth = 0;
+  for (let i = 0; i < s.length; i++) {
+    if (s[i] === "[") depth++;
+    else if (s[i] === "]" && --depth === 0) return i;
+  }
+  return -1;
+}
+
+function itemFrom(row, m, ann, section, line) {
+  const rest = row.slice(m[0].length).trim();
+  let tags = "";
+  let body = rest;
+  if (rest.startsWith("[") && !rest.startsWith("[[")) {
+    const end = closeBracket(rest);
+    if (end > 0) { tags = rest.slice(1, end); body = rest.slice(end + 1).trim(); }
+  }
+  let headline = body.split(/\s*——|\*\*來源/)[0].replace(/~~/g, "")
+    // trailing ` · ✅ <date>` / ` · status=…` / ` · mr=…` written by ship-workflow
+    .replace(/(\s*·\s*(?:✅[^·]*|[a-z][\w-]*=\S*))+\s*$/, "").trim();
+  if (!headline) headline = body.replace(/^[\s—]+/, "").slice(0, 120);
+  const explainLine = ann.find((a) => a.startsWith("↳ explain:"));
+  const explain = explainLine ? explainLine.replace(/^↳ explain:\s*/, "").trim() : null;
+  const pick = (re) => { const x = row.match(re); return x ? x[1].trim() : null; };
+  const mrUrl = row.match(/mr=\S*?\/(\d+)\/?(?=\s|$)/);
+  const mrBang = row.match(/(?:^|[^\w&])!(\d+)\b/);
+  const refs = [];
+  for (const r of [row, ...ann].join("\n").match(/Proposals\/mockups\/[^`\s)|\]]+?\.html/g) || []) {
+    if (!refs.includes(r)) refs.push(r);
+  }
+  const undeployed = row.match(/尚未部署\s*([A-Za-z][\w／/-]*)?/);
+  return {
+    id: m[5],
+    checked: m[2] === "x",
+    section,
+    line,
+    tags,
+    headline,
+    raw: row,
+    ann,
+    doneWhen: ann.filter((a) => a.startsWith("↳ done when:")).map((a) => a.replace(/^↳ done when:\s*/, "").trim()),
+    explain: explain && !/^mockup\b/i.test(explain) ? explain : null,
+    refs,
+    sameAsAbove: ann.some((a) => /mockup 同上/.test(a)),
+    done: pick(/✅[^\d\n]{0,40}?(\d{4}-\d{2}-\d{2})/),
+    undeployed: undeployed ? (undeployed[1] || "") : null,
+    blocked: pick(/blocked:\s*([^·\]\n]*[^·\]\n\s])/),
+    needsBrainstorm: /needs-brainstorm/.test(row),
+    picked: pick(/mockup 定案\s*([^\s·\]]+)/),
+    inReview: /status=in-review/.test(row),
+    epic: /epic/i.test(m[6]) || !!m[7] || /^EPIC\b/.test(tags),
+    commit: pick(/`([0-9a-f]{7,10})`/),
+    mr: mrUrl ? `!${mrUrl[1]}` : mrBang ? `!${mrBang[1]}` : null,
+  };
+}
+
+function parseRoadmap(md) {
+  const lines = String(md || "").split("\n");
+  const items = [];
+  let section = "";
+  for (let i = 0; i < lines.length; i++) {
+    if (/^## /.test(lines[i])) { section = lines[i].slice(3).trim(); continue; }
+    const m = lines[i].match(ROW);
+    if (!m) continue;
+    const ann = [];
+    for (let j = i + 1; j < lines.length && /^\s+↳/.test(lines[j]); j++) ann.push(lines[j].trim());
+    items.push(itemFrom(lines[i], m, ann, section, i));
+  }
+  return items;
+}
+
+// R-094.3 vs R-094.2: compare dot-separated parts, numerically where both are numbers.
+function compareIds(a, b) {
+  const pa = a.slice(2).split("."), pb = b.slice(2).split(".");
+  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
+    if (pa[i] === undefined) return -1;
+    if (pb[i] === undefined) return 1;
+    const na = parseInt(pa[i], 10), nb = parseInt(pb[i], 10);
+    if (na !== nb && !isNaN(na) && !isNaN(nb)) return na - nb;
+    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
+  }
+  return 0;
+}
+
+// `files`: mockup paths relative to the project dir ("Proposals/mockups/x.html").
+function mockupsFor(item, items, files) {
+  const own = (it) => [
+    ...(files || []).filter((f) => /\.html$/i.test(f) && f.split("/").pop().startsWith(`${it.id}-`)),
+    ...(it.refs || []),
+  ];
+  const out = [];
+  for (const f of own(item)) if (!out.includes(f)) out.push(f);
+  if (item.sameAsAbove) {
+    const base = item.id.split(".")[0];
+    const sibs = items.filter((o) => o.id !== item.id && o.id.split(".")[0] === base && own(o).length)
+      .sort((a, b) => compareIds(a.id, b.id));
+    // "同上" means the one written above it: the closest smaller id, else the closest larger.
+    const before = sibs.filter((o) => compareIds(o.id, item.id) < 0).pop();
+    const after = sibs.find((o) => compareIds(o.id, item.id) > 0);
+    for (const f of own(before || after || { refs: [] })) if (!out.includes(f)) out.push(f);
+  }
+  return out;
+}
+
+const PHASE_TEXT = {
+  brainstorm: "討論中", plan: "寫計畫", build: "實作中", review: "審查中",
+  landing: "合併中", "in-review": "等 MR 合併", done: "完成", blocked: "卡住",
+};
+const monthDay = (d) => `${d.getMonth() + 1}/${d.getDate()}`;
+
+// `phaseFile`: the parsed ship-status/<id>.json, or null. A ROADMAP date counts as the end
+// of that day, so on the same day the row's own tags win.
+function statusOf(item, phaseFile, now = new Date(), recentDays = 14) {
+  const pf = phaseFile && PHASE_TEXT[phaseFile.phase] ? phaseFile : null;
+  const pfAt = pf ? Date.parse(pf.updated) : NaN;
+  const tagAt = item.done ? Date.parse(`${item.done}T23:59:59`) : NaN;
+  const usePhase = !!pf && (isNaN(pfAt) ? !item.checked && !item.done : !(tagAt >= pfAt));
+  const phase = usePhase ? pf.phase : null;
+  let doneAt = null;
+  let isDone = false;
+  if (phase === "done") { isDone = true; doneAt = isNaN(pfAt) ? null : new Date(pfAt); }
+  else if (!phase && (item.done || item.checked)) {
+    isDone = true;
+    doneAt = item.done ? new Date(`${item.done}T00:00:00`) : null;
+  }
+  const chips = [];
+  if (phase && phase !== "done") {
+    chips.push(phase === "blocked"
+      ? { kind: "blocked", text: pf.note ? `卡住：${pf.note}` : "卡住" }
+      : { kind: "phase", text: PHASE_TEXT[phase] });
+  }
+  if (isDone) chips.push({ kind: "done", text: doneAt ? `完成 ${monthDay(doneAt)}` : "完成" });
+  if (item.blocked) chips.push({ kind: "blocked", text: `卡住：${item.blocked}` });
+  if (item.undeployed !== null && item.undeployed !== undefined) {
+    chips.push({ kind: "wait", text: `尚未部署${item.undeployed ? ` ${item.undeployed}` : ""}` });
+  }
+  if (item.inReview && !phase) chips.push({ kind: "phase", text: PHASE_TEXT["in-review"] });
+  if (item.needsBrainstorm) chips.push({ kind: "wait", text: "待討論" });
+  if (item.picked) chips.push({ kind: "pick", text: `方案 ${item.picked}` });
+  if (item.epic) chips.push({ kind: "epic", text: "epic" });
+  let group;
+  if ((phase && phase !== "done") || item.blocked || (item.inReview && !isDone)) group = "active";
+  else if (isDone) group = doneAt && now - doneAt <= recentDays * 864e5 ? "recent" : "done";
+  else group = "todo";
+  return { group, chips, phase };
+}
+
+// ---------------------------------------------------------------- 現況 extraction (pure)
+
+const classesOf = (attrs) => {
+  const m = attrs.match(/\bclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
+  return m ? (m[1] ?? m[2] ?? m[3]).split(/\s+/) : [];
+};
+
+// From the opening tag at `start`, the index just past its balanced close; -1 if unclosed.
+function elementEnd(scan, start, name) {
+  const re = new RegExp(`<(/?)${name}\\b[^>]*?(/?)>`, "gi");
+  re.lastIndex = start;
+  let depth = 0;
+  for (let m; (m = re.exec(scan));) {
+    if (m[1]) depth--;
+    else if (!m[2]) depth++;
+    if (depth === 0) return re.lastIndex;
+  }
+  return -1;
+}
+
+// A string scanner, not DOMParser: testable under node and the same on every platform.
+function currentStateDoc(html) {
+  if (typeof html !== "string" || !html) return null;
+  const styles = (html.match(/<style\b[^>]*>[\s\S]*?<\/style>/gi) || []).join("\n");
+  // Blank out style/script bodies (same length) so a `<div` inside them is not counted.
+  const scan = html.replace(/<(style|script)\b[\s\S]*?<\/\1>/gi, (s) => " ".repeat(s.length));
+  const tags = [];
+  for (const m of scan.matchAll(/<([a-zA-Z][\w-]*)\b([^>]*)>/g)) {
+    const cls = classesOf(m[2]);
+    if (cls.includes("panel")) tags.push({ at: m.index, name: m[1], cls });
+  }
+  const pick = tags.find((t) => t.cls.includes("now")) || tags.find((t) => !t.cls.includes("facts"));
+  const end = pick ? elementEnd(scan, pick.at, pick.name) : -1;
+  let el = end > 0 ? html.slice(pick.at, end) : null;
+  if (!el) {
+    const b = html.match(/<body\b[^>]*>([\s\S]*)<\/body>/i);
+    el = b && b[1].trim() ? b[1] : null;
+  }
+  if (!el) return null;
+  el = el.replace(/<script\b[\s\S]*?<\/script>/gi, "");
+  return `<!DOCTYPE html><html><head><meta charset="utf-8">${styles}
+<style>html,body{margin:0;background:#fff;overflow:hidden}body{padding:12px}.panel{margin:0!important}</style>
+</head><body>${el}</body></html>`;
+}
+
+// ---------------------------------------------------------------- plugin
+
+class RoadmapViewPlugin extends Plugin {}
+
+Object.assign(RoadmapViewPlugin, { parseRoadmap, mockupsFor, statusOf, currentStateDoc });
+module.exports = RoadmapViewPlugin;
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 16`, `ℹ pass 16`, `ℹ fail 0`.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/fake-obsidian.js obsidian-roadmap-view/test/load.js obsidian-roadmap-view/test/local-vault.test.js obsidian-roadmap-view/test/parse.test.js
git commit -m "feat(roadmap-view): R-013 Task 3 — parse ROADMAP rows, mockups, status and the 現況 panel"
```

### Task 4: The Roadmap 檢視 view: 近況 / 全部, detail page, lazy zoomable 現況 thumbnails

Seam: `RoadmapViewPlugin` (its registered `roadmap-view` view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.3–§3.4, G1–G4, anti-goals. An `ItemView` with a ribbon icon and 「打開 Roadmap 檢視」; a project picker; 近況 groups and a searchable 全部 list; a detail page with spec / brainstorm / mockup links. Vault events under the project re-render it, debounced 500 ms. Thumbnails render only in view, at most 2 at once, cached per mtime, in a sandboxed iframe; a tap zooms. Every render failure is shown in the pane. The view has no field named `open` (it shadows `View.open`: the spike's black pane).

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Create: `obsidian-roadmap-view/manifest.json`
- Create: `obsidian-roadmap-view/styles.css`
- Modify: `obsidian-roadmap-view/test/fake-obsidian.js`
- Create: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Task 3's four functions and test helpers.
- Produces: `manifest.json` (id `roadmap-view`, `isDesktopOnly: false`), `main.js`, `styles.css` — the three files Task 5 copies into the vault.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/obsidian-roadmap-view/test/fake-obsidian.js b/obsidian-roadmap-view/test/fake-obsidian.js
index f0af3f0..8b70ffd 100644
--- a/obsidian-roadmap-view/test/fake-obsidian.js
+++ b/obsidian-roadmap-view/test/fake-obsidian.js
@@ -1,6 +1,68 @@
-// A stand-in for the `obsidian` module, which exists only inside the app.
-class Plugin { constructor(app, manifest) { this.app = app; this.manifest = manifest; } }
-class ItemView { constructor(leaf) { this.leaf = leaf; this.app = leaf && leaf.app; } }
-class Modal { constructor(app) { this.app = app; } }
-class Notice { constructor(text) { this.text = text; } }
-module.exports = { Plugin, ItemView, Modal, Notice };
+// A stand-in for the `obsidian` module, which exists only inside the app: just enough
+// DOM (Obsidian's createEl helpers) and plugin plumbing for test/*.test.js.
+class El {
+  constructor(tag, o = {}) {
+    Object.assign(this, { tag, children: [], classes: new Set(), attrs: {}, style: {}, dataset: {},
+      listeners: {}, text: "", value: "", parentElement: null, clientWidth: 0 });
+    if (o.cls) for (const c of String(o.cls).split(/\s+/).filter(Boolean)) this.classes.add(c);
+    if (o.text !== undefined) this.text = String(o.text);
+    if (o.value !== undefined) this.value = o.value;
+    for (const k of ["type", "placeholder"]) if (o[k] !== undefined) this.attrs[k] = o[k];
+    if (o.attr) Object.assign(this.attrs, o.attr);
+  }
+  createEl(tag, o) { const e = new El(tag, o); e.parentElement = this; this.children.push(e); return e; }
+  createDiv(o) { return this.createEl("div", o); }
+  createSpan(o) { return this.createEl("span", o); }
+  empty() { this.children = []; this.text = ""; }
+  addClass(c) { this.classes.add(c); }
+  removeClass(c) { this.classes.delete(c); }
+  toggleClass(c, on) { if (on) this.addClass(c); else this.removeClass(c); }
+  hasClass(c) { return this.classes.has(c); }
+  setText(t) { this.text = String(t); this.children = []; }
+  setAttr(k, v) { this.attrs[k] = v; }
+  addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }
+  fire(t, e = {}) {
+    let stopped = false;
+    for (const f of this.listeners[t] || []) {
+      f({ stopPropagation() { stopped = true; }, preventDefault() {}, target: this, ...e });
+    }
+    if (!stopped && this.parentElement && t === "click") this.parentElement.fire(t, e);
+  }
+  remove() {
+    if (this.parentElement) this.parentElement.children = this.parentElement.children.filter((c) => c !== this);
+  }
+  get textContent() { return [this.text, ...this.children.map((c) => c.textContent)].filter(Boolean).join(" "); }
+  findAll(pred) {
+    const out = [];
+    const walk = (e) => { if (pred(e)) out.push(e); e.children.forEach(walk); };
+    walk(this);
+    return out;
+  }
+  querySelectorAll(tag) { return this.findAll((e) => e.tag === tag); }
+}
+
+class Plugin {
+  constructor(app, manifest) {
+    Object.assign(this, { app, manifest, views: {}, commands: [], ribbons: [], events: [], stored: null });
+  }
+  registerView(type, make) { this.views[type] = make; }
+  addRibbonIcon(icon, title, cb) { this.ribbons.push({ icon, title, cb }); }
+  addCommand(c) { this.commands.push(c); }
+  registerEvent(ref) { this.events.push(ref); }
+  async loadData() { return this.stored; }
+  async saveData(d) { this.stored = JSON.parse(JSON.stringify(d)); }
+}
+// Obsidian's View has an `open` method; a subclass field of that name shadows it.
+class ItemView {
+  constructor(leaf) { this.leaf = leaf; this.app = leaf.app; this.contentEl = new El("div"); }
+  open() { return "View.open"; }
+}
+class Modal {
+  constructor(app) { this.app = app; this.contentEl = new El("div"); this.titleEl = new El("div"); this.modalEl = new El("div"); }
+  open() { Modal.opened.push(this); this.onOpen(); }
+  close() { this.onClose(); }
+}
+Modal.opened = [];
+class Notice { constructor(text) { Notice.shown.push(text); } }
+Notice.shown = [];
+module.exports = { Plugin, ItemView, Modal, Notice, El };
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
new file mode 100644
index 0000000..ee2d319
--- /dev/null
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -0,0 +1,302 @@
+// R-013 the view, against a scratch vault on disk and the fake obsidian module.
+const test = require("node:test");
+const assert = require("node:assert/strict");
+const fs = require("fs");
+const os = require("os");
+const path = require("path");
+const P = require("./load");
+const { Modal } = require("./fake-obsidian");
+
+const MAIN = fs.readFileSync(path.join(__dirname, "..", "main.js"), "utf8");
+const NOW = new Date("2026-10-25T12:00:00Z");
+const ROADMAP = `## 🔥 Now
+- [ ] **R-1** [FEATURE] 待做的事 —— 細節
+- [ ] **R-2** [FEATURE · blocked: 等 API 金鑰] 卡住的事
+- [x] **R-3** [FEATURE · ✅ 2026-10-20 · main \`abc1234\`] 最近做完的事
+    ↳ done when: 畫面上看得到
+    ↳ explain: 給人看的一句話。
+- [ ] **R-4** 正在審查的事
+- [ ] **R-5** 另一件待做
+`;
+function vault(files) {
+  const root = fs.mkdtempSync(path.join(os.tmpdir(), "rv-"));
+  for (const [p, body] of Object.entries(files)) {
+    fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true });
+    fs.writeFileSync(path.join(root, p), body);
+  }
+  return root;
+}
+const D = "10 Projects/demo";
+const MOCK = (t) => `<html><head><style>.x{}</style></head><body><div class="panel now">${t}</div></body></html>`;
+const FILES = {
+  [`${D}/ROADMAP.md`]: ROADMAP,
+  [`${D}/Specs/R-3-did-it.md`]: "spec",
+  [`${D}/Specs/R-30-other.md`]: "not R-3's",
+  [`${D}/Brainstorms/R-3-talk.md`]: "brainstorm",
+  [`${D}/Proposals/mockups/R-2-a-mockup.html`]: MOCK("兩"),
+  [`${D}/Proposals/mockups/R-3-a-mockup.html`]: MOCK("三"),
+  [`${D}/Proposals/mockups/R-4-a-mockup.html`]: MOCK("四"),
+  [`${D}/ship-status/R-4.json`]: JSON.stringify({ id: "R-4", phase: "review", updated: "2026-10-25T09:00:00Z" }),
+  [`${D}/ship-status/R-9.json`]: "{ half-synced",
+  "10 Projects/other/ROADMAP.md": "- [ ] **R-77** 別的專案\n",
+  "10 Projects/no-roadmap/README.md": "x",
+};
+
+function fakeApp(root, leaves = []) {
+  const walk = (d, pre = "") => fs.readdirSync(d, { withFileTypes: true })
+    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name), `${pre}${e.name}/`) : [`${pre}${e.name}`]));
+  const handlers = {};
+  const opened = [];
+  const app = {
+    handlers, opened, failRead: null,
+    vault: {
+      getFiles: () => walk(root).map((p) => ({ path: p })),
+      getAbstractFileByPath: (p) => (fs.existsSync(path.join(root, p)) ? { path: p } : null),
+      on: (ev, f) => { (handlers[ev] = handlers[ev] || []).push(f); return { ev }; },
+      adapter: {
+        read: async (p) => {
+          if (app.failRead && p.endsWith(app.failRead)) throw new Error(`EACCES: ${p}`);
+          return fs.readFileSync(path.join(root, p), "utf8");
+        },
+        list: async (p) => ({ files: fs.readdirSync(path.join(root, p)).map((f) => `${p}/${f}`), folders: [] }),
+        stat: async (p) => { try { return { mtime: fs.statSync(path.join(root, p)).mtimeMs }; } catch { return null; } },
+      },
+    },
+    workspace: {
+      onLayoutReady: (f) => f(),
+      getLeavesOfType: () => leaves,
+      openLinkText: (p, src, newLeaf) => opened.push(["link", p, newLeaf]),
+      getLeaf: () => ({ openFile: async (f, st) => opened.push(["file", f.path, st]) }),
+    },
+  };
+  return app;
+}
+
+async function setup(files = FILES, settings = null) {
+  const app = fakeApp(vault(files));
+  const plugin = new P(app, { id: "roadmap-view" });
+  plugin.stored = settings;
+  plugin.now = () => NOW;
+  await plugin.onload();
+  const leaf = { app };
+  const view = plugin.views["roadmap-view"](leaf);
+  await view.onOpen();
+  return { app, plugin, view };
+}
+const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
+const ids = (el) => el.findAll((e) => e.hasClass("rv-id")).map((e) => e.text);
+const byText = (el, t) => el.findAll((e) => e.text === t)[0];
+
+let observed = [];
+global.IntersectionObserver = class {
+  constructor(cb) { this.cb = cb; }
+  observe(el) { observed.push({ el, io: this }); }
+  unobserve() {}
+  disconnect() {}
+};
+const seen = (o) => o.io.cb([{ isIntersecting: true, target: o.el }]);
+
+test("main.js needs nothing but the obsidian module — the phone has no Node APIs", () => {
+  const reqs = [...MAIN.matchAll(/require\(\s*["']([^"']+)["']\s*\)/g)].map((m) => m[1]);
+  assert.deepEqual(reqs, ["obsidian"]);
+  const man = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"));
+  assert.equal(man.id, "roadmap-view");
+  assert.equal(man.isDesktopOnly, false);
+  assert.equal(man.name, "Roadmap 檢視");
+  assert.ok(fs.statSync(path.join(__dirname, "..", "styles.css")).size > 0);
+});
+
+test("onload registers the view, a ribbon icon and 打開 Roadmap 檢視, with default settings", async () => {
+  const { plugin } = await setup();
+  assert.ok(plugin.views["roadmap-view"]);
+  assert.equal(plugin.ribbons.length, 1);
+  assert.deepEqual(plugin.commands.map((c) => c.name), ["打開 Roadmap 檢視"]);
+  assert.deepEqual(plugin.settings, { projectsDir: "10 Projects", recentDays: 14, project: "" });
+  assert.deepEqual(plugin.events.map((e) => e.ev).sort(), ["create", "delete", "modify", "rename"]);
+});
+
+test("the view never has its own `open` field — it would shadow View.open and blank the pane", async () => {
+  const { view } = await setup();
+  view.contentEl.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
+  await flush();
+  assert.equal(Object.prototype.hasOwnProperty.call(view, "open"), false);
+  assert.equal(view.open(), "View.open");
+});
+
+test("近況: 進行中／卡住, then 最近完成, then 待做 collapsed until tapped", async () => {
+  const { view } = await setup();
+  const root = view.contentEl;
+  const groups = root.findAll((e) => e.hasClass("rv-group")).map((e) => e.text);
+  assert.match(groups[0], /^進行中／卡住 · 2/);
+  assert.match(groups[1], /^最近完成.* · 1/);
+  assert.match(groups[2], /^待做 · 2/);
+  assert.deepEqual(ids(root), ["R-2", "R-4", "R-3"]);
+  assert.ok(root.textContent.includes("審查中"));
+  root.findAll((e) => e.hasClass("rv-group"))[2].fire("click");
+  await flush();
+  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3", "R-1", "R-5"]);
+});
+
+test("the project picker lists folders holding a ROADMAP.md and remembers the pick", async () => {
+  const { view, plugin } = await setup();
+  const sel = view.contentEl.findAll((e) => e.tag === "select")[0];
+  assert.deepEqual(sel.children.map((o) => o.value), ["demo", "other"]);
+  assert.equal(sel.value, "demo");
+  sel.value = "other";
+  sel.fire("change");
+  await flush();
+  assert.equal(plugin.stored.project, "other");
+  assert.equal(plugin.current, "10 Projects/other");
+  view.contentEl.findAll((e) => e.text === "全部")[0].fire("click");
+  await flush();
+  assert.deepEqual(ids(view.contentEl), ["R-77"]);
+});
+
+test("全部 lists every item, and search filters by id, headline and explain", async () => {
+  const { view } = await setup();
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  assert.deepEqual(ids(view.contentEl), ["R-1", "R-2", "R-3", "R-4", "R-5"]);
+  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
+  input.value = "給人看";
+  input.fire("input");
+  await new Promise((r) => setTimeout(r, 250));
+  assert.deepEqual(ids(view.contentEl), ["R-3"]);
+});
+
+test("a card opens its detail page: spec, brainstorm and mockup links, commit, folds; back returns", async () => {
+  const { view, app } = await setup();
+  const card = view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3"));
+  card.fire("click");
+  await flush();
+  const root = view.contentEl;
+  const links = root.findAll((e) => e.hasClass("rv-link")).map((e) => e.text);
+  assert.deepEqual(links, ["spec · Specs/R-3-did-it.md", "brainstorm · Brainstorms/R-3-talk.md",
+    "mockup · Proposals/mockups/R-3-a-mockup.html", "commit abc1234", "在 ROADMAP.md 打開這一行"]);
+  assert.ok(root.textContent.includes("給人看的一句話。"));
+  const folds = root.findAll((e) => e.tag === "summary").map((e) => e.text);
+  assert.deepEqual(folds, ["完成條件", "給 AI 的原文"]);
+  byText(root, "spec · Specs/R-3-did-it.md").fire("click");
+  assert.deepEqual(app.opened.at(-1), ["link", `${D}/Specs/R-3-did-it.md`, true]);
+  byText(root, "在 ROADMAP.md 打開這一行").fire("click");
+  await flush();
+  assert.deepEqual(app.opened.at(-1), ["file", `${D}/ROADMAP.md`, { eState: { line: 3 } }]);
+  byText(root, "← 返回").fire("click");
+  await flush();
+  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3"]);
+});
+
+test("an item with no explain says so faintly", async () => {
+  const { view } = await setup();
+  view.contentEl.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
+  await flush();
+  assert.ok(view.contentEl.textContent.includes("還沒有白話說明"));
+});
+
+test("a failed read shows the error in the pane, never a blank pane", async () => {
+  const { view, app } = await setup();
+  app.failRead = "ROADMAP.md";
+  await view.render();
+  const t = view.contentEl.textContent;
+  assert.ok(t.includes("出錯了") && t.includes("EACCES"), t);
+});
+
+test("no project folder with a ROADMAP.md says so", async () => {
+  const { view } = await setup({ "10 Projects/x/README.md": "x" });
+  assert.ok(view.contentEl.textContent.includes("沒有含 ROADMAP.md 的專案"));
+});
+
+test("thumbnails are lazy, at most 2 render at once, sandboxed with no scripts", async () => {
+  observed = [];
+  const { view } = await setup();
+  assert.equal(observed.length, 3);
+  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 0);
+  observed.forEach(seen);
+  await flush();
+  let frames = view.contentEl.findAll((e) => e.tag === "iframe");
+  assert.equal(frames.length, 2);
+  assert.equal(frames[0].attrs.sandbox, "allow-same-origin");
+  assert.ok(frames[0].attrs.srcdoc.includes('<div class="panel now">兩</div>'));
+  assert.equal(frames[0].style.pointerEvents, "none");
+  frames[0].contentDocument = { body: { scrollHeight: 400 } };
+  frames[0].fire("load");
+  await flush();
+  frames = view.contentEl.findAll((e) => e.tag === "iframe");
+  assert.equal(frames.length, 3);
+  assert.equal(frames[0].style.height, "400px");
+});
+
+test("tapping a thumbnail zooms at 符合寬度 / 2× / 3× and does not open the card", async () => {
+  observed = [];
+  Modal.opened = [];
+  const { view } = await setup();
+  observed.forEach(seen);
+  await flush();
+  const box = view.contentEl.findAll((e) => e.hasClass("rv-thumb"))[0];
+  box.fire("click");
+  assert.equal(view.detail, null);
+  assert.equal(Modal.opened.length, 1);
+  const bar = Modal.opened[0].contentEl.findAll((e) => e.tag === "button").map((b) => b.text);
+  assert.deepEqual(bar, ["符合寬度", "2×", "3×"]);
+  assert.equal(Modal.opened[0].contentEl.findAll((e) => e.tag === "iframe").length, 1);
+});
+
+test("the 現況 is read once per mockup version", async () => {
+  observed = [];
+  const { view, app } = await setup();
+  let reads = 0;
+  const read = app.vault.adapter.read;
+  app.vault.adapter.read = async (p) => { if (p.endsWith(".html")) reads++; return read(p); };
+  observed.forEach(seen);
+  await flush();
+  view.contentEl.findAll((e) => e.tag === "iframe").forEach((f) => f.fire("load"));
+  await flush();
+  const first = reads;
+  observed = [];
+  await view.render();
+  observed.forEach(seen);
+  await flush();
+  assert.equal(first, 3);
+  assert.equal(reads, 3);
+});
+
+test("vault changes under the project re-render once, debounced 500 ms; other paths do not", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });
+  const { plugin, app } = await setup();
+  let n = 0;
+  plugin.refresh = () => { n++; };
+  const fire = (ev, p, old) => app.handlers[ev].forEach((f) => f({ path: p }, old));
+  fire("modify", `${D}/ROADMAP.md`);
+  fire("create", `${D}/ship-status/R-4.json`);
+  fire("rename", "elsewhere.md", `${D}/Specs/R-3-did-it.md`);
+  fire("modify", `${D}/notes.md`);
+  fire("modify", "10 Projects/other/ROADMAP.md");
+  t.mock.timers.tick(499);
+  assert.equal(n, 0);
+  t.mock.timers.tick(1);
+  assert.equal(n, 1);
+  fire("modify", `${D}/notes.md`);
+  fire("delete", `${D}/Proposals/mockup.html`);
+  t.mock.timers.tick(600);
+  assert.equal(n, 1);
+  fire("delete", `${D}/Proposals/mockups/R-2-a-mockup.html`);
+  t.mock.timers.tick(500);
+  assert.equal(n, 2);
+});
+
+test("after a re-render, the old render's thumbnails neither hold nor add slots", async () => {
+  observed = [];
+  const { view } = await setup();
+  observed.forEach(seen);
+  await flush();
+  const old = view.contentEl.findAll((e) => e.tag === "iframe");
+  assert.equal(old.length, 2);
+  observed = [];
+  await view.render();   // the two old iframes are gone from the pane, still loading
+  observed.forEach(seen);
+  await flush();
+  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
+  old.forEach((f) => f.fire("load"));   // finishing late must not let a third one start
+  await flush();
+  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
+});
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 31`, `ℹ pass 16`, `ℹ fail 15` — these fail:
  - `✖ main.js needs nothing but the obsidian module — the phone has no Node APIs`
  - `✖ onload registers the view, a ribbon icon and 打開 Roadmap 檢視, with default settings`
  - `✖ the view never has its own `open` field — it would shadow View.open and blank the pane`
  - `✖ 近況: 進行中／卡住, then 最近完成, then 待做 collapsed until tapped`
  - `✖ the project picker lists folders holding a ROADMAP.md and remembers the pick`
  - `✖ 全部 lists every item, and search filters by id, headline and explain`
  - `✖ a card opens its detail page: spec, brainstorm and mockup links, commit, folds; back returns`
  - `✖ an item with no explain says so faintly`
  - `✖ a failed read shows the error in the pane, never a blank pane`
  - `✖ no project folder with a ROADMAP.md says so`
  - `✖ thumbnails are lazy, at most 2 render at once, sandboxed with no scripts`
  - `✖ tapping a thumbnail zooms at 符合寬度 / 2× / 3× and does not open the card`
  - `✖ the 現況 is read once per mockup version`
  - `✖ vault changes under the project re-render once, debounced 500 ms; other paths do not`
  - `✖ after a re-render, the old render's thumbnails neither hold nor add slots`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index 737546f..d6f475b 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -2,7 +2,7 @@
 // ROADMAP.md stays written for AI; this picks what a person needs and shows it.
 // Plain CommonJS, no build: Obsidian loads this one file. The pure functions are static
 // members of the plugin class so `node --test test/` can reach them.
-const { Plugin } = require("obsidian");
+const { Plugin, ItemView, Modal, Notice } = require("obsidian");
 
 // ---------------------------------------------------------------- parsing (pure)
 
@@ -203,9 +203,381 @@ function currentStateDoc(html) {
 </head><body>${el}</body></html>`;
 }
 
+// ---------------------------------------------------------------- rendering
+
+const VIEW = "roadmap-view";
+const DEFAULTS = { projectsDir: "10 Projects", recentDays: 14, project: "" };
+const WATCHED = ["ROADMAP.md", "Proposals/mockups/", "Specs/", "Brainstorms/", "ship-status/"];
+const W = 1100;          // mockups are laid out at desktop width, then scaled down
+const MAX_THUMBS = 2;    // thumbnails rendering at once
+
+function isWatched(path, projectDir) {
+  if (!path || !projectDir || !path.startsWith(`${projectDir}/`)) return false;
+  const rel = path.slice(projectDir.length + 1);
+  return WATCHED.some((w) => (w.endsWith("/") ? rel.startsWith(w) : rel === w));
+}
+
+// An iframe showing `srcdoc` at width W, scaled by `scale`. No scripts run in it; it is
+// same-origin only so its height can be read. It ignores touches, so its box scrolls.
+function frameIn(box, srcdoc, scale, onHeight) {
+  const frame = box.createEl("iframe");
+  frame.setAttr("srcdoc", srcdoc);
+  frame.setAttr("sandbox", "allow-same-origin");
+  frame.setAttr("scrolling", "no");
+  Object.assign(frame.style, { width: `${W}px`, height: "800px", border: "0", transformOrigin: "0 0",
+    transform: `scale(${scale})`, pointerEvents: "none", background: "#fff" });
+  frame.addEventListener("load", () => {
+    let h = 800;
+    try { h = frame.contentDocument.body.scrollHeight || h; } catch (e) { /* unreadable: keep 800 */ }
+    frame.style.height = `${h}px`;
+    onHeight(h);
+  });
+  return frame;
+}
+
+// Resolves true once drawn, false when it never loaded within 3 s (the box is marked).
+function thumb(box, srcdoc, maxHeight) {
+  return new Promise((resolve) => {
+    const scale = (box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 300) / W;
+    const timer = setTimeout(() => { box.addClass("rv-slow"); resolve(false); }, 3000);
+    frameIn(box, srcdoc, scale, (h) => {
+      box.style.height = `${maxHeight ? Math.min(h * scale, maxHeight) : h * scale}px`;
+      clearTimeout(timer);
+      resolve(true);
+    });
+  });
+}
+
+// Tap a thumbnail: the 現況 full-screen at fit-width / 2× / 3×, scrollable.
+class ZoomModal extends Modal {
+  constructor(app, title, srcdoc) { super(app); this.title = title; this.srcdoc = srcdoc; }
+  onOpen() {
+    this.modalEl.addClass("rv-zoom-modal");
+    this.titleEl.setText(this.title);
+    const bar = this.contentEl.createDiv({ cls: "rv-zoom-bar" });
+    const scroller = this.contentEl.createDiv({ cls: "rv-zoom-scroll" });
+    const draw = (f) => {
+      for (const b of bar.querySelectorAll("button")) b.toggleClass("is-on", b.dataset.f === String(f));
+      scroller.empty();
+      const scale = ((scroller.clientWidth || 340) / W) * f;
+      const inner = scroller.createDiv({ cls: "rv-zoom-inner" });
+      inner.style.width = `${W * scale}px`;
+      frameIn(inner, this.srcdoc, scale, (h) => { inner.style.height = `${h * scale}px`; });
+    };
+    for (const [label, f] of [["符合寬度", 1], ["2×", 2], ["3×", 3]]) {
+      const b = bar.createEl("button", { text: label });
+      b.dataset.f = String(f);
+      b.addEventListener("click", () => draw(f));
+    }
+    draw(1);
+  }
+  onClose() { this.contentEl.empty(); }
+}
+
+class RoadmapView extends ItemView {
+  constructor(leaf, plugin) {
+    super(leaf);
+    this.plugin = plugin;
+    // Never a field named `open`: it shadows View.open and blanks the pane (spike v0.0.2).
+    this.tab = "near";          // near | all
+    this.detail = null;         // id of the item on the detail page
+    this.query = "";
+    this.todoExpanded = false;
+    this.listScroll = 0;
+    this.docs = new Map();      // mockup path → { mtime, doc }
+    this.renders = 0;
+    this.gen = 0;
+    this.resetThumbs();
+  }
+  getViewType() { return VIEW; }
+  getDisplayText() { return "Roadmap 檢視"; }
+  getIcon() { return "layout-list"; }
+  async onOpen() { await this.render(); }
+  async onClose() { this.resetThumbs(); }
+
+  async render() {
+    const n = ++this.renders;
+    const root = this.contentEl;
+    try {
+      const data = await this.load();
+      if (n !== this.renders) return;   // a newer render started meanwhile
+      root.empty();
+      root.addClass("rv");
+      this.resetThumbs();
+      this.draw(root, data);
+    } catch (e) {
+      if (n !== this.renders) return;
+      root.empty();
+      root.addClass("rv");
+      root.createEl("pre", { cls: "rv-err", text: `Roadmap 檢視出錯了：\n${(e && (e.stack || e.message)) || e}` });
+      console.error("roadmap-view", e);
+    }
+  }
+
+  async load() {
+    const s = this.plugin.settings;
+    const adapter = this.app.vault.adapter;
+    const all = this.app.vault.getFiles().map((f) => f.path);
+    const pre = `${s.projectsDir}/`;
+    const projects = all.filter((p) => p.startsWith(pre) && /^[^/]+\/ROADMAP\.md$/.test(p.slice(pre.length)))
+      .map((p) => p.slice(pre.length).split("/")[0]).sort();
+    if (!projects.length) { this.plugin.current = null; return { projects }; }
+    const project = projects.includes(s.project) ? s.project : projects[0];
+    const dir = `${pre}${project}`;
+    this.plugin.current = dir;
+    const items = parseRoadmap(await adapter.read(`${dir}/ROADMAP.md`));
+    const list = async (sub) => { try { return (await adapter.list(`${dir}/${sub}`)).files; } catch (e) { return []; } };
+    const mockups = (await list("Proposals/mockups")).filter((p) => /\.html$/i.test(p)).map((p) => p.slice(dir.length + 1));
+    const phases = {};
+    // ponytail: reads every status file on each render; index them if hundreds get slow
+    await Promise.all((await list("ship-status")).filter((p) => /\/R-[^/]+\.json$/.test(p)).map(async (p) => {
+      try { phases[p.split("/").pop().slice(0, -5)] = JSON.parse(await adapter.read(p)); } catch (e) { /* half-synced: skip */ }
+    }));
+    const now = this.plugin.now();
+    const rows = items.map((item) => ({
+      item, status: statusOf(item, phases[item.id] || null, now, s.recentDays), mockups: mockupsFor(item, items, mockups),
+    }));
+    const docs = all.filter((p) => p.startsWith(`${dir}/Specs/`) || p.startsWith(`${dir}/Brainstorms/`));
+    return { projects, project, dir, rows, docs };
+  }
+
+  draw(root, d) {
+    if (!d.projects.length) {
+      root.createDiv({ cls: "rv-empty", text: `「${this.plugin.settings.projectsDir}」底下沒有含 ROADMAP.md 的專案資料夾` });
+      return;
+    }
+    const bar = root.createDiv({ cls: "rv-bar" });
+    const sel = bar.createEl("select", { cls: "dropdown rv-project" });
+    for (const p of d.projects) sel.createEl("option", { text: p, value: p });
+    sel.value = d.project;
+    sel.addEventListener("change", async () => {
+      this.plugin.settings.project = sel.value;
+      this.detail = null;
+      await this.plugin.saveSettings();
+      await this.render();
+    });
+    const tabs = bar.createDiv({ cls: "rv-tabs" });
+    for (const [k, label] of [["near", "近況"], ["all", "全部"]]) {
+      const b = tabs.createEl("button", { text: label });
+      if (this.tab === k && !this.detail) b.addClass("is-on");
+      b.addEventListener("click", () => { this.tab = k; this.detail = null; this.render(); });
+    }
+    const row = this.detail && d.rows.find((r) => r.item.id === this.detail);
+    if (row) return this.drawDetail(root, d, row);
+    if (this.tab === "all") this.drawAll(root, d);
+    else this.drawNear(root, d);
+    root.scrollTop = this.listScroll;
+  }
+
+  drawNear(root, d) {
+    const groups = [["active", "進行中／卡住"], ["recent", `最近完成（${this.plugin.settings.recentDays} 天內）`], ["todo", "待做"]];
+    for (const [g, label] of groups) {
+      const rows = d.rows.filter((r) => r.status.group === g);
+      if (g === "recent") rows.sort((a, b) => (b.item.done || "").localeCompare(a.item.done || ""));
+      const h = root.createDiv({ cls: "rv-group", text: `${label} · ${rows.length}` });
+      if (g === "todo") {
+        h.addClass("rv-foldable");
+        h.addEventListener("click", () => { this.todoExpanded = !this.todoExpanded; this.render(); });
+        if (!this.todoExpanded) { h.setText(`${label} · ${rows.length}（點開）`); continue; }
+      }
+      if (!rows.length) root.createDiv({ cls: "rv-none", text: "沒有" });
+      for (const r of rows) this.card(root, d, r);
+    }
+  }
+
+  drawAll(root, d) {
+    const input = root.createEl("input", { type: "search", cls: "rv-search", placeholder: "搜尋 id、標題、說明…" });
+    input.value = this.query;
+    const list = root.createDiv();
+    const fill = () => {
+      list.empty();
+      this.resetThumbs();
+      const q = this.query.trim().toLowerCase();
+      const rows = q ? d.rows.filter((r) => [r.item.id, r.item.headline, r.item.explain || "", r.item.tags]
+        .join(" ").toLowerCase().includes(q)) : d.rows;
+      list.createDiv({ cls: "rv-group", text: `${rows.length} 項` });
+      for (const r of rows) this.card(list, d, r);
+    };
+    input.addEventListener("input", () => {
+      this.query = input.value;
+      clearTimeout(this.typing);
+      this.typing = setTimeout(fill, 200);
+    });
+    fill();
+  }
+
+  chips(parent, item, status) {
+    const top = parent.createDiv({ cls: "rv-top" });
+    top.createSpan({ cls: "rv-id", text: item.id });
+    for (const c of status.chips) top.createSpan({ cls: `rv-chip rv-${c.kind}`, text: c.text });
+  }
+
+  card(parent, d, r) {
+    const c = parent.createDiv({ cls: `rv-card rv-g-${r.status.group}` });
+    const left = c.createDiv({ cls: "rv-left" });
+    this.chips(left, r.item, r.status);
+    left.createDiv({ cls: "rv-title", text: r.item.headline });
+    if (r.item.explain) left.createDiv({ cls: "rv-exp", text: r.item.explain });
+    if (r.mockups.length) this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `${d.dir}/${r.mockups[0]}`, r.item.id, 70);
+    else c.addClass("rv-nothumb");
+    c.addEventListener("click", () => {
+      this.listScroll = this.contentEl.scrollTop || 0;
+      this.detail = r.item.id;
+      this.render();
+    });
+  }
+
+  drawDetail(root, d, r) {
+    const { item, status } = r;
+    const back = root.createEl("button", { cls: "rv-back", text: "← 返回" });
+    back.addEventListener("click", () => { this.detail = null; this.render(); });
+    this.chips(root, item, status);
+    root.createDiv({ cls: "rv-title rv-headline", text: item.headline });
+    root.createDiv({ cls: item.explain ? "rv-exp rv-full" : "rv-exp rv-faint", text: item.explain || "還沒有白話說明" });
+    if (r.mockups.length) {
+      root.createDiv({ cls: "rv-lbl", text: "MOCKUP · 現況" });
+      const big = root.createDiv({ cls: "rv-big" });
+      this.enqueue(() => this.drawThumb(big, `${d.dir}/${r.mockups[0]}`, item.id, 0));
+      root.createDiv({ cls: "rv-cap", text: "點圖放大" });
+    }
+    root.createDiv({ cls: "rv-lbl", text: "相關文件" });
+    const links = [
+      ...d.docs.filter((p) => p.startsWith(`${d.dir}/Specs/${item.id}-`)).map((p) => ["spec", p]),
+      ...d.docs.filter((p) => p.startsWith(`${d.dir}/Brainstorms/${item.id}-`)).map((p) => ["brainstorm", p]),
+      ...r.mockups.map((m) => ["mockup", `${d.dir}/${m}`]),
+    ];
+    if (!links.length) root.createDiv({ cls: "rv-faint", text: "沒有相關文件" });
+    for (const [kind, p] of links) {
+      const a = root.createEl("a", { cls: "rv-link", text: `${kind} · ${p.slice(d.dir.length + 1)}` });
+      a.addEventListener("click", (e) => {
+        e.preventDefault();
+        if (kind === "mockup") this.openMockup(p);
+        else this.app.workspace.openLinkText(p, "", true);
+      });
+    }
+    const refs = [item.commit && `commit ${item.commit}`, item.mr && `MR ${item.mr}`].filter(Boolean);
+    if (refs.length) root.createDiv({ cls: "rv-link rv-off", text: refs.join(" · ") });
+    const fold = (title, lines) => {
+      const det = root.createEl("details", { cls: "rv-fold" });
+      det.createEl("summary", { text: title });
+      for (const l of lines) det.createDiv({ cls: "rv-raw", text: l });
+    };
+    if (item.doneWhen.length) fold("完成條件", item.doneWhen);
+    fold("給 AI 的原文", [item.raw, ...item.ann]);
+    const jump = root.createEl("a", { cls: "rv-link", text: "在 ROADMAP.md 打開這一行" });
+    jump.addEventListener("click", async (e) => {
+      e.preventDefault();
+      const f = this.app.vault.getAbstractFileByPath(`${d.dir}/ROADMAP.md`);
+      if (f) await this.app.workspace.getLeaf(true).openFile(f, { eState: { line: item.line } });
+    });
+  }
+
+  openMockup(path) {
+    const f = this.app.vault.getAbstractFileByPath(path);
+    const reg = this.app.viewRegistry;
+    if (f && reg && reg.getTypeByExtension && reg.getTypeByExtension("html")) return this.app.workspace.getLeaf(true).openFile(f);
+    if (this.app.openWithDefaultApp) return this.app.openWithDefaultApp(path);
+    new Notice(`沒有可以打開 HTML 的檢視器：${path}`);
+  }
+
+  // ---- thumbnails: lazy (only cards in view), at most MAX_THUMBS at once, cached per mtime
+
+  resetThumbs() {
+    this.gen++;   // jobs still in flight from an older render no longer hold a slot
+    this.running = 0;
+    this.queue = [];
+    this.jobs = new Map();
+    if (this.io) this.io.disconnect();
+    this.io = null;
+  }
+
+  lazyThumb(box, path, id, maxHeight) {
+    const job = () => this.drawThumb(box, path, id, maxHeight);
+    if (typeof IntersectionObserver === "undefined") { this.enqueue(job); return; }
+    if (!this.io) {
+      this.io = new IntersectionObserver((entries) => {
+        for (const e of entries) {
+          const j = e.isIntersecting && this.jobs.get(e.target);
+          if (!j) continue;
+          this.io.unobserve(e.target);
+          this.jobs.delete(e.target);
+          this.enqueue(j);
+        }
+      }, { rootMargin: "200px" });
+    }
+    this.jobs.set(box, job);
+    this.io.observe(box);
+  }
+
+  enqueue(job) { this.queue.push(job); this.pump(); }
+
+  pump() {
+    while (this.running < MAX_THUMBS && this.queue.length) {
+      const job = this.queue.shift();
+      const gen = this.gen;
+      this.running++;
+      Promise.resolve().then(job).catch((e) => console.error("roadmap-view thumbnail", e))
+        .finally(() => { if (gen === this.gen) { this.running--; this.pump(); } });
+    }
+  }
+
+  async drawThumb(box, path, id, maxHeight) {
+    let doc;
+    try { doc = await this.docFor(path); } catch (e) { box.setText("讀不到 mockup"); return; }
+    if (!doc) { box.setText("沒有現況"); return; }
+    box.addEventListener("click", (e) => {
+      e.stopPropagation();   // a thumbnail tap zooms; it does not open the card
+      new ZoomModal(this.app, `${id} · 現況`, doc).open();
+    });
+    await thumb(box, doc, maxHeight);
+  }
+
+  async docFor(path) {
+    const adapter = this.app.vault.adapter;
+    const st = await adapter.stat(path);
+    if (!st) return null;
+    const hit = this.docs.get(path);
+    if (hit && hit.mtime === st.mtime) return hit.doc;
+    const doc = currentStateDoc(await adapter.read(path));
+    this.docs.set(path, { mtime: st.mtime, doc });
+    return doc;
+  }
+}
+
 // ---------------------------------------------------------------- plugin
 
-class RoadmapViewPlugin extends Plugin {}
+class RoadmapViewPlugin extends Plugin {
+  async onload() {
+    this.settings = Object.assign({}, DEFAULTS, await this.loadData());
+    this.current = null;   // the project dir on screen, set by the view
+    this.registerView(VIEW, (leaf) => new RoadmapView(leaf, this));
+    this.addRibbonIcon("layout-list", "Roadmap 檢視", () => this.activate());
+    this.addCommand({ id: "open", name: "打開 Roadmap 檢視", callback: () => this.activate() });
+    // After layout-ready, so the vault's start-up `create` burst is not replayed at us.
+    this.app.workspace.onLayoutReady(() => {
+      const changed = (f, oldPath) => {
+        if (isWatched(f && f.path, this.current) || isWatched(oldPath, this.current)) this.refreshSoon();
+      };
+      for (const ev of ["modify", "create", "delete", "rename"]) this.registerEvent(this.app.vault.on(ev, changed));
+    });
+  }
+  onunload() { clearTimeout(this.timer); }
+  now() { return new Date(); }
+  async saveSettings() { await this.saveData(this.settings); }
+  refreshSoon() {
+    clearTimeout(this.timer);
+    this.timer = setTimeout(() => this.refresh(), 500);
+  }
+  refresh() {
+    for (const leaf of this.app.workspace.getLeavesOfType(VIEW)) if (leaf.view instanceof RoadmapView) leaf.view.render();
+  }
+  async activate() {
+    const { workspace } = this.app;
+    let leaf = workspace.getLeavesOfType(VIEW)[0];
+    if (!leaf) { leaf = workspace.getLeaf(true); await leaf.setViewState({ type: VIEW, active: true }); }
+    workspace.revealLeaf(leaf);
+  }
+}
 
 Object.assign(RoadmapViewPlugin, { parseRoadmap, mockupsFor, statusOf, currentStateDoc });
 module.exports = RoadmapViewPlugin;
diff --git a/obsidian-roadmap-view/manifest.json b/obsidian-roadmap-view/manifest.json
new file mode 100644
index 0000000..fa5fff1
--- /dev/null
+++ b/obsidian-roadmap-view/manifest.json
@@ -0,0 +1,9 @@
+{
+  "id": "roadmap-view",
+  "name": "Roadmap 檢視",
+  "version": "1.0.0",
+  "minAppVersion": "1.4.0",
+  "description": "一次看一個專案的 ROADMAP 近況：白話標題、狀態、ship-next 階段、mockup 現況縮圖（點擊放大），以及 spec／mockup 連結。只讀，不改 ROADMAP。",
+  "author": "ai_system",
+  "isDesktopOnly": false
+}
diff --git a/obsidian-roadmap-view/styles.css b/obsidian-roadmap-view/styles.css
new file mode 100644
index 0000000..e33aef3
--- /dev/null
+++ b/obsidian-roadmap-view/styles.css
@@ -0,0 +1,53 @@
+/* Roadmap 檢視 (R-013) — phone-first: one column, large tap targets. */
+.rv { padding: 10px; }
+.rv-bar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 10px; }
+.rv-project { max-width: 100%; }
+.rv-tabs { display: flex; gap: 4px; }
+.rv-tabs button.is-on, .rv-zoom-bar button.is-on { background: var(--interactive-accent); color: var(--text-on-accent); }
+.rv-group { font-size: 12px; font-weight: 700; color: var(--text-muted); margin: 14px 0 6px; }
+.rv-foldable { cursor: pointer; }
+.rv-none, .rv-faint { color: var(--text-faint); font-size: 12px; }
+.rv-empty { color: var(--text-muted); padding: 20px 0; }
+.rv-search { width: 100%; margin-bottom: 4px; }
+.rv-card { display: grid; grid-template-columns: 1fr 96px; gap: 10px; padding: 10px; margin-bottom: 8px;
+  border-radius: 10px; background: var(--background-secondary); border: 1px solid var(--background-modifier-border);
+  cursor: pointer; }
+.rv-card.rv-nothumb { grid-template-columns: 1fr; }
+.rv-card.rv-g-active { border-color: var(--interactive-accent); }
+.rv-left { min-width: 0; }
+.rv-top { display: flex; gap: 5px; flex-wrap: wrap; align-items: center; }
+.rv-id { font-family: var(--font-monospace); font-size: 11px; font-weight: 700; color: var(--interactive-accent); }
+.rv-chip { font-size: 10px; font-weight: 700; padding: 0 6px; border-radius: 999px; border: 1px solid currentColor; }
+.rv-done { color: var(--color-green); }
+.rv-wait { color: var(--color-yellow); }
+.rv-pick { color: var(--color-purple); }
+.rv-blocked { color: var(--color-red); }
+.rv-phase { color: var(--color-blue); }
+.rv-epic { color: var(--text-muted); }
+.rv-title { font-weight: 600; margin-top: 4px; line-height: 1.4;
+  display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
+.rv-exp { color: var(--text-muted); font-size: 12px; margin-top: 3px;
+  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
+.rv-headline, .rv-full { display: block; -webkit-line-clamp: unset; }
+.rv-headline { font-size: 16px; }
+.rv-thumb { width: 96px; height: 70px; overflow: hidden; border-radius: 6px; background: #fff;
+  border: 1px solid var(--background-modifier-border); font-size: 10px; color: var(--text-faint); cursor: zoom-in; }
+.rv-big { width: 100%; overflow: hidden; border-radius: 8px; background: #fff;
+  border: 1px solid var(--background-modifier-border); cursor: zoom-in; }
+.rv-slow { outline: 2px dashed var(--color-yellow); }
+.rv-back { margin-bottom: 10px; }
+.rv-lbl { font-size: 10.5px; font-weight: 700; color: var(--text-faint); letter-spacing: .04em; margin: 14px 0 5px; }
+.rv-cap { font-size: 10.5px; color: var(--text-faint); margin-top: 4px; }
+.rv-link { display: block; padding: 9px 10px; margin-bottom: 6px; border-radius: 8px; font-size: 12px;
+  background: var(--background-secondary); border: 1px solid var(--background-modifier-border); word-break: break-all; }
+.rv-off { opacity: .6; }
+.rv-fold { margin: 8px 0; font-size: 12px; }
+.rv-fold summary { cursor: pointer; padding: 6px 0; font-weight: 600; }
+.rv-raw { white-space: pre-wrap; word-break: break-all; color: var(--text-muted); margin: 4px 0; font-size: 11px; }
+.rv-err { white-space: pre-wrap; font-size: 10.5px; color: var(--text-error);
+  background: var(--background-secondary); padding: 8px; border-radius: 6px; }
+.rv-zoom-modal { width: 96vw; max-width: 96vw; height: 92vh; max-height: 92vh; }
+.rv-zoom-bar { display: flex; gap: 6px; margin-bottom: 8px; }
+.rv-zoom-scroll { overflow: auto; -webkit-overflow-scrolling: touch; height: calc(92vh - 120px);
+  background: #fff; border-radius: 8px; border: 1px solid var(--background-modifier-border); }
+.rv-zoom-inner { overflow: hidden; }
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 31`, `ℹ pass 31`, `ℹ fail 0`.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/manifest.json obsidian-roadmap-view/styles.css obsidian-roadmap-view/test/fake-obsidian.js obsidian-roadmap-view/test/view.test.js
git commit -m "feat(roadmap-view): R-013 Task 4 — the Roadmap 檢視 view: 近況/全部, detail, lazy zoomable thumbnails"
```

### Task 5: `sync.sh restore` copies the plugin into the vault; `status` reports it

Seam: `sync.sh restore` (plugin) / `sync.sh status` (plugin)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.7, G7, AC-8. Obsidian Sync carries real files only, so the three files are copied, not linked, into `<airos_vault>/.obsidian/plugins/roadmap-view/` — only when they differ. It never enables the plugin, never touches another plugin or this one's `data.json`, and skips a folder that is not an Obsidian vault. `status` adds one `obsidian plugin:` line that never changes the exit code.

**Files:**
- Modify: `claude-skills/ship-workflow/tests/test_sync-install.bats`
- Modify: `sync.sh`

**Interfaces:**
- Consumes: Task 4's three plugin files; `airos-binding.sh vault`.
- Produces: `./sync.sh restore` installs the plugin (rollout step 2).

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_sync-install.bats b/claude-skills/ship-workflow/tests/test_sync-install.bats
index 5ac88e7..c438430 100644
--- a/claude-skills/ship-workflow/tests/test_sync-install.bats
+++ b/claude-skills/ship-workflow/tests/test_sync-install.bats
@@ -165,3 +165,85 @@ make_checkout() {  # turn $R into a git checkout on branch $1
   [ "$status" -eq 1 ] || return 1
   [[ "$output" == *"code-review-skill"*"target missing"* ]]
 }
+
+# --- R-013: restore copies the Roadmap 檢視 plugin into the vault -------------------
+
+# plugin_fixture — the repo's plugin files, sync.sh's vault lookup, and a vault with
+# another plugin and an Obsidian config.
+plugin_fixture() {
+  mkdir -p "$R/obsidian-roadmap-view" "$R/claude-skills/ship-workflow/lib"
+  cp "$SHIP_LIB/airos-binding.sh" "$R/claude-skills/ship-workflow/lib/"
+  for f in manifest.json main.js styles.css; do echo "repo $f" > "$R/obsidian-roadmap-view/$f"; done
+  echo "a test" > "$R/obsidian-roadmap-view/notes.md"   # not one of the three
+  V="$SCRATCH/vault"; export V
+  P="$V/.obsidian/plugins/roadmap-view"; export P
+  mkdir -p "$V/.obsidian/plugins/other"
+  echo other > "$V/.obsidian/plugins/other/main.js"
+  write_global_config "$HOME" "$V"
+}
+
+@test "restore copies the three plugin files into the vault, then changes nothing; other plugins untouched" {
+  plugin_fixture
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  for f in manifest.json main.js styles.css; do cmp -s "$R/obsidian-roadmap-view/$f" "$P/$f" || { echo "$f"; return 1; }; done
+  [ "$(ls "$P" | tr '\n' ' ')" = "main.js manifest.json styles.css " ]
+  [ ! -L "$P" ] && [ ! -L "$P/main.js" ]
+  [[ "$output" == *"Roadmap 檢視"* ]] || return 1
+  touch -t 200001010000 "$P"/* && touch -t 200101010000 "$SCRATCH/ref"
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || return 1
+  [ -z "$(find "$P" -type f -newer "$SCRATCH/ref")" ] || { echo "rewrote an up-to-date copy"; return 1; }
+  [[ "$output" != *"copied the Obsidian plugin"* ]] || return 1
+  [ "$(cat "$V/.obsidian/plugins/other/main.js")" = other ]
+  [ "$(cat "$V/.obsidian/community-plugins.json" 2>/dev/null)" = "" ]   # never enabled for you
+}
+
+@test "restore updates an out-of-date copy in place and keeps the plugin's own settings" {
+  plugin_fixture
+  mkdir -p "$P"
+  echo "old main" > "$P/main.js"
+  echo '{"project":"x"}' > "$P/data.json"
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [ "$(cat "$P/main.js")" = "repo main.js" ]
+  [ "$(cat "$P/data.json")" = '{"project":"x"}' ]
+  [ -z "$(ls -A "$HOME/.claude/.ai_system-displaced" 2>/dev/null | grep roadmap)" ]
+}
+
+@test "restore without a configured vault, or with a folder that is not an Obsidian vault, skips the plugin" {
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || return 1
+  [[ "$output" == *"skip: Obsidian plugin"* ]] || { echo "$output"; return 1; }
+  plugin_fixture
+  rm -rf "$V/.obsidian"
+  run bash "$R/sync.sh" restore --yes
+  [ "$status" -eq 0 ] || return 1
+  [[ "$output" == *"skip: Obsidian plugin"* ]] || return 1
+  [ ! -e "$V/.obsidian" ]
+}
+
+@test "restore --dry-run names the plugin copy and copies nothing" {
+  plugin_fixture
+  run bash "$R/sync.sh" restore --dry-run
+  [ "$status" -eq 0 ] || return 1
+  [[ "$output" == *"would copy the Obsidian plugin into $P"* ]] || { echo "$output"; return 1; }
+  [ ! -e "$P" ]
+}
+
+@test "status prints one obsidian plugin line; its state never changes the exit code" {
+  run bash "$R/sync.sh" status
+  [[ "$output" == *"obsidian plugin: no vault"* ]] || { echo "$output"; return 1; }
+  plugin_fixture
+  bash "$R/sync.sh" restore --yes >/dev/null
+  run bash "$R/sync.sh" status
+  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
+  [ "$(grep -c '^obsidian plugin:' <<<"$output")" -eq 1 ]
+  [[ "$output" == *"obsidian plugin: up to date"* ]] || return 1
+  echo changed > "$P/styles.css"
+  run bash "$R/sync.sh" status
+  [ "$status" -eq 0 ] && [[ "$output" == *"obsidian plugin: out of date"* ]] || { echo "$output"; return 1; }
+  rm -rf "$P"
+  run bash "$R/sync.sh" status
+  [ "$status" -eq 0 ] && [[ "$output" == *"obsidian plugin: not installed"* ]] || { echo "$output"; return 1; }
+}
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_sync-install.bats tests/test_sync.bats; cd - >/dev/null`

Expected: `1..27`, 22 ok, these 5 fail:
  - `not ok 13 restore copies the three plugin files into the vault, then changes nothing; other plugins untouched`
  - `not ok 14 restore updates an out-of-date copy in place and keeps the plugin's own settings`
  - `not ok 15 restore without a configured vault, or with a folder that is not an Obsidian vault, skips the plugin`
  - `not ok 16 restore --dry-run names the plugin copy and copies nothing`
  - `not ok 17 status prints one obsidian plugin line; its state never changes the exit code`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/sync.sh b/sync.sh
index cac015f..43fca27 100755
--- a/sync.sh
+++ b/sync.sh
@@ -3,14 +3,15 @@
 #
 # ai_system is ship-workflow's home (R-004). `restore` links its three skills and
 # ship-workflow's five commands into ~/.claude, so every session runs this checkout;
-# `backup` copies the global CLAUDE.md and the devsync config into the repo.
+# `backup` copies the global CLAUDE.md and the devsync config into the repo. `restore`
+# also copies the Roadmap 檢視 Obsidian plugin (R-013) into the vault.
 #
 # It used to mirror all of ~/.claude/skills with rsync. That mirror drifted: its
 # restore would have reinstalled 40 removed skills, overwritten a newer global
 # CLAUDE.md with an old copy, and replaced the ship-workflow symlink with a copy.
 #
 # Usage:
-#   ./sync.sh restore [--yes] [--dry-run]   links + config files + devsync bootstrap
+#   ./sync.sh restore [--yes] [--dry-run]   links + config files + Obsidian plugin + devsync bootstrap
 #   ./sync.sh backup [--dry-run]             ~/.claude/CLAUDE.md, devsync config -> repo
 #   ./sync.sh status                         link and config state; exit 1 if a link is wrong
 #
@@ -29,6 +30,10 @@ CONFIG_FILES=(
   "$HOME/.config/devsync/config.toml::$SCRIPT_DIR/devsync/config.toml"
 )
 
+# The Roadmap 檢視 plugin: copied, not linked — Obsidian Sync carries real files only.
+PLUGIN_SRC="$SCRIPT_DIR/obsidian-roadmap-view"
+PLUGIN_FILES=(manifest.json main.js styles.css)
+
 if [[ -t 1 ]]; then
   C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
   C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
@@ -153,6 +158,48 @@ restore_configs() {
   done
 }
 
+# plugin_dir — <airos_vault>/.obsidian/plugins/roadmap-view; nothing when no vault is
+# configured or the folder is not an Obsidian vault.
+plugin_dir() {
+  local vault
+  vault=$("$SCRIPT_DIR/claude-skills/ship-workflow/lib/airos-binding.sh" vault 2>/dev/null) || return 0
+  [[ -n "$vault" && -d "$vault/.obsidian" ]] && echo "$vault/.obsidian/plugins/roadmap-view"
+  return 0
+}
+
+# plugin_state <dir> — up to date | out of date | not installed
+plugin_state() {
+  local f
+  [[ -d "$1" ]] || { echo "not installed"; return 0; }
+  for f in "${PLUGIN_FILES[@]}"; do
+    cmp -s "$PLUGIN_SRC/$f" "$1/$f" || { echo "out of date"; return 0; }
+  done
+  echo "up to date"
+}
+
+# Copy the three plugin files when they differ. Never enables the plugin, never touches
+# another plugin or this one's data.json (its settings).
+install_plugin() {
+  local dir f
+  dir=$(plugin_dir)
+  if [[ -z "$dir" ]]; then
+    warn "skip: Obsidian plugin (no airos_vault with a .obsidian folder in ~/.claude/ship-workflow.yml)"
+    return 0
+  fi
+  for f in "${PLUGIN_FILES[@]}"; do
+    [[ -f "$PLUGIN_SRC/$f" ]] || { warn "skip: Obsidian plugin ($PLUGIN_SRC/$f missing)"; return 0; }
+  done
+  [[ "$(plugin_state "$dir")" == "up to date" ]] && return 0
+  if (( DRY )); then log "would copy the Obsidian plugin into $dir"; return 0; fi
+  mkdir -p "$dir"
+  for f in "${PLUGIN_FILES[@]}"; do
+    cmp -s "$PLUGIN_SRC/$f" "$dir/$f" && continue
+    rm -f "$dir/$f"   # a symlink here would be written through, and Sync skips symlinks
+    cp "$PLUGIN_SRC/$f" "$dir/$f"
+  done
+  ok "copied the Obsidian plugin into $dir — enable 「Roadmap 檢視」 once in Obsidian"
+}
+
 devsync_bootstrap() {
   local bootstrap="$SCRIPT_DIR/devsync/bootstrap.sh"
   if (( DRY )) || [[ "${AI_SYSTEM_SKIP_DEVSYNC:-0}" == 1 ]]; then return 0; fi
@@ -197,6 +244,8 @@ cmd_restore() {
   remove_dangling
   info "Config files"
   restore_configs
+  info "Obsidian plugin"
+  install_plugin
   devsync_bootstrap
   if (( DRY )); then ok "Dry run — nothing changed"; else ok "Restore complete"; fi
 }
@@ -237,6 +286,9 @@ cmd_status() {
       log "$live: differs (./sync.sh backup to save it)"
     fi
   done
+  local dir
+  dir=$(plugin_dir)
+  if [[ -n "$dir" ]]; then log "obsidian plugin: $(plugin_state "$dir")"; else log "obsidian plugin: no vault"; fi
   return "$bad"
 }
 
@@ -245,7 +297,8 @@ usage() {
 ${C_BOLD}sync.sh${C_RESET} — install ai_system (ship-workflow + run-plan + code-review-skill)
 
   $(basename "$0") restore [--yes] [--dry-run]  link the skills and commands into ~/.claude,
-                                              restore the config files, run devsync bootstrap
+                                              restore the config files, copy the Obsidian
+                                              plugin into the vault, run devsync bootstrap
   $(basename "$0") backup [--dry-run]           copy ~/.claude/CLAUDE.md and the devsync config here
   $(basename "$0") status                       show link and config state (exit 1 if a link is wrong)
 
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_sync-install.bats tests/test_sync.bats; cd - >/dev/null`

Expected: `1..27`, all 27 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/tests/test_sync-install.bats sync.sh
git commit -m "feat(sync): R-013 Task 5 — restore copies the plugin into the vault; status reports it"
```

### Task 6: One `bats` run covers the plugin's tests; README and repo rules

Seam: repo layout (`test_repo-layout.bats`)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.1, Decisions. `bats tests/` now runs `node --test` too (skipped without node), so the repo has one test command. The repo rules and the README say where the plugin lives, how it is tested and how it is installed.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`
- Modify: `claude-skills/ship-workflow/tests/test_repo-layout.bats`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_repo-layout.bats b/claude-skills/ship-workflow/tests/test_repo-layout.bats
index dadb241..e27482b 100644
--- a/claude-skills/ship-workflow/tests/test_repo-layout.bats
+++ b/claude-skills/ship-workflow/tests/test_repo-layout.bats
@@ -58,3 +58,15 @@ setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }
 @test "the root README shows no ↳ explain line — nothing writes or reads it any more" {
   if grep -n '↳ explain' "$REPO_ROOT/README.md"; then return 1; fi
 }
+
+# R-013: the Roadmap 檢視 plugin is plain JS with node:test, outside claude-skills/.
+@test "the Roadmap view plugin's node tests pass, so one bats run covers them" {
+  command -v node >/dev/null || skip "node not installed"
+  run node --test "$REPO_ROOT/obsidian-roadmap-view/test/"
+  [ "$status" -eq 0 ] || { echo "$output" | tail -30; return 1; }
+}
+
+@test "the repo rules name the plugin's test command and its install" {
+  grep -qF 'node --test obsidian-roadmap-view/test/' "$REPO_ROOT/CLAUDE.md"
+  grep -qF 'Roadmap 檢視' "$REPO_ROOT/README.md"
+}
R013_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..10`, 9 ok, these 1 fail:
  - `not ok 10 the repo rules name the plugin's test command and its install`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_PATCH'
diff --git a/CLAUDE.md b/CLAUDE.md
index 241a49c..74eac11 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -2,7 +2,8 @@
 
 This repo is ship-workflow's home: `claude-skills/` holds `ship-workflow`, plus the two
 skills `/ship-next` needs, `run-plan` and `code-review-skill`, and nothing else (R-004).
-`devsync/` is the separate remote-dev tool; leave it as it is.
+`devsync/` is the separate remote-dev tool; leave it as it is. `obsidian-roadmap-view/` is
+the Roadmap 檢視 Obsidian plugin (R-013): plain JS, no build, no npm dependencies.
 
 ## The main checkout stays on `main`
 
@@ -18,7 +19,10 @@ machine therefore runs whatever this checkout holds, uncommitted edits included.
 
 - Tests: `cd claude-skills/ship-workflow && bats tests/`. In a linked worktree, the
   `cwd-guard: exits 0 when not in a git repo at all` test fails. That failure is
-  pre-existing and known.
+  pre-existing and known. The bats run includes the plugin's tests; alone they are
+  `node --test obsidian-roadmap-view/test/`.
+- `./sync.sh restore` copies the plugin into `<airos_vault>/.obsidian/plugins/roadmap-view/`
+  when it changed. It never enables it: that is a one-time click in Obsidian.
 - After a pull that changes `sync.sh` or the set of directories in `claude-skills/`, run
   `./sync.sh restore`. Then `./sync.sh status` must print `ok` for every link.
 - After editing `~/.claude/CLAUDE.md`, run `./sync.sh backup`. It copies the file to
diff --git a/README.md b/README.md
index 0883fc9..f31333b 100644
--- a/README.md
+++ b/README.md
@@ -28,6 +28,7 @@
 
 - **一行裝好**：換新電腦時，ship-workflow 和它需要的 skill、全域設定一次裝好。
 - **遠端開發**：在公司的 GPU server 上跑程式時，本機寫的 code 會即時同步過去。
+- **手機上看 Roadmap**：Obsidian 外掛「Roadmap 檢視」，一次看一個專案的近況，寫給人看的版本。
 
 ## 2. Quick start
 
@@ -148,6 +149,18 @@ Later → Next → Now     ← 順序由你決定；brainstorm 會建議把太
 | 項目會被逼著變小：brainstorm 會建議拆開太大的項目，拆出來的每一列都必須能驗收 | IDEA 會越積越多：review 自動開的 IDEA 需要定期整理，或標成 `shelved` 擱置 |
 | 問題不會被遺忘：延後處理的 review 問題會變成 IDEA，留在 `docs/ideas/` 等你決定 | 編號在本機分配：兩台機器在 Roadmap 同步之前各自開新項目，可能拿到同一個號碼 |
 
+### 手機上看 Roadmap（Obsidian 外掛「Roadmap 檢視」）
+
+ROADMAP.md 是寫給 AI 看的；這個外掛從裡面挑出人需要的部分，即時顯示，手機優先：
+
+- **近況**：進行中／卡住、最近完成（14 天內）、待做（收合）。**全部**：每一項，可搜尋。
+- 每一項：中文標題、狀態（完成日期、尚未部署、卡住原因、方案）、ship-next 正在哪個階段、mockup 的「現況」縮圖，點了全螢幕放大（符合寬度／2×／3×）。
+- 詳細頁：spec、brainstorm、mockup 的連結，commit／MR，完成條件，給 AI 的原文。
+- 檔案一變就重畫，不用產生。ship-next 每到一個階段就寫 `<專案>/ship-status/<R-NNN>.json`。
+- 只讀：除了自己的設定（`data.json`）不寫任何檔案。
+
+`./sync.sh restore` 會把外掛複製到 vault 的 `.obsidian/plugins/roadmap-view/`，再到 Obsidian 的「第三方外掛」啟用一次。手機靠 Obsidian Sync：要開「同步已安裝的外掛」與「同步其他類型的檔案」（mockup 是 `.html`、狀態是 `.json`）。
+
 ### 遠端開發
 
 ```bash
@@ -188,7 +201,7 @@ devsync stop my-repo   # 結束
 | codex CLI | 第 3 種 executor |
 | `gh` / `glab` | `merge_mode: mr` 開 PR/MR |
 
-測試：`bats claude-skills/ship-workflow/tests/`
+測試：`bats claude-skills/ship-workflow/tests/`（包含 Roadmap 檢視外掛的 `node --test`，需要 Node 22 以上）
 
 ## 6. `/ship-next`
 
R013_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_repo-layout.bats; cd - >/dev/null`

Expected: `1..10`, all 10 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md claude-skills/ship-workflow/tests/test_repo-layout.bats
git commit -m "docs: R-013 Task 6 — bats runs the plugin tests; README and repo rules"
```

### Task 7: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole bats suite** (it includes the plugin's `node --test`)

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..600`, 599 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Run the plugin tests on their own**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 31`, `ℹ fail 0`.

- [ ] **Step 3: Check the plugin's shape**

Run: `ls obsidian-roadmap-view; node -e 'const m=require("./obsidian-roadmap-view/manifest.json"); console.log(m.id, m.isDesktopOnly)'; bash -n sync.sh && echo ok`

Expected: `main.js manifest.json styles.css test`; `roadmap-view false`; `ok`.

- [ ] **Step 4: No commit** — report DONE with the Step 1 and Step 2 counts.
