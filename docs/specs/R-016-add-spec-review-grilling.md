---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-016
status: draft
tags: [ship-next, review, spec-review, brainstorm, grilling]
ai-first: true
---

## For future Claude
> Phase 6 reviewed the diff against coding standards and security only. Nothing checked
> it against the spec, so a missed or misread acceptance criterion could ship as long as
> the code was clean. R-016 adds a Spec review, after Matt Pocock's two-axis
> `code-review` skill: in every review attempt, a sub-agent compares the diff with the
> spec, in parallel with the code review.
> - Missing or wrong acceptance criteria block.
> - Unrequested behaviour is tagged `[ponytail:yagni]`.
>
> R-016 also changes how Phase 3 asks questions, after Pocock's `grilling` skill.
> - Each round asks every question that can be asked now, numbered, each with a
>   recommended answer.
> - Facts are looked up rather than asked.
> - Auto mode takes the recommended answer, not "option 1".
>
> Research: vault `10 Projects/ai_system/Research/pocock-pstack-into-ship-workflow.md`.

## Goals
- **G1.** Every Phase 6 review attempt runs a Spec review next to code-review-skill.
  - Its input is the spec in full and `git diff <ORIG_BRANCH>...HEAD`.
  - Its findings feed the same counts, blocker gate, fix-plan and IDEA filing as the
    code review's.
- **G2.** The Spec review never fails open. A missing, empty or malformed report stops
  the gate; it never parses as zero.
- **G3.** The ship log row and the auto summary show how many spec gaps the review found.
- **G4.** Phase 3 asks clarifying questions in grilling rounds. Auto mode answers each
  with its recommended answer and logs it.

## Non-goals
- A second model as reviewer. That is R-019.
- Changing code-review-skill, superpowers or any file outside this repo. The grilling
  format and the Spec reviewer's prompt are passed as context, as `## Seams` is today.
- Grilling in Phase 4's writing-plans.
- Renaming the existing code review to a "Standards axis".

## Anti-goals
- **A Spec review that blocks on things the diff cannot show.** Example: a criterion
  about what the operator sees in Obsidian. The reviewer reports a gap only with
  evidence. A criterion already met by code on the base branch is not missing.
- **A format so loose that a missing criterion can be tagged `[nit]` or `[pre-existing]`
  and slip past the gate.**

## Design

### Spec review (Phase 6)
- **Prompt.** `sn_spec_review_render <worktree>` writes `.ship/spec-review-prompt.md`,
  reading `ID`, `SLUG` and `ORIG_BRANCH` from `.ship/state.env`. The prompt tells a
  read-only sub-agent:
  - **Inputs.** Read `docs/specs/<ID>-<SLUG>.md` in full. Read the diff with
    `git diff <ORIG_BRANCH>...HEAD`.
  - **What to check.** The spec's acceptance criteria: Given-When-Then rows, `AC-N`
    rows, or a "done when" line. With no such rows, check its stated requirements.
  - **Missing, partial or wrong** → `🔴 [blocking] [spec:missing] <what>` or
    `🔴 [blocking] [spec:wrong] <what> — <file>:<line>`. Each is followed by an indented
    `Spec: "<the spec line, quoted>"` line.
  - **Behaviour the spec did not ask for** →
    `🟢 [nit] [spec:extra] [ponytail:yagni] <what> — <file>:<line>`, or `🟡 [important]`
    when it adds surface area (a flag, an option, a public function).
  - **Before reporting a criterion as missing,** look for it in the worktree, not only
    in the diff. A criterion met by existing code is not missing.
  - **Never tag a spec finding `[pre-existing]`.**
  - **Nothing found** → the single line `No spec gaps.`
  - Write the report, and nothing else, to the path Phase 6 gives.
- **Check.** `sn_spec_review_check <report>` accepts a report only when:
  - every non-blank, non-indented line is either a spec finding line or exactly
    `No spec gaps.`;
  - there is at least one such line;
  - every `[spec:missing]` / `[spec:wrong]` line is 🔴/`[blocking]` and is followed by
    an indented `Spec:` line;
  - every `[spec:extra]` line carries `[ponytail:yagni]` and is not blocking;
  - no finding line carries `[pre-existing]`;
  - no indented line starts with a severity marker (🔴🟡🟢🎉) or a `[` tag, so a
    finding cannot hide as a detail line.

  These rules apply to finding lines only. Text inside an indented `Spec:` quote is
  exempt, because a spec about the review pipeline may itself contain these tags.
  Otherwise it prints the first offending line and returns non-zero. It uses awk, not
  grep, because Claude Code's grep is ugrep (see R-003).
- **Phase 6 wiring.** Each attempt:
  1. Sets `SPEC_OUT=/tmp/ship-next-spec-${ID}-${attempt}.md` and removes any stale copy,
     together with the other two reports.
  2. Renders the prompt and runs the Spec sub-agent in parallel with the code review.
  3. Checks `SPEC_OUT`. On failure, re-runs the sub-agent once; a second failure stops
     Phase 6.
  4. Parses `"$REVIEW_OUT" "$SPEC_OUT"`. Once that reaches 0 blockers, parses
     `"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`.

  The interactive blocker print, the fix-plan and step 4's major filing also read
  `SPEC_OUT`. The first attempt's `SPEC_GAP_COUNT` is saved as `SPEC_GAPS_FOUND` in
  `.ship/state.env`, only when it is not already set. A `--resume` or an extra
  interactive cycle restarts the loop at attempt 1, and must not overwrite the real
  first count with the post-fix 0. A shipped run always ends with 0 gaps, so the first
  attempt's count is the useful number.
- **Counting.** `code-review-parse.sh` adds `SPEC_GAP_COUNT`: finding lines (severity tag
  at line start) carrying `[spec:missing]` or `[spec:wrong]`. Extras are already counted
  by `PONYTAIL_COUNT` and by severity. Indented `Spec:` quote lines are dropped before
  any counting, so quoted spec text cannot add to an unanchored counter
  (`[ponytail:…]`, `**Severity:**`).
- **Reporting.**
  - `sn_log`'s default row gains `spec_gaps=${SPEC_GAPS_FOUND:-0}` after `ponytail=`.
  - `sn_summary` gains
    `• spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed`.

### Grilling rounds (Phase 3)
Phase 3 step 1's invocation context adds the following. It overrides the brainstorming
skill's one-question-per-message habit; the superpowers file stays as it is.
- Ask in rounds.
  - Each round asks every question whose prerequisites are settled, numbered.
  - Each question carries your recommended answer and is worded so "yes" accepts it.
  - A question that depends on one still open in this round waits for the next round.
- Facts are yours to find. Dispatch a sub-agent rather than asking the operator anything
  you could look up. Only decisions go to the operator.
- In auto mode, every question is answered with its recommended answer and logged as
  `brainstorm Q<N> auto-picked recommended answer` with the question and the answer.

The `--auto:yes` argument description says "recommended answer" instead of "option 1".

## Decisions
- leric, 2026-10-26: 「好 先存 然後開Roadmap」, then 「Ship next R016 auto」. This
  covers the research recommendations 1 and 3 as one item (the Spec review and grilling
  rounds).
- My call (auto Q1): the prompt is rendered by a lib function, like
  `review-extra-checks`. It is not a template file or prose in the command; one heredoc
  is the fewest moving parts.
- My call (auto Q2): the format is fixed and checked mechanically, failing closed (G2).
  Missing and wrong criteria must be blocking and must quote the spec. Extras must carry
  `[ponytail:yagni]` and never block on their own, as in R-015.
- My call (auto Q3): the log and summary show attempt 1's gap count. The final count is
  always 0 on a shipped run.
- My call (auto Q4): ship-next sets no round cap. The global CLAUDE.md's "about three
  rounds, then state the assumption" already binds Phase 3 on this machine.
- My call (auto Q5): the Spec review runs every attempt, in parallel with the code
  review. A fix can open a new gap.
- My call (builder check): the format rules bind finding lines only. Indented lines may
  not start with a severity marker or tag (as `security_review_output_check` already
  requires). `Spec:` quotes are exempt and are dropped before counting.
- My call (builder check): `SPEC_GAPS_FOUND` is written once. Resume and extra cycles
  keep the first count.
- My call: report lines use the same severity tags as the code review, so
  `code-review-parse.sh` counts them unchanged. Only one counter is new.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_spec_review_render` | `sn_spec_review_render <worktree>` (reads `.ship/state.env`) | Writes `<worktree>/.ship/spec-review-prompt.md`. It names the spec path, the `git diff <ORIG_BRANCH>...HEAD` command, the three `[spec:…]` tags with their required severities, the `Spec:` quote line and the `No spec gaps.` line. Returns 1 with a message, and writes nothing, when the spec file is absent. |
| `sn_spec_review_check` | `sn_spec_review_check <report>` | Returns 0 for a report in the format above; non-zero, printing the offending line, for a missing or empty file, a prose line, a missing/wrong finding that is not blocking or lacks its `Spec:` line, an extra without `[ponytail:yagni]` or marked blocking, a `[pre-existing]` tag on a finding line, or an indented line starting with a severity marker or `[` tag. `Spec:` quote text is exempt. Same result under bash and zsh. |
| `code-review-parse.sh` | existing | Also prints `SPEC_GAP_COUNT=<n>`: line-start finding lines carrying `[spec:missing]` or `[spec:wrong]`. Indented `Spec:` lines are not counted by any counter. The other counters are unchanged for input without spec tags or `Spec:` lines. |
| `sn_log` / `sn_summary` | existing | The default log row contains `spec_gaps=<SPEC_GAPS_FOUND or 0>`. The auto summary contains `spec review: <n> gap(s) found on attempt 1`. |
| ship-next Phase 6 | command text | Each attempt removes a stale `SPEC_OUT` and runs the Spec review. The pre-security parse includes `SPEC_OUT`, and the post-security parse includes all three reports. The blocker print and the major filing read `SPEC_OUT`. The first attempt saves `SPEC_GAPS_FOUND` only when unset. |
| ship-next Phase 3 | command text | Step 1 requires grilling rounds and sub-agent fact finding. Auto mode logs `auto-picked recommended answer`. "option 1" appears in neither Phase 3 nor the `--auto:yes` description. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a worktree whose state has `ID=R-9`, `SLUG=x`, `ORIG_BRANCH=main` and a `docs/specs/R-9-x.md` | `sn_spec_review_render` | `.ship/spec-review-prompt.md` contains `docs/specs/R-9-x.md`, `git diff main...HEAD`, `[spec:missing]`, `[spec:wrong]`, `[spec:extra]`, `[ponytail:yagni]`, `Spec:` and `No spec gaps.`; exit 0 |
| AC-2 | the same worktree without the spec file | `sn_spec_review_render` | non-zero exit with a message; no prompt file |
| AC-3 | a report with `🔴 [blocking] [spec:missing] X`, an indented `Spec: "…"` line, and `🟢 [nit] [spec:extra] [ponytail:yagni] Y — a.sh:3` | `sn_spec_review_check` | exit 0 |
| AC-4 | a report that is exactly `No spec gaps.` | `sn_spec_review_check` | exit 0 |
| AC-5 | a missing file; an empty file; a prose line; `[nit] [spec:missing]`; `[spec:wrong]` with no `Spec:` line; `[spec:extra]` without `[ponytail:yagni]`; `🔴 [blocking] [spec:extra] [ponytail:yagni]`; `🔴 [blocking] [pre-existing] [spec:missing]`; an indented `  🟢 [nit] [spec:missing] X` | `sn_spec_review_check` | non-zero for each, in bash and in zsh |
| AC-5b | AC-3's report whose `Spec:` quote contains `[pre-existing]` and `[ponytail:delete]` | `sn_spec_review_check` / `code-review-parse.sh` | exit 0 / `PONYTAIL_COUNT=1`, `PRE_EXISTING_COUNT=0` |
| AC-6 | the AC-3 report | `code-review-parse.sh` | `SPEC_GAP_COUNT=1`, `BLOCKING_COUNT=1`, `MINOR_COUNT=1`, `PONYTAIL_COUNT=1` |
| AC-7 | a code review with no spec tags | `code-review-parse.sh` | `SPEC_GAP_COUNT=0`; the other counters are unchanged |
| AC-8 | state with `SPEC_GAPS_FOUND=2` | `sn_log` (squash, default row) / `sn_summary` (AUTO=1) | the row contains `spec_gaps=2`; the summary contains `spec review: 2 gap(s) found on attempt 1` |
| AC-9 | ship-next.md | Phase 6 is read | `rm -f` covers `SPEC_OUT`; the parses are `"$REVIEW_OUT" "$SPEC_OUT"` and `"$REVIEW_OUT" "$SPEC_OUT" "$SEC_OUT"`; the blocker print and `MAJOR_LINES` read `SPEC_OUT`; the first attempt saves `SPEC_GAPS_FOUND` via `sn_state_set` only when it is unset |
| AC-10 | ship-next.md | Phase 3 and the `--auto:yes` line are read | step 1 requires numbered whole-frontier rounds with a recommended answer each and sub-agent fact finding; auto mode logs `auto-picked recommended answer`; no "option 1" remains in either |
| AC-11 | the full suite | `bats tests/` | green apart from the known cwd-guard failure in a linked worktree |

## Left to the builder
- The prompt's exact wording, within the rules above.
- Where in Phase 6 the new step sits (a numbered step next to 1.5/1.6), and how the
  loop shows "run the Spec sub-agent".
- A one-line mention in `claude-skills/ship-workflow/README.md` and the root README's
  Phase 6 row.
