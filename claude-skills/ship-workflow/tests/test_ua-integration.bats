#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ua-integration)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "ua_check_installed: exit 1 when plugin dir missing" {
  cd "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "ua_check_installed: exit 2 when plugin present but KG missing" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "ua_check_installed: exit 0 when both present" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  make_fake_ua_kg "$SCRATCH"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_installed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: empty output when UA absent" {
  cd "$SCRATCH"
  git init -q
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: empty output when KG commit matches HEAD" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local head; head=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$head"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ua_check_drift: mild warning when 1-50 files diverge" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local base; base=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$base"
  # Create 3 new files + commit → 3-file diff vs KG's base
  for i in 1 2 3; do echo "x" > "file$i.txt"; done
  git add . && git -c user.email=t@t -c user.name=t commit -q -m "3 files"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [[ "$output" =~ "UA KG is stale" ]]
  [[ "$output" =~ "3 file(s)" ]]
}

@test "ua_check_drift: severe warning when >50 files diverge" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local base; base=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$base"
  for i in $(seq 1 60); do echo "x" > "file$i.txt"; done
  git add . && git -c user.email=t@t -c user.name=t commit -q -m "60 files"
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [[ "$output" =~ "severely stale" ]]
  [[ "$output" =~ "60 file(s)" ]]
}
