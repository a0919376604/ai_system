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

@test "no ponytail → render is a silent no-op and writes no file" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p .ship
  source "$SHIP_LIB/ponytail-integration.sh"
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "no CONTEXT.md → path is empty and counts are zero" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/context-md.sh"
  run context_md_path
  [ -z "$output" ]
  run context_md_entry_count
  [ "$output" = "0" ]
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "empty repo → test budget is zero and shadow mode is active" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/test-budget.sh"
  run tb_baseline_ratio
  [ "$output" = "0" ]
  run tb_shadow_active
  [ "$status" -eq 0 ]
}

@test "all three libs are sourceable together without collision" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run bash -c "source '$SHIP_LIB/ua-integration.sh'; source '$SHIP_LIB/context-md.sh'; source '$SHIP_LIB/test-budget.sh'; source '$SHIP_LIB/ponytail-integration.sh'; echo ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "ship-next still declares every phase in order" {
  for p in "## Phase 1 " "## Phase 2 " "## Phase 3 " "## Phase 4 " "## Phase 5 " "## Phase 6 " "## Phase 7 " "## Phase 8 " "## Phase 8.5" "## Phase 8.7" "## Phase 9"; do
    run grep -F "$p" "$SHIP_SKILL_ROOT/commands/ship-next.md"
    [ "$status" -eq 0 ]
  done
}

@test "a repo with no codex completes the cycle unchanged" {
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/codex-verdict.sh"
  source "$SHIP_LIB/codex-rounds.sh"
  source "$SHIP_LIB/codex-supervise-state.sh"
  # Nothing here may write, and nothing may report success it cannot support.
  before=$(find . -path ./.git -prune -o -type f -print | sort)
  run codex_verdict missing.log;   [ "$output" = "infra" ]
  run codex_state_attempt "$PWD";  [ "$output" = "0" ]
  run codex_round_count "$PWD";    [ "$output" = "0" ]
  run codex_state_alive "$PWD";    [ "$status" -ne 0 ]
  after=$(find . -path ./.git -prune -o -type f -print | sort)
  [ "$before" = "$after" ]
}
