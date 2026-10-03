#!/usr/bin/env bats
load helpers

setup() { export CMD="$SHIP_SKILL_ROOT/commands/ship-next.md"; }
p3() { awk '/^## Phase 3/,/^## Phase 4/' "$CMD"; }
p3code() { p3 | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'; }

@test "Phase 3 looks up past learnings and sources the lib" {
  p3 | grep -qF 'lib/learnings-lookup.sh' || { echo "never sourced"; return 1; }
  p3code | grep -qF 'learnings_match' || { echo "no lookup is performed"; return 1; }
}

@test "Phase 3 caps how many learnings it opens" {
  # Measured: `bucket` matches 32 of 67 learnings; opening them costs ~100k
  # tokens and buries the signal. The cap is the whole point of the design.
  c=$(p3code)
  echo "$c" | grep -qF 'LEARN_CAP=' || { echo "no cap"; return 1; }
  echo "$c" | grep -qF 'LEARN_N' || { echo "hits are never counted"; return 1; }
}

@test "Phase 3 falls back to a path list instead of opening everything" {
  # Not titles: only 12 of 67 real learnings have an H1, and none has a
  # title: field. The filename carries the slug and every file has one.
  s=$(p3)
  echo "$s" | grep -qiF 'too many to open' || { echo "no over-cap fallback"; return 1; }
  ! echo "$s" | grep -qF 'learnings_title' || { echo "calls a helper that was deleted"; return 1; }
}

@test "Phase 3 counts with the form that does not emit a double zero" {
  # `grep -c ... || echo 0` prints 0 AND exits 1, yielding "00". This repo
  # has already shipped that bug once.
  # Strip comments first: the comment warning about the bad form contains the
  # bad form, and the guard matched it. Fifth time in this repo.
  c=$(p3code | sed 's/[[:space:]]*#.*$//')
  ! echo "$c" | grep -qF 'grep -c . || echo 0' || { echo "double-zero form is back"; return 1; }
  echo "$c" | grep -qE 'grep -c \.( \|\| true)?' || { echo "no count at all"; return 1; }
}

@test "Phase 3 still reads CONTEXT.md first" {
  # Vocabulary before history: the terms drive the lookup.
  s=$(p3)
  ctx=$(echo "$s" | grep -n 'CONTEXT.md' | head -1 | cut -d: -f1)
  lrn=$(echo "$s" | grep -n 'learnings_match' | head -1 | cut -d: -f1)
  [ -n "$ctx" ] && [ -n "$lrn" ]
  [ "$ctx" -lt "$lrn" ] || { echo "learnings are looked up before the vocabulary"; return 1; }
}

@test "Phase 3 bash parses" {
  blk=$(p3code); [ -n "$blk" ]
  echo "$blk" > "$BATS_TEST_TMPDIR/p3.sh"
  run bash -n "$BATS_TEST_TMPDIR/p3.sh"
  [ "$status" -eq 0 ]
}
