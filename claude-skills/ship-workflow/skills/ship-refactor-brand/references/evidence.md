# Reports and evidence

Produce the same two-audience report shape as ship-refactor-scan. This is a proposal, not a claim that the website was fixed.

## Location and identity

Use `Reports/refactor-brand-<timestamp>.html` and `Reports/refactor-brand-<timestamp>.ai.md` in the resolved vault project. Use the user's timezone, include seconds or another collision-safe suffix, and reuse the same stem throughout. If there is no vault binding, use a fresh OS temporary directory and keep the workflow report-only.

Inspect existing reports before refreshing one. Record durable rejected candidates in `Reports/refactor-brand-rejected.md`, with date, candidate/files and reason. Skip ephemeral “not now” reasons. Read this record on later scans, along with queued/completed Roadmap work, so a rerun does not repeat already handled proposals.

## Human HTML

Use ship-workflow's `templates/refactor-report.html` when available. Replace its example project/content and `{{STEM}}`; use plain Traditional Chinese and the user's domain terms. The first screen contains the conclusion, coverage summary, Top recommendation and numbered candidate list. Details explain:

- What is inconsistent or repeated, and its visible/user-facing impact.
- What would be unified, what stays independent, and expected before/after differences.
- Proposed migration order and prerequisites, estimated 小/中/大 effort, recommendation and acceptance outcome.

Keep candidate anchors `c1`, `c2`, … and matching zoom overlays `z1`, `z2`, …. Use readable stacked before/after pictures; label proposed outcomes as proposals, not captured screenshots. Link to the AI report by relative basename. Keep HTML self-contained, with no scripts or external URLs; escape copied source text. Preserve useful intentional variations in examples.

For code-sensitive merge forecasts, use `rs_merge_label HEAD <candidate files>` and label the result as a forecast; final merge handling belongs to ship-next. If the helper is unavailable, mark the forecast unknown rather than inventing it.

Run `rs_report_check <absolute-stem>` when the matching helper is available. Fix reported structural issues. Inspect the report and a zoom detail through `/browse` at phone width and desktop width; inspect the captured image, not only its filename. Use `/browse` for report viewing too, rather than bypassing the configured browser with `rs_report_shot`. If browser access is unavailable, state that report readability and website visuals remain unverified. A report with no worthwhile candidates should say so and offer no invented work.

## AI Markdown

Start with `Human report:` followed by a relative link to the matching HTML basename. Include:

1. **Context and authority:** repo/revision, user scope, approved brand sources, observed conventions, unresolved decisions, existing canonical code and relevant Roadmap rows.
2. **Inventory and coverage:** routes/page families, component consumers, repeated visual treatments, source versus browser inspection, actual viewports/states, blocked or uninspected areas and evidence references. Use a denominator only when discovery is complete.
3. **One `## c<N> · <name>` per candidate:** files/locations, evidence, problem, outcome, proposed consolidation boundary, preserved exceptions, change kind, migration slices, dependencies, estimated size, recommendation strength, merge forecast, expected visual differences, behavior invariants and acceptance criteria. Include an ADR/rejection conflict when relevant. Add diagrams where useful.
4. **Migration order and Top recommendation:** explain dependency edges and which candidate/group can start independently.
5. **Roadmap-ready rows:** proposed description, one-sentence human summary, done-when, dependency and linked card for each intended row. Present any multi-row breakdown before asking for selection.
6. **Verification and continuity:** actual checks performed, missing runtime evidence, and future acceptance work. Propose the eventual design-guidance update as part of a candidate, not an edit performed by this scan.

## Acceptance criteria for future implementation

Use observable outcomes: named consumer migrations, remaining legacy references/overrides, reviewed intentional visual changes, preserved interaction and business behavior, relevant viewport/theme/state coverage, and updates to existing design guidance. Screenshots should use comparable viewport, content, state and font readiness. Select relevant keyboard, navigation, loading/error, long-text and responsive checks. Use existing project checks; do not require new tools merely to complete a scan.

Pure structural changes preserve appearance and behavior. Visual-alignment work names the intended appearance change and preserves unrelated behavior. A brand-decision candidate is complete when a direction is resolved and documented; it must not promise a design decision the user has not made.

## Response at the selection point

Give the human report link first, then a compact numbered proposal list and recommended migration order. Show which work is proposed, already queued or blocked by missing evidence. Ask for candidate selection only after the report and proposed rows are reviewable.

After enqueueing, report each actual R-ID and its description, dependencies, both report links, recorded rejections and any partial failure. Compare repo status with the initial snapshot and attribute only the expected ship sync/reservation effects. Do not report uninspected pages or unexecuted refactors as completed.
