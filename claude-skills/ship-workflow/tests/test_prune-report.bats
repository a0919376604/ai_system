#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch prune-report)"
  mkdir -p "$SCRATCH/repo/tests/src" "$SCRATCH/repo/src"
  cd "$SCRATCH/repo"
  git init -q .
  git config user.email t@t
  git config user.name t
  printf 'def f():\n    return 1\n' > src/a.py
  printf 'def test_f():\n    assert f() == 1\n' > tests/src/test_a.py
  git add -A && git commit -q -m base
  export BASE=$(git rev-parse HEAD)
  printf 'def f():\n    return 2\n' > src/a.py
  git add -A && git commit -q -m change
  export HEAD_REF=$(git rev-parse HEAD)
  source "$SHIP_LIB/prune-report.sh"
}

teardown() { rm -rf "$SCRATCH"; }

# --- branch coverage: every path the phase can take -------------------------

@test "prune_report: a non-major verdict produces no report" {
  run prune_report "$BASE" "$HEAD_REF" pass
  [ "$status" -eq 0 ]
  [[ "$output" == "no report (verdict=pass)" ]]
}

@test "prune_report: a blocking verdict also produces no report" {
  run prune_report "$BASE" "$HEAD_REF" blocking
  [[ "$output" == "no report (verdict=blocking)" ]]
}

@test "prune_report: major with no touched source files produces no report" {
  run prune_report "$HEAD_REF" "$HEAD_REF" major
  [[ "$output" == "no report (no scoped test targets)" ]]
}

@test "prune_report: major with a touched module that has no tests produces no report" {
  mkdir -p other
  printf 'x = 1\n' > other/b.py
  git add -A && git commit -q -m other
  run prune_report "$HEAD_REF" "$(git rev-parse HEAD)" major
  [[ "$output" == "no report (no scoped test targets)" ]]
}

@test "prune_report: major with targets and no candidate file reports zero" {
  run prune_report "$BASE" "$HEAD_REF" major
  [[ "$output" == "0 prune candidate(s)"* ]]
  [[ "$output" == *"nothing deleted"* ]]
}

@test "prune_report: major with candidates reports the count" {
  mkdir -p .ship
  printf 'CANDIDATE: tests/src/test_a.py::test_f — duplicate — same as test_g\n' > .ship/prune-candidates.md
  printf 'CANDIDATE: tests/src/test_a.py::test_g — weak — assert True\n' >> .ship/prune-candidates.md
  run prune_report "$BASE" "$HEAD_REF" major
  [[ "$output" == "2 prune candidate(s)"* ]]
}

# --- counting ---------------------------------------------------------------

@test "prune_report_count: empty file is 0, not 00" {
  : > f.md
  run prune_report_count f.md
  [ "$output" = "0" ]
}

@test "prune_report_count: a header-only file is 0" {
  printf '# Prune candidates\n\n| file | test |\n' > f.md
  run prune_report_count f.md
  [ "$output" = "0" ]
}

@test "prune_report_count: a missing file is 0" {
  run prune_report_count nope.md
  [ "$output" = "0" ]
}

@test "prune_report_count: counts one CANDIDATE line as 1" {
  printf 'CANDIDATE: a.py::t — dup — x\n' > f.md
  run prune_report_count f.md
  [ "$output" = "1" ]
}

# --- the invariant that matters --------------------------------------------

@test "prune_report: destroys nothing, in every branch, on a dirty tree" {
  # No fence extraction, no harness: the function is called directly, so every
  # branch is reachable and none of it can be silently skipped.
  printf 'def test_f():\n    assert f() == 2\n    assert f() != 9\n' > tests/src/test_a.py
  printf 'def test_g():\n    assert True\n' > tests/src/test_b.py
  git add tests/src/test_b.py
  mkdir -p .ship
  printf 'CANDIDATE: tests/src/test_a.py::test_f — dup — x\n' > .ship/prune-candidates.md

  snapshot() {
    git status --porcelain -- . ':(exclude).ship' | sort
    git diff --cached --name-status | sort
    git stash list
    find tests -type f | sort | while IFS= read -r f; do shasum "$f"; done
    git rev-parse HEAD
  }
  before=$(snapshot)
  for v in major pass blocking ""; do
    prune_report "$BASE" "$HEAD_REF" "$v" >/dev/null 2>&1 || true
    prune_report "$HEAD_REF" "$HEAD_REF" "$v" >/dev/null 2>&1 || true
  done
  after=$(snapshot)
  if [ "$before" != "$after" ]; then
    diff <(echo "$before") <(echo "$after") || true
    return 1
  fi
}

@test "prune-report.sh runs no mutating git subcommand and no destructive verb" {
  # A small, self-contained file CAN be read exhaustively — unlike a markdown
  # document whose fences must be located first. Both checks apply.
  src="$SHIP_LIB/prune-report.sh"
  body=$(grep -v '^[[:space:]]*#' "$src")
  while IFS= read -r sub; do
    [ -z "$sub" ] && continue
    [ "$sub" = "diff" ] || { echo "mutating git subcommand: git $sub"; return 1; }
  done <<< "$(echo "$body" | grep -oE '\bgit +[a-z][a-z-]*' | awk '{print $2}')"
  for verb in rm mv cp truncate tee shred; do
    if echo "$body" | grep -qE "(^|[|;&(]|[[:space:]])${verb}([[:space:]]|$)"; then
      echo "destructive verb: $verb"; return 1
    fi
  done
}
