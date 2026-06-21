#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch code-review-parse)"
  export FIXTURE="$SHIP_SKILL_ROOT/tests/fixtures/code-review-output.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "code-review-parse: emits all 4 counts" {
  run "$SHIP_LIB/code-review-parse.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
  [[ "$output" == *"MAJOR_COUNT=2"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
  [[ "$output" == *"PRAISE_COUNT=3"* ]]
}

@test "code-review-parse: output is eval-safe (caller can source it)" {
  run bash -c "eval \"\$('$SHIP_LIB/code-review-parse.sh' '$FIXTURE')\" && echo \"\$BLOCKING_COUNT|\$MAJOR_COUNT|\$MINOR_COUNT|\$PRAISE_COUNT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"2|2|2|3"* ]]
}

@test "code-review-parse: zero counts on empty file" {
  empty="$SCRATCH/empty.md"
  echo "# nothing to see here" > "$empty"
  run "$SHIP_LIB/code-review-parse.sh" "$empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=0"* ]]
  [[ "$output" == *"MAJOR_COUNT=0"* ]]
  [[ "$output" == *"MINOR_COUNT=0"* ]]
  [[ "$output" == *"PRAISE_COUNT=0"* ]]
}

@test "code-review-parse: exits 2 when file missing" {
  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/does-not-exist.md"
  [ "$status" -eq 2 ]
}

@test "code-review-parse: case-insensitive severity matching" {
  mixed="$SCRATCH/mixed.md"
  cat > "$mixed" <<'EOF'
**Severity:** BLOCKING
**Severity:** Blocking
**Severity:** blocking
[BLOCKING] also counts
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$mixed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=4"* ]]
}
