#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch compound-lessons)"
  mkdir -p "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q
}
teardown() { rm -rf "$SCRATCH"; }

s6b() { awk '/^6b\./,/^7\./' "$SHIP_SKILL_ROOT/commands/ship-compound.md"; }

@test "step 6b turns mechanical lessons into proven checks" {
  for needle in tdd_rules_prove tdd_rules_table enforced judgment 'lesson: ${ID}'; do
    s6b | grep -qF "$needle" || return 1
  done
  s6b | grep -qE 'tdd_rules_append "\$ID" "[^"]*" "[^"]*"'
}

@test "step 6b checks the over-cap and unsourced warnings still run" {
  s6b | grep -qF tdd_rules_over_cap
  s6b | grep -qF tdd_rules_unsourced
}

@test "step 6b bash block runs under bash and zsh" {
  s6b | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' |
    sed '/^[[:space:]]*#/d' |
    sed "s|~/.claude/skills/ship-workflow/lib|$SHIP_LIB|g" > "$SCRATCH/block.sh"
  [ -s "$SCRATCH/block.sh" ]
  for shell in bash zsh; do
    run env ID=R-9 "$shell" "$SCRATCH/block.sh"
    [ "$status" -eq 0 ] || { echo "$shell: $output"; return 1; }
    [[ "$output" != *"command not found"* ]] || return 1
  done
}

@test "the learning template and step 4 name Lessons to checks" {
  grep -qxF '## Lessons → checks' "$SHIP_SKILL_ROOT/templates/repo/LEARNING.md"
  awk '/^4\./,/^5\./' "$SHIP_SKILL_ROOT/commands/ship-compound.md" | grep -qF 'Lessons → checks'
}
