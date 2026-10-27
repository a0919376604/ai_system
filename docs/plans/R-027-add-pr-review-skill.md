# R-027 `pr-review` skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** add a fourth skill, `claude-skills/pr-review/`.
- Ship-next Phase 6 steps 1 and 1.3–1.6 move into it verbatim, plus a new step 1.1 for the
  code-review call.
- It gains a PR mode that reviews someone else's GitHub PR, GitLab MR or the current branch
  with the same four axes.

**Architecture:**
- **`pr-review/SKILL.md`** holds § Ship mode (moved text) and § PR mode (new instructions).
- **`pr-review/lib/pr-review.sh`** holds the PR-mode glue: `pr_target`, `pr_checkout`,
  `pr_spec`, `pr_report`, `pr_comment`.
- **`ship-workflow/lib/ship-next.sh`:** `sn_spec_review_render` gains two optional
  arguments.
- **Everything else** stays in `ship-workflow/lib/`.

**Tech Stack:** bash and zsh, git, jq (`/usr/bin/jq`), gh 2.94, glab 1.99, bats.

**Spec:** `docs/specs/R-027-add-pr-review-skill.md`. Read §3 and the Seams first. AC-10 (a
real line-oa MR) is not a task here; the ship's operator runs it after this plan.

## Global Constraints
- **Moved text is byte-for-byte.** The source is `claude-skills/ship-workflow/commands/ship-next.md`
  lines **402–463**: from `1. **Verify code-review-skill installed:**` up to, not including,
  `2. **Loop:**`. Move it with `sed -n '402,463p'`, never retype it.
  - Check first that line 402 starts `1. **Verify code-review-skill installed` and line 464
    starts `2. **Loop:**`.
  - If they do not, locate the same range by those two headings inside `## Phase 6`.
- **`pr-review.sh` conventions:**
  - It finds the ship-workflow lib through `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}`.
  - No arrays, no `BASH_SOURCE`.
  - Subshell functions `name() ( … )` wherever a function `cd`s or sets traps.
  - Every function behaves the same sourced under bash and zsh.
- **JSON** is parsed with `jq`. For github, call `gh … --json <fields>` and pipe the output to
  `jq`, so a test stub only has to print JSON.
- **`pr_target` prints** one `KEY=value` line per variable, values quoted with `printf %q`,
  for `eval`. The keys: `PR_PROVIDER PR_NUMBER PR_BASE PR_BASE_SHA PR_HEAD PR_TITLE PR_URL PR_LABEL`.
- **Tests** live in `claude-skills/ship-workflow/tests/test_pr-review.bats` (`load helpers`).
  - The lib path is `"$SHIP_SKILL_ROOT/../pr-review/lib/pr-review.sh"`.
  - Run with `cd claude-skills/ship-workflow && bats tests/<file>.bats`.
  - The known failure to ignore is `cwd-guard: exits 0 when not in a git repo at all`.
- **No network in tests.** `gh` and `glab` are stubs on `PATH`; remotes are local bare repos.

## Review Focus
1. **The moved text really is unchanged.** The Task 2 verification `diff`s the moved range
   against `main`'s lines 402–463, excluding the new 1.1 step.
2. **ship-next's per-attempt order is unchanged.** The step 2 loop's non-comment lines are
   byte-identical to `main`, checked in Task 2.
3. **zsh.** `pr_target` and `pr_report` give the same output sourced in zsh. Test in Tasks 3
   and 5.
4. **Paths and titles with spaces, quotes or CJK** survive `pr_target`'s `printf %q` and
   `eval`. Test in Task 3, with title `修「登入」 bug's fix`.
5. **A merged PR still has a diff.** `pr_checkout` plus `git diff "$PR_BASE_SHA"...HEAD` is
   non-empty even after the head has been merged into `origin/main`. Test in Task 4.

---

### Task 1: `sn_spec_review_render` optional arguments

**Files:** Modify `claude-skills/ship-workflow/lib/ship-next.sh` (`sn_spec_review_render`);
Test `claude-skills/ship-workflow/tests/test_ship-next-spec-review.bats`.

**Interfaces:** `sn_spec_review_render <wt> [<spec-path> <base>]`. With both optional
arguments:
- `spec` is `<spec-path>`;
- the first prompt line reads `Read <spec-path> in full. Read the diff with git diff <base>...HEAD.`;
- the existence check uses `<spec-path>`.

Without them, it behaves as today. The heredoc body is unchanged.

- [x] **Step 1: Failing test** (AC-6):

```bash
@test "sn_spec_review_render: optional spec path and base override the state (R-027 AC-6)" {
  # Set up a worktree dir with .ship/state.env: ID=R-9 SLUG=x ORIG_BRANCH=main, and docs/specs/R-9-x.md
  sn_spec_review_render "$WT"
  head -1 "$WT/.ship/spec-review-prompt.md" | grep -qF 'Read docs/specs/R-9-x.md in full. Read the diff with git diff main...HEAD.'
  cp "$WT/.ship/spec-review-prompt.md" "$SCRATCH/default.md"
  printf 'desc\n' > "$SCRATCH/spec one.md"
  sn_spec_review_render "$WT" "$SCRATCH/spec one.md" origin/dev
  head -1 "$WT/.ship/spec-review-prompt.md" | grep -qF "Read $SCRATCH/spec one.md in full. Read the diff with git diff origin/dev...HEAD."
  diff <(tail -n +2 "$SCRATCH/default.md") <(tail -n +2 "$WT/.ship/spec-review-prompt.md")
  run sn_spec_review_render "$WT" "$SCRATCH/missing.md" origin/dev
  [ "$status" -ne 0 ]
}
```

  Build `$WT` the way the file's existing tests do, reusing its setup.
- [x] **Step 2:** Run it and expect FAIL.
- [x] **Step 3:** Implement: `local spec="${2:-$1/docs/specs/${ID}-${SLUG}.md}" base="${3:-$ORIG_BRANCH}"`,
  then use `$spec` and `$base` in the first `printf`.
- [x] **Step 4:** `bats tests/test_ship-next-spec-review.bats` and expect all PASS.
- [x] **Step 5:** Commit `feat(R-027): sn_spec_review_render takes an optional spec path and base`.

### Task 2: Move the ship-mode steps into `pr-review/SKILL.md`

**Files:**
- Create: `claude-skills/pr-review/SKILL.md`.
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`, Phase 6.
- Modify the tests named below: change the source path per extraction only.

- [x] **Step 1: Create `pr-review/SKILL.md`** in this order:
  1. Frontmatter:
     - `name: pr-review`;
     - `description:` "Review a pull/merge request or branch with four axes — code standards (code-review-skill), Spec, codex cross-model, security pass — into one severity report. PR mode: /pr-review [<PR/MR number or URL>] [--comment] [--keep] [--no-codex] for GitHub (gh) or GitLab (glab). Ship mode: ship-next Phase 6 runs its steps each review attempt.";
     - `argument-hint: "[<PR/MR number or URL>] [--comment] [--keep] [--no-codex]"`.
  2. `# /pr-review`, plus three lines: the two modes, and that the libs live in
     ship-workflow.
  3. `## Ship mode`, plus one paragraph: "ship-next Phase 6 step 2 runs these each attempt:
     1.1, 1.3 and 1.4 every attempt; 1.5–1.6 only once code review reports 0 blockers. `ID`,
     `attempt`, `WORKTREE` and `ORIG_BRANCH` are set by ship-next."
  4. **The moved range,** ship-next.md lines 402–463, appended with
     `sed -n '402,463p' claude-skills/ship-workflow/commands/ship-next.md >> …`. Then insert
     **after the end of step 1's block and before the `1.3.` line** this new step, exactly:

```
1.1. **Code review (every attempt).** Invoke code-review-skill on `git diff ${ORIG_BRANCH}...HEAD` and write its report to `$REVIEW_OUT` (`/tmp/ship-next-review-${ID}-${attempt}.md`) in the severity format `code-review-parse.sh` counts (🔴/🟡/🟢/🎉 or `[blocking]`/`[important]`/`[nit]`/`[praise]`, plus the category tags). Read `.ship/review-extra-checks.md` when present and apply its checks. Steps 1.3 and 1.4 run alongside it.
```

  5. The line `2. **Loop:** continue in ship-next Phase 6 step 2.`
  6. `## PR mode`, plus one line "See below", which Task 5 fills in.
- [x] **Step 2: Edit ship-next.md.**
  - Delete lines 402–463.
  - In their place, insert exactly:

```
1. **The review steps live in pr-review.** Each attempt of step 2 runs `~/.claude/skills/pr-review/SKILL.md` § Ship mode where step 2's comments name it: 1.1 code review, 1.3 cross-review and 1.4 Spec review every attempt; 1.5–1.6 security pass only once code review reports 0 blockers. They write `$REVIEW_OUT`, `$SPEC_OUT` and `$SEC_OUT`.
```

  - Then change only these comment lines inside step 2's loop:
    - `# Invoke awesome-skills/code-review-skill on REVIEW_TARGET; capture output to $REVIEW_OUT`
      → `# pr-review ship mode step 1.1: code review → $REVIEW_OUT`
    - `# Step 1.3 appends codex's cross-review to $REVIEW_OUT (Claude-written ships only).`
      → `# pr-review step 1.3 appends codex's cross-review to $REVIEW_OUT (Claude-written ships only).`
    - `# Step 1.4 runs the Spec review in parallel; it writes and checks $SPEC_OUT.`
      → `# pr-review step 1.4 runs the Spec review in parallel; it writes and checks $SPEC_OUT.`
    - `# Read .ship/review-extra-checks.md when present.`
      → `# (pr-review step 1.1 reads .ship/review-extra-checks.md when present.)`
    - `# Only once code review reports 0 blockers, run steps 1.5 and 1.6.`
      → `# Only once code review reports 0 blockers, run pr-review steps 1.5 and 1.6.`
- [x] **Step 3: Verify the move** (Review Focus 1–2). Each check must print nothing:

```bash
SN=claude-skills/ship-workflow/commands/ship-next.md; SK=claude-skills/pr-review/SKILL.md
diff <(git show main:$SN | sed -n '402,463p') <(awk '/^## Ship mode/{f=1;next} /^2\. \*\*Loop:\*\* continue/{f=0} f' $SK | awk '/^1\.1\. \*\*Code review/{skip=1;next} skip && /^1\.3\. /{skip=0} !skip' | sed '1,/^1\. \*\*Verify code-review-skill/{/^1\. \*\*Verify/!d}')
diff <(git show main:$SN | awk '/^2\. \*\*Loop/{f=1} /^3\. \*\*If still blocking/{f=0} f' | grep -vE '^\s*#') <(awk '/^2\. \*\*Loop/{f=1} /^3\. \*\*If still blocking/{f=0} f' $SN | grep -vE '^\s*#')
```

  If the first `diff` prints only whitespace differences coming from the extraction pipeline,
  simplify that pipeline. The moved bytes must be identical. Record the final commands in the
  execution log.
- [x] **Step 4: Repoint the tests per extraction.** Assertions stay unchanged.
  - In each file, a range that starts at a moved heading (`1. **Verify code-review-skill`,
    `1.3.`, `1.4.`, `1.5.`, `1.6.` of Phase 6) reads `"$SHIP_SKILL_ROOT/../pr-review/SKILL.md"`.
  - Ranges over text that stayed (step 2 `MAJOR_LINES`, steps 3–4.5, other phases) keep
    reading ship-next.
  - The files:
    - `test_ship-next-security.bats`: `$CMD` usages;
    - `test_ship-next-cross-review.bats`: line ~175;
    - `test_ship-next-spec-review.bats`: `p6()` and the ranges at lines ~7, ~8 and ~63. A
      `## Phase 6` lookup becomes the `## Ship mode` section of SKILL.md;
    - `test_repo-layout.bats:42`;
    - `test_command-blocks.bats`: `sec_pass_block` and `sec_check_block`. The helper
      `block` takes a path relative to `commands/`, so add a twin `skill_block` that reads
      `$SHIP_SKILL_ROOT/../pr-review/SKILL.md`.
  - Run the five files. Any failure means a range now spans both files: split that
    extraction, and do not change the assertion.
- [x] **Step 5:** `bats tests/test_ship-next-security.bats tests/test_ship-next-cross-review.bats tests/test_ship-next-spec-review.bats tests/test_repo-layout.bats tests/test_command-blocks.bats`
  and expect all PASS.
- [x] **Step 6:** Commit `feat(R-027): ship-next Phase 6 review steps move into pr-review (ship mode)`.

### Task 3: `pr_target`

**Files:** Create `claude-skills/pr-review/lib/pr-review.sh`; Test `tests/test_pr-review.bats`.

**Interfaces:** `pr_target [<target>]`, run in a git clone. It prints the 8 `KEY=value` lines
of Global Constraints and exits 0.
- An unknown target form: stderr `pr_target: cannot read target '<t>'`, exit 2.
- A `gh` / `glab` failure: its stderr passes through, exit 1.

| Target | Provider, number |
|---|---|
| `https://github.com/o/r/pull/7` | github, 7 |
| `https://gitlab.example.com/g/r/-/merge_requests/7` | gitlab, 7 |
| `!7` | gitlab, 7 |
| `#7` or `7` | github if `git remote get-url origin` contains `github.com`, else gitlab |
| empty | branch |

- **github:** `gh pr view 7 --json number,title,url,baseRefName,baseRefOid,headRefOid | jq …`
  gives `PR_BASE`=baseRefName, `PR_BASE_SHA`=baseRefOid, `PR_HEAD`=headRefOid.
- **gitlab:** `glab mr view 7 -F json | jq …` gives `PR_BASE`=target_branch,
  `PR_BASE_SHA`=diff_refs.base_sha, `PR_HEAD`=sha, `PR_URL`=web_url.
- **branch:**
  - `PR_BASE` = `git symbolic-ref --short refs/remotes/origin/HEAD` minus `origin/`;
  - `PR_BASE_SHA` = `git merge-base origin/<base> HEAD`;
  - `PR_HEAD` = `git rev-parse HEAD`;
  - `PR_TITLE` = `git branch --show-current`;
  - `PR_NUMBER` and `PR_URL` empty.
- `PR_LABEL` = the number, or the branch name with `/` → `-`.

- [x] **Step 1: Failing tests** (AC-3, Review Focus 3–4).
  - `setup` puts `$SCRATCH/bin` first on `PATH`.
  - It writes a stub `gh` printing `$GH_JSON` and exiting `${GH_RC:-0}`, and a stub `glab`
    printing `$GLAB_JSON`.
  - It makes a scratch clone with a bare `origin`, a `main` commit and
    `refs/remotes/origin/HEAD` → `origin/main` (`git remote set-head origin main`).

```bash
@test "pr_target: github URL, gitlab URL, !N, #N/N by origin host, branch, bad (AC-3)" {
  GH_JSON='{"number":7,"title":"修「登入」 bug'"'"'s fix","url":"https://github.com/o/r/pull/7","baseRefName":"main","baseRefOid":"aaa1","headRefOid":"bbb2"}'
  export GH_JSON
  eval "$(pr_target https://github.com/o/r/pull/7)"
  [ "$PR_PROVIDER" = github ] && [ "$PR_NUMBER" = 7 ] && [ "$PR_BASE" = main ] && [ "$PR_BASE_SHA" = aaa1 ] && [ "$PR_HEAD" = bbb2 ] && [ "$PR_LABEL" = 7 ] || return 1
  [ "$PR_TITLE" = "修「登入」 bug's fix" ] || return 1
  GLAB_JSON='{"iid":7,"title":"t","web_url":"https://gl/g/r/-/merge_requests/7","target_branch":"main","sha":"ccc3","diff_refs":{"base_sha":"ddd4"}}'
  export GLAB_JSON
  eval "$(pr_target 'https://gl/g/r/-/merge_requests/7')"; [ "$PR_PROVIDER" = gitlab ] && [ "$PR_BASE_SHA" = ddd4 ] && [ "$PR_HEAD" = ccc3 ] || return 1
  eval "$(pr_target '!7')"; [ "$PR_PROVIDER" = gitlab ] || return 1
  git remote set-url origin https://github.com/o/r.git
  eval "$(pr_target '#7')"; [ "$PR_PROVIDER" = github ] || return 1
  git remote set-url origin git@gitlab.example.com:g/r.git
  eval "$(pr_target 7)"; [ "$PR_PROVIDER" = gitlab ] || return 1
  git remote set-url origin "$SCRATCH/origin.git"
  eval "$(pr_target)"; [ "$PR_PROVIDER" = branch ] && [ "$PR_BASE" = main ] && [ "$PR_BASE_SHA" = "$(git merge-base origin/main HEAD)" ] || return 1
  run --separate-stderr pr_target foo; [ "$status" -eq 2 ] && [[ "$stderr" == *"cannot read target 'foo'"* ]] || return 1
  GH_RC=1 run pr_target https://github.com/o/r/pull/7; [ "$status" -eq 1 ]
}
@test "pr_target: same values when sourced under zsh" {
  command -v zsh >/dev/null || skip
  # Run the github case through zsh -c "source …; eval \"\$(pr_target …)\"; print -r -- \$PR_TITLE" and compare.
}
```

- [x] **Step 2:** Run it and expect FAIL.
- [x] **Step 3:** Implement. Recognise target forms with `case` patterns plus `sed`. Read the
  remote with `git remote get-url origin`.
- [x] **Step 4:** Run `test_pr-review.bats` and expect PASS.
- [x] **Step 5:** Commit `feat(R-027): pr_target — resolve a PR/MR/branch to review`.

### Task 4: `pr_checkout` and `pr_spec`

**Files:** Modify `pr-review/lib/pr-review.sh`; Test `tests/test_pr-review.bats`.

**Interfaces:**
- **`pr_checkout`** uses the `PR_*` variables and runs in the clone. It prints the absolute
  `PR_DIR`.
  1. Fetch: `git fetch -q origin "$PR_BASE"`, plus `pull/$PR_NUMBER/head` (github) or
     `merge-requests/$PR_NUMBER/head` (gitlab).
  2. `PR_DIR="$(dirname "$top")/$(basename "$top")-worktrees/pr-review-$PR_LABEL"`, where
     `top` is the repo top. If it already exists, `git worktree remove --force` it.
  3. `git worktree add -q --detach "$PR_DIR" "$PR_HEAD"`.
  4. Source `ship-next.sh` and `sn_state_set` the keys `ID=PR-$PR_LABEL`, `SLUG=review` and
     `ORIG_BRANCH=$PR_BASE_SHA`.
- **`pr_spec <out>`** writes `# <title>`, a blank line, the description, then `## Issue #<n>
  · <title>` with its body for each closing issue.
  - github: `gh pr view N --json title,body,closingIssuesReferences`, then
    `gh issue view <n> --json title,body` per issue.
  - gitlab: `glab mr view N -F json` (`.title`, `.description`), then
    `glab api "projects/:id/merge_requests/N/closes_issues"` (an array of
    `{iid,title,description}`).
  - Exit 3 with no file in `branch` mode, or when the description is empty and there are no
    issues.

- [x] **Step 1: Failing tests** (AC-4, AC-5, Review Focus 5).
  - In a scratch bare `origin`, create commit B on main.
  - Create commit H (adds `f.txt`) on a side branch, and push it to `refs/pull/7/head` and
    `refs/merge-requests/7/head`.
  - Then **merge H into origin main**, so the PR is already merged.
  - Set `PR_*` by hand (`PR_BASE_SHA` = B, `PR_HEAD` = H).

```bash
@test "pr_checkout: detached worktree at the head, state with the base SHA, non-empty diff after merge (AC-4)" {
  for prov in github gitlab; do
    PR_PROVIDER=$prov; d=$(pr_checkout)
    [ "$(git -C "$d" rev-parse HEAD)" = "$H" ] || return 1
    grep -qx "ORIG_BRANCH=$B" "$d/.ship/state.env" || return 1
    [ -n "$(git -C "$d" diff "$B"...HEAD)" ] || return 1
    d2=$(pr_checkout); [ "$d2" = "$d" ] || return 1
  done
  PR_PROVIDER=branch PR_LABEL=feat-x PR_HEAD=$(git rev-parse HEAD); d=$(pr_checkout); [ -d "$d" ]
}
@test "pr_spec: description + closing issue / empty / branch (AC-5)" {
  # github stub: pr view JSON has body "Do X" and closingIssuesReferences [{"number":3}]; issue view prints {"title":"Bug","body":"steps"}
  pr_spec "$SCRATCH/s.md"; grep -qF 'Do X' "$SCRATCH/s.md"; grep -qF '## Issue #3 · Bug' "$SCRATCH/s.md"
  # empty body, no issues → exit 3 and no file
  # PR_PROVIDER=branch → exit 3
}
```

  The `.ship/state.env` format is `sn_state_set`'s. `PR_BASE_SHA` is a plain hex, so a
  `grep -qx "ORIG_BRANCH=$B"` works; if `sn_state_set` quotes values, match its quoting.
- [x] **Step 2:** Run them and expect FAIL.
- [x] **Step 3:** Implement.
- [x] **Step 4:** Run them and expect PASS.
- [x] **Step 5:** Commit `feat(R-027): pr_checkout and pr_spec`.

### Task 5: `pr_report`, `pr_comment` and § PR mode

**Files:** Modify `pr-review/lib/pr-review.sh` and `pr-review/SKILL.md`; Test
`tests/test_pr-review.bats`.

**Interfaces:**
- **`pr_report <out> <review> <spec|-> <security>`** counts with
  `"${SHIP_LIB:-…}/code-review-parse.sh" <review> [<spec>] <security>`, through `eval`.
  It writes, in this order:
  1. `# PR review · $PR_TITLE`.
  2. `$PR_URL` (or `branch: $PR_TITLE`), ` · ` and `` `$PR_BASE` (<first 8 of PR_BASE_SHA>)…<first 8 of PR_HEAD> ``.
  3. `**結論：可以合併**` when `BLOCKING_COUNT` is 0, else `**結論：先修 <n> 個 blocking**`.
  4. The table `| blocking | major | minor | spec gaps | security |` with one row of counts.
  5. `## 程式碼與跨模型`, then the review file's lines.
  6. `## Spec`, then the spec file's lines, or `略過：沒有描述或 issue 可對照` when `-`.
  7. `## 安全`, then the security file's lines.

  It prints `<out>`.
- **`pr_comment <report>`:**
  - github: `gh pr comment "$PR_NUMBER" --body-file "<report>"`.
  - gitlab: `glab mr note "$PR_NUMBER" --message "$(cat "<report>")"`.
  - branch: stderr `pr_comment: no PR/MR to comment on`, exit 2.

- [x] **Step 1: Failing tests** (AC-7, AC-8):

```bash
@test "pr_report: verdict, counts, three sections in order, spec skipped (AC-7)" {
  printf '%s\n' '🔴 [blocking] a.py:1 — x' '🟢 [nit] b.py:2 — y' > "$SCRATCH/r.md"
  echo 'No security findings.' > "$SCRATCH/sec.md"
  PR_TITLE=T PR_URL=https://x/7 PR_BASE=main PR_BASE_SHA=abcdef0123 PR_HEAD=9876543210
  pr_report "$SCRATCH/out.md" "$SCRATCH/r.md" - "$SCRATCH/sec.md" >/dev/null
  grep -qF '**結論：先修 1 個 blocking**' "$SCRATCH/out.md"
  grep -qF '`main` (abcdef01)…98765432' "$SCRATCH/out.md"
  [ "$(grep -nE '^## ' "$SCRATCH/out.md" | cut -d: -f2- | tr '\n' '|')" = "## 程式碼與跨模型|## Spec|## 安全|" ]
  grep -qF '略過：沒有描述或 issue 可對照' "$SCRATCH/out.md"
}
@test "pr_comment: gh / glab args, branch refused (AC-8)" {
  # stubs append "$0 $*" to $SCRATCH/calls
  PR_PROVIDER=github PR_NUMBER=7 pr_comment "$SCRATCH/out.md"; grep -qF 'gh pr comment 7 --body-file' "$SCRATCH/calls"
  PR_PROVIDER=gitlab PR_NUMBER=7 pr_comment "$SCRATCH/out.md"; grep -qF 'glab mr note 7 --message' "$SCRATCH/calls"
  PR_PROVIDER=branch run pr_comment "$SCRATCH/out.md"; [ "$status" -eq 2 ]
}
```

  Also add a zsh run of `pr_report`, and assert its output equals the bash run's.
- [x] **Step 2:** Run them and expect FAIL.
- [x] **Step 3: Implement both, then write § PR mode in SKILL.md** following spec §3.3 P0–P6:
  - **Arguments:** `[<target>] [--comment] [--keep] [--no-codex]`.
  - **Blocks:**
    - **P0:** source the lib, then `eval "$(pr_target "$TARGET")"`.
    - **P1:** `PR_DIR=$(pr_checkout)`.
    - **P2:**
      `SPEC_FILE="${TMPDIR:-/tmp}/pr-review-$PR_LABEL-spec-input.md"; pr_spec "$SPEC_FILE" || SPEC_FILE=-`.
    - **P3:** prose for the four axes, using `"$PR_DIR"`:
      - Standards: § Ship mode step 1.1's instruction on `git -C "$PR_DIR" diff "$PR_BASE_SHA"...HEAD`;
      - `sn_cross_review "$PR_DIR" "$REVIEW_OUT"` unless `--no-codex`;
      - when `SPEC_FILE` ≠ `-`: `sn_spec_review_render "$PR_DIR" "$SPEC_FILE" "$PR_BASE_SHA"`,
        a sub-agent, then `sn_spec_review_check`;
      - from inside `PR_DIR`, the security steps of § Ship mode 1.5–1.6 with `$PR_BASE_SHA`
        as the base, run regardless of the other results.

      The output paths are `${TMPDIR:-/tmp}/pr-review-$PR_LABEL-{review,spec,security}.md`.
    - **P4:** `pr_report "${TMPDIR:-/tmp}/pr-review-$PR_LABEL.md" …`, then show the report in
      chat, with the zh-TW summary first.
    - **P5:** only with `--comment`, `pr_comment`.
    - **P6:** unless `--keep`, `git worktree remove --force "$PR_DIR"`.
  - Name the read-only rule: PR mode never pushes and never edits the PR branch.
- [x] **Step 4:** Run `test_pr-review.bats` and expect PASS.
- [x] **Step 5:** Commit `feat(R-027): pr_report, pr_comment and /pr-review PR mode`.

### Task 6: Install and docs

**Files:**
- Modify: `sync.sh`:
  - the header comment: four skills;
  - `SKILLS=(ship-workflow run-plan code-review-skill pr-review)`.
- Modify: `claude-skills/ship-workflow/tests/test_sync-install.bats`:
  - setup creates `$R/claude-skills/pr-review`;
  - both skill loops include `pr-review`;
  - the exact listing at line ~89 becomes `"code-review-skill pr-review run-plan ship-workflow "`;
  - test names say 4 skills.
- Modify: repo `CLAUDE.md`:
  - line 4: `claude-skills/` holds ship-workflow, plus `run-plan`, `code-review-skill` and
    `pr-review`, and nothing else;
  - note that ship-next Phase 6's review steps live in `pr-review` (R-027);
  - line 11: the link list includes pr-review.
- Modify: `claude-skills/ship-workflow/SKILL.md` and `README.md`:
  - "links ship-workflow, run-plan, code-review-skill, pr-review";
  - one line in SKILL.md: "Phase 6's review steps live in `pr-review` (§ Ship mode); `/pr-review` also reviews any GitHub PR or GitLab MR."

- [x] **Step 1:** Update the test first. Run `bats tests/test_sync-install.bats` and expect
  FAIL: pr-review is not linked.
- [x] **Step 2:** Edit `sync.sh` and run again; expect PASS (AC-9).
- [x] **Step 3:** Edit the docs. Check with
  `grep -nE 'code-review-skill[^,]*$|three skills|3 skills' CLAUDE.md claude-skills/ship-workflow/SKILL.md claude-skills/ship-workflow/README.md sync.sh`:
  no stale count may remain.
- [x] **Step 4:** Commit `feat(R-027): install pr-review; docs name four skills`.

### Task 7: Full suite
- [x] **Step 1:** `cd claude-skills/ship-workflow && bats tests/`. Expect every test to pass
  except the known cwd-guard failure. The baseline is 752/753.
- [x] **Step 2:** Fix any other failure in its owning task, and log it.

## Execution log

- Task 1: confirmed the new test failed before implementation; all 7 spec-review tests pass.
- Deviation: preserve the default relative prompt path using `${2:-docs/specs/${ID}-${SLUG}.md}` while `$spec` performs the existence check — printing the prescribed absolute default `$spec` would break the unchanged-default requirement.

- Deviation: added pr-review to the repository-layout exact allow-list — the new skill otherwise fails the existing registry guard.
- Deviation: updated the cross-review ordering test's exact comment match from `# Step 1.3` to `# pr-review step 1.3` — the plan explicitly changes that comment; the ordering assertion remains intact.
- Task 2 byte checks printed nothing. Final commands (simplified extraction):
```bash
SN=claude-skills/ship-workflow/commands/ship-next.md; SK=claude-skills/pr-review/SKILL.md
diff <(git show main:$SN | sed -n '402,463p') <(sed -n '/^1\. \*\*Verify code-review-skill/,/^2\. \*\*Loop:/p' "$SK" | sed '/^1\.1\. \*\*Code review/d; /^2\. \*\*Loop:/d')
diff <(git show main:$SN | awk '/^2\. \*\*Loop/{f=1} /^3\. \*\*If still blocking/{f=0} f' | grep -vE '^\s*#') <(awk '/^2\. \*\*Loop/{f=1} /^3\. \*\*If still blocking/{f=0} f' "$SN" | grep -vE '^\s*#')
```

- Task 2: all 102 tests across the five prescribed files pass.

- Task 3: 7 target tests failed before implementation and now pass, including bash/zsh values and CJK/apostrophe quoting. Real CLI help confirmed gh JSON field names and glab `-F json`; captured under `.ship/cli-probe/` with isolated configuration. Tests use stubs only. Split the target cases into focused tests per the repository TDD rules.

- Task 4: six new tests failed before implementation; all 13 PR-review tests now pass. Both forge refs retain a non-empty diff after merge; repeated detached checkout and issue-derived specs verified.

- Task 5: four new tests failed before implementation; all 17 PR-review tests pass, including bash/zsh report equality and exact comment arguments.
- Deviation: P0 captures and checks `pr_target` output before eval — direct `eval "$(pr_target ...)"` masks a failed resolution and could proceed with stale variables.

- Task 6: install test failed specifically for the absent pr-review link, then all 17 tests passed. Docs and installer help name four skills; the prescribed grep only matches the updated four-skill array/help, with no stale count. Installation was exercised only in scratch HOME fixtures.

- Task 7: `cd claude-skills/ship-workflow && bats tests/` completed: **770/771 pass**. The only failure is the pre-declared baseline `cwd-guard: exits 0 when not in a git repo at all`; no new failures. Full log: `.ship/full-suite.log`. HOME and TMPDIR were isolated under this worktree for the full suite.
- Final verification: bash/zsh syntax checks pass; moved-byte and non-comment loop comparisons against main print nothing; `git diff --check` passes. No remote push, live installation or vault modification was performed. AC-10 remains operator-run as specified.
- Durable learning: extraction changes require both source-range updates and updates to exact registry/comment expectations; preserve the assertions' semantics and verify moved bytes separately.
- Result: DONE_WITH_CONCERNS. All seven tasks executed; the four small deviations above and the known baseline failure are recorded. No new test failures remain.
