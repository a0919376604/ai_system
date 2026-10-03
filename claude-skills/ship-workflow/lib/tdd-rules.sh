#!/usr/bin/env bash
# ship-workflow/lib/tdd-rules.sh
# The testing rules handed to the Phase 5 executor, in three layers.
#
# They used to be four hardcoded `echo` lines inside commands/ship-next.md.
# That made the one layer that shapes what the executor WRITES the only layer
# in this workflow that could not compound: CONTEXT.md grows, learnings
# accumulate, patterns get promoted — the rules stayed frozen at whatever the
# skill author typed. Adding one meant editing and re-shipping the skill.
#
# Worse, the skill is a single symlinked copy shared by every repo, so a
# lesson learned in one repo was asserted at all of them. An early rule cited
# "conftest.py was changed 31 times in this project" — a measurement from one
# product repo, shipped to every other.
#
#   universal  — true everywhere; lives here, in the skill
#   learned    — this repo's own scars; docs/tdd-rules.md, git-tracked
#   seams      — this ship only; from the spec's ## Seams table
#
# Caps exist for the same reason CONTEXT.md has them: rules accumulate and
# nothing expires them. Forty rules nobody reads is the original problem in a
# new shape — context spent on instructions instead of on the work.

TDD_RULES_MAX=20
TDD_RULES_REL="docs/tdd-rules.md"

# tdd_rules_path — echo the repo's learned-rules file, or nothing.
tdd_rules_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  [ -f "$root/$TDD_RULES_REL" ] || return 0
  echo "$root/$TDD_RULES_REL"
}

# tdd_rules_count — echo how many learned rules, 0 when absent.
tdd_rules_count() {
  local f n
  f=$(tdd_rules_path)
  if [ -z "$f" ]; then echo 0; return 0; fi
  n=$(grep -c '^- ' "$f" || true)
  n=$(printf '%s' "$n" | tr -d '[:space:]')
  [ -n "$n" ] || n=0
  echo "$n"
}

# tdd_rules_over_cap — exit 0 when the repo has more rules than it can carry.
tdd_rules_over_cap() {
  local n
  n=$(tdd_rules_count)
  [ "$n" -gt "$TDD_RULES_MAX" ]
}

# tdd_rules_unsourced — learned rules with no `← R-NNN` provenance.
# Without a source a rule cannot be judged still-relevant, so it can never be
# pruned. That is how the file silently becomes unprunable.
tdd_rules_unsourced() {
  local f
  f=$(tdd_rules_path)
  [ -n "$f" ] || return 0
  grep '^- ' "$f" 2>/dev/null | grep -v '← R-[0-9]' || true
}

# tdd_rules_append <R-NNN> <rule text> — add a sourced rule. Idempotent.
tdd_rules_append() {
  local id="$1" text="$2" root f
  case "$id" in
    R-[0-9]*) : ;;
    *) echo "tdd_rules_append: need an R-NNN source, got '$id'" >&2; return 2 ;;
  esac
  [ -n "$text" ] || { echo "tdd_rules_append: empty rule" >&2; return 2; }
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
  f="$root/$TDD_RULES_REL"
  mkdir -p "$(dirname "$f")" || return 2
  if [ ! -f "$f" ]; then
    {
      echo "# Learned TDD rules"
      echo
      echo "Rules this repo earned the hard way. Rendered into \`.ship/tdd-rules.md\`"
      echo "for every Phase 5 executor, after the universal rules and before this"
      echo "ship's seams. Every rule carries the R-NNN that produced it, so an old"
      echo "one can be judged and dropped."
      echo
    } > "$f"
  fi
  grep -qF -- "$text" "$f" && return 0
  printf -- '- %s ← %s\n' "$text" "$id" >> "$f"
}

# tdd_rules_render <R-NNN> <spec file> — the full ruleset for one ship.
tdd_rules_render() {
  local id="$1" spec="$2" learned
  echo "# TDD rules for ${id}"
  echo
  echo "1. Tests attach only to the seams listed below."
  echo "2. \`Seam: none\` tasks add no tests. Behavior unchanged => tests unchanged."
  echo "3. Existing shared fixtures are READ-ONLY. Need a different shape? Add a new"
  echo "   fixture. Editing a shared one edits every test that uses it."
  echo "4. One test, one behavior. Do not pack unrelated assertions into a single test."
  echo "5. Assert on behavior at the seam, never on how it is implemented. A test that"
  echo "   must change when the implementation changes, while the behavior did not,"
  echo "   reports churn instead of regressions."
  learned=$(tdd_rules_path)
  if [ -n "$learned" ] && [ -s "$learned" ]; then
    echo
    echo "## Learned in this repo"
    grep '^- ' "$learned" 2>/dev/null || true
  fi
  echo
  echo "## Declared seams"
  [ -f "$spec" ] && sed -n '/^## Seams/,/^## /p' "$spec" | sed '$d'
  return 0
}
