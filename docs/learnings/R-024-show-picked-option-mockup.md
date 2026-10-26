---
date: 2026-10-27
updated: 2026-10-27
type: learning
id: R-024
tags: [learning, ai_system, obsidian-plugin, roadmap, mockup]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-024
shipped: true
shipped-date: 2026-10-27
---

## For future Claude
> R-024 changes Roadmap 檢視 (`obsidian-roadmap-view/main.js`, R-013) in two ways.
> **完成條件** is now a bulleted list: `splitConditions` splits at top-level `；`, `;` and ` · `.
> **Picked options** are now shown: `pickedOf` reads the picked option, `optionDoc` finds that
> option's panel in the mockup, and the view shows it.
> For a done item, the card thumbnail is the picked option, not 現況. The detail page shows
> 採用方案 X first, then 現況.
> Matching rule: the heading right before the panel, or the panel's own first heading, must
> *start with* 方案/版面 X (optionally after `N · `). Failing that, the class `opt<X>` is used.
> An unclosed panel ends where the next one starts. Across mockups, a label match wins.

## What Shipped
- **`splitConditions(text)`**, a pure function. Brackets, quotes and backticks protect what is
  inside them.
- **`picked`** comes from one of:
  - `mockup 定案 X` on the row;
  - `方案 X 定案` on the row;
  - the first `方案 X` on a `↳` line that mentions a mockup (never a done-when line).
- **`optionDoc(html, picked) → {doc, label, by}`** shares `panelsOf`/`wrapDoc` with
  `currentStateDoc`. Scripts are stripped and the iframe is sandboxed, as before.
- **The view**:
  - 完成條件 is rendered as a `<ul>`;
  - the 採用方案 X section is hidden until the option is found, and removes itself when there is
    no match;
  - a done card shows the option, falling back to 現況;
  - the cache is keyed `path#now|opt:X` + mtime, and thumbnail slots are keyed by project +
    role + id.
- **Tests**: 73 node tests, up from 49. One local-only test checks the real vault: all 11 picked
  rows in langlive-line-oa resolve.

## Key Decisions
- **Card thumbnail for a done item = the picked option** (operator: 「採用的方案（推薦）」). The
  detail page shows the option first, then 現況.
- **Match by heading before class.** In the vault, 「版面甲」 sits in `optB`, so 甲 ≠ `optA`.
- **A heading must *start with* 方案/版面 X.** R-250's supplementary `optB` panel only mentions
  方案 B. The spec first said "contains"; the spec review caught the mismatch.
- **Never read 方案 X from a done-when line.** R-024's own done-when said 「mockup 定案 X 或 方案
  X」.
- **Not-done items keep 現況 on the card**, and their detail page still shows the decided option.
- **No `### section heading` inheritance in v1.**
- **Fixtures are invented** (the repo is public). Door: two-way.

## What Changed From Plan
- The main plan's 2 tasks ran as written: codex, 2 commits, no repairs.
- **Review attempt 1** (spec + correctness + races): 5 blocking, 1 important, 5 nits. Review-fix-2
  fixed them (2 tasks, codex).
  - Three blocking findings came from checking claims against the vault: unclosed panels, the
    `方案 X 定案` row form, and the cross-mockup order.
  - The other two were spec mismatches.
- **Review attempt 2** found 0 blocking, 1 important (a test gap) and 4 nits. I fixed them inline
  after the gate, with TDD, in two commits.
- **Security pass**: no findings.
- **main moved during the ship** (R-023 and R-019 landed). The squash merged cleanly, and
  bats 718/718 passed on the merged main.

## Bugs
- **An unclosed `optB` gave its heading to the next panel.** In insights-handoff-reasons, 甲
  returned 乙's panel (未選), captioned 「版面甲」. The fix: an unclosed option, 現況 or facts
  panel ends at the next one.
- **`方案 X 定案` on the row was not read.** The three newest done items (R-253 to R-255) showed
  no option at all.
- **A class match in mockup 1 beat a label match in mockup 2** (R-257).
- **A test read the label's text while it was `display:none`.** Deleting the code that un-hides
  it left all 71 tests green.
- **The prototype changed the label rule and the spec still said "contains"**. The spec review
  caught it as `[spec:wrong]`.

## Reusable Patterns
- **Mockup option convention.** A mockup's options are `.panel.opt<X>`, titled by the heading
  right before the panel, as in 「方案 B · …」 or 「4 · 方案 A · …」. Match by title first, class
  second.
- **Prove a parser against the real corpus before review.** Run it read-only over every vault
  file and print the result per row. In R-024 that found 3 of the 5 blocking bugs.
- **Remembered sizes need a fallback key** (`on.presize`). The first open of a detail page can
  then start at the card's measured height.

## Lessons → checks
- When a prototype changes a rule the spec states, edit the spec in the same step — judgment
- Before review, run a parser change over every real vault file and print its per-row result; fixtures miss the real forms — judgment
- A test of something shown asserts it is visible, not only that its text exists — judgment

## Technical Debt
- **Two cache entries per mockup.** The 現況 entry and each option entry read the same file
  separately. They are cached per mtime, and the vault has at most 2 mockups per picked item.

## Future Follow-ups
- **AC-11** (operator, on the phone): a done item with 方案 B shows the option; 完成條件 reads
  well.
- **A row with two mockups whose picks differ** (R-257: 版面甲 for one, 方案 B for the other)
  shows a single option. Show one per mockup if that turns out to matter.
- **Inherit 定案 from a `###` section heading** (`… mockup 定案 甲`) if rows under such headings
  should show it.
