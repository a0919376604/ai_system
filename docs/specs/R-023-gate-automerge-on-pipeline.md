---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-023
status: draft
tags: [ship-next, auto-merge, gitlab, door]
ai-first: true
---

## For future Claude
> R-021's auto-merge ran `glab mr merge <iid> --auto-merge --squash --yes`. On line-oa's
> GitLab 16.11.3 that merged at once: !311 merged while its pipeline was still running.
> glab 1.99 sends `auto_merge`, which GitLab only understands from 17.11. Older servers
> ignore it and merge.
>
> R-023 calls the merge API itself. It sends `merge_when_pipeline_succeeds=true` (the
> 16.x name) and `auto_merge=true` (the 17.11+ name), then reads the response to check
> that the MR is still open and scheduled.

## Goals
- **G1.** For GitLab, `forge_automerge_cmd <url> [<sha>]` echoes
  `glab api --method PUT projects/:id/merge_requests/<iid>/merge --field merge_when_pipeline_succeeds=true --field auto_merge=true --field squash=true --raw-field sha=<sha>`.
  - The `sha=` part is present only when `<sha>` is given.
  - GitHub keeps `gh pr merge <url> --auto --squash`.
- **G2.** `sn_auto_merge <url> [<sha>]`, glab path, reads the API response:
  - `state` is `opened` and `merge_when_pipeline_succeeds` (or `auto_merge_enabled`) is
    true → set: return 0.
  - `state` is `merged` and the pipeline it saw was `success` → CI already passed:
    return 0.
  - `state` is `merged` while the pipeline was not `success` → print
    `ERROR: <url> merged before its pipeline finished — CI did not gate it` and return 1.
  - Anything else → WARN and return 1, leaving the merge to a human.
- **G3.** `sn_land` passes the reviewed head, `git rev-parse "$BRANCH"`, as `<sha>`.

## Non-goals
- Upgrading glab.
- The gh path.

## Decisions
- leric, 2026-10-27: 「開R230」 after I proposed R-023. I read it as R-023, digits swapped.
- My call (auto Q1): call the API directly with both parameter names, so the request
  works before and after GitLab 17.11.
- My call (auto Q2): the response is the guard. A stub cannot show what a real server
  does, which is why R-021's tests passed.
- My call (auto Q4): small-change lane.
- Door: one-way — it decides when line-oa skips a human; a wrong answer merges unreviewed code.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `forge_automerge_cmd` | `forge_automerge_cmd <url> [<sha>]` | glab: the API command of G1. gh: unchanged. Exit 1 when the forge is unknown or the MR has no iid. |
| `sn_auto_merge` | `sn_auto_merge <url> [<sha>]` | Returns 0 only for the two G2 success cases. Prints an `ERROR` when the MR merged before a successful pipeline. |
| `sn_land` | existing | Passes `git rev-parse "$BRANCH"` to `sn_auto_merge`. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a gitlab remote, url `…/merge_requests/42`, sha `abc` | `forge_automerge_cmd url abc` | the exact G1 command with `sha=abc` |
| AC-2 | stub glab: pipeline `running`, merge API answers `{"state":"opened","merge_when_pipeline_succeeds":true}` | `sn_auto_merge url abc` | 0, and the recorded call has `merge_when_pipeline_succeeds=true`, `auto_merge=true`, `sha=abc` |
| AC-3 | pipeline `running`, merge API answers `{"state":"merged","merge_when_pipeline_succeeds":false}` | `sn_auto_merge` | 1, with output containing `merged before its pipeline finished` |
| AC-4 | pipeline `success`, merge API answers `{"state":"merged"}` | `sn_auto_merge` | 0 |
| AC-5 | the full suite | `bats tests/` | green apart from the known cwd-guard failure |
