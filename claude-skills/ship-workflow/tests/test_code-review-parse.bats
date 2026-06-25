#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch code-review-parse)"
  export FIXTURE="$SHIP_SKILL_ROOT/tests/fixtures/code-review-output.md"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "code-review-parse: emits all 4 counts" {
  run "$SHIP_LIB/code-review-parse.sh" "$FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
  [[ "$output" == *"MAJOR_COUNT=2"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
  [[ "$output" == *"PRAISE_COUNT=3"* ]]
}

@test "code-review-parse: output is eval-safe (caller can source it)" {
  run bash -c "eval \"\$('$SHIP_LIB/code-review-parse.sh' '$FIXTURE')\" && echo \"\$BLOCKING_COUNT|\$MAJOR_COUNT|\$MINOR_COUNT|\$PRAISE_COUNT\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"2|2|2|3"* ]]
}

@test "code-review-parse: zero counts on empty file" {
  empty="$SCRATCH/empty.md"
  echo "# nothing to see here" > "$empty"
  run "$SHIP_LIB/code-review-parse.sh" "$empty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=0"* ]]
  [[ "$output" == *"MAJOR_COUNT=0"* ]]
  [[ "$output" == *"MINOR_COUNT=0"* ]]
  [[ "$output" == *"PRAISE_COUNT=0"* ]]
}

@test "code-review-parse: exits 2 when file missing" {
  run "$SHIP_LIB/code-review-parse.sh" "$SCRATCH/does-not-exist.md"
  [ "$status" -eq 2 ]
}

@test "code-review-parse: case-insensitive severity matching" {
  mixed="$SCRATCH/mixed.md"
  cat > "$mixed" <<'EOF'
**Severity:** BLOCKING
**Severity:** Blocking
**Severity:** blocking
[BLOCKING] also counts
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$mixed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=4"* ]]
}

@test "code-review-parse: emoji-tier 🔴/🟡/🟢/🎉 count correctly (awesome-skills convention)" {
  emoji="$SCRATCH/emoji.md"
  cat > "$emoji" <<'EOF'
🔴 handler.py:45 — SQL injection risk in cache_get
🔴 dialogue.py:312 — unhandled None in flush_pending
🟡 service.py:88 — N+1 query in scene fetch
🟡 service.py:104 — magic number 1024
🟡 cache.py:42 — could be extracted to helper
🟢 tests/test_engine.py:8 — missing assertion message
🟢 utils.py:200 — line could be shorter
🎉 service.py:280 — excellent abstraction
🎉 dialogue.py:420 — clear docstring
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$emoji"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
  [[ "$output" == *"MAJOR_COUNT=3"* ]]
  [[ "$output" == *"MINOR_COUNT=2"* ]]
  [[ "$output" == *"PRAISE_COUNT=2"* ]]
}

@test "code-review-parse: [nit] tag counts as minor (awesome-skills idiom)" {
  nit="$SCRATCH/nit.md"
  cat > "$nit" <<'EOF'
[nit] var name could be longer
[nit] consider using a constant
[nit] this comment is redundant
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$nit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MINOR_COUNT=3"* ]]
}

@test "code-review-parse: a line with both emoji + [tag] only counts once (no double-count)" {
  dup="$SCRATCH/dup.md"
  cat > "$dup" <<'EOF'
🔴 [blocking] handler.py:45 — security issue
🔴 [blocking] cache.py:12 — null deref
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$dup"
  [ "$status" -eq 0 ]
  # 2 lines × 1 BLOCKING-tag-per-line = 2 (NOT 4 even though each line has 2 patterns)
  [[ "$output" == *"BLOCKING_COUNT=2"* ]]
}

@test "code-review-parse: mixed emoji + word + [nit] in one file totals correctly" {
  mixed="$SCRATCH/multi-vocab.md"
  cat > "$mixed" <<'EOF'
🔴 emoji-blocking
[blocking] tag-blocking
**Severity:** blocking — word-blocking
🟡 emoji-major
**Severity:** Major — word-major
🟢 emoji-minor
[nit] nit-as-minor
[minor] tag-minor
🎉 emoji-praise
[praise] tag-praise
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$mixed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BLOCKING_COUNT=3"* ]]
  [[ "$output" == *"MAJOR_COUNT=2"* ]]
  [[ "$output" == *"MINOR_COUNT=3"* ]]
  [[ "$output" == *"PRAISE_COUNT=2"* ]]
}

@test "code-review-parse: [important] tag counts as major (awesome-skills yellow-tier)" {
  imp="$SCRATCH/important.md"
  cat > "$imp" <<'EOF'
[important] handler.py:45 — input validation missing
[important] cache.py:12 — error swallowed silently
**Severity:** important — service.py:88 — N+1 query
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$imp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MAJOR_COUNT=3"* ]]
}

@test "code-review-parse: legend / example lines do NOT count as findings" {
  legend="$SCRATCH/with-legend.md"
  cat > "$legend" <<'EOF'
# Code Review Output

## Legend
Severity levels: 🔴 / 🟡 / 🟢 are the three severity tiers
- 🔴 [blocking] - Must fix before merge
- 🟡 [important] - Should address
- 🟢 [nit] - Nice to have, not blocking
- 🎉 [praise] - Good work, keep it up!

Example: a finding tagged with 🔴 [blocking] looks like the one below.

## Real findings

🔴 handler.py:45 — actual SQL injection
🟡 service.py:88 — actual N+1 query
🟢 utils.py:200 — actual style nit
🎉 dialogue.py:312 — actual praise
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$legend"
  [ "$status" -eq 0 ]
  # Only the 4 real findings count. Legend bullets start with `- 🔴 ...`
  # — the `- ` prefix is not whitespace, so our `^[[:space:]]*` anchor
  # doesn't match them. Inline `Severity levels: 🔴 / 🟡 ...` has the
  # emoji mid-line, also doesn't match. Example sentence has emoji mid-line
  # too. So only the 4 bare-emoji-prefixed finding lines count.
  [[ "$output" == *"BLOCKING_COUNT=1"* ]]
  [[ "$output" == *"MAJOR_COUNT=1"* ]]
  [[ "$output" == *"MINOR_COUNT=1"* ]]
  [[ "$output" == *"PRAISE_COUNT=1"* ]]
}

@test "code-review-parse: inline 'Legend:' paragraph does NOT inflate counts" {
  inline_legend="$SCRATCH/inline-legend.md"
  cat > "$inline_legend" <<'EOF'
Legend: 🔴 blocking, 🟡 major, 🟢 minor, 🎉 praise. These are explanatory only.

Real findings below:

🔴 handler.py:45 — real blocking issue
EOF
  run "$SHIP_LIB/code-review-parse.sh" "$inline_legend"
  [ "$status" -eq 0 ]
  # Inline `Legend: 🔴 ...` has emoji NOT at line start (mid-line), so shouldn't count
  # Only the bare `🔴 handler.py:45 ...` line at start counts
  [[ "$output" == *"BLOCKING_COUNT=1"* ]]
  [[ "$output" == *"MAJOR_COUNT=0"* ]]
  [[ "$output" == *"MINOR_COUNT=0"* ]]
  [[ "$output" == *"PRAISE_COUNT=0"* ]]
}
