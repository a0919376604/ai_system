#!/usr/bin/env bats
# lib/pre-existing.sh (R-003 §3.5 step 4.5): a pre-existing defect flagged by
# every ship that touches its code path must become ONE follow-up, not one per ship.
load helpers

setup() {
  export SCRATCH="$(make_scratch pre-existing)"
  mkdir -p "$SCRATCH/repo/docs/ideas" && cd "$SCRATCH/repo"
  git init -q
  source "$SHIP_LIB/pre-existing.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "key: file and security category for a security finding" {
  run pre_existing_key '🔴 [blocking] [pre-existing] [security:prompt_injection] backend/prompts/a.py:247 — flat prompt'
  [ "$status" -eq 0 ]
  [ "$output" = "backend/prompts/a.py:prompt_injection" ]
}

@test "key: file and the first 40 lowercased characters of the description otherwise" {
  run pre_existing_key '🟡 [important] [pre-existing] app/x.py:12 — Retry Loop Never Backs Off And Hammers The Upstream API'
  [ "$status" -eq 0 ]
  [ "$output" = "app/x.py:retry loop never backs off and hammers t" ]
}

@test "key: refuses a line with no file:line" {
  run pre_existing_key '🔴 [blocking] [pre-existing] something vague'
  [ "$status" -eq 2 ]
}

@test "tracked: true once an IDEA carries the delimited key" {
  printf '%s\n' '# IDEA-007' 'P6 pre-existing from R-1: flat prompt (pre-existing-key: a.py:prompt_injection)' > docs/ideas/IDEA-007-x.md
  run pre_existing_tracked 'a.py:prompt_injection'
  [ "$status" -eq 0 ]
}

@test "tracked: a key that is only a prefix of a tracked one is not tracked" {
  printf '%s\n' '(pre-existing-key: a.py:sql_injection)' > docs/ideas/IDEA-008-x.md
  run pre_existing_tracked 'a.py:sql'
  [ "$status" -ne 0 ]
}

@test "tracked: false with no ideas directory" {
  rm -rf docs/ideas
  run pre_existing_tracked 'a.py:prompt_injection'
  [ "$status" -ne 0 ]
}

# --- R-003 review round 1 ------------------------------------------------------

@test "lines: only a tag right after the severity tag marks a pre-existing finding" {
  printf '%s\n' \
    '🔴 [blocking] [pre-existing] a.py:3 — old' \
    '🔴 [blocking] b.py:4 — quotes the [pre-existing] marker' \
    '🟡 [important] [Pre-Existing] c.py:5 — mixed case' > "$SCRATCH/r.md"
  run pre_existing_lines "$SCRATCH/r.md"
  [ "$output" = '🔴 [blocking] [pre-existing] a.py:3 — old' ]
}

@test "strip_unverified: a file the diff created cannot hold a pre-existing defect" {
  git config user.email t@t && git config user.name t
  echo old > a.py && git add -A && git commit -q -m base && git branch -m main
  git checkout -q -b ship/R-1-x && echo new > new.py && git add -A && git commit -q -m new
  printf '%s\n' \
    '🔴 [blocking] [pre-existing] a.py:1 — exists on main' \
    '   Base evidence: a.py:1 exists unchanged on main' \
    '🔴 [blocking] [pre-existing] new.py:1 — only on this branch' \
    '🟡 [important] [pre-existing] no location given' > "$SCRATCH/r.md"
  pre_existing_strip_unverified main "$SCRATCH/r.md"
  expected=$(printf '%s\n' \
    '🔴 [blocking] [pre-existing] a.py:1 — exists on main' \
    '   Base evidence: a.py:1 exists unchanged on main' \
    '🔴 [blocking] new.py:1 — only on this branch' \
    '🟡 [important] no location given')
  [ "$(cat "$SCRATCH/r.md")" = "$expected" ]
}

@test "strip_unverified: an unresolvable base exits 2 and changes nothing" {
  printf '%s\n' '🔴 [blocking] [pre-existing] a.py:1 — x' > "$SCRATCH/r.md"
  cp "$SCRATCH/r.md" "$SCRATCH/r.before"
  run pre_existing_strip_unverified no-such-branch "$SCRATCH/r.md"
  [ "$status" -eq 2 ]
  cmp -s "$SCRATCH/r.md" "$SCRATCH/r.before"
}

@test "key: a non-ASCII description is never cut mid-character" {
  # A key ending in a lone UTF-8 lead byte can never be reproduced in an IDEA, so
  # pre_existing_tracked would never match and every ship would re-file it.
  # The C locale is where cut -c counts bytes (no LANG set, as in agent shells); a
  # UTF-8 locale would hide the defect.
  export LC_ALL=C
  run pre_existing_key '🟡 [important] [pre-existing] x.py:1 — 使用者訊息直接拼進系統提示詞沒有任何隔離或跳脫處理'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || { echo "key is not valid UTF-8"; return 1; }
}

@test "key: a CRLF report gives the same key as an LF one" {
  # A trailing \r in the key never matches the IDEA, so every ship would re-file it.
  lf=$(pre_existing_key '🟡 [important] [pre-existing] old.sh:1 — short desc')
  crlf=$(pre_existing_key "$(printf '🟡 [important] [pre-existing] old.sh:1 — short desc\r')")
  [ "$crlf" = "$lf" ]
}

@test "pre_existing_drop: removes pre-existing findings and their detail lines" {
  printf '%s\n' \
    '🟡 [important] [pre-existing] a.sh:1 — old' \
    '   Base evidence: a.sh:1 exists unchanged on main' \
    '🔴 [blocking] b.sh:2 — new' \
    '   detail of new' > "$SCRATCH/report.md"
  run pre_existing_drop "$SCRATCH/report.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *b.sh:2* ]] || return 1
  [[ "$output" == *"detail of new"* ]] || return 1
  [[ "$output" != *a.sh:1* ]] || return 1
  [[ "$output" != *"Base evidence"* ]] || return 1
}
