---
date: 2026-10-23
type: brainstorm
id: R-004
status: complete
spec: docs/specs/R-004-refactor-around-ship-next.md
---

# R-004 brainstorm — refactor ai_system around ship-next

## Trigger
After R-003 landed, the operator asked to reconcile "the local version and the online
version", saying "現在好亂". They want to refactor the project with **ship-next as its
core** and clear out what is unnecessary. Their concrete pain: **"我先搞不清楚哪些是可以刪掉的
skill"**.

## Recon (2026-10-23, read-only)
Three layers were compared: GitHub (`origin`), the local checkout, and the live
`~/.claude`.

- **The repo plays three roles at once:**
  1. a backup of `~/.claude/skills` (`sync.sh backup` rsyncs everything in with
     `--delete -L`);
  2. the home of the product, `claude-skills/ship-workflow`;
  3. the installer for a new Mac (`sync.sh restore`, plus the devsync bootstrap).
- **The live ship-* commands are symlinks into the main checkout's working tree.**
  What runs is whatever branch that checkout is on, plus its uncommitted edits. It was
  on `ship/ship-brief`, which lacked R-001, so `/ship-land` ran stale.
- **Every project carries its own stale copy of the commands.** `ship-init` copies
  `commands/*.md` into each repo's `.claude/commands/`. 6 repos hold 60 copies, and
  0 of them match the repo. A project-level command is believed to take precedence
  over the user-level one with the same name; this is unverified, but consistent with
  the stale-`/ship-land` symptom in langlive.
- **The repo and the live skills have drifted apart:**
  - 40 skills exist only in the repo. gstack and its family (654 files) were removed
    locally.
  - 18 skills exist only in the live tree and have no backup in the repo.
  - `obsidian-second-brain` differs in 45 files.
  - The repo `CLAUDE.md` is an old copy of the global one, missing 6 sections. Running
    `sync.sh restore` would overwrite the global file with it, would reinstall gstack,
    and would likely replace the `ship-workflow` symlink with a dead copy, because its
    rsync has no `-K`.
- **Small debris:**
  - a dangling `~/.claude/commands/ship-arch.md`;
  - a merged local branch, `ship/spec-mirror-symlink-guard`;
  - `ship/ship-brief`, whose only unique commit is `f2fd23f` (the run-plan REPAIR
    RULE, wanted on main) plus uncommitted ship-brief WIP.
  - `docs/product/ROADMAP.md` is a regenerated vault mirror, not WIP.

## Dependency trace: "what does ship-next use?"
The operator asked to decide by this alone, not by usage history.

- **Required:**
  - `ship-workflow`: ship-next, plus the ship-compound, ship-idea and ship-land it
    calls, and its libs and templates.
  - `run-plan`: executor 3.
  - `code-review-skill`: Phase 6. It is a live-only git clone of
    `awesome-skills/code-review-skill` @ `17267ff` and has no backup.
  - Plugins: superpowers, compound-engineering, ponytail, and understand-anything
    (optional).
- **Not used by ship-next:**
  - gstack and every gstack skill. Mentions of "codex" and "review" in ship-next are
    the codex CLI and plain words.
  - the Obsidian family. `obsidian-second-brain` is used only by `/ship-research`.
  - `update-specification`. It is referenced by the global CLAUDE.md, not by
    ship-next.
  - every live-only skill (langlive-*, edenai, postgres, redis, react…).

## What the operator decided
- "沒錯": the repo becomes ship-workflow + run-plan + code-review-skill and nothing else.
- Other ship-* commands: "都沒在用". Keep only what ship-next calls.
- "devsync 先留著".
- "好" to Claude's calls on the rest (below), and to running this as R-004 through
  `/ship-next` itself.

## Claude's calls the operator accepted
- **Removing from the repo is not uninstalling.** Live skills that other projects use
  stay installed, untouched.
- **ship-workflow keeps** `ship-next`, `ship-compound`, `ship-idea`, `ship-land` and
  `ship-init`. `ship-init` is kept because bootstrapping a new repo needs it.
- **ship-workflow deletes** `ship-propose`, `ship-explain`, `ship-brief`,
  `ship-research`, `ship-decision`, `ship-roadmap`, the dangling `ship-arch` link, and
  everything only those use.
- **ship-brief's WIP** is archived under a tag before it is dropped.
- **`sync.sh` stops mirroring skills.** It keeps backing up the global `CLAUDE.md` and
  the devsync config, keeps the devsync bootstrap, and installs the three skills plus
  the commands as symlinks.
- **The repo `CLAUDE.md` becomes project-only.** The global copy gets its own path.
- **The main checkout stays on `main`.** Work happens in ship-next worktrees. Merged and
  archived branches are deleted.
- **`code-review-skill` is vendored** with its license and source commit.
- **`docs/superpowers/` is kept as design history.**

## Found after the dialogue (in the spec, for the operator to confirm)
- The 60 per-repo command copies (see Recon) are the root cause of "which version am I
  running". `ship-init` must stop copying, and the existing copies must go.
