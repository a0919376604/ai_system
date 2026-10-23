#!/usr/bin/env bats
# R-001 done-when A and D: two merge_mode=mr ships open at once; merging one
# must leave the other conflict-free, and nothing either recorded may be lost.
load helpers

setup() {
  export SCRATCH="$(make_scratch parallel-mr)"
  mkdir -p "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p docs/learnings .claude
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  printf '%s\n' '# Learned TDD rules' '' '- Seed rule. ← R-000' > docs/tdd-rules.md
  printf '%s\n' '- **Seed** — a term' > CONTEXT.md
  echo 'merge_mode: mr' > .claude/ship-config.yml
  git add -A && git commit -q -m base
  source "$SHIP_LIB/ship-log.sh"
  source "$SHIP_LIB/tdd-rules.sh"
  source "$SHIP_LIB/context-md.sh"
}
teardown() { rm -rf "$SCRATCH"; }

# What ship-compound step 9 and ship-next Phase 9 do on a review branch.
ship_new_way() {
  git checkout -q -b "ship/$1-x" main
  echo "learning for $1" > "docs/learnings/$1-x.md"
  tdd_rules_append "$1" "Rule learned in $1."
  context_pending_add "$1" "- **Term$1** — defined by $1"
  ship_log "| d | ship-compound | $1 | in-review | n |"
  git add "docs/learnings/$1-x.md" docs/tdd-rules.d docs/ship-pending
  git commit -q -m "compound: $1"
  ship_log "| d | ship-next | $1 | shipped (ratio 1bp vs baseline 1bp) | n |"
  git checkout -q main
}

# The pre-R-001 behaviour: every ship appends to the same two files.
ship_old_way() {
  git checkout -q -b "old/$1-x" main
  echo "| d | ship-next | $1 | shipped | n |" >> docs/learnings/_log.md
  echo "- Rule learned in $1. ← $1" >> docs/tdd-rules.md
  git add -A && git commit -q -m "old: $1"
  git checkout -q main
}

@test "A1: merging one mr-mode ship leaves the other conflict-free" {
  ship_new_way R-1
  ship_new_way R-2
  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
  run git merge-tree --write-tree main ship/R-2-x
  [ "$status" -eq 0 ]
}

@test "A2 (control): the old shared-file appends DO conflict" {
  # Proves A1 can fail: the same scenario written the old way must conflict.
  ship_old_way R-1
  ship_old_way R-2
  git merge -q --no-ff old/R-1-x -m "Merge R-1"
  run git merge-tree --write-tree main old/R-2-x
  [ "$status" -eq 1 ]
}

merge_both() {
  ship_new_way R-1
  ship_new_way R-2
  git merge -q --no-ff ship/R-1-x -m "Merge R-1"
  git merge -q --no-ff ship/R-2-x -m "Merge R-2"
}

@test "D2a: both ships' log rows reach main's history" {
  merge_both
  rows=$(git log --format='%(trailers:key=Ship-Log,valueonly)' main | sed '/^$/d')
  echo "$rows" | grep -qF '| d | ship-next | R-1 |' || return 1
  echo "$rows" | grep -qF '| d | ship-next | R-2 |'
}

@test "D2b: both ships' TDD rules survive alongside the legacy one" {
  merge_both
  [ "$(tdd_rules_count)" -eq 3 ]
}

@test "D2c: both ships' queued terms fold into CONTEXT.md without losing the seed" {
  merge_both
  context_pending_apply R-1 >/dev/null
  context_pending_apply R-2 >/dev/null
  grep -qxF -- '- **TermR-1** — defined by R-1' CONTEXT.md
  grep -qxF -- '- **TermR-2** — defined by R-2' CONTEXT.md
  grep -qxF -- '- **Seed** — a term' CONTEXT.md
}

@test "A3: a review branch never writes a shared file" {
  ship_new_way R-1
  changed=$(git diff --name-only main...ship/R-1-x)
  for f in docs/learnings/_log.md docs/tdd-rules.md CONTEXT.md docs/product/ROADMAP.md; do
    if echo "$changed" | grep -qxF "$f"; then echo "review branch wrote $f"; return 1; fi
  done
}
