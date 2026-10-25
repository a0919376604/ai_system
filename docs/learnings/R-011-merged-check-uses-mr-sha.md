---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-011
tags: [learning, ai_system, ship-workflow, ship-land, gitlab, zsh]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-011
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> GitLab deletes `refs/merge-requests/<iid>/head` some time after a merge. `land_is_merged`
> now checks the API's head sha (glab `sha`, gh `headRefOid`) as a local commit first —
> it was pushed from this clone — and fetches the ref only when that object is missing.

## What Shipped
- `land_is_merged`: API head sha → ref fetch → ancestry; containment semantics unchanged.
- zsh fix: loops over `$(printf '%s\n' "$var")` instead of bare `$var`.

## Key Decisions
- Small-change lane: one function, no plan (my call). Order of checks as above (leric approved "修").

## Bugs
- **zsh does not word-split a bare `$var`.** `for x in $list` runs once with the whole string. The lib runs in zsh (the Bash tool's shell). Use `$(printf '%s\n' "$list")` or a `while read` loop. R-008 shipped this bug in its `$ids` loop.
- Assumed forge refs are permanent; they are not on GitLab.

## Reusable Patterns
- **Verify a forge integration against the real forge, not only a fake.** The bats fakes always had the ref; production had already deleted it for most merged MRs.

## Technical Debt
- none new.

## Future Follow-ups
- none.
