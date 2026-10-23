---
date: 2026-10-23
updated: 2026-10-23
type: spec
id: R-003
status: draft
tags: [ship-workflow, ship-next, phase-6, security-review, prompt-injection, pre-existing]
ai-first: true
brainstorm: docs/brainstorms/R-003-add-security-review-gate.md
related-specs:
  - docs/specs/R-001-add-ship-land-defer-writes.md
supersedes: null
---

## For future Claude
> Phase 6 used to run a single LLM review, code-review-skill. This spec adds a
> **separate security pass** to the same loop, as Anthropic's own pipeline does
> (claude.dev/blog/solving-code-review-at-anthropic, 2026-10-15). Its blocking
> findings count toward the same gate and the same fix-plan loop. It also adds a
> **`[pre-existing]` finding class** that is reported but never blocks; those
> findings become follow-ups.
>
> The security pass is Anthropic's open-source `/security-review` prompt (MIT),
> **vendored with five changes**:
> 1. It diffs `${ORIG_BRANCH}...HEAD`, not `origin/HEAD`.
> 2. It emits ship-next's severity line format.
> 3. It drops upstream exclusion 14 ("user content in AI prompts is not a
>    vulnerability") and adds an AI-input checklist, because the operator's concern
>    is prompt injection through LINE messages.
> 4. It may report pre-existing issues, tagged.
> 5. Its false-positive filters also see the AI-input category, so they do not discard
>    a prompt-injection finding as mere missing hardening.
>
> The built-in `/security-review` command is deliberately not called; §3 says why.

## §1 Problem
- Phase 6's only LLM gate is a general code review. Nothing looks at the diff
  specifically for exploitable security defects.
- The operator's stated worry is injection, chiefly **LINE end-users manipulating the
  AI customer-service bot** in langlive-line-oa. The built-in `/security-review`
  prompt excludes exactly that class: hard exclusion 14 says *"Including
  user-controlled content in AI system prompts is not a vulnerability."*
- Reviewers flag bugs that already existed before the diff. Today these count as
  blockers against the current ship, or get argued away; neither is right.
  Anthropic measured that about 59% of a reviewer's repeat flags were code untouched
  since the first pass, which is why their reviewer has a Pre-existing tag.

## §2 Goals, non-goals, anti-goals
**Goals**
- G1. Every Phase 6 review attempt runs a security pass over `${ORIG_BRANCH}...HEAD`,
  unless the repo turns it off.
- G2. HIGH security findings block exactly like code-review blockers: same count, same
  fix-plan loop, same cap of 3. MEDIUM is treated as important; LOW as nit.
- G3. The security pass covers prompt injection and LLM-output handling whenever the
  diff touches code that builds LLM prompts, ingests content later fed to an LLM, or
  acts on LLM output.
- G4. A finding tagged `[pre-existing]`, from either review, never blocks and never
  counts as important. It is listed separately and becomes a follow-up.
- G5. The upstream prompt's false-positive discipline is preserved: a finder sub-task,
  parallel filter sub-tasks, and a confidence ≥ 8 cutoff.

**Non-goals**
- Deploy / crash / runtime-safety review (the operator's first worry). It is a separate
  future item.
- Fixing langlive's stored-injection path through the auto-published KB (brainstorm
  recon #1). That is a langlive item.
- Writing langlive's `docs/SECURITY_REVIEW.md`. That is a follow-up in langlive.
- A GitLab/GitHub CI job. This gate lives in ship-next only.
- A per-repo switch for the AI-input section. It is always present and conditioned
  inside the prompt.

**Anti-goals** (failure even if it "works")
- A security pass so noisy that blockers get waved through. The upstream FP filtering
  must survive vendoring intact.
- `[pre-existing]` becoming an escape hatch for real new defects (§3.4 verification).

## §3 Design

### 3.1 Why vendor instead of calling the built-in `/security-review`
| Need | Built-in `/security-review` | Vendored prompt |
|---|---|---|
| Diff = this ship (`ORIG_BRANCH...HEAD`) | fixed to `origin/HEAD` | yes |
| Output the parser can count | `* Severity: High` (unparsed) | ship-next line format |
| Prompt injection in scope | hard-excluded (#14) | included |
| Pre-existing reported separately | "do not comment on existing concerns" | yes, tagged |
| Upstream maintenance | automatic | manual re-sync (pinned commit, §8 R1) |

### 3.2 Vendored prompt — `templates/security-review/PROMPT.md` (+ `LICENSE.upstream`)
- **Source:** `anthropics/claude-code-security-review` @ `0c6a49f1fa56`,
  `.claude/commands/security-review.md`. MIT, "Copyright (c) 2025 Anthropic".
  `LICENSE.upstream` is the upstream MIT text verbatim. `PROMPT.md` starts with an HTML
  comment naming the source path, the commit and the list of changes below.
- **Kept verbatim:**
  - OBJECTIVE and CRITICAL INSTRUCTIONS, except the sentence changed in C4
  - SECURITY CATEGORIES
  - ANALYSIS METHODOLOGY
  - SEVERITY GUIDELINES and CONFIDENCE SCORING
  - FALSE POSITIVE FILTERING (hard exclusions 1–13 and 15–17, all 12 precedents, signal
    quality criteria)
  - START ANALYSIS, the 3-step sub-task method with the confidence < 8 cutoff
- **Changes:**
  - **C1 Git context.** The `!`-backtick shell blocks and the slash-command frontmatter
    are removed. They are replaced by instructions to run, in the repo root:
    `git diff --name-only {{orig_branch}}...HEAD`,
    `git log --no-decorate {{orig_branch}}..HEAD`, and `git diff {{orig_branch}}...HEAD`.
    START ANALYSIS gains one parenthetical: a sub-task is a separate agent you dispatch.
  - **C2 Output format.** REQUIRED OUTPUT FORMAT is replaced. One finding is one line
    starting with the severity marker, then indented detail lines:
    ```
    🔴 [blocking] [security:<category>] <file>:<line> — <one-line description>
       Exploit scenario: …
       Recommendation: …
       Confidence: <8-10>/10
    ```
    - HIGH → `🔴 [blocking]`, MEDIUM → `🟡 [important]`, LOW → `🟢 [nit]`.
    - A pre-existing finding inserts `[pre-existing]` after the severity tag and adds
      an indented `Base evidence: <file>:<line> exists unchanged on {{orig_branch}}` line.
    - The output is nothing but finding lines, their indented detail lines and blank
      lines: no title, headings, preamble or summary. A detail line never states a
      severity: no marker, tag, `Severity` field or HIGH/MEDIUM/LOW label. This is exactly what `security_review_output_check`
      accepts, and the prompt's own example passes it.
    - With no findings, the output is exactly `No security findings.`
  - **C3 AI-input safety.**
    - Hard exclusion 14 is deleted.
    - A category **"LLM / AI input safety"** is added to SECURITY CATEGORIES. It applies
      only when the diff touches code that builds an LLM prompt, stores content that a
      later LLM call will read, or acts on LLM output. Checklist:
      1. untrusted text (end-user messages, uploaded media text, third-party content)
         inserted into instructions or system text without role separation or
         delimiting, or able to forge the application's own internal markers;
      2. **stored / indirect injection**: untrusted content persisted somewhere a
         *different* user's or a later LLM call will read it (KB, summaries, memory, RAG
         documents), without human review before it becomes trusted;
      3. LLM output used without validation to send messages, change routing or state,
         write data, call tools, or emit links or URLs to end users;
      4. LLM output able to carry data the requester should not see (other users' data,
         internal notes, system prompt);
      5. tool or function definitions whose arguments the model controls and that reach
         data or actions beyond the requester's own scope.
    - Severity guidance added: (2) reaching other users → HIGH; (3)/(5) reaching
      state-changing actions → HIGH; (1) newly introduced → MEDIUM unless it chains
      into (2), (3) or (5).
  - **C4 Pre-existing.** The sentence "Do not comment on existing security concerns" is
    replaced with: report issues this diff introduces or makes newly reachable. A
    HIGH-confidence existing vulnerability on a code path the diff touches may be
    reported, tagged `[pre-existing]` with base evidence (C2). Upstream filtering
    applies to it unchanged.
  - **C5 Filters see the AI-input category.** START ANALYSIS step 2 also hands each
    false-positive filter sub-task the LLM / AI Input Safety category and its severity
    guidance. Without it, a filter applying only FALSE POSITIVE FILTERING could discard
    a prompt-injection finding as "lack of hardening".

### 3.3 `lib/security-review.sh` (new)
**The review's own configuration is read from `${ORIG_BRANCH}`, never from the branch
under review.** Otherwise a ship, or an autonomous fix-plan trying to clear a security
blocker, could relax its own review in the same diff. This is the usual CI rule that
review definitions run from the base branch.

- `security_review_enabled <orig_branch>` — exit 0 unless
  `git show <orig_branch>:.claude/ship-config.yml` has `security_review: off`. Default
  on; a missing file on base means on. A `security_review: off` that exists only on the
  branch has no effect.
- `security_review_render <orig_branch> <out_file>`:
  - Exit 2 if `<orig_branch>` does not resolve (`git rev-parse --verify`) or the
    template is missing.
  - Otherwise write `PROMPT.md` with `{{orig_branch}}` substituted.
  - If `git show <orig_branch>:docs/SECURITY_REVIEW.md` succeeds, append its content
    under `## REPOSITORY-SPECIFIC NOTES`.
  - If the diff (`git diff --name-only <orig_branch>...HEAD`, root-anchored `:/`
    pathspecs so the cwd does not matter) touches `docs/SECURITY_REVIEW.md`,
    `.claude/ship-config.yml` or `.claude/commands/ship-next.md`, append under
    `## CHANGES TO THIS REVIEW'S OWN CONFIGURATION`: "this diff modifies `<path>`; the
    change takes effect only after merge — review it as part of this pass."
  - Echo the out path. No git writes, no network.
- `security_review_output_check <file>` — exit 0 if the file is exactly
  `No security findings.`, or has at least one C2 finding line and **every** other line
  is blank or an indented detail line. Exit 3 otherwise, including a missing file. An
  upstream `# Vuln 1` block, a bulleted `- 🔴 …` or a bold `**HIGH**` line could hold a
  finding the parser counts as zero; one well-formed line elsewhere does not excuse it.
  - A finding line's marker and tag must agree (`🔴 [blocking]`, `🟡 [important]`,
    `🟢 [nit]`).
  - A detail line may not state a severity in any case or spelling (a marker, a tag,
    the word `severity`, a bold `**HIGH**`-style label), and may not be an indented
    heading such as `# Vuln 2`.
  - It calls `command grep`, never plain `grep`: step 1.6 sources it into Claude
    Code's shell, where `grep` is a ugrep wrapper whose `-vq` exits 1 even when a line
    does not match (§8 R6).
- `PRE_EXISTING_RE` — the one position the tag counts in: at the start of a finding
  line, right after the severity tag (`🔴 [blocking] [pre-existing] …`). Quoted in a
  description, inside a path or in other case, `[pre-existing]` is plain text and the
  finding counts as this ship's own. `pre_existing_lines <file>…` prints those lines.
- `pre_existing_key <finding-line>` — echoes a stable key for a `[pre-existing]`
  finding: `<file>:<category>` when a `[security:<category>]` tag is present, else
  `<file>:<first 40 bytes of the description, lowercased>`, with any partial UTF-8
  character at the cut dropped. Carriage returns are stripped first, so a CRLF report
  gives the same key.
- `pre_existing_tracked <key>` — exit 0 if some `docs/ideas/*.md` already contains
  `(pre-existing-key: <key>)`. The parentheses delimit the key, so `a.py:sql` never
  matches `a.py:sql_injection`.
- `pre_existing_strip_unverified <base> <file>…` — in place, drops the tag from every
  anchored pre-existing line whose cited file does not exist on `<base>`, or that cites
  no file. A file the diff created cannot hold a pre-existing defect. Exit 2 when
  `<base>` does not resolve.
- The `pre_existing_*` functions live in `lib/pre-existing.sh`, because pre-existing
  findings come from both reviews.
- The template path resolves via `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/security-review/PROMPT.md`,
  the same sibling-resolution pattern R-001 used.

### 3.4 `lib/code-review-parse.sh` — multiple files, pre-existing, no "00"
- Accepts **one or more** files and counts across all of them. One file behaves exactly
  as today. Exit 2 if any file is missing. Files are joined with `awk 1`, so a report
  without a trailing newline cannot swallow the next report's first finding.
- Lines matching `PRE_EXISTING_RE` (§3.3) are **excluded** from BLOCKING, MAJOR, MINOR
  and PRAISE, and counted in a new `PRE_EXISTING_COUNT`. Nothing else is excluded.
- New `SECURITY_COUNT`: non-pre-existing **finding lines** (they start with a severity
  marker) that carry `[security:`. Prose and detail lines that name a category do not
  count.
- Every counter prints a single integer. The `grep -c … || echo 0` pattern, which
  printed `00`, is fixed.
- **Verification of the tag:**
  - *Mechanical (step 1.6):* `pre_existing_strip_unverified "$ORIG_BRANCH"` runs on both
    reports. A tag that cites a file absent on the base branch, or no file, is dropped.
  - *Prose:* the Phase 6 session also confirms with `git show ${ORIG_BRANCH}:<file>`
    that the cited code exists there **unchanged**. If not, it drops the tag by hand.

### 3.5 `commands/ship-next.md` Phase 6 (and touch points)
- **0.5(c)** `review-extra-checks.md` gains:
  `[pre-existing]` — the defect exists on `${ORIG_BRANCH}` and this diff neither
  introduces nor worsens it; add a `Base evidence:` line.
- **New step 1.5 (inside the loop, every attempt)**, after code-review-skill writes
  `$REVIEW_OUT`. It is **its own executable `bash` block**, so it can be block-tested;
  the surrounding loop fence stays pseudo-code as today. It:
  - starts with `: "${ORIG_BRANCH:?}" "${ID:?}" "${attempt:?}"`, because these are set
    earlier and blocks do not share a shell;
  - removes `SEC_OUT` (`/tmp/ship-next-security-${ID}-${attempt}.md`) **before anything
    else**, so a report left by an earlier run can never stand in for this one;
  - sources `lib/security-review.sh`; a failed source halts (exit 1, "lib is missing").
    It must never fall through to the disabled branch;
  - if `security_review_enabled "$ORIG_BRANCH"`:
    - writes `on` to `.ship/security-review-state`;
    - renders to `.ship/security-review-prompt.md`;
    - the session follows that prompt (the finder sub-task, then parallel filter
      sub-tasks) and writes the result to `SEC_OUT`;
  - if disabled: writes `off` to `.ship/security-review-state`, `No security findings.`
    to `SEC_OUT`, and prints `security review: off (ship-config on <ORIG_BRANCH>)`.
- **New step 1.6** (its own block) guards `ORIG_BRANCH`, `REVIEW_OUT`, `ID`, `attempt`,
  sources both libs with a check, runs `security_review_output_check`, then
  `pre_existing_strip_unverified "$ORIG_BRANCH" "$REVIEW_OUT" "$SEC_OUT"`.
- **The loop** removes `REVIEW_OUT` and `SEC_OUT` at the top of every attempt, so a
  skipped step 1.5 cannot leave an earlier run's report in place. It then parses
  both files: `PARSED=$(code-review-parse.sh "$REVIEW_OUT" "$SEC_OUT") || exit 1`, then
  `eval "$PARSED"`. A failed parse must stop the gate: `eval` of an empty string
  succeeds and leaves `BLOCKING_COUNT` unset.
- **The security pass never fails open:**
  - **Render fails (exit 2):** Phase 6 halts (exit 1) with a hint, the same way a
    missing code-review-skill halts. A missing lib or template usually means the local
    skill checkout is stale. A fix-plan cannot repair that, so it must not consume
    review attempts.
  - **Malformed output:** `security_review_output_check` returns 3 → re-run the pass
    once. Still 3 → halt with the file path.
- **Scope of the block rule:** only the new blocks guard `ORIG_BRANCH`. Persisting
  `ORIG_BRANCH` for older blocks is a follow-up. The existing `MERGE_MODE` structural
  test is unchanged.
- **Blocker printing, step 4 majors and fix-plans** include findings from both files,
  minus the `PRE_EXISTING_RE` lines.
- **New step 4.5 Pre-existing findings** (after majors). Never blocks.
  - For each `pre_existing_lines "$REVIEW_OUT" "$SEC_OUT"` line, compute
    `pre_existing_key`.
  - If `pre_existing_tracked` says it is already tracked, show
    `already tracked: <key>` and skip it.
  - Otherwise:
    - Interactive: offer `[I]dea-NNN / [S]kip`.
    - Auto: create the IDEA via `/ship-idea --during-build … --related-roadmap-item "$ID"`.
  - The IDEA description ends with `(pre-existing-key: <key>)`, so the next ship that
    hits the same defect skips it. This is Anthropic's "no repeat
    findings" rule, applied across ships.
- **Phase 7 body / Phase 9 summary** gain one line:
  `Security review: blocking 0 ✓ (security findings: N, pre-existing: N)`. When
  `$WORKTREE/.ship/security-review-state` says `off`, the line says
  `off (ship-config on <ORIG_BRANCH>)` instead, so a landed commit never claims a
  review that did not run. Phase 9 step 0 copies the state file to
  `/tmp/ship-<ID>-security-review-state` (or removes a stale copy), and step 4 reads
  that copy. Step 1 removes the worktree first, and step 4 is its own shell, so a shell
  variable set in step 0 would be gone.
- **Interactive blocker printing** first drops each pre-existing finding together
  with its indented detail lines (awk reading `PRE_EXISTING_RE` through `ENVIRON`),
  then prints the blockers with context.
- **Step 4** uses `grep -h`, and only finding lines become IDEAs. Without `-h`,
  two-file output is prefixed with file names and the anchored pre-existing filter
  removes nothing. A removed pre-existing finding also leaves its detail lines behind,
  and those must never be filed as majors.
- **Kill switch:** `security_review: off` in `.claude/ship-config.yml` **on the base
  branch** (§3.3).

### 3.6 README
The ship-workflow README documents the security pass, the kill switch, and
`docs/SECURITY_REVIEW.md`, with an example of what a repo puts in it.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `security_review_enabled` | `security_review_enabled <orig_branch>` | exit 0 unless `<orig_branch>:.claude/ship-config.yml` says `security_review: off`; default on; the branch's own copy is ignored |
| `security_review_render` | `security_review_render <orig_branch> <out>` | writes the vendored prompt with `{{orig_branch}}` substituted and no `origin/HEAD`; appends `<orig_branch>:docs/SECURITY_REVIEW.md` under `## REPOSITORY-SPECIFIC NOTES` when it exists there; flags a diff that touches `docs/SECURITY_REVIEW.md`, `.claude/ship-config.yml` or `.claude/commands/ship-next.md` (root-anchored, any cwd); exit 2 on an unresolvable branch or missing template; no git writes |
| `security_review_output_check` | `security_review_output_check <file>` | exit 0 for `No security findings.`, or ≥1 C2 finding line (marker and tag agreeing) with every other line blank or an indented detail line that carries no severity; exit 3 otherwise, including a missing file; the same result in bash and in Claude Code's shell |
| `PRE_EXISTING_RE` / `pre_existing_lines` | `pre_existing_lines <file>…` | matches the tag only right after a leading severity tag; prints those lines; no output (exit 0) when none |
| `pre_existing_key` / `pre_existing_tracked` | `pre_existing_key <line>` → key; `pre_existing_tracked <key>` | key is `<file>:<category>` or `<file>:<desc40>` (valid UTF-8); tracked iff some `docs/ideas/*.md` contains `(pre-existing-key: <key>)` |
| `pre_existing_strip_unverified` | `pre_existing_strip_unverified <base> <file>…` | in place, drops the tag from anchored lines citing a file absent on `<base>` or no file; leaves every other line byte-identical; exit 2 on an unresolvable base |
| vendored prompt | `templates/security-review/PROMPT.md` | contains upstream hard exclusions 1–13 and 15–17, all 12 precedents, and the < 8 cutoff; lacks exclusion 14; contains the AI-input checklist and the C2 output format; names its upstream commit and license |
| `code-review-parse.sh` | `code-review-parse.sh <file>…` | counts summed across files, line boundaries kept; `PRE_EXISTING_RE` lines excluded from the four severity counts and counted in `PRE_EXISTING_COUNT`; `SECURITY_COUNT` counts non-pre-existing finding lines carrying `[security:`; every value a single integer; exit 2 on a missing file; one-file output identical to today for input without the new tags |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a review file with `🔴 [blocking] [pre-existing] a.py:3 — x` and `🔴 [blocking] b.py:4 — y` | `code-review-parse.sh f` | `BLOCKING_COUNT=1`, `PRE_EXISTING_COUNT=1` |
| AC-2 | two review files with one blocker each | `code-review-parse.sh f1 f2` | `BLOCKING_COUNT=2` |
| AC-3 | a review file with no findings | `code-review-parse.sh f` | every count is exactly `0`, never `00` |
| AC-4 | any existing one-file fixture in `test_code-review-parse.bats` | parsed | output unchanged |
| AC-5 | a repo on branch `ship/R-9-x` off `main` | `security_review_render main out` | `out` contains `git diff main...HEAD`, not `origin/HEAD`; has the AI-input checklist; lacks exclusion 14's sentence; has `🔴 [blocking] [security:` in its format |
| AC-6 | `docs/SECURITY_REVIEW.md` exists on `main` / only on the branch / absent | render against `main` | its `main` text appears under `## REPOSITORY-SPECIFIC NOTES` / no notes heading, and the "changes to this review's own configuration" note names it / no such heading |
| AC-7 | `security_review_render no-such-branch out` | — | exit 2, `out` not written |
| AC-8 | no config on `main` / `security_review: off` on `main` / off only on the branch | `security_review_enabled main` | 0 / 1 / 0 |
| AC-9 | the vendored prompt | inspected | upstream exclusions 1–13 and 15–17 and the 12 precedents present (key phrase per item); exclusion 14 absent; upstream commit `0c6a49f1fa56` and "Copyright (c) 2025 Anthropic" named; `LICENSE.upstream` is MIT |
| AC-10 | output files: `No security findings.` / one C2 line / upstream `# Vuln 1:` + `* Severity: High` / empty / one C2 line plus an unindented `- 🔴 …` line | `security_review_output_check` | 0 / 0 / 3 / 3 / 3 |
| AC-12 | `docs/ideas/IDEA-007.md` contains `(pre-existing-key: a.py:prompt_injection)`; finding `🔴 [blocking] [pre-existing] [security:prompt_injection] a.py:3 — x` | `pre_existing_key` then `pre_existing_tracked` | key `a.py:prompt_injection`; tracked (exit 0) |
| AC-13 | ship-next Phase 6 step 1.5 block, run with `ORIG_BRANCH` unset | block-executed | exits non-zero before rendering anything |
| AC-14 | a code-review file whose last line `🟢 [nit] a.py:1 — x` has no trailing newline, and a security file starting `🔴 [blocking] [security:x] b.py:2 — y` | `code-review-parse.sh rev sec` | `BLOCKING_COUNT=1` |
| AC-15 | `🔴 [blocking] a.py:3 — quotes the text [pre-existing]` / `🔴 [blocking] [PRE-EXISTING] a.py:3 — x` | `code-review-parse.sh f` | `BLOCKING_COUNT=1`, `PRE_EXISTING_COUNT=0` for each |
| AC-16 | `🔴 [blocking] [pre-existing] new.sh:1 — x` where `new.sh` is absent on `main` | step 1.6 block-executed | the line loses `[pre-existing]` and counts as a blocker |
| AC-17 | a stale `SEC_OUT` from an earlier run / a missing `security-review.sh` | step 1.5 block-executed | the stale file is gone afterwards / exit 1 with "lib is missing", never "security review: off", and no `SEC_OUT` |
| AC-18 | `security_review: off` on `main` | step 1.5 then the Phase 7 body | `.ship/security-review-state` is `off`; the body says `Security review: off (ship-config on main)` |
| AC-19 | a missing review file | the loop's parse | Phase 6 stops (exit 1); the gate is not passed |
| AC-20 | a nit plus `- 🔴 [blocking] …`, checked with `grep` wrapped the way Claude Code wraps it / an indented `- 🔴 [blocking] …`, `**HIGH**` or `* Severity: High` detail / `🟢 [blocking] …` | `security_review_output_check` | 3 / 3 / 3 |
| AC-21 | the prompt's REQUIRED OUTPUT FORMAT example | `security_review_output_check` | 0 |
| AC-22 | a code review whose first major is `[pre-existing]` with a `Base evidence:` line, then a new major; a security report with one MEDIUM | step 4 (auto) block-executed | two IDEAs, one per new major; none from a detail line |
| AC-23 | `security_review: off` recorded in the worktree | Phase 9 step 0, then step 1 removes the worktree | the summary still says `off (ship-config on <ORIG_BRANCH>)` |
| AC-11 | ship-next Phase 6 | inspected and block-executed | the security step renders the prompt and the parse call takes both files; every block that reads `MERGE_MODE`/`ORIG_BRANCH` resolves it (existing structural test still passes); step 4.5 exists and never feeds `BLOCKING_COUNT` |

## §5 Rollout
Ships to ai_system `main`. It is live in a repo once the local skill checkout
includes it (see the stale-checkout note in the brainstorm). langlive gets prompt
injection coverage immediately, because the AI-input section is always on.
Repo-specific accuracy improves when langlive adds `docs/SECURITY_REVIEW.md`
(follow-up).

## §8 Known risks
- **R1 Drift from upstream.** The vendored copy is pinned at `0c6a49f1fa56`. Upstream
  improvements are not picked up automatically. Mitigation: the header names the
  commit; re-sync is a manual follow-up when upstream changes.
- **R2 Cost.** Each review attempt adds a finder sub-task plus one filter sub-task per
  candidate. At most 3 attempts per ship.
- **R3 Pre-existing as escape hatch.** The tag counts only in its anchored position,
  and step 1.6 mechanically drops it when the cited file is absent on the base branch.
  Whether the cited code is *unchanged* there is still LLM judgement plus the prose
  `git show` check (§3.4).
- **R4 False negatives on business logic.** The prompt sees the diff plus whatever
  context the finder reads. Stored-injection paths that span several modules (like
  langlive's KB) are only caught when the diff touches them. The KB path itself is a
  pre-existing item for langlive.
- **R5 Command-argument substitution.** Claude Code replaces `$0`, `$1`, … in command
  files with the invocation's arguments. New Phase 6 bash must not use positional
  parameters (`$1`, `$#`, `shift`, `set --`). The existing ones are a separate
  follow-up.
- **R6 Claude Code's grep wrapper.** Command blocks run in Claude Code's zsh, where
  `grep` is a shell function that calls an embedded ugrep. Most flags behave like
  grep, but `-vq` does not: it exits 1 even when a line does not match. bats runs under
  bash and cannot see this, so lib functions that a block sources use `command grep`
  wherever a flag's exit status matters this way. A test emulates the wrapper.
