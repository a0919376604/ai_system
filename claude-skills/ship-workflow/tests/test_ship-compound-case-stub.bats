#!/usr/bin/env bats
# The case stub's contract is the TEMPLATE, not the source of its values. It used to
# be tested by running ua_get_shipped_facts and sed-parsing its output — which tested
# the bash helper, not the template, and baked in the prose-as-contract assumption
# this change removes. Claude now reads /understand-diff and supplies the three
# fields, so the template is tested directly against the values it is handed.
load helpers

setup() {
  export SCRATCH="$(make_scratch ship-compound-case)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
  cd "$SCRATCH"
  source "$SHIP_LIB/render-template.sh"
}

teardown() { rm -rf "$SCRATCH"; }

@test "case stub renders every placeholder it is given" {
  stub=$(render_template "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" \
    id="R-042" project="test" slug="topic-switch" theme="ai-flow" \
    date="2026-08-30" \
    ua_changed_files="- \`foo.py\`: the thing that does the thing" \
    ua_blast_radius="- \`bar.py\` imports foo.py" \
    ua_raw_diff_report="## UA blast radius")

  [[ "$stub" == *"R-042"* ]] || return 1
  [[ "$stub" == *"foo.py"* ]] || return 1
  [[ "$stub" == *"bar.py"* ]] || return 1
  [[ "$stub" == *"ai-flow"* ]] || return 1
  [[ "$stub" == *"2026-08-30"* ]]
}

@test "case stub leaves no unsubstituted placeholder" {
  stub=$(render_template "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" \
    id="R-042" project="test" slug="s" theme="t" date="2026-08-30" \
    ua_changed_files="c" ua_blast_radius="b" ua_raw_diff_report="r")
  if echo "$stub" | grep -oE '\{\{[a-z_]+\}\}'; then
    echo "the template has placeholders the caller is not told to fill"
    return 1
  fi
}

@test "case stub renders with empty UA fields — UA absent must not break it" {
  # ship-compound only runs the UA step when the plugin is installed, but the
  # template must not produce broken markdown if the fields arrive empty.
  stub=$(render_template "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" \
    id="R-042" project="test" slug="s" theme="t" date="2026-08-30" \
    ua_changed_files="" ua_blast_radius="" ua_raw_diff_report="")
  [ -n "$stub" ]
  [[ "$stub" == *"R-042"* ]]
}
