#!/usr/bin/env bats
load helpers
load helpers-coverage

setup() {
  export SCRATCH="$(make_scratch coverage-diff)"
  export DIFF="$SHIP_LIB/coverage-diff.py"
  export B="$SCRATCH/before.json"
  export A="$SCRATCH/after.json"
}

teardown() { rm -rf "$SCRATCH"; }

@test "coverage-diff: identical reports pass" {
  make_cov_json "$B" src/a.py 10 10 src/b.py 5 10
  make_cov_json "$A" src/a.py 10 10 src/b.py 5 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: coverage rising passes" {
  make_cov_json "$B" src/a.py 5 10
  make_cov_json "$A" src/a.py 8 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: a file vanishing from the report fails — the namespace-package hole" {
  make_cov_json "$B" src/a.py 10 10 src/ns/b.py 5 10
  make_cov_json "$A" src/a.py 10 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/ns/b.py"* ]]
  [[ "$output" == *"no longer measured"* ]]
}

@test "coverage-diff: a one-statement drop fails — the case rounded totals hid" {
  make_cov_json "$B" src/a.py 903 1004
  make_cov_json "$A" src/a.py 902 1004
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"903"* ]]
  [[ "$output" == *"902"* ]]
}

@test "coverage-diff: one file dropping fails even when the total rises" {
  make_cov_json "$B" src/a.py 10 10 src/b.py 10 10
  make_cov_json "$A" src/a.py 4  10 src/b.py 20 20
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/a.py"* ]]
}

@test "coverage-diff: a newly measured file does not fail the gate" {
  make_cov_json "$B" src/a.py 10 10
  make_cov_json "$A" src/a.py 10 10 src/new.py 3 9
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: a changed statement count fails — source moved under the gate" {
  make_cov_json "$B" src/a.py 10 10
  make_cov_json "$A" src/a.py 10 12
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"statement count"* ]]
}

@test "coverage-diff: malformed json exits 2, not 0" {
  echo "not json" > "$B"; make_cov_json "$A" src/a.py 1 1
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: a missing input exits 2, not 0" {
  make_cov_json "$A" src/a.py 1 1
  run python3 "$DIFF" "$SCRATCH/nope.json" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: an empty before report exits 2 rather than vacuously passing" {
  make_cov_json "$B"
  make_cov_json "$A" src/a.py 1 1
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}
