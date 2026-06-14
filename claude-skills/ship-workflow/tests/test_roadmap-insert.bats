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
