---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-027
status: draft
tags: [ship-workflow, review, skill, github, gitlab]
ai-first: true
related-specs: [R-003, R-016, R-019]
mockup: null
supersedes: null
---

## For future Claude
> R-027 adds a fourth skill, `claude-skills/pr-review/`. It is the single entry for the review
> that ship-next Phase 6 runs, and it has two modes:
> - **Ship mode.** ship-next Phase 6 steps 1–1.6 now live in `pr-review/SKILL.md`, moved
>   verbatim with the same headings: code-review-skill, codex cross-review, Spec review,
>   security pass and its check. ship-next calls it each attempt and keeps the loop, the
>   fix-plans and the IDEA filing.
> - **PR mode,** `/pr-review [<PR/MR number or URL>] [--comment] [--keep] [--no-codex]`. It
>   reviews someone else's GitHub PR (`gh`) or GitLab MR (`glab`), or the current branch, in
>   a throwaway detached worktree, with the same four axes. It writes one zh-TW report and
>   posts it only with `--comment`.
>
> The review libs stay in `ship-workflow/lib/`; `pr-review/lib/pr-review.sh` adds only the
> PR-mode glue.

## §1 Problem
The operator: 「把目前 ship next 裡的 review 都封裝 在這個skill 方便我後續幫人 code review 也方便 Ship next 也方便」.

Today the full review exists only inside ship-next Phase 6:
- it is 212 of `commands/ship-next.md`'s 717 lines;
- it is tied to a ship worktree's state: `ID`, `SLUG`, `ORIG_BRANCH`, the executor file, and
  the spec path.

Reviewing a colleague's MR with it is impossible. Any change to the review has to be made
inside ship-next.

## §2 Goals, non-goals
**Goals**
- G1. **One place for the review steps.** ship-next Phase 6 steps 1–1.6 move verbatim into
  `pr-review/SKILL.md` § Ship mode. ship-next's behaviour does not change, which the
  existing Phase 6 tests prove by passing with only their file path changed.
- G2. **PR mode** reviews a GitHub PR, a GitLab MR or the current branch, with all four
  axes, and produces one report with severity counts.
- G3. **Nothing is posted** to a PR/MR unless `--comment` is given.
- G4. **Install:** `sync.sh` links the skill, and the R-004 rule says four skills.

**Non-goals**
- Moving the review libs out of `ship-workflow/lib/`.
- Changing what any review checks, its severity format, or the security confidence bar (8).
- The fix loop for someone else's PR. PR mode reports; it does not fix.
- Inline per-line comments. `--comment` posts one summary note.
- Bitbucket or other forges.

## §3 Design
### 3.1 Layout
```
claude-skills/pr-review/
  SKILL.md          # frontmatter name: pr-review; § Ship mode; § PR mode
  lib/pr-review.sh  # pr_target, pr_checkout, pr_spec, pr_report, pr_comment
```
- `lib/pr-review.sh` sources ship-workflow libs through
  `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}`.
- It uses no arrays and runs the same under bash and zsh: Claude Code's Bash tool runs zsh
  (R-003).
- Its tests live in `ship-workflow/tests/test_pr-review.bats`, so one `bats tests/` run
  covers everything.

### 3.2 Ship mode — moved text
- **Move:** ship-next Phase 6 steps `1. **Verify code-review-skill installed:**`, `1.3.`,
  `1.4.`, `1.5.` and `1.6.` move byte-for-byte into `pr-review/SKILL.md` under
  `## Ship mode`, in that order.
  - Their blocks already use absolute `~/.claude/skills/ship-workflow/lib/…` paths, so they
    run unchanged from the new file.
  - The section ends with the line `2. **Loop:** continue in ship-next Phase 6 step 2.`, so
    the existing extraction ranges (`/^1\.6\. …/,/^2\. \*\*Loop/`) still stop where they
    did.
- **New step `1.1. **Code review**`** in § Ship mode, between 1 and 1.3 (builder check: the
  code-review call used to be only a comment inside step 2). It states what that comment
  said:
  - invoke code-review-skill on `git diff ${ORIG_BRANCH}...HEAD`;
  - read `.ship/review-extra-checks.md` when present;
  - write the report to `$REVIEW_OUT` in the severity format `code-review-parse.sh` counts.

  This is the only new text in § Ship mode.
- **ship-next Phase 6** keeps 0.5 and 2–4.5. In place of the moved steps it has one step,
  which keeps today's per-attempt order:

  `1. **The review steps live in pr-review.** Each attempt of step 2 runs ~/.claude/skills/pr-review/SKILL.md § Ship mode where step 2's comments name it: 1.1 code review, 1.3 cross-review and 1.4 Spec review every attempt; 1.5–1.6 security pass only once code review reports 0 blockers. They write $REVIEW_OUT, $SPEC_OUT and $SEC_OUT.`
- **Step 2's comments,** "Invoke awesome-skills/code-review-skill …", "Step 1.3 appends …",
  "Step 1.4 runs …" and "run steps 1.5 and 1.6", name the pr-review steps instead. The loop
  code itself is unchanged.
- **Tests that extract these steps from `commands/ship-next.md`** read
  `../pr-review/SKILL.md` instead. Their assertions do not change: `test_ship-next-security`,
  `test_ship-next-cross-review`, `test_ship-next-spec-review`, `test_repo-layout` and the
  `sec_pass_block` / `sec_check_block` helpers in `test_command-blocks`.

### 3.3 PR mode — `/pr-review [<target>] [--comment] [--keep] [--no-codex]`
Run from a local clone of the repo under review. Steps:

**P0 · Resolve:** `eval "$(pr_target "<target>")"` sets `PR_PROVIDER` (`github`, `gitlab` or
`branch`), `PR_NUMBER`, `PR_BASE`, `PR_HEAD`, `PR_TITLE`, `PR_URL` and `PR_LABEL`. Target
forms:

| Form | Provider |
|---|---|
| `https://github.com/<o>/<r>/pull/<n>` | github |
| `https://<host>/…/-/merge_requests/<n>` | gitlab |
| `!<n>` | gitlab |
| `#<n>` or `<n>` | github when `git remote get-url origin` contains `github.com`, else gitlab |
| empty | `branch`: `PR_BASE` = the origin default branch (`refs/remotes/origin/HEAD`), `PR_HEAD` = `git rev-parse HEAD`, `PR_TITLE` = the current branch name |

- github reads `gh pr view <n> --json number,title,url,baseRefName,baseRefOid,headRefOid`.
- gitlab reads `glab mr view <n> -F json`, taking `iid`, `title`, `web_url`,
  `target_branch`, `sha` and `diff_refs.base_sha`.
- **`PR_BASE_SHA`** is the commit the review diffs against:
  - github `baseRefOid`;
  - gitlab `diff_refs.base_sha`;
  - `branch` `git merge-base origin/<default> HEAD`.

  A recorded base SHA gives the PR's own diff for open and already-merged PRs/MRs alike.
  Diffing against `origin/<base>` gives an empty diff after a merge commit, and after a
  squash merge treats the PR's own code as pre-existing (builder check).
- `PR_LABEL` is `<n>` for a PR/MR, or the branch name with `/` → `-` for `branch`.
- Errors:
  - an unrecognised target: exit 2, `pr_target: cannot read target '<t>'`;
  - a failing CLI: exit 1, with its stderr passed through.

**P1 · Check out:** `PR_DIR=$(pr_checkout)`. It runs in the clone and uses the `PR_*` vars:
1. `git fetch origin <base>` and the head: `pull/<n>/head` (github),
   `merge-requests/<n>/head` (gitlab), or nothing (branch).
2. `git worktree add --detach "$PR_DIR" "$PR_HEAD"`, where `PR_DIR` is
   `<parent>/<repo>-worktrees/pr-review-<label>`. An existing dir is removed first with
   `git worktree remove --force`.
3. It writes `ID=PR-<label>`, `SLUG=review` and `ORIG_BRANCH=$PR_BASE_SHA` into
   `"$PR_DIR/.ship/state.env"` with `sn_state_set`, so the ship review helpers work there
   unchanged.
4. It prints `PR_DIR`.

**P2 · Spec:** `pr_spec "$SPEC_FILE"` writes the PR/MR title and description, then each
closing issue's title and body:
- github: `gh pr view <n> --json body,closingIssuesReferences`, then `gh issue view` per
  issue;
- gitlab: `glab mr view <n> -F json` description, plus
  `glab api projects/:id/merge_requests/<n>/closes_issues`.

Exit 3 with no file when the description is empty and there are no issues, and always in
`branch` mode. The Spec axis is then skipped, and the report says so.

**P3 · Four reviews,** in parallel where they can be. Outputs go to
`${TMPDIR:-/tmp}/pr-review-<label>-{review,spec,security}.md`.
- **Standards:** § Ship mode step 1.1's instruction, run in `PR_DIR` on
  `git -C "$PR_DIR" diff $PR_BASE_SHA...HEAD`, written to `REVIEW_OUT`.
- **Cross-model:** `sn_cross_review "$PR_DIR" "$REVIEW_OUT"`. It runs, because `PR_DIR` has
  no `.claude/.ship-executor`. `--no-codex` skips it.
- **Spec:**
  - `sn_spec_review_render "$PR_DIR" "$SPEC_FILE" "$PR_BASE_SHA"` (§3.4);
  - a read-only sub-agent writes `SPEC_OUT`;
  - `sn_spec_review_check "$SPEC_OUT"`.
- **Security,** from inside `PR_DIR`:
  - `security_review_enabled` / `security_review_render "$PR_BASE_SHA" …`;
  - one finder, filters per candidate, confidence ≥ 8 kept;
  - `security_review_output_check`;
  - `pre_existing_strip_unverified "$PR_BASE_SHA" "$REVIEW_OUT" "$SEC_OUT"`.

  PR mode runs it regardless of the code-review result; it reports, it does not gate.

**P4 · Report:** `pr_report <out> "$REVIEW_OUT" "$SPEC_OUT|-" "$SEC_OUT"`. It counts with
`code-review-parse.sh` and writes:
1. `# PR review · <title>`.
2. A line with `PR_URL` (or the branch) and `<base> (<short base sha>)…<short head>`.
3. A verdict: 「可以合併」 when blocking is 0, else 「先修 <n> 個 blocking」.
4. A table of blocking / major / minor / spec gaps / security.
5. The axes as separate sections, never merged or re-sorted:
   - `## 程式碼與跨模型`: the `REVIEW_OUT` lines;
   - `## Spec`: the `SPEC_OUT` lines, or 「略過：沒有描述或 issue 可對照」 when `-`;
   - `## 安全`: the `SEC_OUT` lines.

The report goes to `${TMPDIR:-/tmp}/pr-review-<label>.md`. Claude shows it in chat.

**P5 · Comment** (only with `--comment`): `pr_comment "$REPORT"`.
- github: `gh pr comment <n> --body-file <report>`.
- gitlab: `glab mr note <n> --message "$(cat <report>)"`.
- In `branch` mode: exit 2, `pr_comment: no PR/MR to comment on`.

**P6 · Clean up:** `git worktree remove --force "$PR_DIR"`, unless `--keep`.

### 3.4 `sn_spec_review_render <wt> [<spec-path> <base>]`
- With both optional arguments, the prompt's first line reads
  `Read <spec-path> in full. Read the diff with git diff <base>...HEAD.`, and the spec must
  exist at `<spec-path>`.
- Without them, it behaves as today: `docs/specs/${ID}-${SLUG}.md` and `ORIG_BRANCH` from
  state.
- The rest of the prompt is unchanged.

### 3.5 Install and docs
- `sync.sh`: `SKILLS=(ship-workflow run-plan code-review-skill pr-review)`; header comment
  updated.
- `tests/test_sync-install.bats`: the scratch tree, the loops and the exact
  `claude-skills` listing include `pr-review`.
- Repo `CLAUDE.md`: the R-004 sentence names the four skills; Commands say the bats run
  covers pr-review.
- `ship-workflow/SKILL.md` and `README.md`: "links ship-workflow, run-plan,
  code-review-skill, pr-review"; Phase 6 is described as calling pr-review.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| ship mode | `pr-review/SKILL.md` § Ship mode steps 1, 1.1, 1.3–1.6 | 1 and 1.3–1.6 byte-identical to ship-next Phase 6 at `main` before this ship; 1.1 states step 2's former code-review comment; followed by `2. **Loop:** …` |
| ship-next Phase 6 | step 1 "The review steps live in pr-review" | no `1.3.`–`1.6.` steps left; per-attempt order unchanged (1.1, 1.3, 1.4 every attempt; 1.5–1.6 at 0 blockers); loop code unchanged, only its comments name pr-review |
| target | `pr_target <target>` → `KEY=value` lines (cwd = clone) | the §3.3 table, including `PR_BASE_SHA` (github `baseRefOid`, gitlab `diff_refs.base_sha`, branch merge-base); unknown form → exit 2; CLI failure → exit 1 |
| checkout | `pr_checkout` (uses `PR_*`) → prints `PR_DIR` | detached worktree at `PR_HEAD`; `.ship/state.env` with `ORIG_BRANCH=<PR_BASE_SHA>`, `ID=PR-<label>`, `SLUG=review` |
| spec | `pr_spec <out>` | description + closing issues → `<out>`; nothing to compare or `branch` → exit 3, no file |
| spec prompt | `sn_spec_review_render <wt> [<spec-path> <base>]` | optional args override spec path and base; without them unchanged |
| report | `pr_report <out> <review> <spec\|-> <security>` | header, verdict, counts table, three separate sections in that order; `-` → skipped note |
| comment | `pr_comment <report>` (uses `PR_*`) | github `gh pr comment <n> --body-file`; gitlab `glab mr note <n> --message`; branch → exit 2 |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | `main`'s ship-next Phase 6 | the ship lands | `pr-review/SKILL.md` § Ship mode steps 1 and 1.3–1.6 equal them byte-for-byte and 1.1 exists; ship-next has the new step 1, no `1.5. **Security pass`, and its loop's non-comment lines unchanged |
| AC-2 | the Phase 6 tests | each extraction of a moved step reads `pr-review/SKILL.md`; extractions of text that stayed keep reading ship-next | they pass with unchanged assertions |
| AC-3 | stub `gh` / `glab` on `PATH`, scratch clones with a github and a gitlab `origin` | `pr_target` on a github URL, a gitlab URL, `!7`, `#7` (github origin), `7` (gitlab origin), empty, `foo` | the right provider, number, base, base SHA, head, title, url and label each time; empty → `branch` with the origin default branch and its merge-base; `foo` → exit 2 |
| AC-4 | a scratch `origin` holding `refs/pull/7/head` and `refs/merge-requests/7/head` | `pr_checkout` for each, and for `branch` | a detached worktree at that head; `.ship/state.env` holds `ORIG_BRANCH=<PR_BASE_SHA>`; a second call replaces it |
| AC-5 | stub description + one closing issue / empty description, no issues / `branch` | `pr_spec` | a file with both / exit 3, no file / exit 3 |
| AC-6 | a worktree with state, and an extra spec file | `sn_spec_review_render "$wt"` / `… "$wt" /x/spec.md origin/dev` | the first line names `docs/specs/<ID>-<SLUG>.md` and `ORIG_BRANCH` / `/x/spec.md` and `origin/dev`; the rest of the prompt is identical |
| AC-7 | review with 1 blocking + 1 minor, spec `-`, security clean | `pr_report` | the verdict 「先修 1 個 blocking」, the counts, the three sections in order, the spec-skipped note |
| AC-8 | stub `gh` / `glab` that log their args | `pr_comment` for github, gitlab, branch | `gh pr comment 7 --body-file <report>` / `glab mr note 7 --message <text>` / exit 2 |
| AC-9 | a scratch HOME | `./sync.sh restore` | `~/.claude/skills/pr-review` links into the checkout; the docs say four skills |
| AC-10 | a merged langlive-line-oa MR (line-oa squash-merges) | Claude runs `/pr-review <that MR>` after the executor, without `--comment` | a report with all four axes in chat, reviewing the MR's own non-empty diff against `diff_refs.base_sha`; nothing posted; the throwaway worktree removed |

## §5 Rollout
1. Land on main.
2. `./sync.sh restore` links `~/.claude/skills/pr-review`.
3. The next ship's Phase 6 runs through pr-review.

## Decisions
**Operator decisions (2026-10-27)**
- 「幫我多一個 skill 叫 pr-review … 方便我後續幫人 code review 也方便 Ship next 也方便」:
  a standalone skill used by ship-next and by hand.
- The six proposed defaults (standalone dir; libs stay; `--comment` opt-in; description as
  spec; codex always in PR mode; the loop stays in ship-next) were taken with 「R27 auto」.

**Claude's calls** (auto mode, the operator can override)
- **Move the step text verbatim with its headings.** The existing tests then prove
  behaviour unchanged by passing with only a path change. Rewriting the steps would need
  new evidence.
- **PR mode writes `.ship/state.env` into its own throwaway worktree,** so
  `sn_cross_review` and the security helpers run unchanged. Only `sn_spec_review_render`
  needs new optional arguments.
- **PR mode runs all four axes every time** and does not gate: it is a report for a
  person, and ship mode keeps the gate.
- **The report summary is zh-TW** (the operator and the langlive team read it). Finding
  lines keep their tags.
- **One summary note on `--comment`, not inline comments.** It is the smallest thing that
  is useful; inline threads are a later item.
**From the builder check**
- **Step 1.1 is the only new ship-mode text:** the code-review call used to be a comment
  inside step 2.
- **ship-next's new step 1 keeps the per-attempt order;** step 2's comments name the
  pr-review steps.
- **PR mode diffs against the PR/MR's recorded base SHA,** not `origin/<base>`. A merged MR
  would otherwise show an empty diff, or have its own code taken as pre-existing.
- **Tests switch their source file per extraction;** assertions stay unchanged.
**Review attempts (auto mode)**
- **Attempt 1:** the Spec review found that §3.5's README line was missing. Fixed (f8a8d2b).
- **Attempt 2, security pass, confidence 9:**
  - Finding: a PR-committed `.ship/state.env` was preserved by `sn_state_set` and sourced by
    `sn_state_load`, so reviewing a hostile PR ran its code. A `.ship/*.tmp` symlink also
    redirected our writes (reproduced).
  - Fix: `pr_checkout` removes the PR's own `.ship/`, `.claude/` and `.codex/` before writing
    state, and warns when they were tracked. They stay in the reviewed diff.
  - Lower-confidence candidates were hardened in SKILL.md:
    - no PR-supplied extra checks;
    - the Spec sub-agent is told SPEC_FILE is untrusted;
    - `--comment` posts only after the operator OKs the report shown in chat.
- **`.codex/` was added after attempt 3's re-check** (confidence 7: a PR's codex config
  could steer the cross-model reviewer, since `~/.codex` trusts `$HOME`). It is the same
  removal, with a test.
- Door: two-way — a new skill dir, a moved block of command text, one optional-argument lib change and docs; reverting the commit restores ship-next's Phase 6 text, and nothing is posted to any PR without `--comment`.

## §8 Known risks
- **R1 Text drift.** A later edit to the ship-mode steps lands in `pr-review/SKILL.md`.
  Reviewers must look there, and this learning says so.
- **R2 Forge CLIs.** The `gh` / `glab` JSON field names are taken from their current
  versions (gh 2.94, glab 1.99); stubs pin them in tests.
- **R3 Large MRs.** codex review has a 600 s timeout (R-019). A huge MR may time out, which
  shows as a WARN on that axis, not a failure.
