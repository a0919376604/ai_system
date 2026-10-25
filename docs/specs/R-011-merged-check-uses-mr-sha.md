---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-011
status: draft
tags: [ship-workflow, ship-land, forge]
ai-first: true
---

## For future Claude
> `land_is_merged` proved containment by fetching `refs/merge-requests/<iid>/head`
> (GitLab) / `refs/pull/<n>/head` (GitHub). GitLab deletes MR head refs some time after
> the merge (line-oa: 96 refs left; !260, merged 2026-10-09, had none by 10-25), so a late
> `/ship-land` read an old merged review as open. The forge API already returns the head
> commit (`sha` / `headRefOid`); that commit was pushed from this clone, so it is usually
> a local object — check containment against it first, fetch the ref only when it is not.

## Decisions
- leric, 2026-10-25: 「好 修」after the worktree cleanup surfaced it (36 of 38 merged ships matched by API sha; 0 by ref).
- Small-change lane (my call): one function, no new seam; no plan file.
- Order: API head sha (local object) → ref fetch → ancestry against origin/<base>. Containment semantics unchanged.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `land_is_merged` | `land_is_merged <branch> <base>` | Exit 0 when a merged review's head (from the API sha if it is a local commit, else from the fetched head ref) contains the local tip, or the tip is in `origin/<base>`; else 1; 2 on usage. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | glab reports a merged MR whose `sha` is a local commit containing the tip; origin has no MR refs | `land_is_merged` | 0 |
| AC-2 | gh reports a merged PR whose `headRefOid` is a local commit containing the tip; no `refs/pull` | `land_is_merged` | 0 |
| AC-3 | API sha not a local object, no refs, tip not in origin/main | `land_is_merged` | 1 |
| AC-4 | existing land_is_merged tests | run | pass |
