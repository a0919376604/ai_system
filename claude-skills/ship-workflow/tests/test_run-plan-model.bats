#!/usr/bin/env bats

@test "run-plan-model opts into Discord discovery with an optional model argument" {
  local skill="$BATS_TEST_DIRNAME/../../run-plan/skills/run-plan-model/SKILL.md"
  grep -q '^discord-visible: true$' "$skill"
  grep -q '^argument-hint: "\[model\]"$' "$skill"
}
load helpers

setup() {
  export SCRATCH="$(make_scratch run-plan-model)"
  export XDG_CONFIG_HOME="$SCRATCH/settings with spaces"
  export RUN_PLAN_SKILL_DIR="$SHIP_SKILL_ROOT/../run-plan"
  MODEL_HELPER="$RUN_PLAN_SKILL_DIR/scripts/model.sh"
}
teardown() {
  rm -rf "$SCRATCH"
  if [ -n "${SLOT:-}" ]; then
    rm -f /tmp/run-plan-{codex,start-ref,cwd,meta}-"$SLOT".{log,pid,txt}
  fi
}

@test "model setting is shared across projects, queried without writes, and reset to inherited" {
  run bash "$MODEL_HELPER"
  [ "$status" -eq 0 ]
  [[ "$output" == *inherit* ]] || return 1
  [ ! -e "$XDG_CONFIG_HOME/run-plan/model" ]
  run bash "$MODEL_HELPER" sol
  [ "$status" -eq 0 ]
  mkdir -p "$SCRATCH/project-b"
  cd "$SCRATCH/project-b"
  run bash "$MODEL_HELPER" get
  [ "$status" -eq 0 ]
  [ "$output" = gpt-6.1-sol ]
  run bash "$MODEL_HELPER" gpt-6.1-terra
  [ "$status" -eq 0 ]
  run bash "$MODEL_HELPER"
  [ "$status" -eq 0 ]
  [[ "$output" == *gpt-6.1-terra* ]] || return 1
  run bash "$MODEL_HELPER" reset
  [ "$status" -eq 0 ]
  run bash "$MODEL_HELPER" get
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "invalid model arguments preserve the previous setting and are never executed" {
  bash "$MODEL_HELPER" astra
  for bad in '' '--model=oops' 'gpt sol' '$(touch SHOULD_NOT_EXIST)' 'a;b' $'sol\nastra'; do
    run bash "$MODEL_HELPER" "$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; return 1; }
    [ "$(bash "$MODEL_HELPER" get)" = gpt-6-astra ]
  done
  run bash "$MODEL_HELPER" sol unexpected
  [ "$status" -ne 0 ]
  [ ! -e SHOULD_NOT_EXIST ]
}

prepare_launch() {
  export SLOT="model-test-$$-$BATS_TEST_NUMBER"
  export PLAN_ABS="$SCRATCH/plan.md" BRANCH=main CWD="$SCRATCH/project"
  export PROMPT_FILE="$SCRATCH/prompt.txt"
  export WAKEUP_CHANNEL_ID='' WAKEUP_DIR=''
  mkdir -p "$CWD" "$SCRATCH/bin"
  git -C "$CWD" init -q -b main
  git -C "$CWD" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m base
  printf 'literal prompt: $HOME `uname`\n' > "$PROMPT_FILE"
  cat > "$SCRATCH/bin/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SCRATCH/args"
cat > "$SCRATCH/stdin"
touch "$SCRATCH/finished"
SH
  chmod +x "$SCRATCH/bin/codex"
  export PATH="$SCRATCH/bin:$PATH"
  awk '/^## Step 3:/{s=1;next} /^## Step 3.5:/{exit} s && /^```bash/{f=1;next} s && /^```/{f=0} f' \
    "$RUN_PLAN_SKILL_DIR/SKILL.md" > "$SCRATCH/launch.sh"
  cd "$CWD"
}

await_launch() {
  for _ in {1..100}; do
    [ -f "$SCRATCH/finished" ] && return 0
    sleep 0.02
  done
  cat "/tmp/run-plan-codex-$SLOT.log"
  return 1
}

@test "launch passes the chosen model and original stdin without overriding effort" {
  prepare_launch
  bash "$MODEL_HELPER" sol
  run bash "$SCRATCH/launch.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  await_launch
  printf '%s\n' exec - --dangerously-bypass-approvals-and-sandbox --model gpt-6.1-sol > "$SCRATCH/expected"
  diff -u "$SCRATCH/expected" "$SCRATCH/args"
  cmp "$PROMPT_FILE" "$SCRATCH/stdin"
  grep -qx 'model=gpt-6.1-sol' "/tmp/run-plan-meta-$SLOT.txt"
  bash "$MODEL_HELPER" astra
  grep -qx 'model=gpt-6.1-sol' "/tmp/run-plan-meta-$SLOT.txt"
}

@test "launch with reset inherits Codex defaults in bash and zsh" {
  prepare_launch
  bash "$MODEL_HELPER" sol
  bash "$MODEL_HELPER" reset
  for shell in bash zsh; do
    rm -f "$SCRATCH/finished"
    run "$shell" "$SCRATCH/launch.sh"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    await_launch
    printf '%s\n' exec - --dangerously-bypass-approvals-and-sandbox > "$SCRATCH/expected"
    diff -u "$SCRATCH/expected" "$SCRATCH/args"
  done
}

@test "corrupt persisted settings fail before launching a model" {
  prepare_launch
  mkdir -p "$XDG_CONFIG_HOME/run-plan"
  printf 'sol\nastra\n' > "$XDG_CONFIG_HOME/run-plan/model"
  run bash "$SCRATCH/launch.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$SCRATCH/args" ]
  [ ! -e "/tmp/run-plan-codex-$SLOT.pid" ]
}
