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

5.5. **UA-augmented case ELI5 stub (auto-detect, silent if UA absent):**

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ua-integration.sh
   ua_check_installed && echo "UA present — run the case-stub step below." || true
   ```

   When UA is present, **invoke `/understand-anything:understand-diff`** with the base
   being the commit of `chore: plan ${ID}` (fall back to two weeks ago if absent). Then
   render the stub, supplying the three UA fields **from the analysis you just read**:

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/render-template.sh
   PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)
   STUB_PATH="/tmp/case-stub-${ID}.md"
   render_template ~/.claude/skills/ship-workflow/templates/repo/CASE_ELI5.md \
     id="$ID" project="$PROJECT" slug="$SLUG" theme="TODO" \
     date="$(date +%Y-%m-%d)" \
     ua_changed_files="$UA_CHANGED" \
     ua_blast_radius="$UA_BLAST" \
     ua_raw_diff_report="$UA_REPORT" \
     > "$STUB_PATH"
   echo "Case ELI5 stub drafted at $STUB_PATH"
   echo "Review + add rationale + move to AIR-OS 10 Projects/$PROJECT/Architecture/cases/<theme>/"
   ```

   Set `UA_CHANGED`, `UA_BLAST` and `UA_REPORT` yourself from the analysis. This used to
   run `ua_get_shipped_facts` and cut the values out with
   `sed -n '/### Changed components/,/^###/p'` — parsing prose for fixed headings. That
   worked only because the prose came from bash. `/understand-diff` is written by a model
   following instructions, and treating its output as a parseable contract is the mistake
   this repo spent thirteen review rounds learning not to make. You read it; you fill the
   fields.

5.6. **REMINDERS candidate prompt (no auto-write):**

   ```bash
   echo
   echo "Any new triggered-time rule to add to REMINDERS.md?"
   echo "Look at UA blast radius — did we touch a module that others should"
   echo "know a rule about before editing? (e.g. 'before touching X, do Y')"
   echo "y/n:"
   ```

   REMINDERS is imperative shape (rules); UA output is declarative (facts). Rather than auto-draft rules (which would hallucinate), just prompt the human.

### Step 6 — Update CONTEXT.md (project vocabulary)

```bash
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/context-md.sh
```

1. **Extract terms.** From this ship's diff and `docs/specs/${ID}-${SLUG}.md`,
   identify domain terms this work **introduced or clarified**. A term qualifies
   only if it is project-specific and a newcomer could not infer it from the code
   alone. Class names, file names, and generic programming vocabulary do not qualify.

2. **Write entries.** Append to (or refine in) `<repo>/CONTEXT.md`, one bullet per
   entry, in exactly this format:

   ```
   - **<term>** — <definition>
   ```

   Continuation lines are indented and are not separate entries.

3. **Cap check.**

   ```bash
   if context_md_over_cap; then
     if [ "$AUTO" = "1" ]; then
       # Deletion is destructive and has no machine-checkable invariant here,
       # so pruning is skipped in --auto:yes. Surface it instead.
       echo "WARN: CONTEXT.md over cap ($(context_md_line_count) lines / $(context_md_entry_count) entries)" >&2
       CONTEXT_MD_STATUS="over cap — prune pending"
       # Spec 4.5 promises a decision-log entry too. An unattended run's WARN goes to
       # stderr and is gone; the log is where the operator looks afterwards.
       ~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P8" \
         "CONTEXT.md over cap — pruning skipped (deletion is never automatic)" \
         "$(context_md_line_count) lines / $(context_md_entry_count) entries"
     else
       CONTEXT_MD_STATUS="pruned"
     fi
   else
     CONTEXT_MD_STATUS="$(context_md_entry_count) entries / $(context_md_line_count) lines"
   fi
   ```

   In interactive mode when over cap, **prune to <= 150 lines** in this order:
   merge semantically duplicate entries; delete terms reported by
   `context_md_orphan_terms`; if still over, delete the entries least recently
   cited by any file under `docs/specs/` or `docs/plans/`.

   **There is no archive section.** `CONTEXT.md` is read in full every Phase 3, so
   an archive heading would keep paying the token cost. Deleted terms are recovered
   with `git log -p --follow CONTEXT.md`.

4. **Commit and mirror.**

   ```bash
   # Guard: a ship that surfaced no qualifying terms leaves no CONTEXT.md. Without
   # this, `git add` exits 128 (pathspec did not match) and spec-mirror.sh exits 2,
   # breaking the purely-additive property every integration in this design holds to.
   if [ -f CONTEXT.md ]; then
     git add CONTEXT.md && git commit -m "context: update vocabulary from ${ID}"
     VAULT_DIR="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
     ~/.claude/skills/ship-workflow/lib/spec-mirror.sh CONTEXT.md "$VAULT_DIR/CONTEXT.md"
   else
     CONTEXT_MD_STATUS="absent — no qualifying terms this ship"
   fi
   ```

6. **Delegate to `compound-engineering:ce-promote`** to look at the "Reusable Patterns" section. For each pattern, ask the user:
   - "Promote `<pattern title>` to AIR-OS `40 Knowledge/Concepts/<slug>.md` or `30 Engineering/<slug>.md`?"
   - On confirm, write the promoted note with AIR-OS frontmatter (`type: concept` or `type: engineering`, ai-first preamble, related-projects wikilink back to current project).

7. **Update ROADMAP.** Edit the AIR-OS ROADMAP.md:
   - Find the `${ID}` line under "🔥 Now"
   - Strip `adhoc-inserted=true` if present
   - Strip `status=in-progress`
   - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
   - Atomic write via `.tmp` + `mv`

7b. **Update Proposal (if any).** Find any vault proposal for this R-NNN:

   ```bash
   PROJECT_PATH=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)
   PROPOSALS_DIR="$PROJECT_PATH/Proposals"
   PROPOSAL_FILE=$(find "$PROPOSALS_DIR" -name "*-${ID}-*-proposal.md" 2>/dev/null | head -1)

   if [ -n "$PROPOSAL_FILE" ]; then
     # 1. Flip status to shipped
     sed -i.bak 's/^status: .*/status: shipped/' "$PROPOSAL_FILE"
     rm "$PROPOSAL_FILE.bak"

     # 2. Add cross-link to the learning at the end of §8.
     if ! grep -q "Shipped via:" "$PROPOSAL_FILE"; then
       printf "\n- Shipped via: [[docs/learnings/%s-%s]]\n" "$ID" "$slug" >> "$PROPOSAL_FILE"
     fi

     echo "Marked $PROPOSAL_FILE as shipped + linked learning."
   fi
   ```

8. **Re-sync** (after ROADMAP + proposal updates so docs/product/ and docs/proposals/ both refresh):
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

9. **Log + commit:**
   ```bash
   echo "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | shipped | n |" >> docs/learnings/_log.md
   git add docs/learnings/${ID}-${slug}.md docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md
   git commit -m "compound: $ID — shipped + learning + ROADMAP update"
   ```

10. **Report:**
    - Learning path
    - Patterns promoted to AIR-OS (paths, if any)
    - ROADMAP item moved to Done
    - Next suggested command: `/ship-next`

## Failure modes

- No plan found → ask user to run `/ship-next` first
- `ce-compound` unavailable → fall back to user-driven structured prompt for each section
- ROADMAP doesn't contain `${ID}` → ERROR, ask user to inspect
