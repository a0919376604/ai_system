# R-003 Review-fix Plan (attempt 3) — round-2 findings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding from R-003 review attempt 2 (1 blocking, 4 important, 3 nit). Each fix is pinned by a test that fails before it, and a test *executes* the code rather than grepping its text wherever the code can run.

**Architecture:** Same seams as `docs/plans/R-003-add-security-review-gate.md` and `-review-fix-2.md`. New here: Claude Code runs command blocks in zsh, where `grep` is a ugrep wrapper. A test emulates that wrapper because bats runs bash and cannot see it.

**Tech Stack:** bash + zsh, git ≥ 2.38, bats 1.13, awk.

**Spec:** `docs/specs/R-003-add-security-review-gate.md` (Task 4 updates it). Review: `/tmp/ship-next-review-R-003-2.md`.

## Global Constraints

- **Scope.** Every file you edit is under `claude-skills/ship-workflow/` or `docs/specs/` in THIS repository. `claude-skills/` is this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/` or the operator's home directory. The tests set their own `HOME` to a scratch dir; that is how they stay away from the real one.
- **Not part of this plan:** `.ship/proto/`, `.ship/proto2/`, `.ship/scratch/` and `.ship/upstream/` are scratch state. Do not read, edit or stage them. Stage only the paths each commit step names, never `git add -A`, because `.ship/proto*` are nested git repositories.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise.
- **Patches are the code.** Each code step is a `git apply` heredoc, generated from and replayed against this exact base (`f1dc5ab`). They apply cleanly in order. If one does not apply, STOP. Do not hand-edit around it.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 5.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** no `local` inside a loop body; no unquoted globs that may match nothing.
- **Commits.** One commit per task, with the exact message given. Never amend, never push, never switch branches. Commit subjects say `review-fix N`, not `Task N`, so Phase 6's gate does not confuse them with the original plan's tasks.

## Review Focus

These are the failure modes behind the findings that a person is most likely to hit next. Each has a test in the owning task:

1. A check that behaves differently in Claude Code's shell than under bats: the `grep` wrapper. → Task 1.
2. A HIGH finding that parses as zero because it is indented, bulleted or mis-tagged. → Task 1.
3. A good security report rejected because the prompt and the check disagree on format. → Task 2.
4. A stale report, a pre-existing detail line filed as a major, or a summary read from a removed worktree. → Task 3.

---
### Task 1: The security output check works in Claude Code's shell and lets no severity hide

Seam: `security_review_output_check`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🔴 security-review.sh:77. Step 1.6 sources this function into Claude Code's zsh, where `grep` is a shell function wrapping an embedded ugrep. There `grep -vq` exits 1 even when a line does not match, so the foreign-line test never fired. A bulleted HIGH next to a well-formed nit passed 1.6 and parsed as `BLOCKING_COUNT=0`. Reproduced: the same report gives rc 0 in Claude Code's zsh and rc 3 under bash. bats runs bash, so the new test emulates the wrapper.
- 🟢 security-review.sh:77. Any indented line counted as a detail line and any marker/tag pair counted as a finding, so an indented `- 🔴 [blocking]`, an indented `**HIGH**` or `* Severity: High`, or a `🟢 [blocking]` line passed the check and counted as zero.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/security-review.sh`
- Test: `claude-skills/ship-workflow/tests/test_security-review.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review.bats b/claude-skills/ship-workflow/tests/test_security-review.bats
index 4ba95b0..6041250 100644
--- a/claude-skills/ship-workflow/tests/test_security-review.bats
+++ b/claude-skills/ship-workflow/tests/test_security-review.bats
@@ -152,3 +152,32 @@ on_main() {  # on_main <path> <content> — commit a file on main, return to the
   security_review_render main "$SCRATCH/out.md" >/dev/null
   grep -qF 'this diff modifies `.claude/commands/ship-next.md`' "$SCRATCH/out.md"
 }
+
+# --- R-003 review round 2 ------------------------------------------------------
+
+@test "output_check: still rejects a foreign line inside Claude Code's grep wrapper" {
+  # Claude Code's Bash tool runs zsh with grep wrapped in ugrep, and step 1.6 sources
+  # this function into that shell. ugrep's `-vq` exits 1 even when some line does
+  # not match, so the foreign-line test never fired there. Emulate the wrapper.
+  grep() {
+    local a
+    for a in "$@"; do
+      case "$a" in --*) ;; -*v*q*|-*q*v*) return 1 ;; esac
+    done
+    command grep "$@"
+  }
+  printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' '- 🔴 [blocking] [security:sqli] a.py:3 — bullet form' > "$SCRATCH/mixed.md"
+  run security_review_output_check "$SCRATCH/mixed.md"
+  [ "$status" -eq 3 ]
+}
+
+@test "output_check: a severity marker never hides in a detail line or a mismatched tag" {
+  for bad in '   - 🔴 [blocking] [security:sqli] a.py:3 — indented bullet' \
+             '   **HIGH** SQL injection in a.py:3' \
+             '   * Severity: High' \
+             '🟢 [blocking] [security:sqli] a.py:3 — marker and tag disagree'; do
+    printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' "$bad" > "$SCRATCH/mixed.md"
+    run security_review_output_check "$SCRATCH/mixed.md"
+    [ "$status" -eq 3 ] || { echo "accepted: $bad"; return 1; }
+  done
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..18`, 16 ok, these 2 fail:
  - `not ok 17 output_check: still rejects a foreign line inside Claude Code's grep wrapper`
  - `not ok 18 output_check: a severity marker never hides in a detail line or a mismatched tag`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/security-review.sh b/claude-skills/ship-workflow/lib/security-review.sh
index 151b51a..13b2760 100644
--- a/claude-skills/ship-workflow/lib/security-review.sh
+++ b/claude-skills/ship-workflow/lib/security-review.sh
@@ -69,12 +69,18 @@ security_review_render() {
 # lines in the ship-next format, their indented detail lines and blank lines. Exit 3
 # otherwise. Any other line — an upstream "# Vuln 1 / * Severity: High" block, a
 # bulleted "- 🔴 …", a bold "**HIGH**" — could hold a finding that parses as zero
-# and passes the gate silently, so one well-formed line does not excuse it.
+# and passes the gate silently, so one well-formed line does not excuse it. A
+# detail line may not carry a severity either, and marker and tag must agree.
+#
+# `command grep`: step 1.6 sources this into Claude Code's shell, which wraps grep
+# in ugrep, and ugrep's `-vq` exits 1 even when a line does not match — the
+# foreign-line test would never fire there.
 security_review_output_check() {
-  local f="$1"
+  local f="$1" finding='^(🔴 \[blocking\]|🟡 \[important\]|🟢 \[nit\]) '
   [ -f "$f" ] || return 3
   [ "$(tr -d '[:space:]' < "$f")" = "Nosecurityfindings." ] && return 0
-  grep -vqE '^[[:space:]]*$|^[[:space:]]+[^[:space:]]|^(🔴|🟡|🟢) \[(blocking|important|nit)\]' "$f" && return 3
-  grep -qE '^(🔴|🟡|🟢) \[(blocking|important|nit)\]' "$f" && return 0
+  command grep -vqE "^[[:space:]]*\$|${finding}|^[[:space:]]+[^[:space:]]" "$f" && return 3
+  command grep -qE '^[[:space:]]+.*(🔴|🟡|🟢|🎉|\[(blocking|important|major|minor|nit|praise)\]|Severity:|\*\*(HIGH|MEDIUM|LOW)\*\*)' "$f" && return 3
+  command grep -qE "$finding" "$f" && return 0
   return 3
 }
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..18`, all 18 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(security-review): review-fix 7 — output check uses command grep (Claude Code wraps grep in ugrep) and lets no severity hide in a detail line"
```

### Task 2: The prompt asks for nothing but findings, so a normal report passes the check

Seam: vendored prompt `templates/security-review/PROMPT.md` ↔ `security_review_output_check`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🟡 PROMPT.md:124. The prompt allowed any line that does not start with a marker, such as a title, a heading or a summary, but the strict check rejects those. A normal markdown report would stop Phase 6 after its one re-run. The finding above hid this; fixing it makes this one live. The new test also runs the prompt's own example through the check.

**Files:**
- Modify: `claude-skills/ship-workflow/templates/security-review/PROMPT.md`
- Test: `claude-skills/ship-workflow/tests/test_security-review-template.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review-template.bats b/claude-skills/ship-workflow/tests/test_security-review-template.bats
index cb16a2a..3372ba9 100644
--- a/claude-skills/ship-workflow/tests/test_security-review-template.bats
+++ b/claude-skills/ship-workflow/tests/test_security-review-template.bats
@@ -92,3 +92,15 @@ has() { grep -qF -- "$1" "$T" || { echo "missing: $1"; return 1; }; }
   has 'C5  the false-positive filter sub-tasks also receive the LLM / AI Input Safety category'
   has 'START ANALYSIS notes that a sub-task is a separate agent you dispatch'
 }
+
+@test "the prompt asks for nothing but findings, so a normal report passes the format check" {
+  # The check rejects every line that is not a finding, a detail line or blank. A
+  # prompt that allows a title or a summary would stop Phase 6 on a good report.
+  has 'nothing but finding lines, their indented detail lines and blank lines'
+  source "$SHIP_LIB/security-review.sh"
+  example=$(awk '/^REQUIRED OUTPUT FORMAT:/{f=1} f&&/^```$/{n++; next} f&&n==1' "$T")
+  [ -n "$example" ] || { echo "no example block"; return 1; }
+  printf '%s\n' "$example" > "$BATS_TEST_TMPDIR/example.md"
+  run security_review_output_check "$BATS_TEST_TMPDIR/example.md"
+  [ "$status" -eq 0 ] || { echo "the prompt's own example fails the check"; return 1; }
+}
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..9`, 8 ok, these 1 fail:
  - `not ok 9 the prompt asks for nothing but findings, so a normal report passes the format check`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/templates/security-review/PROMPT.md b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
index f5cd25e..609268a 100644
--- a/claude-skills/ship-workflow/templates/security-review/PROMPT.md
+++ b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
@@ -121,7 +121,7 @@ You MUST output your findings in markdown, one finding per line in exactly this
 - HIGH → `🔴 [blocking]`, MEDIUM → `🟡 [important]`, LOW → `🟢 [nit]`.
 - `<category>` is a short snake_case name, e.g. `sql_injection`, `xss`, `prompt_injection`, `stored_prompt_injection`.
 - A pre-existing finding inserts `[pre-existing]` right after the severity tag and adds an indented line `Base evidence: <file>:<line> exists unchanged on {{orig_branch}}`.
-- No line other than a finding may begin with 🔴, 🟡, 🟢, 🎉 or a `[blocking]` / `[important]` / `[nit]` tag.
+- Output nothing but finding lines, their indented detail lines and blank lines: no title, no headings, no preamble, no summary. A detail line never carries a severity marker or tag.
 - If there are no findings, your entire output is exactly: `No security findings.`
 
 SEVERITY GUIDELINES:
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..9`, all 9 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(security-review): review-fix 8 — the prompt asks for nothing but finding lines, matching the format check"
```

### Task 3: ship-next: both reports cleared per attempt; step 4, blocker printing and the Phase 9 summary fixed

Seam: ship-next Phase 6 loop and step 4; Phase 9 steps 0 and 4

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:**
- 🟡 ship-next.md:884. The loop removed an old `REVIEW_OUT` but not an old `SEC_OUT`, so a skipped step 1.5 let an earlier run's "No security findings." pass the gate.
- 🟡 ship-next.md:1027. Step 4 was half fixed. Dropping a pre-existing finding line leaves its `Base evidence:` detail line behind, and `awk 'NR==1 || …'` filed that line as a major while `head -$MAJOR_COUNT` cut the real security major. The new test runs the step-4 block itself, with `/ship-idea` recorded.
- 🟡 ship-next.md:1432. The Phase 9 summary read `.ship/security-review-state` after step 1 had removed the worktree, so an off review was reported as "0 finding(s)". Step 0 now captures it, as step 0 already does for the codex rounds.
- 🟢 ship-next.md:905. With two files grep prefixes each line with its file name, so the anchored pre-existing filter removed nothing and interactive mode printed pre-existing findings as blockers. The test now runs that print line instead of grepping its text.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats`
- Test: `claude-skills/ship-workflow/tests/test_ship-next-security.bats`

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index d7cbf71..5907e06 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -326,3 +326,38 @@ pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^##
   head -1 /tmp/ship-next-security-R-T9-1.md | grep -qF '🔴 [blocking] [security:command_injection] brand-new.sh:1' || return 1
   rm -f /tmp/ship-next-security-R-T9-1.md
 }
+
+# --- R-003 review round 2 ------------------------------------------------------
+
+major_block()      { block ship-next.md '^4\. \*\*Major findings handling' '^4\.5\. \*\*Pre-existing findings'; }
+p9_capture_block() { block ship-next.md '^0\. \*\*Capture anything inside the worktree' '^1\. \*\*Remove worktree'; }
+
+@test "ship-next P6 step 4: files every major from both reports, never a pre-existing finding's detail line" {
+  printf '%s\n' '🟡 [important] [pre-existing] old.sh:1 — old defect' \
+                '   Base evidence: old.sh:1 exists unchanged on main' \
+                '   Fix: later' \
+                '🟡 [important] a.sh:2 — first new major' > "$SCRATCH/rev.md"
+  printf '%s\n' '🟡 [important] [security:xss] b.sh:3 — second new major' \
+                '   Exploit scenario: y' > "$SCRATCH/sec.md"
+  # /ship-idea is a slash command, not a program: record what the block would file.
+  { echo 'ship_idea() { printf "%s\n" "$2" >> "$SCRATCH/ideas.txt"; }'
+    major_block | sed 's#/ship-idea #ship_idea #'; } > "$SCRATCH/s4.sh"
+  run env AUTO=1 MAJOR_COUNT=2 REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" \
+      WORKTREE="$REPO" ID=R-T10 bash "$SCRATCH/s4.sh"
+  grep -qF 'a.sh:2 — first new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
+  grep -qF 'b.sh:3 — second new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
+  if grep -qF 'Base evidence' "$SCRATCH/ideas.txt"; then echo "filed a detail line as a major"; return 1; fi
+}
+
+@test "ship-next P9: the security-review state is captured before the worktree is removed" {
+  mkdir -p "$SCRATCH/wt/.ship" && echo off > "$SCRATCH/wt/.ship/security-review-state"
+  { p9_capture_block; echo 'echo "state=${SECURITY_REVIEW_STATE:-}"'; } > "$SCRATCH/p90.sh"
+  run env WORKTREE="$SCRATCH/wt" ID=R-T11 bash "$SCRATCH/p90.sh"
+  [[ "$output" == *"state=off"* ]] || return 1
+  # Step 4 runs after step 1 removed the worktree, so it must use the capture.
+  step4=$(awk '/^## Phase 9/{p=1} p && /^4\. \*\*Auto-mode success notification/{f=1} f && /^## /{exit} f' \
+          "$SHIP_SKILL_ROOT/commands/ship-next.md")
+  [ -n "$step4" ] || return 1
+  if echo "$step4" | grep -qF '.ship/security-review-state'; then echo "summary reads the removed worktree"; return 1; fi
+  echo "$step4" | grep -qF 'SECURITY_REVIEW_STATE'
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-security.bats b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
index b084e80..aa02e97 100644
--- a/claude-skills/ship-workflow/tests/test_ship-next-security.bats
+++ b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
@@ -16,8 +16,19 @@ p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }
 }
 
 @test "blockers from both reviews are printed, minus the anchored pre-existing ones" {
-  p6 | grep -F 'grep -B1 -A3 -E' | grep -qF '"$REVIEW_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE"' \
-    || { echo "security blockers are not printed, or pre-existing ones are"; return 1; }
+  # Run the loop's own print line. With two files grep prefixes each line with its
+  # file name unless -h, and the anchored pre-existing filter then removes nothing.
+  line=$(p6 | grep -F -- '-B1 -A3 -E' | sed 's/^[[:space:]]*//')
+  [ -n "$line" ] || return 1
+  d="$BATS_TEST_TMPDIR"
+  printf '%s\n' '🔴 [blocking] [pre-existing] old.sh:1 — OLD-DEFECT' \
+                '   Base evidence: old.sh:1 exists unchanged on main' '' \
+                '🔴 [blocking] a.sh:2 — NEW-CODE' > "$d/rev.md"
+  printf '%s\n' '🔴 [blocking] [security:sqli] b.sh:3 — NEW-SEC' > "$d/sec.md"
+  run bash -c "source '$SHIP_LIB/pre-existing.sh'; REVIEW_OUT='$d/rev.md'; SEC_OUT='$d/sec.md'; $line"
+  [[ "$output" == *NEW-CODE* ]] || return 1
+  [[ "$output" == *NEW-SEC* ]] || return 1
+  [[ "$output" != *OLD-DEFECT* ]] || { echo "printed a pre-existing finding as a blocker"; return 1; }
 }
 
 @test "pre-existing findings get their own step and never feed BLOCKING_COUNT" {
@@ -43,7 +54,10 @@ p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }
 }
 
 @test "the loop clears the previous code-review report and refuses a failed parse" {
-  p6 | grep -qF 'rm -f "$REVIEW_OUT"' || { echo "a stale code-review report can be reused"; return 1; }
+  # Both reports, at the top of every attempt: if step 1.5 is skipped, an earlier
+  # run's "No security findings." must not be what the parse reads.
+  p6 | grep -B1 -F 'rm -f "$REVIEW_OUT" "$SEC_OUT"' | grep -qF 'SEC_OUT=/tmp/ship-next-security-' \
+    || { echo "a stale report can be reused"; return 1; }
   p6 | grep -A1 -F 'PARSED=$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")' \
     | grep -qF '|| {' || { echo "a failed parse passes the gate"; return 1; }
 }
R003_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats; cd - >/dev/null`

Expected: `1..35`, 31 ok, these 4 fail:
  - `not ok 25 ship-next P6 step 4: files every major from both reports, never a pre-existing finding's detail line`
  - `not ok 26 ship-next P9: the security-review state is captured before the worktree is removed`
  - `not ok 29 blockers from both reviews are printed, minus the anchored pre-existing ones`
  - `not ok 33 the loop clears the previous code-review report and refuses a failed parse`

- [ ] **Step 3: Implement**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index d773566..604f521 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -877,11 +877,11 @@ CHECKS
      # See R-084.1 learning (2026-07-30) for the burn.
      REVIEW_TARGET=$(git diff ${ORIG_BRANCH}...HEAD)
      REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
-     rm -f "$REVIEW_OUT"   # never parse a report left by an earlier run
+     SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
+     rm -f "$REVIEW_OUT" "$SEC_OUT"   # never parse a report left by an earlier run
      # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT
      # Read .ship/review-extra-checks.md alongside .ship/ua-diff-report.md when present.
      # Then run steps 1.5 and 1.6 (the security pass); they write SEC_OUT.
-     SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
 
      # A failed parse (a missing report) must stop the gate, not pass it: eval of an
      # empty string succeeds and leaves BLOCKING_COUNT unset.
@@ -902,7 +902,7 @@ CHECKS
      # Print blockers ONLY in interactive mode (auto mode keeps quiet)
      if [ "$AUTO" = "0" ]; then
        echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
-       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$REVIEW_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE"
+       grep -h -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$REVIEW_OUT" "$SEC_OUT" | grep -vE "$PRE_EXISTING_RE"
      fi
 
      attempt=$((attempt + 1))
@@ -1024,7 +1024,9 @@ CHECKS
 
        # Parse each finding into a 1-line description
        IFS=$'\n'
-       for finding in $(echo "$MAJOR_LINES" | awk 'NR==1 || /^[🟡]|\[major\]|\*\*Severity/' | head -$MAJOR_COUNT); do
+       # Finding lines only: a removed pre-existing finding leaves its detail lines
+       # (`Base evidence: …`) behind, and none of those is a major.
+       for finding in $(echo "$MAJOR_LINES" | awk '/^[🟡]|\[major\]|\*\*Severity/' | head -$MAJOR_COUNT); do
          finding_desc=$(echo "$finding" | sed 's/^[🟡[:space:]]*//' | head -c 120)
          /ship-idea --during-build \
            "P6 major from $ID: $finding_desc" \
@@ -1297,6 +1299,9 @@ runs in `--auto:yes`. Because it is expensive, Phase 9 flags it explicitly.
    # shellcheck disable=SC1091
    source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
 
+   # Whether Phase 6 ran the security review (step 1.5 wrote it); step 4 needs it.
+   SECURITY_REVIEW_STATE=$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null || true)
+
    CODEX_ROUNDS_ARCHIVE=""
    CODEX_LAST_FINDINGS=""
    if [ -f "$WORKTREE/.ship/codex-rounds.md" ]; then
@@ -1429,7 +1434,7 @@ ${CODEX_LAST_FINDINGS}
    • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
    • minor: ${MINOR_COUNT}
    • praise: ${PRAISE_COUNT}
-   • security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
+   • security review: $(if [ "${SECURITY_REVIEW_STATE:-}" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
    • CONTEXT.md: ${CONTEXT_MD_STATUS}
    • Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
    • Test pruning: ${PRUNE_STATUS}
R003_PATCH
````

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats; cd - >/dev/null`

Expected: `1..35`, all 35 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "fix(ship-next): review-fix 9 — both reports cleared per attempt; step 4 files only finding lines; blockers printed with -h; Phase 9 captures the review state"
```

### Task 4: Sync the spec and README with the round-2 fixes

Seam: none (documentation only)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** 🟢 the spec and README had drifted from the code. The render Seams row missed `.claude/commands/ship-next.md`; §3.5 said step 4.5 prints `already tracked (<IDEA file>)`, but it prints `already tracked: <key>`; and the README said "four changes". The round-2 fixes also need recording: the output format, the grep wrapper (§8 R6), the Phase 9 capture, and AC-20 to AC-23.

**Files:**
- Modify: `claude-skills/ship-workflow/README.md`
- Modify: `docs/specs/R-003-add-security-review-gate.md`

- [ ] **Step 1: Apply the update**

````bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/README.md b/claude-skills/ship-workflow/README.md
index 3b56bec..683ddea 100644
--- a/claude-skills/ship-workflow/README.md
+++ b/claude-skills/ship-workflow/README.md
@@ -48,10 +48,11 @@ cd /path/to/your/repo
 
 Every review attempt runs a **separate security pass** next to code-review-skill, as in
 Anthropic's own pipeline. It is a vendored copy of Anthropic's open-source
-`/security-review` prompt (MIT; `templates/security-review/`) with four changes: it
+`/security-review` prompt (MIT; `templates/security-review/`) with five changes: it
 reviews this ship's diff (`<base>...HEAD`), it writes ship-next's severity format, it
-**includes prompt injection and unsafe handling of LLM output**, and it may report
-pre-existing issues tagged `[pre-existing]`.
+**includes prompt injection and unsafe handling of LLM output**, its false-positive
+filters also see that category, and it may report pre-existing issues tagged
+`[pre-existing]`.
 
 - HIGH findings block like code-review blockers (same fix-plan loop, cap 3). MEDIUM is
   important; LOW is a nit.
diff --git a/docs/specs/R-003-add-security-review-gate.md b/docs/specs/R-003-add-security-review-gate.md
index 3d1e2ef..b8c846c 100644
--- a/docs/specs/R-003-add-security-review-gate.md
+++ b/docs/specs/R-003-add-security-review-gate.md
@@ -115,7 +115,10 @@ supersedes: null
     - HIGH → `🔴 [blocking]`, MEDIUM → `🟡 [important]`, LOW → `🟢 [nit]`.
     - A pre-existing finding inserts `[pre-existing]` after the severity tag and adds
       an indented `Base evidence: <file>:<line> exists unchanged on {{orig_branch}}` line.
-    - No line other than a finding may begin with one of those emoji or tags.
+    - The output is nothing but finding lines, their indented detail lines and blank
+      lines: no title, headings, preamble or summary. A detail line never carries a
+      severity marker or tag. This is exactly what `security_review_output_check`
+      accepts, and the prompt's own example passes it.
     - With no findings, the output is exactly `No security findings.`
   - **C3 AI-input safety.**
     - Hard exclusion 14 is deleted.
@@ -174,6 +177,13 @@ review definitions run from the base branch.
   is blank or an indented detail line. Exit 3 otherwise, including a missing file. An
   upstream `# Vuln 1` block, a bulleted `- 🔴 …` or a bold `**HIGH**` line could hold a
   finding the parser counts as zero; one well-formed line elsewhere does not excuse it.
+  - A finding line's marker and tag must agree (`🔴 [blocking]`, `🟡 [important]`,
+    `🟢 [nit]`).
+  - A detail line may not carry a severity marker, a severity tag, `Severity:` or
+    `**HIGH**`-style text.
+  - It calls `command grep`, never plain `grep`: step 1.6 sources it into Claude
+    Code's shell, where `grep` is a ugrep wrapper whose `-vq` exits 1 even when a line
+    does not match (§8 R6).
 - `PRE_EXISTING_RE` — the one position the tag counts in: at the start of a finding
   line, right after the severity tag (`🔴 [blocking] [pre-existing] …`). Quoted in a
   description, inside a path or in other case, `[pre-existing]` is plain text and the
@@ -234,7 +244,8 @@ review definitions run from the base branch.
 - **New step 1.6** (its own block) guards `ORIG_BRANCH`, `REVIEW_OUT`, `ID`, `attempt`,
   sources both libs with a check, runs `security_review_output_check`, then
   `pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"`.
-- **The loop** removes `REVIEW_OUT` before code-review-skill writes it, then parses
+- **The loop** removes `REVIEW_OUT` and `SEC_OUT` at the top of every attempt, so a
+  skipped step 1.5 cannot leave an earlier run's report in place. It then parses
   both files: `PARSED=$(code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT") || exit 1`, then
   `eval "$PARSED"`. A failed parse must stop the gate: `eval` of an empty string
   succeeds and leaves `BLOCKING_COUNT` unset.
@@ -254,7 +265,7 @@ review definitions run from the base branch.
   - For each `pre_existing_lines "$REVIEW_OUT" "$SEC_OUT"` line, compute
     `pre_existing_key`.
   - If `pre_existing_tracked` says it is already tracked, show
-    `already tracked (<IDEA file>)` and skip it.
+    `already tracked: <key>` and skip it.
   - Otherwise:
     - Interactive: offer `[I]dea-NNN / [S]kip`.
     - Auto: create the IDEA via `/ship-idea --during-build … --related-roadmap-item "$ID"`.
@@ -265,7 +276,13 @@ review definitions run from the base branch.
   `Security review: blocking 0 ✓ (security findings: N, pre-existing: N)`. When
   `$WORKTREE/.ship/security-review-state` says `off`, the line says
   `off (ship-config on <ORIG_BRANCH>)` instead, so a landed commit never claims a
-  review that did not run.
+  review that did not run. Phase 9 step 0 captures the state as
+  `SECURITY_REVIEW_STATE`, because step 1 removes the worktree before the summary is
+  built.
+- **Interactive blocker printing and step 4** use `grep -h`, and only finding lines
+  become IDEAs. Without `-h`, two-file output is prefixed with file names and the
+  anchored pre-existing filter removes nothing. A removed pre-existing finding also
+  leaves its detail lines behind, and those must never be filed as majors.
 - **Kill switch:** `security_review: off` in `.claude/ship-config.yml` **on the base
   branch** (§3.3).
 
@@ -278,8 +295,8 @@ The ship-workflow README documents the security pass, the kill switch, and
 | Seam | Interface | Guaranteed behavior |
 |---|---|---|
 | `security_review_enabled` | `security_review_enabled <orig_branch>` | exit 0 unless `<orig_branch>:.claude/ship-config.yml` says `security_review: off`; default on; the branch's own copy is ignored |
-| `security_review_render` | `security_review_render <orig_branch> <out>` | writes the vendored prompt with `{{orig_branch}}` substituted and no `origin/HEAD`; appends `<orig_branch>:docs/SECURITY_REVIEW.md` under `## REPOSITORY-SPECIFIC NOTES` when it exists there; flags a diff that touches `docs/SECURITY_REVIEW.md` or `.claude/ship-config.yml`; exit 2 on an unresolvable branch or missing template; no git writes |
-| `security_review_output_check` | `security_review_output_check <file>` | exit 0 for `No security findings.`, or ≥1 C2 finding line with every other line blank or indented; exit 3 otherwise, including a missing file |
+| `security_review_render` | `security_review_render <orig_branch> <out>` | writes the vendored prompt with `{{orig_branch}}` substituted and no `origin/HEAD`; appends `<orig_branch>:docs/SECURITY_REVIEW.md` under `## REPOSITORY-SPECIFIC NOTES` when it exists there; flags a diff that touches `docs/SECURITY_REVIEW.md`, `.claude/ship-config.yml` or `.claude/commands/ship-next.md` (root-anchored, any cwd); exit 2 on an unresolvable branch or missing template; no git writes |
+| `security_review_output_check` | `security_review_output_check <file>` | exit 0 for `No security findings.`, or ≥1 C2 finding line (marker and tag agreeing) with every other line blank or an indented detail line that carries no severity; exit 3 otherwise, including a missing file; the same result in bash and in Claude Code's shell |
 | `PRE_EXISTING_RE` / `pre_existing_lines` | `pre_existing_lines <file>…` | matches the tag only right after a leading severity tag; prints those lines; no output (exit 0) when none |
 | `pre_existing_key` / `pre_existing_tracked` | `pre_existing_key <line>` → key; `pre_existing_tracked <key>` | key is `<file>:<category>` or `<file>:<desc40>` (valid UTF-8); tracked iff some `docs/ideas/*.md` contains `(pre-existing-key: <key>)` |
 | `pre_existing_strip_unverified` | `pre_existing_strip_unverified <base> <file>…` | in place, drops the tag from anchored lines citing a file absent on `<base>` or no file; leaves every other line byte-identical; exit 2 on an unresolvable base |
@@ -308,6 +325,10 @@ The ship-workflow README documents the security pass, the kill switch, and
 | AC-17 | a stale `SEC_OUT` from an earlier run / a missing `security-review.sh` | step 1.5 block-executed | the stale file is gone afterwards / exit 1 with "lib is missing", never "security review: off", and no `SEC_OUT` |
 | AC-18 | `security_review: off` on `main` | step 1.5 then the Phase 7 body | `.ship/security-review-state` is `off`; the body says `Security review: off (ship-config on main)` |
 | AC-19 | a missing review file | the loop's parse | Phase 6 stops (exit 1); the gate is not passed |
+| AC-20 | a nit plus `- 🔴 [blocking] …`, checked with `grep` wrapped the way Claude Code wraps it / an indented `- 🔴 [blocking] …`, `**HIGH**` or `* Severity: High` detail / `🟢 [blocking] …` | `security_review_output_check` | 3 / 3 / 3 |
+| AC-21 | the prompt's REQUIRED OUTPUT FORMAT example | `security_review_output_check` | 0 |
+| AC-22 | a code review whose first major is `[pre-existing]` with a `Base evidence:` line, then a new major; a security report with one MEDIUM | step 4 (auto) block-executed | two IDEAs, one per new major; none from a detail line |
+| AC-23 | `security_review: off` recorded in the worktree | Phase 9 step 0, then step 1 removes the worktree | the summary still says `off (ship-config on <ORIG_BRANCH>)` |
 | AC-11 | ship-next Phase 6 | inspected and block-executed | the security step renders the prompt and the parse call takes both files; every block that reads `MERGE_MODE`/`ORIG_BRANCH` resolves it (existing structural test still passes); step 4.5 exists and never feeds `BLOCKING_COUNT` |
 
 ## §5 Rollout
@@ -335,3 +356,8 @@ Repo-specific accuracy improves when langlive adds `docs/SECURITY_REVIEW.md`
   files with the invocation's arguments. New Phase 6 bash must not use positional
   parameters (`$1`, `$#`, `shift`, `set --`). The existing ones are a separate
   follow-up.
+- **R6 Claude Code's grep wrapper.** Command blocks run in Claude Code's zsh, where
+  `grep` is a shell function that calls an embedded ugrep. Most flags behave like
+  grep, but `-vq` does not: it exits 1 even when a line does not match. bats runs under
+  bash and cannot see this, so lib functions that a block sources use `command grep`
+  wherever a flag's exit status matters this way. A test emulates the wrapper.
R003_PATCH
````

- [ ] **Step 2: Check the patch applied**

Run: `git diff --stat`

Expected: only `claude-skills/ship-workflow/README.md` and `docs/specs/R-003-add-security-review-gate.md` changed.

- [ ] **Step 3: Commit**

```bash
git add claude-skills/ship-workflow/README.md docs/specs
git commit -m "docs(spec): review-fix 10 — R-003 spec and README match the round-2 fixes (output format, grep wrapper, Phase 9 capture, five changes)"
```

### Task 5: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..608`, 607 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: No commit** — report DONE with the Step 1 counts.
