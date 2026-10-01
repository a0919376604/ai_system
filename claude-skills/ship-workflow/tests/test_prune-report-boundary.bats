#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch prune-report-boundary)"
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
  git commit -qm base
  git tag base
  printf 'x = 2\n' > src/a.py
  git add src/a.py
  git commit -qm change
  printf 'CANDIDATE: tests/src/test_a.py::test_a — duplicate — same behavior\n' > .ship/prune-candidates.md
  source "$SHIP_LIB/prune-report.sh"
}

teardown() { rm -rf "$SCRATCH"; }

@test "boundary: a real diff failure is an evaluation error, not an empty scope" {
  git config diff.renames invalid
  run git rev-parse --verify 'base^{commit}'
  [ "$status" -eq 0 ]
  run git merge-base base HEAD
  [ "$status" -eq 0 ]
  run git diff --name-only base...HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *'bad boolean config value'* ]]

  run prune_report base HEAD major
  printf 'status=%s output=%s\n' "$status" "$output"
  [ "$status" -eq 2 ]
  [[ "$output" != *'no scoped test targets'* ]]
}

@test "boundary: a filename matching the revision range does not hide valid scope" {
  printf 'untracked sentinel\n' > base...HEAD
  # The refs and scope are valid; explicitly separating revisions from paths works.
  run git diff --name-only base...HEAD --
  [ "$status" -eq 0 ]
  [ "$output" = 'src/a.py' ]

  run prune_report base HEAD major
  printf 'status=%s output=%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == '1 prune candidate(s)'* ]]
}

@test "boundary: a report path that is a directory is an evaluation error" {
  rm .ship/prune-candidates.md
  mkdir .ship/prune-candidates.md
  run prune_report base HEAD major
  printf 'status=%s output=%s\n' "$status" "$output"
  [ "$status" -eq 2 ]
}

@test "boundary: failure to create the report directory is an evaluation error" {
  rm .ship/prune-candidates.md
  rmdir .ship
  printf 'existing file\n' > .ship
  run prune_report base HEAD major
  printf 'status=%s output=%s\n' "$status" "$output"
  [ "$status" -eq 2 ]
}
