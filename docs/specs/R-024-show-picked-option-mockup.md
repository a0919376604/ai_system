---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-024
status: draft
tags: [obsidian, plugin, roadmap, mobile, mockup]
ai-first: true
related-specs: [R-013]
mockup: null
supersedes: null
---

## For future Claude
> R-024 makes two changes to Roadmap 檢視, the Obsidian plugin from R-013
> (`obsidian-roadmap-view/main.js`):
> 1. **完成條件 is a bulleted list.** Each `↳ done when:` line is split at its top-level `；`,
>    `;` and ` · `.
> 2. **The option that was picked is shown.** An item whose row names a picked option
>    (`mockup 定案 B`, or `方案 B` on a `↳` line that mentions a mockup) gets a 「採用方案 B」
>    image: its mockup's option panel, zoomable like 現況. For a done item, the list card's
>    thumbnail shows that option instead of 現況.
> The plugin stays read-only. Nothing outside the plugin changes.

## §1 Problem
- **完成條件 is one long sentence.** A done-when line averages about 250 characters. Most chain
  several conditions with ` · ` (160 of 211 lines in the vault) or `；` (50). The detail page
  shows each line as a single block of text.
- **A done item only shows how things were before.** Its thumbnail is the mockup's 現況, the
  picture from before the change. Which option was built is a small 「方案 B」 chip at best,
  and only when the row says `mockup 定案 B`. The image of that option is nowhere in the view.
  The operator asked: 「已完成的有機會顯示是用什麼方案麼，如果有該方案的圖片也附上顯示」.

## §2 Goals, non-goals
**Goals**
- G1. The detail page's 完成條件 fold lists one condition per bullet.
- G2. `parseRoadmap` reads the picked option from `mockup 定案 X` or `方案 X 定案` on the row
  or, failing that, from the first `方案 X` on a `↳` line that mentions a mockup.
- G3. The detail page shows 「採用方案 X」 first, then 現況: the option's panel with its heading
  as caption. It is lazy, cached and zoomable, exactly like 現況.
- G4. On the list, a **done** item whose option panel is found uses it as the card thumbnail.
  A not-done item keeps 現況, and an item whose panel is not found keeps 現況. The chip
  「方案 X」 stays in every case.

**Non-goals**
- Reading a picked option from a `###` section heading (`… mockup 定案 甲`). Rows only.
- Showing the options that were not picked.
- Opening 完成條件 by default; the fold behaves as it does today.

## §3 Design
### 3.1 `splitConditions(text) → string[]`
- Split at `；`, `;` and ` · ` that sit outside brackets and quotes: `（）()「」『』[]【】` and
  backticks.
- Trim every part; drop empty parts. A text with no separator returns `[text]`.
- The detail page renders every `doneWhen` line through it into one `<ul class="rv-dw">`.

### 3.2 `picked`
- First, `mockup 定案 X` on the row, as today, or `方案 X 定案` on the row (the vault's newest
  done items, R-253 to R-255, use that form).
- Otherwise, the first `方案 ?X` on a `↳` line that also contains `mockup`. This covers
  `↳ explain: mockup \`….html\` 方案 B（…）`, `↳ mockup [[…|…（方案 D）]]` and
  `↳ mockup 同上（方案 A）`.
- X is a Latin capital letter or one of 甲乙丙丁. Anything else gives `picked: null`.

### 3.3 `optionDoc(html, picked) → {doc, label} | null`
- The option panels are the elements whose class holds `panel` and a token starting with `opt`
  (`optA`, `optB`, `optC` …).
- An option's **label candidates** are the nearest heading (`h1`–`h4`) before the panel, when that
  heading follows the previous panel, and the first heading inside the panel.
- A panel whose markup never closes, if it is an option, 現況 or facts panel, ends where the next
  such panel starts. Without that, one vault mockup's unclosed `optB` gave its 「版面甲」 heading
  to the `optA` after it.
- The panel to show, in this order:
  1. the first panel with a candidate that **starts with** `方案 X` / `方案X` / `版面 X` / `版面X`,
     optionally after a number such as `4 · `. In the vault, 「版面甲」 is an `optB` panel. A
     heading that only mentions 方案 X mid-sentence, such as 「匯入名單時，方案 B 一起做」, does
     not count;
  2. for a Latin X, the panel whose class holds `opt` + X. Its caption is its own first heading,
     else the heading before it, because a heading before an unlabelled panel is often a section
     heading shared by every option.
- A label is heading text with each tag read as a word break (`方案 B …<span>建議</span>` reads
  `方案 B … 建議`) and HTML entities decoded.
- It reports `by: "label" | "class"`.
- It returns the same document `currentStateDoc` builds, but holding that panel, with scripts
  dropped, plus its label (tags stripped, whitespace collapsed, at most 80 characters).
  It returns null when nothing matches.

### 3.4 The view
- **Which mockup.** A label match in any of the item's mockups beats a class match in an earlier
  one (R-257 has two mockups: the second names 方案 B, the first only has an unlabelled `optB`).
- **Detail page.** When `picked` is set and an option panel is found in one of the item's
  mockups, add a 「採用方案 X」 label, a big image and the caption `label`, then show 現況 as
  before. Taps zoom with the title `<id> · 採用方案 X`.
  - The caption comes from the cache when this item's option was drawn before, so a live
    refresh moves nothing below it.
  - The label and caption stay hidden until the option is found the first time, so a missing
    option never flashes.
- **Card.** A done item (`status.group` is `recent` or `done`) with a found option uses the
  option as its thumbnail. Every other item uses 現況, and so does a done item whose option
  search fails (a mockup mid-sync).
- **Cache.** `entryFor(path, kind)` caches per `path + kind + mtime`, where kind is `now` or
  `opt:X`. The cached height `h` belongs to that entry.
- Searching the item's mockups for the option happens inside the lazy thumbnail job, never in
  `readProject`. A list render therefore reads no mockup until a card comes into view.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `splitConditions` | `RoadmapViewPlugin.splitConditions(text) → string[]` | Top-level `；` / `;` / ` · ` split, trimmed, empties dropped; brackets, quotes and backticks protect their content |
| `parseRoadmap` (picked) | `item.picked` | `mockup 定案 X` or `方案 X 定案` on the row, else the first `方案 X` on a `↳` line containing `mockup` (never a done-when line); X ∈ A–Z or 甲乙丙丁 |
| `optionDoc` | `RoadmapViewPlugin.optionDoc(html, picked) → {doc, label, by} \| null` | First an `opt*` panel whose heading before it or own first heading starts with 方案/版面 X (after an optional `N · `), else class `opt<X>` captioned with its own heading; an unclosed panel ends at the next; the document holds the mockup's styles and that one panel, with no scripts |
| the view | the registered `roadmap-view` view | Detail page shows 採用方案 X then 現況; a done item's card shows the option; 完成條件 is a `<ul>` |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | `「A；B」（含 x；y） · C；` | `splitConditions` | `["「A；B」（含 x；y）", "C"]` |
| AC-2 | a row with `mockup 定案 B` / one with `↳ explain: mockup \`x.html\` 方案 C（…）` / one with `↳ mockup 同上（方案 A）` / one with `方案 B` only in its done-when line | `parseRoadmap` | picked `B` / `C` / `A` / `null` |
| AC-3 | a mockup whose `optB` panel is headed 「版面甲」 and whose `optA` panel 「版面乙」 | `optionDoc(html, "甲")` | the `optB` panel, label 「版面甲 …」 |
| AC-4 | a mockup with `<h2>方案 B · X</h2>` before `.panel.optB`, and a mockup with no labels | `optionDoc(…, "B")` | that panel, label 「方案 B · X」; the unlabelled one matches by class `optB` |
| AC-5 | `optionDoc(…, "D")` with no D panel / with an `optD` script inside | — | null / no `<script>` in the doc |
| AC-6 | a done item with `mockup 定案 B` and a mockup holding `optB` | the list renders and the card comes into view | its thumbnail iframe shows the `optB` panel, not 現況 |
| AC-7 | the same item, detail page | rendered | 「採用方案 B」 label, its image and caption, then 現況; both zoom on tap |
| AC-8 | a not-done item with `mockup 定案 B` | card in view | thumbnail is 現況; the detail page still shows 採用方案 B |
| AC-9 | an item with two done-when lines | detail page | one `<ul>` whose `<li>`s are the split conditions of both lines, in order |
| AC-10 | the real vault, when present | the local-only test | every row whose `picked` is set and whose mockups hold an `opt*` panel yields a non-null `optionDoc` |
| AC-11 | the operator's phone | open a done item that has 方案 B | the card and the detail page show the option; the 完成條件 list reads well — **operator confirms** |

## §5 Rollout
1. Land on main and push.
2. `./sync.sh restore` copies the plugin; Obsidian picks it up after a reload (on the phone, after Sync).
3. The operator confirms AC-11.

## Decisions
**Operator decisions (2026-10-27)**
- 「完成條件顯示時可以條列式麼」 → yes: split into bullets.
- 「已完成的有機會顯示是用什麼方案麼，如果有該方案的圖片也附上顯示」 → show 採用方案 X and its image.
- **Card thumbnail for a done item = the picked option** (answered: 「採用的方案（推薦）」). The
  detail page shows the option first, then 現況.
- **Auto mode** (answered: 「auto（推薦）」).

**Claude's calls** (auto mode, the operator can override)
- **Match by label first, class second.** One vault mockup puts 「版面甲」 in `optB`, so 甲 ≠
  `optA` in general. 49 of 123 option panels carry 「方案 X」 in a heading.
- **`方案 X` is read only from `↳` lines that mention a mockup**, never from done-when text,
  where 「方案」 can mean something else.
- **Done = `recent` or `done` group.** An item in progress keeps 現況 on its card, since it is
  not built yet. Its detail page still shows the decided option.
- **No section-heading inheritance in v1.**
- **Fixtures are invented** (public repo), as in R-013.

**Review attempt 1 (auto mode)**
- **The label must start with 方案/版面 X**, and the heading before a panel counts as well as its
  own. R-250's second `optB` only mentions 方案 B. The spec first said "contains", and the spec
  review caught the mismatch.
- **Unclosed panels end at the next panel**, and **a label match beats a class match across
  mockups**. Both were found by checking the review's claims against the vault.
- **AC-10's local test checks every picked row whose mockups hold any `opt*` panel**, as AC-10
  says. 8 of 8 pass today.
- The caption comes from the cache; the label and caption stay hidden until found; a done card
  falls back to 現況 when the option search fails.
- **`方案 X 定案` on the row is read too.** The three newest done items use it, and none of them
  showed an option.
- **A mockup that cannot be read is skipped**, and the search goes on to the next one. The detail
  page's images start at the height the card already measured. Remembered sizes are keyed by
  project + role + id.
- Door: two-way — a read-only display change inside the plugin; reverting the commit restores R-013's behaviour, and no data or file format changes.

## §8 Known risks
- **R1 Label wording drifts.** Headings may use 「選項 B」 or 「B 案」. Those miss the label
  match, and the class match still covers Latin letters. AC-10 measures it on real data.
- **R2 Cost on the phone.** A done card now looks inside the mockup for the option. This
  happens in the same lazy, at-most-2 job as 現況, and the result is cached per mtime.
