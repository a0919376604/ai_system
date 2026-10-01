#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ponytail-integration)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/ponytail-integration.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "ponytail_check_installed: fails when plugin absent" {
  run ponytail_check_installed
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "ponytail_check_installed: succeeds when plugin + ruleset present" {
  make_fake_ponytail_plugin "$SCRATCH"
  run ponytail_check_installed
  [ "$status" -eq 0 ]
}

@test "ponytail_check_installed: fails when plugin dir present but ruleset missing" {
  make_fake_ponytail_plugin "$SCRATCH" 4.8.4 noruleset
  run ponytail_check_installed
  [ "$status" -ne 0 ]
}

@test "ponytail_version: echoes the installed version directory name" {
  make_fake_ponytail_plugin "$SCRATCH" 5.0.1
  run ponytail_version
  [ "$output" = "5.0.1" ]
}

@test "ponytail_version: silent when plugin absent" {
  run ponytail_version
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ponytail_ruleset_sha256: stable 64-char hex for a fixed ruleset" {
  make_fake_ponytail_plugin "$SCRATCH"
  run ponytail_ruleset_sha256
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
}

@test "ponytail_ruleset_sha256: silent when plugin absent" {
  run ponytail_ruleset_sha256
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ponytail_render_rules: writes scope header then the ladder" {
  make_fake_ponytail_plugin "$SCRATCH"
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  head -1 .ship/ponytail-rules.md | grep -qF "Scope: product code."
  grep -qF "governed by .ship/tdd-rules.md" .ship/ponytail-rules.md
  grep -qF "Does this need to exist?" .ship/ponytail-rules.md
}

@test "ponytail_render_rules: writes nothing and exits 0 when plugin absent" {
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "ponytail_render_rules: writes nothing when ruleset file is missing" {
  make_fake_ponytail_plugin "$SCRATCH" 4.8.4 noruleset
  mkdir -p .ship
  run ponytail_render_rules .ship/ponytail-rules.md
  [ "$status" -eq 0 ]
  [ ! -f .ship/ponytail-rules.md ]
}

@test "ponytail_render_rules: silent outside a git repo" {
  make_fake_ponytail_plugin "$SCRATCH"
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run ponytail_render_rules ./rules.md
  [ "$status" -eq 0 ]
}
