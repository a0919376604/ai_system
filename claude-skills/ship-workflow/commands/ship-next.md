---
name: ship-next
description: Pick next Roadmap item, enter superpowers:brainstorming to produce brainstorm + spec
argument-hint: "[--adhoc <description>]"
discord-visible: true
---

# /ship-next

You are picking the next item and entering the brainstorm flow.

## Arguments

- `--adhoc <description>` — skip Roadmap selection; allocate next R-NNN and insert into "Now"

## Steps

### Branch A: Default (pick from Roadmap)

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Read** `docs/product/ROADMAP.md` "🔥 Now" section. Parse R-NNN items not marked `✅`.

3. **Rank** by:
   - Explicit `impact=high` markers first
   - Dependencies satisfied (no unresolved `dep:` references)
   - `adhoc-inserted=true` items deprioritized vs planned items (planned > emergency)

4. **Present top 1-2** to the user, get confirmation. Capture the chosen `R-NNN` and `<slug>`.

5. **Skip to "Common: Enter brainstorming" below.**

### Branch B: `--adhoc <description>`

1. **Sync product brain (forced)**:
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

2. **Allocate R-NNN:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --reserve)
   ```

3. **Resolve ROADMAP path + insert:**
   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$ID" "<description>" --adhoc
   ```

4. **Re-sync** so the repo mirror picks up the insert:
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

5. **Continue below with $ID and slug derived from `<description>`.**

### Common: Enter brainstorming

6. **Invoke `superpowers:brainstorming`** with context: spec target = `docs/specs/${ID}-${slug}.md`, project = `<project_name>`.

7. **brainstorming will produce** a spec file. Confirm it landed at `docs/specs/${ID}-${slug}.md`.

8. **Also write the brainstorm note** at `docs/brainstorms/${ID}-${slug}.md` (Claude can do this inline or have brainstorming output the file). Use `templates/repo/BRAINSTORM.md` with substitutions.

9. **Log + commit:**
   ```bash
   adhoc_flag=$([ "$ADHOC" = "1" ] && echo y || echo n)
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-next | $ID | $description | $adhoc_flag |" >> docs/learnings/_log.md
   git add docs/brainstorms/${ID}-${slug}.md docs/specs/${ID}-${slug}.md docs/learnings/_log.md docs/product/ROADMAP.md
   git commit -m "brainstorm+spec: $ID $description"
   ```

10. **Report:** ID, slug, brainstorm path, spec path, next suggested command: `/ship-build`.

## Failure modes

- "Now" empty in default branch → ask user to either `/ship-roadmap` first or use `--adhoc`
- brainstorming returns no spec file → ERROR, halt before commit
