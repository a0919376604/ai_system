---
name: ship-compound
description: Wrap up R-NNN once its work is on the base branch — write the learning, update CONTEXT.md, move the ROADMAP row to Done, remove spec and plan (squash: ship-next Phase 8; mr: /ship-land)
discord-visible: true
---

# /ship-compound

You are wrapping up a Roadmap item.

## Argument

(none — uses `ID` when the caller set it, as /ship-land does; otherwise the most recent plan in `docs/plans/R-*.md`)

## Steps

1. **Sync:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh
   ```

2. **Identify the ship.** The caller sets `ID`: ship-next Phase 8 for the R-NNN it just landed, `/ship-land` after the merge. Select its file with `find docs/specs docs/plans -name "${ID}-*.md" 2>/dev/null | grep -v -- '-review-fix-' | sort | head -1` (no shell glob: zsh aborts on a pattern that matches nothing, and a small-change lane ship has no plan) and take `slug` from that filename. Only when run standalone without `ID`, take the most recent `docs/specs/R-*.md` or `docs/plans/R-*.md`.

3. **Gather inputs:**
   - The plan `docs/plans/${ID}-${slug}.md`, if any. A small-change lane ship has none: use the spec and the ship's implementation commits instead, and skip "What Changed From Plan".
   - All decisions tagged `affected-roadmap-items: ... ${ID} ...`
   - All ideas tagged `related-roadmap-item: ${ID}`
   - Git log from the ship's spec commit to HEAD

4. **Draft the learning yourself** with these sections:
   - What Shipped
   - Key Decisions — from the spec's `## Decisions`; the spec leaves the repo in step 9
   - What Changed From Plan
   - Bugs
   - Lessons → checks
   - Reusable Patterns
   - Technical Debt
   - Future Follow-ups

5. **Render** `templates/repo/LEARNING.md` with `{{date}}` / `{{id}}` / `{{project}}` and the learning draft. Write to `docs/learnings/${ID}-${slug}.md`. When `/ship-land` points at a learning draft (`<ship worktree>/.ship/learning-draft.md`, written by ship-next Phase 8 in mr mode), start from it.

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
   cited by any file under `docs/learnings/`.

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

6b. **Promote lessons into checks.**

   **Candidates:** this ship's blocking and major findings (🔴/`[blocking]`,
   🟡/`[important]`/`[major]`) from
   `/tmp/ship-next-{review,spec,security}-${ID}-*.md`, when present, plus the
   learning's Bugs. Keep recurring classes, not one-off typos. Discover reports
   with `find`, not an unmatched shell glob.

   **Mechanical or judgment:** a fixed syntactic pattern, banned call,
   file-location rule, format, or behaviour a test can pin is mechanical;
   everything else is judgment. When this ship repeats a mistake covered by an
   existing judgment rule, promote that rule to mechanical now.

   **Levels:** architecture first — remove the second way so the mistake cannot
   be written. Then a check in the repo being compounded (test or lint), whose
   failure message names the fix. Usually the fix's regression test is already
   the check. An `sn_mech_gates` gate is an option only when the repo is ai_system
   itself, and must be proven through the bats test that exercises it.

   **Prove, then record:** use `tdd_rules_prove` with the real mistake's commit,
   the check command, and only the check paths to overlay. Inspect the red tail
   to confirm it fails on the mistake, not a missing dependency. Record a proven
   check with `tdd_rules_append "$ID" "<rule>" "<check>"`; this promotes an existing
   judgment rule in place and keeps its original source. A failed proof becomes
   a judgment rule. In auto mode, log it with
   `~/.claude/skills/ship-workflow/lib/auto-decision-log.sh "$WORKTREE" "P8" "lesson kept as judgment — proof failed" "<rule>"`.
   **Judgment rules:** use `tdd_rules_append "$ID" "<rule>"`.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/tdd-rules.sh
   # One line, imperative, no repo-specific numbers that will go stale.
   # tdd_rules_prove "<red-ref>" "<check-command>" "<check-path>"
   # tdd_rules_append "$ID" "<rule>" "<check>"
   # tdd_rules_append "$ID" "<rule>"

   if tdd_rules_over_cap; then
     echo "WARN: this repo has $(tdd_rules_count) learned TDD rules in docs/tdd-rules.md + docs/tdd-rules.d/ (cap ${TDD_RULES_MAX})." >&2
     echo "      Review the oldest by their ← R-NNN source and drop what no longer applies." >&2
   fi
   UNSOURCED=$(tdd_rules_unsourced)
   if [ -n "$UNSOURCED" ]; then
     printf 'WARN: rules with no source, so they can never be pruned:\n%s\n' "$UNSOURCED" >&2
   fi
   tdd_rules_table
   ```

   **Commit when changed, before step 9.** Stage the actual check files with
   `git add -- <check files> docs/tdd-rules.d`, skipping any absent path; include
   `docs/tdd-rules.md` when it changed. Replace the count placeholders with this
   step's actual counts before committing.

   ```bash
   # Stage each actual check file, when present: git add -- <check files>
   if [ -d docs/tdd-rules.d ]; then git add -- docs/tdd-rules.d; fi
   if [ -f docs/tdd-rules.md ]; then git add -- docs/tdd-rules.md; fi
   git diff --cached --quiet || git commit -m "lesson: ${ID} — <n> check(s), <m> judgment rule(s)"
   ```

   The learning's `## Lessons → checks` gets one line per lesson: `- <rule> — enforced by <check> · proof: <proof line>` or `- <rule> — judgment`.

7. **Update ROADMAP.** The work is on the base branch (squash: Phase 7 landed it; mr: `/ship-land` runs this after the merge). Edit the AIR-OS ROADMAP.md: find the `${ID}` line under "🔥 Now"; strip `adhoc-inserted=true`, `status=in-progress`, `status=in-review` and the ` · mr=<url>` annotation if present; move it to "✅ Done" with `· ✅ $(date +%Y-%m-%d)`; atomic write via `.tmp` + `mv`. If the `${ID}` row is already under "✅ Done" (a re-run of `/ship-land`), leave the ROADMAP as it is.

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

9. **Log + commit.** One commit, on whatever branch this runs on: the base branch in squash mode, `/ship-land`'s throwaway worktree at `origin/<base>` in mr mode. It never pushes.

   ```bash
   # shellcheck disable=SC1091
   source ~/.claude/skills/ship-workflow/lib/ship-log.sh

   # Only the learning outlives the ship (R-005, R-006). The spec's latest text goes to
   # the vault first — review rounds edit it after Phase 3's mirror. Best-effort: with
   # no vault binding the spec still leaves, and git history keeps it.
   if [ -f "docs/specs/${ID}-${slug}.md" ]; then
     VAULT_PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path 2>/dev/null) \
       && ~/.claude/skills/ship-workflow/lib/spec-mirror.sh "docs/specs/${ID}-${slug}.md" "$VAULT_PROJECT/Specs/${ID}-${slug}.md" \
       || echo "WARN: spec not mirrored to the vault — it stays in git history" >&2
   fi
   # Before ship_log: a failure here must leave nothing written. -f because the
   # plan may carry an uncommitted Execution log note that steps 2-4 already read.
   git rm -q -f --ignore-unmatch -- "docs/plans/${ID}-${slug}.md" "docs/plans/${ID}-${slug}-review-fix-*.md" \
     "docs/specs/${ID}-${slug}.md" "docs/brainstorms/${ID}-${slug}.md" || exit 1

   ship_log "| $(date +%Y-%m-%d\ %H:%M) | ship-compound | $ID | shipped | n |"

   # Required: the learning and the log row. Missing either → stop rather than commit
   # a partial set under a title that claims both.
   git add "docs/learnings/${ID}-${slug}.md" docs/learnings/_log.md || exit 1
   # The vault mirror and this ship's TDD rule fragment, when the repo has them.
   for p in docs/product docs/proposals docs/tdd-rules.d; do
     # An ignored path (ai_system ignores its untracked mirror) is not this ship's to add.
     if [ -e "$p" ] && ! git check-ignore -q "$p"; then git add "$p" || exit 1; fi
   done
   git commit -m "compound: $ID — shipped + learning${SHIP_COMMIT_SUFFIX:-}" || exit 1
   ```

   This commit removes the plan, fix-plans, spec and (legacy) brainstorm
   (`ship_log` only appends, so the staged removal rides this commit); only the
   learning stays; the spec's full text is in the vault `Specs/`.

   `docs/tdd-rules.d/` is staged when present: step 6b writes this ship's rule
   fragment there. `/ship-land` sets `SHIP_COMMIT_SUFFIX=" [skip ci]"`.

10. **Report:**
    - Learning path
    - ROADMAP item moved to Done
    - Next suggested command: `/ship-next`

## Failure modes

- No spec or plan for `${ID}` → ask the user to run `/ship-next` first
- ROADMAP doesn't contain `${ID}` → ERROR, ask user to inspect
