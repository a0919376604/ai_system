#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch ship-compound-case)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "case stub renders with UA facts when UA present" {
  cd "$SCRATCH"
  make_fake_ua_plugin_cache "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "chore: plan R-042"
  local base; base=$(git rev-parse HEAD)
  make_fake_ua_kg "$SCRATCH" "$base"
  echo "x" > foo.py
  git add foo.py && git -c user.email=t@t -c user.name=t commit -q -m "impl"

  source "$SHIP_LIB/ua-integration.sh"
  source "$SHIP_LIB/render-template.sh"
  local ua_facts; ua_facts=$(ua_get_shipped_facts "R-042")
  local stub; stub=$(render_template "$SHIP_SKILL_ROOT/templates/repo/CASE_ELI5.md" \
    id="R-042" project="test" slug="topic-switch" theme="ai-flow" \
    date="2026-08-30" \
    ua_changed_files="$(echo "$ua_facts" | sed -n '/### Changed components/,/^###/p' | sed '/^###/d')" \
    ua_blast_radius="$(echo "$ua_facts" | sed -n '/### Affected components/,/^###/p' | sed '/^###/d')" \
    ua_raw_diff_report="$ua_facts")

  [[ "$stub" =~ "R-042" ]]
  [[ "$stub" =~ "foo.py" ]]
  [[ "$stub" =~ "TODO" ]]
  [[ "$stub" =~ "UA raw facts" ]]
}
