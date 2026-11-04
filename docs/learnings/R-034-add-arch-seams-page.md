---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-034
tags: [learning, ai_system, draw-arch, architecture, seams, ports-and-adapters]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-034
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-034 replaced `/draw-arch`'s module matrix with a **seams** (可替換性) page. Each external
> system gets a verdict and every touchpoint as file and lines, each marked ✅ in an adapter or
> ❌ leaked into the core, plus a list of what to change to swap it. `seams.py` finds the
> touchpoints from probes Claude declares, and `check.py --repo` re-scans them, so the page
> acts as a fitness function.
>
> **Headline lesson:** answer the operator's architecture question, not a metric's. The R-033
> matrix was accurate and useless, because 「module 耦合性」 meant "can I add Discord next to
> LINE, can I swap Confluence". That is a ports-and-adapters and change-scenario question,
> and it is answered per external system.

## What Shipped
- **Removed:** `lib/modules.py`, the `matrix` page type, its checks, tests, docs and CONTEXT entry.
- **`lib/seams.py <repo> <spec>`**
  - Scans `git ls-files '*.py'`, minus test paths and `exclude` globs.
  - `import` probes read `ast` imports, absolute only, of the module or its submodules.
  - `text` probes run a line regex, counting `\n` only.
  - A file that won't parse still gets text probes; an unreadable file is skipped with a
    stderr note.
  - A touchpoint's `note` survives a re-run.
- **`check.py`:** the seams schema (verdict `easy`/`medium`/`hard`, probes required, text
  patterns compiled) and `check: seams: stale <id>`.
- **`render.py`**
  - A summary table (系統 / 能不能換 / 接觸檔 / 漏進核心 / 一句話), with verdict tone classes
    `v-easy`/`v-medium`/`v-hard`.
  - One section per system, leaks listed first.
  - The index order is overview, features, seams, jobs.
- **Tests:** 63 in `test_draw-arch.bats`. The diagram, table and cards golden files are unchanged.
- **The langlive-line-oa pack (vault):** `modules` is removed and `seams` covers five systems.

  | System | Verdict | Files | Leaks | Leaks include |
  |---|---|---|---|---|
  | LINE | 要改一些 | 13 | 7 | the LangGraph router node calls LINE's loading API; chat/workspace call the profile API |
  | Confluence | 要改一些 | 6 | 2 | |
  | LLM | 要改一些 | 8 | 6 | `OpenAIEmbeddings` built in 4 places |
  | Weaviate | 很難換 | 10 | 6 | query syntax in the domain layer |
  | Data warehouse | 容易換 | 2 | 0 | |

## Key Decisions
- **The question behind the request:** 「我一開始以為的 module 比較像是 LINE 跟 Langraph 有沒有解耦…
  Confluence 有沒有解耦」. The industry answers it with ports & adapters, ATAM change scenarios
  and fitness functions. The two linked architect-reviewer skills (SOLID/DDD/Clean
  Architecture checklists) informed the leak and verdict framing (operator + my research).
- **Delete the matrix page,** 「矩陣頁 刪掉」 (operator).
- **Cover every external system:** LINE, Confluence, LLM, Weaviate and the data warehouse
  (operator).
- **Touchpoints come from a script.** Claude declares probes and adapters, `seams.py` finds
  the hits, and `check.py --repo` re-verifies them (my call).
- **Two probe kinds,** `ast` import and line regex, with no call graph (my call).
- **Group touchpoints by file** (my call).
- **Scan Python only,** skipping test paths (my call).
- **Use a three-word verdict, not a score** (my call).
- **The R-033 id rule stays as a judgment rule,** because its check went with `modules.py`
  (my call).
- **Door: two-way.**

## What Changed From Plan
- **Codex ran Tasks 1–3 in one round, DONE_WITH_CONCERNS:**
  - it kept the three dead `.heat`/`.mods` CSS rules in the frozen table/cards CSS, for byte
    parity, and stripped them from seams;
  - the checker suppresses the scanner's parse warnings;
  - it catches `OverflowError` from an `a{4294967296}` pattern.
- **Task 4 (Claude) added two renderer fixes after the screenshot,** verdict tone classes and
  no wrapping for the count columns, plus one data fix (the LINE summary said 6 leaks; the
  scan showed 7). `backend/app/integrations/line_*.py` joined the LINE adapters once the scan
  showed `integrations/line_client.py` exists.
- **Review attempt 1 had 2 blockers,** both reproduced and fixed in 8f957c9. Attempt 2 was clean.

## Bugs
- **`str.splitlines()` also splits on `\f`, `\v`, U+2028 and friends,** so text-probe line
  numbers drifted past such a character.
- **`ast.parse` raises `ValueError`, not `SyntaxError`, on a NUL byte in Python 3.9,** and the
  uncaught error aborted the whole scan.
- **A non-UTF-8 tracked file aborted the scan.** It is now skipped and named.

## Lessons → checks
- Count source lines by splitting on "\n" only, and treat every parse or decode failure of one file as that file's problem, not the scan's — enforced by `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats -f 'newlines only'` · proof: red at 43805fc (exit 1) · green at 5339565
- Before building an analysis page, restate the operator's question as a change scenario ("what would it take to add/replace X?") and check that the page answers it — judgment

## Reusable Patterns
- **Probes plus adapter globs give a cheap ports-and-adapters audit.** Claude names where an
  external system should live, a scanner lists where it actually lives, and the difference is
  the leak list. Re-running the scan in the checker turns the page into a fitness function.
- **Group touchpoints per file, with line lists.** That keeps a whole repo's leak picture on
  one readable page.

## Technical Debt
- Nits not taken:
  - an import probe misses `from <parent> import <submodule>` (`from google import genai`);
    line-oa has no such import today;
  - the scan reads the working tree but stamps HEAD;
  - import-probe patterns are not validated, and regexes prone to catastrophic backtracking
    are not detected;
  - `fnmatch` normalises case on some platforms;
  - `split` runs once per probe;
  - the regression test bundles three fixes;
  - no test covers an adapter or `exclude` change making the scan stale.
- The LINE note "客戶、工單是否以 LINE user id 當主鍵" is still unverified.

## Future Follow-ups
- **In line-oa:**
  - move the router node's loading indicator out of the graph;
  - route profile calls through `integrations/line_client.py`;
  - add an embedding factory;
  - add a vector-store interface before any Weaviate swap;
  - extract a channel interface from `line_service.py` before adding Discord.
- **Optional:** add Elasticsearch, S3 and Mem0 as further seams systems.
