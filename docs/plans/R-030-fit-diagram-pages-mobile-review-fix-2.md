# R-030 review fix 2

Executor: inline (small-change lane). Findings: /tmp/ship-next-review-R-030-1.md.

1. **Blocking: CSS injection through `canvas.w` in the new `style` attribute** (render.py, `render_svg`).
   Reproduced: `canvas.w = "1;background-image:url(//127.0.0.1:8765/beacon);--z:0"` renders `style="--w:1;background-image:url(//…)…px"` with exit 0.
   - Test first: a `mutate` of `canvas.w` to that string → `render.py page` exits 2 and writes no file.
   - Fix: `render_svg` raises `SpecError` unless `canvas.w` and `canvas.h` are positive int/float (not bool).
2. **Important: long node titles overflow the phone card** — the desktop `.cond td:nth-child(1){overflow-wrap:normal}` still applies.
   - Fix: the phone rule for the first cell adds `overflow-wrap:anywhere`; the phone-CSS test asserts it inside the block.
3. Nits taken (ponytail:delete): drop `width:auto!important` and `-webkit-overflow-scrolling:touch` (no effect); the phone-CSS test also asserts exactly one `@media (max-width:700px)` block.
   Not taken: `tabindex` on `.pan` (changes the declared seam; filed nowhere, minor), `max(100%,…)` for tiny canvases (no such canvas in use).
