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

@test "airos-binding: strips inline comments from config values" {
  # Write a config with inline `# comment` after values
  cat > "$HOME_OVERRIDE/.claude/ship-workflow.yml" <<EOF
airos_vault: $AIROS              # this is the vault
airos_projects_dir: "10 Projects"  # subdir
default_roadmap_mode: soft         # soft or strict
default_id_pad: 3                  # IDEA-001 vs IDEA-1
auto_pull_freshness_window: 60     # seconds
EOF
  cd "$REPO" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" vault)"
  [ "$result" = "$AIROS" ]
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" roadmap_mode)"
  [ "$result" = "soft" ]
}

@test "airos-binding: emits code_root" {
  cat > "$HOME_OVERRIDE/.claude/ship-workflow.yml" <<EOF
airos_vault: $AIROS
code_root: /Users/test/Desktop/code   # local workspace root
EOF
  cd "$REPO" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" code_root)"
  [ "$result" = "/Users/test/Desktop/code" ]
}

@test "airos-binding: code_root empty when not set" {
  cat > "$HOME_OVERRIDE/.claude/ship-workflow.yml" <<EOF
airos_vault: $AIROS
EOF
  cd "$REPO" || exit 1
  result="$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" code_root)"
  [ -z "$result" ]
}

# --- R-004 §3.8: a ship-next worktree is named after its main checkout ---------

@test "airos-binding: at a linked worktree's root the project is the main checkout" {
  # basename(pwd) there is the worktree's own name, so R-001/R-003 mirrored their specs
  # into bogus "10 Projects/R-00N-…" vault folders.
  mkdir -p "$SCRATCH/my-repo" && cd "$SCRATCH/my-repo" || return 1
  git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git worktree add -q -b ship/R-9-x "$SCRATCH/my-repo-worktrees/R-9-x"
  cd "$SCRATCH/my-repo-worktrees/R-9-x" || return 1
  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_name)" = "my-repo" ] || return 1
  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_path)" = "$AIROS/10 Projects/my-repo" ]
}

@test "airos-binding: a plain directory inside a linked worktree keeps its own name" {
  # The fixtures above live in non-git dirs nested in whatever checkout runs the suite —
  # often a ship-next worktree. They must not inherit that checkout's name.
  mkdir -p "$SCRATCH/outer" && cd "$SCRATCH/outer" || return 1
  git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git worktree add -q -b ship/R-9-y "$SCRATCH/outer-wt"
  mkdir -p "$SCRATCH/outer-wt/fixture/my-repo" && cd "$SCRATCH/outer-wt/fixture/my-repo" || return 1
  [ "$(HOME="$HOME_OVERRIDE" "$SHIP_LIB/airos-binding.sh" project_name)" = "my-repo" ]
}
