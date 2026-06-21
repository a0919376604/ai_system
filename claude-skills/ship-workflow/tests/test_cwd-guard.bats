#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch cwd-guard)"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "cwd-guard: exits 0 when in main work tree" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 0 ]
}

@test "cwd-guard: exits 0 when not in a git repo at all" {
  cd "$SCRATCH"
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 0 ]
}

@test "cwd-guard: exits 1 + ERROR message inside a worktree" {
  cd "$SCRATCH"
  mkdir main && cd main
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q -b ship/test ../wt
  cd ../wt
  run "$SHIP_LIB/cwd-guard.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot run inside"* ]]
  [[ "$output" == *"ship/"* ]]
}

@test "cwd-guard: stderr-only output (no chatter on stdout when in main tree)" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run "$SHIP_LIB/cwd-guard.sh"
  [ -z "$output" ]
}
