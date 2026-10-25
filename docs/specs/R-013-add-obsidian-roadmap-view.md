---
date: 2026-10-25
updated: 2026-10-25
type: spec
id: R-013
status: draft
tags: [obsidian, plugin, roadmap, mobile, ship-next, ship-status]
ai-first: true
related-specs: []
mockup: "10 Projects/ai_system/Proposals/mockups/obsidian-roadmap-view-mockup.html"
supersedes: null
---

## For future Claude
> R-013 adds an Obsidian plugin, **Roadmap 檢視**. It is a read-only, live, phone-first
> view of one project's ROADMAP, written for a human. ROADMAP.md stays written for AI;
> the plugin picks what a person needs and shows it:
> - one Chinese line per item;
> - its status and ship-next phase;
> - its mockup's 現況 panel as a thumbnail that zooms on tap;
> - links to its spec, brainstorm and mockups.
>
> Two earlier attempts failed because they were snapshots:
> - `/ship-brief` → `Overview/brief.html`, generated on demand;
> - `daily-board-refresh.sh` → `Boards/<repo>.md`, once a day at 09:00.
>
> At four or five items a day, any snapshot is stale. So the plugin re-renders from the
> files on every change, and ship-next writes the one thing the files did not hold:
> which phase each ship is in.

## §1 Problem
- **One project's ROADMAP is unreadable for a person.** The largest one has close to
  300 rows of about 2,000 characters each, most with a done-when line. The rows mix English, file
  names and line numbers. The operator: 「roadmap 目前已經大到我開始看不懂了，太多
  When…有一些是寫給 AI 看的，不是寫給我們看的」.
- **Status is buried.**
  - Done items stay in Next with an empty checkbox, and their state hides in tag text:
    `✅ merged 2026-10-19`, `尚未部署 test`, `blocked: <reason>`,
    `mockup 定案 B`.
  - Which ship-next phase an item is in is recorded nowhere in the vault; it lives only
    in each worktree's `.ship/`.
- **Mockups and specs are not at hand.**
  - A row names a mockup file at best.
  - Specs sit in `Specs/R-NNN-*.md`, unlinked.
  - The operator finds "what am I doing lately" by opening the newest mockups one by
    one.
- **The operator reads it on the phone** (「這個 plugin 主要用戶是在手機上看」), through
  Obsidian Sync.

## §2 Goals, non-goals, anti-goals
**Goals**
- G1. In Obsidian, on the phone and on desktop, one project at a time:
  - a **近況** list: 進行中／卡住, then 最近完成, then 待做 (collapsed);
  - a **全部** list with search;
  - a **detail page** per item.
- G2. **Live.** The view re-renders when ROADMAP.md, a mockup, a spec, a brainstorm or a
  status file changes. There is no generate step.
- G3. **Per item:** a human headline, the status chips parsed from the row, the
  ship-next phase, and the mockup's 現況 thumbnail. **Tapping a thumbnail opens it
  full-screen** at fit-width, 2× and 3×, scrollable.
- G4. **The detail page links** the item's vault spec, legacy brainstorm and mockups, and
  shows its commit or MR text. One tap opens each.
- G5. **ship-next records each ship's phase** in `<vault project>/ship-status/<R-NNN>.json`,
  with timestamps.
- G6. **`/ship-next --adhoc` writes a one-line zh-TW `↳ explain:`** under the row it
  inserts, written for a person.
- G7. **`./sync.sh restore` installs the plugin** by copying it into the vault's
  `.obsidian/plugins/`, so Obsidian Sync carries it to the phone.

**Non-goals**
- Editing anything from the plugin: no checking off rows, no reordering.
- Cross-project views.
- A 時間軸 (timeline) tab. Recorded as a follow-up; the status files make it cheap later.
- Back-filling `↳ explain:` for the 215 existing rows that lack one. They show their
  headline.
- Linking repo-only files (plan, learning). The phone cannot open them.
- Retiring `daily-board-refresh.sh`. That is the operator's call after using this.

**Anti-goals** (failure even if it "works")
- The plugin writing any vault file other than its own settings (`data.json`).
- A black or blank pane. Every render failure shows its error on screen, as the spike
  showed this needs.
- A ship-next run failing, or stalling, because the status file could not be written.
- Rendering every mockup at once on the phone. Thumbnails are lazy and cached.

## §3 Design

### 3.1 Layout
```
obsidian-roadmap-view/        new top-level dir (not a skill, so not under claude-skills/)
  manifest.json               id "roadmap-view", isDesktopOnly false
  main.js                     the whole plugin, plain CommonJS — no build step
  styles.css
  test/*.test.js              node --test, with `obsidian` stubbed; no npm dependencies
```
- Obsidian loads a single `main.js`, so the parser and the view live in one file.
- The pure functions in §Seams are exported as static members of the plugin class, so
  `node --test` can reach them.

### 3.2 Parsing (pure, in `main.js`)
**`parseRoadmap(md) → Item[]`.** One item per row matching
`^(\s*)- \[( |x)\] (⚠️ )?(~~)?\*\*(R-\d[\w.-]*)((?: \([^)*]*\))?)\*\*( \(epic\))?`, plus the
`↳` lines indented under it. The regex covers the real rows seen on 2026-10-25:
`**R-001 (epic)**`, `**R-193.3a-2.1**`, `~~**R-093** …~~` and `⚠️ **R-300** (epic)`. A
line such as `✅ **R-193 號碼衝突已結案**` is a note, not an item. Each item carries:

- **Identity:** `id`, `checked`, `section` (the nearest `## ` heading), `line` (0-based).
- **Text:**
  - `tags` — the leading `[...]`;
  - `headline` — after the tags, up to the first `——` or `**來源`, trimmed;
  - `raw` — the row line;
  - `doneWhen` — the `↳ done when:` lines;
  - `explain` — the `↳ explain:` text, but `null` when it only points at a mockup
    (`↳ explain: mockup …`);
  - `refs` — the `Proposals/mockups/….html` paths found in the row and its `↳` lines;
  - `sameAsAbove` — true when a `↳` line says `mockup 同上`.
- **Status, read from the whole row.** These markers appear inside the leading tags in
  langlive, and as trailing `· ✅ <date>` / `· status=…` / `· mr=…` annotations where
  ship-workflow wrote them, as in ai_system:
  - `done` — date of the first `✅` followed by a date (formats `✅ 2026-10-22～24`,
    `✅ merged 2026-10-19`, `✅ shipped · merged 2026-10-13`); `checked` also means done;
  - `undeployed` — `尚未部署 <env>`;
  - `blocked` — the text after `blocked:` up to the next `·`;
  - `needsBrainstorm` — `needs-brainstorm`;
  - `picked` — `mockup 定案 <X>`;
  - `inReview` — `status=in-review`; `epic` — the `(epic)` marker;
  - `commit` — the first backticked 7–10 hex characters;
  - `mr` — `!<n>`.
- **Child rows** (`R-NNN.M`, indented) are items too.

**`mockupsFor(item, items, files) → string[]`.** Gathers, de-duplicated:
- the mockup files whose name starts with `<id>-`;
- the item's `refs`;
- when `sameAsAbove` is set, the mockups of the nearest item with the same base id
  (`R-094.3` → other `R-094` / `R-094.x` items) that has any. "Nearest" is by id, not by
  line: the closest smaller id, else the closest larger. Rows are not in id order:
  a child row can sit hundreds of lines away from its sibling.

**`statusOf(item, phaseFile) → {group, chips, phase}`.**
- `group` is one of:
  - `active` — a status file whose phase is not `done`, `blocked` set, or a row marked
    `status=in-review` that is not done;
  - `recent` — done within `recentDays`, 14 by default;
  - `done`;
  - `todo`.
- The phase from `ship-status/<id>.json` wins over the tags when it is newer. A ROADMAP
  date counts as the end of that day, so on the same day the row's own tags win. A status
  file with an unknown phase is ignored.

### 3.3 現況 thumbnail
- **`currentStateDoc(html) → srcdoc | null`.**
  - It finds `.panel.now`; failing that, the first `.panel` that is not `.facts`;
    failing that, the whole `<body>`.
  - It returns a document holding all of the mockup's `<style>` blocks plus that one
    element, as the spike did.
  - It is a **string scanner, not `DOMParser`**. It collects every `<style>…</style>`
    block, finds the opening tag whose `class` holds both `panel` and `now`, and returns up
    to that tag's balanced close by counting same-name open and close tags. That makes it
    testable under `node --test`, and identical on desktop and phone. Mockups follow the
    vault convention, where `.panel.now` is a `<div class="panel now">`.
- **Rendering.** The srcdoc goes into an `<iframe srcdoc>` 1100px wide, CSS-scaled to the
  box. Its height is read from `contentDocument.body.scrollHeight` on load. The iframe has
  `pointer-events: none`, so the container receives taps and scrolls. A 3-second timeout
  marks a render that never loaded.
- **No mockup script runs.** `currentStateDoc` drops every `<script>`, and the iframe is
  `sandbox="allow-same-origin"`: same origin, so its height is readable, but no scripts.
  A srcdoc iframe otherwise runs with the Obsidian app's own origin.
- **Thumbnails are lazy.**
  - They render only for cards in view, via `IntersectionObserver`, at most 2 at a time.
    A re-render frees the slots: a thumbnail still loading from the old render neither
    holds one nor, when it finishes, adds one.
  - Results are cached per `path + mtime`; changing a mockup invalidates its entry.
- **Zoom.** Tapping a thumbnail or the detail page's big image opens a modal with
  `符合寬度 / 2× / 3×`. The tap does not also open or close the card.

### 3.4 The view
- **Shell.** An `ItemView` with a ribbon icon and the command 「打開 Roadmap 檢視」.
  - At the top: a project picker, listing the folders under `<projectsDir>` that hold a
    `ROADMAP.md`, plus 近況 / 全部 tabs.
  - **The view must not define a field named `open`** (spike lesson: it shadowed
    `View.open` and blanked the pane). Use `expanded` or similar.
- **Cards:** id, status chips, headline (3-line clamp), explain (2-line clamp) and the
  thumbnail.
- **Detail page:**
  - chips, headline, explain (or a faint 「還沒有白話說明」);
  - the big 現況;
  - links: spec `Specs/<id>-*.md`, legacy `Brainstorms/<id>-*.md`, each mockup
    (opened with the HTML viewer if one is installed, else the system), commit / MR as
    text. Links open in a new tab, so the view keeps its place;
  - folds: 完成條件, 給 AI 的原文, and 「在 ROADMAP.md 打開這一行」 (opens the file at
    `line`).
- **Live updates.** The vault events `modify`, `create`, `delete` and `rename` under the
  project's `ROADMAP.md`, `Proposals/mockups/`, `Specs/`, `Brainstorms/` and
  `ship-status/` re-render the view, debounced 500 ms.
- **Errors.** Every render runs inside try/catch, and an error is shown in the pane with
  its message. Never a blank pane.
- **Settings** (`saveData`): `projectsDir` (default `10 Projects`), `recentDays` (14),
  and the last project picked.

### 3.5 ship-next writes the phase — `sn_status`
- **`sn_status <worktree> <phase> [note]`** in `lib/ship-next.sh`.
  - It resolves the vault project with `airos-binding.sh project_path`; R-004 made this
    correct inside a worktree. It never creates the project folder: a wrong name would
    plant a bogus vault folder, as R-001/R-003 did.
  - `ID` and `BRANCH` come from `<worktree>/.ship/state.env`, else from the caller's
    `ID` / `BRANCH`. `/ship-land` passes the main checkout and its own `ID`.
  - It refuses a phase outside the list below, and an ID that is not a plain `R-…`
    (letters, digits, `.` and `-`), so a bad argument cannot write outside `ship-status/`.
  - It writes `<project>/ship-status/<ID>.json` atomically (tmp + mv), appending
    `{phase, at, note}` to `phases` and setting `phase`, `updated` and `branch`.
- **Format:** `{"id","phase","updated","branch","note","phases":[{"phase","at","note"}…]}`.
- **Phases:** `brainstorm`, `plan`, `build`, `review`, `landing`, `in-review`, `done`,
  `blocked`.
- **It never fails the ship.**
  - On any error (no vault, unwritable, no `jq`), it prints one `WARN` line and returns
    0.
  - One file per ship, so parallel ships never write the same file. The folder name does
    not start with a dot, so Obsidian Sync carries it.
- **Calls in `commands/ship-next.md`:**

  | Where | Phase written |
  |---|---|
  | Phase 2, after the worktree is made | `brainstorm` |
  | Phase 4 start | `plan` |
  | Phase 5 start | `build` |
  | Phase 6 start | `review` |
  | Phase 7 start | `landing` |
  | squash: after Phase 8 | `done` |
  | mr: after Phase 7 | `in-review` |
  | Phase 5 `stop_infra` / `stop_exhausted` / spec-level stop, and Phase 6 cap exhausted | `blocked`, with the reason as the note |

  `/ship-land R-NNN` writes `done` after its compound, using the ID it is given.
  `--discard R-NNN` deletes that ship's status file.

### 3.6 `--adhoc` writes a human line — `roadmap-insert.sh --summary`
- **`roadmap-insert.sh … --summary "<text>"`** adds `↳ explain: <text>` (plain text, no
  `[[ ]]`) as the first annotation line. The text is single-line, with newlines folded to
  spaces. The existing `--explain <slug>` is unchanged.
- **ship-next Phase 1 step 3** tells the session to compose one zh-TW sentence, written
  for a person: what changes and for whom, with no file names. It passes that sentence as
  `--summary`.

### 3.7 Install — `sync.sh`
- **`restore`** copies `obsidian-roadmap-view/{manifest.json,main.js,styles.css}` into
  `<airos_vault>/.obsidian/plugins/roadmap-view/`.
  - The vault path comes from `~/.claude/ship-workflow.yml` `airos_vault`.
  - It copies only when the content differs, and never touches another plugin. A real
    directory in the way is ours, so it is overwritten file by file, not displaced.
  - It does not enable the plugin. Enabling is a one-time click in Obsidian.
  - `--dry-run` prints the copy.
  - With no `airos_vault` configured, it prints a skip line.
- **`status`** prints `obsidian plugin: up to date | out of date | not installed | no
  vault`. It does not affect the exit code; links alone do.
- Copied, not symlinked: Obsidian Sync does not follow a symlink, and the phone needs
  real files.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `parseRoadmap` | `RoadmapViewPlugin.parseRoadmap(md) → Item[]` | One item per `- [ ]/[x] **R-…**` row (children included), with the fields in §3.2; `explain` is null when it only points at a mockup; headline stops at `——` or `**來源` |
| `mockupsFor` | `RoadmapViewPlugin.mockupsFor(item, items, files) → string[]` | `<id>-` files ∪ refs ∪ (sameAsAbove → nearest same-base-id item's); de-duplicated |
| `statusOf` | `RoadmapViewPlugin.statusOf(item, phaseFile, now, recentDays) → {group, chips, phase}` | groups `active / recent / done / todo` by §3.2; a status-file phase newer than the tags wins |
| `currentStateDoc` | `RoadmapViewPlugin.currentStateDoc(html) → string \| null` | the mockup's styles + `.panel.now`, else the first non-facts `.panel`, else the body |
| `sn_status` | `sn_status <worktree> <phase> [note]` | Writes `<project>/ship-status/<ID>.json` atomically per §3.5; always exits 0 |
| `roadmap-insert --summary` | `roadmap-insert.sh <file> <id> <desc> … --summary "<text>"` | Adds a plain `↳ explain: <text>` line as the first annotation; single-line |
| `sync.sh restore` (plugin) | `./sync.sh restore` | Copies the three plugin files into `<vault>/.obsidian/plugins/roadmap-view/` when they differ; touches no other plugin; skips with no vault |
| `sync.sh status` (plugin) | `./sync.sh status` | One `obsidian plugin:` line; exit code unchanged |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | fixture rows written in the exact formats of langlive's R-248, R-256, R-094.2/R-094.3, R-231 and ai_system's trailing-annotation rows (synthetic text: the repo is public, langlive's roadmap is company data) | `parseRoadmap` | R-248: headline 「首頁「熱門分類／分類細節」清單調整」, done 2026-10-19, undeployed `test`, picked `B`, commit `a1b2c3d4`, explain null; R-094.3: blocked `等待正式環境的金鑰`, sameAsAbove; R-231: explain present, needsBrainstorm (all text, hashes and file names invented) |
| AC-2 | R-094.2 with `share-link-tracking-mockup.html` above R-094.3 `mockup 同上` | `mockupsFor(R-094.3)` | that file |
| AC-3 | a status file `{phase:"review"}` for an unchecked item / a `✅ 2026-10-19` item at now=2026-10-25 / one at 2026-09-01 / a plain unchecked row | `statusOf` | active / recent / done / todo |
| AC-4 | a mockup with `.panel.facts` then `.panel.now` (with nested divs) / with no `.panel.now` / with no `.panel` | `currentStateDoc` | the whole now panel, nested divs included / the first non-facts panel / the body; every `<style>` kept |
| AC-4b | the real vault ROADMAP and mockups, when present on the machine | a local-only test (skipped when the vault is absent) | `parseRoadmap` finds every `**R-…**` row; each R-NNN-prefixed mockup yields a non-null `currentStateDoc` |
| AC-5 | a worktree whose vault project is a scratch dir | `sn_status "$WT" plan` then `sn_status "$WT" blocked "codex: 3 attempts"` | `ship-status/R-9.json` has phase `blocked`, note set, two `phases` entries with ISO timestamps |
| AC-6 | no vault configured / unwritable project dir | `sn_status` | one WARN line, exit 0, nothing else changes |
| AC-7 | a ROADMAP fixture | `roadmap-insert.sh f R-9 "desc" --adhoc --summary "客服可以一次關掉多張工單"` | the row, then `    ↳ explain: 客服可以一次關掉多張工單` |
| AC-8 | a scratch HOME + scratch vault | `sync.sh restore --yes` (devsync skipped) twice | first: three files copied into `.obsidian/plugins/roadmap-view/`; second: nothing changes; another plugin dir untouched |
| AC-9 | ship-next.md | inspected | `sn_status` is called with each phase in §3.5, including `blocked` on each stop path |
| AC-10 | Obsidian on the operator's **phone**, plugin enabled, project langlive-line-oa | open the view, tap R-248's thumbnail, then 3× | the 近況 list renders; the thumbnail shows R-248's 現況; the zoom is readable and scrolls — **operator confirms** |
| AC-11 | ROADMAP.md changes on desktop | after Obsidian Sync on the phone | the open view re-renders without reopening — **operator confirms** |

## §5 Rollout
1. Land R-013 on main and push.
2. `./sync.sh restore` copies the plugin into the vault.
3. In Obsidian on the Mac, enable 「Roadmap 檢視」 and **disable and remove the spike**
   「Roadmap 檢視（試驗）」. Claude deletes `.obsidian/plugins/roadmap-view-spike/` once it
   is disabled.
4. On the phone, Obsidian Sync must sync installed plugins and the active plugin list.
   It must also sync **all other file types**, because the mockups are `.html` and the
   status files are `.json`. These are one-time, per-device toggles. Then run AC-10 and
   AC-11.

## Decisions
**Operator decisions (2026-10-24 / 25)**
- **A plugin, not a better ROADMAP.** 「roadmap 看起來也是要寫給 AI 看，所以才說做
  plugin，這樣我就可以選擇顯示我想看的東西給人看」. ROADMAP.md is untouched by the
  plugin.
- **Live, not a snapshot.** 「開發速度太快了，一天可能就開發了四五個 roadmap，這樣 html
  根本跟不上，那個只能當每天回顧，但無法當即時看狀況用」. This is why `/ship-brief`
  (2026-10-12 proposal, option B) went unused.
- **One project at a time.** 「一次只看一個專案」.
- **Links to the item's spec and mockups.** 「下面開發時有什麼關於這個 Roadmap 的 spec 或是
  mockup 請幫我連結，方便我點」.
- **Thumbnail = the mockup's 現況 panel**, chosen over the picked option's panel.
- **Phone-first.** 「這個 plugin 主要用戶是在手機上看」. Option B (board) was dropped,
  since four columns do not fit a phone.
- **Tap to zoom.** After the spike (v0.0.4): 「縮圖應該要讓我可以點擊放大，不然真的太小了」
  → 「這樣就可以看清楚了，太讚了」.
- **Spike first.** 「2 好 先做」. The spike proved that DOMParser + `.panel.now` + a scaled
  srcdoc iframe renders in Obsidian, **on the phone included**: 「手機上看得清楚」
  (2026-10-25). The mockup HTML reached the phone through Obsidian Sync, so its file-type
  settings already carry `.html`. No screenshot fallback is needed.

**Build-time calls (prototype, 2026-10-25, auto mode)**
- **The row regex was widened** after a check against every vault ROADMAP. The spec's
  first regex missed 4 real rows: `(epic)` / `(partial)` inside the bold, ids such as
  `R-193.3a-2.1`, and struck-through rows. A local-only test (AC-4b) now pins this.
- **`status=in-review` counts as active.** Such a row waits on a merge; it is in progress,
  not 待做.
- **Mockup scripts never run** in the thumbnail (sandboxed iframe, scripts stripped).
- **No settings tab.** `projectsDir`, `recentDays` and the last project live in
  `data.json`; nobody has asked to change the first two.
- **`bats tests/` also runs the plugin's `node --test`**, so one command covers the repo.
  It runs it with a scratch HOME, so the real-vault test (AC-4b) runs only under a plain
  `node --test obsidian-roadmap-view/test/`.

**Review attempt 1 (auto mode)**
- **Fixtures and AC-1/AC-2 carry invented text**, not langlive's: the first version copied
  real headlines, commit hashes, a component name and mockup file names into a public repo.
- **`sn_status` calls source the lib in their own shell**, and a test now checks every call
  site. `stop_infra` is recorded inside `sn_codex_after_exit`, the only place that knows
  the reason. `--discard` removes the status file even when the worktree is already gone.
- **Live refreshes keep the reader in place**: the scroll position, open folds and the big
  現況's height survive a redraw; a redraw waits while the search box has focus.

**Review attempt 2 (auto mode)**
- **The record-the-round block rebuilds its own variables.** Round 1's sourcing made its
  `codex_state_write` run with an empty plan and slot; reproduced and fixed.
- **A thumbnail is sized by its ratio** (`aspect-ratio`), with a pixel height only when the
  pane has a width — a hidden tab has none.
- **Only a leaf whose own search box has focus, in a focused window, waits** for a refresh.

**Claude's calls** (the operator can override)
- **Layout option A (近況 list + detail).** The operator moved to "start building"
  without choosing A vs C. A was the recommendation; C's timeline is a later tab.
- **No 時間軸 tab in v1.**
- **Fixtures are synthetic but format-exact.** The repo is public; langlive's roadmap text
  is company data. A local-only test reads the real vault when it is there.
- **`currentStateDoc` is a string scanner, not `DOMParser`.** It is testable in node and
  behaves the same on every platform. The spike used `DOMParser`; the output is the same.
- **Plain JavaScript, no build, no npm dependencies.** Tests use `node --test` with a
  stubbed `obsidian`. The spike ran this way, and the repo has no JS toolchain to
  maintain.
- **The plugin lives top-level in ai_system** (`obsidian-roadmap-view/`), not under
  `claude-skills/` (R-004: that holds the three skills only).
- **Status files:** one per ship, in a non-dot folder `ship-status/`, so parallel ships do
  not collide and Obsidian Sync carries them.
- **`--summary`** is a new flag; the legacy `--explain [[slug]]` stays.
- **The plugin is not auto-enabled** in `community-plugins.json`.
- **Repo-only files are not linked** (plan, learning).
- **Mockups open with an installed HTML viewer.** The operator has `obsidian-html-plugin`.

## §8 Known risks
- **R1 Phone performance** on very large ROADMAPs (the largest is about 700 KB). Mitigations:
  the 待做 group is collapsed, thumbnails are lazy, parsing runs once per change, and
  re-renders are debounced. AC-10 checks it on the device.
- **R2 Tag formats drift.** Status parsing reads free text. AC-1 pins the formats seen on
  2026-10-25; an unknown format degrades to `todo`, never an error.
- **R3 Sync lag.** "Live" on the phone is as live as Obsidian Sync, usually seconds.
