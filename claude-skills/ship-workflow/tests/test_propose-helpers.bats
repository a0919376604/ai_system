#!/usr/bin/env bats

load helpers

HELPER="${BATS_TEST_DIRNAME}/../lib/propose-helpers.sh"

setup() {
  TMPDIR_TEST=$(mktemp -d)
  ROADMAP="$TMPDIR_TEST/ROADMAP.md"
  PROPDIR="$TMPDIR_TEST/Proposals"
  mkdir -p "$PROPDIR"
  cat > "$ROADMAP" <<'EOF'
---
type: roadmap
---

## 🔥 Now (3-5 items)
- [ ] **R-001** Story generation · effort=L · confidence=high · status=in-progress

## 🔜 Next
- [ ] **R-002** Unify bracket guard · effort=S · confidence=high
- [ ] **R-003** Provider error classify · effort=S · confidence=high

## 🕐 Later
- [ ] **R-005** Split dialogue.py · effort=L · confidence=high

## ✅ Done
- [x] **R-000** Bootstrap · ✅ 2026-06-14
EOF
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "list-roadmap-items skips Done section" {
  run "$HELPER" list-roadmap-items "$ROADMAP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Now"$'\t'"R-001"* ]]
  [[ "$output" == *"Next"$'\t'"R-002"* ]]
  [[ "$output" == *"Later"$'\t'"R-005"* ]]
  [[ "$output" != *"R-000"* ]]
}

@test "list-active-proposals returns empty when dir empty" {
  run "$HELPER" list-active-proposals "$PROPDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "list-active-proposals filters by status" {
  cat > "$PROPDIR/p1.md" <<'EOF'
---
roadmap-id: R-001
status: accepted
---
EOF
  cat > "$PROPDIR/p2.md" <<'EOF'
---
roadmap-id: R-002
status: shelved
---
EOF
  cat > "$PROPDIR/p3.md" <<'EOF'
---
roadmap-id: R-003
status: draft
---
EOF
  run "$HELPER" list-active-proposals "$PROPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"R-001"* ]]
  [[ "$output" == *"R-003"* ]]
  [[ "$output" != *"R-002"* ]]
}

@test "next-item picks first Now item with no active proposal" {
  run "$HELPER" next-item "$ROADMAP" "$PROPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == "Now"$'\t'"R-001"$'\t'* ]]
}

@test "next-item skips items with active proposals" {
  cat > "$PROPDIR/p1.md" <<'EOF'
---
roadmap-id: R-001
status: accepted
---
EOF
  run "$HELPER" next-item "$ROADMAP" "$PROPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == "Next"$'\t'"R-002"$'\t'* ]]
}

@test "next-item falls through to Later" {
  cat > "$PROPDIR/p1.md" <<'EOF'
---
roadmap-id: R-001
status: accepted
---
EOF
  cat > "$PROPDIR/p2.md" <<'EOF'
---
roadmap-id: R-002
status: draft
---
EOF
  cat > "$PROPDIR/p3.md" <<'EOF'
---
roadmap-id: R-003
status: in-review
---
EOF
  run "$HELPER" next-item "$ROADMAP" "$PROPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == "Later"$'\t'"R-005"$'\t'* ]]
}

@test "classify-size: S+high → skip" {
  run "$HELPER" classify-size S high
  [ "$status" -eq 0 ]
  [ "$output" = "skip" ]
}

@test "classify-size: L+anything → L" {
  run "$HELPER" classify-size L high
  [ "$output" = "L" ]
}

@test "classify-size: M+medium → M" {
  run "$HELPER" classify-size M medium
  [ "$output" = "M" ]
}

@test "classify-size: defaults to M when unknown" {
  run "$HELPER" classify-size unknown unknown
  [ "$output" = "M" ]
}

@test "slugify lowercases and kebabs" {
  run "$HELPER" slugify "Split Dialogue and Main"
  [ "$output" = "split-dialogue-and-main" ]
}

@test "slugify caps at 6 words" {
  run "$HELPER" slugify "one two three four five six seven eight"
  [ "$output" = "one-two-three-four-five-six" ]
}

@test "proposal-filename builds canonical name" {
  run "$HELPER" proposal-filename 2026-06-15 R-001 story-generation
  [ "$output" = "2026-06-15-R-001-story-generation-proposal.md" ]
}
