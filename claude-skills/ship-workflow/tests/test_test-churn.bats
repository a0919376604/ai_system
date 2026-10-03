#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch test-churn)"
  mkdir -p "$SCRATCH/repo"; cd "$SCRATCH/repo"
  git init -q; git config user.email t@t; git config user.name t
  mkdir -p src tests
  printf 'def foo():\n    return 1\n' > src/foo.py
  printf 'def bar():\n    return 2\n' > src/bar.py
  printf 'def test_foo():\n    assert foo() == 1\n' > tests/test_foo.py
  printf 'def test_bar():\n    assert bar() == 2\n' > tests/test_bar.py
  git add -A; git commit -qm base
  BASE=$(git rev-parse HEAD); export BASE
  source "$SHIP_LIB/test-churn.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "tc_modified_tests: lists existing test files this ship edited" {
  printf 'def test_foo():\n    assert foo() == 1  # tweak\n' > tests/test_foo.py
  git add -A; git commit -qm edit
  run tc_modified_tests "$BASE" HEAD
  [[ "$output" == *tests/test_foo.py* ]] || return 1
  [[ "$output" != *tests/test_bar.py* ]] || return 1
}

@test "tc_modified_tests: a NEW test file is not churn" {
  printf 'def test_new():\n    pass\n' > tests/test_new.py
  git add -A; git commit -qm add
  run tc_modified_tests "$BASE" HEAD
  [ -z "$output" ]
}

@test "tc_unpaired: a test edited WITH its source is legitimate churn" {
  printf 'def foo():\n    return 99\n' > src/foo.py
  printf 'def test_foo():\n    assert foo() == 99\n' > tests/test_foo.py
  git add -A; git commit -qm both
  run tc_unpaired "$BASE" HEAD
  [ -z "$output" ]
}

@test "tc_unpaired: a test edited ALONE is the change-detector smell" {
  # The source did not move, yet the test had to. Either it was coupled to an
  # implementation detail, or it was asserting something untrue.
  printf 'def test_foo():\n    assert foo() == 1  # reworded\n' > tests/test_foo.py
  git add -A; git commit -qm testonly
  run tc_unpaired "$BASE" HEAD
  [[ "$output" == *tests/test_foo.py* ]] || return 1
}

@test "tc_unpaired: pairing is by filename stem, not directory layout" {
  mkdir -p pkg/deep
  printf 'def baz():\n    return 3\n' > pkg/deep/baz.py
  printf 'def test_baz():\n    assert baz() == 3\n' > tests/test_baz.py
  git add -A; git commit -qm add-baz
  B2=$(git rev-parse HEAD)
  printf 'def baz():\n    return 4\n' > pkg/deep/baz.py
  printf 'def test_baz():\n    assert baz() == 4\n' > tests/test_baz.py
  git add -A; git commit -qm move-both
  run tc_unpaired "$B2" HEAD
  [ -z "$output" ]
}

@test "tc_lines_per_test: setup bloat, not test count, is what grew" {
  # Measured on a real repo: 4,737 tests over 116,898 lines is 24 lines each,
  # while tests-per-function was only 1.92. The volume is setup.
  printf 'def test_fat():\n%s    assert foo() == 1\n' "$(for i in $(seq 1 30); do echo "    x$i = 1"; done)" > tests/test_fat.py
  git add -A; git commit -qm fat
  run tc_lines_per_test "$BASE" HEAD
  [ "$status" -eq 0 ]
  [ "$output" -gt 20 ] || { echo "got $output, expected a fat number"; return 1; }
}

@test "tc_lines_per_test: zero new tests yields 0, not a division error" {
  printf 'def foo():\n    return 7\n' > src/foo.py
  git add -A; git commit -qm srconly
  run tc_lines_per_test "$BASE" HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "all functions are silent no-ops outside a git repo" {
  cd "$SCRATCH"
  run tc_modified_tests x y; [ "$status" -eq 0 ]; [ -z "$output" ]
  run tc_unpaired x y;       [ "$status" -eq 0 ]; [ -z "$output" ]
  run tc_lines_per_test x y; [ "$status" -eq 0 ]; [ "$output" = "0" ]
}

@test "tc_unpaired: a test whose source has a SHORTER name still pairs" {
  # Real case: test_admin_dashboard_taxonomy.py covers admin_dashboard.py.
  # Exact stem matching called 20 of 57 real modifications orphans — 35%
  # false positives — which would have made the signal useless.
  mkdir -p src
  printf 'def dash():\n    return 1\n' > src/admin_dashboard.py
  printf 'def test_tax():\n    assert dash() == 1\n' > tests/test_admin_dashboard_taxonomy.py
  git add -A; git commit -qm add
  B2=$(git rev-parse HEAD)
  printf 'def dash():\n    return 2\n' > src/admin_dashboard.py
  printf 'def test_tax():\n    assert dash() == 2\n' > tests/test_admin_dashboard_taxonomy.py
  git add -A; git commit -qm both
  run tc_unpaired "$B2" HEAD
  [ -z "$output" ] || { echo "false positive: $output"; return 1; }
}

@test "tc_report: one call produces the whole report" {
  printf 'def test_foo():\n    assert foo() == 1  # edit\n' > tests/test_foo.py
  git add -A; git commit -qm edit
  run tc_report "$BASE" HEAD
  [[ "$output" == *"modified 1 existing test file(s)"* ]] || return 1
  [[ "$output" == *"1 with no paired source change"* ]] || return 1
  [[ "$output" == *"unpaired: tests/test_foo.py"* ]] || return 1
  [[ "$output" == *"lines per new test case"* ]] || return 1
}

@test "tc_report: lists nothing extra when there is no churn" {
  printf 'def test_new():\n    pass\n' > tests/test_new.py
  git add -A; git commit -qm add
  run tc_report "$BASE" HEAD
  [[ "$output" == *"modified 0 existing"* ]] || return 1
  [[ "$output" != *"unpaired:"* ]] || { echo "listed unpaired with none"; return 1; }
}
