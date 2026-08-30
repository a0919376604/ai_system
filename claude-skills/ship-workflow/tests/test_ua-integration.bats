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
