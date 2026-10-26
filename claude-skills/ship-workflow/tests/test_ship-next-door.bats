#!/usr/bin/env bats
load helpers

setup() {
  export SHIP_LIB
  export SCRATCH="$(make_scratch door)"
  mkdir -p "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p src
  echo base > src/a.py
  git add . && git commit -qm base
  source "$SHIP_LIB/ship-next.sh"
}
teardown() { rm -rf "$SCRATCH"; }

start_ship() {
  git checkout -qb ship/R-9-x
  mkdir -p docs/specs
  printf '# x\n\n## Goals\nDoor: two-way here is a quote\n\n## Decisions\n- Door: %s — why\n' "${1:-two-way}" > docs/specs/R-9-x.md
  sn_state_set "$PWD" ID R-9
  sn_state_set "$PWD" SLUG x
  sn_state_set "$PWD" ORIG_BRANCH main
  sn_state_set "$PWD" REPO "$PWD"
}
commit_changes() { git add . && git commit -qm change; }
door() { run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_door "$PWD"'; }
paths_config() {
  mkdir -p .claude
  cat > .claude/ship-config.yml <<'CFG'
one_way_paths:
  - backend/app/domain/push_*.py
  - "backend/app/api/auth.py"
  - backend/x/*.py  # pushes
CFG
}
paths_changes() {
  mkdir -p backend/app/domain backend/app/api backend/x
  touch backend/app/domain/push_recipients.py backend/app/api/auth.py backend/x/y.py
}
assert_paths() {
  [ "$status" -eq 0 ]
  [[ "$output" == *'signal: one_way_paths backend/app/domain/push_recipients.py'* ]]
  [[ "$output" == *'signal: one_way_paths backend/app/api/auth.py'* ]]
  [[ "$output" == *'signal: one_way_paths backend/x/y.py'* ]]
}

@test "two-way spec, plain change: squash" {
  start_ship
  echo changed > src/a.py
  commit_changes
  door
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'door: two-way' ]
  sn_state_load "$PWD"
  [ "$SHIP_MERGE_MODE" = squash ]
  [ "$SHIP_AUTO_MERGE" = 0 ]
}
@test "no Door line in Decisions: one-way" {
  start_ship
  sed -i '' '/^- Door:/d' docs/specs/R-9-x.md
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'spec: no Door line'* ]]
  sn_state_load "$PWD"
  [ "$SHIP_MERGE_MODE" = mr ]
}
@test "a migration forces one-way" {
  start_ship
  mkdir -p backend/migrations/versions
  touch backend/migrations/versions/0042_x.py
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'signal: migration backend/migrations/versions/0042_x.py'* ]]
}
@test "a new dependency forces one-way; a version bump does not" {
  echo '{"dependencies":{"a":"1"}}' > package.json
  commit_changes
  start_ship
  echo '{"dependencies":{"a":"1","left-pad":"1"}}' > package.json
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'signal: new dependency left-pad (package.json)'* ]]
  echo '{"dependencies":{"a":"2"}}' > package.json
  commit_changes
  door
  [ "${lines[0]}" = 'door: two-way' ]
}
@test "deploy files force one-way" {
  start_ship
  mkdir -p .github/workflows
  touch Dockerfile.backend .github/workflows/ci.yml
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'signal: deploy Dockerfile.backend'* ]]
  [[ "$output" == *'signal: deploy .github/workflows/ci.yml'* ]]
}
@test "one_way_paths come from the base branch" {
  paths_config
  commit_changes
  start_ship
  paths_changes
  commit_changes
  door
  assert_paths
}
@test "one_way_paths only on the ship branch do not escalate" {
  start_ship
  paths_config
  paths_changes
  commit_changes
  door
  [ "${lines[0]}" = 'door: two-way' ]
}
@test "an mr repo with a two-way door auto-merges" {
  mkdir -p .claude
  echo 'merge_mode: mr' > .claude/ship-config.yml
  commit_changes
  start_ship
  commit_changes
  door
  [ "${lines[0]}" = 'door: two-way' ]
  sn_state_load "$PWD"
  [ "$SHIP_MERGE_MODE" = mr ]
  [ "$SHIP_AUTO_MERGE" = 1 ]
}
@test "a rerun overwrites the keys" {
  start_ship one-way
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  sed -i '' 's/Door: one-way/Door: two-way/' docs/specs/R-9-x.md
  commit_changes
  door
  sn_state_load "$PWD"
  [ "$SHIP_DOOR" = two-way ]
  [ "$SHIP_MERGE_MODE" = squash ]
  [ "$SHIP_AUTO_MERGE" = 0 ]
  [ "$SHIP_DOOR_REASONS" = 'spec: Door: two-way — why' ]
}
@test "zsh gives the same door" {
  paths_config
  commit_changes
  start_ship
  paths_changes
  commit_changes
  run zsh -c 'grep() { return 1; }; source "$SHIP_LIB/ship-next.sh"; sn_door "$PWD"'
  assert_paths
}
