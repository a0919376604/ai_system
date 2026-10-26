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

# R-013: sn_status records the ship's phase for the Roadmap 檢視 plugin.
status_fixture() {
  export HOME="$SCRATCH/home"
  vault=$(make_fake_airos "$SCRATCH" wt)
  write_global_config "$HOME" "$vault"
  export PROJ="$vault/10 Projects/wt"
  bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-9; sn_state_set "$WT" BRANCH ship/R-9-x'
}

# warns_once <shell> <script> — the script exits 0 and prints exactly one WARN line.
warns_once() {
  run "$1" -c "source \"\$SHIP_LIB/ship-next.sh\"; $2"
  [ "$status" -eq 0 ] && [ "${#lines[@]}" -eq 1 ] && [[ "$output" == WARN:* ]] || { echo "$1: $output"; return 1; }
}

@test "sn_status records each phase in the vault project's ship-status file" {
  status_fixture
  for shell in bash zsh; do
    rm -rf "$PROJ/ship-status"
    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; sn_status "$WT" plan && sn_status "$WT" blocked "codex: 3 attempts"'
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$shell: $output"; return 1; }
    f="$PROJ/ship-status/R-9.json"
    [ "$(jq -r .id "$f")" = R-9 ]
    [ "$(jq -r .phase "$f")" = blocked ]
    [ "$(jq -r .note "$f")" = "codex: 3 attempts" ]
    [ "$(jq -r .branch "$f")" = ship/R-9-x ]
    [ "$(jq -r '[.phases[].phase] | join(",")' "$f")" = plan,blocked ]
    [ "$(jq -r '.phases[1].note' "$f")" = "codex: 3 attempts" ]
    [ "$(jq -r '.updated, .phases[].at' "$f" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')" -eq 3 ]
    [ "$(ls -A "$PROJ/ship-status")" = R-9.json ]
  done
}

@test "sn_status without a vault config warns once and writes nothing" {
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
  bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-9'
  for shell in bash zsh; do
    warns_once "$shell" 'sn_status "$WT" plan'
  done
  [ -z "$(find "$SCRATCH" -name 'R-9*.json')" ]
}

@test "sn_status with an unwritable project dir warns once and writes nothing" {
  status_fixture
  chmod 555 "$PROJ"
  for shell in bash zsh; do
    warns_once "$shell" 'sn_status "$WT" plan' || { chmod 755 "$PROJ"; return 1; }
  done
  chmod 755 "$PROJ"
  [ ! -e "$PROJ/ship-status" ]
}

@test "sn_status never creates a vault project folder that is not there" {
  status_fixture
  rm -rf "$PROJ"
  for shell in bash zsh; do
    warns_once "$shell" 'sn_status "$WT" plan'
  done
  [ ! -e "$PROJ" ]
}

@test "sn_status leaves a status file it cannot parse as it is" {
  status_fixture
  mkdir -p "$PROJ/ship-status"
  echo 'not json' > "$PROJ/ship-status/R-9.json"
  for shell in bash zsh; do
    warns_once "$shell" 'sn_status "$WT" review'
  done
  [ "$(cat "$PROJ/ship-status/R-9.json")" = 'not json' ]
  [ "$(ls -A "$PROJ/ship-status")" = R-9.json ]
}

@test "sn_status refuses a phase outside the list and an ID that is not a plain R-NNN" {
  status_fixture
  for shell in bash zsh; do
    warns_once "$shell" 'sn_status "$WT" planning'
    warns_once "$shell" 'sn_status "$WT"'
  done
  rm -rf "$WT/.ship"
  for shell in bash zsh; do
    warns_once "$shell" 'ID="../../x"; sn_status "$WT" done'
  done
  [ ! -e "$PROJ/ship-status" ]
  [ -z "$(find "$SCRATCH" -name '*.json')" ]
}

@test "sn_status takes the caller's ID and BRANCH when the dir has no ship state (/ship-land)" {
  status_fixture
  rm -rf "$WT/.ship"
  for shell in bash zsh; do
    run "$shell" -c 'source "$SHIP_LIB/ship-next.sh"; ID=R-9; BRANCH=ship/R-9-y; sn_status "$WT" done'
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$shell: $output"; return 1; }
  done
  [ "$(jq -r '.phase + " " + .branch' "$PROJ/ship-status/R-9.json")" = 'done ship/R-9-y' ]
}

# section <N> — the body of `## Phase N — …` in ship-next.md.
section() { awk -v h="## Phase $1 " 'index($0, h) == 1 {f=1; next} /^## /{f=0} f' "$SHIP_SKILL_ROOT/commands/ship-next.md"; }

@test "ship-next records every phase where it starts, and blocked on each stop path" {
  for pair in 2:brainstorm 4:plan 5:build 6:review 7:landing 8:done 8:in-review; do
    section "${pair%%:*}" | grep -qF "sn_status \"\$WORKTREE\" ${pair#*:}" || { echo "Phase ${pair%%:*} does not record ${pair#*:}"; return 1; }
  done
  section 4 | grep -F 'Small-change lane' | grep -qF 'sn_status "$WORKTREE" build'
  for anchor in 'CODEX_ROUTE=stop_exhausted' '| **spec-level** |' 'cap=3 exhausted' '[n] Pause indefinitely'; do
    grep -F -A6 -- "$anchor" "$SHIP_SKILL_ROOT/commands/ship-next.md" | grep -qF 'sn_status "$WORKTREE" blocked' \
      || { echo "no blocked status at: $anchor"; return 1; }
  done
}

@test "ship-next --adhoc passes a human summary to roadmap-insert" {
  section 1 | grep -F 'roadmap-insert.sh' | grep -qF -- '--adhoc --summary "$SUMMARY_ZH"'
  section 1 | grep -qE '^ *SUMMARY_ZH=.*zh-TW'
}

@test "a codex infra stop records the ship as blocked, with the reason" {
  status_fixture
  echo 'ERROR: Your workspace is out of credits.' > "/tmp/run-plan-codex-${SLOT}.log"
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_codex_after_exit "$WT" "$PLAN" "$SLOT"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'CODEX_ROUTE=stop_infra'* ]] || return 1
  [ "$(jq -r .phase "$PROJ/ship-status/R-9.json")" = blocked ] || return 1
  [[ "$(jq -r .note "$PROJ/ship-status/R-9.json")" == "codex infra: "* ]]
}

# Each fenced block runs in a fresh shell, so a block — or an inline `…` command —
# that calls sn_status must source lib/ship-next.sh itself.
@test "every sn_status call in a command file sources lib/ship-next.sh in its own shell" {
  for f in "$SHIP_SKILL_ROOT"/commands/*.md; do
    run awk '
      /^[[:space:]]*```bash[[:space:]]*$/ { inb = 1; blk = ""; calls = 0; next }
      inb && /^[[:space:]]*```[[:space:]]*$/ {
        inb = 0
        if (calls && blk !~ /lib\/ship-next\.sh/) print FILENAME ": a block calls sn_status without sourcing lib/ship-next.sh"
        next
      }
      inb { blk = blk "\n" $0; if ($0 ~ /sn_status "/) calls = 1; next }
      /sn_status "/ && $0 !~ /source ~\/\.claude\/skills\/ship-workflow\/lib\/ship-next\.sh && sn_status "/ {
        print FILENAME ":" FNR ": an inline sn_status call does not source lib/ship-next.sh"
      }
    ' "$f"
    [ -z "$output" ] || { echo "$output"; return 1; }
  done
  sed -n '/^sn_codex_after_exit()/,/^}/p' "$SHIP_LIB/ship-next.sh" | grep -qF 'sn_status "$WORKTREE" blocked'
}

dep_fixture() {
  cd "$WT"
  git init -q -b main && git config user.email t@t && git config user.name t
  printf '{\n  "name": "app",\n  "version": "1.0.0",\n  "dependencies": {\n    "react": "^19.0.0"\n  }\n}\n' > package.json
  printf 'fastapi==0.110\n' > requirements.txt
  git add . && git commit -qm base
  git checkout -qb ship/R-1-x
}

@test "sn_new_deps lists added dependencies, not version bumps, comments or lockfiles" {
  dep_fixture
  printf '{\n  "name": "app",\n  "version": "1.0.1",\n  "dependencies": {\n    "react": "^19.0.0",\n    "left-pad": "^1.3.0"\n  }\n}\n' > package.json
  printf 'fastapi==0.110\n# pinned for R-1\nrequests==2.31\n' > requirements.txt
  echo '{"lockfileVersion": 3, "x": "1.0.0"}' > package-lock.json
  git add . && git commit -qm deps
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'package.json\tleft-pad\nrequirements.txt\trequests')" ]
}

@test "mechanical gates block a new dependency the spec does not justify, and pass a justified one" {
  dep_fixture
  printf '{\n  "name": "app",\n  "version": "1.0.0",\n  "dependencies": {\n    "react": "^19.0.0",\n    "left-pad": "^1.3.0"\n  }\n}\n' > package.json
  git add . && git commit -qm dep
  mkdir -p docs/specs && printf '## Decisions\n- something else\n' > docs/specs/R-1-x.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-1; sn_state_set "$WT" SLUG x; sn_mech_gates "$WT" main "$WT/no-plan.md"; sn_state_load "$WT"; echo "MB=$MECH_BLOCKERS"'
  [[ "$output" == *"left-pad"* ]] || return 1
  [ "$(printf '%s\n' "$output" | tail -1)" = "MB=1" ] || { echo "$output"; return 1; }
  printf '## Decisions\n- New dependency: left-pad — nothing in the stdlib pads\n' > docs/specs/R-1-x.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_mech_gates "$WT" main "$WT/no-plan.md"; sn_state_load "$WT"; echo "MB=$MECH_BLOCKERS"'
  [ "$(printf '%s\n' "$output" | tail -1)" = "MB=0" ] || { echo "$output"; return 1; }
}

@test "review extra checks list the five ponytail tags" {
  dep_fixture
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_mech_gates "$WT" main "$WT/no-plan.md" >/dev/null 2>&1; cat "$WT/.ship/review-extra-checks.md"'
  for t in delete stdlib native yagni shrink; do
    [[ "$output" == *"[ponytail:$t]"* ]] || { echo "missing $t"; return 1; }
  done
}

@test "one New dependency line can list several names, matched as whole names" {
  dep_fixture
  printf '{\n  "dependencies": {\n    "react": "^19.0.0",\n    "react-dom": "^19.0.0",\n    "left-pad": "^1.3.0"\n  }\n}\n' > package.json
  git add . && git commit -qm deps
  mkdir -p docs/specs && printf '## Decisions\n- New dependency: `react-dom`, left-pad — needed for X\n' > docs/specs/R-1-x.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-1; sn_state_set "$WT" SLUG x; sn_mech_gates "$WT" main "$WT/no-plan.md"; sn_state_load "$WT"; echo "MB=$MECH_BLOCKERS"'
  [ "$(printf '%s\n' "$output" | tail -1)" = "MB=0" ] || { echo "$output"; return 1; }
}

@test "sn_new_deps ignores pyproject lists that are not dependencies, and finds real ones" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '[project]\nname = "app"\ndependencies = [\n  "fastapi>=0.110",\n]\nclassifiers = [\n  "License :: OSI",\n]\n\n[tool.ruff.lint]\nselect = [\n  "E",\n]\n' > pyproject.toml
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf '[project]\nname = "app"\ndependencies = [\n  "fastapi>=0.110",\n  "httpx[http2]>=0.27",\n]\nclassifiers = [\n  "License :: OSI",\n  "Programming Language :: Python",\n]\nkeywords = [\n  "llm",\n]\n\n[project.optional-dependencies]\ndev = ["pytest>=8", "ruff"]\n\n[tool.ruff.lint]\nselect = [\n  "E",\n  "F",\n  "UP",\n]\n' > pyproject.toml
  git commit -qam edit
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'pyproject.toml\thttpx\npyproject.toml\tpytest\npyproject.toml\truff')" ] || { echo "$output"; return 1; }
}

@test "sn_new_deps ignores package.json scripts, engines and overrides" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '{\n  "scripts": {\n    "test": "vitest"\n  },\n  "dependencies": {\n    "react": "^19.0.0"\n  }\n}\n' > package.json
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf '{\n  "scripts": {\n    "test": "vitest",\n    "precommit": "git diff --check"\n  },\n  "engines": {\n    "node": ">=20",\n    "pnpm": ">=9"\n  },\n  "overrides": {\n    "semver": "^7.6.0"\n  },\n  "dependencies": {\n    "react": "^19.0.0"\n  }\n}\n' > package.json
  git commit -qam edit
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "sn_new_deps reads plain multi-line pyproject entries, extras, comments, dependency-groups and name case" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '[project]\ndependencies = [\n  "uvicorn[standard]>=0.29",\n  "FastAPI>=0.110",\n  "pydantic",\n]\n' > pyproject.toml
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf '[project]\ndependencies = [\n  "uvicorn[standard]>=0.29",\n  "fastapi>=0.111",\n  "pydantic",\n  "httpx>=0.27",\n  # "celery",  (later)\n]\n\n[dependency-groups]\ndev = [\n  "pytest>=8",\n]\n' > pyproject.toml
  git commit -qam edit
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'pyproject.toml\thttpx\npyproject.toml\tpytest')" ] || { echo "$output"; return 1; }
}

@test "sn_new_deps finds a manifest under a non-ASCII directory" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  mkdir -p 前端 && printf '{"dependencies": {"react": "^19.0.0"}}\n' > 前端/package.json
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf '{"dependencies": {"react": "^19.0.0", "zod": "^3.23.0"}}\n' > 前端/package.json
  git commit -qam edit
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$output" = "$(printf '前端/package.json\tzod')" ] || { echo "$output"; return 1; }
}

@test "sn_new_deps skips include-group tables and quoted keys, and reads CRLF files" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'fastapi==0.110\r\n' > requirements.txt
  printf '[project]\nname = "app"\n' > pyproject.toml
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf 'fastapi==0.110\r\nrequests==2.31\r\n' > requirements.txt
  printf '[project]\nname = "app"\n\n[project.optional-dependencies]\n"dev" = ["ruff"]\n\n[dependency-groups]\nci = [\n  {include-group = "test"},\n  "coverage",\n]\n' > pyproject.toml
  git commit -qam edit
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_new_deps main HEAD'
  [ "$output" = "$(printf 'pyproject.toml\tcoverage\npyproject.toml\truff\nrequirements.txt\trequests')" ] || { echo "$output" | cat -v; return 1; }
}

@test "a New dependency line written with underscores or dots clears the normalized name" {
  cd "$WT" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'fastapi==0.110\n' > requirements.txt
  git add . && git commit -qm base && git checkout -qb ship/R-1-x
  printf 'fastapi==0.110\ntyping_extensions>=4\nzope.interface\n' > requirements.txt
  git commit -qam deps
  mkdir -p docs/specs && printf '## Decisions\n- New dependency: typing_extensions, zope.interface — needed\n' > docs/specs/R-1-x.md
  run bash -c 'source "$SHIP_LIB/ship-next.sh"; sn_state_set "$WT" ID R-1; sn_state_set "$WT" SLUG x; sn_mech_gates "$WT" main "$WT/no-plan.md"; sn_state_load "$WT"; echo "MB=$MECH_BLOCKERS"'
  [ "$(printf '%s\n' "$output" | tail -1)" = "MB=0" ] || { echo "$output"; return 1; }
}
