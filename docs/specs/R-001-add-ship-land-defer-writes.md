---
date: 2026-10-15
updated: 2026-10-15
type: spec
id: R-001
status: draft
tags: [ship-workflow, merge-mode, mr, ship-land, ship-compound, shared-files]
ai-first: true
brainstorm: docs/brainstorms/R-001-add-ship-land-defer-writes.md
related-specs:
  - docs/superpowers/specs/2026-09-28-ship-next-context-and-test-discipline-design.md
supersedes: null
---

## For future Claude
> In `merge_mode: mr`, every ship wrote four repo-wide files on its review branch:
> `docs/learnings/_log.md` and `docs/tdd-rules.md` (tail appends), `CONTEXT.md`
> (append/refine) and the `docs/product/ROADMAP.md` vault mirror (whole-file). Open
> four MRs, merge one, and the other three conflict — every time.
> The fix gives each file the lightest treatment that removes the shared write:
> `_log.md` rows become `Ship-Log:` commit trailers, tdd rules become per-ship
> fragments, the ROADMAP mirror is no longer committed on review branches, and only
> `CONTEXT.md` is deferred — to `/ship-land`, which folds it onto the base branch in a
> single `[skip ci]` commit after the MR merges. A review branch then touches only
> paths that carry its own R-NNN, so parallel MRs cannot collide.
> `/ship-land` already existed as `commands/ship-land.md` but was never linked into
> `~/.claude/commands/`; this spec rewrites it and installs it.
> **Squash mode keeps its observable behaviour.** Read §2 before widening scope.

## §1 Problem

### 1.1 The incident
2026-10-14, langlive-line-oa: !285–!288 open together. Merging !285 conflicted the
other three on the tails of `_log.md` and `docs/tdd-rules.md`. Three manual union
merges; each later merge re-conflicts whatever is still open.

### 1.2 Every shared write a review branch makes today

| File | Writer(s) on the review branch | Shape |
|---|---|---|
| `docs/learnings/_log.md` | `ship-next` P9 step 3, `ship-compound` step 9, `ship-idea --during-build` (P6) — plus six other commands that may run there | tail append |
| `docs/tdd-rules.md` | `ship-compound` 6b `tdd_rules_append` | tail append |
| `CONTEXT.md` | `ship-compound` step 6 | append or refine an entry |
| `docs/product/ROADMAP.md`, `docs/proposals/` | `ship-compound` step 9 `git add` after `sync.sh --force` | whole-file vault mirror |

`merge=union` is not an option: GitLab and GitHub server-side merges ignore custom
merge drivers.

### 1.3 `/ship-land` is not invocable, and is wrong where it exists
- `commands/ship-land.md` (commit `7cb2ac5`) has no symlink in `~/.claude/commands/`.
- Step 5 appends `_log.md` and commits the ROADMAP mirror to the **local** base
  branch and never pushes, so local base diverges from origin.
- Step 4 uses `git branch -d`, which refuses whenever the local base is behind
  origin — the normal state (langlive's local `main` is 34 behind) — even though
  step 2 just proved the branch merged.
- Step 4 runs `git pull --ff-only` on the operator's checkout, which may be dirty
  (langlive's has a staged `CLAUDE.md`).

## §2 Goals and non-goals

**Goals**
- G1. Two (or more) mr-mode ships open at once; merging any one leaves the others
  conflict-free. (done-when A)
- G2. `/ship-land R-NNN` is installed and, after the MR merges: folds deferred
  `CONTEXT.md` entries onto the base branch, moves the vault ROADMAP row to Done, and
  removes the worktree and branch. It refuses, changing nothing, when the MR has not
  merged. (done-when B)
- G3. Squash mode's observable behaviour is unchanged. (done-when C, as reinterpreted
  in §2.1)
- G4. Nothing deferred is lost. (done-when D, as reinterpreted in §2.1)
- G5. `/ship-land` commits to the base branch only when there is a `CONTEXT.md`
  change to land, and that commit never triggers CI.

**Non-goals**
- Batch landing (`/ship-land` with no argument). One commit per land is accepted.
- IDEA-NNN collisions across parallel branches (§8, R2).
- Changing what `ship-init` copies into a repo's `.claude/commands/`.
- Squash-merged MRs (§8, R1).

### 2.1 Reinterpretations the operator approved (2026-10-15)
- **D, `_log.md`:** an mr-mode ship's log row must reach the base branch's **git
  history** as a `Ship-Log:` trailer, not a line in the file. Writing the file at
  land time would force a commit on every land.
- **C, tdd rules:** new rules are written to `docs/tdd-rules.d/<R-NNN>.md` in **both**
  modes. The rule text every executor receives is identical; only storage moves.
  One code path instead of a mode branch.

## §3 Prior art, and why a per-file mix

| Family | Examples | Maps to |
|---|---|---|
| Fragments compiled later | towncrier, scriv, changesets; GitLab 2018 `changelogs/unreleased/*.yml` | `CONTEXT.md` here |
| Permanent fragments, never compiled | OpenStack reno | tdd rules here |
| No file, derive from git | GitLab's later `Changelog:` commit trailers | `_log.md` here |

GitLab moved from the first family to the third. Applying one family to four files of
different nature was heavier than needed. `CONTEXT.md` alone needs a fold, because
entries are refined in place and the file is read whole.

## §4 Design

### 4.1 Per-file behaviour

| File | mr mode, on a `ship/*` branch | Otherwise (squash mode, or on the base branch) |
|---|---|---|
| `_log.md` | `ship_log` makes one empty commit carrying `Ship-Log: <row>`; file untouched | `ship_log` appends the row to the file (today's behaviour) |
| tdd rules | `tdd_rules_append` writes `docs/tdd-rules.d/<R-NNN>.md` | same |
| ROADMAP / proposals mirror | not staged by `ship-compound` | staged as today |
| `CONTEXT.md` | entries go to `docs/ship-pending/<R-NNN>-context.md` via `context_pending_add`; folded by `/ship-land` | edited directly as today |

Every path a review branch writes now contains its own R-NNN, or is a commit with no
tree change.

### 4.2 `lib/ship-log.sh` (new)

- `ship_log "<row>"` — the single writer of `_log.md` rows.
  - **Defers** when `merge_mode` is `mr` **and** `git branch --show-current` matches
    `ship/*`: `git commit --allow-empty -q -m "log: <cmd> <id>" -m "Ship-Log: <row>"`,
    where `<cmd> <id>` are the row's 2nd and 3rd `|`-fields, trimmed.
  - Otherwise appends `<row>` as one line to `docs/learnings/_log.md` (creating the
    file if absent, as `>>` does today) and does not commit.
  - Exit 2 on an empty row or outside a git repo.
  - No `[skip ci]` on review-branch commits: a skipped pipeline can fail a
    "pipelines must succeed" merge check. Docs-only pushes already match no job.
- `ship_log_ratio_count` — rows in `_log.md` containing `ratio ` plus `Ship-Log`
  trailers reachable from `HEAD` containing `ratio `
  (`git log --format='%(trailers:key=Ship-Log,valueonly)'`).
- Callers: replace each `echo "| … |" >> docs/learnings/_log.md` in `ship-next`,
  `ship-compound`, `ship-idea`, `ship-decision`, `ship-explain` (×2), `ship-research`,
  `ship-roadmap`, `ship-propose` with `ship_log "| … |"`. Their existing
  `git add docs/learnings/_log.md` stays; it is a no-op when nothing changed.

### 4.3 `lib/test-budget.sh`
`tb_shadow_active` counts `ship_log_ratio_count` instead of grepping the file alone.
Without this, a repo that has only ever shipped in mr mode stays in shadow mode
forever and the test budget never blocks.

### 4.4 `lib/tdd-rules.sh`
- `TDD_RULES_DIR=docs/tdd-rules.d`. Rule files = legacy `docs/tdd-rules.md` (if
  present) then `docs/tdd-rules.d/*.md` sorted by name.
- `tdd_rules_append <R-NNN> <text>` writes `- <text> ← <R-NNN>` to
  `docs/tdd-rules.d/<R-NNN>.md` (bullets only, no header). Idempotent across **all**
  rule files. Never writes the legacy file.
- `tdd_rules_count`, `tdd_rules_unsourced`, `tdd_rules_render` read all rule files,
  legacy first. `tdd_rules_over_cap` follows from `tdd_rules_count`.
- `tdd_rules_path` keeps its current meaning (the legacy file or nothing).

### 4.5 `lib/context-md.sh`
- `context_pending_add <R-NNN> "<entry>"` — validates that the first line matches
  `^- \*\*[^*]+\*\* — ` and that every later line is either indented (a continuation)
  or another such entry line, then appends it to
  `docs/ship-pending/<R-NNN>-context.md`. An unindented or blank later line is
  refused (exit 2): `context_pending_apply` would drop it after the queue had been
  reviewed and merged. Touches nothing else.
- `context_pending_apply <R-NNN>` — run at a base-branch checkout root. If the pending
  file is absent: exit 0, no output. Otherwise, for each pending entry in order: if
  `CONTEXT.md` has an entry with the same `**term**`, replace that entry **including
  its continuation lines** (the following lines that begin with whitespace; a blank line
  or the next bullet ends an entry); else append it. Creates `CONTEXT.md` if absent. Deletes
  the pending file. Echoes the number of entries applied. Does not stage or commit.

### 4.6 `lib/ship-land.sh` (new)
- `land_is_merged <branch> <base-ref>` — exit 0 iff
  `git merge-base --is-ancestor <branch> <base-ref>`.
- `land_context <R-NNN> <base>` — never touches the caller's checkout:
  1. `git fetch origin <base>`; add a detached temp worktree at `origin/<base>`.
  2. No `docs/ship-pending/<R-NNN>-context.md` there → remove the temp worktree,
     echo `none`, exit 0.
  3. `context_pending_apply`; stage `CONTEXT.md` and `docs/ship-pending/`; commit
     `context: land <R-NNN> [skip ci]`; `git push origin HEAD:<base>`.
  4. Push rejected → fetch again. If `origin/<base>` moved, it was a lost race:
     discard the temp worktree and redo from step 1 on the fresh tip. The fold is
     deterministic, so a redo cannot conflict. At most 3 attempts, then exit 1. If
     `origin/<base>` did not move (protected branch, auth, network), print git's own
     error and exit 1 at once — retrying cannot help and would hide the cause.
  5. Success → echo `landed <sha>`. The temp worktree is removed on every path that
     returns; an interrupt can leave it registered, and `git worktree prune` clears it.

### 4.7 `commands/ship-compound.md`
- **Step 6, mr mode:** call `context_pending_add` per entry instead of editing
  `CONTEXT.md`; skip the cap check, commit and vault mirror. `/ship-land` does those.
  Refuse (exit 1) unless on a `ship/*` branch (`ship_log_defers`). Squash mode is
  unchanged.
- **Step 9:** resolves `MERGE_MODE` itself — each step runs in its own shell.
- **Step 9, mr mode:** refuse (exit 1) unless on a `ship/*` branch. Stage
  `docs/learnings/${ID}-${slug}.md`, `docs/tdd-rules.d/` and `docs/ship-pending/` only
  — **not** `docs/product/`, `docs/proposals/` or `_log.md`. Write the row with
  `ship_log`, commit, push the current branch. A failed `git add` stops the step.
- **Step 9, squash mode:** the required paths are added in one `git add`; if it fails
  the step stops before committing (as before R-001), instead of committing a partial
  set under a title that claims all of it.
- **Step 9, both modes:** stage `docs/tdd-rules.d/`. Today 6b's appended rule is
  never staged by any step.
- **Step 10, mr mode:** report "row marked in-review — run `/ship-land ${ID}` after
  the MR merges".

### 4.8 `commands/ship-next.md`
- **Every block that reads `$MERGE_MODE` resolves it** (`MERGE_MODE=$(merge_mode)`):
  Phase 7 step 2 and Phase 9 steps 1–3. Each block runs in its own shell; an unset
  mode silently took the squash path. A structural test enforces this across
  ship-next, ship-compound and ship-land.
- **Phase 8:** say where `/ship-compound` runs: squash — the original repo cwd; mr —
  `$WORKTREE`, on the review branch.
- **Phase 9 step 3:** write the row with `ship_log`. In mr mode, in a subshell: refuse
  (exit 1, nothing logged or pushed) if `$WORKTREE` is empty or the branch there is not
  `ship/${ID}-*` (a WORKTREE left over from an earlier ship would push into that
  ship's review) — `cd ""` succeeds silently, and the push would otherwise send the base
  branch to origin — else log and push that branch so the trailer travels with the MR.
  Squash mode keeps `git add` + `git commit -m "log: ship ${ID}"` on `$ORIG_BRANCH`.
- Fix the stale comment above it ("Auto mode picks executor 1…"): auto mode now
  picks codex.

### 4.9 `commands/ship-land.md` (rewrite)
1. **Resolve.** Refuse (exit 2) when run inside a linked worktree — step 5 removes
   the ship's worktree, and git cannot remove the one it is run from. Compare
   `--path-format=absolute` git-dir and common-dir, so a subdirectory of the main
   checkout is not mistaken for a worktree. `ID` from the
   argument; repo root; `BASE` from
   `refs/remotes/origin/HEAD` (fallback `main`); `BRANCH` = local `ship/${ID}-*`.
   No local branch: if the vault ROADMAP row is already Done, report "already landed"
   and exit 0; else error.
2. **Gate.** `git fetch origin --prune`; `land_is_merged "$BRANCH" "origin/$BASE"`.
   On failure: say the MR is open or was closed unmerged (or squash- or
   rebase-merged, §8 R1),
   that nothing changed, and exit 1. The local branch is checked because Phase 7 opens
   MRs with `--remove-source-branch`.
3. **Fold CONTEXT.** Every block that calls the lib sources it (each block runs in its
   own shell). `land_context "$ID" "$BASE"`. Exit 1 → stop; ROADMAP and branch
   untouched. `landed` → mirror `origin/$BASE:CONTEXT.md` to the vault with
   `spec-mirror.sh`; run the cap check and, interactively, prune per `ship-compound`
   step 6.3 as its own reviewed change (an MR in mr mode). Pruning deletes
   vocabulary, so it is never folded into this command's bookkeeping commit.
4. **ROADMAP.** In the vault, move the row from "🔥 Now" to "✅ Done" with
   `· ✅ <date>`, stripping `status=in-review`, `mr=<url>` and `adhoc-inserted=true`.
   Atomic `.tmp` + `mv`. Skip if already Done.
5. **Clean up.** In the worktree, for each mirror path (`docs/product`,
   `docs/proposals`, `docs/roadmap-notes`) separately: `git checkout -- <p>` then
   `git clean -fdq -- <p>`, so neither a sync-modified tracked file nor a newly synced
   untracked one blocks removal — skipped entirely when the lookup resolves to the main
   checkout itself (the ship branch checked out there), so the operator's own untracked
   files are never cleaned; `git worktree remove`; `git branch -D "$BRANCH"`;
   `git push origin --delete "$BRANCH"` (ignore "not found").
   `-D` is safe **because** step 2 proved the tip is in `origin/$BASE`. `-d` would
   compare against the possibly-stale local base and refuse.
6. **Report** the land commit (or "no CONTEXT changes"), the row's new state, and
   what was removed.

No `git pull`, `_log.md` write or ROADMAP-mirror commit on the operator's checkout.

### 4.10 Install
- Create `~/.claude/commands/ship-land.md` → `~/.claude/skills/ship-workflow/commands/ship-land.md`.
- README's install section links **every** `commands/*.md` in one loop, so the next
  new command is not missed the same way.

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `ship_log` | `ship_log "<row>"`, cwd anywhere in the repo or worktree | mr + `ship/*` branch: exactly one new commit, subject `log: <cmd> <id>`, empty tree change, with trailer `Ship-Log: <row>`; anything already staged stays staged and is not in that commit; `_log.md` byte-identical. Else: `<row>` appended as one line; no commit. Exit 2 on empty row. |
| `ship_log_ratio_count` | `ship_log_ratio_count` → integer | count of `ratio ` rows in `_log.md` + `ratio ` Ship-Log trailers reachable from HEAD |
| `tb_shadow_active` | exit 0 = shadow | shadow iff `ship_log_ratio_count` < `TB_SHADOW_SHIPS` |
| `tdd_rules_append` | `tdd_rules_append R-NNN "<rule>"` | rule present exactly once across legacy + fragments, written to `docs/tdd-rules.d/R-NNN.md`; legacy file never modified; exit 2 without an R-NNN or with empty text |
| tdd rule readers | `tdd_rules_count`, `tdd_rules_unsourced`, `tdd_rules_render` | see legacy rules then fragment rules (by filename); render output for a repo with only a legacy file that holds at least one rule is unchanged; a header-only legacy file now renders no "Learned in this repo" heading |
| `context_pending_add` | `context_pending_add R-NNN "<entry>"` | entry appended to `docs/ship-pending/R-NNN-context.md`; nothing else written; exit 2, nothing written, on a malformed first line or a later line that is neither indented nor an entry |
| `context_pending_apply` | `context_pending_apply R-NNN`, cwd = base checkout | every pending entry present in `CONTEXT.md` exactly once (same term replaced with its continuation lines, new term appended); pending file deleted; echoes the number of distinct terms applied; no-op (no output) when absent; no git operations |
| `land_is_merged` | `land_is_merged <branch> <base-ref>` | exit 0 iff branch tip is an ancestor of base-ref |
| `land_context` | `land_context R-NNN <base>` | `none` + no commit when no pending file on `origin/<base>`; else `landed <sha>` where `<sha>` is on `origin/<base>`, message is exactly `context: land R-NNN [skip ci]`, and the pending file is gone there; a push rejected by a concurrent push is redone, up to 3 attempts; any other rejection exits 1 at once with git's error on stderr; the temp worktree is removed on every exit path that returns; caller's checkout and current branch untouched |

## §5 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-A1 | merge_mode mr; two `ship/*` branches off main, each running `ship_log`, `tdd_rules_append`, `context_pending_add` and adding its learning file | branch 1 is merged `--no-ff` into main | `git merge-tree --write-tree main <branch 2>` exits 0 |
| AC-A2 | the same two branches, but writing the old way (tail append to `_log.md` and `docs/tdd-rules.md`) | branch 1 merged | `git merge-tree` reports a conflict — proves AC-A1 can fail |
| AC-B1 | a branch not an ancestor of `origin/main` | `land_is_merged` | exit non-zero |
| AC-B2 | a bare origin whose main has `docs/ship-pending/R-9-context.md` | `land_context R-9 main` | origin/main has a `[skip ci]` commit; `CONTEXT.md` has the entries; pending file gone; caller's checkout unchanged |
| AC-B3 | origin/main has no pending file for R-9 | `land_context R-9 main` | prints `none`; origin/main unchanged |
| AC-B4 | origin/main advances between fetch and push on the first attempt | `land_context` | succeeds on retry; both commits on origin/main |
| AC-B5 | `commands/ship-land.md` | inspected | uses `land_is_merged` and `land_context`; no `_log.md` write; no `git pull`; `~/.claude/commands/ship-land.md` resolves to it |
| AC-B6 | a push rejected while `origin/main` did not move | `land_context` | exit 1 after one attempt, git's error on stderr |
| AC-B7 | mr mode, `$WORKTREE` empty, local-only commits on main | ship-next Phase 9 step 3 block runs (bash and zsh) | exit ≠ 0; origin/main unchanged; base checkout unwritten |
| AC-B8 | a ship worktree with a sync-modified tracked mirror file and an untracked synced proposal | ship-land step 5 block runs | worktree removed, branch deleted |
| AC-C1 | squash mode, or any repo on its base branch | `ship_log "<row>"` | row appended to `_log.md`; no commit created |
| AC-C2 | repo with only a legacy `docs/tdd-rules.md` holding at least one rule | `tdd_rules_render` | output identical to before this change |
| AC-D1 | CONTEXT.md has `**Foo**` with a continuation line; pending has a new `**Foo**` and a new `**Bar**` | `context_pending_apply` | one `**Foo**` (the new text, old continuation gone), `**Bar**` appended, pending file deleted |
| AC-D2 | both AC-A1 branches merged into main | `git log --format='%(trailers:key=Ship-Log,valueonly)' main` | both rows present |
| AC-D3 | a repo with 3 `ratio ` Ship-Log trailers and no `_log.md` | `tb_shadow_active` | exit 1 (shadow over) |

Existing tests that pin the old behaviour and change with it:
`test_ship-land.bats` (`git branch --merged` grep), `test_tdd-rules.bats`
(`tdd_rules_append` writes `docs/tdd-rules.md`). The known pre-existing failure
`test_cwd-guard.bats` "exits 0 when not in a git repo at all" is unrelated (its
scratch dir lives inside the repo) and stays failing.

## §6 Rollout
Lands on `main` of ai_system; live immediately via the `~/.claude/skills/ship-workflow`
symlink. Ships already open in langlive (written the old way) still conflict until
they merge. `/ship-land` on them works: no pending file means no fold.

## §7 Out of scope, noted
- `/ship-next`'s learnings lookup filter is `awk 'length($0) >= 4'`; Claude Code
  substitutes `$0` with the command argument when loading the command, so the filter
  becomes `length(R-001)` and drops every term. Separate one-character fix.

## §8 Known risks
- **R1 Squash-merged MR.** If an MR is merged with GitLab's squash checkbox, the
  branch tip is not an ancestor of base; `/ship-land` refuses. Safe failure: nothing
  is deleted. Its message names this cause. langlive's squash option is `default_off`.
- **R2 IDEA-NNN / D-NNN collisions.** `id-gen.sh idea|decision` scans `docs/ideas/` /
  `docs/decisions/` in the worktree, so parallel branches can mint the same ID (add/add
  conflict) when `/ship-idea` or `/ship-decision` runs during a ship. Not addressed.
- **R3 Stale mirror on base.** In mr mode the committed `docs/product/ROADMAP.md` on
  base is refreshed only by squash-mode ships or manual commits. Tooling is
  unaffected: every command runs `sync.sh` (vault → working tree) first. People
  browsing the forge see an older copy.
- **R4 Two lands of the same R-NNN at once.** The second finds no pending file after
  its redo and prints `none`. Harmless.
