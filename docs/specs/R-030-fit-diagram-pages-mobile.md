---
date: 2026-11-03
updated: 2026-11-03
type: spec
id: R-030
status: draft
tags: [spec, ai_system, arch-diagram, mobile]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-030
related-specs: [R-029]
mockup: "Proposals/mockups/arch-diagram-mobile-prototype-{overview,langgraph}.html"
supersedes: null
---

## For future Claude
> R-030 makes `/arch-diagram` pages readable on a phone. Below 700 px:
> - every diagram sits in a horizontally scrollable `.pan` box at 80 % of its canvas width,
>   under the hint 「← 左右滑動看整張圖 →」;
> - the condition table becomes one card per row.
>
> Above 700 px the page renders as before. Only `render.py`'s page markup and CSS change.

## §1 Problem
The operator: 「html目前有一個問題 在手機上不好讀」. At 390 px wide:
- The 1200 px diagram shrinks to fit the screen, which leaves node text at 3–4 px.
- The four-column condition table squeezes 「什麼條件走到這、離開時往哪」 to about one character per line, so a single row spans several screens.

The operator approved the prototype (「Ok」) in
`Proposals/mockups/arch-diagram-mobile-prototype-{overview,langgraph}.html`.

## §2 Goals, non-goals
**Goals**
- G1. **Diagrams pan on a phone.** Below 700 px, each diagram (the main one and every route copy) sits in a `.pan` box that scrolls horizontally. Its SVG is 80 % of the canvas width, so 13 px titles render at about 10 px. The hint 「← 左右滑動看整張圖 →」 sits above each box.
- G2. **The condition table becomes cards below 700 px.** The header row is hidden. Each row is one card, in this order:
  - the node title, bold;
  - 「做什麼」 and its text;
  - 「條件」 and its text;
  - the code citation, small and wrapping anywhere.
- G3. **Phone chrome is tighter.** The page padding is 16 px, `h1` is 20 px, and the subtitle wraps.
- G4. **Desktop is unchanged.** Above 700 px the hint is hidden and nothing else changes visibly.
- G5. **The langlive-line-oa pack is regenerated** with the new renderer. A real 390 px screenshot of the pages shows readable diagram text and cards.

**Non-goals:** pinch-to-zoom handling (the browser's own is enough), JS, a separate portrait layout, and any spec-format change.

## §3 Design
- **Markup.** `render_page` emits `<p class="pan-hint">← 左右滑動看整張圖 →</p><div class="pan">…svg…</div>` for the main diagram and for each route copy.
- **SVG width.** `render_svg` adds `style="--w:<canvas.w>px"` to its `<svg>`. `render_svg` refuses any `canvas.w`/`canvas.h` that is not a finite positive number before writing the attribute (review attempt 1 showed a string could inject CSS when `render.py` runs without `check.py`).
- **CSS** gets one rule outside any query, plus one media block.
  - Outside any query: `.pan-hint{display:none}`.
  - Inside `@media (max-width:700px){…}`:
    - `main` padding 16 px; `h1` 20 px; `.sub` 12 px with `overflow-wrap:anywhere`;
    - `.pan{overflow-x:auto}` with a 1 px `#1e293b` border and `border-radius:8px`;
    - `.pan svg{width:calc(var(--w)*0.8);max-width:none}`;
    - `.pan-hint{display:block}`;
    - `table.cond` and its `thead`, `tbody`, `tr` and `td` become `display:block`, and `.cond thead` is `display:none`;
    - `.cond tr` is a bordered, rounded card; `.cond td` has no border;
    - the first cell is bold at 15 px;
    - cells 2 and 3 get `::before` labels 「做什麼　」 and 「條件　」 in `#64748b`;
    - cell 4 is 11 px with `overflow-wrap:anywhere`.
- **Order.** The hidden hint rule comes before the media block, so the phone rule wins.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| pan box | `render.py page` output | each diagram SVG (main + one per route) is inside exactly one `<div class="pan">`, immediately preceded by one `<p class="pan-hint">← 左右滑動看整張圖 →</p>`; each `<svg>` carries `style="--w:<canvas.w>px"` |
| phone CSS | the page's `<style>` | `.pan-hint{display:none}` appears before one `@media (max-width:700px)` block, which holds the §3 rules: `.pan-hint{display:block…}` (the hint shows and is styled), the 80 % SVG width, `.cond thead{display:none}`, and the card rules with the 「做什麼」/「條件」 labels |
| canvas size | `render.py page` | a `canvas.w` or `canvas.h` that is not a finite positive number (string, bool, NaN, Infinity, object) → exit 2, no output file; it never reaches the `style` attribute |
| card wrap | phone CSS | the first card cell (node title) wraps anywhere, so a long title never runs past the card |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | the `clean.json` fixture (one route) | `render.py page` | two `.pan` boxes, each preceded by the hint, each SVG with `style="--w:600px"`; output still byte-identical across two runs |
| AC-2 | the `minimal.json` fixture (no routes, no conditions) | `render.py page` | one `.pan` box and one hint |
| AC-3 | any rendered page | its `<style>` is read | `.pan-hint{display:none}` comes before `@media (max-width:700px)`; the block holds `.pan-hint{display:block}`, `calc(var(--w)*0.8)`, `.cond thead{display:none}`, `content:"做什麼　"`, and `content:"條件　"` |
| AC-4 | the existing 33 arch-diagram tests | the change lands | they pass unchanged |
| AC-5 | the langlive-line-oa pack | Claude re-renders the six pages with the new renderer and takes a 390 px-wide iframe screenshot of two of them | the diagram text is readable, the hint shows, the table shows as cards, and nothing is cut off at the right edge |

## Decisions
- **Operator.** The problem: 「html目前有一個問題 在手機上不好讀」. The approval was 「Ok」, given to the prototype (pan the diagram at readable size, cards for the table) and to shipping it with `/ship-next` in auto mode.
- **Door: two-way.** It is CSS and one wrapper element in generated HTML; a revert and a re-render undo it.
- **Claude's calls:**
  - **80 % of the canvas width, read through a CSS variable,** instead of a fixed 980 px. Text size is then the same on every canvas: 13 px × 0.8 ≈ 10 px.
  - **Use the browser's own pinch-zoom, not a JS zoom.** It keeps the pages script-free.
  - **Small-change lane.** It is one task of about 30 changed lines, with no new function.
- **From review attempt 1:** a non-numeric `canvas.w` reached the new `style` attribute as `url(//…)` and the browser fetched it (reproduced). `render_svg` now refuses it; long titles in phone cards wrap.
- **From the prototype:**
  - The 390 px screenshots must come from a 390 px iframe: headless Chrome's window is at least 500 px wide, which looked like overflow.
  - The hidden-hint rule must come before the media block, or the hint never shows.
