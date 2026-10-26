#!/usr/bin/env bats
load helpers
setup() { CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }

@test "Phase 3 requires a Door decision" {
  awk '/^## Phase 3/,/^## Phase 4/' "$CMD" | grep -qF 'Door: one-way|two-way'
}
@test "Phase 7 computes the door and writes the body head" {
  text=$(awk '/^## Phase 7/,/^## Phase 8/' "$CMD")
  [[ "$text" == *'sn_door "$WORKTREE"'* ]] || return 1
  [[ "$text" == *'.ship/pr-head.md'* ]]
}
@test "Phase 8 loads ship state before resolving merge mode" {
  text=$(awk '/^## Phase 8 /,/^## Phase 8.5/' "$CMD")
  [[ "$text" == *sn_state_load*merge_mode* ]]
}
@test "Phase 9 step 0a loads ship state before resolving merge mode" {
  text=$(awk '/^0a\./,/^0\. /' "$CMD" | awk '/```bash/{f=1;next} /```/{f=0} f')
  load_line=$(printf '%s\n' "$text" | grep -n sn_state_load | cut -d: -f1)
  mode_line=$(printf '%s\n' "$text" | grep -nF 'MERGE_MODE=$(merge_mode)' | cut -d: -f1)
  [ -n "$load_line" ] && [ "$load_line" -lt "$mode_line" ]
}
@test "SPEC template includes Door" {
  grep -qF 'Door:' "$SHIP_SKILL_ROOT/templates/repo/SPEC.md"
}

@test "Phase 8 and 9 resolve the per-ship mode in fresh bash and zsh shells" {
  export SHIP_LIB WORKTREE="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$WORKTREE/.ship"
  printf 'SHIP_MERGE_MODE=mr\n' > "$WORKTREE/.ship/state.env"
  awk '/^## Phase 8 /{p=1} /^\*\*`squash`/{p=0} p' "$CMD" > "$BATS_TEST_TMPDIR/phase8"
  awk '/^0a\./,/^0\. /' "$CMD" > "$BATS_TEST_TMPDIR/phase9"
  for phase in phase8 phase9; do
    awk '/```bash/{f=1;next} /```/{f=0} f' "$BATS_TEST_TMPDIR/$phase" \
      | sed 's#~/.claude/skills/ship-workflow/lib/#"$SHIP_LIB"/#g' > "$BATS_TEST_TMPDIR/run.sh"
    if [ "$phase" = phase9 ]; then echo 'echo "$MERGE_MODE"' >> "$BATS_TEST_TMPDIR/run.sh"; fi
    for shell in bash zsh; do
      run "$shell" "$BATS_TEST_TMPDIR/run.sh"
      [ "$status" -eq 0 ]
      [ "$output" = mr ]
    done
  done
}
