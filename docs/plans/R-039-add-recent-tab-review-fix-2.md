# R-039 review fix 2 — Implementation Plan

> **For agentic workers:** execute task by task with TDD; one commit per task.

**Goal:** Clear review attempt 1 of R-039: 1 blocking, 2 important and 7 nits (report `/tmp/ship-next-review-R-039-1.md`; operator: 「都修」).

**Spec:** `docs/specs/R-039-add-recent-tab.md` as of `fc3c0fa` — §3.3, §3.4, the `title reads`, `read state`, `launch baseline` and `refresh` Seams rows, AC-8 and AC-12 changed. Read them first.

## Global Constraints
- Same as the main plan (`docs/plans/R-039-add-recent-tab.md`): `main.js` requires only `obsidian`; no View member named open/load/unload/close; tests run with `node --test obsidian-roadmap-view/test/*.test.js`.
- Do not change 近況／全部 behaviour beyond what a task names.

---

### Task 1: External settings change merges only `opened` (blocking)

**Files:** `obsidian-roadmap-view/main.js` (`onExternalSettingsChange`), `obsidian-roadmap-view/test/view.test.js`

- [x] **Step 1: Failing test** — extend the AC-12 test (or add `external settings change keeps this device's project and detail page`): view on project `demo` with R-3's detail open, `plugin.settings.opened = { a: 10, b: 30 }`; `plugin.stored = { project: "other", recentSince: 1, opened: { a: 20, c: 5 } }`; `await plugin.onExternalSettingsChange(); await flush();` → `plugin.settings.opened` deep-equals `{ a: 20, b: 30, c: 5 }`, `plugin.settings.project === "demo"`, `plugin.settings.recentSince` unchanged, and after a render the detail page for R-3 is still shown.
- [x] **Step 2:** run, expect FAIL (project becomes `other`).
- [x] **Step 3:** `onExternalSettingsChange`: keep only the merge — `this.settings.opened = merged; this.refreshSoon();`. Remove the whole-object replacement and the now-unneeded `recentSince` special case; keep the existing legacy-baseline test green.
- [x] **Step 4:** run the suite, expect PASS.
- [x] **Step 5:** `git commit -m "fix(R-039): an external settings change merges only the read state"`

### Task 2: Read titles only for drawn rows; stop when stale (important)

**Files:** `obsidian-roadmap-view/main.js` (`render`, `readRecent`), `obsidian-roadmap-view/test/view.test.js`

- [x] **Step 1: Failing tests**
  - `recent: titles are read only for the rows drawn` — fixture with 5 recent files in one group; wrap `app.vault.adapter.read` to record paths; open 最近 → exactly the 3 drawn paths were read for titles (thumbnail reads go through `entryFor`; exclude them by stubbing `IntersectionObserver` as the file already does, so no thumbnail is drawn); click 「看全部 5 份」 → the other 2 are read.
  - `recent: a replaced render stops reading` — make `adapter.read` for the first file wait on a promise you control; start `view.render()` on 最近, then start a second `view.render()`; resolve the promise; assert the first render read no further files after resolving (count reads made after the release attributable to the stale render: 0).
- [x] **Step 2:** run, expect FAIL.
- [x] **Step 3:** `readRecent(n)` takes the render number; for each group take `this.recentOpen.has(group) ? items : items.slice(0, 3)`; read the missing titles with `Promise.all`; after each await, return `null` when `n !== this.renders`, and `render()` returns early on `null`. Rows not drawn keep no title (they are not shown).
- [x] **Step 4:** run, expect PASS.
- [x] **Step 5:** `git commit -m "perf(R-039): read titles only for drawn rows and drop stale renders"`

### Task 3: Recent-path refresh only while 最近 is shown; no save on re-open (important + nit)

**Files:** `obsidian-roadmap-view/main.js` (vault event handler in `onload`, `markOpened`, the `file-open` handler), `obsidian-roadmap-view/test/view.test.js`

- [x] **Step 1: Failing tests**
  - Update the AC-8 test: with a leaf whose view is on 最近 (pass `leaves` to `fakeApp`), a `create` for `10 Projects/other/Proposals/mockups/new.html` (written to disk, mtime NOW) calls `refreshSoon`; after advancing past the debounce and rendering, the first row of the first group is `new.html`'s title. With the same leaf on 近況 (`view.tab = "near"`), the same event does not call `refreshSoon`.
  - `file-open on an already-read file saves nothing` — `opened[path] = +NOW`, file mtime `NOW - 1h`; spy `plugin.saveData`; fire `file-open` with the TFile-like `{ path, stat: { mtime } }` → no save; with `opened[path]` older than mtime → one save.
- [x] **Step 2:** run, expect FAIL.
- [x] **Step 3:** in the vault handler, OR the `recentKind` clause with `this.app.workspace.getLeavesOfType(VIEW).some((l) => l.view && l.view.tab === "recent")`; `markOpened(path, mtime)` returns early when `opened[path] >= mtime` (the `file-open` handler passes `f.stat && f.stat.mtime`; the `openMockup` path passes the file's mtime).
- [x] **Step 4:** run, expect PASS.
- [x] **Step 5:** `git commit -m "fix(R-039): refresh for recent paths only on 最近; skip saves on re-open"`

### Task 4: Test-quality nits

**Files:** `obsidian-roadmap-view/test/local-vault.test.js`, `obsidian-roadmap-view/test/view.test.js`, `obsidian-roadmap-view/test/parse.test.js`

- [x] **Step 1:** AC-10: assert each real item's `htmlTitle(...)` differs from its basename without extension (a real `<title>` was found), not merely non-empty.
- [x] **Step 2:** replace the 「看全部」 `style.display/visibility` check with `assert.ok(more)`.
- [x] **Step 3:** split the AC-5 test so each of these is its own test: tabs/picker/headers/3-then-expand (AC-5 proper), first row's title is its `<title>`, the 8-day-old file is absent, expansion survives a re-render.
- [x] **Step 4:** add `recentGroups: the 7-day boundary is inclusive` — an item at exactly `now - 7 days` is kept, one at `now - 7 days - 1 ms` is dropped.
- [x] **Step 5:** the `recentSince` assertions now match the declared `launch baseline` Seam — keep them.
- [x] **Step 6:** run `node --test obsidian-roadmap-view/test/*.test.js`, expect all PASS; then `cd claude-skills/ship-workflow && bats tests/ 2>&1 | grep -E '^not ok|^1\.\.'`, expect only the known `cwd-guard` failure.
- [x] **Step 7:** `git commit -m "test(R-039): sharpen weak and bundled recent-tab tests"`

## Execution log

- Task 1: complete — AC-12 failed with `other !== demo` before the fix; Node suite 93/93 passed after merging only `opened`, including the legacy-baseline test.
- Task 2: complete — both new tests failed before the fix (5 reads for 3 rows; 5 reads after replacement). Titles now load in parallel per drawn group and stale renders stop before further groups; Node suite 95/95 passed.
- Deviation: Task 3 Step 3 says to OR the `recentKind` clause with the 最近-pane check; used AND around the combined new/old-path clause — OR contradicts §3.4, the refresh Seam, AC-8, and Task 3's own test. Existing watched-project and ROADMAP refresh clauses remain unchanged.
- Task 3: complete — AC-8 failed on the unwanted 近況 refresh and the read-state test failed on a redundant save before the fix. The 500 ms refresh displays the new row first, repeated/equal-mtime opens save nothing, and Node suite 96/96 passed.
- Task 4: complete — strengthened the real-vault title assertion, split AC-5 into four behaviors, retained launch-baseline assertions, and added the inclusive boundary test. Node suite 100/100 passed (including real-vault tests); bats completed 896 tests with only the known `cwd-guard: exits 0 when not in a git repo at all` failure (test 203).
- Final read-only review: no Critical, Important, or Minor findings. Existing refresh fan-out and future-mtime behavior remain outside this fix; the approved title inequality and cancellation of subsequent groups were verified without reopening those decisions.
- Result: DONE_WITH_CONCERNS — all four tasks complete; the Task 3 wording correction above is the sole plan deviation. Branch and worktree retained; no push, amend, hook bypass, or vault writes.
