#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch id-gen)"
  export REPO="$(make_fake_repo "$SCRATCH")"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "id-gen: returns IDEA-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" idea)"
  [ "$result" = "IDEA-001" ]
}

@test "id-gen: returns D-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" decision)"
  [ "$result" = "D-001" ]
}

@test "id-gen: returns R-001 in empty repo" {
  cd "$REPO"
  result="$("$SHIP_LIB/id-gen.sh" roadmap)"
  [ "$result" = "R-001" ]
}

@test "id-gen: returns next IDEA after existing" {
  cd "$REPO"
  touch docs/ideas/IDEA-005-foo.md
  touch docs/ideas/IDEA-002-bar.md
  result="$("$SHIP_LIB/id-gen.sh" idea)"
  [ "$result" = "IDEA-006" ]
}

@test "id-gen: returns next D after existing" {
  cd "$REPO"
  touch docs/decisions/D-003-xyz.md
  result="$("$SHIP_LIB/id-gen.sh" decision)"
  [ "$result" = "D-004" ]
}

@test "id-gen: returns next R across all R-NNN folders" {
  cd "$REPO"
  touch docs/brainstorms/R-007-a.md
  touch docs/specs/R-009-b.md
  touch docs/plans/R-002-c.md
  result="$("$SHIP_LIB/id-gen.sh" roadmap)"
  [ "$result" = "R-010" ]
}

@test "id-gen: errors on unknown type" {
  cd "$REPO"
  run "$SHIP_LIB/id-gen.sh" bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown type"* ]]
}

@test "id-gen: serializes concurrent invocations (no duplicates)" {
  cd "$REPO"
  # Spawn 5 concurrent calls
  for i in 1 2 3 4 5; do
    "$SHIP_LIB/id-gen.sh" idea --reserve > "$REPO/.tmp-$i" &
  done
  wait
  # Collect outputs; expect 5 unique IDEA-NNN values
  ids=$(cat "$REPO"/.tmp-* | sort -u | wc -l | tr -d ' ')
  [ "$ids" -eq 5 ]
}
