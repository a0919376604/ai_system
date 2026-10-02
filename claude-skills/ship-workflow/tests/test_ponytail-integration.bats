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

# --- an absent ponytail must be LOUD, not silent -----------------------------
# Spec 8.4 chose a silent no-op, which is right for a missing optional
# dependency and wrong for one the operator asked for and believes is active.
# Measured on the author's machine: ponytail_check_installed was false and
# ponytail_render_rules emitted 0 lines, while /ship-next Phase 5 reported
# nothing, so every executor ran with no ladder and no one knew.

@test "Phase 5 sets a ponytail status rather than failing silently" {
  CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
  sec=$(awk '/^## Phase 5 /,/^## Phase 6 /' "$CMD")
  echo "$sec" | grep -qF 'PONYTAIL_STATUS=' \
    || { echo "Phase 5 records no ponytail status"; return 1; }
  echo "$sec" | grep -qF 'ponytail_check_installed' \
    || { echo "Phase 5 never asks whether ponytail is installed"; return 1; }
  echo "$sec" | grep -qiF 'no ladder enforced' \
    || { echo "an absent ponytail is not named in plain words"; return 1; }
}

@test "Phase 5 announces an absent ponytail in interactive mode too" {
  # The Phase 9 SUMMARY is only built when AUTO=1, so a summary-only notice
  # would leave interactive runs silent — the mode the operator watches.
  CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
  sec=$(awk '/^## Phase 5 /,/^## Phase 6 /' "$CMD")
  echo "$sec" | grep -qE 'echo "ponytail: .*>&2' \
    || { echo "nothing is printed outside the AUTO-only summary"; return 1; }
}

@test "Phase 9 summary carries the ponytail status" {
  CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
  awk '/^## Phase 9 /,0' "$CMD" | grep -qF 'ponytail: ${PONYTAIL_STATUS}' \
    || { echo "the summary omits whether a ladder was enforced"; return 1; }
}

@test "ponytail_check_installed: finds the plugin under any marketplace name" {
  # A fork or re-host changes the marketplace directory but not the plugin's.
  make_fake_ponytail_plugin "$SCRATCH" 5.2.0 "" some-other-marketplace
  run ponytail_check_installed
  [ "$status" -eq 0 ]
  run ponytail_version
  [ "$output" = "5.2.0" ]
}

@test "ponytail_version: picks the highest version, not the last listed" {
  make_fake_ponytail_plugin "$SCRATCH" 4.9.0
  make_fake_ponytail_plugin "$SCRATCH" 4.10.0
  make_fake_ponytail_plugin "$SCRATCH" 4.8.4
  run ponytail_version
  [ "$output" = "4.10.0" ]
}

@test "ponytail_check_installed: the pre-fix layout is NOT accepted" {
  # cache/ponytail/<version>/ was the imagined shape. Accepting it would let
  # the fiction back in and the fixture bug would stop being detectable.
  mkdir -p "$HOME/.claude/plugins/cache/ponytail/9.9.9"
  echo "# Ponytail" > "$HOME/.claude/plugins/cache/ponytail/9.9.9/AGENTS.md"
  run ponytail_check_installed
  [ "$status" -ne 0 ]
}
