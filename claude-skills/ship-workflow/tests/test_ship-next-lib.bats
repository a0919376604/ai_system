#!/usr/bin/env bats
load helpers

setup() {
  export SHIP_LIB
  export SCRATCH="$(make_scratch ship-next-lib)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  export SLOT="R010-test-$$-$BATS_TEST_NUMBER"
  export PLAN="$WT/plan.md"
  echo plan > "$PLAN"
}
teardown() {
  rm -rf "$SCRATCH"
  rm -f "/tmp/run-plan-codex-${SLOT}.log" "/tmp/codex-report-${SLOT}.md"
}

@test "state values round-trip between fresh bash and zsh shells" {
  export VALUE='x y "z"'
  for writer in bash zsh; do
    run "$writer" -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" A "$VALUE"'
    [ "$status" -eq 0 ]
    for reader in bash zsh; do
      run "$reader" -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$WT"; printf "%s" "$A"'
      [ "$output" = "$VALUE" ]
    done
  done
}

@test "state set replaces an existing key" {
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" A old; sn_state_set "$WT" A new; cat "$WT/.ship/state.env"'
  [ "$output" = 'A=new' ]
}

@test "state load without state is a no-op" {
  for shell in bash zsh; do
    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$WT"'
    [ "$status" -eq 0 ]
  done
}

mech_fixture() {
  cd "$WT"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  printf 'echo one\necho two\n' > app.sh
  mkdir tests
  echo '# baseline' > tests/app.bats
  git add . && git commit -qm base
  git checkout -qb ship/test
  printf '### Task 1: refactor\nSeam: none\n' > "$PLAN"
  echo '# added' >> tests/app.bats
  git add tests && git commit -qm 'refactor: Task 1'
}

@test "mechanical gates report a refactor test-line violation" {
  mech_fixture
  for shell in bash zsh; do
    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_mech_gates "$WT" main "$PLAN"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'refactor task added test lines (Task 1, +1 in tests)'* ]] || return 1
  done
}

@test "mechanical gates persist all six results across shells" {
  mech_fixture
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_mech_gates "$WT" main "$PLAN"'
  [ "$status" -eq 0 ]
  run zsh -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$WT"; printf "%s\n" "$MECH_BLOCKERS $TEST_BUDGET_VERDICT $SHIP_RATIO_BP $BASELINE_RATIO_BP $TEST_LINES_ADDED $SRC_LINES_ADDED"'
  [ "$output" = '1 pass 0 1000 1 0' ]
}

@test "mechanical gates report shadow mode and provide review categories" {
  mech_fixture
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_mech_gates "$WT" main "$PLAN"'
  [[ "$output" == *'shadow mode — reporting only'* ]] || return 1
  for tag in seam-violation assertion-roulette weak-assertion pre-existing; do
    grep -qF "[$tag]" "$WT/.ship/review-extra-checks.md"
  done
}

# Same whole-log marker shapes as the existing codex verdict fixtures.
@test "codex success routes to continue and records one round" {
  for verdict in DONE DONE_WITH_CONCERNS; do
    rm -rf "$WT/.ship"
    printf '**%s**\n- completed\n' "$verdict" > "/tmp/run-plan-codex-${SLOT}.log"
    run bash -c 'source "$SHIP_LIB/ship-next.sh"; CODEX_ATTEMPT=0; sn_codex_after_exit "$WT" "$PLAN" "$SLOT"'
    [ "$status" -eq 0 ]
    [[ "$output" == *'CODEX_ROUTE=continue'* ]] || return 1
    run bash -c 'source "$SHIP_LIB/codex-rounds.sh"; codex_round_count "$WT"'
    [ "$output" = 1 ]
    grep -q '^last_verdict: done' "$WT/.ship/codex-supervise.md"
  done
}

@test "codex BLOCKED routes to classify without recording the unclassified round" {
  printf '**BLOCKED**\n- needs classification\n' > "/tmp/run-plan-codex-${SLOT}.log"
  run zsh -c 'source "$SHIP_LIB/ship-next.sh"; sn_codex_after_exit "$WT" "$PLAN" "$SLOT"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'CODEX_ROUTE=classify'* ]] || return 1
  [ ! -e "$WT/.ship/codex-rounds.md" ]
  [ ! -e "$WT/.ship/codex-supervise.md" ]
}

@test "codex infra without a report stops without recording a round" {
  echo 'ERROR: Your workspace is out of credits.' > "/tmp/run-plan-codex-${SLOT}.log"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_codex_after_exit "$WT" "$PLAN" "$SLOT"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'CODEX_ROUTE=stop_infra'* ]] || return 1
  [ ! -e "$WT/.ship/codex-rounds.md" ]
  [ ! -e "$WT/.ship/codex-supervise.md" ]
}

@test "ship body works without a plan file and reads persisted gate values" {
  export HOME="$SCRATCH/home"
  vault=$(make_fake_airos "$SCRATCH" wt)
  write_global_config "$HOME" "$vault"
  printf '**R-1** Example
↳ done when: Ready
' > "$vault/10 Projects/wt/ROADMAP.md"
  rm "$PLAN"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" TEST_LINES_ADDED 3; sn_state_set "$WT" SRC_LINES_ADDED 9; sn_state_set "$WT" SHIP_RATIO_BP 333; sn_state_set "$WT" BASELINE_RATIO_BP 500'
  [ "$status" -eq 0 ]
  for shell in bash zsh; do
    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_ship_body "$WT" R-1 x "$WT/body.md"'
    [ "$status" -eq 0 ]
    grep -qF '↳ done when: Ready' "$WT/body.md"
    grep -qF 'Tests: +3 / Src: +9  (ratio 333bp vs baseline 500bp)' "$WT/body.md"
  done
}

@test "land squash merges and persists the resulting commit" {
  mech_fixture
  git checkout -q main
  git worktree add -q "$SCRATCH/ship" ship/test
  echo body > "$SCRATCH/body"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_land "$SCRATCH/ship" R-1 ship/test main "feat: R-1" "$SCRATCH/body"'
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'feat: R-1' ]
  run zsh -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$SCRATCH/ship"; echo "$MERGE_SHA"'
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "land mr pushes and opens a review without moving the base branch" {
  mech_fixture
  git checkout -q main
  mkdir -p .claude "$SCRATCH/bin"
  echo 'merge_mode: mr' > .claude/ship-config.yml
  git init -q --bare "$SCRATCH/github.com.git"
  git remote add origin "$SCRATCH/github.com.git"
  git worktree add -q "$SCRATCH/ship" ship/test
  echo body > "$SCRATCH/body"
  printf '#!/bin/sh\necho https://github.com/example/repo/pull/1\n' > "$SCRATCH/bin/gh"
  chmod +x "$SCRATCH/bin/gh"
  before=$(git rev-parse main)
  run env PATH="$SCRATCH/bin:$PATH" zsh -c 'source "$SHIP_LIB/ship-next.sh"; sn_land "$SCRATCH/ship" R-1 ship/test main "feat: R-1" "$SCRATCH/body"'
  [ "$status" -eq 0 ]
  [ "$(git rev-parse main)" = "$before" ]
  [ "$(git --git-dir="$SCRATCH/github.com.git" rev-parse ship/test)" = "$(git rev-parse ship/test)" ]
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$SCRATCH/ship"; echo "$SHIP_REVIEW_URL"'
  [ "$output" = 'https://github.com/example/repo/pull/1' ]
}

@test "accepted resume preserves the current invocation's AUTO mode in fresh shells" {
  # Execute the resume state block, then enter a later phase in a fresh shell.
  awk '/^7\. \*\*Detect existing worktree/{f=1} /^## Phase 2/{f=0} f' \
    "$SHIP_SKILL_ROOT/commands/ship-next.md" \
    | awk '/^[[:space:]]*```bash/{f=1;next} /^[[:space:]]*```/{f=0} f' \
    | sed 's#~/.claude/skills/ship-workflow/lib/#"$SHIP_LIB"/#g' > "$SCRATCH/resume.sh"
  export WORKTREE="$WT" ID=R-1 SLUG=x BRANCH=ship/R-1-x ORIG_BRANCH=main REPO="$SCRATCH" DESCRIPTION=Example
  for shell in bash zsh; do
    for mode in 0 1; do
      run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" AUTO "$1"' -- "$((1 - mode))"
      [ "$status" -eq 0 ]
      run env AUTO="$mode" "$shell" "$SCRATCH/resume.sh"
      [ "$status" -eq 0 ]
      run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_load "$WT"; echo "$AUTO"'
      [ "$output" = "$mode" ]
    done
  done
}

@test "land squash from a linked-worktree checkout lands on that checkout's branch, not main" {
  mech_fixture
  git checkout -q main
  git worktree add -q -b wt1 "$SCRATCH/base" main
  git -C "$SCRATCH/base" merge -q --ff-only main
  git worktree add -q "$SCRATCH/ship" ship/test
  echo body > "$SCRATCH/body"
  main_before=$(git rev-parse main)
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$SCRATCH/ship" REPO "$SCRATCH/base"; sn_land "$SCRATCH/ship" R-1 ship/test wt1 "feat: R-1" "$SCRATCH/body"'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(git rev-parse main)" = "$main_before" ] || { echo "landed on main"; return 1; }
  [ "$(git log -1 --format=%s wt1)" = 'feat: R-1' ]
}

@test "ship body lines start at column 0" {
  export HOME="$SCRATCH/home"
  vault=$(make_fake_airos "$SCRATCH" wt)
  write_global_config "$HOME" "$vault"
  printf '**R-1** Example\n↳ done when: Ready\n' > "$vault/10 Projects/wt/ROADMAP.md"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_ship_body "$WT" R-1 x "$WT/body.md"'
  [ "$status" -eq 0 ]
  [ "$(head -1 "$WT/body.md")" = '↳ done when: Ready' ]
  ! grep -qE '^   [^ ]' "$WT/body.md" || { cat "$WT/body.md"; return 1; }
}

@test "state set refuses an empty worktree" {
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "" K V'
  [ "$status" -ne 0 ]
}

@test "Phase 1 derives DESCRIPTION and resume never blanks a stored one" {
  grep -qE '^5\. \*\*Derive slug and DESCRIPTION' "$SHIP_SKILL_ROOT/commands/ship-next.md"

  grep -qF 'if [ -n "$DESCRIPTION" ]; then sn_state_set "$WORKTREE" DESCRIPTION' "$SHIP_SKILL_ROOT/commands/ship-next.md"
}

@test "the state archive lives in the repo's git dir, never in shared /tmp" {
  mech_fixture
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_archive_path R-1'
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse --path-format=absolute --git-common-dir)/ship-R-1-state.env" ]
  ! grep -qE '/tmp/ship-[^ ]*state\.env' "$SHIP_LIB/ship-next.sh" || { grep -nE '/tmp/ship-[^ ]*state\.env' "$SHIP_LIB/ship-next.sh"; return 1; }
}
