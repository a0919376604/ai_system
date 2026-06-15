---
name: ship-propose
description: Produce a prescriptive proposal doc for a Roadmap R-NNN before brainstorm (3 sizes; optional /ship-research integration). Orthogonal to /ship-arch.
argument-hint: "[R-NNN] [--size S|M|L] [--no-research] [--from-idea IDEA-NNN] [--supersede]"
discord-visible: true
---

# /ship-propose

You are producing a **prescriptive** proposal doc for a Roadmap item — orthogonal to `/ship-arch` (which is descriptive snapshot of current state). The proposal's primary purpose is **the author's own self-comprehension**, with secondary value of team alignment.

## When to invoke

| Phase | Why |
|---|---|
| Just after `/ship-roadmap` promoted a big new R-NNN | Lock in why we're going this direction before brainstorm scatters |
| Before `/ship-next` on an R-NNN with effort=L / confidence<high / cross-multi-module | Self-comprehension gate; brainstorm will be cleaner |
| Mid `/ship-build` when implementation reveals "we never really decided X" | Pause, propose, return |
| Author feels "I'm about to start coding but I don't fully understand what I'm doing" | The forcing function |

## Implementation phases (this command)

This file currently covers:
- ✅ Phase 1: Manual draft generation
- ✅ Phase 2: Self-FAQ pass via adversarial reviewer sub-agent
- ✅ Phase 3: /ship-research orchestration + `--no-research` flag
- ⬜ Phase 4: no-arg auto-pick + --supersede / --from-idea / --size flags
- ⬜ Phase 5: downstream ship-* hooks

## Steps

1. **Sync product brain (forced — proposal needs fresh Architecture):**

   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

2. **Resolve project + paths:**

   ```bash
   PROJECT=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)
   PROJECT_PATH=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)
   ROADMAP="$PROJECT_PATH/ROADMAP.md"
   PROPOSALS_DIR="$PROJECT_PATH/Proposals"
   mkdir -p "$PROPOSALS_DIR"
   ```

3. **Parse arguments.**
   - `[R-NNN]` — first positional; required until Phase 4 (auto-pick lands)
   - `--no-research` — boolean; skip the external research sub-step
   - `--size S|M|L` — explicit size override (added in Phase 4)
   - `--from-idea IDEA-NNN` — inherit context from IDEA (added in Phase 4)
   - `--supersede` — replace existing active proposal (added in Phase 4)

   For Phase 3, only `[R-NNN]` and `--no-research` are honored. Set `DO_RESEARCH=1` by default, `DO_RESEARCH=0` if `--no-research` present.

   If `[R-NNN]` is omitted (auto-pick not yet implemented), abort with:

   ```
   ERROR: /ship-propose requires an R-NNN until Phase 4 ergonomics are implemented.
   Usage: /ship-propose R-001 [--no-research]
   ```

4. **Fetch the R-NNN line + description from ROADMAP:**

   ```bash
   ROW=$(~/.claude/skills/ship-workflow/lib/propose-helpers.sh list-roadmap-items "$ROADMAP" \
         | awk -F'\t' -v id="$ID" '$2 == id {print; exit}')
   if [ -z "$ROW" ]; then
     echo "ERROR: $ID not found in $ROADMAP" >&2
     exit 1
   fi
   SECTION=$(awk -F'\t' '{print $1}' <<< "$ROW")
   DESC=$(awk -F'\t' '{print $3}' <<< "$ROW")
   ```

5. **Refuse Done items** — if `$SECTION = Done`, abort with "Cannot propose for shipped item $ID". Done items go through `/ship-compound` not `/ship-propose`.

6. **Detect existing active proposal:**

   ```bash
   ACTIVE=$(~/.claude/skills/ship-workflow/lib/propose-helpers.sh list-active-proposals "$PROPOSALS_DIR")
   if grep -Fxq "$ID" <<< "$ACTIVE"; then
     echo "$ID already has an active proposal in $PROPOSALS_DIR."
     echo "To replace it, pass --supersede (Phase 4)."
     exit 1
   fi
   ```

7. **Extract effort / confidence from the Roadmap row's `· effort=X · confidence=Y` suffix:**

   ```bash
   EFFORT=$(grep -oE 'effort=[SML]'    <<< "$DESC" | cut -d= -f2 || echo "unknown")
   CONF=$(  grep -oE 'confidence=(high|medium|low)' <<< "$DESC" | cut -d= -f2 || echo "unknown")
   SIZE=$(~/.claude/skills/ship-workflow/lib/propose-helpers.sh classify-size "$EFFORT" "$CONF")
   ```

   If `SIZE == "skip"`, tell user "$ID is effort=S + confidence=high — proposal would be overkill. Skip and run `/ship-next` directly?" and exit with code 0.

8. **Generate slug + filename:**

   ```bash
   SLUG=$(~/.claude/skills/ship-workflow/lib/propose-helpers.sh slugify "$DESC")
   FNAME=$(~/.claude/skills/ship-workflow/lib/propose-helpers.sh proposal-filename "$(date +%Y-%m-%d)" "$ID" "$SLUG")
   TARGET="$PROPOSALS_DIR/$FNAME"
   ```

9. **Discover related Architecture nodes.** Read these and pick the 3-7 most relevant:

   ```bash
   ls "$PROJECT_PATH/Architecture/modules/" "$PROJECT_PATH/Architecture/ai-flows/" 2>/dev/null
   ```

   For each candidate, decide if the R-NNN description touches it. Build a list of `[[Architecture/modules/<m>]]` and `[[Architecture/ai-flows/<f>]]` wikilinks.

10. **Discover related history:**

    ```bash
    # Look for IDEA-* or D-* that mention $ID or share keywords with $DESC
    grep -l "$ID" docs/ideas/IDEA-*.md docs/decisions/D-*.md 2>/dev/null
    ```

    Build a list of `[[docs/ideas/IDEA-NNN]]` / `[[docs/decisions/D-NNN]]` wikilinks.

10b. **External grounding** (unless `--no-research`): orchestrate `/ship-research` as a sub-step.

    If `$DO_RESEARCH = 1`:

    a. Build the research topic string from R-NNN description + nearby technical keywords. Example for R-001:
       ```
       TOPIC="$DESC | ai companion narrative generation prior art (storylet / drama manager / arc systems)"
       ```

    b. Dispatch `/ship-research` with the topic. The research-deep command will:
       - Phase 1: scan vault for existing knowledge
       - Phase 2: gap analysis → sub-queries
       - Phase 3: fetch via `scripts.research.research_deep`
       - Phase 4: synthesize delta + write file with AI-first frontmatter

    c. Note where research-deep wrote the result. Typical path:
       ```
       $PROJECT_PATH/Research/<slug>-deep.md
       ```

    d. **Read the result.** Extract the 3-5 most-relevant findings (look for sections like
       "Key findings", "Industry patterns", "Cross-references"). These get cited in:
       - §2 現狀 (when prior art frames our limitations)
       - §3 提案 (when prior art validates / refutes our direction)
       - §3.x Self-FAQ (the sub-agent in Phase 2 sees research too — pass it in as part of the adversarial reviewer prompt)
       - `sources:` frontmatter — add `"[[Research/<slug>-deep]]"` to the list

    e. **If research-deep returns thin / nothing useful**, log a note in §7 開放問題:
       `- External research returned no strong signal — direction is novel or under-researched.`

11. **Render template + draft proposal.** Read `~/.claude/skills/ship-workflow/templates/obsidian/PROPOSAL.md`, substitute:
    - `{{id}}` → `$ID`
    - `{{date}}` → `$(date +%Y-%m-%d)`
    - `{{project}}` → `$PROJECT`
    - `{{slug}}` → `$SLUG`

    Write to `$TARGET`. Then **interactively draft §1-§5** based on the size:

    | Size | What to draft now |
    |---|---|
    | `L` (Full) | §1 / §2 / §3 / §4 / §5 all filled. §3.x filled by step 11b below. |
    | `M` (Lite) | §1 / §3 / §4 / §5 filled. §2 a 2-3 bullet summary linking Architecture. §3.x filled by step 11b below. |
    | (`skip` already handled at step 7) | |

    Drive a short interactive dialogue with the user to fill in:
    - §1 一句話 / 為什麼是現在 / 怎樣算成功
    - §2 引用哪些 Architecture 節點 + 當前限制
    - §3 提案結構(含 mermaid 圖建議)
    - §4 替代方案
    - §5 高層 phase

11b. **Self-FAQ pass** (required for L and M sizes; skip for `skip`-classified). The forcing function of the entire proposal — **the author must answer the questions; the sub-agent only generates them**.

    Dispatch `compound-engineering:ce-adversarial-document-reviewer` with this prompt:

    ```
    You are reviewing a draft Roadmap proposal for ai-companion / FastAPI project ai-eden-service.

    The proposal's R-NNN is $ID, titled "$DESC". Below is the current draft (sections §1-§5).
    Cross-reference these context files: $ARCH_CROSSLINKS, $RESEARCH_NOTES (if any).

    Your task: produce 5-10 sharp questions that an outside reviewer (or the author themselves
    3 months later) would ask about this proposal. Focus on:
      - Unstated assumptions
      - Weak justifications for "why this approach not <obvious alternative>"
      - Missing analysis of failure modes
      - Conflicts with existing Architecture (especially [[Architecture/decisions]] known-limitations)
      - Scope inflation / scope under-coverage

    Return as a numbered list. ONE QUESTION PER ITEM. No answers — just questions.

    Draft proposal:
    ---
    <paste §1-§5 draft here>
    ---
    ```

    When the sub-agent returns 5-10 questions:
    - Read them carefully
    - Pick 3-7 that feel weakest (i.e. you can't immediately answer with confidence)
    - For each picked question:
      - Add it to §3.x as `### Q<n>: <question text>` followed by `**答:** <your answer>`
      - If you cannot honestly answer, copy the question to §7 開放問題 instead
    - Unpicked questions (those you immediately know the answer to with high confidence) can be skipped — they would not change the design

    **Quality check:** if all 3-7 answers feel trivially obvious, the sub-agent didn't push hard enough; re-dispatch with adversarial intensity dial-up:
    "Be harsher. Look for the failure mode I haven't thought of. Don't be polite."

12. **Write file atomically:**

    ```bash
    # Write to .tmp then mv (avoid half-written file)
    mv "$TARGET.tmp" "$TARGET"
    ```

13. **Sync vault → repo mirror:**

    ```bash
    ~/.claude/skills/ship-workflow/lib/sync.sh --force
    ```

14. **Log:**

    ```bash
    echo "| $(date +%Y-%m-%d\ %H:%M) | ship-propose | $ID | draft ($SIZE) | n |" >> docs/learnings/_log.md
    ```

15. **Commit (repo side):**

    ```bash
    git add docs/proposals/ docs/learnings/_log.md
    git commit -m "propose: $ID draft ($SIZE) — $DESC"
    ```

16. **Report:**
    - File path (vault + repo mirror)
    - Size classification (S/M/L)
    - Section coverage (which sections drafted, which left as placeholder for Phase 2)
    - **Next suggested action:**
      - "Review the proposal, then change `status: draft` → `status: accepted` to unlock `/ship-next $ID`."

## Failure modes

- `airos-binding.sh` says no project → run `/ship-init` first
- R-NNN not in ROADMAP → check spelling or run `/ship-roadmap`
- R-NNN in Done section → use `/ship-compound`, not `/ship-propose`
- Active proposal already exists → `--supersede` (Phase 4) or edit existing

## Cross-references

- Spec: `<repo>/docs/superpowers/specs/2026-06-15-ship-propose-design.md`
- Plan: `<repo>/docs/superpowers/plans/2026-06-15-ship-propose.md`
- Template: `~/.claude/skills/ship-workflow/templates/obsidian/PROPOSAL.md`
- Helpers: `~/.claude/skills/ship-workflow/lib/propose-helpers.sh`
