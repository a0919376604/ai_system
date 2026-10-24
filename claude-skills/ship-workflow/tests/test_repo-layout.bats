#!/usr/bin/env bats
# R-004: ai_system is ship-workflow's home. It holds ship-workflow and the two skills
# ship-next needs — run-plan and code-review-skill — and nothing else.
load helpers

setup() { export REPO_ROOT="$(cd "$SHIP_SKILL_ROOT/../.." && pwd)"; }

@test "claude-skills holds exactly ship-workflow, run-plan and code-review-skill" {
  run bash -c "ls -1 '$REPO_ROOT/claude-skills' | sort | tr '\n' ' '"
  [ "$output" = "code-review-skill run-plan ship-workflow " ]
}

@test "run-plan carries the REPAIR RULE" {
  grep -qF 'REPAIR RULE — small plan defects are yours to fix; do NOT stop for them:' \
    "$REPO_ROOT/claude-skills/run-plan/SKILL.md"
}

@test "code-review-skill is vendored with its license and its source, without .git" {
  d="$REPO_ROOT/claude-skills/code-review-skill"
  [ -f "$d/SKILL.md" ] || return 1
  [ -f "$d/LICENSE" ] || return 1
  grep -qF 'https://github.com/awesome-skills/code-review-skill' "$d/VENDORED.md" || return 1
  grep -qF '17267ff' "$d/VENDORED.md" || return 1
  [ ! -e "$d/.git" ]
}

@test "ship-workflow keeps exactly the five commands ship-next uses" {
  run bash -c "ls -1 '$SHIP_SKILL_ROOT/commands' | sort | tr '\n' ' '"
  [ "$output" = "ship-compound.md ship-idea.md ship-init.md ship-land.md ship-next.md " ]
}

@test "no kept file sends anyone to a removed command or the old devsync install" {
  # ship-init.md is pinned separately: its copy step goes away with the copies (R-004 §3.4).
  cd "$SHIP_SKILL_ROOT"
  run bash -c "grep -rnE '/ship-(propose|explain|research|decision|roadmap|brief|arch)([^a-z-]|$)|devsync push' \
    commands/ship-next.md commands/ship-compound.md commands/ship-idea.md commands/ship-land.md \
    SKILL.md README.md references templates lib"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "ship-next's missing-code-review-skill hint installs it from this repo" {
  step=$(awk '/^1\. \*\*Verify code-review-skill installed/,/^1\.5\. /' "$SHIP_SKILL_ROOT/commands/ship-next.md")
  [ -n "$step" ] || return 1
  echo "$step" | grep -qF './sync.sh restore' || { echo "hint does not point at sync.sh restore"; return 1; }
  if echo "$step" | grep -qF 'git clone'; then echo "hint still clones by hand"; return 1; fi
}

@test "the repo CLAUDE.md holds this repo's rules; the global one is backed up separately" {
  # The root CLAUDE.md used to double as the backup of ~/.claude/CLAUDE.md — six sections
  # behind it, and sync.sh restore would have copied it over the newer global file.
  if grep -nE '^# Global Claude operating notes|^## (Post-pull sync|Research output language|langlive VPN)' "$REPO_ROOT/CLAUDE.md"; then
    echo "the repo CLAUDE.md is still a copy of the global notes"; return 1
  fi
  grep -qF './sync.sh backup' "$REPO_ROOT/CLAUDE.md" || { echo "no rule for backing up the global file"; return 1; }
  [ -s "$REPO_ROOT/config/claude/CLAUDE.md" ]
}

@test "the root README shows no ↳ explain line — nothing writes or reads it any more" {
  if grep -n '↳ explain' "$REPO_ROOT/README.md"; then return 1; fi
}
