# R-001 Review-fix Plan (attempt 2) — blockers and majors from the Phase 6 review

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 1 blocking and 7 important findings (plus 6 cheap nits) from the R-001 Phase 6 review, each pinned by a test that fails before the fix.

**Architecture:** Same seams as `docs/plans/R-001-add-ship-land-defer-writes.md`. New here: `tests/test_command-blocks.bats` *executes* the real bash blocks of the command markdown in scratch repos (HOME points `~/.claude/skills/ship-workflow` at this tree), because every command-level defect the review found only shows when a block runs.

**Tech Stack:** bash + zsh, git ≥ 2.38, bats 1.13, awk.

**Spec:** `docs/specs/R-001-add-ship-land-defer-writes.md` (Task 7 updates it). Review: `/tmp/ship-next-review-R-001-1.md`.

## Global Constraints

- **Scope.** Every file you edit is under `claude-skills/ship-workflow/` or `docs/specs/` in THIS repository. `claude-skills/` is this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/` or the operator's home directory. The new tests set their own `HOME` to a scratch dir — that is how they avoid the real one.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise.
- **Patches are the code.** Each code step is a `git apply` heredoc, generated from and replayed against this exact base (`34328d3`). They apply cleanly in order. If one does not apply, STOP — do not hand-edit around it.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 8.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** no `local` inside a loop body; no unquoted globs that may match nothing.
- **Commits.** One commit per task with the exact message given. Never amend, never push, never switch branches. Commit subjects say `review-fix N`, not `Task N`, so Phase 6's gate does not confuse them with the original plan's tasks.

## Review Focus

Failure modes behind the review's findings that a person is most likely to hit next; each has a test in the owning task:

1. A command block run with a variable that an earlier block set — blocks do not share a shell (`$WORKTREE` in Phase 9, `$MERGE_MODE` in ship-compound step 9, the lib in ship-land step 3). → Tasks 3, 4, 5.
2. A push from the wrong branch: Phase 9 / ship-compound in mr mode invoked from the base checkout. → Tasks 3, 4.
3. A forge refusing the land commit for a reason other than a race (protected branch, auth). → Task 2.
4. Vault-mirror files in a worktree that sync modified or newly created. → Task 5.
5. A queued CONTEXT entry whose later lines the fold would drop. → Task 1.

---

### Task 1: `context_pending_add` refuses lines that apply would drop

Seam: `context_pending_add`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review 🟡 context-md.sh:87 — an unindented or blank later line was accepted, then silently dropped by `context_pending_apply` after review and merge (breaks G4).

**Files:**
- Modify: `claude-skills/ship-workflow/lib/context-md.sh`
- Test: `claude-skills/ship-workflow/tests/test_context-pending.bats` (two tests added)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_context-pending.bats b/claude-skills/ship-workflow/tests/test_context-pending.bats
index ab8ddec..14cd979 100644
--- a/claude-skills/ship-workflow/tests/test_context-pending.bats
+++ b/claude-skills/ship-workflow/tests/test_context-pending.bats
@@ -27,6 +27,21 @@ teardown() { rm -rf "$SCRATCH"; }
   [ "$status" -eq 2 ]
 }
 
+@test "context_pending_add: refuses a later line that apply would drop" {
+  # An unindented or blank later line is not part of any entry, so apply would
+  # silently lose it after the queue had been reviewed and merged.
+  run context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' 'not indented')"
+  [ "$status" -eq 2 ]
+  run context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' '' '  after a blank')"
+  [ "$status" -eq 2 ]
+  [ ! -e docs/ship-pending/R-7-context.md ]
+}
+
+@test "context_pending_add: accepts continuation lines and several entries at once" {
+  context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' '  continued' '- **Seat** — second')"
+  [ "$(wc -l < docs/ship-pending/R-7-context.md | tr -d ' ')" -eq 3 ]
+}
+
 @test "context_pending_apply: replaces a same-term entry with its continuation lines, appends a new term" {
   printf '%s\n' '# Context' '' '- **Foo** — old text' '  old continuation' '- **Keep** — untouched' > CONTEXT.md
   context_pending_add R-7 "- **Foo** — new text"
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-pending.bats; cd - >/dev/null`

Expected: `1..12`, 11 ok, these 1 fail:
  - `not ok 4 context_pending_add: refuses a later line that apply would drop`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/context-md.sh b/claude-skills/ship-workflow/lib/context-md.sh
index 5c8d773..587a132 100644
--- a/claude-skills/ship-workflow/lib/context-md.sh
+++ b/claude-skills/ship-workflow/lib/context-md.sh
@@ -75,11 +75,14 @@ context_md_orphan_terms() {
 
 CONTEXT_PENDING_DIR_REL="docs/ship-pending"
 
-# context_pending_add <R-NNN> "<entry>" — queue one entry. The entry's first
-# line must be `- **<term>** — <definition>`; indented continuation lines may
-# follow. Exit 2 on a bad ID, a malformed entry, or outside a git repo.
+# context_pending_add <R-NNN> "<entry>" — queue one or more entries. The first
+# line must be `- **<term>** — <definition>`; every later line must be either
+# indented (a continuation) or another such entry line. Anything else — an
+# unindented line, a blank line — would be dropped by context_pending_apply,
+# so it is refused here, before the queue is reviewed and merged. Exit 2 on a
+# bad ID, a malformed entry, or outside a git repo.
 context_pending_add() {
-  local id="$1" entry="$2" root first
+  local id="$1" entry="$2" root first bad
   case "$id" in
     R-[0-9]*) : ;;
     *) echo "context_pending_add: need an R-NNN, got '$id'" >&2; return 2 ;;
@@ -87,6 +90,11 @@ context_pending_add() {
   first=$(printf '%s\n' "$entry" | head -1)
   printf '%s\n' "$first" | grep -qE '^- \*\*[^*]+\*\* — ' \
     || { echo "context_pending_add: not a '- **term** — definition' entry" >&2; return 2; }
+  bad=$(printf '%s\n' "$entry" | awk 'NR > 1 && !/^[ \t]/ && !/^- \*\*[^*]+\*\* — / { print NR ": " $0 }')
+  [ -z "$bad" ] || {
+    echo "context_pending_add: line is neither indented nor a new entry — $bad" >&2
+    return 2
+  }
   root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
   mkdir -p "$root/$CONTEXT_PENDING_DIR_REL" || return 2
   printf '%s\n' "$entry" >> "$root/$CONTEXT_PENDING_DIR_REL/$id-context.md"
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-pending.bats; cd - >/dev/null`

Expected: `1..12`, all 12 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(context-md): review-fix 1 — context_pending_add refuses lines context_pending_apply would drop"
```

### Task 2: `land_context` retries only lost races and shows git's error otherwise

Seam: `land_context`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review 🟡 ship-land.sh:43 — every push failure was treated as a lost race and `2>/dev/null` hid git's error (e.g. a protected branch). Also the weak-assertion nits on `landed *` and the attempt cap.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/ship-land.sh`
- Test: `claude-skills/ship-workflow/tests/test_ship-land-lib.bats` (exact `landed <sha>` check; cap test replaced by two counting tests)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_ship-land-lib.bats b/claude-skills/ship-workflow/tests/test_ship-land-lib.bats
index c59d610..85388c9 100644
--- a/claude-skills/ship-workflow/tests/test_ship-land-lib.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-land-lib.bats
@@ -55,8 +55,8 @@ merge_pending() {
   head_before=$(git rev-parse HEAD)
   run land_context R-9 main
   [ "$status" -eq 0 ]
-  [[ "$output" == "landed "* ]] || return 1
   git fetch -q origin main
+  [ "$output" = "landed $(git rev-parse origin/main)" ]
   [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
   git show origin/main:CONTEXT.md | grep -qxF -- '- **TermR-9** — from R-9'
   git show origin/main:CONTEXT.md | grep -qxF -- '- **Old** — kept'
@@ -90,11 +90,42 @@ EOF
   [ "$(git log -1 --format=%s origin/main)" = "context: land R-9 [skip ci]" ]
 }
 
-@test "land_context: gives up after the attempt cap" {
+@test "land_context: a rejection that is not a lost race fails at once with git's error" {
+  # e.g. a protected branch: origin/main did not move, so retrying cannot help,
+  # and swallowing the error would hide the real cause.
   merge_pending R-9
-  printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-push
+  cat > .git/hooks/pre-push <<EOF
+#!/bin/sh
+echo attempt >> "$SCRATCH/attempts"
+echo "protected branch: push refused" >&2
+exit 1
+EOF
+  chmod +x .git/hooks/pre-push
+  run land_context R-9 main
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"protected branch: push refused"* ]] || return 1
+  [ "$(wc -l < "$SCRATCH/attempts" | tr -d ' ')" -eq 1 ]
+  [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
+}
+
+@test "land_context: gives up after LAND_PUSH_ATTEMPTS lost races" {
+  merge_pending R-9
+  git clone -q "$SCRATCH/origin.git" "$SCRATCH/other"
+  git -C "$SCRATCH/other" config user.email o@o
+  git -C "$SCRATCH/other" config user.name o
+  # Every push loses: someone else lands a commit first, every time.
+  cat > .git/hooks/pre-push <<EOF
+#!/bin/sh
+unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX
+echo attempt >> "$SCRATCH/attempts"
+git -C "$SCRATCH/other" pull -q --rebase origin main
+git -C "$SCRATCH/other" commit -q --allow-empty -m concurrent
+git -C "$SCRATCH/other" push -q origin main
+exit 0
+EOF
   chmod +x .git/hooks/pre-push
   run land_context R-9 main
   [ "$status" -eq 1 ]
+  [ "$(wc -l < "$SCRATCH/attempts" | tr -d ' ')" -eq "$LAND_PUSH_ATTEMPTS" ]
   [ "$(git worktree list --porcelain | grep -c '^worktree')" -eq 1 ]
 }
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land-lib.bats; cd - >/dev/null`

Expected: `1..7`, 6 ok, these 1 fail:
  - `not ok 6 land_context: a rejection that is not a lost race fails at once with git's error`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/lib/ship-land.sh b/claude-skills/ship-workflow/lib/ship-land.sh
index fdeed9c..702da58 100644
--- a/claude-skills/ship-workflow/lib/ship-land.sh
+++ b/claude-skills/ship-workflow/lib/ship-land.sh
@@ -24,14 +24,19 @@ land_is_merged() {
 # land_context <R-NNN> <base> — fold docs/ship-pending/<R-NNN>-context.md into
 # CONTEXT.md on origin/<base> in one `[skip ci]` commit and push it.
 # Prints `none` (nothing queued, nothing pushed) or `landed <sha>`.
-# Exit 1 when a step fails or every push attempt is rejected; exit 2 on usage.
+# A rejected push is retried only when origin/<base> actually moved — a lost
+# race. Any other rejection (protected branch, auth, network) fails at once
+# and shows git's own error, which retrying would only hide.
+# Exit 1 when a step fails, on a non-race rejection, or after
+# LAND_PUSH_ATTEMPTS lost races; exit 2 on usage.
 land_context() {
-  local id="$1" base="$2" attempt=0 tmp rc sha
+  local id="$1" base="$2" attempt=0 tmp rc sha base_sha
   [ -n "$id" ] && [ -n "$base" ] || { echo "usage: land_context R-NNN <base>" >&2; return 2; }
   tmp=$(mktemp -d "${TMPDIR:-/tmp}/ship-land.XXXXXX") || return 1
   while [ "$attempt" -lt "$LAND_PUSH_ATTEMPTS" ]; do
     attempt=$((attempt + 1))
     git fetch -q origin "$base" || { rm -rf "$tmp"; return 1; }
+    base_sha=$(git rev-parse "origin/$base") || { rm -rf "$tmp"; return 1; }
     git worktree add -q --detach "$tmp/wt" "origin/$base" || { rm -rf "$tmp"; return 1; }
     rc=0
     (
@@ -40,18 +45,26 @@ land_context() {
       context_pending_apply "$id" >/dev/null || exit 1
       git add -A CONTEXT.md "docs/ship-pending" || exit 1
       git commit -q -m "context: land $id [skip ci]" || exit 1
-      git push -q origin "HEAD:$base" 2>/dev/null || exit 11
+      git push -q origin "HEAD:$base" 2>"$tmp/push.err" || exit 11
     ) || rc=$?
     sha=$(git -C "$tmp/wt" rev-parse HEAD 2>/dev/null)
     git worktree remove --force "$tmp/wt" >/dev/null 2>&1
     case "$rc" in
       0)  rm -rf "$tmp"; echo "landed $sha"; return 0 ;;
       10) rm -rf "$tmp"; echo "none"; return 0 ;;
-      11) : ;;
+      11)
+        git fetch -q origin "$base" 2>/dev/null
+        if [ "$(git rev-parse "origin/$base" 2>/dev/null)" = "$base_sha" ]; then
+          cat "$tmp/push.err" >&2
+          rm -rf "$tmp"
+          echo "land_context: push to origin/$base rejected, and not by a concurrent push" >&2
+          return 1
+        fi
+        ;;
       *)  rm -rf "$tmp"; return 1 ;;
     esac
   done
   rm -rf "$tmp"
-  echo "land_context: push to origin/$base rejected $LAND_PUSH_ATTEMPTS times" >&2
+  echo "land_context: lost the race to origin/$base $LAND_PUSH_ATTEMPTS times" >&2
   return 1
 }
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-land-lib.bats; cd - >/dev/null`

Expected: `1..7`, all 7 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-land): review-fix 2 — land_context retries only when origin moved, otherwise fails with git's error"
```

### Task 3: ship-next Phase 9 pushes only a `ship/*` branch; Phase 8 says where `/ship-compound` runs

Seam: `ship_log` (caller: ship-next Phase 9)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review 🔴 ship-next.md:1256 — with `$WORKTREE` empty, `cd ""` succeeds silently, so `git push origin HEAD` pushed the operator's base branch to origin. The reviewer's suggested `( cd "$WORKTREE" || exit 1 … )` is NOT enough (`cd ""` still succeeds) — the fix checks `$WORKTREE` is non-empty AND the branch there is `ship/*`. Review 🟡 ship-compound.md:269 — Phase 8 still said `/ship-compound` runs from the base checkout.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 8 text; Phase 9 step 3 mr branch)
- Create: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (executes the real Phase 9 block in scratch repos, bash and zsh)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-merge-mode.bats` (one test added)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
new file mode 100644
index 0000000..0cdc903
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -0,0 +1,82 @@
+#!/usr/bin/env bats
+# Executes the real bash blocks of command files in scratch repos, instead of
+# grepping their text. The R-001 review found defects that only show when a
+# block runs: an unset $WORKTREE making Phase 9 push the base branch, a mirror
+# restore that blocks worktree removal, a lib not sourced by the block that
+# calls it. A grep cannot see any of those.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch command-blocks)"
+  # Blocks source ~/.claude/skills/ship-workflow/lib/*.sh — point that at this tree.
+  export HOME="$SCRATCH/home"
+  mkdir -p "$HOME/.claude/skills"
+  ln -s "$SHIP_SKILL_ROOT" "$HOME/.claude/skills/ship-workflow"
+  cd "$SCRATCH"
+  git init -q --bare -b main origin.git
+  git init -q -b main repo
+  cd repo
+  git config user.email t@t
+  git config user.name t
+  mkdir -p .claude docs/learnings docs/product
+  echo 'merge_mode: mr' > .claude/ship-config.yml
+  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
+  echo roadmap > docs/product/ROADMAP.md
+  git add -A && git commit -q -m base
+  git remote add origin "$SCRATCH/origin.git"
+  git push -q origin main
+  export REPO="$SCRATCH/repo"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+# block <command file> <start ERE> <end ERE> — the bash fences between two lines.
+block() {
+  S="$2" E="$3" awk '$0 ~ ENVIRON["S"] {f=1} $0 ~ ENVIRON["E"] {f=0} f' \
+      "$SHIP_SKILL_ROOT/commands/$1" \
+    | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
+}
+
+p9_log_block() { block ship-next.md '^3\. \*\*Log \+ commit\.\*\*' '^4\. \*\*Auto-mode'; }
+
+@test "ship-next P9 (mr): an unset WORKTREE pushes nothing and writes nothing" {
+  git commit -q --allow-empty -m "local-only work on main"
+  p9_log_block > "$SCRATCH/p9.sh"
+  [ -s "$SCRATCH/p9.sh" ]
+  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
+  run env MERGE_MODE=mr WORKTREE= ID=R-1 bash "$SCRATCH/p9.sh"
+  [ "$status" -ne 0 ]
+  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
+  [ -z "$(git status --porcelain)" ] || { echo "the base checkout was written"; return 1; }
+}
+
+@test "ship-next P9 (mr): logs on the review branch and pushes only that branch" {
+  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
+  git commit -q --allow-empty -m "local-only work on main"
+  origin_main=$(git ls-remote origin refs/heads/main | cut -f1)
+  p9_log_block > "$SCRATCH/p9.sh"
+  run env MERGE_MODE=mr WORKTREE="$SCRATCH/wt" ID=R-1 bash "$SCRATCH/p9.sh"
+  [ "$status" -eq 0 ]
+  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_main" ]
+  git fetch -q origin ship/R-1-x
+  git log -1 --format='%(trailers:key=Ship-Log,valueonly)' FETCH_HEAD | grep -qF '| ship-next | R-1 |'
+}
+
+@test "ship-next P9 (squash): appends the row and commits it on the current branch" {
+  echo 'merge_mode: squash' > .claude/ship-config.yml
+  git commit -q -am "squash mode"
+  p9_log_block > "$SCRATCH/p9.sh"
+  run env MERGE_MODE=squash ID=R-1 bash "$SCRATCH/p9.sh"
+  [ "$status" -eq 0 ]
+  [ "$(git log -1 --format=%s)" = "log: ship R-1" ]
+  tail -1 docs/learnings/_log.md | grep -qF '| ship-next | R-1 |'
+}
+
+@test "zsh: ship-next P9 (mr) with an unset WORKTREE still pushes nothing" {
+  command -v zsh >/dev/null || skip "zsh not installed"
+  git commit -q --allow-empty -m "local-only work on main"
+  p9_log_block > "$SCRATCH/p9.sh"
+  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
+  run env MERGE_MODE=mr WORKTREE= ID=R-1 zsh "$SCRATCH/p9.sh"
+  [ "$status" -ne 0 ]
+  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-merge-mode.bats b/claude-skills/ship-workflow/tests/test_ship-next-merge-mode.bats
index 833de17..4b9b41d 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-merge-mode.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-merge-mode.bats
@@ -61,3 +61,9 @@ code() { sed 's/[[:space:]]*#.*$//' | grep -v '^[[:space:]]*$'; }
     bash -n "$BATS_TEST_TMPDIR/$f.sh" || { echo "$f does not parse"; return 1; }
   done
 }
+
+@test "Phase 8 says where /ship-compound runs in each mode" {
+  sec=$(awk '/^## Phase 8 — \/ship-compound/,/^## Phase 8\.5/' "$CMD")
+  echo "$sec" | grep -qF '`mr`: from `$WORKTREE`' \
+    || { echo "Phase 8 still sends mr-mode /ship-compound to the base checkout"; return 1; }
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-merge-mode.bats tests/test_ship-next-codex-loop.bats tests/test_ship-next-prune.bats; cd - >/dev/null`

Expected: `1..59`, 56 ok, these 3 fail:
  - `not ok 1 ship-next P9 (mr): an unset WORKTREE pushes nothing and writes nothing`
  - `not ok 4 zsh: ship-next P9 (mr) with an unset WORKTREE still pushes nothing`
  - `not ok 13 Phase 8 says where /ship-compound runs in each mode`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 07ade28..f76691a 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -1043,7 +1043,11 @@ review sets `merge_mode: mr`.
 
 1. **Invoke `/ship-compound`** for this R-NNN. It writes the learning, promotes patterns to AIR-OS, marks the ROADMAP row ✅.
 
-   `/ship-compound` runs from the original repo cwd (Phase 7 already cd'd back), so it touches the canonical ROADMAP in the vault directly.
+   Where it runs depends on the merge mode. `squash`: from the original repo cwd
+   (Phase 7 already cd'd back), on `$ORIG_BRANCH`. `mr`: from `$WORKTREE`, on the
+   review branch — the learning and the queued `CONTEXT.md` entries belong to the
+   review, and `/ship-compound` refuses to run its mr path anywhere else. Either way
+   it edits the canonical ROADMAP in the vault directly.
 
    `/ship-compound` now also updates `CONTEXT.md` and exports `CONTEXT_MD_STATUS`.
 
@@ -1254,10 +1258,20 @@ runs in `--auto:yes`. Because it is expensive, Phase 9 flags it explicitly.
    # shellcheck disable=SC1091
    source ~/.claude/skills/ship-workflow/lib/ship-log.sh
    if [ "$MERGE_MODE" = "mr" ]; then
-     cd "$WORKTREE"
-     ship_log "$SHIP_LOG_ROW"
-     git push origin HEAD
-     cd "$REPO"
+     # Log and push from the review branch only. `cd ""` succeeds silently in
+     # bash and zsh, so an unset $WORKTREE would otherwise leave this in $REPO on
+     # the base branch — and the push would send the base branch to origin.
+     (
+       [ -n "$WORKTREE" ] && cd "$WORKTREE" \
+         || { echo "Phase 9: WORKTREE is not set — nothing logged or pushed" >&2; exit 1; }
+       CUR=$(git branch --show-current)
+       case "$CUR" in
+         ship/*) : ;;
+         *) echo "Phase 9: refusing to log or push from '$CUR' — expected the ship/* review branch" >&2
+            exit 1 ;;
+       esac
+       ship_log "$SHIP_LOG_ROW" && git push origin "$CUR"
+     )
    else
      ship_log "$SHIP_LOG_ROW"
      git add docs/learnings/_log.md
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-merge-mode.bats tests/test_ship-next-codex-loop.bats tests/test_ship-next-prune.bats; cd - >/dev/null`

Expected: `1..59`, all 59 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-next): review-fix 3 — Phase 9 logs and pushes only from a ship/* branch; Phase 8 sends mr-mode compound to the worktree"
```

### Task 4: ship-compound: mr guard, mode resolved in step 9, failed adds stop the step

Seam: `ship_log`, `context_pending_add` (callers: ship-compound)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review 🟡 ship-compound.md:278 (squash `git add` split → silent partial commit) and :269 (mr path never checks it is on the review branch). Found while writing these tests: step 9 used `$MERGE_MODE` without resolving it — each step runs in its own shell, so it silently took the squash branch. Nit: the 6b over-cap warning named only the legacy file.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md` (step 6 mr block, 6b warning text, step 9)
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (three tests appended — they execute step 9)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index 0cdc903..ee84290 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -80,3 +80,47 @@ p9_log_block() { block ship-next.md '^3\. \*\*Log \+ commit\.\*\*' '^4\. \*\*Aut
   [ "$status" -ne 0 ]
   [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
 }
+
+compound_step9() { block ship-compound.md '^9\. \*\*Log \+ commit' '^10\. \*\*Report'; }
+
+@test "ship-compound step 9 (mr) refuses to run on the base branch" {
+  echo "learning" > docs/learnings/R-1-x.md
+  compound_step9 > "$SCRATCH/s9.sh"
+  [ -s "$SCRATCH/s9.sh" ]
+  head_before=$(git rev-parse HEAD)
+  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
+  [ "$status" -ne 0 ]
+  [ "$(git rev-parse HEAD)" = "$head_before" ]
+  git diff --quiet -- docs/learnings/_log.md || { echo "_log.md was written on base"; return 1; }
+}
+
+@test "ship-compound step 9 (mr) commits only this ship's own paths and pushes its branch" {
+  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
+  cd "$SCRATCH/wt"
+  echo "learning" > docs/learnings/R-1-x.md
+  mkdir -p docs/tdd-rules.d docs/ship-pending
+  echo '- A rule. ← R-1' > docs/tdd-rules.d/R-1.md
+  echo '- **Lane** — a queue' > docs/ship-pending/R-1-context.md
+  echo "synced from the vault" >> docs/product/ROADMAP.md
+  compound_step9 > "$SCRATCH/s9.sh"
+  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
+  [ "$status" -eq 0 ]
+  files=$(git show --name-only --format= HEAD | sort | tr '\n' ' ')
+  [ "$files" = "docs/learnings/R-1-x.md docs/ship-pending/R-1-context.md docs/tdd-rules.d/R-1.md " ]
+  git fetch -q origin ship/R-1-x
+  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD)" ]
+}
+
+@test "ship-compound step 9 (squash) stops before committing when a required path is missing" {
+  echo 'merge_mode: squash' > .claude/ship-config.yml
+  git commit -q -am "squash mode"
+  echo "learning" > docs/learnings/R-1-x.md
+  mkdir -p docs/tdd-rules.d
+  echo '- A rule. ← R-1' > docs/tdd-rules.d/R-1.md
+  # no docs/proposals/ in this repo
+  compound_step9 > "$SCRATCH/s9.sh"
+  head_before=$(git rev-parse HEAD)
+  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
+  [ "$status" -ne 0 ]
+  [ "$(git rev-parse HEAD)" = "$head_before" ]
+}
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-compound-merge-mode.bats tests/test_ship-compound-context.bats; cd - >/dev/null`

Expected: `1..20`, 17 ok, these 3 fail:
  - `not ok 5 ship-compound step 9 (mr) refuses to run on the base branch`
  - `not ok 6 ship-compound step 9 (mr) commits only this ship's own paths and pushes its branch`
  - `not ok 7 ship-compound step 9 (squash) stops before committing when a required path is missing`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-compound.md b/claude-skills/ship-workflow/commands/ship-compound.md
index fd736c6..8569a83 100644
--- a/claude-skills/ship-workflow/commands/ship-compound.md
+++ b/claude-skills/ship-workflow/commands/ship-compound.md
@@ -100,6 +100,16 @@ every ship editing it is what made parallel MRs conflict (R-001). Do sub-step 1,
 then queue each entry instead of doing sub-steps 2–4:
 
 ```bash
+# shellcheck disable=SC1091
+source ~/.claude/skills/ship-workflow/lib/context-md.sh
+# shellcheck disable=SC1091
+source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+# The queue belongs on the review branch. From the base checkout it would be
+# committed to base by step 9 — refuse instead (see step 9).
+ship_log_defers || {
+  echo "ship-compound: mr mode — run this from the ship's worktree (a ship/* branch)" >&2
+  exit 1
+}
 # Once per qualifying entry (continuation lines, if any, indented):
 # context_pending_add "$ID" "- **<term>** — <definition>"
 CONTEXT_MD_STATUS="queued for /ship-land"
@@ -188,7 +198,7 @@ Sub-steps 2–4 below are the `squash` path.
    # tdd_rules_append "$ID" "Never assert on log output; assert on the return value."
 
    if tdd_rules_over_cap; then
-     echo "WARN: docs/tdd-rules.md has $(tdd_rules_count) rules (cap ${TDD_RULES_MAX})." >&2
+     echo "WARN: this repo has $(tdd_rules_count) learned TDD rules in docs/tdd-rules.md + docs/tdd-rules.d/ (cap ${TDD_RULES_MAX})." >&2
      echo "      Review the oldest by their ← R-NNN source and drop what no longer applies." >&2
    fi
    UNSOURCED=$(tdd_rules_unsourced)
@@ -260,23 +270,38 @@ Sub-steps 2–4 below are the `squash` path.
    mirror is regenerated from the vault by every `sync.sh` run anyway.
 
    ```bash
+   # Each step runs in its own shell, so resolve the mode here rather than
+   # trusting a MERGE_MODE left over from step 6 or 7.
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
    # shellcheck disable=SC1091
    source ~/.claude/skills/ship-workflow/lib/ship-log.sh
+   MERGE_MODE=$(merge_mode)
    STATUS_WORD=shipped
    [ "$MERGE_MODE" = "mr" ] && STATUS_WORD=in-review
+
+   # mr mode writes to the review branch, so it must be standing on one. Run
+   # from the base checkout it would commit the learning to base and push it.
+   if [ "$MERGE_MODE" = "mr" ] && ! ship_log_defers; then
+     echo "ship-compound: merge_mode is mr but this is '$(git branch --show-current)', not a ship/* review branch — cd into the ship's worktree" >&2
+     exit 1
+   fi
+
    ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | $STATUS_WORD | n |"
 
    if [ "$MERGE_MODE" = "mr" ]; then
-     git add "docs/learnings/${ID}-${slug}.md"
+     git add "docs/learnings/${ID}-${slug}.md" || exit 1
      for p in docs/tdd-rules.d docs/ship-pending; do
-       [ -e "$p" ] && git add "$p"
+       if [ -e "$p" ]; then git add "$p" || exit 1; fi
      done
-     git commit -m "compound: $ID — $STATUS_WORD + learning"
+     git commit -m "compound: $ID — $STATUS_WORD + learning" || exit 1
      # The review is already open; push the learning onto the same branch.
-     git push origin HEAD
+     git push origin "$(git branch --show-current)"
    else
-     git add "docs/learnings/${ID}-${slug}.md" docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md
-     [ -e docs/tdd-rules.d ] && git add docs/tdd-rules.d
+     # One add for the required paths: if any is missing, stop here rather than
+     # commit a partial set under a title that claims all of it.
+     git add "docs/learnings/${ID}-${slug}.md" docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md || exit 1
+     if [ -e docs/tdd-rules.d ]; then git add docs/tdd-rules.d || exit 1; fi
      git commit -m "compound: $ID — $STATUS_WORD + learning + ROADMAP update"
    fi
    ```
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-compound-merge-mode.bats tests/test_ship-compound-context.bats; cd - >/dev/null`

Expected: `1..20`, all 20 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-compound): review-fix 4 — step 9 resolves the mode, refuses mr off a ship/* branch, stops on a failed add"
```

### Task 5: ship-land: source the lib per block, robust mirror restore, absolute-path guard, prune guidance

Seam: `land_is_merged`, `land_context` (callers: /ship-land)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review 🟡 ship-land.md:141 (mirror restore aborts on an untracked path; synced new files block removal), :88 (step 3 blocks call the lib without sourcing it), :120 (prune guidance contradicted the spec). Nits: :42 guard refused a subdirectory of the main checkout; :74 refusal message did not name rebase merges.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-land.md` (steps 1, 2, 3, 5)
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (three tests appended)
- Test: `claude-skills/ship-workflow/tests/test_ship-land.bats` (guard grep updated)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index ee84290..c3242a3 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -124,3 +124,43 @@ compound_step9() { block ship-compound.md '^9\. \*\*Log \+ commit' '^10\. \*\*Re
   [ "$status" -ne 0 ]
   [ "$(git rev-parse HEAD)" = "$head_before" ]
 }
+
+land_step5() { block ship-land.md '^5\. \*\*Clean up' '^6\. \*\*Report'; }
+
+@test "ship-land step 5 removes a worktree whose vault mirror sync dirtied" {
+  # sync.sh rewrites the mirror in every working tree, and since R-001 a review
+  # branch no longer commits it: tracked mirror files show as modified and new
+  # ones as untracked. Neither may block the cleanup.
+  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
+  echo "synced" >> "$SCRATCH/wt/docs/product/ROADMAP.md"
+  mkdir -p "$SCRATCH/wt/docs/proposals"
+  echo "new proposal" > "$SCRATCH/wt/docs/proposals/R-9-proposal.md"
+  land_step5 > "$SCRATCH/s5.sh"
+  [ -s "$SCRATCH/s5.sh" ]
+  run env BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
+  [ "$status" -eq 0 ]
+  [ ! -d "$SCRATCH/wt" ] || { echo "worktree not removed: $output"; return 1; }
+  run git rev-parse --verify -q refs/heads/ship/R-1-x
+  [ "$status" -ne 0 ]
+}
+
+@test "every ship-land block that calls the lib sources it — blocks do not share a shell" {
+  awk '/^[[:space:]]*```bash[[:space:]]*$/{n++; f=1; next} /^[[:space:]]*```[[:space:]]*$/{f=0} f{print n": "$0}' \
+    "$SHIP_SKILL_ROOT/commands/ship-land.md" > "$SCRATCH/blocks"
+  for n in $(grep -E 'land_context|land_is_merged|CONTEXT_MD_MAX' "$SCRATCH/blocks" | cut -d: -f1 | sort -u); do
+    grep -E "^$n: " "$SCRATCH/blocks" | grep -qF 'lib/ship-land.sh' \
+      || { echo "block $n calls the lib without sourcing it"; return 1; }
+  done
+}
+
+@test "ship-land's worktree guard: allows a subdirectory of the main checkout, refuses a worktree" {
+  cond=$(grep -F -- '--git-common-dir' "$SHIP_SKILL_ROOT/commands/ship-land.md" | head -1 \
+         | sed -e 's/^[[:space:]]*if //' -e 's/; then[[:space:]]*$//')
+  [ -n "$cond" ]
+  mkdir -p deep/dir
+  run bash -c "cd deep/dir && $cond"
+  [ "$status" -ne 0 ] || { echo "refuses a subdirectory of the main checkout"; return 1; }
+  git worktree add -q -b ship/R-2-x "$SCRATCH/wt2"
+  run bash -c "cd '$SCRATCH/wt2' && $cond"
+  [ "$status" -eq 0 ]
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-land.bats b/claude-skills/ship-workflow/tests/test_ship-land.bats
index f3a750c..3dee9f8 100644
--- a/claude-skills/ship-workflow/tests/test_ship-land.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-land.bats
@@ -52,5 +52,5 @@ setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-land.md"; }
 }
 
 @test "ship-land refuses to run from inside a worktree" {
-  grep -qF 'git rev-parse --git-common-dir' "$CMD" || { echo "no main-checkout guard"; return 1; }
+  grep -qF 'git rev-parse --path-format=absolute --git-common-dir' "$CMD" || { echo "no main-checkout guard"; return 1; }
 }
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-land.bats; cd - >/dev/null`

Expected: `1..19`, 15 ok, these 4 fail:
  - `not ok 8 ship-land step 5 removes a worktree whose vault mirror sync dirtied`
  - `not ok 9 every ship-land block that calls the lib sources it — blocks do not share a shell`
  - `not ok 10 ship-land's worktree guard: allows a subdirectory of the main checkout, refuses a worktree`
  - `not ok 19 ship-land refuses to run from inside a worktree`

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-land.md b/claude-skills/ship-workflow/commands/ship-land.md
index bfd1612..728b0be 100644
--- a/claude-skills/ship-workflow/commands/ship-land.md
+++ b/claude-skills/ship-workflow/commands/ship-land.md
@@ -39,7 +39,7 @@ Phase 9 already cleaned up.
 
    # From the main checkout, never from the ship's worktree: step 5 removes
    # that worktree, and git refuses to remove the one you are standing in.
-   if [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]; then
+   if [ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
      echo "run /ship-land from the main checkout, not from a worktree" >&2
      exit 2
    fi
@@ -71,8 +71,9 @@ Phase 9 already cleaned up.
    if ! land_is_merged "$BRANCH" "origin/${BASE}"; then
      echo "ERROR: $BRANCH is not merged into origin/$BASE." >&2
      echo "       The review is still open, or it was closed without merging." >&2
-     echo "       If it was merged with the forge's squash option, the branch tip is" >&2
-     echo "       not in origin/$BASE and this check cannot see the merge." >&2
+     echo "       If it was squash-merged or rebase-merged (GitHub \"Rebase and merge\"," >&2
+     echo "       GitLab fast-forward / semi-linear), the branch tip is not in" >&2
+     echo "       origin/$BASE and this check cannot see the merge." >&2
      echo "       Nothing has been changed." >&2
      exit 1
    fi
@@ -85,6 +86,9 @@ Phase 9 already cleaned up.
 3. **Fold the deferred CONTEXT.md entries onto the base branch.**
 
    ```bash
+   # Each block runs in its own shell — source what this one calls.
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-land.sh
    LAND_RESULT=$(land_context "$ID" "$BASE") || {
      echo "ERROR: could not land CONTEXT.md for $ID — ROADMAP and branch untouched." >&2
      exit 1
@@ -102,6 +106,8 @@ Phase 9 already cleaned up.
    the cap check:
 
    ```bash
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/ship-land.sh   # CONTEXT_MD_MAX_* live in context-md.sh, which it loads
    case "$LAND_RESULT" in
      landed*)
        VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
@@ -117,8 +123,10 @@ Phase 9 already cleaned up.
    esac
    ```
 
-   Over cap: prune as `/ship-compound` step 6.3 describes, in a normal commit on the
-   base branch. Pruning deletes, so it is never automatic.
+   Over cap: prune as `/ship-compound` step 6.3 describes, as its own change that
+   goes through review like any other — in `mr` mode, an MR. Pruning deletes
+   vocabulary, so it is never automatic and never folded into this command's
+   bookkeeping commit.
 
 4. **Move the ROADMAP row to Done.** Edit `$ROADMAP_PATH` (skip if already Done):
    - Find the `${ID}` line under "🔥 Now"
@@ -138,7 +146,13 @@ Phase 9 already cleaned up.
      # sync.sh rewrites the vault mirror in every working tree it runs in. Those
      # files are regenerated from the vault, never review content — restore them
      # so they do not block the removal.
-     git -C "$WORKTREE" checkout -- docs/product docs/proposals docs/roadmap-notes 2>/dev/null || true
+     for p in docs/product docs/proposals docs/roadmap-notes; do
+       # One path at a time: `checkout --` aborts on the first untracked path.
+       # `clean` removes mirror files synced after the branch point, which
+       # checkout cannot.
+       git -C "$WORKTREE" checkout -- "$p" 2>/dev/null || true
+       git -C "$WORKTREE" clean -fdq -- "$p"
+     done
      git worktree remove "$WORKTREE" || {
        echo "WARN: worktree at $WORKTREE has uncommitted changes; not removed." >&2
        echo "      Inspect, then: git worktree remove --force $WORKTREE" >&2
R001_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-land.bats; cd - >/dev/null`

Expected: `1..19`, all 19 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-land): review-fix 5 — every lib-calling block sources the lib; mirror restore per path with clean; absolute-path guard"
```

### Task 6: Split the D2 acceptance test

Seam: `ship_log`, `tdd_rules_append`, `context_pending_apply` (composition)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review nit test_parallel-mr.bats:64 [assertion-roulette] — one test bundled trailers, rule count and the CONTEXT fold.

**Files:**
- Test: `claude-skills/ship-workflow/tests/test_parallel-mr.bats` (D2 → D2a/D2b/D2c; no production code)

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R001_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_parallel-mr.bats b/claude-skills/ship-workflow/tests/test_parallel-mr.bats
index c6a9413..dae9039 100644
--- a/claude-skills/ship-workflow/tests/test_parallel-mr.bats
+++ b/claude-skills/ship-workflow/tests/test_parallel-mr.bats
@@ -61,15 +61,27 @@ ship_old_way() {
   [ "$status" -eq 1 ]
 }
 
-@test "D2: both ships' log rows reach main's history, and their rules and terms survive" {
+merge_both() {
   ship_new_way R-1
   ship_new_way R-2
   git merge -q --no-ff ship/R-1-x -m "Merge R-1"
   git merge -q --no-ff ship/R-2-x -m "Merge R-2"
+}
+
+@test "D2a: both ships' log rows reach main's history" {
+  merge_both
   rows=$(git log --format='%(trailers:key=Ship-Log,valueonly)' main | sed '/^$/d')
   echo "$rows" | grep -qF '| d | ship-next | R-1 |' || return 1
-  echo "$rows" | grep -qF '| d | ship-next | R-2 |' || return 1
+  echo "$rows" | grep -qF '| d | ship-next | R-2 |'
+}
+
+@test "D2b: both ships' TDD rules survive alongside the legacy one" {
+  merge_both
   [ "$(tdd_rules_count)" -eq 3 ]
+}
+
+@test "D2c: both ships' queued terms fold into CONTEXT.md without losing the seed" {
+  merge_both
   context_pending_apply R-1 >/dev/null
   context_pending_apply R-2 >/dev/null
   grep -qxF -- '- **TermR-1** — defined by R-1' CONTEXT.md
R001_PATCH
```

- [ ] **Step 2: Run the scoped tests**

Run: `cd claude-skills/ship-workflow && bats tests/test_parallel-mr.bats; cd - >/dev/null`

Expected: `1..6`, all 6 ok — this task only restructures tests, so they pass immediately.

- [ ] **Step 3: (no production code in this task)**

- [ ] **Step 4: (covered by Step 2)**

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "test(parallel-mr): review-fix 6 — split D2 into one behaviour per test"
```

### Task 7: Sync the spec with the review fixes

Seam: none (refactor)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review nits [seam-violation] on test_ship-log.bats:26, test_context-pending.bats:30, test_ship-land-lib.bats:52 — the tests pin real, intended behaviour (index preservation, the echoed count, the exact commit subject); the fix is to declare it in the Seams table, not to drop the assertions.

**Files:**
- Modify: `docs/specs/R-001-add-ship-land-defer-writes.md` (§4.5–§4.9, Seams table, AC-B6–B8)

- [ ] **Step 1: (no test change — documentation only)**

- [ ] **Step 2: (nothing to run)**

- [ ] **Step 3: Implement**

```bash
git apply <<'R001_PATCH'
diff --git a/docs/specs/R-001-add-ship-land-defer-writes.md b/docs/specs/R-001-add-ship-land-defer-writes.md
index 44b88fc..c0d3fe6 100644
--- a/docs/specs/R-001-add-ship-land-defer-writes.md
+++ b/docs/specs/R-001-add-ship-land-defer-writes.md
@@ -146,9 +146,12 @@ forever and the test budget never blocks.
 - `tdd_rules_path` keeps its current meaning (the legacy file or nothing).
 
 ### 4.5 `lib/context-md.sh`
-- `context_pending_add <R-NNN> "<entry>"` — validates `^- \*\*[^*]+\*\* — `, then
-  appends the entry (with any indented continuation lines) to
-  `docs/ship-pending/<R-NNN>-context.md`. Touches nothing else.
+- `context_pending_add <R-NNN> "<entry>"` — validates that the first line matches
+  `^- \*\*[^*]+\*\* — ` and that every later line is either indented (a continuation)
+  or another such entry line, then appends it to
+  `docs/ship-pending/<R-NNN>-context.md`. An unindented or blank later line is
+  refused (exit 2): `context_pending_apply` would drop it after the queue had been
+  reviewed and merged. Touches nothing else.
 - `context_pending_apply <R-NNN>` — run at a base-branch checkout root. If the pending
   file is absent: exit 0, no output. Otherwise, for each pending entry in order: if
   `CONTEXT.md` has an entry with the same `**term**`, replace that entry **including
@@ -165,51 +168,69 @@ forever and the test budget never blocks.
      echo `none`, exit 0.
   3. `context_pending_apply`; stage `CONTEXT.md` and `docs/ship-pending/`; commit
      `context: land <R-NNN> [skip ci]`; `git push origin HEAD:<base>`.
-  4. Push rejected → discard the temp worktree and redo from step 1 on the fresh
-     `origin/<base>`. The fold is deterministic, so a redo cannot conflict. At most 3
-     attempts, then exit 1.
+  4. Push rejected → fetch again. If `origin/<base>` moved, it was a lost race:
+     discard the temp worktree and redo from step 1 on the fresh tip. The fold is
+     deterministic, so a redo cannot conflict. At most 3 attempts, then exit 1. If
+     `origin/<base>` did not move (protected branch, auth, network), print git's own
+     error and exit 1 at once — retrying cannot help and would hide the cause.
   5. Success → echo `landed <sha>`. The temp worktree is always removed.
 
 ### 4.7 `commands/ship-compound.md`
 - **Step 6, mr mode:** call `context_pending_add` per entry instead of editing
   `CONTEXT.md`; skip the cap check, commit and vault mirror. `/ship-land` does those.
-  Squash mode is unchanged.
-- **Step 9, mr mode:** stage `docs/learnings/${ID}-${slug}.md`, `docs/tdd-rules.d/`
-  and `docs/ship-pending/` only — **not** `docs/product/`, `docs/proposals/` or
-  `_log.md`. Write the row with `ship_log`, commit, `git push origin HEAD`.
+  Refuse (exit 1) unless on a `ship/*` branch (`ship_log_defers`). Squash mode is
+  unchanged.
+- **Step 9:** resolves `MERGE_MODE` itself — each step runs in its own shell.
+- **Step 9, mr mode:** refuse (exit 1) unless on a `ship/*` branch. Stage
+  `docs/learnings/${ID}-${slug}.md`, `docs/tdd-rules.d/` and `docs/ship-pending/` only
+  — **not** `docs/product/`, `docs/proposals/` or `_log.md`. Write the row with
+  `ship_log`, commit, push the current branch. A failed `git add` stops the step.
+- **Step 9, squash mode:** the required paths are added in one `git add`; if it fails
+  the step stops before committing (as before R-001), instead of committing a partial
+  set under a title that claims all of it.
 - **Step 9, both modes:** stage `docs/tdd-rules.d/`. Today 6b's appended rule is
   never staged by any step.
 - **Step 10, mr mode:** report "row marked in-review — run `/ship-land ${ID}` after
   the MR merges".
 
 ### 4.8 `commands/ship-next.md`
-- **Phase 9 step 3:** write the row with `ship_log`. In mr mode, run it in
-  `$WORKTREE` and `git push origin HEAD` so the trailer travels with the MR. Squash
-  mode keeps `git add` + `git commit -m "log: ship ${ID}"` on `$ORIG_BRANCH`.
+- **Phase 8:** say where `/ship-compound` runs: squash — the original repo cwd; mr —
+  `$WORKTREE`, on the review branch.
+- **Phase 9 step 3:** write the row with `ship_log`. In mr mode, in a subshell: refuse
+  (exit 1, nothing logged or pushed) if `$WORKTREE` is empty or the branch there is not
+  `ship/*` — `cd ""` succeeds silently, and the push would otherwise send the base
+  branch to origin — else log and push that branch so the trailer travels with the MR.
+  Squash mode keeps `git add` + `git commit -m "log: ship ${ID}"` on `$ORIG_BRANCH`.
 - Fix the stale comment above it ("Auto mode picks executor 1…"): auto mode now
   picks codex.
 
 ### 4.9 `commands/ship-land.md` (rewrite)
 1. **Resolve.** Refuse (exit 2) when run inside a linked worktree — step 5 removes
-   the ship's worktree, and git cannot remove the one it is run from. `ID` from the
+   the ship's worktree, and git cannot remove the one it is run from. Compare
+   `--path-format=absolute` git-dir and common-dir, so a subdirectory of the main
+   checkout is not mistaken for a worktree. `ID` from the
    argument; repo root; `BASE` from
    `refs/remotes/origin/HEAD` (fallback `main`); `BRANCH` = local `ship/${ID}-*`.
    No local branch: if the vault ROADMAP row is already Done, report "already landed"
    and exit 0; else error.
 2. **Gate.** `git fetch origin --prune`; `land_is_merged "$BRANCH" "origin/$BASE"`.
-   On failure: say the MR is open or was closed unmerged (or squash-merged, §8 R1),
+   On failure: say the MR is open or was closed unmerged (or squash- or
+   rebase-merged, §8 R1),
    that nothing changed, and exit 1. The local branch is checked because Phase 7 opens
    MRs with `--remove-source-branch`.
-3. **Fold CONTEXT.** `land_context "$ID" "$BASE"`. Exit 1 → stop; ROADMAP and branch
+3. **Fold CONTEXT.** Every block that calls the lib sources it (each block runs in its
+   own shell). `land_context "$ID" "$BASE"`. Exit 1 → stop; ROADMAP and branch
    untouched. `landed` → mirror `origin/$BASE:CONTEXT.md` to the vault with
    `spec-mirror.sh`; run the cap check and, interactively, prune per `ship-compound`
-   step 6.3 (a prune is a second `[skip ci]` commit through the same path).
+   step 6.3 as its own reviewed change (an MR in mr mode). Pruning deletes
+   vocabulary, so it is never folded into this command's bookkeeping commit.
 4. **ROADMAP.** In the vault, move the row from "🔥 Now" to "✅ Done" with
    `· ✅ <date>`, stripping `status=in-review`, `mr=<url>` and `adhoc-inserted=true`.
    Atomic `.tmp` + `mv`. Skip if already Done.
-5. **Clean up.** In the worktree, restore the mirror paths
-   (`git checkout -- docs/product docs/proposals docs/roadmap-notes`) so a sync-dirtied
-   mirror does not block removal; `git worktree remove`; `git branch -D "$BRANCH"`;
+5. **Clean up.** In the worktree, for each mirror path (`docs/product`,
+   `docs/proposals`, `docs/roadmap-notes`) separately: `git checkout -- <p>` then
+   `git clean -fdq -- <p>`, so neither a sync-modified tracked file nor a newly synced
+   untracked one blocks removal; `git worktree remove`; `git branch -D "$BRANCH"`;
    `git push origin --delete "$BRANCH"` (ignore "not found").
    `-D` is safe **because** step 2 proved the tip is in `origin/$BASE`. `-d` would
    compare against the possibly-stale local base and refuse.
@@ -227,15 +248,15 @@ No `git pull`, `_log.md` write or ROADMAP-mirror commit on the operator's checko
 
 | Seam | Interface | Guaranteed behavior |
 |---|---|---|
-| `ship_log` | `ship_log "<row>"`, cwd = repo or worktree root | mr + `ship/*` branch: exactly one new commit, empty tree change, with trailer `Ship-Log: <row>`; `_log.md` byte-identical. Else: `<row>` appended as one line; no commit. Exit 2 on empty row. |
+| `ship_log` | `ship_log "<row>"`, cwd anywhere in the repo or worktree | mr + `ship/*` branch: exactly one new commit, subject `log: <cmd> <id>`, empty tree change, with trailer `Ship-Log: <row>`; anything already staged stays staged and is not in that commit; `_log.md` byte-identical. Else: `<row>` appended as one line; no commit. Exit 2 on empty row. |
 | `ship_log_ratio_count` | `ship_log_ratio_count` → integer | count of `ratio ` rows in `_log.md` + `ratio ` Ship-Log trailers reachable from HEAD |
 | `tb_shadow_active` | exit 0 = shadow | shadow iff `ship_log_ratio_count` < `TB_SHADOW_SHIPS` |
 | `tdd_rules_append` | `tdd_rules_append R-NNN "<rule>"` | rule present exactly once across legacy + fragments, written to `docs/tdd-rules.d/R-NNN.md`; legacy file never modified; exit 2 without an R-NNN or with empty text |
 | tdd rule readers | `tdd_rules_count`, `tdd_rules_unsourced`, `tdd_rules_render` | see legacy rules then fragment rules (by filename); render output for a repo with only a legacy file is unchanged |
-| `context_pending_add` | `context_pending_add R-NNN "<entry>"` | entry appended to `docs/ship-pending/R-NNN-context.md`; nothing else written; exit 2 on a malformed entry |
-| `context_pending_apply` | `context_pending_apply R-NNN`, cwd = base checkout | every pending entry present in `CONTEXT.md` exactly once (same term replaced with its continuation lines, new term appended); pending file deleted; no-op when absent; no git operations |
+| `context_pending_add` | `context_pending_add R-NNN "<entry>"` | entry appended to `docs/ship-pending/R-NNN-context.md`; nothing else written; exit 2, nothing written, on a malformed first line or a later line that is neither indented nor an entry |
+| `context_pending_apply` | `context_pending_apply R-NNN`, cwd = base checkout | every pending entry present in `CONTEXT.md` exactly once (same term replaced with its continuation lines, new term appended); pending file deleted; echoes the number of distinct terms applied; no-op (no output) when absent; no git operations |
 | `land_is_merged` | `land_is_merged <branch> <base-ref>` | exit 0 iff branch tip is an ancestor of base-ref |
-| `land_context` | `land_context R-NNN <base>` | `none` + no commit when no pending file on `origin/<base>`; else `landed <sha>` where `<sha>` is on `origin/<base>`, message contains `[skip ci]`, and the pending file is gone there; retries a rejected push up to 3 attempts; caller's checkout and current branch untouched |
+| `land_context` | `land_context R-NNN <base>` | `none` + no commit when no pending file on `origin/<base>`; else `landed <sha>` where `<sha>` is on `origin/<base>`, message is exactly `context: land R-NNN [skip ci]`, and the pending file is gone there; a push rejected by a concurrent push is redone, up to 3 attempts; any other rejection exits 1 at once with git's error on stderr; the temp worktree is removed on every exit path that returns; caller's checkout and current branch untouched |
 
 ## §5 Acceptance
 
@@ -248,6 +269,9 @@ No `git pull`, `_log.md` write or ROADMAP-mirror commit on the operator's checko
 | AC-B3 | origin/main has no pending file for R-9 | `land_context R-9 main` | prints `none`; origin/main unchanged |
 | AC-B4 | origin/main advances between fetch and push on the first attempt | `land_context` | succeeds on retry; both commits on origin/main |
 | AC-B5 | `commands/ship-land.md` | inspected | uses `land_is_merged` and `land_context`; no `_log.md` write; no `git pull`; `~/.claude/commands/ship-land.md` resolves to it |
+| AC-B6 | a push rejected while `origin/main` did not move | `land_context` | exit 1 after one attempt, git's error on stderr |
+| AC-B7 | mr mode, `$WORKTREE` empty, local-only commits on main | ship-next Phase 9 step 3 block runs (bash and zsh) | exit ≠ 0; origin/main unchanged; base checkout unwritten |
+| AC-B8 | a ship worktree with a sync-modified tracked mirror file and an untracked synced proposal | ship-land step 5 block runs | worktree removed, branch deleted |
 | AC-C1 | squash mode, or any repo on its base branch | `ship_log "<row>"` | row appended to `_log.md`; no commit created |
 | AC-C2 | repo with only a legacy `docs/tdd-rules.md` | `tdd_rules_render` | output identical to before this change |
 | AC-D1 | CONTEXT.md has `**Foo**` with a continuation line; pending has a new `**Foo**` and a new `**Bar**` | `context_pending_apply` | one `**Foo**` (the new text, old continuation gone), `**Bar**` appended, pending file deleted |
R001_PATCH
```

- [ ] **Step 4: Check the patch applied**

Run: `git diff --stat`

Expected: only `docs/specs/R-001-add-ship-land-defer-writes.md` changed.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow docs/specs
git commit -m "docs(spec): review-fix 7 — R-001 spec matches the review fixes; Seams declare what the tests pin"
```

### Task 8: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..534`, 533 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: No commit** — report DONE with the Step 1 counts.
