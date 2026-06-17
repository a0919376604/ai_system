#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch sync)"
  export AIROS="$(make_fake_airos "$SCRATCH" "test-repo")"
  export REPO="$(make_fake_repo "$SCRATCH")"
  mv "$REPO" "$SCRATCH/test-repo"
  export REPO="$SCRATCH/test-repo"
  export HOME_OVERRIDE="$SCRATCH/home"
  write_global_config "$HOME_OVERRIDE" "$AIROS"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "sync: copies 4 strategy files to docs/product/" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ -f "$REPO/docs/product/VISION.md" ]
  [ -f "$REPO/docs/product/STRATEGY.md" ]
  [ -f "$REPO/docs/product/ROADMAP.md" ]
  [ -f "$REPO/docs/product/QUARTERLY_GOALS.md" ]
}

@test "sync: writes .ship-last-pull timestamp" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ -f "$REPO/.claude/.ship-last-pull" ]
}

@test "sync: skips when within freshness window" {
  cd "$REPO"
  # First sync
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  # Modify AIR-OS source
  echo "MODIFIED" >> "$AIROS/10 Projects/test-repo/ROADMAP.md"
  # Second sync within window — should NOT pick up the change
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  ! grep -q "MODIFIED" "$REPO/docs/product/ROADMAP.md"
}

@test "sync: re-syncs when window expired" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  echo "MODIFIED" >> "$AIROS/10 Projects/test-repo/ROADMAP.md"
  # Backdate last-pull beyond freshness window (60s default)
  touch -t "$(date -v-2M +%Y%m%d%H%M)" "$REPO/.claude/.ship-last-pull"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  grep -q "MODIFIED" "$REPO/docs/product/ROADMAP.md"
}

@test "sync: warns but does not abort when an AIR-OS file is missing" {
  rm "$AIROS/10 Projects/test-repo/QUARTERLY_GOALS.md"
  cd "$REPO"
  run env HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUARTERLY_GOALS.md not found"* ]]
}

@test "sync: uses atomic write (no half-written files on race)" {
  cd "$REPO"
  HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh"
  # After sync no .tmp files should remain
  ! ls "$REPO/docs/product/"*.tmp 2>/dev/null
}

@test "sync: mirrors Roadmap-Notes/ to docs/roadmap-notes/" {
  notes_src="$AIROS/10 Projects/test-repo/Roadmap-Notes"
  mkdir -p "$notes_src"
  cat > "$notes_src/R-001-foo.md" <<'EOF'
---
type: roadmap-note
id: R-001
---
Test note.
EOF
  cd "$REPO" && HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh" --force
  [ -f "$REPO/docs/roadmap-notes/R-001-foo.md" ]
  grep -q "Test note." "$REPO/docs/roadmap-notes/R-001-foo.md"
}

@test "sync: Roadmap-Notes mirror uses atomic write (no .tmp leftover)" {
  notes_src="$AIROS/10 Projects/test-repo/Roadmap-Notes"
  mkdir -p "$notes_src"
  echo "x" > "$notes_src/R-002-bar.md"
  cd "$REPO" && HOME="$HOME_OVERRIDE" "$SHIP_LIB/sync.sh" --force
  ! ls "$REPO/docs/roadmap-notes/"*.tmp 2>/dev/null
}
