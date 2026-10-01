---
date: {{date}}
updated: {{date}}
type: spec
id: {{id}}
tags: [spec, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-item: {{id}}
---

## For future Claude
> {{id}}: spec for <topic>.
> The contract that the plan + build implement.

## Seams

Declare every boundary this work introduces or changes. Tests may assert a
seam's guaranteed behavior and nothing inside it.

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| <name> | `func(arg) -> Type` | <what callers may rely on> |

This section is REQUIRED. `/ship-next` Phase 4 refuses to proceed without it
in `--auto:yes` mode.

(Use superpowers:brainstorming's spec format from here onward.)
