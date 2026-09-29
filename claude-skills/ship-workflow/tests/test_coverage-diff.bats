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
  make_cov_json "$B" src/a.py 1,2,3,4,5,6,7,8,9,10 10 src/b.py 1,2,3,4,5 10
  make_cov_json "$A" src/a.py 1,2,3,4,5,6,7,8,9,10 10 src/b.py 1,2,3,4,5 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: coverage rising passes" {
  make_cov_json "$B" src/a.py 1,2,3,4,5 10
  make_cov_json "$A" src/a.py 1,2,3,4,5,6,7,8 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: a file vanishing from the report fails — the namespace-package hole" {
  make_cov_json "$B" src/a.py 1,2,3,4,5,6,7,8,9,10 10 src/ns/b.py 1,2,3,4,5 10
  make_cov_json "$A" src/a.py 1,2,3,4,5,6,7,8,9,10 10
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/ns/b.py"* ]]
  [[ "$output" == *"no longer measured"* ]]
}

@test "coverage-diff: a one-statement drop fails — the case rounded totals hid" {
  make_cov_json "$B" src/a.py $(python3 -c "print(','.join(str(i) for i in range(1,904)))") 1004
  make_cov_json "$A" src/a.py $(python3 -c "print(','.join(str(i) for i in range(1,903)))") 1004
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  # The old percentage gate rendered both sides as `90`. This names the lost line.
  [[ "$output" == *"lines no longer covered: 903"* ]]
}

@test "coverage-diff: one file dropping fails even when the total rises" {
  make_cov_json "$B" src/a.py 1,2,3,4,5,6,7,8,9,10 10 src/b.py 1,2,3,4,5,6,7,8,9,10 10
  make_cov_json "$A" src/a.py 1,2,3,4 10 src/b.py 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 20
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"src/a.py"* ]]
}

@test "coverage-diff: a newly measured file does not fail the gate" {
  make_cov_json "$B" src/a.py 1,2,3,4,5,6,7,8,9,10 10
  make_cov_json "$A" src/a.py 1,2,3,4,5,6,7,8,9,10 10 src/new.py 1,2,3 9
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: a changed statement count fails — source moved under the gate" {
  make_cov_json "$B" src/a.py 1,2,3,4,5,6,7,8,9,10 10
  make_cov_json "$A" src/a.py 1,2,3,4,5,6,7,8,9,10 12
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

@test "coverage-diff: same count, different lines fails — counts are cardinality, not membership" {
  make_cov_json "$B" src/a.py 1,3,4,5 5
  make_cov_json "$A" src/a.py 1,3,4,6 5
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
  [[ "$output" == *"5"* ]]
  [[ "$output" == *"no longer covered"* ]]
}

@test "coverage-diff: covering extra lines on top of the old set passes" {
  make_cov_json "$B" src/a.py 1,3 5
  make_cov_json "$A" src/a.py 1,3,4 5
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 0 ]
}

@test "coverage-diff: losing one line fails even when others are gained" {
  make_cov_json "$B" src/a.py 1,2,3 5
  make_cov_json "$A" src/a.py 1,2,4,5 5
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 1 ]
}

@test "coverage-diff: a fractional statement count exits 2, not 0" {
  make_cov_json_raw "$B" src/a.py 1,2 1.9
  make_cov_json_raw "$A" src/a.py 1,2 1.1
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: a negative statement count exits 2" {
  make_cov_json_raw "$B" src/a.py 1,2 -5
  make_cov_json_raw "$A" src/a.py 1,2 -5
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: a boolean statement count exits 2" {
  make_cov_json_raw "$B" src/a.py 1,2 true
  make_cov_json_raw "$A" src/a.py 1,2 true
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: a report with no executed_lines exits 2 rather than guessing" {
  python3 -c "
import json
json.dump({'files': {'src/a.py': {'summary': {'covered_lines': 2, 'num_statements': 5}}}}, open('$B','w'))
json.dump({'files': {'src/a.py': {'summary': {'covered_lines': 2, 'num_statements': 5}}}}, open('$A','w'))
"
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
}

@test "coverage-diff: a top-level JSON array exits 2, not 1 with a traceback" {
  echo '[]' > "$B"
  make_cov_json "$A" src/a.py 1 1
  run python3 "$DIFF" "$B" "$A"
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected an object"* ]]
  [[ "$output" != *"Traceback"* ]]
}
