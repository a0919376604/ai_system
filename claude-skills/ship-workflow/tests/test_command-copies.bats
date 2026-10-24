#!/usr/bin/env bats
# R-004 §3.4: ship-workflow commands are installed once per machine, so no project
# carries a copy. ship-init used to copy commands/*.md into every repo, and on
# 2026-10-23 six repos held 60 copies, none current. remove_command_copies clears them.
load helpers

setup() {
  export SCRATCH="$(make_scratch command-copies)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME/.claude/commands" "$SCRATCH/live"
  echo live > "$SCRATCH/live/ship-next.md"
  ln -s "$SCRATCH/live/ship-next.md" "$HOME/.claude/commands/ship-next.md"
  mkdir -p "$SCRATCH/repo/.claude/commands" && cd "$SCRATCH/repo" || return 1
  git init -q -b main
  git config user.email t@t && git config user.name t
  printf '%s\n' '.claude/commands/ship-build.md' > .gitignore
  for f in ship-next ship-propose my-own ship-build; do echo "$f" > ".claude/commands/$f.md"; done
  git add .gitignore .claude/commands/ship-next.md .claude/commands/ship-propose.md .claude/commands/my-own.md
  git commit -q -m base
  source "$SHIP_LIB/command-copies.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "remove_command_copies: tracked copies are git rm'd and staged, ignored ones deleted, others kept" {
  head_before=$(git rev-parse HEAD)
  run remove_command_copies "$SCRATCH/repo"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e .claude/commands/ship-next.md ] && [ ! -e .claude/commands/ship-propose.md ] || return 1
  [ ! -e .claude/commands/ship-build.md ] || { echo "ignored copy kept"; return 1; }
  [ -f .claude/commands/my-own.md ] || { echo "removed a non-ship command"; return 1; }
  [ "$(git diff --cached --name-status | sort | tr '\n' ' ')" = "D	.claude/commands/ship-next.md D	.claude/commands/ship-propose.md " ] || return 1
  [ "$(git rev-parse HEAD)" = "$head_before" ] || { echo "it committed"; return 1; }
}

@test "remove_command_copies: refuses, removing nothing, when the user-level ship-next does not resolve" {
  rm "$SCRATCH/live/ship-next.md"   # the link now dangles
  run remove_command_copies "$SCRATCH/repo"
  [ "$status" -ne 0 ] || return 1
  [[ "$output" == *"ship-next.md"* ]] || return 1
  [ "$(ls .claude/commands | sort | tr '\n' ' ')" = "my-own.md ship-build.md ship-next.md ship-propose.md " ]
}

@test "remove_command_copies: works in a linked worktree" {
  git worktree add -q -b wt "$SCRATCH/repo-wt"
  echo ship-build > "$SCRATCH/repo-wt/.claude/commands/ship-build.md"
  run remove_command_copies "$SCRATCH/repo-wt"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cd "$SCRATCH/repo-wt" || return 1
  [ "$(git diff --cached --name-status | sort | tr '\n' ' ')" = "D	.claude/commands/ship-next.md D	.claude/commands/ship-propose.md " ] || return 1
  [ ! -e .claude/commands/ship-build.md ] && [ -f .claude/commands/my-own.md ]
}

@test "remove_command_copies: a tracked copy with local edits is left alone and reported" {
  echo "my local tweak" >> .claude/commands/ship-next.md
  run remove_command_copies "$SCRATCH/repo"
  [ "$status" -eq 0 ] || return 1
  grep -qF 'my local tweak' .claude/commands/ship-next.md || { echo "local edits lost"; return 1; }
  [[ "$output" == *"ship-next.md"* ]] || return 1
  [ ! -e .claude/commands/ship-propose.md ]
}

@test "ship-init no longer copies commands, and its --upgrade step removes the copies" {
  CMD="$SHIP_SKILL_ROOT/commands/ship-init.md"
  if grep -nE 'cp [^ ]*ship-workflow/commands|git add [^|]*\.claude/commands' "$CMD"; then
    echo "ship-init still copies or commits commands"; return 1
  fi
  if grep -nE '/ship-(propose|explain|research|decision|roadmap|brief|arch)([^a-z-]|$)' "$CMD"; then
    echo "ship-init points at a removed command"; return 1
  fi
  blk=$(awk '/^2\. \*\*`--upgrade`/{f=1} /^3\. \*\*Scaffold repo side/{f=0} f' "$CMD" \
        | awk '/^[[:space:]]*```bash[[:space:]]*$/{b=1;next} /^[[:space:]]*```[[:space:]]*$/{b=0} b')
  [ -n "$blk" ] || { echo "no --upgrade block"; return 1; }
  mkdir -p "$HOME/.claude/skills" && ln -s "$SHIP_SKILL_ROOT" "$HOME/.claude/skills/ship-workflow"
  printf '%s\n' "$blk" > "$SCRATCH/upgrade.sh"
  run bash "$SCRATCH/upgrade.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e .claude/commands/ship-next.md ] && [ -f .claude/commands/my-own.md ]
}

@test "remove_command_copies: refuses when the repo's commands dir is the user-level one" {
  # /ship-init --upgrade from a session started in ~ would otherwise delete the live links.
  run remove_command_copies "$HOME"
  [ "$status" -ne 0 ] || return 1
  [ -L "$HOME/.claude/commands/ship-next.md" ]
}
