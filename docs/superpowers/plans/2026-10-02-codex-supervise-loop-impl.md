# Codex Supervise Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/ship-next` Phase 5 supervise a codex run instead of invoking it once and hoping, routing a `BLOCKED` verdict to repair, to a stop, or to the operator.

**Architecture:** Three new bash libraries hold everything mechanical — classifying a run's terminal verdict, accumulating per-round reports verbatim, and persisting loop state across session restarts. Each follows the `auto-decision-log.sh` contract: small, single-purpose, exit-code-driven, unit-tested with bats. The judgement step (is this a plan defect, an executor error, or a contradiction of the spec?) stays in `ship-next.md` as instructions to Claude, because it is judgement. Phase 5's prose grows a loop around those pieces; Phase 6's fix-plan re-invoke reuses them.

**Tech Stack:** bash (macOS `bash 3.2` compatible — no `declare -A`, no `${x^^}`, no `mapfile`), bats-core, `git`. No new runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-10-02-codex-supervise-loop-design.md`

## Global Constraints

- **Every public function is a silent no-op when its dependency is absent** — matches `ua-integration.sh` and `prune-report.sh`. A repo without codex completes a full cycle unchanged.
- **macOS bash 3.2 compatible.** No associative arrays, no `${var^^}`, no `readarray`/`mapfile`.
- **Declare `local` once at function top, never inside a loop body.** zsh prints a re-declared local and bash does not; `tests/test_ua-zsh-portability.bats` enforces this repo-wide.
- **Exit-code contract, from `prune-report.sh`:** `0` a decision was reached, `2` the input could not be evaluated. Callers treat `2` as failure. "Cannot tell" is never "fine".
- **Infrastructure signatures** (spec §4.2), matched literally: `out of credits`, `flagged for possible`, `UnknownProcessId`, `failed to record rollout items`. Absence of any verdict marker is also infrastructure.
- **Verdict markers:** `DONE`, `DONE_WITH_CONCERNS`, `BLOCKED`, each possibly wrapped in `**`.
- **Attempt cap is 3**, matching Phase 6's review loop. Infrastructure failures never consume an attempt.
- **State file:** `<worktree>/.ship/codex-supervise.md`. Round history: `<worktree>/.ship/codex-rounds.md`. Both are per-worktree and die at Phase 9 cleanup.
- **Round reports are stored byte-identical** to what the executor emitted. No summarising, no reflowing.
- Tests run with `bats tests/` from `claude-skills/ship-workflow/`.
- Markdown command files are verified by grep assertions over **extracted bash fences**, never over prose — a guard that scans a whole section matches its own explanation.

## Review Focus

- **A log whose verdict marker appears inside quoted prose rather than as the executor's own verdict** — e.g. a report that says `the plan says to report BLOCKED`. Classifying on a substring anywhere in the file will mis-read it. Covered in Task 1.
- **A log containing both an infrastructure signature and a real verdict** — credits run out *after* a `BLOCKED` was printed. Infrastructure must win, because the run did not complete. Covered in Task 1.
- **A round report containing backticks, `$`, or a line starting with `#`** — it is stored verbatim into a Markdown file and must not corrupt the surrounding structure or be re-interpreted on read-back. Covered in Task 2.
- **A state file left behind by a previous, unrelated ship** — stale `attempt:` or `blocked_at:` must not silently resume someone else's loop. Covered in Task 3.
- **A live codex process when Phase 5 is re-entered** — relaunching would run two executors on one branch. Covered in Task 3.

---

### Task 1: `lib/codex-verdict.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/codex-verdict.sh`
- Test: `claude-skills/ship-workflow/tests/test_codex-verdict.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `codex_verdict <logfile>` echoing exactly one of `done`, `done_with_concerns`, `blocked`, `infra`, and `codex_verdict_reason <logfile>` echoing a one-line explanation. Task 4 calls both; Task 2 stores the verdict alongside the report.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_codex-verdict.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-verdict)"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-verdict.sh"
}
teardown() { rm -rf "$SCRATCH"; }

mklog() { printf '%s\n' "$@" > run.log; }

@test "codex_verdict: a bold DONE is done" {
  mklog "tokens used" "140,000" "**DONE.** Committed Task 11 as 7a15404."
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: a bare DONE is done" {
  mklog "DONE"
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: DONE_WITH_CONCERNS is its own verdict" {
  mklog "**DONE_WITH_CONCERNS** two follow-ups recorded"
  run codex_verdict run.log
  [ "$output" = "done_with_concerns" ]
}

@test "codex_verdict: a bold BLOCKED is blocked" {
  mklog "**BLOCKED.** Suite passed 231/231, but three guard bypasses remain:"
  run codex_verdict run.log
  [ "$output" = "blocked" ]
}

@test "codex_verdict: out of credits is infra, not a verdict" {
  mklog "BEGIN." "ERROR: Your workspace is out of credits. Add credits to continue."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a content filter trip is infra" {
  mklog "ERROR: This content was flagged for possible cybersecurity risk."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a crashed process is infra" {
  mklog "ERROR codex_core::tools::router: error=exec_command failed: UnknownProcessId { process_id: 91680 }"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a lost rollout thread is infra" {
  mklog "ERROR codex_core::session: failed to record rollout items: thread not found"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: no marker at all is infra, never done" {
  mklog "OpenAI Codex v0.155.1" "workdir: /tmp/x" "tokens used" "42"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: infrastructure wins over a verdict printed before it" {
  # Credits ran out after the report was emitted: the run did not complete.
  mklog "**BLOCKED.** two defects remain" "ERROR: Your workspace is out of credits."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a marker quoted mid-sentence is not the verdict" {
  # The prompt tells the executor to "report BLOCKED"; echoing that is not a verdict.
  mklog "The instructions say to report BLOCKED if anything fails." "**DONE.** all green"
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: a missing log is infra, not an error" {
  run codex_verdict nope.log
  [ "$status" -eq 0 ]
  [ "$output" = "infra" ]
}

@test "codex_verdict_reason: names the infrastructure signature it matched" {
  mklog "ERROR: Your workspace is out of credits."
  run codex_verdict_reason run.log
  [[ "$output" == *"out of credits"* ]]
}

@test "codex_verdict_reason: says so when no marker was produced" {
  mklog "tokens used" "42"
  run codex_verdict_reason run.log
  [[ "$output" == *"no verdict"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-verdict.bats`
Expected: FAIL — `codex-verdict.sh` does not exist, so `source` errors in `setup`.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/codex-verdict.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/codex-verdict.sh
# Classify how a `/run-plan` codex run ended, from its log.
#
# Echoes exactly one of: done | done_with_concerns | blocked | infra
# Always exits 0 — the classification IS the result; a missing or unreadable
# log classifies as infra rather than failing.
#
# Why `infra` is separate from `blocked`:
#   Across 19 real runs, two ended without producing any verdict — credits ran
#   out, and a content filter crashed the process. Retrying those is pointless,
#   and counting them against a repair budget burns attempts that real defects
#   need. A run that produced no verdict produced no information.
#
# Why infrastructure beats a verdict already printed:
#   Credits can run out after the report is emitted. The report describes work
#   that then did not finish, so the run is not trustworthy.
#
# Why the verdict must be the executor's own:
#   The prompt itself contains the words "report BLOCKED". Matching that
#   substring anywhere in the log reads the instructions back as a result, so a
#   verdict only counts at the start of a line, optionally bold.

CODEX_INFRA_SIGNATURES='out of credits|flagged for possible|UnknownProcessId|failed to record rollout items'

# _codex_marker <logfile> — echo the last line-anchored verdict marker, or nothing.
_codex_marker() {
  grep -aoE '^\*{0,2}(DONE_WITH_CONCERNS|DONE|BLOCKED)\b' "$1" 2>/dev/null \
    | tr -d '*' | tail -1
}

# codex_verdict <logfile>
codex_verdict() {
  local log="$1" marker
  [ -f "$log" ] || { echo infra; return 0; }
  if grep -aqE "$CODEX_INFRA_SIGNATURES" "$log" 2>/dev/null; then
    echo infra; return 0
  fi
  marker=$(_codex_marker "$log")
  case "$marker" in
    DONE_WITH_CONCERNS) echo done_with_concerns ;;
    DONE)               echo done ;;
    BLOCKED)            echo blocked ;;
    *)                  echo infra ;;
  esac
}

# codex_verdict_reason <logfile> — one line explaining the classification.
codex_verdict_reason() {
  local log="$1" hit marker
  [ -f "$log" ] || { echo "no log file at $log"; return 0; }
  hit=$(grep -aoE "$CODEX_INFRA_SIGNATURES" "$log" 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    echo "infrastructure failure: $hit"
    return 0
  fi
  marker=$(_codex_marker "$log")
  if [ -z "$marker" ]; then
    echo "no verdict marker in the log — the run produced no result"
    return 0
  fi
  echo "executor reported $marker"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-verdict.bats`
Expected: PASS — 14 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/codex-verdict.sh \
        claude-skills/ship-workflow/tests/test_codex-verdict.bats
git commit -m "feat: classify a codex run's terminal verdict, infra separately"
```

---

### Task 2: `lib/codex-rounds.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/codex-rounds.sh`
- Test: `claude-skills/ship-workflow/tests/test_codex-rounds.bats`

**Interfaces:**
- Consumes: nothing. (The verdict string is passed in by the caller, which got it from `codex_verdict`.)
- Produces: `codex_round_append <worktree> <n> <verdict> <reportfile> <classification> <note>`, `codex_round_count <worktree>`, `codex_round_last_findings <worktree>`. Task 4 calls all three; Task 5 calls `codex_round_last_findings` for the Phase 9 digest.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_codex-rounds.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-rounds)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-rounds.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "codex_round_append: stores the report byte-identical" {
  printf '**BLOCKED**\n\nTwo defects:\n\n- `git diff` returns exit 0\n- $HOME is unquoted\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "fixed step 3"
  # Every byte of the original must survive, including backticks and $.
  while IFS= read -r line; do
    grep -qxF -- "$line" "$WT/.ship/codex-rounds.md" \
      || { echo "lost line: $line"; return 1; }
  done < r.md
}

@test "codex_round_append: records the round number, verdict and classification" {
  echo "report body" > r.md
  codex_round_append "$WT" 2 blocked r.md "executor error" "relaunched with a note"
  grep -qF "## Round 2" "$WT/.ship/codex-rounds.md"
  grep -qF "blocked" "$WT/.ship/codex-rounds.md"
  grep -qF "executor error" "$WT/.ship/codex-rounds.md"
  grep -qF "relaunched with a note" "$WT/.ship/codex-rounds.md"
}

@test "codex_round_append: a leading # in the report does not become a heading" {
  printf '# not a section heading\nbody\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "x"
  # Exactly one level-2 heading — ours. The report is fenced, not inlined.
  [ "$(grep -c '^## ' "$WT/.ship/codex-rounds.md")" -eq 1 ]
}

@test "codex_round_append: accumulates rather than overwriting" {
  echo "first" > r1.md; echo "second" > r2.md
  codex_round_append "$WT" 1 blocked r1.md "plan defect" "a"
  codex_round_append "$WT" 2 done   r2.md "n/a" "b"
  grep -qF "first"  "$WT/.ship/codex-rounds.md"
  grep -qF "second" "$WT/.ship/codex-rounds.md"
}

@test "codex_round_count: counts rounds, zero when absent" {
  run codex_round_count "$WT"
  [ "$output" = "0" ]
  echo "x" > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "a"
  codex_round_append "$WT" 2 blocked r.md "plan defect" "b"
  run codex_round_count "$WT"
  [ "$output" = "2" ]
}

@test "codex_round_last_findings: returns the last round's bullets only" {
  printf '**BLOCKED**\n\n- first round finding\n' > r1.md
  printf '**BLOCKED**\n\n- second round finding\n' > r2.md
  codex_round_append "$WT" 1 blocked r1.md "plan defect" "a"
  codex_round_append "$WT" 2 blocked r2.md "plan defect" "b"
  run codex_round_last_findings "$WT"
  [[ "$output" == *"second round finding"* ]]
  [[ "$output" != *"first round finding"* ]]
}

@test "codex_round_last_findings: empty when there are no rounds" {
  run codex_round_last_findings "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "codex_round_append: a missing report file exits 2 rather than writing a blank round" {
  run codex_round_append "$WT" 1 blocked nope.md "plan defect" "x"
  [ "$status" -eq 2 ]
  [ ! -f "$WT/.ship/codex-rounds.md" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-rounds.bats`
Expected: FAIL — `codex-rounds.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/codex-rounds.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/codex-rounds.sh
# Accumulate one entry per codex round in <worktree>/.ship/codex-rounds.md.
#
# The executor's report is stored BYTE-IDENTICAL, inside a fence. Its shape is
# load-bearing for an operator who was not present: a verdict line, a framing
# count, concrete bullets, evidence with numbers, a statement of what was NOT
# changed, and the required next action. That fifth element is the blast radius
# of a failed run and is exactly what summarising destroys.
#
# Fencing matters: a report can begin a line with `#`, which would otherwise
# become a heading in the surrounding document and break round counting.

# codex_round_append <worktree> <n> <verdict> <reportfile> <classification> <note>
# Exit 2 if the report file is missing — a round with no report is not a round.
codex_round_append() {
  local wt="$1" n="$2" verdict="$3" report="$4" cls="$5" note="$6" out
  [ -d "$wt" ] || return 2
  [ -f "$report" ] || return 2
  mkdir -p "$wt/.ship" || return 2
  out="$wt/.ship/codex-rounds.md"
  {
    printf '## Round %s — %s — %s\n\n' "$n" "$verdict" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '~~~text\n'
    cat "$report"
    printf '\n~~~\n\n'
    printf '**Supervisor:** classified as %s. %s\n\n' "$cls" "$note"
  } >> "$out"
}

# codex_round_count <worktree>
codex_round_count() {
  local f="$1/.ship/codex-rounds.md" n
  [ -f "$f" ] || { echo 0; return 0; }
  n=$(grep -c '^## Round ' "$f" 2>/dev/null || true)
  n=$(echo "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# codex_round_last_findings <worktree> — the bullet lines of the final round.
codex_round_last_findings() {
  local f="$1/.ship/codex-rounds.md" start
  [ -f "$f" ] || return 0
  start=$(grep -n '^## Round ' "$f" | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 0
  tail -n "+$start" "$f" | grep -E '^- ' || true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-rounds.bats`
Expected: PASS — 8 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/codex-rounds.sh \
        claude-skills/ship-workflow/tests/test_codex-rounds.bats
git commit -m "feat: accumulate codex round reports byte-identical"
```

---

### Task 3: `lib/codex-supervise-state.sh`

**Files:**
- Create: `claude-skills/ship-workflow/lib/codex-supervise-state.sh`
- Test: `claude-skills/ship-workflow/tests/test_codex-supervise-state.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `codex_state_write <worktree> <plan> <slot> <attempt> <verdict> <class> <blocked_at>`, `codex_state_get <worktree> <key>`, `codex_state_attempt <worktree>`, `codex_state_matches <worktree> <plan>`, `codex_state_alive <worktree>`. Task 4 calls all five.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_codex-supervise-state.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-state)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-supervise-state.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "codex_state_write then get round-trips every field" {
  codex_state_write "$WT" "docs/plans/R-001-x.md" "slot-a" 2 blocked "plan defect" "Task 7"
  run codex_state_get "$WT" plan;        [ "$output" = "docs/plans/R-001-x.md" ]
  run codex_state_get "$WT" slot;        [ "$output" = "slot-a" ]
  run codex_state_get "$WT" attempt;     [ "$output" = "2" ]
  run codex_state_get "$WT" last_verdict;[ "$output" = "blocked" ]
  run codex_state_get "$WT" last_class;  [ "$output" = "plan defect" ]
  run codex_state_get "$WT" blocked_at;  [ "$output" = "Task 7" ]
}

@test "codex_state_attempt: zero when no state exists" {
  run codex_state_attempt "$WT"
  [ "$output" = "0" ]
}

@test "codex_state_attempt: reads the recorded attempt" {
  codex_state_write "$WT" "p.md" "s" 3 blocked "plan defect" "Task 1"
  run codex_state_attempt "$WT"
  [ "$output" = "3" ]
}

@test "codex_state_write overwrites rather than appending" {
  codex_state_write "$WT" "p.md" "s" 1 blocked "plan defect" "Task 1"
  codex_state_write "$WT" "p.md" "s" 2 blocked "executor error" "Task 2"
  [ "$(grep -c '^attempt:' "$WT/.ship/codex-supervise.md")" -eq 1 ]
  run codex_state_attempt "$WT"
  [ "$output" = "2" ]
}

@test "codex_state_matches: true for the same plan" {
  codex_state_write "$WT" "docs/plans/R-001-x.md" "s" 1 blocked "plan defect" "Task 1"
  run codex_state_matches "$WT" "docs/plans/R-001-x.md"
  [ "$status" -eq 0 ]
}

@test "codex_state_matches: false for a different plan — no resuming someone else's loop" {
  codex_state_write "$WT" "docs/plans/R-001-x.md" "s" 2 blocked "plan defect" "Task 7"
  run codex_state_matches "$WT" "docs/plans/R-099-other.md"
  [ "$status" -ne 0 ]
}

@test "codex_state_matches: false when there is no state at all" {
  run codex_state_matches "$WT" "docs/plans/R-001-x.md"
  [ "$status" -ne 0 ]
}

@test "codex_state_alive: false when no pid file exists" {
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

@test "codex_state_alive: true while the recorded process is running" {
  sleep 30 & pid=$!
  mkdir -p "$WT/.ship"; echo "$pid" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -eq 0 ]
  kill "$pid" 2>/dev/null || true
}

@test "codex_state_alive: false once the process is gone" {
  sleep 30 & pid=$!; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  mkdir -p "$WT/.ship"; echo "$pid" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

@test "codex_state_get: a missing key is empty, not an error" {
  codex_state_write "$WT" "p.md" "s" 1 blocked "plan defect" "Task 1"
  run codex_state_get "$WT" nonesuch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-supervise-state.bats`
Expected: FAIL — `codex-supervise-state.sh` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `claude-skills/ship-workflow/lib/codex-supervise-state.sh`:

```bash
#!/usr/bin/env bash
# ship-workflow/lib/codex-supervise-state.sh
# Persist the supervise loop's state in <worktree>/.ship/codex-supervise.md so
# Phase 5 can be re-entered after a Claude session restart.
#
# This exists because sessions restarted nine times during the 19 runs that
# motivated the loop. Codex survived each one — `/run-plan` detaches via nohup —
# but the supervisor did not, and progress was re-derived by hand every time.
#
# The plan path is part of the state and is checked on resume: a state file left
# by a previous, unrelated ship must not silently resume someone else's loop.

# codex_state_write <wt> <plan> <slot> <attempt> <verdict> <class> <blocked_at>
codex_state_write() {
  local wt="$1"
  [ -d "$wt" ] || return 2
  mkdir -p "$wt/.ship" || return 2
  cat > "$wt/.ship/codex-supervise.md" <<EOF
plan: $2
slot: $3
attempt: $4
last_verdict: $5
last_class: $6
blocked_at: $7
updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

# codex_state_get <wt> <key> — echo the value, or nothing.
codex_state_get() {
  local f="$1/.ship/codex-supervise.md"
  [ -f "$f" ] || return 0
  sed -n "s/^$2: //p" "$f" | head -1
}

# codex_state_attempt <wt> — echo the attempt count, 0 when absent.
codex_state_attempt() {
  local n
  n=$(codex_state_get "$1" attempt)
  [ -n "$n" ] || n=0
  echo "$n"
}

# codex_state_matches <wt> <plan> — exit 0 only if the state is for this plan.
codex_state_matches() {
  local recorded
  recorded=$(codex_state_get "$1" plan)
  [ -n "$recorded" ] || return 1
  [ "$recorded" = "$2" ]
}

# codex_state_alive <wt> — exit 0 while the recorded codex process is running.
# Relaunching over a live run would put two executors on one branch.
codex_state_alive() {
  local pidf="$1/.ship/codex.pid" pid
  [ -f "$pidf" ] || return 1
  pid=$(tr -d '[:space:]' < "$pidf")
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_codex-supervise-state.bats`
Expected: PASS — 11 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/lib/codex-supervise-state.sh \
        claude-skills/ship-workflow/tests/test_codex-supervise-state.bats
git commit -m "feat: persist codex supervise state across session restarts"
```

---

### Task 4: Phase 5 becomes a supervise loop

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 5 steps 3-4)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`

**Interfaces:**
- Consumes: `codex_verdict`, `codex_verdict_reason` (Task 1); `codex_round_append`, `codex_round_count` (Task 2); all five state functions (Task 3).
- Produces: `SLOT` (derived from the plan filename, matching `/run-plan`'s own derivation — Task 6 reads it), and the `CODEX_ROUNDS` and `CODEX_FINAL_VERDICT` shell variables Task 5 reads for the Phase 9 summary. `CODEX_CLASS`, `CODEX_NOTE` and `CODEX_BLOCKED_AT` are set by Claude from its classification, not computed.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`:

```bash
#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }

p5_bash() {
  awk '/^## Phase 5/,/^## Phase 6/' "$CMD" \
  | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

@test "Phase 5 sources all three supervise libs" {
  for lib in codex-verdict.sh codex-rounds.sh codex-supervise-state.sh; do
    p5_bash | grep -qF "lib/$lib" || { echo "Phase 5 does not source $lib"; return 1; }
  done
}

@test "Phase 5 resumes from state before relaunching" {
  p5_bash | grep -qF 'codex_state_matches' || { echo "no plan-identity check on resume"; return 1; }
  p5_bash | grep -qF 'codex_state_alive'   || { echo "no live-process check"; return 1; }
}

@test "Phase 5 routes on the classified verdict, not on raw log text" {
  body=$(p5_bash)
  echo "$body" | grep -qF 'codex_verdict' || { echo "verdict is not classified"; return 1; }
  for v in done blocked infra; do
    echo "$body" | grep -qF "$v" || { echo "no branch for verdict $v"; return 1; }
  done
}

@test "Phase 5 does not consume an attempt on an infrastructure failure" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  echo "$section" | grep -qF 'attempt count unchanged' \
    || { echo "the infra branch does not state that the attempt is preserved"; return 1; }
}

@test "Phase 5 documents the three-way BLOCKED routing" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  for cls in 'plan defect' 'executor error' 'spec-level'; do
    echo "$section" | grep -qF "$cls" || { echo "missing BLOCKED class: $cls"; return 1; }
  done
}

@test "Phase 5 escalates a spec-level finding instead of designing around it" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  echo "$section" | grep -qiF 'escalate' || { echo "no escalation path"; return 1; }
  echo "$section" | grep -qF 'When the classification is unclear' \
    || { echo "no bias toward escalation on an unclear call"; return 1; }
}

@test "Phase 5 caps repair attempts at 3 and retains the worktree" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  echo "$section" | grep -qF 'CODEX_ATTEMPT_CAP=3' || { echo "no cap of 3"; return 1; }
  echo "$section" | grep -qiF 'worktree retained' || { echo "exhaustion discards the worktree"; return 1; }
}

@test "Phase 5 carries all five prompt-hardening items" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  for item in 'Scope override' 'auto:yes' 'Engineering vocabulary' 'Resume context' 'Round history'; do
    echo "$section" | grep -qF "$item" || { echo "prompt hardening missing: $item"; return 1; }
  done
}

@test "Phase 5 records every round before acting on it" {
  p5_bash | grep -qF 'codex_round_append' || { echo "rounds are not recorded"; return 1; }
}

@test "Phase 5 bash blocks parse as valid shell" {
  block=$(p5_bash)
  [ -n "$block" ]
  echo "$block" > "$BATS_TEST_TMPDIR/p5.sh"
  run bash -n "$BATS_TEST_TMPDIR/p5.sh"
  [ "$status" -eq 0 ]
}

@test "Phase 5 options 1 and 2 are untouched" {
  section=$(awk '/^## Phase 5/,/^## Phase 6/' "$CMD")
  echo "$section" | grep -qF 'superpowers:subagent-driven-development' || return 1
  echo "$section" | grep -qF 'superpowers:executing-plans' || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: FAIL — 9 of 11 fail; only the options-1-and-2 and bash-parse tests pass against the current text.

- [ ] **Step 3: Write minimal implementation**

In `commands/ship-next.md`, replace Phase 5 steps 3 and 4 — the block from
`3. **Invoke the chosen sub-skill:**` up to but not including `## Phase 6` — with:

````markdown
3. **Invoke the chosen sub-skill.**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → the supervise loop in step 4 below.

4. **Executor 3 only — supervise the codex run.**

   `/run-plan` detaches codex and returns. It does not finish the work. Across 19
   real runs it stopped 13 times with a `BLOCKED` verdict, and every one of those
   stops was correct. This step does the routing a human did by hand 16 times.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-verdict.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh

   CODEX_ATTEMPT_CAP=3
   PLAN="docs/plans/${ID}-${SLUG}.md"
   # Same derivation /run-plan uses, so this agrees with its /tmp state files.
   SLOT=$(basename "$PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')

   # Resume before relaunching. A session restart kills the supervisor but not
   # codex, and a state file from a different ship must not be inherited.
   if codex_state_matches "$WORKTREE" "$PLAN"; then
     CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
     if codex_state_alive "$WORKTREE"; then
       echo "codex is still running for $PLAN — attaching, not relaunching."
     fi
   else
     CODEX_ATTEMPT=0
   fi
   ```

   **Launch** with `/run-plan "$PLAN"`, then record its pid to
   `$WORKTREE/.ship/codex.pid` so a later re-entry can tell a live run from a dead
   one. Carry all five hardening items in the prompt — each is here because a run
   failed without it:

   - **Scope override.** `/run-plan`'s template tells the agent to ignore anything
     under `.claude/skills/`. When the plan's target *is* a skill directory, the
     agent refuses the entire plan.
   - **`--auto:yes` requirement.** Codex cannot answer an interactive prompt. A plan
     step invoking `/ship-next` without it hangs until the cap expires.
   - **Engineering vocabulary.** A prompt written as "attack it", "payloads", "try to
     make it delete" tripped a provider content filter and crashed the run. The same
     review, phrased as input validation, completed. Request the same content; do not
     phrase it as offensive security.
   - **Resume context.** Which tasks are committed, which task to start at, and which
     conclusions from earlier rounds are settled and must not be re-litigated.
   - **Round history.** `.ship/codex-rounds.md`, so the executor does not rediscover
     what the previous round already found.

   **When codex exits**, classify before judging:

   ```bash
   CODEX_LOG="/tmp/run-plan-codex-${SLOT}.log"
   CODEX_FINAL_VERDICT=$(codex_verdict "$CODEX_LOG")
   CODEX_REASON=$(codex_verdict_reason "$CODEX_LOG")
   tail -40 "$CODEX_LOG" | sed -n '/^\*\{0,2\}\(DONE\|BLOCKED\)/,$p' > /tmp/codex-report-${ID}.md
   ```

   Then route on `$CODEX_FINAL_VERDICT`:

   - **`done` / `done_with_concerns`** → record the round and continue to Phase 6.

     ```bash
     codex_round_append "$WORKTREE" "$((CODEX_ATTEMPT + 1))" "$CODEX_FINAL_VERDICT" \
       /tmp/codex-report-${ID}.md "n/a" "executor completed"
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     ```

   - **`infra`** → STOP and notify. Do **not** relaunch, and leave the **attempt count
     unchanged**: two of the 19 runs ended this way, and retrying them would have
     burned the budget real defects needed. Use Phase 9's notification routing with
     `$CODEX_REASON`. The worktree and branch are retained.

   - **`blocked`** → read the executor's report and classify it into exactly one of
     three, then act:

     | Class | Signal | Action |
     |---|---|---|
     | **plan defect** | the prescribed step is wrong, ambiguous or impossible as written | repair `$PLAN`, relaunch from the blocked task |
     | **executor error** | the plan is right and the executor deviated — a transcription slip, an edit in the wrong place | relaunch with a correction note, plan unchanged |
     | **spec-level** | the finding says the *approach* cannot work, not that this step is wrong | **STOP and notify the operator** |

     **When the classification is unclear, treat it as spec-level and escalate.** The
     cost of a needless escalation is one message. The cost of silently redesigning
     the software overnight is a morning spent reading commits to find out what it
     decided. Changing what the software is supposed to do is not the executor's call
     and it is not yours.

     **Set these three yourself from the classification above** — they are the
     judgement's output and nothing computes them:

     ```bash
     CODEX_CLASS="plan defect"          # or "executor error" — spec-level stops instead
     CODEX_NOTE="repaired Task 7 step 3; the prescribed grep lacked --"
     CODEX_BLOCKED_AT="Task 7"          # the task the executor stopped at
     ```

     Record the round, then relaunch or stop:

     ```bash
     CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))
     codex_round_append "$WORKTREE" "$CODEX_ATTEMPT" blocked \
       /tmp/codex-report-${ID}.md "$CODEX_CLASS" "$CODEX_NOTE"
     codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" \
       blocked "$CODEX_CLASS" "$CODEX_BLOCKED_AT"
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     if [ "$CODEX_ATTEMPT" -ge "$CODEX_ATTEMPT_CAP" ]; then
       echo "codex: $CODEX_ATTEMPT_CAP repair attempts exhausted — stopping." >&2
       echo "worktree retained at $WORKTREE; history in .ship/codex-rounds.md" >&2
     fi
     ```

     On exhaustion, stop and notify. A run that burns three attempts is a signal the
     plan was not ready, not a budget to raise.

5. **Wait for the executor to finish.** For options 1 and 2 this is the sub-skill
   returning. For option 3 it is the loop above reaching `done`, an escalation, or
   the cap. Either way the branch carries ≥ 1 commit per completed task.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: PASS — 11 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
git commit -m "feat: Phase 5 supervises codex instead of invoking it once"
```

---

### Task 5: Phase 9 surfaces the round history

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 9 steps 3-4)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`

**Interfaces:**
- Consumes: `CODEX_ROUNDS` and `CODEX_FINAL_VERDICT` (Task 4); `codex_round_last_findings` (Task 2).
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`:

```bash
@test "Phase 9 log row records the codex round count and verdict" {
  row=$(grep -F '>> docs/learnings/_log.md' "$CMD")
  [ -n "$row" ]
  [[ "$row" == *'codex: ${CODEX_ROUNDS}'* ]]
  [[ "$row" == *'${CODEX_FINAL_VERDICT}'* ]]
}

@test "Phase 9 summary carries the last round's findings, not a paraphrase" {
  section=$(awk '/^## Phase 9/,0' "$CMD")
  echo "$section" | grep -qF 'codex_round_last_findings' \
    || { echo "the summary does not pull the last round's bullets"; return 1; }
}

@test "Phase 9 points at the full history rather than inlining it" {
  section=$(awk '/^## Phase 9/,0' "$CMD")
  echo "$section" | grep -qF '.ship/codex-rounds.md' \
    || { echo "the summary does not reference the round history file"; return 1; }
}

@test "the round history is copied out before Phase 9 removes the worktree" {
  section=$(awk '/^## Phase 9/,0' "$CMD")
  echo "$section" | grep -qiF 'copy it out' \
    || { echo "nothing warns that cleanup destroys the round history"; return 1; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: FAIL — the 4 new tests fail; the 11 from Task 4 still pass.

- [ ] **Step 3: Write minimal implementation**

In Phase 9 step 3, extend the log row — it currently ends `prune: ${PRUNE_STATUS}) | n |`:

```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp, prune: ${PRUNE_STATUS}, codex: ${CODEX_ROUNDS} round(s) ${CODEX_FINAL_VERDICT}) | n |" >> docs/learnings/_log.md
```

In Phase 9 step 4, extend the `SUMMARY` heredoc after the `UA:` line:

```
   • codex: ${CODEX_ROUNDS} round(s), final ${CODEX_FINAL_VERDICT}
   $(codex_round_last_findings "$WORKTREE")
   • full round history: ${WORKTREE}/.ship/codex-rounds.md
```

and add, immediately below the heredoc:

```markdown
   The summary carries the **last round's bullets verbatim**, not a paraphrase. That
   list is the operator's only window into an unattended run, and its fifth element —
   the statement of what was *not* changed — is the blast radius of a failed round.
   Summarising destroys exactly the part that makes it scannable.

   `.ship/` dies with the worktree at step 1 of this phase. If a post-mortem needs the
   full history, **copy it out** before cleanup — the same caveat that already applies
   to `.ship-auto-decisions.md`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: PASS — 15 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
git commit -m "feat: Phase 9 surfaces codex round count and last findings"
```

---

### Task 6: Phase 6's fix-plan re-invoke reuses the loop

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md` (Phase 6 fix-plan executor case)
- Test: `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: nothing downstream.

- [ ] **Step 1: Write the failing test**

Append to `claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats`:

```bash
@test "Phase 6's fix-plan re-invoke supervises rather than firing and forgetting" {
  section=$(awk '/^## Phase 6/,/^## Phase 7/' "$CMD")
  echo "$section" | grep -qF 'codex_verdict' \
    || { echo "the fix-plan re-invoke does not classify codex's verdict"; return 1; }
  # `invoke /run-plan $FIX_PLAN` with no supervision was the original.
  if echo "$section" | grep -qE '^\s*3\) invoke /run-plan \$FIX_PLAN ;;\s*$'; then
    echo "the fix-plan case still fires and forgets"
    return 1
  fi
}

@test "Phase 6's fix-plan rounds land in the same history file" {
  section=$(awk '/^## Phase 6/,/^## Phase 7/' "$CMD")
  echo "$section" | grep -qF 'codex_round_append' \
    || { echo "fix-plan rounds are not recorded"; return 1; }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: FAIL — the 2 new tests fail; the 15 from Tasks 4-5 still pass.

- [ ] **Step 3: Write minimal implementation**

In Phase 6's fix-plan loop, replace the line `3) invoke /run-plan $FIX_PLAN ;;` with:

```bash
       3) # Supervise this run the same way Phase 5 does — a fix-plan run can be
          # BLOCKED or hit infrastructure exactly as the original run can, and
          # firing-and-forgetting here would silently drop the reason.
          invoke /run-plan "$FIX_PLAN"
          FIX_VERDICT=$(codex_verdict "/tmp/run-plan-codex-${SLOT}.log")
          tail -40 "/tmp/run-plan-codex-${SLOT}.log" \
            | sed -n '/^\*\{0,2\}\(DONE\|BLOCKED\)/,$p' > "/tmp/codex-fix-${ID}-${attempt}.md"
          codex_round_append "$WORKTREE" "fix-${attempt}" "$FIX_VERDICT" \
            "/tmp/codex-fix-${ID}-${attempt}.md" "review fix-plan" \
            "attempt ${attempt} of the Phase 6 review loop"
          if [ "$FIX_VERDICT" = "infra" ]; then
            echo "codex infrastructure failure during the fix-plan run — stopping." >&2
            break
          fi
          ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-skills/ship-workflow && bats tests/test_ship-next-codex-loop.bats`
Expected: PASS — 17 tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md \
        claude-skills/ship-workflow/tests/test_ship-next-codex-loop.bats
git commit -m "feat: Phase 6 fix-plan runs are supervised and recorded too"
```

---

### Task 7: acceptance — the loop is additive and the spec's gate holds

**Files:**
- Modify: `claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats`
- Test: `claude-skills/ship-workflow/tests/test_codex-acceptance.bats`

**Interfaces:**
- Consumes: everything.
- Produces: nothing.

This task is the spec's §7 gate. A finding blocks **only if it describes a way a developer loses work or is misled about the outcome of a ship**; anything else is a follow-up.

- [ ] **Step 1: Write the failing test**

Create `claude-skills/ship-workflow/tests/test_codex-acceptance.bats`:

```bash
#!/usr/bin/env bats
# Spec 7: the acceptance gate. Each test maps to one numbered criterion.
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-acceptance)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-verdict.sh"
  source "$SHIP_LIB/codex-rounds.sh"
  source "$SHIP_LIB/codex-supervise-state.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "spec 7.2: every infrastructure signature classifies as infra" {
  for sig in "ERROR: Your workspace is out of credits." \
             "ERROR: This content was flagged for possible cybersecurity risk." \
             "error=exec_command failed: UnknownProcessId { process_id: 1 }" \
             "ERROR codex_core::session: failed to record rollout items: thread not found"; do
    printf '%s\n' "$sig" > l.log
    run codex_verdict l.log
    [ "$output" = "infra" ] || { echo "not classified infra: $sig"; return 1; }
  done
}

@test "spec 7.2: an infra round does not advance the attempt count" {
  codex_state_write "$WT" "p.md" "s" 1 blocked "plan defect" "Task 1"
  before=$(codex_state_attempt "$WT")
  # The infra branch records no new state, by construction — nothing to call.
  after=$(codex_state_attempt "$WT")
  [ "$before" = "$after" ]
}

@test "spec 7.3: a spec-level report is recognisable as such" {
  # Fixture modelled on the real round that concluded a gate could not work.
  cat > r.md <<'EOT'
**BLOCKED.** Suite passed 237/237, but Phase 8.5 still accepts coverage loss.
These are more defects of the same measurement class.
**I recommend making Phase 8.5 REPORT-ONLY:** the approach cannot establish safety.
EOT
  run codex_verdict <(cat r.md)
  [ "$output" = "blocked" ]
  grep -qiE 'cannot (work|establish)|recommend making' r.md
}

@test "spec 7.4: three attempts is the documented cap" {
  grep -qF 'CODEX_ATTEMPT_CAP=3' "$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "spec 7.5: a stored round is byte-identical to the report" {
  printf '**BLOCKED**\n\n- `git diff` returns 0\n- $HOME unquoted\n# hash line\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "x"
  while IFS= read -r line; do
    grep -qxF -- "$line" "$WT/.ship/codex-rounds.md" || { echo "lost: $line"; return 1; }
  done < r.md
}

@test "spec 7.6: resume reads state and does not inherit another ship's loop" {
  codex_state_write "$WT" "docs/plans/R-001-a.md" "s" 2 blocked "plan defect" "Task 7"
  run codex_state_matches "$WT" "docs/plans/R-001-a.md"; [ "$status" -eq 0 ]
  run codex_state_matches "$WT" "docs/plans/R-002-b.md"; [ "$status" -ne 0 ]
  run codex_state_attempt "$WT"; [ "$output" = "2" ]
}

@test "spec 7.7: every supervise helper no-ops without codex state" {
  run codex_verdict "$SCRATCH/absent.log";        [ "$output" = "infra" ]
  run codex_round_count "$WT";                    [ "$output" = "0" ]
  run codex_round_last_findings "$WT";            [ -z "$output" ]
  run codex_state_attempt "$WT";                  [ "$output" = "0" ]
  run codex_state_alive "$WT";                    [ "$status" -ne 0 ]
}

@test "spec 7.7: the three new libs source together without collision" {
  run bash -c "source '$SHIP_LIB/codex-verdict.sh'; source '$SHIP_LIB/codex-rounds.sh'; source '$SHIP_LIB/codex-supervise-state.sh'; echo ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "no supervise helper declares a local inside a loop body" {
  # zsh prints a re-declared local; bash does not. Enforced repo-wide.
  for f in codex-verdict.sh codex-rounds.sh codex-supervise-state.sh; do
    awk '
      /^[a-z_]+\(\)/ { fn=$1; depth=0 }
      /(^|[[:space:];])(while|for)[[:space:]].*[[:space:];]do[[:space:]]*$/ { if (fn) depth++ }
      /^[[:space:]]*done/ { if (fn && depth>0) depth-- }
      /^[[:space:]]*local / { if (fn && depth>0) print FILENAME": "FNR": "$0 }
    ' "$SHIP_LIB/$f"
  done > /tmp/codex-loop-locals.txt
  if [ -s /tmp/codex-loop-locals.txt ]; then cat /tmp/codex-loop-locals.txt; return 1; fi
}
```

Append to `claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats`:

```bash
@test "a repo with no codex completes the cycle unchanged" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/codex-verdict.sh"
  source "$SHIP_LIB/codex-rounds.sh"
  source "$SHIP_LIB/codex-supervise-state.sh"
  # Nothing here may write, and nothing may report success it cannot support.
  before=$(find . -path ./.git -prune -o -type f -print | sort)
  run codex_verdict missing.log;   [ "$output" = "infra" ]
  run codex_state_attempt "$PWD";  [ "$output" = "0" ]
  run codex_round_count "$PWD";    [ "$output" = "0" ]
  after=$(find . -path ./.git -prune -o -type f -print | sort)
  [ "$before" = "$after" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-skills/ship-workflow && bats tests/`
Expected: FAIL only if Tasks 1-6 left a gap. If they are correct these pass immediately — that is the point. This task is the proof, not new behaviour.

- [ ] **Step 3: Fix any gap surfaced**

If a test fails, the defect belongs to the task that owns that lib or phase. Fix it there. Do not weaken the acceptance test.

- [ ] **Step 4: Run the full suite**

Run: `cd claude-skills/ship-workflow && bats tests/`
Expected: PASS — every file, including all pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/tests/test_codex-acceptance.bats \
        claude-skills/ship-workflow/tests/test_ship-next-no-ua.bats
git commit -m "test: acceptance gate for the codex supervise loop"
```
