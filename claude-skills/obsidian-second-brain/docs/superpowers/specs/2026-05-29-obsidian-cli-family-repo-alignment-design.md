# Obsidian CLI Family `<repo>` Alignment Design

**Status:** Draft — ready for review
**Date:** 2026-05-29
**Author:** brainstormed with user (Eugeniu)
**Related specs:**
- v4.x architect specs (`/obsidian-architect` already uses `<repo>`)
- v4.4 `/obsidian-brainstorm` spec (this rename touches it)

---

## Goal

Rename `/research` → `/obsidian-research`, `/research-deep` → `/obsidian-research-deep`, and unify the **first positional argument** across the five project-scoped commands to `<repo>` (currently a mix of `<repo>` / `<project-name>` / `--project=<flag>`). Output: a Discord-friendly CLI surface where the user picks repo first, then types their query / flags.

## Why

**Driving pain:** in Discord, slash commands map cleanly to typed parameters with autocomplete. Today `/research` takes the topic positionally with `--project=` as optional flag — Discord users must type query first AND remember the project-flag dance. They want:

> 先選 project (dropdown) → 再打 query。

Equivalent CLI grammar must put `<repo>` first positional so Discord's first-param autocomplete is the project picker.

**Secondary win:** family-wide consistency. Right now:
- `/obsidian-architect <repo>` ← uses `<repo>`
- `/obsidian-brainstorm <project-name>` ← uses `<project-name>`
- `/obsidian-roadmap <project-name>` ← uses `<project-name>`
- `/research <topic> [--project=...]` ← project as optional flag
- `/research-deep <topic> [--project=...]` ← same

Five commands, three different naming conventions. Unify on `<repo>` because architect is the most-used entry point and its meaning (path OR project name) is already the user mental model.

## Non-goals

- NOT renaming `/obsidian-project`, `/obsidian-decide`, `/obsidian-recap`, `/obsidian-task`, `/obsidian-board`, or other `obsidian-*` commands. They don't take a `<project>` as first positional arg in the same shape — leave them alone.
- NOT changing the underlying Python scripts (`scripts/research/research.py`, `scripts/research/research_deep.py`) — only the command-body parsing and the routing logic change.
- NOT adding new functionality. This is a CLI surface refactor only.
- NOT shipping Discord adapter wiring in this release — but reserve the frontmatter schema (`param-autocomplete`) so a future Discord adapter ships can pick up without further command-body changes.

## Scope (5 commands)

| # | Command | Today | After |
|---|---|---|---|
| 1 | `/obsidian-architect` | `<repo>` | `<repo>` (unchanged in name; switch to shared `resolve_repo_arg` helper) |
| 2 | `/obsidian-brainstorm` | `<project-name>` | `<repo>` (rename hint, switch to shared resolver) |
| 3 | `/obsidian-roadmap` | `<project-name>` | `<repo>` (rename hint, switch to shared resolver) |
| 4 | `/research` | `<topic> [--project=<name>]` | `/obsidian-research <repo> <topic> [--academic]` |
| 5 | `/research-deep` | `<topic> [--project=<name>]` | `/obsidian-research-deep <repo> <topic>` |

## `<repo>` semantics

Three forms accepted (parsed in order):

1. **Sentinel `global`** — `_` and `-` also accepted as aliases. Skips project routing entirely. Only valid for research commands (4 & 5); brainstorm/roadmap/architect reject it with a clear error.
2. **Absolute path** — starts with `/`. Resolved against vault's project hubs by `local-path` frontmatter exact match. Single match → bind that project. Zero matches → abort with "no project hub binds to this path; run `/obsidian-project <name>` first." Multiple matches → abort and list.
3. **Project name** — anything else. Resolved by:
   - **Exact match** against `Projects/<token>/` folder name → state `project`, bind immediately.
   - **Fuzzy match** otherwise — token is a substring of one-or-more project folder names, OR Levenshtein distance ≤ 2 from one-or-more folder names. Returns state `ambiguous` with the matching candidate list. Caller asks the user to pick one. If `len(candidates) == 1`, still return `ambiguous` (not auto-bind) so the user explicitly confirms the typo-correction.
   - **No match** at all → state `unknown` with `candidates` = full list of all `Projects/*/` folder names. Caller aborts with the list shown to user.

## New grammar

```bash
/obsidian-architect       <repo> [--refresh] [--no-features] [--no-ai-flows] ...   # unchanged
/obsidian-brainstorm      <repo> [--topic="..."] [--lens=...] [--depth=...] [--lang=...] [--research-window-days=N]
/obsidian-roadmap         <repo> [--dry-run] [--force] [--only-themes=N] [--skip-research] [--lang=...] [--scope-research-days=N]
/obsidian-research        <repo> <topic> [--academic]
/obsidian-research-deep   <repo> <topic>
```

Rules:
- `<repo>` is always the **first positional argument**. No exceptions.
- For research commands: `<topic>` is everything after the first whitespace until first `--flag`. So `/obsidian-research langlive-line-oa LINE 限流策略 --academic` parses topic = `LINE 限流策略`.
- For brainstorm/roadmap/architect: flags-only after `<repo>` (no `<topic>` positional).

**Examples (all valid):**

```bash
/obsidian-research langlive-line-oa LINE 限流策略
/obsidian-research ai-eden-service Replika memory v2 --academic
/obsidian-research global agent memory 2025 trends
/obsidian-research-deep ai-eden-service Character.AI retention model
/obsidian-research /Users/leric/Desktop/code/langlive-line-oa "shift handoff workflow"
/obsidian-brainstorm langlive-line-oa --topic="客戶流失" --depth=medium
/obsidian-roadmap ai-eden-service --dry-run
/obsidian-architect /Users/leric/Desktop/code/ai-eden-service --refresh
```

## Shared resolver (`scripts/commands/repo_resolver.py`)

NEW Python module with one public function:

```python
@dataclass
class RepoResolution:
    state: str                       # "project" | "global" | "ambiguous" | "unknown"
    project_slug: str | None         # set when state == "project"
    project_dir: Path | None         # set when state == "project"
    local_path: str | None           # bound repo path from project hub frontmatter, if any
    candidates: list[str]            # set when state == "ambiguous" or "unknown"
    message: str                     # human-readable explanation for the caller


def resolve_repo_arg(
    token: str,
    vault_root: Path,
    *,
    allow_global: bool = False,
) -> RepoResolution:
    """Resolve a CLI <repo> token into a project hub binding.

    Resolution order:
    1. If token is `global`, `_`, or `-` AND allow_global=True → state='global'.
    2. If token starts with `/` (absolute path):
       a. Walk Projects/*/<P>.md hubs; match by `local-path` frontmatter == token.
       b. Single match → state='project' with that hub.
       c. Zero matches → state='unknown' with empty candidates.
       d. Multiple matches → state='ambiguous' with project_slug list.
    3. Otherwise treat as a project-name token:
       a. Exact match against Projects/<token>/ folder → state='project'.
       b. Fuzzy match (substring or Levenshtein ≤ 2) → state='ambiguous' with candidates.
       c. No match → state='unknown' with full project list as candidates.
    """
```

5 commands all call `resolve_repo_arg(token, vault_root, allow_global=...)`. The slash-command body inspects `RepoResolution.state` and acts:
- `project`: continue execution with `project_dir`
- `global`: continue execution with vault-wide pathing (research commands only)
- `ambiguous`: ASK user to disambiguate via `AskUserQuestion`
- `unknown`: ABORT with `message` shown to user (includes candidate list)

## Backward compatibility

Two-tier deprecation:

**Tier 1 — soft deprecation (this release):**

- `/research` and `/research-deep` still callable. Adapter's command file body opens with a deprecation banner:
  ```
  ⚠️  /research is renamed to /obsidian-research. Old name still works
      for now but will be removed in a future minor release. Use:
        /obsidian-research <repo> <topic>
      (where <repo> is "global" for cross-project research).
  ```
- Old `--project=<name>` flag still parsed for `/obsidian-research` and `/obsidian-research-deep` — when present AND first positional is `global`, the flag wins (overrides sentinel to bind that project).
- `/obsidian-brainstorm <project-name>` and `/obsidian-roadmap <project-name>` — already accept project names; no warning (rename is purely doc-side).

**Tier 2 — hard removal (next minor release after this one):**

- Delete `commands/research.md` and `commands/research-deep.md`.
- Drop `--project=` flag support in research commands.

Tracked in CHANGELOG as a `## Deprecated` section that survives across releases until hard removal.

## File-by-file changes

**New files:**
- `scripts/commands/__init__.py` (if missing)
- `scripts/commands/repo_resolver.py` — `resolve_repo_arg()` + `RepoResolution` dataclass
- `tests/commands/test_repo_resolver.py` — 7+ tests covering all 4 resolution states
- `commands/obsidian-research.md` — new (copy from `commands/research.md` content + grammar change + frontmatter `argument-hint` + `param-autocomplete`)
- `commands/obsidian-research-deep.md` — same

**Modified files:**
- `commands/research.md` — replaced by deprecation stub:
  ```markdown
  ---
  description: "[deprecated] use /obsidian-research instead"
  category: research
  ---

  Print deprecation warning to user, then forward to `/obsidian-research $ARGUMENTS`.

  This stub is removed in the next minor release.
  ```
- `commands/research-deep.md` — same shape stub
- `commands/obsidian-brainstorm.md` — change `argument-hint: <project-name>` → `<repo>`; change body's Phase 0 to call `resolve_repo_arg`; reject sentinel `global` with error; remove ambiguity about path-vs-name (it now accepts both)
- `commands/obsidian-roadmap.md` — same shape change
- `commands/obsidian-architect.md` — body's project resolution section replaced by `resolve_repo_arg` call (semantic-equivalent; existing path/name resolution logic moves into the shared helper)
- `SKILL.md` — update command table (5 rows)
- `README.md` — update command table (5 rows)
- `CHANGELOG.md` — `## [Unreleased]` entry + `## Deprecated` section

## Slash-command frontmatter — new optional field

Add `param-autocomplete` for Discord adapter to consume (currently no-op for claude-code/codex/gemini/opencode):

```yaml
---
description: ...
argument-hint: <repo> <topic>
category: research
triggers_en: [...]
param-autocomplete:
  - name: repo
    source: vault-projects-plus-global   # adapter implementation will resolve this token
  - name: topic
    source: freetext
---
```

Sources defined for v1:
- `vault-projects` — autocomplete from `<vault>/Projects/*/` folder names. Used by brainstorm/roadmap/architect.
- `vault-projects-plus-global` — vault projects + the literal `global`. Used by research commands.
- `freetext` — no autocomplete (Discord shows a plain text input).

`adapters/` build pipeline today reads frontmatter for `description` / `argument-hint` / `triggers_en` etc. Adding `param-autocomplete` is forward-compatible — existing adapters ignore unknown fields. Discord adapter (future ship) generates Discord slash-command JSON from this.

## Body parsing — Phase 0 stub all 5 commands share

Replace each command's "Project routing" Phase 0 block with a unified preamble:

````markdown
## Phase 0: Resolve <repo>

Parse the first whitespace-delimited token from `$ARGUMENTS` as the `<repo>` argument.

```python
import shlex
tokens = shlex.split(args, posix=True)
if not tokens:
    abort("missing <repo> argument; see /obsidian-architect --help")
repo_token, remaining_args = tokens[0], " ".join(tokens[1:])

from scripts.commands.repo_resolver import resolve_repo_arg
resolution = resolve_repo_arg(
    repo_token,
    vault_root=Path("~/Documents/SecondBrain").expanduser(),
    allow_global=<true for research commands, false otherwise>,
)

if resolution.state == "project":
    project_dir = resolution.project_dir
    project_slug = resolution.project_slug
elif resolution.state == "global":
    project_dir = None     # research commands route to Research/Web/ etc.
elif resolution.state == "ambiguous":
    ask_user_to_pick(resolution.candidates)
elif resolution.state == "unknown":
    abort(resolution.message)
```

`remaining_args` is what the rest of the command body consumes (flags + topic).
````

The actual body inserts this as a documentation block + concrete Phase 0 step. The slash-command runtime (Claude) executes the resolution by reading the project list directly from the vault — no Python invocation needed in most cases (it's a string match + folder list).

## Tests (TDD coverage required)

`tests/commands/test_repo_resolver.py`:

1. `test_resolve_repo_arg_global_sentinel` — token `global`, `_`, `-` → state `global` when `allow_global=True`
2. `test_resolve_repo_arg_global_rejected_when_not_allowed` — token `global` with `allow_global=False` → state `unknown`
3. `test_resolve_repo_arg_absolute_path_single_match` — `/Users/x/repo` matches one hub → state `project`
4. `test_resolve_repo_arg_absolute_path_no_match` — `/nowhere` → state `unknown`
5. `test_resolve_repo_arg_absolute_path_multiple_match` — 2 hubs binding same path → state `ambiguous`
6. `test_resolve_repo_arg_exact_project_name` — `langlive-line-oa` matches folder → state `project`
7. `test_resolve_repo_arg_fuzzy_project_name` — `langlive` substring-matches one → state `ambiguous` with candidate
8. `test_resolve_repo_arg_unknown_project_name` — `nonexistent-thing` → state `unknown`, candidates = all projects

Acceptance smoke (manual or scripted):

9. Run new `/obsidian-research langlive-line-oa LINE 限流策略` end-to-end → verify saves to `Projects/langlive-line-oa/Research/...`
10. Run `/obsidian-research global agent memory` → saves to vault-wide `Research/Web/...`
11. Run old `/research LINE 限流策略 --project=langlive-line-oa` → still works + prints deprecation warning

## Out-of-scope / deferred

- Discord adapter implementation — `param-autocomplete` frontmatter ships, adapter consumes later
- Other `obsidian-*` commands (`/obsidian-project`, `/obsidian-decide`, etc.) — different argument shapes, not affected
- Rename of `local-path` frontmatter key — stays as `local-path` (changing it breaks all existing project hubs)
- New trigger-phrase additions to old research commands — keep current triggers on stubs

## Open questions resolved

- **Q:** Why `<repo>` not `<project>` if research doesn't read code?
  A: User wants Discord UX consistency across all 5 commands. `<repo>` is the architect-established label. The actual semantic = "the project hub whose local-path binds to this codebase". For `global`, there's no repo — sentinel.
- **Q:** What about brainstorm/roadmap users who currently type `<project-name>`?
  A: No behavior change — those names still match. Only the doc/hint changes. No deprecation warning needed.
- **Q:** Hard cut or soft deprecation for `/research` / `/research-deep`?
  A: Soft for one minor release with warning, then hard. Migration friction acceptable.

## Success criteria

- [x] Brainstorm + design approved
- [ ] Spec self-review pass
- [ ] User reviews this spec
- [ ] Implementation plan written via `writing-plans` skill
- [ ] Implementation lands; all 5 commands route through `resolve_repo_arg`; old `/research` still callable for 1 release with warning; tests pass; 4 adapter builds OK
