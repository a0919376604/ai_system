---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-022
tags: [learning, ai_system, ship-next, sn_land, glab]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-022
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-022: `sn_land` records the review URL by its shape, the last
> `…/merge_requests/<n>` or `…/pull/<n>`, instead of the last URL in the forge output.
> An outdated glab (1.99 vs 1.124) ends `mr create` with an upgrade-notice link, which
> `tail -1` had picked. Found while opening line-oa !310. It was the first ship routed by
> R-021: a two-way door, so it squashed.

## What Shipped
- `lib/ship-next.sh`: one `grep -oE` pattern in `sn_land`'s mr path.
- One test, run through the real `sn_land`:
  - an MR URL followed by the notice → the MR URL is kept;
  - the notice alone → "produced no URL".
- The forge stub takes `STUB_CREATE_OUT`.

## Key Decisions
- leric: 「好」.
- Match the review path shape, not the host, so self-hosted GitLab works.
- Small-change lane, inline TDD.
- Door: two-way. The run's own `sn_door` routed it to squash.

## What Changed From Plan
- The test-budget gate blocked attempt 1: 11000bp against a 6420bp limit. The two tests
  each repeated 8 setup lines.
- Attempt 2 merged them into one test with shared setup, 4333bp (major, not blocking).
- AC-2 lost its "no SHIP_REVIEW_URL written" clause. The state still holds the first
  run's URL, and exiting before the write is existing behaviour.

## Bugs
- **The review URL was the last URL of the forge output** (since R-008). With an
  outdated glab that is the upgrade notice. ROADMAP's `mr=` link was wrong, and R-021's
  auto-merge found no iid; it fell back safely to a human merge.

## Lessons → checks
- Pick a forge URL by its review path, never by its position in the output.
  - Enforced by `tests/test_ship-next-door.bats::the review URL is the merge_requests one, never glab's upgrade notice`.
  - Proof: red at 4cc45cf (exit 1) · green at d53f632.

## Reusable Patterns
- **A tiny fix with duplicated test setup trips the test budget.** Share the setup within
  one test before adding a second.

## Technical Debt
- glab is 1.99 against 1.124. Upgrading would drop the notice, but glab's CLI surface
  could change. Re-check `glab mr view/merge` usage after any upgrade.
- `sn_door` reasons are still split on "; " (seen in this ship's own output).

## Future Follow-ups
- None.
