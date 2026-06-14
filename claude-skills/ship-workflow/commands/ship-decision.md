---
name: ship-decision
description: Record an architectural or product decision as D-NNN with options/chosen/reasoning. Optionally invokes compound-engineering:ce-doc-review for an independent read. Use when a meaningful trade-off has been made — switching libraries, refactoring boundaries, deciding scope, etc.
---

# /ship-decision

You are recording a decision into `docs/decisions/D-NNN-<slug>.md`.

## Argument

`<topic>` — short identifier (Claude infers the rest from conversation)

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Allocate ID:**
   ```bash
   ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh decision)
   ```

3. **Generate slug** from `<topic>` (same rules as ship-idea).

4. **Read ROADMAP** (`docs/product/ROADMAP.md`) to determine `affected-roadmap-items`. Look at R-NNN entries in "Now" and "Next" and pick the ones plausibly impacted by this decision. If none, leave empty.

5. **Infer Context / Options / Chosen / Reasoning / Consequences** from the last 20-50 conversation messages. If the user wants more rigor, invoke `compound-engineering:ce-doc-review` on the draft.

6. **Render template** with `{{date}}` / `{{id}}` / `{{project}}` and write to `docs/decisions/${ID}-${slug}.md`. Make sure `ship-context: true` is set.

7. **Append log:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-decision | $ID | $topic | n |" >> docs/learnings/_log.md
   ```

8. **Commit:**
   ```bash
   git add docs/decisions/${ID}-${slug}.md docs/learnings/_log.md
   git commit -m "decision: $ID $topic"
   ```

9. **Report** to the user: ID, file, affected R-NNN items, and ask "Do you want to mark `decision-status: accepted`?" — if yes, edit frontmatter and commit a follow-up.

## Failure modes

- `docs/decisions/` doesn't exist → run `/ship-init` first
- Cannot reasonably infer Context — too little conversation history → ask user to paste context
