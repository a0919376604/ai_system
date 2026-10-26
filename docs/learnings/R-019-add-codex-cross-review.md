---
date: 2026-10-27
updated: 2026-10-27
type: learning
id: R-019
tags: [learning, ai_system, ship-next, review, codex, cross-model]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-019
shipped: true
shipped-date: 2026-10-27
---

## For future Claude
> R-019: ships whose code Claude wrote (small-change lane, executor 1 or 2) get a second
> reviewer, `codex review --base <base>`, in Phase 6 step 1.3. This follows pstack's
> `interrogate` ("the adversarial signal comes from model diversity").
>
> - Findings are converted from codex's `- [Pn] title — /abs/path:a-b` blocks: P0/P1
>   block, P2 is important, P3 is a nit.
> - They are tagged `[codex]`, plus `[both]` when code review cited the same file within
>   ±3 lines, and appended to the code review report, so one parse counts them.
> - Codex-executed ships skip it. An unavailable codex only warns.

## What Shipped
- `lib/ship-next.sh`:
  - `sn_cross_review <worktree> <review_out>`: awk parser, `pwd -P` path stripping,
    `[both]` matching, and the state keys
    `CROSS_REVIEW` / `CROSS_REVIEW_COUNT` / `CROSS_REVIEW_BOTH`;
  - `xreview=` in the log row;
  - `• cross-review (codex):` in the summary.
- `commands/ship-next.md`: Phase 6 step 1.3, and the loop comment.
- 18 tests driven by a byte-for-byte capture of real codex output. Suite: 718 tests, the
  known cwd-guard failure only.

## Key Decisions
- leric: 「R19 auto」.
- Facts first: real `codex review` runs set the format.
  - A custom prompt is rejected together with `--base`/`--commit` (gstack's docs show
    the older CLI).
  - Findings come under `Full review comments:`.
  - Paths are absolute.
- Mapping: P0/P1 → blocking, P2 → important, P3 → nit.
- Append to the code review report. That means one count and the existing fix-plan path.
- `[both]` means the same file within ±3 lines.
- An unavailable codex warns, and the ship continues.
- Door: two-way. It landed by squash.

## What Changed From Plan
- The plan's first write failed: `docs/plans/` no longer existed, because compound had
  emptied it. The launcher stopped at reading the plan before codex started, so no run
  was wasted.
- Codex: 1 round, DONE_WITH_CONCERNS. It added `|| return 1` to new `[[ ]]` assertions
  after the hygiene check (R-017) flagged them.
- Review: 2 nits, no Spec gaps.

## Bugs
- None shipped.
- Two CLI facts were caught before writing code, by running the real tool. Both would
  have been invisible to a docs-based stub:
  - the `--commit` + prompt rejection;
  - the `--base` + prompt rejection.

## Lessons → checks
- Before stubbing a CLI, run it once and pin its real output and argument rules — judgment.

## Reusable Patterns
- **Run the real tool before writing the stub.** R-021 (glab URL), R-023 (glab
  auto-merge on 16.11) and R-019 (codex prompt flags) were all one real run away.

## Technical Debt
- `codex review` is read-only only by default (`sandbox: read-only` in the run). Pin it
  with `-c sandbox_mode="read-only"` (review nit).
- A codex title containing " — " is cut at its first dash (review nit).
- `CROSS_REVIEW=skipped` was set by hand on this ship, because it was codex-executed and
  the live skill predates step 1.3.

## Future Follow-ups
- Pin the sandbox. Then, on the first inline ship, compare the `[both]` rate with the
  code review's findings.
