#!/usr/bin/env bats
# Spec §7: the acceptance gate. Each test maps to one numbered criterion.
#
# A finding blocks ONLY if it describes a way a developer loses work or is
# misled about the outcome of a ship. Anything else is a follow-up.
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-acceptance)"
  export WT="$SCRATCH/wt"
  mkdir -p "$WT"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-verdict.sh"
  source "$SHIP_LIB/codex-rounds.sh"
  source "$SHIP_LIB/codex-supervise-state.sh"
  export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"
}
teardown() { rm -rf "$SCRATCH"; }

@test "spec 7.2: every infrastructure signature classifies as infra" {
  for sig in "ERROR: Your workspace is out of credits." \
             "ERROR: This content was flagged for possible cybersecurity risk." \
             "error=exec_command failed: UnknownProcessId { process_id: 1 }" \
             "ERROR codex_core::session: failed to record rollout items: thread not found"; do
    printf '%s\n' "$sig" > l.log
    run codex_verdict l.log
    [ "$output" = "infra" ] || { echo "not classified infra: $sig"; return 1; }
  done
}

@test "spec 7.2: the infra branch neither advances the attempt nor writes state" {
  # The plan's version of this test read the attempt twice with no call in
  # between and asserted the two were equal — it could not fail. The claim is
  # about the COMMAND TEXT, so check that: the infra branch must not reach
  # codex_state_write or increment CODEX_ATTEMPT.
  infra=$(awk '/- \*\*`stop_infra`\*\*/,/- \*\*`classify`\*\*/' "$CMD")
  [ -n "$infra" ]
  ! echo "$infra" | grep -qF 'codex_state_write' \
    || { echo "the infra branch writes state"; return 1; }
  ! echo "$infra" | grep -qF 'CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))' \
    || { echo "the infra branch advances the attempt"; return 1; }
  echo "$infra" | grep -qF 'attempt count unchanged' \
    || { echo "the infra branch does not state the invariant"; return 1; }
}

@test "spec 7.3: a spec-level report is recognisable as such" {
  # Fixture modelled on the real round that concluded a gate could not work.
  # NB: passed as a real file. The plan used `<(cat r.md)`, and codex_verdict
  # tests `[ -f ]`, which is false for a process substitution — that version
  # classified this as infra and asserted blocked.
  cat > r.md <<'EOT'
**BLOCKED.** Suite passed 237/237, but Phase 8.5 still accepts coverage loss.
These are more defects of the same measurement class.
**I recommend making Phase 8.5 REPORT-ONLY:** the approach cannot establish safety.
EOT
  run codex_verdict r.md
  [ "$output" = "blocked" ]
  # NOTE: only the line above exercises code. Deciding that this report is
  # spec-level rather than a plan defect is an LLM judgement with no mechanical
  # surface, so there is nothing further to assert here. An earlier version
  # grepped the fixture for the words the fixture itself contains, which could
  # not fail for any implementation change. The routing rules that act on this
  # judgement are covered in test_ship-next-codex-loop.bats.
}

@test "spec 7.4: three attempts is the documented cap, and it gates the relaunch" {
  grep -qF 'CODEX_ATTEMPT_CAP=3' "$CMD"
  grep -qF 'CODEX_ROUTE=stop_exhausted' "$CMD"
}

@test "spec 7.5: a stored round is byte-identical to the report" {
  printf '**BLOCKED**\n\n- `git diff` returns 0\n- $HOME unquoted\n# hash line\n' > r.md
  codex_round_append "$WT" 1 blocked r.md "plan defect" "x"
  while IFS= read -r line; do
    grep -qxF -- "$line" "$WT/.ship/codex-rounds.md" || { echo "lost: $line"; return 1; }
  done < r.md
}

@test "spec 7.5: a long report survives — the operator is not shown an empty round" {
  # The failure this guards: a report whose verdict marker sits outside a fixed
  # tail window extracted to nothing, while the run classified as `done`. The
  # operator would read a blank round and believe the run reported nothing.
  { for i in $(seq 1 60); do echo "progress line $i"; done
    echo "**DONE**"; echo ""; echo "- Task 1 complete"
    for i in $(seq 1 45); do echo "trailing detail $i"; done
  } > big.log
  run codex_report_extract big.log rpt.md
  [ "$status" -eq 0 ]
  [ -s rpt.md ]
  codex_round_append "$WT" 1 done rpt.md "n/a" "completed"
  run codex_round_last_findings "$WT"
  [[ "$output" == *"- Task 1 complete"* ]]
}

@test "spec 7.5: an unextractable report is never stored as an empty round" {
  printf 'no verdict here at all\n' > l.log
  run codex_report_extract l.log rpt.md
  [ "$status" -eq 2 ]
  [ ! -f rpt.md ]
  run codex_round_count "$WT"
  [ "$output" = "0" ]
}

@test "spec 7.6: resume reads state and does not inherit another ship's loop" {
  codex_state_write "$WT" "docs/plans/R-001-a.md" "s" 2 blocked "plan defect" "Task 7"
  run codex_state_matches "$WT" "docs/plans/R-001-a.md"; [ "$status" -eq 0 ]
  run codex_state_matches "$WT" "docs/plans/R-002-b.md"; [ "$status" -ne 0 ]
  run codex_state_attempt "$WT"; [ "$output" = "2" ]
}

@test "spec 7.6: liveness never reports alive on a pid it cannot verify" {
  # A false "alive" is the one failure this feature exists to prevent: Phase 5
  # waits forever on a process that does not exist.
  mkdir -p "$WT/.ship"
  for bad in "-1" "0" "not-a-pid" ""; do
    printf '%s\n' "$bad" > "$WT/.ship/codex.pid"
    run codex_state_alive "$WT"
    [ "$status" -ne 0 ] || { echo "reported alive for pid '$bad'"; return 1; }
  done
}

@test "spec 7.6: the round history is captured before cleanup destroys it" {
  # Phase 9 step 1 removes the worktree. Reading .ship/ after that returns
  # nothing, and the operator is told the run produced no findings.
  sec=$(awk '/^## Phase 9/,0' "$CMD")
  read_at=$(echo "$sec" | grep -n 'codex_round_last_findings' | head -1 | cut -d: -f1)
  rm_at=$(echo "$sec" | grep -n 'git worktree remove "\$WORKTREE"' | head -1 | cut -d: -f1)
  [ -n "$read_at" ] && [ -n "$rm_at" ]
  [ "$read_at" -lt "$rm_at" ]
}

@test "spec 7.7: every supervise helper no-ops without codex state" {
  run codex_verdict "$SCRATCH/absent.log";        [ "$output" = "infra" ]
  run codex_round_count "$WT";                    [ "$output" = "0" ]
  run codex_round_last_findings "$WT";            [ -z "$output" ]
  run codex_state_attempt "$WT";                  [ "$output" = "0" ]
  run codex_state_alive "$WT";                    [ "$status" -ne 0 ]
}

@test "spec 7.7: the three new libs source together without collision" {
  run bash -c "source '$SHIP_LIB/codex-verdict.sh'; source '$SHIP_LIB/codex-rounds.sh'; source '$SHIP_LIB/codex-supervise-state.sh'; echo ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "spec 7.7: every phase that calls a supervise helper also sources its lib" {
  # Phases do not share a shell. Three prior defects in this repo were exactly
  # this, and all of them fail closed — the feature silently does nothing.
  #
  # The function list is DERIVED from the libs, not restated here. A hardcoded
  # list omitted codex_state_alive/_matches/_attempt/_get, and a review proved
  # the hole: inserting codex_state_alive into Phase 6 (which did not source
  # codex-supervise-state.sh) left the whole suite green.
  for lib in codex-verdict.sh codex-rounds.sh codex-supervise-state.sh; do
    fns=$(grep -oE '^codex_[a-z_]+\(\)' "$SHIP_LIB/$lib" | tr -d '()')
    [ -n "$fns" ] || { echo "derived no public functions from $lib"; return 1; }
    for phase in 5 6 9; do
      case "$phase" in
        5) sec=$(awk '/^## Phase 5 /,/^## Phase 6 /' "$CMD") ;;
        6) sec=$(awk '/^## Phase 6 /,/^## Phase 7 /' "$CMD") ;;
        9) sec=$(awk '/^## Phase 9 /,0' "$CMD") ;;
      esac
      [ -n "$sec" ] || { echo "Phase $phase not found"; return 1; }
      for fn in $fns; do
        if echo "$sec" | grep -qF "$fn"; then
          echo "$sec" | grep -qF "lib/$lib" \
            || { echo "Phase $phase calls $fn without sourcing $lib"; return 1; }
        fi
      done
    done
  done
}

@test "spec 7.7: the derived function list is not silently empty" {
  # If the grep that derives the list ever stops matching, the guard above
  # passes vacuously. Pin the two functions whose omission was the known hole.
  all=$(grep -hoE '^codex_[a-z_]+\(\)' "$SHIP_LIB"/codex-*.sh | tr -d '()')
  for fn in codex_state_alive codex_state_matches codex_wait_for_exit \
            codex_verdict codex_report_extract codex_round_count; do
    echo "$all" | grep -qx "$fn" || { echo "derivation missed $fn"; return 1; }
  done
}

@test "no supervise helper declares a local inside a loop body" {
  # zsh prints a re-declared local; bash does not. Enforced repo-wide.
  for f in codex-verdict.sh codex-rounds.sh codex-supervise-state.sh; do
    awk '
      /^[a-z_]+\(\)/ { fn=$1; depth=0 }
      /(^|[[:space:];])(while|for)[[:space:]].*[[:space:];]do[[:space:]]*$/ { if (fn) depth++ }
      /^[[:space:]]*done/ { if (fn && depth>0) depth-- }
      /^[[:space:]]*local / { if (fn && depth>0) print FILENAME": "FNR": "$0 }
    ' "$SHIP_LIB/$f"
  done > "$SCRATCH/loop-locals.txt"
  if [ -s "$SCRATCH/loop-locals.txt" ]; then cat "$SCRATCH/loop-locals.txt"; return 1; fi
}

@test "bash and zsh agree on every supervise helper" {
  for sh in bash zsh; do
    command -v "$sh" >/dev/null || continue
    "$sh" -c "
      source '$SHIP_LIB/codex-verdict.sh'
      source '$SHIP_LIB/codex-rounds.sh'
      source '$SHIP_LIB/codex-supervise-state.sh'
      mkdir -p '$SCRATCH/$sh/wt'
      printf '**BLOCKED**\n\n- a finding\n' > '$SCRATCH/$sh/r.md'
      codex_round_append '$SCRATCH/$sh/wt' 1 blocked '$SCRATCH/$sh/r.md' c n >/dev/null
      codex_state_write '$SCRATCH/$sh/wt' p.md s 1 blocked c 'Task 1'
      echo \"\$(codex_round_count '$SCRATCH/$sh/wt')|\$(codex_round_last_findings '$SCRATCH/$sh/wt')|\$(codex_state_attempt '$SCRATCH/$sh/wt')\"
    " > "$SCRATCH/$sh.out" 2>&1
  done
  if [ -f "$SCRATCH/zsh.out" ]; then
    diff "$SCRATCH/bash.out" "$SCRATCH/zsh.out" || { echo "bash and zsh diverge"; return 1; }
  fi
}

@test "spec 7.6: the integer pid guard holds even with a permissive matcher" {
  # Defense in depth, pinned independently. The ps check currently MASKS the
  # integer guard — `ps -p -1` errors out, so removing the guard changes no
  # observable behaviour and a mutation of it survives. Stub ps to accept
  # anything, and the guard becomes the only thing standing between a pid file
  # of "-1" and `kill -0 -1`, which exits 0 because it signals a process group.
  mkdir -p "$SCRATCH/bin"
  printf '#!/bin/sh\necho "codex exec --dangerously-bypass"\n' > "$SCRATCH/bin/ps"
  chmod +x "$SCRATCH/bin/ps"
  export PATH="$SCRATCH/bin:$PATH"
  mkdir -p "$WT/.ship"
  # Sanity: the stub is in effect, so a REAL pid does read as alive here.
  echo "$$" > "$WT/.ship/codex.pid"
  run codex_state_alive "$WT"
  [ "$status" -eq 0 ] || { echo "stub not in effect; test proves nothing"; return 1; }
  for bad in "-1" "0"; do
    printf '%s\n' "$bad" > "$WT/.ship/codex.pid"
    run codex_state_alive "$WT"
    [ "$status" -ne 0 ] || { echo "reported alive for pid '$bad'"; return 1; }
  done
}
