#!/usr/bin/env bats
load helpers

setup() {
  export CMD="$SHIP_SKILL_ROOT/commands/ship-compound.md"
}

@test "ship-compound sources context-md.sh" {
  run grep -F 'lib/context-md.sh' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound documents the CONTEXT.md entry format" {
  run grep -F -- '- **<term>** — <definition>' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound mirrors CONTEXT.md to the vault" {
  run grep -F 'spec-mirror.sh' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'CONTEXT.md' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound prunes to the 150-line target in interactive mode" {
  run grep -F 'prune to <= 150 lines' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound does NOT prune in auto mode" {
  run grep -F 'pruning is skipped in --auto:yes' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound exports CONTEXT_MD_STATUS for the P9 summary" {
  run grep -F 'CONTEXT_MD_STATUS=' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound guards the CONTEXT.md commit and mirror on file existence" {
  run grep -F 'if [ -f CONTEXT.md ]; then' "$CMD"
  [ "$status" -eq 0 ]
  run grep -F 'absent — no qualifying terms this ship' "$CMD"
  [ "$status" -eq 0 ]
}

@test "ship-compound logs the over-cap decision in auto mode, as the spec promises" {
  # Spec 4.5: auto mode emits "a WARN, a .ship-auto-decisions.md entry, and a line in
  # the P9 summary". Only the WARN and the status were wired. The decision log is the
  # audit trail for an unattended run — the one place the operator looks afterwards.
  run grep -F 'auto-decision-log.sh' "$CMD"
  [ "$status" -eq 0 ]
  block=$(awk '/over cap/,/^   \`\`\`$/' "$CMD")
  echo "$block" | grep -qF 'auto-decision-log.sh' \
    || { echo "the over-cap branch does not write the decision log"; return 1; }
}
