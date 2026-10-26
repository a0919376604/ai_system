---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-022
status: draft
tags: [ship-next, sn_land, mr, glab]
ai-first: true
---

## For future Claude
> `sn_land` took the review URL as the last URL in the forge CLI's output
> (`grep -oE 'https?://…' | tail -1`). When glab is out of date (1.99 vs 1.124), its
> output ends with an upgrade notice link, `https://gitlab.com/gitlab-org/cli/-/releases/v1.124.0`.
> The ROADMAP then pointed at that link, and R-021's auto-merge could not find an MR
> iid in it. Found opening line-oa !310.

## Goals
- **G1.** `sn_land` keeps only URLs that name a review: a path ending in
  `/merge_requests/<digits>` (GitLab) or `/pull/<digits>` (GitHub). It takes the last
  such URL.
- **G2.** With no such URL, `sn_land` stops as today ("the review command produced no
  URL").

## Decisions
- leric, 2026-10-26: 「好」 to fixing this as an `--adhoc` item.
- My call (auto Q1): match the review path shape, not the host, so self-hosted GitLab
  works.
- My call (auto Q2): small-change lane, inline TDD.
- Door: two-way — a parsing fix in `sn_land`; reverting it restores today's behaviour.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_land` (mr path) | existing | `SHIP_REVIEW_URL` is the last `…/merge_requests/<n>` or `…/pull/<n>` URL in the forge output, ignoring every other URL. With none, it exits non-zero with the existing message. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a stub `glab mr create` that prints `https://g/grp/repo/-/merge_requests/42`, then a glab upgrade notice with `https://gitlab.com/gitlab-org/cli/-/releases/v1.124.0` | `sn_land` (mr) | state `SHIP_REVIEW_URL=https://g/grp/repo/-/merge_requests/42` |
| AC-2 | a stub that prints only the upgrade notice URL | `sn_land` (mr) | non-zero exit with `produced no URL` |
| AC-3 | the full suite | `bats tests/` | green apart from the known cwd-guard failure |
