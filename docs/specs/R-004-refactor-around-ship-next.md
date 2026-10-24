---
date: 2026-10-23
updated: 2026-10-23
type: spec
id: R-004
status: draft
tags: [ship-workflow, repo-structure, install, sync, cleanup]
ai-first: true
brainstorm: docs/brainstorms/R-004-refactor-around-ship-next.md
related-specs:
  - docs/specs/R-001-add-ship-land-defer-writes.md
  - docs/specs/R-003-add-security-review-gate.md
supersedes: null
---

## For future Claude
> ai_system used to be three things at once:
> - a mirror of the operator's whole `~/.claude/skills`;
> - the home of ship-workflow;
> - a new-Mac installer.
>
> The mirror drifted. 40 skills were in the repo but no longer installed, 18 were
> installed but not in the repo. Its `restore` would have overwritten the newer global
> `CLAUDE.md` and reinstalled gstack. Worse, two mechanisms made "which ship-next am I
> running" unanswerable:
> - the live commands are symlinks into whatever branch the main checkout happens to be
>   on;
> - `ship-init` copied the commands into every project, where 60 copies went stale.
>
> After R-004 the repo holds **ship-workflow, run-plan and code-review-skill and nothing
> else**. ship-workflow keeps only ship-next and the commands ship-next calls.
> `sync.sh` installs those three skills as symlinks, and projects carry no copies.

## §1 Problem
- The operator cannot tell which skills are safe to delete. The repo mirrors 55 skill
  directories; ship-next needs 3 of them.
- **Live version ≠ main.**
  - `~/.claude/commands/ship-*.md` and `~/.claude/skills/ship-workflow` are symlinks
    into the main checkout's working tree.
  - When that checkout sits on a feature branch (it sat on `ship/ship-brief`, which
    lacked R-001), every session on the machine runs that branch, uncommitted edits
    included.
- **Per-project copies.** `ship-init` (`commands/ship-init.md:66`, and again on
  `--upgrade`) copies `commands/*.md` into `<repo>/.claude/commands/`.
  - On 2026-10-23, 6 repos held 60 copies, and none matched the repo.
  - A project-level command is believed to take precedence over the user-level command
    of the same name (unverified; it matches langlive running a stale `/ship-land`).
- **`sync.sh restore` is unsafe:**
  - It rsyncs the whole repo mirror over `~/.claude/skills`. That would reinstall the
    40 removed skills (gstack has 1107 files that differ) and, with no `-K`, would
    likely replace the `ship-workflow` symlink with a copy.
  - It copies the repo `CLAUDE.md`, which is 6 sections behind, over
    `~/.claude/CLAUDE.md`.

## §2 Goals, non-goals, anti-goals
**Goals**
- G1. `claude-skills/` contains exactly `ship-workflow`, `run-plan` and
  `code-review-skill`.
- G2. `claude-skills/ship-workflow/commands/` contains exactly `ship-next`,
  `ship-compound`, `ship-idea`, `ship-land` and `ship-init`.
- G3. One command, `./sync.sh restore`, makes the live `~/.claude` run this checkout:
  - three skill symlinks;
  - five command symlinks;
  - no dangling ship-* links.

  It is idempotent and deletes no real file.
- G4. No project needs a copy of a ship-* command.
  - `ship-init` stops copying.
  - `ship-init --upgrade` removes existing copies.
- G5. ship-next warns when the checkout behind the live skills is not on `main` or has
  uncommitted changes.
- G6. Nothing of value is lost:
  - the run-plan REPAIR RULE (`f2fd23f`) reaches `main`;
  - ship-brief's WIP is archived under a tag;
  - the global `CLAUDE.md` and the devsync config keep a backup in the repo.

**Non-goals**
- Uninstalling anything from `~/.claude/skills`. Skills that other projects use, and the
  six gstack leftovers that are still installed, stay exactly as they are; they simply
  stop being mirrored.
- Changing devsync, `devsync/`, or its bootstrap (the operator: "devsync 先留著").
- Changing ship-next's behaviour beyond:
  - removing references to deleted commands;
  - removing the dead proposal/explain checks;
  - adding the G5 warning.
- Rewriting `docs/superpowers/`. It is kept as design history.
- The R-003 follow-ups (step-4 awk byte matching, backticks into `/ship-idea`, and so on).

**Anti-goals** (failure even if it "works")
- `restore` deleting a real directory or file in `~/.claude`.
- A window in which a project has neither its copy nor a working user-level command.
  The user-level symlinks must be correct before any copy is removed.
- Losing ship-brief's uncommitted WIP, or the REPAIR RULE.

## §3 Design

### 3.1 Repo layout after R-004
```
CLAUDE.md            project rules for ai_system only (3.6)
CONTEXT.md, README.md
sync.sh              backup / restore / status (3.3)
config/claude/CLAUDE.md   backup of ~/.claude/CLAUDE.md (new path)
devsync/             unchanged
claude-skills/
  ship-workflow/     commands: ship-next, ship-compound, ship-idea, ship-land, ship-init
  run-plan/          including the REPAIR RULE from f2fd23f
  code-review-skill/ vendored (3.5)
docs/                unchanged, apart from this item's files
```

### 3.2 Removed
- **`claude-skills/`** — all 53 directories other than `ship-workflow` and `run-plan`:
  - the gstack family: `gstack`, `autoplan`, `benchmark`, `benchmark-models`, `browse`,
    `canary`, `careful`, `connect-chrome`, `cso`, `defuddle`, `design-*`,
    `devex-review`, `freeze`, `gstack-upgrade`, `guard`, `health`, `land-and-deploy`,
    `landing-report`, `learn`, `make-pdf`, `office-hours`, `open-gstack-browser`,
    `pair-agent`, `plan-*`, `qa`, `qa-only`, `retro`, `scrape`, `setup-*`, `ship`,
    `skillify`, `unfreeze`;
  - `codex`, `context-restore`, `context-save`, `document-release`, `investigate`,
    `review`;
  - `obsidian-bases`, `obsidian-cli`, `obsidian-markdown`, `obsidian-second-brain`,
    `json-canvas`, `update-specification`.

  The builder lists the directory afterwards to confirm exactly three remain.
- **ship-workflow commands:** `ship-propose`, `ship-explain`, `ship-research`,
  `ship-decision`, `ship-roadmap`. `ship-brief` exists only as uncommitted WIP; see §5.
- **Files used only by those commands:**
  - `lib/propose-helpers.sh` and `tests/test_propose-helpers.bats`;
  - `templates/obsidian/PROPOSAL.md`, `templates/obsidian/ROADMAP-NOTE.md`;
  - `templates/repo/DECISION.md`.

  Rule for anything not listed here: delete a file only when every consumer is a
  deleted command. Keep anything that a kept command, a kept lib or a kept test uses.
  `lib/roadmap-insert.sh` stays, because ship-next `--adhoc` uses it. `lib/sync.sh`
  stays unchanged, even though it still mirrors `Proposals/` and `Roadmap-Notes/`.
- **References in kept files:**
  - **ship-next:**
    - delete the Phase 3 step 1 proposal check;
    - delete the step 4.5 `↳ explain` / proposal warnings;
    - in the step 4.5 refusal and the slug note, replace `/ship-roadmap` and
      `/ship-explain` with plain instructions such as "edit ROADMAP.md";
    - make the Phase 6 step 1 install hint say `./sync.sh restore` in ai_system, with
      no `git clone`.
  - **ship-idea, ship-init, `SKILL.md`, `README.md`:** list the five commands and
    nothing else. Drop the stale `devsync push` install line.
- **The old `CLAUDE.md` sync entry.** The `SYNC_FILES` pairing of `~/.claude/CLAUDE.md`
  with repo-root `CLAUDE.md` is removed; 3.3 replaces it.

### 3.3 `sync.sh`
The skills rsync, in both directions, is removed.
- **`backup [--dry-run]`** copies two files into the repo and nothing else (`--dry-run`
  only names them; any other option exits 2):
  - `~/.claude/CLAUDE.md` → `config/claude/CLAUDE.md`
  - `~/.config/devsync/config.toml` → `devsync/config.toml`
- **`restore [--yes] [--dry-run]`** first checks where it runs (review attempt 1). From
  a linked worktree it refuses (exit 2) and links nothing — links into a ship-next
  worktree dangle machine-wide once Phase 9 removes it. From a checkout off `main` it
  warns and continues. Then, in order:
  1. **Links.** For each of `ship-workflow`, `run-plan` and `code-review-skill`, it
     makes `~/.claude/skills/<name>` a symlink to `<this checkout>/claude-skills/<name>`.
     For each of the five commands, it makes `~/.claude/commands/<cmd>.md` a symlink to
     `~/.claude/skills/ship-workflow/commands/<cmd>.md`, matching today's form.
     - An existing correct link is left alone.
     - A wrong link is replaced.
     - **A real file or directory in the way is moved to
       `~/.claude/.ai_system-displaced/<name>-<UTC timestamp>`, never deleted.** This
       applies to today's `run-plan` copy and the `code-review-skill` clone.
  2. **Dangling links.** It removes each `~/.claude/commands/ship-*.md` that is a
     symlink resolving into ship-workflow's `commands/` and whose target does not
     exist — except the five kept commands, whose links step 1 owns (they only dangle
     until the skill link is fixed, and a dry run must not plan to remove them). That covers `ship-arch` and the five deleted commands. It touches no other
     entry.
  3. **Config files.** It restores the two config files, repo → live, only when they
     differ. It shows the diff (saying how many lines it cut) and asks first; `--yes`
     skips the prompt. The live file it replaces is moved under `.ai_system-displaced/`
     first, so edits the last backup missed are never lost.
  4. **devsync.** It runs the devsync bootstrap exactly as today.
  - `--dry-run` prints what each step would do and changes nothing.
  - A second run makes no change.
- **`status`** prints, for each link, `ok` / `target missing` / `missing` /
  `wrong target` / `blocked by a real file`, and for each config file `same` / `differs`. It exits 1 if any link is not
  `ok`.
- Tests must be able to run it with `HOME` pointed at a scratch directory and the devsync
  bootstrap skipped. The mechanism is the builder's choice: an env var or a flag.

### 3.4 Per-project command copies
- `ship-init` no longer copies commands. The user-level symlinks serve every repo.
  Steps and text that mention copying, or the "9 ship-*.md files" check, are removed.
- **Removal lives in a standalone lib script.** It is `remove_command_copies
  <repo-path>`; the file name is the builder's choice.
  - It removes every `.claude/commands/<name>.md` whose `<name>` is one of the 13 current
    or former ship-workflow commands: `ship-next`, `ship-compound`, `ship-idea`,
    `ship-land`, `ship-init`, `ship-propose`, `ship-explain`, `ship-brief`,
    `ship-research`, `ship-decision`, `ship-roadmap`, `ship-arch`, `ship-build`.
  - It leaves every other file alone.
  - A **tracked** copy is `git rm`'d. The removal is staged, never committed: the operator
    commits, or opens an MR in mr-mode repos.
  - An **untracked or gitignored** copy is deleted with plain `rm`. 3 of the 6 repos hold
    their copies this way.
  - A tracked copy **with local edits** is left in place and reported, so no edit is
    lost.
  - It works on any checkout path, a linked worktree included, and does not use
    `cwd-guard.sh`.
  - It refuses, and removes nothing, unless `~/.claude/commands/ship-next.md` resolves
    to an existing file. A repo is never left with no working command (anti-goal 2).
  - It also refuses when the repo's `.claude/commands` is `~/.claude/commands` itself —
    a session started in `~` — because those `ship-*.md` are the installed links.
- **`ship-init --upgrade`** becomes a thin wrapper that calls it on the current repo.
- **Rollout step 5 calls the script directly from ai_system**, not through each repo's
  `/ship-init`. Every one of those repos holds an old `ship-init.md` copy, and its
  `--upgrade` re-copies the commands. If project commands do shadow user commands, that
  old copy is what would run.

### 3.5 `code-review-skill`
- **Vendored** from `https://github.com/awesome-skills/code-review-skill` @ `17267ff`,
  the clone in `~/.claude/skills/code-review-skill`. Its files are copied without `.git`.
- Its `LICENSE` is kept. A one-line `VENDORED.md` names the upstream URL and commit.
- No local edits.

### 3.6 `CLAUDE.md` (repo root)
- **Becomes rules for this repo only:**
  - this repo is ship-workflow's home;
  - the main checkout stays on `main`, and work happens in `/ship-next` worktrees;
  - how to run tests (`cd claude-skills/ship-workflow && bats tests/`);
  - `./sync.sh restore` after a pull that changes `sync.sh` or the set of top-level
    `claude-skills/` directories;
  - `./sync.sh backup` after editing `~/.claude/CLAUDE.md`.
- **Removed:**
  - the sections copied from the global file;
  - the old "after every pull run `./sync.sh restore`" rule.
- **New global backup.** `config/claude/CLAUDE.md` is created from the current
  `~/.claude/CLAUDE.md`, the newer one with all its sections, as part of this item.
- **Visibility (operator decision, 2026-10-24).** `github.com/a0919376604/ai_system` is
  public, and the global file names langlive's VPN gateway (`61.216.4.193`), its EKS
  context names and its bastion. The operator accepted publishing it as is: "反正隨時可以切
  private". `backup` is therefore a plain copy, with no filtering.

### 3.7 Live-checkout warning (G5)
- **New lib function.** `live_checkout_warning` resolves
  `~/.claude/skills/ship-workflow` to its git checkout. It prints one warning line:
  - when that checkout's branch is not `main`;
  - or when the checkout has uncommitted changes to tracked files.
- **Silent otherwise.** It is also silent when the path is not a symlink into a git
  checkout, and it never fails.
- **Where it runs.** ship-next Phase 1 calls it right after argument parsing, and also
  in `--auto:yes`. It only warns and never blocks.
- **The builder's choice:** which lib file holds it, and the exact wording.

### 3.8 `airos-binding.sh` project name inside a worktree
- **Found during this ship.** `PROJECT_NAME` is `basename "$(pwd)"`, so inside a
  ship-next worktree the "project" is the worktree directory (`R-004-refactor-…`).
- **The cost.** Phase 3.5 then mirrored R-001's and R-003's specs into two bogus vault
  folders, `10 Projects/R-00N-…/Specs/`. Claude has moved them, by hand, to
  `10 Projects/ai_system/Specs/`.
- **Fix.** At the root of a linked worktree, derive the name from the main checkout:
  `git rev-parse --path-format=absolute --git-common-dir` → its parent directory →
  `basename`.
  - Everywhere else, the name stays `basename "$(pwd)"`, as before: the main checkout,
    a subdirectory, and a plain directory nested inside some checkout.
  - The narrowing was found while building. The suite's fixtures are non-git
    directories under `tests/.tmp/`, often inside a ship-next worktree. "Use the main
    checkout whenever inside git" gave every one of them the enclosing checkout's name.
  - `PROJECT_NAME_OVERRIDE` keeps winning.
  - The check is also a subcommand, `airos-binding.sh in_linked_worktree`. `lib/sync.sh`
    (the vault → `docs/product/` mirror) exits 0 at a linked worktree's root: once the
    name was right it started writing vault files over a worktree's tracked
    `docs/product/`, and Phase 9's `git worktree remove` refused (review attempt 1).

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sync.sh restore` | `./sync.sh restore [--yes] [--dry-run]` | Refuses (exit 2) from a linked worktree; warns off `main`. Afterwards the 3 skill links and 5 command links point at this checkout. A replaced live config file is moved under `~/.claude/.ai_system-displaced/` first. A real file or directory in the way is moved under `~/.claude/.ai_system-displaced/`, never deleted. Dangling `ship-*.md` links into ship-workflow are removed; no other `~/.claude` entry changes. Config files are restored only on confirm or `--yes`. `--dry-run` changes nothing. A second run changes nothing. |
| `sync.sh backup` | `./sync.sh backup [--dry-run]` | `--dry-run` writes nothing; an unknown option exits 2. Otherwise copies `~/.claude/CLAUDE.md` → `config/claude/CLAUDE.md` and the devsync config → `devsync/config.toml`; writes nothing else. |
| `sync.sh status` | `./sync.sh status` | One line per link and config file with its state; a correct link whose target is gone is `target missing`. Exit 1 when any link is not `ok`. |
| `ship-init` | `/ship-init`, `/ship-init --upgrade` | Init writes no `.claude/commands/ship-*.md`. `--upgrade` calls `remove_command_copies` on the current repo. |
| `remove_command_copies` | `remove_command_copies <repo-path>` | Removes only the 13 names in 3.4: tracked → `git rm`, staged and not committed; untracked or ignored → `rm`; a tracked copy with local edits → kept and reported. Other files are untouched. Refuses and removes nothing when the user-level `ship-next.md` does not resolve. Works in a linked worktree. |
| `live_checkout_warning` | shell function | One warning line when the checkout behind `~/.claude/skills/ship-workflow` is off `main` or dirty; nothing otherwise; exit 0 always. |
| `airos-binding.sh project_name` | CLI | At a linked worktree's root: the main checkout's directory name. Anywhere else, including a plain directory nested inside a worktree: `basename "$(pwd)"`. `PROJECT_NAME_OVERRIDE` wins. |
| repo contents | the tree | `claude-skills/` holds exactly `ship-workflow`, `run-plan`, `code-review-skill`. `commands/` holds exactly the five kept commands. |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | the R-004 tree | `ls claude-skills` / `ls claude-skills/ship-workflow/commands` | exactly 3 dirs / exactly the 5 kept `.md` files |
| AC-2 | a scratch HOME with a real `skills/run-plan` dir, no `code-review-skill`, a dangling `commands/ship-arch.md` link and an unrelated `skills/other` dir | `sync.sh restore --yes` (devsync skipped) | 3 skill links and 5 command links point into the checkout; the real `run-plan` dir now sits under `.ai_system-displaced/`; `ship-arch.md` is gone; `skills/other` is untouched |
| AC-3 | AC-2's result | `restore --yes` again | no file changes (same listing, same link targets, nothing new displaced) |
| AC-4 | AC-2's starting state | `restore --dry-run` | no file changes; the output names each planned action |
| AC-5 | scratch HOME with `CLAUDE.md` and devsync config | `sync.sh backup` | `config/claude/CLAUDE.md` and `devsync/config.toml` updated; nothing under `claude-skills/` changes |
| AC-6 | AC-2's result / a HOME missing one link | `sync.sh status` | exit 0 / exit 1 and a `missing` line naming it |
| AC-7 | a scratch repo whose `.claude/commands/` holds tracked `ship-next.md` and `ship-propose.md`, a gitignored `ship-build.md`, and a tracked `my-own.md`; the user-level `ship-next.md` resolves | `remove_command_copies <repo>` | the two tracked copies are `git rm`'d and staged, with no commit; `ship-build.md` is gone; `my-own.md` stays |
| AC-8 | AC-7 with no user-level `ship-next.md` | `remove_command_copies <repo>` | refuses, removes nothing |
| AC-8b | AC-7's repo, as a linked worktree | `remove_command_copies <worktree>` | same result as AC-7 |
| AC-9 | a fresh scratch repo | `ship-init` (block-executed) | no `.claude/commands/ship-*.md` exists |
| AC-10 | `~/.claude/skills/ship-workflow` → a checkout on branch `x` / on `main` with a modified tracked file / on clean `main` | `live_checkout_warning` | a warning naming `x` / a warning naming uncommitted changes / no output; exit 0 in all three |
| AC-11 | the R-004 tree | grep the kept commands, `SKILL.md`, `README.md` | no `/ship-propose`, `/ship-explain`, `/ship-research`, `/ship-decision`, `/ship-roadmap`, `/ship-brief`, `devsync push` |
| AC-12 | the R-004 tree | `claude-skills/run-plan/SKILL.md` | contains the REPAIR RULE text from `f2fd23f` |
| AC-13 | the R-004 tree | inspect `claude-skills/code-review-skill/` | `SKILL.md`, `LICENSE` and `VENDORED.md` (upstream URL + `17267ff`) present; no `.git` |
| AC-16 | a linked worktree of an ai_system checkout / a checkout on `feature-x` | `sync.sh restore --yes` | exit 2, nothing linked / a warning naming `feature-x`, links made |
| AC-17 | a live `~/.claude/CLAUDE.md` that differs from the repo copy | `sync.sh restore --yes` | the live file now equals the repo copy; its old content is under `.ai_system-displaced/CLAUDE.md-*` |
| AC-18 | `HOME` as the repo | `remove_command_copies "$HOME"` | refuses; the installed links stay |
| AC-19 | a worktree whose tracked `docs/product/ROADMAP.md` differs from the vault's | `lib/sync.sh --force` at the worktree root | the file is unchanged; the worktree stays clean |
| AC-15 | a repo `proj` and a linked worktree of it at `…/proj-worktrees/R-9-x` / a plain dir `fixture/my-repo` inside a linked worktree | `airos-binding.sh project_name` | `proj` at the worktree root / `my-repo` |
| AC-14 | the full ship-workflow suite | `bats tests/` | passes, apart from the known linked-worktree `cwd-guard` failure |

## §5 Rollout (in this order)
1. **Before Phase 7: archive ship-brief's WIP.** The operator's main checkout is on
   `ship/ship-brief`, with 3 untracked ship-brief files and 4 modified files.
   - Commit them on a throwaway branch.
   - Tag that commit `archive/ship-brief-wip` and push the tag.
   - Delete the throwaway branch, then switch the main checkout to `main`.

   Phase 7's `git checkout main` cannot run otherwise. `docs/product/ROADMAP.md` is a
   regenerated vault mirror, not WIP; it is left alone.
2. **Land R-004 on `main`** through ship-next, and push.
3. **Install.** In the main checkout, on `main`, run `./sync.sh restore`.
   - It displaces the real `run-plan` and `code-review-skill` directories and links all
     three skills.
   - Then run `./sync.sh status`; it must exit 0.
4. **Branches.** Delete local `ship/ship-brief` and `ship/spec-mirror-symlink-guard`,
   and remote `origin/ship/ship-brief`. The tag keeps the WIP, and `f2fd23f` is on
   `main` by then.
5. **Per-project copies.** Claude runs `remove_command_copies` from ai_system on each
   repo. As of 2026-10-23:
   - **Untracked copies** (plain `rm`, nothing to commit): `ai-eden-service`,
     `claudecode-discord`, `langlive-line-oa`.
   - **Tracked copies** (staged `git rm`; the operator commits): `lang-anchor-recommendation`,
     `lang30s-viewer` and its worktree `lang30s-viewer-wt-1`.
     - The two `lang30s-viewer` checkouts each hold the same 10 files, added by the
       operator on 2026-07-21 (`chore: initialize ship-workflow`).
     - shane.lin also commits to that repo, but the copies cannot be what he runs.
       `ship-next.md` alone reads `~/.claude/skills/ship-workflow/lib/…` 25 times, so
       without ship-workflow installed they fail anyway.
     - The operator approved including them (2026-10-24).

## §8 Known risks
- **R1 Precedence assumption.** That project-level commands shadow user-level ones is
  unverified. For one symptom the evidence points the other way: langlive has no
  `ship-land.md` copy, so its stale `/ship-land` came from the live checkout sitting on
  an old branch (§1), not from a copy. Removing the copies is right either way, since
  they are 60 stale files that may shadow the real ones. The check, after step 5:
  `/ship-next` in langlive shows the R-003 security step (Phase 6 step 1.5).
- **R2 Live skills during the ship.** Until rollout step 3,
  `~/.claude/skills/ship-workflow` still points at the main checkout. After step 1 that
  checkout is on `main`, without R-004. Sessions run main's ship-workflow, which is
  correct.
- **R3 Displaced directories.** The `.ai_system-displaced/` copies are never cleaned up
  automatically. The operator deletes them once satisfied.
- **R4 Mirror loss.** Skills that exist only in the live tree (langlive-*, edenai, …)
  had no repo backup before R-004 and still have none. This is accepted: they are not
  ship-next's, and the operator chose a repo for ship-next only.
