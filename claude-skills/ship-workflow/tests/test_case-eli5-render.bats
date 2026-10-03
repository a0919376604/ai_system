#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch case-eli5)"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "CASE_ELI5.md template exists at expected path" {
  [ -f "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" ]
}

@test "render_template substitutes all placeholders in CASE_ELI5" {
  source "$SHIP_LIB/render-template.sh"
  local out
  out=$(render_template "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" \
    id="R-042" project="langlive-line-oa" slug="topic-switch" theme="ai-flow" \
    date="2026-08-30" ua_changed_files="- foo.py" ua_blast_radius="- bar.py imports foo" \
    ua_raw_diff_report="raw diff here")
  [[ "$out" =~ "R-042" ]] || return 1
  [[ "$out" =~ "langlive-line-oa" ]] || return 1
  [[ "$out" =~ "topic-switch" ]] || return 1
  [[ "$out" =~ "ai-flow" ]] || return 1
  [[ "$out" =~ "2026-08-30" ]] || return 1
  [[ "$out" =~ "- foo.py" ]] || return 1
  [[ "$out" =~ "- bar.py imports foo" ]] || return 1
  [[ "$out" =~ "TODO" ]]  # human sections retain TODO markers
}
