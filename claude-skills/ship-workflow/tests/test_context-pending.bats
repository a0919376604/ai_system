#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch context-pending)"
  mkdir -p "$SCRATCH/repo"
  cd "$SCRATCH/repo"
  git init -q
  source "$SHIP_LIB/context-md.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "context_pending_add: queues the entry under the ship's own path and nothing else" {
  context_pending_add R-7 "- **Lane** — a queue of tickets"
  [ "$(cat docs/ship-pending/R-7-context.md)" = "- **Lane** — a queue of tickets" ]
  [ ! -e CONTEXT.md ] || { echo "CONTEXT.md was written"; return 1; }
}

@test "context_pending_add: refuses a malformed entry" {
  run context_pending_add R-7 "Lane: a queue"
  [ "$status" -eq 2 ]
  [ ! -e docs/ship-pending/R-7-context.md ]
}

@test "context_pending_add: refuses a missing R-NNN" {
  run context_pending_add "" "- **Lane** — x"
  [ "$status" -eq 2 ]
}

@test "context_pending_add: refuses a later line that apply would drop" {
  # An unindented or blank later line is not part of any entry, so apply would
  # silently lose it after the queue had been reviewed and merged.
  run context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' 'not indented')"
  [ "$status" -eq 2 ]
  run context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' '' '  after a blank')"
  [ "$status" -eq 2 ]
  [ ! -e docs/ship-pending/R-7-context.md ]
}

@test "context_pending_add: a trailing newline is not a blank line" {
  # e.g. a multi-line quoted argument whose closing quote sits on its own line
  context_pending_add R-7 "- **Lane** — a queue
"
  [ "$(cat docs/ship-pending/R-7-context.md)" = "- **Lane** — a queue" ]
}

@test "context_pending_add: accepts continuation lines and several entries at once" {
  context_pending_add R-7 "$(printf '%s\n' '- **Lane** — first' '  continued' '- **Seat** — second')"
  [ "$(wc -l < docs/ship-pending/R-7-context.md | tr -d ' ')" -eq 3 ]
}

@test "context_pending_apply: replaces a same-term entry with its continuation lines, appends a new term" {
  printf '%s\n' '# Context' '' '- **Foo** — old text' '  old continuation' '- **Keep** — untouched' > CONTEXT.md
  context_pending_add R-7 "- **Foo** — new text"
  context_pending_add R-7 "- **Bar** — brand new"
  run context_pending_apply R-7
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
  expected=$(printf '%s\n' '# Context' '' '- **Foo** — new text' '- **Keep** — untouched' '- **Bar** — brand new')
  [ "$(cat CONTEXT.md)" = "$expected" ]
  [ ! -e docs/ship-pending/R-7-context.md ] || { echo "pending file survived"; return 1; }
}

@test "context_pending_apply: a pending entry keeps its own continuation lines" {
  printf '%s\n' '- **Foo** — old' > CONTEXT.md
  printf '%s\n' '- **Foo** — new' '  second line' > "$BATS_TEST_TMPDIR/entry"
  context_pending_add R-7 "$(cat "$BATS_TEST_TMPDIR/entry")"
  context_pending_apply R-7 >/dev/null
  [ "$(cat CONTEXT.md)" = "$(cat "$BATS_TEST_TMPDIR/entry")" ]
}

@test "context_pending_apply: every term ends up exactly once" {
  printf '%s\n' '- **Foo** — a' '- **Foo** — duplicate already in file' > CONTEXT.md
  context_pending_add R-7 "- **Foo** — first queued"
  context_pending_add R-7 "- **Foo** — last queued wins"
  context_pending_apply R-7 >/dev/null
  [ "$(grep -c '^- \*\*Foo\*\*' CONTEXT.md)" -eq 1 ]
  grep -qxF -- '- **Foo** — last queued wins' CONTEXT.md
}

@test "context_pending_apply: terms with regex characters match literally" {
  printf '%s\n' '- **C++ (v2)** — old' '- **C** — unrelated' > CONTEXT.md
  context_pending_add R-7 "- **C++ (v2)** — new"
  context_pending_apply R-7 >/dev/null
  expected=$(printf '%s\n' '- **C++ (v2)** — new' '- **C** — unrelated')
  [ "$(cat CONTEXT.md)" = "$expected" ]
}

@test "context_pending_apply: creates CONTEXT.md when the repo has none" {
  context_pending_add R-7 "- **Lane** — a queue"
  context_pending_apply R-7 >/dev/null
  [ "$(cat CONTEXT.md)" = "- **Lane** — a queue" ]
}

@test "context_pending_apply: no pending file is a silent no-op" {
  printf '%s\n' '- **Foo** — a' > CONTEXT.md
  run context_pending_apply R-7
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat CONTEXT.md)" = "- **Foo** — a" ]
}

@test "zsh: apply produces the same CONTEXT.md as bash" {
  command -v zsh >/dev/null || skip "zsh not installed"
  printf '%s\n' '- **Foo** — old' '  cont' '- **Keep** — k' > CONTEXT.md
  cp CONTEXT.md "$BATS_TEST_TMPDIR/ctx.orig"
  context_pending_add R-7 "- **Foo** — new"
  cp docs/ship-pending/R-7-context.md "$BATS_TEST_TMPDIR/pending"
  context_pending_apply R-7 >/dev/null
  cp CONTEXT.md "$BATS_TEST_TMPDIR/ctx.bash"
  cp "$BATS_TEST_TMPDIR/ctx.orig" CONTEXT.md
  cp "$BATS_TEST_TMPDIR/pending" docs/ship-pending/R-7-context.md
  run zsh -c "source '$SHIP_LIB/context-md.sh'; context_pending_apply R-7"
  [ "$output" = "1" ]
  cmp -s CONTEXT.md "$BATS_TEST_TMPDIR/ctx.bash"
}
