---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-032
status: draft
tags: [ship-workflow, ship-refactor-brand, design, mockup, report]
ai-first: true
related-specs: [R-024, R-026]
supersedes: null
---

## For future Claude
> R-032 changes `/ship-refactor-brand` from a consistency audit into "pick a brand direction
> first, then audit against it".
> - **New step 1 「品牌方向」**: the scan deals three directions with tasteskill v2
>   (`design-taste-frontend`, an external install), builds the scope's main screen in each
>   with real content, and writes one comparison mockup to
>   `<vault project>/Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html`
>   (`.panel.now` + `.panel.optA|optB|optC`, Roadmap 檢視 reads them, R-024). It stops until
>   the operator picks (or mixes, which adds 方案 D). The pick goes to
>   `<vault project>/Reports/refactor-brand-direction.md`; later scans reuse it unless the
>   operator says 「重選」.
> - **The audit and candidates use the picked direction as the target.** Every candidate's
>   「改完」 picture is a screenshot of its screen built in that direction; hand-drawn
>   schematic boxes are no longer allowed in brand reports.
> - **The old 「缺品牌權威不得發明新樣貌」 clause is gone.**
> - **The shared report template `templates/refactor-report.html` is redesigned** (also used by
>   `/ship-refactor-scan`); it still passes `rs_report_check` and now passes taste's `lint.mjs`
>   with no FAIL.
> - Without taste v2 installed the scan still runs the old audit, says 「mockup 未驗證」 and
>   draws nothing by hand.

## §1 Problem
The operator, 2026-11-04, about `/ship-refactor-brand`:
「1. 他設計出的樣子有點醜 2. 他最後出來的樣子很沒有品牌化 3. 希望報告出來時要順便給會變成怎麼樣的 mockup
4. 在品牌化之前應該要至少生三個品牌 mockup 樣子給我選才對」.

Facts, checked 2026-11-04 against main `bc08cb2` and the six langlive-line-oa reports
(`10 Projects/langlive-line-oa/Reports/refactor-brand-2026-10-30-175412` … `-2026-11-02-125831`):
- **Ugly:** each candidate's 「改完」 picture is hand-made HTML inside the report, labelled
  「改完的方向・提案示意，尚未實作」 (grey boxes, see
  `refactor-brand-2026-11-01-233615.evidence/report-zoom1-1440.png`). No design rules or visual
  check apply to it. The template itself fails taste's lint: 3 FAIL (two 1px hairlines, the ✕
  emoji), 3 WARN (outlined boxes); it also has an eyebrow label (`.hero .k`) and pill chips.
- **Not branded:** `skills/ship-refactor-brand/SKILL.md` §1 says "Missing brand authority becomes
  an explicit decision gap; it does not justify inventing a new identity." The audit aligns
  pages to the existing `BRAND_GUIDE.md`, so results converge on the current look. The
  2026-11-02 report lists the logo question only as an undecided row (c5).
- **No rendered after-state:** only 「現在」 is a real screenshot.
- **No choice of direction:** the workflow has no such step.

tasteskill v2 (`~/.claude/skills/design-taste-frontend`, installed 2026-11-04 from
`Leonxlnx/taste-skill`; needs Node 22+, Chrome) deals directions with `scripts/draw.mjs`:
- Pages: `--sector … --options 3` deals three of twenty directions.
- App screens: `--app --kind <kind> --options 3` deals *up to* three of seven styles. Measured:
  `--kind support` gives 2 (light: `achromatic-ledger`, `framed-sheet`; `--theme dark`:
  `true-black-flat`, `data-terminal`); `--kind smb-admin` adds `accent-ladder`.
- `--keep palette,type` keeps a brand's colours and faces; `inspect.mjs [--app]` measures a
  built screen at 1440/768/390; `lint.mjs` checks source.

## §2 Goals, non-goals
**Goals**
- G1. Before any inventory, the operator sees three rendered brand directions of their own main
  screen and picks one (§3.1).
- G2. Every candidate's after-picture is a rendered screenshot in the picked direction (§3.3).
- G3. The SKILL.md no longer forbids proposing a new identity (§3.2).
- G4. The shared report template looks designed: taste `lint.mjs` 0 FAIL, still passes
  `rs_report_check` (§3.4).
- G5. The pick is durable; reruns do not re-ask (§3.1 step 7).
- G6. Without taste v2 the scan degrades honestly (§3.5).

**Non-goals**
- Vendoring taste v2 into `claude-skills/` (R-004/R-029: that directory holds our six skills only).
- Hallmark or any second design engine.
- Implementing a direction in a product: that stays `/ship-next` work on the selected rows.
- Running a real brand scan of langlive-line-oa inside this ship.
- Changing what `/ship-refactor-scan` finds or its box-diagram pictures' meaning.

## §3 Design
### 3.1 Step 1 「品牌方向」 — new `skills/ship-refactor-brand/references/directions.md`
Runs after step 0 (resolve project) and before the inventory.
1. **Reuse check.** `<vault project>/Reports/refactor-brand-direction.md` holds one
   `## <surface>` section per surface (`app` for screens people work in, `page` for public
   pages). If the scan's surface has a section and the operator did not say 「重選」 (or
   "re-pick"), load it, state 「沿用 <date> 選的方案 X」 and skip to the inventory. A scope on
   another surface deals its own three. With no vault binding, deal and pick in the temporary
   report directory, persist nothing, and say the pick will be asked again next time.
2. **Resolve taste v2**: the first of `~/.claude/skills/design-taste-frontend`,
   `~/.agents/skills/design-taste-frontend`, `~/.codex/skills/design-taste-frontend` that holds
   `scripts/draw.mjs`; plus `node --version` ≥ 22 and a Chrome. Missing → §3.5.
3. **Main screen.** The highest-traffic screen in scope (shared shell + one key route, e.g. the
   chat inbox for langlive-line-oa), captured at 1440 and 390 as 現況. One screen only.
4. **Deal three.** App screen → `draw.mjs --app --kind <kind> --screens <screen> --options 3`;
   page → `draw.mjs --sector <sector> --sections <…> --options 3`. Fewer than three distinct
   style/direction ids → deal again with the other `--theme`, then the closest neighbouring
   `--kind`/`--sector`, until three distinct ids. `--keep palette,type` only for values that
   `BRAND_GUIDE.md` (or the project's approved brand source) marks as fixed; the logo is always
   kept as an asset. Run from a scratch dir; every taste command in steps 4–5 carries
   `TASTE_SKILL_HISTORY="<evidence>/taste-history.json"` (`<evidence>` = `Reports/<stem>.evidence`,
   or the same path in the temp report dir), so the operator's global taste history is untouched.
   If top-ups still give fewer than three, say how many and why; never show two silently.
5. **Deal each option in full** (`--style <id>` / `--direction <id>`, the call that writes taste
   history) with the history prefix and `--out <evidence>/directions/<x>/.taste-skill`, then
   **build each** with taste's own run (app: `references/app-screens.md` §2.3–2.7; page: the
   run's steps), real labels and realistic data from the repo, into
   `<evidence>/directions/<a|b|c>/index.html` (a mix: `d/`). `inspect.mjs [--app]` on each; fix
   FAILs; at most three look-and-fix rounds as taste prescribes.
6. **Comparison mockup** `Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html`,
   following the vault's Project Mockup Convention: h1 + 「三個方案 · 待選」, `.sub`, `.banner`,
   `.panel.facts`, `.panel.now` (現況 screenshots), `.panel.optA|optB|optC` each headed
   `方案 A · <one-line idea>` (style id + seed, type, palette swatches, 1440 + 390 screenshots,
   `.notes` 好處/弱點, the recommended one `.tag.rec`), `table.t` 方案並排, 需要你拍板. Panels use
   screenshots (JPEG/PNG data URIs), not live markup, because Roadmap 檢視 strips scripts and
   taste's charts need JS; a relative link opens each live build. Self-contained, no external
   URLs. Without a vault binding it sits beside the reports in the temp report dir. Rendered and
   looked at (headless Chrome) before it is shown.
7. **Stop for the pick.** Ask 「選 A、B、C，或混搭（例如 A 的配色＋B 的字）」. A mix is built and
   added as `.panel.optD` 「方案 D · …」, shown, and confirmed before going on. Then write
   `Reports/refactor-brand-direction.md`: date, report stem, picked option, taste style or
   direction id + seed, kind/sector + theme, palette and type tokens, kept brand assets, the
   mockup path, and the operator's words, under that surface's section. Silence or a general
   「好」 is not a pick.

### 3.2 SKILL.md and decisions
- Steps become: 0 resolve · 1 品牌方向 · 2 inventory · 3 propose · 4 reports · 5 enqueue.
- Delete the "does not justify inventing a new identity" sentence. The picked direction is the
  **proposed authority** the inventory measures against; approved rules in `BRAND_GUIDE.md`
  stay approved, and a conflict between them and the pick is listed, not silently resolved.
- When a direction was picked in this scan, candidate c1 is 「把選定方向寫進 BRAND_GUIDE」 (kind:
  brand decision, now resolved). Its row text carries the mockup path
  `Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html` and `mockup 定案 <X>`, so
  Roadmap 檢視 shows the picked option (R-024). Visual-alignment candidates depend on it. On a
  reuse run whose direction row is already queued or done, no c1 is re-proposed: candidates
  number from c1 as usual and depend on that existing R-ID. A reused pick whose row is neither
  queued nor done is proposed as c1 again. Only that direction-documentation row carries the
  mockup path and `mockup 定案 <X>` (from the recorded pick on reuse). The rule lives once, in
  `references/roadmap.md`; SKILL.md links it.

### 3.3 Evidence (`references/evidence.md`)
- Each visual-alignment candidate's picture = 「現在」 captured screenshot + 「改完」 screenshot of
  that candidate's screen built in the picked direction, 「改完」 labelled 「提案 · 方案 X」. The
  same screen reuses the step-1 build; another screen reuses its shell, tokens and type with that
  screen's real content, checked once with `inspect.mjs` (no new deal, no full taste run).
- The direction candidate (c1) shows the picked panel's screenshots.
- A structural-consolidation candidate shows 「現在」 only, labelled 「外觀不變」; it promises no
  visual change, so no after-picture is rendered.
- Images are embedded (data URIs) so the report stays self-contained.
- Hand-drawn schematic boxes are not allowed as a brand after-picture.
- The human report gains a 「品牌方向」 block near the top: the picked option, its 390 screenshot,
  and a relative link to the comparison mockup.

### 3.4 Shared template `templates/refactor-report.html`
Same blocks, ids and comments as R-026 (title, hero, list, hint, `c<N>` sections with `z<N>`
zoom overlays, AI links, footer, `{{STEM}}`), restyled phone-first (390 primary, readable at
1440): no eyebrow label, no pill chips, no 1px hairlines or outlined boxes, no emoji; strength,
size and merge label stay as text. The picture block shows the box-diagram example (scan) and a
commented `<img>` before/after example (brand). Must pass `rs_report_check` after `{{STEM}}`
substitution and `lint.mjs` with 0 FAIL.

### 3.5 Without taste v2
Skip step 1; run the audit against existing brand sources as before; the human report's first
screen says 「mockup 未驗證：沒有安裝 taste v2」 with the install command
`npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend -g`
(in the HTML its slashes are written `&#47;` so `rs_report_check` sees no raw URL while the
displayed command stays verbatim); candidates' 「改完」 slot says 未驗證. Nothing is hand-drawn in
its place.

### 3.6 Small text updates
`commands/ship-refactor-brand.md` and `agents/openai.yaml` mention the direction pick.

## Seams
| Seam | Interface | Guaranteed behavior |
| --- | --- | --- |
| step order | `skills/ship-refactor-brand/SKILL.md` | a step headed with 「品牌方向」 links `references/directions.md` and comes before the inventory step; the text "does not justify inventing a new identity" appears nowhere under `skills/ship-refactor-brand/` |
| direction procedure | `references/directions.md` | names the per-surface record (`## app` / `## page`), the three install paths, `draw.mjs`, `--options 3`, the top-up rule (other `--theme`, then neighbouring kind/sector, until three distinct ids; "fewer than three" is said, never silent), `--keep` limited to brand-fixed values, `TASTE_SKILL_HISTORY` on the full deals of step 5 with one `--out` per option (no undefined `$REPORT_DIR`), `.panel.optD` for a mix, the mockup path `Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html`, `.panel.now`, `.panel.optA`, headings `方案 A ·`, `Reports/refactor-brand-direction.md`, 「重選」, and a stop for the operator's pick |
| after-pictures | `references/evidence.md` | requires 「改完」 to be a rendered screenshot in the picked direction, names 「外觀不變」 for structural candidates, forbids hand-drawn substitutes, requires PNG or JPEG data URIs (never SVG, never a build's markup or scripts), and states the 「mockup 未驗證」 fallback, whose `&#47;`-encoded install snippet passes `rs_report_check` and displays the command verbatim |
| direction row | `references/roadmap.md` | the c1 row carries the directions mockup path and `mockup 定案 <X>`; only the direction-documentation row carries them; a reused pick without a queued or done row is re-proposed; SKILL.md links this rule instead of repeating it |
| report template | `templates/refactor-report.html` with `{{STEM}}` filled | passes `rs_report_check`; has no `<script`, no `http(s)://`, no `taste-skill-ignore`, no `<figcaption`; keeps `id="top"`, `c1`/`z1` anchors, `:target`, `{{STEM}}.ai.md` and an `<img` brand example on the `.fig` surface; taste `lint.mjs` reports 0 FAIL (skipped when taste v2 is not installed) |

## §4 Acceptance
| ID | Given | When | Then |
| --- | --- | --- | --- |
| AC-1 | the brand skill's SKILL.md | it is read | the 「品牌方向」 step links `references/directions.md` and precedes the inventory step |
| AC-2 | every file under `skills/ship-refactor-brand/` | grepped | "does not justify inventing a new identity" is absent |
| AC-3 | `references/directions.md` | grepped | every item in the "direction procedure" seam is present |
| AC-4 | `references/evidence.md` | grepped | rendered-screenshot requirement, the ban on hand-drawn after-pictures, and 「mockup 未驗證」 are present |
| AC-5 | `references/roadmap.md` | grepped | the c1 row rule names the directions mockup path and `mockup 定案` |
| AC-6 | the template with `{{STEM}}` replaced and a matching `.ai.md` | `rs_report_check` runs | exit 0 (R-026's existing template test keeps passing) |
| AC-7 | taste v2 installed | `lint.mjs` runs on the filled template | 0 FAIL; the test skips when `design-taste-frontend` is absent |
| AC-8 | the filled template | Claude renders it at 390 and 1440 with headless Chrome and looks | text readable, nothing past the right edge, zoom overlay opens; screenshots noted in the ship's evidence |
| AC-9 | the full bats suite | it runs in the worktree | green except the known `cwd-guard: exits 0 when not in a git repo at all` |

## Decisions
- **Engine: taste v2 only** (operator, 2026-11-04: 「taste v2」). Hallmark overlaps (it credits
  taste-skill) and two anti-slop rulebooks would conflict.
- **taste v2 stays an external install** (my call, from R-004/R-029).
- **Reuse the pick across scans; 「重選」 re-deals** (operator: Q1 yes).
- **Three directions, all dealt by taste and distinct; top up from another theme / neighbouring
  kind; logo always kept; `--keep` only for BRAND_GUIDE-fixed values** (operator: Q2 yes).
- **One main screen per direction, 1440 + 390, real content** (operator: Q3 yes).
- **Mixing allowed; a mix is rendered as 方案 D and confirmed** (operator: Q4 yes; 方案 D naming is
  my call).
- **Fonts / offline** (operator Q5: 「英文數字字型內嵌、中文用系統字，維持單檔離線可開」). My call on
  the mechanism: comparison panels are screenshots, so faces are baked into the images and the
  mockup stays one offline file without font embedding; the live builds in `.evidence/` may load
  web fonts. Same outcome the operator approved, less tooling.
- **Redesign the shared template, keep its anchors** (operator: Q6 yes).
- **c1 is always 「把選定方向寫進 BRAND_GUIDE」 with `mockup 定案 X`** (operator approved the
  first-row rule in the 2026-11-04 proposal; the R-024 marker is my call).
- **Panels as screenshots, live builds linked** (my call: Roadmap 檢視 strips scripts).
- **Isolated `TASTE_SKILL_HISTORY`** (my call: a scan must not skew the operator's taste history).
- **Builder-check answers** (my calls, 2026-11-04): the pick is recorded per surface (`app` /
  `page`), since `decisions.md` keeps those deliberately different; structural candidates show
  「外觀不變」 instead of an after-picture; other screens reuse the picked shell rather than a new
  taste run; c1 is not re-proposed once its row exists; with no vault binding the pick is not
  persisted.
- **Review attempt 1 fixes** (my calls, verified before applying): taste history isolation moved to
  the full deals that actually write it; brand pictures sit on the `.fig` surface (zoom contrast);
  the negated lint-escape check uses `run !` (a bare `!` mid-test cannot fail in bats); the c1 rule
  is kept once in roadmap.md; the scan argument is called *scope* so "direction" means the brand
  direction only.
- **Tests are text-contract greps plus the template checks** (my call: the procedure is prose an
  agent follows; a real scan is the operator's next `/ship-refactor-brand` run).
- Door: two-way — skill prose and an HTML template; a revert restores the old behaviour and no
  data, schema or external contract changes.
