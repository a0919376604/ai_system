# Escape Hatches

## `--adhoc` for urgent work

```
/ship-next --adhoc "Fix langfuse token leak"
```

What happens:

1. id-gen.sh allocates next R-NNN (same namespace as planned items — no separate ADHOC)
2. roadmap-insert.sh appends a line to AIR-OS ROADMAP.md "🔥 Now":
   ```
   - [ ] **R-018** Fix langfuse token leak · adhoc-inserted=true · status=in-progress
   ```
3. sync.sh mirrors the updated ROADMAP back to repo
4. Continue with normal brainstorm + spec flow

When `/ship-compound` ships R-018:
- The line moves to "✅ Done" section
- The `adhoc-inserted=true` marker is stripped (no longer relevant)
- Dataview queries on `tags: roadmap` can filter on `adhoc-inserted` history if needed
  by reading the Done-section history (markers are NOT preserved post-ship)

## Mid-implementation capture

While `/ship-next` is running:

```
/ship-idea --during-ship-next "Maybe rich menu can use templated variants"
/ship-decision --during-ship-next "Switch to celery-task for retries"
```

Both produce normal IDEA-NNN / D-NNN files but with extra frontmatter:

```yaml
related-roadmap-item: R-018          # the current ship cycle's ID
created-during: ship-next            # the phase
```

This lets `/ship-compound` later sweep up all captures from this ship cycle into the learning.

## Worktree-cwd-block (3 commands)

The following commands refuse to run inside a ship/* worktree because they modify cross-cutting state on main:

- `/ship-roadmap` — modifies ROADMAP.md (canonical)
- `/ship-init` — scaffolds repo + vault state
- `/ship-propose` — writes to Proposals/

If you invoke any of these inside a worktree, you'll see:

```
ERROR: this command cannot run inside a ship/* worktree.
       cd back to the main repo (the parent project) first.
```

This is enforced by `lib/cwd-guard.sh` (called at Step 0 of each command).

## Skipping init

`/ship-init` is idempotent. Re-running:
- Skips existing files
- Re-copies `.claude/commands/ship-*.md` (use `--upgrade` for an explicit refresh)
- Doesn't overwrite AIR-OS strategy files

## Forcing fresh sync

```bash
~/.claude/skills/ship-workflow/lib/sync.sh --force
```

Ignores the freshness window. Use after editing strategy in Obsidian without waiting 60 seconds.
