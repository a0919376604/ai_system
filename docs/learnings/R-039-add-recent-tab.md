---
date: 2026-11-07
updated: 2026-11-07
type: learning
id: R-039
tags: [learning, ai_system, obsidian-plugin, roadmap-view, mockup]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-039
shipped: true
shipped-date: 2026-11-07
---

## For future Claude
> R-039 adds the 「最近」 tab to Roadmap 檢視 (`obsidian-roadmap-view/`, R-013): every mockup / report /
> research / architecture-pack / doc HTML changed in the last 7 days, across all `10 Projects/*` folders
> and `20 Research/`, grouped by project (newest group first, 3 rows then 「看全部 N 份」), each row with a
> first-screen thumbnail and a green dot until opened since its last change. The pure core is
> `recentKind`, `recentGroups`, `htmlTitle`, `isUnread`. Read state is `opened` + `recentSince` in the
> plugin's own `data.json`; `onExternalSettingsChange` merges **only** `opened`.

## What Shipped
- **Pure core** (exported, table-tested in `parse.test.js`): `recentKind(path)` — `Proposals/mockups` →
  mockup, `Reports` → report, `Research`/`20 Research` → research, `Architecture/**/index.html` →
  architecture, `Specs`/`Docs` → doc; never `*.evidence/` or `_archive`; `recentGroups` (7 days inclusive,
  future mtimes kept), `htmlTitle` (first `<title>`, entities decoded, else basename), `isUnread`.
- **Tab**: 近況 · 全部 · 最近; picker hidden on 最近; thumbnails through the existing `lazyThumb` /
  `entryFor` (a new `zoom: false` so a thumbnail tap opens the file); rows open via `openMockup`.
- **Reads**: titles via `adapter.read`, cached per path + mtime, only for drawn rows, in parallel per
  group; a replaced render stops (on the real vault: 51 items / 13.4 MB before, a few files now).
- **Read state**: `file-open` anywhere and `openWithDefaultApp` mark read; re-opening a read file saves
  nothing; stored time is `max(now, mtime)`; entries older than 7 days pruned on save; `recentSince`
  seeds launch so old files carry no dot.
- **Refresh**: vault events on recent paths refresh only while some pane shows 最近.
- **Tests**: node 73 → 101 (real-vault test included); bats 896, only the known `cwd-guard` failure.
## Key Decisions
> Carry the spec's `## Decisions` forward, one line each with its why. The spec leaves the repo at compound; this is what stays.
- **A 「最近」 tab, not Obsidian's native sort** (operator) — native sort reorders every folder and still needs three folders opened.
- **All projects plus `20 Research`** (operator: 「列出所有剛做好的 mockup 和 報告」).
- **Grouped by project with thumbnails** (operator: 「C+B」 on `Proposals/mockups/roadmap-recent-tab-mockup.html`).
- **7 days, green dot, no filter in v1** (mine from the mockup; operator approved the playback).
- **Every folder under `10 Projects/`, `_archive` excluded; whole row opens; opened anywhere counts; state in the plugin's data file** (operator Q1–Q4).
- **Architecture packs as one 架構圖 row; `Specs/`/`Docs/` HTML as 文件** (operator Q5, Q6).
- **External settings change merges only `opened`, later time wins** (mine, builder check; tightened after review attempt 1).
- **Phone acceptance is the operator's look (AC-13)**; Claude cannot drive the phone.
- **`recentSince` launch baseline; 7 days as a constant; reuse `lazyThumb`/`currentStateDoc`/`openMockup`** (mine).
- **Review attempt 1: fix everything** (operator: 「都修」).
- Door: two-way — a read-only view plus two keys in the plugin's own settings.

## What Changed From Plan
- Main plan: codex (gpt-6.1-sol), one round, DONE_WITH_CONCERNS, 5 commits. Deviations: updated the
  onload guard test for the new settings/events; `openMockup`'s default-app branch marks read itself (no
  `file-open` fires there); an external change kept `recentSince` (later superseded by merging only `opened`).
- Review attempt 1: 1 blocking, 2 important, 7 nits → fix-plan 2 (codex, 4 commits). My fix-plan said
  "OR the 最近-pane check"; codex used AND, matching the spec and its own test — my wording error.
- Review attempt 2: 0 blocking, 0 important, 6 nits; I fixed the future-mtime one inline with TDD (`3587c59`).
- AC-11 (desktop look) not run: Obsidian's command line interface is off on this machine.
## Bugs
- **A synced settings file took over this device's view.** The first `onExternalSettingsChange` replaced the
  whole settings object, so the other device's `project` moved this pane and closed its detail page. Before
  R-039 settings were saved only on a picker change; once every file-open saves, Sync carries `project`
  across on each open.
- **The first 最近 render read 13.4 MB.** Titles were read in full for all 51 items, 42 of them hidden
  behind 「看全部」, and a replaced render kept reading.
- **Refresh fan-out.** Any recent-path change in any project redrew the current project's 近況 and its iframes.
- **A future mtime kept its dot after opening.** Storing `now` lost to an mtime from a fast-clock device.
## Lessons → checks
> Each lesson: the check that enforces it, with its proof, or `judgment`.
- When a plugin starts saving settings on a frequent event, an external (synced) settings change must merge only the keys that event owns — enforced by `view.test.js` "external settings change keeps this device's project and detail page (AC-12)" · proof: red at 936b52d (exit 1) · green at 5bd49bd
- Read only what the screen draws; a list that reads every file before drawing grows with the vault — judgment

## Reusable Patterns
> Patterns worth promoting to 40 Knowledge/ or 30 Engineering/ (handled by `/ship-compound`).
- **Classify by path, test the classifier with a table, then probe the real vault with the same function**: the real-vault test caught nothing new because the table already held the cases found by listing the vault first.
- **Seed read state at first run** (`recentSince`) so a new unread marker does not light up everything at launch.

## Technical Debt
- Review attempt 2 nits left: writes to the last-picked project's watched paths still redraw 最近; `markOpened`/external changes redraw every Roadmap pane; a no-op stale check inside the per-group read; a drawn row reads its HTML twice (title + thumbnail); one test covers two behaviours.
- AC-11 (desktop look) and AC-13 (phone, Sync mtime) are not yet verified.
## Future Follow-ups
- Enable Obsidian CLI (Settings › General › Advanced) or look manually: AC-11 on desktop, AC-13 on the phone.
- If the phone shows every synced file as new, file a follow-up: Sync is not keeping file times.
