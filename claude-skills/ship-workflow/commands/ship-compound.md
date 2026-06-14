---
name: ship-compound
description: Wrap up R-NNN — write learning, promote patterns to AIR-OS, move ROADMAP item to Done
discord-visible: true
---

# /ship-compound

You are wrapping up a Roadmap item.

## Argument

(none — operates on the most recent plan in `docs/plans/R-*.md`)

## Steps

1. **Sync:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Identify the plan.** Find the most recent `docs/plans/R-*.md`. Extract `$ID` and `$SLUG`.

3. **Gather inputs:**
   - The plan: `docs/plans/${ID}-${slug}.md`
   - All decisions tagged `affected-roadmap-items: ... ${ID} ...`
   - All ideas tagged `related-roadmap-item: ${ID}`
   - Git log from plan's first commit timestamp to HEAD on this branch

4. **Delegate to `compound-engineering:ce-compound`** to draft the learning content:
   - What Shipped
   - What Changed From Plan
   - Bugs
   - Reusable Patterns
   - Technical Debt
   - Future Follow-ups

5. **Render** `templates/repo/LEARNING.md` with `{{date}}` / `{{id}}` / `{{project}}` and the ce-compound output. Write to `docs/learnings/${ID}-${slug}.md`.

6. **Delegate to `compound-engineering:ce-promote`** to look at the "Reusable Patterns" section. For each pattern, ask the user:
   - "Promote `<pattern title>` to AIR-OS `40 Knowledge/Concepts/<slug>.md` or `30 Engineering/<slug>.md`?"
   - On confirm, write the promoted note with AIR-OS frontmatter (`type: concept` or `type: engineering`, ai-first preamble, related-projects wikilink back to current project).

7. **Update ROADMAP.** Edit the AIR-OS ROADMAP.md:
   - Find the `${ID}` line under "🔥 Now"
   - Strip `adhoc-inserted=true` if present
   - Strip `status=in-progress`
   - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
   - Atomic write via `.tmp` + `mv`

8. **Re-sync:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

9. **Log + commit:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | shipped | n |" >> docs/learnings/_log.md
   git add docs/learnings/${ID}-${slug}.md docs/product/ROADMAP.md docs/learnings/_log.md
   git commit -m "compound: $ID — shipped + learning + ROADMAP update"
   ```

10. **Report:**
    - Learning path
    - Patterns promoted to AIR-OS (paths, if any)
    - ROADMAP item moved to Done
    - Next suggested command: `/ship-next`

## Failure modes

- No plan found → ask user to run `/ship-build` first
- `ce-compound` unavailable → fall back to user-driven structured prompt for each section
- ROADMAP doesn't contain `${ID}` → ERROR, ask user to inspect
