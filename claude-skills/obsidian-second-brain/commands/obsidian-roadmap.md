---
description: Synthesize Architecture signals + Research into a project Roadmap.md plus T-NNN tasks plus board cards
argument-hint: <project-name>
category: thinking
triggers_en: ["roadmap", "synth roadmap", "plan backlog", "generate backlog", "what to build next"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-roadmap $ARGUMENTS`:

The argument is `<project-name>` (the folder name under `Projects/`). Optional flags:
`--dry-run` (Phase 1+2a only, write to /tmp), `--force` (treat all themes as new),
`--only-themes=<N>` (cap synthesis output, default 12), `--skip-research` (Phase 2 skipped,
signals only), `--lang=<en|zh-TW>` (override vault `_CLAUDE.md output-lang`),
`--scope-research-days=<N>` (vault-wide Research window, default 30).

If `<project-name>` is omitted and `pwd` is inside `Projects/<P>/`, default to `<P>`.
Otherwise ASK the user which project.

## Pre-flight

- Vault root has `_CLAUDE.md`? If no, abort with "Run /obsidian-init first."
- `Projects/<P>/Architecture/` exists with at least `future.md`? If no, abort with
  "Run /obsidian-architect <repo> first."
- Resolve `output_lang`:

  ```bash
  uv run python -c "from scripts.architect.lang import resolve_output_lang; from pathlib import Path; import sys; print(resolve_output_lang(sys.argv[1] or None, Path(sys.argv[2])))" "${LANG_FLAG:-}" "<vault-root>"
  ```

## Phase 1+2a — Deterministic scan

```bash
uv run python scripts/roadmap_synth.py \
    --project-root <vault>/Projects/<P> \
    --vault-root <vault> \
    --out /tmp/roadmap-<hash>/ \
    --lang <output_lang>
```

Outputs:
- `/tmp/roadmap-<hash>/candidates.json` — Phase 1 candidates (gap / limitation / aspiration / promote-to-adr / todo-cluster)
- `/tmp/roadmap-<hash>/keyword_extraction_prompt.txt` — prompt for Phase 2a

If `--dry-run`: print candidate count to user and stop.

If candidate count is 0: report "No candidates found — Architecture/ signals are insufficient. Suggest adding README Limitations / Future Work sections, or running /obsidian-architect with richer signals." Stop.

## Phase 2a — Keyword extraction (LLM)

Read `/tmp/roadmap-<hash>/keyword_extraction_prompt.txt` and invoke the LLM with it. Expect JSON response: `{<candidate-id>: [<keyword>, ...]}`. Save to `/tmp/roadmap-<hash>/keywords.json`.

## Phase 2b — Keyword prefilter (deterministic)

For each candidate, call `scripts.roadmap.research_match.keyword_prefilter(...)` to find candidate research notes (project Research/ unfiltered + vault Research/{Web,Deep} within `--scope-research-days`, capped at 10 per candidate). Save matches to `/tmp/roadmap-<hash>/prefilter.json`.

## Phase 2c — LLM relevance check

Call `scripts.roadmap.research_match.build_relevance_prompt(matches_by_cand, candidates_text, output_lang)` to build the prompt. Invoke LLM; expect JSON: `{<candidate-id>: [<relevant-research-path>, ...]}`. Save to `/tmp/roadmap-<hash>/relevance.json`.

Build a merged "linked-candidates" view: each candidate now carries its evidence wikilinks (architect source + filtered research paths converted to `[[<path-without-extension>]]`).

## Phase 3 — Theme synthesis (LLM)

Read `Projects/<P>/Architecture/_manifest.yml` for `modules_summary` (e.g. "backend, frontend, services, ...").

Call `scripts.roadmap.synthesis.build_synthesis_prompt(candidates=linked_candidates, modules_summary=..., project=<P>, output_lang=..., max_themes=--only-themes-flag)`. Invoke LLM; expect JSON list of themes (per spec §7 Phase 3 schema, with fully-spec'd tasks).

Save to `/tmp/roadmap-<hash>/themes.json`.

## Phase 4 — Batch review (user)

Print a markdown table to the conversation:

```markdown
| # | Action | 主題 | Priority | Effort | Evidence | Tasks |
|---|---|---|---|---|---|---|
| 1 | __ | <title> | 🔴 | M | 2 | 4 |
...

(per-theme detail follows: why, evidence wikilinks, task descriptions)
```

Then ask user to paste back the table with the Action column filled in. Valid actions:
- (empty) or `K` — keep
- `D` — drop
- `M:<n>` — merge into theme <n>
- `E` — edit (user provides edited JSON inline below the table)

Parse via `scripts.roadmap.parser.parse_review_response(paste, n_themes)`. If `ParseError`: show the error to the user, ask them to re-paste. Max 3 retries before aborting.

Compute the final theme list (drop D rows, merge M rows into their target, apply E edits).

Re-prompt user "請確認 N themes / M tasks 將寫入。是否進 Phase 5?" — wait for Y/N.

## Phase 5 — Materialize (deterministic)

Load `Projects/<P>/_roadmap.lock.json` if it exists; otherwise initialize.

For each kept theme:
1. Compute signal-hash. If lockfile has this theme slug with matching hash, SKIP. If theme slug exists with different hash, mark `needs-refresh` and proceed. If new theme, allocate.
2. For each task, call `allocate_task_id(lock)` for the next "T-NNN" then `normalize_slug(task.slug or task.description)`.
3. Write `Projects/<P>/Tasks/T-NNN-<slug>.md` via `compose_task_note(...)`.
4. Append board card via `append_to_board(Projects/<P>/board.md, [format_board_card(task, theme.slug, theme.priority)], heading_zh="## 待辦", heading_en="## Backlog")`.
5. Update `lockfile.themes[slug]` and `lockfile.tasks[task-id]`.

Detect stale themes: every theme in lockfile whose slug doesn't appear in this run's kept themes. Mark `status: stale`, include in `stale_themes` arg to `compose_roadmap`.

Write `Projects/<P>/Roadmap.md` via `compose_roadmap(project=<P>, themes=kept, stale_themes=stale, synthesis_summary={...}, output_lang=...)`.

Write `Projects/<P>/_roadmap.lock.json` via `write_lockfile(...)`.

## Daily / operation log

- If `Logs/` exists, append `**HH:MM** - roadmap | <P> - synthesized N themes (K new, M refreshed) → N+K tasks` to `Logs/YYYY-MM-DD.md`.
- Otherwise append `## [YYYY-MM-DD] roadmap | <P> - ...` to `log.md`.
- Append to today's daily note `## Activity` section: `- /obsidian-roadmap: synthesized [[<P>/Roadmap]]`.

## Errors and edge cases

- Architecture/ missing → abort, suggest `/obsidian-architect`.
- All sections of `architecture-future` flagged `status: insufficient-signal` → no candidates → report + stop.
- Phase 2c LLM returns malformed JSON → retry once with stricter "STRICT JSON ONLY" preamble; if still bad, downgrade to "all matches kept" (skip relevance filter) with warning.
- Phase 4 parse fails 3 times → abort, save `/tmp/roadmap-<hash>/` for inspection.
- Phase 5 write of one task fails (e.g. permission) → rollback that theme's tasks, don't update lockfile entry for that theme, continue with others.
- Lockfile schema-version mismatch → abort, instruct user to upgrade or remove the lockfile.

---

**AI-first rule:** Every note created by this command MUST follow `references/ai-first-rules.md` — frontmatter (`type`, `date`, `lang`, `tags`, `ai-first: true`, plus type-specific fields), `## For future Claude` preamble, `[[wikilinks]]`, code identifiers preserved in English, recency markers for external claims.

**Language:** Respect `_CLAUDE.md`'s `- output-lang: zh-TW` line by default; honor `--lang=` flag override. Roadmap.md / Task notes / board cards use that language for prose + headings; T-NNN-slug filenames, frontmatter keys/enums, wikilink path segments, and code identifiers remain English. See `references/ai-first-rules.md` §Language.

**Obsidian Markdown:** Roadmap.md uses OFM wikilinks (`[[Tasks/T-001-foo|display]]`), bilingual H2/H3 headings, and the sentinel-aware `@generated` block convention from architect. Reference the `obsidian-markdown` skill for OFM specifics (callouts, embeds, anchor formatting).
