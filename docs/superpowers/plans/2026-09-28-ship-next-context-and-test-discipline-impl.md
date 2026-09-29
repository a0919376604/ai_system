# ship-next Context + Test Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two gaps in `/ship-next` — domain vocabulary that does not survive across R-NNN cycles, and a test suite that only ever grows — without replacing its 9-phase shape.

**Architecture:** Three new self-contained bash libraries (`context-md.sh`, `test-budget.sh`, `ponytail-integration.sh`) each following the `ua-integration.sh` contract: every public function is a silent no-op when its dependency is absent. `ship-next.md` and `ship-compound.md` then wire them into existing phases plus two new ones (P8.5 test pruning, P8.7 UA rebuild). Markdown command files are verified by grep assertions in bats, the idiom already used by `tests/test_ship-next-no-ua.bats`.

**Tech Stack:** bash (POSIX-ish, macOS `bash 3.2` compatible — no `declare -A`, no `${x^^}`), bats-core for tests, `git`, `coverage`/`pytest` invoked only from generated instructions (never from lib code).

**Spec:** `docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md`

## Global Constraints

- Every public function in a new lib is a **silent no-op when its dependency is absent** — no stdout, exit 0. Matches `ua-integration.sh` header contract.
- **macOS bash 3.2 compatible.** No associative arrays, no `${var^^}`, no `readarray`/`mapfile`.
- `ship-workflow.yml` is **global only** at `~/.claude/ship-workflow.yml`. No per-repo config file is introduced.
- **No superpowers files are modified.** Spec/plan shape is influenced only through `templates/repo/SPEC.md`, `templates/repo/PLAN.md`, and instruction text inside `ship-next.md`.
- `CONTEXT.md` entry format is exactly one bullet per entry: `- **<term>** — <definition>` (definition may wrap onto indented continuation lines).
- CONTEXT.md caps: trigger at `> 200` lines **or** `> 60` entries; prune target `<= 150` lines.
- Test budget multipliers: `major` at `> 2x` baseline, `blocking` at `> 4x` baseline. Shadow mode for the first `3` ships.
- UA rebuild threshold: `> 50` drifted files (reused from `ua_check_drift`, not re-derived).
- ponytail scope header is fixed text: `Scope: product code. Test code is out of scope for this ladder and is governed by .ship/tdd-rules.md.`
- Tests run with `bats tests/` from `claude-skills/ship-workflow/`.
- All new lib files start with `#!/usr/bin/env bash` and a header comment block naming the file and its no-op contract.

## Review Focus

- **Empty or entry-less `CONTEXT.md`** — a file that exists but has zero `- **term**` bullets must report `0` entries and must not be treated as over-cap. Covered in Task 1.
- **Repo with zero test files** — `tb_baseline_ratio` divides by a test-line total of 0; must emit `0` rather than a divide-by-zero error or empty string. Covered in Task 2.
- **Missing `docs/learnings/_log.md`** — shadow-mode derivation reads a file that does not exist on a fresh repo; must report shadow-active rather than crash. Covered in Task 2.
- **ponytail installed but ruleset file renamed upstream** — `AGENTS.md` absent inside a present plugin dir must render nothing and exit 0, not emit a truncated rules file. Covered in Task 3.
- **Not inside a git repo** — every path helper in all three libs is reachable from a non-repo cwd and must no-op instead of leaking `fatal: not a git repository` to stdout. Covered in Tasks 1, 2, 3.

---

### Task 1: `lib/context-md.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/context-md.sh`
- Test: `claude-skills/ship-workflow/tests/test_context-md.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `context_md_path`, `context_md_line_count`, `context_md_entry_count`, `context_md_over_cap`, `context_md_orphan_terms`. Task 8 calls `context_md_over_cap` and `context_md_orphan_terms`; Task 6 calls `context_md_path`.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_context-md.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch context-md)"
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/context-md.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "context_md_path: echoes repo-root CONTEXT.md when present" {
  echo "x" > CONTEXT.md
  run context_md_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"/CONTEXT.md" ]]
}

@test "context_md_path: silent when file absent" {
  run context_md_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context_md_path: silent outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run context_md_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context_md_entry_count: counts one bullet per entry" {
  cat > CONTEXT.md <<'EOF'
# Context

- **adapter** — compiles commands/ per platform.
  Continuation line that must not be counted.
- **seam** — a declared interface boundary.
EOF
  run context_md_entry_count
  [ "$output" = "2" ]
}

@test "context_md_entry_count: zero on a file with no bullets" {
  echo "# Context" > CONTEXT.md
  run context_md_entry_count
  [ "$output" = "0" ]
}

@test "context_md_entry_count: zero when file absent" {
  run context_md_entry_count
  [ "$output" = "0" ]
}

@test "context_md_line_count: zero when file absent" {
  run context_md_line_count
  [ "$output" = "0" ]
}

@test "context_md_over_cap: false for a small file" {
  printf -- "- **a** — x\n" > CONTEXT.md
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "context_md_over_cap: true above 200 lines" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 201 ]; do echo "filler" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 0 ]
}

@test "context_md_over_cap: true above 60 entries" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 61 ]; do printf -- "- **t%s** — d\n" "$i" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 0 ]
}

@test "context_md_over_cap: false at exactly 200 lines and 60 entries" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 60 ]; do printf -- "- **t%s** — d\n" "$i" >> CONTEXT.md; i=$((i+1)); done
  i=0; while [ "$i" -lt 140 ]; do echo "filler" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "context_md_orphan_terms: lists terms with no hit outside CONTEXT.md" {
  mkdir -p src
  echo "def adapter(): pass" > src/a.py
  git add -A && git -c user.email=t@t -c user.name=t commit -q -m src
  cat > CONTEXT.md <<'EOF'
- **adapter** — present in code.
- **ghosted** — nowhere in code.
EOF
  run context_md_orphan_terms
  [[ "$output" == *"ghosted"* ]]
  [[ "$output" != *"adapter"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-md.bats`
Expected: FAIL — `context-md.sh` does not exist, so `source` errors in `setup`.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/context-md.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/context-md.sh
# Helpers for <repo>/CONTEXT.md — the project's shared domain vocabulary.
# Every public function is a silent no-op when CONTEXT.md or the git repo
# is absent: no stdout, exit 0 (except the boolean context_md_over_cap).
#
# Entry format is exactly one bullet per entry:
#   - **<term>** — <definition>
# Continuation lines are indented and are NOT counted as entries.

CONTEXT_MD_MAX_LINES=200
CONTEXT_MD_MAX_ENTRIES=60
CONTEXT_MD_TARGET_LINES=150

# context_md_path — echo the repo-root CONTEXT.md path, or nothing.
context_md_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  [ -f "$root/CONTEXT.md" ] || return 0
  echo "$root/CONTEXT.md"
}

# context_md_line_count — echo line count, or 0.
context_md_line_count() {
  local f
  f=$(context_md_path)
  if [ -z "$f" ]; then echo 0; return 0; fi
  wc -l < "$f" | tr -d '[:space:]'
}

# context_md_entry_count — echo number of `- **term**` bullets, or 0.
context_md_entry_count() {
  local f n
  f=$(context_md_path)
  if [ -z "$f" ]; then echo 0; return 0; fi
  n=$(grep -cE '^- \*\*[^*]+\*\*' "$f" || true)
  n=$(echo -n "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# context_md_over_cap — exit 0 if over either cap, 1 otherwise.
context_md_over_cap() {
  local lines entries
  lines=$(context_md_line_count)
  entries=$(context_md_entry_count)
  [ "$lines" -gt "$CONTEXT_MD_MAX_LINES" ] && return 0
  [ "$entries" -gt "$CONTEXT_MD_MAX_ENTRIES" ] && return 0
  return 1
}

# context_md_orphan_terms — echo terms (one per line) with no occurrence
# anywhere in the repo outside CONTEXT.md itself. Prune candidates.
context_md_orphan_terms() {
  local f root term
  f=$(context_md_path)
  [ -n "$f" ] || return 0
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  grep -oE '^- \*\*[^*]+\*\*' "$f" 2>/dev/null \
    | sed -e 's/^- \*\*//' -e 's/\*\*$//' \
    | while IFS= read -r term; do
        [ -n "$term" ] || continue
        if ! grep -rqIF --exclude=CONTEXT.md -- "$term" "$root" 2>/dev/null; then
          echo "$term"
        fi
      done
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_context-md.bats`
Expected: PASS — 12 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/context-md.sh claude-skills/ship-workflow/tests/test_context-md.bats
git commit -m "feat: add context-md.sh for CONTEXT.md size + orphan checks"
```

---

### Task 2: `lib/test-budget.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/test-budget.sh`
- Test: `claude-skills/ship-workflow/tests/test_test-budget.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `tb_baseline_ratio`, `tb_ship_ratio <base_ref> <head_ref>`, `tb_ship_lines <base_ref> <head_ref>`, `tb_verdict <ship_ratio> <baseline_ratio>`, `tb_shadow_active`. Task 7 calls all five; Task 9 calls `tb_verdict`'s result via the P6-exported `TEST_BUDGET_VERDICT`.

Ratios are emitted as integer basis points (`ratio * 1000`, floored) so bash 3.2 can compare them without `bc`. `tb_verdict` therefore also takes basis-point integers.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_test-budget.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch test-budget)"
  cd "$SCRATCH"
  git init -q
  git config user.email t@t
  git config user.name t
  source "$SHIP_LIB/test-budget.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

seed() {
  mkdir -p src tests
  i=0; while [ "$i" -lt 100 ]; do echo "x = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 60 ]; do echo "assert $i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m seed
}

@test "tb_baseline_ratio: 60 test lines over 100 src lines is 600 bp" {
  seed
  run tb_baseline_ratio
  [ "$output" = "600" ]
}

@test "tb_baseline_ratio: zero when repo has no test files" {
  mkdir -p src
  echo "x = 1" > src/a.py
  git add -A && git commit -q -m nosrc
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_baseline_ratio: zero when repo has no src files" {
  mkdir -p tests
  echo "assert 1" > tests/test_a.py
  git add -A && git commit -q -m notests
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_baseline_ratio: zero outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_ship_ratio: measures only lines added between two refs" {
  seed
  base=$(git rev-parse HEAD)
  i=0; while [ "$i" -lt 20 ]; do echo "y = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 10 ]; do echo "assert x$i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m ship
  run tb_ship_ratio "$base" HEAD
  [ "$output" = "500" ]
}

@test "tb_ship_ratio: zero when the ship added no src lines" {
  seed
  base=$(git rev-parse HEAD)
  echo "assert extra" >> tests/test_a.py
  git add -A && git commit -q -m testonly
  run tb_ship_ratio "$base" HEAD
  [ "$output" = "0" ]
}

@test "tb_ship_lines: echoes added test lines then added src lines" {
  seed
  base=$(git rev-parse HEAD)
  i=0; while [ "$i" -lt 20 ]; do echo "y = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 10 ]; do echo "assert x$i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m ship
  run tb_ship_lines "$base" HEAD
  [ "$output" = "10 20" ]
}

@test "tb_ship_lines: zeroes outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run tb_ship_lines HEAD HEAD
  [ "$output" = "0 0" ]
}

@test "tb_verdict: pass at exactly 2x baseline" {
  run tb_verdict 1200 600
  [ "$output" = "pass" ]
}

@test "tb_verdict: major just above 2x baseline" {
  run tb_verdict 1201 600
  [ "$output" = "major" ]
}

@test "tb_verdict: major at exactly 4x baseline" {
  run tb_verdict 2400 600
  [ "$output" = "major" ]
}

@test "tb_verdict: blocking just above 4x baseline" {
  run tb_verdict 2401 600
  [ "$output" = "blocking" ]
}

@test "tb_verdict: pass when baseline is zero (greenfield repo)" {
  run tb_verdict 9999 0
  [ "$output" = "pass" ]
}

@test "tb_shadow_active: active when _log.md is absent" {
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "tb_shadow_active: active with 2 ratio rows" {
  mkdir -p docs/learnings
  printf '| d | ship-next | R-1 | shipped (ratio 0.40 vs baseline 0.60) | n |\n' >> docs/learnings/_log.md
  printf '| d | ship-next | R-2 | shipped (ratio 0.41 vs baseline 0.60) | n |\n' >> docs/learnings/_log.md
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "tb_shadow_active: inactive at 3 ratio rows" {
  mkdir -p docs/learnings
  i=0; while [ "$i" -lt 3 ]; do
    printf '| d | ship-next | R-%s | shipped (ratio 0.40 vs baseline 0.60) | n |\n' "$i" >> docs/learnings/_log.md
    i=$((i+1))
  done
  run tb_shadow_active
  [ "$status" -eq 1 ]
}

@test "tb_shadow_active: rows without a ratio field do not count" {
  mkdir -p docs/learnings
  i=0; while [ "$i" -lt 5 ]; do
    printf '| d | ship-next | R-%s | shipped (review: blocking=0) | n |\n' "$i" >> docs/learnings/_log.md
    i=$((i+1))
  done
  run tb_shadow_active
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_test-budget.bats`
Expected: FAIL — `test-budget.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/test-budget.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/test-budget.sh
# Measures this ship's test growth against the repo's own baseline.
# Ratios are integer BASIS POINTS (ratio * 1000, floored) so bash 3.2 can
# compare them without bc. Every function echoes 0 / returns cleanly when
# it is outside a git repo or has no data.
#
# Shadow mode is DERIVED, never stored: it reads how many prior rows in
# docs/learnings/_log.md already carry a "ratio " field.

TB_MAJOR_MULT=2
TB_BLOCKING_MULT=4
TB_SHADOW_SHIPS=3

# _tb_is_test_path <path> — exit 0 if the path is test code.
_tb_is_test_path() {
  case "$1" in
    tests/*|test/*|*/tests/*|*/test/*) return 0 ;;
    test_*.py|*_test.py|*/test_*.py|*/*_test.py) return 0 ;;
    *.test.*|*.spec.*|*.bats) return 0 ;;
    *) return 1 ;;
  esac
}

# _tb_is_code_path <path> — exit 0 if the path is code we count at all.
_tb_is_code_path() {
  case "$1" in
    *.py|*.sh|*.bash|*.bats|*.js|*.ts|*.tsx|*.jsx|*.rb|*.go|*.rs) return 0 ;;
    *) return 1 ;;
  esac
}

# _tb_bp <numerator> <denominator> — echo floor(n/d * 1000), or 0 if d is 0.
_tb_bp() {
  local n="$1" d="$2"
  if [ -z "$d" ] || [ "$d" -eq 0 ] 2>/dev/null; then echo 0; return 0; fi
  echo $(( n * 1000 / d ))
}

# tb_baseline_ratio — repo-wide test_lines : src_lines, in basis points.
tb_baseline_ratio() {
  local root f tl=0 sl=0 n
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo 0; return 0; }
  [ -n "$root" ] || { echo 0; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    [ -f "$root/$f" ] || continue
    n=$(wc -l < "$root/$f" | tr -d '[:space:]')
    if _tb_is_test_path "$f"; then tl=$(( tl + n )); else sl=$(( sl + n )); fi
  done <<EOF
$(cd "$root" && git ls-files 2>/dev/null)
EOF
  _tb_bp "$tl" "$sl"
}

# tb_ship_ratio <base_ref> <head_ref> — added test_lines : added src_lines, bp.
tb_ship_ratio() {
  local base="$1" head="$2" f tl=0 sl=0 added
  git rev-parse --show-toplevel >/dev/null 2>&1 || { echo 0; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    added=$(git diff --numstat "$base...$head" -- "$f" 2>/dev/null | awk '{print $1}' | head -1)
    case "$added" in ''|-) added=0 ;; esac
    if _tb_is_test_path "$f"; then tl=$(( tl + added )); else sl=$(( sl + added )); fi
  done <<EOF
$(git diff --name-only "$base...$head" 2>/dev/null)
EOF
  _tb_bp "$tl" "$sl"
}

# tb_ship_lines <base_ref> <head_ref> — echo "<added_test_lines> <added_src_lines>".
# Shares the classification predicates with tb_ship_ratio so the two can never disagree.
tb_ship_lines() {
  local base="$1" head="$2" f tl=0 sl=0 added
  git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "0 0"; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _tb_is_code_path "$f" || continue
    added=$(git diff --numstat "$base...$head" -- "$f" 2>/dev/null | awk '{print $1}' | head -1)
    case "$added" in ''|-) added=0 ;; esac
    if _tb_is_test_path "$f"; then tl=$(( tl + added )); else sl=$(( sl + added )); fi
  done <<EOF
$(git diff --name-only "$base...$head" 2>/dev/null)
EOF
  echo "$tl $sl"
}

# tb_verdict <ship_bp> <baseline_bp> — echo pass | major | blocking.
tb_verdict() {
  local ship="$1" base="$2"
  if [ -z "$base" ] || [ "$base" -eq 0 ] 2>/dev/null; then echo pass; return 0; fi
  if [ "$ship" -gt $(( base * TB_BLOCKING_MULT )) ]; then echo blocking; return 0; fi
  if [ "$ship" -gt $(( base * TB_MAJOR_MULT )) ]; then echo major; return 0; fi
  echo pass
}

# tb_shadow_active — exit 0 while fewer than TB_SHADOW_SHIPS prior ships
# recorded a ratio in docs/learnings/_log.md.
tb_shadow_active() {
  local root log n
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  log="$root/docs/learnings/_log.md"
  [ -f "$log" ] || return 0
  n=$(grep -cF "ratio " "$log" 2>/dev/null || true)
  n=$(echo -n "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  [ "$n" -lt "$TB_SHADOW_SHIPS" ] && return 0
  return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_test-budget.bats`
Expected: PASS — 17 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/test-budget.sh claude-skills/ship-workflow/tests/test_test-budget.bats
git commit -m "feat: add test-budget.sh with repo-relative baseline and derived shadow mode"
```

---

### Task 3: `lib/ponytail-integration.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/ponytail-integration.sh`
- Test: `claude-skills/ship-workflow/tests/test_ponytail-integration.bats`
- Modify: `claude-skills/ship-workflow/tests/helpers.bash` (add `make_fake_ponytail_plugin`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ponytail_check_installed`, `ponytail_ruleset_path`, `ponytail_ruleset_sha256`, `ponytail_version`, `ponytail_render_rules <outfile>`. Task 6 calls `ponytail_render_rules`; Task 10 calls `ponytail_version` and `ponytail_ruleset_sha256` for the drift line.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/ship-workflow/tests/helpers.bash`:

```bash
# Build a fake ponytail plugin cache under <scratch>/home. Caller must
# export HOME="$scratch/home" before calling lib functions.
# $2 = version string (default 4.8.4). $3 = "noruleset" to omit AGENTS.md.
make_fake_ponytail_plugin() {
  local scratch="$1"
  local version="${2:-4.8.4}"
  local mode="${3:-}"
  local dir="$scratch/home/.claude/plugins/cache/ponytail/$version"
  mkdir -p "$dir"
  if [ "$mode" != "noruleset" ]; then
    cat > "$dir/AGENTS.md" <<'EOF'
# Ponytail

1. Does this need to exist? -> no: skip it (YAGNI)
2. Already in this codebase? -> reuse it
3. Stdlib does it? -> use it
EOF
  fi
}
```

Create `claude-skills/ship-workflow/tests/test_ponytail-integration.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ponytail-integration)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/ponytail-integration.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "ponytail_check_installed: fails when plugin absent" {
  run ponytail_check_installed
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "ponytail_check_installed: succeeds when plugin + ruleset present" {
  make_fake_ponytail_plugin "$SCRATCH"
  run ponytail_check_installed
  [ "$status" -eq 0 ]
}

@test "ponytail_check_installed: fails when plugin dir present but ruleset missing" {
  make_fake_ponytail_plugin "$SCRATCH" 4.8.4 noruleset
  run ponytail_check_installed
  [ "$status" -ne 0 ]
}

@test "ponytail_version: echoes the installed version directory name" {
  make_fake_ponytail_plugin "$SCRATCH" 5.0.1
  run ponytail_version
  [ "$output" = "5.0.1" ]
}

@test "ponytail_version: silent when plugin absent" {
  run ponytail_version
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ponytail_ruleset_sha256: stable 64-char hex for a fixed ruleset" {
  make_fake_ponytail_plugin "$SCRATCH"
  run ponytail_ruleset_sha256
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
}

@test "ponytail_ruleset_sha256: silent when plugin absent" {
  run ponytail_ruleset_sha256
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ponytail_render_rules: writes scope header then the ladder" {
  make_fake_ponytail_plugin "$SCRATCH"
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  head -1 .ship/ponytail-rules.md | grep -qF "Scope: product code."
  grep -qF "governed by .ship/tdd-rules.md" .ship/ponytail-rules.md
  grep -qF "Does this need to exist?" .ship/ponytail-rules.md
}

@test "ponytail_render_rules: writes nothing and exits 0 when plugin absent" {
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "ponytail_render_rules: writes nothing when ruleset file is missing" {
  make_fake_ponytail_plugin "$SCRATCH" 4.8.4 noruleset
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "ponytail_render_rules: silent outside a git repo" {
  make_fake_ponytail_plugin "$SCRATCH"
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run ponytail_render_rules ./rules.md
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ponytail-integration.bats`
Expected: FAIL — `ponytail-integration.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/ponytail-integration.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/ponytail-integration.sh
# Detects an installed ponytail plugin and renders its ladder into
# .ship/ponytail-rules.md for the Phase 5 executor to read.
#
# Why render instead of relying on the plugin's own activation: Phase 5
# spawns a fresh subagent per task, and ponytail documents that subagent
# start hooks cannot inject its ruleset. Injection beats activation.
#
# Every public function is a silent no-op when ponytail is absent.

PONYTAIL_SCOPE_HEADER="Scope: product code. Test code is out of scope for this ladder and is governed by .ship/tdd-rules.md."

# _ponytail_dir — echo the highest-sorting installed version directory.
_ponytail_dir() {
  local base="$HOME/.claude/plugins/cache/ponytail"
  [ -d "$base" ] || return 0
  ls -1 "$base" 2>/dev/null | sort -V | tail -1 | while IFS= read -r v; do
    [ -n "$v" ] && echo "$base/$v"
  done
}

# ponytail_version — echo the installed version, or nothing.
ponytail_version() {
  local d
  d=$(_ponytail_dir)
  [ -n "$d" ] || return 0
  basename "$d"
}

# ponytail_ruleset_path — echo the shipped AGENTS.md path, or nothing.
ponytail_ruleset_path() {
  local d
  d=$(_ponytail_dir)
  [ -n "$d" ] || return 0
  [ -f "$d/AGENTS.md" ] || return 0
  echo "$d/AGENTS.md"
}

# ponytail_check_installed — exit 0 only when plugin dir AND ruleset exist.
ponytail_check_installed() {
  local p
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 1
  return 0
}

# ponytail_ruleset_sha256 — echo the ruleset hash, or nothing.
ponytail_ruleset_sha256() {
  local p
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 0
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$p" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$p" | awk '{print $1}'
  fi
}

# ponytail_render_rules <outfile> — write scope header + ladder, or no-op.
ponytail_render_rules() {
  local out="$1" p
  [ -n "$out" ] || return 0
  p=$(ponytail_ruleset_path)
  [ -n "$p" ] || return 0
  {
    echo "$PONYTAIL_SCOPE_HEADER"
    echo
    cat "$p"
  } > "$out"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ponytail-integration.bats`
Expected: PASS — 11 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/ponytail-integration.sh \
        claude-skills/ship-workflow/tests/test_ponytail-integration.bats \
        claude-skills/ship-workflow/tests/helpers.bash
git commit -m "feat: add ponytail-integration.sh rendering ladder to .ship/"
```

---

### Task 4: three new categories in `code-review-parse.sh`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/code-review-parse.sh`
- Modify: `claude-skills/ship-workflow/tests/test_code-review-parse.bats`
- Create: `claude-skills/ship-workflow/tests/fixtures/code-review-categories.md`

**Do NOT modify `tests/fixtures/code-review-output.md`.** It is the contract for the
pre-existing severity tests; appending findings to it moves `MAJOR_COUNT` and
`MINOR_COUNT` out from under assertions this task does not own. The category tests get
their own fixture, and the shared fixture becomes a regression guard proving this task
is purely additive.

**Interfaces:**
- Consumes: nothing.
- Produces: three additional `eval`-able variables on top of the existing four — `SEAM_VIOLATION_COUNT`, `ASSERTION_ROULETTE_COUNT`, `WEAK_ASSERTION_COUNT`. Task 7 reads them at P6.

These are **category** counters, orthogonal to the existing **severity** counters. A single finding line tagged `[major] [seam-violation]` increments both `MAJOR_COUNT` and `SEAM_VIOLATION_COUNT`. The existing four counters must not change.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/fixtures/code-review-categories.md`:

```markdown
# Review output — category tagging fixture

🟡 [seam-violation] test asserts `_rank_rows` internals, not the `roadmap-parser` seam
🟢 [assertion-roulette] `test_parse` bundles four unrelated assertions
🟢 [weak-assertion] `assert result is not None` cannot fail for any valid input
```

Known counts for this fixture: blocking 0, major 1, minor 2, praise 0; categories 1/1/1.

Append to `claude-skills/ship-workflow/tests/test_code-review-parse.bats`:

```bash
@test "code-review-parse: emits the three category counts" {
  CAT="$SHIP_SKILL_ROOT/tests/fixtures/code-review-categories.md"
  run "$SHIP_LIB/code-review-parse.sh" "$CAT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SEAM_VIOLATION_COUNT=1"* ]]
  [[ "$output" == *"ASSERTION_ROULETTE_COUNT=1"* ]]
  [[ "$output" == *"WEAK_ASSERTION_COUNT=1"* ]]
}

@test "code-review-parse: category tags still count toward severity" {
  CAT="$SHIP_SKILL_ROOT/tests/fixtures/code-review-categories.md"
  run "$SHIP_LIB/code-review-parse.sh" "$CAT"
  [[ "$output" == *"MAJOR_COUNT=1"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
}

@test "code-review-parse: category output is eval-safe" {
  CAT="$SHIP_SKILL_ROOT/tests/fixtures/code-review-categories.md"
  run bash -c "eval \"\$('$SHIP_LIB/code-review-parse.sh' '$CAT')\" && echo \"\$SEAM_VIOLATION_COUNT|\$ASSERTION_ROULETTE_COUNT|\$WEAK_ASSERTION_COUNT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"1|1|1"* ]]
}

@test "code-review-parse: the shared fixture is unperturbed by this change" {
  run "$SHIP_LIB/code-review-parse.sh" "$FIXTURE"
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
  [[ "$output" == *"MAJOR_COUNT=2"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
  [[ "$output" == *"PRAISE_COUNT=3"* ]]
  [[ "$output" == *"SEAM_VIOLATION_COUNT=0"* ]]
  [[ "$output" == *"ASSERTION_ROULETTE_COUNT=0"* ]]
  [[ "$output" == *"WEAK_ASSERTION_COUNT=0"* ]]
}
```

That last test is the point: it pins the pre-existing severity numbers so a future change
to the category feature cannot silently move them again.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats`
Expected: FAIL — the three `*_COUNT` variables are not emitted, so the three new category
tests fail. Every pre-existing test still passes; inside the new unperturbed-shared-fixture
guard, only its three `*_COUNT=0` assertions fail.

- [ ] **Step 3: Write minimal implementation**

In `claude-skills/ship-workflow/lib/code-review-parse.sh`, add after `count_praise()`:

```bash
# --- Category counters (orthogonal to severity) ------------------------------
# A finding may carry a category tag in addition to its severity tag.
# Category tags are matched anywhere on the line, since severity already
# occupies the line-start position.

count_seam_violation() {
  grep -ciE '\[seam-violation\]' "$FILE" || echo 0
}

count_assertion_roulette() {
  grep -ciE '\[assertion-roulette\]' "$FILE" || echo 0
}

count_weak_assertion() {
  grep -ciE '\[weak-assertion\]' "$FILE" || echo 0
}
```

Then, after the existing `PRAISE=$(count_praise)` line, add:

```bash
SEAM_VIOLATION=$(count_seam_violation)
ASSERTION_ROULETTE=$(count_assertion_roulette)
WEAK_ASSERTION=$(count_weak_assertion)
```

Extend the whitespace-stripping block with:

```bash
SEAM_VIOLATION=$(echo -n "$SEAM_VIOLATION" | tr -d '[:space:]')
ASSERTION_ROULETTE=$(echo -n "$ASSERTION_ROULETTE" | tr -d '[:space:]')
WEAK_ASSERTION=$(echo -n "$WEAK_ASSERTION" | tr -d '[:space:]')
```

And extend the output block with:

```bash
echo "SEAM_VIOLATION_COUNT=${SEAM_VIOLATION}"
echo "ASSERTION_ROULETTE_COUNT=${ASSERTION_ROULETTE}"
echo "WEAK_ASSERTION_COUNT=${WEAK_ASSERTION}"
```

Finally, update the header comment block to document the three category tags alongside the severity styles.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_code-review-parse.bats`
Expected: PASS — all pre-existing tests plus 4 new ones.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/code-review-parse.sh \
        claude-skills/ship-workflow/tests/test_code-review-parse.bats \
        claude-skills/ship-workflow/tests/fixtures/code-review-categories.md
git commit -m "feat: count seam-violation, assertion-roulette, weak-assertion categories"
```

---

### Task 5: templates and global config documentation

**Files:**
- Modify: `claude-skills/ship-workflow/templates/repo/SPEC.md`
- Modify: `claude-skills/ship-workflow/templates/repo/PLAN.md`
- Modify: `claude-skills/ship-workflow/examples/ship-workflow.example.yml`
- Modify: `claude-skills/ship-workflow/SKILL.md`
- Test: `claude-skills/ship-workflow/tests/test_templates-seams.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: the literal strings `## Seams`, `Seam:`, `Read .ship/tdd-rules.md`, `Read .ship/ponytail-rules.md` in the templates. Tasks 6 and 7 grep-assert against these exact strings.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_templates-seams.bats`:

```bash
#!/usr/bin/env bats
load helpers

@test "SPEC template declares the Seams section" {
  run grep -F '## Seams' "$SHIP_SKILL_ROOT/templates/repo/SPEC.md"
  [ "$status" -eq 0 ]
}

@test "SPEC template states the seam assertion rule" {
  run grep -F 'nothing inside it' "$SHIP_SKILL_ROOT/templates/repo/SPEC.md"
  [ "$status" -eq 0 ]
}

@test "PLAN template carries a Seam label line" {
  run grep -E '^Seam: ' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
}

@test "PLAN template points executors at both .ship rule files" {
  run grep -F 'Read .ship/tdd-rules.md' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
  run grep -F 'Read .ship/ponytail-rules.md' "$SHIP_SKILL_ROOT/templates/repo/PLAN.md"
  [ "$status" -eq 0 ]
}

@test "example global config documents the ponytail block" {
  run grep -F 'ponytail:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'pinned_version:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'ruleset_sha256:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
}

@test "example global config documents the test budget multipliers" {
  run grep -F 'test_budget:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
  run grep -F 'major_multiplier:' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -eq 0 ]
}

@test "example global config does NOT store a per-repo ship counter" {
  run grep -iE 'shipped_count|ship_count' "$SHIP_SKILL_ROOT/examples/ship-workflow.example.yml"
  [ "$status" -ne 0 ]
}

@test "SKILL.md global config section mentions ponytail" {
  run grep -F 'ponytail' "$SHIP_SKILL_ROOT/SKILL.md"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_templates-seams.bats`
Expected: FAIL — 7 of 8 tests fail (only the negative shipped-count test passes).

- [ ] **Step 3: Write minimal implementation**

In `templates/repo/SPEC.md`, insert immediately before the line
`(Use superpowers:brainstorming's spec format from here onward.)`:

```markdown
## Seams

Declare every boundary this work introduces or changes. Tests may assert a
seam's guaranteed behavior and nothing inside it.

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| <name> | `func(arg) -> Type` | <what callers may rely on> |

This section is REQUIRED. `/ship-next` Phase 4 refuses to proceed without it
in `--auto:yes` mode.
```

In `templates/repo/PLAN.md`, inside the per-task block, add after the task heading:

```markdown
Seam: <seam name from the spec's ## Seams table, or `none (refactor)`>

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.
```

In `examples/ship-workflow.example.yml`, append:

```yaml
# --- ponytail (global: one install, one pin) ---------------------------------
# /ship-next Phase 5 renders the installed ponytail ladder into
# .ship/ponytail-rules.md. On a hash mismatch it USES THE NEW VERSION and
# surfaces the drift; it never silently pins you to stale rules.
ponytail:
  mode: full                 # lite | full | ultra | off
  pinned_version: "4.8.4"
  ruleset_sha256: ""         # fill from: ponytail_ruleset_sha256

# --- test budget (global multipliers; baseline is computed per-repo) ---------
# Baseline is this repo's own test:src line ratio, measured live, so these
# multipliers are portable across repos with different testing cultures.
# Shadow mode is DERIVED from docs/learnings/_log.md — do not add a counter here.
test_budget:
  major_multiplier: 2
  blocking_multiplier: 4
```

In `SKILL.md`, under the `**Global** (~/.claude/ship-workflow.yml):` section, add one line each documenting the `ponytail:` and `test_budget:` blocks, and one sentence stating that shadow-mode ship count is derived from `docs/learnings/_log.md` and is deliberately not stored in config.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_templates-seams.bats`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/templates claude-skills/ship-workflow/examples \
        claude-skills/ship-workflow/SKILL.md claude-skills/ship-workflow/tests/test_templates-seams.bats
git commit -m "feat: add Seams section, .ship rule pointers, ponytail + budget config docs"
```

---

### Task 6: wire Phases 3, 4, 5 in `ship-next.md`

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 3 step 0, Phase 4, Phase 5)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-context-wiring.bats`

**Assertion note (applies to Tasks 6-10):** these tests grep a markdown command file.
Backticks inside a bash double-quoted string in that file MUST be escaped (`\``) or the
shell would treat them as command substitution, so a search string containing an
unescaped backtick will not match. Assert on the shortest stable substring that carries
the meaning and contains no backtick. Never edit the implementation text to satisfy a
brittle assertion.

**Interfaces:**
- Consumes: `context_md_path` (Task 1), `ponytail_render_rules` (Task 3), the `## Seams` / `Read .ship/...` strings (Task 5).
- Produces: the shell snippets Tasks 7 and 9 extend; exports nothing.

- [x] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-next-context-wiring.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "P3 sources context-md.sh and announces CONTEXT.md" {
  run grep -F 'lib/context-md.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CONTEXT.md present — Read it before brainstorm dialog.' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P3 tells brainstorming that ## Seams is a required section" {
  run grep -F 'required output section: `## Seams`' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P4 refuses in auto mode when the spec has no ## Seams" {
  run grep -F 'refused — spec has no' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P4 only warns about missing Seams in interactive mode" {
  run grep -F 'WARN: spec has no' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 renders both rule files into .ship/" {
  run grep -F '.ship/tdd-rules.md' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'ponytail_render_rules .ship/ponytail-rules.md' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 detects ponytail ruleset drift against the global pin" {
  run grep -F 'PONYTAIL_DRIFT=1' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F '[A]ccept and re-pin' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 drift never blocks the ship" {
  run grep -F 'Drift NEVER blocks' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P5 tdd-rules carries the three governing rules" {
  run grep -F 'Tests attach only to the seams listed below.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'Behavior unchanged => tests unchanged.' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'One test, one behavior.' "$CMD"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-context-wiring.bats`
Expected: FAIL — 8 tests fail; none of these strings exist yet.

- [x] **Step 3: Write minimal implementation**

In `commands/ship-next.md`, **Phase 3 step 0**, after the existing UA pre-context block, add:

````markdown
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
````

In **Phase 3 step 2**, extend the brainstorming invocation context with:

```markdown
   Also pass a **required output section: `## Seams`** — a three-column table
   (Seam | Interface | Guaranteed behavior) declaring every boundary this work
   introduces or changes. Tests may assert a seam's behavior and nothing inside
   it. This instruction travels in the invocation context; no `superpowers`
   file is modified.
```

At the top of **Phase 4**, before step 1, add:

````markdown
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
````

In **Phase 5**, before step 3 (invoke the chosen sub-skill), add:

````markdown
2.5. **Render executor rule files.**

   ```bash
   mkdir -p .ship

   # TDD discipline, rendered from the spec's ## Seams table
   {
     echo "# TDD rules for ${ID}"
     echo
     echo "1. Tests attach only to the seams listed below."
     echo "2. \`Seam: none\` tasks add no tests. Behavior unchanged => tests unchanged."
     echo "3. One test, one behavior. Do not pack unrelated assertions into a single test."
     echo
     echo "## Declared seams"
     sed -n '/^## Seams/,/^## /p' "docs/specs/${ID}-${SLUG}.md" | sed '$d'
   } > .ship/tdd-rules.md

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
````

- [x] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-context-wiring.bats`
Expected: PASS — 8 tests.

- [x] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-context-wiring.bats
git commit -m "feat: wire CONTEXT.md, seam gate, and executor rule files into P3-P5"
```

---

### Task 7: Phase 6 gates and the Phase 7 ratio line

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 6 step 0.5, Phase 6 step 2, Phase 7 step 4)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-test-gates.bats`

**Interfaces:**
- Consumes: `tb_baseline_ratio`, `tb_ship_ratio`, `tb_verdict`, `tb_shadow_active` (Task 2); `SEAM_VIOLATION_COUNT` and siblings (Task 4).
- Produces: shell variables `TEST_BUDGET_VERDICT`, `SHIP_RATIO_BP`, `BASELINE_RATIO_BP` for Task 9's P8.5 trigger and Task 10's P9 summary.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-next-test-gates.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "P6 flags refactor tasks that added test lines as blocking" {
  run grep -F 'Seam: none' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'refactor task added test lines' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 sources test-budget.sh and exports the verdict" {
  run grep -F 'lib/test-budget.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'TEST_BUDGET_VERDICT=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 suppresses the budget finding while shadow mode is active" {
  run grep -F 'tb_shadow_active' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'shadow mode — reporting only' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 asks the reviewer for the three category tags" {
  run grep -F '.ship/review-extra-checks.md' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F '[seam-violation]' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P6 derives the raw added-line counts for the P7 message" {
  run grep -F 'tb_ship_lines "$ORIG_BRANCH" HEAD' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'TEST_LINES_ADDED=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P7 commit message carries the test ratio line" {
  run grep -F 'Tests: +' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'vs baseline' "$CMD"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-test-gates.bats`
Expected: FAIL — 6 tests fail.

- [ ] **Step 3: Write minimal implementation**

In `commands/ship-next.md`, add **Phase 6 step 0.5** after the existing UA blast-radius step:

````markdown
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

Keep your usual severity tag as well; these categories are orthogonal to severity.
CHECKS
   ```

   `MECH_BLOCKERS > 0` feeds the same fix-plan loop as LLM blockers in step 2.
````

In **Phase 6 step 2**, change the review invocation note to instruct
code-review-skill to Read `.ship/review-extra-checks.md` alongside
`.ship/ua-diff-report.md`, and add `MECH_BLOCKERS` into the loop's blocking total:

```bash
     BLOCKING_COUNT=$((BLOCKING_COUNT + MECH_BLOCKERS))
```

In **Phase 7 step 4**, add one line to the commit-message heredoc immediately
after the `Code review (...)` block:

```
   Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-test-gates.bats`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-test-gates.bats
git commit -m "feat: add P6 mechanical test gates and P7 ratio line"
```

---

### Task 8: Phase 8 CONTEXT.md write and cap check

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-compound.md`
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 8 note)
- Test: `claude-skills/ship-workflow/tests/test_ship-compound-context.bats`

**Invocation note:** any `grep` whose pattern begins with `-` needs `--` before the
pattern, or the shell tool parses it as an option and exits 2 (usage error) rather than
1 (no match). `- **<term>** — <definition>` is such a pattern.

**Interfaces:**
- Consumes: `context_md_over_cap`, `context_md_orphan_terms`, `context_md_line_count`, `context_md_entry_count` (Task 1); `spec-mirror.sh` (existing).
- Produces: `CONTEXT_MD_STATUS` for Task 10's P9 summary.

- [x] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-compound-context.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-compound.md"
}

@test "ship-compound sources context-md.sh" {
  run grep -F 'lib/context-md.sh' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound documents the CONTEXT.md entry format" {
  run grep -F -- '- **<term>** — <definition>' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound mirrors CONTEXT.md to the vault" {
  run grep -F 'spec-mirror.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CONTEXT.md' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound prunes to the 150-line target in interactive mode" {
  run grep -F 'prune to <= 150 lines' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound does NOT prune in auto mode" {
  run grep -F 'pruning is skipped in --auto:yes' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound exports CONTEXT_MD_STATUS for the P9 summary" {
  run grep -F 'CONTEXT_MD_STATUS=' "$CMD"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-context.bats`
Expected: FAIL — 6 tests fail.

- [x] **Step 3: Write minimal implementation**

Add a new step to `commands/ship-compound.md`, after the learning is written:

````markdown
### Step 6 — Update CONTEXT.md (project vocabulary)

```bash
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/context-md.sh
```

1. **Extract terms.** From this ship's diff and `docs/specs/${ID}-${SLUG}.md`,
   identify domain terms this work **introduced or clarified**. A term qualifies
   only if it is project-specific and a newcomer could not infer it from the code
   alone. Class names, file names, and generic programming vocabulary do not qualify.

2. **Write entries.** Append to (or refine in) `<repo>/CONTEXT.md`, one bullet per
   entry, in exactly this format:

   ```
   - **<term>** — <definition>
   ```

   Continuation lines are indented and are not separate entries.

3. **Cap check.**

   ```bash
   if context_md_over_cap; then
     if [ "$AUTO" = "1" ]; then
       # Deletion is destructive and has no machine-checkable invariant here,
       # so pruning is skipped in --auto:yes. Surface it instead.
       echo "WARN: CONTEXT.md over cap ($(context_md_line_count) lines / $(context_md_entry_count) entries)" >&2
       CONTEXT_MD_STATUS="over cap — prune pending"
     else
       CONTEXT_MD_STATUS="pruned"
     fi
   else
     CONTEXT_MD_STATUS="$(context_md_entry_count) entries / $(context_md_line_count) lines"
   fi
   ```

   In interactive mode when over cap, **prune to <= 150 lines** in this order:
   merge semantically duplicate entries; delete terms reported by
   `context_md_orphan_terms`; if still over, delete the entries least recently
   cited by any file under `docs/specs/` or `docs/plans/`.

   **There is no archive section.** `CONTEXT.md` is read in full every Phase 3, so
   an archive heading would keep paying the token cost. Deleted terms are recovered
   with `git log -p --follow CONTEXT.md`.

4. **Commit and mirror.**

   ```bash
   # Guard: a ship that surfaced no qualifying terms leaves no CONTEXT.md. Without
   # this, `git add` exits 128 (pathspec did not match) and spec-mirror.sh exits 2,
   # breaking the purely-additive property every integration in this design holds to.
   if [ -f CONTEXT.md ]; then
     git add CONTEXT.md && git commit -m "context: update vocabulary from ${ID}"
     VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
     ~/.claude/skills/ship-workflow/lib/spec-mirror.sh CONTEXT.md "$VAULT_DIR/CONTEXT.md"
   else
     CONTEXT_MD_STATUS="absent — no qualifying terms this ship"
   fi
   ```
````

In `commands/ship-next.md` **Phase 8**, add one sentence noting that
`/ship-compound` now also updates `CONTEXT.md` and exports `CONTEXT_MD_STATUS`.

- [x] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-context.bats`
Expected: PASS — 6 tests.

- [x] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-compound.md \
        claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-compound-context.bats
git commit -m "feat: write and cap CONTEXT.md in ship-compound"
```

---

### Task 9: Phase 8.5 test pruning

> **SUPERSEDED 2026-09-29 — do not implement the steps below as written.**
> This task specified a scoped prune behind a coverage gate. Six acceptance-review
> rounds found fourteen defects in that gate, and the last three showed why it cannot
> work: coverage records which lines executed, not whether an assertion observed them.
> Phase 8.5 shipped as **report-only** — it lists candidates in
> `.ship/prune-candidates.md` and deletes nothing. See spec §7.1 and the Execution log
> entry for 2026-09-29. The steps below are kept as the record of what was attempted.


**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (new Phase 8.5)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-prune.bats`

**Interfaces:**
- Consumes: `TEST_BUDGET_VERDICT` (Task 7).
- Produces: `PRUNE_STATUS` for Task 10's P9 summary.

- [x] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-next-prune.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "Phase 8.5 exists and sits between Phase 8 and Phase 9" {
  run grep -n '^## Phase 8.5 — Test pruning' "$CMD"
  [ "$status" -eq 0 ]
  p85=$(grep -n '^## Phase 8.5' "$CMD" | cut -d: -f1)
  p8=$(grep -n '^## Phase 8 ' "$CMD" | cut -d: -f1)
  p9=$(grep -n '^## Phase 9' "$CMD" | cut -d: -f1)
  [ "$p8" -lt "$p85" ]
  [ "$p85" -lt "$p9" ]
}

@test "Phase 8.5 triggers only on the major verdict" {
  run grep -F 'TEST_BUDGET_VERDICT" != "major"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 scopes pruning to modules this ship touched" {
  run grep -F 'git diff --name-only "${ORIG_BRANCH}...${BRANCH}"' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 records coverage before and after" {
  run grep -F 'COV_BEFORE' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'COV_AFTER' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 rolls back when coverage drops or tests fail" {
  run grep -F 'git checkout -- tests/' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'coverage dropped' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 commits separately from the R-NNN squash" {
  run grep -F 'test: prune redundant tests' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.5 runs in auto mode" {
  run grep -F 'runs in --auto:yes because its invariants are machine-checked' "$CMD"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats`
Expected: FAIL — 7 tests fail; Phase 8.5 does not exist.

- [x] **Step 3: Write minimal implementation**

Insert a new section in `commands/ship-next.md` between Phase 8 and Phase 9:

````markdown
## Phase 8.5 — Test pruning

Unlike `CONTEXT.md` pruning, this **runs in `--auto:yes` because its invariants are machine-checked**: coverage must not drop and tests must stay green, and a failure rolls back for free since nothing is committed yet.

1. **Trigger.** Reuses the number Phase 6 already computed; normal ships skip.

   ```bash
   if [ "$TEST_BUDGET_VERDICT" != "major" ]; then
     PRUNE_STATUS="skipped (verdict=${TEST_BUDGET_VERDICT})"
   else
   ```

2. **Scope.** Only tests covering modules this ship touched. Bounded blast radius,
   and the judgment is at its most accurate while the context is hot.

   ```bash
     TOUCHED=$(git diff --name-only "${ORIG_BRANCH}...${BRANCH}" | grep -v '^tests/' || true)
     MODULES=$(echo "$TOUCHED" | sed 's|/[^/]*$||' | sort -u)
     TEST_TARGETS=$(for m in $MODULES; do ls tests/${m##*/}/*.py 2>/dev/null; done | sort -u)
     # NO fallback to tests/. Spec 7.3 bounds the blast radius to modules this ship
     # touched; widening to the whole suite would turn this into an unscoped LLM prune
     # pass over unrelated tests, and that bound is what justifies running in auto mode.
     if [ -z "$TEST_TARGETS" ]; then
       PRUNE_STATUS="skipped (no scoped test targets for ${MODULES})"
     else
   ```

3. **Record the baseline.**

   ```bash
     # Pin the measurement scope. Without --source, coverage reports only files that
     # were IMPORTED, so deleting a module's only test drops that module out of the
     # report entirely and the remaining average can RISE. Measured on exactly that
     # case: 100% reported, 50% actual. With --source the module stays in scope and
     # its coverage correctly falls, which is what the gate needs to see.
     COV_SOURCE=$(echo "$MODULES" | tr '\n' ',' | sed 's/,$//')
     mkdir -p .ship

     # Check pytest's exit code on its own. Chaining `run ...; report ...` with `;`
     # discarded it, so a RED baseline still produced a number and pruning away the
     # failing test then passed the gate.
     if ! coverage run --source="$COV_SOURCE" -m pytest $TEST_TARGETS -q >/dev/null 2>&1; then
       PRUNE_STATUS="skipped (baseline tests not green)"
     else
     # Delete first, then CHECK THE EXIT CODE. `|| true` swallowed an export failure,
     # and a stale cov-after.json left over from an earlier run then satisfied the
     # -s test and got compared: measured coverage fell 4 -> 3 and the gate committed.
     # Freshness is part of the evidence, not a detail.
     rm -f .ship/cov-before.json
     if ! coverage json -q -o .ship/cov-before.json 2>/dev/null || [ ! -s .ship/cov-before.json ]; then
       PRUNE_STATUS="skipped (coverage export failed)"
     else
   ```

4. **Prune.** Edit only files under `$TEST_TARGETS`, in this order:
   1. duplicate coverage — two tests asserting the same behavior, keep one
   2. seam violations — tests asserting inside a seam, lift to seam level or delete
   3. never-failing tests — assertions too weak to discriminate, strengthen or delete

5. **Verify both invariants, or roll back.**

   ```bash
       # Same --source as the baseline, or the two numbers are not comparable.
       if ! coverage run --source="$COV_SOURCE" -m pytest $TEST_TARGETS -q >/dev/null 2>&1; then
         git checkout -- tests/
         PRUNE_STATUS="rolled back (tests failed)"
       else
         rm -f .ship/cov-after.json
         # The gate compares executed-line SETS, not counts and not percentages.
         # A percentage hid a 903 -> 902 loss behind a rounded `90`. Exact counts
         # then hid [1,3,4,5] -> [1,3,4,6], where the count stays 4 while line 5
         # loses its only test: counts preserve cardinality, not membership.
         # Exit 2 means "cannot decide" and is treated as a regression.
         if ! coverage json -q -o .ship/cov-after.json 2>/dev/null || [ ! -s .ship/cov-after.json ]; then
           git checkout -- tests/
           PRUNE_STATUS="rolled back (coverage export failed after pruning)"
         elif ! python3 ~/.claude/skills/ship-workflow/lib/coverage-diff.py \
              .ship/cov-before.json .ship/cov-after.json; then
           git checkout -- tests/
           PRUNE_STATUS="rolled back (coverage regression)"
         else
           PRUNED_LINES=$(git diff --numstat -- tests/ | awk '{s+=$2} END {print s+0}')
           git add tests/
           git commit -m "test: prune redundant tests in ${MODULES}"
           PRUNE_STATUS="pruned -${PRUNED_LINES} lines, per-file coverage verified"
         fi
       fi
     fi
     fi
     fi
   fi
   ```

   This is a **separate commit** from the Phase 7 squash on purpose: folding it in
   would pollute the R-NNN diff and defocus review.

   **Known limit:** per-file coverage parity does not prove assertion *strength* was
   preserved — a test can be weakened without touching which lines execute. This bounds
   the damage; it does not eliminate it.

   **Auto-mode log:**
   ```bash
   [ "$AUTO" = "1" ] && ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P8.5" "$PRUNE_STATUS"
   ```
````

- [x] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats`
Expected: PASS — 7 tests.

- [x] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-prune.bats
git commit -m "feat: add Phase 8.5 coverage-gated test pruning"
```

---

### Task 10: Phase 8.7 UA rebuild and the Phase 9 summary

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (new Phase 8.7, Phase 9 steps 3-4)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-ua-rebuild.bats`

**Interfaces:**
- Consumes: `ua_check_installed`, `ua_check_drift` (existing); `CONTEXT_MD_STATUS` (Task 8), `PRUNE_STATUS` (Task 9), `SHIP_RATIO_BP` / `BASELINE_RATIO_BP` (Task 7), `ponytail_version` / `ponytail_ruleset_sha256` (Task 3).
- Produces: nothing downstream.

- [x] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-next-ua-rebuild.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "Phase 8.7 sits between Phase 8.5 and Phase 9" {
  p85=$(grep -n '^## Phase 8.5' "$CMD" | cut -d: -f1)
  p87=$(grep -n '^## Phase 8.7' "$CMD" | cut -d: -f1)
  p9=$(grep -n '^## Phase 9' "$CMD" | cut -d: -f1)
  [ "$p85" -lt "$p87" ]
  [ "$p87" -lt "$p9" ]
}

@test "Phase 8.7 reuses the existing 50-file drift threshold" {
  run grep -F 'DRIFT_COUNT" -gt 50' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.7 runs /understand only above the threshold" {
  run grep -F 'Invoke `/understand`' "$CMD"
  [ "$status" -eq 0 ]
}

@test "Phase 8.7 is a silent no-op when UA is absent" {
  run grep -F 'ua_check_installed' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P9 summary reports CONTEXT, test budget, prune, ponytail drift and UA" {
  run grep -F 'CONTEXT.md: ${CONTEXT_MD_STATUS}' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'Test pruning: ${PRUNE_STATUS}' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'ruleset changed, this ship used the new version' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'UA KG rebuilt' "$CMD"
  [ "$status" -eq 0 ]
}

@test "P9 log row carries the ratio field that drives shadow mode" {
  run grep -F 'ratio ${SHIP_RATIO_BP}bp' "$CMD"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-ua-rebuild.bats`
Expected: FAIL — 6 tests fail.

- [x] **Step 3: Write minimal implementation**

Insert between Phase 8.5 and Phase 9 in `commands/ship-next.md`:

````markdown
## Phase 8.7 — UA knowledge graph rebuild

Runs after Phase 8.5 so the rebuilt graph reflects the final tree, pruning commit
included. Ordering is load-bearing.

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
````

In **Phase 9 step 3**, change the log append so the row carries the ratio field
that `tb_shadow_active` counts:

```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp) | n |" >> docs/learnings/_log.md
```

In **Phase 9 step 4**, extend the `SUMMARY` heredoc with:

```
   • CONTEXT.md: ${CONTEXT_MD_STATUS}
   • Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
   • Test pruning: ${PRUNE_STATUS}
   • UA: ${UA_STATUS}
```

and, when the ponytail hash differed from the pin at Phase 5, one more line:

```
   ⚠ ponytail ${PONYTAIL_PINNED} -> ${PONYTAIL_CURRENT}, ruleset changed, this ship used the new version
```

Prefix the `UA: ` line with `🔄 UA KG rebuilt` when `UA_STATUS` starts with `rebuilt`.

- [x] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-ua-rebuild.bats`
Expected: PASS — 6 tests.

- [x] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-ua-rebuild.bats
git commit -m "feat: add Phase 8.7 UA rebuild and extend the P9 summary"
```

---

### Task 11: absent-dependency regression

**Files:**
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats`

**Interfaces:**
- Consumes: all three new libs.
- Produces: nothing.

This is the single most important test in the plan: all three integrations must be purely additive, so a repo with no ponytail, no UA, and no `CONTEXT.md` must behave exactly as it did before.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats`:

```bash
@test "no ponytail → render is a silent no-op and writes no file" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p .ship
  source "$SHIP_LIB/ponytail-integration.sh"
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "no CONTEXT.md → path is empty and counts are zero" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/context-md.sh"
  run context_md_path
  [ -z "$output" ]
  run context_md_entry_count
  [ "$output" = "0" ]
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "empty repo → test budget is zero and shadow mode is active" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/test-budget.sh"
  run tb_baseline_ratio
  [ "$output" = "0" ]
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "all three libs are sourceable together without collision" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run bash -c "source '$SHIP_LIB/ua-integration.sh'; source '$SHIP_LIB/context-md.sh'; source '$SHIP_LIB/test-budget.sh'; source '$SHIP_LIB/ponytail-integration.sh'; echo ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "ship-next still declares every phase in order" {
  for p in "## Phase 1 " "## Phase 2 " "## Phase 3 " "## Phase 4 " "## Phase 5 " "## Phase 6 " "## Phase 7 " "## Phase 8 " "## Phase 8.5" "## Phase 8.7" "## Phase 9"; do
    run grep -F "$p" "$SHIP_SKILL_ROOT/commands/ship-next.md"
    [ "$status" -eq 0 ]
  done
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-no-ua.bats`
Expected: FAIL only if an earlier task regressed. If Tasks 1-10 are correct these pass immediately, which is the point — this task is the proof, not new behavior.

- [ ] **Step 3: Fix any regression surfaced**

If a test fails, the defect is in the task that owns that lib or phase. Fix it there, not by weakening this test.

- [ ] **Step 4: Run the full suite**

Run: `cd claude-skills/ship-workflow && bats tests/`
Expected: PASS — every file, including all pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats
git commit -m "test: assert all three integrations are purely additive"
```

### 2026-09-28 — Task 4 amended (second attempt), resuming

Two BLOCKED runs, both correct stops by codex.

Run 1 found a real plan defect: Task 4 appended findings to
`tests/fixtures/code-review-output.md`, the shared contract for pre-existing severity
assertions it does not own, moving MAJOR_COUNT 2->3 and MINOR_COUNT 2->4. Codex proposed
updating those assertions; rejected, because that accepts the contamination. Task 4 now
creates its own `code-review-categories.md`, leaves the shared fixture untouched, and adds
a test pinning it at 2|2|2|3 with zero category counts. Task 4 was violating the same
purely-additive property Task 11 enforces.

Run 2 was blocked by a defect in the amendment itself, not the plan's content: an
index-slice edit overshot the Task 4 boundary and deleted Task 4 Steps 2-5 and all of
Task 5, and it was committed without verification. Restored from 63ce51e and re-applied
by splitting on task headings so the edit cannot cross a task boundary, with assertions
on step count and heading count before writing.

Durable learning: when patching a plan file programmatically, split on structural
boundaries and assert the structure survived. A textual index slice on a 1900-line
document has no boundary and fails silently.

## Execution log

### 2026-09-29 — Task 11 acceptance BLOCKED at 393e80e

- Applied the invoked ship skill and executing-plans verification/review workflow
  within the repository-only acceptance scope. Release, global bookkeeping, and
  live HOME/.claude operations were excluded. No source fixes or committed test
  changes were made; the existing Task 11 tests were left intact.
- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **229/229 passed, exit 0**. Initial HEAD was `393e80e`; the only initial working
  tree entry was the pre-existing untracked `.claude-uploads/`.

**BLOCKER: destructive statements still bypass the structural guard.**

Used a scratch copy of `commands/ship-next.md` and the real
`tests/test_ship-next-prune.bats`. Redirected only the copied test's `load helpers`
path to the original helpers and its `CMD` assignment to the copied command file.
Inserted each statement separately immediately after `mkdir -p .ship` inside
Phase 8.5's existing Bash fence. Ran:

```bash
bats --filter 'Phase 8.5 deletes nothing' \
  claude-skills/ship-workflow/tests/.tmp/acceptance-393e80e/guard.bats
```

| Injected statement | Guard exit | Actual extracted phase effect |
|---|---:|---|
| none (control) | 0 | bytes, index and HEAD unchanged |
| `rm -f tests/src/test_a.py` | 1 | rejected control; not executed |
| `git add -- tests/src/test_a.py` | 1 | rejected control; not executed |
| `: > tests/src/test_a.py` | 1 | rejected control; not executed |
| `git -C . add -- tests/src/test_a.py` | **0** | stages previously unstaged sentinel |
| `/bin/rm -f tests/src/test_a.py` | **0** | deletes the test file |
| `: > .ship/../tests/src/test_a.py` | **0** | truncates the test file to zero bytes |
| `sed -e 's/assert/pass #/' -i '' tests/src/test_a.py` | **0** | edits the test's assertion |

Restoring the original command copy returned guard exit 0. An additional awk
write injection was rejected, exit 1.

Executed all four accepted destructive mutants through the **actual extracted
Phase 8.5 Bash**, using `/bin/bash` 3.2.57 and real Git in separate isolated
repositories under `tests/.tmp/acceptance-393e80e/`. Each fixture had two commits
changing `src/a.py`, a mapped `tests/src/test_a.py`, distinct staged/unstaged
sentinels, an isolated HOME, and a one-candidate report. Set
`TEST_BUDGET_VERDICT=major`, `ORIG_BRANCH=<first commit>`, and
`BRANCH=<second commit>`. Every mutant exited 0 and reported
`1 prune candidate(s) ... (nothing deleted)` despite its measured side effect.
HEAD stayed unchanged; the Git-option mutant changed the index tree, and the
other three changed or removed the test bytes.

The reasons are concrete: `test_ship-next-prune.bats:44` only recognizes a Git
subcommand immediately after `git`, missing Git global options; lines 47–48
still match a verb denylist, missing absolute executable paths and reordered
sed options; line 59 accepts the lexical `.ship/*` prefix without resolving
parent traversal. These checks do not enforce the stated shell behavior.
This is a regression-guard defect, **not a claim that the original phase
currently contains a destructive operation**, and does not reopen report-only
as the settled design.

**BLOCKER: current normative spec text still contradicts report-only operation.**

The command, spec §7, spec §10 phase map, and plan Task 9 SUPERSEDED banner agree
that Phase 8.5 proposes candidates and deletes/commits nothing. The updated P8.7
text also agrees. However, the spec still contains these unmarked current claims:

- Line 23: “a scoped prune at a new P8.5”.
- §3 P5, lines 106–108: guard deletion with coverage and green-test invariants
  rather than refusing unattended operation.
- §12.4, lines 508–509: the “P8.5 coverage gate” bounds the damage.
- §13, lines 524–525: simulate a prune that drops coverage and assert rollback
  restores `tests/`.

Reproduce with:

```bash
rg -n 'scoped prune at|Guard deletion|P8.5 coverage gate|P8.5 rollback' \
  docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md
```

These are outside the explicitly superseded plan history. The shipped-document
check only searches three phrases and therefore stays green with the contradictory
residual-risk and test-strategy instructions still present.

**Remaining finishing defect: empty reports emit `00`, not `0`.**

Executed the original extracted phase against three report contents. A single
`CANDIDATE: ` line correctly reports 1. A header-only `# Candidate report` file
and a zero-byte file both report **`00 prune candidate(s)`**, exit 0.
At `commands/ship-next.md:782`, a no-match `grep -c` prints `0` and exits 1;
`|| echo 0` prints another `0`, and line 783 joins them. The prefix repair fixes
header collisions for nonempty candidate lists but leaves the previously reported
zero-result defect. This is a formatting defect, not an assertion that the
numeric candidate total is nonzero. The guard checks source text rather than
executing the empty/header-only cases.

**Repairs and absent integrations that hold.**

- Executed the actual P9 log block with `PRUNE_STATUS="7 prune candidate(s)"`
  and a no-op Git function. It exits 0 and now appends `prune: 7 prune candidate(s)`
  to the durable row. The missing-log-status finding is fixed.
- An independent in-host reviewer executed eight actual extracted optional
  blocks individually and sequentially: P1.5 drift, P3 UA and CONTEXT, P5 ponytail
  render/drift, P6 UA, ship-compound UA and CONTEXT cap/commit, and P8.7 rebuild.
  Tested AUTO=0 and AUTO=1, with UA absent and with its plugin present but no KG,
  always without ponytail or CONTEXT. Installed-library paths were redirected
  locally and HOME was isolated under tests/.tmp/. File hashes, staged index tree,
  HEAD and status remained unchanged, including staged/unstaged sentinels.
  Optional outputs stayed absent, stdout/stderr stayed empty, and binding/mirror
  sentinels were not called. Public absent-helper checks also passed.
- Every extracted block exits 0 except the already documented P1.5 trailing
  false string test, which exits 1 silently. The sequential cycle exits 0 without
  unspecified errexit. No new absent-integration blocker was found. This checks
  actual optional-hook blocks, not an entire external agent-driven ship conversation.

**Verdict: BLOCKED. Task 11 remains incomplete; no acceptance commit created.**

Required repair: make the no-destruction guard reject the reproduced mutations,
remove or explicitly supersede the remaining normative coverage-gate claims, and
normalize zero candidate output. Preserve report-only operation. No implementation
fix or test weakening was attempted in this acceptance review.

Scratch fixtures under `tests/.tmp/acceptance-393e80e/` and
`tests/.tmp/acceptance-393e80e-absent/` were removed after recording the evidence.
Only this Execution log was edited. No push, branch switch, amend, hook bypass,
live HOME/.claude modification, or `.claude-uploads/` change occurred.

Durable learning: an allowed subcommand check is still lexical if it cannot parse
options and executable paths. A permitted path prefix is not directory containment.
Prove the property using alternate valid shell forms and measured file/index effects;
exercise zero-output paths rather than asserting that the counting expression exists.


### 2026-09-29 — Final Task 11 acceptance BLOCKED at 9f8c0bf

- Applied the explicitly invoked ship skill and executing-plans review/verification
  workflow within the user's repository-only acceptance scope. No release, global
  bookkeeping, installation, or live HOME/.claude actions were performed. A fresh
  in-host reviewer independently exercised the absent integrations.
- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **226/226 passed, exit 0**. HEAD was `9f8c0bf`; initial working tree contained only
  the pre-existing untracked `.claude-uploads/`. The Task 11 tests are already in HEAD
  and were not rewritten. No implementation or committed tests were changed.

**Acceptance failure 1: the documents still prescribe the withdrawn gate.**

Spec §7 and the Task 9 SUPERSEDED banner correctly describe report-only operation,
but other current, unmarked normative text disagrees:

- Spec introduction, line 23: “a scoped prune at a new P8.5”.
- Spec §3 P5, lines 106–108: guard deletion with coverage/green-test invariants
  rather than refusing unattended operation.
- Spec §9.4, lines 430–431: “The pruning commit has already landed”.
- Spec §10, line 450: “test pruning ... scoped, coverage-gated, own commit, runs in auto”.
- Spec §12.4, lines 507–508: the P8.5 coverage gate “bounds the damage”.
- Spec §13, lines 523–524: simulate a coverage drop and assert rollback restores tests.
- `commands/ship-next.md:791–792`: the rebuilt graph includes the “pruning commit”.

Reproduce the inconsistency with:

```bash
rg -n 'coverage-gated|pruning commit|P8.5 coverage gate|P8.5 rollback|Guard deletion' \
  docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md \
  claude-skills/ship-workflow/commands/ship-next.md
```

These are not the explicitly superseded Task 9 history. The authoritative current
phase map and acceptance strategy still instruct a future executor to use the
operation §7 withdrew. Acceptance item 4 therefore fails.

**Acceptance failure 2: injected destructive commands still pass the guard.**

Used a scratch copy of the real command file and the real
`Phase 8.5 deletes nothing — no test edits, no rollback, no commit` Bats test.
Only the test's CMD path was redirected to the copy. For each trial, inserted one
line after Phase 8.5's `mkdir -p .ship` inside its existing Bash fence:

| Injected line | Existing guard exit |
|---|---:|
| none (control) | 0 |
| `git checkout -- tests/` | 1 |
| `git add tests/` | 1 |
| `rm -f tests/src/test_a.py` | 0 |
| `: > tests/src/test_a.py` | 0 |
| `git add -- tests/src/test_a.py` | 0 |
| `git commit -m "remove tests"` | 0 |

Reproduction command after setting the scratch copy's CMD:
`bats --filter 'Phase 8.5 deletes nothing' <scratch>/guard.bats`.
The guard catches its five exact strings, not the claimed no-edit/no-stage/no-delete
property. The alternate staging syntax alone bypasses it.

Executed the rm, truncation, and alternate-add mutants through the extracted actual
Phase 8.5 Bash in an isolated Git repo. The fixture had `src/a.py` changed between
two commits, a mapped `tests/src/test_a.py`, and distinct staged/unstaged sentinel
comments in that test. With `TEST_BUDGET_VERDICT=major`, rm removed the test,
truncation emptied it, and alternate-add changed the index. Each phase exited 0
and still reported “(nothing deleted)”. Original test bytes and index were restored
between trials, only inside the scratch fixture.

This is a defect in the claimed regression guard, **not evidence that the unmodified
phase currently contains those commands**. The original extracted Bash preserved
all test bytes, the exact staged diff, and HEAD for pass, blocking, major, and
unresolved-target paths. No present test-edit/stage/delete operation was found in
that original Bash. The report-only scope decision remains sound.

**Acceptance failure 3: candidate counts are wrong for ordinary Markdown tables.**

`commands/ship-next.md:775–777` counts every line beginning `| `, including a header.
For a valid report containing:

```markdown
| file | test | category | why |
|---|---|---|---|
| tests/src/test_a.py | test_a | duplicate coverage | same behavior |
```

the actual extracted phase reports **2 prune candidate(s)**, though there is one.
A header-only table reports **1** with zero candidates. A zero-byte report reports
**00**: `grep -c` prints 0 and exits 1, `echo 0` prints another 0, and whitespace
removal concatenates them. These were executed with macOS `/bin/bash` 3.2.57, the
real grep, and the actual phase blocks; no counter reimplementation was used.

**Acceptance failure 4: the promised durable report summary is missing.**

Spec §7.2 and `commands/ship-next.md:786–787` promise the count in both the P9 summary
and `_log.md` row. Execute the real P9 log block (`:845–848`) with
`PRUNE_STATUS="7 prune candidate(s)"`, `ID=R-TEST`, `MAJOR_COUNT=0`,
`SHIP_RATIO_BP=2500`, `BASELINE_RATIO_BP=1000`, and a recording/no-op Git function
so staging/committing are not performed. The appended row is:

```text
| <date/time> | ship-next | R-TEST | shipped (review: blocking=0, major=0, ratio 2500bp vs baseline 1000bp) | n |
```

It contains neither the count nor PRUNE_STATUS. The automatic notification does
include PRUNE_STATUS; the durable row does not. This contradicts the new §7 contract,
independently of the stale deletion text above.

**Absent-integration checks and review limits.**

The independent reviewer ran actual extracted P1.5, P3 UA/CONTEXT, P4, full P5,
P6 UA/budget, ship-compound UA/context cap/commit/mirror, P8.7, and P9 summary blocks
sequentially in isolated Git fixtures for AUTO=0 and AUTO=1. Installed-library
paths were redirected to this repository. Controls omitted only the optional
integration hooks, retaining the shared seam/TDD/budget behavior. Candidate and
control file hashes/status matched; HEAD and index tree were unchanged; absent
CONTEXT, UA and ponytail artifacts stayed absent; isolated HOME remained empty;
binding/mirror sentinels were never called. Shared TDD/review-extra-checks files
were generated equally in both runs. All blocks exited 0 except the pre-existing
P1.5 trailing false string test (exit 1, silent); without unspecified errexit the
sequence completed with exit 0. The AUTO=1 bell was common to both runs.

This establishes additivity of the executed optional-hook cycle. It does **not**
claim a complete external agent-driven brainstorm/review/worktree/merge conversation
was executed. The existing eight Task 11 tests also remain helper/text checks,
not that complete end-to-end cycle. No new absent-integration regression was found.

**Verdict: BLOCKED. Task 11 remains uncommitted and incomplete.**

Repair the stale normative documentation, count only candidate data rows and wire
the count into the durable P9 log. Strengthen the no-destruction regression so the
observed edit/stage/delete mutants actually fail, and then rerun acceptance. Do not
restore the coverage gate. No source fix or test weakening was attempted here.

Scratch copies, fixtures and injection scripts under
`tests/.tmp/final-prune-review/` and `tests/.tmp/final-absent-review/` were removed
after recording this evidence. Only this Execution log was edited. No commit, push,
branch switch, amend, hook bypass, or live HOME/.claude modification occurred;
`.claude-uploads/` was left untouched.

Durable learning: testing a blacklist with one known spelling proves that spelling
is blocked, not the property in the test name. Inject independent edit, delete and
stage operations. A report-only conversion must also update current phase maps,
residual-risk sections and acceptance instructions, not just its primary section.


### 2026-09-28 — Tasks 4–5 complete; Task 6 BLOCKED at Step 4

- Resume began at `65b6175` on `ship/ship-next-context-test-discipline`.
  Fresh baseline was `bats tests/`: 172/172 green. Tasks 1–3 were not redone.
- Task 4: prescribed new tests failed first (3 failures; the severity-only
  check passed immediately). Exact implementation passed 16/16 parser tests
  and 176/176 full-suite tests. Committed as `81fbbc1` with the plan's message.
  `tests/fixtures/code-review-output.md` was not modified.
- Task 5: 7/8 prescribed tests failed first; the negative counter check passed
  immediately. Implementation passed 8/8 targeted and 184/184 full-suite tests.
  Committed as `685af68` with the plan's message. The existing PLAN template
  had no per-task block, so a minimal `### Task N: <task name>` heading was
  added to host the exact prescribed lines.
- Task 6: re-read `commands/ship-next.md`; all 8 prescribed tests failed first.
  Inserted all four implementation blocks verbatim from Step 3. Step 4 now
  passes 5/8 and fails these three tests:
  - `P4 refuses in auto mode when the spec has no ## Seams`: the test searches
    for literal unescaped backticks, while the specified shell source has
    backslash-escaped backticks (`\`## Seams\`` in source).
  - `P4 only warns about missing Seams in interactive mode`: same mismatch.
  - `P5 detects ponytail ruleset drift against the global pin`: the test
    searches for `Accept and re-pin`, but the prescribed text contains
    `[A]ccept and re-pin`.
- Confirmed all four inserted Task 6 blocks match the plan verbatim. Making
  these tests green requires amending the prescribed tests or implementation;
  no assertion was weakened and no extra matching text was added to hide the
  mismatch. Per the exact-text and stop-on-failure instructions, Task 6 is
  NOT complete and remains uncommitted. Tasks 7–11 were not started.
- Recommended plan repair: make the two P4 checks match shell-source escaping
  (or explicitly test emitted messages), and make the P5 check match
  `[A]ccept and re-pin`. Preserve both the runtime behavior and meaningful
  assertions. Re-run Task 6 after the repaired instructions are accepted.
- Durable learning: literal grep assertions against shell embedded in Markdown
  see source escapes and accelerator notation, not the displayed runtime text.
  Plan authors must verify exact test patterns against their own snippets.
- No push, branch switch, amend, hook bypass, or live `$HOME/.claude/` edits.

### 2026-09-28 — Task 6 assertions corrected, resuming

Tasks 4 and 5 landed green (176/176 and 184/184 against a 129-test baseline).

Task 6 blocked on three grep assertions that could not match what the implementation
correctly writes:
- two searched for `` `## Seams` `` with bare backticks, but the file escapes them
  (`\``) because they sit inside a bash double-quoted string, where bare backticks would
  be command substitution;
- one searched for `Accept and re-pin` while the file says `[A]ccept and re-pin`.

The implementation text was right in all three cases; the assertions were wrong. Fixed by
asserting on the shortest stable backtick-free substring. A standing note now sits in
Task 6 covering Tasks 6-10, which share this hazard.

Durable learning: grep assertions against a markdown file that embeds shell code are
brittle about escaping. Assert on meaning-bearing substrings that avoid backticks,
brackets, and `$`, or the test pins the escaping rather than the wiring.

### 2026-09-28 — Task 6 complete (resumed from Step 1)

- Started at `17b47d2` on `ship/ship-next-context-test-discipline`; baseline 184/184 green. Tasks 1–5 were not redone.
- Re-read ship-next.md; copied the prescribed tests and observed 8/8 fail before implementation.
- Inserted all four prescribed blocks verbatim; targeted tests 8/8 and full `bats tests/` 192/192 green. No additional assertion adjustments.
- Repo-only scope overrides ship skill global bookkeeping and release actions; no push, branch switch, amend, hook bypass, or live HOME/.claude edits.

### 2026-09-28 — Task 7 BLOCKED at Step 4 (executor transcription error)

- Task 6 committed as `ea43942`; targeted 8/8 and full suite 192/192 green.
- Re-read all of commands/ship-next.md before Task 7. Copied the prescribed six tests verbatim; all six failed before implementation.
- Inserted the prescribed P6 mechanical-gate block and blocking-count addition, and added the reviewer instruction. The P7 insertion was incorrect: the extraction regex mistook a closing triple-backtick fence for an opening fence and copied the explanatory paragraph beginning `In **Phase 7 step 4**` instead of the prescribed `Tests: +...` line.
- Targeted verification: 5/6 pass; `P7 commit message carries the test ratio line` fails at line 45. The full-suite command was chained after targeted success and therefore did not run.
- This is an executor implementation/transcription error, not an escaping/literal mismatch. Per the user's explicit stop-on-other-failures instruction, stopped without changing any assertion or attempting a corrective edit. Task 7 remains incomplete and uncommitted; Tasks 8–11 were not started.
- Required next action: replace the accidentally inserted explanatory paragraph with the exact Task 7 ratio line, then run targeted and full-suite verification before committing Task 7. This is not a defect in the prescribed ratio line or test.
- Durable learning: an untyped Markdown fence regex can treat the closing fence of a preceding typed block as an opener. Extract from a specific structural anchor and assert the extracted content starts with the expected literal before writing; counting regex matches alone is insufficient.
- No push, branch switch, amend, hook bypass, or live HOME/.claude edits. The pre-existing untracked .claude-uploads/ directory was left untouched.

### 2026-09-29 — Task 7 unblocked by the operator, resuming at Task 8

Codex's diagnosis was exact and its stop was correct: the failure was a transcription
error in its own P7 insertion, not an escaping mismatch, so it fell outside the
authorized assertion exception.

Lines 707-711 of `commands/ship-next.md` held the explanatory paragraph
`In **Phase 7 step 4**, add one line to the commit-message heredoc...` where the
prescribed ratio line belonged. Replaced with the exact line from Task 7 Step 3, anchored
on both sentences of the misinserted text and asserted before writing.

Verified empirically, not assumed: `bats tests/test_ship-next-test-gates.bats` 6/6, and
`bats tests/` 198 tests with 0 failures. Committed as Task 7.

Codex's durable learning is adopted as a standing rule for Tasks 8-10: when inserting a
block into `ship-next.md`, assert the extracted content starts with the expected literal
before writing. An untyped Markdown fence regex can mistake a preceding block's closing
fence for an opening one, and a match count alone will not catch it.


### 2026-09-29 — Task 8 BLOCKED at Step 2 (grep option parsing)

- Resumed at `1d99026` on `ship/ship-next-context-test-discipline`. Fresh
  baseline: `bats tests/` passed 198/198. Tasks 1–7 were not modified or redone.
- Re-read both command files. Extracted Task 8's six prescribed tests from its
  uniquely anchored Step 1 block, asserted the expected shebang and test count,
  and wrote them verbatim to `tests/test_ship-compound-context.bats`.
- Targeted red run: 0/6 pass. Five assertions fail because the implementation
  is absent. The entry-format assertion has a different defect:
  `grep -F '- **<term>** — <definition>'` interprets the leading hyphen as an
  option and exits 2 with `grep: invalid option --  `.
- Confirmed independently using stdin containing exactly the expected entry:
  the prescribed invocation still exits 2; adding `--` before the unchanged
  pattern exits 0 and prints the entry. This is option parsing, not an
  escaping/literal mismatch, so it falls outside the authorized exception.
- Stopped before implementation. No assertion adjustment was made, no task
  was marked complete, and no commit was created. Tasks 9–11 were not started.
- Recommended plan repair: authorize `grep -F -- '- **<term>** — <definition>'`
  for this assertion. It preserves the entire expected string and the strength
  of the test. Then resume Task 8's red check and implementation.
- Durable learning: fixed-string grep still parses options; patterns beginning
  with a hyphen need `--` or `-e`. Verify red failures are absent behavior,
  rather than invocation errors, before writing implementation.
- Repo-only scope overrides global skill bookkeeping and release steps. No
  push, branch switch, amend, hook bypass, or live HOME/.claude access occurred.
  The pre-existing untracked `.claude-uploads/` directory was left untouched.
- Ran the full suite separately after the targeted failure: 204 tests,
  198 pass and the six new Task 8 tests fail; all pre-existing tests remain
  green. Full output: `claude-skills/ship-workflow/tests/.tmp/task-8-full-suite.log`.

### 2026-09-29 — Task 8 grep invocation fixed, resuming

Codex stopped again and was right to: `grep -F '- **<term>** — <definition>'` exits 2
because the pattern's leading hyphen is parsed as an option. That is a malformed
invocation, not the escaping mismatch its authorization covered, so it proposed the
repair rather than applying it.

Verified empirically before patching: without `--` exit 2, with `--` exit 0. Swept the
whole plan for the same hazard; this was the only occurrence. Added `--` and a standing
invocation note in Task 8.

The executor's authorization is widened for the remaining tasks: a grep exiting 2
(usage error) means the invocation is malformed and may be minimally repaired without
changing the pattern. Exit 1 still means a genuine no-match and still stops the run.

### 2026-09-29 — Task 8 complete

- Resumed at `d6a5a43`; Tasks 1–7 were left untouched. Used executing-plans and ship within the user's repo-only scope; global bookkeeping and release steps are excluded.
- Copied the six prescribed tests verbatim; red run failed 6/6 because wiring was absent.
- Asserted extracted implementation starts with its literal heading before writing; re-read both inserted regions. Task 8 block matches the plan verbatim.
- Targeted tests passed 6/6; separate `bats tests/` passed 204/204. No assertion adjustments.
- Task 8 complete; next: Task 9. Existing `.claude-uploads/` left untouched.

### 2026-09-29 — Task 9 authorized assertion adjustment (a)

- Initial red run: 7/7 fail. After inserting the exact plan block: 6/7 pass.
- The sole remaining failure searched `runs in --auto:yes because its invariants are machine-checked`; the implementation contains Markdown backticks around `--auto:yes`. Verified the entire inserted phase equals the plan block, including the explicit auto-mode statement.
- Under authorized class (a), narrowed only the grep pattern to `because its invariants are machine-checked`. This uniquely identifies the auto-mode rationale; removing the Phase 8.5 wiring removes the match. Implementation was not changed to satisfy the assertion.

### 2026-09-29 — Task 9 complete

- Task 8 committed as `81230eb`. Re-read all of ship-next.md before Task 9.
- Asserted Phase 8.5's literal heading before insertion and verified the stored region equals the plan's complete block.
- Following the class (a) adjustment recorded above, targeted tests passed 7/7; separate `bats tests/` passed 211/211 (log: `claude-skills/ship-workflow/tests/.tmp/task-9-full-suite.log`).
- Task 9 complete; next: Task 10. No implementation deviations.

### 2026-09-29 — Task 10 complete

- Task 9 committed as `147c17f`. Re-read all of ship-next.md before Task 10.
- Prescribed red run: four failures; the UA-installation and ratio-substring checks already passed against earlier phases. No tests were changed. The missing-phase ordering assertion failed because its line number was empty, as expected before insertion.
- Asserted the literal starts of the Phase 8.7 block, P9 log row, summary lines, and conditional additions before writing; re-read the inserted region. All prescribed text is present verbatim.
- Implemented the prescribed conditional summary behavior with a case on `UA_STATUS` and an if on `PONYTAIL_DRIFT`; directly verified absent, below-threshold, and rebuilt/drift summary cases with `/bin/bash`.
- Targeted tests passed 6/6; separate `bats tests/` passed 217/217 (log: `claude-skills/ship-workflow/tests/.tmp/task-10-full-suite.log`). No assertion adjustments.
- Task 10 complete; next: Task 11 acceptance gate.

### 2026-09-29 — Task 11 acceptance BLOCKED after green tests

- Commits completed this run: Task 8 `81230eb`, Task 9 `147c17f`, Task 10 `57d264d`, using the plan's exact commit messages. Tasks 1–7 remain unchanged.
- Appended Task 11's five prescribed tests verbatim. Targeted file passed 8/8 immediately; separate `bats tests/` passed 222/222, exit 0 (log: `claude-skills/ship-workflow/tests/.tmp/task-11-full-suite.log`).
- Confirmed phase order 8 < 8.5 < 8.7 < 9, exact prescribed implementation blocks, and unchanged P1–P7 text. No further assertion adjustments.
- Independent read-only acceptance review found two important defects in the prescribed Task 9 implementation, not transcription deviations:
  1. `commands/ship-next.md:744–745` maps only `tests/<module-basename>/*.py`, then falls back to the entire `tests/` tree. For `src/a.py` with conventional `tests/test_a.py`, that includes unrelated tests and violates spec §7.3's touched-module scope.
  2. `commands/ship-next.md:770` uses integer-only `-lt` for coverage totals. A direct `/bin/bash` reproduction of the exact comparison with before `80.25` and after `79.75` printed `integer expression expected`, entered the commit branch, and exited 0. This fails open instead of enforcing spec §7.5's no-coverage-drop invariant when decimal totals occur.
- Stopped under the user's stop-on-other-failures rule. These are outside authorized grep exception classes (a)/(b); no implementation fix or test weakening was attempted. Task 11 remains incomplete and uncommitted despite its green tests. The acceptance tests exercise helpers and text, not an end-to-end dependency-absent ship cycle or actual pruning rollback.
- Required next action: operator repair/authorization for Task 9's scope resolution and numeric coverage gate, with behavioral regression coverage, before re-running Task 11 acceptance. No push, branch switch, amend, hook bypass, or live HOME/.claude access occurred. Existing `.claude-uploads/` remains untouched.
- Durable learning: green Markdown grep assertions prove text presence, not safety invariants. A destructive pruning gate needs behavioral checks for unresolved test mappings and non-integer coverage totals; a comparison error must never route to the commit branch.

### 2026-09-29 — Task 11 acceptance re-review BLOCKED at 44891f8

- Resumed Task 11 only. Its five existing uncommitted tests were left unchanged.
  Used executing-plans and ship within the explicit repo-only scope, including
  an independent read-only reviewer. No global bookkeeping or release actions.
- Read Phase 8.5, `tb_coverage_ok`, the eight behavioral tests, and the three
  wiring guards. All three repairs hold: unresolved mappings skip without a
  suite-wide fallback; decimal decreases, empty values, and nonnumeric values
  are rejected by the helper; Phase 8.5 sources the helper before calling it.
- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **233/233 passed, exit 0**. This includes all eight tests in the Task 11 file.
  `git diff --check` also passed.
- Acceptance remains BLOCKED on three independently verified defects in
  committed implementation, not on the existing Task 11 assertions:
  1. **Absent CONTEXT.md is not a no-op in ship-compound.** A ship introducing
     no qualifying domain terms can leave the file absent. Nevertheless,
     `commands/ship-compound.md:126–128` unconditionally stages and mirrors it.
     In an isolated repo, `git add CONTEXT.md` exited 128 with
     `fatal: pathspec 'CONTEXT.md' did not match any files`; the actual mirror
     helper exited 2 with `ERROR: source spec not found: CONTEXT.md`.
     The helper-only absent-dependency tests do not exercise this command path.
  2. **Coverage can lose an entire source module while the gate passes.**
     `commands/ship-next.md:763,777–786` measures whatever files execute, with
     no fixed source-file universe. In a real coverage/pytest fixture with
     `src/a.py`, `src/b.py`, and `tests/src/test_modules.py`, both tests passed
     and the total was 100. Removing only the test that imports/calls `b`
     left one green test and total 100; `src/b.py` disappeared from the report
     and `tb_coverage_ok 100 100` returned 0. Measuring the unchanged source
     universe with `coverage run --source=src` exposed 50% coverage, with
     `src/b.py` at 0%. This is loss of measured source coverage, distinct from
     the documented residual risk about assertion strength.
  3. **The baseline test exit status is discarded.** At line 763 the semicolon
     runs `coverage report` even if baseline pytest fails. The same fixture
     with one deliberately failing assertion produced pytest exit 1 but
     `COV_BEFORE=100` and assignment exit 0. Removing the failing test then
     yielded pytest exit 0, `COV_AFTER=100`, and helper exit 0. The phase can
     therefore treat deletion of a failing test as a verified prune.
- Reproductions used the installed coverage/pytest and `/bin/bash`, with all
  fixture files and an isolated HOME under
  `claude-skills/ship-workflow/tests/.tmp/task11-acceptance-f57exfpg/`.
  No live `$HOME/.claude/` access, source fixes, test rewrites, commits, push,
  branch switch, amend, or hook bypass occurred. `.claude-uploads/` was untouched.
- Required repair before acceptance: skip absent/unchanged vocabulary writes
  cleanly; compare coverage over a stable source scope that includes unexecuted
  modules; require a successful baseline test run before any pruning. Add
  behavioral integration regressions for these cases, then rerun Task 11.
- Durable learning: a valid numeric comparison cannot prove coverage safety
  when the measured file set changes. A destructive refactor gate must validate
  the baseline run and preserve its measurement scope; helper no-ops alone do
  not establish that their enclosing command is additive.

### 2026-09-29 — Task 11 acceptance round 3 BLOCKED at 3e974f7

- Reviewed the current Phase 8.5 and Phase 8 CONTEXT.md commit block, with an
  independent read-only reviewer. Task 11's five existing uncommitted tests
  were preserved unchanged. No Tasks 1–10 implementation or tests were edited.
- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **237/237 passed, exit 0**. `git diff --check` also passed.
- **A holds.** Executing the actual CONTEXT.md commit block with no file exits
  0 and sets `CONTEXT_MD_STATUS="absent — no qualifying terms this ship"`.
  Neither staging nor mirroring is invoked. The absent ponytail renderer is
  silent and writes no file; the actual absent-UA P8.7 block exits 0 with
  `UA_STATUS=n/a`. These absent paths did not produce a new blocker.
- **C holds.** Executing the extracted gate against a failing baseline sets
  `skipped (baseline tests not green)` and never enters pruning or commit.
- **B is only partially repaired.** Both runs use the same `--source`, but
  this does not guarantee the same measured file set. Two blocking measurement
  defects were reproduced with real Coverage.py 7.14.0, pytest, and macOS
  `/bin/bash` 3.2.57:
  1. **Namespace-package files still disappear.** At
     `commands/ship-next.md:768,773,791`, `--source=src` initially includes
     imported `src/a.py` and `src/ns/b.py`. With no `src/ns/__init__.py`, deleting
     only the test importing/calling `b` removes that source file from the
     report. Both pytest runs are green; measured coverage goes from 4/4
     statements to 2/2 and reports `100 -> 100`, although the original source
     universe now has only 50% coverage. The independent review executed the
     actual extracted gate and it committed the deletion in an isolated
     fixture. This repeats the previous round's shrinking-measurement-set bug.
  2. **Rounded totals hide actual coverage loss.** At
     `commands/ship-next.md:776,795,800`, the default
     `coverage report --format=total` rounds both 903/1004 statements
     (89.940239%) and 902/1004 (89.840637%) to `90`. Removing one test loses an
     executed source statement; both runs remain green and `tb_coverage_ok 90
     90` succeeds. The extracted gate selects commit, not rollback. Numeric
     validation cannot recover precision already discarded by the report.
- Evidence is retained under `claude-skills/ship-workflow/tests/.tmp/`:
  `task11-independent-pedx6xbc/` contains the namespace reproduction script,
  actual gate result and before/after coverage JSON;
  `task11-round3-omxc5j4f/` contains the rounding fixture and JSON, extracted
  gate harness and `gate-results.txt`. The latter harness stubs git plumbing
  only, uses real pytest/coverage, and proves both commit paths. Controls prove
  a regular package with `__init__.py` rolls back at `100 -> 50` and a red
  baseline skips. Isolated HOME directories stay inside the repository.
- **Recommendation: make Phase 8.5 REPORT-ONLY.** List prune candidates in
  the P9 summary and delete nothing. This round surfaces more defects of the
  same measurement/safety-gate class despite 237 green tests; the concentration
  in the destructive phase continues. The operator decides this scope change;
  it has not been applied here.
- Task 11 remains incomplete and uncommitted. No parent-repository commit,
  push, branch switch, amend, hook bypass, live `$HOME/.claude/` access, or
  `.claude-uploads/` changes occurred. Only this execution-log entry was edited.
- Durable learning: a fixed source argument is not an enumerated, verified
  source universe, and displayed percentages are lossy measurements. A
  destructive gate must validate file membership and exact coverage evidence;
  syntax checks and a correct numeric comparator prove neither.

### 2026-09-29 — Acceptance round 4 BLOCKED at 8da8bed

- Reviewed the current `lib/coverage-diff.py`, Phase 8.5, and absent-dependency
  command paths. Applied the ship skill's review/verification intent within the
  explicit review-only, repository-only scope; release actions and global skill
  bookkeeping are excluded. No implementation or committed tests were changed.
- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **238/238 passed, exit 0**. The five Task 11 tests are already committed and
  were left unchanged. `git diff --check` passed.
- Behavioral harness: extracted Phase 8.5's actual Bash fences through the
  verification step, inserted a test-file replacement at its documented prune
  step, and redirected only the installed comparator path to this repository.
  Ran with macOS `/bin/bash` 3.2.57, Coverage.py 7.14.0 and pytest 8.4.2.
  Git scope/diff results were supplied by a shell function; checkout/add/commit
  were recorded, never executed. Consequently “selected commit” below means
  the actual command branch invoked the recording stub, not a repository commit.

**P1 — failed exports can reuse stale coverage evidence.**

- `commands/ship-next.md:770` and `:789` discard `coverage json` failures with
  `|| true`. The fixed output paths are neither invalidated nor tied to the
  successful test run. The comparator cannot determine that an old document
  describes a different run.
- Reproduction: `src/a.py` contains `left()` and `right()`, each with a single
  return statement. Two initial tests call both functions, measuring 4/4 source
  statements. First seed `.ship/cov-after.json` with that successful report,
  as a previous pruning invocation would leave it. Run the extracted phase
  and delete only `test_right` at the prune step.
- Both current pytest runs returned 0. Immediately before the after-export,
  the harness injected `COVERAGE_RCFILE="$PWD/missing-coveragerc"` into the
  coverage wrapper. This is an explicit report-failure injection; the report
  command itself and its failure are real. Coverage printed
  `Couldn't read '.../missing-coveragerc' as a config file` and exited 1
  before touching the old JSON. The phase then compared 4/4 against stale
  4/4, invoked `git add tests/` and `git commit`, and reported
  `per-file coverage verified`.
- Saved the actual after-run coverage database before fault injection and
  exported it with the normal configuration: **3/4**, executed lines
  `[1, 2, 4]` versus baseline `[1, 2, 4, 5]`. Comparing this fresh JSON
  returned 1: `src/a.py: covered statements fell 4 -> 3`.
- This does not claim every export failure preserves old output: a separate
  no-data failure removed the output and correctly rolled back. The reproduced
  configuration-read failure preserves it and fails open. Both baseline and
  after-export commands need success/freshness checks if this gate is retained.

**P1 — exact per-file counts still lose statement identity.**

- `lib/coverage-diff.py:39–41,69–78` retains only summary counts, discarding
  `executed_lines`. Equal counts can hide one previously covered statement
  becoming uncovered while another statement in the same file becomes covered.
  All three implemented invariants hold in this case.
- Minimal real source (`src/a.py`, line numbers derive from these blank lines):

  ```python
  import os

  def choose():
      if os.environ.get("MODE") == "left":
          return "left"
      return "right"
  ```

  Initial `tests/src/test_a.py`:

  ```python
  import os
  from src.a import choose

  def test_config():
      os.environ["MODE"] = "left"
      assert os.environ["MODE"] == "left"

  def test_choose():
      assert choose() == os.environ.get("MODE", "right")
  ```

- Start with `MODE` unset; delete only `test_config`, leaving the other test
  and all product source unchanged. Before and after, execute
  `coverage run --source=src -m pytest tests/src/test_a.py -q` followed by
  `coverage json -q -o <report>`. Both runs are green. Coverage changes from
  executed lines **[1, 3, 4, 5]** to **[1, 3, 4, 6]**, while both summaries
  remain **4/5**. The comparator returns 0 and the extracted phase selects
  commit. This fixture uses test-order state interaction; the gate does not
  establish test isolation and cannot assume deleting tests only subtracts
  executed lines.
- This is source execution loss, distinct from the documented assertion-strength
  limitation, which explicitly concerns weakening without changing executed
  lines. If retained, the gate needs statement-identity preservation, not just
  cardinality preservation.

**P2 — malformed coverage summaries are accepted as valid evidence.**

- `lib/coverage-diff.py:41` calls `int()` instead of validating integer type
  and range. For the JSON shape
  `{"files":{"src/a.py":{"summary":{"covered_lines":C,"num_statements":S}}}}`,
  before `(C,S)=(1.9,2)` and after `(1.1,2)` both truncate to `(1,2)` and
  exit **0**. Identical reports containing `(-1,-2)`, `(true,true)`,
  `(999,2)`, or `("1","2")` also exit **0**. These are not valid exact
  Coverage.py summary integers; malformed measurement evidence should return 2.
- A top-level JSON array instead raises uncaught `AttributeError` and exits 1,
  rather than the documented 2. That case still fails closed at the caller;
  it is not an additional fail-open finding.

**Controls and additive integrations verified:**

- Real namespace fixture: deleting the only test importing `src/ns/b.py`
  removed that file from the report; the comparator identified it and the
  extracted phase selected rollback.
- Real 1004-statement fixture: deleting one test changed **903/1004 to
  902/1004**; the comparator identified the exact loss and selected rollback.
- Ordinary **4/4 to 3/4** loss with fresh exports selected rollback. A red
  baseline skipped without pruning or Git actions. An unresolved module
  mapping skipped without expanding to the whole suite. Empty baseline
  documents returned 2.
- In an isolated empty Git repo with an isolated HOME, executed the actual
  ship-compound CONTEXT.md cap/commit block and Phase 8.7 block (library paths
  redirected locally). No CONTEXT.md yielded exit 0 and
  `absent — no qualifying terms this ship`, with no staging or mirror attempt.
  No UA yielded exit 0 and `UA_STATUS=n/a`. The absent ponytail renderer
  produced no stdout/stderr and no output file. Combined libraries loaded
  without collision; absent context counts and empty test budget were zero,
  shadow mode was active, and Git status remained empty. These paths produced
  no new additive-integration blocker.

**Verdict: BLOCKED. Recommendation: make Phase 8.5 REPORT-ONLY.**

The latest repairs do catch the prior reproduced cases, but another round has
again exposed the same measurement/safety class. A per-file integer remains
a lossy scalar over executed statements, and a valid report need not be fresh
evidence of the current run. Four rounds of patching this phase weigh against
continuing automatic deletion. List prune candidates in Phase 9 and delete
nothing automatically. This recommendation is recorded, not implemented.

All round-4 scratch fixtures under `tests/.tmp/round4-review/` were removed
after recording these reproductions. Only this Execution log was edited;
HEAD remained `8da8bed`. No commit, push, branch switch, amend, hook bypass,
live `$HOME/.claude/` access, or `.claude-uploads/` change occurred.

Durable learning: exact counts preserve cardinality, not membership. A
destructive gate must preserve the identities it claims to protect and prove
that every input document was successfully produced by the current run.

### 2026-09-29 — Acceptance round 5 BLOCKED at 63e8d1e

- Ran `cd claude-skills/ship-workflow && bats tests/` as its own command:
  **247/247 passed, exit 0**. No implementation or committed tests were edited.
- Applied the ship skill's adversarial review and verification intent within the
  explicit repository-only acceptance scope. Global bookkeeping, release actions,
  nested Codex invocations, and implementation changes were excluded.
- Constructed and ran fixtures with Coverage.py **7.14.0**, pytest **8.4.2**,
  and macOS `/bin/bash` **3.2.57**. Extracted the actual Phase 8.5 Bash fences
  through its verification step, inserted a test-file replacement at the prune
  step, and redirected the comparator path to this repository. A Git function
  supplied `src/a.py` as the touched path and recorded checkout/add/commit calls.
  Thus "selected commit" below means the actual phase invoked the recording
  stub, not that a repository commit was made. Product source and coverage
  configuration stayed unchanged during each pruning run. HOME was isolated
  inside each scratch fixture; no live HOME/.claude access was needed.

**P1 — preserved line sets can lose measured branch coverage.**

- `lib/coverage-diff.py:67–73,102–113` reads line sets and statement counts
  but discards `executed_branches`, even when the reports contain branch data.
  This is another measurement defect, distinct from assertion strength.
- Minimal `src/a.py` (line numbers start at the first line below):

  ```python
  def choose(flag):
      if flag:
          value = 1
      return 1
  ```

  `.coveragerc`:

  ```ini
  [run]
  branch = True
  ```

  Initial `tests/src/test_a.py`:

  ```python
  from src.a import choose

  def test_true():
      assert choose(True) == 1

  def test_false():
      assert choose(False) == 1
  ```

- Run `coverage run --source=src -m pytest tests/src/test_a.py -q`, then
  `coverage json -q -o before.json`. Delete only `test_false`, repeat the same
  commands with `after.json`, and run the repository's `coverage-diff.py` on
  the two reports. Both tests runs and exports exit 0; the comparator exits 0.
- Both reports have executed lines **[1,2,3,4]**, 4 covered statements, and
  `num_statements=4`. Executed branches change from **[[2,3],[2,4]]** to
  **[[2,3]]**; `[2,4]` becomes missing. Branch coverage falls **100% -> 50%**;
  the report's combined coverage falls **100% -> 83.333333%**.
- The extracted Phase 8.5 selects `git add tests/` and `git commit` and reports
  `per-file coverage verified`. This requires no malformed input, failed
  exporter, source modification, or assertion weakening. A distinct executed
  control-flow edge lost its only test.

**P1 — fresh JSON can combine baseline data into the after measurement.**

- `commands/ship-next.md:767–775,789–803` invalidates JSON outputs but does
  not isolate or reset Coverage.py's underlying data between measurements.
  With `[run] parallel = True`, the after export can include baseline data.
- Minimal `src/a.py`:

  ```python
  def left():
      return "left"

  def right():
      return "right"
  ```

  `.coveragerc` contains `[run]` followed by `parallel = True`. Initial tests:

  ```python
  from src.a import left, right

  def test_left():
      assert left() == "left"

  def test_right():
      assert right() == "right"
  ```

- Start in a **clean fixture with no pre-existing coverage database or JSON**.
  Run the same run/export commands as above, delete only `test_right`, and
  repeat for the after report. All four commands exit 0. Both freshly written
  JSON documents report executed lines **[1,2,4,5]**, **4/4** statements.
  The comparator returns 0 and the extracted phase selects commit.
- Copied each `.coverage.*` shard immediately after its test run and before
  its export. Exporting the copies separately using `COVERAGE_FILE=<copy>`
  proves the current runs actually recorded **[1,2,4,5] -> [1,2,4]**,
  **4/4 -> 3/4**. Comparing those isolated reports returns 1 and names line 5.
- Verified the mechanism against the installed Coverage.py command code:
  reporting calls `load()` and then `combine(strict=False, keep=False)`.
  The after export merges the new parallel shard with the retained baseline
  database. JSON deletion and a successful fresh export do not remove that
  contamination. An additional run seeded with an earlier combined database
  also selected commit, but the clean-fixture reproduction needs no such seed.
- This repeats the previous round's evidence-freshness class at the database
  layer. **Fresh serialization does not establish fresh measurement.**

**Controls and additive integrations:**

- The same left/right fixture in normal serial mode reports 4/4 -> 3/4,
  names line 5, and selects rollback. A real dynamic import of `src/ns/b.py`
  without `src/ns/__init__.py` disappears after deleting its only test;
  the comparator names the vanished file and the phase selects rollback.
- Hand-built top-level array/null/bool, invalid `files`, missing
  `executed_lines`, and bool/fractional/negative/string/null line values all
  return 2. A report-key change from `src/a.py` to `./src/a.py` returns 1,
  conservatively rejecting the changed spelling. An unchanged real
  `# pragma: no cover` fixture passes; its excluded line stays outside the
  executed-line evidence in both reports.
- An independent in-host reviewer ran the actual CONTEXT cap/commit and P3
  announcement blocks, actual P8.7 UA block, and P5 ponytail render/drift
  portion in an isolated empty Git repo. Absent CONTEXT exits 0 with the
  absent status and no stage/mirror attempt. Absent UA exits 0 with `n/a`.
  Absent ponytail is silent, writes no rules file, and yields empty version
  and hash with drift 0. Four libraries load without collision; empty counts
  and budget ratios are zero, shadow mode is active, and Git status stays
  empty. These concrete absent paths remain additive. This does not claim
  execution of an entire agent-driven ship conversation.

**Verdict: BLOCKED. Third recommendation: make Phase 8.5 REPORT-ONLY.**

Two fresh reproductions expose the same measurement/safety-gate class despite
247 green tests. List prune candidates in Phase 9 and delete nothing
automatically. This recommendation is recorded, not implemented.

The statement "line identity summarises nothing" is false: an executed-line
set discards control-flow edge identity and execution context. Even a richer
set cannot distinguish current execution from historical data merged into it.
The gate needs evidence of both what was executed and which run produced it;
preserving line membership alone establishes neither complete coverage parity
nor measurement isolation.

All round-5 fixtures in `tests/.tmp/round5-review/` and
`tests/.tmp/round5-additive/` were removed after recording the reproductions.
Only this Execution log was edited; `git diff --check` passed and HEAD
remained `63e8d1e`. No commit, push, branch switch, amend, hook bypass,
live HOME/.claude change, or `.claude-uploads/` change occurred.

## RESUME HERE — paused 2026-09-29 (codex workspace out of credits)

**State: clean and green.** Branch `ship/ship-next-context-test-discipline`, HEAD
`fea7807`, 33 commits ahead of `main`. Working tree clean apart from a pre-existing
untracked `.claude-uploads/`. `cd claude-skills/ship-workflow && bats tests/` gives
**198 tests, 0 failures** (baseline before this work was 129).

**Done:** Tasks 1-7, each committed with its own tests green.

| Commit | Task |
|---|---|
| `9b45dad` | 1 — `lib/context-md.sh` |
| `d752304` | 2 — `lib/test-budget.sh` |
| `744f666` | 3 — `lib/ponytail-integration.sh` |
| `81fbbc1` | 4 — three category counters in `code-review-parse.sh` |
| `685af68` | 5 — templates + global config docs |
| `ea43942` | 6 — P3-P5 wiring (CONTEXT.md, seam gate, `.ship/` rule files) |
| `1d99026` | 7 — P6 mechanical gates + P7 ratio line |

**Remaining:** Tasks 8, 9, 10, 11 — unstarted, nothing half-applied, no reverts needed.

**To resume, relaunch from Task 8.** The launch prompt that was in flight when credits
ran out is preserved at `/tmp/run-plan-prompt-<slot>.txt`; regenerate it if /tmp has been
cleared. It must carry four things, all learned the hard way:

1. **Scope override.** `claude-skills/ship-workflow/` is the target, not agent config to
   skip. Without this the executor refuses the whole plan.
2. **Authorized deviation (a): brittle grep assertions.** A search string that fails only
   because the file escapes a backtick (`\``) or contains a literal `[` `]` `$` may be
   narrowed to the shortest stable substring. Never edit implementation to satisfy a test.
3. **Authorized deviation (b): malformed grep invocation.** grep exit 2 is a usage error,
   not a no-match; repair the invocation (e.g. insert `--`) without changing the pattern.
   Exit 1 still stops the run.
4. **Insertion rule for Tasks 8-10.** Assert the extracted block starts with the expected
   literal before writing. An untyped Markdown fence regex can mistake a preceding block's
   closing fence for an opening one.

Also: run the full suite as its own command after each task, never chained behind a
targeted run with `&&`.

### Retrospective on the five blocked runs

Codex stopped five times and was right every time. Four stops were defects in this plan,
one was its own transcription error, which it correctly identified as outside its
authorization rather than quietly patching. The defect classes, all authored here:

1. **Shared-fixture contamination** — Task 4 appended to a fixture that other tests own.
2. **Unbounded programmatic edit** — a textual index slice while repairing Task 4 deleted
   Task 4 Steps 2-5 and all of Task 5, and was committed unverified.
3. **Escaping-blind assertions** — Task 6 grepped for bare backticks the file must escape.
4. **Option-parsing** — Task 8 grepped a pattern beginning with `-` without `--`.

The through-line: every one is an assertion or edit written without executing it. The
self-review in `writing-plans` checked cross-task variable definitions and caught two real
gaps, but it cannot catch a string that only fails at runtime. A future plan touching
markdown-embedded shell should dry-run its grep assertions against the real file before
the plan is handed to an executor.

### 2026-09-29 — Task 9 safety defects repaired, Task 11 handed back

Tasks 8, 9 and 10 committed (`81230eb`, `147c17f`, `57d264d`) at 222/222. Task 11's five
prescribed tests were applied and passed, and the executor still refused to commit the
task. It was right to: the acceptance gate's job is to establish safety invariants, and
its own review found two defects in Task 9's prescribed code that green grep assertions
could never have caught.

**Defect 1 — unscoped fallback.** `[ -z "$TEST_TARGETS" ] && TEST_TARGETS="tests/"` widened
an unresolved module mapping into an LLM prune pass over the entire suite, contradicting
§7.3 and destroying the bounded-blast-radius property that justifies running this in
`--auto:yes`. Removed; an unresolved mapping now skips pruning.

**Defect 2 — the coverage gate failed open.** `[ "$COV_AFTER" -lt "$COV_BEFORE" ]` is
integer-only. `coverage report --format=total` can emit `80.25`, which makes `[` error;
a non-zero exit from `[` routed to the **commit** branch, so a coverage drop shipped.
Testing the repair surfaced two more fail-open cases the review had not named: an empty
`COV_BEFORE`, and any non-numeric total. All three now roll back.

**Repair shape, per the executor's own request for behavioral coverage.** Rather than
patching the inline comparison, the logic moved out of untestable Markdown into
`lib/test-budget.sh` as `tb_coverage_ok <after> <before>`, which fails closed. Eight
behavioral tests pin it, including the decimal-drop case `[ -lt ]` got wrong. Three grep
guards pin the wiring: no `tests/` fallback, the helper is used instead of an inline
integer compare, and the helper is sourced before it is called.

**Defect 3, found while verifying the repair.** Phase 8.5 called `tb_coverage_ok` but
never sourced `lib/test-budget.sh`. Phase 7 `cd`s back to the main repo, so Phase 8.5
does not inherit Phase 6's shell. This failed closed (missing command exits non-zero, so
every prune would have rolled back) but silently disabled the feature. Source line added,
with an assertion that it precedes the call.

Suite: 222 -> 233, 0 failures.

Durable learning, adopted from the executor verbatim: **green Markdown grep assertions
prove text presence, not safety invariants.** Logic that gates a destructive operation
belongs in a lib where it can be unit-tested, not inline in a command file where the only
available assertion is that the text exists.

### 2026-09-29 — third acceptance review: three more defects repaired

The executor ran the acceptance gate again, confirmed the previous three repairs hold at
233/233, and refused to commit Task 11 a second time. It found three more defects, one of
which invalidated the previous round's fix.

**Defect A — `CONTEXT.md` commit was not additive.** A ship that surfaces no qualifying
terms leaves no file, so `git add CONTEXT.md` exits 128 and `spec-mirror.sh` exits 2.
Guarded on `[ -f CONTEXT.md ]`, with `CONTEXT_MD_STATUS="absent — no qualifying terms
this ship"` on the other branch.

**Defect B — the coverage measurement scope shrank with the deletion.** This is the
important one. `coverage run -m pytest` without `--source` reports only files that were
IMPORTED. Deleting a module's only test removes that module from the report entirely, so
the remaining average can RISE and the gate passes. The executor measured the case
directly: 100% reported, 50% under fixed-source measurement.

Last round's `tb_coverage_ok` repair was correct and irrelevant. The comparison was never
the problem; the two numbers being compared were not measuring the same thing. Both runs
now pass `--source="$COV_SOURCE"`, derived from the touched modules, so a module stays in
scope after its test is deleted and its coverage correctly falls.

**Defect C — a red baseline still produced a number.** `coverage run ... >/dev/null 2>&1;
coverage report ...` discards pytest's exit status through the `;`. A failing baseline
yielded a usable COV_BEFORE, so pruning away the failing test passed the gate. The run's
exit code is now checked on its own, and a non-green baseline skips pruning.

Verification went beyond counting this time: the Phase 8.5 bash blocks are extracted and
parsed with `bash -n`, and that check is now a bats test so it cannot regress. Three more
grep guards pin `--source` on both runs, the absence of the bare `coverage run -m pytest`
form, the baseline exit check, and the absence of the `; coverage report` form.

Suite: 233 -> 237, 0 failures.

**Defect concentration, recorded deliberately.** Phase 8.5 has now produced six defects
across three review rounds. Every other task combined has produced one. It is the only
destructive operation in the design, and each round's fix looked complete at the time.
Rounds one and two both passed a green suite. If a fourth round surfaces more, the right
move is to make Phase 8.5 report-only — list prune candidates in the P9 summary and
delete nothing — rather than patch instance after instance of the same class.

Durable learning: a safety gate on a destructive operation must validate its own
measurement, not just its comparison. Ask what the metric is computed over, and whether
the destructive act changes that set.

### 2026-09-29 — the percentage gate is replaced by a real coverage diff

Fourth acceptance review. Two more defects of the same class, both reproduced in isolated
fixtures by the executor:

- **`--source` does not pin a namespace package.** With `--source=src`, deleting the only
  test importing `src/ns/b.py` still drops that file from the report when `src/ns/` has no
  `__init__.py`. Both runs reported 100 -> 100 while coverage over the original file set
  was 50%. The extracted gate committed the deletion.
- **Rounded totals hide real losses.** 903/1004 (89.940%) -> 902/1004 (89.840%). Both
  render as `90`. The gate accepted the deletion.

That is eight defects in Phase 8.5 across four rounds, against one in every other task
combined. Rounds one through three each produced a fix that was correct and insufficient,
and each passed a fully green suite. The executor recommended making Phase 8.5
report-only. The operator chose instead to build the gate properly.

**Root cause, finally stated correctly.** A coverage *percentage* is not a safety
invariant for deletion. It is a lossy scalar computed over a file set that the destructive
act itself can shrink. Every previous round fixed the comparison while leaving the
measurement unsound.

**The replacement: `lib/coverage-diff.py`.** It compares two `coverage json` documents and
enforces three invariants per file, on exact integers:

1. every file measured before is still measured after — catches the vanishing-file hole
2. `covered_lines` never falls for any such file — catches 903 -> 902, and catches a
   single file falling while the total rises
3. `num_statements` is unchanged — a moving statement count means the comparison is not
   like-for-like

Exit 0 means no regression, 1 means regression, and 2 means *cannot decide* — missing
input, malformed JSON, or an empty baseline. Callers treat 2 as a regression, so "cannot
tell" is never confused with "safe". Ten behavioral tests cover all of it, including the
two cases the executor reproduced.

`tb_coverage_ok` and its eight tests were deleted rather than left beside the new gate.
It was created two rounds ago for this call site and is now dead code; leaving a weaker
gate in the library invites someone to reach for it. Phase 8.5's `source` of
`lib/test-budget.sh` went with it, since no lib function is called there any more.

Suite: 237 -> 238, 0 failures (ten added for the new gate, eight removed with the old one,
four rewritten).

Durable learning: before trusting a metric as a safety gate, ask what set it is computed
over and whether the guarded operation can change that set. A correct comparison over an
unsound measurement is still unsound.

### 2026-09-29 — the gate now compares line sets, not counts

Fifth acceptance review, three more defects, all reproduced by the executor:

- **Equal counts hid lost lines.** Executed lines went `[1,3,4,5]` -> `[1,3,4,6]`.
  `covered_lines` stayed 4 and the gate committed, while line 5 lost its only test.
- **A stale report could pass.** `coverage json ... || true` swallowed an export failure,
  so a leftover `cov-after.json` from an earlier run was compared. Measured coverage fell
  4 -> 3 and the gate committed.
- **Malformed summaries passed.** `int(1.9)` truncates to 1, and `isinstance(True, int)`
  is true in Python, so fractional, negative and boolean counts all sailed through.

The executor restated its report-only recommendation. The operator chose one more round.

**The conceptual error, finally named.** Round four moved from a rounded percentage to
exact integer counts and called that ground truth. It is not. *Counts preserve
cardinality, not membership.* The only representation with nothing left to summarise is
the set of executed line numbers, which is what `coverage json` already records per file.

The gate now enforces, per file present in the baseline:

  a. the file is still measured after                       — membership
  b. `set(executed_lines_before) ⊆ set(executed_lines_after)` — identity
  c. `num_statements` unchanged                              — like-for-like

(b) subsumes the old count check: a superset cannot have a smaller count. Values are
validated strictly — a plain non-negative `int`, with `bool` rejected explicitly — so a
malformed report cannot pass. A missing `executed_lines` is exit 2, never a guess.

Export freshness is now part of the evidence: each report is deleted before the run, the
`coverage json` exit code is checked, and an empty or failed export rolls back rather
than comparing whatever was on disk.

**One defect found by the operator, not the reviewer.** Probing the new gate with
hand-built inputs before handing it back, a top-level JSON array returned exit 1 with an
uncaught `AttributeError` traceback instead of exit 2. Fail-closed in direction, wrong in
signal. The document type is now validated and `AttributeError` is caught. This is the
first defect in Phase 8.5 caught before review rather than by it, and it was caught by
running adversarial inputs rather than by reading the code — the same method the reviewer
has been using for five rounds.

Suite: 238 -> 247, 0 failures.

Durable learning: when a gate guards a destructive act, keep asking what the compared
value is a summary *of*. Percentage summarises count, count summarises line identity,
line identity summarises nothing. Stop only when there is no summary left.

### 2026-09-29 — Phase 8.5 becomes report-only

Sixth acceptance review, two more reproduced defects:

- **Branch loss with identical line sets.** Executed lines unchanged while branch
  coverage fell 100% -> 50%. A line set cannot see control-flow edges.
- **Coverage data accumulation.** The previous round made the JSON *export* fresh by
  deleting it first, but `.coverage` itself accumulates across runs, so a faithfully
  fresh export reported stale combined data and hid a real 4/4 -> 3/4 loss.

That is fourteen defects in one phase across six rounds, against one in every other task
combined. The executor recommended report-only three times; the operator accepted on the
third, after the underlying reason was finally stated correctly.

**Why the gate could never have worked.** Three separate rounds each declared the root
cause found — first the comparison, then the percentage, then the count — and each was
wrong in the same direction: still comparing a summary. But even a perfect coverage
comparison answers the wrong question. Coverage records which lines and branches
*executed*. It does not record whether an assertion *observed* them. Delete a test and
replace it with one that walks the identical path and asserts nothing, and every
coverage-derived gate passes. §7.5 of the spec listed this as a "known limit" from the
start; it was not a limit, it was the whole problem, and it took six rounds to see that
the accepted residual risk was in fact fatal to the design.

The tool that answers the real question is mutation testing: inject a defect, confirm a
test catches it. Different cost, different scope, its own roadmap item.

**What shipped.** Phase 8.5 keeps its trigger and scope and writes
`.ship/prune-candidates.md` — file, test, category, one line of reasoning per row. P9
surfaces the count. There is no coverage run, no rollback path and no commit, so the
`--auto:yes` question disappears with the destructive act. The operator deletes.

Deleted rather than left beside it: `lib/coverage-diff.py`, its 18 tests, the fixture
helper, and every reference. A superseded gate left in `lib/` is an invitation to reach
for it.

**One test defect found by injection, not by reading.** The new "Phase 8.5 deletes
nothing" guard passed while scanning the whole section — and would have kept passing with
destructive code present, because the section's own prose says "there is no coverage run"
and the scan matched its own explanation. Caught by injecting `git checkout -- tests/`
into the phase and confirming the guard went red, then confirming it went green again on
revert. The guard now scans only the extracted bash.

Suite: 247 -> 226 (18 gate tests removed with the gate, prune guards consolidated 13 -> 10).
0 failures.

Durable learning: before building a gate, ask what question the metric answers, not just
how accurately it answers it. Six rounds were spent improving the accuracy of an answer
to the wrong question. And verify a guard by injecting the defect it claims to catch —
a guard that has never gone red has not been tested, it has only been run.

### 2026-09-29 — report-only finishing defects closed

Seventh review. Four findings, all valid and all different in kind from the fourteen
before them: these are finishing defects in the report-only change, not another instance
of the measurement class.

**1. Documents still claimed deletion.** §7 of the spec was amended but its §10 phase map
still read "coverage-gated, own commit", and Phase 8.7 in both the spec and the command
file still spoke of "the pruning commit". Documentation drift is the exact disease this
change set exists to cure, and it was introduced while curing it. Fixed in all three
places, with a guard asserting no shipped document contains `coverage-gated`,
`pruning commit` or `test: prune`.

**2. The no-destruction guard was a leaky denylist.** It listed `git add tests/` and
missed `git add -- tests/src/test_a.py`; it had no entry for `rm` or for `> tests/x.py`
truncation. A denylist of literal strings cannot be complete.

Replaced with three structural rules over the extracted bash:
  - the only permitted `git` subcommand is `diff`, which kills add, rm, commit, checkout,
    restore and stash in one rule regardless of argument form
  - no file-mutating command at all (`rm`, `mv`, `cp`, `truncate`, `tee`, `sed -i`, …)
  - every redirect must target `.ship/` or `/dev/null`, so truncation has nowhere to go

Verified by injecting ten separate destructive statements, including all three the
reviewer used. All ten turn the guard red; reverting turns it green.

**3. Candidate counting collided with its own table header.** `grep -c '^| '` over a
Markdown table counts the header and separator rows: one candidate read as two, and a
header-only file read as one. The format is now one `CANDIDATE: ` line per row, a prefix
no header can produce.

**4. The `_log.md` row omitted the count.** Phase 8.5's text promised Phase 9 would carry
the status into both the summary and the log row; only the summary was wired. Fixed, with
a guard on the row's content.

Suite: 226 -> 229, 0 failures.

Durable learning: a denylist guard is only as good as the author's imagination, and the
author is the same person who wrote the thing being guarded. Prefer a structural rule
that admits a small allowed set over a list of forbidden strings — and prove it by
injecting the defects it claims to catch, one at a time.

### 2026-09-30 — the no-destruction guard becomes behavioural

Eighth review. Four statements passed the "structural" guard and actually mutated the
reviewer's fixtures:

    git -C . add -- tests/src/test_a.py          # `-C` is not [a-z], so no subcommand parsed
    /bin/rm -f tests/src/test_a.py               # `rm` preceded by `/`, not whitespace
    : > .ship/../tests/src/test_a.py             # target starts with .ship/, traversal
    sed -e 's/assert/pass #/' -i '' tests/...    # `-i` not adjacent to `sed`

The previous round called those rules "structural, not a denylist". They were not. They
were still string patterns over shell text, and the ways to spell a destructive command
are unbounded — `/bin/rm`, `$(command -v rm)`, `eval`, `find -delete`, `python3 -c`.
A textual guard cannot establish that a shell block does nothing.

**Replaced with a behavioural guard.** The phase's bash is extracted and *executed*
against a fixture git repo, and the worktree, index, stash list, test-file hashes and
HEAD are compared before and after. That is how the reviewer found every one of these:
it ran them.

Two fixture properties turned out to be load-bearing, and both were discovered by
injection rather than reasoning:

- **The fixture must be dirty.** On a clean tree `git add`, `git checkout -- tests/`,
  `git restore` and `git stash push` are all no-ops and slip through. With an unstaged
  edit and a separately staged file present, all four are caught.
- **`.ship/` must exist.** Otherwise `: > .ship/../tests/x.py` fails on a missing
  directory and the injection looks harmless, while in a real run the directory is there.

Sixteen destructive statements were injected one at a time, including all four from this
round and all ten from the last. Every one turns the guard red; reverting turns it green.

**Also fixed.** `grep -c` prints `0` *and* exits 1 when it matches nothing, so
`|| echo 0` appended a second zero and an empty report displayed `00`. Now `|| true`,
with the default covering only a missing file. Verified across five cases.

**And the documents, a third time.** §7 was amended in one round, §10 and Phase 8.7 in
the next, and this round the reviewer still found §3's principle P5, §12.4's residual
risks and §13's test strategy prescribing the coverage gate. All corrected — this time by
sweeping the whole spec for `coverage|rollback|prune|deletes` and judging every hit,
rather than fixing the sections that came to mind. Principle P5 keeps its point and gains
the corollary the whole episode earned: *if no mechanical invariant exists, do not perform
the destructive act at all.*

Suite: 229 -> 231, 0 failures.

Durable learning: to prove code does nothing, run it and look at what changed. Every
textual approximation of that claim — denylist, allowlist, "structural" rules — is a
guess about how the next author will spell the thing you are forbidding. And when a
behavioural test passes, check the fixture actually represents the state where the defect
would bite; a no-op on the wrong fixture is indistinguishable from safety.
