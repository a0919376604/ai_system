# Ship → Compound Engineering Skill Mapping

| Ship command | Primary delegation | Fallback when ce-* unavailable |
|---|---|---|
| `ship-init` | (none) | n/a |
| `ship-idea` | optional `compound-engineering:ce-ideate` (only on user request) | Skip ideation; just capture |
| `ship-decision` | optional `compound-engineering:ce-doc-review` | Write decision manually |
| `ship-roadmap` | `compound-engineering:ce-strategy` (preferred) or `ce-plan` | Re-rank in conversation, show reasoning |
| `ship-next` | `superpowers:brainstorming` | Required — no fallback |
| `ship-build` | `superpowers:writing-plans` + user-chosen executor | Required for plan generation |
| `ship-compound` | `compound-engineering:ce-compound` + `ce-promote` | Hand-write learning sections |
| `ship-arch` | `obsidian-second-brain:/obsidian-architect` | Tell user to keep obsidian-second-brain skill (kept by design for architect + research-deep only) |
| `ship-research` | `obsidian-second-brain:/obsidian-research-deep` | Same — tell user to keep that skill |

## Detection

Each `ship-*` command, before delegating, should probe whether the target ce-* skill is available:

```
# In Claude prompt logic:
1. Check that compound-engineering:ce-X is in the available skills list
2. If yes → delegate via Skill tool
3. If no → emit a warning ("ce-X not available, proceeding with manual flow")
   and execute the fallback path inline
```

## Interface contract

When delegating, ship-* passes:
- Project name (from airos-binding.sh)
- Relevant input files (already mirror-synced via sync.sh)
- The ship-* command's specific question (e.g. "rank these roadmap items by Impact × Dependency")

The ce-* skill returns its standard output; ship-* takes that output and applies the ship-side housekeeping (frontmatter, log line, commit message).

## Versioning

If a ce-* skill's interface changes (different argument names, different output schema), the ship-* wrapper either:

1. Adapts to the new interface inline, or
2. Pins to a known-good version in `~/.claude/ship-workflow.yml`:
   ```yaml
   ce_skill_versions:
     ce-compound: "1.2"
     ce-strategy: "0.8"
   ```

v1 ships with no version pinning — Claude is expected to adapt at call time.
