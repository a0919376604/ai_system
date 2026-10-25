#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch run-plan-blocks)"
  SLOT="r009-test-$$"
  sleep 30 &
  export SLEEP_PID=$!
  echo "$SLEEP_PID" > "/tmp/run-plan-codex-$SLOT.pid"
  touch "/tmp/run-plan-codex-$SLOT.log"
}

teardown() {
  kill "$SLEEP_PID" 2>/dev/null || true
  wait "$SLEEP_PID" 2>/dev/null || true
  rm -f "/tmp/run-plan-codex-$SLOT.pid" "/tmp/run-plan-codex-$SLOT.log"
  rm -rf "$SCRATCH"
}

@test "zsh: run-plan status without an argument targets its one live slot" {
  # Other real runs may exist: expose only this test's process as live.
  echo 'kill() { [ "$2" = "$SLEEP_PID" ] && builtin kill "$@"; }' > "$SCRATCH/status.sh"
  awk '/^## Step 5:/{s=1;next} /^## Step 5a:/{exit} s && /^```bash/{f=1;next} s && /^```/{f=0} f' \
    "$SHIP_SKILL_ROOT/../run-plan/SKILL.md" >> "$SCRATCH/status.sh"
  [ -s "$SCRATCH/status.sh" ]
  run env ARGUMENTS=status zsh "$SCRATCH/status.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"slot=$SLOT PID=$SLEEP_PID — ALIVE"* ]]
}
