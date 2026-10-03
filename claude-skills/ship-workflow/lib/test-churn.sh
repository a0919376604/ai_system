#!/usr/bin/env bash
# ship-workflow/lib/test-churn.sh
# Measures test CHURN — editing tests that already exist — which the test
# budget does not see. tb_ship_ratio counts ADDED lines only, so a ship that
# rewrote forty existing tests and added none scores perfectly.
#
# Why churn is worth its own signal, measured on a real 200-commit window:
#   test files added 376 · MODIFIED 456 · deleted 95
# More edits than additions, and nothing in the flow reported it.
#
# Not all churn is waste. A test edited alongside its source is tracking a
# real behaviour change. A test edited while its source stood still is the
# change-detector smell: it was coupled to an implementation detail, or it
# was asserting something that was not true. Only the second kind is reported.
#
# Every function is a silent no-op outside a git repo.

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]:-$0}")/test-budget.sh" 2>/dev/null || true

# _tc_stem <path> — the pairing key: basename, minus a test_ prefix,
# minus _test / .test / .spec suffixes, minus the extension.
_tc_stem() {
  local b
  b=$(basename "$1")
  b="${b%.*}"
  b="${b#test_}"
  b="${b%_test}"
  b="${b%.test}"
  b="${b%.spec}"
  printf '%s' "$b"
}

# tc_modified_tests <base> <head> — test files this ship EDITED (status M).
# Added files are not churn: writing a new test is the point of the work.
tc_modified_tests() {
  local base="$1" head="$2" st f
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  git diff --name-status "${base}...${head}" 2>/dev/null \
  | while IFS="$(printf '\t')" read -r st f; do
      [ "$st" = "M" ] || continue
      _tb_is_test_path "$f" || continue
      printf '%s\n' "$f"
    done
}

# tc_unpaired <base> <head> — modified tests whose paired source did NOT change.
tc_unpaired() {
  local base="$1" head="$2" changed f stem
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  # Every non-test file this ship touched, reduced to pairing stems.
  changed=$(git diff --name-only "${base}...${head}" 2>/dev/null \
            | while IFS= read -r f; do
                _tb_is_test_path "$f" && continue
                _tc_stem "$f"; printf '\n'
              done)
  tc_modified_tests "$base" "$head" | while IFS= read -r f; do
    stem=$(_tc_stem "$f")
    # PREFIX match, not exact. One test file routinely covers a source file
    # with a shorter name: test_admin_dashboard_taxonomy.py tests
    # admin_dashboard.py. Exact stem matching called 20 of 57 real cases
    # orphans when their source had in fact changed — a 35% false positive
    # rate that would have made the whole signal untrustworthy.
    _tc_prefix_hit "$stem" "$changed" || printf '%s\n' "$f"
  done
}

# _tc_prefix_hit <test-stem> <newline-separated source stems>
# True when a changed source stem is a prefix of the test stem, or the test
# stem is a prefix of a changed source stem.
_tc_prefix_hit() {
  local stem="$1" list="$2" c
  printf '%s\n' "$list" | while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$stem" in "$c"*) echo hit; break ;; esac
    case "$c" in "$stem"*) echo hit; break ;; esac
  done | grep -q hit
}

# tc_lines_per_test <base> <head> — added test lines per added test case.
# The volume signal that matters. On the same real repo, tests-per-function
# was only 1.92 while each test averaged 24 lines: the bulk is setup, not
# test count, so counting tests would have pointed at the wrong thing.
tc_lines_per_test() {
  local base="$1" head="$2" lines cases f n
  git rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return 0; }
  lines=0
  for f in $(git diff --name-only "${base}...${head}" 2>/dev/null); do
    _tb_is_test_path "$f" || continue
    n=$(git diff --numstat "${base}...${head}" -- "$f" 2>/dev/null | awk '{print $1}' | head -1)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    lines=$((lines + n))
  done
  cases=$(git diff "${base}...${head}" 2>/dev/null \
          | grep -cE '^\+[[:space:]]*((async )?def test_|@test |it\(|test\()' || true)
  cases=$(printf '%s' "$cases" | tr -d '[:space:]')
  [ -n "$cases" ] || cases=0
  [ "$cases" -gt 0 ] 2>/dev/null || { echo 0; return 0; }
  echo $((lines / cases))
}

# tc_report <base> <head> — the whole churn report, as lines.
# Lives here, not in the phase, for the reason prune_report does: Phase 8.5's
# body is guarded by an exhaustive allowlist, and that allowlist only works
# while the body stays short enough to enumerate. Logic belongs in a lib that
# is unit-tested directly.
tc_report() {
  local base="$1" head="$2" n orphan lpt
  n=$(tc_modified_tests "$base" "$head" | grep -c . || true)
  orphan=$(tc_unpaired "$base" "$head" | grep -c . || true)
  lpt=$(tc_lines_per_test "$base" "$head")
  n=$(printf '%s' "$n" | tr -d '[:space:]'); [ -n "$n" ] || n=0
  orphan=$(printf '%s' "$orphan" | tr -d '[:space:]'); [ -n "$orphan" ] || orphan=0
  echo "churn: modified ${n} existing test file(s); ${orphan} with no paired source change"
  echo "churn: ${lpt} added lines per new test case"
  if [ "$orphan" -gt 0 ] 2>/dev/null; then
    tc_unpaired "$base" "$head" | sed 's|^|  unpaired: |'
  fi
}
