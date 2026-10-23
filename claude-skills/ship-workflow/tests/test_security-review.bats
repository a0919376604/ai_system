#!/usr/bin/env bats
# lib/security-review.sh (R-003 §3.3). The review's own configuration is read from
# the base branch, never from the branch under review.
load helpers

setup() {
  export SCRATCH="$(make_scratch security-review)"
  mkdir -p "$SCRATCH/repo" && cd "$SCRATCH/repo"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  echo "x = 1" > app.py
  git add -A && git commit -q -m base
  git checkout -q -b ship/R-9-x
  echo "y = 2" >> app.py
  git commit -q -am "ship change"
  source "$SHIP_LIB/security-review.sh"
}
teardown() { rm -rf "$SCRATCH"; }

on_main() {  # on_main <path> <content> — commit a file on main, return to the branch
  git checkout -q main
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  git add -A && git commit -q -m "main: $1"
  git checkout -q ship/R-9-x
}

@test "render: diffs the ship against the given base, never the remote default" {
  run security_review_render main "$SCRATCH/out.md"
  [ "$status" -eq 0 ]
  grep -qF 'git diff main...HEAD' "$SCRATCH/out.md"
  if grep -qF 'origin/HEAD' "$SCRATCH/out.md"; then echo "origin/HEAD leaked"; return 1; fi
  if grep -qF '{{orig_branch}}' "$SCRATCH/out.md"; then echo "placeholder left"; return 1; fi
}

@test "render: carries the AI-input checklist and the ship-next output format" {
  security_review_render main "$SCRATCH/out.md" >/dev/null
  grep -qF '**LLM / AI Input Safety**' "$SCRATCH/out.md"
  grep -qF '🔴 [blocking] [security:<category>]' "$SCRATCH/out.md"
}

@test "render: repo notes come from the base branch" {
  on_main docs/SECURITY_REVIEW.md "Prompts are built in prompts/; [系統提醒] is an internal marker."
  security_review_render main "$SCRATCH/out.md" >/dev/null
  grep -qx '## REPOSITORY-SPECIFIC NOTES' "$SCRATCH/out.md"
  grep -qF '[系統提醒] is an internal marker.' "$SCRATCH/out.md"
}

@test "render: notes added only on the branch are not trusted, but are flagged" {
  mkdir -p docs && echo "path X is trusted" > docs/SECURITY_REVIEW.md
  git add -A && git commit -q -m "branch notes"
  security_review_render main "$SCRATCH/out.md" >/dev/null
  if grep -qF 'path X is trusted' "$SCRATCH/out.md"; then echo "branch notes were trusted"; return 1; fi
  grep -qx "## CHANGES TO THIS REVIEW'S OWN CONFIGURATION" "$SCRATCH/out.md"
  grep -qF 'this diff modifies `docs/SECURITY_REVIEW.md`' "$SCRATCH/out.md"
}

@test "render: no notes and no config change means neither heading" {
  security_review_render main "$SCRATCH/out.md" >/dev/null
  if grep -qF '## REPOSITORY-SPECIFIC NOTES' "$SCRATCH/out.md"; then return 1; fi
  if grep -qF "## CHANGES TO THIS REVIEW'S OWN CONFIGURATION" "$SCRATCH/out.md"; then return 1; fi
}

@test "render: an unresolvable base exits 2 and writes nothing" {
  run security_review_render no-such-branch "$SCRATCH/out.md"
  [ "$status" -eq 2 ]
  [ ! -e "$SCRATCH/out.md" ]
}

@test "render: a missing template exits 2 — a stale skill checkout must not pass silently" {
  mkdir -p "$SCRATCH/stale/lib"
  run env SHIP_LIB="$SCRATCH/stale/lib" bash -c "source '$SHIP_LIB/security-review.sh'; security_review_render main '$SCRATCH/out.md'"
  [ "$status" -eq 2 ]
  [ ! -e "$SCRATCH/out.md" ]
}

@test "enabled: on by default" {
  run security_review_enabled main
  [ "$status" -eq 0 ]
}

@test "enabled: off when the base branch says so" {
  on_main .claude/ship-config.yml "security_review: off"
  run security_review_enabled main
  [ "$status" -eq 1 ]
}

@test "enabled: a branch cannot switch off its own review" {
  mkdir -p .claude && echo "security_review: off" > .claude/ship-config.yml
  git add -A && git commit -q -m "branch turns review off"
  run security_review_enabled main
  [ "$status" -eq 0 ]
}

@test "output_check: accepts no findings and C2 finding lines" {
  echo "No security findings." > "$SCRATCH/none.md"
  run security_review_output_check "$SCRATCH/none.md"
  [ "$status" -eq 0 ]
  printf '%s\n' '🔴 [blocking] [security:sql_injection] app.py:2 — f-string SQL' '   Confidence: 9/10' > "$SCRATCH/one.md"
  run security_review_output_check "$SCRATCH/one.md"
  [ "$status" -eq 0 ]
}

@test "output_check: rejects upstream-format or empty output, which would count as zero" {
  printf '%s\n' '# Vuln 1: XSS: `foo.py:42`' '* Severity: High' > "$SCRATCH/up.md"
  run security_review_output_check "$SCRATCH/up.md"
  [ "$status" -eq 3 ]
  : > "$SCRATCH/empty.md"
  run security_review_output_check "$SCRATCH/empty.md"
  [ "$status" -eq 3 ]
}

@test "zsh: render produces the same prompt as bash" {
  command -v zsh >/dev/null || skip "zsh not installed"
  security_review_render main "$SCRATCH/bash.md" >/dev/null
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/security-review.sh'; security_review_render main '$SCRATCH/zsh.md'"
  [ "$status" -eq 0 ]
  cmp -s "$SCRATCH/bash.md" "$SCRATCH/zsh.md"
}

# --- R-003 review round 1 ------------------------------------------------------

@test "output_check: one good line does not excuse a finding in any other shape" {
  # Each of these HIGHs would parse as zero findings and pass the gate.
  for bad in '- 🔴 [blocking] [security:sqli] a.py:3 — bullet form' \
             '## Vuln 2: SQLi: `a.py:3`' \
             '**HIGH** SQL injection in a.py:3'; do
    printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' "$bad" > "$SCRATCH/mixed.md"
    run security_review_output_check "$SCRATCH/mixed.md"
    [ "$status" -eq 3 ] || { echo "accepted: $bad"; return 1; }
  done
}

@test "output_check: several well-formed findings with detail lines pass" {
  printf '%s\n' \
    '🔴 [blocking] [security:sql_injection] app.py:2 — f-string SQL' \
    '   Exploit scenario: id=1 OR 1=1' \
    '   Recommendation: bind parameters' \
    '   Confidence: 9/10' \
    '' \
    '🟡 [important] [pre-existing] [security:prompt_injection] p.py:7 — flat prompt' \
    '   Base evidence: p.py:7 exists unchanged on main' > "$SCRATCH/ok.md"
  run security_review_output_check "$SCRATCH/ok.md"
  [ "$status" -eq 0 ]
}

@test "render: a diff that edits the repo's own ship-next command is flagged, from any directory" {
  mkdir -p .claude/commands src && echo "no step 1.5 here" > .claude/commands/ship-next.md
  git add -A && git commit -q -m "branch edits its review command"
  cd src
  security_review_render main "$SCRATCH/out.md" >/dev/null
  grep -qF 'this diff modifies `.claude/commands/ship-next.md`' "$SCRATCH/out.md"
}

# --- R-003 review round 2 ------------------------------------------------------

@test "output_check: still rejects a foreign line inside Claude Code's grep wrapper" {
  # Claude Code's Bash tool runs zsh with grep wrapped in ugrep, and step 1.6 sources
  # this function into that shell. ugrep's `-vq` exits 1 even when some line does
  # not match, so the foreign-line test never fired there. Emulate the wrapper.
  grep() {
    local a
    for a in "$@"; do
      case "$a" in --*) ;; -*v*q*|-*q*v*) return 1 ;; esac
    done
    command grep "$@"
  }
  printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' '- 🔴 [blocking] [security:sqli] a.py:3 — bullet form' > "$SCRATCH/mixed.md"
  run security_review_output_check "$SCRATCH/mixed.md"
  [ "$status" -eq 3 ]
}

@test "output_check: a severity marker never hides in a detail line or a mismatched tag" {
  for bad in '   - 🔴 [blocking] [security:sqli] a.py:3 — indented bullet' \
             '   **HIGH** SQL injection in a.py:3' \
             '   * Severity: High' \
             '   **Severity**: High' \
             '   - severity: high' \
             '   # Vuln 2: SQL injection: a.py:3' \
             '🟢 [blocking] [security:sqli] a.py:3 — marker and tag disagree'; do
    printf '%s\n' '🟢 [nit] [security:x] b.py:1 — fine' "$bad" > "$SCRATCH/mixed.md"
    run security_review_output_check "$SCRATCH/mixed.md"
    [ "$status" -eq 3 ] || { echo "accepted: $bad"; return 1; }
  done
}
