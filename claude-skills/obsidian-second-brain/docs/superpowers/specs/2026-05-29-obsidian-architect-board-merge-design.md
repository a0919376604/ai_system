# `/obsidian-architect` + Board Refresh Merge Design

**Status:** Draft — ready for review
**Date:** 2026-05-29
**Author:** brainstormed with user (Eugeniu)
**Related:**
- v4.3 `/obsidian-architect` (current heavy LLM synthesis flow)
- `commands/obsidian-board.md` `--refresh` mode (existing fast deterministic refresh)
- `scripts/cron/trigger-board-refresh.sh` (existing cron path; **must keep working unchanged**)

---

## Goal

Make `/obsidian-architect <repo>` automatically refresh `Projects/<P>/board.md` as its final phase (Phase 7), so a single command call updates both Architecture/* notes AND board progress. Extract the existing `--refresh` logic from `commands/obsidian-board.md` into a shared `scripts/board/refresh.py` helper that both architect and `/obsidian-board --refresh` (cron) call. No external behavior change for the cron path.

## Why

**Driving pain:** After a code change session, the user wants ONE command that updates everything for that project. Today they have to run:
1. `/obsidian-architect <repo>` (30-90 min, LLM-heavy) → Architecture/* notes
2. `/obsidian-board <repo> --refresh` (1-2 min, deterministic) → board.md

Both scan the same git log and codebase. Two commits to remember, two activity log entries, two `last-*` timestamps drift. Easy to forget step 2 and end up with stale board.

**Why merge as final phase (not full unification):**
- Cron job runs `/obsidian-board --refresh` daily — that path is fast/cheap and shouldn't become a 30-90 min architect invocation
- Board-refresh is mostly deterministic (git scan + bucket clustering + section preserve); doesn't need LLM
- Folding board-refresh into architect adds ~1-2 min — negligible vs architect's existing total

**Cleanest split:** shared helper, two callers (architect Phase 7 + obsidian-board --refresh body).

## Non-goals

- NOT changing the cron entry point. `scripts/cron/trigger-board-refresh.sh` continues calling `/obsidian-board --refresh`.
- NOT changing `/obsidian-board` interactive mode (no `--refresh` flag). Stays as-is.
- NOT auto-creating `board.md` when missing. Phase 7 skips with a log line; user must run `/obsidian-project` first to bootstrap.
- NOT promoting Phase 7 to a separate slash command. `/obsidian-board --refresh` stays the standalone entry point for cron.
- NOT changing the board.md schema, frontmatter, or bucket conventions.

## Scope

Three changes:

1. **Extract** `commands/obsidian-board.md` `--refresh` mode's deterministic logic into a new Python module `scripts/board/refresh.py` exposing one function `refresh_board(project_dir, signals=None, full=False) -> RefreshResult`.
2. **Wire** `commands/obsidian-board.md` `--refresh` mode to call `refresh_board(project_dir, signals=None)` (no signals → walk on demand, as today).
3. **Add Phase 7** to `commands/obsidian-architect.md` that calls `refresh_board(project_dir, signals=architect_signals)` reusing already-collected `git_last_touch` + git metadata + a newly-walked `docs/superpowers/{specs,plans}/` list. Failure isolated; logged as warning; doesn't block architect's overall success.

## `refresh_board` API

```python
@dataclass
class RefreshResult:
    status: str                          # "ok" | "skipped" | "error"
    project_slug: str                    # bound project
    board_path: Path                     # Projects/<P>/board.md
    done_count: int                      # ✅ Done items detected
    in_flight_count: int                 # 🔨 In Progress
    backlog_count: int                   # 📋 Backlog
    buckets: list[str]                   # topic bucket names after refresh
    new_items: list[dict]                # commits/specs/plans added since last refresh
    last_refresh_before: str | None      # the previous timestamp (None if first run)
    last_refresh_after: str              # the freshly-written timestamp
    message: str                         # human summary or error explanation


def refresh_board(
    project_dir: Path,
    *,
    signals: dict | None = None,
    full: bool = False,
) -> RefreshResult:
    """Refresh Projects/<P>/board.md.

    `signals` is optional. When None (cron path) the function walks git log +
    spec/plan files itself. When provided (architect path) it reuses caller's
    already-collected signals to avoid re-walking:

      {
          "local_path": Path,                   # repo root
          "git_last_touch": dict[str, str],      # file → YYYY-MM-DD
          "git_log_since_last_refresh": list[GitCommit],
          "spec_files": list[Path],              # docs/superpowers/specs/*.md
          "plan_files": list[Path],              # docs/superpowers/plans/*.md
          "last_refresh_iso": str | None,        # from board.md frontmatter
      }

    When `full=True`, ignore `last_refresh_iso` and rebuild all topic buckets
    from full history.

    Returns RefreshResult. Caller logs / propagates as needed.
    """
```

The function:

1. Reads `Projects/<P>/board.md` frontmatter (current `last-refresh`, totals).
2. If file missing → return `RefreshResult(status="skipped", message="no board.md in <project>")`.
3. Builds the new bucket list following the existing `--refresh` mode's rules from `commands/obsidian-board.md`:
   - Cluster commits into topic buckets (preserve existing bucket names)
   - Classify Done / In Progress / Backlog per commit/branch/spec activity
   - Preserve `## 🔥 This Week` + `## 待辦` / `## 進行中` / `## 已完成` per the existing SYNTHESIZE rule
   - Recompute `## Bucket summary` table
4. Writes `board.md`.
5. Returns `RefreshResult`.

## Architect Phase 7

Inserted in `commands/obsidian-architect.md` after Phase 6 (Hub note + activity log), before final exit.

```text
## Phase 7: Board refresh (auto, opt-out with --no-board-refresh)

Skip if `--no-board-refresh` was passed.

Skip if `Projects/<P>/board.md` does not exist (log: "no board.md — skipping
board refresh, run /obsidian-project <P> to bootstrap").

1. Assemble architect_signals dict from already-collected Phase 1 data:
   - local_path = repo path
   - git_last_touch = scan_report["git_last_touch"]
   - git_log_since_last_refresh: walk `git log --since=<last_refresh_iso>`
     (read last_refresh_iso from board.md frontmatter; if missing, full=True)
   - spec_files: ls docs/superpowers/specs/*.md filtered by mtime since
     last_refresh (or all if last_refresh missing)
   - plan_files: same for docs/superpowers/plans/*.md
   - last_refresh_iso: from board.md frontmatter

2. Call refresh:
   ```python
   from scripts.board.refresh import refresh_board
   try:
       refresh_result = refresh_board(
           project_dir=arch_dir.parent,  # Projects/<P>/
           signals=architect_signals,
           full=False,
       )
   except Exception as e:
       refresh_result = None
       log_warning(f"board refresh failed: {e}; architect itself succeeded")
   ```

3. Combine into single activity log line (replaces architect's standalone log):
   - If refresh_result.status == "ok":
     `**HH:MM** - architect+board | <P> @ commit <sha> - <module-summary> + board (<done> done, <in_flight> in-flight, <backlog> backlog)`
   - If status == "skipped" or error:
     `**HH:MM** - architect | <P> @ commit <sha> - <module-summary> | board: <message>`

4. Architect's overall exit status is unaffected by Phase 7 outcome — architecture/* is the primary deliverable; board refresh failure is non-blocking.
```

### New flag in command body

`--no-board-refresh` — skip Phase 7. Default OFF (board refresh runs by default when board.md exists).

## `/obsidian-board --refresh` body change

Replace the inline body (steps 1-9 of "Refresh mode" in current `commands/obsidian-board.md`) with:

```text
1. Resolve <repo> via scripts.commands.repo_resolver.resolve_repo_arg
   (allow_global=False; abort if state != "project")
2. Call refresh:
   ```python
   from scripts.board.refresh import refresh_board
   result = refresh_board(
       project_dir=resolution.project_dir,
       signals=None,                    # walk on demand
       full=("--full" in flags),
   )
   if result.status == "skipped":
       abort(result.message)
   ```
3. Append activity log line per result.
4. Return a one-line summary to caller (cron uses this for Discord notification).
```

Behavior externally unchanged. Cron path works identically.

## Activity log format

Single combined line when both run successfully (architect Phase 7 wrote both):

```
**14:35** - architect+board | langlive-line-oa @ commit 8af18eb - 5 modules + 2 ai-flows + memory + rag + features + decisions + personas + board (32 done, 5 in-flight, 12 backlog, 8 buckets)
```

When architect runs without board refresh (board.md missing or `--no-board-refresh`):

```
**14:35** - architect | langlive-line-oa @ commit 8af18eb - 5 modules + ... | board: skipped (no board.md)
```

When `/obsidian-board --refresh` runs standalone (cron):

```
**14:35** - board | langlive-line-oa refreshed - 32 done, 5 in-flight, 12 backlog across 8 buckets
```

## File-by-file changes

**New files:**
- `scripts/board/__init__.py` — empty
- `scripts/board/refresh.py` — `refresh_board()` + `RefreshResult` dataclass + helpers (bucket clustering, classification, section preservation, frontmatter write)
- `tests/board/__init__.py` — empty
- `tests/board/test_refresh.py` — unit tests:
  1. `test_refresh_returns_skipped_when_no_board_md` — missing board.md → status="skipped"
  2. `test_refresh_classifies_commits_into_done_in_flight_backlog` — fixture vault + git history → expected counts
  3. `test_refresh_preserves_user_maintained_sections` — `## 🔥 This Week` / `## 待辦` user-edited content preserved
  4. `test_refresh_resynthesizes_synthesis_sections_when_missing` — first run on a board with only topic buckets → synthesis sections added
  5. `test_refresh_full_mode_ignores_last_refresh` — `full=True` walks all history
  6. `test_refresh_with_signals_reuses_caller_data` — when `signals=` provided, no extra git walk needed (mock subprocess to confirm)

**Modified files:**
- `commands/obsidian-board.md` — `--refresh` mode body replaced with `refresh_board(signals=None)` call
- `commands/obsidian-architect.md` — new Phase 7 + `--no-board-refresh` flag in documentation + body
- `SKILL.md` — architect description gains "順手 refresh board" note
- `CHANGELOG.md` — `## [Unreleased]` entry

**Untouched:**
- `scripts/cron/trigger-board-refresh.sh` — still calls `/obsidian-board --refresh`
- `scripts/cron/board-refresh-prompt.txt` — unchanged
- `dist/*` — regenerated by `bash scripts/build.sh`

## Open questions resolved

- **board.md missing — auto-create?** No. Phase 7 skips silently with log line. User runs `/obsidian-project <P>` first to bootstrap.
- **Activity log combined or two lines?** Combined into one line when both ran (architect+board prefix). Two-line fallback only when architect skipped board (board.md missing or `--no-board-refresh`).
- **What if board refresh is FAST enough that we don't need signals reuse?** Still extract — the helper is useful even without signals reuse; it ensures one implementation of bucket clustering logic instead of two.

## Out-of-scope (deferred)

- Caching `last-refresh` to skip Phase 7 when run twice in 5 minutes — YAGNI; let it always run (cheap)
- Auto-creating board.md from a template — separate brainstorm; `/obsidian-project` already does this
- Board refresh diagnostics command (show which commits got bucketed where) — future
- Moving bucket-clustering's LLM-driven naming step into Python — currently the command body asks Claude for bucket names when items don't match; keep as-is

## Tests (TDD coverage required)

- 6 unit tests in `tests/board/test_refresh.py` (listed above)
- 1 integration smoke (manual): run `/obsidian-architect /Users/leric/Desktop/code/langlive-line-oa --no-features --no-ai-flows --no-ai-memory --no-ai-rag` (fast path) and verify board.md last-refresh updates + activity log line is `architect+board`-prefixed

## Success criteria

- [x] Brainstorm + design approved
- [ ] Spec self-review pass
- [ ] User reviews this spec
- [ ] Implementation plan via `writing-plans` skill
- [ ] Implementation lands: `scripts/board/refresh.py` + 6 tests pass; both callers (architect Phase 7 + obsidian-board --refresh) route through helper; cron path unchanged; activity log format matches above
