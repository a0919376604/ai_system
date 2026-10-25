---
date: 2026-10-25
updated: 2026-10-25
type: learning
id: R-012
tags: [learning, ai_system, launchd, macos-privacy, vault-backup]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-012
shipped: true
shipped-date: 2026-10-25
---

## For future Claude
> The vault backup (`examples/launchd-autopush`) runs through `~/Applications/SecondBrainAutopush.app`,
> which holds the macOS Documents grant. Order: add → commit → pull --rebase (abort on conflict) → push.
> Logs: `~/Library/Logs/secondbrain-autopush.log`. Tests run on scratch vaults only.

## What Shipped
- Example script = the fixed install, plus `SECONDBRAIN_VAULT` / `SECONDBRAIN_AUTOPUSH_LOG` overrides.
- AppleScript wrapper source; plist opens the app; README install/grant steps and failure table.
- 6 bats tests.

## Key Decisions
- App wrapper with a Documents grant (leric chose it over Full Disk Access for bash or moving the vault).
- A conflicted pull aborts the rebase and keeps the local commit; a human resolves it (review attempt 1).

## Bugs
- **launchd jobs cannot read ~/Documents** (`Operation not permitted`); git then reports "no origin remote". 520 silent failures from 2026-06-15.
- **`cmd | head -N` under `set -o pipefail` + `set -e` kills the script** once `cmd`'s output exceeds the pipe buffer. Wrap in `$( … || true)`.
- **Pull before commit** always fails with uncommitted changes.

## Reusable Patterns
- **A background job that "fails" with a misleading message: reproduce it inside the same context** (`launchctl submit` a probe) before trusting the message.
- **Scripts that act on real data need an override and a test guard** that refuses to run if the override is missing.

## Technical Debt
- The app wrapper swallows the script's exit code (read the log, not `launchctl list`).
