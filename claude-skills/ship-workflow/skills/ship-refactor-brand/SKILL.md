---
name: ship-refactor-brand
description: Use when an existing website needs three rendered brand directions followed by a brand consistency and shared-component scan, integration proposals, migration ordering, and selectable Roadmap candidates for ship-next. Applies to 品牌一致性、前端整體優化、共用元件整合 and ship-refactor-brand. This is a planning and Roadmap intake workflow, not an implementation command.
---

# Ship Refactor Brand

One invocation produces a brand/component inventory, integration proposals and migration order, then lets the user choose what enters **🔜 Next**. Follow the report → pick → enqueue contract of `/ship-refactor-scan`. `/ship-next` designs and implements selected Roadmap items later.

There are no audit/plan/apply modes. An optional scope (pages, subsystem or pain point) narrows the scan. Calling this skill alone authorizes scanning and reports; it does not select candidates, authorize Roadmap writes, or start implementation.

## 0. Resolve project and ship integration

Run against the target repo, not the skill directory. Read [Roadmap integration](references/roadmap.md) to resolve the installed ship helpers and vault project. Read the available `commands/ship-refactor-scan.md` for its report/pick conventions; do not invoke its architecture scan or its implementation workflow.

Record the repo root, revision and dirty state. Read `CONTEXT.md`, existing brand guidance, design-system docs, tokens, shared UI, relevant previous reports, rejected candidates and existing Roadmap rows. Match rendered evidence to its revision when possible; label working-tree deviations. Preserve existing user edits.

## 1. 品牌方向 · pick a brand direction

Follow the [direction procedure](references/directions.md): deal three rendered directions, stop for the pick (or reuse the recorded one), and make the picked direction the target of step 2. Without taste v2, follow its unverified fallback.

## 2. Inventory brand drift and duplicate UI

Read [decision criteria](references/decisions.md). Distinguish approved rules, observed implementation and proposed decisions. Preserve intentional differences across marketing, reading and product surfaces. The picked direction is the proposed authority the inventory measures against. Approved rules stay approved; list any conflict between them and the pick instead of resolving it silently.

Inspect both source and rendered UI using gstack `/browse`. Cover typography, color roles, spacing/layout, imagery/icons, motion, voice and interaction states. Map similar treatments to their components, consumers and canonical alternatives. Record checked routes, viewports and states; mark sampling, authentication blocks and unavailable previews. Source-only findings cannot establish rendered visual quality.

Use frontend reach and user impact to prioritize: shared navigation/controls and high-traffic journeys before isolated decoration. Git churn can supplement this evidence; it is not the only scan filter. Revisit a previously rejected candidate only when new evidence changes its rationale, and explain why.

## 3. Propose integration and migration order

Turn findings into numbered candidates with a concrete outcome, evidence, intended common boundary, consumers, preserved exceptions, estimated size and acceptance checks. Reuse existing tokens/components where their contracts fit. Similar appearance alone does not justify combining independent domain logic.

Classify each candidate as **structural consolidation**, **intentional visual alignment**, or **brand decision needed**. Identify dependencies and a recommended order. For wide structural changes, propose independently landable expand → migrate → contract slices. Make intended visual differences explicit and separate them from behavior that must remain unchanged. Interface design and implementation detail belong to `/ship-next` Phase 3.

Propose the direction-documentation candidate 「把選定方向寫進 BRAND_GUIDE」 as c1 by the rule in [Roadmap integration](references/roadmap.md#selection-and-row-preparation); visual-alignment candidates depend on it.

## 4. Present linked reports and the choice

Read [reports and evidence](references/evidence.md). Save linked human HTML and AI Markdown reports, including the inventory, integration proposals, migration sequence, coverage gaps and Top recommendation. Validate and visually inspect the human report before presenting it. No application source, design guidance or dependencies are modified during the scan.

Ask which numbered candidates should enter Roadmap. Offer the recommended candidate or dependency-complete group, allow a custom subset, and offer report-only. Choosing concrete rows authorizes those writes; do not ask for the same approval again. If selection is missing, wait with reports ready. Do not infer selection from silence or a general acknowledgement.

## 5. Enqueue only the selected work

Follow [Roadmap integration](references/roadmap.md): check dependencies and duplicates, show the proposed selected row breakdown, sync, reserve IDs, insert into the vault's **Next**, then sync the mirror. New or materially changed rows need selection; do not silently add prerequisites. Capture durable rejection reasons alongside the reports.

Stop after reporting the written IDs and report links, or the report-only outcome. Hand off to `/ship-next R-NNN`; do not execute the refactor, update design rules, commit source changes or start a ship automatically.
