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

@test "tdd_rules_append: adds a sourced rule to the ship's fragment, idempotently" {
  tdd_rules_append R-042 "Never assert on log output."
  tdd_rules_append R-042 "Never assert on log output."
  run tdd_rules_count
  [ "$output" = "1" ]
  grep -qxF -- '- Never assert on log output. ← R-042' docs/tdd-rules.d/R-042.md
  [ ! -f docs/tdd-rules.md ] || { echo "append wrote the shared legacy file"; return 1; }
}

@test "tdd_rules_append: refuses a rule with no R-NNN" {
  run tdd_rules_append "" "orphan rule"
  [ "$status" -ne 0 ]
  [ ! -f docs/tdd-rules.md ]
  [ ! -d docs/tdd-rules.d ]
}

@test "tdd_rules_append: never modifies the legacy file, and dedupes against it" {
  # Every ship appending to one file is what made parallel MRs conflict.
  mkrules '- Old rule. ← R-001'
  cp docs/tdd-rules.md "$BATS_TEST_TMPDIR/legacy.before"
  tdd_rules_append R-002 "Old rule."
  [ ! -e docs/tdd-rules.d/R-002.md ] || { echo "duplicated a legacy rule"; return 1; }
  tdd_rules_append R-002 "New rule."
  grep -qxF -- '- New rule. ← R-002' docs/tdd-rules.d/R-002.md
  cmp -s docs/tdd-rules.md "$BATS_TEST_TMPDIR/legacy.before"
}

@test "tdd rule readers see the legacy file first, then fragments by name" {
  mkrules '- Legacy. ← R-001'
  mkdir -p docs/tdd-rules.d
  printf -- '- Frag B. ← R-003\n' > docs/tdd-rules.d/R-003.md
  printf -- '- Frag A.\n' > docs/tdd-rules.d/R-002.md
  run tdd_rules_count
  [ "$output" = "3" ]
  run tdd_rules_unsourced
  [ "$output" = "- Frag A." ]
  printf '## Seams\n| a | b | c |\n' > spec.md
  run tdd_rules_render R-123 spec.md
  l=$(echo "$output" | grep -n -- '- Legacy.' | cut -d: -f1)
  a=$(echo "$output" | grep -n -- '- Frag A.' | cut -d: -f1)
  b=$(echo "$output" | grep -n -- '- Frag B.' | cut -d: -f1)
  [ -n "$l" ] && [ -n "$a" ] && [ -n "$b" ]
  [ "$l" -lt "$a" ] && [ "$a" -lt "$b" ]
}

@test "tdd_rules_render: a repo with only the legacy file renders exactly as before" {
  mkrules '# Learned TDD rules' '' '- One. ← R-001' '- Two. ← R-002'
  printf '## Seams\n| a | b | c |\n' > spec.md
  run tdd_rules_render R-123 spec.md
  learned=$(echo "$output" | sed -n '/^## Learned in this repo$/,/^## Declared seams$/p')
  expected=$(printf '%s\n' '## Learned in this repo' '- One. ← R-001' '- Two. ← R-002' '' '## Declared seams')
  [ "$learned" = "$expected" ]
}

@test "zsh: rule readers work with and without a fragment directory" {
  command -v zsh >/dev/null || skip "zsh not installed"
  mkrules '- Legacy. ← R-001'
  run zsh -c "source '$SHIP_LIB/tdd-rules.sh'; tdd_rules_count"
  [ "$output" = "1" ]
  mkdir -p docs/tdd-rules.d
  run zsh -c "source '$SHIP_LIB/tdd-rules.sh'; tdd_rules_count"
  [ "$output" = "1" ]
}
