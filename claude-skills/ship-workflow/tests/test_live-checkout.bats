#!/usr/bin/env bats
# R-004 §3.7: every session on a machine runs the checkout behind
# ~/.claude/skills/ship-workflow, uncommitted edits included. ship-next warns when that
# checkout is not on main, or is dirty — the machine is not running what shipped.
load helpers

setup() {
  export SCRATCH="$(make_scratch live-checkout)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME/.claude/skills" "$SCRATCH/ai"
  cd "$SCRATCH/ai" || return 1
  git init -q -b main
  mkdir -p claude-skills/ship-workflow && echo x > claude-skills/ship-workflow/SKILL.md
  git add -A && git -c user.email=t@t -c user.name=t commit -q -m base
  ln -s "$SCRATCH/ai/claude-skills/ship-workflow" "$HOME/.claude/skills/ship-workflow"
  source "$SHIP_LIB/live-checkout.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "live_checkout_warning: names the branch when the live checkout is off main" {
  git checkout -q -b ship/R-9-x
  run live_checkout_warning
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship/R-9-x"* ]]
}

@test "live_checkout_warning: on main, warns about uncommitted changes to tracked files" {
  echo y >> claude-skills/ship-workflow/SKILL.md
  run live_checkout_warning
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "live_checkout_warning: silent on a clean main, and an untracked file does not count" {
  echo scratch > untracked.txt
  run live_checkout_warning
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "live_checkout_warning: silent when the live skill is not a link into a checkout" {
  rm "$HOME/.claude/skills/ship-workflow" && mkdir -p "$HOME/.claude/skills/ship-workflow"
  run live_checkout_warning
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ship-next Phase 1 runs the live-checkout warning, from the lib it sources" {
  CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
  blk=$(awk '/^0\.5\. \*\*Which ship-workflow is live/{f=1} /^1\. \*\*Handle `--discard`/{f=0} f' "$CMD" \
        | awk '/^[[:space:]]*```bash[[:space:]]*$/{b=1;next} /^[[:space:]]*```[[:space:]]*$/{b=0} b')
  [ -n "$blk" ] || { echo "no Phase 1 step 0.5 block"; return 1; }
  # Run the block itself. The live checkout carries the lib and sits off main, so the
  # block must print exactly the warning the function prints.
  mkdir -p claude-skills/ship-workflow/lib
  cp "$SHIP_LIB/live-checkout.sh" claude-skills/ship-workflow/lib/
  git add -A && git -c user.email=t@t -c user.name=t commit -q -m lib
  git checkout -q -b ship/R-9-z
  printf '%s\n' "$blk" > "$SCRATCH/p1.sh"
  run bash "$SCRATCH/p1.sh"
  [ "$status" -eq 0 ] || return 1
  [[ "$output" == *"ship/R-9-z"* ]] || return 1
  [ "$output" = "$(live_checkout_warning 2>&1)" ]
}
