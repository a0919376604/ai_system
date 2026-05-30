---
description: "[deprecated] use /obsidian-research instead — to be removed in next minor release"
argument-hint: <topic>
category: research
triggers_en: ["research this", "look up", "find info on", "web research"]
---

Use the obsidian-second-brain skill. Execute `/research $ARGUMENTS`:

**Deprecation notice:** `/research` is renamed to `/obsidian-research`. The old name still works for now but will be removed in the next minor release.

**Old grammar:** `/research <topic> [--project=<name>] [--academic]`
**New grammar:** `/obsidian-research <repo> <topic> [--academic]`

When invoked, this stub:

1. Prints to the user (visible in chat):
   ```
   WARNING: /research is renamed to /obsidian-research. Use:
       /obsidian-research <repo> <topic> [--academic]
     (where <repo> is "global" for cross-project research, or a project name like "langlive-line-oa")
   ```

2. Translates the legacy invocation to the new grammar:
   - If `--project=<name>` flag is present, use `<name>` as `<repo>`.
   - Otherwise, use `global` as `<repo>`.
   - Forward the remaining args (the topic + `--academic` if present) to `/obsidian-research`.

3. Continues execution using the new command's body (see `commands/obsidian-research.md`).

This stub is removed in the next minor release. After that, only `/obsidian-research` is recognized.
