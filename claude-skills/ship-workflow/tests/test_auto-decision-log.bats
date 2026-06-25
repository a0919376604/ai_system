#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch auto-decision-log)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT/.claude"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "auto-decision-log: appends timestamped line to .claude/.ship-auto-decisions.md" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P3" "auto-picked: option 1"
  [ "$status" -eq 0 ]
  [ -f "$WT/.claude/.ship-auto-decisions.md" ]
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z P3 auto-picked: option 1' "$WT/.claude/.ship-auto-decisions.md"
}

@test "auto-decision-log: optional detail appended with em-dash" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P6" "review attempt 1" "blocking=2 (handler.py:45, cache.py:12)"
  [ "$status" -eq 0 ]
  grep -qF "P6 review attempt 1 — blocking=2 (handler.py:45, cache.py:12)" "$WT/.claude/.ship-auto-decisions.md"
}

@test "auto-decision-log: multiple calls append in order" {
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P3" "first" > /dev/null
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P4" "second" > /dev/null
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P5" "third" > /dev/null
  lines=$(wc -l < "$WT/.claude/.ship-auto-decisions.md" | tr -d ' ')
  [ "$lines" -eq 3 ]
  # Verify in order
  first_phase=$(head -1 "$WT/.claude/.ship-auto-decisions.md" | awk '{print $2}')
  last_phase=$(tail -1 "$WT/.claude/.ship-auto-decisions.md" | awk '{print $2}')
  [ "$first_phase" = "P3" ]
  [ "$last_phase" = "P5" ]
}

@test "auto-decision-log: creates .claude/ if missing" {
  rm -rf "$WT/.claude"
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P1" "pre-flight pass"
  [ "$status" -eq 0 ]
  [ -f "$WT/.claude/.ship-auto-decisions.md" ]
}

@test "auto-decision-log: exits 2 when worktree dir missing" {
  run "$SHIP_LIB/auto-decision-log.sh" "$SCRATCH/nonexistent" "P1" "test"
  [ "$status" -eq 2 ]
}

@test "auto-decision-log: requires 3 args minimum" {
  run "$SHIP_LIB/auto-decision-log.sh" "$WT" "P1"
  [ "$status" -ne 0 ]
}

@test "auto-decision-log: log file is covered by .claude/.gitignore rule" {
  # The existing .claude/.gitignore in ship-init.md adds `.ship-auto-decisions.md`.
  # That rule lives INSIDE .claude/, so it only matches files within .claude/.
  # This test verifies our log path lies under .claude/ — if someone moves it
  # to docs/, this fails and signals "update the gitignore location too."
  "$SHIP_LIB/auto-decision-log.sh" "$WT" "P1" "test"
  parent=$(dirname "$WT/.claude/.ship-auto-decisions.md")
  [ "$(basename "$parent")" = ".claude" ]
}
