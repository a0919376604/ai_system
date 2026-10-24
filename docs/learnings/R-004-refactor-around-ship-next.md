---
date: 2026-10-24
updated: 2026-10-24
type: learning
id: R-004
tags: [learning, ai_system, ship-workflow, repo-structure, install, sync]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-004
shipped: true
shipped-date: 2026-10-24
---

## For future Claude
> R-004 made ai_system ship-workflow's home. `claude-skills/` now holds exactly
> ship-workflow, run-plan and code-review-skill, and ship-workflow keeps the five
> commands ship-next uses.
>
> The trigger was the operator asking "which skills can I delete?". The real problem
> turned out to be that **"which ship-next am I running" had three answers**:
> - the live symlinks resolve into whatever branch the main checkout is on;
> - every project held its own stale copy of the commands (60 copies, none current);
> - the repo kept a backup mirror of `~/.claude/skills` that had drifted both ways.
>
> If something looks stale, check those three before debugging the code.

## What Shipped
- **Three skills, five commands, links.** `./sync.sh restore` links the skills and
  the commands into `~/.claude`.
  - A real file or directory in the way is moved to `~/.claude/.ai_system-displaced/`,
    never deleted. That includes a replaced live config file.
  - Running it twice changes nothing.
  - It refuses in a linked worktree and warns when the checkout is off `main`.
- **`backup` / `status`.**
  - `backup` copies only the global `CLAUDE.md` (to `config/claude/CLAUDE.md`) and
    the devsync config.
  - `status` reports each link (including `target missing`) and exits 1 when a link
    is wrong.
- **No per-repo copies.** `ship-init` no longer copies commands.
  - `lib/command-copies.sh` `remove_command_copies <repo>` removes copies of the 13
    current and former command names: tracked ones are `git rm`'d and left staged,
    untracked ones are `rm`'d.
  - It keeps a locally edited copy and reports it.
  - It refuses when the user-level `ship-next` doesn't resolve, or when the repo's
    commands dir *is* `~/.claude/commands`.
- **`live_checkout_warning`** (ship-next Phase 1 step 0.5) warns when the checkout
  behind the live skills is off `main` or dirty.
- **`airos-binding` names a linked worktree after its main checkout.** That bug had
  mirrored R-001's and R-003's specs into bogus vault folders, which were moved home.
  `lib/sync.sh` is now a no-op at a worktree root.
- **Repo contents.**
  - 53 skill directories deleted.
  - The 5 unused ship-* commands deleted, along with their files.
  - code-review-skill vendored from upstream `17267ff`.
  - The run-plan REPAIR RULE (`f2fd23f`, stranded on ship/ship-brief) reached main.
  - ship-brief's WIP is under the tag `archive/ship-brief-wip`.

## What Changed From Plan
- The plan ran in one codex round: DONE, 8 commits, zero deviations, the tree identical
  to the prototype.
- Review had one round: 0 blocking, 5 important + 3 nits, all fixed inline after the
  gate, test-first. The security finder found nothing at confidence ≥ 7.
- The builder check caught three things the spec missed:
  - half the repos' copies are gitignored, so `git rm` fails;
  - each repo's own stale `ship-init --upgrade` would re-copy the commands;
  - `ship-build` was another former command.

## Bugs
- **Fixing a long-wrong lookup surfaces its dependants.** Once `airos-binding`
  resolved the real project inside a worktree, `lib/sync.sh` started writing vault
  files over a worktree's tracked `docs/product/`. That dirtied the worktree and made
  Phase 9's `git worktree remove` refuse. The wrong name had been hiding this.
- **Git-based cwd checks and nested fixtures.** The suite's fixtures are plain
  directories under `tests/.tmp/`, often inside a ship-next worktree. "Use git's answer
  whenever inside git" renamed every fixture, so every such check now compares
  `--show-toplevel` with `pwd -P`.
- **`set -euo pipefail` traps in `sync.sh`:**
  - `n=$(diff a b | wc -l)` exits the script, because diff exits 1 when the files
    differ.
  - `(( n > 40 )) && log …` as an if-body's last command made the body fail.

  Both were caught by tests, not by reading.
- **`remove_command_copies "$HOME"`** would have deleted the installed links (a
  session started in `~`). The reviewer reproduced it.

## Reusable Patterns
- **"Delete from the repo" is not "uninstall".** Classify by the dependency trace of
  the core command (the operator's rule: "only what ship-next uses"), not by usage
  history.
- **Never delete in an installer.** Move whatever is in the way into a timestamped
  displaced dir. Make the dry run plan the real run's actions, kept links included.
- **Removal scripts for other repos run from the source repo.** A repo's own stale
  copy of the tool may do the opposite of what you want.

## Technical Debt
- `codex_state_alive: false once the process is gone` can flake on PID reuse in a
  full-suite run (seen once in R-004). It predates R-004.
- `lib/roadmap-insert.sh --explain` and `lib/sync.sh`'s `Proposals/` and
  `Roadmap-Notes/` mirroring now have no consumer.
- `ship-init` step 1 still reads `$1`, which Claude Code substitutes in command files.

## Future Follow-ups
- `codex_verdict` still misreports ship-workflow ships as `infra` (overridden again).
- The R-003 follow-ups still open:
  - step 4's awk `[🟡]` byte matching;
  - backticks in finding text reaching `/ship-idea`'s `git commit -m`;
  - Phase 9's `CODEX_ROUNDS` living in a shell variable.
- ai_system has no `docs/ideas/`, so `/ship-idea` and step 4.5 cannot file follow-ups
  here.
