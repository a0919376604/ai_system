# R-003 Implementation Plan — a separate security gate in ship-next Phase 6, plus Pre-existing findings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Phase 6 review attempt also runs a vendored copy of Anthropic's `/security-review`. The copy reviews this ship's diff, writes ship-next's severity format, and includes prompt-injection checks. Its HIGH findings block like code-review blockers. `[pre-existing]` findings never block and become one follow-up each.

**Architecture:** Four focused units, each behind a bats-tested seam:
- `code-review-parse.sh` sums several reports and excludes `[pre-existing]` lines.
- `templates/security-review/PROMPT.md` is the vendored MIT prompt.
- `lib/security-review.sh` renders the prompt and checks its output, reading the review's own config **from the base branch**.
- `lib/pre-existing.sh` holds the stable keys.

`commands/ship-next.md` only calls these. Its new blocks are executed by tests, not grepped.

**Tech Stack:** bash + zsh-compatible shell, git ≥ 2.38, bats 1.13, awk/sed.

**Spec:** `docs/specs/R-003-add-security-review-gate.md` — read it before Task 1.

**Why code steps are patches:** this plan is written for `codex /run-plan`, and per the vault learning `codex-run-plan-plan-must-be-mechanical`, codex stops rather than guesses at any ambiguity. Each patch was generated from a working prototype and replayed task by task against this exact base. That is why this plan is longer than a signatures-only plan would be.

## Global Constraints

- **Scope.** Every file you edit is under `claude-skills/ship-workflow/` in THIS repository. That directory is this repo's product code, not agent configuration. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/` or the operator's home directory. Tests that need a home directory create their own under their scratch dir.
- **Working directory.** Run every command from the repository (worktree) root unless the step says otherwise. Patches use repo-root-relative paths.
- **Patches are the code.** Each code step is a `git apply` heredoc, generated from and replayed against this base. They apply cleanly in order. If one does not apply, STOP — do not hand-edit around it.
- **Read before each task:** `.ship/tdd-rules.md` before writing tests, `.ship/ponytail-rules.md` before writing code. If absent, proceed.
- **Tests.** Run only the scoped `bats` files each task names. The full suite runs once, in Task 7.
- **Known pre-existing failure.** In a linked worktree, `tests/test_cwd-guard.bats` "cwd-guard: exits 0 when not in a git repo at all" fails before any change. It must stay the ONLY failure.
- **bats hygiene:** a `[[ ]]` that is not the last command of a test must end in `|| return 1`.
- **zsh parity:** no `local` inside a loop body; no unquoted globs that may match nothing.
- **No positional parameters in new command blocks.** Claude Code substitutes `$0`, `$1`, … in command files with the invocation's arguments.
- **Commits.** One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

Inputs a person will hit that the spec implies; each has a test in the owning task:

1. A stale skill checkout, where the lib is present but the template is missing. The gate must halt, not vanish. → Task 3 "a missing template exits 2…", Task 5 "a stale skill checkout halts instead of skipping".
2. A ship, or an autonomous fix-plan, that adds `security_review: off` or loosens `docs/SECURITY_REVIEW.md` in its own diff. It must have no effect and must be flagged. → Task 3 "a branch cannot switch off its own review", "notes added only on the branch are not trusted, but are flagged".
3. The model falls back to upstream's `# Vuln 1 / * Severity: High` format, which would parse as zero findings. → Task 3 "output_check: rejects upstream-format…", Task 5 "an upstream-format report is rejected…".
4. The same pre-existing defect flagged by ship after ship. It must be filed once, and must not be confused with a key that merely shares a prefix. → Task 4 "a key that is only a prefix…", Task 5 "already-tracked defects are not filed again".
5. A step-1.5 block run in a fresh shell where `ORIG_BRANCH` was never set. It must stop before rendering anything. → Task 5 "refuses to run with ORIG_BRANCH unset".

---

### Task 1: `code-review-parse.sh` — several files, `[pre-existing]`, no "00"

Seam: `code-review-parse.sh`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/lib/code-review-parse.sh`
- Test: `claude-skills/ship-workflow/tests/test_code-review-parse.bats` (5 tests appended)

**Interfaces:**
- Consumes: nothing new.
- Produces: `code-review-parse.sh <file>…` → `BLOCKING_COUNT MAJOR_COUNT MINOR_COUNT PRAISE_COUNT SEAM_VIOLATION_COUNT ASSERTION_ROULETTE_COUNT WEAK_ASSERTION_COUNT PRE_EXISTING_COUNT SECURITY_COUNT`, each a single integer; `[pre-existing]` lines excluded from the four severity counts; exit 2 on any missing file.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_code-review-parse.bats b/claude-skills/ship-workflow/tests/test_code-review-parse.bats
index a44055f..95112c8 100644
--- a/claude-skills/ship-workflow/tests/test_code-review-parse.bats
+++ b/claude-skills/ship-workflow/tests/test_code-review-parse.bats
@@ -219,3 +219,51 @@ EOF
   [[ "$output" == *"ASSERTION_ROULETTE_COUNT=0"* ]] || return 1
   [[ "$output" == *"WEAK_ASSERTION_COUNT=0"* ]]
 }
+
+# --- R-003: several files, pre-existing findings, single-integer counts -------
+
+@test "code-review-parse: counts are single integers, never 00" {
+  # `grep -c … || echo 0` printed "0" twice when nothing matched, giving "00".
+  printf 'nothing here\n' > "$SCRATCH/none.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/none.md"
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qx 'BLOCKING_COUNT=0' || return 1
+  echo "$output" | grep -qx 'PRE_EXISTING_COUNT=0' || return 1
+  if echo "$output" | grep -q '=00'; then echo "a counter printed 00"; return 1; fi
+}
+
+@test "code-review-parse: [pre-existing] findings never count as blocking or important" {
+  cat > "$SCRATCH/pre.md" <<'EOF'
+🔴 [blocking] [pre-existing] a.py:3 — existed before this diff
+   Base evidence: a.py:3 exists unchanged on main
+🔴 [blocking] b.py:4 — introduced here
+🟡 [important] [pre-existing] [security:prompt_injection] c.py:9 — old flat prompt
+EOF
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/pre.md"
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qx 'BLOCKING_COUNT=1' || return 1
+  echo "$output" | grep -qx 'MAJOR_COUNT=0' || return 1
+  echo "$output" | grep -qx 'PRE_EXISTING_COUNT=2'
+}
+
+@test "code-review-parse: counts sum across several files" {
+  printf '🔴 [blocking] a.py:1 — x\n' > "$SCRATCH/r1.md"
+  printf '🔴 [blocking] [security:sql_injection] b.py:2 — y\n🟡 [important] [security:xss] c.py:3 — z\n' > "$SCRATCH/r2.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/r1.md" "$SCRATCH/r2.md"
+  [ "$status" -eq 0 ]
+  echo "$output" | grep -qx 'BLOCKING_COUNT=2' || return 1
+  echo "$output" | grep -qx 'MAJOR_COUNT=1' || return 1
+  echo "$output" | grep -qx 'SECURITY_COUNT=2'
+}
+
+@test "code-review-parse: SECURITY_COUNT leaves out pre-existing security findings" {
+  printf '🔴 [blocking] [security:sqli] a.py:1 — x\n🔴 [blocking] [pre-existing] [security:sqli] b.py:2 — y\n' > "$SCRATCH/s.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/s.md"
+  echo "$output" | grep -qx 'SECURITY_COUNT=1'
+}
+
+@test "code-review-parse: exits 2 when any of several files is missing" {
+  printf 'x\n' > "$SCRATCH/ok.md"
+  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/ok.md" "$SCRATCH/missing.md"
+  [ "$status" -eq 2 ]
+}
R003_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats; cd - >/dev/null`

Expected: `1..21`, 16 ok, these 5 fail:
  - `not ok 17 code-review-parse: counts are single integers, never 00`
  - `not ok 18 code-review-parse: [pre-existing] findings never count as blocking or important`
  - `not ok 19 code-review-parse: counts sum across several files`
  - `not ok 20 code-review-parse: SECURITY_COUNT leaves out pre-existing security findings`
  - `not ok 21 code-review-parse: exits 2 when any of several files is missing`

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/code-review-parse.sh b/claude-skills/ship-workflow/lib/code-review-parse.sh
index 98af27b..07cdfd3 100755
--- a/claude-skills/ship-workflow/lib/code-review-parse.sh
+++ b/claude-skills/ship-workflow/lib/code-review-parse.sh
@@ -2,7 +2,7 @@
 # code-review-parse.sh — count severity findings in code-review-skill markdown output.
 #
 # Usage:
-#   eval "$(code-review-parse.sh /path/to/review.md)"
+#   eval "$(code-review-parse.sh /path/to/review.md [/path/to/security.md …])"
 #   echo "$BLOCKING_COUNT"   # → e.g. 2
 #
 # Recognizes severity-tag styles in the input (any one counts):
@@ -39,11 +39,26 @@
 
 set -euo pipefail
 
-FILE="${1:-}"
-if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
-  echo "ERROR: input file not found: $FILE" >&2
+# One or more review files; counts are summed across all of them (R-003: the
+# code review and the security review are parsed together).
+if [ "$#" -lt 1 ]; then
+  echo "ERROR: input file not found: " >&2
   exit 2
 fi
+for f in "$@"; do
+  [ -f "$f" ] || { echo "ERROR: input file not found: $f" >&2; exit 2; }
+done
+
+ALL=$(mktemp "${TMPDIR:-/tmp}/crp-all.XXXXXX")
+FILE=$(mktemp "${TMPDIR:-/tmp}/crp-kept.XXXXXX")
+trap 'rm -f "$ALL" "$FILE"' EXIT
+cat "$@" > "$ALL"
+
+# `[pre-existing]` findings (R-003) exist on the base branch already: they are
+# reported, but they never count toward any severity — so they can never block a
+# ship or be asked about as one of its own importants. Everything below counts
+# the remaining lines.
+grep -viF '[pre-existing]' "$ALL" > "$FILE" || true
 
 # Each helper greps lines matching ANY pattern for the level and counts.
 # Note: `grep -c` counts matching lines, not match instances — so duplicate
@@ -54,22 +69,22 @@ fi
 
 count_blocking() {
   # Line start: 🔴 or [blocking]; OR anywhere: **Severity:** blocking/🔴
-  grep -ciE '^[[:space:]]*(🔴|\[blocking\])|\*\*Severity:\*\*[[:space:]]*(blocking|🔴)' "$FILE" || echo 0
+  grep -ciE '^[[:space:]]*(🔴|\[blocking\])|\*\*Severity:\*\*[[:space:]]*(blocking|🔴)' "$FILE" || true
 }
 
 count_major() {
   # Line start: 🟡, [major], or [important]; OR anywhere: **Severity:** major/important/🟡
-  grep -ciE '^[[:space:]]*(🟡|\[major\]|\[important\])|\*\*Severity:\*\*[[:space:]]*(major|important|🟡)' "$FILE" || echo 0
+  grep -ciE '^[[:space:]]*(🟡|\[major\]|\[important\])|\*\*Severity:\*\*[[:space:]]*(major|important|🟡)' "$FILE" || true
 }
 
 count_minor() {
   # Line start: 🟢, [minor], or [nit]; OR anywhere: **Severity:** minor/nit/🟢
-  grep -ciE '^[[:space:]]*(🟢|\[minor\]|\[nit\])|\*\*Severity:\*\*[[:space:]]*(minor|nit|🟢)' "$FILE" || echo 0
+  grep -ciE '^[[:space:]]*(🟢|\[minor\]|\[nit\])|\*\*Severity:\*\*[[:space:]]*(minor|nit|🟢)' "$FILE" || true
 }
 
 count_praise() {
   # Line start: 🎉 or [praise]; OR anywhere: **Severity:** praise/🎉
-  grep -ciE '^[[:space:]]*(🎉|\[praise\])|\*\*Severity:\*\*[[:space:]]*(praise|🎉)' "$FILE" || echo 0
+  grep -ciE '^[[:space:]]*(🎉|\[praise\])|\*\*Severity:\*\*[[:space:]]*(praise|🎉)' "$FILE" || true
 }
 
 # --- Category counters (orthogonal to severity) ------------------------------
@@ -78,15 +93,23 @@ count_praise() {
 # occupies the line-start position.
 
 count_seam_violation() {
-  grep -ciE '\[seam-violation\]' "$FILE" || echo 0
+  grep -ciE '\[seam-violation\]' "$FILE" || true
 }
 
 count_assertion_roulette() {
-  grep -ciE '\[assertion-roulette\]' "$FILE" || echo 0
+  grep -ciE '\[assertion-roulette\]' "$FILE" || true
 }
 
 count_weak_assertion() {
-  grep -ciE '\[weak-assertion\]' "$FILE" || echo 0
+  grep -ciE '\[weak-assertion\]' "$FILE" || true
+}
+
+count_pre_existing() {
+  grep -ciF '[pre-existing]' "$ALL" || true
+}
+
+count_security() {
+  grep -ciF '[security:' "$FILE" || true
 }
 
 BLOCKING=$(count_blocking)
@@ -96,6 +119,8 @@ PRAISE=$(count_praise)
 SEAM_VIOLATION=$(count_seam_violation)
 ASSERTION_ROULETTE=$(count_assertion_roulette)
 WEAK_ASSERTION=$(count_weak_assertion)
+PRE_EXISTING=$(count_pre_existing)
+SECURITY=$(count_security)
 
 # Strip whitespace that grep -c may inject on some bash versions
 BLOCKING=$(echo -n "$BLOCKING" | tr -d '[:space:]')
@@ -105,6 +130,8 @@ PRAISE=$(echo -n "$PRAISE" | tr -d '[:space:]')
 SEAM_VIOLATION=$(echo -n "$SEAM_VIOLATION" | tr -d '[:space:]')
 ASSERTION_ROULETTE=$(echo -n "$ASSERTION_ROULETTE" | tr -d '[:space:]')
 WEAK_ASSERTION=$(echo -n "$WEAK_ASSERTION" | tr -d '[:space:]')
+PRE_EXISTING=$(echo -n "$PRE_EXISTING" | tr -d '[:space:]')
+SECURITY=$(echo -n "$SECURITY" | tr -d '[:space:]')
 
 echo "BLOCKING_COUNT=${BLOCKING}"
 echo "MAJOR_COUNT=${MAJOR}"
@@ -113,3 +140,5 @@ echo "PRAISE_COUNT=${PRAISE}"
 echo "SEAM_VIOLATION_COUNT=${SEAM_VIOLATION}"
 echo "ASSERTION_ROULETTE_COUNT=${ASSERTION_ROULETTE}"
 echo "WEAK_ASSERTION_COUNT=${WEAK_ASSERTION}"
+echo "PRE_EXISTING_COUNT=${PRE_EXISTING:-0}"
+echo "SECURITY_COUNT=${SECURITY:-0}"
R003_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats; cd - >/dev/null`

Expected: `1..21`, all 21 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(code-review-parse): R-003 Task 1 — sum several reports, exclude [pre-existing], never print 00"
```

### Task 2: Vendored security-review prompt + upstream MIT license

Seam: vendored prompt

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Create: `claude-skills/ship-workflow/templates/security-review/PROMPT.md` (upstream @ 0c6a49f1fa56 with changes C1–C4)
- Create: `claude-skills/ship-workflow/templates/security-review/LICENSE.upstream` (upstream MIT text, verbatim)
- Test: `claude-skills/ship-workflow/tests/test_security-review-template.bats` (new)

**Interfaces:**
- Consumes: nothing.
- Produces: `templates/security-review/PROMPT.md` with placeholder `{{orig_branch}}`; output format `🔴 [blocking] [security:<category>] <file>:<line> — <description>`, or exactly `No security findings.`

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review-template.bats b/claude-skills/ship-workflow/tests/test_security-review-template.bats
new file mode 100644
index 0000000..c3bdc14
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_security-review-template.bats
@@ -0,0 +1,83 @@
+#!/usr/bin/env bats
+# The vendored security-review prompt (R-003 §3.2): upstream's false-positive
+# discipline must survive vendoring intact. Each upstream hard exclusion and
+# precedent is pinned by a key phrase, so a careless edit cannot drop one.
+load helpers
+
+setup() {
+  export T="$SHIP_SKILL_ROOT/templates/security-review/PROMPT.md"
+  export L="$SHIP_SKILL_ROOT/templates/security-review/LICENSE.upstream"
+}
+
+has() { grep -qF -- "$1" "$T" || { echo "missing: $1"; return 1; }; }
+
+@test "template names its upstream source, commit and license" {
+  has 'anthropics/claude-code-security-review @ 0c6a49f1fa56'
+  has 'Copyright (c) 2025 Anthropic'
+  grep -qx 'MIT License' "$L"
+  grep -qF 'Copyright (c) 2025 Anthropic' "$L"
+}
+
+@test "template keeps upstream hard exclusions 1-13 and 15-17" {
+  for phrase in \
+    'Denial of Service (DOS) vulnerabilities or resource exhaustion attacks.' \
+    'Secrets or credentials stored on disk if they are otherwise secured.' \
+    'Rate limiting concerns or service overload scenarios.' \
+    'Memory consumption or CPU exhaustion issues.' \
+    'Lack of input validation on non-security-critical fields without proven security impact.' \
+    'Input sanitization concerns for GitHub Action workflows' \
+    'A lack of hardening measures.' \
+    'Race conditions or timing attacks that are theoretical' \
+    'Vulnerabilities related to outdated third-party libraries.' \
+    'Do not report memory safety issues in rust' \
+    'Files that are only unit tests or only used as part of running tests.' \
+    'Log spoofing concerns.' \
+    'SSRF vulnerabilities that only control the path.' \
+    'Regex injection.' \
+    'Regex DOS concerns.' \
+    'Insecure documentation.' \
+    'A lack of audit logs is not a vulnerability.'; do
+    has "$phrase" || return 1
+  done
+}
+
+@test "template keeps all 12 upstream precedents and the confidence cutoff" {
+  for phrase in \
+    'Logging high value secrets in plaintext is a vulnerability.' \
+    'UUIDs can be assumed to be unguessable' \
+    'Environment variables and CLI flags are trusted values.' \
+    'Resource management issues such as memory or file descriptor leaks are not valid.' \
+    'tabnabbing, XS-Leaks, prototype pollution, and open redirects' \
+    'React and Angular are generally secure against XSS.' \
+    'Most vulnerabilities in github action workflows are not exploitable in practice.' \
+    'A lack of permission checking or authentication in client-side JS/TS code is not a vulnerability.' \
+    'Only include MEDIUM findings if they are obvious and concrete issues.' \
+    'Most vulnerabilities in ipython notebooks' \
+    'Logging non-PII data is not a vulnerability' \
+    'Command injection vulnerabilities in shell scripts are generally not exploitable in practice' \
+    'Filter out any vulnerabilities where the sub-task reported a confidence less than 8.'; do
+    has "$phrase" || return 1
+  done
+}
+
+@test "template drops exclusion 14 and adds the LLM / AI input safety checklist" {
+  if grep -qF 'Including user-controlled content in AI system prompts is not a vulnerability.' "$T"; then
+    echo "exclusion 14 is still there"; return 1
+  fi
+  has '**LLM / AI Input Safety**'
+  has 'Stored / indirect prompt injection'
+  has 'stored injection that reaches other users → HIGH'
+}
+
+@test "template diffs the ship, not the remote default branch" {
+  has 'git diff {{orig_branch}}...HEAD'
+  if grep -qF 'origin/HEAD' "$T"; then echo "still diffs origin/HEAD"; return 1; fi
+  if grep -q '^allowed-tools:' "$T"; then echo "slash-command frontmatter left in"; return 1; fi
+}
+
+@test "template output format is the one code-review-parse.sh counts" {
+  has '🔴 [blocking] [security:<category>] <file>:<line> — <one-line description>'
+  has 'No security findings.'
+  has '[pre-existing]'
+  if grep -qF '# Vuln 1:' "$T"; then echo "upstream output format left in"; return 1; fi
+}
R003_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..6`, 0 ok, these 6 fail:
  - `not ok 1 template names its upstream source, commit and license`
  - `not ok 2 template keeps upstream hard exclusions 1-13 and 15-17`
  - `not ok 3 template keeps all 12 upstream precedents and the confidence cutoff`
  - `not ok 4 template drops exclusion 14 and adds the LLM / AI input safety checklist`
  - `not ok 5 template diffs the ship, not the remote default branch`
  - `not ok 6 template output format is the one code-review-parse.sh counts`

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/templates/security-review/LICENSE.upstream b/claude-skills/ship-workflow/templates/security-review/LICENSE.upstream
new file mode 100644
index 0000000..aadec62
--- /dev/null
+++ b/claude-skills/ship-workflow/templates/security-review/LICENSE.upstream
@@ -0,0 +1,21 @@
+MIT License
+
+Copyright (c) 2025 Anthropic
+
+Permission is hereby granted, free of charge, to any person obtaining a copy
+of this software and associated documentation files (the "Software"), to deal
+in the Software without restriction, including without limitation the rights
+to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
+copies of the Software, and to permit persons to whom the Software is
+furnished to do so, subject to the following conditions:
+
+The above copyright notice and this permission notice shall be included in all
+copies or substantial portions of the Software.
+
+THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
+IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
+AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
+OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
+SOFTWARE.
\ No newline at end of file
diff --git a/claude-skills/ship-workflow/templates/security-review/PROMPT.md b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
new file mode 100644
index 0000000..8b2b18d
--- /dev/null
+++ b/claude-skills/ship-workflow/templates/security-review/PROMPT.md
@@ -0,0 +1,197 @@
+<!--
+Derived from anthropics/claude-code-security-review @ 0c6a49f1fa56,
+.claude/commands/security-review.md — MIT License, Copyright (c) 2025 Anthropic
+(full text: LICENSE.upstream in this directory).
+
+ship-workflow changes (R-003, docs/specs/R-003-add-security-review-gate.md §3.2):
+  C1  git context: explicit commands against {{orig_branch}} instead of the remote default branch;
+      slash-command frontmatter removed
+  C2  output: ship-next's severity line format instead of "# Vuln N" blocks
+  C3  hard exclusion 14 (user content in AI prompts) removed; an
+      "LLM / AI input safety" category and severity guidance added
+  C4  pre-existing issues may be reported, tagged [pre-existing]
+Everything else is upstream text, unchanged.
+-->
+
+You are a senior security engineer conducting a focused security review of the changes on this branch.
+
+GIT CONTEXT — run these in the repository root before anything else:
+
+```
+git status
+git diff --name-only {{orig_branch}}...HEAD
+git log --no-decorate {{orig_branch}}..HEAD
+git diff {{orig_branch}}...HEAD
+```
+
+Review the complete diff from the last command. It contains all code changes in this ship.
+
+
+OBJECTIVE:
+Perform a security-focused code review to identify HIGH-CONFIDENCE security vulnerabilities that could have real exploitation potential. This is not a general code review - focus ONLY on security implications newly added or made newly reachable by this change. A HIGH-confidence vulnerability that already exists on {{orig_branch}}, on a code path this diff touches, may be reported — but only tagged `[pre-existing]` with base evidence (see REQUIRED OUTPUT FORMAT). It will not block this change.
+
+CRITICAL INSTRUCTIONS:
+1. MINIMIZE FALSE POSITIVES: Only flag issues where you're >80% confident of actual exploitability
+2. AVOID NOISE: Skip theoretical issues, style concerns, or low-impact findings
+3. FOCUS ON IMPACT: Prioritize vulnerabilities that could lead to unauthorized access, data breaches, or system compromise
+4. EXCLUSIONS: Do NOT report the following issue types:
+   - Denial of Service (DOS) vulnerabilities, even if they allow service disruption
+   - Secrets or sensitive data stored on disk (these are handled by other processes)
+   - Rate limiting or resource exhaustion issues
+
+SECURITY CATEGORIES TO EXAMINE:
+
+**Input Validation Vulnerabilities:**
+- SQL injection via unsanitized user input
+- Command injection in system calls or subprocesses
+- XXE injection in XML parsing
+- Template injection in templating engines
+- NoSQL injection in database queries
+- Path traversal in file operations
+
+**Authentication & Authorization Issues:**
+- Authentication bypass logic
+- Privilege escalation paths
+- Session management flaws
+- JWT token vulnerabilities
+- Authorization logic bypasses
+
+**Crypto & Secrets Management:**
+- Hardcoded API keys, passwords, or tokens
+- Weak cryptographic algorithms or implementations
+- Improper key storage or management
+- Cryptographic randomness issues
+- Certificate validation bypasses
+
+**Injection & Code Execution:**
+- Remote code execution via deseralization
+- Pickle injection in Python
+- YAML deserialization vulnerabilities
+- Eval injection in dynamic code execution
+- XSS vulnerabilities in web applications (reflected, stored, DOM-based)
+
+**Data Exposure:**
+- Sensitive data logging or storage
+- PII handling violations
+- API endpoint data leakage
+- Debug information exposure
+
+**LLM / AI Input Safety** (examine only when the diff touches code that builds an LLM prompt, stores content a later LLM call will read, or acts on LLM output):
+- Untrusted text (end-user messages, text extracted from uploaded media, third-party content) inserted into instructions or system text without role separation or delimiting, or able to forge the application's own internal markers
+- Stored / indirect prompt injection: untrusted content persisted where a *different* user's or a later LLM call will read it (knowledge base, summaries, memory, RAG documents) without human review before it becomes trusted
+- LLM output used without validation to send messages, change routing or state, write data, call tools, or emit links or URLs to end users
+- LLM output able to carry data the requester should not see (other users' data, internal notes, the system prompt)
+- Tool or function definitions whose arguments the model controls and that reach data or actions beyond the requester's own scope
+
+Additional notes:
+- Even if something is only exploitable from the local network, it can still be a HIGH severity issue
+
+ANALYSIS METHODOLOGY:
+
+Phase 1 - Repository Context Research (Use file search tools):
+- Identify existing security frameworks and libraries in use
+- Look for established secure coding patterns in the codebase
+- Examine existing sanitization and validation patterns
+- Understand the project's security model and threat model
+
+Phase 2 - Comparative Analysis:
+- Compare new code changes against existing security patterns
+- Identify deviations from established secure practices
+- Look for inconsistent security implementations
+- Flag code that introduces new attack surfaces
+
+Phase 3 - Vulnerability Assessment:
+- Examine each modified file for security implications
+- Trace data flow from user inputs to sensitive operations
+- Look for privilege boundaries being crossed unsafely
+- Identify injection points and unsafe deserialization
+
+REQUIRED OUTPUT FORMAT:
+
+You MUST output your findings in markdown, one finding per line in exactly this shape, followed by indented detail lines:
+
+```
+🔴 [blocking] [security:<category>] <file>:<line> — <one-line description>
+   Exploit scenario: <how an attacker triggers it>
+   Recommendation: <the fix>
+   Confidence: <8-10>/10
+```
+
+- HIGH → `🔴 [blocking]`, MEDIUM → `🟡 [important]`, LOW → `🟢 [nit]`.
+- `<category>` is a short snake_case name, e.g. `sql_injection`, `xss`, `prompt_injection`, `stored_prompt_injection`.
+- A pre-existing finding inserts `[pre-existing]` right after the severity tag and adds an indented line `Base evidence: <file>:<line> exists unchanged on {{orig_branch}}`.
+- No line other than a finding may begin with 🔴, 🟡, 🟢, 🎉 or a `[blocking]` / `[important]` / `[nit]` tag.
+- If there are no findings, your entire output is exactly: `No security findings.`
+
+SEVERITY GUIDELINES:
+- **HIGH**: Directly exploitable vulnerabilities leading to RCE, data breach, or authentication bypass
+- **MEDIUM**: Vulnerabilities requiring specific conditions but with significant impact
+- **LOW**: Defense-in-depth issues or lower-impact vulnerabilities
+- LLM / AI input safety: stored injection that reaches other users → HIGH; LLM output or model-controlled tool arguments that reach state-changing actions → HIGH; a newly introduced unseparated insertion of untrusted text → MEDIUM, unless it chains into one of the HIGH cases
+
+CONFIDENCE SCORING:
+- 0.9-1.0: Certain exploit path identified, tested if possible
+- 0.8-0.9: Clear vulnerability pattern with known exploitation methods
+- 0.7-0.8: Suspicious pattern requiring specific conditions to exploit
+- Below 0.7: Don't report (too speculative)
+
+FINAL REMINDER:
+Focus on HIGH and MEDIUM findings only. Better to miss some theoretical issues than flood the report with false positives. Each finding should be something a security engineer would confidently raise in a PR review.
+
+FALSE POSITIVE FILTERING:
+
+> You do not need to run commands to reproduce the vulnerability, just read the code to determine if it is a real vulnerability. Do not use the bash tool or write to any files.
+>
+> HARD EXCLUSIONS - Automatically exclude findings matching these patterns:
+> 1. Denial of Service (DOS) vulnerabilities or resource exhaustion attacks.
+> 2. Secrets or credentials stored on disk if they are otherwise secured.
+> 3. Rate limiting concerns or service overload scenarios.
+> 4. Memory consumption or CPU exhaustion issues.
+> 5. Lack of input validation on non-security-critical fields without proven security impact.
+> 6. Input sanitization concerns for GitHub Action workflows unless they are clearly triggerable via untrusted input.
+> 7. A lack of hardening measures. Code is not expected to implement all security best practices, only flag concrete vulnerabilities.
+> 8. Race conditions or timing attacks that are theoretical rather than practical issues. Only report a race condition if it is concretely problematic.
+> 9. Vulnerabilities related to outdated third-party libraries. These are managed separately and should not be reported here.
+> 10. Memory safety issues such as buffer overflows or use-after-free-vulnerabilities are impossible in rust. Do not report memory safety issues in rust or any other memory safe languages.
+> 11. Files that are only unit tests or only used as part of running tests.
+> 12. Log spoofing concerns. Outputting un-sanitized user input to logs is not a vulnerability.
+> 13. SSRF vulnerabilities that only control the path. SSRF is only a concern if it can control the host or protocol.
+> 15. Regex injection. Injecting untrusted content into a regex is not a vulnerability.
+> 16. Regex DOS concerns.
+> 16. Insecure documentation. Do not report any findings in documentation files such as markdown files.
+> 17. A lack of audit logs is not a vulnerability.
+> 
+> PRECEDENTS -
+> 1. Logging high value secrets in plaintext is a vulnerability. Logging URLs is assumed to be safe.
+> 2. UUIDs can be assumed to be unguessable and do not need to be validated.
+> 3. Environment variables and CLI flags are trusted values. Attackers are generally not able to modify them in a secure environment. Any attack that relies on controlling an environment variable is invalid.
+> 4. Resource management issues such as memory or file descriptor leaks are not valid.
+> 5. Subtle or low impact web vulnerabilities such as tabnabbing, XS-Leaks, prototype pollution, and open redirects should not be reported unless they are extremely high confidence.
+> 6. React and Angular are generally secure against XSS. These frameworks do not need to sanitize or escape user input unless it is using dangerouslySetInnerHTML, bypassSecurityTrustHtml, or similar methods. Do not report XSS vulnerabilities in React or Angular components or tsx files unless they are using unsafe methods.
+> 7. Most vulnerabilities in github action workflows are not exploitable in practice. Before validating a github action workflow vulnerability ensure it is concrete and has a very specific attack path.
+> 8. A lack of permission checking or authentication in client-side JS/TS code is not a vulnerability. Client-side code is not trusted and does not need to implement these checks, they are handled on the server-side. The same applies to all flows that send untrusted data to the backend, the backend is responsible for validating and sanitizing all inputs.
+> 9. Only include MEDIUM findings if they are obvious and concrete issues.
+> 10. Most vulnerabilities in ipython notebooks (*.ipynb files) are not exploitable in practice. Before validating a notebook vulnerability ensure it is concrete and has a very specific attack path where untrusted input can trigger the vulnerability.
+> 11. Logging non-PII data is not a vulnerability even if the data may be sensitive. Only report logging vulnerabilities if they expose sensitive information such as secrets, passwords, or personally identifiable information (PII).
+> 12. Command injection vulnerabilities in shell scripts are generally not exploitable in practice since shell scripts generally do not run with untrusted user input. Only report command injection vulnerabilities in shell scripts if they are concrete and have a very specific attack path for untrusted input.
+> 
+> SIGNAL QUALITY CRITERIA - For remaining findings, assess:
+> 1. Is there a concrete, exploitable vulnerability with a clear attack path?
+> 2. Does this represent a real security risk vs theoretical best practice?
+> 3. Are there specific code locations and reproduction steps?
+> 4. Would this finding be actionable for a security team?
+> 
+> For each finding, assign a confidence score from 1-10:
+> - 1-3: Low confidence, likely false positive or noise
+> - 4-6: Medium confidence, needs investigation
+> - 7-10: High confidence, likely true vulnerability
+
+START ANALYSIS:
+
+Begin your analysis now. Do this in 3 steps (a sub-task is a separate agent you dispatch):
+
+1. Use a sub-task to identify vulnerabilities. Use the repository exploration tools to understand the codebase context, then analyze the PR changes for security implications. In the prompt for this sub-task, include all of the above.
+2. Then for each vulnerability identified by the above sub-task, create a new sub-task to filter out false-positives. Launch these sub-tasks as parallel sub-tasks. In the prompt for these sub-tasks, include everything in the "FALSE POSITIVE FILTERING" instructions.
+3. Filter out any vulnerabilities where the sub-task reported a confidence less than 8.
+
+Your final reply must contain the markdown report and nothing else.
\ No newline at end of file
R003_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review-template.bats; cd - >/dev/null`

Expected: `1..6`, all 6 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(security-review): R-003 Task 2 — vendor Anthropic's /security-review prompt with ship diff, ship-next format, AI-input checks"
```

### Task 3: `lib/security-review.sh` — enabled / render / output check

Seam: `security_review_enabled`, `security_review_render`, `security_review_output_check`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Create: `claude-skills/ship-workflow/lib/security-review.sh`
- Test: `claude-skills/ship-workflow/tests/test_security-review.bats` (new)

**Interfaces:**
- Consumes: the template from Task 2, resolved as `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/security-review/PROMPT.md`.
- Produces: `security_review_enabled <orig_branch>` (exit 0 = on; reads `<orig_branch>:.claude/ship-config.yml` only) · `security_review_render <orig_branch> <out>` (exit 2 on bad base / missing template; echoes `<out>`) · `security_review_output_check <file>` (0 ok, 3 malformed).

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_security-review.bats b/claude-skills/ship-workflow/tests/test_security-review.bats
new file mode 100644
index 0000000..156d1d0
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_security-review.bats
@@ -0,0 +1,120 @@
+#!/usr/bin/env bats
+# lib/security-review.sh (R-003 §3.3). The review's own configuration is read from
+# the base branch, never from the branch under review.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch security-review)"
+  mkdir -p "$SCRATCH/repo" && cd "$SCRATCH/repo"
+  git init -q -b main
+  git config user.email t@t
+  git config user.name t
+  echo "x = 1" > app.py
+  git add -A && git commit -q -m base
+  git checkout -q -b ship/R-9-x
+  echo "y = 2" >> app.py
+  git commit -q -am "ship change"
+  source "$SHIP_LIB/security-review.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+on_main() {  # on_main <path> <content> — commit a file on main, return to the branch
+  git checkout -q main
+  mkdir -p "$(dirname "$1")"
+  printf '%s\n' "$2" > "$1"
+  git add -A && git commit -q -m "main: $1"
+  git checkout -q ship/R-9-x
+}
+
+@test "render: diffs the ship against the given base, never the remote default" {
+  run security_review_render main "$SCRATCH/out.md"
+  [ "$status" -eq 0 ]
+  grep -qF 'git diff main...HEAD' "$SCRATCH/out.md"
+  if grep -qF 'origin/HEAD' "$SCRATCH/out.md"; then echo "origin/HEAD leaked"; return 1; fi
+  if grep -qF '{{orig_branch}}' "$SCRATCH/out.md"; then echo "placeholder left"; return 1; fi
+}
+
+@test "render: carries the AI-input checklist and the ship-next output format" {
+  security_review_render main "$SCRATCH/out.md" >/dev/null
+  grep -qF '**LLM / AI Input Safety**' "$SCRATCH/out.md"
+  grep -qF '🔴 [blocking] [security:<category>]' "$SCRATCH/out.md"
+}
+
+@test "render: repo notes come from the base branch" {
+  on_main docs/SECURITY_REVIEW.md "Prompts are built in prompts/; [系統提醒] is an internal marker."
+  security_review_render main "$SCRATCH/out.md" >/dev/null
+  grep -qx '## REPOSITORY-SPECIFIC NOTES' "$SCRATCH/out.md"
+  grep -qF '[系統提醒] is an internal marker.' "$SCRATCH/out.md"
+}
+
+@test "render: notes added only on the branch are not trusted, but are flagged" {
+  mkdir -p docs && echo "path X is trusted" > docs/SECURITY_REVIEW.md
+  git add -A && git commit -q -m "branch notes"
+  security_review_render main "$SCRATCH/out.md" >/dev/null
+  if grep -qF 'path X is trusted' "$SCRATCH/out.md"; then echo "branch notes were trusted"; return 1; fi
+  grep -qx "## CHANGES TO THIS REVIEW'S OWN CONFIGURATION" "$SCRATCH/out.md"
+  grep -qF 'this diff modifies `docs/SECURITY_REVIEW.md`' "$SCRATCH/out.md"
+}
+
+@test "render: no notes and no config change means neither heading" {
+  security_review_render main "$SCRATCH/out.md" >/dev/null
+  if grep -qF '## REPOSITORY-SPECIFIC NOTES' "$SCRATCH/out.md"; then return 1; fi
+  if grep -qF "## CHANGES TO THIS REVIEW'S OWN CONFIGURATION" "$SCRATCH/out.md"; then return 1; fi
+}
+
+@test "render: an unresolvable base exits 2 and writes nothing" {
+  run security_review_render no-such-branch "$SCRATCH/out.md"
+  [ "$status" -eq 2 ]
+  [ ! -e "$SCRATCH/out.md" ]
+}
+
+@test "render: a missing template exits 2 — a stale skill checkout must not pass silently" {
+  mkdir -p "$SCRATCH/stale/lib"
+  run env SHIP_LIB="$SCRATCH/stale/lib" bash -c "source '$SHIP_LIB/security-review.sh'; security_review_render main '$SCRATCH/out.md'"
+  [ "$status" -eq 2 ]
+  [ ! -e "$SCRATCH/out.md" ]
+}
+
+@test "enabled: on by default" {
+  run security_review_enabled main
+  [ "$status" -eq 0 ]
+}
+
+@test "enabled: off when the base branch says so" {
+  on_main .claude/ship-config.yml "security_review: off"
+  run security_review_enabled main
+  [ "$status" -eq 1 ]
+}
+
+@test "enabled: a branch cannot switch off its own review" {
+  mkdir -p .claude && echo "security_review: off" > .claude/ship-config.yml
+  git add -A && git commit -q -m "branch turns review off"
+  run security_review_enabled main
+  [ "$status" -eq 0 ]
+}
+
+@test "output_check: accepts no findings and C2 finding lines" {
+  echo "No security findings." > "$SCRATCH/none.md"
+  run security_review_output_check "$SCRATCH/none.md"
+  [ "$status" -eq 0 ]
+  printf '%s\n' '🔴 [blocking] [security:sql_injection] app.py:2 — f-string SQL' '   Confidence: 9/10' > "$SCRATCH/one.md"
+  run security_review_output_check "$SCRATCH/one.md"
+  [ "$status" -eq 0 ]
+}
+
+@test "output_check: rejects upstream-format or empty output, which would count as zero" {
+  printf '%s\n' '# Vuln 1: XSS: `foo.py:42`' '* Severity: High' > "$SCRATCH/up.md"
+  run security_review_output_check "$SCRATCH/up.md"
+  [ "$status" -eq 3 ]
+  : > "$SCRATCH/empty.md"
+  run security_review_output_check "$SCRATCH/empty.md"
+  [ "$status" -eq 3 ]
+}
+
+@test "zsh: render produces the same prompt as bash" {
+  command -v zsh >/dev/null || skip "zsh not installed"
+  security_review_render main "$SCRATCH/bash.md" >/dev/null
+  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/security-review.sh'; security_review_render main '$SCRATCH/zsh.md'"
+  [ "$status" -eq 0 ]
+  cmp -s "$SCRATCH/bash.md" "$SCRATCH/zsh.md"
+}
R003_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..13`, 0 ok, these 13 fail:
  - `not ok 1 render: diffs the ship against the given base, never the remote default`
  - `not ok 2 render: carries the AI-input checklist and the ship-next output format`
  - `not ok 3 render: repo notes come from the base branch`
  - `not ok 4 render: notes added only on the branch are not trusted, but are flagged`
  - `not ok 5 render: no notes and no config change means neither heading`
  - `not ok 6 render: an unresolvable base exits 2 and writes nothing`
  - `not ok 7 render: a missing template exits 2 — a stale skill checkout must not pass silently`
  - `not ok 8 enabled: on by default`
  - `not ok 9 enabled: off when the base branch says so`
  - `not ok 10 enabled: a branch cannot switch off its own review`
  - `not ok 11 output_check: accepts no findings and C2 finding lines`
  - `not ok 12 output_check: rejects upstream-format or empty output, which would count as zero`
  - `not ok 13 zsh: render produces the same prompt as bash`

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/security-review.sh b/claude-skills/ship-workflow/lib/security-review.sh
new file mode 100644
index 0000000..6c4964c
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/security-review.sh
@@ -0,0 +1,75 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/security-review.sh
+# The Phase 6 security pass (R-003): a vendored copy of Anthropic's open-source
+# /security-review prompt, rendered for this ship's diff.
+#
+# The review's own configuration — the `security_review: off` switch and the
+# repo's docs/SECURITY_REVIEW.md notes — is read from the BASE branch, never from
+# the branch under review. Otherwise a ship, or an autonomous fix-plan trying to
+# clear a security blocker, could relax its own review in the same diff.
+
+SECURITY_REVIEW_TEMPLATE="${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/security-review/PROMPT.md"
+
+# _sr_base_file <base> <path> — print <path> as it exists on <base>; fail if absent.
+_sr_base_file() {
+  git show "$1:$2" 2>/dev/null
+}
+
+# security_review_enabled <orig_branch> — exit 0 unless the base branch's
+# .claude/ship-config.yml says `security_review: off`. Default on.
+security_review_enabled() {
+  local base="$1" v
+  [ -n "$base" ] || return 0
+  v=$(_sr_base_file "$base" .claude/ship-config.yml \
+      | sed -n 's/^security_review:[[:space:]]*//p' | head -1 \
+      | tr -d '"'"'"' \t\r')
+  [ "$v" = "off" ] && return 1
+  return 0
+}
+
+# security_review_render <orig_branch> <out_file> — write the rendered prompt.
+# Exit 2 on a missing argument, an unresolvable base, or a missing template.
+# No git writes, no network.
+security_review_render() {
+  local base="$1" out="$2" esc notes touched p
+  [ -n "$base" ] && [ -n "$out" ] \
+    || { echo "usage: security_review_render <orig_branch> <out_file>" >&2; return 2; }
+  git rev-parse --verify -q "${base}^{commit}" >/dev/null \
+    || { echo "security_review_render: '$base' does not resolve" >&2; return 2; }
+  [ -f "$SECURITY_REVIEW_TEMPLATE" ] \
+    || { echo "security_review_render: template missing: $SECURITY_REVIEW_TEMPLATE" >&2; return 2; }
+  mkdir -p "$(dirname "$out")" || return 2
+
+  # Escape the replacement for sed: & and the | delimiter are special there.
+  esc=$(printf '%s' "$base" | sed 's/[&|\\]/\\&/g')
+  sed "s|{{orig_branch}}|$esc|g" "$SECURITY_REVIEW_TEMPLATE" > "$out.tmp" || return 2
+
+  if notes=$(_sr_base_file "$base" docs/SECURITY_REVIEW.md) && [ -n "$notes" ]; then
+    printf '\n## REPOSITORY-SPECIFIC NOTES\n\n%s\n' "$notes" >> "$out.tmp"
+  fi
+
+  touched=$(git diff --name-only "${base}...HEAD" -- docs/SECURITY_REVIEW.md .claude/ship-config.yml 2>/dev/null)
+  if [ -n "$touched" ]; then
+    printf "\n## CHANGES TO THIS REVIEW'S OWN CONFIGURATION\n\n" >> "$out.tmp"
+    printf '%s\n' "$touched" | while IFS= read -r p; do
+      printf -- '- this diff modifies `%s`; the change takes effect only after merge — review it as part of this pass.\n' "$p"
+    done >> "$out.tmp"
+  fi
+
+  mv "$out.tmp" "$out" || return 2
+  echo "$out"
+}
+
+# security_review_output_check <file> — exit 0 when the pass produced something
+# code-review-parse.sh can count: exactly "No security findings.", or at least one
+# finding line in the ship-next format and no upstream-format line. Exit 3
+# otherwise: an upstream "# Vuln 1 / * Severity: High" report would parse as zero
+# findings and pass the gate silently.
+security_review_output_check() {
+  local f="$1"
+  [ -f "$f" ] || return 3
+  [ "$(tr -d '[:space:]' < "$f")" = "Nosecurityfindings." ] && return 0
+  grep -qE '^#[[:space:]]*Vuln|^\*[[:space:]]*Severity:' "$f" && return 3
+  grep -qE '^[[:space:]]*(🔴|🟡|🟢)[[:space:]]+\[(blocking|important|nit)\]' "$f" && return 0
+  return 3
+}
R003_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_security-review.bats; cd - >/dev/null`

Expected: `1..13`, all 13 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(security-review): R-003 Task 3 — render the prompt from the base branch's config and notes; reject output that would parse as zero"
```

### Task 4: `lib/pre-existing.sh` — stable keys so a defect is filed once

Seam: `pre_existing_key`, `pre_existing_tracked`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Create: `claude-skills/ship-workflow/lib/pre-existing.sh`
- Test: `claude-skills/ship-workflow/tests/test_pre-existing.bats` (new)

**Interfaces:**
- Consumes: nothing.
- Produces: `pre_existing_key <finding-line>` → `<file>:<category>` or `<file>:<desc40>` (exit 2 without `file:line`) · `pre_existing_tracked <key>` (exit 0 when `docs/ideas/*.md` contains `(pre-existing-key: <key>)`).

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_pre-existing.bats b/claude-skills/ship-workflow/tests/test_pre-existing.bats
new file mode 100644
index 0000000..9034a78
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_pre-existing.bats
@@ -0,0 +1,47 @@
+#!/usr/bin/env bats
+# lib/pre-existing.sh (R-003 §3.5 step 4.5): a pre-existing defect flagged by
+# every ship that touches its code path must become ONE follow-up, not one per ship.
+load helpers
+
+setup() {
+  export SCRATCH="$(make_scratch pre-existing)"
+  mkdir -p "$SCRATCH/repo/docs/ideas" && cd "$SCRATCH/repo"
+  git init -q
+  source "$SHIP_LIB/pre-existing.sh"
+}
+teardown() { rm -rf "$SCRATCH"; }
+
+@test "key: file and security category for a security finding" {
+  run pre_existing_key '🔴 [blocking] [pre-existing] [security:prompt_injection] backend/prompts/a.py:247 — flat prompt'
+  [ "$status" -eq 0 ]
+  [ "$output" = "backend/prompts/a.py:prompt_injection" ]
+}
+
+@test "key: file and the first 40 lowercased characters of the description otherwise" {
+  run pre_existing_key '🟡 [important] [pre-existing] app/x.py:12 — Retry Loop Never Backs Off And Hammers The Upstream API'
+  [ "$status" -eq 0 ]
+  [ "$output" = "app/x.py:retry loop never backs off and hammers t" ]
+}
+
+@test "key: refuses a line with no file:line" {
+  run pre_existing_key '🔴 [blocking] [pre-existing] something vague'
+  [ "$status" -eq 2 ]
+}
+
+@test "tracked: true once an IDEA carries the delimited key" {
+  printf '%s\n' '# IDEA-007' 'P6 pre-existing from R-1: flat prompt (pre-existing-key: a.py:prompt_injection)' > docs/ideas/IDEA-007-x.md
+  run pre_existing_tracked 'a.py:prompt_injection'
+  [ "$status" -eq 0 ]
+}
+
+@test "tracked: a key that is only a prefix of a tracked one is not tracked" {
+  printf '%s\n' '(pre-existing-key: a.py:sql_injection)' > docs/ideas/IDEA-008-x.md
+  run pre_existing_tracked 'a.py:sql'
+  [ "$status" -ne 0 ]
+}
+
+@test "tracked: false with no ideas directory" {
+  rm -rf docs/ideas
+  run pre_existing_tracked 'a.py:prompt_injection'
+  [ "$status" -ne 0 ]
+}
R003_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_pre-existing.bats; cd - >/dev/null`

Expected: `1..6`, 0 ok, these 6 fail:
  - `not ok 1 key: file and security category for a security finding`
  - `not ok 2 key: file and the first 40 lowercased characters of the description otherwise`
  - `not ok 3 key: refuses a line with no file:line`
  - `not ok 4 tracked: true once an IDEA carries the delimited key`
  - `not ok 5 tracked: a key that is only a prefix of a tracked one is not tracked`
  - `not ok 6 tracked: false with no ideas directory`

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/lib/pre-existing.sh b/claude-skills/ship-workflow/lib/pre-existing.sh
new file mode 100644
index 0000000..59116db
--- /dev/null
+++ b/claude-skills/ship-workflow/lib/pre-existing.sh
@@ -0,0 +1,36 @@
+#!/usr/bin/env bash
+# ship-workflow/lib/pre-existing.sh
+# Follow-ups for `[pre-existing]` review findings (R-003). A defect that already
+# exists on the base branch gets flagged again by every ship that touches its code
+# path; without a stable key, each ship would file a duplicate IDEA — the repeat-flag
+# noise the Pre-existing tag exists to remove.
+#
+# Convention: the IDEA created for a pre-existing finding carries the literal text
+# `(pre-existing-key: <key>)`. The parentheses delimit the key, so `a.py:sql` is
+# never mistaken for `a.py:sql_injection`.
+
+# pre_existing_key <finding-line> — echo `<file>:<category>` for a finding tagged
+# `[security:<category>]`, else `<file>:<first 40 chars of the description,
+# lowercased>`. Exit 2 when the line names no `<file>:<line>`.
+pre_existing_key() {
+  local line="$1" file cat desc
+  file=$(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9_./-]+:[0-9]+' | head -1 | cut -d: -f1)
+  [ -n "$file" ] || return 2
+  cat=$(printf '%s\n' "$line" | sed -n 's/.*\[security:\([A-Za-z0-9_]*\)\].*/\1/p' | head -1)
+  if [ -n "$cat" ]; then
+    echo "$file:$cat"
+    return 0
+  fi
+  desc=$(printf '%s\n' "$line" | sed 's/^.* — //' | tr '[:upper:]' '[:lower:]' | cut -c1-40)
+  echo "$file:$desc"
+}
+
+# pre_existing_tracked <key> — exit 0 when some docs/ideas/*.md already carries
+# `(pre-existing-key: <key>)`.
+pre_existing_tracked() {
+  local key="$1" root
+  [ -n "$key" ] || return 2
+  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
+  [ -d "$root/docs/ideas" ] || return 1
+  grep -rqF -- "(pre-existing-key: $key)" "$root/docs/ideas" 2>/dev/null
+}
R003_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_pre-existing.bats; cd - >/dev/null`

Expected: `1..6`, all 6 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(pre-existing): R-003 Task 4 — key pre-existing findings so each defect becomes one follow-up"
```

### Task 5: Wire the security pass and pre-existing step into ship-next Phase 6

Seam: `code-review-parse.sh`, `security_review_*`, `pre_existing_*` (callers)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 6 0.5(c), new steps 1.5 / 1.6, loop parse + printing + fix-plan note, new step 4.5; Phase 7 body line; Phase 9 summary line)
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats` (6 block-executing tests appended)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-security.bats` (new)

**Interfaces:**
- Consumes: everything from Tasks 1, 3 and 4.
- Produces: Phase 6 step 1.5 writes `/tmp/ship-next-security-${ID}-${attempt}.md` (`SEC_OUT`); the loop evals `code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT"`.

- [ ] **Step 1: Write the failing test(s)**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index fc78900..fd56fcb 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -206,3 +206,73 @@ land_step5() { block ship-land.md '^5\. \*\*Clean up' '^6\. \*\*Report'; }
   run env BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
   [ -f docs/proposals/draft.md ] || { echo "cleaned the operator's checkout"; return 1; }
 }
+
+# --- R-003: the Phase 6 security pass -----------------------------------------
+
+sec_pass_block()  { block ship-next.md '^1\.5\. \*\*Security pass' '^1\.6\. \*\*Check the security report'; }
+sec_check_block() { block ship-next.md '^1\.6\. \*\*Check the security report' '^2\. \*\*Loop'; }
+pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^## Phase 7'; }
+
+@test "ship-next P6 security pass: refuses to run with ORIG_BRANCH unset" {
+  sec_pass_block > "$SCRATCH/s15.sh"
+  [ -s "$SCRATCH/s15.sh" ]
+  run env ID=R-T1 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -ne 0 ]
+  [ ! -e .ship/security-review-prompt.md ] || { echo "rendered without a base"; return 1; }
+}
+
+@test "ship-next P6 security pass: renders the prompt against the base branch" {
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env ORIG_BRANCH=main ID=R-T2 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -eq 0 ]
+  grep -qF 'git diff main...HEAD' .ship/security-review-prompt.md
+  rm -f /tmp/ship-next-security-R-T2-1.md
+}
+
+@test "ship-next P6 security pass: switched off on the base branch, it reports no findings" {
+  echo 'security_review: off' >> .claude/ship-config.yml
+  git commit -q -am "review off"
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env ORIG_BRANCH=main ID=R-T3 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -eq 0 ]
+  [ "$(cat /tmp/ship-next-security-R-T3-1.md)" = "No security findings." ]
+  [ ! -e .ship/security-review-prompt.md ]
+  rm -f /tmp/ship-next-security-R-T3-1.md
+}
+
+@test "ship-next P6 security pass: a stale skill checkout halts instead of skipping" {
+  # The lib is present but its template is not — what a checkout from before
+  # R-003 plus a half-synced lib looks like. Skipping would make the gate vanish.
+  mkdir -p "$SCRATCH/stale/.claude/skills/ship-workflow/lib"
+  cp "$SHIP_SKILL_ROOT/lib/security-review.sh" "$SCRATCH/stale/.claude/skills/ship-workflow/lib/"
+  sec_pass_block > "$SCRATCH/s15.sh"
+  run env HOME="$SCRATCH/stale" ORIG_BRANCH=main ID=R-T4 attempt=1 bash "$SCRATCH/s15.sh"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"not skipping it"* ]] || return 1
+  rm -f /tmp/ship-next-security-R-T4-1.md
+}
+
+@test "ship-next P6 security check: an upstream-format report is rejected, a clean one passes" {
+  sec_check_block > "$SCRATCH/s16.sh"
+  [ -s "$SCRATCH/s16.sh" ]
+  printf '%s\n' '# Vuln 1: XSS: `a.py:1`' '* Severity: High' > /tmp/ship-next-security-R-T5-1.md
+  run env ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
+  [ "$status" -eq 3 ]
+  echo "No security findings." > /tmp/ship-next-security-R-T5-1.md
+  run env ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
+  [ "$status" -eq 0 ]
+  rm -f /tmp/ship-next-security-R-T5-1.md
+}
+
+@test "ship-next P6 pre-existing step: already-tracked defects are not filed again" {
+  mkdir -p docs/ideas
+  echo 'flat prompt (pre-existing-key: p.py:prompt_injection)' > docs/ideas/IDEA-001-x.md
+  printf '%s\n' '🔴 [blocking] [pre-existing] [security:prompt_injection] p.py:3 — flat prompt' > "$SCRATCH/sec.md"
+  printf '%s\n' '🟡 [important] [pre-existing] q.py:9 — Retry loop never backs off' > "$SCRATCH/rev.md"
+  pre_block > "$SCRATCH/s45.sh"
+  [ -s "$SCRATCH/s45.sh" ]
+  run env REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" bash "$SCRATCH/s45.sh"
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"already tracked: p.py:prompt_injection"* ]] || return 1
+  [[ "$output" == *"new pre-existing: q.py:retry loop never backs off"* ]]
+}
diff --git a/claude-skills/ship-workflow/tests/test_ship-next-security.bats b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
new file mode 100644
index 0000000..3939965
--- /dev/null
+++ b/claude-skills/ship-workflow/tests/test_ship-next-security.bats
@@ -0,0 +1,43 @@
+#!/usr/bin/env bats
+# R-003: how the security pass is wired into ship-next Phase 6. The behaviour of
+# the new blocks is exercised in test_command-blocks.bats; these pin the wiring.
+load helpers
+
+setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }
+
+p6() { awk '/^## Phase 6/,/^## Phase 7/' "$CMD"; }
+
+@test "the reviewer is told about the [pre-existing] tag" {
+  p6 | grep -qF -- '- `[pre-existing]` — the defect exists on' || { echo "extra checks lack [pre-existing]"; return 1; }
+}
+
+@test "the loop parses the code review and the security review together" {
+  p6 | grep -qF 'code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT"' || { echo "security findings are not counted"; return 1; }
+}
+
+@test "blockers from both reviews are printed and fed to the fix-plan" {
+  p6 | grep -F 'grep -B1 -A3 -E' | grep -qF '"$REVIEW_OUT" "$SEC_OUT"' || { echo "security blockers are not printed"; return 1; }
+  p6 | grep -qF 'blocking findings from both $REVIEW_OUT and $SEC_OUT' || { echo "fix-plan ignores security blockers"; return 1; }
+}
+
+@test "pre-existing findings get their own step and never feed BLOCKING_COUNT" {
+  step=$(awk '/^4\.5\. \*\*Pre-existing findings/,/^## Phase 7/' "$CMD")
+  [ -n "$step" ] || { echo "no step 4.5"; return 1; }
+  echo "$step" | grep -qF 'pre_existing_tracked' || return 1
+  if echo "$step" | grep -qE 'BLOCKING_COUNT[[:space:]]*='; then echo "step 4.5 changes BLOCKING_COUNT"; return 1; fi
+}
+
+@test "the landed commit and the auto summary report the security review" {
+  awk '/^## Phase 7/,/^## Phase 8 /' "$CMD" | grep -qF 'Security review:' || { echo "Phase 7 body has no security line"; return 1; }
+  awk '/^## Phase 9/,0' "$CMD" | grep -qF '• security review:' || { echo "Phase 9 summary has no security line"; return 1; }
+}
+
+@test "new Phase 6 blocks use no positional parameters (Claude Code substitutes them)" {
+  # Claude Code replaces $0, $1, … in a command file with the invocation's
+  # arguments, so `$1` inside a block becomes the user's first argument.
+  blocks=$(awk '/^1\.5\. \*\*Security pass/,/^2\. \*\*Loop/' "$CMD"; awk '/^4\.5\. \*\*Pre-existing findings/,/^## Phase 7/' "$CMD")
+  [ -n "$blocks" ]
+  if echo "$blocks" | grep -qE '\$[0-9@#*]|(^|[[:space:]])shift([[:space:]]|$)|set --'; then
+    echo "a new block uses a positional parameter"; return 1
+  fi
+}
R003_PATCH
```

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats tests/test_ship-next-merge-mode.bats tests/test_ship-next-codex-loop.bats tests/test_ship-next-prune.bats tests/test_ship-next-test-gates.bats; cd - >/dev/null`

Expected: `1..87`, 75 ok, these 12 fail:
  - `not ok 15 ship-next P6 security pass: refuses to run with ORIG_BRANCH unset`
  - `not ok 16 ship-next P6 security pass: renders the prompt against the base branch`
  - `not ok 17 ship-next P6 security pass: switched off on the base branch, it reports no findings`
  - `not ok 18 ship-next P6 security pass: a stale skill checkout halts instead of skipping`
  - `not ok 19 ship-next P6 security check: an upstream-format report is rejected, a clean one passes`
  - `not ok 20 ship-next P6 pre-existing step: already-tracked defects are not filed again`
  - `not ok 21 the reviewer is told about the [pre-existing] tag`
  - `not ok 22 the loop parses the code review and the security review together`
  - `not ok 23 blockers from both reviews are printed and fed to the fix-plan`
  - `not ok 24 pre-existing findings get their own step and never feed BLOCKING_COUNT`
  - `not ok 25 the landed commit and the auto summary report the security review`
  - `not ok 26 new Phase 6 blocks use no positional parameters (Claude Code substitutes them)`

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index 65e7eb4..9bda682 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -765,6 +765,10 @@ categories by appending the literal tag to the finding line:
 - `[seam-violation]` — a test asserts something not declared in the spec's `## Seams`
 - `[assertion-roulette]` — one test bundles multiple unrelated assertions
 - `[weak-assertion]` — an assertion that cannot fail for any valid input
+- `[pre-existing]` — the defect exists on the base branch already, and this diff
+  neither introduces nor worsens it. Put the tag right after the severity tag and add
+  an indented line `Base evidence: <file>:<line> exists unchanged on <base branch>`.
+  A pre-existing finding is reported but never blocks this ship.
 
 Keep your usual severity tag as well; these categories are orthogonal to severity.
 CHECKS
@@ -783,6 +787,56 @@ CHECKS
    fi
    ```
 
+1.5. **Security pass (every review attempt)** — a separate review, next to
+   code-review-skill, as in Anthropic's own pipeline (R-003). It is a vendored copy of
+   Anthropic's open-source `/security-review` prompt, rendered for this ship's diff, with
+   prompt-injection and LLM-output checks added. Its HIGH findings block exactly like
+   code-review blockers. Run this block inside the loop below, after code-review-skill
+   has written `$REVIEW_OUT`:
+
+   ```bash
+   # Each block runs in its own shell: these come from the surrounding phase.
+   : "${ORIG_BRANCH:?ORIG_BRANCH is not set}" "${ID:?ID is not set}" "${attempt:?attempt is not set}"
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/security-review.sh
+   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
+   mkdir -p .ship
+   if security_review_enabled "$ORIG_BRANCH"; then
+     security_review_render "$ORIG_BRANCH" .ship/security-review-prompt.md >/dev/null || {
+       echo "ERROR: the security review could not be rendered — not skipping it." >&2
+       echo "       A missing lib or template usually means the local ship-workflow checkout is stale." >&2
+       exit 1
+     }
+     echo "security review: follow .ship/security-review-prompt.md and write its report to $SEC_OUT"
+   else
+     echo "No security findings." > "$SEC_OUT"
+     echo "security review: off (ship-config on $ORIG_BRANCH)"
+   fi
+   ```
+
+   Then **follow `.ship/security-review-prompt.md`**: one finder sub-task, one parallel
+   filter sub-task per candidate, drop anything below confidence 8. Write the final
+   report, and nothing else, to `$SEC_OUT`. Before accepting a `[pre-existing]`
+   finding from either review, confirm with `git show ${ORIG_BRANCH}:<file>` that the
+   cited code exists there; if it does not, delete the tag so the finding counts.
+
+1.6. **Check the security report** — the pass must never fail open:
+
+   ```bash
+   : "${ID:?ID is not set}" "${attempt:?attempt is not set}"
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/security-review.sh
+   SEC_OUT="/tmp/ship-next-security-${ID}-${attempt}.md"
+   if ! security_review_output_check "$SEC_OUT"; then
+     echo "security report is not in the required format: $SEC_OUT" >&2
+     echo "Re-run step 1.5 once. If this check fails again, stop Phase 6 here." >&2
+     exit 3
+   fi
+   ```
+
+   An upstream-format report (`# Vuln 1 … * Severity: High`) would parse as zero
+   findings and pass the gate silently. This check exists to stop that.
+
 2. **Loop:**
    ```
    # Phase 6 is a different shell from Phase 5 — Phase 7 cd's back to the main
@@ -807,8 +861,10 @@ CHECKS
      REVIEW_OUT=/tmp/ship-next-review-${ID}-${attempt}.md
      # Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT
      # Read .ship/review-extra-checks.md alongside .ship/ua-diff-report.md when present.
+     # Then run steps 1.5 and 1.6 (the security pass); they write SEC_OUT.
+     SEC_OUT=/tmp/ship-next-security-${ID}-${attempt}.md
 
-     eval "$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh $REVIEW_OUT)"
+     eval "$(~/.claude/skills/ship-workflow/lib/code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT")"
      BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))
 
      # Auto mode: log every attempt
@@ -823,7 +879,7 @@ CHECKS
      # Print blockers ONLY in interactive mode (auto mode keeps quiet)
      if [ "$AUTO" = "0" ]; then
        echo "🛑 ${BLOCKING_COUNT} blocking finding(s):"
-       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' $REVIEW_OUT
+       grep -B1 -A3 -E '(\*\*Severity:\*\*[[:space:]]*blocking|\[blocking\]|🔴)' "$REVIEW_OUT" "$SEC_OUT" | grep -viF '[pre-existing]'
      fi
 
      attempt=$((attempt + 1))
@@ -832,6 +888,8 @@ CHECKS
      # Build inline fix-plan
      FIX_PLAN=docs/plans/${ID}-${SLUG}-review-fix-${attempt}.md
      # ... (existing logic: write fix-plan, invoke subagent on it)
+     # The fix-plan covers the blocking findings from both $REVIEW_OUT and $SEC_OUT,
+     # never the [pre-existing] ones.
 
      if [ "$AUTO" = "1" ]; then
        ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P6" \
@@ -957,6 +1015,29 @@ CHECKS
 
    - **Interactive (`AUTO=0`):** list majors and ask per-finding `[F]ix-now / [I]dea-NNN-followup / [S]kip`.
 
+4.5. **Pre-existing findings** — reported by either review, tagged `[pre-existing]`.
+   They never block and are never asked about as this ship's own importants. Each
+   becomes one follow-up, and a defect that is already tracked is not filed again:
+
+   ```bash
+   : "${REVIEW_OUT:?REVIEW_OUT is not set}" "${SEC_OUT:?SEC_OUT is not set}"
+   # shellcheck disable=SC1091
+   source ~/.claude/skills/ship-workflow/lib/pre-existing.sh
+   grep -hF '[pre-existing]' "$REVIEW_OUT" "$SEC_OUT" 2>/dev/null | while IFS= read -r finding; do
+     key=$(pre_existing_key "$finding") || continue
+     if pre_existing_tracked "$key"; then
+       echo "already tracked: $key"
+     else
+       echo "new pre-existing: $key — $finding"
+     fi
+   done
+   ```
+
+   For each `new pre-existing` line, make the description end with
+   `(pre-existing-key: <key>)` so the next ship that meets the same defect skips it:
+   - **Auto (`AUTO=1`):** `/ship-idea --during-build "P6 pre-existing from $ID: <finding> (pre-existing-key: <key>)" --source "ship-next Phase 6" --related-roadmap-item "$ID"`.
+   - **Interactive (`AUTO=0`):** ask per finding `[I]dea-NNN-followup / [S]kip`.
+
 ## Phase 7 — Land the branch (squash merge, or open a review)
 
 `merge_mode` in `.claude/ship-config.yml` decides. Default `squash` — the
@@ -990,6 +1071,8 @@ review sets `merge_mode: mr`.
    - minor:    ${MINOR_COUNT}
    - praise:   ${PRAISE_COUNT}
 
+   Security review: blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})
+
    Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
    Spec:  docs/specs/${ID}-${SLUG}.md
    Plan:  docs/plans/${ID}-${SLUG}.md
@@ -1319,6 +1402,7 @@ ${CODEX_LAST_FINDINGS}
    • major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
    • minor: ${MINOR_COUNT}
    • praise: ${PRAISE_COUNT}
+   • security review: ${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN
    • CONTEXT.md: ${CONTEXT_MD_STATUS}
    • Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
    • Test pruning: ${PRUNE_STATUS}
R003_PATCH
```

- [ ] **Step 4: Run the scoped tests — all pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-security.bats tests/test_ship-next-merge-mode.bats tests/test_ship-next-codex-loop.bats tests/test_ship-next-prune.bats tests/test_ship-next-test-gates.bats; cd - >/dev/null`

Expected: `1..87`, all 87 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "feat(ship-next): R-003 Task 5 — Phase 6 runs a separate security pass every attempt; pre-existing findings become follow-ups"
```

### Task 6: README: the security review, its kill switch, `docs/SECURITY_REVIEW.md`

Seam: none (refactor)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:**
- Modify: `claude-skills/ship-workflow/README.md` (new section before Development)

**Interfaces:**
- Consumes: nothing.
- Produces: documentation only.

- [ ] **Step 1: (no test — documentation only; `Seam: none` tasks add no tests)**

- [ ] **Step 2: (nothing to run)**

- [ ] **Step 3: Implement**

```bash
git apply <<'R003_PATCH'
diff --git a/claude-skills/ship-workflow/README.md b/claude-skills/ship-workflow/README.md
index e0c77c5..3b56bec 100644
--- a/claude-skills/ship-workflow/README.md
+++ b/claude-skills/ship-workflow/README.md
@@ -44,6 +44,33 @@ cd /path/to/your/repo
 
 **UA integration** — `/ship-next` auto-picks up `.ua/knowledge-graph.json` if present in the target repo. See spec `docs/superpowers/specs/2026-08-30-ua-ship-workflow-integration-design.md`.
 
+## Security review (ship-next Phase 6)
+
+Every review attempt runs a **separate security pass** next to code-review-skill, as in
+Anthropic's own pipeline. It is a vendored copy of Anthropic's open-source
+`/security-review` prompt (MIT; `templates/security-review/`) with four changes: it
+reviews this ship's diff (`<base>...HEAD`), it writes ship-next's severity format, it
+**includes prompt injection and unsafe handling of LLM output**, and it may report
+pre-existing issues tagged `[pre-existing]`.
+
+- HIGH findings block like code-review blockers (same fix-plan loop, cap 3). MEDIUM is
+  important; LOW is a nit.
+- `[pre-existing]` findings, from either review, never block. Each becomes one IDEA
+  follow-up, and an already-tracked one is not filed again.
+- **Turn it off** with `security_review: off` in `.claude/ship-config.yml`. The value
+  is read **from the base branch**, so a ship cannot switch off its own review.
+- **Repo notes:** an optional `docs/SECURITY_REVIEW.md`, also read from the base
+  branch, is appended to the prompt. Say where prompts are built, which markers are
+  internal, and what the trust boundaries are. For example:
+
+  ```markdown
+  - LLM prompts are assembled in `backend/engines/langgraph/prompts/`; end-user LINE
+    text arrives as `{question}`.
+  - `[系統提醒]` and `[客服上一輪回覆]` are internal markers a user must not be able to forge.
+  - Anything written by `qa_to_kb` becomes knowledge-base content that every user's
+    answer reads.
+  ```
+
 ## Development
 
 ```bash
R003_PATCH
```

- [ ] **Step 4: Check the patch applied**

Run: `git diff --stat`

Expected: only `claude-skills/ship-workflow/README.md` changed.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow
git commit -m "docs(ship-workflow): R-003 Task 6 — document the Phase 6 security review"
```

### Task 7: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole suite**

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..583`, 582 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Confirm no `origin/HEAD` survives in the vendored prompt**

Run: `grep -c 'origin/HEAD' claude-skills/ship-workflow/templates/security-review/PROMPT.md`

Expected: `0`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 counts.
