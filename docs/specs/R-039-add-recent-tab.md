---
date: 2026-11-07
updated: 2026-11-07
type: spec
id: R-039
status: draft
tags: [obsidian-plugin, roadmap-view, mockup, report]
ai-first: true
related-specs: [R-013, R-024]
mockup: Proposals/mockups/roadmap-recent-tab-mockup.html
supersedes: null
---

## For future Claude
> R-039 adds a third tab, **最近**, to Roadmap 檢視 (`obsidian-roadmap-view/`, R-013). It lists every
> HTML mockup, report and research page changed in the last 7 days across **all** project folders
> and `20 Research/`, grouped by project (projects ordered by their newest file), newest first inside a
> group, 3 shown per group with 「看全部 N 份」 to expand. Each row: kind, `<title>`, time, a first-screen
> thumbnail (the existing 現況 renderer, which already falls back to `<body>`), and a green dot until
> the file has been opened since it last changed. Tapping a row opens the file in a new tab. Picked
> option: mockup 定案 C（加 B 的縮圖）in `Proposals/mockups/roadmap-recent-tab-mockup.html`.

## §1 Problem
The operator, 2026-11-07: 「很常新提出的 proposal mockup 我都要找很久」「Research mockup 要找很久」.
They look in each project's `Proposals/mockups/` folder; what they want is the one just made.

Facts (vault and `main.js` at `fdc8448`, 2026-11-07):
- langlive-line-oa's `Proposals/mockups/` holds 132 files; its `Reports/` + `Research/` hold 35 HTML.
  Obsidian's file list sorts by name, so the newest file sits in the middle.
- In the last 7 days 48 HTML files changed: langlive-line-oa 40, ai_system 5, ai-eden-service 1,
  lang30s-viewer 1, `20 Research/` 1. All of them have a `<title>`.
- `Reports/<stem>.evidence/` holds 11 HTML build artifacts that are not for reading.
- A draw-arch run rewrote 10 HTML pages under `langlive-line-oa/Architecture/diagrams/html/` (one
  `index.html` per pack); `Specs/` and `Docs/` each held one HTML file changed this week.
- The view lists only folders with a `ROADMAP.md` (`main.js` `projects`), shows a mockup only when a
  Roadmap row mentions it (`mockupsFor`), and re-renders only on the current project's
  `ROADMAP.md`, `Proposals/mockups/`, `Specs/`, `Brainstorms/`, `ship-status/` (`WATCHED`, `isWatched`).
  The newest mockups have no R-ID, so the view cannot show them.

## §2 Goals, non-goals
**Goals**
- G1. One tap on 「最近」 shows every mockup / report / research HTML changed in the last 7 days.
- G2. Grouped by project, so the operator sees what each project produced (option C).
- G3. A thumbnail per row so a mockup is recognisable at a glance (option B).
- G4. A green dot marks a file not opened since it last changed.
- G5. A new file written by Claude appears without reopening the view.

**Non-goals**
- Searching older files by topic; filters (mockup only / report only) — Q4, later if needed.
- A settings tab or a configurable window (R-013 decided no settings tab).
- Moving, renaming or editing any vault file.

## §3 Design
### 3.1 What is listed (pure core)
`recentKind(path, projectsDir, researchDir)` classifies a vault path:
- `<projectsDir>/<project>/Proposals/mockups/…/<name>.html` → `mockup`
- `<projectsDir>/<project>/Reports/…/<name>.html` → `report`
- `<projectsDir>/<project>/Research/…/<name>.html` → `research`
- `<researchDir>/…/<name>.html` → `research`, group `20 Research`
- `<projectsDir>/<project>/Architecture/…/index.html` → `architecture` (one row per draw-arch pack; the
  pack's other pages → `null`)
- `<projectsDir>/<project>/Specs/…/<name>.html` and `…/Docs/…/<name>.html` → `doc`
- anything else, any path with a segment ending `.evidence` or named `_archive`, and any project
  folder named `_archive` → `null`.
`projectsDir` is the existing setting (`10 Projects`); `researchDir` is the constant `20 Research`.
Every folder under `projectsDir` counts, with or without a `ROADMAP.md` (operator Q1).

`recentGroups(files, now, opts)` takes `{path, mtime}` entries and returns
`[{ group, latest, items: [{ path, kind, mtime, where }] }]`:
- keeps entries with a kind and `now - mtime <= 7 days`;
- `group` is the project folder name, or `20 Research`;
- `where` is the folder inside the group, shown on the row for `20 Research` (e.g. `LLM`);
- items newest first; groups ordered by `latest` (their newest mtime), newest first; ties by name.

`htmlTitle(html, path)` returns the trimmed text of the first `<title>`, with `&amp; &lt; &gt; &quot;
&#39;` decoded, or the file's basename without `.html` when there is none or it is empty.

`isUnread(item, opened, since)`: unread when the file changed after the last time it was opened
(`opened[path] < mtime`, or never opened), except files whose `mtime` is older than `since`, the
moment the plugin first ran this feature, which count as read so the launch does not paint dozens of dots.

### 3.2 The tab
- Tabs become 「近況」「全部」「最近」. On 最近 the project picker is hidden; the list covers all groups.
- Group header: `<group> · N 份`. A group shows its 3 newest items; when N > 3 a 「看全部 N 份」
  control expands it. Expanded groups survive a live re-render (like folds), not a restart.
- Row: kind label (mockup / 報告 / 研究 / 架構圖 / 文件), the title, and `<time>` (`<where> · <time>` in the
  `20 Research` group, as in mockup option C) where time is local `HH:MM`
  today, 「昨天 HH:MM」 yesterday, `MM/DD HH:MM` otherwise; a green dot when unread; the thumbnail on
  the right.
- Thumbnail: the existing `lazyThumb` + `currentStateDoc` (現況 panel, else `<body>`), slot key
  `recent|<path>`, same caps (2 at a time, sandboxed iframe, scripts stripped, cached per mtime).
- The whole row (thumbnail included) opens the file with the existing `openMockup(path)`; no zoom
  (operator Q2).
- Empty window: 「7 天內沒有新的 mockup、報告或研究」.

### 3.3 Read state
- Settings gain `opened: { [path]: epochMs }` and `recentSince: epochMs` (set on first load when
  absent). Opening a listed file from the tab, or anywhere in Obsidian (`workspace` `file-open`),
  records `opened[path] = now` and saves settings (operator Q3). Only paths with a `recentKind` are
  recorded.
- Entries older than the 7-day window are dropped when settings are saved, so the map stays small.
- When the settings file changes from outside (Obsidian Sync from the other device,
  `Plugin.onExternalSettingsChange`), reload it and merge **only** `opened` into the in-memory map,
  keeping the later time per path, so a file opened on the phone loses its dot on the desktop too.
  Every other setting (the picked `project`, `recentSince`) stays this device's.
- Re-opening a file that is already read (`opened[path] >= mtime`, e.g. switching back to its tab)
  saves nothing.
- Stored in the plugin's own data file only (operator Q4).

### 3.4 Live refresh and reads
The vault `create / modify / delete / rename` handler also refreshes when the path (or old path) has a
`recentKind` **and a pane is showing 最近**, so a file Claude writes appears within the existing 500 ms
debounce without redrawing other projects' 近況／全部 screens. Titles are read with `vault.adapter.read`
(as `entryFor` does) and cached per path + mtime, only for the rows about to be drawn (3 per group, or
all in an expanded group), in parallel; a render that a newer one has replaced stops reading.

## Seams
| Seam | Interface | Guaranteed behavior |
| --- | --- | --- |
| classify | `recentKind(path, projectsDir, researchDir)` | returns `mockup` / `report` / `research` / `architecture` (pack `index.html` only) / `doc` per §3.1, `null` for other paths, `.evidence` segments and `_archive` |
| group | `recentGroups(files, now, opts)` | 7-day window inclusive; items newest first; groups ordered by newest item; `20 Research` is its own group with `where` |
| title | `htmlTitle(html, path)` | first `<title>` text, entities decoded, else basename without `.html` |
| title reads | `readRecent()` | reads only the rows it will draw (3 per collapsed group); a stale render stops reading |
| unread | `isUnread(item, opened, since)` | true iff `mtime >= since` and (`opened[path]` missing or `< mtime`) |
| tab | the view's 最近 tab (fake obsidian) | three tabs; picker hidden on 最近; group headers with counts; 3 rows then 「看全部 N 份」 expands; row shows kind, title, meta, dot; row click calls `openMockup(path)` |
| read state | `file-open` handler + settings | opening a listed path stores `opened[path]` and the dot disappears on the next render; re-opening a read file saves nothing; non-listed paths are not stored; entries older than 7 days are pruned on save; `onExternalSettingsChange` merges only `opened` (later time wins) and leaves `project` and `recentSince` as they were |
| launch baseline | `recentSince` | set to the first load's time when absent; files older than it count as read |
| refresh | vault event handler | an event on a path with a `recentKind` schedules `refreshSoon()` while some pane shows 最近, even when no project is on screen; with no 最近 pane it does not |
| exports | `RoadmapViewPlugin` statics | `recentKind`, `recentGroups`, `htmlTitle`, `isUnread` are exported for tests |

## §4 Acceptance
| ID | Given | When | Then |
| --- | --- | --- | --- |
| AC-1 | paths under a project's `Proposals/mockups/`, `Reports/`, `Research/`, under `20 Research/LLM/`, `Architecture/diagrams/html/index.html`, `Architecture/diagrams/html/jobs.html`, `Specs/x.html`, `Docs/y.html`, under `Reports/x.evidence/`, under `_archive/`, and a `.md` | `recentKind` | mockup / report / research / research / architecture / null / doc / doc / null / null / null |
| AC-2 | files from 3 projects and `20 Research`, one 8 days old | `recentGroups(files, now)` | the old one is gone; groups ordered by their newest file; items newest first; `20 Research` group carries `where` |
| AC-3 | `<title>A &amp; B</title>`, an empty title, no title | `htmlTitle` | `A & B`, basename, basename |
| AC-4 | an item changed after it was opened, one opened after it changed, one never opened, one older than `since` | `isUnread` | true, false, true, false |
| AC-5 | a fake vault with 5 recent files in one project and 1 in another | the view switches to 最近 | three tabs, no project picker, two group headers with counts, 3 rows then 「看全部 5 份」; tapping it shows 5 |
| AC-6 | the 最近 tab | a row is clicked | `openMockup` is called with that path |
| AC-7 | an unread row | `file-open` fires for its path, then the view re-renders | `opened[path]` is saved and the row has no dot; a `file-open` for a `.md` note stores nothing |
| AC-8 | the view on 最近 | the vault fires `create` for a new mockup in another project | `refreshSoon` runs and the new row is first after the debounce; with the pane on 近況 the same event does not refresh |
| AC-9 | the existing 73 node tests and the bats suite | the change lands | they pass (bats: only the known worktree `cwd-guard` failure) |
| AC-10 | the real vault (local-only test, skipped without it) | `recentGroups` over the vault's files | every listed item has a non-empty title and no `.evidence` path |
| AC-11 | the plugin copied into the vault by `./sync.sh restore` | Claude opens 最近 on the desktop app and looks | groups, thumbnails and dots render; tapping a row opens the HTML |
| AC-12 | settings holding `opened` = {a: 10, b: 30} and `project` = demo in memory, and `opened` = {a: 20, c: 5}, `project` = other on disk | `onExternalSettingsChange` | `opened` = {a: 20, b: 30, c: 5}; `project` stays demo and an open detail page stays open |
| AC-13 | the synced phone app, after merge | the operator opens 最近 | the same groups and order as the desktop; if a fresh sync shows every file as new, that is filed as a follow-up (Obsidian Sync not keeping file times), not fixed here |

## Decisions
- **A 「最近」 tab in Roadmap 檢視** (operator: 「可以加一個 最近的分頁」), not Obsidian's native sort,
  which would reorder every folder and still needs three folders opened.
- **All projects plus `20 Research`** (operator: 「列出所有剛做好的 mockup 和 報告」).
- **Grouped by project with thumbnails** (operator: 「C+B」 on the mockup).
- **7 days, green dot, no filter in v1** (my calls from the mockup's recommendations; the operator
  approved the playback: 「好」).
- **Every folder under `10 Projects/`, not only those with a ROADMAP.md; `_archive` excluded**
  (operator Q1: yes).
- **Whole row opens the file; no thumbnail zoom** (operator Q2: yes).
- **Opened anywhere in Obsidian counts as read** (operator Q3: yes).
- **Read state lives in the plugin's data file** (operator Q4: yes).
- **Architecture packs as one 架構圖 row (their `index.html`); `Specs/` and `Docs/` HTML as 文件**
  (operator Q5, Q6: yes).
- **Merge `opened` on an external settings change, later time wins** (mine, from the builder check:
  Sync would otherwise let one device overwrite the other's read state).
- **Review attempt 1 fixes** (operator: 「都修」): an external settings change merges only `opened`; title reads only for drawn rows, stopped when stale; recent-path refresh only while 最近 is shown; no save when re-opening a read file; `adapter.read` stays (spec aligned to the code).
- **Phone acceptance is the operator's look (AC-13)** (mine): Claude cannot drive the phone.
- **`recentSince` seeds the read state** so launch does not mark 48 old files unread (mine).
- **The 7-day window is a constant, not a setting** (mine; R-013 has no settings tab).
- **Reuse `lazyThumb`, `currentStateDoc` and `openMockup`** (mine): the 現況 renderer already falls
  back to `<body>` for reports, and `openMockup` already opens HTML in a new tab.
- Door: two-way — a read-only view plus two new keys in the plugin's own settings; a revert restores the old view and leaves no vault file changed.
