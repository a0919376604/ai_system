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
                                        │ (some graduate)
                                        ▼
        ┌─────────────────┐    ┌─────────────────┐
        │ /ship-decision  │───▶│ docs/decisions/ │
        └─────────────────┘    │ D-NNN-*.md      │
                               └────────┬────────┘
                                        │
                                        ▼
                            ┌─────────────────┐
                            │ /ship-roadmap   │ (refresh ranking)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-next      │ (pick + brainstorm + spec)
                            └────────┬────────┘
                                     │ also accepts --adhoc
                                     ▼
                            ┌─────────────────┐
                            │ /ship-build     │ (plan + execute)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-compound  │ (learn + promote + close)
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
                                                 ├── brainstorms/R-NNN-*.md
                                                 ├── specs/R-NNN-*.md
                                                 ├── plans/R-NNN-*.md
                                                 └── learnings/R-NNN-*.md
```

Sync direction is **strictly one-way** (Obsidian → repo). To edit strategy, edit in Obsidian.
