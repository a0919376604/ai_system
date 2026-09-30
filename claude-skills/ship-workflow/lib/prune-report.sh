#!/usr/bin/env bash
# ship-workflow/lib/prune-report.sh
# Phase 8.5's mechanical half: decide whether a prune report is due, resolve its
# scope, count the candidates Claude wrote, and echo a status line.
#
# READ-ONLY BY CONSTRUCTION. The only filesystem write is `mkdir -p .ship`. The git
# subcommands are `diff`, `rev-parse` and `merge-base` — all of them read. Nothing here
# edits, stages, deletes or commits a test. The audit in tests/test_prune-report.bats
# enforces that list as an allowlist, so adding a fourth subcommand fails until it is
# reviewed and added deliberately.
#
# This logic used to live as bash inside commands/ship-next.md, and proving it
# destroyed nothing meant extracting the fenced blocks and executing them. Four
# review rounds found holes in that harness rather than in the code: an unindented
# fence was silently skipped, the non-major branch was never exercised, the
# reachability check accepted a vacuous run. A function in lib/ is tested the way
# every other function here is tested, and those holes cannot exist.
#
# Usage:  prune_report <orig_ref> <head_ref> <verdict>
# Echoes the status; always exits 0.

# prune_report_ref_ok <ref>
# Exit 0 only for a string that resolves to a commit and cannot be read as an option.
#
# Without this, `git diff --name-only "${orig}...${head}"` interpolates an attacker's
# string straight into git's argument list, and git parses a leading `-` as an option:
#   prune_report '--output=tests/pwned' '' major   ->   writes tests/pwned...
# It returned exit 0 and "no scoped test targets" while doing it. `--` does not help,
# because the `A...B` range has to sit in the option position.
prune_report_ref_ok() {
  local ref="$1"
  [ -n "$ref" ] || return 1
  case "$ref" in -*) return 1 ;; esac
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1
}

# prune_report_targets <orig_ref> <head_ref>
# Echo the test files in scope: those covering non-test modules the ship touched.
prune_report_targets() {
  local orig="$1" head="$2" touched modules m
  prune_report_ref_ok "$orig" || return 0
  prune_report_ref_ok "$head" || return 0
  touched=$(git diff --name-only "${orig}...${head}" 2>/dev/null | grep -v '^tests/' || true)
  [ -n "$touched" ] || return 0
  modules=$(echo "$touched" | sed 's|/[^/]*$||' | sort -u)
  for m in $modules; do
    ls "tests/${m##*/}"/*.py 2>/dev/null || true
  done | sort -u
}

# prune_report_count [file]
# Echo the number of CANDIDATE: lines. `grep -c` prints 0 AND exits 1 on no match,
# so `|| echo 0` would append a second zero and render as `00`.
prune_report_count() {
  local f="${1:-.ship/prune-candidates.md}" n
  n=$(grep -c '^CANDIDATE: ' "$f" 2>/dev/null || true)
  n=$(echo "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# prune_report <orig_ref> <head_ref> <verdict>
#
# Exit 0  a decision was reached: either a report, or a legitimate skip.
# Exit 2  the input could not be evaluated. NEVER conflated with a skip.
#
# The earlier version returned 0 and "no report (no scoped test targets)" for a
# malformed ref, an unknown verdict, and two commits with no merge base. That reads
# identically to "there was genuinely nothing in scope", so a ship whose refs were
# wrong looked exactly like a quiet, healthy one. This is the same distinction
# coverage-diff.py draws between "clean" and "cannot decide", which was built there
# and then not carried over to here.
prune_report() {
  local orig="$1" head="$2" verdict="$3" targets n
  case "$verdict" in
    major|pass|blocking) ;;
    *) echo "invalid verdict: '${verdict}' (expected major, pass or blocking)"; return 2 ;;
  esac
  if [ "$verdict" != "major" ]; then
    echo "no report (verdict=${verdict})"
    return 0
  fi
  prune_report_ref_ok "$orig" || {
    echo "invalid ref: '${orig}' does not resolve to a commit"; return 2; }
  prune_report_ref_ok "$head" || {
    echo "invalid ref: '${head}' does not resolve to a commit"; return 2; }
  git merge-base "$orig" "$head" >/dev/null 2>&1 || {
    echo "error: '${orig}' and '${head}' have no merge base"; return 2; }
  targets=$(prune_report_targets "$orig" "$head")
  if [ -z "$targets" ]; then
    echo "no report (no scoped test targets)"
    return 0
  fi
  mkdir -p .ship
  n=$(prune_report_count)
  echo "${n} prune candidate(s) — see .ship/prune-candidates.md (nothing deleted)"
}
