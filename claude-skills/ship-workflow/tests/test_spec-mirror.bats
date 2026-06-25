#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch spec-mirror)"
  export SRC="$SCRATCH/src/docs/specs/R-001.3-wire-scene-engine.md"
  export DST="$SCRATCH/dst/Specs/R-001.3-wire-scene-engine.md"
  mkdir -p "$(dirname "$SRC")"
  cat > "$SRC" <<'EOF'
---
date: 2026-06-22
type: spec
status: draft
id: R-001.3
tags: [spec]
ai-first: true
---

## For future Claude
> Test spec body.

## §1 Problem
Spec body content goes here.
EOF
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "spec-mirror: writes destination file with body preserved" {
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  [ "$status" -eq 0 ]
  [ -f "$DST" ]
  grep -q "## §1 Problem" "$DST"
  grep -q "Spec body content goes here." "$DST"
}

@test "spec-mirror: injects mirror-source key inside frontmatter" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  grep -qF "mirror-source: $SRC" "$DST"
  # Verify it's INSIDE frontmatter (between the two --- lines), not in body
  awk '
    /^---$/ { fm++ ; next }
    fm == 1 && /^mirror-source:/ { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$DST"
}

@test "spec-mirror: idempotent — running twice produces same content" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  cp "$DST" "$DST.first"
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  diff -q "$DST" "$DST.first"
  # Verify only ONE mirror-source: line
  count=$(grep -c "^mirror-source:" "$DST")
  [ "$count" -eq 1 ]
}

@test "spec-mirror: idempotent on src that already has mirror-source" {
  # Pre-seed src with the key
  sed -i.bak '/^ai-first: true$/a\
mirror-source: docs/specs/R-001.3-wire-scene-engine.md' "$SRC" && rm "$SRC.bak"
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  count=$(grep -c "^mirror-source:" "$DST")
  [ "$count" -eq 1 ]
}

@test "spec-mirror: creates parent dir via mkdir -p" {
  nested="$SCRATCH/dst/deeply/nested/Specs/R-001.3-x.md"
  rm -rf "$SCRATCH/dst/deeply"
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$nested"
  [ "$status" -eq 0 ]
  [ -f "$nested" ]
}

@test "spec-mirror: atomic write — no .tmp leftover on success" {
  "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  ! ls "$DST.tmp" 2>/dev/null
}

@test "spec-mirror: exits 2 when src doesn't exist" {
  run "$SHIP_LIB/spec-mirror.sh" "$SCRATCH/nonexistent.md" "$DST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "spec-mirror: exits 1 (or non-zero) when fewer than 2 args" {
  run "$SHIP_LIB/spec-mirror.sh" "$SRC"
  [ "$status" -ne 0 ]
}

@test "spec-mirror: src without frontmatter is copied as-is" {
  cat > "$SRC" <<'EOF'
# Plain markdown without frontmatter

Some content.
EOF
  run "$SHIP_LIB/spec-mirror.sh" "$SRC" "$DST"
  [ "$status" -eq 0 ]
  # mirror-source NOT injected (no frontmatter to inject into)
  ! grep -q "^mirror-source:" "$DST"
  # Body content still copied
  grep -q "Some content." "$DST"
}
