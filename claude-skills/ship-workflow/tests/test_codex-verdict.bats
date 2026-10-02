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
