# R-025 `/ship-refactor-scan` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a sixth ship-workflow command, `/ship-refactor-scan`.
- It runs Matt Pocock's `improve-codebase-architecture` from vendored text.
- It scopes by churn × lines hotspots and saves the HTML report to the vault.
- It turns picked candidates into 🔜 Next ROADMAP rows with refactor guardrails.

**Architecture:**
- **Vendored text:** four upstream files plus the license, under
  `claude-skills/ship-workflow/templates/pocock/`.
- **Command file:** `commands/ship-refactor-scan.md`, which carries Pocock's Process with
  four named changes.
- **New lib:** `lib/refactor-scan.sh` holds the testable parts: `rs_hotspots`,
  `rs_done_when` and `rs_write_rows`.
- **Changed lib:** `lib/roadmap-insert.sh` gains `--next`.
- **Install:** `sync.sh` links the command.

**Tech Stack:** bash and zsh (the libs are sourced from Claude Code's Bash tool, which runs
zsh on this machine), awk, git, bats.

**Spec:** `docs/specs/R-025-add-ship-refactor-scan.md`. Read it first. §3 is the design,
§4 the acceptance rows, and Decisions the reasons.

AC-11, the real run on langlive-line-oa, is not a task here. The ship's operator runs it after
this plan is done.

## Global Constraints
- **Paths:** everything new lives under `claude-skills/ship-workflow/`, except the
  `sync.sh` and `CLAUDE.md` edits at the repo root. Do not modify any file under
  `~/.claude/` or the vault.
- **Vendored files are byte-identical to upstream `mattpocock/skills@5beb35b040e3de97e54fa9e386d7e42d15c295c2`.**
  Copies are already fetched to `/tmp/r025-pocock/`. Their `git hash-object` values are:
  - `44cc7d3136c44534d68ac523fa6cd37e759d2846` — `improve-codebase-architecture/SKILL.md`
  - `e39e8255b8797cf8257d014fb6658fb533f3a399` — `improve-codebase-architecture/HTML-REPORT.md`
  - `3f63c8146dd2604b419c929e9876b90c30d410e9` — `codebase-design/SKILL.md`
  - `cd94075cfd754d147555c5d747a16431ed4c7dd8` — `codebase-design/DEEPENING.md`
  - `f1dd2c09108dde1a5f56097cee8461b3ea834499` — `LICENSE.upstream` (upstream `LICENSE`)

  If `/tmp/r025-pocock/` is missing, refetch each file with
  `gh api "repos/mattpocock/skills/contents/<upstream path>?ref=5beb35b040e3de97e54fa9e386d7e42d15c295c2" --jq .content | base64 -d`.
- **Libs locate siblings with `${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}`**, the
  existing convention. Never use `BASH_SOURCE`.
- **`lib/refactor-scan.sh` functions behave identically when sourced under bash and zsh.**
  - No arrays: zsh arrays are 1-based.
  - Split TSV fields with `cut -f<n>`, never `IFS=$'\t' read`, which merges consecutive tabs
    and drops empty fields.
  - Reverse lines with `awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}'`.
- **Guardrail sentences**, exact text, in this order:
  1. `先補「固定現有行為」的測試（打在重構後模組的介面上），全綠才動結構`
  2. `搬動結構期間既有測試一行都不改且保持全綠；介面測試涵蓋後，才在最後一個獨立 commit 刪掉被取代的淺層測試`
  3. `只動結構不改行為，行為改動另開項目`
- **Hotspot extension list:** `py ts tsx js jsx mjs cjs go rs rb java kt swift php cs c cc cpp h hpp sh vue svelte scala`.
- **Hotspot skips:**
  - a path segment `test`, `tests`, `__tests__`, `spec`, `migrations`, `vendor`,
    `node_modules`, `dist` or `build`;
  - a basename starting `test_` or containing `.test.` / `.spec.`;
  - `*.d.ts`, `*.min.*`;
  - churn 0.
- **Tests:** run from `claude-skills/ship-workflow` with `bats tests/<file>.bats`. A linked
  worktree has one known failure, `cwd-guard: exits 0 when not in a git repo at all`. Ignore
  that one only.

## Review Focus
1. **Non-ASCII or spaced file names.** `rs_hotspots` must print `中文.py` and `a b.py` as
   real paths, not git's quoted `"\344…"` form, so run git with `-c core.quotePath=false`.
   Test in Task 2.
2. **Empty and odd TSV fields.**
   - A trailing empty `reason` (line ends in a tab) is accepted.
   - An empty middle field (summary) is rejected with exit 2, never shifted into the next
     field.
   - A non-numeric `card` is rejected.
   Tests in Task 5.
3. **Shell-special text in descriptions.** `/api/x`, `&`, `「」` and `（）` must reach the
   ROADMAP unchanged. `roadmap-insert.sh` passes the row line through `awk -v`. Test in
   Task 5.
4. **Sourced under zsh.** `rs_write_rows` must give the same rows and order when sourced in
   `zsh`. Test in Task 5, skipped when zsh is missing.
5. **An empty Next section, and a repo with no commits in the window.** `--next` inserts into
   a Next section that has no rows yet. `rs_hotspots` prints nothing and exits 0 when nothing
   changed in the window. Tests in Tasks 4 and 2.

---

### Task 1: Vendor Pocock's text

**Files:**
- Create: `claude-skills/ship-workflow/templates/pocock/improve-codebase-architecture/SKILL.md`
- Create: `claude-skills/ship-workflow/templates/pocock/improve-codebase-architecture/HTML-REPORT.md`
- Create: `claude-skills/ship-workflow/templates/pocock/codebase-design/SKILL.md`
- Create: `claude-skills/ship-workflow/templates/pocock/codebase-design/DEEPENING.md`
- Create: `claude-skills/ship-workflow/templates/pocock/LICENSE.upstream`
- Create: `claude-skills/ship-workflow/templates/pocock/SOURCE.md`
- Test: `claude-skills/ship-workflow/tests/test_refactor-scan.bats` (new file; Tasks 2, 3 and
  5 add to it)

**Interfaces:**
- Produces: `SOURCE.md` lines matching `^- \`<relative path>\` · upstream \`<upstream path>\` · blob \`<40-hex>\`$`
  for each of the five files.

- [x] **Step 1: Write the failing test** (`load helpers`, `setup` exports
  `P="$SHIP_SKILL_ROOT/templates/pocock"`)

```bash
@test "pocock: vendored files are byte-identical to the shas in SOURCE.md" {
  [ -f "$P/LICENSE.upstream" ]
  n=0
  while IFS= read -r line; do
    path=$(printf '%s' "$line" | sed -E 's/^- `([^`]+)`.*/\1/')
    sha=$(printf '%s' "$line" | sed -E 's/.*blob `([0-9a-f]{40})`$/\1/')
    [ "$(git hash-object "$P/$path")" = "$sha" ] || { echo "drift: $path"; return 1; }
    n=$((n + 1))
  done < <(grep -E '^- `[^`]+` · upstream `[^`]+` · blob `[0-9a-f]{40}`$' "$P/SOURCE.md")
  [ "$n" -eq 5 ]
  grep -qF '5beb35b040e3de97e54fa9e386d7e42d15c295c2' "$P/SOURCE.md"
  grep -qF 'DESIGN-IT-TWICE.md' "$P/SOURCE.md"
}
```

- [x] **Step 2: Run it, expect FAIL** (`bats tests/test_refactor-scan.bats`: no
  `LICENSE.upstream`).
- [x] **Step 3: Copy the five files** from `/tmp/r025-pocock/` with `cp`, never retyped.
  Then write `SOURCE.md`:
  - a short header: repo `mattpocock/skills`, the full commit, MIT, Copyright (c) 2026 Matt
    Pocock;
  - that the files are verbatim and `/ship-refactor-scan` names its four changes;
  - that `DESIGN-IT-TWICE.md` is not vendored, so the link to it is dead on purpose;
  - the five `- \`path\` · upstream \`path\` · blob \`sha\`` lines, upstream paths under
    `skills/engineering/` and `LICENSE`.
- [x] **Step 4: Run, expect PASS.** Also `git hash-object` each file and compare it with the
  Global Constraints list.
- [x] **Step 5: Commit** `feat(R-025): vendor Pocock improve-codebase-architecture + codebase-design`.

### Task 2: `rs_hotspots`

**Files:**
- Create: `claude-skills/ship-workflow/lib/refactor-scan.sh`
- Test: `claude-skills/ship-workflow/tests/test_refactor-scan.bats`

**Interfaces:**
- Produces: `rs_hotspots [months=6] [top=10]`. Stdout lines
  `score<TAB>churn<TAB>lines<TAB>path`, sorted by score descending, then path ascending.
  Exit 0. Outside a git repo: a message on stderr, exit 1.

- [x] **Step 1: Write the failing tests.**
  - Add a helper `mkrepo` that runs `git init -q -b main` in `$SCRATCH/r`.
  - Add a helper `commit_file <path> <lines> [<date>]`. It writes exactly `<lines>` lines,
    the first being `# <counter>` (so every commit changes the file), and commits it. With
    `<date>` (e.g. `"8 months ago"`) it sets `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`
    from `date -v-8m` (BSD) or `date -d '8 months ago'` (GNU), whichever works.
  - Each test sources `$SHIP_LIB/refactor-scan.sh`.

```bash
@test "rs_hotspots: churn × lines, code only, tests/migrations/deleted/non-code skipped (AC-1)" {
  # a.py: 3 commits ending at 10 lines; b.ts: 1 commit, 100 lines; tests/test_a.py ×5;
  # migrations/0001.py ×2; README.md ×4; c.py committed then git rm'd
  run rs_hotspots 6 10
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '100\t1\t100\tb.ts\n30\t3\t10\ta.py')" ]
}
@test "rs_hotspots: the window counts commits by date (AC-2)" {
  # a.py: one commit 8 months ago, one today
  [ "$(rs_hotspots 6 10 | cut -f2)" = "1" ]
  [ "$(rs_hotspots 12 10 | cut -f2)" = "2" ]
}
@test "rs_hotspots: top limits the lines (AC-3)" {   # three scored files
  [ "$(rs_hotspots 6 2 | wc -l | tr -d ' ')" = "2" ]
}
@test "rs_hotspots: outside a git repo → exit 1, stderr only (AC-4)" {
  cd "$SCRATCH"   # not a repo
  run --separate-stderr rs_hotspots
  [ "$status" -eq 1 ]; [ -z "$output" ]; [ -n "$stderr" ]
}
@test "rs_hotspots: non-ASCII and spaced paths print as real paths" {   # Review Focus 1
  # commit `中文.py` (2 lines) and `a b.py` (3 lines)
  rs_hotspots 6 10 | cut -f4 | grep -qxF '中文.py'
  rs_hotspots 6 10 | cut -f4 | grep -qxF 'a b.py'
}
@test "rs_hotspots: nothing in the window → no output, exit 0" {   # Review Focus 5
  # one commit 8 months ago only
  run rs_hotspots 6 10
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
```

  If bats lacks `--separate-stderr` (bats < 1.5), use `run sh -c '… 2>/dev/null'` for stdout
  and check stderr separately.
- [x] **Step 2: Run, expect FAIL** (`rs_hotspots: command not found`).
- [x] **Step 3: Implement `rs_hotspots` in `lib/refactor-scan.sh`.** A header comment names
  R-025 and the three functions.
  - Check with `git rev-parse --show-toplevel`; run from the top level.
  - Churn: `git -c core.quotePath=false log --since="<months> months ago" --no-merges --format= --name-only`,
    counted per path.
  - Line counts: `wc -l` on each path that survives the `git -c core.quotePath=false ls-files`
    filter.
  - The filtering, scoring and sorting are one awk program, then `sort -t$'\t' -k1,1nr -k4,4`
    and `head -n <top>`.
- [x] **Step 4: Run, expect PASS** (all six).
- [x] **Step 5: Commit** `feat(R-025): rs_hotspots — churn × lines hotspots`.

### Task 3: `rs_done_when`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/refactor-scan.sh`
- Test: `claude-skills/ship-workflow/tests/test_refactor-scan.bats`

**Interfaces:**
- Produces: `rs_done_when <outcome> [<reason>]`. One stdout line: outcome, then the three
  Global-Constraints guardrails, then `Door: one-way — <reason>` only when a reason is
  given, joined by `；`. Empty outcome: exit 2.

- [x] **Step 1: Write the failing test** (AC-5).

```bash
@test "rs_done_when: outcome + three guardrails, Door only with a reason (AC-5)" {
  G1='先補「固定現有行為」的測試（打在重構後模組的介面上），全綠才動結構'
  G2='搬動結構期間既有測試一行都不改且保持全綠；介面測試涵蓋後，才在最後一個獨立 commit 刪掉被取代的淺層測試'
  G3='只動結構不改行為，行為改動另開項目'
  [ "$(rs_done_when 'X 收進一個 module')" = "X 收進一個 module；$G1；$G2；$G3" ]
  [ "$(rs_done_when 'X 收進一個 module' '改到 /api/x 回應')" = "X 收進一個 module；$G1；$G2；$G3；Door: one-way — 改到 /api/x 回應" ]
  run rs_done_when ''
  [ "$status" -eq 2 ]
}
```

- [x] **Step 2: Run, expect FAIL.**
- [x] **Step 3: Implement it** with `printf`, the guardrails as three readonly-style
  variables at the top of the lib (`RS_GUARD_1..3`).
- [x] **Step 4: Run, expect PASS.**
- [x] **Step 5: Commit** `feat(R-025): rs_done_when — refactor guardrails`.

### Task 4: `roadmap-insert.sh --next`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/roadmap-insert.sh`:
  - the usage comment;
  - the flag parse (`--next) NEXT=1; shift ;;`);
  - insert mode.
- Test: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`

**Interfaces:**
- Produces: `roadmap-insert.sh <ROADMAP> <ID> <desc> --next [--summary s] [--done-when d] [--est e] [--adhoc]`
  - The row and its `↳ explain:` / `↳ done when:` lines go directly under `## 🔜 Next`.
  - The suffix keeps ` · est=` / ` · adhoc-inserted=true` but never ` · status=in-progress`.
  - With no `## 🔜 Next` heading: stderr `ERROR: no '## 🔜 Next' heading found in <file>`,
    exit 1, file unchanged.
  - Only insert mode honours the flag.

- [x] **Step 1: Write the failing tests** (the file's `setup` gives `$ROADMAP` from
  `make_fake_airos`, whose Now and Next are empty).

```bash
@test "roadmap-insert --next: row, explain, done-when under Next, above existing rows, no status (AC-6)" {
  sed -i.bak '/^## 🔥 Now/a\
- [x] **R-001** now item' "$ROADMAP" && rm "$ROADMAP.bak"
  sed -i.bak '/^## 🔜 Next/a\
- [x] **R-002** next item' "$ROADMAP" && rm "$ROADMAP.bak"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-003 "d" --next --summary s --done-when w
  next_ln=$(grep -n '^## 🔜 Next' "$ROADMAP" | cut -d: -f1)
  [ "$(sed -n "$((next_ln+1))p" "$ROADMAP")" = "- [x] **R-003** d" ]
  [ "$(sed -n "$((next_ln+2))p" "$ROADMAP")" = "    ↳ explain: s" ]
  [ "$(sed -n "$((next_ln+3))p" "$ROADMAP")" = "    ↳ done when: w" ]
  [ "$(sed -n "$((next_ln+4))p" "$ROADMAP")" = "- [x] **R-002** next item" ]
  now_ln=$(grep -n '^## 🔥 Now' "$ROADMAP" | cut -d: -f1)
  [ "$(sed -n "$((now_ln+1))p" "$ROADMAP")" = "- [x] **R-001** now item" ]
  ! grep -F 'R-003' "$ROADMAP" | grep -qF 'status='
}
@test "roadmap-insert --next: into an empty Next section" {   # Review Focus 5
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-010 "e" --next
  next_ln=$(grep -n '^## 🔜 Next' "$ROADMAP" | cut -d: -f1)
  later_ln=$(grep -n '^## 🕐 Later' "$ROADMAP" | cut -d: -f1)
  r_ln=$(grep -n 'R-010' "$ROADMAP" | cut -d: -f1)
  [ "$next_ln" -lt "$r_ln" ] && [ "$r_ln" -lt "$later_ln" ]
}
@test "roadmap-insert --next: no Next heading → exit 1, file untouched (AC-7)" {
  sed -i.bak '/^## 🔜 Next/d' "$ROADMAP" && rm "$ROADMAP.bak"
  before=$(shasum "$ROADMAP")
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-011 "f" --next
  [ "$status" -eq 1 ]
  [[ "$output" == *"no '## 🔜 Next' heading"* ]] || return 1
  [ "$(shasum "$ROADMAP")" = "$before" ]
}
```

- [x] **Step 2: Run, expect FAIL** (the row lands under Now).
- [x] **Step 3: Implement.**
  - Insert mode picks the heading regex (`^## 🔜 Next` when `NEXT=1`, else `^## 🔥 Now`) and
    passes it to the existing awk.
  - It skips the `status=in-progress` suffix when `NEXT=1`.
  - The Next-heading check runs before writing `$TMP`.
- [x] **Step 4: Run** `bats tests/test_roadmap-insert.bats`. Expect all PASS, the 38 old
  tests included.
- [x] **Step 5: Commit** `feat(R-025): roadmap-insert --next`.

### Task 5: `rs_write_rows`

**Files:**
- Modify: `claude-skills/ship-workflow/lib/refactor-scan.sh`
- Test: `claude-skills/ship-workflow/tests/test_refactor-scan.bats`

**Interfaces:**
- Consumes:
  - `rs_done_when` (Task 3);
  - `roadmap-insert.sh … --next` (Task 4);
  - `${SHIP_LIB:-…}/id-gen.sh roadmap --reserve`, which reads `$PWD/docs/product/ROADMAP.md`
    and `$PWD/.claude/.id-reservations`, and appends the reserved ID there.
- Produces: `rs_write_rows <roadmap> <report-basename>`. Stdin holds TSV lines
  `chain card description summary outcome reason`; stdout is `ID<TAB>description` per row,
  in input order.
  - Exit 0 on success, and on empty stdin with no output.
  - Exit 2 with `line <n>: <problem>` on stderr, before any reservation, when a line:
    - has a field count ≠ 6;
    - has an empty chain, card, description, summary or outcome;
    - has a chain other than `new`/`after`;
    - has a non-numeric card;
    - is line 1 with `after`.
  - Exit 1 when `id-gen.sh` or `roadmap-insert.sh` fails.
  - Blank stdin lines are skipped.

- [x] **Step 1: Write the failing tests.**
  - Setup for these: `$SCRATCH/r` is a git repo containing `docs/product/ROADMAP.md` with
    rows `**R-001**`..`**R-003**`, and is the cwd.
  - `$RM` is a scratch vault ROADMAP from `make_fake_airos "$SCRATCH" demo`.
  - Write TSV with `printf 'new\t1\t…\n'`.

```bash
@test "rs_write_rows: four rows in input order, chained, linked, guarded (AC-10)" {
  run rs_write_rows "$RM" x.html < <(printf '%s\n' \
    $'new\t1\tA 收進一個 module\tsa\toa\t' \
    $'new\t2\tB 新增新介面\tsb\tob\t改到 /api/x 回應' \
    $'after\t2\tB 遷移呼叫點\tsc\toc\t' \
    $'after\t2\tB 刪舊介面\tsd\tod\t')
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')" = "R-004 R-005 R-006 R-007 " ]
  order=$(grep -oE '^- \[ \] \*\*R-00[4-7]\*\*' "$RM" | grep -oE 'R-00[4-7]' | tr '\n' ' ')
  [ "$order" = "R-004 R-005 R-006 R-007 " ]
  grep -F '**R-006**' "$RM" | grep -qF '；接在 R-005 之後做（報告：Reports/x.html#c2）'
  grep -F '**R-007**' "$RM" | grep -qF '；接在 R-006 之後做（報告：Reports/x.html#c2）'
  grep -F '**R-004**' "$RM" | grep -qF 'A 收進一個 module（報告：Reports/x.html#c1）'
  [ "$(grep -c '↳ done when: .*只動結構不改行為，行為改動另開項目' "$RM")" -eq 4 ]
  [ "$(grep -c 'Door: one-way' "$RM")" -eq 1 ]
  grep -A2 -F '**R-005**' "$RM" | grep -qF 'Door: one-way — 改到 /api/x 回應'
  ! grep -E 'R-00[4-7]' "$RM" | grep -qF 'status='
}
@test "rs_write_rows: first line after / 5 fields / empty summary / bad card → exit 2, nothing reserved (AC-10b)" {
  before=$(shasum "$RM")
  for bad in $'after\t1\td\ts\to\t' $'new\t1\td\ts\to' $'new\t1\td\t\to\t' $'new\tx\td\ts\to\t'; do
    run rs_write_rows "$RM" x.html <<<"$bad"
    [ "$status" -eq 2 ] || { echo "accepted: $bad"; return 1; }
  done
  [ ! -s .claude/.id-reservations ]
  [ "$(shasum "$RM")" = "$before" ]
}
@test "rs_write_rows: shell-special text reaches the ROADMAP unchanged" {   # Review Focus 3
  rs_write_rows "$RM" x.html <<<$'new\t3\t改 /api/x & y「z」（w）\ts & t\to\t' >/dev/null
  grep -qF '改 /api/x & y「z」（w）（報告：Reports/x.html#c3）' "$RM"
  grep -qF '↳ explain: s & t' "$RM"
}
@test "rs_write_rows: empty stdin → exit 0, no output" {
  run rs_write_rows "$RM" x.html </dev/null
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "rs_write_rows: same rows when sourced under zsh" {   # Review Focus 4
  command -v zsh >/dev/null || skip "zsh not installed"
  printf '%s\n' $'new\t1\tA\tsa\toa\t' $'after\t1\tB\tsb\tob\t' > "$SCRATCH/rows.tsv"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_write_rows '$RM' x.html < '$SCRATCH/rows.tsv'"
  [ "$status" -eq 0 ]
  grep -F '**R-005**' "$RM" | grep -qF '；接在 R-004 之後做'
  [ "$(grep -oE '^- \[ \] \*\*R-00[45]\*\*' "$RM" | grep -oE 'R-00[45]' | tr '\n' ' ')" = "R-004 R-005 " ]
}
```

- [x] **Step 2: Run, expect FAIL.**
- [x] **Step 3: Implement `rs_write_rows`** under the Global Constraints shell rules:
  1. Validate the whole input in one `awk -F'\t'` pass (it sees empty fields correctly).
  2. Reserve one ID per line and write `ID<TAB>line` to a `mktemp` file, carrying the
     previous ID for `after`.
  3. Build each description.
  4. Insert in reverse with the awk reverser.
  5. Print in input order.
  6. Remove the temp file on every path.
- [x] **Step 4: Run, expect PASS** (all of `test_refactor-scan.bats`).
- [x] **Step 5: Commit** `feat(R-025): rs_write_rows — picked candidates become Next rows`.

### Task 6: The command file

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-refactor-scan.md`
- Test: `claude-skills/ship-workflow/tests/test_command-blocks.bats`

**Interfaces:**
- Consumes: `rs_hotspots`, `rs_write_rows` (lib), `airos-binding.sh project_path`, and
  `lib/sync.sh --force`.
- Produces: numbered step headings that the block extractor relies on, exactly:
  - `0. **Resolve paths.**`
  - `1. **Read the method.**`
  - `2. **Pick.**`
  - `3. **Write rows.**`
  - `4. **Report back.**`

- [x] **Step 1: Write the failing test** (AC-10c). Model it on the existing test near line
  620 that uses `make_fake_airos "$SCRATCH" repo`:
  - the global `ship-workflow.yml` goes in `$HOME/.claude`, as at line 180;
  - the vault project is named `repo`, the scratch repo's directory name.

```bash
rows_block() { block ship-refactor-scan.md '^3\. \*\*Write rows' '^4\. \*\*Report back'; }

@test "ship-refactor-scan step 3: syncs, writes the rows file into the vault ROADMAP's Next, mirrors it (AC-10c)" {
  vault=$(make_fake_airos "$SCRATCH" repo)
  printf 'airos_vault: %s\nairos_projects_dir: "10 Projects"\n' "$vault" > "$HOME/.claude/ship-workflow.yml"
  VP="$vault/10 Projects/repo"; mkdir -p "$VP/Reports"
  printf '%s\n' $'new\t1\tA 收進一個 module\tsa\toa\t' > "$VP/Reports/refactor-scan-T.rows.tsv"
  rows_block > "$SCRATCH/s3.sh"; [ -s "$SCRATCH/s3.sh" ]
  run env STAMP=T bash "$SCRATCH/s3.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  awk '/^## 🔜 Next/{f=1;next} /^## /{f=0} f' "$VP/ROADMAP.md" | grep -qF 'A 收進一個 module（報告：Reports/refactor-scan-T.html#c1）'
  grep -qF 'A 收進一個 module' docs/product/ROADMAP.md
}
@test "ship-refactor-scan: one bash block per step 0, 1, 3, 4; step 2 has none" {
  [ -n "$(block ship-refactor-scan.md '^0\. \*\*Resolve' '^1\. \*\*Read the method')" ]
  [ -n "$(block ship-refactor-scan.md '^1\. \*\*Read the method' '^2\. \*\*Pick')" ]
  [ -z "$(block ship-refactor-scan.md '^2\. \*\*Pick' '^3\. \*\*Write rows')" ]
  [ -n "$(block ship-refactor-scan.md '^4\. \*\*Report back' '^## ')" ]
}
```

- [x] **Step 2: Run, expect FAIL** (no command file).
- [x] **Step 3: Write the command file.**
  - Frontmatter:
    - `name: ship-refactor-scan`;
    - `description:` one line: Pocock architecture scan → vault HTML report → picked
      candidates become 🔜 Next rows for /ship-next;
    - `argument-hint: "[<direction: a module, subsystem or pain point>]"`.
  - Then an intro naming `templates/pocock/` and its four changes C1–C4, followed by the
    steps in spec §3.2 order, with their prose from the spec.
  - The blocks, each self-contained, because every block runs in a fresh shell:
    - **Step 0:** source the lib.
      1. `STAMP=$(date +%Y-%m-%d-%H%M)`.
      2. Resolve `PROJ_DIR` with `airos-binding.sh project_path 2>/dev/null` plus a `-d`
         check. If it resolves: `REPORT_DIR=$PROJ_DIR/Reports` (`mkdir -p`), and `ROADMAP`
         only if the file exists. Else: `REPORT_DIR=${TMPDIR:-/tmp}`, empty `ROADMAP`.
      3. Save `git status --porcelain | grep -v ' docs/product/' || true` to
         `${TMPDIR:-/tmp}/refactor-scan-$STAMP.status-before`.
      4. Print `STAMP=… REPORT_DIR=… ROADMAP=…`. Tell Claude to carry these values into later
         blocks.
    - **Step 1:** source the lib; `rs_hotspots 6 10`. The prose says a `<direction>` skips
      this. The prose holds C1–C4 from spec §3.2 nearly verbatim, including:
      - read `$REPORT_DIR/refactor-scan-rejected.md` first;
      - `<article id="c<N>">`;
      - the hotspot table in the report header;
      - `open` the report;
      - CONTEXT.md for GLOSSARY.md;
      - read the vendored `codebase-design` files instead of calling the Skill tool;
      - "Do NOT propose interfaces yet".
    - **Step 2:** prose only. The numbered pick question, with Top recommendation as the
      recommended answer; the rejected-line format; the ADR-style test for which rejections
      to record.
    - **Step 3:**
      - `STAMP="${STAMP:?set STAMP to the value step 0 printed}"`; source the lib.
      - Re-resolve `PROJ_DIR`; `ROADMAP=$PROJ_DIR/ROADMAP.md`;
        `ROWS=$PROJ_DIR/Reports/refactor-scan-$STAMP.rows.tsv`.
      - No ROADMAP: print `no vault ROADMAP — report only` and `exit 0`. No rows file: an
        error and `exit 1`.
      - `"${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/sync.sh" --force || exit 1`.
      - `rs_write_rows "$ROADMAP" "refactor-scan-$STAMP.html" < "$ROWS" || exit 1`.
      - Sync again.

      The prose before it gives the TSV format, the ordinary/wide rule (Pocock `to-tickets`
      wide refactor → expand / migrate / contract as `new` / `after` / `after`) and the
      one-way rule.
    - **Step 4:** `STAMP` as in step 3. Compare
      `git status --porcelain | grep -v ' docs/product/' || true` with the saved file:
      equal → `repo unchanged outside docs/product/`; different → `WARN:` plus a `diff`.
      The prose lists the report path, the rows printed by step 3, and the rejected lines.
- [x] **Step 4: Run** `bats tests/test_command-blocks.bats`. Expect all PASS, the old tests
  included.
- [x] **Step 5: Commit** `feat(R-025): /ship-refactor-scan command`.

### Task 7: Install and docs

**Files:**
- Modify: `sync.sh:5` (header comment: six commands) and `sync.sh:26`
  (`COMMANDS=(ship-next ship-compound ship-idea ship-land ship-init ship-refactor-scan)`).
- Modify: `claude-skills/ship-workflow/tests/test_sync-install.bats` lines 18 and 45:
  - both loops gain `ship-refactor-scan`;
  - the test name at line 44 says 6 commands.
- Modify: `claude-skills/ship-workflow/SKILL.md`:
  - description: "Six ship-* slash commands … scanning a repo for refactors";
  - intro: "Its six";
  - a list line after `/ship-idea`: `**\`/ship-refactor-scan [<direction>]\`** — Scan for
    deepening opportunities with Pocock's improve-codebase-architecture (churn × lines
    hotspots, HTML report in the vault); picked candidates become 🔜 Next rows for
    /ship-next (R-025)`;
  - the Usage block's "the 6 commands".
- Modify: `claude-skills/ship-workflow/README.md` lines 3 and 21 (six / 6), plus the same
  list line wherever README lists the commands.
- Modify: `CLAUDE.md:11`: "the six ship-* commands".

- [x] **Step 1: Update the test loops first** and run `bats tests/test_sync-install.bats`.
  Expect FAIL: `sync.sh` does not link `ship-refactor-scan.md`.
- [x] **Step 2: Edit `sync.sh`.** Run again, expect PASS (AC-9).
- [x] **Step 3: Edit the three docs.** Check with
  `grep -rnE '[Ff]ive|\b5 commands|the 5 ' sync.sh CLAUDE.md claude-skills/ship-workflow/SKILL.md claude-skills/ship-workflow/README.md`.
  It must print no line about the command count. README line 48's "five changes" is about
  the security prompt and stays.
- [x] **Step 4: Commit** `feat(R-025): install /ship-refactor-scan; docs say six commands`.

### Task 8: Full suite

- [x] **Step 1:** `cd claude-skills/ship-workflow && bats tests/`. Expected: everything
  passes except the known `cwd-guard: exits 0 when not in a git repo at all`. The baseline
  was 717/718; the new count is 718 + the tests added here.
- [x] **Step 2:** If anything else fails, fix it in the task that owns it and re-run. Do not
  edit a test to make it pass unless the test itself is wrong, and say why in the commit.

## Execution log

Pre-flight: Tasks 2/3/4 feed Task 5; Tasks 1/2/5 feed Task 6; Task 7 installs Task 6. Interfaces agree. Execution stays in this worktree; test HOME and TMPDIR use scratch paths here.

Task 1: complete — vendor test failed before copy, then passed (1/1); all five blob hashes match.

Deviation: Task 2 sets GIT_CEILING_DIRECTORIES for the non-repository fixture — scratch is nested inside this worktree and otherwise inherits its git root. Test names use ASCII per .ship/tdd-rules.md.

Task 2: complete — six hotspot tests failed before implementation; refactor-scan suite passed 7/7.

Deviation: Task 3 expected strings use ${G1}, ${G2}, ${G3} — unbraced variables adjacent to full-width punctuation are misparsed by the installed Bash; the expected text is unchanged.

Task 3: complete — guardrail test RED then GREEN; refactor-scan suite 8/8.

Task 4: complete — three Next tests RED then GREEN; roadmap-insert suite 41/41.

Task 5: complete — five row-writer tests RED then GREEN; refactor-scan suite 13/13, including zsh.

Deviation: Task 6 also executes step 3 under zsh — .ship/tdd-rules.md requires command-block integration coverage in both shells.

Task 6: complete — two prescribed tests RED then GREEN; command-block suite 53/53, plus the added zsh integration test passed.

Task 7: complete — install test failed for the missing command link, then suite passed 17/17. Count check only finds the intentionally retained security-prompt “five changes”.

Deviation: Task 8 updates test_repo-layout.bats to expect the sixth command — the full suite exposed an existing exact command allow-list omitted from Task 7. The equality assertion remains strict.

Final review: independent reviewer found no Critical, Important, or Minor issues; verified all five upstream hashes and diff whitespace. AC-11 remains operator-owned as planned. Full-suite results are verified by the executor, and pre-existing behavior remains outside the repair scope.

Task 8 verification: first full run completed 737 tests with only the known cwd-guard failure and the omitted command allow-list failure. After the local allow-list repair, test_repo-layout.bats passed 10/10; full-suite rerun completed: 736/737 passed, with only `cwd-guard: exits 0 when not in a git repo at all` failing (the documented baseline exception).

Task 8: complete — `bats tests/` rerun has no new failures. `git diff --check` passes. DONE_WITH_CONCERNS for the four local deviations recorded above and the known baseline failure. AC-11 was not run, as directed. Branch and worktree retained; no remote push.
