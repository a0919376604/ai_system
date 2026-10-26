---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-020
tags: [learning, ai_system, ship-next, ship-body, roadmap, adhoc]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-020
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-020: the landed body is right without hand edits again.
> - `sn_done_when` reads a row's done-when from its whole `↳` block. Both readers use it:
>   the body and Phase 1's auto gate.
> - The body shows the Spec review count.
> - The body ends with `$SHIP_COAUTHOR` (the session's line), or with a co-author line
>   that names no model.
> - `--adhoc` writes a `↳ done when:` line, so `--adhoc --auto:yes` no longer trips its
>   own gate.
>
> This ship's own body was the first one generated correctly.

## What Shipped
- `lib/ship-next.sh`:
  - `sn_done_when <roadmap> <ID>`, an awk scan of the row's `↳` block, anchored on
    `**ID**`;
  - `sn_ship_body` uses it;
  - a `Spec review:` line;
  - the `${SHIP_COAUTHOR:-Co-Authored-By: Claude <noreply@anthropic.com>}` line.
- `commands/ship-next.md`:
  - step 3 passes `--done-when "$DONE_WHEN_ZH"`;
  - step 4.5 uses `sn_done_when`;
  - Phase 7 says to set `SHIP_COAUTHOR`.
- 4 tests. Suite: 662 tests; one known cwd-guard failure.

## Key Decisions
- leric: 「好」 to fixing the two `sn_ship_body` defects as an `--adhoc` item.
- One shared lookup: Phase 1's `grep -A2` had the same defect, one annotation later.
- The session sets `SHIP_COAUTHOR`. The fallback names no model, so it cannot go stale.
- The Spec review count goes in the body, after it was hand-added twice.
- `--adhoc` carries a done-when, and this ship needed one to start.
- Small-change lane, run inline with TDD.

## What Changed From Plan
- Small-change lane, so there was no plan. One review attempt:
  - the code review was inline (1 nit, 1 pre-existing);
  - the Spec review sub-agent found "No spec gaps.";
  - the security pass found nothing.

## Bugs
- **The body's done-when was empty since R-013.** `grep -A1` saw only the
  `↳ explain:` line.
- **Phase 1's `-A2` had the same latent defect.**
- **`--adhoc --auto:yes` was always refused by step 4.5.** `--adhoc` wrote no
  done-when.

## Lessons → checks
- Read a row's annotation from its whole `↳` block, never a fixed `grep -A<n>`.
  - Enforced by `tests/test_ship-next-lib.bats::ship body carries done-when past explain`.
  - Proof: red at 8c50b6c (exit 1) · green at 7eaff88.
- Never hard-code a model name in generated commit text.
  - Enforced by `tests/test_ship-next-lib.bats::no model name is hard-coded in the ship-next lib`.
  - Proof: red at 8c50b6c (exit 1) · green at 7eaff88.

## Reusable Patterns
- **When a lookup reads a fixed number of lines after an anchor, read the block
  instead.** Line counts drift as the format grows annotations.

## Technical Debt
- `DONE_WHEN_ZH="…"` is a placeholder the agent must fill, as `SUMMARY_ZH` is. Left
  unfilled, "…" passes the gate.
- [pre-existing] `ROW=$(grep …)` in `sn_ship_body` is never read. Not filed: there is no
  `docs/ideas/`.

## Future Follow-ups
- Drop the dead `ROW` line the next time `sn_ship_body` is touched.
