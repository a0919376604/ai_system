# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (architect + board merge)

- `/obsidian-architect <repo>` now auto-refreshes `Projects/<P>/board.md`
  as Phase 7 (after Architecture/* notes + hub block + activity log).
  Opt-out via `--no-board-refresh`. Activity log line is combined:
  `architect+board | <P> ... + board (<done> done, ...)`.
- `/obsidian-board <repo> --refresh` body now imports the shared helper
  `scripts.board.refresh.refresh_board()` instead of inline logic.
  External behavior unchanged; cron path unaffected.

### Added

- `/obsidian-architect` v4.6 — AI companion archetype detection + 4-layer
  schema. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-architect-v4.6-companion-archetype-design.md`.

  New module: `scripts/architect/companion_detect.py` with
  `detect_companion_archetype()` + `CompanionDetection` + `LayerEvidence`
  dataclasses. Auto-detect rule: character + storyline both present.
  Frontmatter `archetype: ai-companion` override.

  4 new section types: `character-card` (9 blocks) / `world` (10) /
  `storyline` (11) / `companion-overview` (9). 19 new heading mappings
  in `lang.py` with zh-TW translations.

  Detector loosened (`scripts/architect/ai_flow.py`): custom-pipeline
  no longer requires `nodes/` dir when LLM provider imports + prompts
  file present. Additionally, `detect_ai_flows(repo_root,
  companion_archetype=True)` waives the prompts-file requirement entirely
  when the companion archetype was detected — covers stacks like
  ai-eden-service that inline system prompts in provider modules instead
  of using a top-level `prompts.toml`. `scripts/architect/scan.py` runs
  companion detection BEFORE `detect_ai_flows` and threads the signal
  through. Fixes "0 AI flows detected" miss on ai-eden-service-style stacks.

  Phase 3.7.5 in command body. Flags `--no-companion` / `--companion-only`.
  Lockfile gains `ai_companion: dict` slot. Roadmap candidate detector
  walks 3 new files; companion-overview Imp citing ≥2 layer wikilinks
  → priority `high`.

- `scripts/board/refresh.py` — shared `refresh_board(project_dir,
  signals=None, full=False)` helper. Walks git log + spec/plan files
  when signals=None (cron path), reuses caller-provided signals dict
  when called from architect. Returns `RefreshResult` dataclass with
  counts + buckets + new items + last-refresh timestamps + message.
- 8 unit tests in `tests/board/test_refresh.py` covering skipped-when-
  no-board / signals-None walks / classification heuristic / bucket
  clustering / signals-provided reuse / frontmatter last-refresh update
  / full mode.

### Changed (CLI family alignment)

- 5 commands now share `<repo>` first-positional grammar via the new
  `scripts/commands/repo_resolver.py` helper. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-cli-family-repo-alignment-design.md`.
- `/obsidian-architect <repo>` — unchanged user-facing; internal Phase 0
  now routes through shared resolver.
- `/obsidian-brainstorm <repo>` — argument-hint renamed from
  `<project-name>` (now also accepts absolute path via hub
  local-path match).
- `/obsidian-roadmap <repo>` — same shape change.
- `/obsidian-research <repo> <topic> [--academic]` — NEW (renamed from
  `/research`). `<repo>` accepts `global` sentinel for vault-wide.
- `/obsidian-research-deep <repo> <topic>` — NEW (renamed from
  `/research-deep`).

### Deprecated

- `/research` — use `/obsidian-research`. Stub remains for one minor
  release with deprecation warning; will be removed.
- `/research-deep` — use `/obsidian-research-deep`. Same treatment.

### Added

- `scripts/commands/repo_resolver.py` — shared `<repo>` argument resolver
  with `RepoResolution` dataclass (4 states: project / global /
  ambiguous / unknown). 11 unit tests in
  `tests/commands/test_repo_resolver.py`.
- Frontmatter field `param-autocomplete` for slash commands — reserved
  for future Discord adapter to generate slash-command schemas.
  Sources: `vault-projects` / `vault-projects-plus-global` / `freetext`.

### Added

- `/obsidian-brainstorm` - new slash command for "stuck on next step"
  sessions. Per spec
  `docs/superpowers/specs/2026-05-29-obsidian-brainstorm-design.md`.
  Claude reads vault (Architecture/* + features + ai-flows + personas +
  decisions + Research + board + recent Logs + past brainstorms) and
  opens with 4-6 bold provocations (gap / persona / trend / premortem
  lens). User reacts (drill / kill / park / rewrite); Claude drills via
  follow-ups. Output: `Projects/<P>/Brainstorms/YYYY-MM-DD-<slug>.md`
  with 9 @generated blocks (context, opening-provocations,
  drilled-explorations, distilled-imps, hypotheses, parked,
  open-questions, meta-reflection, dependencies). `/obsidian-roadmap`
  picks up `distilled-imps` + `hypotheses` blocks automatically; new
  dedup rule prefers Brainstorms/ source over features.md and
  architecture-inferred sources.

  New helpers: `parse_hypothesis_block` and `compose_brainstorm_note`
  in `scripts/architect/sections.py`. 8 new heading mappings in
  `scripts/architect/lang.py`. Roadmap candidate detector extension
  in `scripts/roadmap/candidates.py:_extract_brainstorm_candidates`.
- `/obsidian-architect` v4.3 — `ai-flows/memory.md` + `ai-flows/rag.md` cross-flow
  notes. Per spec
  `docs/superpowers/specs/2026-05-28-obsidian-architect-v4.3-ai-memory-rag-design.md`.
  Adds `ai_memory_detect.py` (langgraph checkpointer + langchain memory + reducer
  cap extraction), `ai_rag_detect.py` (vector store + embedding lib + 3-state
  embedding_aligned check), 4 new sections.py helpers (`build_ai_memory_prompt`,
  `build_ai_rag_prompt`, `compose_ai_memory_note`, `compose_ai_rag_note`),
  Lockfile `ai_memory` + `ai_rag` slots (additive), roadmap candidate walks for
  `ai-memory-improvement` + `ai-rag-improvement` (priority `high` when
  `embedding-aligned` evidence cited).
- `/obsidian-architect` v4.2 — `features.md` as product PM lens. Per spec
  `docs/superpowers/specs/2026-05-28-obsidian-architect-v4.2-features-design.md`.
  Adds `research_walker.py`, `git_history.py`, `build_features_prompt`,
  `render_features_inventory` (deterministic online/deprecated marker),
  `compute_doc_sync_score`, `parse_doc_actions_block`. `/obsidian-roadmap`
  candidate detector walks features.md missing-features / improvements /
  doc-sync-actions blocks with dedup against module Imps via Evidence
  wikilink overlap.
- `/obsidian-architect` v4.1 — AI Flows layer. Scanner auto-detects LangGraph,
  LangChain, and custom-pipeline AI subsystems (threshold: ≥ 3 nodes) and
  produces `Architecture/ai-flows/<slug>.md` per flow. Each note has 10 body
  sections: Purpose / Graph topology / State schema / Prompts / LLM config /
  Evaluation / Strengths / Weaknesses / Improvements / Dependencies.
- Full prompt text embedded in vault via Obsidian collapsible callout
  (`> [!quote]-`) for AI-first self-contained context. Per-prompt sentinel
  with source-hash tracking in lockfile — only modified prompts regenerate
  their block on refresh.
- New `architecture-ai-flow` type in `references/ai-first-rules.md`.
- Host module notes gain a sentinel-wrapped `**AI engine:** [[ai-flows/<slug>]]`
  line when they host a detected flow.
- `--no-ai-flows` flag opts out (e.g. for projects where the AI layer should
  remain in module notes).

### Changed

- `/obsidian-roadmap` Phase 1 signal source extended: now also walks
  `Architecture/ai-flows/*.md` for `## Improvement opportunities` blocks.
- Lockfile schema (still v4, no version bump) gains an `ai_flows` field with
  per-flow + per-prompt source-hash tracking.

### Detection rules

- LangGraph: `langgraph` dep OR `from langgraph` import + `graph.py` + ≥ 3 nodes
- LangChain: `langchain` dep (without langgraph) + ≥ 3 nodes
- Custom-pipeline: `pipeline.py` + `nodes/` + prompts file + OpenAI/Anthropic/Gemini lib
- Projects without these signals get no `ai-flows/` directory (zero cost).

### Changed

- `/obsidian-architect` v4 — Overview reframed from MOC to self-contained
  top-down report. Reader opens overview.md once and gets the whole project
  story; detail files (modules, decisions, personas) are now drill-down
  references, not required reading. 6 obsolete files deleted in migration:
  `future.md`, `roadmap.md`, `jobs.md`, `api-surface.md`, `features.md`,
  `flows.md`. Their content moved:
  - `features.md` → `overview.md` `## Capabilities` section
  - `flows.md` → `overview.md` `## Flows` section (with Mermaid + friction)
  - `future.md` "Known limitations" → `decisions.md` `## Known limitations`
  - `future.md` "Aspirational ideas" → per-module `## Improvement opportunities`
  - `roadmap.md` removed (curated roadmap is `/obsidian-roadmap`'s output)
  - `jobs.md` removed (friction → module Imps; JTBD → capability framing)
  - `api-surface.md` removed (machine-readable only, in `scan-report.json`)
- `Architecture/` directory now has 8 files: `overview.md`, `modules/<5>.md`,
  `decisions.md`, `personas.md` (down from 14).
- Lockfile schema bumped to v4 with `frame: "report-v4"` default.
- `/obsidian-roadmap` Phase 1 signal source narrowed to overview + modules
  + decisions only. Same number of candidates (no improvements lost) but
  cleaner source provenance.
- `decisions.md` body section list gains `## Known limitations` (auto-migrated
  from v3 `future.md` content on first v4 run).
- `/obsidian-architect` reframed from description-driven (file-tree recital)
  to judgment-driven (design strengths / weaknesses / improvement opportunities).
  Module notes no longer contain `## Key files` sections; the codebase is
  treated as the source of truth for code structure, and vault notes capture
  judgment that the codebase does not record.
- Every Improvement opportunity must cite Evidence (commit SHA, decision
  wikilink, AGENTS.md section, or `path:line`). LLM is instructed to drop
  Imps it cannot ground in Evidence rather than speculate.
- `api-surface.md` reframed from exhaustive HTTP route / export / env tables
  (17 KB) to high-level prefix-grouped overview (≤ 5 KB). Full tables remain
  available in `/tmp/architect-<hash>/scan-report.json` for tooling.
- Lockfile schema bumped to v3 with `frame` marker
  (`description-v2` legacy vs `judgment-v3` new).

### Added

- `--frame=<report|judgment|description>` flag on `/obsidian-architect`.
  Default `report` (v4). `judgment` keeps v3 14-file output; `description`
  restores v2 file-tree-listing behavior.
- `--keep-deprecated` flag — skip deletion of v3 files during migration
  (not recommended; tar.gz backup already preserves them).
- v3 → v4 migration step: tar.gz `Architecture/_archive/...` backup;
  `--dry-run` shows plan; auto-merges known-limitations into decisions.md.
- `Architecture/personas.md`, `jobs.md`, `flows.md` — product-eye layer
  capturing who uses the product, what jobs they want done, and the
  end-to-end flows they traverse. Each is judgment-aware (jobs declare
  maturity, flows include friction assessment).
- `--frame=<judgment|description>` flag on `/obsidian-architect`. Default
  `judgment` (v3). `description` falls back to v2 behaviour for compatibility.
- `--improvements-per-file=<N>` (default 4) and `--require-evidence` (default
  true) flags on `/obsidian-architect`.
- v2 → v3 migration step: drops v2 `@generated` file-tree blocks, preserves
  `@user` blocks, archives the pre-v3 Architecture/ tree to
  `_archive/architecture-pre-v3-<timestamp>.tar.gz` as a safety net.

### Deprecated

- `architecture-features`, `architecture-flows`, `architecture-future`,
  `architecture-roadmap`, `architecture-jobs`, `architecture-api-surface`
  schema types. Still callable for backward compat (with deprecation log
  warning), but no longer emitted by the default `--frame=report` pipeline.

### `/obsidian-roadmap` integration

- Phase 1 (gap detection) now reads `## 改進機會` / `## Improvement opportunities`
  blocks from every architect file. Each Imp arrives at Phase 3 with full
  metadata (Why, Evidence, Effort, Risk, Confidence), eliminating the
  Phase 1 inference step.
- `Candidate` dataclass extended with optional v3 fields (`why`, `evidence`,
  `effort`, `risk_if_not_done`, `confidence`). v2 candidates without these
  fields continue to work.

### Added

- `/obsidian-roadmap <project>` — synthesize a project Roadmap.md plus
  Tasks/T-NNN-*.md plus board cards from Architecture/ signals
  (future.md, decisions.md "Promote to ADR", roadmap.md TODO clusters)
  and accumulated Research/ (project-scoped + recent vault-wide). New
  `type: roadmap` schema lives at `Projects/<P>/Roadmap.md` (separate
  from `architecture-roadmap` under `Architecture/`). `_roadmap.lock.json`
  tracks theme + task materialization for idempotent re-runs.
- 5-phase pipeline: Phase 1 deterministic gap detection, Phase 2 two-stage
  research matching (keyword prefilter + LLM relevance), Phase 3 single
  LLM call producing fully-spec'd themes, Phase 4 batch markdown table
  review (K/D/M/E actions), Phase 5 deterministic file write.
- `type: task` gains two optional fields: `roadmap-theme` (links back to
  a Roadmap.md theme) and `created-by` (provenance marker).
- `/obsidian-architect <repo-path>` slash command: scans a codebase and generates
  an architecture overview plus per-module notes into the project hub at
  `Projects/<P>/Architecture/`. Diff-aware refresh preserves user edits via
  `@generated`/`@user` sentinels and a lockfile. Module identity is pinned via
  a user-editable `_manifest.yml`. Supports local repos and remote GitHub URLs
  (via `repomix --remote`), plus `--project=<P>` for multi-repo projects.
- `scripts/architect/` Python package: deterministic Phase 1 scanner (file tree
  walker, language stats, entry-point detection, dep extraction, module proposal
  heuristics, manifest read/write, lockfile, sentinel parser, refresh decision).
- `references/ai-first-rules.md`: documented three new `type:` values:
  `architecture-overview`, `architecture-module`, `architecture-data-flow`.
- `/obsidian-architect` now produces narrative section notes alongside the
  module deep-dives: `features.md`, `roadmap.md`, `decisions.md`,
  `future.md`, and `api-surface.md`. `overview.md` becomes a MOC with a
  `stack:` frontmatter block.
- Optional function-level layer via `--functions=public` writes
  `Architecture/functions/<module>/<func>.md` for public-surface symbols.
- `--skip-sections=<csv>` and `--only-sections=<csv>` for surgical
  section regeneration; `--lang=<zh-TW|en>` for per-call language
  override. Vault-wide default lives in `_CLAUDE.md` as
  `- output-lang: zh-TW`.

### Fixed

- **architect: deps and runtime dirs leaked through as active modules.** Surfaced
  while scanning a real Node + Python repo: `node_modules/`, `logs/`, `reports/`,
  `coverage/`, `vendor/` and similar dirs ended up in the proposed manifest with
  `excluded: false`. The walker correctly skipped their files during traversal,
  but `proposal.SKIP_AS_MODULE` was too narrow and still emitted module entries
  for the top-level folders. Extended `SKIP_AS_MODULE` with the missing
  categories (deps, runtime data, build output for JVM/.NET, test coverage,
  GitLab CI) and added a regression test.
- **architect: silenced 420 `pathspec` `GitWildMatchPattern` deprecation
  warnings** by switching `PathSpec.from_lines("gitwildmatch", ...)` to
  `PathSpec.from_lines("gitignore", ...)` in `scripts/architect/walker.py`.
  Same matcher behaviour, future-proof against pathspec dropping the old name.

### Known limitations (scanner v0.1.0)

Documented behaviours that surfaced during the first real-repo run. Candidates
for a v1.1 follow-up:

- `primary_language` is token-weighted, so a docs-heavy repo can rank `markdown`
  (or `html`) above its actual primary code language. Workaround: pin
  `primary_language` in `_manifest.yml` — refresh respects the pin via the
  lockfile.
- External-dependency detector only inspects `pyproject.toml`, `package.json`,
  `Cargo.toml`, and `go.mod` at the repo root. Nested deps files
  (e.g. `backend/requirements.txt`, `frontend/package.json` in a two-image
  monorepo) are missed. Workaround: paste them into the `overview.md`
  `## External dependencies` block.
- Entry-point detector matches the exact filename `Dockerfile`. Variants like
  `Dockerfile.backend` / `Dockerfile.frontend` are not picked up. `python -m
  <pkg>` style entry points are also not detected unless declared in
  `[project.scripts]`. Workaround: same as above.

- **SessionStart hook (`hooks/load_vault_context.py`):** injects `_CLAUDE.md` into context once per session when the session starts inside the vault. Eliminates the per-command re-read of `_CLAUDE.md` that burned tokens on every invocation. Wired automatically by `scripts/setup.sh`.
- **`scripts/setup.sh` updated:** wires the new SessionStart hook (`hooks/load_vault_context.py`) in addition to the existing PostCompact background agent.
- **Per-day operation logs:** `/obsidian-init` now creates a `Logs/` folder with per-day files (`Logs/YYYY-MM-DD.md`) instead of a monolithic `log.md`. Root `log.md` becomes a pointer file only. Cheaper to read, faster to query.
- **`scripts/vault_stats.py`:** computes vault stats (notes by type, project/task counts by status, people by strength) and rewrites the `<!-- BEGIN STATS -->`/`<!-- END STATS -->` markers in `index.md`. Idempotent and re-runnable.
- **`scripts/migrate_log.py`:** splits an existing monolithic `log.md` (with `## YYYY-MM-DD` section headers) into per-day files under `Logs/`. Idempotent - skips days that already exist. Replaces root `log.md` with a pointer file after migration.
- **`/idea-discovery [seed]`** - surface 3-5 next-direction candidates by scanning `Ideas/`, `Projects/` Open Questions, and orphan `Research/` notes.
- **`--academic` flag on `/research`** - restricts to arXiv + Semantic Scholar + OpenAlex + CrossRef.
- **New free-source clients** under `scripts/research/lib/sources/`: arxiv, semantic_scholar, openalex, crossref, duckduckgo, wikipedia, hackernews, reddit, lobsters, devto.
- **File-based cache** at `~/.cache/obsidian-second-brain/research/` with 24h default TTL.
- **`~/.config/obsidian-second-brain/research.toml`** for `contact_email` + SearXNG instance list + rate-limit overrides.
- Plan 1 implementation reference: `docs/superpowers/plans/2026-05-25-vault-hybrid-foundation.md`.
- `/obsidian-notion-sync` - new command that syncs vault recaps + ADRs to Notion via MCP, with auto-discovery and creation of Notion main page / Weekly Recaps DB / Decisions Archive sub-page.
- Two `scripts/cron/` prompt files + trigger scripts for macOS launchd: `board-refresh` (Mon-Fri 09:00) and `weekly-recap` (Saturday 12:00). Originally designed for `/schedule` (Anthropic Cloud remote agents) but switched to launchd because remote agents can't access the local vault or local MCP servers.
- Plan 2 implementation reference: `docs/superpowers/plans/2026-05-25-vault-hybrid-activation-layer.md`.

### Changed

- Lockfile schema bumped to v2: adds `sections` and `functions` blocks,
  plus a `lang` field per entry. v1 lockfiles migrate silently (first
  v2 run regenerates all sections once; module entries are preserved).
- `references/ai-first-rules.md` documents 5 new `type:` values
  (`architecture-features`, `architecture-roadmap`, `architecture-decisions`,
  `architecture-future`, `architecture-api-surface`), 1 optional
  (`architecture-function`), and the language preamble that governs all
  generated notes.
- **Project-scoped vault routing**: 14 slash commands now accept `--project=<name>` and route writes to `Projects/<name>/{Ideas,Tasks,Decisions,Learnings,Research,Recaps}/` sub-folders. Without the flag, default behavior is preserved (writes to vault root). See `docs/superpowers/specs/2026-05-25-vault-hybrid-architecture-and-pipeline-design.md` for the design rationale.
- **`/obsidian-adr` retargeted**: ADRs now write to `Projects/<P>/Decisions/` (was `Knowledge/ADR-...`). Aligns with industry convention. ADR template now includes "What would change my mind" field.
- **`/obsidian-learn` gains `--capture` mode**: write a single learning at the moment of insight (Checkpoint 3 in the spec). The original review-mode is still the default.
- **`/obsidian-board` gains `--refresh` mode**: regenerates the board from codebase git log + spec/plan scan + bucket classification. Preserves manual sections (`## 🔥 This Week`, `## For future Claude` preamble, frontmatter).
- **`/obsidian-graduate` and `/obsidian-project`**: create projects in sub-folder layout (`Projects/<name>/<name>.md` + sub-folder skeleton) instead of flat `Projects/<name>.md`.
- **Research toolkit no longer requires paid APIs.** All 7 research commands now run on free, key-less sources (arXiv, Semantic Scholar, OpenAlex, CrossRef, DuckDuckGo, Wikipedia, HackerNews, Reddit, Lobsters, dev.to). Synthesis is performed by the calling Claude session instead of an external LLM API.

### Dependencies

- Added `pyyaml>=6.0.1` (manifest serialization) and `pathspec>=0.12.1`
  (`.gitignore` matching) to runtime deps.
- Optional: `repomix` (npm package) for repo packing. Python fallback exists
  but is about 3x slower.

### Renamed

- **`/x-pulse` -> `/discourse-pulse`** (HN/Reddit/Lobsters/dev.to; X.com is no longer queried).
- **`/x-read` -> `/thread-read`** (HN/Reddit thread URLs).
- **`/notebooklm` -> `/vault-deep-synthesis`** (Claude reads vault directly; no external LLM).

### Deprecated

- **`scripts/research/lib/{perplexity,grok,gemini}.py`** moved to `scripts/research/_deprecated/`. Will be removed in v2.0.
- **`XAI_API_KEY`, `PERPLEXITY_API_KEY`, `GEMINI_API_KEY`, `YOUTUBE_API_KEY`** are no longer read by the default install. The `.env.example` keeps them commented as an escape hatch for fork users.

### Removed

- **`commands/x-pulse.md`, `commands/x-read.md`, `commands/notebooklm.md`** (replaced by the renamed commands above).

### Fixed

- **`scripts/setup.sh` robustness:** four issues fixed together. Vault paths containing apostrophes or other shell metacharacters (`Joe's Notes`) no longer crash the installer - `eval echo` replaced with bash parameter substitution. `python` replaced with `python3` for compatibility with macOS 13+ and Ubuntu 22+ which don't ship a `python` symlink. All three `settings.json` writes are now atomic (`mv` instead of `cat … && rm`). The MCP setup prompt is skipped when stdin is not a terminal so `curl | bash` installs and CI don't hang.

- **`vault_stats.py` people count:** now counts both `type: person` and `type: entity` in the People aggregate. Real vaults using either convention report the correct count.
- **Log layout routing in all commands:** every `/obsidian-*` command that reads or appends to the operation log now explicitly detects the vault layout (`Logs/YYYY-MM-DD.md` vs monolithic `log.md`) and uses the correct file and format. Previously, commands hardcoded `log.md` with the old `## [YYYY-MM-DD]` section-header format, which would write incorrectly formatted entries on modernized vaults.
- **`vault_stats.py` folder exclusions case-insensitive:** `EXCLUDED_FOLDERS` comparison now uses `part.lower()`, so `templates/` and `Templates/` are both excluded. Added `raw/` to the exclusion set (immutable source folder convention).
- **Em-dashes swept from `vault_stats.py` output, `commands/obsidian-init.md` entry template, and `SKILL.md` format spec:** all user-facing and vault-facing prose now uses ` - ` per the no-em-dash rule.

## [0.8.0] — 2026-05-15

### Added

- **`/notebooklm` command rewritten end to end — no browser, one HTTP call.** Replaces the prior bundle-and-paste workflow (which required opening notebooklm.google.com manually and pasting the response back into the terminal) with a single-phase command that calls Google's Gemini File Search API directly. Same architectural shape as `/research-deep`: one HTTP call, no manual step. Under the hood: scans the vault for the top 12 relevant notes (Research/NotebookLM/ excluded so the synthesis doesn't self-reference its own bundle), uploads them to an ephemeral Gemini File Search store, asks Gemini (default `gemini-2.5-flash`, free-tier friendly) for a citation-style synthesis grounded only against those sources, writes the AI-first synthesis to `Research/NotebookLM/YYYY-MM-DD - <slug>.md`, deletes the store, and emits a propagation payload for `/obsidian-save`. Requires `GEMINI_API_KEY` from https://aistudio.google.com/apikey (free tier covers it). Cost: roughly $0.004 per run on Flash, $0.06 per run on Pro (override via `NOTEBOOKLM_MODEL` env). Filenames written by this command use ASCII separators (`2026-05-15 - <slug>.md`) instead of em-dashes; existing `/research-deep` filenames untouched. The two research tracks (open-web via `/research-deep`, vault-grounded via `/notebooklm`) are designed to run in parallel for high-stakes topics. Contradictions across the two tracks are where the insight is.

### Fixed

- **`/notebooklm` self-reference bug.** Previous implementation re-scanned the vault during the save phase, which scored the bundle file (written during the start phase) as a top hit. The synthesis linked to its own input bundle as a vault baseline. Fix: `vault_scan` now excludes anything under `Research/NotebookLM/`.
- **`/notebooklm` em-dash filenames blew up the Gemini SDK upload.** Vault filenames in `Research/Deep/` and `wiki/logs/` often contain em-dashes (from the prior `/research-deep` convention). The Gemini SDK puts the basename in a Content-Disposition header, and httpx rejects non-ASCII headers. Fix: copy each source to a temp path with an ASCII-safe name before upload; preserve the original path as the human-readable `display_name`.
- **`/notebooklm` em-dashes baked into vault output.** The synthesis H1 used `topic — NotebookLM synthesis (date)` and the preamble had mid-sentence em-dashes. The voice rule says no em-dashes anywhere. Both now use a colon and a period-restructure respectively.

## [0.7.0] — 2026-05-13

### Added

- **`bootstrap_vault.py --preset` and `--mode` flags:** wires the preset/mode interface that `SKILL.md` documented but the script never implemented (running `--preset researcher` errored with `unrecognized arguments: --preset researcher --mode personal`). Five presets land at once, matching the existing SKILL.md description verbatim: `default` (preserves existing Life-OS layout — no change in behavior when no flag is passed), `executive` (Decisions/People/Meetings/OKRs · Boards: OKRs/Quarterly/Weekly), `builder` (Projects/Dev Logs/Architecture/Debugging · Boards: Backlog/Sprint/In Progress/Done), `creator` (Content/Ideas/Audience/Publishing · Boards: Ideas/Drafts/Scheduled/Published), `researcher` (Sources/Literature/Hypotheses/Methodology/Synthesis · Boards: Reading/Processing/Synthesized/Done). Each preset declares its folder list, kanban columns, `_CLAUDE.md` folder map, Home dashboard nav, and template extras via a single `PRESETS` dict at the top of the file — adding a new preset is one dict entry plus optional template lines in `write_preset_extras()`. Two modes: `personal` (default — owner-style `_CLAUDE.md`) and `assistant` (uses the `references/claude-md-assistant-template.md` schema, requires `--subject "Name"` and renders the operator/subject distinction). Fully backwards-compatible: `--path`, `--name`, `--jobs`, `--no-sidebiz` keep their meaning under the default preset; `--no-sidebiz` is silently ignored on non-default presets. The vault-not-empty check now ignores `.obsidian/` so re-running on a vault that only has Obsidian config no longer prompts.
- **`/create-command` interview flow (Phase 5):** new meta command that scaffolds a new `commands/<name>.md` through a 9-phase conversation — zero markdown editing. Asks intent, name, category, triggers, behavior steps, AI-first compliance, and external API needs, then writes a fully-formed command file (frontmatter + body + AI-first footer where applicable) using the Write tool. The new file flows automatically into every platform via the existing adapters — no extra build steps. Lowers the contribution bar so anyone can extend the skill, and every command added through this flow lands AI-first-compliant by construction. Listed under `meta` category; total command count is now 32 (was 31).
- **Write-time AI-first validator (Phase 4):** new `hooks/validate-ai-first.sh` runs as a Claude Code `PostToolUse` hook after every `Write` or `Edit` on a markdown file inside `OBSIDIAN_VAULT_PATH`. Warns (non-blocking) when the file fails the AI-first rule: missing frontmatter delimiters, missing required fields (`date`, `type`, `tags`, `ai-first: true`), tabs in YAML, or missing `## For future Claude` preamble. Surfaces specific warnings on stderr so Claude can repair the note in the same turn. Skips `raw/`, `templates/`, `_export/`, `.obsidian/`, `.git/`, `.trash/` and anything outside the vault. Platform-neutral spec at `hooks/validate-ai-first.hook.yaml`. Setup instructions in `SKILL.md` under "Write-Time AI-First Validator (PostToolUse Hook)". This is the **write-time cleanup primitive** that the Second Brain for Companies thesis depends on — humans write inconsistent input, the validator enforces AI-first discipline automatically.
- **Multilingual trigger phrases (Phase 3):** every command now declares `triggers_<lang>:` lines in its frontmatter. English (`triggers_en:`) is populated for all 31 commands; the schema is extensible to any language via `triggers_es:`, `triggers_it:`, `triggers_fr:`, `triggers_de:`, `triggers_pt:`, `triggers_ru:`, `triggers_ja:` (community contributions welcome). The non-Claude dispatchers (`AGENTS.md`, `GEMINI.md`) now include a `## Trigger phrases` section grouped by language then by category, so AI agents on those platforms can match natural-language requests without seeing the slash form. Adapters auto-detect which languages are populated; empty languages do not appear in the output. Documented in `CONTRIBUTING.md` under "Translating trigger phrases (multilingual support)".
- **Command categorization (Phase 2):** each command in `commands/` now declares a `category:` (vault, thinking, research, meta). Non-Claude dispatcher tables in `AGENTS.md` / `GEMINI.md` are now emitted as four grouped sections instead of one 31-row blob. Adapters use the shared `emit_routing_table_grouped` helper in `adapters/lib.sh`, so the categorization carries through automatically when a new command is added. No breaking changes — Claude Code build is still a byte-exact identity copy.
- **Multi-platform adapter pattern (Phase 1):** one source, four platforms.
  - `scripts/build.sh` orchestrator + `scripts/lib.sh` utility helpers
  - `adapters/lib.sh` shared parsing, path rewriting, tool-name neutralization
  - `adapters/claude-code/adapter.sh` — identity copy (Claude Code is the canonical platform)
  - `adapters/codex-cli/adapter.sh` — emits `AGENTS.md` + `.codex/commands/`
  - `adapters/gemini-cli/adapter.sh` — emits `GEMINI.md` + `.gemini/commands/`
  - `adapters/opencode/adapter.sh` — emits `AGENTS.md` + `.opencode/commands/`
  - Auto-generated routing tables (parses each command's `description:` frontmatter)
  - Tool-name neutralization for non-Claude platforms (`Read tool` → `read files`, etc.)
  - Per-platform `exclude:` frontmatter field for opt-outs
  - Build output goes to `dist/<platform>/` (gitignored)
- `CODE_OF_CONDUCT.md` (Contributor Covenant v2.1)
- `CONTRIBUTING.md` with full contributor guide
- `CLAUDE.md` at repo root for contributor-facing operating instructions
- `CHANGELOG.md` (this file)
- `.github/` community files: issue templates, PR template, FUNDING.yml
- `CITATION.cff` for Google Scholar / Zenodo / OpenSSF
- `llms.txt` at repo root for AI crawlers (ChatGPT, Claude, Perplexity)
- FAQ section in README to boost AI-search citation rate
- GitHub Pages site with Cayman theme + jekyll-seo-tag + jekyll-sitemap
- Banner image and polished author hero in README
- `examples/sample-vault/` showing 6 AI-first compliant note types (daily, person, project, idea, devlog, plus `_CLAUDE.md` template)
- `SECURITY.md` — vulnerability reporting policy and coordinated disclosure timeline
- Schema.org JSON-LD `SoftwareApplication` block on the Pages site (`_includes/head_custom.html`) for rich-result eligibility and AI-search citation
- 3 new FAQ entries targeting "Obsidian plugin vs Claude Code skill" search intent

### Changed

- GitHub About description rewritten to lead with "Claude Code skill for Obsidian"
- README banner alt text now contains the full search-intent phrasing
- GitHub topics: swapped `markdown` and `pkm` for `obsidian-skill` and `claude-code-skill`

### Fixed

- **`bootstrap_vault.py` `UnicodeEncodeError` on Windows `cp1252` consoles.** The script's emoji print statements (`🧠 Bootstrapping vault: ...`, `📁 Folders created`, `✅ Vault bootstrapped at: ...`) crashed on Windows before doing any work because the default Python `sys.stdout` encoding on Windows PowerShell / cmd is `cp1252`, which has no codepoints for those characters. `sys.stdout` and `sys.stderr` are now reconfigured to UTF-8 at script start, wrapped in `try/except (AttributeError, ValueError)` so non-text streams or environments without `.reconfigure()` fall back gracefully.
- **Removed dead `--minimal` flag from `bootstrap_vault.py`.** `argparse` accepted `--minimal` but the value was never passed into `bootstrap()` — the flag had no effect for any user since v0.1.0. Removing it changes no behavior.
- `pyproject.toml` version was `0.1.0`, now matches the v0.6.0 release tag.

## [0.6.0] — 2026-04-26

### Added

- `references/ai-first-rules.md` — canonical spec for vault writes (the 7 rules, frontmatter schemas per note type, preamble templates, anti-patterns, audit checklist).

### Changed

- All 31 commands now explicitly reference the AI-first rule. Surgical cross-reference per command file, no body rewrites. Closes the gap where two Claude sessions on the same conversation could produce inconsistently structured notes.
- `references/write-rules.md` now points to `ai-first-rules.md` as the foundation.
- `SKILL.md` — new "AI-first vault rule" section under Core Operating Principles.

### Notes

- 29 files changed, +406 lines, 0 breaking changes. Additive only.

## [0.5.0] — 2026-04-26

### Added

- **Research Toolkit** — five new commands that turn the vault into a live research workspace.
  - `/x-read [url]` — verbatim X post + thread + TL;DR + key claims + reply sentiment (Grok-4 + x_search).
  - `/x-pulse [topic]` — what's hot on X, gaps, working hooks, post ideas (Grok-4.20-reasoning + x_search).
  - `/research [topic]` — web research dossier with citations, recency markers, contrarian views, open questions (Perplexity Sonar Pro).
  - `/research-deep [topic]` — vault-first: scans vault, identifies gaps, fills only those, synthesizes a delta report, propagates updates via `/obsidian-save` (Perplexity sonar-reasoning-pro + Grok + vault scan).
  - `/youtube [url]` — transcript + metadata + top comments, summarized AI-first (youtube-transcript-api + YouTube Data API v3 + Grok-4).
- Section 0 of `_CLAUDE.md` template — first version of the AI-first vault rule, applied to all 5 research commands from day one.
- API key handling at `~/.config/obsidian-second-brain/.env` (Mac-local, never synced).
- `pyproject.toml` + `uv.lock` for Python dependency management.
- Auto-open behavior: every research save pops Obsidian to the new note via `obsidian://open?...`.

### Notes

- Command count went 26 → 31. Same install, same `_CLAUDE.md`.
- Without API keys, the original 26 commands still work — research toolkit degrades gracefully.

[Unreleased]: https://github.com/eugeniughelbur/obsidian-second-brain/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/eugeniughelbur/obsidian-second-brain/releases/tag/v0.6.0
[0.5.0]: https://github.com/eugeniughelbur/obsidian-second-brain/releases/tag/v0.5.0
