# obsidian-architect v4.2 — features.md (Product PM lens + doc-sync drift) Design

**Status:** Draft — ready for review
**Date:** 2026-05-28
**Author:** brainstormed with user (Eugeniu)
**Related specs:**
- [2026-05-27-obsidian-architect-v4-design.md](./2026-05-27-obsidian-architect-v4-consolidated-report-design.md) — v4 consolidated report frame
- [2026-05-28-obsidian-architect-v4.1-ai-flows-design.md](./2026-05-28-obsidian-architect-v4.1-ai-flows-design.md) — v4.1 AI flow layer
- (planned) `/obsidian-roadmap` Phase 1 candidate detector

---

## Goal

Re-introduce `Projects/<P>/Architecture/features.md` as an **additive 9th file** in the v4 family, providing a **product-PM lens** complementary to:

- `overview.md` — system architect lens (top-down report)
- `modules/*.md` — module-author lens (technical judgment)
- `ai-flows/*.md` — AI engineer lens (subsystem deep dive)
- `decisions.md` — decision archivist lens (ADR candidates + technical debt)
- `personas.md` — UX researcher lens (user types)
- **`features.md` — product-PM lens (NEW: feature inventory + doc-sync drift + product gap analysis)**

The file answers three product-level questions a maintainer / PM / sales contact needs:

1. **What does this product actually offer today?** (capability inventory, online vs deprecated)
2. **Are our user-facing docs honest?** (doc-sync drift: deprecated features still in README; online features with no docs)
3. **What should the product offer that it doesn't?** (gap analysis grounded in vault `Research/` notes + persona jobs)

## Non-goals

- NOT a marketing landing page or sales sheet.
- NOT a replacement for `overview.md ## 核心能力` — overview's 7 capability areas stay; features.md is the granular drilldown (~25-40 rows).
- NOT a replacement for `decisions.md ## 已知限制` — that captures technical debt; features.md `## limitations` captures product boundaries (channel coverage, scaling caps, integration requirements).
- NOT an example-use-case page — overview.md already has 5 Mermaid flows for that; further user-story content belongs in `personas.md`.
- NOT a deduplication of per-module strengths/weaknesses — features.md `## strengths/weaknesses` are PM-voice (product set health), not technical-voice (refactor priorities).

## Frame & file shape

**File:** `Projects/<P>/Architecture/features.md`
**Type (frontmatter):** `architecture-features` — un-deprecates the v3 type. `DEPRECATED_SECTIONS` in `sections.py` loses `"features"`.
**Frame:** Stays `report-v4` — no lockfile schema bump. Just adds `sections.features` slot in lockfile.
**Lang:** Respects vault `output-lang` (zh-TW default).
**Lifecycle:** Additive. Existing v4 vaults get features.md on next `/obsidian-architect` run (no migration). v3→v4 migration still deletes the *old* v3 features.md (different format); new format is written by the post-migration scan.

## Body block design

Ten `<!-- @generated:start <name> -->` blocks. (Note: the trailing `## Related` block with `[[overview]]` + `[[<project>]]` wikilinks is hardcoded by `compose_note` — separate from the 10 LLM-generated blocks here.) Canonical English H2 heading mapping per existing `_BLOCK_HEADINGS` convention (translated via `lang.heading()`):

| # | Block name | H2 (zh-TW) | H2 (en) | Content |
|---|------------|------------|---------|---------|
| 1 | `summary` | `## 摘要` | `## Summary` | 1 short paragraph. Product 做什麼;偵測到 N 個 capability;X 個 online、Y 個 deprecated;doc-sync 健康分數 (% online_with_docs ÷ online_total). |
| 2 | `capability-inventory` | `## 能力清單` | `## Capability inventory` | Markdown table. Columns: `Capability \| Description (≤80 char) \| Status \| Last touch \| Doc anchors \| Code anchors \| Module`. Status = `online`/`deprecated` (deterministic, post-LLM). Last touch = `YYYY-MM` (git log most recent commit on any code_anchor file). Code anchors = wikilink to `[[modules/<host>]]` + `path:line` ranges. Doc anchors = README section name / AGENTS.md line range / CHANGELOG bullet. |
| 3 | `product-coverage` | `## 產品覆蓋度` | `## Product coverage` | PM lens aligning capabilities to persona jobs (if `personas.md` exists). For each persona, list which capabilities their typical jobs hit. Mark gaps: ✅ covered / ⚠️ partial / ❌ missing. Skipped if no `personas.md`. |
| 4 | `limitations` | `## 產品邊界 / Limitations` | `## Limitations` | Objective product boundaries (3-7 bullets). Not opinions. Examples: "只支援 LINE,不支援 WhatsApp/Telegram/Messenger";"最多 N 個 admin per tenant (`MAX_ADMIN_PER_TENANT` env)";"KB 必依賴 Confluence,無法純本地運作";"無多租戶 — 一個 deployment 一個 OA";"無 message scheduling". Each bullet may cite `code:path:line` or env var for grounding. |
| 5 | `strengths` | `## Product 優點` | `## Product strengths` | 3-5 PM-voice tight bullets. Format: `**Title (≤30 char).** clarification (≤80 char)`. PM-voice ban list: "god module", "refactor", "type safety", "test coverage" — these are tech voice. Allowed: "完整 ticket lifecycle", "客服 onboarding 路徑暢通", "報表足以打董事會月會". |
| 6 | `weaknesses` | `## Product 缺點` | `## Product weaknesses` | 3-5 PM-voice tight bullets. Same shape as strengths. Allowed examples: "單一 channel 假設 — 整個 stack 只認 LINE", "客服需要切換 3 個 view 才能...", "夜班客服無法跨班接手". Same ban list. |
| 7 | `missing-features` | `## 可加 features (gap analysis)` | `## Missing features (gap analysis)` | 3-5 H3 entries. Each entry: name (H3) + **為什麼該有**: 1 sentence + **Evidence**: must be one of (a) `[[Research/<note>]]` wikilink to vault research note, (b) `[[Architecture/personas#<persona>]]` persona job pointer, (c) `code:path:line` showing a pattern that begs the feature + **Effort**: S/M/L/XL + **Confidence**: `stated` (research-backed) / `high` (persona-backed) / `medium` (code-pattern hint) / `speculation` (no evidence — flagged as "speculation; needs research") + **對哪個 module 開門**: `[[modules/<slug>]]` wikilink. |
| 8 | `improvements` | `## Product 改進方向` | `## Product improvements` | 3-5 Imps, standard `ImprovementItem` shape (`Why / Evidence / Effort / Risk / Confidence`). **PRODUCT direction**, not technical refactor. Imp examples: "深化 assist 模式 (而非擴 admin dashboard)", "把 KB candidate UX 從 review-flow 改成 inline-suggestion". |
| 9 | `doc-sync-actions` | `## 文件補補丁` | `## Doc sync actions` | Actionable doc-cleanup todos in 2 groups: **`### 清除 deprecated 殘留`** (orphan README/AGENTS mentions of dead features) + **`### 補缺 doc`** (online features with no README/AGENTS coverage). Each todo is 1 line, machine-actionable: `- [ ] Remove "/old-endpoint" mention from README.md L42-48`, `- [ ] Add "Knowledge Base" section to README listing /kb-candidates/* endpoints`. Format compatible with checkbox toggling. |
| 10 | `dependencies` | `## 相關連結 / Dependencies` | `## Dependencies` | Wikilinks only. `[[Architecture/overview]]` / each referenced `[[Architecture/modules/<slug>]]` / `[[Architecture/personas]]` / each `[[Architecture/ai-flows/<slug>]]` referenced / each `[[Research/<note>]]` referenced in `missing-features` evidence. |

(Sentinel block count = 10; originally proposed at 10 then dropped `doc-drift-detail` per user feedback "drift 應該只要分 online 和 deprecated 吧 看 git 就知道",then added `limitations` per follow-up question, landing back at 10.)

## Frontmatter

```yaml
---
type: architecture-features
date: YYYY-MM-DD
project: "[[<project-name>]]"
local-path: "/abs/path/to/repo"           # or repo: "<url>" depending on `_repo_yaml_lines` rule
last-scanned: YYYY-MM-DD
commit: <sha>
sources: ["README.md", "AGENTS.md", "CHANGELOG.md", "scan: api_surface", "manifest: modules", "vault: Research/*", "vault: personas.md"]
confidence: high                          # high when api_surface complete + research excerpts present
lang: <output_lang>
tags: [architecture, features]
ai-first: true
status: current
feature-count: 32                         # rows in capability-inventory
deprecated-count: 3                       # rows where status=deprecated
doc-sync-score: 0.87                      # online_with_doc / online_total, 0..1, 2 decimal
---
```

`feature-count` / `deprecated-count` / `doc-sync-score` are 3 NEW fields. Computable by Obsidian DataView for cross-project comparison.

## Scanner additions (Phase 1 deterministic, `architect_scan.py`)

`scan_report.json` gets three new top-level keys (or sub-keys under existing structure):

```jsonc
{
  // ... existing keys ...
  "agents_md_text": "<raw AGENTS.md content, capped 20KB>",
  "research_excerpts": [
    {
      "path": "Research/2026-04-line-bot-trends.md",   // path RELATIVE to project hub root (vault-relative)
      "title": "LINE bot 2026 趨勢",                    // from frontmatter `title:` or first H1
      "first_para": "<≤500 char>",                     // first non-blank paragraph after frontmatter
      "tags": ["competitor", "line"],
      "date": "2026-04-15"                             // from frontmatter
    }
    // walked from <vault>/Projects/<P>/Research/*.md (recursive)
    // cap: 10 files OR total 10KB of excerpts (whichever first)
    // ordering: most recent `date:` frontmatter first
  ],
  "git_last_touch": {
    "backend/app/api/auth.py": "2026-05-20",
    "backend/app/api/admin.py": "2025-09-12"
    // ... per file appearing in api_surface (HTTP routes / CLI commands / exports)
    // populated via `git log -1 --format=%ad --date=short -- <file>`
    // for files not under git or never committed: omitted (post-processor treats as "unknown")
  }
}
```

### Why scanner reads vault, not just repo

Existing scanner only reads `<repo>/`. For `research_excerpts` it must additionally read `<vault>/Projects/<P>/Research/`. This is a **new dependency direction** (scanner → vault). Implementation:

- `architect_scan.py --out` already accepts an output dir; add `--vault-project-dir <path>` flag (the slash command body resolves this and passes it in).
- New helper `scripts.architect.research_walker.collect_research_excerpts(project_dir: Path) -> list[dict]`. Pure-function; testable with fixture vault.
- If `project_dir` not passed or doesn't exist → `research_excerpts: []`. Scanner doesn't crash; LLM gracefully synthesizes without research evidence (and downgrades affected `missing-features` to `Confidence: speculation`).

### git_last_touch

- New helper `scripts.architect.git_history.last_touch_map(repo: Path, files: list[str]) -> dict[str, str]`.
- Uses `subprocess.run(["git", "log", "-1", "--format=%ad", "--date=short", "--", file], ...)` per file.
- For very large `api_surface` (>200 files): cap at 200 most-recently-modified files (mtime-sorted) to keep scan ≤ 5s.
- Failures (file not under VCS, repo dirty, etc.) → key omitted from map; post-processor treats omitted as `unknown` and shows `—` in the Last touch column.

### Two-pass synthesis (deterministic deprecated detection)

The LLM never decides online vs deprecated. Flow:

1. **Pass 1 (LLM):** `build_features_prompt(...)` (NEW in `sections.py`) requests a JSON object with all 9 block bodies. For `capability-inventory`, the LLM returns a **structured list** (NOT markdown table), each row a dict:
   ```json
   {
     "name": "客服回覆與媒體上傳",
     "description": "支援文字、圖片、檔案、影片四種 reply",
     "code_anchors": ["backend/app/api/workspace.py:/agent-reply", "backend/app/api/workspace.py:/reply-images"],
     "doc_anchors": ["README.md#Conversation Workspace", "AGENTS.md L17-19"],
     "module": "backend"
   }
   ```
   Other 8 block bodies are returned as raw markdown strings.

2. **Pass 2 (deterministic post-processor in `sections.py:render_features_inventory(...)`):** For each row:
   - For each `code_anchor` (parse as `<file_path>:<endpoint_or_symbol>`), check existence in `scan_report.api_surface` (HTTP routes have a `path` field; CLI commands have a `name`; exports have a `name`).
   - If ANY anchor matches → `status = "online"`, `last_touch = git_last_touch[file]` (or `unknown`).
   - If NONE match → `status = "deprecated"`, `last_touch = "—"`.

3. **Render:** Post-processor converts the now-status-annotated list into the markdown table format described in Block 2 design. The table is the `capability-inventory` block body passed to `compose_note(...)`.

This 2-pass design ensures:
- LLM hallucinations on endpoint paths don't produce false-positive `online`s.
- Adding new `status` enums later (e.g. `beta`) doesn't require prompt changes.
- The deterministic table column ordering is consistent across runs (LLM ordering is stable but post-processor sorts within each status group by `last_touch` desc).

### Doc-sync detection (also deterministic)

For each `online` row, the post-processor checks:
- Does any string in `code_anchors` correspond to text mentioned in `readme_sections` (case-insensitive substring) → contributes to "has README doc"?
- Same for `agents_md_text`.
- Same for `changelog`.

`doc-sync-score` = `count(online rows with ≥1 of {readme, agents, changelog} mention) ÷ count(online rows)`, rounded to 2 decimals.

Doc-sync action lists (block 9 input):
- **清除 deprecated 殘留:** for each deprecated row, list every (README/AGENTS) line where its anchors are still mentioned. LLM block-9 prose wraps these into machine-actionable checkbox lines.
- **補缺 doc:** for each online row with 0 doc mentions, list `(name, module)`. LLM block-9 prose suggests where to add the doc reference.

The LLM RECEIVES this evidence in the prompt input; LLM does not invent doc anchors. This keeps `doc-sync-actions` factual.

## Refresh logic

`features` section's `signal-hash` (in lockfile `sections.features.signal-hash`) is computed over the SHA-256 of canonical JSON of:

```python
{
  "readme_sections": scan_report["readme_sections"],
  "agents_md_text": scan_report["agents_md_text"],
  "changelog": scan_report["changelog"],
  "api_surface": scan_report["api_surface"],
  "research_excerpts": [
    {"path": r["path"], "mtime": stat(r["path"]).mtime} for r in research_excerpts
  ],
  "personas_hash": sha256(personas.md content)  # or None if file absent
}
```

Notes:
- `git_last_touch` is NOT in the signal hash. Every scan recomputes it from git; it's display-only. Including it would force re-synthesis on every commit, defeating refresh.
- `research_excerpts` uses `mtime` (per file) not content hash, to keep computation cheap. Adding/renaming a Research note always triggers re-synthesis; editing one within the same minute will also.
- Personas hash uses content (small file). Persona job changes ARE meaningful for `product-coverage` block.

If `signal-hash` unchanged AND existing `features.md` exists AND not `--force`/`--refresh`: skip synthesis, leave file untouched.

## Roadmap (`/obsidian-roadmap`) integration

`scripts/roadmap/candidates.py:detect_candidates(project_dir)` walks one additional file when `Projects/<P>/Architecture/features.md` exists. Three new source buckets:

| Block parsed in features.md | Candidate type | Default priority | Effort source |
|---|---|---|---|
| `## Product 改進方向` (block `improvements`) | `feature-improvement` | `normal` | block-provided |
| `## 可加 features (gap analysis)` (block `missing-features`) | `missing-feature` | **`high` if any `[[Research/...]]` wikilink in Evidence; `normal` otherwise** | block-provided |
| `## 文件補補丁` (block `doc-sync-actions`) | `doc-action` | `low` (allowed to bulk-mark done) | inferred (S for each line) |

Parser uses the existing `parse_improvements_block` for blocks 8 + 7 (both follow ImprovementItem shape). Block 9 uses a new parser `parse_doc_actions_block` that splits on `- [ ]` checkboxes.

### Dedup with module-level Imps

The user's earlier brainstorm requested deduplication. Implementation:

- After candidate detection, compare Evidence wikilinks across candidates.
- If a `feature-improvement` from `features.md` and an `improvement` from `modules/<slug>.md` cite identical or overlapping Evidence wikilinks → keep the `features.md` version as primary (PM angle gets the title), demote the module version to a child-candidate referenced by ID.
- This avoids double-counting in Roadmap.md totals.

## Command surface

`/obsidian-architect` (existing slash command body extended):

- **`--no-features`** — new flag. Default OFF. When ON, skip Phase 3.5.5 (features synthesis below).
- **`--features-only`** — diagnostic flag. Run only Phase 1 (scan) + Phase 3.5.5 (features synth). Useful for iterating on the features prompt without re-running other sections.
- All existing flags (`--frame`, `--refresh`, `--lang`, `--functions`, `--skip-sections`, `--no-ai-flows`, etc.) continue to work.

`--skip-sections=features` is also supported for symmetry with other sections.

### Phase 3.5.5 in command body (between existing 3.5 and 3.7)

Inserted into the slash command body between Phase 3.5 (decisions/personas synthesis) and Phase 3.7 (AI flow synthesis):

```text
## Phase 3.5.5: Features synthesis (v4.2)

Skip if `--no-features` OR if `sections.features.signal-hash` in lockfile matches current scan signal hash AND `features.md` exists.

1. Resolve research excerpts: scan walked Projects/<P>/Research/ for excerpts.
2. Resolve git_last_touch map: scan computed per-file last-commit dates.
3. Build prompt: scripts.architect.sections.build_features_prompt(...)
4. Invoke LLM. Expect strict JSON: 9 keys (capability-inventory as structured list, others as markdown).
5. Two-pass annotation: scripts.architect.sections.render_features_inventory(llm_inventory, api_surface, git_last_touch) → markdown table + status counts.
6. Compute doc-sync-score per Doc-sync detection rules above.
7. compose_note(section="features", project=<P>, ...) with extra frontmatter (feature-count, deprecated-count, doc-sync-score) merged before ai-first: true.
8. Write to Projects/<P>/Architecture/features.md.
9. Update lockfile sections.features (signal-hash / lang / commit / feature-count / deprecated-count / doc-sync-score).
```

## Hub note + overview wikilinks

After Phase 3.5.5 succeeds:

- Project hub `## 架構` block (`Projects/<P>/<P>.md`): add ONE new line BEFORE the `重新整理:` line:
  ```
  - 產品 feature inventory + doc-sync: [[Architecture/features]] (feature-count + doc-sync-score, see frontmatter)
  ```
- `overview.md ## 想深讀的入口` (`drill-down` block): add ONE new line BETWEEN `模組設計判斷` and `AI Flows 深判斷`:
  ```
  - **產品 feature inventory:** [[features]] (online/deprecated 狀態 + gap analysis + 文件補補丁)
  ```

Both edits are idempotent (sentinel-aware in hub block; line-presence-check in overview).

## Migration / existing vault handling

- **v4 vault, no features.md** (current langlive state): Phase 3.5.5 writes the file. No migration.
- **v4 vault, features.md already exists from this feature**: signal-hash comparison; refresh or skip per refresh logic.
- **v3 vault**: v3→v4 migration still deletes the legacy `features.md` (different block schema). After migration, Phase 3.5.5 runs and writes new format.
- **Lockfile**: no schema bump (still `version: 4`, `frame: report-v4`). New `sections.features` slot is additive; old lockfiles missing the slot are treated as "no prior synthesis".

## Lockfile fields (`sections.features`)

```jsonc
{
  "sections": {
    "features": {
      "signal-hash": "sha256:...",
      "lang": "zh-TW",
      "last-generated": "YYYY-MM-DD",
      "commit": "<sha>",
      "feature-count": 32,
      "deprecated-count": 3,
      "doc-sync-score": 0.87
    }
  }
}
```

## Tests

TDD coverage required (`tests/architect/test_features.py`):

1. **`test_build_features_prompt_includes_research_excerpts`** — when `research_excerpts` non-empty, prompt body contains research title + first_para.
2. **`test_build_features_prompt_omits_personas_when_absent`** — `product-coverage` directive absent from prompt when `personas.md` doesn't exist.
3. **`test_render_features_inventory_marks_online_when_anchor_in_api_surface`** — given LLM inventory + api_surface containing matching path, status="online".
4. **`test_render_features_inventory_marks_deprecated_when_no_anchor_matches`** — given LLM inventory + api_surface NOT containing any anchor, status="deprecated".
5. **`test_render_features_inventory_last_touch_from_git_map`** — last_touch column populated from git_last_touch map; missing keys render as "—".
6. **`test_compute_doc_sync_score`** — given 10 online rows where 7 have at least one doc anchor mention found in readme/agents/changelog text, score = 0.7.
7. **`test_collect_research_excerpts_walks_recursively`** — fixture vault with `Research/A.md` + `Research/sub/B.md`; both returned.
8. **`test_collect_research_excerpts_caps_at_limit`** — fixture with 15 notes; returns first 10 by date desc.
9. **`test_collect_research_excerpts_returns_empty_when_dir_missing`** — no `Research/` dir → empty list, no crash.
10. **`test_last_touch_map_for_files_under_git`** — git fixture with known commit history; returns expected dates.
11. **`test_last_touch_map_omits_unknown_files`** — files never committed → key absent (not "—" placeholder).
12. **`test_signal_hash_includes_research_mtime`** — touching a Research file changes signal_hash; touching git_last_touch does NOT.
13. **`test_signal_hash_includes_personas_content`** — editing personas.md changes hash.
14. **`test_compose_features_note_emits_extra_frontmatter`** — output contains `feature-count` / `deprecated-count` / `doc-sync-score` keys before `ai-first: true`.
15. **`test_detect_candidates_walks_features_md`** — `/obsidian-roadmap` candidate detector picks up `missing-features` block; research-backed entries get `priority=high`.
16. **`test_detect_candidates_dedup_features_vs_module`** — when features.md Imp and module.md Imp cite same Evidence wikilink, keep features.md as primary.

End-to-end smoke test (against `langlive-line-oa`): run `/obsidian-architect /Users/leric/Desktop/code/langlive-line-oa --features-only` → verify `features.md` written with non-zero `feature-count`, deprecated-count = 0 expected (no Research/ notes exist yet so all `missing-features` will carry `Confidence: speculation`).

## Open questions resolved

- **Q: Should we add `## limitations` (product boundaries) and `## example use case`?**
  A: Add `limitations` — fills a non-redundant PM-level gap. Skip `example use case` — duplicates `overview.md ## 核心使用流程`.
- **Q: Drift taxonomy granularity?**
  A: Just `online` vs `deprecated`. User: "Drift 應該只要分 online 和 deprecated 吧 看 git 就知道". 5-state taxonomy was over-engineered.
- **Q: Where does PM-angle gap analysis source from?**
  A: Codebase + vault `Research/<P>/*` excerpts. Single source = codebase-only was less differentiated; codebase + personas is fine but Research adds competitive grounding.
- **Q: Per-feature 優缺點 or file-level?**
  A: File-level. User wanted PM voice considering the ENTIRE feature set holistically, not per-row noise. Per-row in inventory is fact-only.

## Out of scope (deferred to future v4.x)

- **Multi-project feature comparison** (DataView dashboard across vault projects). Frontmatter has `feature-count`/`deprecated-count`/`doc-sync-score` ready; DataView spec is its own task.
- **Auto-suggest README patches.** `doc-sync-actions` block lists todos; actual README writes are manual. A future `/obsidian-doc-sync` command could close that loop.
- **Beta/Alpha status enum.** v4.2 ships `online`/`deprecated` only. Adding a 3rd `beta` status (detected via `# TODO`, `# BETA` comments) is straightforward but deferred.
- **Feature dependency graph** (Mermaid showing which features depend on which modules / external services). Possible v4.3.

## File-level shape preview (langlive case, illustrative)

```markdown
---
type: architecture-features
date: 2026-05-29
project: "[[langlive-line-oa]]"
local-path: "/Users/leric/Desktop/code/langlive-line-oa"
last-scanned: 2026-05-29
commit: 8af18eb
sources: ["README.md", "AGENTS.md", "CHANGELOG.md", "scan: api_surface", "manifest: modules"]
confidence: high
lang: zh-TW
tags: [architecture, features]
ai-first: true
status: current
feature-count: 32
deprecated-count: 3
doc-sync-score: 0.84
---

## 給未來 Claude
本檔是 product PM 視角:看完整 feature set,標 online/deprecated,從產品角度討論優缺、缺什麼、該補哪些 doc。技術視角請見 [[Architecture/modules/]] / [[Architecture/ai-flows/]];使用者型態請見 [[Architecture/personas]]。

## 摘要
<!-- @generated:start summary -->
... product 是什麼,32 個 capability(29 online + 3 deprecated),doc-sync-score 0.84 ...
<!-- @generated:end summary -->

## 能力清單
<!-- @generated:start capability-inventory -->
| Capability | Description | Status | Last touch | Docs | Code | Module |
| --- | --- | --- | --- | --- | --- | --- |
| 客服回覆與媒體上傳 | 支援 4 種 reply 類型 | online | 2026-05-22 | README#Conversation Workspace; AGENTS L17-19 | `backend/app/api/workspace.py:/agent-reply` | [[modules/backend]] |
| 舊版 v1 webhook | legacy `/line_webhook` (deprecated) | online | 2025-08-03 | README#LINE Webhook | `backend/app/api/line_webhook.py:legacy` | [[modules/backend]] |
| ... | ... | ... | ... | ... | ... | ... |
<!-- @generated:end capability-inventory -->

(...其餘 7 個 block...)
```

## Success criteria

This design ships when:

- [x] User approves Section 1 (frame & file shape).
- [x] User approves Section 2 (block design incl. `limitations`, deferred `example use case`).
- [x] User approves Section 3 (scanner, refresh, roadmap, command).
- [ ] Spec self-review pass (this file).
- [ ] User reviews this written spec.
- [ ] Implementation plan written via `writing-plans` skill.
- [ ] Implementation lands; `langlive-line-oa` smoke produces `features.md` with sensible online/deprecated split + research-empty graceful degradation.
