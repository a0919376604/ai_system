---
name: ship-explain
description: Generate (or refresh) a plain-language explainer note for a ROADMAP row
argument-hint: "<R-NNN> | --all-now | --force-refresh <R-NNN>"
discord-visible: true
---

# /ship-explain

You are generating a plain-language **Roadmap Explainer Note** for a ROADMAP row. The reader is a product owner with limited domain knowledge — your note must let them understand the row in 10-20 lines without opening the full proposal.

## Arguments

- `<R-NNN>` — single-row mode. Generate (or refresh) the explainer for one row.
- `--all-now` — bulk mode. Generate explainers for every "Now" item that doesn't yet have one. Skip rows that already have `↳ explain:`. (Phase 2, see step 7.)
- `--force-refresh <R-NNN>` — overwrite an existing explainer for a row. Print a diff before writing.

## Steps (single-row mode)

1. **Resolve paths:**
   ```bash
   ROADMAP_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)/ROADMAP.md"
   PROJECT_PATH="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path)"
   PROJECT_NAME="$(~/.claude/skills/ship-workflow/lib/airos-binding.sh project_name)"
   NOTES_DIR="$PROJECT_PATH/Roadmap-Notes"
   mkdir -p "$NOTES_DIR"
   ```

2. **Extract row context from ROADMAP.md.** Grep for the line containing `**${ID}**` (or `**${ID} (epic)**`). Capture:
   - Full row text (description + effort/confidence/status markers)
   - Existing `↳ done when:` annotation if any
   - Parent epic ID if `${ID}` matches `R-NNN.M`

3. **Derive slug.** From the row description, derive a kebab-case English slug, 3-5 words. Examples:
   - "Wire SceneEngine into dialogue.py..." → `wire-scene-engine`
   - "Migrate runway_atelier 為 canary world" → `migrate-runway-canary`
   - Format: `R-NNN[.M]-<slug>` (full filename stem)

4. **Refuse refresh unless `--force-refresh`.** If `$NOTES_DIR/${ID}-*.md` already exists AND the invocation didn't pass `--force-refresh`, exit with:
   ```
   Explainer already exists at <path>. Use /ship-explain --force-refresh ${ID} to rewrite.
   ```

5. **Gather context sources.** Read (in priority order, fail-soft if absent):
   - **Must-read**: matching proposal at `$PROJECT_PATH/Proposals/*-${PARENT_OR_ID}-*-proposal.md`. Extract §1 (success criterion / 為什麼), §3 (architecture summary), §5 (phase exit conditions) for *this* `${ID}`'s phase if R-NNN.M.
   - **Must-read**: `$PROJECT_PATH/Architecture/overview.md` (high-level module graph).
   - **Should-read**: any `$PROJECT_PATH/Architecture/modules/*.md` or `$PROJECT_PATH/Architecture/ai-flows/*.md` whose name appears in the row description or proposal.
   - **Should-read**: sibling explainers in `$NOTES_DIR/${PARENT}-*.md` (same epic) — copy voice + reuse glossary entries.
   - **May-read**: `$PROJECT_PATH/Decisions/D-*.md` if the row mentions `D-NNN`.

6. **Draft the note in zh-TW.** Use the template at `~/.claude/skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md`. Substitute placeholders:
   - `{{date}}` → today (YYYY-MM-DD)
   - `{{id}}` → `${ID}`
   - `{{parent}}` → parent R-NNN if child, else `null`
   - `{{project}}` → `${PROJECT_NAME}`
   - `{{proposal_ref}}` → wikilink to proposal file (e.g. `[[Proposals/2026-06-15-R-001-...]]`) or `null`
   - `{{one_liner}}` → one sentence, plain-language, ≤ 30 字
   - `{{plain_what}}` → 3-5 sentence prose. **Rewrite, do not copy from proposal.**
   - `{{role_in_epic}}` / `{{cost_if_skipped}}` / `{{user_visible_change}}` → one line each
   - `{{blocked_by}}` / `{{unblocks}}` / `{{siblings}}` → wikilinks where available
   - `{{glossary_rows}}` → markdown table rows; entries for every domain term you used in `{{plain_what}}` that the reader might not know
   - `{{deeper_reading_links}}` → bullet list of wikilinks (proposal §, Architecture modules)

   **Voice rule (critical):** First occurrence of any domain noun gets an inline gloss. Example: instead of "SceneEngine selects next scene", write "SceneEngine (規則層,負責決定下一個 scene 要演哪個) 在這步被接到 prompt 路徑上".

   **Section scaling**: per spec §4.1.1, S-effort rows may leave `為什麼要做這步`, `前後關係`, `用到的 domain 名詞` empty (write a single `—`). M/L rows fill all sections.

7. **Write atomically:**
   ```bash
   NOTE_PATH="$NOTES_DIR/${ID}-${slug}.md"
   # Write to .tmp, then mv
   ```

8. **Sync vault → repo:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/sync.sh --force
   ```

9. **Inject annotation into ROADMAP row:**
   ```bash
   ~/.claude/skills/ship-workflow/lib/roadmap-insert.sh "$ROADMAP_PATH" "${ID}" \
     --inject-explain "Roadmap-Notes/${ID}-${slug}"
   ~/.claude/skills/ship-workflow/lib/sync.sh --force   # re-sync after row edit
   ```

10. **Print summary to terminal:**
    ```
    📒 Explainer drafted: <NOTE_PATH>

    一句話總結
      {{one_liner}}

    為什麼要做這步
      {{role_in_epic}}

    Read full? [Y/n/edit]
    ```

11. **Handle user response:**
    - `Y` (default): print the full markdown body.
    - `edit`: open `$NOTE_PATH` in `${EDITOR:-vi}`.
    - `n`: exit.

12. **Log + commit (repo side):**
    ```bash
    echo "| $(date +%Y-%m-%d\ %H:%M) | ship-explain | ${ID} | $(basename $NOTE_PATH) | n |" >> docs/learnings/_log.md
    git add docs/product/ROADMAP.md docs/roadmap-notes/ docs/learnings/_log.md
    git commit -m "explain: ${ID} ${slug}"
    ```

## Failure modes

- Row `${ID}` not found in ROADMAP.md → ERROR with hint "Did you mean R-NNN.M?"
- Neither proposal nor Architecture/overview.md available → still produce minimal note (一句話總結 + 這步在做什麼 + 深入閱讀); leave 為什麼 section with a hint "需要 /ship-propose 後 refresh"
- `--force-refresh` without arg → ERROR
