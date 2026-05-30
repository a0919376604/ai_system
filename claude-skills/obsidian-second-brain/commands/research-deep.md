---
description: "[deprecated] use /obsidian-research-deep instead — to be removed in next minor release"
argument-hint: <topic>
category: research
triggers_en: ["deep research", "thorough research", "vault-first research"]
---

Use the obsidian-second-brain skill. Execute `/research-deep $ARGUMENTS`:

**Deprecation notice:** `/research-deep` is renamed to `/obsidian-research-deep`. The old name still works for now but will be removed in the next minor release.

**Old grammar:** `/research-deep <topic> [--project=<name>]`
**New grammar:** `/obsidian-research-deep <repo> <topic>`

When invoked, this stub:

1. Prints to the user:
   ```
   WARNING: /research-deep is renamed to /obsidian-research-deep. Use:
       /obsidian-research-deep <repo> <topic>
     (where <repo> is "global" for cross-project research, or a project name)
   ```

2. Translates legacy invocation to new grammar (same logic as /research stub: `--project=<name>` -> `<name>` as `<repo>`; otherwise `global`).

3. Continues execution using `commands/obsidian-research-deep.md`'s body.

Removed in next minor release.
