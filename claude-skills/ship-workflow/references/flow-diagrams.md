# Ship Workflow — Flow Diagrams

## Daily flow

```
                            ┌─────────────────┐
                            │ /ship-init      │ (once per repo)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ UA /understand  │ ← optional, run in Claude Code
                            └────────┬────────┘
                                     │
                                     ▼
        ┌─────────────────┐    ┌─────────────────┐
        │ /ship-idea      │───▶│ docs/ideas/     │
        └─────────────────┘    │ IDEA-NNN-*.md   │
                               └────────┬────────┘
                                        │ (some graduate into ROADMAP.md rows)
                                        ▼
                            ┌─────────────────┐
                            │ /ship-next      │
                            │ (mega)          │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ ✅ shipped       │ → /ship-compound runs inside Phase 8
                            └────────┬────────┘   optional: UA /understand if code shape shifted significantly
                                     │
                                     └─▶ back to /ship-next
```

## Optional input

UA's `/understand` (code understanding) is an optional input: when
`target-repo/.ua/knowledge-graph.json` exists, ship-next reads it in Phases 3, 6 and 8.

## Dual-brain sync

```
Obsidian AIR-OS (source of truth)              Repo (mirror + execution)
─────────────────────────────────              ─────────────────────────
10 Projects/<repo>/                            <repo>/
  ├── VISION.md          ───── sync ─────▶     docs/product/VISION.md
  ├── STRATEGY.md        ───── sync ─────▶     docs/product/STRATEGY.md
  ├── ROADMAP.md         ───── sync ─────▶     docs/product/ROADMAP.md
  ├── QUARTERLY_GOALS.md ───── sync ─────▶     docs/product/QUARTERLY_GOALS.md
  └── (other AIR-OS notes — not synced)

                                               <repo>/docs/
                                                 ├── ideas/IDEA-NNN-*.md
                                                 ├── decisions/D-NNN-*.md
                                                 ├── brainstorms/R-NNN-*.md
                                                 ├── specs/R-NNN-*.md
                                                 ├── plans/R-NNN-*.md
                                                 └── learnings/R-NNN-*.md
```

Sync direction is **strictly one-way** (Obsidian → repo). To edit strategy, edit in Obsidian.
