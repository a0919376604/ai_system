#!/usr/bin/env bats
# The vendored security-review prompt (R-003 §3.2): upstream's false-positive
# discipline must survive vendoring intact. Each upstream hard exclusion and
# precedent is pinned by a key phrase, so a careless edit cannot drop one.
load helpers

setup() {
  export T="$SHIP_SKILL_ROOT/templates/security-review/PROMPT.md"
  export L="$SHIP_SKILL_ROOT/templates/security-review/LICENSE.upstream"
}

has() { grep -qF -- "$1" "$T" || { echo "missing: $1"; return 1; }; }

@test "template names its upstream source, commit and license" {
  has 'anthropics/claude-code-security-review @ 0c6a49f1fa56'
  has 'Copyright (c) 2025 Anthropic'
  grep -qx 'MIT License' "$L"
  grep -qF 'Copyright (c) 2025 Anthropic' "$L"
}

@test "template keeps upstream hard exclusions 1-13 and 15-17" {
  for phrase in \
    'Denial of Service (DOS) vulnerabilities or resource exhaustion attacks.' \
    'Secrets or credentials stored on disk if they are otherwise secured.' \
    'Rate limiting concerns or service overload scenarios.' \
    'Memory consumption or CPU exhaustion issues.' \
    'Lack of input validation on non-security-critical fields without proven security impact.' \
    'Input sanitization concerns for GitHub Action workflows' \
    'A lack of hardening measures.' \
    'Race conditions or timing attacks that are theoretical' \
    'Vulnerabilities related to outdated third-party libraries.' \
    'Do not report memory safety issues in rust' \
    'Files that are only unit tests or only used as part of running tests.' \
    'Log spoofing concerns.' \
    'SSRF vulnerabilities that only control the path.' \
    'Regex injection.' \
    'Regex DOS concerns.' \
    'Insecure documentation.' \
    'A lack of audit logs is not a vulnerability.'; do
    has "$phrase" || return 1
  done
}

@test "template keeps all 12 upstream precedents and the confidence cutoff" {
  for phrase in \
    'Logging high value secrets in plaintext is a vulnerability.' \
    'UUIDs can be assumed to be unguessable' \
    'Environment variables and CLI flags are trusted values.' \
    'Resource management issues such as memory or file descriptor leaks are not valid.' \
    'tabnabbing, XS-Leaks, prototype pollution, and open redirects' \
    'React and Angular are generally secure against XSS.' \
    'Most vulnerabilities in github action workflows are not exploitable in practice.' \
    'A lack of permission checking or authentication in client-side JS/TS code is not a vulnerability.' \
    'Only include MEDIUM findings if they are obvious and concrete issues.' \
    'Most vulnerabilities in ipython notebooks' \
    'Logging non-PII data is not a vulnerability' \
    'Command injection vulnerabilities in shell scripts are generally not exploitable in practice' \
    'Filter out any vulnerabilities where the sub-task reported a confidence less than 8.'; do
    has "$phrase" || return 1
  done
}

@test "template drops exclusion 14 and adds the LLM / AI input safety checklist" {
  if grep -qF 'Including user-controlled content in AI system prompts is not a vulnerability.' "$T"; then
    echo "exclusion 14 is still there"; return 1
  fi
  has '**LLM / AI Input Safety**'
  has 'Stored / indirect prompt injection'
  has 'stored injection that reaches other users → HIGH'
}

@test "template diffs the ship, not the remote default branch" {
  has 'git diff {{orig_branch}}...HEAD'
  if grep -qF 'origin/HEAD' "$T"; then echo "still diffs origin/HEAD"; return 1; fi
  if grep -q '^allowed-tools:' "$T"; then echo "slash-command frontmatter left in"; return 1; fi
}

@test "template output format is the one code-review-parse.sh counts" {
  has '🔴 [blocking] [security:<category>] <file>:<line> — <one-line description>'
  has 'No security findings.'
  has '[pre-existing]'
  if grep -qF '# Vuln 1:' "$T"; then echo "upstream output format left in"; return 1; fi
}

@test "the false-positive filters also see the AI-input category" {
  # Without it a filter could drop a prompt-injection finding under exclusion 7
  # ("a lack of hardening measures") — the operator's main concern for R-003.
  has 'Also include the **LLM / AI Input Safety** category above and its severity guidance line'
}

@test "the header lists every change made to upstream text" {
  has 'C5  the false-positive filter sub-tasks also receive the LLM / AI Input Safety category'
  has 'START ANALYSIS notes that a sub-task is a separate agent you dispatch'
}

@test "the prompt asks for nothing but findings, so a normal report passes the format check" {
  # The check rejects every line that is not a finding, a detail line or blank. A
  # prompt that allows a title or a summary would stop Phase 6 on a good report.
  has 'nothing but finding lines, their indented detail lines and blank lines'
  has 'A detail line never states a severity'
  source "$SHIP_LIB/security-review.sh"
  example=$(awk '/^REQUIRED OUTPUT FORMAT:/{f=1} f&&/^```$/{n++; next} f&&n==1' "$T")
  [ -n "$example" ] || { echo "no example block"; return 1; }
  printf '%s\n' "$example" > "$BATS_TEST_TMPDIR/example.md"
  run security_review_output_check "$BATS_TEST_TMPDIR/example.md"
  [ "$status" -eq 0 ] || { echo "the prompt's own example fails the check"; return 1; }
}
