#!/usr/bin/env bats
# Executes the real bash blocks of command files in scratch repos, instead of
# grepping their text. The R-001 review found defects that only show when a
# block runs: an unset $WORKTREE making Phase 9 push the base branch, a mirror
# restore that blocks worktree removal, a lib not sourced by the block that
# calls it. A grep cannot see any of those.
load helpers

setup() {
  export SCRATCH="$(make_scratch command-blocks)"
  # Blocks source ~/.claude/skills/ship-workflow/lib/*.sh — point that at this tree.
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME/.claude/skills"
  ln -s "$SHIP_SKILL_ROOT" "$HOME/.claude/skills/ship-workflow"
  cd "$SCRATCH"
  git init -q --bare -b main origin.git
  git init -q -b main repo
  cd repo
  git config user.email t@t
  git config user.name t
  mkdir -p .claude docs/learnings docs/product
  echo 'merge_mode: mr' > .claude/ship-config.yml
  printf '| date | cmd | id | what | n |\n' > docs/learnings/_log.md
  echo roadmap > docs/product/ROADMAP.md
  git add -A && git commit -q -m base
  git remote add origin "$SCRATCH/origin.git"
  git push -q origin main
  export REPO="$SCRATCH/repo"
}
teardown() { rm -rf "$SCRATCH"; }

# block <command file> <start ERE> <end ERE> — the bash fences between two lines.
block() {
  S="$2" E="$3" awk '$0 ~ ENVIRON["S"] {f=1} $0 ~ ENVIRON["E"] {f=0} f' \
      "$SHIP_SKILL_ROOT/commands/$1" \
    | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f'
}

p9_log_block() { block ship-next.md '^3\. \*\*Log \+ commit\.\*\*' '^4\. \*\*Auto-mode'; }

@test "ship-next P9 (mr): an unset WORKTREE pushes nothing and writes nothing" {
  git commit -q --allow-empty -m "local-only work on main"
  p9_log_block > "$SCRATCH/p9.sh"
  [ -s "$SCRATCH/p9.sh" ]
  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
  run env WORKTREE= ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
  [ -z "$(git status --porcelain)" ] || { echo "the base checkout was written"; return 1; }
}

@test "ship-next P9 (mr): logs on the review branch and pushes only that branch" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  git commit -q --allow-empty -m "local-only work on main"
  origin_main=$(git ls-remote origin refs/heads/main | cut -f1)
  p9_log_block > "$SCRATCH/p9.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -eq 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_main" ]
  git fetch -q origin ship/R-1-x
  git log -1 --format='%(trailers:key=Ship-Log,valueonly)' FETCH_HEAD | grep -qF '| ship-next | R-1 |'
}

@test "ship-next P9 (squash): appends the row and commits it on the current branch" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  git commit -q -am "squash mode"
  p9_log_block > "$SCRATCH/p9.sh"
  run env ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "log: ship R-1" ]
  tail -1 docs/learnings/_log.md | grep -qF '| ship-next | R-1 |'
}

@test "zsh: ship-next P9 (mr) with an unset WORKTREE still pushes nothing" {
  command -v zsh >/dev/null || skip "zsh not installed"
  git commit -q --allow-empty -m "local-only work on main"
  p9_log_block > "$SCRATCH/p9.sh"
  origin_before=$(git ls-remote origin refs/heads/main | cut -f1)
  run env WORKTREE= ID=R-1 zsh "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$origin_before" ]
}

compound_step9() { block ship-compound.md '^9\. \*\*Log \+ commit' '^10\. \*\*Report'; }

@test "ship-compound step 9 (mr) refuses to run on the base branch" {
  echo "learning" > docs/learnings/R-1-x.md
  compound_step9 > "$SCRATCH/s9.sh"
  [ -s "$SCRATCH/s9.sh" ]
  head_before=$(git rev-parse HEAD)
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head_before" ]
  git diff --quiet -- docs/learnings/_log.md || { echo "_log.md was written on base"; return 1; }
}

@test "ship-compound step 9 (mr) commits only this ship's own paths and pushes its branch" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  cd "$SCRATCH/wt"
  echo "learning" > docs/learnings/R-1-x.md
  mkdir -p docs/tdd-rules.d docs/ship-pending
  echo '- A rule. ← R-1' > docs/tdd-rules.d/R-1.md
  echo '- **Lane** — a queue' > docs/ship-pending/R-1-context.md
  echo "synced from the vault" >> docs/product/ROADMAP.md
  compound_step9 > "$SCRATCH/s9.sh"
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -eq 0 ]
  files=$(git show --name-only --format= HEAD | sort | tr '\n' ' ')
  [ "$files" = "docs/learnings/R-1-x.md docs/ship-pending/R-1-context.md docs/tdd-rules.d/R-1.md " ]
  git fetch -q origin ship/R-1-x
  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD)" ]
}

@test "ship-compound step 9 (squash) stops before committing when a required path is missing" {
  echo 'merge_mode: squash' > .claude/ship-config.yml
  git commit -q -am "squash mode"
  echo "learning" > docs/learnings/R-1-x.md
  mkdir -p docs/tdd-rules.d
  echo '- A rule. ← R-1' > docs/tdd-rules.d/R-1.md
  # no docs/proposals/ in this repo
  compound_step9 > "$SCRATCH/s9.sh"
  head_before=$(git rev-parse HEAD)
  run env ID=R-1 slug=x bash "$SCRATCH/s9.sh"
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$head_before" ]
}

land_step5() { block ship-land.md '^5\. \*\*Clean up' '^6\. \*\*Report'; }

@test "ship-land step 5 removes a worktree whose vault mirror sync dirtied" {
  # sync.sh rewrites the mirror in every working tree, and since R-001 a review
  # branch no longer commits it: tracked mirror files show as modified and new
  # ones as untracked. Neither may block the cleanup.
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  echo "synced" >> "$SCRATCH/wt/docs/product/ROADMAP.md"
  mkdir -p "$SCRATCH/wt/docs/proposals"
  echo "new proposal" > "$SCRATCH/wt/docs/proposals/R-9-proposal.md"
  land_step5 > "$SCRATCH/s5.sh"
  [ -s "$SCRATCH/s5.sh" ]
  run env BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
  [ "$status" -eq 0 ]
  [ ! -d "$SCRATCH/wt" ] || { echo "worktree not removed: $output"; return 1; }
  run git rev-parse --verify -q refs/heads/ship/R-1-x
  [ "$status" -ne 0 ]
}

@test "every ship-land block that calls the lib sources it — blocks do not share a shell" {
  awk '/^[[:space:]]*```bash[[:space:]]*$/{n++; f=1; next} /^[[:space:]]*```[[:space:]]*$/{f=0} f{print n": "$0}' \
    "$SHIP_SKILL_ROOT/commands/ship-land.md" > "$SCRATCH/blocks"
  for n in $(grep -E 'land_context|land_is_merged|CONTEXT_MD_MAX' "$SCRATCH/blocks" | cut -d: -f1 | sort -u); do
    grep -E "^$n: " "$SCRATCH/blocks" | grep -qF 'lib/ship-land.sh' \
      || { echo "block $n calls the lib without sourcing it"; return 1; }
  done
}

@test "ship-land's worktree guard: allows a subdirectory of the main checkout, refuses a worktree" {
  cond=$(grep -F -- '--git-common-dir' "$SHIP_SKILL_ROOT/commands/ship-land.md" | head -1 \
         | sed -e 's/^[[:space:]]*if //' -e 's/; then[[:space:]]*$//')
  [ -n "$cond" ]
  mkdir -p deep/dir
  run bash -c "cd deep/dir && $cond"
  [ "$status" -ne 0 ] || { echo "refuses a subdirectory of the main checkout"; return 1; }
  git worktree add -q -b ship/R-2-x "$SCRATCH/wt2"
  run bash -c "cd '$SCRATCH/wt2' && $cond"
  [ "$status" -eq 0 ]
}

@test "every command block that reads MERGE_MODE resolves it — blocks do not share a shell" {
  # Phase 9 step 3 once took the squash branch in mr mode because MERGE_MODE
  # was set two blocks earlier. The ship's log row then never reached its MR.
  for f in ship-next ship-compound ship-land; do
    awk '/^[[:space:]]*```bash[[:space:]]*$/{n++; f=1; next} /^[[:space:]]*```[[:space:]]*$/{f=0} f{print n": "$0}' \
      "$SHIP_SKILL_ROOT/commands/$f.md" > "$SCRATCH/blocks"
    for n in $(grep -F '$MERGE_MODE' "$SCRATCH/blocks" | cut -d: -f1 | sort -u); do
      grep -E "^$n: " "$SCRATCH/blocks" | grep -qF 'MERGE_MODE=$(merge_mode)' \
        || { echo "$f.md block $n reads MERGE_MODE without resolving it"; return 1; }
    done
  done
}

@test "ship-next P9 step 1 (mr) keeps the worktree the review still needs" {
  git worktree add -q -b ship/R-1-x "$SCRATCH/wt"
  block ship-next.md '^1\. \*\*Remove worktree\*\*' '^2\. \*\*Delete worktree branch\*\*' > "$SCRATCH/p9s1.sh"
  [ -s "$SCRATCH/p9s1.sh" ]
  run env WORKTREE="$SCRATCH/wt" bash "$SCRATCH/p9s1.sh"
  [ -d "$SCRATCH/wt" ] || { echo "removed the worktree of an open review"; return 1; }
}

@test "ship-next P9 (mr): refuses another ship's worktree left over in WORKTREE" {
  git worktree add -q -b ship/R-2-y "$SCRATCH/wt-other"
  p9_log_block > "$SCRATCH/p9.sh"
  run env WORKTREE="$SCRATCH/wt-other" ID=R-1 bash "$SCRATCH/p9.sh"
  [ "$status" -ne 0 ]
  run git ls-remote --exit-code origin refs/heads/ship/R-2-y
  [ "$status" -ne 0 ] || { echo "R-1's row was pushed to R-2's review"; return 1; }
}

@test "ship-land step 5 never cleans the operator's own checkout" {
  # If the ship branch is checked out in the main checkout, the worktree lookup
  # resolves to the main checkout itself; cleaning there deletes the operator's
  # untracked files.
  git checkout -q -b ship/R-1-x
  mkdir -p docs/proposals
  echo "operator draft" > docs/proposals/draft.md
  land_step5 > "$SCRATCH/s5.sh"
  run env BRANCH=ship/R-1-x bash "$SCRATCH/s5.sh"
  [ -f docs/proposals/draft.md ] || { echo "cleaned the operator's checkout"; return 1; }
}

# --- R-003: the Phase 6 security pass -----------------------------------------

sec_pass_block()  { block ship-next.md '^1\.5\. \*\*Security pass' '^1\.6\. \*\*Check the security report'; }
sec_check_block() { block ship-next.md '^1\.6\. \*\*Check the security report' '^2\. \*\*Loop'; }
pre_block()       { block ship-next.md '^4\.5\. \*\*Pre-existing findings' '^## Phase 7'; }

@test "ship-next P6 security pass: refuses to run with ORIG_BRANCH unset" {
  sec_pass_block > "$SCRATCH/s15.sh"
  [ -s "$SCRATCH/s15.sh" ]
  run env ID=R-T1 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -ne 0 ]
  [ ! -e .ship/security-review-prompt.md ] || { echo "rendered without a base"; return 1; }
}

@test "ship-next P6 security pass: renders the prompt against the base branch" {
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T2 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  grep -qF 'git diff main...HEAD' .ship/security-review-prompt.md
  rm -f /tmp/ship-next-security-R-T2-1.md
}

@test "ship-next P6 security pass: switched off on the base branch, it reports no findings" {
  echo 'security_review: off' >> .claude/ship-config.yml
  git commit -q -am "review off"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T3 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  [ "$(cat /tmp/ship-next-security-R-T3-1.md)" = "No security findings." ]
  [ ! -e .ship/security-review-prompt.md ]
  rm -f /tmp/ship-next-security-R-T3-1.md
}

@test "ship-next P6 security pass: a stale skill checkout halts instead of skipping" {
  # The lib is present but its template is not — what a checkout from before
  # R-003 plus a half-synced lib looks like. Skipping would make the gate vanish.
  mkdir -p "$SCRATCH/stale/.claude/skills/ship-workflow/lib"
  cp "$SHIP_SKILL_ROOT/lib/security-review.sh" "$SCRATCH/stale/.claude/skills/ship-workflow/lib/"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env HOME="$SCRATCH/stale" ORIG_BRANCH=main ID=R-T4 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not skipping it"* ]] || return 1
  rm -f /tmp/ship-next-security-R-T4-1.md
}

@test "ship-next P6 security check: an upstream-format report is rejected, a clean one passes" {
  sec_check_block > "$SCRATCH/s16.sh"
  [ -s "$SCRATCH/s16.sh" ]
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  printf '%s\n' '# Vuln 1: XSS: `a.py:1`' '* Severity: High' > /tmp/ship-next-security-R-T5-1.md
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 3 ]
  echo "No security findings." > /tmp/ship-next-security-R-T5-1.md
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T5 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 0 ]
  rm -f /tmp/ship-next-security-R-T5-1.md
}

@test "ship-next P6 pre-existing step: already-tracked defects are not filed again" {
  mkdir -p docs/ideas
  echo 'flat prompt (pre-existing-key: p.py:prompt_injection)' > docs/ideas/IDEA-001-x.md
  printf '%s\n' '🔴 [blocking] [pre-existing] [security:prompt_injection] p.py:3 — flat prompt' > "$SCRATCH/sec.md"
  printf '%s\n' '🟡 [important] [pre-existing] q.py:9 — Retry loop never backs off' \
                 '🔴 [blocking] r.py:2 — a new finding that quotes the [pre-existing] tag' > "$SCRATCH/rev.md"
  pre_block > "$SCRATCH/s45.sh"
  [ -s "$SCRATCH/s45.sh" ]
  run env REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" bash "$SCRATCH/s45.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already tracked: p.py:prompt_injection"* ]] || return 1
  [[ "$output" == *"new pre-existing: q.py:retry loop never backs off"* ]] || return 1
  [[ "$output" != *"r.py"* ]] || { echo "a quoted tag was treated as pre-existing"; return 1; }
}

# --- R-003 review round 1 ------------------------------------------------------

@test "ship-next P6 security pass: a stale report from an earlier run is removed first" {
  # Otherwise a leftover "No security findings." passes 1.6 for a pass that never ran.
  echo "No security findings." > /tmp/ship-next-security-R-T6-1.md
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T6 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 0 ]
  [ ! -e /tmp/ship-next-security-R-T6-1.md ] || { echo "stale report survived"; return 1; }
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  sec_check_block > "$SCRATCH/s16.sh"
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T6 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 3 ]
}

@test "ship-next P6 security pass: a missing lib halts — it is not reported as switched off" {
  mkdir -p "$SCRATCH/nolib/.claude/skills/ship-workflow/lib"
  sec_pass_block > "$SCRATCH/s15.sh"
  run env HOME="$SCRATCH/nolib" ORIG_BRANCH=main ID=R-T7 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib is missing"* ]] || return 1
  [[ "$output" != *"security review: off"* ]] || { echo "reported as off"; return 1; }
  [ ! -e /tmp/ship-next-security-R-T7-1.md ]
}

@test "ship-next P6 security pass: records whether the review ran, for the landed commit" {
  sec_pass_block > "$SCRATCH/s15.sh"
  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$(cat .ship/security-review-state)" = "on" ]
  echo 'security_review: off' >> .claude/ship-config.yml
  git commit -q -am "review off"
  run env ORIG_BRANCH=main ID=R-T8 attempt=1 bash "$SCRATCH/s15.sh"
  [ "$(cat .ship/security-review-state)" = "off" ]
  rm -f /tmp/ship-next-security-R-T8-1.md
}

@test "ship-next P6 security check: a pre-existing tag the base branch cannot back is removed" {
  printf 'No findings.\n' > "$SCRATCH/rev.md"
  printf '%s\n' '🔴 [blocking] [pre-existing] [security:command_injection] brand-new.sh:1 — x' \
                '   Base evidence: brand-new.sh:1 exists unchanged on main' > /tmp/ship-next-security-R-T9-1.md
  sec_check_block > "$SCRATCH/s16.sh"
  run env ORIG_BRANCH=main REVIEW_OUT="$SCRATCH/rev.md" ID=R-T9 attempt=1 bash "$SCRATCH/s16.sh"
  [ "$status" -eq 0 ]
  head -1 /tmp/ship-next-security-R-T9-1.md | grep -qF '🔴 [blocking] [security:command_injection] brand-new.sh:1' || return 1
  rm -f /tmp/ship-next-security-R-T9-1.md
}

# --- R-003 review round 2 ------------------------------------------------------

major_block()      { block ship-next.md '^4\. \*\*Major findings handling' '^4\.5\. \*\*Pre-existing findings'; }
p9_capture_block() { block ship-next.md '^0\. \*\*Capture anything inside the worktree' '^1\. \*\*Remove worktree'; }

@test "ship-next P6 step 4: files every major from both reports, never a pre-existing finding's detail line" {
  printf '%s\n' '🟡 [important] [pre-existing] old.sh:1 — old defect' \
                '   Base evidence: old.sh:1 exists unchanged on main' \
                '   Fix: later' \
                '🟡 [important] a.sh:2 — first new major' > "$SCRATCH/rev.md"
  printf '%s\n' '🟡 [important] [security:xss] b.sh:3 — second new major' \
                '   Exploit scenario: y' > "$SCRATCH/sec.md"
  # /ship-idea is a slash command, not a program: record what the block would file.
  { echo 'ship_idea() { printf "%s\n" "$2" >> "$SCRATCH/ideas.txt"; }'
    major_block | sed 's#/ship-idea #ship_idea #'; } > "$SCRATCH/s4.sh"
  run env AUTO=1 MAJOR_COUNT=2 REVIEW_OUT="$SCRATCH/rev.md" SEC_OUT="$SCRATCH/sec.md" \
      WORKTREE="$REPO" ID=R-T10 bash "$SCRATCH/s4.sh"
  grep -qF 'a.sh:2 — first new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
  grep -qF 'b.sh:3 — second new major' "$SCRATCH/ideas.txt" || { cat "$SCRATCH/ideas.txt"; return 1; }
  if grep -qF 'Base evidence' "$SCRATCH/ideas.txt"; then echo "filed a detail line as a major"; return 1; fi
}

@test "ship-next P9: the security-review state is captured before the worktree is removed" {
  mkdir -p "$SCRATCH/wt/.ship" && echo off > "$SCRATCH/wt/.ship/security-review-state"
  p9_capture_block > "$SCRATCH/p90.sh"
  run env WORKTREE="$SCRATCH/wt" ID=R-T11 bash "$SCRATCH/p90.sh"
  [ "$status" -eq 0 ]
  rm -rf "$SCRATCH/wt"   # step 1 removes the worktree
  # Step 4 is its own block, so its own shell: a variable set in step 0 is gone.
  step4=$(awk '/^## Phase 9/{p=1} p && /^4\. \*\*Auto-mode success notification/{f=1} f && /^## /{exit} f' \
          "$SHIP_SKILL_ROOT/commands/ship-next.md")
  line=$(echo "$step4" | grep -F '• security review:' | sed 's/^[[:space:]]*//')
  [ -n "$line" ] || return 1
  printf 'echo "%s"\n' "$line" > "$SCRATCH/p94.sh"
  run env ID=R-T11 ORIG_BRANCH=main bash "$SCRATCH/p94.sh"
  rm -f /tmp/ship-R-T11-security-review-state
  [[ "$output" == *"off (ship-config on main)"* ]]
}
