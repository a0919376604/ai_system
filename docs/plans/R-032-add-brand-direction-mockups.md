# R-032 Brand direction mockups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/ship-refactor-brand` deals three tasteskill-v2 brand directions as rendered mockups, waits for a pick, audits against it, shows rendered after-pictures, and its shared report template looks designed.

**Architecture:** Skill prose (Markdown an agent follows) under `claude-skills/ship-workflow/skills/ship-refactor-brand/`, one new reference file `references/directions.md`, a restyled shared HTML template, and one new bats file pinning the text contracts and template checks.

**Tech Stack:** Markdown skill files, plain HTML/CSS template, bash + bats-core ≥ 1.5, tasteskill v2 `lint.mjs` (Node) as an optional check.

**Spec:** `docs/specs/R-032-add-brand-direction-mockups.md` — read it whole before Task 1; every task argues from it.

## Global Constraints
- Base branch: `main`. Work only in this worktree. Editing `claude-skills/ship-workflow/skills/ship-refactor-brand/`, `claude-skills/ship-workflow/templates/`, `claude-skills/ship-workflow/commands/ship-refactor-brand.md` and `claude-skills/ship-workflow/tests/` is explicitly authorized, although `~/.claude/skills/ship-workflow` links to this repo.
- Never modify `~/.claude/skills/design-taste-frontend/` (external install, read-only). Nothing from it is copied into `claude-skills/` (R-004/R-029).
- The external skill is named `design-taste-frontend`; install command, verbatim: `npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend -g`.
- Exact paths: mockup `Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html`; pick record `Reports/refactor-brand-direction.md`; live builds `Reports/<stem>.evidence/directions/<a|b|c>/index.html`.
- Report HTML rules (`rs_report_check`): no `<script`, no `on<event>=` attribute, no `javascript:`, no `http://`/`https://` anywhere (inline SVG omits `xmlns`), anchors `c1…cN` / `#c1…#cN` contiguous, `z<N>` only for existing `c<N>`, both reports cross-linked by basename, none of these words in visible text: module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.
- Skill prose stays English like the existing files; user-facing strings stay zh-TW exactly as the spec writes them (「品牌方向」「重選」「方案 A ·」「提案 · 方案 X」「外觀不變」「mockup 未驗證」「把選定方向寫進 BRAND_GUIDE」「選 A、B、C，或混搭（例如 A 的配色＋B 的字）」).
- Tests: scoped runs `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats tests/test_refactor-scan.bats`; the full suite only in Task 4.

## Review Focus
1. A brand report embeds an SVG screenshot as a data URI — its `xmlns="http://…"` trips `rs_report_check` external-url. Expect evidence.md to require PNG/JPEG data URIs. Pinned in Task 2 (`evidence: images are PNG or JPEG, never SVG`).
2. Live taste builds use `charts.js`; copying their markup into the report adds `<script>`. Expect evidence.md to say pictures are images only. Pinned in Task 2.
3. Top-ups still yield fewer than three directions. Expect the scan to say how many and why, never silently show two. Pinned in Task 1 (`fewer than three`).
4. The template "passes" lint by sprinkling `taste-skill-ignore`. Expect the comment to be absent. Pinned in Task 3.
5. Run from Codex (`~/.codex/skills/ship-refactor-brand`), taste is not under `~/.claude`. Expect all three install paths to be searched. Pinned in Task 1.

---

### Task 1: SKILL.md step order + `references/directions.md`

**Files:**
- Create: `claude-skills/ship-workflow/tests/test_refactor-brand.bats`
- Create: `claude-skills/ship-workflow/skills/ship-refactor-brand/references/directions.md`
- Modify: `claude-skills/ship-workflow/skills/ship-refactor-brand/SKILL.md` (whole file: headings, §1 sentence, description)
- Modify: `claude-skills/ship-workflow/skills/ship-refactor-brand/references/decisions.md` (Brand coherence intro, Reference basis)

**Interfaces:**
- Produces: `tests/test_refactor-brand.bats` with `setup()` setting `B="$SHIP_SKILL_ROOT/skills/ship-refactor-brand"`, `T="$SHIP_SKILL_ROOT/templates/refactor-report.html"`, `S="$(make_scratch refactor-brand)"`; `teardown() { rm -rf "$S"; }`. Tasks 2–3 append tests to this file.
- Produces: SKILL.md headings `## 0. Resolve project and ship integration`, `## 1. 品牌方向 · pick a brand direction`, `## 2. Inventory brand drift and duplicate UI`, `## 3. Propose integration and migration order`, `## 4. Present linked reports and the choice`, `## 5. Enqueue only the selected work`.

- [x] **Step 1: Write the failing tests** (file header `#!/usr/bin/env bats`, `load helpers`, `bats_require_minimum_version 1.5.0`, then setup/teardown above)

```bash
@test "SKILL.md: 品牌方向 step links directions.md and precedes the inventory (AC-1)" {
  f="$B/SKILL.md"
  d=$(grep -n '^## .*品牌方向' "$f" | head -1 | cut -d: -f1)
  i=$(grep -n '^## .*Inventory' "$f" | head -1 | cut -d: -f1)
  [ -n "$d" ] && [ -n "$i" ] && [ "$d" -lt "$i" ]
  sed -n "${d},${i}p" "$f" | grep -qF '(references/directions.md)'
}
@test "brand skill: the no-new-identity clause is gone (AC-2)" {
  ! grep -rqF 'does not justify inventing a new identity' "$B"
}
@test "directions.md: names every item of the direction procedure (AC-3)" {
  f="$B/references/directions.md"
  for s in '## app' '## page' 'draw.mjs' '--options 3' '--theme' 'neighbouring' 'TASTE_SKILL_HISTORY' \
           'Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html' '.panel.now' '.panel.optA' '.panel.optD' \
           '方案 A ·' 'Reports/refactor-brand-direction.md' '重選' '選 A、B、C，或混搭' 'fewer than three' \
           '~/.claude/skills/design-taste-frontend' '~/.agents/skills/design-taste-frontend' '~/.codex/skills/design-taste-frontend' \
           'mockup 未驗證' 'npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend -g'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
  grep -E -- '--keep' "$f" | grep -qi 'fixed'
}
```

- [x] **Step 2: Run to verify they fail**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats`
Expected: AC-1, AC-2, AC-3 FAIL (no 品牌方向 heading; the clause exists; directions.md missing).

- [x] **Step 3: Write `references/directions.md`** from spec §3.1 steps 1–7 and §3.5, as numbered steps, containing every string in the AC-3 loop. Pin these, in prose:
  - Reuse check per surface (`## app` / `## page` sections of the record), 「重選」 or "re-pick" forces a new deal, no vault binding → pick in the temp report dir, persist nothing, say it will be asked again.
  - Resolution order of the three install paths, each must hold `scripts/draw.mjs`; Node ≥ 22; a Chrome. Missing → the §3.5 fallback (skip the step, audit against existing brand sources, first screen says 「mockup 未驗證：沒有安裝 taste v2」 with the install command, after-slots say 未驗證, nothing hand-drawn).
  - One main screen captured at 1440 and 390.
  - Deal commands (app: `draw.mjs --app --kind <kind> --screens <screen> --options 3`; page: `draw.mjs --sector <sector> --sections <roles> --options 3`), top-up: other `--theme`, then the neighbouring kind/sector, until three distinct ids; "If top-ups still give fewer than three, say how many and why before showing them; never present two silently." `--keep palette,type` only for values the approved brand source marks as fixed; the logo is always kept. `TASTE_SKILL_HISTORY="$REPORT_DIR/<stem>.evidence/taste-history.json"`, run from a scratch dir.
  - Build each with taste's own run (app: its `references/app-screens.md` §2.3–2.7; page: the run), real labels and realistic repo data, into the live-build path; `inspect.mjs [--app]`, fix FAILs, at most three look-and-fix rounds.
  - Comparison mockup structure per the vault's Project Mockup Convention, panel headings that *start with* `方案 A ·` / `方案 B ·` / `方案 C ·` (R-024 matching), panels hold JPEG/PNG data-URI screenshots at 1440 and 390 plus a relative link to the live build, `.tag.rec` on the recommendation, self-contained, rendered with headless Chrome and looked at before showing.
  - Stop and ask 「選 A、B、C，或混搭（例如 A 的配色＋B 的字）」; a mix is built, added as `.panel.optD` 「方案 D · …」, shown and confirmed; write the record fields from spec §3.1 step 7 under the surface's section; silence or a general 「好」 is not a pick.

- [x] **Step 4: Rewrite SKILL.md** to the six headings in Interfaces. New §1 is a short summary that links `[direction procedure](references/directions.md)` and says the picked direction is the target of §2. In §2 replace the sentence "Missing brand authority becomes an explicit decision gap; it does not justify inventing a new identity." with: "The picked direction is the proposed authority the inventory measures against. Approved rules stay approved; list any conflict between them and the pick instead of resolving it silently." §3 adds the c1 rule from spec §3.2 (c1 = 「把選定方向寫進 BRAND_GUIDE」 when a direction was picked this scan; visual-alignment candidates depend on it; not re-proposed when its row already exists). Update the frontmatter `description` to mention three rendered brand directions. Keep every other rule of the current file.

- [x] **Step 5: decisions.md** — in "Brand coherence", after "Tie each rule to an approved source or mark it as observed/proposed.", add: "A direction picked in step 1 counts as proposed until its BRAND_GUIDE row lands." Add to "Reference basis": `- [tasteskill v2](https://github.com/Leonxlnx/taste-skill): deals and checks the step-1 directions.`

- [x] **Step 6: Run to verify they pass**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats`
Expected: 3 tests, 0 failures.

- [x] **Step 7: Commit**
```bash
git add claude-skills/ship-workflow/tests/test_refactor-brand.bats claude-skills/ship-workflow/skills/ship-refactor-brand/
git commit -m "feat(R-032): ship-refactor-brand deals three brand directions before the inventory"
```

### Task 2: evidence, roadmap, command and agent text

**Files:**
- Modify: `claude-skills/ship-workflow/skills/ship-refactor-brand/references/evidence.md` (Human HTML section)
- Modify: `claude-skills/ship-workflow/skills/ship-refactor-brand/references/roadmap.md` ("Selection and row preparation", step 4 of "Write selected rows")
- Modify: `claude-skills/ship-workflow/commands/ship-refactor-brand.md`
- Modify: `claude-skills/ship-workflow/skills/ship-refactor-brand/agents/openai.yaml`
- Test: `claude-skills/ship-workflow/tests/test_refactor-brand.bats`

**Interfaces:**
- Consumes: Task 1's `setup()` variables `B`, `T`, `S`.

- [x] **Step 1: Append the failing tests**

```bash
@test "evidence.md: rendered after-pictures, 外觀不變, no hand-drawn, 未驗證 fallback (AC-4)" {
  f="$B/references/evidence.md"
  for s in '提案 · 方案' '外觀不變' 'mockup 未驗證' 'Hand-drawn schematic boxes are never a brand after-picture' '品牌方向'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; return 1; }
  done
}
@test "evidence: images are PNG or JPEG, never SVG, never copied markup (review focus 1-2)" {
  f="$B/references/evidence.md"
  grep -qF 'PNG or JPEG data URIs, never SVG' "$f"
  grep -qF "never copy a build's markup or scripts into the report" "$f"
}
@test "roadmap.md: the c1 row carries the directions mockup and mockup 定案 (AC-5)" {
  f="$B/references/roadmap.md"
  grep -qF 'Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html' "$f"
  grep -qF 'mockup 定案 <X>' "$f"
}
```

- [x] **Step 2: Run to verify they fail**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats`
Expected: the three new tests FAIL, Task 1's pass.

- [x] **Step 3: evidence.md** — in "Human HTML", replace "Use readable stacked before/after pictures; label proposed outcomes as proposals, not captured screenshots." with spec §3.3: visual-alignment candidates show 「現在」 (captured) and 「改完」 (a screenshot of the screen built in the picked direction, labelled 「提案 · 方案 X」; same screen reuses the step-1 build, another screen reuses its shell/tokens/type with real content, one `inspect.mjs` check, no new deal); c1 shows the picked panel's screenshots; structural candidates show 「現在」 only, labelled 「外觀不變」; the sentences "Hand-drawn schematic boxes are never a brand after-picture." and "Pictures are images only: embed PNG or JPEG data URIs, never SVG, and never copy a build's markup or scripts into the report."; a 「品牌方向」 block near the top (picked option, its 390 screenshot, relative link to the comparison mockup); without taste v2, the first screen says 「mockup 未驗證：沒有安裝 taste v2」 and after-slots say 未驗證. Keep the `rs_report_check`, `/browse`, merge-forecast and AI-report rules as they are.

- [x] **Step 4: roadmap.md** — in "Selection and row preparation" add the c1 rule from spec §3.2; in "Write selected rows" step 4 add: "The c1 row's description also contains the comparison mockup path `Proposals/mockups/refactor-brand-<stamp>-directions-mockup.html` and `mockup 定案 <X>` (the picked option letter), so Roadmap 檢視 shows the picked option (R-024)." The acceptance policy for brand-decision candidates now reads: a direction picked in step 1 is resolved; its deliverable is documenting it in BRAND_GUIDE.

- [x] **Step 5: command + agent text** — `commands/ship-refactor-brand.md`: one sentence before "Produce the inventory": "Start with the brand-direction step: three rendered directions in one comparison mockup, then wait for the pick (or reuse the recorded one)." `agents/openai.yaml` `default_prompt`: prepend 「先給我三個品牌方向的 mockup 選，」 and `short_description`: 「先選三個品牌方向，再盤點品牌與重複元件，提出整合方案和遷移順序，再選擇加入 Roadmap」.

- [x] **Step 6: Run to verify they pass**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats tests/test_repo-layout.bats tests/test_sync-install.bats`
Expected: 0 failures.

- [x] **Step 7: Commit**
```bash
git add claude-skills/ship-workflow/skills/ship-refactor-brand/ claude-skills/ship-workflow/commands/ship-refactor-brand.md claude-skills/ship-workflow/tests/test_refactor-brand.bats
git commit -m "feat(R-032): brand reports show rendered after-pictures in the picked direction"
```

### Task 3: Redesign the shared report template

**Files:**
- Modify: `claude-skills/ship-workflow/templates/refactor-report.html` (whole file)
- Test: `claude-skills/ship-workflow/tests/test_refactor-brand.bats`; existing `tests/test_refactor-scan.bats` "template: with {{STEM}} filled…" (AC-6) must keep passing unchanged.

**Interfaces:**
- Consumes: `T`, `S` from Task 1's setup.
- Produces (unchanged contract for `/ship-refactor-scan` C2 and the brand evidence rules): `<header id="top">`, hero linking `#c1`, candidate list `<a href="#c<N>">`, hint 「要做哪幾個？在對話裡回數字就好，例如「1、2」。」, `<section id="c<N>">` with 「← 回清單」, the picture wrapped in `<a href="#z<N>">`, overlay `<div id="z<N>" class="zoom">` opened by CSS `:target` with a 「關閉」 link to `#c<N>`, 「問題：」「怎麼改：」「改完：」, AI links to `{{STEM}}.ai.md`, footer, and the `<!-- … -->` repeat comments. Class names may change.

- [x] **Step 1: Append the failing tests**

```bash
@test "template: taste lint reports 0 FAIL (AC-7)" {
  L="${TASTE_SKILL_DIR:-$HOME/.claude/skills/design-taste-frontend}/scripts/lint.mjs"
  [ -f "$L" ] || skip "design-taste-frontend not installed"
  command -v node >/dev/null || skip "node missing"
  sed 's/{{STEM}}/refactor-brand-T/g' "$T" > "$S/report.html"
  run node "$L" "$S/report.html"
  [[ "$output" == *'RESULT: 0 FAIL'* ]] || { echo "$output"; return 1; }
}
@test "template: keeps anchors, zoom, AI link and a brand image example; no lint escapes (review focus 4)" {
  ! grep -qF 'taste-skill-ignore' "$T"
  for s in 'id="top"' 'id="c1"' 'href="#c1"' 'id="z1"' 'href="#z1"' '{{STEM}}.ai.md' ':target' '<img'; do
    grep -qF -- "$s" "$T" || { echo "missing: $s"; return 1; }
  done
}
```

- [x] **Step 2: Run to verify they fail**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats`
Expected: AC-7 FAIL with `RESULT: 3 FAIL, 3 WARN`; the anchors test FAILs on `<img`.

- [x] **Step 3: Restyle the template.** Before writing CSS, read `~/.claude/skills/design-taste-frontend/references/tells.md`, `type.md` and `colour.md`. Rules: phone-first one column (390 primary, comfortable at 1440 with a readable measure), body ≥ 16px, one ground / one ink / one accent, separation by space and tone (no 1px hairlines, no outlined 1px boxes, no shadows-as-borders), no eyebrow label above the hero title, no pill chips (strength · size · merge label become one quiet text line), no emoji (「✕ 關閉」 → 「關閉」), system font stack incl. `"PingFang TC", "Noto Sans TC"`. Keep the box-diagram picture (scan) — boxes become filled tone blocks, problem box in the warning tone, result box in ink. Add, inside an HTML comment next to the picture, the brand variant: `<figure>` with two `<img src="data:image/jpeg;base64,…" alt="…">` captioned 「現在」 and 「提案 · 方案 X」, plus the 「品牌方向」 block for brand reports. Example copy stays as now.

- [x] **Step 4: Run to verify they pass**
Run: `cd claude-skills/ship-workflow && bats tests/test_refactor-brand.bats tests/test_refactor-scan.bats tests/test_command-blocks.bats`
Expected: 0 failures.

- [x] **Step 5: Render for the reviewer (AC-8)**
```bash
mkdir -p .ship/evidence && sed 's/{{STEM}}/refactor-brand-T/g' claude-skills/ship-workflow/templates/refactor-report.html > .ship/evidence/report.html
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$C" --headless=new --hide-scrollbars --window-size=390,2400 --screenshot=.ship/evidence/template-390.png "file://$PWD/.ship/evidence/report.html"
"$C" --headless=new --hide-scrollbars --window-size=1440,1800 --screenshot=.ship/evidence/template-1440.png "file://$PWD/.ship/evidence/report.html"
"$C" --headless=new --hide-scrollbars --window-size=390,844 --screenshot=.ship/evidence/template-z1-390.png "file://$PWD/.ship/evidence/report.html#z1"
```
Expected: three PNGs exist (`.ship/` is git-ignored; do not commit them).

- [x] **Step 6: Commit**
```bash
git add claude-skills/ship-workflow/templates/refactor-report.html claude-skills/ship-workflow/tests/test_refactor-brand.bats
git commit -m "feat(R-032): redesign the shared refactor report template"
```

### Task 4: Full suite

- [x] **Step 1: Run**
Run: `cd claude-skills/ship-workflow && bats tests/ 2>&1 | grep -E '^not ok|^1\.\.'`
Expected: only `not ok … cwd-guard: exits 0 when not in a git repo at all` (known in a linked worktree).

- [x] **Step 2: Guard the diff scope**
Run: `git diff --name-only main...HEAD`
Expected: only paths under `docs/specs/`, `docs/plans/`, `claude-skills/ship-workflow/skills/ship-refactor-brand/`, `claude-skills/ship-workflow/templates/refactor-report.html`, `claude-skills/ship-workflow/commands/ship-refactor-brand.md`, `claude-skills/ship-workflow/tests/test_refactor-brand.bats`.

## Execution log

- Deviation: Use ASCII-only names for the new bats tests, keeping their assertions unchanged — `.ship/tdd-rules.md` requires ASCII names because CJK names can be skipped by bats under some locales.
- Task 1: AC-1/2/3 failed before implementation; `bats tests/test_refactor-brand.bats` passed 3/3. Baseline `test_refactor-scan.bats` passed 27/27.
- Task 2: the three added tests failed before implementation; brand/layout/sync checks passed 38/38.
- Deviation: Re-rendered the phone evidence through the existing `rs_report_shot` 390px iframe helper and cropped only the surrounding browser canvas — the prescribed `--window-size=390,...` captures clipped content because Chrome lays out at its minimum width, contrary to AC-8 and `.ship/tdd-rules.md`.
- Task 3: new template tests failed as expected (3 FAIL / 3 WARN and missing image example); brand/scan/command checks passed 91/91, and filled-template lint reported 0 FAIL / 0 WARN. Inspected `.ship/evidence/template-390.png`, `template-1440.png`, and `template-z1-390.png`: readable, no right-edge clipping at true 390px, zoom opens with its close link. The phone overview includes the helper's red 844px fold marker.
- Task 4: full suite ran 827 tests: 826 passed, only the documented pre-existing `cwd-guard: exits 0 when not in a git repo at all` failed (test 203). Full TAP log: `.ship/evidence/full-suite.log`. `git diff --name-only main...HEAD` contains only the allowed paths. No new baseline failures.
- Deviation: Added an HTML-encoded fallback-command example while preserving the exact displayed command — a literal `https://` in the prescribed no-taste report reproducibly fails `rs_report_check` with `external-url`.
- Deviation: Restricted comparison-mockup metadata to the direction-documentation candidate and used its recorded path on reuse — an ordinary c1 or a no-taste scan has no new direction mockup to attach.
- Deviation: Added the missing reuse-without-row guard in SKILL.md and roadmap.md — a saved pick followed by report-only must still propose the BRAND_GUIDE prerequisite until its matching row is queued or done; existing-row reuse remains unchanged.
- Review fixes: three added regression tests failed before the fixes; brand/scan checks now pass 38/38. Deferred minor: the commented brand figure needs a light `.fig` surface when copied into the dark zoom overlay; the rendered scan example is unaffected.
- Final verification after review fixes: full suite 829/830 passed; the only failure remains the documented test 203 `cwd-guard: exits 0 when not in a git repo at all`. Log: `.ship/evidence/full-suite-after-review.log`. Scope remains within the authorized paths. No push or branch switch.
