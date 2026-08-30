#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ship-next-no-ua)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "ship-next: no UA → ua_check_drift silent no-op" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/ua-integration.sh"
  run ua_check_drift
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ship-next Phase 1 pattern: DRIFT_WARN empty and doesn't print when UA absent" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  # Replicate the pattern from ship-next.md Phase 1
  source "$SHIP_LIB/ua-integration.sh"
  DRIFT_WARN=$(ua_check_drift)
  [ -z "$DRIFT_WARN" ]
}

@test "ship-next Phase 3 passes the resolved ID to UA pre-context" {
  run grep -F 'ua_get_pre_brainstorm_context "$ID"' "$SHIP_SKILL_ROOT/commands/ship-next.md"
  [ "$status" -eq 0 ]
}
