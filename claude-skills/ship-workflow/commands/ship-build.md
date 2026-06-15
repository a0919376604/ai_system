---
name: ship-build
description: Spec → plan via superpowers:writing-plans → user picks executor (subagent / inline / codex)
argument-hint: "[--from-spec <path>]"
discord-visible: true
---

# /ship-build

You are taking a spec to a shipped feature.

## Arguments

- `--from-spec <path>` — use this exact spec path; otherwise pick most recent `docs/specs/R-*.md`

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Stale-snapshot warning.** Check `docs/product/ROADMAP.md`'s git age:
   ```bash
   if [ $(($(date +%s) - $(git log -1 --format=%ct docs/product/ROADMAP.md))) -gt 604800 ]; then
     echo "WARN: docs/product/ROADMAP.md hasn't been refreshed in >7 days. Consider /ship-roadmap first."
   fi
   ```

3. **Resolve spec path.** If `--from-spec` provided, use it. Otherwise, find `docs/specs/R-*.md` modified most recently. Extract `$ID` and `$SLUG` from filename.

4. **Invoke `superpowers:writing-plans`** with the spec. It produces `docs/plans/${ID}-${slug}.md`.

5. **Offer executor choice.** Ask the user:
   ```
   Plan ready at docs/plans/${ID}-${slug}.md. Choose executor:
     1. Subagent-driven (recommended) — fresh subagent per task, review between
     2. Inline executing-plans — sequential in this session, batch with checkpoints
     3. Codex run-plan — hand off to codex exec, runs autonomously in background
   ```

6. **Invoke the chosen sub-skill:**
   - `1` → `superpowers:subagent-driven-development`
   - `2` → `superpowers:executing-plans`
   - `3` → `/run-plan docs/plans/${ID}-${slug}.md` (the gstack skill)

7. **During execution, allow escape hatches:**
   - If user runs `/ship-idea --during-build "X"` → capture as IDEA-NNN with `related-roadmap-item: ${ID}`
   - If user runs `/ship-decision --during-build "Y"` → capture as D-NNN with `affected-roadmap-items: [${ID}]`

8. **After executor finishes**, log + commit (only the plan file — code commits come from sub-skill):
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-build | $ID | exec=$executor_choice | n |" >> docs/learnings/_log.md
   git add docs/plans/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "plan: $ID $description"
   ```

9. **Report:** plan path, executor used, count of commits made by executor, next suggested command: `/ship-compound`.

## Failure modes

- No spec found → ask user to run `/ship-next` first
- writing-plans fails to produce a plan → halt before commit, surface error
- Sub-skill executor fails mid-run → log it in `## Execution log` section of the plan file, surface to user
