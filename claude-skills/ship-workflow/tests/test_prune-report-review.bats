#!/usr/bin/env bats
# Acceptance review of the public boundary. Failing cases intentionally retain
# the requested error contract; do not weaken them to accept a successful skip.
load helpers

setup() {
  export SCRATCH="$(make_scratch prune-report-review)"
  export HOME="$SCRATCH/home"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0
  mkdir -p "$HOME" "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q
  git config user.email t@t
  git config user.name t
  mkdir -p src tests/src .ship
  printf 'x = 1\n' > src/a.py
  printf 'assert 1\n' > tests/src/test_a.py
  git add src tests
  git commit -q -m "base source"
  BASE=$(git rev-parse HEAD)
  printf 'x = 2\n' > src/a.py
  git add src/a.py
  git commit -q -m change
  HEAD_REF=$(git rev-parse HEAD)
  git tag base-light "$BASE"
  git tag -a base-annotated -m base "$BASE"
  git tag tree-tag "HEAD^{tree}"
  printf 'stash sentinel\n' >> src/a.py
  git stash push -qm sentinel
  printf 'assert 2\n' > tests/src/test_a.py
  printf 'assert 3\n' > tests/src/test_b.py
  git add tests/src/test_b.py
  printf 'untracked sentinel\n' > untracked.txt
  printf 'CANDIDATE: tests/src/test_a.py::test_a — duplicate — same behavior\n' > .ship/prune-candidates.md
  source "$SHIP_LIB/prune-report.sh"
}

teardown() { rm -rf "$SCRATCH"; }

review_snapshot() {
  git rev-parse HEAD
  git status --porcelain --untracked-files=all
  git ls-files --stage
  shasum .git/index
  git stash list --format='%H %gs'
  find . -path ./.git -prune -o -type f -print | LC_ALL=C sort |
    while IFS= read -r f; do shasum "$f"; done
}

# Check both argument positions, including state preservation on rejected input.
assert_invalid_ref() {
  local bad="$1" before failed=0 position
  run prune_report_ref_ok "$bad"
  [ "$status" -ne 0 ]
  before=$(review_snapshot)
  for position in orig head; do
    if [ "$position" = orig ]; then
      run prune_report "$bad" "$HEAD_REF" major
    else
      run prune_report "$BASE" "$bad" major
    fi
    [ "$(review_snapshot)" = "$before" ] || return 1
    if [ "$status" -eq 0 ] || [[ "$output" != *[Ii]nvalid* && "$output" != *[Ee]rror* && "$output" != *[Uu]nresolv* ]]; then
      printf '%s ref <%q>: status=%s output=%s\n' "$position" "$bad" "$status" "$output"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "review: empty ref is an explicit input error" {
  assert_invalid_ref ""
}

@test "review: option-like refs are explicit input errors and create nothing" {
  assert_invalid_ref '--output=tests/pwned'
}

@test "review: whitespace-only ref is an explicit input error" {
  assert_invalid_ref ' '
}

@test "review: embedded whitespace in a missing ref is an explicit input error" {
  assert_invalid_ref 'not a ref'
}

@test "review: newline in a missing ref is an explicit input error" {
  assert_invalid_ref $'HEAD\nmissing'
}

@test "review: tree object is an explicit input error" {
  assert_invalid_ref "$(git rev-parse HEAD^{tree})"
}

@test "review: tag naming a tree is an explicit input error" {
  assert_invalid_ref tree-tag
}

@test "review: nonexistent ref is an explicit input error" {
  assert_invalid_ref refs/heads/does-not-exist
}

@test "review: parent traversal string is an explicit input error" {
  assert_invalid_ref '../src/../HEAD'
}

@test "review: blob object is an explicit input error" {
  assert_invalid_ref "$(git rev-parse HEAD:src/a.py)"
}

@test "review: lightweight and annotated commit tags resolve normally" {
  before=$(review_snapshot)
  for ref in base-light base-annotated; do
    run prune_report "$ref" "$HEAD_REF" major
    [ "$status" -eq 0 ]
    [[ "$output" == '1 prune candidate(s)'* ]]
    [ "$(review_snapshot)" = "$before" ]
  done
}

@test "review: relative and whitespace-containing commit selectors resolve normally" {
  before=$(review_snapshot)
  for ref in HEAD~1 'HEAD^{/base source}' 'HEAD@{0}~1'; do
    run prune_report "$ref" "$HEAD_REF" major
    [ "$status" -eq 0 ]
    [[ "$output" == '1 prune candidate(s)'* ]]
    [ "$(review_snapshot)" = "$before" ]
  done
}

@test "review: invalid verdicts are explicit input errors" {
  before=$(review_snapshot)
  failed=0
  for verdict in '' unknown MAJOR ' major ' '--output=tests/pwned' $'major\npass'; do
    run prune_report "$BASE" "$HEAD_REF" "$verdict"
    [ "$(review_snapshot)" = "$before" ]
    if [ "$status" -eq 0 ]; then
      printf 'verdict <%q>: status=%s output=%s\n' "$verdict" "$status" "$output"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

@test "review: every defined verdict preserves dirty worktree, exact index, stash and HEAD" {
  before=$(review_snapshot)
  for verdict in major pass blocking; do
    for orig in "$BASE" "$HEAD_REF"; do
      run prune_report "$orig" "$HEAD_REF" "$verdict"
      [ "$status" -eq 0 ]
      [ "$(review_snapshot)" = "$before" ]
      if [ "$verdict" = major ] && [ "$orig" = "$BASE" ]; then
        [[ "$output" == '1 prune candidate(s)'* ]]
      elif [ "$verdict" = major ]; then
        [ "$output" = 'no report (no scoped test targets)' ]
      else
        [ "$output" = "no report (verdict=$verdict)" ]
      fi
    done
  done
}

@test "review: valid commits without a merge base must report a diff error" {
  other=$(printf 'unrelated\n' | git commit-tree "HEAD^{tree}")
  run git diff --name-only "$other...$HEAD_REF"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no merge base"* ]]
  before=$(review_snapshot)
  run prune_report "$other" "$HEAD_REF" major
  [ "$(review_snapshot)" = "$before" ]
  printf 'status=%s output=%s\n' "$status" "$output"
  [ "$status" -ne 0 ]
}
