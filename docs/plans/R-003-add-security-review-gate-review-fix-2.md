# R-003 Review-fix Plan (attempt 2) — blockers, importants and nits from the Phase 6 review

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the review findings from the R-003 Phase 6 review in one pass: 2 blocking, 6 important (one tagged pre-existing), and 6 nits. Each fix is pinned by a test that fails before it.

**Architecture:** Same seams as `docs/plans/R-003-add-security-review-gate.md`. New here: `pre_existing_strip_unverified` and `PRE_EXISTING_RE`, the single definition of where the `[pre-existing]` tag counts. Command-level fixes are pinned by `tests/test_command-blocks.bats`, which *executes* the real Phase 6 blocks in scratch repos.

**Tech Stack:** bash + zsh, git ≥ 2.38, bats 1.13, awk, iconv.

**Spec:** `docs/specs/R-003-add-security-review-gate.md` (Task 5 updates it). Review: `.ship/review-R-003-1.md`.

## Global Constraints

- **Scope.** Every file you edit is under `claude-skills/ship-workflow/` or `docs/specs/` in THIS repository. `claude-skills/` is this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/` or the operator's home directory. The tests set their own `HOME` to a scratch dir; that is how they stay away from the real one.
- **Not part of this plan:** `.ship/proto/`, `.ship/scratch/` and `.ship/upstream/` are scratch state. Do not read, edit or stage them. Stage only the paths each commit step names, never `git add -A`, because `.ship/proto` is a nested git repository.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise.
- **Patches are the code.** Each code step is a `git apply` heredoc, generated from and replayed against this exact base (`7594ab1`). They apply cleanly in order. If one does not apply, STOP. Do not hand-edit around it.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 6.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** no `local` inside a loop body; no unquoted globs that may match nothing.
- **Commits.** One commit per task, with the exact message given. Never amend, never push, never switch branches. Commit subjects say `review-fix N`, not `Task N`, so Phase 6's gate does not confuse them with the original plan's tasks.

## Review Focus

These are the failure modes behind the review's findings that a person is most likely to hit next. Each has a test in the owning task:

1. A security finding hidden by how the reports are joined or shaped: a missing trailing newline, or a bulleted or bold HIGH. → Tasks 1, 2.
2. A report left by an earlier run standing in for this run's: `SEC_OUT` or `REVIEW_OUT`. → Task 4.
3. A broken setup that reads as a clean pass: a missing lib taken as "off", or a failed parse taken as zero blockers. → Task 4.
4. `[pre-existing]` used as an escape hatch: the tag quoted in a description, in mixed case, or citing a file this diff created. → Tasks 1, 4.
5. A prompt-injection finding discarded by a filter sub-task that never saw the AI-input category. → Task 3.

---
### Task 1: Reports keep their line boundaries; only the anchored `[pre-existing]` tag counts

Seam: `code-review-parse.sh`, `PRE_EXISTING_RE` / `pre_existing_lines`, `pre_existing_key`, `pre_existing_strip_unverified`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🔴 code-review-parse.sh:55 — `cat "$@"` glued a report without a trailing newline onto the next report's first finding, so a security blocker went uncounted.
- 🟡 code-review-parse.sh:61 — the exclusion matched `[pre-existing]` anywhere in a line, in any case, so a description that merely quoted the tag stopped blocking.
- 🟢 code-review-parse.sh:107 — `SECURITY_COUNT` counted prose and detail lines, not just finding lines.
- 🟢 pre-existing.sh:24 — `cut -c1-40` is byte-based without a UTF-8 locale and cut a Chinese description mid-character, so the key could never match an IDEA.
- New seam `pre_existing_strip_unverified`: the tag check becomes mechanical. Step 1.6 calls it in Task 4.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/code-review-parse.sh`
- Modify: `claude-skills/ship-workflow/lib/pre-existing.sh`
- Test: `claude-skills/ship-workflow/tests/test_code-review-parse.bats`
- Test: `claude-skills/ship-workflow/tests/test_pre-existing.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_code-review-parse.bats b/claude-skills/ship-workflow/tests/test_code-review-parse.bats
index 95112c8..388c0cf 100644
--- a/claude-skills/ship-workflow/tests/test_code-review-parse.bats
+++ b/claude-skills/ship-workflow/tests/test_code-review-parse.bats
@@ -267,3 +267,34 @@ EOF
   run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/ok.md" "$SCRATCH/missing.md"
   [ "$status" -eq 2 ]
 }
+
+# --- R-003 review round 1 ------------------------------------------------------
+
+@test "code-review-parse: a report without a trailing newline does not swallow the next one's first finding" {
+  # Claude's Write tool leaves no trailing newline when content lacks one; `cat`
+  # then glued the security report's HIGH onto the review's last line (fail open).
+  printf '🟢 [nit] a.sh:3 — style' > "$SCRATCH/rev.md"
+  printf '🔴 [blocking] [security:command_injection] b.sh:1 — x\n' > "$SCRATCH/sec.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/rev.md" "$SCRATCH/sec.md"
+  echo "$output" | grep -qx 'BLOCKING_COUNT=1'
+}
+
+@test "code-review-parse: a description that quotes the tag still counts as this ship's finding" {
+  printf '%s\n' '🔴 [blocking] b.py:4 — user text can forge the [pre-existing] marker the gate trusts' > "$SCRATCH/q.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/q.md"
+  echo "$output" | grep -qx 'BLOCKING_COUNT=1' || return 1
+  echo "$output" | grep -qx 'PRE_EXISTING_COUNT=0'
+}
+
+@test "code-review-parse: a mixed-case or misplaced tag fails closed" {
+  printf '%s\n' '🔴 [blocking] [Pre-Existing] c.py:1 — x' '🔴 [blocking] src/[pre-existing]/run.sh:2 — y' > "$SCRATCH/m.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/m.md"
+  echo "$output" | grep -qx 'BLOCKING_COUNT=2' || return 1
+  echo "$output" | grep -qx 'PRE_EXISTING_COUNT=0'
+}
+
+@test "code-review-parse: SECURITY_COUNT counts finding lines only" {
+  printf '%s\n' 'Notes: see [security:xss] above' '🟡 [important] [security:xss] v.js:9 — innerHTML' '   Recommendation: escape it, [security:xss] style' > "$SCRATCH/n.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/n.md"
+  echo "$output" | grep -qx 'SECURITY_COUNT=1'
+}
diff --git a/claude-skills/ship-workflow/tests/test_pre-existing.bats b/claude-skills/ship-workflow/tests/test_pre-existing.bats
index 9034a78..5220dac 100644
--- a/claude-skills/ship-workflow/tests/test_pre-existing.bats
+++ b/claude-skills/ship-workflow/tests/test_pre-existing.bats
@@ -45,3 +45,48 @@ teardown() { rm -rf "$SCRATCH"; }
   run pre_existing_tracked 'a.py:prompt_injection'
   [ "$status" -ne 0 ]
 }
+
+# --- R-003 review round 1 ------------------------------------------------------
+
+@test "lines: only a tag right after the severity tag marks a pre-existing finding" {
+  printf '%s\n' \
+    '🔴 [blocking] [pre-existing] a.py:3 — old' \
+    '🔴 [blocking] b.py:4 — quotes the [pre-existing] marker' \
+    '🟡 [important] [Pre-Existing] c.py:5 — mixed case' > "$SCRATCH/r.md"
+  run pre_existing_lines "$SCRATCH/r.md"
+  [ "$output" = '🔴 [blocking] [pre-existing] a.py:3 — old' ]
+}
+
+@test "strip_unverified: a file the diff created cannot hold a pre-existing defect" {
+  git config user.email t@t && git config user.name t
+  echo old > a.py && git add -A && git commit -q -m base && git branch -m main
+  git checkout -q -b ship/R-1-x && echo new > new.py && git add -A && git commit -q -m new
+  printf '%s\n' \
+    '🔴 [blocking] [pre-existing] a.py:1 — exists on main' \
+    '   Base evidence: a.py:1 exists unchanged on main' \
+    '🔴 [blocking] [pre-existing] new.py:1 — only on this branch' \
+    '🟡 [important] [pre-existing] no location given' > "$SCRATCH/r.md"
+  pre_existing_strip_unverified main "$SCRATCH/r.md"
+  expected=$(printf '%s\n' \
+    '🔴 [blocking] [pre-existing] a.py:1 — exists on main' \
+    '   Base evidence: a.py:1 exists unchanged on main' \
+    '🔴 [blocking] new.py:1 — only on this branch' \
+    '🟡 [important] no location given')
+  [ "$(cat "$SCRATCH/r.md")" = "$expected" ]
+}
+
+@test "strip_unverified: an unresolvable base exits 2 and changes nothing" {
+  printf '%s\n' '🔴 [blocking] [pre-existing] a.py:1 — x' > "$SCRATCH/r.md"
+  cp "$SCRATCH/r.md" "$SCRATCH/r.before"
+  run pre_existing_strip_unverified no-such-branch "$SCRATCH/r.md"
+  [ "$status" -eq 2 ]
+  cmp -s "$SCRATCH/r.md" "$SCRATCH/r.before"
+}
+
+@test "key: a non-ASCII description is never cut mid-character" {
+  # A key ending in a lone UTF-8 lead byte can never be reproduced in an IDEA, so
+  # pre_existing_tracked would never match and every ship would re-file it.
+  run pre_existing_key '🟡 [important] [pre-existing] x.py:1 — 使用者訊息直接拼進系統提示詞沒有任何隔離或跳脫處理'
+  [ "$status" -eq 0 ]
+  printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || { echo "key is not valid UTF-8"; return 1; }
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats tests/test_pre-existing.bats; cd - >/dev/null`

Expected: `1..35`, 28 ok, these 7 fail:
  - `not ok 22 code-review-parse: a report without a trailing newline does not swallow the next one's first finding`
  - `not ok 23 code-review-parse: a description that quotes the tag still counts as this ship's finding`
  - `not ok 24 code-review-parse: a mixed-case or misplaced tag fails closed`
  - `not ok 25 code-review-parse: SECURITY_COUNT counts finding lines only`
  - `not ok 32 lines: only a tag right after the severity tag marks a pre-existing finding`
  - `not ok 33 strip_unverified: a file the diff created cannot hold a pre-existing defect`
  - `not ok 34 strip_unverified: an unresolvable base exits 2 and changes nothing`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/code-review-parse.sh b/claude-skills/ship-workflow/lib/code-review-parse.sh
index 07cdfd3..b2d3af7 100755
--- a/claude-skills/ship-workflow/lib/code-review-parse.sh
+++ b/claude-skills/ship-workflow/lib/code-review-parse.sh
@@ -49,16 +49,22 @@ for f in "$@"; do
   [ -f "$f" ] || { echo "ERROR: input file not found: $f" >&2; exit 2; }
 done
 
+# The anchored [pre-existing] rule lives in one place, shared with Phase 6 step 4.5.
+# shellcheck disable=SC1091
+. "$(cd "$(dirname "$0")" && pwd)/pre-existing.sh"
+
 ALL=$(mktemp "${TMPDIR:-/tmp}/crp-all.XXXXXX")
 FILE=$(mktemp "${TMPDIR:-/tmp}/crp-kept.XXXXXX")
 trap 'rm -f "$ALL" "$FILE"' EXIT
-cat "$@" > "$ALL"
+# `awk 1` ends every file's last line. A plain `cat` glued the next report's first
+# line onto a report written without a trailing newline, hiding a HIGH finding.
+awk 1 "$@" > "$ALL"
 
 # `[pre-existing]` findings (R-003) exist on the base branch already: they are
 # reported, but they never count toward any severity — so they can never block a
-# ship or be asked about as one of its own importants. Everything below counts
-# the remaining lines.
-grep -viF '[pre-existing]' "$ALL" > "$FILE" || true
+# ship or be asked about as one of its own importants. Only the anchored tag
+# counts (PRE_EXISTING_RE). Everything below counts the remaining lines.
+grep -vE "$PRE_EXISTING_RE" "$ALL" > "$FILE" || true
 
 # Each helper greps lines matching ANY pattern for the level and counts.
 # Note: `grep -c` counts matching lines, not match instances — so duplicate
@@ -105,11 +111,12 @@ count_weak_assertion() {
 }
 
 count_pre_existing() {
-  grep -ciF '[pre-existing]' "$ALL" || true
+  grep -cE "$PRE_EXISTING_RE" "$ALL" || true
 }
 
 count_security() {
-  grep -ciF '[security:' "$FILE" || true
+  # Finding lines only — not prose or indented detail lines that mention a category.
+  grep -ciE '^[[:space:]]*(🔴|🟡|🟢|\[blocking\]|\[important\]|\[major\]|\[minor\]|\[nit\]).*\[security:' "$FILE" || true
 }
 
 BLOCKING=$(count_blocking)
diff --git a/claude-skills/ship-workflow/lib/pre-existing.sh b/claude-skills/ship-workflow/lib/pre-existing.sh
index 59116db..878d169 100644
--- a/claude-skills/ship-workflow/lib/pre-existing.sh
+++ b/claude-skills/ship-workflow/lib/pre-existing.sh
@@ -9,6 +9,17 @@
 # `(pre-existing-key: <key>)`. The parentheses delimit the key, so `a.py:sql` is
 # never mistaken for `a.py:sql_injection`.
 
+# The ONE position a `[pre-existing]` tag counts in: right after the severity tag at
+# the start of a finding line, exactly as review-extra-checks.md and the security
+# prompt prescribe. Anywhere else — quoted in a description, inside a path, in mixed
+# case — it is just text, and the finding counts as this ship's own. Fail closed.
+PRE_EXISTING_RE='^[[:space:]]*(🔴|🟡|🟢|🎉)?[[:space:]]*\[(blocking|important|major|minor|nit|praise)\][[:space:]]*\[pre-existing\]'
+
+# pre_existing_lines <file>… — print the finding lines tagged in that position.
+pre_existing_lines() {
+  grep -hE "$PRE_EXISTING_RE" "$@" 2>/dev/null || true
+}
+
 # pre_existing_key <finding-line> — echo `<file>:<category>` for a finding tagged
 # `[security:<category>]`, else `<file>:<first 40 chars of the description,
 # lowercased>`. Exit 2 when the line names no `<file>:<line>`.
@@ -21,7 +32,10 @@ pre_existing_key() {
     echo "$file:$cat"
     return 0
   fi
-  desc=$(printf '%s\n' "$line" | sed 's/^.* — //' | tr '[:upper:]' '[:lower:]' | cut -c1-40)
+  # Byte cut, then drop any partial UTF-8 character it left at the end: a key that
+  # ends mid-character can never be reproduced in an IDEA, so it would never match.
+  desc=$(printf '%s\n' "$line" | sed 's/^.* — //' | tr '[:upper:]' '[:lower:]' \
+         | LC_ALL=C cut -c1-40 | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
   echo "$file:$desc"
 }
 
@@ -34,3 +48,28 @@ pre_existing_tracked() {
   [ -d "$root/docs/ideas" ] || return 1
   grep -rqF -- "(pre-existing-key: $key)" "$root/docs/ideas" 2>/dev/null
 }
+
+# pre_existing_strip_unverified <base> <file>… — in place, drop the tag from every
+# pre-existing finding whose cited file does not exist on <base> (or that cites no
+# file at all): a file this diff created cannot hold a pre-existing defect. Such a
+# finding then counts as this ship's own. Exit 2 when <base> does not resolve.
+pre_existing_strip_unverified() {
+  local base="$1" f line file tmp
+  git rev-parse --verify -q "${base}^{commit}" >/dev/null 2>&1 || return 2
+  shift
+  for f in "$@"; do
+    [ -f "$f" ] || continue
+    tmp="$f.strip.$$"
+    : > "$tmp"
+    while IFS= read -r line || [ -n "$line" ]; do
+      if printf '%s\n' "$line" | grep -qE "$PRE_EXISTING_RE"; then
+        file=$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9_./-]+:[0-9]+' | head -1 | cut -d: -f1)
+        if [ -z "$file" ] || ! git cat-file -e "${base}:${file}" 2>/dev/null; then
+          line=$(printf '%s\n' "$line" | sed 's/\[pre-existing\][[:space:]]*//')
+        fi
+      fi
+      printf '%s\n' "$line" >> "$tmp"
+    done < "$f"
+    mv "$tmp" "$f"
+  done
+}
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats tests/test_pre-existing.bats; cd - >/dev/null`

Expected: `1..35`, all 35 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(review-parse): review-fix 1 — reports keep their line boundaries; only the anchored [pre-existing] tag counts"
```

### Task 2: The security output check rejects any line outside the finding format

Seam: `security_review_output_check`, `security_review_render`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🟡 security-review.sh:72 — one well-formed line excused a HIGH finding written in any other shape, such as `- 🔴 …` or `**HIGH**`. That finding then parsed as zero.
- 🟢 security-review.sh:51 — the self-configuration flag missed the repo's own `.claude/commands/ship-next.md`, and its pathspecs depended on the cwd.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/security-review.sh`
- Test: `claude-skills/ship-workflow/tests/test_security-review.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review.bats b/claude-skills/ship-workflow/tests/test_security-review.bats
index 156d1d0..4ba95b0 100644
--- a/claude-skills/ship-workflow/tests/test_security-review.bats
+++ b/claude-skills/ship-workflow/tests/test_security-review.bats
@@ -118,3 +118,37 @@ on_main() {  # on_main <path> <content> — commit a file on main, return to the
   [ "$status" -eq 0 ]
   cmp -s "$SCRATCH/bash.md" "$SCRATCH/zsh.md"
 }
+
+# --- R-003 review round 1 ------------------------------------------------------
+
+@test "output_check: one good line does not excuse a finding in any other shape" {
+  # Each of these HIGHs would parse as zero findings and pass the gate.
+  for bad in '- 🔴 [blocking] [security:sqli] a.py:3 — bullet form' \
+             '## Vuln 2: SQLi: `a.py:3`' \
+             '**HIGH** SQL injection in a.py:3'; do
+    printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' "$bad" > "$SCRATCH/mixed.md"
+    run security_review_output_check "$SCRATCH/mixed.md"
+    [ "$status" -eq 3 ] || { echo "accepted: $bad"; return 1; }
+  done
+}
+
+@test "output_check: several well-formed findings with detail lines pass" {
+  printf '%s\n' \
+    '🔴 [blocking] [security:sql_injection] app.py:2 — f-string SQL' \
+    '   Exploit scenario: id=1 OR 1=1' \
+    '   Recommendation: bind parameters' \
+    '   Confidence: 9/10' \
+    '' \
+    '🟡 [important] [pre-existing] [security:prompt_injection] p.py:7 — flat prompt' \
+    '   Base evidence: p.py:7 exists unchanged on main' > "$SCRATCH/ok.md"
+  run security_review_output_check "$SCRATCH/ok.md"
+  [ "$status" -eq 0 ]
+}
+
+@test "render: a diff that edits the repo's own ship-next command is flagged, from any directory" {
+  mkdir -p .claude/commands src && echo "no step 1.5 here" > .claude/commands/ship-next.md
+  git add -A && git commit -q -m "branch edits its review command"
+  cd src
+  security_review_render main "$SCRATCH/out.md" >/dev/null
+  grep -qF 'this diff modifies `.claude/commands/ship-next.md`' "$SCRATCH/out.md"
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..16`, 14 ok, these 2 fail:
  - `not ok 14 output_check: one good line does not excuse a finding in any other shape`
  - `not ok 16 render: a diff that edits the repo's own ship-next command is flagged, from any directory`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/security-review.sh b/claude-skills/ship-workflow/lib/security-review.sh
index 6c4964c..151b51a 100644
--- a/claude-skills/ship-workflow/lib/security-review.sh
+++ b/claude-skills/ship-workflow/lib/security-review.sh
@@ -48,7 +48,11 @@ security_review_render() {
     printf '\n## REPOSITORY-SPECIFIC NOTES\n\n%s\n' "$notes" >> "$out.tmp"
   fi
 
-  touched=$(git diff --name-only "${base}...HEAD" -- docs/SECURITY_REVIEW.md .claude/ship-config.yml 2>/dev/null)
+  # Root-anchored (`:/`), so the answer does not depend on the cwd. The repo's own
+  # copy of ship-next is included: a diff that drops step 1.5 from it would remove
+  # the security pass for every later ship.
+  touched=$(git diff --name-only "${base}...HEAD" -- \
+            ':/docs/SECURITY_REVIEW.md' ':/.claude/ship-config.yml' ':/.claude/commands/ship-next.md' 2>/dev/null)
   if [ -n "$touched" ]; then
     printf "\n## CHANGES TO THIS REVIEW'S OWN CONFIGURATION\n\n" >> "$out.tmp"
     printf '%s\n' "$touched" | while IFS= read -r p; do
@@ -61,15 +65,16 @@ security_review_render() {
 }
 
 # security_review_output_check <file> — exit 0 when the pass produced something
-# code-review-parse.sh can count: exactly "No security findings.", or at least one
-# finding line in the ship-next format and no upstream-format line. Exit 3
-# otherwise: an upstream "# Vuln 1 / * Severity: High" report would parse as zero
-# findings and pass the gate silently.
+# code-review-parse.sh can count: exactly "No security findings.", or only finding
+# lines in the ship-next format, their indented detail lines and blank lines. Exit 3
+# otherwise. Any other line — an upstream "# Vuln 1 / * Severity: High" block, a
+# bulleted "- 🔴 …", a bold "**HIGH**" — could hold a finding that parses as zero
+# and passes the gate silently, so one well-formed line does not excuse it.
 security_review_output_check() {
   local f="$1"
   [ -f "$f" ] || return 3
   [ "$(tr -d '[:space:]' < "$f")" = "Nosecurityfindings." ] && return 0
-  grep -qE '^#[[:space:]]*Vuln|^\*[[:space:]]*Severity:' "$f" && return 3
-  grep -qE '^[[:space:]]*(🔴|🟡|🟢)[[:space:]]+\[(blocking|important|nit)\]' "$f" && return 0
+  grep -vqE '^[[:space:]]*$|^[[:space:]]+[^[:space:]]|^(🔴|🟡|🟢) \[(blocking|important|nit)\]' "$f" && return 3
+  grep -qE '^(🔴|🟡|🟢) \[(blocking|important|nit)\]' "$f" && return 0
   return 3
 }
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..16`, all 16 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(security-review): review-fix 2 — output check rejects any line outside the finding format; self-config flag covers ship-next from any directory"
```

### Task 3: The filter sub-tasks see the AI-input category; the header lists every change

Seam: vendored prompt `templates/security-review/PROMPT.md`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🟢 PROMPT.md:194 — the false-positive filters received only FALSE POSITIVE FILTERING, so a filter could discard a prompt-injection finding as "lack of hardening". This is the operator's main concern (LINE end-users steering the bot).
- 🟢 PROMPT.md:191 — the "(a sub-task is a separate agent you dispatch)" change was not listed in the header.

**Files:**
- Modify: `claude-skills/ship-workflow/templates/security-review/PROMPT.md`
- Test: `claude-skills/ship-workflow/tests/test_security-review-template.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review-template.bats b/claude-skills/ship-workflow/tests/test_security-review-template.bats
index c3bdc14..cb16a2a 100644
--- a/claude-skills/ship-workflow/tests/test_security-review-template.bats
+++ b/claude-skills/ship-workflow/tests/test_security-review-template.bats
@@ -81,3 +81,14 @@ has() { grep -qF -- "$1" "$T" || { echo "missing: $1"; return 1; }; }
   has '[pre-existing]'
   if grep -qF '# Vuln 1:' "$T"; then echo "upstream output format left in"; return 1; fi
 }
+
+@test "the false-positive filters also see the AI-input category" {
+  # Without it a filter could drop a prompt-injection finding under exclusion 7
+  # ("a lack of hardening measures") — the operator's main concern for R-003.
+  has 'Also include the **LLM / AI Input Safety** category above and its severity guidance line'
+}
+
+@test "the header lists every change made to upstream text" {
+  has 'C5  the false-positive filter sub-tasks also receive the LLM / AI Input Safety category'
+  has 'START ANALYSIS notes that a sub-task is a separate agent you dispatch'
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..8`, 6 ok, these 2 fail:
  - `not ok 7 the false-positive filters also see the AI-input category`
  - `not ok 8 the header lists every change made to upstream text`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/templates/security-review/PROMPT.md b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
index 8b2b18d..f5cd25e 100644
--- a/claude-skills/ship-workflow/templates/security-review/PROMPT.md
+++ b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
@@ -5,11 +5,12 @@ Derived from anthropics/claude-code-security-review @ 0c6a49f1fa56,
 
 ship-workflow changes (R-003, docs/specs/R-003-add-security-review-gate.md §3.2):
   C1  git context: explicit commands against {{orig_branch}} instead of the remote default branch;
-      slash-command frontmatter removed
+      slash-command frontmatter removed; START ANALYSIS notes that a sub-task is a separate agent you dispatch
   C2  output: ship-next's severity line format instead of "# Vuln N" blocks
   C3  hard exclusion 14 (user content in AI prompts) removed; an
       "LLM / AI input safety" category and severity guidance added
   C4  pre-existing issues may be reported, tagged [pre-existing]
+  C5  the false-positive filter sub-tasks also receive the LLM / AI Input Safety category
 Everything else is upstream text, unchanged.
 -->
 
@@ -191,7 +192,7 @@ START ANALYSIS:
 Begin your analysis now. Do this in 3 steps (a sub-task is a separate agent you dispatch):
 
 1. Use a sub-task to identify vulnerabilities. Use the repository exploration tools to understand the codebase context, then analyze the PR changes for security implications. In the prompt for this sub-task, include all of the above.
-2. Then for each vulnerability identified by the above sub-task, create a new sub-task to filter out false-positives. Launch these sub-tasks as parallel sub-tasks. In the prompt for these sub-tasks, include everything in the "FALSE POSITIVE FILTERING" instructions.
+2. Then for each vulnerability identified by the above sub-task, create a new sub-task to filter out false-positives. Launch these sub-tasks as parallel sub-tasks. In the prompt for these sub-tasks, include everything in the "FALSE POSITIVE FILTERING" instructions. Also include the **LLM / AI Input Safety** category above and its severity guidance line, so a filter does not discard a prompt-injection finding as a mere lack of hardening.
 3. Filter out any vulnerabilities where the sub-task reported a confidence less than 8.
 
 Your final reply must contain the markdown report and nothing else.
\ No newline at end of file
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..8`, all 8 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(security-review): review-fix 3 — filter sub-tasks see the AI-input category; header lists every change"
```

### Task 4: ship-next Phase 6: stale reports removed, lib sources checked, a failed parse stops the gate, both reports read, off state recorded

Seam: ship-next Phase 6 steps 1.5, 1.6, 2 (loop), 4, 4.5; Phase 7 body; Phase 9 summary

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🔴 ship-next.md:802 — step 1.5 never removed an existing `SEC_OUT`, so a stale or pre-written report passed step 1.6 and the parse. It is now removed first, on every exit path.
- 🟡 ship-next.md:867 — `eval "$(code-review-parse.sh …)"` swallowed the parser's exit 2, so a missing report left `BLOCKING_COUNT` unset and the gate passed.
- 🟡 ship-next.md:801 — an unchecked `source`: with the lib missing, the block took the "off" branch and reported the review as switched off.
- 🟡 ship-next.md:996 — step 4 extracted majors from `$REVIEW_OUT` only, and included pre-existing ones.
- 🟡 ship-next.md:1074 — the landed commit always said "Security review: blocking 0 ✓". It had no off state.
- 🟡 [pre-existing] ship-next.md:861 — `REVIEW_OUT` was never cleared before code-review-skill wrote it. This is fixed here too, since the same edit covers `SEC_OUT`.
- 🟢 [seam-violation] test_ship-next-security.bats:20 — an assertion on a prose comment is replaced by assertions on the extraction commands.
- Step 1.6 now calls `pre_existing_strip_unverified` (Task 1) on both reports.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats`
- Test: `claude-skills/ship-workflow/tests/test_ship-next-security.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index fd56fcb..d7cbf71 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -255,11 +255,12 @@ pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^##
 @test "ship-next P6 security check: an upstream-format report is rejected, a clean one passes" {
   sec_check_block > "$SCRATCH/s16.sh"
   [ -s "$SCRATCH/s16.sh" ]
+  printf 'No findings.\n' > "$SCRATCH/rev.md"
   printf '%s\n' '# Vuln 1: XSS: `a.py:1`' '* Severity: High' > /tmp/ship-next-security-R-T5-1.md
-  run env ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
+  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
   [ "$status" -eq 3 ]
   echo "No security findings." > /tmp/ship-next-security-R-T5-1.md
-  run env ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
+  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
   [ "$status" -eq 0 ]
   rm -f /tmp/ship-next-security-R-T5-1.md
 }
@@ -268,11 +269,60 @@ pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^##
   mkdir -p docs/ideas
   echo 'flat prompt (pre-existing-key: p.py:prompt_injection)' > docs/ideas/IDEA-001-x.md
   printf '%s\n' '🔴 [blocking] [pre-existing] [security:prompt_injection] p.py:3 — flat prompt' > "$SCRATCH/sec.md"
-  printf '%s\n' '🟡 [important] [pre-existing] q.py:9 — Retry loop never backs off' > "$SCRATCH/rev.md"
+  printf '%s\n' '🟡 [important] [pre-existing] q.py:9 — Retry loop never backs off' \
+                 '🔴 [blocking] r.py:2 — a new finding that quotes the [pre-existing] tag' > "$SCRATCH/rev.md"
   pre_block > "$SCRATCH/s45.sh"
   [ -s "$SCRATCH/s45.sh" ]
   run env REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" bash "$SCRATCH/s45.sh"
   [ "$status" -eq 0 ]
   [[ "$output" == *"already tracked: p.py:prompt_injection"* ]] || return 1
-  [[ "$output" == *"new pre-existing: q.py:retry loop never backs off"* ]]
+  [[ "$output" == *"new pre-existing: q.py:retry loop never backs off"* ]] || return 1
+  [[ "$output" != *"r.py"* ]] || { echo "a quoted tag was treated as pre-existing"; return 1; }
+}
+
+# --- R-003 review round 1 ------------------------------------------------------
+
+@test "ship-next P6 security pass: a stale report from an earlier run is removed first" {
+  # Otherwise a leftover "No security findings." passes 1.6 for a pass that never ran.
+  echo "No security findings." > /tmp/ship-next-security-R-T6-1.md
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env ORIG_BRANCH=main ID=R-T6 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -eq 0 ]
+  [ ! -e /tmp/ship-next-security-R-T6-1.md ] || { echo "stale report survived"; return 1; }
+  printf 'No findings.\n' > "$SCRATCH/rev.md"
+  sec_check_block > "$SCRATCH/s16.sh"
+  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T6 attempt=1 bash "$SCRATCH/s16.sh"
+  [ "$status" -eq 3 ]
+}
+
+@test "ship-next P6 security pass: a missing lib halts — it is not reported as switched off" {
+  mkdir -p "$SCRATCH/nolib/.claude/skills/ship-workflow/lib"
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env HOME="$SCRATCH/nolib" ORIG_BRANCH=main ID=R-T7 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"lib is missing"* ]] || return 1
+  [[ "$output" != *"security review: off"* ]] || { echo "reported as off"; return 1; }
+  [ ! -e /tmp/ship-next-security-R-T7-1.md ]
+}
+
+@test "ship-next P6 security pass: records whether the review ran, for the landed commit" {
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$(cat .ship/security-review-state)" = "on" ]
+  echo 'security_review: off' >> .claude/ship-config.yml
+  git commit -q -am "review off"
+  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$(cat .ship/security-review-state)" = "off" ]
+  rm -f /tmp/ship-next-security-R-T8-1.md
+}
+
+@test "ship-next P6 security check: a pre-existing tag the base branch cannot back is removed" {
+  printf 'No findings.\n' > "$SCRATCH/rev.md"
+  printf '%s\n' '🔴 [blocking] [pre-existing] [security:command_injection] brand-new.sh:1 — x' \
+                '   Base evidence: brand-new.sh:1 exists unchanged on main' > /tmp/ship-next-security-R-T9-1.md
+  sec_check_block > "$SCRATCH/s16.sh"
+  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T9 attempt=1 bash "$SCRATCH/s16.sh"
+  [ "$status" -eq 0 ]
+  head -1 /tmp/ship-next-security-R-T9-1.md | grep -qF '🔴 [blocking] [security:command_injection] brand-new.sh:1' || return 1
+  rm -f /tmp/ship-next-security-R-T9-1.md
 }
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-security.bats b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
index 3939965..b084e80 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-security.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
@@ -15,9 +15,9 @@ p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }
   p6 | grep -qF 'code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT"' || { echo "security findings are not counted"; return 1; }
 }
 
-@test "blockers from both reviews are printed and fed to the fix-plan" {
-  p6 | grep -F 'grep -B1 -A3 -E' | grep -qF '"$REVIEW_OUT" "$SEC_OUT"' || { echo "security blockers are not printed"; return 1; }
-  p6 | grep -qF 'blocking findings from both $REVIEW_OUT and $SEC_OUT' || { echo "fix-plan ignores security blockers"; return 1; }
+@test "blockers from both reviews are printed, minus the anchored pre-existing ones" {
+  p6 | grep -F 'grep -B1 -A3 -E' | grep -qF '"$REVIEW_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE"' \
+    || { echo "security blockers are not printed, or pre-existing ones are"; return 1; }
 }
 
 @test "pre-existing findings get their own step and never feed BLOCKING_COUNT" {
@@ -41,3 +41,21 @@ p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }
     echo "a new block uses a positional parameter"; return 1
   fi
 }
+
+@test "the loop clears the previous code-review report and refuses a failed parse" {
+  p6 | grep -qF 'rm -f "$REVIEW_OUT"' || { echo "a stale code-review report can be reused"; return 1; }
+  p6 | grep -A1 -F 'PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")' \
+    | grep -qF '|| {' || { echo "a failed parse passes the gate"; return 1; }
+}
+
+@test "step 4 files majors from both reports, minus pre-existing ones" {
+  step=$(awk '/^4\. \*\*Major findings handling/,/^4\.5\. \*\*Pre-existing findings/' "$CMD")
+  echo "$step" | grep -F 'MAJOR_LINES=' | grep -qF '"$REVIEW_OUT" "$SEC_OUT"' || { echo "security importants are not filed"; return 1; }
+  echo "$step" | grep -qF 'grep -vE "$PRE_EXISTING_RE"' || { echo "pre-existing findings are filed as majors"; return 1; }
+}
+
+@test "the landed commit and the auto summary say when the security review was off" {
+  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'security-review-state' || return 1
+  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'off (ship-config on' || return 1
+  awk '/^## Phase 9/,0' "$CMD" | grep -qF 'security-review-state'
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats; cd - >/dev/null`

Expected: `1..33`, 24 ok, these 9 fail:
  - `not ok 20 ship-next P6 pre-existing step: already-tracked defects are not filed again`
  - `not ok 21 ship-next P6 security pass: a stale report from an earlier run is removed first`
  - `not ok 22 ship-next P6 security pass: a missing lib halts — it is not reported as switched off`
  - `not ok 23 ship-next P6 security pass: records whether the review ran, for the landed commit`
  - `not ok 24 ship-next P6 security check: a pre-existing tag the base branch cannot back is removed`
  - `not ok 27 blockers from both reviews are printed, minus the anchored pre-existing ones`
  - `not ok 31 the loop clears the previous code-review report and refuses a failed parse`
  - `not ok 32 step 4 files majors from both reports, minus pre-existing ones`
  - `not ok 33 the landed commit and the auto summary say when the security review was off`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 9bda682..d773566 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -797,11 +797,18 @@ CHECKS
    ```bash
    # Each block runs in its own shell: these come from the surrounding phase.
    : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${ID:?ID is not set}" "${attempt:?attempt is not set}"
-   # shellcheck disable=SC1091
-   source ~/.claude/skills/ship-workflow/lib/security-review.sh
    SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
+   # A report left by an earlier run must never stand in for this one: removing it
+   # first, on every exit path, means step 1.6 catches a pass that produced nothing.
+   rm -f "$SEC_OUT"
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/security-review.sh || {
+     echo "ERROR: the security-review lib is missing (stale ship-workflow checkout?) — not skipping the review." >&2
+     exit 1
+   }
    mkdir -p .ship
    if security_review_enabled "$ORIG_BRANCH"; then
+     echo on > .ship/security-review-state
      security_review_render "$ORIG_BRANCH" .ship/security-review-prompt.md >/dev/null || {
        echo "ERROR: the security review could not be rendered — not skipping it." >&2
        echo "       A missing lib or template usually means the local ship-workflow checkout is stale." >&2
@@ -809,6 +816,7 @@ CHECKS
      }
      echo "security review: follow .ship/security-review-prompt.md and write its report to $SEC_OUT"
    else
+     echo off > .ship/security-review-state
      echo "No security findings." > "$SEC_OUT"
      echo "security review: off (ship-config on $ORIG_BRANCH)"
    fi
@@ -823,19 +831,27 @@ CHECKS
 1.6. **Check the security report** — the pass must never fail open:
 
    ```bash
-   : "${ID:?ID is not set}" "${attempt:?attempt is not set}"
+   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${REVIEW_OUT:?REVIEW_OUT is not set}" \
+     "${ID:?ID is not set}" "${attempt:?attempt is not set}"
    # shellcheck disable=SC1091
-   source ~/.claude/skills/ship-workflow/lib/security-review.sh
+   source ~/.claude/skills/ship-workflow/lib/security-review.sh || { echo "ERROR: security-review lib missing" >&2; exit 1; }
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh || { echo "ERROR: pre-existing lib missing" >&2; exit 1; }
    SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
    if ! security_review_output_check "$SEC_OUT"; then
      echo "security report is not in the required format: $SEC_OUT" >&2
      echo "Re-run step 1.5 once. If this check fails again, stop Phase 6 here." >&2
      exit 3
    fi
+   # A file this diff created cannot hold a pre-existing defect: drop the tag from
+   # any [pre-existing] finding whose cited file does not exist on the base branch,
+   # in both reports, so it counts as this ship's own.
+   pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"
    ```
 
-   An upstream-format report (`# Vuln 1 … * Severity: High`) would parse as zero
-   findings and pass the gate silently. This check exists to stop that.
+   An upstream-format report (`# Vuln 1 … * Severity: High`), or any line outside the
+   ship-next finding format, could hold a finding that parses as zero and passes the
+   gate silently. This check exists to stop that.
 
 2. **Loop:**
    ```
@@ -849,6 +865,8 @@ CHECKS
    source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
    # shellcheck disable=SC1091
    source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE
 
    attempt=1
    while [ "$attempt" -le 3 ]; do
@@ -859,12 +877,17 @@ CHECKS
      # See R-084.1 learning (2026-07-30) for the burn.
      REVIEW_TARGET=$(git diff ${ORIG_BRANCH}...HEAD)
      REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
+     rm -f "$REVIEW_OUT"   # never parse a report left by an earlier run
      # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT
      # Read .ship/review-extra-checks.md alongside .ship/ua-diff-report.md when present.
      # Then run steps 1.5 and 1.6 (the security pass); they write SEC_OUT.
      SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
 
-     eval "$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")"
+     # A failed parse (a missing report) must stop the gate, not pass it: eval of an
+     # empty string succeeds and leaves BLOCKING_COUNT unset.
+     PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT") \
+       || { echo "review parse failed — not passing the gate" >&2; exit 1; }
+     eval "$PARSED"
      BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))
 
      # Auto mode: log every attempt
@@ -879,7 +902,7 @@ CHECKS
      # Print blockers ONLY in interactive mode (auto mode keeps quiet)
      if [ "$AUTO" = "0" ]; then
        echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
-       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$REVIEW_OUT" "$SEC_OUT" | grep -viF '[pre-existing]'
+       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$REVIEW_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE"
      fi
 
      attempt=$((attempt + 1))
@@ -992,8 +1015,12 @@ CHECKS
    - **In auto mode (`AUTO=1`):** every major finding becomes an `IDEA-NNN` follow-up (NEVER skip; quality-debt must be visible).
      ```bash
      if [ "$MAJOR_COUNT" -gt 0 ]; then
-       # Extract major findings from $REVIEW_OUT — grab the line + 1-2 lines context
-       MAJOR_LINES=$(grep -B0 -A2 -E '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' $REVIEW_OUT)
+       # shellcheck disable=SC1091
+       source ~/.claude/skills/ship-workflow/lib/pre-existing.sh   # PRE_EXISTING_RE
+       # Majors from BOTH reports (security MEDIUMs are importants), minus the
+       # pre-existing ones — MAJOR_COUNT excludes those, and step 4.5 files them.
+       MAJOR_LINES=$(grep -h -B0 -A2 -E '(\*\*Severity:\*\*[[:space:]]*major|\[major\]|🟡)' "$REVIEW_OUT" "$SEC_OUT" \
+                     | grep -vE "$PRE_EXISTING_RE")
 
        # Parse each finding into a 1-line description
        IFS=$'\n'
@@ -1022,8 +1049,8 @@ CHECKS
    ```bash
    : "${REVIEW_OUT:?REVIEW_OUT is not set}" "${SEC_OUT:?SEC_OUT is not set}"
    # shellcheck disable=SC1091
-   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh
-   grep -hF '[pre-existing]' "$REVIEW_OUT" "$SEC_OUT" 2>/dev/null | while IFS= read -r finding; do
+   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh || { echo "ERROR: pre-existing lib missing" >&2; exit 1; }
+   pre_existing_lines "$REVIEW_OUT" "$SEC_OUT" | while IFS= read -r finding; do
      key=$(pre_existing_key "$finding") || continue
      if pre_existing_tracked "$key"; then
        echo "already tracked: $key"
@@ -1071,7 +1098,7 @@ review sets `merge_mode: mr`.
    - minor:    ${MINOR_COUNT}
    - praise:   ${PRAISE_COUNT}
 
-   Security review: blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})
+   Security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})"; fi)
 
    Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
    Spec:  docs/specs/${ID}-${SLUG}.md
@@ -1402,7 +1429,7 @@ ${CODEX_LAST_FINDINGS}
    • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
    • minor: ${MINOR_COUNT}
    • praise: ${PRAISE_COUNT}
-   • security review: ${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN
+   • security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
    • CONTEXT.md: ${CONTEXT_MD_STATUS}
    • Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
    • Test pruning: ${PRUNE_STATUS}
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats; cd - >/dev/null`

Expected: `1..33`, all 33 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-next): review-fix 4 — stale reports removed, lib sources checked, a failed parse stops the gate, step 4 reads both reports, off state recorded"
```

### Task 5: Sync the spec with the review fixes

Seam: none (documentation only)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** the spec still described the round-1 behaviour: four vendoring changes, an unanchored tag, a prose-only tag check, the parse inside step 1.5, and no off state. Every later reader, and the next review, measures the code against it.

**Files:**
- Modify: `docs/specs/R-003-add-security-review-gate.md`

- [ ] **Step 1: Apply the spec update**

````bash
git apply <<'R003_PATCH'
diff --git a/docs/specs/R-003-add-security-review-gate.md b/docs/specs/R-003-add-security-review-gate.md
index c8a9dc6..3d1e2ef 100644
--- a/docs/specs/R-003-add-security-review-gate.md
+++ b/docs/specs/R-003-add-security-review-gate.md
@@ -21,13 +21,15 @@ supersedes: null
 > findings become follow-ups.
 >
 > The security pass is Anthropic's open-source `/security-review` prompt (MIT),
-> **vendored with four changes**:
+> **vendored with five changes**:
 > 1. It diffs `${ORIG_BRANCH}...HEAD`, not `origin/HEAD`.
 > 2. It emits ship-next's severity line format.
 > 3. It drops upstream exclusion 14 ("user content in AI prompts is not a
 >    vulnerability") and adds an AI-input checklist, because the operator's concern
 >    is prompt injection through LINE messages.
 > 4. It may report pre-existing issues, tagged.
+> 5. Its false-positive filters also see the AI-input category, so they do not discard
+>    a prompt-injection finding as mere missing hardening.
 >
 > The built-in `/security-review` command is deliberately not called; §3 says why.
 
@@ -101,6 +103,7 @@ supersedes: null
     are removed. They are replaced by instructions to run, in the repo root:
     `git diff --name-only {{orig_branch}}...HEAD`,
     `git log --no-decorate {{orig_branch}}..HEAD`, and `git diff {{orig_branch}}...HEAD`.
+    START ANALYSIS gains one parenthetical: a sub-task is a separate agent you dispatch.
   - **C2 Output format.** REQUIRED OUTPUT FORMAT is replaced. One finding is one line
     starting with the severity marker, then indented detail lines:
     ```
@@ -139,6 +142,10 @@ supersedes: null
     HIGH-confidence existing vulnerability on a code path the diff touches may be
     reported, tagged `[pre-existing]` with base evidence (C2). Upstream filtering
     applies to it unchanged.
+  - **C5 Filters see the AI-input category.** START ANALYSIS step 2 also hands each
+    false-positive filter sub-task the LLM / AI Input Safety category and its severity
+    guidance. Without it, a filter applying only FALSE POSITIVE FILTERING could discard
+    a prompt-injection finding as "lack of hardening".
 
 ### 3.3 `lib/security-review.sh` (new)
 **The review's own configuration is read from `${ORIG_BRANCH}`, never from the branch
@@ -156,37 +163,53 @@ review definitions run from the base branch.
   - Otherwise write `PROMPT.md` with `{{orig_branch}}` substituted.
   - If `git show <orig_branch>:docs/SECURITY_REVIEW.md` succeeds, append its content
     under `## REPOSITORY-SPECIFIC NOTES`.
-  - If the diff (`git diff --name-only <orig_branch>...HEAD`) touches
-    `docs/SECURITY_REVIEW.md` or `.claude/ship-config.yml`, append under
+  - If the diff (`git diff --name-only <orig_branch>...HEAD`, root-anchored `:/`
+    pathspecs so the cwd does not matter) touches `docs/SECURITY_REVIEW.md`,
+    `.claude/ship-config.yml` or `.claude/commands/ship-next.md`, append under
     `## CHANGES TO THIS REVIEW'S OWN CONFIGURATION`: "this diff modifies `<path>`; the
     change takes effect only after merge — review it as part of this pass."
   - Echo the out path. No git writes, no network.
 - `security_review_output_check <file>` — exit 0 if the file is exactly
-  `No security findings.` or has at least one C2 finding line and no upstream-format
-  line (`^# Vuln` or `^\* Severity:`). Exit 3 otherwise: the pass produced something
-  the parser would count as zero.
+  `No security findings.`, or has at least one C2 finding line and **every** other line
+  is blank or an indented detail line. Exit 3 otherwise, including a missing file. An
+  upstream `# Vuln 1` block, a bulleted `- 🔴 …` or a bold `**HIGH**` line could hold a
+  finding the parser counts as zero; one well-formed line elsewhere does not excuse it.
+- `PRE_EXISTING_RE` — the one position the tag counts in: at the start of a finding
+  line, right after the severity tag (`🔴 [blocking] [pre-existing] …`). Quoted in a
+  description, inside a path or in other case, `[pre-existing]` is plain text and the
+  finding counts as this ship's own. `pre_existing_lines <file>…` prints those lines.
 - `pre_existing_key <finding-line>` — echoes a stable key for a `[pre-existing]`
   finding: `<file>:<category>` when a `[security:<category>]` tag is present, else
-  `<file>:<first 40 chars of the description, lowercased>`.
+  `<file>:<first 40 bytes of the description, lowercased>`, with any partial UTF-8
+  character at the cut dropped.
 - `pre_existing_tracked <key>` — exit 0 if some `docs/ideas/*.md` already contains
   `(pre-existing-key: <key>)`. The parentheses delimit the key, so `a.py:sql` never
-  matches `a.py:sql_injection`. These two live in `lib/pre-existing.sh`, because
-  pre-existing findings come from both reviews.
+  matches `a.py:sql_injection`.
+- `pre_existing_strip_unverified <base> <file>…` — in place, drops the tag from every
+  anchored pre-existing line whose cited file does not exist on `<base>`, or that cites
+  no file. A file the diff created cannot hold a pre-existing defect. Exit 2 when
+  `<base>` does not resolve.
+- The `pre_existing_*` functions live in `lib/pre-existing.sh`, because pre-existing
+  findings come from both reviews.
 - The template path resolves via `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/security-review/PROMPT.md`,
   the same sibling-resolution pattern R-001 used.
 
 ### 3.4 `lib/code-review-parse.sh` — multiple files, pre-existing, no "00"
 - Accepts **one or more** files and counts across all of them. One file behaves exactly
-  as today. Exit 2 if any file is missing.
-- Lines containing `[pre-existing]` (case-insensitive) are **excluded** from BLOCKING,
-  MAJOR, MINOR and PRAISE, and counted in a new `PRE_EXISTING_COUNT`.
-- New `SECURITY_COUNT`: non-pre-existing finding lines that carry `[security:`.
+  as today. Exit 2 if any file is missing. Files are joined with `awk 1`, so a report
+  without a trailing newline cannot swallow the next report's first finding.
+- Lines matching `PRE_EXISTING_RE` (§3.3) are **excluded** from BLOCKING, MAJOR, MINOR
+  and PRAISE, and counted in a new `PRE_EXISTING_COUNT`. Nothing else is excluded.
+- New `SECURITY_COUNT`: non-pre-existing **finding lines** (they start with a severity
+  marker) that carry `[security:`. Prose and detail lines that name a category do not
+  count.
 - Every counter prints a single integer. The `grep -c … || echo 0` pattern, which
   printed `00`, is fixed.
-- **Verification of the tag (Phase 6 prose, not mechanical):** before accepting a
-  `[pre-existing]` finding, the Phase 6 session confirms with
-  `git show ${ORIG_BRANCH}:<file>` that the cited code exists there. If it does not,
-  the session edits the line to drop the tag, so the finding counts normally.
+- **Verification of the tag:**
+  - *Mechanical (step 1.6):* `pre_existing_strip_unverified "$ORIG_BRANCH"` runs on both
+    reports. A tag that cites a file absent on the base branch, or no file, is dropped.
+  - *Prose:* the Phase 6 session also confirms with `git show ${ORIG_BRANCH}:<file>`
+    that the cited code exists there **unchanged**. If not, it drops the tag by hand.
 
 ### 3.5 `commands/ship-next.md` Phase 6 (and touch points)
 - **0.5(c)** `review-extra-checks.md` gains:
@@ -197,15 +220,24 @@ review definitions run from the base branch.
   the surrounding loop fence stays pseudo-code as today. It:
   - starts with `: "${ORIG_BRANCH:?}" "${ID:?}" "${attempt:?}"`, because these are set
     earlier and blocks do not share a shell;
-  - sources `lib/security-review.sh` and `lib/code-review-parse.sh` itself;
+  - removes `SEC_OUT` (`/tmp/ship-next-security-${ID}-${attempt}.md`) **before anything
+    else**, so a report left by an earlier run can never stand in for this one;
+  - sources `lib/security-review.sh`; a failed source halts (exit 1, "lib is missing").
+    It must never fall through to the disabled branch;
   - if `security_review_enabled "$ORIG_BRANCH"`:
-    - render to `.ship/security-review-prompt.md`;
-    - follow that prompt: the finder sub-task, then parallel filter sub-tasks;
-    - write the result to `/tmp/ship-next-security-${ID}-${attempt}.md`;
-  - if disabled: write `No security findings.` there and print
-    `security review: off (ship-config on <ORIG_BRANCH>)`;
-  - finally, `eval "$(code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")"` replaces the
-    single-file parse.
+    - writes `on` to `.ship/security-review-state`;
+    - renders to `.ship/security-review-prompt.md`;
+    - the session follows that prompt (the finder sub-task, then parallel filter
+      sub-tasks) and writes the result to `SEC_OUT`;
+  - if disabled: writes `off` to `.ship/security-review-state`, `No security findings.`
+    to `SEC_OUT`, and prints `security review: off (ship-config on <ORIG_BRANCH>)`.
+- **New step 1.6** (its own block) guards `ORIG_BRANCH`, `REVIEW_OUT`, `ID`, `attempt`,
+  sources both libs with a check, runs `security_review_output_check`, then
+  `pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"`.
+- **The loop** removes `REVIEW_OUT` before code-review-skill writes it, then parses
+  both files: `PARSED=$(code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT") || exit 1`, then
+  `eval "$PARSED"`. A failed parse must stop the gate: `eval` of an empty string
+  succeeds and leaves `BLOCKING_COUNT` unset.
 - **The security pass never fails open:**
   - **Render fails (exit 2):** Phase 6 halts (exit 1) with a hint, the same way a
     missing code-review-skill halts. A missing lib or template usually means the local
@@ -216,9 +248,11 @@ review definitions run from the base branch.
 - **Scope of the block rule:** only the new blocks guard `ORIG_BRANCH`. Persisting
   `ORIG_BRANCH` for older blocks is a follow-up. The existing `MERGE_MODE` structural
   test is unchanged.
-- **Blocker printing and fix-plans** include findings from both files.
+- **Blocker printing, step 4 majors and fix-plans** include findings from both files,
+  minus the `PRE_EXISTING_RE` lines.
 - **New step 4.5 Pre-existing findings** (after majors). Never blocks.
-  - For each `[pre-existing]` line, compute `pre_existing_key`.
+  - For each `pre_existing_lines "$REVIEW_OUT" "$SEC_OUT"` line, compute
+    `pre_existing_key`.
   - If `pre_existing_tracked` says it is already tracked, show
     `already tracked (<IDEA file>)` and skip it.
   - Otherwise:
@@ -228,7 +262,10 @@ review definitions run from the base branch.
     hits the same defect skips it. This is Anthropic's "no repeat
     findings" rule, applied across ships.
 - **Phase 7 body / Phase 9 summary** gain one line:
-  `Security review: blocking 0 ✓, important N, pre-existing N` (or `off`).
+  `Security review: blocking 0 ✓ (security findings: N, pre-existing: N)`. When
+  `$WORKTREE/.ship/security-review-state` says `off`, the line says
+  `off (ship-config on <ORIG_BRANCH>)` instead, so a landed commit never claims a
+  review that did not run.
 - **Kill switch:** `security_review: off` in `.claude/ship-config.yml` **on the base
   branch** (§3.3).
 
@@ -242,10 +279,12 @@ The ship-workflow README documents the security pass, the kill switch, and
 |---|---|---|
 | `security_review_enabled` | `security_review_enabled <orig_branch>` | exit 0 unless `<orig_branch>:.claude/ship-config.yml` says `security_review: off`; default on; the branch's own copy is ignored |
 | `security_review_render` | `security_review_render <orig_branch> <out>` | writes the vendored prompt with `{{orig_branch}}` substituted and no `origin/HEAD`; appends `<orig_branch>:docs/SECURITY_REVIEW.md` under `## REPOSITORY-SPECIFIC NOTES` when it exists there; flags a diff that touches `docs/SECURITY_REVIEW.md` or `.claude/ship-config.yml`; exit 2 on an unresolvable branch or missing template; no git writes |
-| `security_review_output_check` | `security_review_output_check <file>` | exit 0 for `No security findings.` or ≥1 C2 finding line with no upstream-format line; exit 3 otherwise |
-| `pre_existing_key` / `pre_existing_tracked` | `pre_existing_key <line>` → key; `pre_existing_tracked <key>` | key is `<file>:<category>` or `<file>:<desc40>`; tracked iff some `docs/ideas/*.md` contains `(pre-existing-key: <key>)` |
+| `security_review_output_check` | `security_review_output_check <file>` | exit 0 for `No security findings.`, or ≥1 C2 finding line with every other line blank or indented; exit 3 otherwise, including a missing file |
+| `PRE_EXISTING_RE` / `pre_existing_lines` | `pre_existing_lines <file>…` | matches the tag only right after a leading severity tag; prints those lines; no output (exit 0) when none |
+| `pre_existing_key` / `pre_existing_tracked` | `pre_existing_key <line>` → key; `pre_existing_tracked <key>` | key is `<file>:<category>` or `<file>:<desc40>` (valid UTF-8); tracked iff some `docs/ideas/*.md` contains `(pre-existing-key: <key>)` |
+| `pre_existing_strip_unverified` | `pre_existing_strip_unverified <base> <file>…` | in place, drops the tag from anchored lines citing a file absent on `<base>` or no file; leaves every other line byte-identical; exit 2 on an unresolvable base |
 | vendored prompt | `templates/security-review/PROMPT.md` | contains upstream hard exclusions 1–13 and 15–17, all 12 precedents, and the < 8 cutoff; lacks exclusion 14; contains the AI-input checklist and the C2 output format; names its upstream commit and license |
-| `code-review-parse.sh` | `code-review-parse.sh <file>…` | counts summed across files; `[pre-existing]` lines excluded from the four severity counts and counted in `PRE_EXISTING_COUNT`; `SECURITY_COUNT` counts non-pre-existing `[security:` finding lines; every value a single integer; exit 2 on a missing file; one-file output identical to today for input without the new tags |
+| `code-review-parse.sh` | `code-review-parse.sh <file>…` | counts summed across files, line boundaries kept; `PRE_EXISTING_RE` lines excluded from the four severity counts and counted in `PRE_EXISTING_COUNT`; `SECURITY_COUNT` counts non-pre-existing finding lines carrying `[security:`; every value a single integer; exit 2 on a missing file; one-file output identical to today for input without the new tags |
 
 ## §4 Acceptance
 
@@ -260,9 +299,15 @@ The ship-workflow README documents the security pass, the kill switch, and
 | AC-7 | `security_review_render no-such-branch out` | — | exit 2, `out` not written |
 | AC-8 | no config on `main` / `security_review: off` on `main` / off only on the branch | `security_review_enabled main` | 0 / 1 / 0 |
 | AC-9 | the vendored prompt | inspected | upstream exclusions 1–13 and 15–17 and the 12 precedents present (key phrase per item); exclusion 14 absent; upstream commit `0c6a49f1fa56` and "Copyright (c) 2025 Anthropic" named; `LICENSE.upstream` is MIT |
-| AC-10 | output files: `No security findings.` / one C2 line / upstream `# Vuln 1:` + `* Severity: High` / empty | `security_review_output_check` | 0 / 0 / 3 / 3 |
+| AC-10 | output files: `No security findings.` / one C2 line / upstream `# Vuln 1:` + `* Severity: High` / empty / one C2 line plus an unindented `- 🔴 …` line | `security_review_output_check` | 0 / 0 / 3 / 3 / 3 |
 | AC-12 | `docs/ideas/IDEA-007.md` contains `(pre-existing-key: a.py:prompt_injection)`; finding `🔴 [blocking] [pre-existing] [security:prompt_injection] a.py:3 — x` | `pre_existing_key` then `pre_existing_tracked` | key `a.py:prompt_injection`; tracked (exit 0) |
 | AC-13 | ship-next Phase 6 step 1.5 block, run with `ORIG_BRANCH` unset | block-executed | exits non-zero before rendering anything |
+| AC-14 | a code-review file whose last line `🟢 [nit] a.py:1 — x` has no trailing newline, and a security file starting `🔴 [blocking] [security:x] b.py:2 — y` | `code-review-parse.sh rev sec` | `BLOCKING_COUNT=1` |
+| AC-15 | `🔴 [blocking] a.py:3 — quotes the text [pre-existing]` / `🔴 [blocking] [PRE-EXISTING] a.py:3 — x` | `code-review-parse.sh f` | `BLOCKING_COUNT=1`, `PRE_EXISTING_COUNT=0` for each |
+| AC-16 | `🔴 [blocking] [pre-existing] new.sh:1 — x` where `new.sh` is absent on `main` | step 1.6 block-executed | the line loses `[pre-existing]` and counts as a blocker |
+| AC-17 | a stale `SEC_OUT` from an earlier run / a missing `security-review.sh` | step 1.5 block-executed | the stale file is gone afterwards / exit 1 with "lib is missing", never "security review: off", and no `SEC_OUT` |
+| AC-18 | `security_review: off` on `main` | step 1.5 then the Phase 7 body | `.ship/security-review-state` is `off`; the body says `Security review: off (ship-config on main)` |
+| AC-19 | a missing review file | the loop's parse | Phase 6 stops (exit 1); the gate is not passed |
 | AC-11 | ship-next Phase 6 | inspected and block-executed | the security step renders the prompt and the parse call takes both files; every block that reads `MERGE_MODE`/`ORIG_BRANCH` resolves it (existing structural test still passes); step 4.5 exists and never feeds `BLOCKING_COUNT` |
 
 ## §5 Rollout
@@ -278,8 +323,10 @@ Repo-specific accuracy improves when langlive adds `docs/SECURITY_REVIEW.md`
   commit; re-sync is a manual follow-up when upstream changes.
 - **R2 Cost.** Each review attempt adds a finder sub-task plus one filter sub-task per
   candidate. At most 3 attempts per ship.
-- **R3 Pre-existing as escape hatch.** The tag relies on LLM judgement plus the
-  Phase 6 `git show` check (§3.4). The check is prose, not mechanical.
+- **R3 Pre-existing as escape hatch.** The tag counts only in its anchored position,
+  and step 1.6 mechanically drops it when the cited file is absent on the base branch.
+  Whether the cited code is *unchanged* there is still LLM judgement plus the prose
+  `git show` check (§3.4).
 - **R4 False negatives on business logic.** The prompt sees the diff plus whatever
   context the finder reads. Stored-injection paths that span several modules (like
   langlive's KB) are only caught when the diff touches them. The KB path itself is a
R003_PATCH
````

- [ ] **Step 2: Check the patch applied**

Run: `git diff --stat`

Expected: only `docs/specs/R-003-add-security-review-gate.md` changed.

- [ ] **Step 3: Commit**

```bash
git add docs/specs
git commit -m "docs(spec): review-fix 5 — R-003 spec matches the review fixes (C5, anchored tag, mechanical strip, stale reports, parse guard, off state)"
```

### Task 6: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..603`, 602 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: No commit** — report DONE with the Step 1 counts.
