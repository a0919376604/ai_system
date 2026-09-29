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

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-context.bats`
Expected: FAIL — 6 tests fail.

- [ ] **Step 3: Write minimal implementation**

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
   git add CONTEXT.md && git commit -m "context: update vocabulary from ${ID}"
   VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
   ~/.claude/skills/ship-workflow/lib/spec-mirror.sh CONTEXT.md "$VAULT_DIR/CONTEXT.md"
   ```
````

In `commands/ship-next.md` **Phase 8**, add one sentence noting that
`/ship-compound` now also updates `CONTEXT.md` and exports `CONTEXT_MD_STATUS`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-compound-context.bats`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-compound.md \
        claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-compound-context.bats
git commit -m "feat: write and cap CONTEXT.md in ship-compound"
```

---

### Task 9: Phase 8.5 test pruning

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (new Phase 8.5)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-prune.bats`

**Interfaces:**
- Consumes: `TEST_BUDGET_VERDICT` (Task 7).
- Produces: `PRUNE_STATUS` for Task 10's P9 summary.

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats`
Expected: FAIL — 7 tests fail; Phase 8.5 does not exist.

- [ ] **Step 3: Write minimal implementation**

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
     [ -z "$TEST_TARGETS" ] && TEST_TARGETS="tests/"
   ```

3. **Record the baseline.**

   ```bash
     COV_BEFORE=$(coverage run -m pytest $TEST_TARGETS -q >/dev/null 2>&1; coverage report --format=total 2>/dev/null || echo "")
     if [ -z "$COV_BEFORE" ]; then
       PRUNE_STATUS="skipped (no coverage baseline)"
     else
   ```

4. **Prune.** Edit only files under `$TEST_TARGETS`, in this order:
   1. duplicate coverage — two tests asserting the same behavior, keep one
   2. seam violations — tests asserting inside a seam, lift to seam level or delete
   3. never-failing tests — assertions too weak to discriminate, strengthen or delete

5. **Verify both invariants, or roll back.**

   ```bash
       if ! coverage run -m pytest $TEST_TARGETS -q >/dev/null 2>&1; then
         git checkout -- tests/
         PRUNE_STATUS="rolled back (tests failed)"
       else
         COV_AFTER=$(coverage report --format=total 2>/dev/null || echo 0)
         if [ "${COV_AFTER:-0}" -lt "${COV_BEFORE:-0}" ]; then
           git checkout -- tests/
           PRUNE_STATUS="rolled back (coverage dropped ${COV_BEFORE} -> ${COV_AFTER})"
         else
           PRUNED_LINES=$(git diff --numstat -- tests/ | awk '{s+=$2} END {print s+0}')
           git add tests/
           git commit -m "test: prune redundant tests in ${MODULES}"
           PRUNE_STATUS="pruned -${PRUNED_LINES} lines, coverage ${COV_BEFORE} -> ${COV_AFTER}"
         fi
       fi
     fi
   fi
   ```

   This is a **separate commit** from the Phase 7 squash on purpose: folding it in
   would pollute the R-NNN diff and defocus review.

   **Known limit:** flat coverage does not prove assertion strength was preserved.
   This bounds the damage; it does not eliminate it.

   **Auto-mode log:**
   ```bash
   [ "$AUTO" = "1" ] && ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P8.5" "$PRUNE_STATUS"
   ```
````

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-prune.bats`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-ua-rebuild.bats`
Expected: FAIL — 6 tests fail.

- [ ] **Step 3: Write minimal implementation**

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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-ua-rebuild.bats`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

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
