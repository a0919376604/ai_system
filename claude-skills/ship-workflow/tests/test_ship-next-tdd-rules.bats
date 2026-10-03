#!/usr/bin/env bats
load helpers
setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; export CC="$SHIP_SKILL_ROOT/commands/ship-compound.md"; }
p5() { awk '/^## Phase 5 /,/^## Phase 6 /' "$CMD"; }

@test "Phase 5 renders rules from the lib, not from inline echoes" {
  s=$(p5)
  echo "$s" | grep -qF 'lib/tdd-rules.sh' || { echo "lib not sourced"; return 1; }
  echo "$s" | grep -qF 'tdd_rules_render' || { echo "render not called"; return 1; }
}

@test "Phase 5 no longer hardcodes the rule text" {
  # The rules were four echo lines in this file, which is why they could not
  # compound and why one repo's conftest.py count shipped to every repo.
  s=$(p5 | sed 's/[[:space:]]*#.*$//')
  ! echo "$s" | grep -qF 'echo "1. Tests attach only to the seams' \
    || { echo "inline rule text is back"; return 1; }
  ! echo "$s" | grep -qF 'conftest.py' \
    || { echo "a repo's evidence is in the shared skill again"; return 1; }
}

@test "ship-compound can add a learned rule" {
  grep -qF 'tdd_rules_append' "$CC" || { echo "rules never compound"; return 1; }
  grep -qF 'lib/tdd-rules.sh' "$CC" || { echo "lib not sourced in compound"; return 1; }
}

@test "ship-compound surfaces the cap and unsourced rules" {
  grep -qF 'tdd_rules_over_cap' "$CC" || { echo "no cap check"; return 1; }
  grep -qF 'tdd_rules_unsourced' "$CC" || { echo "unprunable rules go unreported"; return 1; }
}

@test "Phase 5 bash parses" {
  blk=$(p5 | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f')
  [ -n "$blk" ]; echo "$blk" > "$BATS_TEST_TMPDIR/p5.sh"
  run bash -n "$BATS_TEST_TMPDIR/p5.sh"; [ "$status" -eq 0 ]
}
