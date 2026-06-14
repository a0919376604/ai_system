---
name: ship-research
description: Vault-first deep research on a topic; synthesized to AIR-OS (wraps /obsidian-research-deep)
argument-hint: <topic>
discord-visible: true
---

# /ship-research

You are running vault-first deep research to fill a knowledge gap.

## Argument

`<topic>` — what to research. Free text, no quotes needed. Optionally prefix with `global` (or `_` / `-`) for cross-project research; default scopes to the current repo's project.

## When to invoke

| Phase | Why |
|---|---|
| Mid `/ship-next` brainstorm | Brainstorm reveals "I don't fully understand X yet" → research first → return |
| Mid `/ship-build` | Hit "need to know how Y works" without leaving Claude Code |
| Before `/ship-roadmap` | Validate a candidate R-NNN belongs on Roadmap by checking what's known |
| In `/ship-idea` with low confidence | Promote `confidence: speculation` to `medium`+ by grounding in literature |
| In `/ship-compound` Reusable Patterns | Verify a pattern is novel vs already documented elsewhere |

## Steps

1. **Sync product brain:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Resolve project name:**
   ```bash
   PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)
   ```

3. **Decide scope** based on user's intent:
   - If user prefixed `global` (or `_` / `-`) → invoke with `global` as repo arg → output lands in `Research/Deep/YYYY-MM-DD-<slug>.md`
   - Otherwise → invoke with `$PROJECT` → output lands in `Projects/<PROJECT>/Research/<slug>-deep.md`

4. **Delegate to `/obsidian-research-deep`**:
   ```
   /obsidian-research-deep $PROJECT $TOPIC
   ```
   (or `/obsidian-research-deep global $TOPIC` for vault-wide.)
   The research-deep command will:
   - Phase 1: scan vault for existing knowledge on $TOPIC
   - Phase 2: gap analysis → 3-5 sub-queries
   - Phase 3: fetch via `scripts.research.research_deep`
   - Phase 4: synthesize delta + write file with AI-first frontmatter
   - Append log line to `Logs/YYYY-MM-DD.md`

5. **Append log line (repo side):**
   ```bash
   scope=$([ "$ARG_SCOPE" = "global" ] && echo "global" || echo "$PROJECT")
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-research | - | $TOPIC ($scope) | n |" >> docs/learnings/_log.md
   ```

6. **Commit the log entry (repo side):**
   ```bash
   git add docs/learnings/_log.md
   git commit -m "chore: ship-research on '$TOPIC'"
   ```

7. **Report:**
   - Where the research file landed (AIR-OS path)
   - Sub-queries used + total sources gathered
   - Key findings 1-line summary
   - Suggested follow-up: if you're mid-brainstorm, return to it now; if findings reveal a Roadmap item, run `/ship-idea` to capture.

## Failure modes

- `/obsidian-research-deep` not installed → tell user to keep obsidian-second-brain skill (this is one of the 2 obsidian sub-commands explicitly kept)
- Topic too vague → ask user for one specific angle, retry
- All sub-queries return empty / blocked → write a "what was already known" stub and skip Phase 3; ship-research is still useful as a vault baseline summary
