# Brand and component decisions

Use these criteria for an existing frontend. Scale the inventory to the requested scope; a small site does not need a separate design-system package.

## Brand coherence

Tie each rule to an approved source or mark it as observed/proposed. Check:

- **Typography:** families, roles, hierarchy, line height, readable measure, density, language coverage and fallbacks. Marketing, reading and task-oriented surfaces may use different scales within one system.
- **Color:** text, surfaces, borders, actions, status and focus; contrast and existing themes.
- **Geometry:** spacing rhythm, container widths, grid, alignment, border/radius, depth and responsive behavior.
- **Expression:** logo handling, photography/illustration, icon family, motion and recurring signature elements.
- **Content and behavior:** consistent action names and tone, feedback, loading, empty/error states and navigation expectations.

Keep deliberate variation visible in the rules. For example, an expressive campaign hero and a compact billing screen can share the same brand without sharing a template.

## Token decisions

Select a token by its role, not its current value. `action.primary` and `status.success` remain separate semantic roles even when both currently resolve to the same green. They may share a primitive color underneath when that fits the existing token model.

Map hard-coded values to an existing token only when meaning fits. A near match can be intentional; inspect usage before rounding all values onto a scale. Introduce a token when it represents a reusable or authoritative decision, not merely because a literal exists. Account for themes and states when replacing values. Follow existing naming and canonical storage.

## Component decisions

| Evidence | Decision |
| --- | --- |
| An existing primitive already supports the behavior | Reuse it; migrate the local copy. |
| Same purpose and behavior, with meaningful size/emphasis differences | Use explicit variants with sensible defaults. |
| Repeated visual structure with independent business rules | Share a presentational layer or composition primitive; retain domain components. |
| Similar markup but different interaction/HTML semantics | Preserve those contracts; share styling or smaller primitives where useful. |
| A one-off or unstable pattern | Keep it local until the reusable contract is evident. |
| Vendor-controlled UI | Use documented theming/composition hooks and record limits. |

Repeated use is evidence, not a mandatory count. Three occurrences do not justify merging unrelated behavior; an established primitive can be appropriate for one new consumer.

Before extraction, describe what consumers would change together and what must remain independent. An API accumulating unrelated booleans or page-name checks signals a misplaced boundary.

For example, `ProductCard` and `InvoiceSummary` can share a `Surface` only if its presentation contract is useful. Product inventory and payment permissions stay in their domain components. Likewise, a navigation CTA remains a link; adopting button styling must not remove link behavior.

## Migration decision record

For each family, record:

- Canonical component/token and the rule that justifies it.
- Current consumers and destination mapping.
- Variants/states to preserve, and deliberate exceptions with reasons.
- Expected visual differences versus behavior that must stay the same.
- Migration status and remaining legacy references.

Reuse an existing project tracking format. Prioritize shared navigation, controls, typography and layout primitives by impact and dependency order. Avoid collecting every possible future abstraction.

## Reference basis

These are background sources, not dependencies to open on every run:

- [Interface Inventory](https://bradfrost.com/blog/post/interface-inventory/): compare treatments across a site.
- [Atlassian design tokens](https://atlassian.design/foundations/tokens/design-tokens): choose semantic roles.
- [GOV.UK contribution criteria](https://design-system.service.gov.uk/community/contribution-criteria/): useful, unique, usable, consistent and versatile components.
- [Impeccable extract flow](https://github.com/pbakaus/impeccable/blob/main/skill/reference/extract.md): discover, extract, migrate and document.
