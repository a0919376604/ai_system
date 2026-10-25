---
date: 2026-10-26
updated: 2026-10-26
type: learning
id: R-013
tags: [learning, ai_system, obsidian-plugin, mobile, ship-status, roadmap]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-013
shipped: true
shipped-date: 2026-10-26
---

## For future Claude
> R-013 adds **Roadmap 檢視**, an Obsidian plugin in `obsidian-roadmap-view/`. It is plain CommonJS
> with no build; its tests run with `node --test obsidian-roadmap-view/test/` against a fake `obsidian`
> module, and `bats tests/` runs them too. The plugin is a live, read-only, phone-first view of one
> project's ROADMAP. ship-next feeds it through `sn_status`, which writes
> `<vault project>/ship-status/<ID>.json` at every phase. `./sync.sh restore` copies the three plugin
> files into `<vault>/.obsidian/plugins/roadmap-view/`; enabling the plugin is a one-time click in Obsidian.

## What Shipped
- **The plugin**:
  - pure core: `parseRoadmap`, `mockupsFor`, `statusOf`, and a string-scanned `currentStateDoc` that
    returns the mockup's 現況 panel and its styles;
  - an `ItemView` with a 近況/全部 view, a project picker, a detail page with spec, brainstorm and mockup
    links, folds, and a jump to the ROADMAP line;
  - lazy thumbnails: at most 2 render at once, each in a sandboxed iframe, cached per mtime, with a zoom
    modal (符合寬度/2×/3×);
  - a re-render on vault events, debounced 500 ms.
- **`sn_status <worktree> <phase> [note]`**:
  - It is called at every ship-next phase, on each stop path, by `--discard` (which deletes the file)
    and by `/ship-land` (which writes done).
  - It never fails the ship: it prints one WARN and returns 0, never creates a project folder, and
    refuses an unknown phase or an ID that is not a plain `R-…`.
- **`roadmap-insert.sh --summary`** writes a plain zh-TW `↳ explain:` line. `--adhoc` passes it.
- **`sync.sh`**: `restore` copies the plugin only when a file differs; `status` prints an
  `obsidian plugin:` line.
- **Tests**: 49 node tests and 27 new bats tests. One node test runs only on this machine: it parses
  every real vault ROADMAP and mockup.

## Key Decisions
- **A plugin, not a more readable ROADMAP.** ROADMAP.md stays written for AI; the plugin chooses what a
  person sees (operator).
- **Live, not a snapshot.** At four or five items a day, `/ship-brief` and the daily board were always
  stale (operator).
- **One project at a time, phone-first.** For that reason the 4-column board, option B, was dropped
  (operator).
- **The thumbnail is the mockup's 現況 panel, and a tap zooms it.** Both were confirmed on the phone
  with the spike (operator).
- **A string scanner, not DOMParser.** It is testable in node and behaves the same on every platform.
- **Fixtures are invented but keep the exact row formats.** The repo is public; langlive's ROADMAP is
  company data.
- **The row regex was widened from real data.** The first version missed `(epic)` inside the bold,
  ids such as `R-193.3a-2.1`, `~~struck~~` rows, `- [~]` rows and `- [X]` rows.
- **Mockup scripts never run.** The iframe is `sandbox="allow-same-origin"`, with the sandbox and
  srcdoc attributes set before it is inserted, and `<script>` is stripped.
- **One status file per ship, in a folder whose name does not start with a dot**, so Obsidian Sync
  carries it and parallel ships never collide.
- **No settings tab, no 時間軸 tab, and not auto-enabled.**

## What Changed From Plan
- The main plan's 6 tasks ran exactly as written: codex made 6 commits with no deviations.
- **Review attempt 1** had 5 blocking, 8 important and 11 nits, fixed by review-fix-2 (4 tasks). The
  blocking ones:
  - company data in the fixtures;
  - four `sn_status` calls in shells that never sourced the lib;
  - a re-render that jumped the scroll position;
  - dropped `[~]` rows;
  - a `load()` method that replaced Obsidian's own `Component.load()`.
- **Review attempt 2** had 1 blocking, 2 important and 3 nits, fixed by review-fix-3 (2 tasks). The
  blocking one was round 1's own regression, described under Bugs.
- **Review attempt 3** and the security pass found nothing blocking.

## Bugs
- **`async load()` on the view replaced `Component.load()`.** `View.open()` calls `this.load()` and
  then `onOpen()`. With the override, the view's lifecycle never ran and every open read the project
  twice. This is the same trap as the spike's `this.open` field, which blanked the pane. Never give a
  View member the name `open`, `load`, `unload` or `close`; a test now checks this.
- **The real-data test was as blind as the parser.** The local test counted rows with the same `[ x]`
  pattern as the parser, so the 10 `- [~]` rows were missing from both and the test passed.
- **Sourcing the libs in the stop_exhausted block made it worse.** That block's variables were set in
  another shell, so `codex_state_write` began writing an empty plan and slot, where on main it had
  failed with command not found and written nothing. Reproduced in a fresh bash: it printed
  `integer expression expected` and routed to relaunch.
- **Re-renders: the scroll position, open folds and the big image's height were lost.** A width
  measured in a hidden pane is 0, so a refresh in a background tab sized the big 現況 for 300 px. Size
  it with `aspect-ratio` instead.
- **bats silently skipped a test with 「檢視」 in its name.** Under the replay's locale it printed
  `bats warning: Executed 9 instead of expected 10 tests`, with no `not ok`.
- **`sn_ship_body` looks for `↳ done when:` only on the line right after the row.** R-013's done-when
  was on the second line, so the squash body had to be filled in by hand. This is pre-existing.

## Reusable Patterns
- **An Obsidian plugin without a build.** One CommonJS `main.js` that requires only `"obsidian"`, with
  the pure functions as static members. The tests answer `require("obsidian")` through a
  `Module._load` hook, and a fake `El` (createEl/createDiv/fire) is enough to drive the view.
- **Showing untrusted HTML inside Obsidian.** Use a srcdoc iframe with
  `sandbox="allow-same-origin"` and no `allow-scripts`. Its height stays readable, but nothing in it
  runs with the app's origin.
- **A live view keyed by screen.** Keep the scroll position when the same screen redraws; reset it
  only when the screen changes. Hold a redraw only while this leaf's own input has focus in a focused
  window. Use a generation counter so thumbnails from an old render neither hold nor add slots.
- **Prototype → patch → replay.** Replay red/green in a real linked worktree of the branch. Assert
  that the number of bats tests that ran equals the number declared, and diff the final tree against
  the prototype.

## Technical Debt
- **The status files are read again on every render** (ponytail: they are not indexed). They
  accumulate at one per ship.
- **Memory of thumbnail iframes on a long 全部 list is unmeasured.** AC-10 on the phone decides it.

## Future Follow-ups
- **AC-10 and AC-11 need the operator to confirm on the phone:**
  - **AC-10:** the 近況 list and R-248's 現況 zoom are readable;
  - **AC-11:** a desktop edit re-renders after Obsidian Sync.
- **Pre-existing:** in ship-next.md Phase 5, the launch and "When codex exits" blocks read `PLAN`,
  `SLOT` and `CODEX_ATTEMPT`, which only step 4's shell sets. The record block reads `CODEX_CLASS`,
  `CODEX_NOTE` and `CODEX_BLOCKED_AT` from a separate block. Rebuild them from `state.env` and the
  supervise state, as review-fix-3 did for the record block.
- **Pre-existing:** `sn_ship_body` should search all of the row's `↳` lines for the done-when.
- **This ship's reviewers never saw `.ship/review-extra-checks.md`,** so its test-quality tags were not
  applied. Pass the file to the reviewers in the next ship.
- **Later:** a 時間軸 tab built from `ship-status/*.json`. Retiring `daily-board-refresh.sh` is the
  operator's call.
