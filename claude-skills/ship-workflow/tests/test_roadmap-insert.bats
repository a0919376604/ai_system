#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch roadmap-insert)"
  export AIROS="$(make_fake_airos "$SCRATCH" "demo")"
  export ROADMAP="$AIROS/10 Projects/demo/ROADMAP.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "roadmap-insert: appends to empty Now section" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-018 "Fix langfuse leak"
  grep -q "R-018" "$ROADMAP"
  # Confirm it's between the Now heading and the Next heading
  now_ln=$(grep -n "^## 🔥 Now" "$ROADMAP" | head -1 | cut -d: -f1)
  r018_ln=$(grep -n "R-018" "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$(grep -n "^## 🔜" "$ROADMAP" | head -1 | cut -d: -f1)
  [ "$now_ln" -lt "$r018_ln" ]
  [ "$r018_ln" -lt "$next_ln" ]
}

@test "roadmap-insert: marks adhoc-inserted=true" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-019 "Quick fix" --adhoc
  grep -q "adhoc-inserted=true" "$ROADMAP"
}

@test "roadmap-insert: skips adhoc marker when --adhoc absent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-020 "Planned work"
  ! awk '/R-020/' "$ROADMAP" | grep -q "adhoc-inserted=true"
}

@test "roadmap-insert: preserves existing Now items" {
  # Pre-populate
  sed -i.bak '/^## 🔥 Now/a\
- [ ] **R-001** Existing item' "$ROADMAP" && rm "$ROADMAP.bak"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-002 "New item"
  grep -q "R-001" "$ROADMAP"
  grep -q "R-002" "$ROADMAP"
}

@test "roadmap-insert: writes atomically (no .tmp left)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-021 "Atomic test"
  ! ls "$AIROS/10 Projects/demo/"*.tmp 2>/dev/null
}

@test "roadmap-insert: errors when ROADMAP.md missing" {
  run "$SHIP_LIB/roadmap-insert.sh" "$AIROS/nonexistent/ROADMAP.md" R-099 "x"
  [ "$status" -ne 0 ]
}

@test "roadmap-insert: errors when no Now heading found" {
  echo "no headings here" > "$ROADMAP"
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-099 "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Now"* ]]
}

@test "roadmap-insert: --epic adds (epic) marker" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  grep -q '\*\*R-014 (epic)\*\*' "$ROADMAP"
}

@test "roadmap-insert: --child inserts indented child under parent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Backoff layer" --child R-014
  # Child appears after parent
  parent_ln=$(grep -n 'R-014 (epic)' "$ROADMAP" | head -1 | cut -d: -f1)
  child_ln=$(grep -n 'R-014\.1' "$ROADMAP" | head -1 | cut -d: -f1)
  [ "$child_ln" -gt "$parent_ln" ]
  # Child is indented (starts with 2 spaces)
  grep -E '^  - \[ \] \*\*R-014\.1\*\*' "$ROADMAP"
}

@test "roadmap-insert: --child errors if parent not found" {
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Orphan" --child R-099
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent R-099 not found"* ]]
}

@test "roadmap-insert: --mark-warning adds ⚠️ + flagged annotation" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "touches 3 modules"
  grep -q '⚠️ \*\*R-014\*\*' "$ROADMAP"
  grep -q 'flagged: touches 3 modules' "$ROADMAP"
}

@test "roadmap-insert: --mark-warning idempotent" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "reason 1"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "reason 2"
  warning_count=$(grep -c '⚠️ \*\*R-014\*\*' "$ROADMAP")
  [ "$warning_count" -eq 1 ]
}

@test "roadmap-insert: --mark-epic strips ⚠️ + adds (epic)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-warning "too big"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 --mark-epic
  # ⚠️ gone, (epic) present
  ! grep -q '⚠️' "$ROADMAP"
  grep -q '\*\*R-014 (epic)\*\*' "$ROADMAP"
  # flagged annotation also gone
  ! grep -q 'flagged:' "$ROADMAP"
}

@test "roadmap-insert: --done-when writes a 2-line entry (insert mode)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-030 "Add OTel tracing to webhook handler" \
    --done-when "p95 trace coverage > 95% in staging"
  grep -q '\*\*R-030\*\* Add OTel tracing' "$ROADMAP"
  grep -q '↳ done when: p95 trace coverage > 95% in staging' "$ROADMAP"
  # done-when line is INDENTED (4 spaces) and immediately follows the entry
  entry_ln=$(grep -n '\*\*R-030\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((entry_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^    ↳ done when:'
}

@test "roadmap-insert: --est adds est=<duration> to suffix" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-031 "Refactor auth layer" --est 3d
  grep -q 'est=3d' "$ROADMAP"
}

@test "roadmap-insert: --done-when + --est combine on the same entry" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-032 "Migrate to pnpm" \
    --est 1w --done-when "pnpm install green on CI"
  # Entry line carries est=
  grep -E '\*\*R-032\*\*.*est=1w' "$ROADMAP"
  # Annotation present
  grep -q '↳ done when: pnpm install green on CI' "$ROADMAP"
}

@test "roadmap-insert: --done-when in --child mode writes indented (6 spaces) annotation" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Backoff layer" --child R-014 \
    --done-when "exponential backoff 200ms→3s passes integration test"
  grep -q '↳ done when: exponential backoff' "$ROADMAP"
  # The done-when annotation under a child must be indented by 6 spaces
  child_ln=$(grep -n '\*\*R-014\.1\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((child_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^      ↳ done when:'
}

@test "roadmap-insert: --explain writes a [[wikilink]] annotation (insert mode)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-040 "Add OTel tracing" \
    --explain "Roadmap-Notes/R-040-add-otel-tracing"
  grep -q '\*\*R-040\*\* Add OTel tracing' "$ROADMAP"
  grep -qF '↳ explain: [[Roadmap-Notes/R-040-add-otel-tracing]]' "$ROADMAP"
  # Annotation indented 4 spaces immediately below entry
  entry_ln=$(grep -n '\*\*R-040\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((entry_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain: \[\['
}

@test "roadmap-insert: --explain appears BEFORE --done-when when both given (insert mode)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-041 "Wire SceneEngine" \
    --explain "Roadmap-Notes/R-041-wire-scene-engine" \
    --done-when "TTFB 不 regress"
  entry_ln=$(grep -n '\*\*R-041\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  explain_ln=$((entry_ln + 1))
  done_ln=$((entry_ln + 2))
  sed -n "${explain_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain: \[\['
  sed -n "${done_ln}p" "$ROADMAP" | grep -qE '^    ↳ done when:'
}

@test "roadmap-insert: --explain in child mode indents 6 spaces" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Backoff layer" --child R-014 \
    --explain "Roadmap-Notes/R-014.1-backoff-layer"
  child_ln=$(grep -n '\*\*R-014\.1\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((child_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^      ↳ explain: \[\[Roadmap-Notes/R-014\.1'
}

@test "roadmap-insert: --inject-explain adds explain annotation to existing row" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-050 "Refactor cache"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-050 --inject-explain "Roadmap-Notes/R-050-refactor-cache"
  grep -qF '↳ explain: [[Roadmap-Notes/R-050-refactor-cache]]' "$ROADMAP"
  entry_ln=$(grep -n '\*\*R-050\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((entry_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain:'
}

@test "roadmap-insert: --inject-explain is idempotent on same slug" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 "Add tracing"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 --inject-explain "Roadmap-Notes/R-051-add-tracing"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 --inject-explain "Roadmap-Notes/R-051-add-tracing"
  count=$(grep -cF '↳ explain: [[Roadmap-Notes/R-051-add-tracing]]' "$ROADMAP")
  [ "$count" -eq 1 ]
}

@test "roadmap-insert: --inject-explain on different slug replaces + warns" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 "Add metrics"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 --inject-explain "Roadmap-Notes/R-052-old-slug"
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 --inject-explain "Roadmap-Notes/R-052-new-slug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: replacing explain annotation"* ]]
  grep -qF '↳ explain: [[Roadmap-Notes/R-052-new-slug]]' "$ROADMAP"
  ! grep -qF '↳ explain: [[Roadmap-Notes/R-052-old-slug]]' "$ROADMAP"
}

@test "roadmap-insert: --inject-explain places annotation BEFORE existing done-when" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-053 "Wire X" --done-when "p95 < 100ms"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-053 --inject-explain "Roadmap-Notes/R-053-wire-x"
  entry_ln=$(grep -n '\*\*R-053\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  explain_ln=$((entry_ln + 1))
  done_ln=$((entry_ln + 2))
  sed -n "${explain_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain:'
  sed -n "${done_ln}p"    "$ROADMAP" | grep -qE '^    ↳ done when:'
}
