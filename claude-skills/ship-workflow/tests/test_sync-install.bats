#!/usr/bin/env bats
# R-004 §3.3: sync.sh installs ship-workflow's three skills and five commands as
# symlinks into this checkout, and backs up the two config files the repo keeps. The
# old sync.sh mirrored all of ~/.claude/skills with rsync: its restore would have
# reinstalled 40 removed skills and overwritten a newer global CLAUDE.md.
# Each test runs a copy of sync.sh inside a scratch "ai_system", so neither the real
# repo nor the real ~/.claude is touched.
load helpers

setup() {
  export SCRATCH="$(make_scratch sync-install)"
  export HOME="$SCRATCH/home"
  export AI_SYSTEM_SKIP_DEVSYNC=1
  R="$SCRATCH/ai_system"; export R
  mkdir -p "$R/claude-skills/ship-workflow/commands" "$R/claude-skills/run-plan" \
           "$R/claude-skills/code-review-skill" "$R/config/claude" "$R/devsync"
  cp "$SHIP_SKILL_ROOT/../../sync.sh" "$R/sync.sh"
  for c in ship-next ship-compound ship-idea ship-land ship-init; do
    echo "$c" > "$R/claude-skills/ship-workflow/commands/$c.md"
  done
  echo "global rules" > "$R/config/claude/CLAUDE.md"
  echo "[defaults]" > "$R/devsync/config.toml"
  # A machine as it stood on 2026-10-23: a real run-plan copy, no code-review-skill,
  # a dangling ship-arch link, and a skill the repo has nothing to do with.
  mkdir -p "$HOME/.claude/skills/run-plan" "$HOME/.claude/skills/other" "$HOME/.claude/commands"
  echo "old copy" > "$HOME/.claude/skills/run-plan/SKILL.md"
  echo keep > "$HOME/.claude/skills/other/SKILL.md"
  ln -s "$HOME/.claude/skills/ship-workflow/commands/ship-arch.md" "$HOME/.claude/commands/ship-arch.md"
  ln -s "$SCRATCH/elsewhere/ship-x.md" "$HOME/.claude/commands/ship-x.md"   # dangling, not ours
}
teardown() { rm -rf "$SCRATCH"; }

snapshot() {  # every path under HOME, with link targets
  (cd "$HOME" && find . -print | sort | while IFS= read -r p; do
     if [ -L "$p" ]; then echo "$p -> $(readlink "$p")"; else echo "$p"; fi
   done)
}

@test "restore links the 3 skills and 5 commands, moves a real dir aside, clears only our dangling links" {
  run bash "$R/sync.sh" restore --yes
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  for s in ship-workflow run-plan code-review-skill; do
    [ "$(readlink "$HOME/.claude/skills/$s")" = "$R/claude-skills/$s" ] || { echo "skill $s"; return 1; }
  done
  for c in ship-next ship-compound ship-idea ship-land ship-init; do
    [ "$(readlink "$HOME/.claude/commands/$c.md")" = "$HOME/.claude/skills/ship-workflow/commands/$c.md" ] || { echo "cmd $c"; return 1; }
    [ -f "$HOME/.claude/commands/$c.md" ] || return 1
  done
  moved=$(ls -d "$HOME/.claude/.ai_system-displaced/run-plan-"* 2>/dev/null | head -1)
  [ -n "$moved" ] && grep -qF "old copy" "$moved/SKILL.md" || { echo "run-plan copy not kept"; return 1; }
  [ ! -L "$HOME/.claude/commands/ship-arch.md" ] || { echo "our dangling link kept"; return 1; }
  [ -L "$HOME/.claude/commands/ship-x.md" ] || { echo "removed a link that is not ours"; return 1; }
  [ "$(cat "$HOME/.claude/skills/other/SKILL.md")" = keep ]
}

@test "restore twice changes nothing the second time" {
  bash "$R/sync.sh" restore --yes >/dev/null
  before=$(snapshot)
  run bash "$R/sync.sh" restore --yes
  [ "$status" -eq 0 ] || return 1
  [ "$(snapshot)" = "$before" ]
}

@test "restore --dry-run changes nothing and names each planned action" {
  before=$(snapshot)
  run bash "$R/sync.sh" restore --dry-run
  [ "$status" -eq 0 ] || return 1
  [ "$(snapshot)" = "$before" ] || { echo "dry run changed files"; return 1; }
  [[ "$output" == *"code-review-skill"* ]] || return 1
  [[ "$output" == *"run-plan"* ]] || return 1
  [[ "$output" == *"ship-arch.md"* ]]
}

@test "restore without --yes asks before overwriting a differing config file" {
  mkdir -p "$HOME/.claude" && echo "newer live rules" > "$HOME/.claude/CLAUDE.md"
  run bash -c "echo n | bash '$R/sync.sh' restore"
  [ "$(cat "$HOME/.claude/CLAUDE.md")" = "newer live rules" ] || { echo "overwrote without consent"; return 1; }
  [ "$(readlink "$HOME/.claude/skills/run-plan")" = "$R/claude-skills/run-plan" ]
}

@test "backup copies the two config files into the repo and touches nothing else" {
  mkdir -p "$HOME/.claude" "$HOME/.config/devsync"
  echo "live global rules" > "$HOME/.claude/CLAUDE.md"
  echo "[live]" > "$HOME/.config/devsync/config.toml"
  run bash "$R/sync.sh" backup
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$R/config/claude/CLAUDE.md")" = "live global rules" ] || return 1
  [ "$(cat "$R/devsync/config.toml")" = "[live]" ] || return 1
  [ "$(ls "$R/claude-skills" | sort | tr '\n' ' ')" = "code-review-skill run-plan ship-workflow " ]
}

@test "status exits 0 when every link is right and 1 naming a missing one" {
  bash "$R/sync.sh" restore --yes >/dev/null
  run bash "$R/sync.sh" status
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  rm "$HOME/.claude/commands/ship-land.md"
  run bash "$R/sync.sh" status
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"ship-land"*"missing"* ]]
}

# --- R-004 review attempt 1 ----------------------------------------------------

make_checkout() {  # turn $R into a git checkout on branch $1
  git -C "$R" init -q -b "$1" && git -C "$R" add -A \
    && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m base
}

@test "restore refuses to run from a linked worktree, and links nothing" {
  # Links into a ship-next worktree dangle machine-wide once Phase 9 removes it.
  make_checkout main
  git -C "$R" worktree add -q -b ship/R-9-x "$SCRATCH/ai_system-wt"
  run bash "$SCRATCH/ai_system-wt/sync.sh" restore --yes
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"worktree"* ]] || return 1
  [ ! -e "$HOME/.claude/skills/ship-workflow" ]
}

@test "restore from a checkout off main warns, and still links" {
  make_checkout feature-x
  run bash "$R/sync.sh" restore --yes
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"feature-x"* ]] || return 1
  [ "$(readlink "$HOME/.claude/skills/ship-workflow")" = "$R/claude-skills/ship-workflow" ]
}

@test "restore keeps the live CLAUDE.md it replaces" {
  mkdir -p "$HOME/.claude" && echo "newer live rules" > "$HOME/.claude/CLAUDE.md"
  run bash "$R/sync.sh" restore --yes
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$HOME/.claude/CLAUDE.md")" = "global rules" ] || return 1
  kept=$(ls "$HOME/.claude/.ai_system-displaced/"CLAUDE.md-* 2>/dev/null | head -1)
  [ -n "$kept" ] && [ "$(cat "$kept")" = "newer live rules" ]
}

@test "backup --dry-run writes nothing, and an unknown option is refused" {
  mkdir -p "$HOME/.claude" "$HOME/.config/devsync"
  echo "live global rules" > "$HOME/.claude/CLAUDE.md"
  echo "[live]" > "$HOME/.config/devsync/config.toml"
  run bash "$R/sync.sh" backup --dry-run
  [ "$status" -eq 0 ] || return 1
  [ "$(cat "$R/config/claude/CLAUDE.md")" = "global rules" ] || { echo "dry run wrote"; return 1; }
  [ "$(cat "$R/devsync/config.toml")" = "[defaults]" ] || return 1
  run bash "$R/sync.sh" backup --bogus
  [ "$status" -eq 2 ]
}

@test "dry-run never plans to remove a kept command link" {
  # With the ship-workflow link wrong, the kept command links dangle until restore
  # fixes it — the real run keeps them, so the dry run must not say otherwise.
  mkdir -p "$SCRATCH/empty" "$HOME/.claude/skills"
  ln -s "$SCRATCH/empty" "$HOME/.claude/skills/ship-workflow"
  ln -s "$HOME/.claude/skills/ship-workflow/commands/ship-next.md" "$HOME/.claude/commands/ship-next.md"
  run bash "$R/sync.sh" restore --dry-run
  [ "$status" -eq 0 ] || return 1
  if [[ "$output" == *"dangling"*"ship-next.md"* ]]; then echo "$output"; return 1; fi
  run bash "$R/sync.sh" restore --yes
  [ -f "$HOME/.claude/commands/ship-next.md" ]
}

@test "status flags a link whose target is missing" {
  bash "$R/sync.sh" restore --yes >/dev/null
  rm -rf "$R/claude-skills/code-review-skill"
  run bash "$R/sync.sh" status
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == *"code-review-skill"*"target missing"* ]]
}
