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
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
MERGE_MODE=$(merge_mode)
```

**`mr` mode: queue, do not edit.** A review branch must not touch `CONTEXT.md` —
every ship editing it is what made parallel MRs conflict (R-001). Do sub-step 1,
then queue each entry instead of doing sub-steps 2–4:

```bash
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/context-md.sh
# shellcheck disable=SC1091
source ~/.claude/skills/ship-workflow/lib/ship-log.sh
# The queue belongs on the review branch. From the base checkout it would be
# committed to base by step 9 — refuse instead (see step 9).
ship_log_defers || {
  echo "ship-compound: mr mode — run this from the ship's worktree (a ship/* branch)" >&2
  exit 1
}
# Once per qualifying entry (continuation lines, if any, indented):
# context_pending_add "$ID" "- **<term>** — <definition>"
CONTEXT_MD_STATUS="queued for /ship-land"
```

Step 9 commits the queue file `docs/ship-pending/${ID}-context.md` on the review
branch, so the entries are reviewed with the work. `/ship-land` folds them into
`CONTEXT.md`, runs the cap check and mirrors to the vault after the MR merges.
Sub-steps 2–4 below are the `squash` path.

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

6b. **Promote a testing lesson into the repo's TDD rules.** If this ship's
   learning is about *how to write tests here* — a seam that kept getting
   violated, a fixture that kept rippling, an assertion shape that kept
   lying — append it. The Phase 6 review tags are the trigger: a finding
   tagged `[seam-violation]`, `[assertion-roulette]` or `[weak-assertion]`
   is a candidate.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/tdd-rules.sh
   # One line, imperative, no repo-specific numbers that will go stale.
   # tdd_rules_append "$ID" "Never assert on log output; assert on the return value."

   if tdd_rules_over_cap; then
     echo "WARN: this repo has $(tdd_rules_count) learned TDD rules in docs/tdd-rules.md + docs/tdd-rules.d/ (cap ${TDD_RULES_MAX})." >&2
     echo "      Review the oldest by their ← R-NNN source and drop what no longer applies." >&2
   fi
   UNSOURCED=$(tdd_rules_unsourced)
   [ -n "$UNSOURCED" ] && printf 'WARN: rules with no source, so they can never be pruned:\n%s\n' "$UNSOURCED" >&2
   ```

   **A rule with no `← R-NNN` cannot be judged later.** Forty unprunable rules
   is the context problem this workflow exists to prevent, wearing a new hat.

7. **Update ROADMAP.** What "done" means depends on how Phase 7 landed it.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   MERGE_MODE=$(merge_mode)
   ```

   - **`squash`** — the work is on the base branch. Edit the AIR-OS ROADMAP.md:
     - Find the `${ID}` line under "🔥 Now"
     - Strip `adhoc-inserted=true` if present
     - Strip `status=in-progress`
     - Move the line to "✅ Done" with `· ✅ $(date +%Y-%m-%d)` suffix
     - Atomic write via `.tmp` + `mv`

   - **`mr`** — the work is in review, not landed. The row stays in "🔥 Now":

     ```bash
     ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh \
       "$ROADMAP_PATH" "$ID" --mark-review "$SHIP_REVIEW_URL"
     ```

     Moving it to Done here would make the ROADMAP assert a merge that has not
     happened. `/ship-land` performs the Done move after the review merges.

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

9. **Log + commit.** In `mr` mode the learning belongs ON the review branch,
   so it is reviewed and merged with the work it describes. Committing it to
   the base branch would put a learning for unmerged code on main.

   In `mr` mode the review branch stages only paths that carry this ship's own
   ID. The shared files — `_log.md`, the `docs/product/` and `docs/proposals/`
   vault mirror, `CONTEXT.md` — are what made parallel MRs conflict (R-001).
   `ship_log` turns the row into a `Ship-Log:` commit trailer there, and the
   mirror is regenerated from the vault by every `sync.sh` run anyway.

   ```bash
   # Each step runs in its own shell, so resolve the mode here rather than
   # trusting a MERGE_MODE left over from step 6 or 7.
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/merge-mode.sh
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-log.sh
   MERGE_MODE=$(merge_mode)
   STATUS_WORD=shipped
   [ "$MERGE_MODE" = "mr" ] && STATUS_WORD=in-review

   # mr mode writes to the review branch, so it must be standing on one. Run
   # from the base checkout it would commit the learning to base and push it.
   if [ "$MERGE_MODE" = "mr" ] && ! ship_log_defers; then
     echo "ship-compound: merge_mode is mr but this is '$(git branch --show-current)', not a ship/* review branch — cd into the ship's worktree" >&2
     exit 1
   fi

   # Before ship_log: a failure here must leave nothing written. -f because the
   # plan may carry an uncommitted Execution log note that steps 2-4 already read.
   git rm -q -f --ignore-unmatch -- "docs/plans/${ID}-${slug}.md" "docs/plans/${ID}-${slug}-review-fix-*.md" || exit 1

   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | $STATUS_WORD | n |"

   if [ "$MERGE_MODE" = "mr" ]; then
     git add "docs/learnings/${ID}-${slug}.md" || exit 1
     for p in docs/tdd-rules.d docs/ship-pending; do
       if [ -e "$p" ]; then git add "$p" || exit 1; fi
     done
     git commit -m "compound: $ID — $STATUS_WORD + learning" || exit 1
     # The review is already open; push the learning onto the same branch.
     git push origin "$(git branch --show-current)"
   else
     # One add for the required paths: if any is missing, stop here rather than
     # commit a partial set under a title that claims all of it.
     git add "docs/learnings/${ID}-${slug}.md" docs/product/ROADMAP.md docs/proposals/ docs/learnings/_log.md || exit 1
     if [ -e docs/tdd-rules.d ]; then git add docs/tdd-rules.d || exit 1; fi
     git commit -m "compound: $ID — $STATUS_WORD + learning + ROADMAP update"
   fi
   ```

   Both modes remove this ship's plan and fix-plans in the commit above (`ship_log`
   commits with `--only`, so the staged removal waits for it): steps 2–4
   were the plan's last reader, and plans left behind piled up to 321 files with no
   reader on one repo (R-005). Specs, brainstorms and learnings stay.

   `docs/tdd-rules.d/` is staged in both modes: step 6b writes this ship's rule
   fragment there, and no other step commits it.

10. **Report:**
    - Learning path
    - Patterns promoted to AIR-OS (paths, if any)
    - `squash`: ROADMAP item moved to Done
    - `mr`: row marked in-review — run `/ship-land ${ID}` after the review merges
    - Next suggested command: `/ship-next`

## Failure modes

- No plan found → ask user to run `/ship-next` first
- `ce-compound` unavailable → fall back to user-driven structured prompt for each section
- ROADMAP doesn't contain `${ID}` → ERROR, ask user to inspect
