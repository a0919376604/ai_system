#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch roadmap-insert)"
  export AIROS="$(make_fake_airos "$SCRATCH" "demo")"
  export ROADMAP="$AIROS/10 Projects/demo/ROADMAP.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "roadmap-insert: appends to empty Now section" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-018 "Fix langfuse leak"
  grep -q "R-018" "$ROADMAP"
  # Confirm it's between the Now heading and the Next heading
  now_ln=$(grep -n "^## 🔥 Now" "$ROADMAP" | head -1 | cut -d: -f1)
  r018_ln=$(grep -n "R-018" "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$(grep -n "^## 🔜" "$ROADMAP" | head -1 | cut -d: -f1)
  [ "$now_ln" -lt "$r018_ln" ]
  [ "$r018_ln" -lt "$next_ln" ]
}

@test "roadmap-insert: marks adhoc-inserted=true" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-019 "Quick fix" --adhoc
  grep -q "adhoc-inserted=true" "$ROADMAP"
}

@test "roadmap-insert: skips adhoc marker when --adhoc absent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-020 "Planned work"
  ! awk '/R-020/' "$ROADMAP" | grep -q "adhoc-inserted=true"
}

@test "roadmap-insert: preserves existing Now items" {
  # Pre-populate
  sed -i.bak '/^## 🔥 Now/a\
- [ ] **R-001** Existing item' "$ROADMAP" && rm "$ROADMAP.bak"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-002 "New item"
  grep -q "R-001" "$ROADMAP"
  grep -q "R-002" "$ROADMAP"
}

@test "roadmap-insert: writes atomically (no .tmp left)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-021 "Atomic test"
  ! ls "$AIROS/10 Projects/demo/"*.tmp 2>/dev/null
}

@test "roadmap-insert: errors when ROADMAP.md missing" {
  run "$SHIP_LIB/roadmap-insert.sh" "$AIROS/nonexistent/ROADMAP.md" R-099 "x"
  [ "$status" -ne 0 ]
}

@test "roadmap-insert: errors when no Now heading found" {
  echo "no headings here" > "$ROADMAP"
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-099 "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Now"* ]]
}

@test "roadmap-insert: --epic adds (epic) marker" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  grep -q '\*\*R-014 (epic)\*\*' "$ROADMAP"
}

@test "roadmap-insert: --child inserts indented child under parent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Backoff layer" --child R-014
  # Child appears after parent
  parent_ln=$(grep -n 'R-014 (epic)' "$ROADMAP" | head -1 | cut -d: -f1)
  child_ln=$(grep -n 'R-014\.1' "$ROADMAP" | head -1 | cut -d: -f1)
  [ "$child_ln" -gt "$parent_ln" ]
  # Child is indented (starts with 2 spaces)
  grep -E '^  - \[ \] \*\*R-014\.1\*\*' "$ROADMAP"
}

@test "roadmap-insert: --child errors if parent not found" {
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Orphan" --child R-099
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent R-099 not found"* ]]
}

@test "roadmap-insert: --mark-warning adds ⚠️ + flagged annotation" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "touches 3 modules"
  grep -q '⚠️ \*\*R-014\*\*' "$ROADMAP"
  grep -q 'flagged: touches 3 modules' "$ROADMAP"
}

@test "roadmap-insert: --mark-warning idempotent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "reason 1"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "reason 2"
  warning_count=$(grep -c '⚠️ \*\*R-014\*\*' "$ROADMAP")
  [ "$warning_count" -eq 1 ]
}

@test "roadmap-insert: --mark-epic strips ⚠️ + adds (epic)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "too big"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-epic
  # ⚠️ gone, (epic) present
  ! grep -q '⚠️' "$ROADMAP"
  grep -q '\*\*R-014 (epic)\*\*' "$ROADMAP"
  # flagged annotation also gone
  ! grep -q 'flagged:' "$ROADMAP"
}
