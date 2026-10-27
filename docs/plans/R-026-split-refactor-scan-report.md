# R-026 Split the refactor-scan report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/ship-refactor-scan` writes two linked reports with one stem: a phone-first human
HTML (mockup option B: conclusion first, tap for details) and an AI Markdown file. Both are
gated by `rs_report_check`, and the human one is looked at through `rs_report_shot`.

**Architecture:**
- **`lib/refactor-scan.sh`** gains `rs_merge_label`, `rs_report_check` and
  `rs_report_shot`. `rs_write_rows` changes its links.
- **New template** `templates/refactor-report.html` is the human layout.
- **`commands/ship-refactor-scan.md`** has C2 rewritten, plus small step 3 and step 4
  edits.

**Tech Stack:** bash and zsh (libs are sourced from Claude Code's Bash tool, which runs zsh),
awk, grep, bats, self-contained HTML/CSS.

**Spec:** `docs/specs/R-026-split-refactor-scan-report.md`. Read it first. §3 is the design,
§4 the acceptance rows. AC-8 and AC-9 are not tasks here; the ship's operator runs them
after this plan.

## Global Constraints
- **Paths:** everything lives under `claude-skills/ship-workflow/`. Do not modify anything
  under `~/.claude/` or the Obsidian vault. You may read `/tmp/r026-mockup.html`, a copy of
  the chosen mockup.
- **Libs:**
  - Locate siblings with `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}`. No
    `BASH_SOURCE`.
  - Use no arrays: zsh is 1-based.
  - Every new function behaves the same sourced under bash and zsh. Write functions with
    side effects (`cd`, `trap`, sourcing) as subshell functions, `name() ( … )`, the way
    `rs_hotspots` is.
- **Jargon words,** matched case-insensitively as whole words under `LC_ALL=C`, so CJK bytes
  count as word boundaries: `module interface implementation depth deep shallow seam adapter
  leverage locality`.
- **Exact strings:**
  - merge labels: `自動合併`, `要人審`;
  - row links: description suffix `（報告：Reports/<stem>.ai.md#c<N>）`, explain suffix
    `（看報告：Reports/<stem>.html#c<N>）`;
  - `rs_report_check` stderr prefix: `rs_report_check: `;
  - `rs_report_shot` skip notice: `rs_report_shot: Chrome not found — skipped`.
- **Tests:** run from `claude-skills/ship-workflow` with `bats tests/<file>.bats`. The known
  failure in a linked worktree is `cwd-guard: exits 0 when not in a git repo at all`; ignore
  that one only.

## Review Focus
1. **Paths with spaces.** The vault dir is `…/10 Projects/…`.
   - `rs_report_check` must quote everything.
   - `rs_report_shot` must percent-encode at least space, `%`, `#` and `?` in the file URL it
     puts in the iframe `src`.

   Tests in Tasks 2 and 3 use a stem under a directory with a space.
2. **Jargon only in visible text.** `class="deep"` and `.seam {}` in `<style>` must not
   trip rule 7, while `Deep module` in a `<p>` must. Test in Task 2.
3. **Duplicate anchors.** The hero and its list row both link `#c1`. Rule 4 compares sets,
   so repeated `href="#c1"` is fine. Test in Task 2.
4. **zsh.** `rs_report_check` and `rs_merge_label` give the same result sourced in zsh. Test
   in Task 2, skipped when zsh is missing.
5. **A stem passed with `.html`.** `rs_write_rows "$RM" x.html` and `rs_write_rows "$RM" x`
   write identical rows. Test in Task 4.

---

### Task 1: `rs_merge_label`

**Files:** Modify `claude-skills/ship-workflow/lib/refactor-scan.sh`; Test
`claude-skills/ship-workflow/tests/test_refactor-scan.bats`.

**Interfaces:**
- Consumes: `_sn_one_way_paths <ref>` and `_sn_glob_match <glob> <path>` from `lib/ship-next.sh`.
- Produces: `rs_merge_label <base-ref> <path>...` → stdout `要人審` or `自動合併`, exit 0.

- [x] **Step 1: Failing test** (AC-1). In a scratch repo (`mkrepo`), commit
  `.claude/ship-config.yml` with:

```yaml
merge_mode: mr
one_way_paths:
  - backend/app/domain/line_service.py   # LINE
  - backend/app/domain/push_*.py
```

```bash
@test "rs_merge_label: one_way_paths at the base ref decide the label (AC-1)" {
  mkrepo
  mkdir -p .claude
  printf '%s\n' 'merge_mode: mr' 'one_way_paths:' '  - backend/app/domain/line_service.py   # LINE' '  - backend/app/domain/push_*.py' > .claude/ship-config.yml
  git add .claude/ship-config.yml && git commit -qm cfg
  [ "$(rs_merge_label HEAD backend/app/api/admin_dashboard.py)" = "自動合併" ]
  [ "$(rs_merge_label HEAD backend/app/domain/push_x.py)" = "要人審" ]
  [ "$(rs_merge_label HEAD a.py backend/app/domain/line_service.py)" = "要人審" ]
  [ "$(rs_merge_label HEAD)" = "自動合併" ]
  git rm -q .claude/ship-config.yml && git commit -qm rm
  [ "$(rs_merge_label HEAD backend/app/domain/line_service.py)" = "自動合併" ]
}
```

- [x] **Step 2:** Run it and expect FAIL.
- [x] **Step 3:** Implement it as a subshell function that sources
  `${SHIP_LIB:-…}/ship-next.sh`, loops over `_sn_one_way_paths "$1"` × paths with
  `_sn_glob_match`, and prints the label.
- [x] **Step 4:** Run it and expect PASS. Then run the whole `test_refactor-scan.bats` to
  confirm R-025's tests still pass.
- [x] **Step 5:** Commit `feat(R-026): rs_merge_label — 自動合併 / 要人審 from one_way_paths`.

### Task 2: `rs_report_check`

**Files:** Modify `lib/refactor-scan.sh`; Test `tests/test_refactor-scan.bats`.

**Interfaces:**
- Produces: `rs_report_check <stem>`, where `<stem>` is a path without extension. It reads
  `<stem>.html` and `<stem>.ai.md`.
  - When rules 1–8 of spec §3.3 hold: exit 0, no output.
  - Otherwise: exit 1, one `rs_report_check: <rule>: <detail>` line per broken rule on
    stderr. `<rule>` is one of `missing`, `script`, `external-url`, `anchors`, `ai-sections`,
    `cross-link`, `jargon`, `zoom`.
  - The cross-link rule compares **basenames**: the HTML must contain
    `<basename>.ai.md`, and the `.ai.md` must contain `<basename>.html`.

- [x] **Step 1: Failing tests** (AC-3 and Review Focus 1–4).
  - Add a helper `good_pair <stem>` that writes a minimal valid pair:
    - **HTML:** `<header id="top">`; a hero `<a href="#c1">`; a row `<a href="#c1">`;
      `<section id="c1">` with `<a href="#z1">` and `<div id="z1" class="zoom">`; a link to
      `<basename>.ai.md`; a `<style>.deep{} .seam{}</style>`; an element
      `<div class="deep">`.
    - **AI file:** `## c1 · Deepen the ticket population` and a link to `<basename>.html`.
  - Use a stem under `"$SCRATCH/10 Projects/Reports/refactor-scan-T"`.

```bash
@test "rs_report_check: a valid pair passes silently; jargon in style/attributes is fine" {
  good_pair "$S"; run --separate-stderr rs_report_check "$S"
  [ "$status" -eq 0 ]; [ -z "$output" ]; [ -z "$stderr" ]
}
@test "rs_report_check: each broken rule exits 1 and names itself (AC-3)" {
  for case in script external-url anchors ai-sections cross-link jargon zoom missing; do
    good_pair "$S"; break_rule "$case" "$S"
    run --separate-stderr rs_report_check "$S"
    [ "$status" -eq 1 ] || { echo "passed: $case"; return 1; }
    [[ "$stderr" == *"rs_report_check: $case:"* ]] || { echo "wrong rule for $case: $stderr"; return 1; }
  done
}
@test "rs_report_check: same verdicts sourced under zsh" {
  command -v zsh >/dev/null || skip "zsh not installed"
  good_pair "$S"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_report_check '$S'"
  [ "$status" -eq 0 ]
  break_rule jargon "$S"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_report_check '$S'"
  [ "$status" -eq 1 ]
}
```

  `break_rule <case> <stem>` edits the pair for one case:

  | case | edit |
  |---|---|
  | `script` | add `<script>x</script>` |
  | `external-url` | add `<a href="https://cdn.example/x.js">` |
  | `anchors` | add `<section id="c3">` with no row |
  | `ai-sections` | delete the `## c1 ·` line from the `.ai.md` |
  | `cross-link` | remove the `.ai.md` link from the HTML |
  | `jargon` | add `<p>Deep module</p>` |
  | `zoom` | add `<div id="z2" class="zoom">` |
  | `missing` | `rm` the `.ai.md` |

- [x] **Step 2:** Run them and expect FAIL.
- [x] **Step 3: Implement.**
  - Read each file once.
  - To get the visible text: drop `<style>…</style>` and `<!--…-->` (multi-line), then every
    `<…>` tag, with one awk program that slurps the file.
  - Rule 4: extract the `id="c[0-9]+"` and `href="#c[0-9]+"` number sets with
    `grep -o … | sort -nu`. They must be equal and exactly `1..N`.
  - Rule 5: extract the `^## c[0-9]+ · ` set from the `.ai.md` and compare it with the HTML
    set.
  - Rule 8: every `z<N>` number must be in the `c` set.
  - Collect every broken rule, then exit once.
- [x] **Step 4:** Run the file and expect PASS.
- [x] **Step 5:** Commit `feat(R-026): rs_report_check — mechanical gate for the two reports`.

### Task 3: The human template + `rs_report_shot`

**Files:** Create `claude-skills/ship-workflow/templates/refactor-report.html`; Modify
`lib/refactor-scan.sh`; Test `tests/test_refactor-scan.bats`.

**Interfaces:**
- **The template.** A self-contained file following spec §3.1 blocks 1–6.
  - Its CSS is taken from `/tmp/r026-mockup.html`: the `.hr`, `.hero`, `.li`, `.chip*`,
    `.fig`, `.bx*`, `.arr`, `.row2`, `.zoom`/`.zoomed`, `.p` and `.ailink` rules, adapted
    from the phone frame to a full page: `body { max-width: 480px; margin: 0 auto; }`.
  - Add `.zoom { display:none; position:fixed; inset:0; overflow:auto; background:rgba(15,23,42,.96); padding:16px; z-index:10 } .zoom:target { display:block }`
    and `* { overflow-wrap: anywhere }`.
  - Use the placeholder `{{STEM}}` wherever the stem's basename goes, e.g. `{{STEM}}.ai.md`.
  - Write example content for **one** candidate (c1), using the line-oa case shown in
    mockup option B, so the rendered template looks real. Include `<!-- repeat per candidate -->`
    comments.
  - It has no `<script>`, no `http`, and no jargon in visible text.
- **`rs_report_shot <html> <png> [<fragment>]`:** spec §3.3, Seams row "report shot".
  - The harness `src` is `file://` plus the absolute path, with `%` `→%25`, space `→%20`,
    `#` `→%23` and `?` `→%3F` encoded; `#<fragment>` is appended unencoded.
  - Chrome args: `--headless=new --hide-scrollbars --allow-file-access-from-files --virtual-time-budget=3000 --window-size=<w>,<h> --screenshot=<png> file://<harness>`.
    `<w>,<h>` is `420,6000` for the whole page, or `420,900` with a fragment.
  - The harness:
    - whole page: `<iframe style="width:390px;height:6000px;border:0" src="…">` with a
      `<div style="position:absolute;top:844px;left:0;width:390px;border-top:2px solid red">`
      over it;
    - with a fragment: `width:390px;height:844px`.

- [x] **Step 1: Failing tests** (AC-2, AC-4).

```bash
@test "template: with {{STEM}} filled and a matching .ai.md it passes rs_report_check (AC-2)" {
  T="$SHIP_SKILL_ROOT/templates/refactor-report.html"; [ -f "$T" ]
  ! grep -qiE '<script|https?://' "$T"
  sed 's/{{STEM}}/refactor-scan-T/g' "$T" > "$S.html"
  n=$(grep -oE 'id="c[0-9]+"' "$S.html" | sort -u | wc -l | tr -d ' ')
  { echo '[human](refactor-scan-T.html)'; for i in $(seq 1 "$n"); do echo "## c$i · x"; done; } > "$S.ai.md"
  run --separate-stderr rs_report_check "$S"
  [ "$status" -eq 0 ] || { echo "$stderr"; return 1; }
}
@test "rs_report_shot: 390px iframe harness, fold line, fragment mode, skip without Chrome (AC-4)" {
  mkdir -p "$SCRATCH/bin"
  cat > "$SCRATCH/bin/chrome" <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in --screenshot=*) out="${a#--screenshot=}";; file://*) h="${a#file://}";; esac; done
cp "$h" "$SCRATCH_HARNESS"; : > "$out"
SH
  chmod +x "$SCRATCH/bin/chrome"
  export RS_CHROME="$SCRATCH/bin/chrome" SCRATCH_HARNESS="$SCRATCH/harness.html"
  echo '<p>x</p>' > "$SCRATCH/10 Projects/x.html"
  rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/out.png"
  [ -f "$SCRATCH/out.png" ]
  grep -q 'width:390px;height:6000px' "$SCRATCH/harness.html"
  grep -q 'top:844px' "$SCRATCH/harness.html"
  grep -qF '10%20Projects/x.html"' "$SCRATCH/harness.html"
  rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/z.png" z1
  grep -q 'width:390px;height:844px' "$SCRATCH/harness.html"
  grep -qF 'x.html#z1"' "$SCRATCH/harness.html"
  RS_CHROME=/nonexistent run --separate-stderr rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/n.png"
  [ "$status" -eq 0 ]; [[ "$stderr" == *"rs_report_shot: Chrome not found — skipped"* ]]
}
```

  Create `$SCRATCH/10 Projects/Reports` in `setup` for these tests. Assert that the harness
  temp dir is removed by capturing its path through the stub (`dirname "$h"`) and checking
  `[ ! -d … ]` after the call.
- [x] **Step 2:** Run them and expect FAIL.
- [x] **Step 3:** Write the template. Implement `rs_report_shot` as a subshell function with
  `trap 'rm -rf "$dir"' EXIT`. If `[ -x "$chrome" ]` is false, print the notice and exit 0.
  A non-zero Chrome exit, or no PNG afterwards, means exit 1.
- [x] **Step 4:** Run the file and expect PASS. Then, if real Chrome exists, render the
  filled template once with `rs_report_shot` as a smoke check and note it in the execution
  log. Do not assert on pixels.
- [x] **Step 5:** Commit `feat(R-026): phone-first report template + rs_report_shot`.

### Task 4: `rs_write_rows` links both files

**Files:** Modify `lib/refactor-scan.sh` (`rs_write_rows`); Modify
`tests/test_refactor-scan.bats` lines 125–163 and `tests/test_command-blocks.bats:729`.

**Interfaces:**
- Produces: `rs_write_rows <roadmap> <stem-or-basename>`. `stem="${2%.html}"`.
  - The description suffix is `（報告：Reports/${stem}.ai.md#c${card}）`.
  - The summary suffix is `（看報告：Reports/${stem}.html#c${card}）`.
  - Everything else is unchanged.

- [x] **Step 1: Update the R-025 assertions,** a behaviour the spec changes (AC-5):
  - every expected `（報告：Reports/x.html#cN）` becomes `（報告：Reports/x.ai.md#cN）`, where
    the call still passes `x.html`;
  - add `grep -F '**R-004**' -A1 "$RM" | grep -qF '↳ explain: sa（看報告：Reports/x.html#c1）'`;
  - add a test calling with `x` and with `x.html` into two fresh ROADMAPs and asserting the
    files are identical apart from IDs (Review Focus 5). Easiest: two scratch repos with the
    same mirror, then `cmp`.
  - In `test_command-blocks.bats:729`, expect `（報告：Reports/refactor-scan-T.ai.md#c1）`
    and also `（看報告：Reports/refactor-scan-T.html#c1）` (AC-6).
- [x] **Step 2:** Run them and expect FAIL.
- [x] **Step 3:** Implement. The summary is field 3 of the temp line; append its suffix
  where the description's is built.
- [x] **Step 4:** Run `bats tests/test_refactor-scan.bats tests/test_command-blocks.bats -f 'refactor-scan|rs_'`
  and expect PASS.
- [x] **Step 5:** Commit `feat(R-026): rows link the AI report, explain links the human one`.

### Task 5: The command file

**Files:** Modify `claude-skills/ship-workflow/commands/ship-refactor-scan.md`; Test
`tests/test_command-blocks.bats`.

- [x] **Step 1: Failing test** (AC-7).

```bash
@test "ship-refactor-scan: C2 writes and checks both reports; step 3 passes the stem (AC-7)" {
  F="$SHIP_SKILL_ROOT/commands/ship-refactor-scan.md"
  for s in 'refactor-scan-$STAMP.ai.md' 'templates/refactor-report.html' 'rs_report_check' 'rs_report_shot' 'rs_merge_label HEAD'; do
    grep -qF "$s" "$F" || { echo "missing: $s"; return 1; }
  done
  block ship-refactor-scan.md '^3\. \*\*Write rows' '^4\. \*\*Report back' | grep -qF 'rs_write_rows "$ROADMAP" "refactor-scan-$STAMP" <'
  block ship-refactor-scan.md '^1\. \*\*Read the method' '^2\. \*\*Pick' | grep -qF 'rs_report_check "$REPORT_DIR/refactor-scan-$STAMP"'
}
```

- [x] **Step 2:** Run it and expect FAIL.
- [x] **Step 3: Edit the command.**
  - **Intro:** C2 now says "split the report: human HTML from the template, AI Markdown".
  - **C2 bullet:** replace it with spec §3.5's text:
    - the two files with the same stem;
    - the human file copied from `templates/refactor-report.html` with `{{STEM}}` replaced,
      following its comments;
    - the AI file per spec §3.2, with the list of fields;
    - the strength mapping (Strong → 值得做, Worth exploring → 可考慮, Speculative → 待觀察);
    - size as Claude's estimate;
    - the merge label from `rs_merge_label HEAD <candidate files>`, written into both files.
  - **A second bash block at the end of step 1:**

```bash
STAMP="${STAMP:?set STAMP to the value step 0 printed}"
REPORT_DIR="${REPORT_DIR:?set REPORT_DIR to the value step 0 printed}"
source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/refactor-scan.sh"
rs_report_check "$REPORT_DIR/refactor-scan-$STAMP" || exit 1
rs_report_shot "$REPORT_DIR/refactor-scan-$STAMP.html" "${TMPDIR:-/tmp}/refactor-scan-$STAMP.png"
rs_report_shot "$REPORT_DIR/refactor-scan-$STAMP.html" "${TMPDIR:-/tmp}/refactor-scan-$STAMP-z1.png" z1
```

  - **The prose after that block:**
    - fix every `rs_report_check` line before going on;
    - Read both PNGs: the list ends above the red 844 px line, and picture labels are
      legible;
    - then `open` (or `xdg-open`) the human file.
  - **Step 3:** `rs_write_rows "$ROADMAP" "refactor-scan-$STAMP" < "$ROWS" || exit 1`.
  - **Step 4:** prose prints both report paths.
- [x] **Step 4:** Run `bats tests/test_command-blocks.bats` and expect all PASS.
- [x] **Step 5:** Commit `feat(R-026): /ship-refactor-scan writes, checks and shoots both reports`.

### Task 6: Full suite
- [x] **Step 1:** `cd claude-skills/ship-workflow && bats tests/`. Everything passes except
  the known cwd-guard failure. The baseline is 737/738; the new count is that plus this
  plan's tests.
- [x] **Step 2:** Fix any other failure in its owning task, and record it in the execution log.

## Execution log

- Pre-flight: Tasks 1–3 provide the labels, checker, template and screenshots consumed by Task 5; Task 4 accepts both the old basename and Task 5's stem. Interfaces agree.
- Execution uses the existing required worktree; test temporary files are kept under `claude-skills/ship-workflow/tests/.tmp/` with TMPDIR.
- Task 1: AC-1 failed with the missing function, then all 15 refactor-scan tests passed. Reused ship-next's config and glob helpers.
- Task 2: checker tests failed before implementation; all 19 refactor-scan tests now pass, including zsh checker and merge-label checks. The added zsh merge-label test initially omitted SHIP_LIB in its fresh shell; corrected the test setup before verification.
- Task 3: template and harness tests failed first; all 23 refactor-scan tests pass. Additional reserved-character coverage caught zsh treating unescaped `%` and `#` substitution patterns specially; URL encoding now uses portable sed. Chrome failure/no-PNG cleanup checks passed immediately. Real Chrome 156 rendered the filled template and z1 overlay successfully, using an isolated worktree-local browser profile.
- Task 4: changed-link and basename-equivalence tests failed first; the prescribed filtered run passed all 26 tests after the change.
- Deviation: updated the identical step-3 link assertion in the zsh command-block test as well as the referenced bash test — both exercise the same changed output.
- Task 5: AC-7 and fresh-shell command execution failed first; all 56 command-block tests pass after C2, the gate/screenshots, stem argument and both reported paths were updated. Fresh bash and zsh shells verify valid pairs continue and invalid pairs stop before screenshots.
- Task 6 first full run: 748/750 passed. Besides the known cwd-guard baseline failure, suite hygiene flagged three new Task 5 loop assertions.
- Deviation: added explicit `|| return 1` to the three flagged `[[ ]]` assertions in Task 5's fresh-shell test — the existing suite-hygiene guard requires it so a failed assertion cannot be ignored inside a loop. No assertion was removed or loosened.
- Final independent branch review: no Critical, Important or Minor findings and no requested code fixes. AC-8/AC-9 and external vault state were excluded as the plan explicitly assigns them to the operator; the executor owns the full-suite result and Chrome smoke evidence.
- Task 6 final verification: `bats tests/test_suite-hygiene.bats tests/test_command-blocks.bats` passed 57/57 after the repair; `bats tests/` passed 749/750, with only the explicitly allowed pre-existing `cwd-guard: exits 0 when not in a git repo at all` failure. `git diff --check` passed.
- Result: DONE_WITH_CONCERNS. All six tasks completed; deviations are the matching zsh link assertion update and explicit failure returns required by suite hygiene. No push, branch switch, amendment, hook bypass or operator vault regeneration performed.
