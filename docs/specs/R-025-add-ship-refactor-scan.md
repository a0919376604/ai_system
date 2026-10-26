---
date: 2026-10-27
updated: 2026-10-27
type: spec
id: R-025
status: draft
tags: [ship-workflow, refactoring, architecture, pocock, roadmap]
ai-first: true
related-specs: [R-016, R-017, R-021]
mockup: null
supersedes: null
---

## For future Claude
> R-025 adds a sixth ship-workflow command, `/ship-refactor-scan [<direction>]`. It runs
> Matt Pocock's `improve-codebase-architecture` inside ship. The command:
> 1. scopes the scan by hotspots (6-month churn × lines);
> 2. has a sub-agent look for shallow modules there;
> 3. writes Pocock's HTML report, with before/after diagrams, into the vault project's
>    `Reports/`;
> 4. turns the candidates the operator picks into 🔜 Next rows of the scanned repo's ROADMAP,
>    for `/ship-next`.
>
> Pocock's skill sets `disable-model-invocation: true`, so ship cannot call it. Four of its
> files are copied verbatim under `templates/pocock/` (MIT), and the command names its four
> changes to them.
>
> Research: vault `10 Projects/ai_system/Research/codebase-refactoring-skills-survey.md`.

## §1 Problem
- The operator wants a refactoring tool for long-lived repos like langlive-line-oa:
  - `admin_dashboard.py` changed 122 times in six months and is 3,461 lines;
  - `line_service.py` is 5,345 lines.
- Pocock's `improve-codebase-architecture` is the method the operator chose. It stops at a
  grilling conversation, though: nothing in it executes the refactor.
- Ship executes ROADMAP rows, but nothing turns a scan into rows.
- The two cannot be glued at run time. Pocock's skill is user-invocable only, writes its
  report to a temp dir, and ends in grilling.

## §2 Goals, non-goals
**Goals**
- G1. `/ship-refactor-scan` follows Pocock's Process steps 1–2 from the vendored text, with
  exactly four changes (§3.2).
- G2. The scan and the pick (steps 0–2) are read-only for the scanned repo: no file written
  inside it, no commit, no dependency installed.
  - Step 3 writes rows through ship's existing machinery, as `/ship-next --adhoc` does. That
    refreshes the repo's `docs/product/` mirror and the gitignored `.claude/.id-reservations`,
    and nothing else in the repo.
- G3. Each picked candidate becomes one ROADMAP row in 🔜 Next. A wide refactor becomes three
  rows. Every row's done-when carries the refactor guardrails (§3.4).
- G4. A candidate the operator rejects for a reason a future scan needs is recorded, and later
  scans skip it.
- G5. The command is installed like the other five: `sync.sh` links it, and the docs list six
  commands.

**Non-goals**
- Dead-code scanning (vulture, knip). It is not part of Pocock's method; a later item can add it.
- Running the refactor. `/ship-next` does that, row by row.
- Grilling inside this command. ship-next Phase 3 grills each row when it ships.
- Pocock's `DESIGN-IT-TWICE.md`, `grilling` and `domain-modeling`. They are not vendored.
- Changing ship-next. The guardrails live in each row's done-when, and the Spec review (R-016)
  checks a ship against its spec.

## §3 Design
### 3.1 Vendored text — `claude-skills/ship-workflow/templates/pocock/`
The upstream layout is kept, so the relative links inside the files still resolve:

```
templates/pocock/
  improve-codebase-architecture/SKILL.md
  improve-codebase-architecture/HTML-REPORT.md
  codebase-design/SKILL.md
  codebase-design/DEEPENING.md
  LICENSE.upstream          # mattpocock/skills LICENSE, verbatim
  SOURCE.md                 # repo, commit 5beb35b0, one line per file: path + git blob sha
```

- The four files are byte-identical to `mattpocock/skills@5beb35b0`
  `skills/engineering/<same path>`.
- `SOURCE.md` names the upstream path of each file and its `git hash-object` sha.
- `SOURCE.md` also states that `DESIGN-IT-TWICE.md` is not vendored, so the link to it from
  `codebase-design/SKILL.md` is dead on purpose.
- Claude Code registers only `~/.claude/skills/<name>/SKILL.md`, so these nested files never
  register as skills.

### 3.2 The command — `claude-skills/ship-workflow/commands/ship-refactor-scan.md`
The command is run from the root of the repo to scan, and has these steps:

0. **Resolve paths.**
   - `PROJ_DIR=$(airos-binding.sh project_path)`. When it fails, there is no vault:
     `REPORT_DIR=${TMPDIR:-/tmp}` and no rows are written.
   - Otherwise `REPORT_DIR="$PROJ_DIR/Reports"` (`mkdir -p`; it is the vault, not the repo),
     and `ROADMAP="$PROJ_DIR/ROADMAP.md"` when that file exists.
   - `STAMP=$(date +%Y-%m-%d-%H%M)`.
1. **Read the method.** Read the four vendored files. Run Pocock's `## Process` steps 1 and 2
   as written, except for these four changes:
   - **C1 Scope.**
     - A `<direction>` argument is taken as given, as upstream says.
     - Otherwise the scope is `rs_hotspots 6 10`, which replaces "walk back the commit
       history". The sub-agent explores the top entries first, and widens when they show no
       friction.
     - Before exploring, read `$REPORT_DIR/refactor-scan-rejected.md` if it exists. A listed
       candidate is surfaced again only if its friction is clearly worse, marked as "rejected
       on <date>: <reason>", the same way upstream treats an ADR conflict.
   - **C2 Report location.**
     - The report goes to `$REPORT_DIR/refactor-scan-$STAMP.html`, not the OS temp dir.
     - Each candidate card is `<article id="c<N>">`, numbered from 1.
     - The header also holds the hotspot table used for C1: score, churn, lines and path.
     - Open the report with `open` (or `xdg-open`) and print its path.
   - **C3 Vocabulary.**
     - The repo's `CONTEXT.md` stands in for `GLOSSARY.md` and is read-only here.
     - ADRs are read from `docs/adr/` when present.
     - "Call the Skill tool with codebase-design" means: read the vendored
       `codebase-design/SKILL.md` and `DEEPENING.md`.
   - **C4 No grilling here.** Upstream step 3 is replaced by §3.2 steps 2–3 below.
     Interfaces are still not proposed (upstream: "Do NOT propose interfaces yet").
2. **Pick.**
   - Ask which candidates become Roadmap items, numbered, with the report's Top
     recommendation as the recommended answer. Several may be picked.
   - For a candidate the operator rejects with a reason a future scan needs (upstream's ADR
     test: not "not now", not self-evident), append one line to
     `$REPORT_DIR/refactor-scan-rejected.md`:
     `- <YYYY-MM-DD> · <candidate name> (<files>) — <reason>`.
3. **Write rows.** Only when `$ROADMAP` is set. For each picked candidate:
   - **Ordinary candidate:** one row.
   - **Wide refactor:** a single mechanical change whose blast radius breaks many call sites
     at once, so that no single slice lands green (Pocock `to-tickets`). It becomes three
     rows:
     1. expand: add the new form beside the old;
     2. migrate the call sites;
     3. contract: delete the old form.
     Rows 2 and 3 say 「接在 R-x 之後做」, naming the previous row.
   - Claude writes one TSV line per row, in reading order, to
     `$REPORT_DIR/refactor-scan-$STAMP.rows.tsv`. The file is kept next to the report as the
     record of what was written:
     `chain<TAB>card<TAB>description<TAB>summary<TAB>outcome<TAB>reason`.
     - `chain` is `new` for a row that starts a group, or `after` when it follows the line
       above (migrate and contract).
     - `card` is the report card number N.
     - `summary` is one zh-TW sentence for a person.
     - `reason` is empty unless the row is one-way.
   - The step's bash block runs:
     1. `lib/sync.sh --force`, so the mirror that `id-gen.sh` reads matches the vault;
     2. `rs_write_rows "$ROADMAP" "refactor-scan-$STAMP.html" < "$REPORT_DIR/refactor-scan-$STAMP.rows.tsv"`.
        The block starts from `STAMP` (the step-0 value, which Claude writes in) and
        re-resolves `ROADMAP` / `REPORT_DIR`, because every block runs in a fresh shell;
     3. `lib/sync.sh --force` again.

     This is the `--adhoc` pattern.
   - The description names the candidate in CONTEXT.md / codebase-design vocabulary.
   - A one-way reason is given when the candidate changes something callers outside the repo
     depend on: an HTTP route or payload, a DB schema, or a function another repo imports.
   - When `lib/sync.sh` stops on a divergence (R-087), no rows are written. Its message is
     shown as is.
4. **Report back.** Print:
   - the report path;
   - each row written (ID and description);
   - the rejected lines appended;
   - `git status --porcelain` of the scanned repo. It must equal the one taken at step 0,
     except for paths under `docs/product/`.

### 3.3 `lib/refactor-scan.sh`
- **`rs_hotspots [months=6] [top=10]`.** Runs in the cwd's git repo.
  - Each output line is `score<TAB>churn<TAB>lines<TAB>path`, sorted by score descending,
    then path ascending. At most `top` lines.
  - `churn` = the number of non-merge commits in the last `months` months that touched the
    path (`git log --since="<months> months ago" --no-merges --format= --name-only`).
  - `lines` = the line count of the file at HEAD. `score` = churn × lines.
  - Counted: only paths tracked at HEAD (`git ls-files`) whose extension is one of
    `py ts tsx js jsx mjs cjs go rs rb java kt swift php cs c cc cpp h hpp sh vue svelte scala`.
  - Skipped:
    - any path with a segment `test`, `tests`, `__tests__`, `spec`, `migrations`, `vendor`,
      `node_modules`, `dist` or `build`;
    - a basename starting `test_` or containing `.test.` / `.spec.`;
    - `*.d.ts` and `*.min.*`;
    - churn 0.
  - Outside a git repo: message to stderr, exit 1.
- **`rs_done_when <outcome> [<one-way reason>]`** prints one line, joined with `；`:
  1. `<outcome>`;
  2. `先補「固定現有行為」的測試（打在重構後模組的介面上），全綠才動結構`;
  3. `搬動結構期間既有測試一行都不改且保持全綠；介面測試涵蓋後，才在最後一個獨立 commit 刪掉被取代的淺層測試`;
  4. `只動結構不改行為，行為改動另開項目`;
  5. only with a reason: `Door: one-way — <reason>`.

  Exit 2 when `<outcome>` is empty.
- **`rs_write_rows <roadmap> <report-basename>`** reads the TSV lines of §3.2 step 3 on stdin.
  It runs in the scanned repo's cwd, because `id-gen.sh` reads that repo's mirror and
  reservations.
  - It first reserves one ID per line, in input order, with `id-gen.sh roadmap --reserve`.
  - Description per line:
    - `chain=after` appends `；接在 <previous line's ID> 之後做`;
    - every description then ends with `（報告：Reports/<report-basename>#c<card>）`.
  - It inserts the rows in reverse input order with `roadmap-insert.sh <roadmap> <ID> <desc>
    --next --summary <summary> --done-when "$(rs_done_when <outcome> [<reason>])"`, so Next
    reads in input order with ascending IDs.
  - Output: `ID<TAB>description` per row, in input order.
  - Validation, before anything is reserved:
    - a line with fewer than 6 fields, an empty description, outcome or summary, a `chain`
      other than `new`/`after`, or a first line that is `after` → exit 2 naming the line;
    - empty stdin → exit 0 with no output.

### 3.4 `lib/roadmap-insert.sh --next`
- In insert mode, `--next` inserts the row and its `↳ explain:` / `↳ done when:` lines right
  under `## 🔜 Next` instead of `## 🔥 Now`.
- It adds no `status=in-progress`: a Next row is not started. `--est` and `--adhoc` still
  apply.
- A ROADMAP without `## 🔜 Next` makes it fail: exit 1, `ERROR: no '## 🔜 Next' heading …`.
  The file is not modified.
- The existing `## 🔥 Now` precondition still applies, unchanged.
- `--next` is honored in insert mode only.

### 3.5 Install and docs
- `sync.sh`: `COMMANDS` gains `ship-refactor-scan`; the header comment says six commands.
- `tests/test_sync-install.bats`: both command loops include it.
- `claude-skills/ship-workflow/SKILL.md`:
  - the description and intro say six commands;
  - the command list gains `/ship-refactor-scan [<direction>]` with one line on what it does;
  - the Usage block says "the 6 commands".
- `claude-skills/ship-workflow/README.md`: the same count and list change.
- Repo `CLAUDE.md`: "the six ship-* commands".

## Seams

| Seam | Interface | Guaranteed behavior |
|---|---|---|
| hotspots | `rs_hotspots [months] [top]` (source `lib/refactor-scan.sh`, cwd in a git repo) | TSV `score churn lines path`, score = churn × lines, sorted score desc then path; only HEAD-tracked code files in the extension list; excluded segments/basenames/churn 0 skipped; at most `top` lines; non-repo → stderr + exit 1 |
| guardrail line | `rs_done_when <outcome> [<reason>]` | one line: outcome；three fixed guardrail sentences；`Door: one-way — <reason>` only when a reason is given; empty outcome → exit 2 |
| row writer | `rs_write_rows <roadmap> <report-basename>` < TSV `chain card description summary outcome reason` (cwd = scanned repo) | IDs reserved in input order; rows inserted under Next so they read in input order with ascending IDs; `after` rows name the previous ID; every description ends with the report card link; done-when = `rs_done_when`; prints `ID<TAB>description`; malformed input → exit 2 before any reservation; empty input → exit 0 |
| Next insert | `roadmap-insert.sh <ROADMAP> <ID> <desc> --next [--summary s] [--done-when d] [--est e] [--adhoc]` | row + explain + done-when lines directly under `## 🔜 Next`, no `status=`; no Next heading → exit 1, file untouched |
| vendored text | `templates/pocock/**`, `SOURCE.md` | each listed file's `git hash-object` equals the sha in `SOURCE.md`, which equals upstream `5beb35b0`; `LICENSE.upstream` present |
| install | `sync.sh restore` | links `~/.claude/commands/ship-refactor-scan.md` to `ship-workflow/commands/ship-refactor-scan.md` like the other five |
| the command | `/ship-refactor-scan [<direction>]` | steps 0–4 of §3.2; the scanned repo's `git status --porcelain` is the same before and after, except `docs/product/`; rows only when the vault ROADMAP exists |

## §4 Acceptance

| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | a scratch repo: `a.py` 10 lines × 3 commits, `b.ts` 100 lines × 1 commit, `tests/test_a.py` × 5, `migrations/0001.py` × 2, `README.md` × 4, `c.py` committed then deleted | `rs_hotspots 6 10` | exactly `100 1 100 b.ts` then `30 3 10 a.py` |
| AC-2 | `a.py` has one commit dated 8 months ago and one from today | `rs_hotspots 6 10` / `rs_hotspots 12 10` | churn 1 / churn 2 |
| AC-3 | three scored files | `rs_hotspots 6 2` | two lines, the top two |
| AC-4 | cwd is not a git repo | `rs_hotspots` | exit 1, message on stderr, nothing on stdout |
| AC-5 | — | `rs_done_when "X 收進一個 module"` / with reason `改到 /api/x 回應` / with `""` | outcome + 3 guardrails joined by `；` / same + `；Door: one-way — 改到 /api/x 回應` / exit 2 |
| AC-6 | a ROADMAP with Now holding R-001 and Next holding R-002 | `roadmap-insert.sh … R-003 "d" --next --summary s --done-when w` | the R-003 row, `↳ explain: s` and `↳ done when: w` sit right under `## 🔜 Next`, above R-002; no `status=` on it; Now unchanged |
| AC-7 | a ROADMAP with no `## 🔜 Next` | `--next` insert | exit 1, the file byte-identical |
| AC-8 | the vendored files | the test hashes each with `git hash-object` | every sha matches `SOURCE.md`; `LICENSE.upstream` exists |
| AC-9 | a scratch HOME | `./sync.sh restore` | `commands/ship-refactor-scan.md` is a link into the checkout's ship-workflow, like the other five |
| AC-10 | a scratch repo whose `docs/product/ROADMAP.md` holds R-001..R-003 and a scratch ROADMAP | `rs_write_rows` with one `new` line, then `new` / `after` / `after` (card 2, second line with a reason) | four rows under Next in input order, IDs R-004..R-007 top to bottom; R-006 says 接在 R-005 之後做 and R-007 says 接在 R-006 之後做; every description ends `（報告：Reports/x.html#c<N>）`; every done-when holds the three guardrails; only R-005's (the line with the reason) holds `Door: one-way — …` |
| AC-10b | stdin whose first line is `after`, or a line with 5 fields | `rs_write_rows` | exit 2, no reservation written, ROADMAP byte-identical |
| AC-10c | the command file | its step 3 bash block runs in a scratch repo with HOME at the tree under test, a scratch vault and a rows file at `Reports/refactor-scan-$STAMP.rows.tsv` | it syncs, writes the rows into the vault ROADMAP's Next and syncs again (the mirror then holds them) |
| AC-11 | langlive-line-oa on main | Claude runs `/ship-refactor-scan` from this worktree's command file after the executor finishes, picking the top recommendation | the vault report exists and its hotspot table lists `admin_dashboard.py` and `line_service.py`; ≥ 1 row is in line-oa's 🔜 Next with the guardrails; line-oa's `git status --porcelain` is unchanged outside `docs/product/` |

## §5 Rollout
1. Land on main.
2. `./sync.sh restore` links the new command.
3. AC-11's line-oa row is then ready for `/ship-next <ID>`.

## Decisions
**Operator decisions (2026-10-27)**
- 「比較想要獨立的skill 可以掃一掃 然後包裝成roadmap 給 ship next 跑也可以」, then
  「我希望他是 ship workflow 的體系之一」: a ship-workflow command, not a separate skill.
- 「我希望他是有整合 improve-codebase-architecture skill的」: Pocock's method at the core.
- Dead-code scanning is dropped from v1 (proposed, then 「R25 auto」).
- Auto mode (「R25 auto」).

**Claude's calls** (auto mode, the operator can override)
- **Vendor, don't call.** Upstream sets `disable-model-invocation: true`. Verbatim files plus
  sha checks make a later upstream diff trivial; R-003 vendored Anthropic's security prompt
  the same way.
- **Rejected candidates go to the vault (`Reports/refactor-scan-rejected.md`), not
  `CONTEXT.md`.** This departs from the ROADMAP done-when, which says CONTEXT.md. Three
  reasons:
  - that done-when also says the scan must not change the repo;
  - `CONTEXT.md` is the repo's vocabulary file, with a one-bullet-per-term format and a
    60-entry cap;
  - writing it from a scan would leave an uncommitted change on the base branch.
  The intent, that the next scan does not re-suggest a rejected candidate, holds.
- **Guardrails sequenced with Pocock's "replace, don't layer"** (`DEEPENING.md`: old unit
  tests on shallow modules "become waste … delete them"):
  - existing tests stay untouched and green while structure moves;
  - the replaced ones are deleted last, in their own commit, once interface tests cover them.
- **Wide refactors are three top-level rows, not epic children.** `roadmap-insert.sh
  --mark-review` matches only top-level rows, so an mr-mode repo like line-oa would fail at
  Phase 8 on a child.
- **`--next` rows carry no `status=`.** `--mark-review` adds one when needed.
- **Grilling stays in ship-next Phase 3.** Each row links its report card, which is the input
  Phase 3 grills from.
- **AC-11 is run by Claude after the executor.** It needs judgment, and it writes a real row
  into line-oa's vault ROADMAP, which the done-when asks for.
**From the builder check**
- **"Read-only" covers steps 0–2.**
  - Writing rows refreshes the repo's tracked `docs/product/` mirror and the gitignored
    `.claude/.id-reservations`, as every `/ship-next --adhoc` does today. line-oa's
    `.claude/.gitignore` already ignores `.id-reservations`.
  - Step 4 compares `git status` outside `docs/product/`.
- **Sync before reserving.** `id-gen.sh` reads the repo mirror, not the vault, so step 3 syncs
  first, as `--adhoc` does. A stale mirror would hand out IDs that collide with vault rows.
- **`rs_write_rows` reads a TSV rows file kept in the vault next to the report** (plan time: a here-doc cannot be fed to a block that runs in a fresh shell). Claude composes the rows at run time; a helper
  makes the step testable (AC-10) and keeps the bash block short.
- Door: two-way — a new command, a lib, a flag and docs; reverting the commit removes them, and no data, schema or deploy path changes.

## §8 Known risks
- **R1 Upstream drift.** Pocock's skill keeps changing (PR #533 added the scoping step). SHAs
  in `SOURCE.md` make a re-vendor a reviewed diff.
- **R2 Big repos.** line-oa's hotspots run to 5,000 lines. The exploring sub-agent is told to
  read the top hotspots first, and AC-11 measures it once.
- **R3 Line count is a rough proxy for complexity.** It is good enough to point the sub-agent;
  Pocock's own step is judgment anyway.
