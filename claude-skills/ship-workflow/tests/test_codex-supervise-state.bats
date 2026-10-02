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
  # The matcher is the seam: a test cannot launch codex, so it pins the match to
  # the program it did launch. Production leaves it at the default, "codex".
  export CODEX_STATE_PROCESS_MATCH=sleep
  sleep 30 & pid=$!
  mkdir -p "$WT/.ship"; echo "$pid" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -eq 0 ]
  kill "$pid" 2>/dev/null || true
}

@test "codex_state_alive: false once the process is gone" {
  export CODEX_STATE_PROCESS_MATCH=sleep
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

# --- Ruling 3: a pid must be a positive integer before kill -0 sees it --------
# `kill -0 -1` and `kill -0 0` exit 0 on macOS: they are process-GROUP queries.
# Either would make the supervisor believe codex is running forever and wait on
# a process that does not exist.

@test "codex_state_alive: a pid of -1 is not alive (process-group query)" {
  mkdir -p "$WT/.ship"; echo "-1" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

@test "codex_state_alive: a pid of 0 is not alive (own process group)" {
  mkdir -p "$WT/.ship"; echo "0" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

@test "codex_state_alive: a non-numeric pid file is not alive" {
  mkdir -p "$WT/.ship"; echo "not-a-pid" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

@test "codex_state_alive: an empty pid file is not alive" {
  mkdir -p "$WT/.ship"; : > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
}

# --- Ruling 4: a live pid that is not codex is a recycled pid ----------------

@test "codex_state_alive: a live pid running a different program is not alive" {
  # Resume happens minutes-to-hours after the pid was recorded and macOS
  # recycles pids in that window. Default matcher ("codex") vs a live sleep.
  sleep 30 & pid=$!
  mkdir -p "$WT/.ship"; echo "$pid" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -ne 0 ]
  kill "$pid" 2>/dev/null || true
}

# --- Ruling 5: a value cannot forge another field ----------------------------

@test "codex_state_write: a multi-line value cannot forge another field" {
  codex_state_write "$WT" "docs/plans/R-001-x.md" "s" 1 blocked "plan defect" \
    "Task 7
attempt: 99
plan: docs/plans/R-099-other.md"
  # Exactly one of each field, despite the injected lines.
  [ "$(grep -c '^attempt:' "$WT/.ship/codex-supervise.md")" -eq 1 ]
  [ "$(grep -c '^plan:'    "$WT/.ship/codex-supervise.md")" -eq 1 ]
  run codex_state_attempt "$WT"
  [ "$output" = "1" ]
  # The real plan still matches, and the injected one does not.
  run codex_state_matches "$WT" "docs/plans/R-001-x.md"
  [ "$status" -eq 0 ]
  run codex_state_matches "$WT" "docs/plans/R-099-other.md"
  [ "$status" -ne 0 ]
}

@test "codex_state_write: a missing worktree exits 2 rather than writing" {
  run codex_state_write "$SCRATCH/nope" "p.md" "s" 1 blocked "plan defect" "Task 1"
  [ "$status" -eq 2 ]
  [ ! -f "$SCRATCH/nope/.ship/codex-supervise.md" ]
}

# --- codex_wait_for_exit -----------------------------------------------------

@test "codex_wait_for_exit: returns immediately when no pid file exists" {
  run codex_wait_for_exit "$WT/.ship/absent.pid" 1
  [ "$status" -eq 0 ]
}

@test "codex_wait_for_exit: returns once the process is gone" {
  mkdir -p "$WT/.ship"
  sleep 30 & pid=$!
  echo "$pid" > "$WT/.ship/w.pid"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  run codex_wait_for_exit "$WT/.ship/w.pid" 1
  [ "$status" -eq 0 ]
}

@test "codex_wait_for_exit: does not spin forever on a malformed pid" {
  # Without validation, a pid file of -1 makes kill -0 succeed forever.
  mkdir -p "$WT/.ship"
  for bad in "-1" "0" "garbage"; do
    echo "$bad" > "$WT/.ship/w.pid"
    run timeout 5 bash -c "source '$SHIP_LIB/codex-supervise-state.sh'; codex_wait_for_exit '$WT/.ship/w.pid' 1"
    [ "$status" -eq 0 ] || { echo "hung or failed on pid '$bad' (status $status)"; return 1; }
  done
}

@test "codex_wait_for_exit: actually blocks while the process is alive" {
  mkdir -p "$WT/.ship"
  sleep 2 & pid=$!
  echo "$pid" > "$WT/.ship/w.pid"
  start=$(date +%s)
  codex_wait_for_exit "$WT/.ship/w.pid" 1
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -ge 1 ] || { echo "returned in ${elapsed}s — it did not wait"; return 1; }
  kill "$pid" 2>/dev/null || true
}
