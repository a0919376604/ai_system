#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch airos-binding)"
  export AIROS="$(make_fake_airos "$SCRATCH" "my-repo")"
  export REPO="$(make_fake_repo "$SCRATCH")"
  export HOME_OVERRIDE="$SCRATCH/home"
  write_global_config "$HOME_OVERRIDE" "$AIROS"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "airos-binding: auto-detect by basename when no per-repo override" {
  cd "$REPO" || exit 1
  # Rename the repo dir to 'my-repo' so basename matches
  mv "$REPO" "$SCRATCH/my-repo"
  cd "$SCRATCH/my-repo" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)"
  [ "$result" = "$AIROS/10 Projects/my-repo" ]
}

@test "airos-binding: per-repo override wins over basename" {
  cd "$REPO" || exit 1
  mkdir -p .claude
  cat > .claude/ship-config.yml <<EOF
airos_project: my-repo
EOF
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)"
  [ "$result" = "$AIROS/10 Projects/my-repo" ]
}

@test "airos-binding: emits vault path" {
  cd "$REPO" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" vault)"
  [ "$result" = "$AIROS" ]
}

@test "airos-binding: errors out when global config missing" {
  cd "$REPO" || exit 1
  run env HOME="$SCRATCH/nonexistent" "$SHIP_LIB/airos-binding.sh" vault
  [ "$status" -ne 0 ]
  [[ "$output" == *"ship-workflow.yml not found"* ]]
}
