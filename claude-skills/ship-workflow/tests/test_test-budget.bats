#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch test-budget)"
  cd "$SCRATCH"
  git init -q
  git config user.email t@t
  git config user.name t
  source "$SHIP_LIB/test-budget.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

seed() {
  mkdir -p src tests
  i=0; while [ "$i" -lt 100 ]; do echo "x = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 60 ]; do echo "assert $i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m seed
}

@test "tb_baseline_ratio: 60 test lines over 100 src lines is 600 bp" {
  seed
  run tb_baseline_ratio
  [ "$output" = "600" ]
}

@test "tb_baseline_ratio: zero when repo has no test files" {
  mkdir -p src
  echo "x = 1" > src/a.py
  git add -A && git commit -q -m nosrc
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_baseline_ratio: zero when repo has no src files" {
  mkdir -p tests
  echo "assert 1" > tests/test_a.py
  git add -A && git commit -q -m notests
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_baseline_ratio: zero outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run tb_baseline_ratio
  [ "$output" = "0" ]
}

@test "tb_ship_ratio: measures only lines added between two refs" {
  seed
  base=$(git rev-parse HEAD)
  i=0; while [ "$i" -lt 20 ]; do echo "y = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 10 ]; do echo "assert x$i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m ship
  run tb_ship_ratio "$base" HEAD
  [ "$output" = "500" ]
}

@test "tb_ship_ratio: zero when the ship added no src lines" {
  seed
  base=$(git rev-parse HEAD)
  echo "assert extra" >> tests/test_a.py
  git add -A && git commit -q -m testonly
  run tb_ship_ratio "$base" HEAD
  [ "$output" = "0" ]
}

@test "tb_ship_lines: echoes added test lines then added src lines" {
  seed
  base=$(git rev-parse HEAD)
  i=0; while [ "$i" -lt 20 ]; do echo "y = $i" >> src/a.py; i=$((i+1)); done
  i=0; while [ "$i" -lt 10 ]; do echo "assert x$i" >> tests/test_a.py; i=$((i+1)); done
  git add -A && git commit -q -m ship
  run tb_ship_lines "$base" HEAD
  [ "$output" = "10 20" ]
}

@test "tb_ship_lines: zeroes outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run tb_ship_lines HEAD HEAD
  [ "$output" = "0 0" ]
}

@test "tb_verdict: pass at exactly 2x baseline" {
  run tb_verdict 1200 600
  [ "$output" = "pass" ]
}

@test "tb_verdict: major just above 2x baseline" {
  run tb_verdict 1201 600
  [ "$output" = "major" ]
}

@test "tb_verdict: major at exactly 4x baseline" {
  run tb_verdict 2400 600
  [ "$output" = "major" ]
}

@test "tb_verdict: blocking just above 4x baseline" {
  run tb_verdict 2401 600
  [ "$output" = "blocking" ]
}

@test "tb_verdict: pass when baseline is zero (greenfield repo)" {
  run tb_verdict 9999 0
  [ "$output" = "pass" ]
}

@test "tb_shadow_active: active when _log.md is absent" {
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "tb_shadow_active: active with 2 ratio rows" {
  mkdir -p docs/learnings
  printf '| d | ship-next | R-1 | shipped (ratio 0.40 vs baseline 0.60) | n |\n' >> docs/learnings/_log.md
  printf '| d | ship-next | R-2 | shipped (ratio 0.41 vs baseline 0.60) | n |\n' >> docs/learnings/_log.md
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "tb_shadow_active: inactive at 3 ratio rows" {
  mkdir -p docs/learnings
  i=0; while [ "$i" -lt 3 ]; do
    printf '| d | ship-next | R-%s | shipped (ratio 0.40 vs baseline 0.60) | n |\n' "$i" >> docs/learnings/_log.md
    i=$((i+1))
  done
  run tb_shadow_active
  [ "$status" -eq 1 ]
}

@test "tb_shadow_active: rows without a ratio field do not count" {
  mkdir -p docs/learnings
  i=0; while [ "$i" -lt 5 ]; do
    printf '| d | ship-next | R-%s | shipped (review: blocking=0) | n |\n' "$i" >> docs/learnings/_log.md
    i=$((i+1))
  done
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "tb_coverage_ok: equal coverage passes" {
  run tb_coverage_ok 80 80
  [ "$status" -eq 0 ]
}

@test "tb_coverage_ok: higher coverage passes" {
  run tb_coverage_ok 85 80
  [ "$status" -eq 0 ]
}

@test "tb_coverage_ok: integer drop fails" {
  run tb_coverage_ok 75 80
  [ "$status" -ne 0 ]
}

@test "tb_coverage_ok: decimal rise passes" {
  run tb_coverage_ok 80.25 79.75
  [ "$status" -eq 0 ]
}

@test "tb_coverage_ok: decimal drop fails — the case [ -lt ] got wrong" {
  run tb_coverage_ok 79.75 80.25
  [ "$status" -ne 0 ]
}

@test "tb_coverage_ok: empty after fails closed" {
  run tb_coverage_ok "" 80
  [ "$status" -ne 0 ]
}

@test "tb_coverage_ok: empty before fails closed" {
  run tb_coverage_ok 80 ""
  [ "$status" -ne 0 ]
}

@test "tb_coverage_ok: non-numeric fails closed" {
  run tb_coverage_ok "N/A" 80
  [ "$status" -ne 0 ]
}
