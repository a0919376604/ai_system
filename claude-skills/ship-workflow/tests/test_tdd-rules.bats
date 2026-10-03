#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch tdd-rules)"
  mkdir -p "$SCRATCH/repo/docs"; cd "$SCRATCH/repo"
  git init -q
  source "$SHIP_LIB/tdd-rules.sh"
}
teardown() { rm -rf "$SCRATCH"; }

mkrules() { printf '%s\n' "$@" > docs/tdd-rules.md; }

@test "tdd_rules_path: nothing when the repo keeps none" {
  run tdd_rules_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tdd_rules_path: the repo-relative file when present" {
  mkrules '- Shared fixtures are read-only. ← R-001'
  run tdd_rules_path
  [[ "$output" == */docs/tdd-rules.md ]] || return 1
}

@test "tdd_rules_count: counts rule bullets, 0 when absent" {
  run tdd_rules_count
  [ "$output" = "0" ]
  mkrules '# Learned rules' '' '- One. ← R-001' '- Two. ← R-002'
  run tdd_rules_count
  [ "$output" = "2" ]
}

@test "tdd_rules_over_cap: trips on too many rules" {
  n=0; : > docs/tdd-rules.md
  while [ "$n" -lt "$((TDD_RULES_MAX + 1))" ]; do
    echo "- rule $n. ← R-$n" >> docs/tdd-rules.md; n=$((n+1))
  done
  run tdd_rules_over_cap
  [ "$status" -eq 0 ]
}

@test "tdd_rules_over_cap: quiet under the cap" {
  mkrules '- just one. ← R-001'
  run tdd_rules_over_cap
  [ "$status" -ne 0 ]
}

@test "tdd_rules_unsourced: a rule with no provenance is listed" {
  # Rules accumulate and nothing expires them. Without a source there is no
  # way to judge whether a rule still applies, so it can never be pruned —
  # which is how a rule file becomes 40 lines nobody reads.
  mkrules '- Has a source. ← R-001' '- Came from nowhere.'
  run tdd_rules_unsourced
  [[ "$output" == *"Came from nowhere."* ]] || return 1
  [[ "$output" != *"Has a source."* ]] || return 1
}

@test "tdd_rules_unsourced: empty when every rule is sourced" {
  mkrules '- A. ← R-001' '- B. ← R-002.1'
  run tdd_rules_unsourced
  [ -z "$output" ]
}

@test "tdd_rules_render: universal rules come first, then learned, then seams" {
  mkrules '- Repo-specific thing. ← R-007'
  printf '## Seams\n| Seam | Interface | Behavior |\n| a | b | c |\n' > spec.md
  run tdd_rules_render R-123 spec.md
  [ "$status" -eq 0 ]
  u=$(echo "$output" | grep -n 'attach only to the seams' | cut -d: -f1)
  l=$(echo "$output" | grep -n 'Repo-specific thing' | cut -d: -f1)
  s=$(echo "$output" | grep -n 'Declared seams' | cut -d: -f1)
  [ -n "$u" ] && [ -n "$l" ] && [ -n "$s" ]
  [ "$u" -lt "$l" ] || { echo "learned rules precede universal ones"; return 1; }
  [ "$l" -lt "$s" ] || { echo "seams precede learned rules"; return 1; }
}

@test "tdd_rules_render: works with no learned rules at all" {
  printf '## Seams\n| a | b | c |\n' > spec.md
  run tdd_rules_render R-123 spec.md
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'attach only to the seams' || return 1
  echo "$output" | grep -q 'Declared seams' || return 1
}

@test "tdd_rules_render: universal rules carry no repo-specific evidence" {
  # An earlier version baked 'conftest.py was changed 31 times in this
  # project' into the shared skill, so one repo's history was asserted at
  # every other repo. Evidence belongs in the repo's own file.
  printf '## Seams\n| a | b | c |\n' > spec.md
  run tdd_rules_render R-123 spec.md
  [[ "$output" != *conftest* ]] || { echo "repo-specific evidence in the universal section"; return 1; }
  [[ "$output" != *"31"* ]] || { echo "a repo's measurement leaked into the skill"; return 1; }
}

@test "tdd_rules_append: adds a sourced rule, idempotently" {
  tdd_rules_append R-042 "Never assert on log output."
  tdd_rules_append R-042 "Never assert on log output."
  run tdd_rules_count
  [ "$output" = "1" ]
  grep -q '← R-042' docs/tdd-rules.md
}

@test "tdd_rules_append: refuses a rule with no R-NNN" {
  run tdd_rules_append "" "orphan rule"
  [ "$status" -ne 0 ]
  [ ! -f docs/tdd-rules.md ]
}
