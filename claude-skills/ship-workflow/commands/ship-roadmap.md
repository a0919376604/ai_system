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
   - **`<airos_project_path>/Architecture/overview.md`** if exists — produced by `/ship-arch`. Gives ce-strategy a module dependency graph + per-module improvement candidates so Impact × Dependency ranking is grounded in real code structure, not guesswork. Pass alongside STRATEGY/ROADMAP in the prompt.

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

6. **Detect "too big" items.** For each item in "Now", evaluate against this rubric:
   - Description contains ≥ 2 distinct outcomes ("do X and Y and Z")
   - Touches ≥ 3 modules per `Architecture/overview.md`
   - Estimated effort (`est=`) > 1 week
   - Has ≥ 3 unresolved dependencies (`dep: R-... R-... R-...`)
   - ce-strategy independently rates `complexity: high`

   **If ≥ 2 are true** → mark via `roadmap-insert.sh <ROADMAP> <R-NNN> --mark-warning "<one-line reason>"`. This prefixes the line with ⚠️ and adds a `↳ flagged: <reason>` annotation.

7. **Interactive decompose (per ⚠️ item).** After all warnings applied, for each flagged R-NNN ask the user:
   ```
   ⚠️ R-NNN looks too big: <reason>
   Decompose now into 2-5 smaller R-NNN.M children? [y/N/later]
   ```
   - **`y`**: Enter short decompose brainstorm. **Each child MUST follow the action-verb + done-when format** (this is what makes ROADMAP entries actually readable later — descriptions like "R-001.x improve auth" are useless; "R-001.1 Add refresh-token rotation · done when: tokens auto-rotate every 24h with no user re-auth" is actionable). For each sub-item, ask:
     1. **Action sentence**: one imperative verb + object (e.g. "Add refresh-token rotation to /auth endpoints", NOT "auth improvements")
     2. **done-when**: a single observable success criterion (CI green, metric threshold, user-visible behavior). If the user can't state one, the sub-item is still too vague — push back and refine before allocating an ID.
     3. **est** (optional but recommended): rough duration in days/weeks. Reject anything ≥ 1w — that's another decomposition signal.

     Then allocate + insert:
     ```bash
     # Convert parent to epic
     roadmap-insert.sh "$ROADMAP" R-NNN --mark-epic

     # For each child, allocate ID + insert under parent with done-when
     # (loop over an array of {desc, done_when, est} triples gathered above)
     for i in 1 2 3; do
       CHILD_ID=$(id-gen.sh roadmap --child R-NNN --reserve)
       roadmap-insert.sh "$ROADMAP" "$CHILD_ID" "${desc[i]}" --child R-NNN \
         --done-when "${done_when[i]}" \
         ${est[i]:+--est "${est[i]}"}
     done
     ```

     After all children inserted, **auto-draft an explainer note for each newly-created child** (and for the newly-converted epic parent):

     ```bash
     # Run /ship-explain inline for each newly-created child + the parent epic
     for cid in "R-NNN" "${CHILD_IDS[@]}"; do
       # Follow /ship-explain single-row mode steps for each cid
       # (the brainstorm session shares context, so re-reading proposal
       #  is cheap; explainers benefit from shared voice)
       ~/.claude/commands/ship-explain.md $cid    # conceptual — Claude follows command file
     done
     ```

     Rationale: at decompose time the brainstorm context is hot — Claude has the proposal, Architecture, and the rationale for the split all in mind. Generating explainers in the same session yields higher-quality, more consistent prose than deferring to a later `/ship-explain --all-now`.

     **Reject decompositions where any child lacks done-when.** Better to bounce back to the user for clarification than to insert vague children that re-create the original "what does R-001.x mean" problem.
   - **`N`** (or default): drop the ⚠️ marker. User has decided this item is fine as-is. Re-write the line without ⚠️ by manually editing ROADMAP.md (sed `s/⚠️ //` for that specific line) and remove the ↳ flagged annotation.
     **Also** — if the original entry has no done-when annotation, prompt: "R-NNN has no `↳ done when:` annotation. Add one now? [Y/n]" — if Y, ask for the criterion and inject it as a second line under the entry. Keeping the ⚠️ off without a done-when is allowed but flagged in the report.
   - **`later`** (or `l`): keep ⚠️ marker so ship-next can re-prompt next time the item is picked. Don't touch the line.

8. **Show diff.** Render a unified diff between current ROADMAP.md and proposed, ask the user to confirm overall.

9. **On confirm: write to AIR-OS, then sync back to repo:**
   ```bash
   # Edit $ROADMAP_PATH (atomic write — .tmp then mv)
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

10. **Log + commit (repo side):**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-roadmap | - | refresh | n |" >> docs/learnings/_log.md
   git add docs/product/ROADMAP.md docs/learnings/_log.md
   git commit -m "chore: refresh ROADMAP.md"
   ```

11. **Report:**
    - Count of items moved between sections
    - **Top 3 "Now" priorities — render each with its `↳ done when:` annotation inline** so the user can see at a glance what "done" means without opening ROADMAP.md. Example:
      ```
      1. R-014.1 — Add refresh-token rotation to /auth endpoints
         ↳ done when: tokens auto-rotate every 24h with no user re-auth
      2. R-007   — Wire LangFuse trace IDs through webhook handler
         ↳ done when: every webhook request has a queryable trace in LangFuse
      3. R-022   — Cache embedding lookups (lru, 10k entries)
         ↳ done when: p95 embedding latency < 50ms on staging
      ```
      If an item is missing `↳ done when:`, render `(no done-when set — consider adding)` in red so it's visually obvious.
    - **Count of items in "Now" missing `↳ done when:` annotation.** This is the readability health metric — target zero.
    - **Count of items in "Now" missing `↳ explain:` annotation.** This is the comprehension health metric — target zero. Suggested fix:
      ```
      $ /ship-explain --all-now      ← drafts explainers for every Now item without one
      ```
    - **Count of newly-decomposed epics + child counts**
    - **Proposal suggestions** — scan items that changed this run (newly added, Later→Next, Next→Now). For each that has `effort=L` OR `confidence=low|medium` OR description hints at cross-module impact (≥2 modules in `[[Architecture/modules/]]`):
      ```
      ⚠️ $ID changed this run with effort=$EFFORT confidence=$CONF.
         Consider /ship-propose $ID before /ship-next.
      ```
    - Next suggested action:
      ```
      $ /ship-propose                    ← auto-picks next R-NNN without active proposal
      (or specify: /ship-propose <R-NNN>)
      ```

## Fallback

If `compound-engineering:ce-strategy` is unavailable, do the re-ranking yourself in-conversation and explain your reasoning before showing the diff.
