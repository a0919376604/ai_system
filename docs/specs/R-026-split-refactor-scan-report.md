---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-026
status: draft
tags: [ship-workflow, refactoring, report, mobile]
ai-first: true
related-specs: [R-025]
mockup: Proposals/mockups/refactor-scan-report-mockup.html
supersedes: null
---

## For future Claude
> R-026 splits `/ship-refactor-scan`'s report (R-025) in two, with the same stem:
> - **`Reports/refactor-scan-<stamp>.html`, for a person:** mockup option B, "先看結論，點開細節".
>   The first screen says which candidate to do first and why, then one row per candidate
>   (strength, size, how it merges). Each row jumps to a detail section with a stacked
>   picture of big boxes; tapping the picture opens it full screen. Pure CSS: no JS, no CDN.
>   Plain zh-TW, no Pocock jargon.
> - **`Reports/refactor-scan-<stamp>.ai.md`, for AI:** everything R-025's HTML card held,
>   as Markdown: files with lines, Pocock-vocabulary Problem / Solution, Mermaid source.
>
> The two link to each other. Rows written to ROADMAP link the AI file from the description
> and the human file from `↳ explain`.
>
> `rs_report_check` gates both files mechanically, `rs_merge_label` computes 自動合併 / 要人審
> from the scanned repo's `one_way_paths`, and `rs_report_shot` renders the human file in a
> 390 px iframe so Claude can look before reporting.

## §1 Problem
The operator, after R-025's first report (line-oa, R-259): 「報告寫得太複雜了 看的不是很懂 可以寫一份是給AI一份給人看的沒關係 反正可以連結 然後圖片需要放大 我在手機上根本看不到字」.

Measured on 2026-10-27 in a 390 px iframe (the mockup's facts panel):
- **Before/after diagrams:** shown side by side, each about 140 px wide, so their labels
  are unreadable.
- **Hotspot table:** runs past the right edge.
- **File paths first:** card 1 opens with about 12 wrapped lines of paths before its
  picture.
- **Jargon:** every card uses module / seam / locality / leverage.
- **No pinch zoom:** `obsidian-html-plugin` had pinch zoom off. The operator turned it on
  separately on 2026-10-27; this spec does not rely on that.

The operator picked option B of `Proposals/mockups/refactor-scan-report-mockup.html`.

## §2 Goals, non-goals
**Goals**
- G1. The human file follows option B (§3.1) and passes `rs_report_check` (§3.3).
- G2. The AI file keeps every field R-025's card carried, so nothing the next
  `/ship-next` Phase 3 needs is lost (§3.2).
- G3. Rows written by `rs_write_rows` link the AI file from the description and the human
  file from `↳ explain` (§3.4).
- G4. The 自動合併 / 要人審 label is computed, not guessed (§3.3 `rs_merge_label`).
- G5. Claude looks at a 390 px render of the human file before reporting (§3.3
  `rs_report_shot`, §3.5 step 1).
- G6. The line-oa report `refactor-scan-2026-10-27-0317` is regenerated in the new format,
  and R-259's links are updated (AC-9).

**Non-goals**
- Changing what the scan finds (Pocock's step 1, `rs_hotspots`).
- Changing the vendored Pocock files. `HTML-REPORT.md` still defines the card fields; it no
  longer defines the human layout.
- Dead-code scanning.
- Pinch zoom (a plugin setting, done).

## §3 Design
### 3.1 Human file — template `claude-skills/ship-workflow/templates/refactor-report.html`
The template is a self-contained HTML file with the option-B CSS taken from the mockup. It
contains one example of every block below, with `<!-- … -->` comments saying what to repeat.
Claude copies it and fills it in each run.

Blocks, in order:
1. **Title** `重構建議 · <project>` and a meta line: date, how many files were scanned, how
   many candidates.
2. **Hero:** label 「建議先做」, `<candidate N> · <plain title>`, one or two sentences of why,
   and a link `看細節 →` to `#c<N>`.
3. **List:** one row per candidate, an `<a href="#c<N>">` holding:
   - the number;
   - the plain title;
   - three chips: strength 「值得做」 or 「可考慮」 (from Pocock Strong / Worth exploring;
     Speculative becomes 「待觀察」), size 「小 / 中 / 大」, and the merge label from
     `rs_merge_label`.
4. **Hint:** 「要做哪幾個？在對話裡回數字就好，例如「1、2」。」
5. **Detail sections,** `<section id="c<N>">` each, holding:
   - 「← 回清單」, a link to `#top`;
   - the title and chips;
   - **the picture:** labels 「現在」 and 「改完」 stacked vertically. Boxes hold at most
     about 8 characters, 15 px or larger. A problem box is red, the result box dark. Two
     boxes may sit side by side, never more.
   - the picture is wrapped in `<a href="#z<N>">` with 「點圖放大 ⤢」. A full-screen overlay
     `<div id="z<N>" class="zoom">` (CSS `:target`) shows the same picture at 18 px, with
     「✕ 關閉」 linking to `#c<N>`;
   - three plain sentences: 「問題：」「怎麼改：」「改完：」;
   - a link 「給 AI 的細節（檔案、行號）→」 to `<stem>.ai.md`.
6. **Footer:** a link to `<stem>.ai.md`.

Rules:
- Body text 16 px. One column. Nothing wider than the viewport: long words wrap
  (`overflow-wrap: anywhere`).
- No `<script>`, no external URL (no `http:` / `https:` in `src` / `href` / CSS `url()`).
  Inline SVG, if used, omits `xmlns`; it is optional in HTML5, and its `http://` would
  break rule 3.
- No Pocock jargon in visible text: module, interface, implementation, depth, deep,
  shallow, seam, adapter, leverage, locality.

### 3.2 AI file — `Reports/refactor-scan-<stamp>.ai.md`
Markdown, in English as the vocabulary requires, with:
1. A header line `Human report: [refactor-scan-<stamp>.html](refactor-scan-<stamp>.html)`.
2. The hotspot table: score, churn, lines, path.
3. One section per candidate, `## c<N> · <Pocock-vocabulary name>`, holding exactly R-025's
   card fields, from upstream `HTML-REPORT.md` and the R-025 explore prompt:
   - Files, with line ranges;
   - Problem and Solution, in codebase-design vocabulary;
   - Benefits (locality / leverage / tests);
   - Before and After as fenced `mermaid` blocks;
   - Strength;
   - Dependency category (in-process / local-substitutable / ports & adapters / mock);
   - Wide refactor? (yes/no);
   - External callers? (yes/no, what);
   - Merge label (the `rs_merge_label` output);
   - an ADR / rejected-before callout when one applies.
4. `## Top recommendation`: which candidate, and why.

### 3.3 `lib/refactor-scan.sh` additions
- **`rs_merge_label <base-ref> <path>...`** prints `要人審` when any path matches a glob in
  the `one_way_paths` of `.claude/ship-config.yml` at `<base-ref>`, else `自動合併`.
  - It reuses `_sn_one_way_paths` and `_sn_glob_match` from `lib/ship-next.sh`, sourced via
    `${SHIP_LIB:-…}`.
  - No paths, or no config: `自動合併`.
- **`rs_report_check <stem>`** runs in the vault Reports dir, or takes paths relative to the
  cwd. It reads `<stem>.html` and `<stem>.ai.md`.
  - Exit 0 and no output when every rule holds.
  - Otherwise exit 1, with one `rs_report_check: <rule>: <detail>` line per broken rule on
    stderr.
  - Rules:
    1. both files exist;
    2. the HTML has no `<script`, no `on…=` event-handler attribute and no `javascript:`
       URL (security pass, attempt 1);
    3. the HTML has no `http://` or `https://`;
    4. the HTML's `id="c<N>"` set equals its `href="#c<N>"` set, numbered from 1 with no
       gaps;
    5. every `c<N>` has a `## c<N> ·` heading in the `.ai.md`, and no heading lacks a section;
    6. the HTML links `<stem>.ai.md`, and the `.ai.md` links `<stem>.html`;
    7. the HTML's visible text (outside `<style>`, comments and tags) contains none of the
       jargon words, matched case-insensitively as whole words;
    8. every `id="z<N>"` overlay has a matching `c<N>`.
- **`rs_report_shot <html> <png> [<fragment>]`** writes a harness page that holds the HTML in
  a 390 px wide iframe, then runs Chrome headless (`$RS_CHROME`, default
  `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`) to screenshot it to
  `<png>`.
  - With no Chrome executable: one `rs_report_shot: Chrome not found — skipped` line on
    stderr, exit 0.
  - Exit 1 when Chrome fails.
  - The harness lives in a `mktemp -d` dir, removed on exit.
  - **Without a fragment:** the iframe is tall enough for the whole page (6000 px), with a
    red line drawn across it at 844 px marking the end of the first phone screen.
  - **With a fragment** (e.g. `z1`): the iframe loads `<html>#<fragment>` at 390 × 844, which
    shows the full-screen overlay.
  - The 390 px iframe is the point: a 390 px Chrome window is laid out wider than 390 px,
    which R-025's own check missed.

### 3.4 `rs_write_rows` link change
- The second argument becomes the report **stem** (`refactor-scan-<stamp>`), not the
  `.html` basename. An argument ending in `.html` is reduced to its stem.
- The description ends with `（報告：Reports/<stem>.ai.md#c<card>）`.
- The summary (the `↳ explain` line) ends with `（看報告：Reports/<stem>.html#c<card>）`.
- Everything else (validation, reservation order, reverse insert, `after` chaining, the
  guardrails) is unchanged.

### 3.5 Command — `commands/ship-refactor-scan.md`
- **C2** is rewritten. Step 1 writes both files, from §3.1 and §3.2, with the same `$STAMP`
  stem, then runs:
  1. `rs_report_check "$REPORT_DIR/refactor-scan-$STAMP"`. A failure is fixed before
     going on; it never reaches the operator.
  2. `rs_report_shot "$REPORT_DIR/refactor-scan-$STAMP.html" "${TMPDIR:-/tmp}/refactor-scan-$STAMP.png"`,
     and again with fragment `z1`. Read both PNGs and fix what is unreadable: the list must
     end above the 844 px line, and the labels must be legible.
  3. `open` the human file.
- **The merge label** for each candidate comes from
  `rs_merge_label HEAD <candidate files>` and goes into both files.
- **Step 3** passes the stem to `rs_write_rows`.
- **Step 4** prints both paths.
- The intro's list of changes says the report is split. C1, C3 and C4 are unchanged.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| merge label | `rs_merge_label <base-ref> <path>...` (cwd = scanned repo) | `要人審` if any path matches a `one_way_paths` glob of `.claude/ship-config.yml` at `<base-ref>`, else `自動合併`; no paths or no config → `自動合併` |
| report check | `rs_report_check <stem>` | exit 0 silent when §3.3 rules 1–8 hold; else exit 1 and one `rs_report_check: <rule>: <detail>` stderr line per broken rule |
| report shot | `rs_report_shot <html> <png> [<fragment>]` (`$RS_CHROME` overrides Chrome) | Chrome screenshots a harness holding `<html>` in a 390 px iframe into `<png>`: whole page (6000 px) with a red line at 844 px, or `<html>#<fragment>` at 390 × 844; no Chrome → stderr notice, exit 0; Chrome failure → exit 1; harness dir removed |
| row writer | `rs_write_rows <roadmap> <stem>` | as R-025, except: description ends `（報告：Reports/<stem>.ai.md#c<N>）`, explain ends `（看報告：Reports/<stem>.html#c<N>）`; a `.html` argument is reduced to its stem |
| human template | `templates/refactor-report.html` | passes `rs_report_check` together with a minimal matching `.ai.md`; no script, no external URL |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a scratch repo whose HEAD `.claude/ship-config.yml` lists `one_way_paths: [backend/app/domain/line_service.py, backend/app/domain/push_*.py]` | `rs_merge_label HEAD backend/app/api/admin_dashboard.py` / `… backend/app/domain/push_x.py` / `… a.py backend/app/domain/line_service.py` / no config | `自動合併` / `要人審` / `要人審` / `自動合併` |
| AC-2 | the template copied as `<stem>.html` plus a minimal `<stem>.ai.md` with matching `## c1 ·` | `rs_report_check <stem>` | exit 0, no output |
| AC-3 | that pair, broken one way at a time: a `<script>`; a `https://cdn` link; `id="c3"` with no row; an `.ai.md` missing `## c1 ·`; no cross-link; visible text 「deep module」 | `rs_report_check` | exit 1 and a line naming the broken rule each time; 「module」 inside `<style>` or a tag attribute is not flagged |
| AC-4 | `RS_CHROME` pointing at a stub script that copies the harness it is given and writes its `--screenshot=` path | `rs_report_shot x.html out.png` / `… out.png z1` | the harness iframe is 390 wide and 6000 tall with a line at 844 / loads `x.html#z1` at 390 × 844; `out.png` exists; the harness dir is gone. With `RS_CHROME=/nonexistent`: exit 0 and the skip notice |
| AC-5 | the R-025 four-row TSV | `rs_write_rows "$RM" refactor-scan-T` and `rs_write_rows "$RM" refactor-scan-T.html` | every description ends `（報告：Reports/refactor-scan-T.ai.md#c<N>）`, every explain line ends `（看報告：Reports/refactor-scan-T.html#c<N>）`, both calls give the same text; R-025's chaining, ordering and guardrail assertions still hold |
| AC-6 | the command file | its step 3 block runs (as R-025's AC-10c) | rows carry both links |
| AC-7 | the command file | read | C2 names both files, `rs_report_check`, `rs_report_shot` and `rs_merge_label`; step 4 prints both paths |
| AC-8 | the template | rendered by `rs_report_shot` in a 390 px iframe | Claude reads the PNG: nothing runs past the right edge, the list fits the first screen, picture labels are readable |
| AC-9 | the line-oa report `refactor-scan-2026-10-27-0317` | Claude regenerates it in the new format after the executor, from R-025's 5 explored candidates (the old `.html` is read first, since the new human file reuses its name) | `rs_report_check` passes; the 390 px render is readable; R-259's description links `…0317.ai.md#c1` and its explain line `…0317.html#c1` |

## §5 Rollout
1. Land on main.
2. The command picks the change up through the live checkout; `./sync.sh restore` is not
   needed, since no command was added.
3. AC-9 rewrites the line-oa report and R-259's row in the vault.

## Decisions
**Operator decisions (2026-10-27)**
- 「可以寫一份是給AI一份給人看的沒關係 反正可以連結 然後圖片需要放大」: two files, linked;
  big pictures.
- **Mockup option B** (「B」): conclusion first, tap for details.
- Pinch zoom in `obsidian-html-plugin` turned on (「好 幫我打開」), outside this ship.
- Auto mode (「26 auto」).

**Claude's calls** (auto mode, the operator can override)
- **Same stem for both files.** R-259's existing `…0317.html#c1` link keeps pointing at the
  human report.
- **Rows:** the description links the AI file, which ship-next Phase 3 reads; `↳ explain`
  links the human file, which the operator taps in Roadmap 檢視. This is mockup Q3.
- **The AI file is Markdown** (mockup Q4). It is cheapest for an AI to read, renders in
  Obsidian, and keeps the Mermaid source.
- **The merge label is computed** from `one_way_paths` with the existing ship-next helpers.
  - `sn_door` also escalates migrations, deploy files and new dependencies. A
    structure-only refactor row rarely touches those, so the label checks
    `one_way_paths` only (builder check; R4).
  - The label is a forecast; `sn_door` decides at ship time.
- **The checks are mechanical rules, not reviewer judgment.** The readability failure was
  invisible to R-025's review; R-017 says a lesson that can be checked becomes a check.
- **`rs_report_shot` uses a 390 px iframe.** A 390 px headless window lays pages out wider
  than 390 px: this ship's own mockup work first misreported the old report's title as
  cut off.
- **Strength mapping:** Strong → 值得做, Worth exploring → 可考慮, Speculative → 待觀察.
- **Size (小 / 中 / 大) is Claude's estimate,** written in both files. Nothing computes it.
**Review attempt 1 (auto mode)**
- **Chrome's log is kept quiet** unless a shot fails. Every real run had printed about 50
  CVDisplayLink lines into the command output.
- **Security pass:**
  - The finder flagged the LLM-written report being rendered with JS on and
    `--allow-file-access-from-files` (confidence 5, below the bar).
  - The flag was dropped: the iframe renders the same pixels without it.
  - Rule 2 now also rejects `on…=` handlers and `javascript:`.
  - JS-off was tried and rejected: with `scriptEnabled=false` and no file flag, Chrome
    writes no screenshot.
- Door: two-way — a template, three lib functions, a changed link format and command text; reverting the commit restores R-025's report, and no data or deploy path changes.

## §8 Known risks
- **R1 Jargon list.** A whole-word match misses Chinese renderings such as 「模組」. That is
  accepted: the rule exists to stop English Pocock terms leaking into the human file.
- **R2 Chrome missing.** `rs_report_shot` skips with a notice, and the mechanical check
  still runs.
- **R3 Claude's size estimate** is a judgment call. It is labelled as such in the AI file.
- **R4 Merge label vs. `sn_door`.** A candidate touching a migration, a deploy file or a new
  dependency is labelled 自動合併 but would be sent to review at ship time.
