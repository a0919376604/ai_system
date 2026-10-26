---
date: 2026-10-27
updated: 2026-10-27
type: learning
id: R-023
tags: [learning, ai_system, ship-next, auto-merge, gitlab, glab]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-023
shipped: true
shipped-date: 2026-10-27
---

## For future Claude
> R-023: on GitLab, R-021's auto-merge now goes through the merge API, with
> `merge_when_pipeline_succeeds=true` (16.x), `auto_merge=true` (17.11+), `squash` and
> the reviewed `sha`. It trusts the response, not the exit status.
>
> The cause: `glab mr merge --auto-merge` (glab 1.99) sends only `auto_merge`. GitLab
> 16.11.3 ignores that and merges at once, which is how line-oa !311 merged with its
> pipeline still running.

Merged as GitHub PR #2 (squash `e85e8be2`) by leric after review — a one-way door.

## What Shipped
- `forge_automerge_cmd <url> [<sha>]`: the glab API form; a non-hex sha is refused
  before the command is eval'd.
- `sn_auto_merge <url> [<sha>]`: reads `state` and the scheduling flag from the
  response:
  - opened and scheduled → ok;
  - merged after a successful pipeline → ok;
  - merged mid-pipeline → `ERROR`, return 1;
  - anything else → WARN.
- `sn_land` passes `git rev-parse "$BRANCH"`.
- The tests' forge stub plays the API.

## Key Decisions
- leric: 「開R230」, read as R-023.
- Send both parameter names, because the server version varies.
- The response is the guard.
- Small-change lane.
- Door: one-way.

## What Changed From Plan
- Small-change lane, one review attempt.
  - The Spec review raised one nit, the extra sha check. It is kept: it validates input
    at an eval boundary.

## Bugs
- **R-021's auto-merge skipped CI on GitLab < 17.11.** Its tests used a stub that "merged
  when told", so a server-version difference was invisible.
  - Found when !311 merged mid-pipeline. CI then passed, so nothing broke.

## Lessons → checks
- A merge-gating CLI call must be verified from the server's response, not its exit
  code.
  - Enforced by `tests/test_ship-next-door.bats::auto-merge: a merge that lands while the pipeline runs is an ERROR`.
  - Proof: red at 82925b6 (exit 1) · green at e85e8be.

## Reusable Patterns
- **Check the server's version before trusting a CLI flag that maps to a newer API
  field.** `glab api version` answered it in one call.

## Technical Debt
- The behaviour has not been proven on a real 16.11 server without a throwaway MR. The
  response read-back is the guard.
- The gh path still trusts the exit status. No mr-mode GitHub repo exists.

## Future Follow-ups
- On the first line-oa two-way ship after this merges, check that the MR shows "merge
  when pipeline succeeds".
