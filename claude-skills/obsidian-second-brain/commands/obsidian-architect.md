---
description: Scan a codebase and generate architecture overview plus module notes into the project hub
argument-hint: <repo>
category: vault
triggers_en: ["architect", "architecture doc", "scan repo", "document architecture", "codebase overview"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-architect $ARGUMENTS`:

The argument is `<repo-path>` (local path or github URL). Optional flags:
`--project=<P>` (force project hub binding), `--refresh` (explicit refresh),
`--dry-run` (Phase 1 only, no vault writes), `--force` (ignore "no changes" gate),
`--functions=<off|public>`, `--skip-sections=<csv>`, `--only-sections=<csv>`,
`--lang=<en|zh-TW>` (override vault `_CLAUDE.md output-lang`).

**v4-specific flags:**
- `--frame=<report|judgment|description>` — default `report` (v4). `judgment`
  falls back to v3 behaviour; `description` to v2. v4 produces 8 files
  (overview + 5 modules + decisions + personas); legacy frames keep their
  larger file counts.
- `--keep-deprecated` — when migrating v3→v4, do NOT delete the 6 obsolete
  files. Not recommended; tar.gz backup already preserves them.
- `--improvements-per-file=<N>` — cap on per-file Imps, default 4. Overview
  cross-cutting Imps cap separately at 5.
- `--require-evidence` — default true. When false, LLM may emit Imps without
  Evidence (debugging only).

**v4.1-specific flags:**
- `--no-ai-flows` — even when scanner detects AI subsystem(s), do NOT produce
  `ai-flows/` notes. Use this if you don't want the AI flow layer for a project.
  Default OFF (AI flows ARE produced when detected).

**v4.2-specific flags:**
- `--no-features` — even when scanner can produce a features.md, skip Phase
  3.5.5. Use this if a project doesn't need the product-PM lens. Default OFF
  (features.md IS produced by default in v4.2+).
- `--features-only` — diagnostic flag. Run only Phase 1 (scan) + Phase 3.5.5
  (features synth). Useful for iterating on the features prompt without
  re-running other sections.

**v4.3-specific flags:**
- `--no-ai-memory` - even when >=1 AI flow is detected, skip Phase 3.8
  (memory.md). Default OFF (memory.md IS produced when >=1 AI flow is detected).
- `--no-ai-rag` - same shape; skips Phase 3.9 (rag.md). Default OFF.
- `--ai-memory-only` - diagnostic: run Phase 1 + 3.7 (per-flow ai-flow notes,
  needed for cross-link integrity) + Phase 3.8 only. Useful for iterating on
  the memory prompt.
- `--ai-rag-only` - same shape for Phase 3.9.

If `<repo-path>` is omitted and `pwd` is inside a git repo, default to `.`.
Otherwise ASK the user.

## Project routing

Resolve the target project hub in this order:

1. `--project=<P>` flag.
2. Search the vault for a project hub whose `local-path` frontmatter (resolved
   to an absolute path) equals the absolute path of `<repo-path>`. Exactly one
   match: use it.
3. Zero matches: create a new project hub. Follow the same conventions as
   `/obsidian-project`: sub-folder layout, hub frontmatter schema with `date`,
   `tags: [project]`, `status: active`, `local-path`, the
   `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/`
   skeleton, and a `board.md`. Project name defaults to the repo folder basename.
   ASK the user before creating so typos can be corrected.
4. Multiple matches: abort, list candidates, ask user to pass `--project=<P>`.

## Phase 1: Deterministic scan

Run:

```bash
uv run python scripts/architect_scan.py <repo-path> --out /tmp/architect-<hash>/
```

This produces `/tmp/architect-<hash>/_manifest.yml` and `scan-report.json`.

The scan-report includes manifest signals AND narrative signals:
`readme_sections`, `changelog`, `decision_docs`, `stack`, `todos`, `api_surface`,
`commit_decisions`. Phase 3.5 consumes these.

If `--dry-run`, print the manifest to the user and stop. No vault writes.

## Phase 1.5: v2 → v3 migration (only when `--frame=judgment` AND existing vault is v2)

Detect if `Projects/<P>/Architecture/_manifest.lock.json` exists and reports
`schema-version: 2` (or `version` < 3, or `frame != "judgment-v3"`). If so:

1. Call `scripts.architect.migration.plan_v2_to_v3_migration(arch_dir)` to
   compute what would change.
2. Print the plan to the user — list which files will be modified, which
   `@generated` blocks will be dropped (the v2 file-tree noise), and which
   `@user` blocks will be preserved.
3. ASK user: `proceed | dry-run | abort`. (`--force` bypasses with proceed.)
4. On `proceed`: call `scripts.architect.migration.backup_architecture_dir(arch_dir)`
   to write `_archive/architecture-pre-v3-<timestamp>.tar.gz`, then call
   `apply_v2_to_v3_migration(arch_dir, plan, dry_run=False)`.
5. On `dry-run`: call `apply_v2_to_v3_migration(arch_dir, plan, dry_run=True)`
   and stop. User reviews, re-runs without dry-run when ready.

After successful migration, lockfile is overwritten in Phase 5 (per-section
synthesis) with `schema-version: 3` and `frame: "judgment-v3"`.

## Phase 1.6: v3 → v4 migration (only when `--frame=report` AND existing vault is v3)

Detect if `Projects/<P>/Architecture/_manifest.lock.json` exists and reports
`frame: "judgment-v3"` (or `version: 3`).

1. Call `scripts.architect.migration.plan_v3_to_v4_migration(arch_dir)`.
2. Print the plan to the user — 6 files to delete (`future.md`, `roadmap.md`,
   `jobs.md`, `api-surface.md`, `features.md`, `flows.md`), known-limitations
   content to migrate into `decisions.md`, files kept (`overview.md`,
   `modules/*`, `decisions.md`, `personas.md`).
3. ASK user `proceed | dry-run | abort`. `--force` bypasses with proceed.
   `--keep-deprecated` skips the delete step but still merges known-limitations.
4. On `proceed`: call `backup_architecture_dir(arch_dir)` first
   (tar.gz to `_archive/architecture-pre-v4-<timestamp>.tar.gz`), then
   `apply_v3_to_v4_migration(arch_dir, plan, dry_run=False)`.
5. On `dry-run`: call `apply_v3_to_v4_migration(... dry_run=True)` and stop.

After successful migration the overview.md content from v3 is now stale (it's
still the v3 MOC). Phase 4 (Overview synthesis below) overwrites it with v4
report content. Lockfile is rewritten in Phase 5 with `version: 4`,
`frame: "report-v4"`.

## Phase 2: Manifest review

Read `_manifest.yml` from the temp output. If
`Projects/<P>/Architecture/_manifest.yml` already exists in the vault:
diff via `scripts/architect/manifest_diff.py` and show added / removed /
renamed modules to the user. Otherwise show the full proposal.

ASK the user to confirm or edit. They can:

- Approve as proposed.
- Provide an edited YAML (paste it back inline).
- Reject and abort.

On approve: write `Projects/<P>/Architecture/_manifest.yml` to the vault.

## Phase 3: Per-module synthesis (v3 judgment frame)

For each module slug in the approved manifest (not excluded):

1. Pack the module's source paths via repomix:
   ```bash
   repomix --include "<paths>" --style xml --compress > /tmp/architect-<hash>/repomix-<slug>.xml
   ```
2. Build the LLM prompt:
   ```python
   from scripts.architect.sections import build_module_prompt
   prompt = build_module_prompt(
       module_slug=slug,
       repomix_packed=open("/tmp/architect-<hash>/repomix-<slug>.xml").read(),
       agents_md_excerpt=agents_md_text[:5000],
       output_lang=output_lang,
   )
   ```
3. Invoke the LLM. Expect strict JSON with 5 keys:
   `scope, strengths, weaknesses, improvements, dependencies`.
4. Validate the `improvements` block: parse via
   `scripts.architect.sections.parse_improvements_block(...)` and confirm
   ≥1 Imp survives (every Imp must include Why/Evidence/Effort/Risk/Confidence).
   If 0 Imps parse, retry once with stricter prompt; if still 0, write the
   block as `_(無 Evidence-grounded improvements;owner 校對)_` and continue.
5. Compose the module note via `scripts.architect.sections.compose_note(...)`
   with `section="module"` (note: v3 introduces this section name).
6. Write to `Projects/<P>/Architecture/modules/<slug>.md`.
7. Update `_manifest.lock.json` `modules[<slug>]` entry.

The new module note:
- Has NO `## Key files` section.
- Body is judgment, not transcription.
- Dependencies section uses wikilinks only.

## Phase 3.5: Per-section synthesis (v4)

Resolve `output_lang`:

```bash
uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
```

Order:
1. **decisions.md** — `compose_note(section="decisions", ...)`. New block
   `known-limitations` is populated from migration carry-over (if any) plus
   LLM additions; the LLM should produce the other blocks (summary,
   stack-rationale, etc.) per existing v3 behavior.
2. **personas.md** — `compose_note(section="personas", ...)`. Lighter v4
   version: drop the heavy pain-points list (those moved to module Imps).

Removed in v4 (no longer written): api-surface.md, features.md, roadmap.md,
future.md, jobs.md, flows.md. If `--frame=judgment` is passed, the v3
behavior is restored and these are written.

api-surface detection still runs as part of Phase 1 deterministic scan; the
data lives in `scan-report.json` for `/obsidian-roadmap` and other tooling.

For per-section content rules see `references/ai-first-rules.md` §language and §architecture-*.

If `--functions=public`:

8. Call `scripts.architect.public_surface.eligible_functions(api_surface, module_paths)` to get the candidate list.
9. For each candidate, run an LLM call to produce the body blocks (`what-it-does`, `inputs-and-outputs`, `behavior-notes`, `callers`).
10. Call `sections.compose_function_note(...)` and write to `Projects/<P>/Architecture/functions/<module>/<func>.md`.
11. Update lockfile `functions[<module>/<func>]`.

Failure isolation: if any one section or function synthesis throws, write the note with `status: scan-failed`, record the error in the body, and continue.

## Phase 3.5.5: Features synthesis (v4.2)

Skip if `--no-features` is passed.

Skip if `sections.features.signal-hash` in lockfile matches current scan signal hash AND `Projects/<P>/Architecture/features.md` exists (refresh logic).

1. Compute signal hash:
   ```python
   from scripts.architect.sections import signal_hash
   feature_signal = {
       "readme_sections": scan_report["readme_sections"],
       "agents_md_text": scan_report["agents_md_text"],
       "changelog": scan_report["changelog"],
       "api_surface": scan_report["api_surface"],
       "research_excerpts": [
           {"path": r["path"], "mtime": (vault_proj / r["path"]).stat().st_mtime}
           for r in scan_report["research_excerpts"]
       ],
       "personas_hash": _sha256_of_personas(arch_dir / "personas.md"),
   }
   sig_hash = signal_hash(feature_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_features_prompt
   prompt = build_features_prompt(
       project=project_name,
       readme_sections=scan_report["readme_sections"],
       agents_md_text=scan_report["agents_md_text"],
       changelog=scan_report["changelog"],
       api_surface_summary=_render_api_surface_summary(scan_report["api_surface"]),
       modules_summary=_render_modules_summary(manifest_modules, arch_dir / "modules"),
       personas_summary=_read_personas_excerpt(arch_dir / "personas.md"),
       research_excerpts=scan_report["research_excerpts"],
       output_lang=output_lang,
   )
   ```

3. Invoke the LLM. Expect strict JSON: 10 keys (capability-inventory as STRUCTURED LIST, others as markdown strings).

4. Two-pass annotation + table render:
   ```python
   from scripts.architect.sections import render_features_inventory, compute_doc_sync_score
   table_md, counts = render_features_inventory(
       llm_output["capability-inventory"],
       scan_report["api_surface"],
       scan_report["git_last_touch"],
   )
   # Compute rendered_rows from llm inventory + assigned statuses for doc-sync-score.
   rendered_rows = [
       {**row, "status": _status_for_row(row, scan_report["api_surface"])}
       for row in llm_output["capability-inventory"]
   ]
   sync_score = compute_doc_sync_score(rendered_rows)
   ```

5. Compose note:
   ```python
   from scripts.architect.sections import compose_features_note
   blocks = {**llm_output, "capability-inventory": table_md}
   note = compose_features_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["README.md", "AGENTS.md", "CHANGELOG.md",
                       "scan: api_surface", "manifest: modules"]
                      + (["vault: Research/*"] if scan_report["research_excerpts"] else [])
                      + (["vault: personas.md"] if (arch_dir / "personas.md").exists() else []),
       confidence="high" if scan_report["research_excerpts"] else "medium",
       output_lang=output_lang,
       generated_blocks=blocks,
       feature_count=counts["online"] + counts["deprecated"],
       deprecated_count=counts["deprecated"],
       doc_sync_score=sync_score,
   )
   ```

6. Write to `Projects/<P>/Architecture/features.md`.

7. Update lockfile `sections.features`:
   ```python
   lockfile.sections["features"] = {
       "signal-hash": sig_hash,
       "lang": output_lang,
       "last-generated": today_iso,
       "commit": commit,
       "feature-count": counts["online"] + counts["deprecated"],
       "deprecated-count": counts["deprecated"],
       "doc-sync-score": sync_score,
   }
   ```

8. Hub block + overview drill-down (idempotent, sentinel-aware):
   - Hub `Projects/<P>/<P>.md` `<!-- @generated:start architecture-section -->` block: ensure line `- 產品 feature inventory + doc-sync: [[Architecture/features]]` is present once.
   - `Projects/<P>/Architecture/overview.md` `<!-- @generated:start drill-down -->` block: ensure line `- **產品 feature inventory:** [[features]] (online/deprecated 狀態 + gap analysis + 文件補補丁)` is present once.

If `--features-only`: skip all other Phases (3, 3.5, 3.7, 4) and only run Phase 1 + Phase 3.5.5 + final hub/overview update + lockfile write.

## Phase 3.7: AI Flow synthesis (v4.1)

For each AI flow in `scan_report["ai_flows"]` (skip if `--no-ai-flows`):

1. Run repomix on `flow["root_path"]`:
   ```bash
   repomix --include "<flow.root_path>/**" --style xml --compress --top-files-len 30 -o /tmp/repomix-<slug>.xml
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_flow_prompt
   prompt = build_ai_flow_prompt(
       flow_slug=flow["slug"],
       flow_name=flow["name"],
       framework=flow["framework"],
       flow_kind=flow["flow_kind"],
       prompts_inventory=flow["prompts"],
       state_module=flow.get("state_module"),
       graph_files=flow.get("graph_files", []),
       repomix_packed=repomix_text,
       output_lang=output_lang,
   )
   ```

3. Invoke LLM. Expect strict JSON with 10 block keys (ai-purpose / graph-topology /
   state-schema / prompts (annotations only) / llm-config / evaluation / strengths /
   weaknesses / improvements / dependencies).

4. **Prompts block reconstruction.** The LLM's `prompts` value is annotations only -
   it provides per-prompt `{purpose, type_note}` dict, but does NOT generate the body
   (bodies come from the inventory verbatim). Reconstruct via:
   ```python
   from scripts.architect.sections import render_prompts_block
   prompts_body = render_prompts_block(
       inventory=flow["prompts"],
       annotations=llm_output["prompts_annotations"],  # LLM returns this map
       lang=output_lang,
   )
   ```
   Then put `prompts_body` into `generated_blocks["prompts"]` for compose_note.

5. Compose: `compose_note(section="ai-flow", project=<P>, ...)`. Frontmatter
   needs `ai-framework`, `flow-kind`, `maturity` - these are emitted by appending
   custom fields after the standard set (compose_note doesn't know about them, so
   merge AFTER the call by string-replace the `tags: ` line):
   ```python
   note = compose_note(...)
   extra_fm = f"ai-framework: {flow['framework']}\nflow-kind: {flow['flow_kind']}\nmaturity: {llm_output.get('maturity', 'Beta')}\n"
   note = note.replace("ai-first: true", extra_fm + "ai-first: true", 1)
   ```

6. Write to `Projects/<P>/Architecture/ai-flows/<flow-slug>.md` (create
   `ai-flows/` directory if needed).

7. Update lockfile `ai_flows[<slug>]`:
   - `signal-hash`, `lang`, `framework`, `last-generated`
   - Per-prompt sub-dict from inventory (source-hash from each ExtractedPrompt)

8. For each module hosting an AI flow, write a sentinel block via
   `format_ai_engine_link(...)`. Insert it into `modules/<host>.md` near the top
   (after `## 給未來 Claude` preamble). Idempotent - sentinel-aware update.

   To determine which module hosts an AI flow:
   - Match flow's `root_path` against each module's `paths`. First matching
     module hosts the flow.
   - Example: flow `lang-ai-customer` at `backend/engines/langgraph` matches
     module `backend` (paths `["backend/"]`).
   - For flows that don't match any module's `paths`, skip the link (the
     `ai-flows/` note still exists, just no module-side back-pointer).

## Phase 3.8: AI memory synthesis (v4.3)

Skip if `--no-ai-memory` is passed.

Skip if `scan_report["ai_flows"]` is empty.

Skip if `lockfile.ai_memory.signal-hash` matches the new signal hash AND
`Projects/<P>/Architecture/ai-flows/memory.md` exists (refresh logic).

1. Compute signal hash:
   ```python
   from scripts.architect.sections import signal_hash
   import hashlib
   memory_signal = {
       "ai_memory": scan_report["ai_memory"],
       "per_flow_state_schema_hash": {
           f["slug"]: _sha256_block(arch_dir / "ai-flows" / f"{f['slug']}.md",
                                      "state-schema")
           for f in scan_report["ai_flows"]
       },
   }
   sig_hash = signal_hash(memory_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_memory_prompt
   prompt = build_ai_memory_prompt(
       project=project_name,
       ai_memory_signals=scan_report["ai_memory"],
       ai_flows_summary=[
           {"slug": f["slug"], "framework": f["framework"],
            "root_path": f["root_path"]}
           for f in scan_report["ai_flows"]
       ],
       output_lang=output_lang,
   )
   ```

3. Invoke the LLM. Expect strict JSON: 11 keys (all markdown strings).

4. Compose:
   ```python
   from scripts.architect.sections import compose_ai_memory_note
   note = compose_ai_memory_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["scan: ai_memory",
                        f"ai-flows: {', '.join(f['slug'] for f in scan_report['ai_flows'])}",
                        "manifest: modules"],
       confidence="high" if scan_report["ai_memory"]["summary"]["memory_flows"] > 0 else "medium",
       output_lang=output_lang,
       generated_blocks=llm_output,
       memory_flows=scan_report["ai_memory"]["summary"]["memory_flows"],
       stateless_flows=scan_report["ai_memory"]["summary"]["stateless_flows"],
       backend=scan_report["ai_memory"]["summary"]["primary_backend"],
   )
   ```

5. Write to `Projects/<P>/Architecture/ai-flows/memory.md`.

6. Update lockfile `ai_memory`:
   ```python
   lockfile.ai_memory = {
       "signal-hash": sig_hash,
       "lang": output_lang,
       "last-generated": today_iso,
       "commit": commit,
       "memory_flows": scan_report["ai_memory"]["summary"]["memory_flows"],
       "stateless_flows": scan_report["ai_memory"]["summary"]["stateless_flows"],
       "backend": scan_report["ai_memory"]["summary"]["primary_backend"],
   }
   ```

## Phase 3.9: AI RAG synthesis (v4.3)

Skip if `--no-ai-rag` is passed.

Skip if `scan_report["ai_flows"]` is empty.

Skip if `lockfile.ai_rag.signal-hash` matches the new signal hash AND
`Projects/<P>/Architecture/ai-flows/rag.md` exists.

1. Compute signal hash (mirrors Phase 3.8 but uses `llm-config` block hash
   per flow, since embedding model lives there):
   ```python
   rag_signal = {
       "ai_rag": scan_report["ai_rag"],
       "per_flow_llm_config_hash": {
           f["slug"]: _sha256_block(arch_dir / "ai-flows" / f"{f['slug']}.md",
                                      "llm-config")
           for f in scan_report["ai_flows"]
       },
   }
   sig_hash = signal_hash(rag_signal)
   ```

2. Build prompt:
   ```python
   from scripts.architect.sections import build_ai_rag_prompt
   prompt = build_ai_rag_prompt(
       project=project_name,
       ai_rag_signals=scan_report["ai_rag"],
       ai_flows_summary=[...same shape as Phase 3.8...],
       output_lang=output_lang,
   )
   ```

3. Invoke LLM. Expect strict JSON: 11 keys.

4. Compose:
   ```python
   from scripts.architect.sections import compose_ai_rag_note
   summary = scan_report["ai_rag"]["summary"]
   note = compose_ai_rag_note(
       project=project_name,
       repo_label=repo_label,
       commit=commit,
       signal_sources=["scan: ai_rag",
                        f"ai-flows: {', '.join(f['slug'] for f in scan_report['ai_flows'])}",
                        "manifest: modules"],
       confidence="high" if summary["embedding_aligned"] is not None else "medium",
       output_lang=output_lang,
       generated_blocks=llm_output,
       rag_flows_read=summary["read_flows"],
       rag_flows_write=summary["write_flows"],
       vector_store=summary["primary_vector_store"],
       embedding_aligned=summary["embedding_aligned"],
   )
   ```

5. Write to `Projects/<P>/Architecture/ai-flows/rag.md`.

6. Update lockfile `ai_rag` (mirrors Phase 3.8 pattern).

7. Hub block + overview drill-down (idempotent, sentinel-aware):
   - Hub `Projects/<P>/<P>.md` architecture-section block: ensure line
     `- AI memory + RAG 深判斷 (v4.3): [[Architecture/ai-flows/memory]] | [[Architecture/ai-flows/rag]]`
     is present once.
   - `Projects/<P>/Architecture/overview.md` drill-down block: ensure line
     `- **AI 跨流程深判斷:** [[ai-flows/memory]] (lifecycle + TTL + compaction) | [[ai-flows/rag]] (data flow + embedding 對齊)`
     is present once.

If `--ai-memory-only` or `--ai-rag-only`: skip Phases 3 / 3.5 / 3.5.5 (features) / 4 (overview);
only Phase 1 + 3.7 (needed for cross-link integrity) + the target phase run.

## Phase 4: Overview synthesis (v4 + v4.1)

This is the centerpiece of v4. The overview becomes a self-contained report.

In the Module map section, for each module that hosts an AI flow,
append ` + AI: [[ai-flows/<slug>]]` to its module line.

In the Drill-down entries section, if `ai-flows/` directory exists,
add a row:
- `## AI Flows:` `[[ai-flows/<slug-1>]]` | `[[ai-flows/<slug-2>]]` | ...

1. Gather context inputs:
   - `modules_summary` — slug + display name + 1-line role per module
     (from manifest + module note `## 模組職責` blocks).
   - `personas_summary` — first 2 KB of `personas.md`.
   - `per_module_improvements_summary` — concatenation of each module's
     `## 改進機會` block (capped). The LLM uses this to write cross-cutting
     Imps with proper Evidence wikilinks.
   - `readme_excerpt`, `agents_md_excerpt` — first 4 KB of each.

2. Build the prompt: `scripts.architect.sections.build_overview_prompt(...)`.

3. Invoke the LLM. Expect strict JSON:
   ```json
   {
     "purpose": "...",
     "system-diagram": "```mermaid\\n...\\n```",
     "capabilities": "### Area\\n- ...",
     "flows": "### Flow 1: ...\\n```mermaid\\n...\\n```\\n**摩擦:**\\n- ...",
     "cross-cutting-improvements": "### Imp 1: ...\\n- **為什麼:** ..."
   }
   ```

4. Validate `cross-cutting-improvements` via `parse_improvements_block(...)`.
   Each Imp must cite ≥ 2 modules in its Evidence (cross-cutting requirement).
   If a candidate Imp cites only one module, downgrade it / drop it. Aim for
   3-5 Imps total.

5. Compose: `scripts.architect.sections.compose_overview(...)` assembles the
   8-section report. Stack section is auto-generated from `stack` arg
   (which was detected by Phase 1 scanner). Module map and Drill-down
   sections are deterministic from `modules` arg.

6. Write to `Projects/<P>/Architecture/overview.md`. The frontmatter has
   `report-style: true` and `lang: <output_lang>`.

7. Update lockfile section entry: `sections.overview.signal-hash`,
   `sections.overview.lang`, etc.

## Data flow note (optional)

If the scan report identifies at least one entry point with a clear
input -> output chain (a chain reachable from the entry point through
multiple modules), generate `Projects/<P>/Architecture/data-flow.md`
with a Mermaid sequence diagram plus brief walkthrough. Skip if no such
chain is detectable - never write speculative data-flow diagrams.

## Hub note update (v4)

Append/replace `## Architecture` (or `## 架構` if zh-TW) block in
`Projects/<P>/<P>.md`. v4 wikilinks:

```markdown
## 架構

- 總覽 (top-down 報告): [[Architecture/overview]] (v4 report-style, 上次掃描 YYYY-MM-DD @ `<sha>`)
- 模組設計判斷: [[Architecture/modules/backend]] | [[Architecture/modules/frontend]] | ... (list each module)
- 技術決定 + ADR 候選 + 已知限制: [[Architecture/decisions]]
- 使用者型態 reference: [[Architecture/personas]]
- Curated Roadmap: [[Roadmap]]
- 重新整理: `/obsidian-architect <repo-path> --refresh`
```

The legacy v3 wikilinks to `future.md` / `roadmap.md` / `jobs.md` /
`api-surface.md` / `features.md` / `flows.md` MUST be removed from the
hub block — those vault files no longer exist post-migration.

## Daily and operation log

- If `Logs/` exists: append `**HH:MM** - architect | <P> - N modules (M new, K updated, L deprecated)` to `Logs/YYYY-MM-DD.md`.
- Otherwise append `## [YYYY-MM-DD] architect | <P> - N modules ...` to `log.md`.
- Append to today's daily note `## Activity` section: `- /obsidian-architect: scanned [[<P>]] @ commit <commit>`.

## Errors and edge cases

- Repo path missing / not a git repo: abort with clear error. No vault writes.
- `repomix` not installed: the Python wrapper falls back automatically. Inform the user that runs are slower.
- Vault has no `_CLAUDE.md`: abort, suggest `/obsidian-init`.
- Multiple project hubs match the same `local-path`: abort, list candidates, ask user to disambiguate with `--project=<P>`.
- Dirty working tree: warn, do not block. The manifest records `dirty: true`
  and the commit field is tagged `+dirty`.
- Working tree dirty during refresh: per-module diff uses committed states only,
  so uncommitted module changes do not trigger re-synthesis. User can pass
  `--force` to override.
- A single module's synthesis fails: write the note with `status: scan-failed`
  in frontmatter plus the error message, continue with other modules.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` - `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval - not human reading.

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag as a single-run override. Run `scripts.architect.lang.resolve_output_lang(cli_flag, vault_root)` to get the effective language. All narrative section notes, the overview MOC, modules, and the hub `## Architecture` block must use that language. Code identifiers (paths, function names, CLI commands, URLs) and frontmatter keys/enums/sentinels remain English regardless. See `references/ai-first-rules.md` for the full rule set.
