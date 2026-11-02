---
date: 2026-11-03
updated: 2026-11-03
type: learning
id: R-030
tags: [learning, ai_system, arch-diagram, mobile, css, security]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-030
shipped: true
shipped-date: 2026-11-03
---

## For future Claude
> R-030 made `/arch-diagram` pages readable on a phone. Below 700 px, each diagram pans
> horizontally in a `.pan` box at 80 % of its canvas width, under 「← 左右滑動看整張圖 →」, and
> the condition table becomes one card per row. Desktop output is byte-identical to before.
>
> **Headline lesson:** the moment a spec value moves into a new HTML context, it needs its own
> validation there. `canvas.w` had been harmless inside `viewBox`. Copied into a `style` attribute,
> a string value became `url(//…)` and the browser fetched it, because `render.py` runs without
> `check.py`. HTML escaping does not make a value safe as CSS.

## What Shipped
- **`render.py`:**
  - `pan()` wraps every diagram (the main one and each route copy) in a `.pan` box under the hint.
  - `<svg>` gets `style="--w:<canvas.w>px"`.
  - The phone block, `@media (max-width:700px)`, holds the 80 % width, card rules with 做什麼／條件
    labels, wrapping titles and tighter chrome.
  - `render_svg` refuses a canvas size that is not a finite positive number, exiting 2 with no output.
- **Tests:** three new, 65/65 in the scoped suite.
- **The langlive-line-oa pack is re-rendered.**

## Key Decisions
- The operator: 「html目前有一個問題 在手機上不好讀」, then 「Ok」 to the prototype. The prototype was a
  panning diagram at a readable size plus table cards, shipped through `/ship-next` auto.
- **Door: two-way.** It is CSS and one wrapper element.
- **Claude's calls:**
  - the width is 80 % of the canvas through a CSS variable, rather than a fixed 980 px, so text
    size is the same on every canvas;
  - the browser's own pinch-zoom instead of JS;
  - the small-change lane with the inline executor.

## What Changed From Plan
- **Small-change lane: there was no plan file.** Review attempt 1 led to a fix-plan, and its
  findings were reproduced first:
  - a string `canvas.w` injected CSS — blocking;
  - long titles overflowed the phone cards.
- **Attempt 2 was clean.** Three cheap nits were taken: reject NaN and Infinity, move the hint
  styling inside the phone block, and declare both behaviours in the spec's Seams.

## Bugs
- **CSS injection through `canvas.w`,** introduced by this ship and caught in review attempt 1.
  `attr()` HTML-escapes values, but `;`, `:` and `url(` pass through it. `esc()` turns `http:` into
  `http&#58;`, but the browser decodes that before parsing the CSS, and a protocol-relative
  `url(//…)` is not touched at all.
- **The prototype's hint never showed,** because the hidden rule came after the media block.
- **Headless Chrome's minimum window is 500 px,** so "390 px" screenshots looked cut off. A real
  390 px check needs an iframe harness.

## Lessons → checks
- Validate a spec value inside the renderer itself whenever it moves into a new HTML context (attribute, style, URL); escaping is not validation — enforced by `bats tests/test_arch-diagram.bats -f 'non-numeric canvas'` · proof: red at 3a98c61 (exit 1) · green at 73e6c44
- Take narrow-viewport screenshots through an iframe of that width; headless Chrome's window is never narrower than 500 px — judgment

## Reusable Patterns
- **Pan instead of shrink.** A wide diagram on a phone stays at about 80 % scale inside an
  `overflow-x:auto` box, with a one-line hint. Text stays legible and no JS is needed.
- **Table → cards with pure CSS.** Set `display:block` on the table parts, hide `thead`, and give
  each cell a `::before` label.

## Technical Debt
- **Phone-CSS test:** it checks rules from `@media` to the end of the CSS, not inside the block.
  Moving a rule out of the block would not fail it.
- **Scrollbar track:** `.pan` shows a light track on desktops narrower than 700 px that use classic
  scrollbars. `color-scheme:dark` would fix it.
- **Keyboard access:** `.pan` is not keyboard-focusable (no `tabindex`).

## Future Follow-ups
- Same as R-029: IDEA-001…003, and the line-oa findings still to verify.
