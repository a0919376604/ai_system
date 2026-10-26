---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-016
tags: [learning, ai_system, ship-next, spec-review, grilling, review]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-016
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-016: every Phase 6 attempt now runs a **Spec review**, after Matt Pocock's two-axis
> `code-review`. A read-only sub-agent compares `git diff <base>...HEAD` with the spec
> (step 1.4).
> - Missing or wrong criteria block.
> - Extras are `[ponytail:yagni]`.
> - `sn_spec_review_check` rejects a malformed report before it is counted.
>
> Phase 3 now asks in **grilling rounds**: every answerable question, numbered, with a
> recommended answer. Auto mode takes that answer instead of "option 1".
>
> On its own ship the Spec review found a real blocker that code review had let through.

## What Shipped
- **`sn_spec_review_render <wt>`** writes `.ship/spec-review-prompt.md`.
- **`sn_spec_review_check <report>`** is one awk program that fails closed. It rejects:
  - prose lines;
  - a non-blocking or unquoted missing/wrong finding;
  - an extra without `[ponytail:yagni]`;
  - `[pre-existing]`;
  - an indented line posing as a finding;
  - findings mixed with `No spec gaps.`.
- **`code-review-parse.sh`**:
  - `SPEC_GAP_COUNT`;
  - indented `Spec:` quotes and their continuation lines are dropped before any counting.
- **Phase 6**:
  - step 1.4;
  - `SPEC_OUT=/tmp/ship-next-spec-<ID>-<attempt>.md`, included in `rm -f`, both parses,
    the blocker print, the fix-plan and step 4's majors;
  - `SPEC_GAPS_FOUND` is written once, from the first attempt.
- **Phase 9**: `spec_gaps=` in the log row; `• spec review: N gap(s) found on attempt 1,
  all closed` in the summary.
- **Phase 3**: the grilling-round requirement, and auto mode logging
  `auto-picked recommended answer`.
- **Docs**: both READMEs.
- **Tests**: 638 in the suite (+15); one known cwd-guard failure.

## Key Decisions
- leric: ship research items 1 + 3 together. Research note:
  `Research/pocock-pstack-into-ship-workflow.md`.
- The prompt is rendered by a lib heredoc, like review-extra-checks. A template file was
  the alternative; one heredoc has fewer moving parts.
- The report format is fixed and checked mechanically. Missing/wrong must block and
  quote the spec; extras never block alone.
- Log and summary carry the first attempt's gap count. The final count is always 0 on a
  shipped run.
- No round cap in ship-next: the global CLAUDE.md's three-round rule already applies.
- The Spec review runs every attempt, in parallel with code review.
- From the builder check:
  - format rules bind finding lines only, and `Spec:` quote text is exempt;
  - `SPEC_GAPS_FOUND` is write-once, so a resume or an extra cycle keeps the real first
    count.

## What Changed From Plan
- Codex (round 1, DONE_WITH_CONCERNS) recorded two repairs:
  - step 1.4's check block initializes the lib and `SPEC_OUT` itself. Command blocks run
    in fresh shells.
  - the existing security wiring tests got empty spec reports.
- It also flagged the multi-line quote limitation, which the review then raised as a
  blocker.
- The attempt-1 code review was done inline: the operator stopped a long reviewer agent
  as stuck.
- The one-blocker fix-plan (attempt 2) was also done inline: a 2-line parser fix plus a
  test. Starting codex for it would have taken about 10 minutes.
- Dogfood: this ship's Phase 6 used the new `sn_spec_review_render` from the worktree.
  The live checkout did not have it yet.

## Bugs
- **Multi-line `Spec:` quotes were counted** (`[spec:wrong]`, found by the new Spec
  review).
  - The parser dropped only the `Spec:` line.
  - Continuation lines holding `**Severity:** blocking` or `[ponytail:…]` reached the
    unanchored counters.
  - That gave a phantom blocker that no fix could clear.
  - Fix: drop the quote's indented continuation lines too, resetting per file.

## Reusable Patterns
- **A second review axis pays for itself immediately.** The defect sat in the plan's own
  prescribed code, and executor and code review both treated it as "per plan". Only a
  reviewer reading the spec's Seams row called it wrong.
- **Check that the reader accepts only what the writer can produce.** The checker
  accepted multi-line quotes, but the parser assumed single-line ones. Diff the accepted
  grammar against the counted grammar.
- **When the operator says a run is stuck, shrink the loop, not the gate.** Inline review
  plus an inline fix still went through every gate (parse, security pass, full suite).

## Technical Debt
- `sn_ship_body` reads `↳ done when:` with `grep -A1`. Since R-013 adds an `↳ explain:`
  line first, the landed body's done-when is empty. This ship filled it by hand. Phase 1
  uses `-A2` correctly.
- `sn_ship_body` hard-codes `Co-Authored-By: Claude Opus 5`. Fixed by hand in this
  body.
- Unanchored counters (`[ponytail:…]`) still count a finding whose prose quotes a tag.
  This is the pre-existing class; only `Spec:` quotes are exempt.
- The spec reviewer's nit: the checker rejects two shapes that the Seam row does not
  list (detail after a blank line; findings plus the sentinel). Kept on purpose, from
  the plan's Review Focus.

## Future Follow-ups
- Fix `sn_ship_body`'s done-when lookup (`-A3`, or match the row's block) and take the
  attribution line from the session.
- R-019 (Later): a cross-model reviewer for inline ships.
- Watch `spec_gaps=` in `_log.md`. If codex ships keep arriving with gaps, put the AC
  list into the run-plan prompt.
