# Ship Workflow — Flow Diagrams

## Daily flow

```
                            ┌─────────────────┐
                            │ /ship-init      │ (once per repo)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-arch      │ ← optional: snapshot initial architecture
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
                            │ /ship-next      │ ◀── /ship-research <topic>
                            └────────┬────────┘     (fill gap before brainstorm)
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-build     │ ◀── /ship-research <topic>
                            └────────┬────────┘     (mid-build knowledge need)
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ /ship-compound  │ → optional: /ship-arch (refresh if architecture shifted)
                            └────────┬────────┘
                                     │
                                     └─▶ back to /ship-next
```

## Knowledge-input bridge commands

`/ship-arch` and `/ship-research` are **optional inputs** that write to AIR-OS:

```
                     ┌────────────────────────────────┐
   /ship-arch  ────▶ │ AIR-OS 10 Projects/<P>/        │
                     │   Architecture/  ◀── codebase  │
                     │     scan output                │
                     │                                │
/ship-research  ───▶ │ AIR-OS Projects/<P>/Research/  │ ◀── 3-5 external sub-queries
   <topic>           │   or Research/Deep/ (global)   │     synthesized vs vault baseline
                     └────────────────────────────────┘
                              │
                              ▼
                     next ship-* command's sync.sh
                     auto-pulls into repo's docs/product/
                     so brainstorm / writing-plans see it
```

These commands DELEGATE to the underlying obsidian-second-brain skill commands (`/obsidian-architect` and `/obsidian-research-deep`) but add ship housekeeping (sync, _log.md, commit).

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
