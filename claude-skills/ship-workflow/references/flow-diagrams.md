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
                            │ (mega)          │     (fill gap before brainstorm or implementation)
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ ✅ shipped       │ → /ship-compound runs inside Phase 8
                            └────────┬────────┘   optional: UA /understand if code shape shifted significantly
                                     │
                                     └─▶ back to /ship-next
```

## Knowledge-input bridge commands

`/ship-research` (external grounding) and UA's `/understand` / `/understand-explain` (code understanding) are **optional inputs**:

```
   /ship-research  ────▶ │ AIR-OS 10 Projects/<P>/Research/         │
   UA /understand  ────▶ │ target-repo/.ua/knowledge-graph.json    │
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
