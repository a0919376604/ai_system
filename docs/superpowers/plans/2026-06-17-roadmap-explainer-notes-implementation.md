# Roadmap Explainer Notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-row plain-language "Roadmap Explainer Note" artifact so a product owner with limited domain knowledge can open any ROADMAP row and understand what it actually does in one click.

**Architecture:** New vault-canonical / repo-mirror artifact at `<vault>/<project>/Roadmap-Notes/R-NNN[.M]-<slug>.md`. Claude drafts the note from `Proposals/`, `Architecture/`, and sibling explainers; user reviews. ROADMAP row links to the note via a new `↳ explain:` annotation. Three integration points: `/ship-explain` (new command), `/ship-next` (pre-flight read), `/ship-roadmap` (auto-explain during decompose).

**Tech Stack:** Bash + awk (`lib/*.sh`), bats (tests), markdown (templates + slash commands), Obsidian wikilinks, existing `sync.sh` one-way mirror.

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-17-roadmap-explainer-notes-design.md`:

- **Vault is canonical; repo is read-only mirror** (`sync.sh` one-way, atomic `.tmp → mv`).
- **Annotation indent rules**: top-level row annotation = 4 spaces; child row (`R-NNN.M`) annotation = 6 spaces. Sequence: `↳ explain:` MUST appear **before** `↳ done when:`.
- **zh-TW prose voice** for vault-side artifacts (per vault `_CLAUDE.md` `output-lang: zh-TW`). English code, paths, command names allowed.
- **Slash-command frontmatter contract**: `name`, `description` (≤ 100 char), `argument-hint`, `discord-visible: true`.
- **Atomic write**: every script that mutates a tracked file must write to `<dst>.tmp` then `mv` to `<dst>`.
- **Test gate**: 61 existing bats tests must remain green after every code task. New tests added inline per task.
- **Lock file**: `lib/id-gen.sh` uses `mkdir`-based locking (macOS-compatible); do not introduce `flock`.
- **Tooling baseline**: bats 1.x, bash 5.x, macOS-compatible (`stat -f %m` fallback). No new system dependencies.

---

## File Structure

### New files
| Path | Responsibility |
|---|---|
| `claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md` | Template for per-row explainer note (lives in vault) |
| `claude-skills/ship-workflow/commands/ship-explain.md` | `/ship-explain` slash command (single R-NNN, `--all-now`, `--force-refresh`) |
| `claude-skills/ship-workflow/tests/test_ship-explain-helpers.bats` | Tests for any helper functions used by `/ship-explain` |

### Modified files
| Path | Change |
|---|---|
| `claude-skills/ship-workflow/lib/roadmap-insert.sh` | Add `--explain "<slug>"` flag to `insert` + `child` modes; add new `--inject-explain` mode |
| `claude-skills/ship-workflow/lib/sync.sh` | Add `Roadmap-Notes/` mirror (vault → `docs/roadmap-notes/`) |
| `claude-skills/ship-workflow/templates/repo/BRAINSTORM.md` | Add `roadmap-note-ref` frontmatter field |
| `claude-skills/ship-workflow/commands/ship-next.md` | Add **step 4b. Explainer pre-flight** between picking R-NNN and entering brainstorm |
| `claude-skills/ship-workflow/commands/ship-roadmap.md` | Step 7: auto-run `/ship-explain` per newly decomposed child. Step 11: add "Now items missing `↳ explain:`" count to report |
| `claude-skills/ship-workflow/tests/test_roadmap-insert.bats` | +4 tests (3 for `--explain`, 1 for `--inject-explain`) |
| `claude-skills/ship-workflow/tests/test_sync.bats` | +2 tests (Roadmap-Notes mirror, atomic write) |

### Out-of-tree
| Path | Change |
|---|---|
| `~/.claude/commands/ship-explain.md` | Symlink → skill source |
| `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Roadmap-Notes/` | 8 new explainer notes (R-001 + R-001.1–.7) created during Task 10 |

---

## Task Right-Sizing Notes

10 tasks. Tasks 1-3 are pure bash + bats (strict TDD). Tasks 4-9 are mostly markdown (templates, command files) — TDD doesn't apply directly, so each ends with a smoke test (run the command on a known input + check the output) instead of a unit test. Task 10 is the live backfill, which doubles as the AC-009 acceptance check.

---

## Task 1: `roadmap-insert.sh --explain` flag (insert + child modes)

**Files:**
- Modify: `claude-skills/ship-workflow/lib/roadmap-insert.sh`
- Test: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`

**Interfaces:**
- Consumes: none (extends existing `insert` and `child` modes)
- Produces:
  - New CLI flag `--explain "<slug>"` accepted by `insert` and `child` modes.
  - When given, emits a new annotation line `↳ explain: [[Roadmap-Notes/<slug>]]` immediately above any `↳ done when:` annotation, with indent matching mode (`insert` = 4 spaces, `child` = 6 spaces).
  - When omitted, behavior is unchanged from current code.

### Step 1.1: Write failing tests

- [ ] Append the following bats tests to `tests/test_roadmap-insert.bats`:

```bash
@test "roadmap-insert: --explain writes a [[wikilink]] annotation (insert mode)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-040 "Add OTel tracing" \
    --explain "Roadmap-Notes/R-040-add-otel-tracing"
  grep -q '\*\*R-040\*\* Add OTel tracing' "$ROADMAP"
  grep -qF '↳ explain: [[Roadmap-Notes/R-040-add-otel-tracing]]' "$ROADMAP"
  # Annotation indented 4 spaces immediately below entry
  entry_ln=$(grep -n '\*\*R-040\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((entry_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain: \[\['
}

@test "roadmap-insert: --explain appears BEFORE --done-when when both given (insert mode)" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-041 "Wire SceneEngine" \
    --explain "Roadmap-Notes/R-041-wire-scene-engine" \
    --done-when "TTFB 不 regress"
  entry_ln=$(grep -n '\*\*R-041\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  explain_ln=$((entry_ln + 1))
  done_ln=$((entry_ln + 2))
  sed -n "${explain_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain: \[\['
  sed -n "${done_ln}p" "$ROADMAP" | grep -qE '^    ↳ done when:'
}

@test "roadmap-insert: --explain in child mode indents 6 spaces" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014 "Webhook retry" --epic
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-014.1 "Backoff layer" --child R-014 \
    --explain "Roadmap-Notes/R-014.1-backoff-layer"
  child_ln=$(grep -n '\*\*R-014\.1\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((child_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^      ↳ explain: \[\[Roadmap-Notes/R-014\.1'
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd claude-skills/ship-workflow && bats tests/test_roadmap-insert.bats 2>&1 | tail -25
```

Expected: 3 failures with messages indicating `--explain` is unrecognized (it falls through the `*) shift ;;` catch-all in the flag parser).

- [ ] **Step 1.3: Implement `--explain` flag**

Edit `lib/roadmap-insert.sh`:

**(a)** Update the header doc comment to list the new flag. Add this line under the `insert` mode usage block:

```
#       --explain    → add ↳ explain: [[<slug>]] annotation (positioned BEFORE done-when)
```

And add the same under the child-mode usage block.

**(b)** Add `EXPLAIN=""` to the flag-init block (next to `DONE_WHEN=""`):

```bash
EXPLAIN=""
```

**(c)** Add a case to the flag-parser `while` loop (next to the `--done-when)` case):

```bash
    --explain)      EXPLAIN="${2:-}"; shift 2 ;;
```

**(d)** In the `insert` mode body, after the `ANNOTATION=""` block, build the two-annotation suffix carefully. Replace this block:

```bash
    ANNOTATION=""
    [ -n "$DONE_WHEN" ] && ANNOTATION="    ↳ done when: ${DONE_WHEN}"

    awk -v line="$NEW_LINE" -v annot="$ANNOTATION" '
      { print }
      /^## 🔥 Now/ && !inserted {
        print line
        if (annot != "") print annot
        inserted = 1
      }
    ' "$ROADMAP" > "$TMP"
```

with:

```bash
    EXPLAIN_LINE=""
    DONE_LINE=""
    [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="    ↳ explain: [[${EXPLAIN}]]"
    [ -n "$DONE_WHEN" ] && DONE_LINE="    ↳ done when: ${DONE_WHEN}"

    awk -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
      { print }
      /^## 🔥 Now/ && !inserted {
        print line
        if (explain   != "") print explain
        if (done_line != "") print done_line
        inserted = 1
      }
    ' "$ROADMAP" > "$TMP"
```

**(e)** In the `child` mode body, replace the corresponding block similarly. The indent strings change from 4 to 6 spaces:

```bash
    EXPLAIN_LINE=""
    DONE_LINE=""
    [ -n "$EXPLAIN" ]   && EXPLAIN_LINE="      ↳ explain: [[${EXPLAIN}]]"
    [ -n "$DONE_WHEN" ] && DONE_LINE="      ↳ done when: ${DONE_WHEN}"

    awk -v parent="$CHILD_PARENT" -v line="$NEW_LINE" -v explain="$EXPLAIN_LINE" -v done_line="$DONE_LINE" '
      {
        print
        if (!inserted && match($0, "^- \\[ \\] (⚠️ )?\\*\\*" parent "(\\*\\*| )")) {
          print line
          if (explain   != "") print explain
          if (done_line != "") print done_line
          inserted = 1
        }
      }
    ' "$ROADMAP" > "$TMP"
```

- [ ] **Step 1.4: Run tests to verify pass**

```bash
bats tests/test_roadmap-insert.bats 2>&1 | tail -25
```

Expected: 20 tests pass (17 existing + 3 new), 0 fail.

- [ ] **Step 1.5: Run full suite to verify no regressions**

```bash
bats tests/ 2>&1 | tail -5
```

Expected: `61 + 3 = 64` tests pass (and full count incl. Task 1's tests).

- [ ] **Step 1.6: Commit**

```bash
git add claude-skills/ship-workflow/lib/roadmap-insert.sh \
        claude-skills/ship-workflow/tests/test_roadmap-insert.bats
git commit -m "feat(roadmap-insert): --explain flag emits [[wikilink]] annotation before done-when"
```

---

## Task 2: `roadmap-insert.sh --inject-explain` new mode

**Files:**
- Modify: `claude-skills/ship-workflow/lib/roadmap-insert.sh`
- Test: `claude-skills/ship-workflow/tests/test_roadmap-insert.bats`

**Interfaces:**
- Consumes: existing `insert`/`child` modes (uses same row-matching regex)
- Produces:
  - New mode invoked as `roadmap-insert.sh <ROADMAP> <R-NNN> --inject-explain "<slug>"`.
  - Modifies an EXISTING row in-place (does not create new row).
  - Behavior matrix:
    1. Row already has `↳ explain: [[Roadmap-Notes/<slug>]]` (same slug) → no-op, exit 0
    2. Row has no `↳ explain:` → insert `↳ explain: [[Roadmap-Notes/<slug>]]` immediately under the row, BEFORE any existing `↳ done when:` annotation. Indent = 4 for top-level row, 6 for child row.
    3. Row has `↳ explain: [[Roadmap-Notes/<other-slug>]]` (different slug) → replace, AND emit a stderr warning: `WARN: replacing explain annotation; old slug '<other-slug>' note remains on disk — archive/delete manually if no longer needed`. exit 0.

### Step 2.1: Write failing tests

- [ ] Append to `tests/test_roadmap-insert.bats`:

```bash
@test "roadmap-insert: --inject-explain adds explain annotation to existing row" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-050 "Refactor cache"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-050 --inject-explain "Roadmap-Notes/R-050-refactor-cache"
  grep -qF '↳ explain: [[Roadmap-Notes/R-050-refactor-cache]]' "$ROADMAP"
  entry_ln=$(grep -n '\*\*R-050\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  next_ln=$((entry_ln + 1))
  sed -n "${next_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain:'
}

@test "roadmap-insert: --inject-explain is idempotent on same slug" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 "Add tracing"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 --inject-explain "Roadmap-Notes/R-051-add-tracing"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-051 --inject-explain "Roadmap-Notes/R-051-add-tracing"
  count=$(grep -cF '↳ explain: [[Roadmap-Notes/R-051-add-tracing]]' "$ROADMAP")
  [ "$count" -eq 1 ]
}

@test "roadmap-insert: --inject-explain on different slug replaces + warns" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 "Add metrics"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 --inject-explain "Roadmap-Notes/R-052-old-slug"
  run "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-052 --inject-explain "Roadmap-Notes/R-052-new-slug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: replacing explain annotation"* ]]
  grep -qF '↳ explain: [[Roadmap-Notes/R-052-new-slug]]' "$ROADMAP"
  ! grep -qF '↳ explain: [[Roadmap-Notes/R-052-old-slug]]' "$ROADMAP"
}

@test "roadmap-insert: --inject-explain places annotation BEFORE existing done-when" {
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-053 "Wire X" --done-when "p95 < 100ms"
  "$SHIP_LIB/roadmap-insert.sh" "$ROADMAP" R-053 --inject-explain "Roadmap-Notes/R-053-wire-x"
  entry_ln=$(grep -n '\*\*R-053\*\*' "$ROADMAP" | head -1 | cut -d: -f1)
  explain_ln=$((entry_ln + 1))
  done_ln=$((entry_ln + 2))
  sed -n "${explain_ln}p" "$ROADMAP" | grep -qE '^    ↳ explain:'
  sed -n "${done_ln}p"    "$ROADMAP" | grep -qE '^    ↳ done when:'
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
bats tests/test_roadmap-insert.bats 2>&1 | tail -10
```

Expected: 4 failures (unknown flag `--inject-explain`).

- [ ] **Step 2.3: Implement `--inject-explain` mode**

In `lib/roadmap-insert.sh`:

**(a)** Add to flag parser:

```bash
    --inject-explain) MODE="inject-explain"; EXPLAIN="${2:-}"; shift 2 ;;
```

**(b)** Add a new case block after the existing `mark-epic)` case, before the closing `*)`:

```bash
  inject-explain)
    if [ -z "$EXPLAIN" ]; then
      echo "ERROR: --inject-explain requires a slug" >&2
      exit 2
    fi
    new_annot="↳ explain: [[${EXPLAIN}]]"
    awk -v rid="$RID" -v new_annot="$new_annot" '
      function indent_for(line) {
        if (match(line, /^  /)) return "      "
        return "    "
      }
      {
        if (!modified && match($0, "^(  )?- \\[ \\] (⚠️ )?\\*\\*" rid "(\\*\\*| )")) {
          row_line = $0
          row_indent = indent_for(row_line)
          print row_line
          # Look ahead at next line — may be existing explain annotation
          if ((getline nxt) > 0) {
            if (nxt ~ ("^" row_indent "↳ explain:")) {
              if (nxt == row_indent new_annot) {
                # Idempotent: same slug, keep as-is
                print nxt
              } else {
                # Different slug — replace + warn to stderr
                old = nxt
                sub("^" row_indent "↳ explain: \\[\\[", "", old)
                sub("\\]\\][[:space:]]*$", "", old)
                printf("WARN: replacing explain annotation; old slug %s note remains on disk — archive/delete manually if no longer needed\n", old) > "/dev/stderr"
                print row_indent new_annot
              }
            } else {
              # No existing explain; inject new annotation, then re-emit captured line
              print row_indent new_annot
              print nxt
            }
          } else {
            # Row was last line of file
            print row_indent new_annot
          }
          modified = 1
          next
        }
        print
      }
    ' "$ROADMAP" > "$TMP"
    if [ "$(grep -c "$RID" "$TMP")" -eq 0 ]; then
      echo "ERROR: row $RID not found in $ROADMAP" >&2
      rm -f "$TMP"
      exit 1
    fi
    mv "$TMP" "$ROADMAP"
    ;;
```

- [ ] **Step 2.4: Run tests to verify pass**

```bash
bats tests/test_roadmap-insert.bats 2>&1 | tail -10
```

Expected: 24 tests pass (17 base + 3 from Task 1 + 4 from Task 2), 0 fail.

- [ ] **Step 2.5: Run full suite**

```bash
bats tests/ 2>&1 | grep -E '^(ok|not ok)' | wc -l
bats tests/ 2>&1 | grep -c '^not ok '
```

Expected: 65+ ok lines, 0 not-ok.

- [ ] **Step 2.6: Commit**

```bash
git add claude-skills/ship-workflow/lib/roadmap-insert.sh \
        claude-skills/ship-workflow/tests/test_roadmap-insert.bats
git commit -m "feat(roadmap-insert): --inject-explain mode (idempotent, replaces with warning on slug change)"
```

---

## Task 3: `sync.sh` Roadmap-Notes mirror

**Files:**
- Modify: `claude-skills/ship-workflow/lib/sync.sh`
- Test: `claude-skills/ship-workflow/tests/test_sync.bats`

**Interfaces:**
- Consumes: nothing new
- Produces:
  - `sync.sh` now also mirrors `<project_path>/Roadmap-Notes/*.md` → `<repo>/docs/roadmap-notes/*.md` using the same atomic-write pattern as the existing `Proposals/` mirror.
  - If the source directory doesn't exist, sync skips silently (no warning).

### Step 3.1: Write failing tests

- [ ] Add to `tests/test_sync.bats`:

```bash
@test "sync: mirrors Roadmap-Notes/ to docs/roadmap-notes/" {
  notes_src="$AIROS/10 Projects/demo/Roadmap-Notes"
  mkdir -p "$notes_src"
  cat > "$notes_src/R-001-foo.md" <<'EOF'
---
type: roadmap-note
id: R-001
---
Test note.
EOF
  cd "$REPO" && "$SHIP_LIB/sync.sh" --force
  [ -f "$REPO/docs/roadmap-notes/R-001-foo.md" ]
  grep -q "Test note." "$REPO/docs/roadmap-notes/R-001-foo.md"
}

@test "sync: Roadmap-Notes mirror uses atomic write (no .tmp leftover)" {
  notes_src="$AIROS/10 Projects/demo/Roadmap-Notes"
  mkdir -p "$notes_src"
  echo "x" > "$notes_src/R-002-bar.md"
  cd "$REPO" && "$SHIP_LIB/sync.sh" --force
  ! ls "$REPO/docs/roadmap-notes/"*.tmp 2>/dev/null
}
```

- [ ] **Step 3.2: Run tests to verify they fail**

```bash
bats tests/test_sync.bats 2>&1 | tail -15
```

Expected: 2 failures (the destination directory or file doesn't exist after sync).

- [ ] **Step 3.3: Implement Roadmap-Notes mirror**

In `lib/sync.sh`, after the existing `VAULT_PROPOSALS` block (right before the freshness-marker write), append:

```bash
# Mirror vault Roadmap-Notes/ → repo docs/roadmap-notes/ (read-only one-way mirror).
VAULT_NOTES="$PROJECT_PATH/Roadmap-Notes"
REPO_NOTES="$REPO_ROOT/docs/roadmap-notes"
if [ -d "$VAULT_NOTES" ]; then
  mkdir -p "$REPO_NOTES"
  for f in "$VAULT_NOTES"/*.md; do
    [ -f "$f" ] || continue
    bn=$(basename "$f")
    cp "$f" "$REPO_NOTES/$bn.tmp"
    mv "$REPO_NOTES/$bn.tmp" "$REPO_NOTES/$bn"
  done
fi
```

- [ ] **Step 3.4: Run tests to verify pass**

```bash
bats tests/test_sync.bats 2>&1 | tail -15
```

Expected: all sync tests pass.

- [ ] **Step 3.5: Run full suite**

```bash
bats tests/ 2>&1 | tail -3
```

Expected: 67+ tests pass, 0 fail.

- [ ] **Step 3.6: Commit**

```bash
git add claude-skills/ship-workflow/lib/sync.sh \
        claude-skills/ship-workflow/tests/test_sync.bats
git commit -m "feat(sync): mirror Roadmap-Notes/ to docs/roadmap-notes/ with atomic write"
```

---

## Task 4: Templates (new ROADMAP-NOTE.md + modify BRAINSTORM.md)

**Files:**
- Create: `claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md`
- Modify: `claude-skills/ship-workflow/templates/repo/BRAINSTORM.md`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `ROADMAP-NOTE.md` template with frontmatter + section scaffolding per spec §4.1. Placeholders use `{{var}}` syntax matching existing templates.
  - `BRAINSTORM.md` gains `roadmap-note-ref` frontmatter field.

- [ ] **Step 4.1: Create ROADMAP-NOTE.md template**

Write `claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md`:

```markdown
---
date: {{date}}
updated: {{date}}
type: roadmap-note
id: {{id}}
parent: {{parent}}
tags: [roadmap-note, {{project}}]
ai-first: true
project: "[[{{project}}]]"
roadmap-row: {{id}}
proposal-ref: {{proposal_ref}}
status: live
---

## For future Claude
> {{id}} 的入門口袋書 — plain language 解釋這步在做什麼、為什麼做、用到的
> domain 名詞代表什麼。讀者:domain 不熟的 product owner / 新加入的工程師。
> Voice 規則:**不要直接抄 proposal 句子**。Rewrite into plain Chinese。第一次
> 出現的 domain 名詞 inline 定義(例:「SceneEngine(規則層,決定下一個 scene
> 演什麼)」)。避免「整合」「重構」這種抽象動詞,優先具象描述。

## 一句話總結
> {{one_liner}}

## 這步在做什麼
{{plain_what}}

## 為什麼要做這步
- **在 epic 的角色**:{{role_in_epic}}
- **沒做會怎樣**:{{cost_if_skipped}}
- **做完後玩家/系統會感覺到什麼**:{{user_visible_change}}

## 前後關係
- **依賴 (blocked-by)**: {{blocked_by}}
- **解鎖 (unblocks)**: {{unblocks}}
- **同 epic 兄弟**: {{siblings}}

## 用到的 domain 名詞
| 詞 | 是什麼 | 完整定義 |
|---|---|---|
{{glossary_rows}}

## 深入閱讀
{{deeper_reading_links}}
```

- [ ] **Step 4.2: Modify BRAINSTORM.md template**

Edit `claude-skills/ship-workflow/templates/repo/BRAINSTORM.md` — in the frontmatter, between `plan-path:` and `parent:`, add:

```yaml
roadmap-note-ref: "[[Roadmap-Notes/{{id}}-{{slug}}]]"
```

So the frontmatter block becomes:

```yaml
spec-path: docs/specs/{{id}}-{{slug}}.md
plan-path: docs/plans/{{id}}-{{slug}}.md
roadmap-note-ref: "[[Roadmap-Notes/{{id}}-{{slug}}]]"
parent: null   # if this is a child of an epic R-NNN, set to that R-NNN
```

- [ ] **Step 4.3: Smoke-test substitution**

Manually `cat` both files and confirm placeholders are present and well-formed:

```bash
grep -E '\{\{[a-z_]+\}\}' claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md | wc -l
grep -E '\{\{[a-z_]+\}\}' claude-skills/ship-workflow/templates/repo/BRAINSTORM.md   | wc -l
```

Expected: ROADMAP-NOTE has ≥ 11 placeholders; BRAINSTORM still has its original placeholders + 1 (the new `roadmap-note-ref` line).

- [ ] **Step 4.4: Commit**

```bash
git add claude-skills/ship-workflow/templates/obsidian/ROADMAP-NOTE.md \
        claude-skills/ship-workflow/templates/repo/BRAINSTORM.md
git commit -m "feat(templates): ROADMAP-NOTE.md vault template + BRAINSTORM gains roadmap-note-ref"
```

---

## Task 5: `/ship-explain` single R-NNN mode

**Files:**
- Create: `claude-skills/ship-workflow/commands/ship-explain.md`

**Interfaces:**
- Consumes:
  - `lib/airos-binding.sh project_path` (existing)
  - `lib/roadmap-insert.sh ... --inject-explain "<slug>"` (Task 2)
  - `lib/sync.sh --force` (Task 3, plus pre-existing)
  - `templates/obsidian/ROADMAP-NOTE.md` (Task 4)
- Produces:
  - New slash command `/ship-explain <R-NNN>`. Discoverable via Discord (`discord-visible: true`).
  - Side effects per spec §4.2.4: drafts vault note → sync → inject `↳ explain:` annotation into ROADMAP row → print summary → ask user "Read full? [Y/n/edit]".

- [ ] **Step 5.1: Create `commands/ship-explain.md`**

```markdown
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
```

- [ ] **Step 5.2: Symlink to user commands**

```bash
ln -sf ~/.claude/skills/ship-workflow/commands/ship-explain.md ~/.claude/commands/ship-explain.md
ls -la ~/.claude/commands/ship-explain.md
```

Expected: symlink listed, target = skill source.

- [ ] **Step 5.3: Smoke test (in ai-eden-service repo)**

```bash
# In a separate shell:
cd /Users/leric/Desktop/code/ai-eden-service
# Then invoke /ship-explain R-001.3 — Claude follows the .md instructions.
```

Manual checks after invocation:
- File `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Roadmap-Notes/R-001.3-*.md` exists.
- Mirror exists at `docs/roadmap-notes/R-001.3-*.md`.
- ROADMAP row R-001.3 now has `↳ explain: [[Roadmap-Notes/R-001.3-...]]` annotation.
- Annotation order: `↳ explain:` precedes `↳ done when:`.

(If anything fails, fix the .md instructions and re-run.)

- [ ] **Step 5.4: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-explain.md
git commit -m "feat(ship-explain): single-row mode (draft note + sync + inject annotation)"
```

---

## Task 6: `/ship-explain` bulk + force-refresh modes

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-explain.md`

**Interfaces:**
- Consumes: Task 5's single-row logic
- Produces:
  - `--all-now` and `--force-refresh <R-NNN>` modes documented per spec §4.2.1 + §6.3.

- [ ] **Step 6.1: Append `--all-now` and `--force-refresh` sections to ship-explain.md**

Append after the `## Failure modes` block (and before any trailing content):

```markdown
## Steps (--all-now mode)

1. **Parse "Now" section.** Read ROADMAP.md and collect every `**R-NNN[.M]**` ID under the `## 🔥 Now` heading, in document order (parent epic R-NNN first, then children R-NNN.M ascending).

2. **Filter.** For each `${ID}`, skip if:
   - Row already has `↳ explain:` annotation, OR
   - `$NOTES_DIR/${ID}-*.md` already exists on disk

3. **Sequential draft.** For each remaining `${ID}`, run the single-row mode steps 2-9, **but defer the user-interactive Step 10-11 prompt**. Print one-line progress per draft:
   ```
   ✓ R-001    (3 sections) → Roadmap-Notes/R-001-...md
   ✓ R-001.1  (5 sections) → Roadmap-Notes/R-001.1-...md
   ```

4. **Batch review prompt.** After all drafts done:
   ```
   📒 Drafted N explainer notes:
   - R-001   <one-liner>
   - R-001.1 <one-liner>
   ...

   Review all in $EDITOR? [Y/n/list]
   ```
   - `Y`: open `$NOTES_DIR/` directory (or sequentially open each file).
   - `list`: print each note's `## 一句話總結` + `## 為什麼要做這步`.
   - `n`: skip review.

5. **Atomic-ish rollback.** If any single draft fails midway, abort the rest. Prior drafts remain on disk; user may `git status` to inspect.

6. **Commit (single commit for the batch):**
   ```bash
   git add docs/product/ROADMAP.md docs/roadmap-notes/ docs/learnings/_log.md
   git commit -m "explain: backfill N notes for Now section"
   ```

## Steps (--force-refresh mode)

1. Confirm existing note file path: `$NOTES_DIR/${ID}-*.md`.
2. Read existing note → keep its frontmatter `date` field (preserve creation date), update `updated:` to today.
3. Re-run single-row mode steps 5-9 (gather context + draft + sync + inject — inject is no-op if slug unchanged).
4. **Show diff** between old and new before writing:
   ```
   diff -u <old-note> <new-draft>
   ```
   Ask: `Apply? [Y/n]`
5. On `Y`: atomic write, sync, commit.
6. On `n`: discard new draft, leave old in place.
```

- [ ] **Step 6.2: Smoke test --all-now (after Task 8 + 9 are in place)**

This test deferred to Task 10 (the actual backfill exercise covers it).

- [ ] **Step 6.3: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-explain.md
git commit -m "feat(ship-explain): --all-now bulk + --force-refresh modes"
```

---

## Task 7: `/ship-next` step 4b — Explainer pre-flight

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`

**Interfaces:**
- Consumes: `/ship-explain ${ID}` (Task 5) — invoked when no explainer exists.
- Produces:
  - New **step 4b** inserted between current step 4 (present top 1-2 + capture chosen ID) and step 5 (proceed to brainstorm).
  - Surfaces explainer summary to terminal before entering brainstorm.

- [ ] **Step 7.1: Edit ship-next.md**

In `commands/ship-next.md`, between the existing `4a. **Decompose-first if ⚠️ flagged.**` block and step `5. **Skip to "Common: Enter brainstorming" below**`, insert:

```markdown
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
```

- [ ] **Step 7.2: Smoke test**

Manual: in ai-eden-service repo, run `/ship-next` and pick R-001.3. Verify:
- (Before Task 10 backfill) prompt offers to run `/ship-explain R-001.3`.
- (After Task 10 backfill) explainer is loaded and summary is printed.

- [ ] **Step 7.3: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md
git commit -m "feat(ship-next): step 4b — explainer pre-flight surfaces note before brainstorm"
```

---

## Task 8: `/ship-roadmap` step 7 auto-explain + step 11 report

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-roadmap.md`

**Interfaces:**
- Consumes: `/ship-explain ${CHILD_ID}` (Task 5)
- Produces:
  - Step 7 (decompose) auto-runs `/ship-explain` for each newly-inserted child.
  - Step 11 (report) adds "Now items missing `↳ explain:`" count.

- [ ] **Step 8.1: Edit step 7 to auto-run /ship-explain per child**

In `commands/ship-roadmap.md`, locate the decompose loop in step 7 (the bash block starting with `# Convert parent to epic`). Append AFTER the child-insert `done` loop:

```markdown
   After all children inserted, **auto-draft an explainer note for each newly-created child** (and for the newly-converted epic parent):

   ```bash
   # Run /ship-explain inline for each newly-created child + the parent epic
   for cid in "R-NNN" "${CHILD_IDS[@]}"; do
     # Follow /ship-explain single-row mode steps for each cid
     # (the brainstorm session shares context, so re-reading proposal
     #  is cheap; explainers benefit from shared voice)
     ~/.claude/commands/ship-explain.md $cid    # conceptual — Claude follows command file
   done
   ```

   Rationale: at decompose time the brainstorm context is hot — Claude has the proposal, Architecture, and the rationale for the split all in mind. Generating explainers in the same session yields higher-quality, more consistent prose than deferring to a later `/ship-explain --all-now`.
```

- [ ] **Step 8.2: Edit step 11 (report) to add missing-explainer count**

In the same file, locate the step 11 `**Report:**` block. After the existing bullet `**Count of items in "Now" missing `↳ done when:` annotation.**`, add:

```markdown
    - **Count of items in "Now" missing `↳ explain:` annotation.** This is the comprehension health metric — target zero. Suggested fix:
      ```
      $ /ship-explain --all-now      ← drafts explainers for every Now item without one
      ```
```

- [ ] **Step 8.3: Smoke test (after Task 10)**

Run `/ship-roadmap` in a project with a flagged ⚠️ item; verify decompose flow auto-runs `/ship-explain` per child and step 11 report includes the new count.

- [ ] **Step 8.4: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-roadmap.md
git commit -m "feat(ship-roadmap): auto-explain per decomposed child + missing-explainer count in report"
```

---

## Task 9: Install + verify all commands

**Files:**
- None modified (symlink + verification only)

**Interfaces:**
- Consumes: Tasks 5-8 outputs
- Produces:
  - `~/.claude/commands/ship-explain.md` symlink to skill source (if Task 5.2 was skipped or stale)
  - Verified ROADMAP integrity in ai-eden-service vault + repo mirror

- [ ] **Step 9.1: Ensure ship-explain symlink exists**

```bash
ln -sf ~/.claude/skills/ship-workflow/commands/ship-explain.md ~/.claude/commands/ship-explain.md
ls -la ~/.claude/commands/ship-*.md | wc -l
```

Expected: ≥ 10 symlinks (was 9, +1 new ship-explain).

- [ ] **Step 9.2: Full bats suite green**

```bash
cd /Users/leric/Desktop/code/ai_system/claude-skills/ship-workflow && bats tests/
```

Expected: all tests pass (67+ total).

- [ ] **Step 9.3: Sanity-check existing commands didn't regress**

```bash
# These should produce help text or sane errors, not 'invalid command'.
~/.claude/skills/ship-workflow/lib/roadmap-insert.sh 2>&1 | head -5
~/.claude/skills/ship-workflow/lib/sync.sh --force 2>&1 | head -5
```

Expected: both run without unrecognized-flag errors.

- [ ] **Step 9.4: No commit (verification-only task)**

---

## Task 10: Backfill ai-eden-service (8 explainer notes)

**Files:**
- Create (in vault): `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Roadmap-Notes/R-001-*.md` (1 file)
- Create (in vault): `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Roadmap-Notes/R-001.{1..7}-*.md` (7 files)
- Modify (in vault): `/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/ROADMAP.md` (add `↳ explain:` annotations to all 8 rows)
- Mirror-only (auto via sync): `/Users/leric/Desktop/code/ai-eden-service/docs/roadmap-notes/*.md` (8 files)

**Interfaces:**
- Consumes: `/ship-explain --all-now` (Task 6)
- Produces:
  - 8 explainer notes in ai-eden-service vault
  - 8 mirrored copies in repo
  - ROADMAP rows updated with `↳ explain:` annotations
  - AC-009 satisfied (user subjective acknowledgement: "現在打開 ai-eden-service ROADMAP + 點任一 R-001.x explainer,我懂這步在做什麼")

- [ ] **Step 10.1: Verify pre-conditions**

```bash
ls "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Proposals/" \
  | grep "R-001-story-generation"
```

Expected: proposal `2026-06-15-R-001-story-generation-pipeline-proposal.md` exists (it does — confirmed during brainstorm).

```bash
ls "/Users/leric/Documents/SecondBrain/10 Projects/ai-eden-service/Architecture/overview.md"
```

Expected: file exists.

If either is missing, halt and fix before proceeding.

- [ ] **Step 10.2: Pull current ROADMAP into mirror**

```bash
cd /Users/leric/Desktop/code/ai-eden-service
~/.claude/skills/ship-workflow/lib/sync.sh --force
```

- [ ] **Step 10.3: Run /ship-explain --all-now**

In Claude session, run:

```
/ship-explain --all-now
```

Claude will produce drafts for R-001 + R-001.1 .. R-001.7 = 8 files, in sequence. Print per-file one-line summaries.

Expected console output ends with:

```
📒 Drafted 8 explainer notes:
- R-001    <one-liner>
- R-001.1  <one-liner>
- R-001.2  <one-liner>
- R-001.3  <one-liner>
- R-001.4  <one-liner>
- R-001.5  <one-liner>
- R-001.6  <one-liner>
- R-001.7  <one-liner>

Review all in $EDITOR? [Y/n/list]
```

- [ ] **Step 10.4: Manual review**

For each of the 8 notes, open and verify:
- All required sections present (per Task 4's template)
- `## 一句話總結` reads as plain Chinese (not a copy of proposal §1)
- Domain terms (SceneEngine, stable-prefix cache, D-004, etc.) defined inline or in `## 用到的 domain 名詞` section
- Wikilinks to proposal § + Architecture modules in `## 深入閱讀`

If any note has issues, run `/ship-explain --force-refresh R-001.X` and iterate.

- [ ] **Step 10.5: Verify ROADMAP row injections**

```bash
grep -c '↳ explain:' /Users/leric/Documents/SecondBrain/10\ Projects/ai-eden-service/ROADMAP.md
```

Expected: 8.

```bash
grep -B1 '↳ explain:' /Users/leric/Documents/SecondBrain/10\ Projects/ai-eden-service/ROADMAP.md \
  | grep -E '\*\*R-001' | wc -l
```

Expected: 8 (each `↳ explain:` annotation immediately follows an R-001 row).

- [ ] **Step 10.6: Verify repo mirror updated**

```bash
ls /Users/leric/Desktop/code/ai-eden-service/docs/roadmap-notes/ | wc -l
```

Expected: 8.

- [ ] **Step 10.7: AC-009 — user acceptance**

Print the user-facing check:

> Open `ai-eden-service` ROADMAP.md, click into any R-001.x explainer note. Does it answer "what is this step doing" in plain Chinese without making you open the proposal? **Yes / No?**

If `Yes`: AC-009 satisfied. Commit.
If `No`: identify which notes failed the test, `/ship-explain --force-refresh` them, repeat.

- [ ] **Step 10.8: Commit (ai-eden-service repo)**

```bash
cd /Users/leric/Desktop/code/ai-eden-service
git add docs/product/ROADMAP.md docs/roadmap-notes/ docs/learnings/_log.md
git commit -m "explain: backfill 8 notes for R-001 epic + R-001.1-.7 (Phase 5 of explainer rollout)"
```

(Vault side commits happen via the 6h launchd auto-push.)

---

## Self-Review (run after the plan is fully drafted)

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 Artifact location | Task 3 (sync) + Task 5 (write path) |
| §3.2 ROADMAP annotation format | Tasks 1, 2 |
| §3.3 Artifact relationship diagram | Documented in plan header (no impl) |
| §3.4 Lifecycle (loose coupling) | Task 8 step 11 stale-detection note |
| §4.1 Template + section scaling | Task 4 + Task 5 prompt rules |
| §4.2 /ship-explain modes | Tasks 5, 6 |
| §4.3 roadmap-insert.sh --explain | Task 1 |
| §4.4 /ship-next integration | Task 7 |
| §4.5 /ship-roadmap integration | Task 8 |
| §4.6 BRAINSTORM frontmatter | Task 4 step 4.2 |
| §6 Backfill plan | Task 10 |
| §7 AC-001..AC-009 | Tasks 1, 5, 5, 6, 7, 7, 8, 1+2+3, 10 (respectively) |

All sections covered.

**2. Placeholder scan:**
- No `TBD` / `TODO` / `fill in later` anywhere.
- All code blocks are complete.
- All test cases have full bats syntax.

**3. Type consistency:**
- `--explain "<slug>"` flag accepts a slug (e.g. `Roadmap-Notes/R-001.3-wire-scene-engine`) — same shape across Tasks 1, 2, 5, 6, 7.
- `--inject-explain` mode signature consistent: `roadmap-insert.sh <ROADMAP> <R-NNN> --inject-explain "<slug>"`.
- Indent rules ("4 for top-level, 6 for child") repeated identically in Task 1 (--explain) and Task 2 (--inject-explain).
- Annotation order ("explain before done-when") asserted in tests in both Task 1 and Task 2.

All consistent.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-17-roadmap-explainer-notes-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for the 10 tasks here because Tasks 1-3 are highly mechanical (TDD bash) and well-suited to disposable subagents.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch with checkpoints. Best if you want to review code as I type it.

Which approach?

## Execution log

### Codex run 2026-06-17 (PID 46864, codex-cli 0.134.0, reasoning=high)
Status: **DONE_WITH_CONCERNS**. 8 commits b49a954..96793cf. Full `bats tests/` suite green (70/70).

- Task 5.2 deferred by codex — skipped symlink/listing under `~/.claude/` per repository-only execution constraint.
- Task 5.3 deferred: requires Claude `/ship-explain` invocation; covered by Task 10 backfill.
- Task 6.2 deferred — requires `/ship-explain --all-now` live backfill, covered by Task 10.
- Task 7.2 deferred: requires Claude `/ship-explain` invocation; covered by Task 10 backfill.
- Task 8.3 deferred: requires Claude `/ship-explain` invocation; covered by Task 10 backfill.
- Task 9.1 deferred by codex — skipped symlink/listing under `~/.claude/` per repository-only execution constraint.
- Task 10 deferred — requires interactive Claude session in ai-eden-service repo.

### Post-codex follow-up by Claude (2026-06-17)
- **Task 5.2 / 9.1 completed**: symlinked `~/.claude/commands/ship-explain.md` → skill source. `~/.claude/commands/ship-*.md` now shows 10 symlinks (was 9).
- **Task 10 next**: requires running `/ship-explain --all-now` in `/Users/leric/Desktop/code/ai-eden-service` to backfill 8 explainer notes for R-001 epic + R-001.1–.7.
