# Ship Workflow — Flow Diagrams

## Daily flow

```
                            ┌─────────────────┐
                            │ /ship-init      │ (once per repo)
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
                            └────────┬────────┘
                                     │
                                     └─▶ back to /ship-next
```

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
                                                 ├── specs/R-NNN-*.md      (in flight only)
                                                 ├── plans/R-NNN-*.md      (in flight only)
                                                 └── learnings/R-NNN-*.md  (what a shipped R-NNN leaves)
```

Sync direction is **strictly one-way** (Obsidian → repo). To edit strategy, edit in Obsidian.
