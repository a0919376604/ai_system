#!/usr/bin/env bats
load helpers

setup() {
  export SCRATCH="$(make_scratch context-md)"
  cd "$SCRATCH"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  source "$SHIP_LIB/context-md.sh"
}

teardown() {
  rm -rf "$SCRATCH"
}

@test "context_md_path: echoes repo-root CONTEXT.md when present" {
  echo "x" > CONTEXT.md
  run context_md_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"/CONTEXT.md" ]]
}

@test "context_md_path: silent when file absent" {
  run context_md_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context_md_path: silent outside a git repo" {
  mkdir -p "$SCRATCH/notrepo"
  cd "$SCRATCH/notrepo"
  run context_md_path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "context_md_entry_count: counts one bullet per entry" {
  cat > CONTEXT.md <<'EOF'
# Context

- **adapter** — compiles commands/ per platform.
  Continuation line that must not be counted.
- **seam** — a declared interface boundary.
EOF
  run context_md_entry_count
  [ "$output" = "2" ]
}

@test "context_md_entry_count: zero on a file with no bullets" {
  echo "# Context" > CONTEXT.md
  run context_md_entry_count
  [ "$output" = "0" ]
}

@test "context_md_entry_count: zero when file absent" {
  run context_md_entry_count
  [ "$output" = "0" ]
}

@test "context_md_line_count: zero when file absent" {
  run context_md_line_count
  [ "$output" = "0" ]
}

@test "context_md_over_cap: false for a small file" {
  printf -- "- **a** — x\n" > CONTEXT.md
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "context_md_over_cap: true above 200 lines" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 201 ]; do echo "filler" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 0 ]
}

@test "context_md_over_cap: true above 60 entries" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 61 ]; do printf -- "- **t%s** — d\n" "$i" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 0 ]
}

@test "context_md_over_cap: false at exactly 200 lines and 60 entries" {
  : > CONTEXT.md
  i=0; while [ "$i" -lt 60 ]; do printf -- "- **t%s** — d\n" "$i" >> CONTEXT.md; i=$((i+1)); done
  i=0; while [ "$i" -lt 140 ]; do echo "filler" >> CONTEXT.md; i=$((i+1)); done
  run context_md_over_cap
  [ "$status" -eq 1 ]
}

@test "context_md_orphan_terms: lists terms with no hit outside CONTEXT.md" {
  mkdir -p src
  echo "def adapter(): pass" > src/a.py
  git add -A && git -c user.email=t@t -c user.name=t commit -q -m src
  cat > CONTEXT.md <<'EOF'
- **adapter** — present in code.
- **ghosted** — nowhere in code.
EOF
  run context_md_orphan_terms
  [[ "$output" == *"ghosted"* ]] || return 1
  [[ "$output" != *"adapter"* ]]
}
