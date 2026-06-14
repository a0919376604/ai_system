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

## Mid-build capture

While `/ship-build` is running:

```
/ship-idea --during-build "Maybe rich menu can use templated variants"
/ship-decision --during-build "Switch to celery-task for retries"
```

Both produce normal IDEA-NNN / D-NNN files but with extra frontmatter:

```yaml
related-roadmap-item: R-018          # the current build's ID
created-during: build                # the phase
```

This lets `/ship-compound` later sweep up all captures from this build into the learning.

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
