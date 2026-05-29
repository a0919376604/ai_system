# obsidian-architect — Design Spec

**Date:** 2026-05-26
**Status:** Draft - awaiting user sign-off, then writing-plans
**Branch:** TBD (suggest `feat/obsidian-architect`)
**New surface:** `/obsidian-architect <repo-path>` slash command + `scripts/architect_scan.py`
**Layer:** Layer 1 (Vault Operations)

---

## 1. Motivation

The vault already documents people, projects, ideas, tasks, decisions, dev logs, and weekly reviews. What it does not document is the **codebases** behind active projects.

Today, when the user wants to come back to a project after a few weeks away (or onboard a collaborator to one), there is no living "architecture overview" inside the vault. The user has to re-derive structure by reading source. The project hub note (`Projects/<P>/<P>.md`) carries the `local-path` field but nothing fills in the architectural shape that lives at that path.

This spec adds a slash command that scans a repo and generates a maintained architecture document set, hung off the existing project hub.

The vault already contains the building blocks: project hubs with `local-path`, `/obsidian-adr` for decision records, the AI-first vault rule, the adapter-friendly slash-command pattern. The missing piece is the scanner-plus-synthesizer that produces the architecture notes.

---

## 2. Goals

1. **One command in, maintained doc out.** `/obsidian-architect <repo-path>` produces `overview.md` plus per-module notes under `Projects/<P>/Architecture/`. Refresh is the same command, re-run.
2. **Optimised for onboarding and self-recall.** Content emphasis is human-friendly (one Mermaid diagram per overview, prose paragraphs, named entry points). Form is AI-first (frontmatter, `## For future Claude` preamble, wikilinks, recency markers) per the non-negotiable repo rule.
3. **Refresh preserves user edits.** A diff-aware re-run never overwrites paragraphs the user wrote. Sentinels and a lockfile back this guarantee.
4. **Module identity is stable across refresh.** A user-editable `_manifest.yml` pins module slugs, paths, roles. LLM proposes; user pins. Folder renames in source do not silently shuffle vault notes.
5. **Hybrid pipeline: deterministic where it must be, LLM where judgment is needed.** Phase 1 (scan and propose manifest) is pure Python and is deterministic for a given commit hash. Phase 3 (synthesise prose and diagrams) is LLM.
6. **No new vault schema changes outside `Architecture/`.** All output frontmatter conforms to `references/ai-first-rules.md`. New frontmatter `type:` values (`architecture-overview`, `architecture-module`, `architecture-data-flow`) are documented in that file as part of this change.
7. **Adapter-compatible.** The command body uses generic tool wording so the existing adapters compile it for Codex CLI, Gemini CLI, and OpenCode without per-platform forks.

---

## 3. Non-goals

- **No automatic refresh.** No new scheduled agent in Layer 4 for v1. User triggers refresh manually. If usage proves it is wanted, adding a cron is additive later.
- **No ER diagrams from DB schemas, no sequence diagrams from runtime traces, no LSP integration.** Out of scope for v1. The frontmatter reserves a `pattern:` field so future emerge-style cross-repo work has a slot, but no implementation here.
- **No cross-repo architectural emerge.** That belongs in a future extension of `/obsidian-emerge`, not in this command.
- **No "all-LLM" generation path.** The scanner is the manifest source. Pure-LLM module proposals would drift between runs and break refresh.
- **No Notion sync from architecture notes.** The existing `/obsidian-notion-sync` covers that surface; the user runs it separately if desired.
- **No human-friendly rewrite of vault output.** The repo's `CLAUDE.md` explicitly forbids this. Content density is tuned for readability; form stays AI-first.

---

## 4. Locked decisions (from brainstorming)

These are settled. The implementation plan should treat them as constraints, not options.

| Decision | Choice |
|---|---|
| Primary audience | Human onboarding and self-recall (with AI-first form preserved) |
| Detail level | Overview plus 5-10 top-level module notes (no per-file granularity) |
| Refresh strategy | Diff-aware re-run, preserves user edits via sentinels and lockfile |
| Module identity | Folder-based plus LLM merge/split, pinned by user-editable `_manifest.yml` |
| Hub integration | Auto-find project hub via `local-path`; auto-create if missing (re-use `/obsidian-project` logic); `--project=<P>` flag for multi-repo |
| Implementation shape | Python scanner (`scripts/architect_scan.py`) plus repomix for packing plus LLM for synthesis |

---

## 5. Command surface

### 5.1 File

`commands/obsidian-architect.md` (platform-neutral source, picked up by adapters).

Frontmatter:

```yaml
---
description: Scan a codebase and generate architecture overview plus module notes into the project hub
category: vault
triggers_en: ["architect", "architecture doc", "scan repo", "document architecture", "codebase overview"]
---
```

### 5.2 Invocation

```
/obsidian-architect <repo-path>                  # default: scan + write
/obsidian-architect <repo-path> --project=<P>    # force project hub binding
/obsidian-architect <github-url>                 # remote repo via repomix --remote
/obsidian-architect <repo-path> --refresh        # explicit refresh (vs auto-detect)
/obsidian-architect <repo-path> --dry-run        # Phase 1 only, no vault writes
/obsidian-architect <repo-path> --force          # ignore "no changes" gate
```

If `<repo-path>` is omitted and the current working directory is a git repo, it defaults to `.`. Otherwise the command asks the user.

### 5.3 Project hub resolution

Priority order:

1. `--project=<P>` flag.
2. Search vault for a project hub whose `local-path` frontmatter resolves to the same absolute path as `<repo-path>`. Comparison is on resolved absolute paths (symlinks followed), case-sensitive on Linux and macOS, case-insensitive on Windows. If exactly one match, use it.
3. If zero matches: create the project hub following the same conventions used by `/obsidian-project` (sub-folder layout, hub frontmatter schema with `date`, `tags: [project]`, `status: active`, `local-path`, the `Projects/<P>/{Ideas,Tasks,Decisions,Learnings,Research,Competitors,Recaps}/` skeleton, and a `board.md`). Project name defaults to the repo folder basename; ASK the user before creating so a typo can be corrected.
4. If multiple matches: abort with an error listing the candidate hubs, ask user to disambiguate via `--project=<P>`.

Note: this command duplicates the hub-creation conventions rather than invoking `/obsidian-project` directly, because slash commands in this repo are not callable as functions. The duplication is acceptable because the schema is documented in `references/ai-first-rules.md` and changes to it are infrequent.

---

## 6. Vault layout

### 6.1 Single-repo layout (default)

```
Projects/<P>/
|-- <P>.md                             # existing hub. New "## Architecture" section appended/replaced.
|-- Architecture/
|   |-- _manifest.yml                  # module identity. User-editable. Source of truth.
|   |-- _manifest.lock.json            # auto-generated. Tracks LLM-written field hashes for refresh.
|   |-- overview.md                    # system overview + Mermaid
|   |-- data-flow.md                   # data flow note (skipped if no clear chain detected)
|   `-- modules/
|       |-- <module-slug>.md
|       `-- ...
|-- Decisions/                         # existing. Architecture/ wikilinks here for ADRs.
`-- _archived/                         # if any module is archived during refresh (see Section 11)
```

### 6.2 Multi-repo layout (via `--project=<P>` with multiple repos)

```
Projects/<P>/
|-- Architecture/
|   |-- _index.md                      # lists each repo's architecture entry
|   |-- <repo-name>/
|   |   |-- _manifest.yml
|   |   |-- _manifest.lock.json
|   |   |-- overview.md
|   |   `-- modules/...
|   `-- <other-repo>/
|       `-- ...
```

The `_index.md` is regenerated on every run that touches any sub-repo; it lists each repo, last scan date, module count, link to its `overview.md`.

### 6.3 Hub note integration

`Projects/<P>/<P>.md` gets a `## Architecture` section, appended if absent or replaced in place if present. Idempotent. Content:

```markdown
## Architecture

- Overview: [[Architecture/overview]] (last scanned 2026-05-26 @ `a3f9b21`)
- Modules: 5 active, 0 deprecated
- Refresh: `/obsidian-architect <repo-path> --refresh`
```

For multi-repo hubs, the section instead lists each repo with its own line and link to its sub-`overview.md`.

---

## 7. Pipeline

Three phases. Phase 1 is deterministic Python. Phase 2 is an interactive checkpoint. Phase 3 is LLM synthesis.

### 7.1 Phase 1: Deterministic scan (`scripts/architect_scan.py`)

Inputs: repo path (local) or github URL (cloned to temp via `repomix --remote`), optional existing `_manifest.yml`.

Steps:

1. **Resolve repo.** Local: validate it is a git repo. Remote: call `repomix --remote <url> --output /tmp/<hash>/` to clone-and-pack; treat the clone as the local repo from here on.
2. **Probe metadata.**
   - `git rev-parse HEAD` for commit hash. `git status --porcelain` for dirty-tree flag.
   - Language counts from walking files with `.gitignore` respected (use `repomix --output-style json --top-files-len 0` to get file list plus per-file token counts; fall back to a Python `pathspec`-based walker if repomix not installed).
   - Entry points by reading config files: `package.json` (`main`, `bin`, `scripts`), `pyproject.toml` (`[project.scripts]`, `[tool.poetry.scripts]`), `go.mod` plus `main.go`, `Cargo.toml` (`[[bin]]`), `Makefile` targets, `Dockerfile` ENTRYPOINT/CMD.
   - External runtime deps from the same files (exclude dev/test groups).
3. **Module proposal.**
   - Default: each first-level folder under the repo root (or `src/` if it exists) becomes a candidate module.
   - Heuristic merge: sibling folders that share a primary language and each contain fewer than 2000 tokens are proposed as merged.
   - Heuristic split: a single folder with more than 30 files and more than one entry point is proposed as split.
   - Skip set: `tests/`, `docs/`, `examples/`, `.github/`, build output (`dist/`, `build/`, `target/`, `out/`). These appear in the manifest with `excluded: true` so the overview can still reference them but no module note is generated.
   - **Flat-repo fallback**: if the repo has no `src/` and fewer than 3 non-skip folders at the root (e.g. all source files live in the repo root), Phase 1 proposes a single `core` module covering the root, plus separate modules for any non-skip folder. The scanner emits a warning that flat layouts produce thin documentation and suggests the user manually split the manifest if the repo has logical sub-systems.
4. **Output**: `_manifest.yml` proposal plus `scan-report.json` (file tree, tokens, deps, entry points, monorepo workspaces if detected).

Determinism guarantee: given the same commit hash and the same scanner version, Phase 1 output is byte-identical.

### 7.2 Phase 2: Manifest review

Command body, after invoking Phase 1:

1. If `Projects/<P>/Architecture/_manifest.yml` already exists: diff against the new proposal. Show added modules, removed modules, renamed paths.
2. If it does not exist: show the full proposal.
3. **Ask the user** to confirm or to edit the manifest before writing. The user can:
   - Approve as proposed.
   - Edit inline (the command opens the manifest in `$EDITOR` if interactive, or accepts a piped-in YAML).
   - Reject (abort with no vault writes).
4. Write the approved `_manifest.yml` to the vault.

### 7.3 Phase 3: Synthesis

For each module in the approved manifest where the module is not `excluded`:

1. Run `repomix --include "<paths>" --style xml --compress` to produce a packed module corpus.
2. Token gate: if the packed output exceeds 80,000 tokens as reported by repomix's own count (which uses `tiktoken`'s `o200k_base` and is close to but not identical to Claude tokenization), fall back to packing only the largest-N files plus the leading docstring or comment block of every other file. Record the truncation in the module note frontmatter (`scan-truncated: true`). The 80,000 limit is a conservative budget that leaves headroom for the prompt plus completion within a 200K context window.
3. LLM writes `modules/<slug>.md` using the schema in Section 9.2. If `_manifest.yml` has a non-null `description` for the module, that text is inserted verbatim into the note's "What it does" section and LLM does not regenerate that paragraph.

After all module notes are written:

4. LLM writes `overview.md` from: every module note's frontmatter plus its first paragraph, the full file tree, the entry-points list, the external deps list. The overview is regenerated on every run (cheap, and any module change can affect the global story).
5. If the scanner identified a clear input-to-output data chain (at least one entry point with reachable outputs), LLM writes `data-flow.md`. Otherwise skip.

### 7.4 Failure handling per phase

| Phase | Failure | Behaviour |
|---|---|---|
| 1 | Repo path missing or not a git repo | Abort with error. No vault writes. |
| 1 | repomix not installed | Fall back to pure-Python walker with a warning. About 3x slower but functionally equivalent. |
| 1 | Vault root has no `_CLAUDE.md` | Abort with prompt to run `/obsidian-init` first. |
| 1 | Multiple hubs match the same `local-path` | Abort, list candidates, ask user to pass `--project=<P>`. |
| 2 | User rejects manifest | Abort. Manifest not written. No side effects. |
| 3 | A single module's synthesis fails | Skip that module, write a placeholder note with `status: scan-failed` and the error captured in frontmatter. Continue other modules. |
| 3 | Overview synthesis fails | Module notes are preserved. Overview is written as a placeholder with `status: scan-failed`. User can re-run `--refresh --force`. |

`--dry-run` runs Phase 1, prints the proposed manifest plus scan report, and exits. No vault writes. No way to "continue from dry-run" - re-running without the flag re-does Phase 1 (cheap and deterministic).

---

## 8. Manifest schema

### 8.1 `_manifest.yml`

```yaml
# Auto-generated by /obsidian-architect, but user-editable.
# Fields marked [pinned] are preserved verbatim across refresh.

version: 1
repo:
  name: obsidian-second-brain
  root: /Users/leric/Desktop/code/obsidian-second-brain   # [pinned] = the hub's local-path
  remote: https://github.com/eugeniu/obsidian-second-brain
  primary_language: python
  languages:
    - { lang: python, files: 23, tokens: 18400 }
    - { lang: markdown, files: 42, tokens: 31200 }
    - { lang: shell, files: 8, tokens: 2100 }

last_scan:
  date: 2026-05-26
  commit: a3f9b21
  dirty: false
  scanner_version: 0.1.0

modules:
  - slug: commands              # [pinned] stable identity, used as filename
    display_name: Slash Commands
    paths:                      # [pinned by user] what counts as this module
      - commands/
    role: surface               # [pinned] surface | core | adapter | infra | data | docs | other
    description: |              # [user-editable] if present (non-null), NOT overwritten
      The platform-neutral source of truth for all 32 slash commands.
    excluded: false
    pattern: null               # reserved for future /obsidian-emerge

  - slug: tests
    display_name: Tests
    paths: [tests/]
    role: docs
    excluded: true              # included in overview, no module note
```

### 8.2 Refresh field preservation

| Field | Refresh behaviour |
|---|---|
| `repo.name` | Overwrite. |
| `repo.root` | Preserve (user-set, pinned). |
| `repo.languages` | Overwrite (recount each scan). |
| `last_scan.*` | Overwrite. |
| `modules[].slug` | Preserve. Slug change is treated as a rename (see Section 11). |
| `modules[].paths` | Preserve if user edited (lockfile says hash differs from last LLM write). Otherwise re-propose. |
| `modules[].display_name` | Preserve if user edited. |
| `modules[].role` | Preserve if user edited. |
| `modules[].description` | Preserve if non-null. If null, LLM writes the summary into the note (not into the manifest). |
| `modules[].excluded` | Preserve. |
| `modules[].pattern` | Preserve. |

### 8.3 `_manifest.lock.json`

Auto-generated. The user should not edit it. Recommended to commit it to git so cross-machine refresh is consistent.

```json
{
  "version": 1,
  "scanner_version": "0.1.0",
  "fields": {
    "modules.commands.display_name": { "hash": "sha256:abc...", "value": "Slash Commands" },
    "modules.commands.role":         { "hash": "sha256:def...", "value": "surface" }
  },
  "note_blocks": {
    "modules/commands.md": {
      "what-it-does":  { "hash": "sha256:..." },
      "how-it-works":  { "hash": "sha256:..." }
    }
  }
}
```

The `fields` map covers manifest preservation. The `note_blocks` map covers user-edit detection inside note bodies (Section 9.4).

---

## 9. Note schemas

Every note conforms to `references/ai-first-rules.md`: `## For future Claude` preamble, rich frontmatter, mandatory wikilinks for every person, project, concept; external claims with `(as of YYYY-MM, source-url)`; confidence levels where applicable.

### 9.1 Overview note (`Architecture/overview.md`)

Frontmatter:

```yaml
---
type: architecture-overview
date: 2026-05-26
project: "[[<P>]]"
repo: <repo-name>
local-path: <absolute path>
commit: a3f9b21
last-scanned: 2026-05-26
scanner-version: 0.1.0
primary-language: python
tags:
  - architecture
  - codebase-doc
ai-first: true
status: current
---
```

Body sections, in order:

1. `## For future Claude` preamble.
2. `## Purpose` - one paragraph.
3. `## Layer map` - one Mermaid diagram (`graph TD` by default; `flowchart LR` if more than 8 top-level nodes, switch is automatic).
4. `## Modules` - bullet list, each line is `[[modules/<slug>|<display_name>]] - <role> - <one-line summary>`.
5. `## Entry points` - bullet list with brief annotation.
6. `## External dependencies` - bullet list, runtime deps with recency marker `(as of YYYY-MM, source-url)` for each.
7. `## Key abstractions` - extracted from module summaries, 2-5 items.
8. `## Related` - links back to project hub, Decisions folder, and the data-flow note if present.

### 9.2 Module note (`Architecture/modules/<slug>.md`)

Frontmatter:

```yaml
---
type: architecture-module
date: 2026-05-26
project: "[[<P>]]"
repo: <repo-name>
module-slug: <slug>
display-name: <display>
role: <role>
paths:
  - <path1>
  - <path2>
last-scanned: 2026-05-26
commit: a3f9b21
file-count: 35
tokens: 18400
primary-language: markdown
scan-truncated: false
tags:
  - architecture
  - module
ai-first: true
status: current
---
```

Body sections:

1. `## For future Claude` preamble.
2. `## What it does` - one paragraph. Replaced verbatim if manifest `description` non-null.
3. `## How it works` - bullet list, 3-7 points.
4. `## Key files` - bullet list, 4-8 files with one-line summary each.
5. `## Depends on` - wikilinks to other module notes within this repo (inferred from imports plus heuristics).
6. `## Consumed by` - the inverse direction.
7. `## Recent activity` - last 5 git commits touching this module's paths, with date and one-line subject.
8. `## Related` - links to overview, manifest, relevant decisions.

### 9.3 Data-flow note (`Architecture/data-flow.md`)

Same frontmatter shape with `type: architecture-data-flow`. Body is one or two Mermaid sequence diagrams plus a brief prose walkthrough. Generated only when the scanner identifies a clear input-to-output chain; never speculative.

### 9.4 Sentinels for refresh safety

Every LLM-written section in a module note is wrapped in sentinels:

```markdown
<!-- @generated:start what-it-does -->
LLM-written paragraph.
<!-- @generated:end what-it-does -->

<!-- @user:start notes -->
## Notes
This module is being deprecated in favor of X. See [[ADR-007]].
<!-- @user:end notes -->
```

Refresh rules:

- `@generated:start/end` blocks are replaced verbatim on refresh.
- `@user:start/end` blocks are never touched.
- Any content outside both sentinel kinds: refresh compares against the previous LLM output hash from `_manifest.lock.json`. If hash matches, the content is treated as LLM-written and overwritten. If hash differs, the content is preserved and a warning is emitted: "Found user edits outside sentinels in modules/<slug>.md - preserved as-is, will not be re-generated."

---

## 10. Hub note `## Architecture` section

Format for single-repo:

```markdown
## Architecture

- Overview: [[Architecture/overview]] (last scanned 2026-05-26 @ `a3f9b21`)
- Modules: 5 active, 0 deprecated
- Refresh: `/obsidian-architect <repo-path> --refresh`
```

Format for multi-repo:

```markdown
## Architecture

- web-frontend: [[Architecture/web-frontend/overview]] (last scanned 2026-05-26 @ `a3f9b21`)
- api-backend: [[Architecture/api-backend/overview]] (last scanned 2026-05-24 @ `7c8e1d4`)
- ios-app: [[Architecture/ios-app/overview]] (last scanned 2026-05-20 @ `9bf2a01`)
- Refresh: `/obsidian-architect <repo-path> --refresh` per repo.
```

Placement: appended to end if section absent, replaced in place if present. The section is the **last** auto-managed section in the hub; user-added sections after it are preserved.

---

## 11. Refresh, rename, archive

### 11.1 Refresh decision tree

```
/obsidian-architect <repo-path>
    |
    v
Does Projects/<P>/Architecture/_manifest.yml exist?
    |
    +-- No  -> first-run flow (Phase 1 -> 2 -> 3 all run)
    |
    +-- Yes -> refresh flow
            |
            +-- Run Phase 1. Compare new manifest to old.
            |
            +-- Manifests equal AND commit equal AND not --force?
            |       -> Ask "No changes detected since last scan. Re-synthesize anyway?"
            |
            +-- Manifests differ (added, removed, renamed modules)?
            |       -> Show diff, ask confirm.
            |
            +-- Phase 3: only re-synthesise affected modules. Skip unaffected.
```

### 11.2 Per-module re-synthesis rule

```
For each module in the approved manifest:
    if module.slug not in lockfile:
        new module -> generate note.
    elif module.paths changed vs lockfile:
        path change -> regenerate note (frontmatter updated).
    elif git diff --quiet <old-commit>..<new-commit> -- <module-paths> returns non-zero:
        content change -> regenerate note.
    elif --force:
        regenerate.
    else:
        skip body, update frontmatter `last-scanned` only.
```

Overview always regenerated. Cheap, and any module change can shift the global narrative.

**Known limitation: dirty working tree.** The git-diff check above compares committed states (`<old-commit>..<new-commit>`). Uncommitted changes in the working tree do not trigger re-synthesis of an otherwise-unchanged module. The user can pass `--force` to override, or commit first. Phase 1 still records `dirty: true` in the manifest's `last_scan` block and tags the commit field with `+dirty` so the staleness is visible in the note frontmatter.

### 11.3 Renames, archives, deletions

| Situation | Behaviour |
|---|---|
| New folder in repo | Phase 1 proposes a new module. User confirms. New note written. |
| Folder deleted in repo | Manifest entry stays. Module note frontmatter set to `status: deprecated`, `removed_at: YYYY-MM-DD` added. File not deleted. |
| Folder renamed in repo | Phase 1 detects "old path empty, new path has no module" and proposes a rename. On confirm, manifest `paths` updates. Note slug and filename unchanged (slug is the identity). |
| User changes slug in manifest | Refresh detects "manifest has slug X but note file Y exists at the old slug". Proposes `mv` of the note file. Never moves automatically. |
| User merges two manifest entries | Refresh detects "manifest has one entry but two notes exist for the old slugs". Proposes archiving the redundant note to `Architecture/_archived/<old-slug>.md`. Never archives automatically. |

### 11.4 Daily note and operation log propagation

After a successful run (consistent with `/obsidian-adr` convention):

- If `Logs/` exists in the vault: append `**HH:MM** - architect | <P> - N modules (M new, K updated, L deprecated)` to `Logs/YYYY-MM-DD.md`.
- Otherwise: append `## [YYYY-MM-DD] architect | <P> - N modules (M new, K updated, L deprecated)` to `log.md`.
- Append to today's daily note `## Activity` section: `- /obsidian-architect: scanned [[<P>]] @ commit a3f9b21`.

---

## 12. Edge cases

| Situation | Behaviour |
|---|---|
| Repo is a monorepo | Phase 1 detects `pnpm-workspace.yaml`, `lerna.json`, `Cargo.toml [workspace]`, or `go.work`. Each workspace member becomes a module candidate. |
| Repo is not a git repo | Abort. Architecture doc needs a commit hash for provenance. |
| Working tree dirty | Warn, do not block. Commit field written as `a3f9b21+dirty`. |
| Same `local-path` matches multiple hubs | Abort, list candidates, require `--project=<P>`. |
| Polyglot repo | `repo.languages` lists top 5. `primary-language` is the highest by token count. Entry-point detection runs per supported language config file. |
| Repo is mostly docs (source token share below 5 percent) | Ask user to confirm. Suggest `/obsidian-project` instead if appropriate. |
| `repomix` not installed | Fall back to pure-Python walker (uses `pathspec` for `.gitignore`). Functional, slower. |
| `repomix --remote` fails on private repo | Suggest user `git clone` locally first, then re-run with the local path. |
| Vault has no `_CLAUDE.md` | Abort with prompt to run `/obsidian-init`. |
| `Architecture/` exists but `_manifest.yml` is missing | Ask user: (a) reconstruct manifest from existing module notes, or (b) wipe and re-scan. |

---

## 13. Adapter compatibility

- **Claude Code**: identity copy via the existing adapter.
- **Codex CLI, Gemini CLI, OpenCode**: the command body uses generic tool wording (`read files` not "Read tool", `run shell commands` not "Bash tool"). The existing `adapters/lib.sh` rewrites pick this up automatically. No `exclude:` frontmatter; all four platforms can run the command provided `python` and (optionally) `repomix` are in PATH.

---

## 14. Testing strategy

The repo currently has no automated test suite for commands, but `architect_scan.py` is deterministic Python and warrants real unit tests.

### 14.1 Unit tests (`tests/test_architect_scan.py`)

Fixture repos under `tests/fixtures/architect/`:

- `single-lang-python/` - a small Python package with `pyproject.toml` and three source folders.
- `monorepo-pnpm/` - a `pnpm-workspace.yaml` with two workspace members.
- `polyglot/` - Python plus JS plus shell in the same repo.
- `docs-only/` - mostly markdown, very little code.

Assertions:

- Phase 1 output (file tree, language counts, entry points, dep list, proposed manifest) is byte-stable for a given fixture.
- Module proposal heuristics (merge, split, exclude) behave as documented in Section 7.1.
- Manifest diff logic correctly classifies added, removed, renamed, edited modules.
- Lockfile hash logic correctly distinguishes LLM-written from user-edited fields.

### 14.2 Manual verification

Phase 3 LLM synthesis is not unit-tested. The spec ships with a manual verification checklist:

1. Run `/obsidian-architect .` against this repo. Inspect the generated `overview.md` against `architecture.md` (the hand-written reference document). Spot major omissions or hallucinations.
2. Edit a paragraph inside a `@generated` block. Re-run. Confirm the paragraph was regenerated (sentinels working).
3. Edit a paragraph outside any sentinel. Re-run. Confirm the paragraph was preserved and a warning was emitted.
4. Add a `## Notes` section wrapped in `@user` sentinels. Re-run. Confirm it survived.
5. Manually rename a module slug in `_manifest.yml`. Re-run. Confirm the command asks before moving the note file.

---

## 15. Documentation updates

Adding a new command requires (per `CLAUDE.md`):

- New `commands/obsidian-architect.md`.
- New `scripts/architect_scan.py` plus supporting modules under `scripts/architect/` if needed.
- Update `references/ai-first-rules.md` with the new `type:` values: `architecture-overview`, `architecture-module`, `architecture-data-flow`.
- Update `SKILL.md` (Layer 1 command list and count) and `README.md` (commands table).
- Add `CHANGELOG.md` entry under "Unreleased".

---

## 16. Open questions

None at draft time. Brainstorming locked all six major decisions. The lockfile-versus-YAML-comment-sentinel question, the manifest auto-vs-interactive question, and the sentinel scope question were all resolved during the design walk-through.

If the spec review (next step) surfaces a new question, it goes here.

---

## 17. What ships in v1

A working `/obsidian-architect <repo-path>` plus the supporting scanner, with the behaviour described above. Specifically:

- First-run flow on any local git repo.
- Refresh flow with diff-aware re-synthesis.
- Manifest plus lockfile.
- Overview, module, optional data-flow notes with AI-first frontmatter and sentinels.
- Hub note integration.
- Daily log and operation log propagation.
- Multi-repo support via `--project=<P>`.
- Remote repo support via `repomix --remote`.
- Adapter compatibility for all four platforms.
- Unit tests for Phase 1.

What does **not** ship in v1: scheduled refresh agent, ER diagrams, sequence-from-trace, LSP integration, cross-repo emerge, Notion sync from architecture notes.
