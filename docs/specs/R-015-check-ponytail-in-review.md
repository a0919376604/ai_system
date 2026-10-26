---
date: 2026-10-26
updated: 2026-10-26
type: spec
id: R-015
status: draft
tags: [ship-next, ponytail, review, dependencies]
ai-first: true
---

## For future Claude
> Since R-014 codex reads the ponytail ladder; nothing checked whether it followed it.
> R-015 adds two checks to Phase 6: the reviewer tags over-engineering with ponytail-review's
> five tags (counted, logged, never blocking by themselves), and a mechanical gate blocks a new
> dependency unless the spec's Decisions justify it with a `New dependency: <name>` line.

## Decisions
- leric, 2026-10-26: 「好」to layers 1 + 2 (per-ship diff review + dependency gate); layer 3 (`/ponytail-audit`, `/ponytail-debt`) stays manual.
- Tags reuse ponytail-review's vocabulary verbatim: `delete`, `stdlib`, `native`, `yagni`, `shrink` — written `[ponytail:<tag>]` (my call: one reviewer pass, no extra agent).
- Ponytail findings are nit or important, never blocking on their own (my call: start by measuring).
- Dependency detection (my call, revised in three review rounds): parse each manifest's real dependency sections at merge-base and head and take the set difference — package.json `dependencies`/`devDependencies`/`peerDependencies`/`optionalDependencies` (jq; without jq it warns and skips), requirements*.txt lines, pyproject `[project] dependencies`, `[project.optional-dependencies]`, `[dependency-groups]` (minus `{include-group}` tables), poetry tables. CRLF stripped; Python names and the `New dependency:` marker both compared per PEP 503. The marker is explicit and one line may list several names (`New dependency: react, react-dom — new LIFF app`). Checked on line-oa history: croniter, brotli, psutil, msw, aiomysql flagged; the langchain-google-genai bump not.
- Inline TDD despite two small functions (my call: scope fully specified here).

## Seams
| Seam | Interface | Guaranteed behavior |
|---|---|---|
| `sn_new_deps` | `sn_new_deps <base> <head>` (cwd: repo) | One `<file>\t<name>` line per dependency added between base...head in package.json / requirements*.txt / pyproject.toml; nothing for version bumps, scripts, comments, lockfiles. |
| `sn_mech_gates` | existing | Also: each new dependency without a `New dependency: <name>` line in `docs/specs/<ID>-<SLUG>.md` adds one mechanical blocker with a message naming it; review-extra-checks lists the five `[ponytail:<tag>]` tags. |
| `code-review-parse.sh` | existing | Also prints `PONYTAIL_COUNT=<n>` (lines carrying a `[ponytail:<tag>]` tag). |
| Phase 9 | log row, summary | Include the ponytail finding count. |

## §4 Acceptance
| ID | Given | When | Then |
|---|---|---|---|
| AC-1 | package.json adds `"left-pad": "^1.3.0"` and bumps `"version"` | `sn_new_deps` | prints only `package.json\tleft-pad` |
| AC-2 | requirements.txt adds `requests==2.31` and a comment | `sn_new_deps` | prints only `requests` |
| AC-3 | AC-1 with no marker / with `- New dependency: left-pad — …` in the spec | `sn_mech_gates` | MECH_BLOCKERS=1 and a message / 0 |
| AC-4 | a review with two `[ponytail:yagni]` lines | parse | `PONYTAIL_COUNT=2` |
