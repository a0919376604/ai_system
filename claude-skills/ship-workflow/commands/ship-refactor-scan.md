---
name: ship-refactor-scan
description: Pocock architecture scan → linked human HTML and AI Markdown reports → picked candidates become 🔜 Next rows for /ship-next
argument-hint: "[<direction: a module, subsystem or pain point>]"
---

# Ship Refactor Scan

Run from the root of the repo to scan. Follow Matt Pocock's vendored method in
`templates/pocock/`, with exactly four changes: C1 scope by hotspots and prior
rejections, C2 split the report: human HTML from the template, AI Markdown,
C3 use CONTEXT.md and vendored design
vocabulary, C4 replace grilling with picking candidates and writing Next rows.

Steps 0–2 are read-only for the scanned repo: no repo files written, no commits,
no dependencies installed. Step 3 uses ship's existing sync and reservation
machinery to refresh `docs/product/` and the gitignored `.claude/.id-reservations`.
Do not run the refactor; `/ship-next` executes the picked rows later.

0. **Resolve paths.**

   Run the block and carry its printed STAMP, REPORT_DIR and ROADMAP values into
   later blocks. Each block runs in a fresh shell. With no vault, save the report
   in the OS temp directory and write no rows.

   ```bash
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/refactor-scan.sh"
   STAMP=$(date +%Y-%m-%d-%H%M)
   ROADMAP=""
   if PROJ_DIR=$("${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/airos-binding.sh" project_path 2>/dev/null) && [ -d "$PROJ_DIR" ]; then
     REPORT_DIR="$PROJ_DIR/Reports"
     mkdir -p "$REPORT_DIR" || exit 1
     if [ -f "$PROJ_DIR/ROADMAP.md" ]; then ROADMAP="$PROJ_DIR/ROADMAP.md"; fi
   else
     REPORT_DIR="${TMPDIR:-/tmp}"
   fi
   (git status --porcelain | command grep -v ' docs/product/' || true) > "${TMPDIR:-/tmp}/refactor-scan-$STAMP.status-before"
   printf 'STAMP=%s\nREPORT_DIR=%s\nROADMAP=%s\n' "$STAMP" "$REPORT_DIR" "$ROADMAP"
   ```

1. **Read the method.**

   Read all four files under `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/pocock/`:
   `improve-codebase-architecture/SKILL.md`, `improve-codebase-architecture/HTML-REPORT.md`,
   `codebase-design/SKILL.md`, and `codebase-design/DEEPENING.md`.
   Run Pocock's `## Process` steps 1 and 2 as written, including spawning a
   sub-agent to explore friction, applying the deletion test, and presenting
   candidate cards with files, problem, solution, benefits, before/after diagrams,
   recommendation strength and a Top recommendation. Apply only these changes:

   - **C1 Scope.** A `<direction>` argument is taken as given; skip the hotspot
     block below in that case. Otherwise `rs_hotspots 6 10` replaces “walk back the
     commit history”. The sub-agent explores the top entries first, and widens
     when they show no friction. Before exploring, read
     `$REPORT_DIR/refactor-scan-rejected.md` if it exists. A listed candidate is
     surfaced again only if its friction is clearly worse, marked as
     “rejected on <date>: <reason>”, the same way upstream treats an ADR conflict.
   - **C2 Split the report.** Write two linked files with the same stem:
     `$REPORT_DIR/refactor-scan-$STAMP.html` for a person and
     `$REPORT_DIR/refactor-scan-$STAMP.ai.md` for AI.
     Copy `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/../templates/refactor-report.html`
     for the human file, replace `{{STEM}}` with `refactor-scan-$STAMP`, and follow
     its comments. Use plain zh-TW: conclusion first, one row per candidate,
     details with stacked big-box pictures and a CSS zoom overlay. Number the
     candidates from 1; keep the `c<N>` sections, links and `z<N>` overlays aligned.
     Keep it self-contained, with no scripts, external URLs or visible design jargon.
     The AI Markdown file starts with
     `Human report: [refactor-scan-$STAMP.html](refactor-scan-$STAMP.html)`.
     Include the C1 hotspot table (score, churn, lines, path; when a direction
     skips hotspots, state that scope instead), then one `## c<N> · <name>` section
     per candidate, using Pocock vocabulary. Preserve every upstream card field:
     Files with line ranges; Problem; Solution; Benefits (locality / leverage /
     tests); Before and After as fenced `mermaid` source; Strength; Dependency
     category (in-process / local-substitutable / ports & adapters / mock);
     Wide refactor? (yes/no); External callers? (yes/no, what); Merge label;
     and an ADR / rejected-before callout when applicable. End with
     `## Top recommendation`, naming the candidate and why.
     Map Strong → 值得做, Worth exploring → 可考慮, Speculative → 待觀察 in
     the human file. Size (小 / 中 / 大) is Claude's estimate: write it in both
     files and label it as an estimate in the AI file. Compute each merge label
     with `rs_merge_label HEAD <candidate files>` in the scanned repo, and write
     that exact 自動合併 / 要人審 output into both files.
   - **C3 Vocabulary.** The repo's `CONTEXT.md` stands in for `GLOSSARY.md` and is
     read-only here. Read ADRs from `docs/adr/` when present. “Call the Skill tool
     with codebase-design” means: read the vendored `codebase-design/SKILL.md`
     and `DEEPENING.md`. Use their architecture terms and CONTEXT.md domain names.
   - **C4 No grilling here.** Upstream step 3 is replaced by steps 2–3 below.
     Do NOT propose interfaces yet. Grilling belongs to `/ship-next` Phase 3.

   ```bash
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/refactor-scan.sh"
   rs_hotspots 6 10
   ```

   After writing both files, run this second block:

   ```bash
   STAMP="${STAMP:?set STAMP to the value step 0 printed}"
   REPORT_DIR="${REPORT_DIR:?set REPORT_DIR to the value step 0 printed}"
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/refactor-scan.sh"
   rs_report_check "$REPORT_DIR/refactor-scan-$STAMP" || exit 1
   rs_report_shot "$REPORT_DIR/refactor-scan-$STAMP.html" "${TMPDIR:-/tmp}/refactor-scan-$STAMP.png"
   rs_report_shot "$REPORT_DIR/refactor-scan-$STAMP.html" "${TMPDIR:-/tmp}/refactor-scan-$STAMP-z1.png" z1
   ```

   Fix every `rs_report_check` line before going on. Read both PNGs and fix
   anything unreadable: the list must end above the red 844 px line, and picture
   labels must be legible. If Chrome is unavailable, report its skip notice.
   Then open the human file with `open` (or `xdg-open`).

2. **Pick.**

   Ask “Which numbered candidates should become Roadmap items?” Offer the
   report's Top recommendation as the recommended answer; several may be picked.
   For a candidate the operator rejects with a reason a future scan needs, append
   one line to `$REPORT_DIR/refactor-scan-rejected.md`:
   `- <YYYY-MM-DD> · <candidate name> (<files>) — <reason>`.
   Apply upstream's ADR test: record a load-bearing reason a future explorer
   needs to avoid re-suggesting it; skip ephemeral “not now” and self-evident
   reasons. Do not edit CONTEXT.md or write ADRs during this scan.

3. **Write rows.**

   Only when a vault ROADMAP exists, write one TSV line per row, in reading order,
   to `$REPORT_DIR/refactor-scan-$STAMP.rows.tsv`. Keep it next to the report as
   the record of what was written. The six fields are:
   `chain<TAB>card<TAB>description<TAB>summary<TAB>outcome<TAB>reason`.
   `chain` is `new` for the start of a group, `after` for a row following the one
   above. `card` is the report card number N. `summary` is one zh-TW sentence for
   a person. Fields contain no tabs or newlines; retain the final tab when reason
   is empty. An ordinary candidate becomes one row.

   A wide refactor (Pocock `to-tickets`) is a single mechanical change whose
   blast radius breaks many call sites at once, so no single slice lands green.
   Make three rows: expand (add the new form beside the old), migrate call sites,
   contract (delete the old form), with `new` / `after` / `after`. Rows 2 and 3
   name the previous ID with 「接在 R-x 之後做」. Descriptions use CONTEXT.md and
   codebase-design vocabulary. Give a one-way reason only when the candidate
   changes something external callers depend on: an HTTP route or payload, a DB
   schema, or a function another repo imports. The helper appends the guardrails
   to every outcome and `Door: one-way — <reason>` only when a reason is given.

   Set STAMP to the value step 0 printed. Re-resolve paths, sync before reserving
   IDs, write the rows, then mirror again (the `--adhoc` pattern). If sync stops
   on divergence (R-087), show its message as is; no rows are written.

   ```bash
   STAMP="${STAMP:?set STAMP to the value step 0 printed}"
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/refactor-scan.sh"
   if ! PROJ_DIR=$("${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/airos-binding.sh" project_path 2>/dev/null) || [ ! -d "$PROJ_DIR" ]; then
     printf '%s\n' 'no vault ROADMAP — report only'
     exit 0
   fi
   ROADMAP="$PROJ_DIR/ROADMAP.md"
   ROWS="$PROJ_DIR/Reports/refactor-scan-$STAMP.rows.tsv"
   if [ ! -f "$ROADMAP" ]; then
     printf '%s\n' 'no vault ROADMAP — report only'
     exit 0
   fi
   if [ ! -f "$ROWS" ]; then
     printf 'ERROR: rows file not found: %s\n' "$ROWS" >&2
     exit 1
   fi
   "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/sync.sh" --force || exit 1
   rs_write_rows "$ROADMAP" "refactor-scan-$STAMP" < "$ROWS" || exit 1
   "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/sync.sh" --force || exit 1
   ```

4. **Report back.**

   Print both report paths (`$REPORT_DIR/refactor-scan-$STAMP.html` and
   `$REPORT_DIR/refactor-scan-$STAMP.ai.md`), each row written (ID and description,
   from step 3), and
   the rejected lines appended. Show the scanned repo's `git status --porcelain`;
   compare it with step 0, excluding `docs/product/`.

   ```bash
   STAMP="${STAMP:?set STAMP to the value step 0 printed}"
   BEFORE="${TMPDIR:-/tmp}/refactor-scan-$STAMP.status-before"
   AFTER=$(git status --porcelain | command grep -v ' docs/product/' || true)
   git status --porcelain
   if [ -f "$BEFORE" ] && [ "$(cat "$BEFORE")" = "$AFTER" ]; then
     printf '%s\n' 'repo unchanged outside docs/product/'
   else
     printf '%s\n' 'WARN: repo status differs outside docs/product/'
     diff "$BEFORE" <(if [ -n "$AFTER" ]; then printf '%s\n' "$AFTER"; fi) || true
   fi
   ```
