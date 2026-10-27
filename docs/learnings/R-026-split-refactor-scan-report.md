---
date: 2026-10-27
updated: 2026-10-27
type: learning
id: R-026
tags: [learning, ai_system, ship-workflow, refactoring, report, mobile]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-026
shipped: true
shipped-date: 2026-10-27
---

## For future Claude
> R-026 split `/ship-refactor-scan`'s report into two files with one stem.
> - **`Reports/refactor-scan-<stamp>.html`, for a person.** It is mockup option B from
>   `templates/refactor-report.html`:
>   - the first screen holds the top recommendation plus one row per candidate, showing
>     值得做/可考慮, 小/中/大 and 自動合併/要人審;
>   - each `#c<N>` holds a stacked big-box picture that opens full screen through CSS
>     `:target`;
>   - no JS, no CDN, no Pocock jargon.
> - **`Reports/refactor-scan-<stamp>.ai.md`, for AI.** It keeps every card field R-025 had.
>
> Rows link the AI file from the description and the human file from `↳ explain`. Three new
> lib functions gate it:
> - `rs_report_check`: eight mechanical rules;
> - `rs_report_shot`: a 390 px **iframe** render with an 844 px fold line;
> - `rs_merge_label`: reads `one_way_paths`.
>
> The line-oa report and R-259 were regenerated in the new format.

## What Shipped
- **`templates/refactor-report.html`:** the option-B CSS and blocks, with one example
  candidate and a `{{STEM}}` placeholder.
- **`lib/refactor-scan.sh`:**
  - `rs_merge_label <base-ref> <path>...` reuses `_sn_one_way_paths` and `_sn_glob_match`.
  - `rs_report_check <stem>`, with rules `missing`, `script` (tags, `on…=` handlers,
    `javascript:`), `external-url`, `anchors`, `ai-sections`, `cross-link`, `jargon`
    (visible text only, under `LC_ALL=C`) and `zoom`.
  - `rs_report_shot <html> <png> [<fragment>]`: a harness iframe of 390 × 6000 with a fold
    line, or 390 × 844 for an overlay. Chrome's log is shown only on failure, and no
    file-access flag is passed.
  - `rs_write_rows` takes a stem.
- **`commands/ship-refactor-scan.md`:**
  - C2 rewritten: two files, the field list, the strength mapping, `rs_merge_label`.
  - A check-and-shot block at the end of step 1.
  - Step 3 passes the stem; step 4 prints both paths.
- **Tests:** 753 (+15); the one known cwd-guard failure.
- **Vault, AC-9:**
  - `langlive-line-oa/Reports/refactor-scan-2026-10-27-0317.{html,ai.md}` regenerated;
  - R-259 links both files;
  - the R-025 HTML was kept at `/tmp/refactor-scan-2026-10-27-0317.r025.html` until this
    session ends.

## Key Decisions
- **leric:**
  - 「可以寫一份是給AI一份給人看的沒關係 反正可以連結 然後圖片需要放大 我在手機上根本看不到字」;
  - picked mockup option B (`Proposals/mockups/refactor-scan-report-mockup.html`);
  - had pinch zoom turned on in `obsidian-html-plugin` (`zoomByWheelAndGesture`), outside
    the ship;
  - 「26 auto」.
- **Same stem for both files,** so R-259's human link survived.
- **The description links the AI file (Phase 3 reads it); `↳ explain` links the human file**
  (the operator taps it in Roadmap 檢視). These were mockup Q3 and Q4, taken as
  recommended.
- **The merge label is a forecast from `one_way_paths` only.** `sn_door` still decides at
  ship time, since it also escalates migrations, deploy files and dependencies (spec R4).
- **Readability is gated by mechanical rules plus a picture Claude must look at,** not by
  review judgment. R-025's review never saw the phone.
- **From the builder check:**
  - the shot is a tall page with a fold line, plus an optional fragment shot;
  - SVG without `xmlns`;
  - read the old report before overwriting it.
- Door: two-way.

## What Changed From Plan
- **Codex** (1 round, DONE_WITH_CONCERNS) made two local repairs: the zsh twin of the
  step-3 link assertion was updated too, and `|| return 1` was added to three loop
  assertions for suite hygiene. Its URL encoding moved to portable sed after zsh mangled
  `%` and `#` in parameter expansion.
- **Review attempt 1:**
  - Running AC-9 for real showed `rs_report_shot` printing about 50 Chrome CVDisplayLink
    lines per call. Fixed with TDD (842e34f).
  - Code review (inline): 2 nits. Spec review: no gaps.
  - **Security pass:** one candidate at confidence 5, below the bar: an LLM-written page
    rendered with JS on and `--allow-file-access-from-files`. It was hardened anyway
    (099f519):
    - the flag was measured as unnecessary (same pixels without it) and removed;
    - rule 2 now rejects `on…=` and `javascript:`;
    - JS-off was tried and rejected, because Chrome writes no screenshot with
      `scriptEnabled=false` unless the file flag is on.
- **Review attempt 2:** no spec gaps, 2 nits. The spec was updated to match the stricter
  rule 2.

## Bugs
- **`rs_report_shot` passed Chrome's stderr straight through.** Every command run would have
  printed about 50 harmless lines. Caught only by running the function on a real report.
- **The headless window is not the viewport.** While making the mockup, a 390 px
  `--window-size` screenshot was laid out wider than 390 px, and that made it look as if
  R-025's report title was cut off. That was false; the real defects were 140 px diagrams,
  an overflowing hotspot table and 12 lines of paths before the picture. Wrapping the page
  in a 390 px iframe gives the true phone layout; `rs_report_shot` is built on it.

## Lessons → checks
- A wrapper around a noisy external program keeps its log and shows it only on failure —
  enforced by `tests/test_refactor-scan.bats` "rs_report_shot: Chrome's own log stays quiet
  on success and surfaces on failure" · proof: red at 2e7ce2a (exit 1) · green at 914459b.
- Rendering LLM-written HTML grants no extra local file privileges — enforced by
  `tests/test_refactor-scan.bats` "rs_report_shot: Chrome gets no file-access flag" · proof: red at 842e34f (exit 1) · green at 914459b.

## Reusable Patterns
- **Measure phone layouts inside a 390 px iframe, not a 390 px headless window.**
  `rs_report_shot` does it. The vault mockup convention's verify step still says
  `--window-size` only.
- **Run the new function on real data before review.** Both bugs of this ship (log noise,
  the window-size illusion) were invisible to unit tests and fixtures.
- **Turn "a person couldn't read it" into rules plus a mandatory look:** rules for what can
  be counted (anchors, jargon, external URLs), and a screenshot with a fold line for what
  cannot.

## Technical Debt
- Rule 2's `[[:space:]]on[a-z]+[[:space:]]*=` also matches plain text such as `one = two`.
  It fails closed and is unlikely in zh-TW prose (review nit).
- `rs_report_check` passes a pair with zero candidates (review nit).
- The merge label ignores migrations, deploy files and new dependencies (spec R4).
- Rule 6 only checks that the other file's name appears, not that it is a real link
  (spec-review note).

## Future Follow-ups
- Update the vault `_CLAUDE.md` Project Mockup Convention: for phone width, verify in a
  390 px iframe, since a narrow `--window-size` lays out wider.
- R-259 in line-oa is ready for `/ship-next R-259`.
