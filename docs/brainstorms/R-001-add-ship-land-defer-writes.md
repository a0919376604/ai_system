---
date: 2026-10-15
type: brainstorm
id: R-001
status: complete
spec: docs/specs/R-001-add-ship-land-defer-writes.md
---

# R-001 brainstorm — parallel mr-mode ships stop conflicting; /ship-land works

## Trigger

2026-10-14, langlive-line-oa: !285–!288 open at once. Merging !285 put !286/!287/!288
into conflict on the tails of `docs/learnings/_log.md` and `docs/tdd-rules.md`.
Three manual union merges; every later merge re-conflicts the rest.

## What exploration found (before any question)

- Every `compound:` / `context:` / `log: ship` commit of an mr-mode ship lands on the
  review branch (verified: `8401aea8 log: ship R-237`, `b7007e4f compound: R-237`,
  `2884ef23 context: …R-237` are only reachable from `ship/R-237-*`).
- Four shared files are written by every ship: `_log.md` (tail append),
  `docs/tdd-rules.md` (tail append), `CONTEXT.md` (append or refine),
  `docs/product/ROADMAP.md` (whole-file vault mirror).
- `_log.md` has nine appenders, not two: next, compound, idea, decision, explain,
  research, roadmap, propose, land. `/ship-idea --during-build` runs inside the
  worktree during Phase 6, so it hits the review branch too.
- `commands/ship-land.md` **exists** (commit `7cb2ac5`) but was never linked into
  `~/.claude/commands/`, so `/ship-land` is not invocable. Its last step commits
  `_log.md` + the ROADMAP mirror to the local base branch and never pushes.
- langlive `main`: protected, push allowed for Maintainers; the operator is
  Maintainer (access_level 40). Convention since 2026-09-18 is MR-only.
- langlive CI: every job carries a `changes:` filter on code paths (`backend/`,
  `modules/`, `frontend/`, `frontend-liff/`, `Dockerfile.*`, `.gitlab-ci.yml`).
  A commit touching only `docs/` + `CONTEXT.md` creates no pipeline.
- `.claude/ship-config.yml` is tracked, so `merge_mode` resolves correctly inside
  worktrees. Phase 7 opens MRs with `--remove-source-branch`.

## Decisions

| # | Question | Answer | Why |
|---|---|---|---|
| 1 | May `/ship-land` push a bookkeeping commit straight to the base branch? | **Yes**, tagged `[skip ci]` | Operator is Maintainer; CI path filters already skip docs-only commits; `[skip ci]` makes it hold for repos without filters |
| 2 | One commit per land, or batch land? | **A1 — one per `/ship-land R-NNN`** | Simplest; batch is YAGNI |
| 3 | Is a land-time fold the right pattern at all? (operator asked for prior art) | **Per-file mix**, not one mechanism | See below |
| 4 | `CONTEXT.md`: single file deferred to land, or per-term fragments? | **X — single file, deferred** | Keeps the format other tools read; only lands with new terms commit |
| 5 | Reinterpret done-when D for `_log.md` | **OK** — row must reach base branch *git history* (`Ship-Log:` trailer), not the file | Writing the file at land would force a commit every land |
| 6 | Reinterpret done-when C for tdd rules | **OK** — new rules go to fragments in both modes; executor sees identical rule text | One code path instead of a mode branch |

## Prior art consulted (decision 3)

1. **Fragments compiled later** — towncrier, scriv, changesets; GitLab's 2018
   `changelogs/unreleased/*.yml`. Compile happens at release, batched.
2. **Permanent fragments, never compiled** — OpenStack reno.
3. **No file at all, derive from git** — GitLab later replaced its YAML fragments
   with `Changelog:` commit trailers.

GitLab moved from (1) to (3). Applying (1) uniformly to four files of different
nature was heavier than needed, so each file got the lightest family that fits:
`_log.md` → (3); `tdd-rules` → (2); ROADMAP mirror → stop committing it; only
`CONTEXT.md` → (1).

## Out of scope, recorded

- IDEA-NNN allocation scans `docs/ideas/` in the worktree, so two parallel
  branches can mint the same ID (add/add conflict). Separate follow-up.
- langlive keeps stale June copies of the commands in a gitignored
  `.claude/commands/` (from `/ship-init`'s `cp`). Not touched here.
