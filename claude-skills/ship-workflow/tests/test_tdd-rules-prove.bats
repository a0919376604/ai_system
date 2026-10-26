#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch tdd-rules-prove)"
  mkdir -p "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q
  git config user.name Test
  git config user.email test@example.com
  printf '%s\n' 'echo bad' > f.sh
  git add f.sh
  git commit -qm A
  A=$(git rev-parse HEAD)
  printf '%s\n' 'echo good' > f.sh
  git commit -qam B
  B=$(git rev-parse HEAD)
  export A B SHIP_LIB
  source "$SHIP_LIB/tdd-rules.sh"
  printf '%s\n' '[ "$(sh f.sh)" = good ]' > check.sh
  before=$(git worktree list | wc -l)
}
teardown() { rm -rf "$SCRATCH"; }

@test "proof: red on the mistake, green on the fix" {
  run tdd_rules_prove "$A" "sh check.sh" check.sh
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "proof: red at ${A:0:7} (exit 1) · green at ${B:0:7}" ]
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "a check that passes on the mistake is refused" {
  echo true > check.sh
  run tdd_rules_prove "$A" "sh check.sh" check.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"check does not fail on the mistake"* ]] || return 1
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "a check that fails on the fix is refused" {
  echo false > check.sh
  run tdd_rules_prove "$A" "sh check.sh" check.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"check fails on the fix"* ]] || return 1
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "bad input gives usage and no worktree is left" {
  run tdd_rules_prove no-such-ref "sh check.sh" check.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]] || return 1
  [ "$(git worktree list | wc -l)" -eq "$before" ]
  run tdd_rules_prove "$A" "sh check.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]] || return 1
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "a check path in a new directory works" {
  mkdir -p tests/new
  mv check.sh tests/new/check.sh
  run tdd_rules_prove "$A" "sh tests/new/check.sh" tests/new/check.sh
  [ "$status" -eq 0 ]
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "only the named paths reach the red run" {
  git checkout -q --detach "$A"
  echo 'echo good' > f.sh
  run tdd_rules_prove "$A" "sh check.sh" check.sh
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "proof: red at ${A:0:7} (exit 1) · green at ${A:0:7}" ]
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}

@test "zsh gives the same result" {
  run zsh -c 'source "$SHIP_LIB/tdd-rules.sh"; tdd_rules_prove "$A" "sh check.sh" check.sh'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "proof: red at ${A:0:7} (exit 1) · green at ${B:0:7}" ]
  [ "$(git worktree list | wc -l)" -eq "$before" ]
}
