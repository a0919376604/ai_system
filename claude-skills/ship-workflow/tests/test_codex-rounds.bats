#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-rounds)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-rounds.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "codex_round_append: stores the report byte-identical" {
  printf '**BLOCKED**\n\nTwo defects:\n\n- `git diff` returns exit 0\n- $HOME is unquoted\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "fixed step 3"
  # Every byte of the original must survive, including backticks and $.
  while IFS= read -r line; do
    grep -qxF -- "$line" "$WT/.ship/codex-rounds.md" \
      || { echo "lost line: $line"; return 1; }
  done < r.md
}

@test "codex_round_append: records the round number, verdict and classification" {
  echo "report body" > r.md
  codex_round_append "$WT" 2 blocked r.md "executor error" "relaunched with a note"
  grep -qF "## Round 2" "$WT/.ship/codex-rounds.md"
  grep -qF "blocked" "$WT/.ship/codex-rounds.md"
  grep -qF "executor error" "$WT/.ship/codex-rounds.md"
  grep -qF "relaunched with a note" "$WT/.ship/codex-rounds.md"
}

@test "codex_round_append: a leading # in the report does not become a heading" {
  printf '# not a section heading\nbody\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "x"
  # Exactly one level-2 heading — ours. The report is fenced, not inlined.
  [ "$(grep -c '^## ' "$WT/.ship/codex-rounds.md")" -eq 1 ]
}

@test "codex_round_append: accumulates rather than overwriting" {
  echo "first" > r1.md; echo "second" > r2.md
  codex_round_append "$WT" 1 blocked r1.md "plan defect" "a"
  codex_round_append "$WT" 2 done   r2.md "n/a" "b"
  grep -qF "first"  "$WT/.ship/codex-rounds.md"
  grep -qF "second" "$WT/.ship/codex-rounds.md"
}

@test "codex_round_count: counts rounds, zero when absent" {
  run codex_round_count "$WT"
  [ "$output" = "0" ]
  echo "x" > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "a"
  codex_round_append "$WT" 2 blocked r.md "plan defect" "b"
  run codex_round_count "$WT"
  [ "$output" = "2" ]
}

@test "codex_round_last_findings: returns the last round's bullets only" {
  printf '**BLOCKED**\n\n- first round finding\n' > r1.md
  printf '**BLOCKED**\n\n- second round finding\n' > r2.md
  codex_round_append "$WT" 1 blocked r1.md "plan defect" "a"
  codex_round_append "$WT" 2 blocked r2.md "plan defect" "b"
  run codex_round_last_findings "$WT"
  [[ "$output" == *"second round finding"* ]]
  [[ "$output" != *"first round finding"* ]]
}

@test "codex_round_last_findings: empty when there are no rounds" {
  run codex_round_last_findings "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "codex_round_append: a missing report file exits 2 rather than writing a blank round" {
  run codex_round_append "$WT" 1 blocked nope.md "plan defect" "x"
  [ "$status" -eq 2 ]
  [ ! -f "$WT/.ship/codex-rounds.md" ]
}
