# Free Research Toolkit — Design Spec

**Date:** 2026-05-25
**Status:** Draft — awaiting user sign-off, then writing-plans
**Branch:** TBD (suggest `feat/free-research-toolkit`)
**Replaces:** Existing `/research`, `/research-deep`, `/x-pulse`, `/x-read`, `/notebooklm`, `/youtube` (all depend on paid APIs: Perplexity, xAI Grok, Gemini, YouTube Data API)
**Inspired by:** [wanshuiyin/Auto-claude-code-research-in-sleep](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) (ARIS) — specifically their `/research-lit`, `/idea-discovery` patterns and their free-source list (arXiv, Semantic Scholar, OpenAlex, CrossRef).

---

## 1. Motivation

The current `obsidian-second-brain` research toolkit (`scripts/research/*.py`) requires three paid API keys:

| Command | Paid dependency | Free tier exists? |
|---|---|---|
| `/research` | Perplexity Sonar | No (paywall after demo) |
| `/research-deep` | Perplexity Sonar + xAI Grok Live Search | No / No |
| `/x-pulse`, `/x-read` | xAI Grok Live Search | No |
| `/notebooklm` | Google Gemini | Yes (1500/day) but still requires a key |
| `/youtube` | YouTube Data API + xAI Grok | Yes (10K/day) / No |

The user wants **zero paid APIs and zero required API keys** — the toolkit must work out of the box on a fresh install with `uv pip install` and nothing else.

The synthesis step (turning raw search results into a structured AI-first dossier) currently happens inside the paid API ("Perplexity writes the dossier and returns it"). When we strip the paid APIs, that step has to move somewhere. The user picked: **the calling Claude session synthesizes**. This keeps everything inside the existing subscription, costs zero per-call dollars, and removes any external-LLM dependency.

The user also wants to extend the toolkit with ARIS-style academic-paper-aware research and an idea-gap-finder. These are net-new capabilities the current toolkit does not have.

---

## 2. Goals

1. **Zero paid APIs**, **zero required API keys**. A fresh install with `uv pip install -e .` works for every research command. Optional `contact_email` for polite-pool HTTP headers; that's it.
2. **Synthesis quality stays competitive** with Perplexity Sonar via Claude doing the synthesis on raw search results from 6–8 free sources in parallel.
3. **Covers both general web discourse (HN, Reddit, blogs) and academic literature (arXiv, Semantic Scholar, OpenAlex, CrossRef)** in a single `/research` command via a flag, not separate commands the user has to choose between.
4. **All AI-first vault rules preserved** — every produced note has frontmatter, `## For future Claude` preamble, recency markers, source URLs, mandatory wikilinks.
5. **Graceful degradation** — when N of 8 sources are down/rate-limited, the remaining sources still produce a usable dossier. A research run never fails entirely unless every source fails simultaneously.
6. **Backward compatible escape hatch** — the deprecated `lib/perplexity.py`, `lib/grok.py`, `lib/gemini.py` modules stay on disk (marked deprecated) so a user who wants to re-add a paid key can still use them via a fork or future flag.

---

## 3. Non-Goals

- **No X.com access.** The `/x-pulse` and `/x-read` commands rename to `/discourse-pulse` and `/thread-read`. They explicitly do not attempt X — Nitter mirrors are too unreliable and twscrape requires user accounts. We accept the loss of X as a data source.
- **No local LLM as a default.** Local Ollama remains a possibility for users who want offline, but it is not part of this design. Synthesis is by the calling Claude session.
- **No Google Scholar.** No official API, scraping is discouraged. arXiv + Semantic Scholar + OpenAlex cover ≥ 95% of what Scholar surfaces.
- **No new vault schema changes.** All output notes use the same AI-first frontmatter shapes documented in `references/ai-first-rules.md` today.

---

## 4. Architecture

### 4.1 Data flow

```
Discord / Claude Code CLI
  │
  │  /research <topic> [--academic]
  ▼
~/.claude/commands/research.md  (instructions for Claude)
  │
  │  Claude reads instructions, then runs:
  ▼
scripts/research/research.py <topic> [--academic]
  │
  │  Spawn N parallel source clients via ThreadPoolExecutor.
  │  N depends on command (6 for /research default, 4 for --academic,
  │  4 for /discourse-pulse, etc. — see §5). All clients live under
  │  lib/sources/ and share the SourceClient interface.
  │
  │  Aggregate results into JSON; print to stdout.
  ▼
{
  "topic": "...",
  "academic_mode": false,
  "results": {
    "web":       [{url, title, snippet, source: "duckduckgo"}],
    "encyclopedia": [{url, title, extract, source: "wikipedia"}],
    "discourse": [{url, title, points, comments, source: "hackernews|reddit"}],
    "academic":  [{doi, title, abstract, authors, year, source: "arxiv|s2|openalex"}]
  },
  "stats": {"sources_attempted": 8, "sources_succeeded": 6, "results_total": 47},
  "warnings": ["reddit: rate-limited", "duckduckgo: captcha"]
}
  │
  ▼
Claude (this session) reads JSON, synthesizes AI-first dossier
  │
  │  - Cross-reference vault (Read tool / mcp__obsidian-vault)
  │  - Apply AI-first rule (preamble, frontmatter, wikilinks, recency markers)
  │  - Cite every claim with inline source URL from the JSON
  ▼
Research/Web/YYYY-MM-DD-<slug>.md  (or Research/Deep/, Research/Pulse/, etc.)
```

### 4.2 Source-client interface

Every source client implements one method:

```python
class SourceClient(Protocol):
    name: str

    def search(self, query: str, n: int = 10) -> list[Result]: ...
```

`Result` is a typed dataclass with a small superset of fields; each source fills the ones it has. Missing fields are `None`.

```python
@dataclass(frozen=True)
class Result:
    source: str       # client name, e.g. "arxiv"
    title: str
    url: str
    snippet: str | None = None        # for web results
    abstract: str | None = None       # for academic
    authors: list[str] | None = None  # for academic
    year: int | None = None           # for academic
    points: int | None = None         # HN score
    comments: int | None = None       # HN/Reddit comment count
    posted_at: str | None = None      # ISO date if available
```

### 4.3 Module layout

```
scripts/research/
├── lib/
│   ├── __init__.py
│   ├── http.py              ← shared httpx client with polite User-Agent, retries, cache
│   ├── cache.py             ← ~/.cache/obsidian-second-brain/research/ JSON cache (TTL 24h)
│   ├── config.py            ← reads ~/.config/obsidian-second-brain/research.toml
│   ├── result.py            ← Result dataclass + JSON encoder
│   ├── aggregator.py        ← ThreadPoolExecutor that runs N sources in parallel
│   └── sources/
│       ├── __init__.py
│       ├── duckduckgo.py
│       ├── wikipedia.py
│       ├── hackernews.py    ← Algolia HN search
│       ├── reddit.py
│       ├── lobsters.py
│       ├── devto.py
│       ├── arxiv.py
│       ├── semantic_scholar.py
│       ├── openalex.py
│       └── crossref.py
│
├── research.py              ← /research entry — calls aggregator with web + academic groups
├── research_deep.py         ← /research-deep entry — vault scan delegated to Claude; this script
│                              just does Phase 3 gap-fill (same as research.py but per-query batch)
├── idea_discovery.py        ← /idea-discovery entry — quick arxiv+hn scan per gap
├── discourse_pulse.py       ← /discourse-pulse entry — HN+Reddit+Lobsters+devto only
├── thread_read.py           ← /thread-read entry — single URL fetch
├── youtube_extract.py       ← /youtube entry — youtube-transcript-api + scrape metadata
│
└── _deprecated/             ← old modules: perplexity.py, grok.py, gemini.py (escape hatch)
    ├── perplexity.py        ← header: DEPRECATION: replaced by lib/sources/*.py in v1.0
    ├── grok.py              ← same
    └── gemini.py            ← same
```

### 4.4 Command (`.md`) updates

Each of the 7 commands gets a corresponding `~/.claude/commands/<name>.md` rewrite that:

1. Tells Claude to invoke the Python fetcher (with the topic from `$ARGUMENTS`).
2. Tells Claude to read the JSON stdout.
3. Tells Claude how to synthesize a dossier following the AI-first schema for that command's note type.
4. Tells Claude where to save (`Research/Web/`, `Research/Deep/`, etc.).
5. Tells Claude to append to `Logs/YYYY-MM-DD.md` and update `index.md`.

The old `description`, `category`, `triggers_en` frontmatter stays compatible with the `claudecode-discord` plugin bridge so the same files surface as Discord slash commands.

---

## 5. Per-Command Specs

### 5.1 `/research <topic> [--academic]`

| Aspect | Spec |
|---|---|
| **Input** | Required topic string. Optional `--academic` flag. |
| **Sources (default)** | `duckduckgo`, `wikipedia`, `hackernews`, `reddit`, `arxiv`, `semantic_scholar` (6 parallel) |
| **Sources (`--academic`)** | `arxiv`, `semantic_scholar`, `openalex`, `crossref` (4 parallel) |
| **Output note** | `Research/Web/YYYY-MM-DD-<slug>.md` (or `Research/Academic/` with flag) |
| **Sections** | Summary · Key Facts (recency markers) · Timeline · Key Players · Contrarian Views · Open Questions · Sources |
| **Frontmatter** | `type: research`, `tags: [research, ...]`, `model: claude-via-self`, `sources: [...]`, `ai-first: true` |

### 5.2 `/research-deep <topic>`

| Aspect | Spec |
|---|---|
| **Input** | Required topic string. |
| **Phase 1 — vault scan** | Claude greps `Research/`, `Projects/`, `Knowledge/` for baseline. |
| **Phase 2 — gap analysis** | Claude generates 3–5 targeted sub-queries from vault baseline (no external LLM call). |
| **Phase 3 — gap fill** | For each sub-query, call `research.py` fetcher (sequential, ~3s × 5 = 15s). |
| **Phase 4 — synthesis + propagate** | Claude writes delta report to `Research/Deep/YYYY-MM-DD-<slug>.md`. Then dispatches sub-agents to update `People/`, `Projects/`, `Ideas/` per the synthesis's "Recommended Vault Updates" section (same propagation behavior as today). |

### 5.3 `/idea-discovery [seed]`

| Aspect | Spec |
|---|---|
| **Input** | Optional seed topic. |
| **Step 1** | Claude reads `Ideas/*.md` where `status != graduated`, and the **Open Questions** sections of `Projects/*.md`. |
| **Step 2** | Claude finds Research/ notes with no matching Project — orphan research. |
| **Step 3** | Calls `idea_discovery.py` fetcher → quick `arxiv` + `hackernews` scan per gap (`n=5` each). |
| **Step 4** | Writes `Ideas/YYYY-MM-DD-discovery.md` with 3–5 ranked next directions, each with rationale and source citations. |
| **Does NOT** | Auto-graduate. User must explicitly `/obsidian-graduate <idea>` to promote. |

### 5.4 `/discourse-pulse <topic>` (renamed from `/x-pulse`)

| Aspect | Spec |
|---|---|
| **Input** | Required topic string. |
| **Sources** | `hackernews`, `reddit` (search across r/MachineLearning, r/programming, r/LocalLLaMA, etc.), `lobsters`, `devto` |
| **Output note** | `Research/Pulse/YYYY-MM-DD-<slug>.md` |
| **Sections** | Hot Threads · Key Voices · Counter-takes · Post Angle Ideas · Sources |
| **Tone** | "What builders are saying this week" — closer to news than academic. |

### 5.5 `/thread-read <url>` (renamed from `/x-read`)

| Aspect | Spec |
|---|---|
| **Input** | Single thread URL. Supported hosts: HN, Reddit, dev.to, Lobsters, generic blog. |
| **Step 1** | Detect host → select source client. |
| **Step 2** | Fetch OP + top N comments (`n=20` default, configurable). |
| **Output note** | `Research/Threads/YYYY-MM-DD-<slug>.md` with OP summary, top arguments grouped by stance, and verbatim quotes. |

### 5.6 `/youtube <url>`

| Aspect | Spec |
|---|---|
| **Input** | YouTube URL. |
| **Step 1** | Use `youtube-transcript-api` Python package (no API key) to fetch transcript. |
| **Step 2** | Scrape video page HTML for `<title>`, channel, published date, view count (no YouTube Data API). |
| **Step 3** | Claude summarizes transcript with section headers + key timestamps + topics covered. |
| **Output note** | `Research/YouTube/YYYY-MM-DD-<slug>.md` |
| **Fallback** | If no transcript exists (private video / no captions), Claude writes a stub note with metadata only and a `transcript-available: false` frontmatter flag. |

### 5.7 `/vault-deep-synthesis <topic>` (renamed from `/notebooklm`)

| Aspect | Spec |
|---|---|
| **Input** | Topic string. |
| **No Python fetcher** | Pure vault operation, no external network. |
| **Step 1** | Claude greps vault for all notes mentioning the topic (Research/, Knowledge/, Projects/, Ideas/, Logs/). |
| **Step 2** | Reads each matching note in full. |
| **Step 3** | Cross-references: which notes claim the same fact but differ? Which claims repeat? Which are isolated? |
| **Step 4** | Writes `Knowledge/YYYY-MM-DD-synthesis-<slug>.md` containing the unified view, contradiction list, and stale-claim flags. |
| **Does NOT** | Mutate existing notes. Synthesis is a derivative; existing notes stay as-is for provenance. |

---

## 6. Error Handling & Rate Limits

### 6.1 Per-source rate limits & failure mode

| Source | Rate limit | Required header | Failure modes | Strategy |
|---|---|---|---|---|
| arXiv API | 1 req / 3 s | `User-Agent: obsidian-second-brain/1.0 (mailto:<contact>)` | 5xx | 3 retries with exponential backoff |
| Semantic Scholar | 100 req / 5 min unauth | none | 429 frequent | Backoff to next call; if 429 twice in a row, skip source |
| OpenAlex | 100K req / day | UA with `mailto:` → polite pool | rare | Use polite pool |
| CrossRef | 50 req / s with polite pool | UA with `mailto:` | rare | Use polite pool |
| HN Algolia | none documented | none | rare 503 | 1 retry, then skip |
| Reddit JSON | 100 req / min unauth | unique `User-Agent` required | 429 / 403 | Use realistic UA, 0.5s sleep between calls |
| Wikipedia REST | 200 req / s | UA with contact | rare | Use directly |
| DuckDuckGo HTML | none doc'd, CAPTCHA possible | realistic browser UA + Accept-Language | CAPTCHA | Fall back to SearXNG |
| SearXNG public | ~5 req / s per instance | normal UA | instance down | 3 fallback instances; rotate |
| `youtube-transcript-api` | YouTube's own limits | package handles | transcript missing, private video | Return empty transcript; Claude notes "no transcript" in dossier |

### 6.2 Per-client contract

```python
class SourceClient:
    name: str

    def search(self, query: str, n: int = 10) -> list[Result]:
        """Search. Never raises. Failures return [] and log to stderr."""
        try:
            return self._search_impl(query, n)
        except RateLimitError as e:
            log_stderr(f"[{self.name}] rate-limited: {e}")
            return []
        except (httpx.TimeoutException, httpx.ConnectError) as e:
            log_stderr(f"[{self.name}] network: {e}")
            return []
        except Exception as e:
            log_stderr(f"[{self.name}] UNEXPECTED: {e}")
            return []
```

### 6.3 Aggregator contract

- Spawn N source clients in parallel via `concurrent.futures.ThreadPoolExecutor(max_workers=N)`.
- Wait for all with a 30s overall timeout. Sources that don't return in time are recorded as `timeout` warnings.
- **Success rule**: if `≥ 3` sources returned `> 0` results, the aggregate run is a success. Otherwise it's `partial` (still print results, but include a `success: false` flag so Claude can warn the user).
- Total elapsed time is approximately the slowest source's latency, typically 3–5 s.

### 6.4 Cache

- Cache key: `<source>-<sha1(normalized_query)>.json`
- Cache dir: `~/.cache/obsidian-second-brain/research/`
- Default TTL: 24 h. Configurable per source via `research.toml`.
- Indexing layer reads cache; on hit, skip the network call entirely.
- CLI flag `--no-cache` skips reads (writes still happen). CLI flag `--clear-cache` wipes the directory.

### 6.5 Configuration

`~/.config/obsidian-second-brain/research.toml` (optional file — sensible defaults if missing):

```toml
# Used in HTTP User-Agent for polite pools (arXiv, OpenAlex, CrossRef).
# No secret; safe to commit if you publish your dotfiles.
contact_email = "you@example.com"

[searxng]
instances = [
  "https://searx.be",
  "https://search.brave4u.com",
  "https://priv.au",
]

[rate_limits]
arxiv_seconds = 3.0
reddit_seconds = 0.5
semantic_scholar_seconds = 3.0   # 100 req / 5 min ≈ 1 / 3 s

[cache]
ttl_hours = 24
```

No API keys. No secrets.

---

## 7. Testing

| Layer | Scope | How to run |
|---|---|---|
| **Unit** | Each `SourceClient` parser, mocked HTTP responses via `responses` package. Tests the JSON-to-Result conversion. | `pytest tests/sources/` |
| **Contract** | One real query per source against the live API, asserting shape stability (not content). Tagged `@pytest.mark.live`. | `pytest -m live tests/contract/` — manual, not in CI |
| **Smoke** | `python -m scripts.research.research "claude api caching"` → stdout is valid JSON, ≥ 3 sources returned results. | `tests/smoke.sh` |
| **Integration** | In a real vault, run `/research`, assert: note created, frontmatter validates, ≥ 1 recency marker present, ≥ 1 wikilink present. | Manual or `python tests/integration/test_vault_write.py` |

---

## 8. Deprecation & Migration

1. `scripts/research/lib/perplexity.py`, `lib/grok.py`, `lib/gemini.py` move under `scripts/research/_deprecated/`, header annotated:
   ```python
   """
   DEPRECATED in v1.0 — replaced by scripts/research/lib/sources/*.py.
   Kept on disk as an escape hatch for users who want to bring back
   paid-API behavior. Not imported by any current command.
   """
   ```
2. `.env.example` rewritten — every key listed as **optional**, with a note that the default install needs zero keys.
3. `README.md` + `SKILL.md` — update the research-toolkit section's "What you need" from "Perplexity API key + xAI key" to "nothing (optional: a contact email for polite-pool HTTP headers)".
4. `references/ai-first-rules.md` — unchanged. The vault contract did not change.
5. CHANGELOG entry under "Unreleased":
   ```markdown
   ### Changed
   - Research toolkit no longer requires paid APIs (Perplexity, xAI, Gemini, YouTube Data).
     All 7 research commands now run on free sources (arXiv, Semantic Scholar, OpenAlex,
     CrossRef, DuckDuckGo, Wikipedia, HackerNews, Reddit, Lobsters, dev.to) with
     synthesis by the calling Claude session.
   ### Renamed
   - `/x-pulse` → `/discourse-pulse` (HN/Reddit/Lobsters/dev.to; X.com is no longer queried)
   - `/x-read` → `/thread-read` (HN/Reddit/blog threads)
   - `/notebooklm` → `/vault-deep-synthesis` (Claude reads vault directly; no external LLM)
   ### Added
   - `/idea-discovery` — surface 3-5 ranked next-direction candidates by scanning
     Ideas/, Projects/ Open Questions, and orphan Research/ notes.
   - `--academic` flag on `/research` — restricts to arXiv + Semantic Scholar + OpenAlex + CrossRef.
   ### Deprecated
   - `scripts/research/lib/{perplexity,grok,gemini}.py` moved to `_deprecated/`.
     Will be removed in v2.0 unless a maintained "bring-your-own-key" path is added.
   ```

---

## 9. Open Questions

1. **Reddit subreddit list** — `/discourse-pulse` needs to know which subs to query. Default to a curated list (`r/MachineLearning`, `r/programming`, `r/LocalLLaMA`, `r/LangChain`, `r/ClaudeAI`, etc.)? Or accept a `--subreddits` flag? **Recommendation**: ship a default list editable via `research.toml`, plus a `--subreddits` override.
2. **`/idea-discovery` ranking heuristic** — what makes one gap rank higher than another? Recency of last touch? Number of orphan research notes pointing at it? Project status (active vs planning)? **Recommendation**: simple "recency × orphan_count" score for v1; revisit after first 10 uses.
3. **DuckDuckGo CAPTCHA frequency** — if it CAPTCHAs every 5th query, SearXNG public instances become the primary general-web source. Need a few weeks of real use to know. **Recommendation**: ship DuckDuckGo as primary, SearXNG as fallback in v1; flip the default if CAPTCHA rate observed > 20%.
4. **Concurrent client cap** — 8 parallel HTTP calls per `/research` is fine on Wi-Fi but might rate-limit on weak connections. **Recommendation**: 8 default, configurable via `research.toml`.

---

## 10. Inspiration & Sources

- ARIS repo (research-lit, idea-discovery patterns, multi-source aggregation, polite-pool emails): https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep (as of 2026-05)
- arXiv API docs: https://info.arxiv.org/help/api/index.html (as of 2026-05)
- Semantic Scholar API: https://api.semanticscholar.org/api-docs/ (as of 2026-05)
- OpenAlex polite pool: https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication#the-polite-pool (as of 2026-05)
- CrossRef etiquette: https://www.crossref.org/documentation/retrieve-metadata/rest-api/tips-for-using-the-crossref-rest-api/ (as of 2026-05)
- `youtube-transcript-api`: https://pypi.org/project/youtube-transcript-api/ (as of 2026-05)
- HN Algolia search: https://hn.algolia.com/api (as of 2026-05)
- Reddit JSON: https://www.reddit.com/dev/api (as of 2026-05)
- SearXNG instances list: https://searx.space/ (as of 2026-05)
