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

2. **Read** `docs/product/ROADMAP.md` "🔥 Now" section. Parse R-NNN items not marked `✅`. **Detect special states:**
   - `⚠️ R-NNN` — flagged for decomposition by `/ship-roadmap`. Treat as actionable: when picking, the FIRST action is to offer decomposition (see step 4a).
   - `R-NNN (epic)` — already decomposed. The epic itself is NOT directly actionable; only its `R-NNN.M` children are. When ranking, skip the epic and rank its children individually.
   - `R-NNN.M` — child of an epic. Treat as a regular item.

3. **Rank** by (in tiebreaker order, top down):
   - Explicit `impact=high` markers first
   - Dependencies satisfied (no unresolved `dep:` references)
   - `adhoc-inserted=true` items deprioritized vs planned items (planned > emergency)
   - **Children of the same epic ordered ascending by `.M`** (R-014.1 before R-014.2 before R-014.3). The decompose brainstorm produces children in intended sequence; honor that order. Don't pick R-014.3 unless R-014.1 and R-014.2 are already done.
   - For top-level R-NNN when all else ties: ascending by NNN (earlier-decided items go first). Weak preference — usually impact/dependency already broke the tie.
   - **Epics themselves are not in the rank** — their children are. Skip any line containing `(epic)` when iterating "Now".

4. **Present top 1-2** to the user, get confirmation. Capture the chosen `R-NNN` (or `R-NNN.M`) and `<slug>`.

4a. **Decompose-first if ⚠️ flagged.** If the chosen item carries the `⚠️` marker:
    ```
    R-NNN was flagged as too big by /ship-roadmap.
    Decompose it now into 2-5 children before brainstorming the work itself? [Y/n]
    ```
    - **Y** (default): same flow as `/ship-roadmap` step 7 — short decompose brainstorm. **Every child MUST have action-verb description + done-when criterion** before being inserted (this is what makes "R-NNN.M" entries readable later; reject vague descriptions like "improve X" — push back for refinement). For each sub-item, capture `desc` (imperative verb + object), `done_when` (one observable success criterion), and optional `est`. Then allocate + insert:
      ```bash
      # Convert parent to epic
      ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" R-NNN --mark-epic

      # For each child gathered above:
      CHILD_ID=$(~/.claude/skills/ship-workflow/lib/id-gen.sh roadmap --child R-NNN --reserve)
      ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "$CHILD_ID" "$desc" \
        --child R-NNN --done-when "$done_when" ${est:+--est "$est"}
      ```
      Then ask "Pick one child to brainstorm now?" and continue with that child as the chosen item. The brainstorm for the picked child should start from its `done when:` annotation as the AC #1.
    - **n**: strip the ⚠️ (acknowledge as fine-as-is) and continue with the original R-NNN to brainstorming. If the item lacks a `↳ done when:` annotation, prompt the user for one now and inject it via a manual edit of ROADMAP.md before continuing — brainstorming without a done-when is allowed but produces weaker specs.

4b. **Explainer pre-flight.** Before entering brainstorm:
    1. Search ROADMAP row for `${ID}` and extract any `↳ explain: [[Roadmap-Notes/<slug>]]` annotation.
    2. **Branch on presence:**
       - **Annotation present**: read `$PROJECT_PATH/Roadmap-Notes/<slug>.md`. Print to terminal:
         ```
         📒 Loaded explainer: <slug>

         一句話總結
           <content of ## 一句話總結>

         為什麼要做這步
           <content of ## 為什麼要做這步>

         Read full note before brainstorm? [Y/n]
         ```
         If `Y`, print the entire note body. Then continue.
       - **Annotation missing**: ask user:
         ```
         No explainer for ${ID}. Run /ship-explain ${ID} now? [Y/n]
         ```
         If `Y`: invoke `/ship-explain ${ID}` inline (per Task 5 single-row mode), then continue with the freshly-generated explainer as context.
         If `n`: proceed to brainstorm. Warn: "Proceeding without explainer; brainstorm may lack domain context".
    3. When entering brainstorming below (step 6), inject the explainer's `## 這步在做什麼` and `## 為什麼要做這步` sections into the initial brainstorm context alongside any proposal §1-§7 already loaded.

5. **Skip to "Common: Enter brainstorming" below** with the (possibly child) chosen item.

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

### Common pre-step: Proposal check

After picking the R-NNN (Branch A step 5 or Branch B), but **before** entering brainstorming:

```bash
PROJECT_PATH=$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)
PROPOSALS_DIR="$PROJECT_PATH/Proposals"
PROPOSAL_FILE=$(find "$PROPOSALS_DIR" -name "*-${ID}-*-proposal.md" 2>/dev/null | head -1)
```

Three branches:

1. **Proposal exists AND `status: accepted`**:
   - Read the proposal
   - Load §1-§7 as **brainstorm starting context** (problem is already framed; brainstorm focuses on design choices within the proposal's bounds)
   - Tell user: "Loaded accepted proposal $(basename $PROPOSAL_FILE) as brainstorm context."

2. **Proposal exists but `status` ∈ {draft, in-review}**:
   - Tell user: "Proposal exists at $PROPOSAL_FILE but status=$STATUS. Accept it first or proceed without."
   - Ask: `[A] accept now + use it / [P] proceed without / [N] cancel`
   - If `A`: edit frontmatter `status: accepted`, sync, log, then load as brainstorm context
   - If `P`: proceed to brainstorming as if no proposal

3. **No proposal AND R-NNN appears big** (EFFORT extracted from row contains `L`, OR description mentions ≥2 module names):
   - Ask: `No proposal for $ID. Run /ship-propose first? [Y/n]`
   - If `Y`: tell user to run `/ship-propose $ID`, exit. Do not continue to brainstorm.
   - If `n`: proceed to brainstorming with cold start

4. **No proposal AND R-NNN appears small**: proceed straight to brainstorming (skip prompt — the smallness is the design signal that no proposal is needed).

### Common: Enter brainstorming

6. **Invoke `superpowers:brainstorming`** with context: spec target = `docs/specs/${ID}-${slug}.md`, project = `<project_name>`. If a proposal was loaded above, include its §1-§7 in the initial context.

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
