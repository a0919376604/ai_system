# R-039 Roadmap 檢視「最近」分頁 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** A third tab 「最近」 in Roadmap 檢視 lists every mockup / report / research / architecture / doc HTML changed in the last 7 days across all projects and `20 Research`, grouped by project, with thumbnails and an unread dot.

**Architecture:** Four pure functions (classify, group, title, unread) exported from `main.js` and tested in `parse.test.js`; the view gains a `recent` tab that draws from them, reusing `lazyThumb` / `entryFor` / `openMockup`; the plugin records opened files in its settings and refreshes on vault events for listed paths.

**Tech Stack:** plain CommonJS Obsidian plugin (no build, no npm deps), `node --test` with `test/fake-obsidian.js`.

**Spec:** `docs/specs/R-039-add-recent-tab.md` — read it whole first. Learning to respect: `docs/learnings/R-013-add-obsidian-roadmap-view.md` (never give the View a member named `open`, `load`, `unload` or `close`; `main.js` may require nothing but `obsidian`).

## Global Constraints
- Window: 7 days, a constant `RECENT_DAYS = 7`; research root: constant `RESEARCH_DIR = "20 Research"`; projects root: the existing `settings.projectsDir`.
- Kinds and labels: `mockup` → 「mockup」, `report` → 「報告」, `research` → 「研究」, `architecture` → 「架構圖」, `doc` → 「文件」.
- Tab labels in order: 「近況」「全部」「最近」; tab key `recent`.
- Copy: group header `<group> · N 份`; expander 「看全部 N 份」; empty state 「7 天內沒有新的 mockup、報告或研究」.
- Row meta: local time `HH:MM` today, 「昨天 HH:MM」 yesterday, `MM/DD HH:MM` older; in the `20 Research` group prefix `<where> · ` when `where` is non-empty.
- Settings keys: `opened` (object path → epoch ms), `recentSince` (epoch ms). No settings tab.
- `main.js` stays dependency-free; the thumbnail never runs scripts (reuse the existing renderer).
- Test runs: `node --test obsidian-roadmap-view/test/*.test.js` (use the glob: Node 26 lists nothing for a bare directory, IDEA-005).

## Review Focus
1. A half-synced file whose read throws: the row still shows, titled by its basename, and the tab does not error. → Task 2 test `recent: an unreadable file keeps its row, titled by its name`.
2. Paths with spaces and CJK names (`10 Projects/…/觀察.html`) and an upper-case `.HTML`: classified like any other. → Task 1 test `recentKind: spaces, CJK and .HTML`.
3. A file whose mtime is in the future (another device's clock): listed, first in its group, no crash. → Task 1 test `recentGroups: a future mtime is kept and sorts first`.
4. `opened` holding a path that no longer exists: rendering and saving still work. → Task 3 test `read state: a stale opened path is harmless and pruned`.
5. Tapping a row's thumbnail must open the file, not the zoom modal. → Task 2 test `recent: tapping the thumbnail opens the file`.

---

### Task 1: Pure core — classify, group, title, unread

**Files:**
- Modify: `obsidian-roadmap-view/main.js` (new functions above `// ---- plugin`; extend the `Object.assign(RoadmapViewPlugin, …)` export line)
- Test: `obsidian-roadmap-view/test/parse.test.js`

**Interfaces:**
- Produces:
  - `recentKind(path: string, projectsDir: string, researchDir: string) → "mockup"|"report"|"research"|"architecture"|"doc"|null`
  - `recentGroups(files: {path, mtime}[], now: Date, opts: {projectsDir, researchDir, days}) → {group: string, latest: number, items: {path, kind, mtime, where}[]}[]`
  - `htmlTitle(html: string|null, path: string) → string`
  - `isUnread(item: {path, mtime}, opened: {[path]: number}, since: number) → boolean`
  - all four on `RoadmapViewPlugin` statics.

- [x] **Step 1: Write the failing tests** in `parse.test.js` (`const P = require("./load")`):

```js
const PD = "10 Projects", RD = "20 Research";
test("recentKind classifies by folder (R-039 AC-1)", () => {
  const k = (p) => P.recentKind(p, PD, RD);
  assert.equal(k("10 Projects/a/Proposals/mockups/x.html"), "mockup");
  assert.equal(k("10 Projects/a/Reports/r.html"), "report");
  assert.equal(k("10 Projects/a/Research/sub/r.html"), "research");
  assert.equal(k("20 Research/LLM/r.html"), "research");
  assert.equal(k("10 Projects/a/Architecture/diagrams/html/index.html"), "architecture");
  assert.equal(k("10 Projects/a/Architecture/diagrams/html/jobs.html"), null);
  assert.equal(k("10 Projects/a/Specs/s.html"), "doc");
  assert.equal(k("10 Projects/a/Docs/d.html"), "doc");
  assert.equal(k("10 Projects/a/Reports/x.evidence/index.html"), null);
  assert.equal(k("10 Projects/_archive/Reports/r.html"), null);
  assert.equal(k("10 Projects/a/Reports/_archive/r.html"), null);
  assert.equal(k("10 Projects/a/Reports/r.md"), null);
  assert.equal(k("10 Projects/a/Notes/n.html"), null);
});
test("recentKind: spaces, CJK and .HTML", () => {
  assert.equal(P.recentKind("10 Projects/my proj/Reports/觀察 報告.HTML", PD, RD), "report");
});
const NOW = new Date("2026-10-25T12:00:00Z"), H = 3600e3, DAY = 24 * H;
test("recentGroups: 7-day window, groups by newest, items newest first (AC-2)", () => {
  const f = (path, ago) => ({ path, mtime: NOW - ago });
  const g = P.recentGroups([
    f("10 Projects/a/Reports/old.html", 8 * DAY),
    f("10 Projects/a/Reports/r1.html", 5 * H),
    f("10 Projects/a/Proposals/mockups/m1.html", 1 * H),
    f("10 Projects/b/Reports/r2.html", 2 * H),
    f("20 Research/LLM/x.html", 3 * H),
    f("10 Projects/a/Notes/n.md", 1 * H),
  ], NOW, { projectsDir: PD, researchDir: RD, days: 7 });
  assert.deepEqual(g.map((x) => x.group), ["a", "b", "20 Research"]);
  assert.deepEqual(g[0].items.map((i) => i.path.split("/").pop()), ["m1.html", "r1.html"]);
  assert.equal(g[2].items[0].where, "LLM");
  assert.equal(g[0].latest, NOW - 1 * H);
});
test("recentGroups: a future mtime is kept and sorts first", () => {
  const g = P.recentGroups([{ path: "10 Projects/a/Reports/r.html", mtime: +NOW - H },
    { path: "10 Projects/a/Reports/f.html", mtime: +NOW + H }], NOW, { projectsDir: PD, researchDir: RD, days: 7 });
  assert.equal(g[0].items[0].path, "10 Projects/a/Reports/f.html");
});
test("htmlTitle: first <title>, entities decoded, else the basename (AC-3)", () => {
  assert.equal(P.htmlTitle("<title> A &amp; B &lt;x&gt; &quot;q&quot; &#39;s </title>", "a/b.html"), `A & B <x> "q" 's`);
  assert.equal(P.htmlTitle("<title>  </title>", "a/R-1-x.html"), "R-1-x");
  assert.equal(P.htmlTitle("<p>none</p>", "a/r.html"), "r");
  assert.equal(P.htmlTitle(null, "a/r.HTML"), "r");
});
test("isUnread: changed after opening, never opened, older than since (AC-4)", () => {
  const it = (mtime) => ({ path: "p", mtime });
  assert.equal(P.isUnread(it(30), { p: 20 }, 0), true);
  assert.equal(P.isUnread(it(30), { p: 40 }, 0), false);
  assert.equal(P.isUnread(it(30), {}, 0), true);
  assert.equal(P.isUnread(it(30), {}, 50), false);
});
```

- [x] **Step 2: Run to verify they fail**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: the six new tests fail (`P.recentKind is not a function`); the 73 existing pass.

- [x] **Step 3: Implement the four functions in `main.js`.** `recentKind`: case-insensitive `.html`; reject any segment that ends `.evidence` or equals `_archive`; under `<projectsDir>/<project>/` the first folder decides (`Proposals/mockups` → mockup, `Reports` → report, `Research` → research, `Specs`/`Docs` → doc, `Architecture` → architecture only when the basename is `index.html`); under `<researchDir>/` → research. `recentGroups`: keep entries with a kind and `now - mtime <= days * 864e5`; `group` is the project folder (or `researchDir`); `where` is the folder between `researchDir/` and the file (`""` for projects and for files at the research root); sort items by mtime desc, groups by `latest` desc then name. `htmlTitle`: first `<title>…</title>` (case-insensitive), trim, decode the five entities, fall back to the basename without its extension. `isUnread`: `mtime >= since && !(opened[path] >= mtime)`. Add the four names to the existing export line.

- [x] **Step 4: Run to verify they pass**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: 79 tests, 0 fail.

- [x] **Step 5: Commit**
```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/parse.test.js
git commit -m "feat(R-039): classify and group recent mockups, reports and research"
```

### Task 2: The 「最近」 tab

**Files:**
- Modify: `obsidian-roadmap-view/main.js` (`render`, `draw`, new `readRecent` and `drawRecent` methods, `drawThumb`), `obsidian-roadmap-view/styles.css`
- Test: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Task 1's four functions.
- Produces: view tab key `"recent"`; `readRecent() → Promise<{groups}>` where each item gains `title: string` and `unread: boolean`; `this.recentOpen: Set<string>` (expanded groups); `lazyThumb(box, slot, find, maxHeight, { zoom: false })` skips the zoom listener so the tap reaches the row.

- [x] **Step 1: Write the failing tests** in `view.test.js`. Extend the existing `fakeApp` so `getFiles()` returns `{ path: p, stat: { mtime: fs.statSync(...).mtimeMs } }`, and add a helper `aged(root, rel, ms)` that calls `fs.utimesSync` to set a file's mtime to `NOW - ms`. Use a fixture with 5 recent files in `10 Projects/demo/` (mockups and reports, `<title>`s set), 1 in `10 Projects/other/Reports/`, one 8-day-old file, and the existing `FILES`.

```js
test("最近: three tabs, no picker, groups with counts, 3 rows then 看全部 (R-039 AC-5)", async () => {
  // switch: click the 「最近」 tab button
  // assert: tab texts === ["近況", "全部", "最近"]; no element with class "rv-project"
  // assert: group header texts === ["demo · 5 份", "other · 1 份"] (demo has the newest file)
  // assert: demo shows 3 rows and an element with text "看全部 5 份"; clicking it shows 5 rows
  // assert: the 8-day-old file is absent; the first row's title is its <title>
});
test("最近: a row click opens the file (AC-6)", async () => { /* stub view.openMockup to record the path; click the first row; assert the recorded path */ });
test("recent: tapping the thumbnail opens the file", async () => { /* let the thumbnail draw via `seen(...)`; click the thumbnail box; assert openMockup got the path and no ZoomModal opened */ });
test("recent: an unreadable file keeps its row, titled by its name", async () => { /* app.failRead = "<that file name>"; the row's title is the basename; no .rv-err */ });
test("最近: an empty window says so", async () => { /* only old files: text 「7 天內沒有新的 mockup、報告或研究」 */ });
test("最近: row meta is local time; 20 Research rows carry their folder", async () => {
  // a file aged 1h in demo → meta equals `${HH}:${MM}` from new Date(NOW - 1h) local getters
  // a 20 Research/LLM file → meta starts with "LLM · "
});
```

- [x] **Step 2: Run to verify they fail**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: the new tests fail (no 「最近」 tab).

- [x] **Step 3: Implement.**
  - `render()`: `const data = this.tab === "recent" ? await this.readRecent() : await this.readProject();`.
  - `draw()`: tabs list `[["near","近況"],["all","全部"],["recent","最近"]]`; when `this.tab === "recent"` draw the tab bar without the project `<select>` and call `drawRecent(root, data)` before the no-projects early return.
  - `readRecent()`: `recentGroups(getFiles().map(f => ({path: f.path, mtime: f.stat && f.stat.mtime})), this.plugin.now(), {projectsDir, researchDir: RESEARCH_DIR, days: RECENT_DAYS})`; for every item read `adapter.read` (cache in `this.titles` keyed `path#mtime`; on error use `htmlTitle(null, path)`), set `title` and `unread = isUnread(item, settings.opened || {}, settings.recentSince || 0)`.
  - `drawRecent()`: header per group (`<group> · N 份`), first 3 items unless `this.recentOpen.has(group)`, then the 「看全部 N 份」 control which adds the group and re-renders; each row is a `.rv-card` with a left column (`.rv-top` holding `.rv-dot` when unread and a `.rv-chip .rv-k-<kind>` label; `.rv-title`; `.rv-exp` meta) and a `.rv-thumb` drawn by `lazyThumb(box, "recent|" + path, find, 70, { zoom: false })` where `find` mirrors `nowSource` via `entryFor(path, "now")`; the row's click calls `this.openMockup(path)`.
  - `drawThumb`: add the zoom click listener only when `on.zoom !== false`.
  - `styles.css`: `.rv-dot` (7px green circle, `var(--color-green)`), kind colours `.rv-k-mockup` purple, `.rv-k-report` blue, `.rv-k-research` orange, `.rv-k-architecture` cyan, `.rv-k-doc` muted; `.rv-more` as a tappable accent text line.

- [x] **Step 4: Run to verify they pass**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: all pass.

- [x] **Step 5: Commit**
```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/styles.css obsidian-roadmap-view/test/view.test.js
git commit -m "feat(R-039): 最近 tab grouped by project with thumbnails"
```

### Task 3: Read state and live refresh

**Files:**
- Modify: `obsidian-roadmap-view/main.js` (`RoadmapViewPlugin.onload`, new `markOpened(path)` and `onExternalSettingsChange()`, `saveSettings`)
- Modify: `obsidian-roadmap-view/test/view.test.js` (fake `workspace.on`)
- Test: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: `recentKind`, `isUnread`, the view's 「最近」 rows from Task 2.
- Produces: `plugin.markOpened(path: string) → Promise<void>`; `plugin.onExternalSettingsChange() → Promise<void>` (the Obsidian ≥ 1.5.7 hook); settings `opened`, `recentSince`.

- [x] **Step 1: Write the failing tests.** Add `on: (ev, f) => { (wsHandlers[ev] = wsHandlers[ev] || []).push(f); return { ev }; }` to the fake `workspace`, exposing `wsHandlers` on `app`.

```js
test("first load seeds recentSince; files older than it show no dot", async () => { /* stored=null → plugin.settings.recentSince === +NOW; recent rows have no .rv-dot */ });
test("file-open marks a listed file read; a note is not stored (AC-7)", async () => {
  // stored = { recentSince: 0 } → the newest row has a .rv-dot
  // fire app.wsHandlers["file-open"][0]({ path: thatPath }); await flush(); await view.render()
  // assert plugin.stored.opened[thatPath] === +NOW and that row has no .rv-dot
  // fire file-open for "10 Projects/demo/notes.md" → not in plugin.stored.opened
});
test("read state: a stale opened path is harmless and pruned", async () => {
  // stored = { recentSince: 0, opened: { "10 Projects/demo/Reports/gone.html": +NOW - 1000, "x.html": +NOW - 8 * DAY } }
  // render 最近 without error; after markOpened(a listed path) the 8-day-old entry is gone, the fresh one stays
});
test("a vault event on a listed path refreshes even with no project on screen (AC-8)", async () => {
  // plugin.current = null; spy plugin.refreshSoon; fire app.handlers.create[0]({ path: "10 Projects/other/Proposals/mockups/new.html" })
  // assert the spy ran; fire for "10 Projects/demo/Notes/n.md" → it did not
});
test("external settings change merges opened, later time wins (AC-12)", async () => {
  // plugin.settings.opened = { a: 10, b: 30 }; plugin.stored = { opened: { a: 20, c: 5 } }
  // await plugin.onExternalSettingsChange(); assert.deepEqual(plugin.settings.opened, { a: 20, b: 30, c: 5 })
});
```

- [x] **Step 2: Run to verify they fail**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: the five new tests fail.

- [x] **Step 3: Implement.**
  - `onload`: after loading settings, `this.settings.opened = { ...(this.settings.opened || {}) }`; when `recentSince` is absent set it to `+this.now()` and `saveSettings()`.
  - Inside `onLayoutReady`: `this.registerEvent(this.app.workspace.on("file-open", (f) => this.markOpened(f && f.path)))`; in the vault-event handler also refresh when `recentKind(p)` or `recentKind(oldPath)` is non-null (projectsDir from settings, `RESEARCH_DIR`).
  - `markOpened(path)`: ignore unless `recentKind` is non-null; set `opened[path] = +this.now()`; `saveSettings()`; `refreshSoon()`.
  - `saveSettings()`: before saving, drop `opened` entries older than `RECENT_DAYS` from `now()`.
  - `onExternalSettingsChange()`: `const disk = (await this.loadData()) || {}`; `this.settings = Object.assign({}, DEFAULTS, disk, { opened: merged })` where `merged` keeps the larger time per path from memory and disk; `refreshSoon()`.

- [x] **Step 4: Run to verify they pass**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: all pass.

- [x] **Step 5: Commit**
```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/view.test.js
git commit -m "feat(R-039): unread dots follow file-open and merge across devices"
```

### Task 4: Real-vault check and full suites

**Files:**
- Test: `obsidian-roadmap-view/test/local-vault.test.js`

- [x] **Step 1: Add the local-only test (AC-10)**, skipped like its neighbours when no vault is configured:

```js
test("the real vault: recent items have titles and no .evidence paths", { skip: !V && "no vault on this machine" }, () => {
  // walk V for files under "10 Projects" and "20 Research" with their mtimes (fs.statSync(...).mtimeMs)
  // run P.recentGroups(files, new Date(), { projectsDir: "10 Projects", researchDir: "20 Research", days: 7 })
  // for every item: !item.path.includes(".evidence/") and P.htmlTitle(fs.readFileSync(...), item.path).length > 0
});
```

- [x] **Step 2: Run the node suite**
Run: `node --test obsidian-roadmap-view/test/*.test.js`
Expected: all pass (the local test runs on this machine).

- [x] **Step 3: Run the bats suite once**
Run: `cd claude-skills/ship-workflow && bats tests/ 2>&1 | grep -E '^not ok|^1\.\.'`
Expected: only `not ok … cwd-guard: exits 0 when not in a git repo at all`.

- [x] **Step 4: Guard the diff scope**
Run: `git diff --name-only main...HEAD`
Expected: only `docs/specs/R-039-add-recent-tab.md`, `docs/plans/R-039-add-recent-tab.md` and files under `obsidian-roadmap-view/`.

- [x] **Step 5: Commit**
```bash
git add obsidian-roadmap-view/test/local-vault.test.js
git commit -m "test(R-039): real-vault recent items have titles"
```

AC-11 (desktop look) and AC-13 (phone) run after landing, once `./sync.sh restore` copies the plugin into the vault; they are not executor tasks.

## Execution log

- 前置檢查：分支為 `ship/R-039-add-recent-tab`，工作目錄乾淨；已讀取 TDD、ponytail、spec 與 R-013 learning。基準 Node 測試 73/73 通過。
- 介面檢查：Task 1 → Task 2 的四個純函式、Task 2 → Task 3 的最近列與 settings、Task 1 → Task 4 的匯出介面相符。
- Task 1：六個新增測試因函式尚未匯出而失敗；實作後指定 Node suite 79/79 通過。
- Task 2：六個新增測試先因缺少「最近」分頁失敗；實作後修正完整測試抓到的明細消失時分頁選取回歸；指定 Node suite 85/85 通過。
- Deviation: 更新既有 onload guard 測試的完整 settings 與事件期望，加入 `opened`、`recentSince`、`file-open` — 計畫新增的介面讓舊期望失效；保留完整相等斷言。
- Task 3：五個新增測試先失敗；實作與上述 guard 更新後，指定 Node suite 90/90 通過。
- Task 4：加入唯讀 real-vault 測試並於本機實際執行；Node suite 91/91 通過（無 skip）。Bats 跑過 896 項，唯一失敗為已知基準 `not ok 203 cwd-guard: exits 0 when not in a git repo at all`。
- 範圍檢查：`git diff --name-only main...HEAD` 僅含既定 spec、plan 與 `obsidian-roadmap-view/`；未推送，未寫入 vault 或使用者的 `~/.claude/`。AC-11、AC-13 依計畫留待 landing 後驗收。
- 最終唯讀分支審查：五個 Review Focus 均覆蓋，無 Critical 或 Minor；兩個 Important 已由執行者新增失敗測試重現後修正。
- Deviation: 預設外部程式成功開檔後呼叫 `markOpened` — 此開檔分支不會發出 workspace `file-open`，原計畫的事件掛鉤不足以滿足 spec §3.3 的分頁開檔已讀要求；修正在既有 `openMockup` 內完成。
- Deviation: 外部設定缺少 `recentSince` 時保留本機值 — 原計畫直接替換 settings 會丟掉首次啟用基準，讓原本已抑制的舊檔重新出現綠點。
- 審查修正驗證：`recent: opening with the default app marks the file read` 與 `external legacy settings preserve the launch unread baseline` 先失敗，再通過；最終指定 Node suite 93/93 通過（real-vault 執行、無 skip）。Bats 已依 Task 4 跑過一次，結果如上。
- 最終狀態：DONE_WITH_CONCERNS；三項小型偏差皆已記錄且已修正，唯一 suite 失敗為上述已知基準。分支與 worktree 保留，未推送；桌面／手機驗收維持 landing 後執行。
