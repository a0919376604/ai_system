---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-012
status: draft
tags: [ship-workflow, examples, launchd, vault-backup]
ai-first: true
---

## For future Claude
> `examples/launchd-autopush` installs the vault's 6-hourly git backup. On the real
> machine it silently stopped on 2026-06-15 (520 failed runs): macOS denies launchd jobs
> access to ~/Documents, and the script mis-reported that as "no origin remote". Two more
> bugs surfaced when it ran again: `git diff | head -3` under `pipefail` killed the script
> once a commit had many files, and pulling before committing always failed. R-012 brings
> the example in line with the fixed install and adds tests.

## Decisions
- leric, 2026-10-25: chose option 2 — wrap the script in `SecondBrainAutopush.app` and grant it Documents access (not Full Disk Access to bash; not moving the vault).
- My call: `SECONDBRAIN_VAULT` / `SECONDBRAIN_AUTOPUSH_LOG` env overrides so the script can be tested without touching the real vault.
- Small-change lane (my call): one script, one plist, one README; no plan file.

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `secondbrain-autopush.sh` | env `SECONDBRAIN_VAULT`, `SECONDBRAIN_AUTOPUSH_LOG`; exit code | add -A → commit (if changes) → pull --rebase → push; logs `committed N file(s)` / `push OK`; exit 5 with a privacy hint when the vault's `.git` cannot be read; exit 4 when push fails. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | vault with 3,000 new files, bare origin | run | exit 0; origin/main has the commit; log has `push OK` |
| AC-2 | uncommitted change locally; origin moved by another clone | run | exit 0; origin has both commits; no `WARN` in the log |
| AC-3 | vault whose `.git` is unreadable | run | exit 5; log names the privacy fix |
