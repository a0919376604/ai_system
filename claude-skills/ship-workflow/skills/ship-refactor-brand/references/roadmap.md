# Roadmap integration

Use ship's existing vault binding, synchronization, ID reservation and insertion helpers. This skill changes its own proposal workflow; it does not replace ship's infrastructure.

## Resolve once, carry paths explicitly

An explicitly supplied `SHIP_LIB` is authoritative. Otherwise locate a coherent ship-workflow installation through the available skill path, then the usual `~/.agents/skills/ship-workflow`, `~/.claude/skills/ship-workflow` or `~/.codex/skills/ship-workflow` locations. Prefer the installation that contains the current `commands/ship-refactor-scan.md`. Require these files in the same installation:

- `lib/airos-binding.sh`
- `lib/sync.sh`
- `lib/id-gen.sh`
- `lib/roadmap-insert.sh`

Set `SHIP_LIB` to that installation's absolute `lib` directory; use it in every shell/process, since shell variables do not persist between calls. Source its `refactor-scan.sh` only for available report and structural-acceptance helpers. Read the installed command/helper interfaces before calling them; do not mix an old Claude installation with a newer Agents installation.

From the target repo root, run `bash "$SHIP_LIB/airos-binding.sh" project_path` to resolve the vault project. Read its `ROADMAP.md` and confirm the **## 🔜 Next** section. Put reports in that project's `Reports/`. With missing binding/helpers/ROADMAP, finish the scan in a temporary report directory and explain that enqueueing is unavailable. Do not manufacture a new project or write to `docs/product/ROADMAP.md` as the source of truth.

A linked worktree requires care: ship sync can skip there. Before enqueueing, resolve the main checkout, verify its binding matches the report's project, and perform synchronization/reservation/insertion from that main root. Do not reserve against a stale worktree mirror.

## Selection and row preparation

Before any sync, reservation or Roadmap mutation:

1. Have a report and reviewable proposed rows. Get explicit selection of those candidates/rows. A recommendation is not selection; “thanks/OK” without a concrete selected set is not an instruction to enqueue everything.
2. Check the canonical Roadmap for the same outcome, affected scope and existing report/card links. Reuse an existing queued item's ID in the report when appropriate instead of inserting a duplicate; modifying its scope requires a separate user instruction.
3. Check dependencies. A selected dependent needs its prerequisite already completed/queued or included in the selected set. If it is absent, explain the dependency and ask for the revised selection. Leave dependent writes pending; never silently select extra work.
4. If a candidate now needs more/different rows than the breakdown the user saw, present that breakdown before writing it. A pre-shown expand/migrate/contract group can be selected as one candidate.
5. Prepare a durable `<stem>.rows.json` beside the reports, with selected card, change kind, description, summary, done-when, prerequisites and later the assigned ID/write status. Use data files/process argument arrays, never executable interpolation of report text.

## Acceptance policy

`rs_write_rows` unconditionally appends structural-only guardrails. Do not use it for a mixed batch or for visual-alignment work.

For **structural consolidation**, preserve appearance and behavior. Where available, use `rs_done_when <outcome>` to include ship's established refactor safeguards in that row's done-when.

For **intentional visual alignment**, name the approved target and expected appearance differences, require relevant before/after and interaction checks, and preserve unrelated business behavior. Do not append “only structure changes” or “all visuals unchanged”. For **brand decision needed**, define a decision/documentation deliverable, not implementation of an unchosen identity.

Include a `Door: one-way — <reason>` annotation only when grounded in a genuinely one-way external contract change. Never downgrade ship's eventual risk checks based on this scan.

## Write selected rows using existing helpers

Once selection is settled:

1. Re-resolve and verify the vault binding and report paths. Confirm Roadmap still has Next and recheck duplicates.
2. Run `bash "$SHIP_LIB/sync.sh" --force` from the main repo root. This bypasses freshness only; preserve divergence protection. On failure, show the error and write no rows. Never add `--override-divergence` automatically.
3. Reserve IDs with `bash "$SHIP_LIB/id-gen.sh" roadmap --reserve` in intended reading order, persisting each ID into the rows record before insertion. Resolve prerequisites to actual R-IDs, e.g. 「接在 R-031 之後做」. Do not guess IDs or depend on an unselected/unallocated ID.
4. Make each description link to `Reports/<stem>.ai.md#c<N>`, and its human summary link to `Reports/<stem>.html#c<N>`. Invoke the existing insertion helper with separate arguments:

   ```text
   bash <SHIP_LIB>/roadmap-insert.sh <vault ROADMAP.md> <reserved R-ID> <description>
     --next --summary <human summary> --done-when <row-specific acceptance>
   ```

   The helper prepends to Next: insert prepared rows in reverse reading order, so prerequisites appear first in the final Roadmap. Use top-level R-NNN rows, not epic children. Existing helpers interpret backslash escapes in some fields; keep human-readable fields single-line without literal backslash escape sequences, and put code snippets only in the linked AI report.
5. Mark each successful insertion in the rows record. Read the resulting rows back and verify IDs, order, report links and acceptance text. On partial failure, report exactly which rows landed. On retry, reconcile the saved IDs against the Roadmap instead of reserving and inserting the entire batch again. Do not treat reserved-but-unwritten IDs as queued work.
6. Run `bash "$SHIP_LIB/sync.sh" --force` again to refresh the mirror. If this fails after insertion, report that the vault rows exist and the mirror is pending; do not reinsert them.

These are the only target-repo writes in this workflow: ship's normal mirror/freshness/reservation artifacts after selection. The website implementation stays for `/ship-next R-NNN`.

## Rejections and continuation

Record only durable rejection reasons next to the reports. On future scans, read the prior report, rows record, rejection notes and current Roadmap; recognize already queued/completed work before proposing new rows. No selection or no remaining worthwhile candidate is a valid report-only outcome.
