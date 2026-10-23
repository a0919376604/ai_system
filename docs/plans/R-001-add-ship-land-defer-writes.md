# R-001 Implementation Plan — parallel mr-mode ships stop conflicting; /ship-land works

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `merge_mode: mr`, a review branch writes only paths that carry its own R-NNN, so parallel MRs never conflict; `/ship-land` folds the one deferred shared file (`CONTEXT.md`) onto the base branch after the merge.

**Architecture:** Two new bash libs (`lib/ship-log.sh`, `lib/ship-land.sh`) and additions to three existing ones (`tdd-rules.sh`, `context-md.sh`, `test-budget.sh`) carry all the logic, each behind a bats-tested seam. The command markdown files only call those functions. `_log.md` rows become `Ship-Log:` commit trailers on review branches, TDD rules become per-ship fragments, `CONTEXT.md` entries are queued per ship and folded by `/ship-land`.

**Tech Stack:** bash + zsh-compatible shell, git ≥ 2.38 (`merge-tree --write-tree`, `%(trailers:key=…)`), bats 1.13, awk.

**Spec:** `docs/specs/R-001-add-ship-land-defer-writes.md` — read it before Task 1.

## Global Constraints

- **Scope.** Every file you edit is under `claude-skills/ship-workflow/` in THIS repository. That directory is this repo's product code — it is not agent configuration — so the usual "ignore `.claude/skills/`" rule does not apply to it. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/`, or the operator's home directory.
- **Working directory.** Run every command in this plan from the repository (worktree) root unless the step says otherwise. Each `git apply` patch uses repo-root-relative paths.
- **Patches are the code.** Each code step is a `git apply` heredoc. The patches were generated from, and replayed against, this exact base commit; they apply cleanly in order. If one does not apply, STOP — do not hand-edit around it.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. They are rendered by Phase 5 into the worktree root. If a file is absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 10.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change (its scratch dir lives inside the repo). It is not yours to fix and must stay the ONLY failure.
- **bats hygiene** (enforced by `tests/test_suite-hygiene.bats`): a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity** (enforced by tests): no `local` inside a loop body; no unquoted globs that may match nothing (use `find`); helpers must print the same output under bash and zsh.
- **Commits.** One commit per task with the exact message given. Never amend, never push, never switch branches.
- **`/ship-next` from a task:** never needed in this plan. If you think you need it, STOP.

## Review Focus

Inputs the spec implies that a person will hit; each now has a test in the owning task:

1. `ship_log` called from a subdirectory (e.g. a command run in `docs/`): `merge_mode` reads `.claude/ship-config.yml` relative to the cwd, so `ship_log_defers` must resolve the repo root first. → Task 1, "defers from a subdirectory too".
2. A CONTEXT term containing regex metacharacters (`C++ (v2)`): replacement must match the term literally, not as a pattern, and must not clobber a shorter term (`C`). → Task 4, "terms with regex characters match literally".
3. A pending entry with indented continuation lines replacing an entry that has its own: neither the old continuation lines nor a duplicate entry may survive. → Task 4, two tests.
4. Another push reaching `origin/<base>` between `land_context`'s fetch and push: the land must redo the fold on the new tip, not fail or rebase. → Task 6, "redoes the fold when another push wins the race" (plus the cap test).
5. `/ship-land` run from inside the ship's worktree: step 5 would try to remove the worktree it is standing in. → Task 9, "refuses to run from inside a worktree".

---

### Task 1: `ship_log` — the single writer of `_log.md` rows

Seam: `ship_log`, `ship_log_ratio_count`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Create: `claude-skills/ship-workflow/lib/ship-log.sh`
- Test: `claude-skills/ship-workflow/tests/test_ship-log.bats` (new)

**Interfaces:**
- Consumes: `merge_mode` from `lib/merge-mode.sh` (existing; sourced by ship-log.sh itself if not already defined).
- Produces: `ship_log "<row>"` (exit 0; exit 2 on empty row / outside git) · `ship_log_defers` (exit 0 = mr mode on a `ship/*` branch) · `ship_log_ratio_count` → integer on stdout · `SHIP_LOG_REL="docs/learnings/_log.md"`.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-log.bats b/claude-skills/ship-workflow/tests/test_ship-log.bats
new file mode 100644
index 0000000..930b41f
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_ship-log.bats
@@ -0,0 +1,88 @@
+#!/usr/bin/env bats
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch ship-log)"
+  mkdir -p "$SCRATCH/repo/docs/learnings" "$SCRATCH/repo/.claude"
+  cd "$SCRATCH/repo"
+  git init -q -b main
+  git config user.email t@t
+  git config user.name t
+  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
+  git add -A && git commit -q -m base
+  source "$SHIP_LIB/ship-log.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+mr_mode() { echo 'merge_mode: mr' > .claude/ship-config.yml; }
+
+@test "ship_log: squash mode appends the row and makes no commit" {
+  before=$(git rev-parse HEAD)
+  ship_log "| d | ship-next | R-1 | shipped | n |"
+  [ "$(tail -1 docs/learnings/_log.md)" = "| d | ship-next | R-1 | shipped | n |" ]
+  [ "$(git rev-parse HEAD)" = "$before" ]
+}
+
+@test "ship_log: mr mode on a ship/* branch makes one empty commit with a Ship-Log trailer" {
+  mr_mode
+  git checkout -q -b ship/R-1-demo
+  before=$(git rev-parse HEAD)
+  cp docs/learnings/_log.md "$BATS_TEST_TMPDIR/log.before"
+  ship_log "| d | ship-next | R-1 | shipped | n |"
+  [ "$(git rev-list --count "$before"..HEAD)" -eq 1 ]
+  [ -z "$(git diff --name-only "$before" HEAD)" ] || { echo "the log commit changed files"; return 1; }
+  cmp -s docs/learnings/_log.md "$BATS_TEST_TMPDIR/log.before" || { echo "_log.md was written"; return 1; }
+  [ "$(git log -1 --format='%(trailers:key=Ship-Log,valueonly)' | sed '/^$/d')" = "| d | ship-next | R-1 | shipped | n |" ]
+  [ "$(git log -1 --format=%s)" = "log: ship-next R-1" ]
+}
+
+@test "ship_log: mr mode on the base branch still appends" {
+  mr_mode
+  before=$(git rev-parse HEAD)
+  ship_log "| d | ship-idea | IDEA-9 | x | n |"
+  [ "$(tail -1 docs/learnings/_log.md)" = "| d | ship-idea | IDEA-9 | x | n |" ]
+  [ "$(git rev-parse HEAD)" = "$before" ]
+}
+
+@test "ship_log: defers from a subdirectory too" {
+  # merge_mode reads .claude/ship-config.yml relative to the working directory.
+  mr_mode
+  git checkout -q -b ship/R-1-demo
+  mkdir -p deep/dir && cd deep/dir
+  before=$(git rev-parse HEAD)
+  ship_log "| d | ship-idea | IDEA-1 | x | n |"
+  [ "$(git rev-list --count "$before"..HEAD)" -eq 1 ]
+}
+
+@test "ship_log: refuses an empty row" {
+  run ship_log ""
+  [ "$status" -eq 2 ]
+}
+
+@test "ship_log_ratio_count: counts file rows and trailers together" {
+  printf '| d | ship-next | R-1 | shipped (ratio 1bp vs baseline 1bp) | n |\n' >> docs/learnings/_log.md
+  git commit -q -am "row"
+  mr_mode
+  git checkout -q -b ship/R-2-demo
+  ship_log "| d | ship-next | R-2 | shipped (ratio 2bp vs baseline 1bp) | n |"
+  ship_log "| d | ship-compound | R-2 | in-review | n |"
+  run ship_log_ratio_count
+  [ "$output" = "2" ]
+}
+
+@test "ship_log_ratio_count: 0 in a repo with no commits and no log" {
+  rm -rf "$SCRATCH/empty" && mkdir -p "$SCRATCH/empty" && cd "$SCRATCH/empty" && git init -q
+  run ship_log_ratio_count
+  [ "$output" = "0" ]
+}
+
+@test "zsh: ship_log behaves the same as in bash" {
+  command -v zsh >/dev/null || skip "zsh not installed"
+  mr_mode
+  git checkout -q -b ship/R-3-demo
+  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/ship-log.sh'; ship_log '| d | ship-next | R-3 | shipped | n |' && ship_log_ratio_count"
+  [ "$status" -eq 0 ]
+  [ "$output" = "0" ]
+  [ "$(git log -1 --format=%s)" = "log: ship-next R-3" ]
+}
+
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-log.bats; cd - >/dev/null`

Expected: `1..8`, 0 ok, these 8 fail:
  - `not ok 1 ship_log: squash mode appends the row and makes no commit`
  - `not ok 2 ship_log: mr mode on a ship/* branch makes one empty commit with a Ship-Log trailer`
  - `not ok 3 ship_log: mr mode on the base branch still appends`
  - `not ok 4 ship_log: defers from a subdirectory too`
  - `not ok 5 ship_log: refuses an empty row`
  - `not ok 6 ship_log_ratio_count: counts file rows and trailers together`
  - `not ok 7 ship_log_ratio_count: 0 in a repo with no commits and no log`
  - `not ok 8 zsh: ship_log behaves the same as in bash`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/ship-log.sh b/claude-skills/ship-workflow/lib/ship-log.sh
new file mode 100644
index 0000000..74aee91
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/ship-log.sh
@@ -0,0 +1,63 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/ship-log.sh
+# The single writer of docs/learnings/_log.md rows.
+#
+# In merge_mode=mr every ship appended its row to the same file on its review
+# branch, so whenever one MR merged, every other open MR conflicted on the
+# file's tail (langlive !285–!288, 2026-10-14). On a review branch the row now
+# travels as a `Ship-Log:` commit trailer instead: it reaches the base
+# branch's history with the MR and touches no shared file. Everywhere else —
+# squash mode, or on the base branch — it is appended to the file as before.
+
+SHIP_LOG_REL="docs/learnings/_log.md"
+
+command -v merge_mode >/dev/null 2>&1 \
+  || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
+
+# ship_log_defers — exit 0 when a row must become a trailer, not a line:
+# merge_mode is mr AND the current branch is a ship/* review branch.
+ship_log_defers() {
+  local root mode branch
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
+  mode=$(cd "$root" && merge_mode 2>/dev/null)
+  [ "$mode" = "mr" ] || return 1
+  branch=$(git branch --show-current 2>/dev/null)
+  case "$branch" in
+    ship/*) return 0 ;;
+    *)      return 1 ;;
+  esac
+}
+
+# ship_log "<row>" — record one log row. Exit 2 on an empty row or outside git.
+ship_log() {
+  local row="$1" root subject
+  [ -n "$row" ] || { echo "ship_log: empty row" >&2; return 2; }
+  root=$(git rev-parse --show-toplevel 2>/dev/null) \
+    || { echo "ship_log: not in a git repo" >&2; return 2; }
+  if ship_log_defers; then
+    subject=$(printf '%s\n' "$row" | awk -F'|' '{
+      c=$3; i=$4
+      gsub(/^[ \t]+|[ \t]+$/, "", c); gsub(/^[ \t]+|[ \t]+$/, "", i)
+      print "log: " c " " i }')
+    git commit --allow-empty -q -m "$subject" -m "Ship-Log: $row"
+    return $?
+  fi
+  mkdir -p "$root/docs/learnings"
+  printf '%s\n' "$row" >> "$root/$SHIP_LOG_REL"
+}
+
+# ship_log_ratio_count — how many ships recorded a test ratio: `ratio ` rows in
+# the file plus `ratio ` Ship-Log trailers reachable from HEAD.
+ship_log_ratio_count() {
+  local root f t
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 0; return 0; }
+  f=0
+  if [ -f "$root/$SHIP_LOG_REL" ]; then
+    f=$(grep -cF "ratio " "$root/$SHIP_LOG_REL" 2>/dev/null || true)
+  fi
+  t=$(git log --format='%(trailers:key=Ship-Log,valueonly)' HEAD 2>/dev/null \
+      | grep -cF "ratio " || true)
+  f=$(printf '%s' "$f" | tr -d '[:space:]')
+  t=$(printf '%s' "$t" | tr -d '[:space:]')
+  echo $(( ${f:-0} + ${t:-0} ))
+}
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-log.bats; cd - >/dev/null`

Expected: `1..8`, all 8 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-log): Task 1 — ship_log turns _log.md rows into Ship-Log trailers on mr review branches"
```

### Task 2: Shadow-mode count includes `Ship-Log` trailers

Seam: `tb_shadow_active`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/test-budget.sh` (header comment; source ship-log.sh; `tb_shadow_active`)
- Test: `claude-skills/ship-workflow/tests/test_test-budget.bats` (append one test)

**Interfaces:**
- Consumes: `ship_log_ratio_count` (Task 1).
- Produces: `tb_shadow_active` — exit 0 while `ship_log_ratio_count` < `TB_SHADOW_SHIPS` (3).

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_test-budget.bats b/claude-skills/ship-workflow/tests/test_test-budget.bats
index 118609c..a597d61 100644
--- a/claude-skills/ship-workflow/tests/test_test-budget.bats
+++ b/claude-skills/ship-workflow/tests/test_test-budget.bats
@@ -144,3 +144,16 @@ seed() {
   [ "$status" -eq 0 ]
 }
 
+
+@test "tb_shadow_active: Ship-Log trailers count, so an mr-only repo leaves shadow mode" {
+  # In merge_mode=mr the ship-next row is a commit trailer, never a file line.
+  # Counting the file alone would keep such a repo in shadow mode forever.
+  i=0; while [ "$i" -lt 3 ]; do
+    git commit -q --allow-empty -m "log: ship-next R-$i" \
+      -m "Ship-Log: | d | ship-next | R-$i | shipped (ratio 1bp vs baseline 1bp) | n |"
+    i=$((i+1))
+  done
+  [ ! -f docs/learnings/_log.md ]
+  run tb_shadow_active
+  [ "$status" -eq 1 ]
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_test-budget.bats; cd - >/dev/null`

Expected: `1..18`, 17 ok, these 1 fail:
  - `not ok 18 tb_shadow_active: Ship-Log trailers count, so an mr-only repo leaves shadow mode`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/test-budget.sh b/claude-skills/ship-workflow/lib/test-budget.sh
index 8467d77..bbbed81 100644
--- a/claude-skills/ship-workflow/lib/test-budget.sh
+++ b/claude-skills/ship-workflow/lib/test-budget.sh
@@ -5,13 +5,17 @@
 # compare them without bc. Every function echoes 0 / returns cleanly when
 # it is outside a git repo or has no data.
 #
-# Shadow mode is DERIVED, never stored: it reads how many prior rows in
-# docs/learnings/_log.md already carry a "ratio " field.
+# Shadow mode is DERIVED, never stored: it counts how many prior ships recorded
+# a "ratio " field — rows in docs/learnings/_log.md plus `Ship-Log:` commit
+# trailers (see lib/ship-log.sh).
 
 TB_MAJOR_MULT=2
 TB_BLOCKING_MULT=4
 TB_SHADOW_SHIPS=3
 
+command -v ship_log_ratio_count >/dev/null 2>&1 \
+  || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/ship-log.sh"
+
 # _tb_is_test_path <path> — exit 0 if the path is test code.
 _tb_is_test_path() {
   case "$1" in
@@ -97,15 +101,13 @@ tb_verdict() {
 }
 
 # tb_shadow_active — exit 0 while fewer than TB_SHADOW_SHIPS prior ships
-# recorded a ratio in docs/learnings/_log.md.
+# recorded a ratio. Counts `_log.md` rows AND `Ship-Log:` trailers: in
+# merge_mode=mr the row is a commit trailer, so counting the file alone would
+# keep an mr-only repo in shadow mode forever.
 tb_shadow_active() {
-  local root log n
-  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
-  log="$root/docs/learnings/_log.md"
-  [ -f "$log" ] || return 0
-  n=$(grep -cF "ratio " "$log" 2>/dev/null || true)
-  n=$(echo -n "$n" | tr -d '[:space:]')
-  [ -n "$n" ] || n=0
+  local n
+  git rev-parse --show-toplevel >/dev/null 2>&1 || return 0
+  n=$(ship_log_ratio_count)
   [ "$n" -lt "$TB_SHADOW_SHIPS" ] && return 0
   return 1
 }
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_test-budget.bats; cd - >/dev/null`

Expected: `1..18`, all 18 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(test-budget): Task 2 — shadow-mode count reads Ship-Log trailers too"
```

### Task 3: TDD rules become per-ship fragments

Seam: `tdd_rules_append`, tdd rule readers

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/tdd-rules.sh`
- Test: `claude-skills/ship-workflow/tests/test_tdd-rules.bats` (two tests changed, four added)

**Interfaces:**
- Consumes: nothing new.
- Produces: `TDD_RULES_DIR_REL="docs/tdd-rules.d"` · `tdd_rules_files` (legacy file, then fragments sorted) · `tdd_rules_bullets` · `tdd_rules_append R-NNN "<rule>"` now writes `docs/tdd-rules.d/R-NNN.md` · `tdd_rules_count` / `tdd_rules_unsourced` / `tdd_rules_render` read all rule files. `tdd_rules_path` unchanged.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_tdd-rules.bats b/claude-skills/ship-workflow/tests/test_tdd-rules.bats
index 23ee916..9c65524 100644
--- a/claude-skills/ship-workflow/tests/test_tdd-rules.bats
+++ b/claude-skills/ship-workflow/tests/test_tdd-rules.bats
@@ -93,16 +93,66 @@ mkrules() { printf '%s\n' "$@" > docs/tdd-rules.md; }
   [[ "$output" != *"31"* ]] || { echo "a repo's measurement leaked into the skill"; return 1; }
 }
 
-@test "tdd_rules_append: adds a sourced rule, idempotently" {
+@test "tdd_rules_append: adds a sourced rule to the ship's fragment, idempotently" {
   tdd_rules_append R-042 "Never assert on log output."
   tdd_rules_append R-042 "Never assert on log output."
   run tdd_rules_count
   [ "$output" = "1" ]
-  grep -q '← R-042' docs/tdd-rules.md
+  grep -qxF -- '- Never assert on log output. ← R-042' docs/tdd-rules.d/R-042.md
+  [ ! -f docs/tdd-rules.md ] || { echo "append wrote the shared legacy file"; return 1; }
 }
 
 @test "tdd_rules_append: refuses a rule with no R-NNN" {
   run tdd_rules_append "" "orphan rule"
   [ "$status" -ne 0 ]
   [ ! -f docs/tdd-rules.md ]
+  [ ! -d docs/tdd-rules.d ]
+}
+
+@test "tdd_rules_append: never modifies the legacy file, and dedupes against it" {
+  # Every ship appending to one file is what made parallel MRs conflict.
+  mkrules '- Old rule. ← R-001'
+  cp docs/tdd-rules.md "$BATS_TEST_TMPDIR/legacy.before"
+  tdd_rules_append R-002 "Old rule."
+  [ ! -e docs/tdd-rules.d/R-002.md ] || { echo "duplicated a legacy rule"; return 1; }
+  tdd_rules_append R-002 "New rule."
+  grep -qxF -- '- New rule. ← R-002' docs/tdd-rules.d/R-002.md
+  cmp -s docs/tdd-rules.md "$BATS_TEST_TMPDIR/legacy.before"
+}
+
+@test "tdd rule readers see the legacy file first, then fragments by name" {
+  mkrules '- Legacy. ← R-001'
+  mkdir -p docs/tdd-rules.d
+  printf -- '- Frag B. ← R-003\n' > docs/tdd-rules.d/R-003.md
+  printf -- '- Frag A.\n' > docs/tdd-rules.d/R-002.md
+  run tdd_rules_count
+  [ "$output" = "3" ]
+  run tdd_rules_unsourced
+  [ "$output" = "- Frag A." ]
+  printf '## Seams\n| a | b | c |\n' > spec.md
+  run tdd_rules_render R-123 spec.md
+  l=$(echo "$output" | grep -n -- '- Legacy.' | cut -d: -f1)
+  a=$(echo "$output" | grep -n -- '- Frag A.' | cut -d: -f1)
+  b=$(echo "$output" | grep -n -- '- Frag B.' | cut -d: -f1)
+  [ -n "$l" ] && [ -n "$a" ] && [ -n "$b" ]
+  [ "$l" -lt "$a" ] && [ "$a" -lt "$b" ]
+}
+
+@test "tdd_rules_render: a repo with only the legacy file renders exactly as before" {
+  mkrules '# Learned TDD rules' '' '- One. ← R-001' '- Two. ← R-002'
+  printf '## Seams\n| a | b | c |\n' > spec.md
+  run tdd_rules_render R-123 spec.md
+  learned=$(echo "$output" | sed -n '/^## Learned in this repo$/,/^## Declared seams$/p')
+  expected=$(printf '%s\n' '## Learned in this repo' '- One. ← R-001' '- Two. ← R-002' '' '## Declared seams')
+  [ "$learned" = "$expected" ]
+}
+
+@test "zsh: rule readers work with and without a fragment directory" {
+  command -v zsh >/dev/null || skip "zsh not installed"
+  mkrules '- Legacy. ← R-001'
+  run zsh -c "source '$SHIP_LIB/tdd-rules.sh'; tdd_rules_count"
+  [ "$output" = "1" ]
+  mkdir -p docs/tdd-rules.d
+  run zsh -c "source '$SHIP_LIB/tdd-rules.sh'; tdd_rules_count"
+  [ "$output" = "1" ]
 }
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_tdd-rules.bats tests/test_ship-next-context-wiring.bats tests/test_ship-next-test-churn.bats; cd - >/dev/null`

Expected: `1..29`, 26 ok, these 3 fail:
  - `not ok 11 tdd_rules_append: adds a sourced rule to the ship's fragment, idempotently`
  - `not ok 13 tdd_rules_append: never modifies the legacy file, and dedupes against it`
  - `not ok 14 tdd rule readers see the legacy file first, then fragments by name`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/tdd-rules.sh b/claude-skills/ship-workflow/lib/tdd-rules.sh
index d688f64..f56a903 100644
--- a/claude-skills/ship-workflow/lib/tdd-rules.sh
+++ b/claude-skills/ship-workflow/lib/tdd-rules.sh
@@ -14,7 +14,10 @@
 # product repo, shipped to every other.
 #
 #   universal  — true everywhere; lives here, in the skill
-#   learned    — this repo's own scars; docs/tdd-rules.md, git-tracked
+#   learned    — this repo's own scars, git-tracked: one fragment per ship in
+#                docs/tdd-rules.d/<R-NNN>.md, plus the legacy docs/tdd-rules.md
+#                if the repo has one. Fragments exist because every ship used to
+#                append to the one file, and parallel MRs conflicted on its tail.
 #   seams      — this ship only; from the spec's ## Seams table
 #
 # Caps exist for the same reason CONTEXT.md has them: rules accumulate and
@@ -23,6 +26,7 @@
 
 TDD_RULES_MAX=20
 TDD_RULES_REL="docs/tdd-rules.md"
+TDD_RULES_DIR_REL="docs/tdd-rules.d"
 
 # tdd_rules_path — echo the repo's learned-rules file, or nothing.
 tdd_rules_path() {
@@ -33,12 +37,33 @@ tdd_rules_path() {
   echo "$root/$TDD_RULES_REL"
 }
 
-# tdd_rules_count — echo how many learned rules, 0 when absent.
+# tdd_rules_files — every learned-rule file: the legacy file first, then the
+# per-ship fragments by name. `find`, not a glob: an unmatched glob is an error
+# in zsh, and these helpers run under the operator's zsh.
+tdd_rules_files() {
+  local root
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
+  [ -n "$root" ] || return 0
+  if [ -f "$root/$TDD_RULES_REL" ]; then echo "$root/$TDD_RULES_REL"; fi
+  if [ -d "$root/$TDD_RULES_DIR_REL" ]; then
+    find "$root/$TDD_RULES_DIR_REL" -maxdepth 1 -type f -name '*.md' | sort
+  fi
+  return 0
+}
+
+# tdd_rules_bullets — every learned rule line (`- ...`), in tdd_rules_files order.
+tdd_rules_bullets() {
+  local f
+  tdd_rules_files | while IFS= read -r f; do
+    grep '^- ' "$f" 2>/dev/null || true
+  done
+  return 0
+}
+
+# tdd_rules_count — echo how many learned rules, 0 when none.
 tdd_rules_count() {
-  local f n
-  f=$(tdd_rules_path)
-  if [ -z "$f" ]; then echo 0; return 0; fi
-  n=$(grep -c '^- ' "$f" || true)
+  local n
+  n=$(tdd_rules_bullets | grep -c '^- ' || true)
   n=$(printf '%s' "$n" | tr -d '[:space:]')
   [ -n "$n" ] || n=0
   echo "$n"
@@ -55,13 +80,13 @@ tdd_rules_over_cap() {
 # Without a source a rule cannot be judged still-relevant, so it can never be
 # pruned. That is how the file silently becomes unprunable.
 tdd_rules_unsourced() {
-  local f
-  f=$(tdd_rules_path)
-  [ -n "$f" ] || return 0
-  grep '^- ' "$f" 2>/dev/null | grep -v '← R-[0-9]' || true
+  tdd_rules_bullets | grep -v '← R-[0-9]' || true
 }
 
-# tdd_rules_append <R-NNN> <rule text> — add a sourced rule. Idempotent.
+# tdd_rules_append <R-NNN> <rule text> — add a sourced rule to this ship's
+# fragment, docs/tdd-rules.d/<R-NNN>.md. Idempotent across every rule file.
+# Never writes the legacy docs/tdd-rules.md: a file every ship appends to is a
+# file every pair of parallel MRs conflicts on.
 tdd_rules_append() {
   local id="$1" text="$2" root f
   case "$id" in
@@ -70,20 +95,9 @@ tdd_rules_append() {
   esac
   [ -n "$text" ] || { echo "tdd_rules_append: empty rule" >&2; return 2; }
   root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
-  f="$root/$TDD_RULES_REL"
+  tdd_rules_bullets | grep -qF -- "$text" && return 0
+  f="$root/$TDD_RULES_DIR_REL/$id.md"
   mkdir -p "$(dirname "$f")" || return 2
-  if [ ! -f "$f" ]; then
-    {
-      echo "# Learned TDD rules"
-      echo
-      echo "Rules this repo earned the hard way. Rendered into \`.ship/tdd-rules.md\`"
-      echo "for every Phase 5 executor, after the universal rules and before this"
-      echo "ship's seams. Every rule carries the R-NNN that produced it, so an old"
-      echo "one can be judged and dropped."
-      echo
-    } > "$f"
-  fi
-  grep -qF -- "$text" "$f" && return 0
   printf -- '- %s ← %s\n' "$text" "$id" >> "$f"
 }
 
@@ -100,11 +114,11 @@ tdd_rules_render() {
   echo "5. Assert on behavior at the seam, never on how it is implemented. A test that"
   echo "   must change when the implementation changes, while the behavior did not,"
   echo "   reports churn instead of regressions."
-  learned=$(tdd_rules_path)
-  if [ -n "$learned" ] && [ -s "$learned" ]; then
+  learned=$(tdd_rules_bullets)
+  if [ -n "$learned" ]; then
     echo
     echo "## Learned in this repo"
-    grep '^- ' "$learned" 2>/dev/null || true
+    printf '%s\n' "$learned"
   fi
   echo
   echo "## Declared seams"
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_tdd-rules.bats tests/test_ship-next-context-wiring.bats tests/test_ship-next-test-churn.bats; cd - >/dev/null`

Expected: `1..29`, all 29 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(tdd-rules): Task 3 — new rules go to per-ship fragments; readers see legacy + fragments"
```

### Task 4: Queue and fold `CONTEXT.md` entries

Seam: `context_pending_add`, `context_pending_apply`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/context-md.sh` (append a section)
- Test: `claude-skills/ship-workflow/tests/test_context-pending.bats` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `CONTEXT_PENDING_DIR_REL="docs/ship-pending"` · `context_pending_add R-NNN "<entry>"` → appends to `docs/ship-pending/R-NNN-context.md` (exit 2 on bad ID / malformed entry) · `context_pending_apply R-NNN` → folds into `CONTEXT.md` at repo root, deletes the pending file, echoes the distinct-term count; no pending file = silent no-op.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_context-pending.bats b/claude-skills/ship-workflow/tests/test_context-pending.bats
new file mode 100644
index 0000000..ab8ddec
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_context-pending.bats
@@ -0,0 +1,94 @@
+#!/usr/bin/env bats
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch context-pending)"
+  mkdir -p "$SCRATCH/repo"
+  cd "$SCRATCH/repo"
+  git init -q
+  source "$SHIP_LIB/context-md.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+@test "context_pending_add: queues the entry under the ship's own path and nothing else" {
+  context_pending_add R-7 "- **Lane** — a queue of tickets"
+  [ "$(cat docs/ship-pending/R-7-context.md)" = "- **Lane** — a queue of tickets" ]
+  [ ! -e CONTEXT.md ] || { echo "CONTEXT.md was written"; return 1; }
+}
+
+@test "context_pending_add: refuses a malformed entry" {
+  run context_pending_add R-7 "Lane: a queue"
+  [ "$status" -eq 2 ]
+  [ ! -e docs/ship-pending/R-7-context.md ]
+}
+
+@test "context_pending_add: refuses a missing R-NNN" {
+  run context_pending_add "" "- **Lane** — x"
+  [ "$status" -eq 2 ]
+}
+
+@test "context_pending_apply: replaces a same-term entry with its continuation lines, appends a new term" {
+  printf '%s\n' '# Context' '' '- **Foo** — old text' '  old continuation' '- **Keep** — untouched' > CONTEXT.md
+  context_pending_add R-7 "- **Foo** — new text"
+  context_pending_add R-7 "- **Bar** — brand new"
+  run context_pending_apply R-7
+  [ "$status" -eq 0 ]
+  [ "$output" = "2" ]
+  expected=$(printf '%s\n' '# Context' '' '- **Foo** — new text' '- **Keep** — untouched' '- **Bar** — brand new')
+  [ "$(cat CONTEXT.md)" = "$expected" ]
+  [ ! -e docs/ship-pending/R-7-context.md ] || { echo "pending file survived"; return 1; }
+}
+
+@test "context_pending_apply: a pending entry keeps its own continuation lines" {
+  printf '%s\n' '- **Foo** — old' > CONTEXT.md
+  printf '%s\n' '- **Foo** — new' '  second line' > "$BATS_TEST_TMPDIR/entry"
+  context_pending_add R-7 "$(cat "$BATS_TEST_TMPDIR/entry")"
+  context_pending_apply R-7 >/dev/null
+  [ "$(cat CONTEXT.md)" = "$(cat "$BATS_TEST_TMPDIR/entry")" ]
+}
+
+@test "context_pending_apply: every term ends up exactly once" {
+  printf '%s\n' '- **Foo** — a' '- **Foo** — duplicate already in file' > CONTEXT.md
+  context_pending_add R-7 "- **Foo** — first queued"
+  context_pending_add R-7 "- **Foo** — last queued wins"
+  context_pending_apply R-7 >/dev/null
+  [ "$(grep -c '^- \*\*Foo\*\*' CONTEXT.md)" -eq 1 ]
+  grep -qxF -- '- **Foo** — last queued wins' CONTEXT.md
+}
+
+@test "context_pending_apply: terms with regex characters match literally" {
+  printf '%s\n' '- **C++ (v2)** — old' '- **C** — unrelated' > CONTEXT.md
+  context_pending_add R-7 "- **C++ (v2)** — new"
+  context_pending_apply R-7 >/dev/null
+  expected=$(printf '%s\n' '- **C++ (v2)** — new' '- **C** — unrelated')
+  [ "$(cat CONTEXT.md)" = "$expected" ]
+}
+
+@test "context_pending_apply: creates CONTEXT.md when the repo has none" {
+  context_pending_add R-7 "- **Lane** — a queue"
+  context_pending_apply R-7 >/dev/null
+  [ "$(cat CONTEXT.md)" = "- **Lane** — a queue" ]
+}
+
+@test "context_pending_apply: no pending file is a silent no-op" {
+  printf '%s\n' '- **Foo** — a' > CONTEXT.md
+  run context_pending_apply R-7
+  [ "$status" -eq 0 ]
+  [ -z "$output" ]
+  [ "$(cat CONTEXT.md)" = "- **Foo** — a" ]
+}
+
+@test "zsh: apply produces the same CONTEXT.md as bash" {
+  command -v zsh >/dev/null || skip "zsh not installed"
+  printf '%s\n' '- **Foo** — old' '  cont' '- **Keep** — k' > CONTEXT.md
+  cp CONTEXT.md "$BATS_TEST_TMPDIR/ctx.orig"
+  context_pending_add R-7 "- **Foo** — new"
+  cp docs/ship-pending/R-7-context.md "$BATS_TEST_TMPDIR/pending"
+  context_pending_apply R-7 >/dev/null
+  cp CONTEXT.md "$BATS_TEST_TMPDIR/ctx.bash"
+  cp "$BATS_TEST_TMPDIR/ctx.orig" CONTEXT.md
+  cp "$BATS_TEST_TMPDIR/pending" docs/ship-pending/R-7-context.md
+  run zsh -c "source '$SHIP_LIB/context-md.sh'; context_pending_apply R-7"
+  [ "$output" = "1" ]
+  cmp -s CONTEXT.md "$BATS_TEST_TMPDIR/ctx.bash"
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-pending.bats tests/test_context-md.bats; cd - >/dev/null`

Expected: `1..22`, 12 ok, these 10 fail:
  - `not ok 1 context_pending_add: queues the entry under the ship's own path and nothing else`
  - `not ok 2 context_pending_add: refuses a malformed entry`
  - `not ok 3 context_pending_add: refuses a missing R-NNN`
  - `not ok 4 context_pending_apply: replaces a same-term entry with its continuation lines, appends a new term`
  - `not ok 5 context_pending_apply: a pending entry keeps its own continuation lines`
  - `not ok 6 context_pending_apply: every term ends up exactly once`
  - `not ok 7 context_pending_apply: terms with regex characters match literally`
  - `not ok 8 context_pending_apply: creates CONTEXT.md when the repo has none`
  - `not ok 9 context_pending_apply: no pending file is a silent no-op`
  - `not ok 10 zsh: apply produces the same CONTEXT.md as bash`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/context-md.sh b/claude-skills/ship-workflow/lib/context-md.sh
index 2aedcb6..5c8d773 100644
--- a/claude-skills/ship-workflow/lib/context-md.sh
+++ b/claude-skills/ship-workflow/lib/context-md.sh
@@ -66,3 +66,73 @@ context_md_orphan_terms() {
         fi
       done
 }
+
+# ── Deferred entries (merge_mode=mr) ─────────────────────────────────────────
+# A review branch must not edit CONTEXT.md: every ship appending or refining it
+# made parallel MRs conflict. In mr mode a ship queues its entries in
+# docs/ship-pending/<R-NNN>-context.md (a path no other ship writes), and
+# /ship-land folds them into CONTEXT.md on the base branch after the MR merges.
+
+CONTEXT_PENDING_DIR_REL="docs/ship-pending"
+
+# context_pending_add <R-NNN> "<entry>" — queue one entry. The entry's first
+# line must be `- **<term>** — <definition>`; indented continuation lines may
+# follow. Exit 2 on a bad ID, a malformed entry, or outside a git repo.
+context_pending_add() {
+  local id="$1" entry="$2" root first
+  case "$id" in
+    R-[0-9]*) : ;;
+    *) echo "context_pending_add: need an R-NNN, got '$id'" >&2; return 2 ;;
+  esac
+  first=$(printf '%s\n' "$entry" | head -1)
+  printf '%s\n' "$first" | grep -qE '^- \*\*[^*]+\*\* — ' \
+    || { echo "context_pending_add: not a '- **term** — definition' entry" >&2; return 2; }
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
+  mkdir -p "$root/$CONTEXT_PENDING_DIR_REL" || return 2
+  printf '%s\n' "$entry" >> "$root/$CONTEXT_PENDING_DIR_REL/$id-context.md"
+}
+
+# context_pending_apply <R-NNN> — fold queued entries into CONTEXT.md at the
+# repo root. A pending term that already exists replaces that entry, including
+# its continuation lines (the following lines that begin with whitespace); a
+# new term is appended. Each term ends up exactly once. Deletes the pending
+# file and echoes how many distinct terms it applied. No pending file: no-op,
+# no output. Does not stage or commit.
+context_pending_apply() {
+  local id="$1" root pending ctx n
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
+  pending="$root/$CONTEXT_PENDING_DIR_REL/$id-context.md"
+  ctx="$root/CONTEXT.md"
+  [ -f "$pending" ] || return 0
+  if [ ! -s "$pending" ]; then rm -f "$pending"; echo 0; return 0; fi
+  [ -f "$ctx" ] || : > "$ctx"
+  n=$(grep -oE '^- \*\*[^*]+\*\*' "$pending" | sort -u | wc -l | tr -d '[:space:]')
+  awk '
+    function term_of(line,   t) { t = line; sub(/^- \*\*/, "", t); sub(/\*\*.*$/, "", t); return t }
+    FNR == NR {
+      if ($0 ~ /^- \*\*[^*]+\*\*/) {
+        cur = term_of($0)
+        if (!(cur in blk)) order[++n] = cur
+        blk[cur] = $0
+        next
+      }
+      if (cur != "" && $0 ~ /^[ \t]/) { blk[cur] = blk[cur] "\n" $0; next }
+      cur = ""
+      next
+    }
+    {
+      if ($0 ~ /^- \*\*[^*]+\*\*/) {
+        t = term_of($0)
+        if (t in done) { skipping = 1; next }
+        if (t in blk) { print blk[t]; done[t] = 1; skipping = 1; next }
+        skipping = 0; print; next
+      }
+      if (skipping && $0 ~ /^[ \t]/) next
+      skipping = 0
+      print
+    }
+    END { for (i = 1; i <= n; i++) if (!(order[i] in done)) print blk[order[i]] }
+  ' "$pending" "$ctx" > "$ctx.tmp" && mv "$ctx.tmp" "$ctx" || return 1
+  rm -f "$pending"
+  echo "$n"
+}
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-pending.bats tests/test_context-md.bats; cd - >/dev/null`

Expected: `1..22`, all 22 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(context-md): Task 4 — queue CONTEXT.md entries per ship and fold them deterministically"
```

### Task 5: Acceptance: parallel mr-mode ships do not conflict

Seam: `ship_log`, `tdd_rules_append`, `context_pending_add` (composition)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Test: `claude-skills/ship-workflow/tests/test_parallel-mr.bats` (new — no production code)

**Interfaces:**
- Consumes: `ship_log` (Task 1), `tdd_rules_append` / `tdd_rules_count` (Task 3), `context_pending_add` / `context_pending_apply` (Task 4).
- Produces: spec AC-A1, AC-A2 (control), AC-A3, AC-D2 as executable tests.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_parallel-mr.bats b/claude-skills/ship-workflow/tests/test_parallel-mr.bats
new file mode 100644
index 0000000..c6a9413
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_parallel-mr.bats
@@ -0,0 +1,86 @@
+#!/usr/bin/env bats
+# R-001 done-when A and D: two merge_mode=mr ships open at once; merging one
+# must leave the other conflict-free, and nothing either recorded may be lost.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch parallel-mr)"
+  mkdir -p "$SCRATCH/repo"
+  cd "$SCRATCH/repo"
+  git init -q -b main
+  git config user.email t@t
+  git config user.name t
+  mkdir -p docs/learnings .claude
+  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
+  printf '%s\n' '# Learned TDD rules' '' '- Seed rule. ← R-000' > docs/tdd-rules.md
+  printf '%s\n' '- **Seed** — a term' > CONTEXT.md
+  echo 'merge_mode: mr' > .claude/ship-config.yml
+  git add -A && git commit -q -m base
+  source "$SHIP_LIB/ship-log.sh"
+  source "$SHIP_LIB/tdd-rules.sh"
+  source "$SHIP_LIB/context-md.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+# What ship-compound step 9 and ship-next Phase 9 do on a review branch.
+ship_new_way() {
+  git checkout -q -b "ship/$1-x" main
+  echo "learning for $1" > "docs/learnings/$1-x.md"
+  tdd_rules_append "$1" "Rule learned in $1."
+  context_pending_add "$1" "- **Term$1** — defined by $1"
+  ship_log "| d | ship-compound | $1 | in-review | n |"
+  git add "docs/learnings/$1-x.md" docs/tdd-rules.d docs/ship-pending
+  git commit -q -m "compound: $1"
+  ship_log "| d | ship-next | $1 | shipped (ratio 1bp vs baseline 1bp) | n |"
+  git checkout -q main
+}
+
+# The pre-R-001 behaviour: every ship appends to the same two files.
+ship_old_way() {
+  git checkout -q -b "old/$1-x" main
+  echo "| d | ship-next | $1 | shipped | n |" >> docs/learnings/_log.md
+  echo "- Rule learned in $1. ← $1" >> docs/tdd-rules.md
+  git add -A && git commit -q -m "old: $1"
+  git checkout -q main
+}
+
+@test "A1: merging one mr-mode ship leaves the other conflict-free" {
+  ship_new_way R-1
+  ship_new_way R-2
+  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
+  run git merge-tree --write-tree main ship/R-2-x
+  [ "$status" -eq 0 ]
+}
+
+@test "A2 (control): the old shared-file appends DO conflict" {
+  # Proves A1 can fail: the same scenario written the old way must conflict.
+  ship_old_way R-1
+  ship_old_way R-2
+  git merge -q --no-ff old/R-1-x -m "Merge R-1"
+  run git merge-tree --write-tree main old/R-2-x
+  [ "$status" -eq 1 ]
+}
+
+@test "D2: both ships' log rows reach main's history, and their rules and terms survive" {
+  ship_new_way R-1
+  ship_new_way R-2
+  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
+  git merge -q --no-ff ship/R-2-x -m "Merge R-2"
+  rows=$(git log --format='%(trailers:key=Ship-Log,valueonly)' main | sed '/^$/d')
+  echo "$rows" | grep -qF '| d | ship-next | R-1 |' || return 1
+  echo "$rows" | grep -qF '| d | ship-next | R-2 |' || return 1
+  [ "$(tdd_rules_count)" -eq 3 ]
+  context_pending_apply R-1 >/dev/null
+  context_pending_apply R-2 >/dev/null
+  grep -qxF -- '- **TermR-1** — defined by R-1' CONTEXT.md
+  grep -qxF -- '- **TermR-2** — defined by R-2' CONTEXT.md
+  grep -qxF -- '- **Seed** — a term' CONTEXT.md
+}
+
+@test "A3: a review branch never writes a shared file" {
+  ship_new_way R-1
+  changed=$(git diff --name-only main...ship/R-1-x)
+  for f in docs/learnings/_log.md docs/tdd-rules.md CONTEXT.md docs/product/ROADMAP.md; do
+    if echo "$changed" | grep -qxF "$f"; then echo "review branch wrote $f"; return 1; fi
+  done
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests**

Run: `cd claude-skills/ship-workflow && bats tests/test_parallel-mr.bats; cd - >/dev/null`

Expected: `1..4`, all 4 ok. These are acceptance tests over Tasks 1, 3 and 4, so they pass immediately — that is allowed. The A2 control test is what proves A1 can fail: it replays the pre-R-001 writes and must report a conflict.

- [ ] **Step 3: (no production code in this task)**

- [ ] **Step 4: (covered by Step 2)**

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "test(parallel-mr): Task 5 — two mr ships merge without conflict; control proves the old way conflicts"
```

### Task 6: `land_is_merged` and `land_context`

Seam: `land_is_merged`, `land_context`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Create: `claude-skills/ship-workflow/lib/ship-land.sh`
- Test: `claude-skills/ship-workflow/tests/test_ship-land-lib.bats` (new)

**Interfaces:**
- Consumes: `context_pending_apply` (Task 4; ship-land.sh sources context-md.sh itself if needed).
- Produces: `land_is_merged <branch> <base-ref>` (exit 0 iff ancestor; 2 on usage) · `land_context R-NNN <base>` → prints `none` or `landed <sha>`; exit 1 on failure or after `LAND_PUSH_ATTEMPTS` (3) rejected pushes; exit 2 on usage.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-land-lib.bats b/claude-skills/ship-workflow/tests/test_ship-land-lib.bats
new file mode 100644
index 0000000..c59d610
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_ship-land-lib.bats
@@ -0,0 +1,100 @@
+#!/usr/bin/env bats
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch ship-land-lib)"
+  cd "$SCRATCH"
+  git init -q --bare -b main origin.git
+  git init -q -b main work
+  cd work
+  git config user.email t@t
+  git config user.name t
+  printf '%s\n' '- **Old** — kept' > CONTEXT.md
+  git add -A && git commit -q -m base
+  git remote add origin "$SCRATCH/origin.git"
+  git push -q origin main
+  source "$SHIP_LIB/ship-land.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+# Put a pending file for $1 on origin/main, as a merged MR would.
+merge_pending() {
+  mkdir -p docs/ship-pending
+  printf '%s\n' "- **Term$1** — from $1" > "docs/ship-pending/$1-context.md"
+  git add -A && git commit -q -m "merge $1" && git push -q origin main
+}
+
+@test "land_is_merged: false for a branch with commits not in base" {
+  git checkout -q -b ship/R-1-x
+  git commit -q --allow-empty -m work
+  git checkout -q main
+  run land_is_merged ship/R-1-x main
+  [ "$status" -ne 0 ]
+}
+
+@test "land_is_merged: true once the branch tip is in base" {
+  git checkout -q -b ship/R-1-x
+  git commit -q --allow-empty -m work
+  git checkout -q main
+  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
+  run land_is_merged ship/R-1-x main
+  [ "$status" -eq 0 ]
+}
+
+@test "land_context: nothing queued prints none and pushes nothing" {
+  before=$(git ls-remote origin refs/heads/main | cut -f1)
+  run land_context R-9 main
+  [ "$status" -eq 0 ]
+  [ "$output" = "none" ]
+  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$before" ]
+}
+
+@test "land_context: folds the queue onto origin in one [skip ci] commit" {
+  merge_pending R-9
+  git checkout -q --detach        # the operator's checkout must not move
+  head_before=$(git rev-parse HEAD)
+  run land_context R-9 main
+  [ "$status" -eq 0 ]
+  [[ "$output" == "landed "* ]] || return 1
+  git fetch -q origin main
+  [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
+  git show origin/main:CONTEXT.md | grep -qxF -- '- **TermR-9** — from R-9'
+  git show origin/main:CONTEXT.md | grep -qxF -- '- **Old** — kept'
+  run git cat-file -e origin/main:docs/ship-pending/R-9-context.md
+  [ "$status" -ne 0 ]
+  [ "$(git rev-parse HEAD)" = "$head_before" ]
+  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
+}
+
+@test "land_context: redoes the fold when another push wins the race" {
+  merge_pending R-9
+  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
+  git -C "$SCRATCH/other" config user.email o@o
+  git -C "$SCRATCH/other" config user.name o
+  # pre-push fires once: someone else lands a commit first, so our push is rejected.
+  cat > .git/hooks/pre-push <<EOF
+#!/bin/sh
+unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
+[ -f "$SCRATCH/raced" ] && exit 0
+touch "$SCRATCH/raced"
+git -C "$SCRATCH/other" commit -q --allow-empty -m concurrent
+git -C "$SCRATCH/other" push -q origin main
+exit 0
+EOF
+  chmod +x .git/hooks/pre-push
+  run land_context R-9 main
+  [ "$status" -eq 0 ]
+  [ -f "$SCRATCH/raced" ] || { echo "the race never happened"; return 1; }
+  git fetch -q origin main
+  git log --format=%s origin/main | grep -qxF concurrent
+  [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
+}
+
+@test "land_context: gives up after the attempt cap" {
+  merge_pending R-9
+  printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-push
+  chmod +x .git/hooks/pre-push
+  run land_context R-9 main
+  [ "$status" -eq 1 ]
+  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land-lib.bats; cd - >/dev/null`

Expected: `1..6`, 0 ok, these 6 fail:
  - `not ok 1 land_is_merged: false for a branch with commits not in base`
  - `not ok 2 land_is_merged: true once the branch tip is in base`
  - `not ok 3 land_context: nothing queued prints none and pushes nothing`
  - `not ok 4 land_context: folds the queue onto origin in one [skip ci] commit`
  - `not ok 5 land_context: redoes the fold when another push wins the race`
  - `not ok 6 land_context: gives up after the attempt cap`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/ship-land.sh b/claude-skills/ship-workflow/lib/ship-land.sh
new file mode 100644
index 0000000..fdeed9c
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/ship-land.sh
@@ -0,0 +1,57 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/ship-land.sh
+# The mechanical half of /ship-land: is the review merged, and fold this
+# ship's deferred CONTEXT.md entries onto the base branch.
+#
+# land_context never touches the operator's checkout. Their base branch is
+# routinely behind origin and sometimes dirty, so it works in a throwaway
+# worktree at origin/<base> and pushes from there. The fold is deterministic,
+# so when a push loses a race it simply redoes the fold on the new tip —
+# there is nothing to rebase and nothing that can conflict.
+
+LAND_PUSH_ATTEMPTS=3
+
+command -v context_pending_apply >/dev/null 2>&1 \
+  || . "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/context-md.sh"
+
+# land_is_merged <branch> <base-ref> — exit 0 iff the branch tip is already in
+# base-ref. Exit 2 on a missing argument.
+land_is_merged() {
+  [ -n "$1" ] && [ -n "$2" ] || return 2
+  git merge-base --is-ancestor "$1" "$2" 2>/dev/null
+}
+
+# land_context <R-NNN> <base> — fold docs/ship-pending/<R-NNN>-context.md into
+# CONTEXT.md on origin/<base> in one `[skip ci]` commit and push it.
+# Prints `none` (nothing queued, nothing pushed) or `landed <sha>`.
+# Exit 1 when a step fails or every push attempt is rejected; exit 2 on usage.
+land_context() {
+  local id="$1" base="$2" attempt=0 tmp rc sha
+  [ -n "$id" ] && [ -n "$base" ] || { echo "usage: land_context R-NNN <base>" >&2; return 2; }
+  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ship-land.XXXXXX") || return 1
+  while [ "$attempt" -lt "$LAND_PUSH_ATTEMPTS" ]; do
+    attempt=$((attempt + 1))
+    git fetch -q origin "$base" || { rm -rf "$tmp"; return 1; }
+    git worktree add -q --detach "$tmp/wt" "origin/$base" || { rm -rf "$tmp"; return 1; }
+    rc=0
+    (
+      cd "$tmp/wt" || exit 1
+      [ -f "docs/ship-pending/$id-context.md" ] || exit 10
+      context_pending_apply "$id" >/dev/null || exit 1
+      git add -A CONTEXT.md "docs/ship-pending" || exit 1
+      git commit -q -m "context: land $id [skip ci]" || exit 1
+      git push -q origin "HEAD:$base" 2>/dev/null || exit 11
+    ) || rc=$?
+    sha=$(git -C "$tmp/wt" rev-parse HEAD 2>/dev/null)
+    git worktree remove --force "$tmp/wt" >/dev/null 2>&1
+    case "$rc" in
+      0)  rm -rf "$tmp"; echo "landed $sha"; return 0 ;;
+      10) rm -rf "$tmp"; echo "none"; return 0 ;;
+      11) : ;;
+      *)  rm -rf "$tmp"; return 1 ;;
+    esac
+  done
+  rm -rf "$tmp"
+  echo "land_context: push to origin/$base rejected $LAND_PUSH_ATTEMPTS times" >&2
+  return 1
+}
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land-lib.bats; cd - >/dev/null`

Expected: `1..6`, all 6 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-land): Task 6 — land_context folds deferred CONTEXT.md in a throwaway worktree and pushes [skip ci]"
```

### Task 7: Route every `_log.md` writer through `ship_log`

Seam: `ship_log` (callers)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 9 step 3)
- Modify: `commands/ship-idea.md`, `ship-decision.md`, `ship-research.md`, `ship-roadmap.md`, `ship-propose.md`, `ship-explain.md` (each: the one `echo … >> docs/learnings/_log.md` line)
- Test: `tests/test_ship-next-prune.bats`, `tests/test_ship-next-codex-loop.bats` (locate the row via `SHIP_LOG_ROW="|`; compare quoted row text)

**Interfaces:**
- Consumes: `ship_log` (Task 1).
- Produces: ship-next Phase 9 step 3 builds `SHIP_LOG_ROW` once and calls `ship_log "$SHIP_LOG_ROW"`; in mr mode it runs in `$WORKTREE` and pushes.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats b/claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
index 4416e6b..f2a7975 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
@@ -142,7 +142,7 @@ p9_bash() {
 }
 
 @test "Phase 9 log row records the codex round count and verdict" {
-  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
+  row=$(grep -F 'SHIP_LOG_ROW="|' "$CMD")
   [ -n "$row" ]
   [[ "$row" == *'${CODEX_LOG_FRAGMENT}'* ]] || return 1
   frag=$(p9_bash | grep -F 'CODEX_LOG_FRAGMENT=", codex:')
@@ -151,7 +151,7 @@ p9_bash() {
 }
 
 @test "Phase 9 omits the codex fragment on ships that never ran codex" {
-  # Auto mode picks executor 1, so most ships have no codex state at all.
+  # Ships that ran executor 1 or 2 have no codex state at all.
   # An unguarded "codex:  round(s)" on every row hides the rows that matter.
   body=$(p9_bash)
   echo "$body" | grep -qF 'CODEX_LOG_FRAGMENT=""' || { echo "fragment is not defaulted empty"; return 1; }
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-prune.bats b/claude-skills/ship-workflow/tests/test_ship-next-prune.bats
index 342500b..423c6a2 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-prune.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-prune.bats
@@ -65,7 +65,7 @@ p85_bash() {
 }
 
 @test "Phase 9 log row carries the prune status, not only the summary" {
-  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
+  row=$(grep -F 'SHIP_LOG_ROW="|' "$CMD")
   [ -n "$row" ]
   [[ "$row" == *'prune: ${PRUNE_STATUS}'* ]]
 }
@@ -153,5 +153,8 @@ p85_bash() {
   cmd_row=$(grep -F 'shipped (review: blocking=0, major=' "$CMD" | head -1)
   plan_row=$(grep -F 'shipped (review: blocking=0, major=' "$PLAN" | head -1)
   [ -n "$cmd_row" ] && [ -n "$plan_row" ]
-  [ "$(echo "$cmd_row" | sed 's/^[[:space:]]*//')" = "$(echo "$plan_row" | sed 's/^[[:space:]]*//')" ]
+  # Compare the quoted row text, not the whole line: the command file holds it in
+  # SHIP_LOG_ROW="…" for ship_log (R-001), older plans show `echo "…" >> _log.md`.
+  row_of() { sed 's/^[^"]*"//; s/"[^"]*$//'; }
+  [ "$(echo "$cmd_row" | row_of)" = "$(echo "$plan_row" | row_of)" ]
 }
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats tests/test_ship-next-codex-loop.bats; cd - >/dev/null`

Expected: `1..46`, 44 ok, these 2 fail:
  - `not ok 6 Phase 9 log row carries the prune status, not only the summary`
  - `not ok 30 Phase 9 log row records the codex round count and verdict`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-decision.md b/claude-skills/ship-workflow/commands/ship-decision.md
index a8b30c4..8525f05 100644
--- a/claude-skills/ship-workflow/commands/ship-decision.md
+++ b/claude-skills/ship-workflow/commands/ship-decision.md
@@ -35,7 +35,9 @@ You are recording a decision into `docs/decisions/D-NNN-<slug>.md`.
 
 7. **Append log:**
    ```bash
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-decision | $ID | $topic | n |" >> docs/learnings/_log.md
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-decision | $ID | $topic | n |"
    ```
 
 8. **Commit:**
diff --git a/claude-skills/ship-workflow/commands/ship-explain.md b/claude-skills/ship-workflow/commands/ship-explain.md
index f3cb462..c7bdd1b 100644
--- a/claude-skills/ship-workflow/commands/ship-explain.md
+++ b/claude-skills/ship-workflow/commands/ship-explain.md
@@ -103,7 +103,9 @@ You are generating a plain-language **Roadmap Explainer Note** for a ROADMAP row
 
 12. **Log + commit (repo side):**
     ```bash
-    echo "| $(date +%Y-%m-%d\ %H:%M) | ship-explain | ${ID} | $(basename $NOTE_PATH) | n |" >> docs/learnings/_log.md
+    # shellcheck disable=SC1091
+    source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+    ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-explain | ${ID} | $(basename $NOTE_PATH) | n |"
     git add docs/product/ROADMAP.md docs/roadmap-notes/ docs/learnings/_log.md
     git commit -m "explain: ${ID} ${slug}"
     ```
diff --git a/claude-skills/ship-workflow/commands/ship-idea.md b/claude-skills/ship-workflow/commands/ship-idea.md
index 80d2f3f..979bab2 100644
--- a/claude-skills/ship-workflow/commands/ship-idea.md
+++ b/claude-skills/ship-workflow/commands/ship-idea.md
@@ -74,7 +74,9 @@ You are capturing a new idea into `docs/ideas/IDEA-NNN-<slug>.md`.
 
 7. **Append log line:**
    ```bash
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-idea | $ID | $description | n |" >> docs/learnings/_log.md
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-idea | $ID | $description | n |"
    ```
 
 8. **Commit:**
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index a83a315..07ade28 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -1237,19 +1237,32 @@ runs in `--auto:yes`. Because it is expensive, Phase 9 flags it explicitly.
 
    The squash merge in Phase 7 doesn't update branch reachability, so `-d` may complain. Use `-D` if needed; the work is already squashed onto $ORIG_BRANCH.
 
-3. **Log + commit (repo side, on $ORIG_BRANCH):**
+3. **Log + commit.** `squash`: in `$REPO`, on `$ORIG_BRANCH`. `mr`: in
+   `$WORKTREE`, on the review branch — `ship_log` turns the row into a
+   `Ship-Log:` commit trailer there, so it reaches the base branch's history with
+   the review and parallel MRs never touch a shared file (R-001).
 
    ```bash
-   # Only ships that actually ran codex carry a codex fragment. Auto mode picks
-   # executor 1, so most ships never run it, and an empty "codex:  round(s)" on
+   # Only ships that actually ran codex carry a codex fragment. Ships that ran
+   # executor 1 or 2 have no codex state, and an empty "codex:  round(s)" on
    # every row is noise that hides the rows where it means something.
    CODEX_LOG_FRAGMENT=""
    if [ "${CODEX_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
      CODEX_LOG_FRAGMENT=", codex: ${CODEX_ROUNDS} round(s) ${CODEX_FINAL_VERDICT}"
    fi
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp, prune: ${PRUNE_STATUS}${CODEX_LOG_FRAGMENT}) | n |" >> docs/learnings/_log.md
-   git add docs/learnings/_log.md
-   git commit -m "log: ship ${ID}"
+   SHIP_LOG_ROW="| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp, prune: ${PRUNE_STATUS}${CODEX_LOG_FRAGMENT}) | n |"
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   if [ "$MERGE_MODE" = "mr" ]; then
+     cd "$WORKTREE"
+     ship_log "$SHIP_LOG_ROW"
+     git push origin HEAD
+     cd "$REPO"
+   else
+     ship_log "$SHIP_LOG_ROW"
+     git add docs/learnings/_log.md
+     git commit -m "log: ship ${ID}"
+   fi
    ```
 
 4. **Auto-mode success notification** (only if `AUTO=1`):
diff --git a/claude-skills/ship-workflow/commands/ship-propose.md b/claude-skills/ship-workflow/commands/ship-propose.md
index e8e55dd..8b72953 100644
--- a/claude-skills/ship-workflow/commands/ship-propose.md
+++ b/claude-skills/ship-workflow/commands/ship-propose.md
@@ -287,7 +287,9 @@ This file currently covers:
 14. **Log:**
 
     ```bash
-    echo "| $(date +%Y-%m-%d\ %H:%M) | ship-propose | $ID | draft ($SIZE) | n |" >> docs/learnings/_log.md
+    # shellcheck disable=SC1091
+    source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+    ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-propose | $ID | draft ($SIZE) | n |"
     ```
 
 15. **Commit (repo side):**
diff --git a/claude-skills/ship-workflow/commands/ship-research.md b/claude-skills/ship-workflow/commands/ship-research.md
index f2b5c2d..ecb2d2d 100644
--- a/claude-skills/ship-workflow/commands/ship-research.md
+++ b/claude-skills/ship-workflow/commands/ship-research.md
@@ -54,13 +54,17 @@ You are running vault-first deep research to fill a knowledge gap.
 5. **Append log line (repo side):**
    ```bash
    scope=$([ "$ARG_SCOPE" = "global" ] && echo "global" || echo "$PROJECT")
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-research | - | $TOPIC ($scope) | n |" >> docs/learnings/_log.md
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-research | - | $TOPIC ($scope) | n |"
    ```
 
 6. **Commit the log entry (repo side):**
    ```bash
    git add docs/learnings/_log.md
-   git commit -m "chore: ship-research on '$TOPIC'"
+   # On a merge_mode=mr review branch ship_log already committed the row as a
+   # trailer, so there may be nothing staged here.
+   git diff --cached --quiet || git commit -m "chore: ship-research on '$TOPIC'"
    ```
 
 7. **Report:**
diff --git a/claude-skills/ship-workflow/commands/ship-roadmap.md b/claude-skills/ship-workflow/commands/ship-roadmap.md
index a349936..2608071 100644
--- a/claude-skills/ship-workflow/commands/ship-roadmap.md
+++ b/claude-skills/ship-workflow/commands/ship-roadmap.md
@@ -114,7 +114,9 @@ You are running the Roadmap refresh ritual.
 
 10. **Log + commit (repo side):**
    ```bash
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-roadmap | - | refresh | n |" >> docs/learnings/_log.md
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-roadmap | - | refresh | n |"
    git add docs/product/ROADMAP.md docs/learnings/_log.md
    git commit -m "chore: refresh ROADMAP.md"
    ```
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats tests/test_ship-next-codex-loop.bats; cd - >/dev/null`

Expected: `1..46`, all 46 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(commands): Task 7 — every _log.md row goes through ship_log; ship-next P9 logs on the review branch in mr mode"
```

### Task 8: `ship-compound`: queue CONTEXT, stage only own-ID paths in mr mode

Seam: `context_pending_add`, `ship_log` (callers)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md` (step 6 intro, step 9, step 10)
- Test: `claude-skills/ship-workflow/tests/test_ship-compound-merge-mode.bats` (append two tests)

**Interfaces:**
- Consumes: `context_pending_add` (Task 4), `ship_log` (Task 1), `merge_mode`.
- Produces: step 6 sets `MERGE_MODE` and, in mr mode, queues entries; step 9 mr branch stages only `docs/learnings/${ID}-${slug}.md`, `docs/tdd-rules.d`, `docs/ship-pending`.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-compound-merge-mode.bats b/claude-skills/ship-workflow/tests/test_ship-compound-merge-mode.bats
index 5764343..0b6f0d9 100644
--- a/claude-skills/ship-workflow/tests/test_ship-compound-merge-mode.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-compound-merge-mode.bats
@@ -21,3 +21,20 @@ setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-compound.md"; }
   echo "$sec" | grep -qF 'MERGE_MODE' \
     || { echo "learnings land on the base branch while the work is unmerged"; return 1; }
 }
+
+@test "ship-compound's mr branch of step 9 stages no shared file" {
+  # _log.md, the vault mirror and CONTEXT.md are what made parallel MRs conflict.
+  sec=$(awk '/^9\. \*\*Log \+ commit/,/^10\. \*\*Report/' "$CMD")
+  mr=$(echo "$sec" | awk '/if \[ "\$MERGE_MODE" = "mr" \]; then/{f=1;next} /^[[:space:]]*else$/{f=0} f')
+  [ -n "$mr" ] || { echo "no mr branch in step 9"; return 1; }
+  for shared in docs/product docs/proposals _log.md CONTEXT.md; do
+    if echo "$mr" | grep -qF "$shared"; then echo "mr branch stages $shared"; return 1; fi
+  done
+  echo "$sec" | grep -qF 'ship_log "|' || { echo "the row bypasses ship_log"; return 1; }
+}
+
+@test "ship-compound queues CONTEXT.md entries instead of editing them in mr mode" {
+  sec=$(awk '/^### Step 6/,/^6\. \*\*Delegate/' "$CMD")
+  echo "$sec" | grep -qF 'context_pending_add "$ID"' || { echo "no queue in mr mode"; return 1; }
+  echo "$sec" | grep -qF 'MERGE_MODE=$(merge_mode)' || { echo "step 6 cannot tell the mode"; return 1; }
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-merge-mode.bats tests/test_ship-compound-context.bats tests/test_ship-next-tdd-rules.bats; cd - >/dev/null`

Expected: `1..18`, 16 ok, these 2 fail:
  - `not ok 4 ship-compound's mr branch of step 9 stages no shared file`
  - `not ok 5 ship-compound queues CONTEXT.md entries instead of editing them in mr mode`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-compound.md b/claude-skills/ship-workflow/commands/ship-compound.md
index 052bbbd..fd736c6 100644
--- a/claude-skills/ship-workflow/commands/ship-compound.md
+++ b/claude-skills/ship-workflow/commands/ship-compound.md
@@ -90,8 +90,26 @@ You are wrapping up a Roadmap item.
 ```bash
 # shellcheck disable=SC1091
 source ~/.claude/skills/ship-workflow/lib/context-md.sh
+# shellcheck disable=SC1091
+source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
+MERGE_MODE=$(merge_mode)
+```
+
+**`mr` mode: queue, do not edit.** A review branch must not touch `CONTEXT.md` —
+every ship editing it is what made parallel MRs conflict (R-001). Do sub-step 1,
+then queue each entry instead of doing sub-steps 2–4:
+
+```bash
+# Once per qualifying entry (continuation lines, if any, indented):
+# context_pending_add "$ID" "- **<term>** — <definition>"
+CONTEXT_MD_STATUS="queued for /ship-land"
 ```
 
+Step 9 commits the queue file `docs/ship-pending/${ID}-context.md` on the review
+branch, so the entries are reviewed with the work. `/ship-land` folds them into
+`CONTEXT.md`, runs the cap check and mirrors to the vault after the MR merges.
+Sub-steps 2–4 below are the `squash` path.
+
 1. **Extract terms.** From this ship's diff and `docs/specs/${ID}-${SLUG}.md`,
    identify domain terms this work **introduced or clarified**. A term qualifies
    only if it is project-specific and a newcomer could not infer it from the code
@@ -235,23 +253,42 @@ source ~/.claude/skills/ship-workflow/lib/context-md.sh
    so it is reviewed and merged with the work it describes. Committing it to
    the base branch would put a learning for unmerged code on main.
 
+   In `mr` mode the review branch stages only paths that carry this ship's own
+   ID. The shared files — `_log.md`, the `docs/product/` and `docs/proposals/`
+   vault mirror, `CONTEXT.md` — are what made parallel MRs conflict (R-001).
+   `ship_log` turns the row into a `Ship-Log:` commit trailer there, and the
+   mirror is regenerated from the vault by every `sync.sh` run anyway.
+
    ```bash
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
    STATUS_WORD=shipped
    [ "$MERGE_MODE" = "mr" ] && STATUS_WORD=in-review
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | $STATUS_WORD | n |" >> docs/learnings/_log.md
-   git add docs/learnings/${ID}-${slug}.md docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md
-   git commit -m "compound: $ID — $STATUS_WORD + learning + ROADMAP update"
+   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | $STATUS_WORD | n |"
 
    if [ "$MERGE_MODE" = "mr" ]; then
+     git add "docs/learnings/${ID}-${slug}.md"
+     for p in docs/tdd-rules.d docs/ship-pending; do
+       [ -e "$p" ] && git add "$p"
+     done
+     git commit -m "compound: $ID — $STATUS_WORD + learning"
      # The review is already open; push the learning onto the same branch.
      git push origin HEAD
+   else
+     git add "docs/learnings/${ID}-${slug}.md" docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md
+     [ -e docs/tdd-rules.d ] && git add docs/tdd-rules.d
+     git commit -m "compound: $ID — $STATUS_WORD + learning + ROADMAP update"
    fi
    ```
 
+   `docs/tdd-rules.d/` is staged in both modes: step 6b writes this ship's rule
+   fragment there, and no other step commits it.
+
 10. **Report:**
     - Learning path
     - Patterns promoted to AIR-OS (paths, if any)
-    - ROADMAP item moved to Done
+    - `squash`: ROADMAP item moved to Done
+    - `mr`: row marked in-review — run `/ship-land ${ID}` after the review merges
     - Next suggested command: `/ship-next`
 
 ## Failure modes
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-merge-mode.bats tests/test_ship-compound-context.bats tests/test_ship-next-tdd-rules.bats; cd - >/dev/null`

Expected: `1..18`, all 18 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-compound): Task 8 — mr mode queues CONTEXT entries and commits no shared file"
```

### Task 9: Rewrite `/ship-land`; document linking every command

Seam: `land_is_merged`, `land_context` (callers)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify (rewrite): `claude-skills/ship-workflow/commands/ship-land.md`
- Modify: `claude-skills/ship-workflow/README.md` (Development section)
- Test: `tests/test_ship-land.bats` (two assertions changed, three tests added)
- Test: `tests/test_ship-log.bats` (append the routing guard)

**Interfaces:**
- Consumes: `land_is_merged`, `land_context` (Task 6), `CONTEXT_MD_MAX_LINES` / `CONTEXT_MD_MAX_ENTRIES` (context-md.sh).
- Produces: the installable `/ship-land R-NNN` command.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-land.bats b/claude-skills/ship-workflow/tests/test_ship-land.bats
index 28cf07e..f3a750c 100644
--- a/claude-skills/ship-workflow/tests/test_ship-land.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-land.bats
@@ -13,7 +13,7 @@ setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-land.md"; }
   # The whole point is that it finishes what mr mode deferred. Doing that on
   # an unmerged review would mark Done and delete the branch the review needs.
   grep -qiF 'merged' "$CMD" || { echo "no merge check"; return 1; }
-  grep -qF 'git branch --merged' "$CMD" || { echo "merge state is never verified"; return 1; }
+  grep -qF 'land_is_merged "$BRANCH" "origin/${BASE}"' "$CMD" || { echo "merge state is never verified"; return 1; }
 }
 
 @test "ship-land moves the row to Done and clears in-review" {
@@ -23,7 +23,20 @@ setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-land.md"; }
 
 @test "ship-land cleans up what Phase 9 deliberately kept" {
   grep -qF 'git worktree remove' "$CMD" || { echo "worktree is never removed"; return 1; }
-  grep -qF 'git branch -d' "$CMD" || { echo "branch is never deleted"; return 1; }
+  grep -qF 'git branch -D "$BRANCH"' "$CMD" || { echo "branch is never deleted"; return 1; }
+}
+
+@test "ship-land folds deferred CONTEXT.md entries through the lib" {
+  grep -qF 'lib/ship-land.sh' "$CMD" || { echo "lib not sourced"; return 1; }
+  grep -qF 'land_context "$ID" "$BASE"' "$CMD" || { echo "deferred entries are never landed"; return 1; }
+}
+
+@test "ship-land never writes _log.md or pulls the operator's checkout" {
+  # Both were in the first version: a local-only commit on the base branch that
+  # was never pushed, and a pull on a checkout that may be dirty or behind.
+  code=$(awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' "$CMD")
+  if echo "$code" | grep -qF '_log.md'; then echo "ship-land writes _log.md"; return 1; fi
+  if echo "$code" | grep -qE 'git pull'; then echo "ship-land pulls the operator checkout"; return 1; fi
 }
 
 @test "ship-land is registered as a ship-* command" {
@@ -37,3 +50,7 @@ setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-land.md"; }
   run bash -n "$BATS_TEST_TMPDIR/l.sh"
   [ "$status" -eq 0 ]
 }
+
+@test "ship-land refuses to run from inside a worktree" {
+  grep -qF 'git rev-parse --git-common-dir' "$CMD" || { echo "no main-checkout guard"; return 1; }
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-log.bats b/claude-skills/ship-workflow/tests/test_ship-log.bats
index 930b41f..096c22b 100644
--- a/claude-skills/ship-workflow/tests/test_ship-log.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-log.bats
@@ -86,3 +86,9 @@ mr_mode() { echo 'merge_mode: mr' > .claude/ship-config.yml; }
   [ "$(git log -1 --format=%s)" = "log: ship-next R-3" ]
 }
 
+@test "every command writes _log.md rows through ship_log" {
+  # A direct append on a review branch is a shared-file write — what made
+  # parallel MRs conflict (R-001).
+  hits=$(grep -l '>> docs/learnings/_log.md' "$SHIP_SKILL_ROOT"/commands/*.md || true)
+  [ -z "$hits" ] || { echo "direct appends in: $hits"; return 1; }
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land.bats tests/test_ship-log.bats; cd - >/dev/null`

Expected: `1..18`, 12 ok, these 6 fail:
  - `not ok 2 ship-land refuses to run before the review has actually merged`
  - `not ok 4 ship-land cleans up what Phase 9 deliberately kept`
  - `not ok 5 ship-land folds deferred CONTEXT.md entries through the lib`
  - `not ok 6 ship-land never writes _log.md or pulls the operator's checkout`
  - `not ok 9 ship-land refuses to run from inside a worktree`
  - `not ok 18 every command writes _log.md rows through ship_log`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/README.md b/claude-skills/ship-workflow/README.md
index f20b3dd..e0c77c5 100644
--- a/claude-skills/ship-workflow/README.md
+++ b/claude-skills/ship-workflow/README.md
@@ -53,6 +53,10 @@ bats tests/
 
 # Local install for development
 ln -sf $(pwd) ~/.claude/skills/ship-workflow
+# Link every command. Re-run after adding one — /ship-land existed for weeks
+# without a link and so could not be invoked.
+mkdir -p ~/.claude/commands
+for f in commands/*.md; do ln -sf ~/.claude/skills/ship-workflow/"$f" ~/.claude/commands/; done
 ```
 
 ## Specification
diff --git a/claude-skills/ship-workflow/commands/ship-land.md b/claude-skills/ship-workflow/commands/ship-land.md
index b1e7bf3..bfd1612 100644
--- a/claude-skills/ship-workflow/commands/ship-land.md
+++ b/claude-skills/ship-workflow/commands/ship-land.md
@@ -1,6 +1,6 @@
 ---
 name: ship-land
-description: Finish an R-NNN that shipped via merge_mode=mr — verify the review merged, move the ROADMAP row to Done, then clean up the branch and worktree
+description: Finish an R-NNN that shipped via merge_mode=mr — verify the review merged, fold its deferred CONTEXT.md entries onto the base branch, move the ROADMAP row to Done, then clean up the branch and worktree
 discord-visible: true
 ---
 
@@ -9,10 +9,16 @@ discord-visible: true
 Closes the loop that `merge_mode: mr` deliberately leaves open.
 
 In `mr` mode Phase 7 pushes the branch and opens a review instead of merging.
-Phase 8 marks the ROADMAP row `status=in-review` rather than Done, and Phase 9
-keeps the branch and worktree the review depends on. All of that is correct
-while the review is open and all of it is stale once it merges. This command is
-the "once it merges" half.
+Phase 8 marks the ROADMAP row `status=in-review` rather than Done, queues any new
+`CONTEXT.md` entries in `docs/ship-pending/<R-NNN>-context.md` instead of editing
+`CONTEXT.md`, and Phase 9 keeps the branch and worktree the review depends on. All
+of that is correct while the review is open and stale once it merges. This command
+is the "once it merges" half.
+
+The review branch never writes a file another ship also writes — that is what made
+parallel MRs conflict (R-001). `CONTEXT.md` is the one shared file that cannot be
+split per ship, so it is the one this command writes, after the merge, on the base
+branch. A land with no queued entries makes no commit at all.
 
 Nothing here is needed in `squash` mode — Phase 7 already landed the work and
 Phase 9 already cleaned up.
@@ -25,85 +31,130 @@ Phase 9 already cleaned up.
 
 ## Steps
 
-1. **Resolve the row and the branch.**
+1. **Resolve the row, the base and the branch.** Run from the main repo root.
 
    ```bash
    ID="$1"
    [ -n "$ID" ] || { echo "usage: /ship-land R-NNN" >&2; exit 2; }
 
+   # From the main checkout, never from the ship's worktree: step 5 removes
+   # that worktree, and git refuses to remove the one you are standing in.
+   if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
+     echo "run /ship-land from the main checkout, not from a worktree" >&2
+     exit 2
+   fi
    REPO=$(git rev-parse --show-toplevel)
    cd "$REPO"
-   ORIG_BRANCH=$(git symbolic-ref --short HEAD)
+   BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
+   [ -n "$BASE" ] || BASE=main
    BRANCH=$(git branch --list "ship/${ID}-*" --format='%(refname:short)' | head -1)
-   [ -n "$BRANCH" ] || { echo "no ship branch found for $ID" >&2; exit 1; }
+   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
+
+   if [ -z "$BRANCH" ]; then
+     if awk '/✅ Done/{d=1} d' "$ROADMAP_PATH" 2>/dev/null | grep -qF "**${ID}**"; then
+       echo "$ID is already landed — nothing to do."
+       exit 0
+     fi
+     echo "no local ship branch found for $ID" >&2
+     exit 1
+   fi
    ```
 
 2. **Verify the review actually merged.** This is the gate. Marking Done and
    deleting a branch whose review is still open is how the work disappears.
 
    ```bash
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
    git fetch origin --prune
 
-   if ! git branch --merged "origin/${ORIG_BRANCH}" --format='%(refname:short)' \
-        | grep -qx "$BRANCH"; then
-     echo "ERROR: $BRANCH is not merged into origin/$ORIG_BRANCH." >&2
+   if ! land_is_merged "$BRANCH" "origin/${BASE}"; then
+     echo "ERROR: $BRANCH is not merged into origin/$BASE." >&2
      echo "       The review is still open, or it was closed without merging." >&2
+     echo "       If it was merged with the forge's squash option, the branch tip is" >&2
+     echo "       not in origin/$BASE and this check cannot see the merge." >&2
      echo "       Nothing has been changed." >&2
      exit 1
    fi
    ```
 
-   `--merged origin/<base>` is checked rather than the local base: the review
-   merged on the remote, and a stale local base would answer the wrong
-   question.
+   The **local** branch is checked against `origin/<base>`: Phase 7 opens the review
+   with `--remove-source-branch`, so the remote branch is usually gone by now, and a
+   stale local base would answer the wrong question.
 
-3. **Move the ROADMAP row to Done.**
+3. **Fold the deferred CONTEXT.md entries onto the base branch.**
 
    ```bash
-   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
+   LAND_RESULT=$(land_context "$ID" "$BASE") || {
+     echo "ERROR: could not land CONTEXT.md for $ID — ROADMAP and branch untouched." >&2
+     exit 1
+   }
+   echo "$LAND_RESULT"
    ```
 
-   Edit `$ROADMAP_PATH`:
+   `land_context` works in a throwaway worktree at `origin/<base>`, so the
+   operator's checkout — often behind origin, sometimes dirty — is never pulled,
+   switched or committed to. It makes one commit, `context: land <R-NNN> [skip ci]`,
+   and pushes it. `[skip ci]` keeps a docs-only bookkeeping commit from starting a
+   pipeline. If another push wins the race it redoes the fold on the new tip.
+
+   When `$LAND_RESULT` starts with `landed`, mirror the result to the vault and run
+   the cap check:
+
+   ```bash
+   case "$LAND_RESULT" in
+     landed*)
+       VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
+       git show "origin/${BASE}:CONTEXT.md" > "/tmp/ship-land-CONTEXT-${ID}.md"
+       ~/.claude/skills/ship-workflow/lib/spec-mirror.sh \
+         "/tmp/ship-land-CONTEXT-${ID}.md" "$VAULT_DIR/CONTEXT.md"
+       LINES=$(wc -l < "/tmp/ship-land-CONTEXT-${ID}.md" | tr -d ' ')
+       ENTRIES=$(grep -cE '^- \*\*[^*]+\*\*' "/tmp/ship-land-CONTEXT-${ID}.md" || true)
+       if [ "$LINES" -gt "$CONTEXT_MD_MAX_LINES" ] || [ "$ENTRIES" -gt "$CONTEXT_MD_MAX_ENTRIES" ]; then
+         echo "WARN: CONTEXT.md over cap (${LINES} lines / ${ENTRIES} entries) — prune it" >&2
+       fi
+       ;;
+   esac
+   ```
+
+   Over cap: prune as `/ship-compound` step 6.3 describes, in a normal commit on the
+   base branch. Pruning deletes, so it is never automatic.
+
+4. **Move the ROADMAP row to Done.** Edit `$ROADMAP_PATH` (skip if already Done):
    - Find the `${ID}` line under "🔥 Now"
    - Strip `status=in-review` and the `mr=<url>` annotation Phase 8 added
    - Strip `adhoc-inserted=true` if present
    - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
    - Atomic write via `.tmp` + `mv`
 
-   Then re-sync so the repo mirror matches:
-
-   ```bash
-   ~/.claude/skills/ship-workflow/lib/sync.sh --force
-   ```
+   The vault is the source of truth; nothing is committed for this step.
 
-4. **Clean up what Phase 9 kept.**
+5. **Clean up what Phase 9 kept.**
 
    ```bash
-   git pull --ff-only origin "$ORIG_BRANCH"
-
    WORKTREE=$(git worktree list --porcelain \
               | awk -v b="refs/heads/$BRANCH" '/^worktree /{w=$2} /^branch /{if ($2==b) print w}')
    if [ -n "$WORKTREE" ]; then
+     # sync.sh rewrites the vault mirror in every working tree it runs in. Those
+     # files are regenerated from the vault, never review content — restore them
+     # so they do not block the removal.
+     git -C "$WORKTREE" checkout -- docs/product docs/proposals docs/roadmap-notes 2>/dev/null || true
      git worktree remove "$WORKTREE" || {
        echo "WARN: worktree at $WORKTREE has uncommitted changes; not removed." >&2
        echo "      Inspect, then: git worktree remove --force $WORKTREE" >&2
      }
    fi
 
-   git branch -d "$BRANCH"
+   git branch -D "$BRANCH"
    git push origin --delete "$BRANCH" 2>/dev/null || true
    ```
 
-   `-d` not `-D`: by this point the branch IS merged, so `-d` succeeds. If it
-   refuses, the step-2 check was wrong and the work must not be discarded.
-
-5. **Log it.**
+   `-D` is safe **because** step 2 proved the branch tip is in `origin/<base>`. `-d`
+   would compare against the local base, which is routinely behind origin, and
+   refuse a branch that is in fact merged.
 
-   ```bash
-   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-land | ${ID} | landed | n |" >> docs/learnings/_log.md
-   git add docs/learnings/_log.md docs/product/ROADMAP.md
-   git commit -m "land: ${ID} — review merged, roadmap closed"
-   ```
+6. **Report:** the land commit (or "no CONTEXT.md changes"), the row's new state,
+   and the branch and worktree removed.
 
-6. **Report:** the row's new state, the branch and worktree removed, and the
-   merge commit on the base branch.
+There is no `_log.md` write and no `git pull` here. The ship's log rows reached the
+base branch's history as `Ship-Log:` trailers when the review merged.
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land.bats tests/test_ship-log.bats; cd - >/dev/null`

Expected: `1..18`, all 18 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-land): Task 9 — /ship-land folds CONTEXT via land_context, never pulls or writes _log.md"
```

### Task 10: Full-suite verification against the spec

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

**Interfaces:**
- Consumes: everything from Tasks 1–9.
- Produces: the evidence the review gate reads.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..518`, 517 ok, exactly one failure — the known pre-existing `cwd-guard: exits 0 when not in a git repo at all`. Any other failure is yours: STOP and report it.

- [ ] **Step 2: Confirm no command appends to `_log.md` directly**

Run: `grep -rn '>> docs/learnings/_log.md' claude-skills/ship-workflow/commands/ || echo "none"`

Expected: `none`.

- [ ] **Step 3: Confirm the spec's acceptance IDs are all covered**

Run:
```bash
cd claude-skills/ship-workflow
grep -c '^@test' tests/test_ship-log.bats tests/test_context-pending.bats tests/test_parallel-mr.bats tests/test_ship-land-lib.bats
cd - >/dev/null
```

Expected: `tests/test_ship-log.bats:9`, `tests/test_context-pending.bats:10`, `tests/test_parallel-mr.bats:4`, `tests/test_ship-land-lib.bats:6`.

- [ ] **Step 4: No commit** — this task changes nothing. Report DONE with the Step 1 counts.

## Not in this plan (operator steps at land time)

- Create `~/.claude/commands/ship-land.md` → `~/.claude/skills/ship-workflow/commands/ship-land.md`. It lives outside the repo, so the executor must not do it; the supervisor does it after the squash lands.

## Execution log

- Tasks 1–9: prescribed patches applied in numerical order; expected RED results observed and all scoped GREEN runs passed; nine commits used the prescribed messages. Task 5 acceptance tests passed immediately as expected.
- Task 10: full suite ran once: 518 tests, 517 passed, only the documented pre-existing cwd-guard failure. Direct-append search: none. Acceptance test counts: 9 / 10 / 4 / 6.
- Deviation: added `--only` to the empty Ship-Log commit and strengthened the existing test with staged-file/index-preservation assertions — final review found that the prescribed `--allow-empty` command included staged changes, violating the explicit empty-tree seam. The strengthened test failed before the fix.
- Deviation: the late local repair uses a separate follow-up commit — Tasks 1–9 were already committed, and existing commits must not be amended.
- Repair verification: ship-log 9/9, test-budget 18/18, parallel-mr 4/4 passed. Full suite was not repeated, honoring the plan's once-only constraint. Final read-only review found no issues in the five listed review-focus cases.
