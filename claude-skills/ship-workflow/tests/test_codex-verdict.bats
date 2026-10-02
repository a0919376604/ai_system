#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch codex-verdict)"
  cd "$SCRATCH"
  source "$SHIP_LIB/codex-verdict.sh"
}
teardown() { rm -rf "$SCRATCH"; }

mklog() { printf '%s\n' "$@" > run.log; }

@test "codex_verdict: a bold DONE is done" {
  mklog "tokens used" "140,000" "**DONE.** Committed Task 11 as 7a15404."
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: a bare DONE is done" {
  mklog "DONE"
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: DONE_WITH_CONCERNS is its own verdict" {
  mklog "**DONE_WITH_CONCERNS** two follow-ups recorded"
  run codex_verdict run.log
  [ "$output" = "done_with_concerns" ]
}

@test "codex_verdict: a bold BLOCKED is blocked" {
  mklog "**BLOCKED.** Suite passed 231/231, but three guard bypasses remain:"
  run codex_verdict run.log
  [ "$output" = "blocked" ]
}

@test "codex_verdict: out of credits is infra, not a verdict" {
  mklog "BEGIN." "ERROR: Your workspace is out of credits. Add credits to continue."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a content filter trip is infra" {
  mklog "ERROR: This content was flagged for possible cybersecurity risk."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a crashed process is infra" {
  mklog "ERROR codex_core::tools::router: error=exec_command failed: UnknownProcessId { process_id: 91680 }"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a lost rollout thread is infra" {
  mklog "ERROR codex_core::session: failed to record rollout items: thread not found"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: no marker at all is infra, never done" {
  mklog "OpenAI Codex v0.155.1" "workdir: /tmp/x" "tokens used" "42"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: infrastructure wins over a verdict printed before it" {
  # Credits ran out after the report was emitted: the run did not complete.
  mklog "**BLOCKED.** two defects remain" "ERROR: Your workspace is out of credits."
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_verdict: a marker quoted mid-sentence is not the verdict" {
  # The prompt tells the executor to "report BLOCKED"; echoing that is not a verdict.
  mklog "The instructions say to report BLOCKED if anything fails." "**DONE.** all green"
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict: a missing log is infra, not an error" {
  run codex_verdict nope.log
  [ "$status" -eq 0 ]
  [ "$output" = "infra" ]
}

@test "codex_verdict_reason: names the infrastructure signature it matched" {
  mklog "ERROR: Your workspace is out of credits."
  run codex_verdict_reason run.log
  [[ "$output" == *"out of credits"* ]]
}

@test "codex_verdict_reason: says so when no marker was produced" {
  mklog "tokens used" "42"
  run codex_verdict_reason run.log
  [[ "$output" == *"no verdict"* ]]
}

# --- codex_report_extract ----------------------------------------------------

@test "codex_report_extract: finds a marker far from the end of a long log" {
  # The reproduction: 109 lines, verdict 49 lines from the end. The `tail -40`
  # version produced a zero-line report here while codex_verdict said `done`.
  { for i in $(seq 1 60); do echo "progress line $i"; done
    echo "**DONE**"
    echo ""
    echo "- Task 1 complete"
    for i in $(seq 1 45); do echo "trailing detail $i"; done
  } > big.log
  run codex_report_extract big.log out.md
  [ "$status" -eq 0 ]
  [ "$(head -1 out.md)" = "**DONE**" ]
  grep -qF -- "- Task 1 complete" out.md
  grep -qF "trailing detail 45" out.md
  # And it agrees with the classifier on the same log.
  run codex_verdict big.log
  [ "$output" = "done" ]
}

@test "codex_report_extract: takes the last marker, not the first" {
  printf 'BLOCKED\nfirst report\n**DONE**\nsecond report\n' > run.log
  run codex_report_extract run.log out.md
  [ "$status" -eq 0 ]
  [ "$(head -1 out.md)" = "**DONE**" ]
  ! grep -qF 'first report' out.md
}

@test "codex_report_extract: no marker exits 2 and writes no file" {
  printf 'just some output\nnothing conclusive\n' > run.log
  run codex_report_extract run.log out.md
  [ "$status" -eq 2 ]
  [ ! -f out.md ]
}

@test "codex_report_extract: a missing log exits 2" {
  run codex_report_extract nope.log out.md
  [ "$status" -eq 2 ]
  [ ! -f out.md ]
}

@test "codex_report_extract: the prompt's own words do not start a report" {
  # Same line-anchoring rule as the classifier: "report BLOCKED" mid-sentence
  # is an instruction, not a verdict.
  printf 'you must report BLOCKED if you cannot proceed\n**DONE**\nthe real report\n' > run.log
  run codex_report_extract run.log out.md
  [ "$status" -eq 0 ]
  [ "$(head -1 out.md)" = "**DONE**" ]
  ! grep -qF 'you must report' out.md
}

@test "codex_report_extract: the report is preserved byte-for-byte from the marker" {
  printf '**BLOCKED**\n\n- `git diff` returns exit 0\n- $HOME is unquoted\n~~~\n' > run.log
  run codex_report_extract run.log out.md
  [ "$status" -eq 0 ]
  run diff run.log out.md
  [ "$status" -eq 0 ]
}

@test "codex_verdict: a log containing ONLY the prompt's echoed marker is infra" {
  # The previous anchoring test put a real **DONE.** after the quoted line, so
  # removing ^ from CODEX_VERDICT_MARKER_RE still produced the right answer and
  # the test could not fail on its own claim. With no real verdict present, the
  # anchor is the only thing preventing the prompt from being read back as one.
  mklog "you must report DONE / DONE_WITH_CONCERNS / BLOCKED when finished" \
        "run interrupted before any verdict was printed"
  run codex_verdict run.log
  [ "$output" = "infra" ]
}

@test "codex_report_extract: the prompt's echoed marker does not start a report" {
  printf 'please report DONE when finished\nnothing else happened\n' > run.log
  run codex_report_extract run.log out.md
  [ "$status" -eq 2 ]
  [ ! -f out.md ]
}

@test "codex_verdict: the LAST marker wins, not the first" {
  # The last-vs-first rule is duplicated between _codex_marker and
  # codex_report_extract; only the extractor's half was pinned. Changing
  # _codex_marker's `tail -1` to `head -1` previously left the suite green.
  mklog "BLOCKED" "retried after repairing the plan" "**DONE.** all green"
  run codex_verdict run.log
  [ "$output" = "done" ]
}

@test "codex_verdict_reason: also reports the LAST marker" {
  mklog "DONE" "then a later task failed" "**BLOCKED.** task 7 cannot proceed"
  run codex_verdict_reason run.log
  [[ "$output" == *BLOCKED* ]]
}
