---
name: ship-roadmap
description: Refresh ROADMAP.md via ce-strategy — re-rank Now/Next/Later/Done by Impact × Dependency
discord-visible: true
---

# /ship-roadmap

You are running the Roadmap refresh ritual.

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```
   (Force here so the latest Obsidian edit lands before we read.)

2. **Resolve AIR-OS Roadmap path:**
   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ```

3. **Gather inputs.** Read:
   - `docs/product/STRATEGY.md`
   - `docs/product/ROADMAP.md` (current state)
   - `docs/ideas/IDEA-*.md` where `status != shelved`
   - `docs/decisions/D-*.md` where `decision-status: accepted`
   - `docs/learnings/R-*.md` modified within last 30 days

4. **Delegate to `compound-engineering:ce-strategy`** with all inputs concatenated. Ask it to:
   - Identify Roadmap items that should change status
   - Suggest new R-NNN items derived from accepted ideas/decisions
   - Re-rank by Impact × Dependency

5. **Apply PRD §6 rules:**
   - Cap "Now" at 3-5 items
   - Preserve Done section verbatim (don't lose history)
   - Move shipped items from "Now" → "Done" with `✅ <YYYY-MM-DD>` marker
   - Strip `adhoc-inserted=true` markers from any item now in Done
   - Sort "Next" and "Later" by Impact × Dependency

6. **Show diff.** Render a unified diff between current ROADMAP.md and proposed, ask the user to confirm.

7. **On confirm: write to AIR-OS, then sync back to repo:**
   ```bash
   # Edit $ROADMAP_PATH (atomic write — .tmp then mv)
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

8. **Log + commit (repo side):**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-roadmap | - | refresh | n |" >> docs/learnings/_log.md
   git add docs/product/ROADMAP.md docs/learnings/_log.md
   git commit -m "chore: refresh ROADMAP.md"
   ```

9. **Report:** Count of items moved between sections, top 3 "Now" priorities, next suggested action (`/ship-next`).

## Fallback

If `compound-engineering:ce-strategy` is unavailable, do the re-ranking yourself in-conversation and explain your reasoning before showing the diff.
