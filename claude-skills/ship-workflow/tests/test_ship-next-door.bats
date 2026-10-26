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
  [[ "$output" == *'signal: one_way_paths backend/app/domain/push_recipients.py'* ]] || return 1
  [[ "$output" == *'signal: one_way_paths backend/app/api/auth.py'* ]] || return 1
  [[ "$output" == *'signal: one_way_paths backend/x/y.py'* ]] || return 1
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
  [[ "$output" == *'spec: no Door line'* ]] || return 1
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
  [[ "$output" == *'signal: migration backend/migrations/versions/0042_x.py'* ]] || return 1
}
@test "a new dependency forces one-way; a version bump does not" {
  echo '{"dependencies":{"a":"1"}}' > package.json
  commit_changes
  start_ship
  echo '{"dependencies":{"a":"1","left-pad":"1"}}' > package.json
  commit_changes
  door
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'signal: new dependency left-pad (package.json)'* ]] || return 1
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
  [[ "$output" == *'signal: deploy Dockerfile.backend'* ]] || return 1
  [[ "$output" == *'signal: deploy .github/workflows/ci.yml'* ]] || return 1
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

forge_stubs() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  cat > "$BATS_TEST_TMPDIR/bin/glab" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
  'mr view'|'mr merge')
    case "$3" in ''|*[!0-9]*) echo 'unknown MR' >&2; exit 2 ;; esac ;;
esac
case "$*" in
  'mr view '*) printf '%s\n' "$STUB_VIEW_JSON" ;;
  'mr create '*) echo https://g/grp/repo/-/merge_requests/42 ;;
  'mr merge '*) exit "${STUB_MERGE_EXIT:-0}" ;;
esac
STUB
  cp "$BATS_TEST_TMPDIR/bin/glab" "$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/glab" "$BATS_TEST_TMPDIR/bin/gh"
  git remote add origin https://gitlab.example/x.git
}
@test "no pipeline: no merge" {
  forge_stubs
  export SN_PIPELINE_WAIT=0 STUB_VIEW_JSON='{"head_pipeline":null}' SN_PIPELINE_WAIT=0
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_auto_merge https://g/grp/repo/-/merge_requests/42'
  [ "$status" -eq 1 ]
  [[ "$output" == *WARN* ]] || return 1
  ! grep -q '^mr merge ' "$CALLS"
}
@test "a pipeline: auto-merge is set" {
  forge_stubs
  export SN_PIPELINE_WAIT=0 STUB_VIEW_JSON='{"head_pipeline":{"id":7,"status":"running"}}'
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_auto_merge https://g/grp/repo/-/merge_requests/42'
  [ "$status" -eq 0 ]
  grep -qxF 'mr view 42 -F json' "$CALLS"
  grep -qxF 'mr merge 42 --auto-merge --squash --yes' "$CALLS"
}
@test "a failing merge command does not fail sn_land" {
  forge_stubs
  git init -q --bare "$SCRATCH/gitlab.git"
  git remote set-url origin "$SCRATCH/gitlab.git"
  start_ship
  commit_changes
  git push -q -u origin ship/R-9-x
  sn_state_set "$PWD" SHIP_MERGE_MODE mr
  sn_state_set "$PWD" SHIP_AUTO_MERGE 1
  export SN_PIPELINE_WAIT=0 STUB_VIEW_JSON='{"head_pipeline":{"id":7,"status":"running"}}' STUB_MERGE_EXIT=1
  echo body > "$SCRATCH/body"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_land "$PWD" R-9 ship/R-9-x main title "$SCRATCH/body"'
  [ "$status" -eq 0 ]
  grep -qxF 'mr view 42 -F json' "$CALLS"
  grep -qxF 'mr merge 42 --auto-merge --squash --yes' "$CALLS"
  sn_state_load "$PWD"
  [ "$SHIP_AUTO_MERGED" = 0 ]
}
@test "sn_cleanup keeps a one-way ship worktree in a squash repo" {
  export WT="$SCRATCH/wt"
  git worktree add -qb ship/R-9-x "$WT"
  sn_state_set "$WT" SHIP_MERGE_MODE mr
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_cleanup "$WT" ship/R-9-x'
  [ "$status" -eq 0 ]
  [ -d "$WT" ]
  git show-ref --verify refs/heads/ship/R-9-x
}

body_fixture() {
  export HOME="$SCRATCH/home"
  local vault
  vault=$(make_fake_airos "$SCRATCH" repo)
  write_global_config "$HOME" "$vault"
  printf '**R-9** Example\n↳ done when: Ready\n' > "$vault/10 Projects/repo/ROADMAP.md"
  start_ship
  sn_state_set "$PWD" SHIP_DOOR one-way
  sn_state_set "$PWD" SHIP_DOOR_REASONS 'spec: no Door line; signal: migration m/1.py'
}
@test "body: Summary, Evidence, Merge Danger, Ship details in order" {
  body_fixture
  printf '## Summary\nS-LINE\n\n## Evidence\nE-LINE\n\n**Blast Radius:** low\nB-LINE\n' > .ship/pr-head.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_ship_body "$PWD" R-9 x "$PWD/body.md"'
  [ "$status" -eq 0 ]
  previous=0
  for line in '## Summary' S-LINE '## Evidence' E-LINE '## Merge Danger' '**Door:** one-way' '- spec: no Door line' '- signal: migration m/1.py' '**Blast Radius:** low' B-LINE '## Ship details' '↳ done when: Ready'; do
    current=$(grep -nxF -- "$line" body.md | cut -d: -f1)
    [ "$current" -gt "$previous" ]
    previous=$current
  done
  [ "$(tail -1 body.md)" = 'Co-Authored-By: Claude <noreply@anthropic.com>' ]
}
@test "body without pr-head.md warns and still carries Merge Danger" {
  body_fixture
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_ship_body "$PWD" R-9 x "$PWD/body.md" 2> "$PWD/warnings"'
  [ "$status" -eq 0 ]
  grep -q WARN warnings
  grep -qxF '## Merge Danger' body.md
  grep -qxF '**Blast Radius:** unstated' body.md
  grep -qxF '## Ship details' body.md
}
@test "summary carries the door and its landing result" {
  start_ship
  sn_state_set "$PWD" AUTO 1
  sn_state_set "$PWD" SHIP_DOOR one-way
  sn_state_set "$PWD" SHIP_MERGE_MODE mr
  sn_state_set "$PWD" SHIP_REVIEW_URL https://g/grp/repo/-/merge_requests/42
  sn_state_set "$PWD" SHIP_AUTO_MERGED 0
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_summary "$PWD" R-9'
  [[ "$output" == *'• door: one-way → awaiting human review: https://g/grp/repo/-/merge_requests/42'* ]] || return 1
  sn_state_set "$PWD" SHIP_DOOR two-way
  sn_state_set "$PWD" SHIP_MERGE_MODE squash
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_summary "$PWD" R-9'
  [[ "$output" == *'• door: two-way → squash-merged'* ]] || return 1
  sn_state_set "$PWD" SHIP_MERGE_MODE mr
  sn_state_set "$PWD" SHIP_AUTO_MERGED 1
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_summary "$PWD" R-9'
  [[ "$output" == *'• door: two-way → auto-merge set (merges after CI)'* ]] || return 1
}
@test "log row carries the door" {
  start_ship
  sn_state_set "$PWD" SHIP_DOOR one-way
  sn_state_set "$PWD" SHIP_MERGE_MODE squash
  mkdir -p docs/learnings
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_log "$PWD" R-9 ""'
  [ "$status" -eq 0 ]
  grep -qF 'door=one-way' docs/learnings/_log.md
}

@test "bad MR URL: warns without merging" {
  forge_stubs
  export SN_PIPELINE_WAIT=0 STUB_VIEW_JSON='{"head_pipeline":{"id":7,"status":"running"}}'
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_auto_merge https://g/x'
  [ "$status" -eq 1 ]
  [[ "$output" == *WARN* ]] || return 1
  ! grep -q '^mr merge ' "$CALLS"
}

@test "failed door check persists safe routing" {
  start_ship
  commit_changes
  sn_state_set "$PWD" ORIG_BRANCH no-such-branch
  door
  [ "$status" -ne 0 ]
  sn_state_load "$PWD"
  [ "$SHIP_DOOR" = one-way ]
  [ "$SHIP_MERGE_MODE" = mr ]
  [ "$SHIP_AUTO_MERGE" = 0 ]
  [[ "$SHIP_DOOR_REASONS" == *'door check failed'* ]]
}

@test "quoted two-way mention cannot override a one-way Door" {
  start_ship
  printf '## Decisions\n- My call: a `Door: two-way` ship auto-merges\n- Door: one-way — drops a column\n' > docs/specs/R-9-x.md
  commit_changes
  door
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'spec: Door: one-way — drops a column'* ]]
}
@test "a quoted Door alone is no Door line" {
  start_ship
  printf '## Decisions\n- My call: a `Door: two-way` ship auto-merges\n' > docs/specs/R-9-x.md
  commit_changes
  door
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'spec: no Door line'* ]]
}
@test "a later one-way Door overrides a counted two-way Door" {
  start_ship
  printf '\n- Door: one-way — drops a column\n' >> docs/specs/R-9-x.md
  commit_changes
  door
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'door: one-way' ]
  [[ "$output" == *'spec: Door: one-way — drops a column'* ]]
}

@test "failed pipeline warns without merging" {
  forge_stubs
  export SN_PIPELINE_WAIT=0 STUB_VIEW_JSON='{"head_pipeline":{"id":7,"status":"failed"}}'
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_auto_merge https://g/grp/repo/-/merge_requests/42'
  [ "$status" -eq 1 ]
  [[ "$output" == *'WARN: pipeline failed — auto-merge not set'* ]] || return 1
  ! grep -q '^mr merge ' "$CALLS"
}

@test "push failure explains that a one-way door needs review" {
  start_ship
  commit_changes
  sn_state_set "$PWD" SHIP_MERGE_MODE mr
  sn_state_set "$PWD" SHIP_DOOR one-way
  echo body > "$SCRATCH/body"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_land "$PWD" R-9 ship/R-9-x main title "$SCRATCH/body" 2> "$SCRATCH/stderr"'
  [ "$status" -ne 0 ]
  grep -qF 'a one-way door needs a review' "$SCRATCH/stderr"
}
