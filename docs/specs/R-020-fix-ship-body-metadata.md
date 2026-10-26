---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-020
status: draft
tags: [ship-next, ship-body, roadmap, adhoc]
ai-first: true
---

## For future Claude
> The landed commit body (`sn_ship_body`) lost its `↳ done when:` line after R-013.
> - The cause: rows got an `↳ explain:` line first, and the lookup used `grep -A1`.
> - Phase 1's auto gate uses `grep -A2` and breaks the same way once a row carries one
>   more annotation.
>
> The body also hard-coded `Co-Authored-By: Claude Opus 5`, and it never showed the
> R-016 spec review count. Both were hand-fixed in R-016 and R-017.
>
> `--adhoc` never wrote a `↳ done when:` line, so `--adhoc --auto:yes` was always
> refused by its own gate.

## Goals
- **G1.** One helper, `sn_done_when <roadmap> <ID>`, reads a row's done-when from its
  whole `↳` block. `sn_ship_body` and Phase 1 step 4.5 both use it.
- **G2.** The body's co-author line comes from `$SHIP_COAUTHOR` when set; otherwise
  `Co-Authored-By: Claude <noreply@anthropic.com>`. Phase 7 tells the agent to set it to
  the line its session prescribes.
- **G3.** The body shows
  `Spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed`.
- **G4.** `--adhoc` writes a `↳ done when:` line (`DONE_WHEN_ZH`) with the row.

## Non-goals
- Changing the Obsidian plugin's parser. It already reads the annotation list.
- Changing `roadmap-insert.sh`. It already takes `--done-when`.

## Decisions
- leric, 2026-10-26: 「好」 to fixing the two `sn_ship_body` defects found in R-016/R-017
  as an `--adhoc` item.
- My call (auto Q1): one shared lookup. Phase 1's `-A2` has the same defect class one
  annotation later.
- My call (auto Q2):
  - The session knows its own model, so it sets `$SHIP_COAUTHOR`.
  - The fallback names no model, so it cannot go stale.
- My call (auto Q3): the spec review count goes into the body. It was hand-added in both
  previous ships.
- My call (auto Q4): `--adhoc` carries a done-when, and this ship needed it to start.
- My call: small-change lane (one helper and about 50 lines), executor 2, TDD inline.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_done_when` | `sn_done_when <roadmap> <ID>` | Prints the text after `↳ done when: ` from the indented `↳` lines directly under the row containing `**<ID>**`. It prints nothing when there is none, and does not match `**<ID>0**`. It stops at the first line that is not a `↳` annotation. |
| `sn_ship_body` | existing | The body's `↳ done when:` line uses `sn_done_when`. It has a `Spec review:` line. Its last line is `$SHIP_COAUTHOR`, or `Co-Authored-By: Claude <noreply@anthropic.com>` when that is unset. |
| ship-next Phase 1 | command text | Step 4.5 uses `sn_done_when`. Step 3 passes `--done-when "$DONE_WHEN_ZH"`. Phase 7 tells the agent to set `SHIP_COAUTHOR`. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a row with `↳ explain:`, then `↳ done when: X`, then a row `**R-90**` | `sn_done_when <file> R-9` | prints `X` |
| AC-2 | a row `**R-90**` with done-when `Y`, and a row `**R-9**` with no done-when, followed by a row whose `↳ done when: Z` belongs to the next row | `sn_done_when <file> R-9` | prints nothing |
| AC-3 | AC-1's file in state | `sn_ship_body` | the body's first line is `↳ done when: X`; it has `Spec review: 2 gap(s) found on attempt 1, all closed` when `SPEC_GAPS_FOUND=2` |
| AC-4 | `SHIP_COAUTHOR` unset / set to `Co-Authored-By: T <t@x>` | `sn_ship_body` | the last line is `Co-Authored-By: Claude <noreply@anthropic.com>` / `Co-Authored-By: T <t@x>`; no `Opus 5` anywhere in `lib/` |
| AC-5 | ship-next.md | Phase 1 is read | step 4.5 calls `sn_done_when`; step 3's insert passes `--done-when "$DONE_WHEN_ZH"`; Phase 7 names `SHIP_COAUTHOR` |
| AC-6 | the full suite | `bats tests/` | green apart from the known cwd-guard failure |
