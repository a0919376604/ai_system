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

@test "ship_log: squash mode appends the row and makes no commit" {
  before=$(git rev-parse HEAD)
  ship_log "| d | ship-next | R-1 | shipped | n |"
  [ "$(tail -1 docs/learnings/_log.md)" = "| d | ship-next | R-1 | shipped | n |" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "ship_log: mr mode on a ship/* branch makes one empty commit with a Ship-Log trailer" {
  mr_mode
  git checkout -q -b ship/R-1-demo
  before=$(git rev-parse HEAD)
  cp docs/learnings/_log.md "$BATS_TEST_TMPDIR/log.before"
  printf "staged work\n" > staged.txt
  git add staged.txt
  index_before=$(git write-tree)
  ship_log "| d | ship-next | R-1 | shipped | n |"
  [ "$(git rev-list --count "$before"..HEAD)" -eq 1 ]
  [ -z "$(git diff --name-only "$before" HEAD)" ] || { echo "the log commit changed files"; return 1; }
  cmp -s docs/learnings/_log.md "$BATS_TEST_TMPDIR/log.before" || { echo "_log.md was written"; return 1; }
  [ "$(git log -1 --format='%(trailers:key=Ship-Log,valueonly)' | sed '/^$/d')" = "| d | ship-next | R-1 | shipped | n |" ]
  [ "$(git log -1 --format=%s)" = "log: ship-next R-1" ]
  [ "$(git write-tree)" = "$index_before" ]
  [ "$(git diff --cached --name-only)" = "staged.txt" ]
}

@test "ship_log: mr mode on the base branch still appends" {
  mr_mode
  before=$(git rev-parse HEAD)
  ship_log "| d | ship-idea | IDEA-9 | x | n |"
  [ "$(tail -1 docs/learnings/_log.md)" = "| d | ship-idea | IDEA-9 | x | n |" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "ship_log: defers from a subdirectory too" {
  # merge_mode reads .claude/ship-config.yml relative to the working directory.
  mr_mode
  git checkout -q -b ship/R-1-demo
  mkdir -p deep/dir && cd deep/dir
  before=$(git rev-parse HEAD)
  ship_log "| d | ship-idea | IDEA-1 | x | n |"
  [ "$(git rev-list --count "$before"..HEAD)" -eq 1 ]
}

@test "ship_log: refuses an empty row" {
  run ship_log ""
  [ "$status" -eq 2 ]
}

@test "ship_log_ratio_count: counts file rows and trailers together" {
  printf '| d | ship-next | R-1 | shipped (ratio 1bp vs baseline 1bp) | n |\n' >> docs/learnings/_log.md
  git commit -q -am "row"
  mr_mode
  git checkout -q -b ship/R-2-demo
  ship_log "| d | ship-next | R-2 | shipped (ratio 2bp vs baseline 1bp) | n |"
  ship_log "| d | ship-compound | R-2 | in-review | n |"
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
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/ship-log.sh'; ship_log '| d | ship-next | R-3 | shipped | n |' && ship_log_ratio_count"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(git log -1 --format=%s)" = "log: ship-next R-3" ]
}

@test "every command writes _log.md rows through ship_log" {
  # A direct append on a review branch is a shared-file write — what made
  # parallel MRs conflict (R-001).
  hits=$(grep -l '>> docs/learnings/_log.md' "$SHIP_SKILL_ROOT"/commands/*.md || true)
  [ -z "$hits" ] || { echo "direct appends in: $hits"; return 1; }
}
