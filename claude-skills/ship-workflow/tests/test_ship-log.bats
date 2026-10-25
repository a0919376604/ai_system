#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ship-log)"
  mkdir -p "$SCRATCH/repo/docs/learnings" "$SCRATCH/repo/.claude"
  cd "$SCRATCH/repo"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  git add -A && git commit -q -m base
  source "$SHIP_LIB/ship-log.sh"
}
teardown() { rm -rf "$SCRATCH"; }

mr_mode() { echo 'merge_mode: mr' > .claude/ship-config.yml; }

@test "ship_log: appends the row and makes no commit" {
  before=$(git rev-parse HEAD)
  ship_log "| d | ship-next | R-1 | shipped | n |"
  [ "$(tail -1 docs/learnings/_log.md)" = "| d | ship-next | R-1 | shipped | n |" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "ship_log: refuses an empty row" {
  run ship_log ""
  [ "$status" -eq 2 ]
}

@test "ship_log_ratio_count: counts file rows" {
  printf '%s\n' '| d | ship-next | R-1 | ratio 1 | n |' '| d | ship-next | R-2 | ratio 2 | n |' >> docs/learnings/_log.md
  git commit -q --allow-empty -m trailer -m 'Ship-Log: | d | ship-next | R-3 | ratio 3 | n |'
  run ship_log_ratio_count
  [ "$output" = "2" ]
}

@test "ship_log_ratio_count: 0 in a repo with no commits and no log" {
  rm -rf "$SCRATCH/empty" && mkdir -p "$SCRATCH/empty" && cd "$SCRATCH/empty" && git init -q
  run ship_log_ratio_count
  [ "$output" = "0" ]
}

@test "zsh: ship_log behaves the same as in bash" {
  command -v zsh >/dev/null || skip "zsh not installed"
  mr_mode
  git checkout -q -b ship/R-3-demo
  before=$(git rev-parse HEAD)
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/ship-log.sh'; ship_log '| d | ship-next | R-3 | shipped | n |' && ship_log_ratio_count"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(cat .ship/ship-log-rows)" = "| d | ship-next | R-3 | shipped | n |" ]
  git diff --exit-code -- docs/learnings/_log.md
}

@test "every command writes _log.md rows through ship_log" {
  # A direct append on a review branch is a shared-file write — what made
  # parallel MRs conflict (R-001).
  hits=$(grep -l '>> docs/learnings/_log.md' "$SHIP_SKILL_ROOT"/commands/*.md || true)
  [ -z "$hits" ] || { echo "direct appends in: $hits"; return 1; }
}

@test "ship_log: on a ship/* branch in mr mode, writes .ship/ship-log-rows, not _log.md" {
  mr_mode
  git checkout -q -b ship/R-1-x
  before=$(git rev-parse HEAD)
  ship_log "| d | ship-idea | IDEA-1 | follow-up | n |"
  ship_log "| d | ship-next | R-1 | shipped | n |"
  [ "$(cat .ship/ship-log-rows)" = "$(printf '%s\n' '| d | ship-idea | IDEA-1 | follow-up | n |' '| d | ship-next | R-1 | shipped | n |')" ]
  git diff --exit-code -- docs/learnings/_log.md
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "ship_log: squash mode on a ship/* branch still appends to _log.md" {
  git checkout -q -b ship/R-1-x
  ship_log "squash row"
  [ "$(tail -1 docs/learnings/_log.md)" = "squash row" ]
}

@test "ship_log: mr mode on the base branch appends to _log.md" {
  mr_mode
  ship_log "base row"
  [ "$(tail -1 docs/learnings/_log.md)" = "base row" ]
}
