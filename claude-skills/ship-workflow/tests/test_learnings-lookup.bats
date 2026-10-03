#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch learnings-lookup)"
  mkdir -p "$SCRATCH/repo/docs/learnings"; cd "$SCRATCH/repo"
  git init -q
  # Filenames carry the slug, exactly like the real corpus.
  printf 'body about solve_rate here\n' > docs/learnings/R-001-unify-solve-rate.md
  printf 'body about buckets\n'         > docs/learnings/R-002-bucket-cutover.md
  printf 'solve_rate and bucket\n'      > docs/learnings/R-003-solve-rate-bucket.md
  printf '| date | x |\n' > docs/learnings/_log.md
  source "$SHIP_LIB/learnings-lookup.sh"
}
teardown() { rm -rf "$SCRATCH"; }

@test "learnings_match: finds files containing the term" {
  run learnings_match solve-rate
  [ "$status" -eq 0 ]
  [[ "$output" == *R-001-unify-solve-rate.md* ]] || return 1
  [[ "$output" == *R-003-solve-rate-bucket.md* ]] || return 1
  [[ "$output" != *R-002-bucket-cutover.md* ]] || return 1
}

@test "learnings_match: never returns the log file" {
  # _log.md is an append-only ledger, not a learning. It matches almost
  # anything and would crowd out the real hits.
  run learnings_match log
  [[ "$output" != *_log.md* ]] || { echo "the ledger came back as a learning"; return 1; }
}

@test "learnings_match: several terms are unioned and deduped" {
  run learnings_match solve-rate bucket
  [ "$(echo "$output" | grep -c .)" -eq 3 ]
  [ "$(echo "$output" | grep -c 'R-003-solve-rate-bucket.md')" -eq 1 ]
}

@test "learnings_match: a term starting with a dash is not read as an option" {
  # This repo has been bitten by exactly this: grep -F '- **term**' exits 2.
  run learnings_match -- -rf
  [ "$status" -eq 0 ]
}

@test "learnings_match: regex metacharacters are literal" {
  printf 'x\n' > docs/learnings/R-004.1-dots.md
  run learnings_match 'R-004.1'
  [[ "$output" == *R-004.1-dots.md* ]] || return 1
  run learnings_match 'RX004X1'
  [ -z "$output" ]
}

@test "learnings_match: no matches is empty and still exit 0" {
  run learnings_match zzzznope
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "learnings_match: silent no-op when the repo has no learnings dir" {
  rm -rf docs/learnings
  run learnings_match solve_rate
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}



@test "learnings_match: matches the FILENAME, not the body" {
  # Measured on 67 real learnings: body grep for the slug words of
  # `unify-ai-resolve-rate` returned 48 of 67, because "resolve" and "rate"
  # appear in almost every 147-line narrative. Filenames returned 4.
  printf '# x\n\nthis body mentions solve_rate many times\n' > docs/learnings/R-009-unrelated-name.md
  run learnings_match unrelated
  [[ "$output" == *R-009-unrelated-name.md* ]] || return 1
  # The body word must NOT pull it in via learnings_match.
  run learnings_match solve_rate
  [[ "$output" != *R-009-unrelated-name.md* ]] || { echo "body matching is back"; return 1; }
}

@test "learnings_grep_body: identifier-like terms only" {
  printf '# y\n\ncontains solve_rate here\n' > docs/learnings/R-010-z.md
  run learnings_grep_body solve_rate
  [[ "$output" == *R-010-z.md* ]] || return 1
  # A bare English word is refused: it is what made body grep useless.
  run learnings_grep_body rate
  [ -z "$output" ]
}

@test "learnings_grep_body: never returns the log" {
  printf 'solve_rate\n' >> docs/learnings/_log.md
  run learnings_grep_body solve_rate
  [[ "$output" != *_log.md* ]] || return 1
}

@test "bash and zsh agree on multi-term lookup" {
  # Phase 3 passes an unquoted $LEARN_TERMS; zsh does not word-split unquoted
  # parameters the way bash does, so this is worth pinning rather than assuming.
  for sh in bash zsh; do
    command -v "$sh" >/dev/null || continue
    "$sh" -c "cd '$SCRATCH/repo'; source '$SHIP_LIB/learnings-lookup.sh'
      T=\$(printf 'solve-rate\nbucket\n')
      learnings_match \$T" > "$SCRATCH/$sh.out" 2>&1
  done
  if [ -f "$SCRATCH/zsh.out" ]; then
    diff "$SCRATCH/bash.out" "$SCRATCH/zsh.out" || { echo "shells diverge"; return 1; }
  fi
  [ "$(grep -c . "$SCRATCH/bash.out")" -eq 3 ]
}
