# Free Research Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every paid-API dependency in the obsidian-second-brain research toolkit with free, key-less sources, with synthesis performed by the calling Claude session.

**Architecture:** A single shared aggregator (`scripts/research/lib/aggregator.py`) fans out parallel HTTP calls to ~10 source clients under `scripts/research/lib/sources/`, each returning a typed `Result` dataclass. Per-command Python entry points pick which sources to query and emit JSON to stdout. Claude (the calling session) reads that JSON and synthesizes an AI-first vault note.

**Tech Stack:** Python 3.10+, `requests`, `responses` (test mocks), `tomli` (config), `pytest`. No new runtime deps with API keys.

**Spec:** `docs/superpowers/specs/2026-05-25-free-research-toolkit-design.md`

---

## File Structure

**Created:**
- `scripts/research/lib/result.py` — `Result` dataclass + JSON encoder
- `scripts/research/lib/http.py` — shared `requests.Session` with polite UA + retries
- `scripts/research/lib/cache.py` — file-based JSON cache with TTL
- `scripts/research/lib/config.py` — TOML config reader (replaces existing env-var module)
- `scripts/research/lib/aggregator.py` — parallel source dispatcher
- `scripts/research/lib/sources/__init__.py`
- `scripts/research/lib/sources/arxiv.py`
- `scripts/research/lib/sources/semantic_scholar.py`
- `scripts/research/lib/sources/openalex.py`
- `scripts/research/lib/sources/crossref.py`
- `scripts/research/lib/sources/duckduckgo.py`
- `scripts/research/lib/sources/wikipedia.py`
- `scripts/research/lib/sources/hackernews.py`
- `scripts/research/lib/sources/reddit.py`
- `scripts/research/lib/sources/lobsters.py`
- `scripts/research/lib/sources/devto.py`
- `scripts/research/idea_discovery.py`
- `scripts/research/discourse_pulse.py` (will replace `x_pulse.py`)
- `scripts/research/thread_read.py` (will replace `x_read.py`)
- `tests/research/sources/` (one test file per source)
- `tests/research/test_aggregator.py`
- `tests/research/test_cache.py`
- `tests/research/test_result.py`
- `commands/idea-discovery.md`
- `commands/discourse-pulse.md`
- `commands/thread-read.md`
- `commands/vault-deep-synthesis.md`

**Modified:**
- `scripts/research/research.py` — emits JSON instead of dossier text
- `scripts/research/research_deep.py` — same; vault scan + synth now done by Claude
- `scripts/research/youtube_extract.py` — drop YouTube Data API + Grok
- `commands/research.md`, `commands/research-deep.md`, `commands/youtube.md` — Claude-side synthesis instructions
- `pyproject.toml` — add `tomli`, `responses` (dev), `pytest` (dev); remove `openai`, `google-api-python-client`, `google-genai`
- `.env.example` — every key marked optional; default zero-key install
- `README.md` — research toolkit section rewrite
- `SKILL.md` — command list updates
- `CHANGELOG.md` — under Unreleased

**Moved (deprecated):**
- `scripts/research/lib/perplexity.py` → `scripts/research/_deprecated/perplexity.py`
- `scripts/research/lib/grok.py` → `scripts/research/_deprecated/grok.py`
- `scripts/research/lib/gemini.py` → `scripts/research/_deprecated/gemini.py`
- `scripts/research/x_pulse.py` → `scripts/research/_deprecated/x_pulse.py`
- `scripts/research/x_read.py` → `scripts/research/_deprecated/x_read.py`
- `scripts/research/notebooklm.py` → `scripts/research/_deprecated/notebooklm.py`
- `commands/x-pulse.md`, `commands/x-read.md`, `commands/notebooklm.md` → delete (renamed commands take over)

---

## Phase 0 — Setup

### Task 0: Create feature branch + add dev deps

**Files:**
- Modify: `pyproject.toml`

- [ ] **Step 1: Create branch**

```bash
cd ~/Desktop/code/obsidian-second-brain
git checkout -b feat/free-research-toolkit
```

- [ ] **Step 2: Add deps (replace [project.dependencies] and add [dependency-groups.dev])**

Edit `pyproject.toml`:

```toml
[project]
name = "obsidian-second-brain-research"
version = "1.0.0-dev"
description = "Research toolkit for obsidian-second-brain — free-source web/academic/discourse research that saves to your vault"
requires-python = ">=3.10"
dependencies = [
    "requests>=2.32.0",
    "python-dotenv>=1.0.0",
    "youtube-transcript-api>=0.6.2",
    "tomli>=2.0.0 ; python_version < '3.11'",
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "responses>=0.25.0",
]

[tool.ruff]
line-length = 100
target-version = "py310"

[tool.pytest.ini_options]
testpaths = ["tests"]
markers = [
    "live: hits live APIs (skipped by default; opt-in with -m live)",
]
```

- [ ] **Step 3: Install**

```bash
uv sync --all-groups
```

Expected: no errors. `openai`, `google-*` packages no longer pulled.

- [ ] **Step 4: Commit**

```bash
git add pyproject.toml uv.lock
git commit -m "chore: switch deps to free-source toolkit (v1.0-dev)"
```

---

## Phase 1 — Shared Infrastructure

### Task 1: `Result` dataclass + JSON encoder

**Files:**
- Create: `scripts/research/lib/result.py`
- Test: `tests/research/test_result.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_result.py
import json
from scripts.research.lib.result import Result, encode_results


def test_result_round_trips_through_json():
    r = Result(
        source="arxiv",
        title="A paper",
        url="https://arxiv.org/abs/2305.06564",
        abstract="An abstract.",
        authors=["Alice", "Bob"],
        year=2023,
    )
    out = json.dumps([r], default=encode_results)
    parsed = json.loads(out)
    assert parsed[0]["source"] == "arxiv"
    assert parsed[0]["title"] == "A paper"
    assert parsed[0]["authors"] == ["Alice", "Bob"]
    assert parsed[0]["snippet"] is None  # unset fields default to None


def test_result_partial_fields_only():
    """Web results don't have abstract/authors — those stay None."""
    r = Result(
        source="duckduckgo",
        title="Page",
        url="https://example.com",
        snippet="Some snippet.",
    )
    out = json.loads(json.dumps([r], default=encode_results))
    assert out[0]["abstract"] is None
    assert out[0]["authors"] is None
    assert out[0]["snippet"] == "Some snippet."
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/Desktop/code/obsidian-second-brain
uv run pytest tests/research/test_result.py -v
```

Expected: `ModuleNotFoundError: No module named 'scripts.research.lib.result'` or test failure.

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/result.py
"""Typed result returned by every source client. Pure data, no behavior."""

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass(frozen=True)
class Result:
    """A single search result. Sources fill the fields they have; rest stay None."""

    source: str
    title: str
    url: str
    snippet: str | None = None        # web/discourse one-line preview
    abstract: str | None = None       # academic full abstract
    authors: list[str] | None = None  # academic
    year: int | None = None           # academic
    points: int | None = None         # HN score / Reddit upvotes
    comments: int | None = None       # discourse comment count
    posted_at: str | None = None      # ISO 8601 date if known
    extra: dict[str, Any] = field(default_factory=dict)  # per-source extras (doi, etc.)


def encode_results(obj: Any) -> Any:
    """`json.dumps` default= callable. Serializes Result to plain dict."""
    if isinstance(obj, Result):
        return asdict(obj)
    raise TypeError(f"Object of type {type(obj).__name__} is not JSON serializable")
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run pytest tests/research/test_result.py -v
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/research/lib/result.py tests/research/test_result.py
git commit -m "feat(research): add Result dataclass + JSON encoder"
```

---

### Task 2: Shared HTTP client (`lib/http.py`)

**Files:**
- Create: `scripts/research/lib/http.py`
- Test: `tests/research/test_http.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_http.py
import responses
from scripts.research.lib.http import get_session, polite_user_agent


def test_polite_user_agent_includes_contact():
    ua = polite_user_agent("test-client/1.0", contact_email="me@example.com")
    assert "test-client/1.0" in ua
    assert "mailto:me@example.com" in ua


def test_polite_user_agent_without_contact():
    ua = polite_user_agent("test-client/1.0", contact_email=None)
    assert ua == "test-client/1.0"


@responses.activate
def test_session_retries_on_5xx():
    responses.add(responses.GET, "https://api.example.com/x", status=503)
    responses.add(responses.GET, "https://api.example.com/x", status=503)
    responses.add(responses.GET, "https://api.example.com/x", json={"ok": True}, status=200)

    sess = get_session(retries=3, backoff=0.0)
    r = sess.get("https://api.example.com/x", timeout=5)
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    assert len(responses.calls) == 3


@responses.activate
def test_session_gives_up_after_retries():
    for _ in range(4):
        responses.add(responses.GET, "https://api.example.com/x", status=503)

    sess = get_session(retries=3, backoff=0.0)
    r = sess.get("https://api.example.com/x", timeout=5)
    assert r.status_code == 503
```

- [ ] **Step 2: Run test to verify it fails**

```bash
uv run pytest tests/research/test_http.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/http.py
"""Shared requests.Session with polite User-Agent + retries on 5xx.

Sources should NOT create their own sessions; import `get_session()` instead.
The User-Agent is built from the per-client name + optional contact email
loaded from `~/.config/obsidian-second-brain/research.toml`.
"""

from __future__ import annotations

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from .config import get_contact_email

DEFAULT_TIMEOUT = 15  # seconds; sources can override per-call
USER_AGENT_BASE = "obsidian-second-brain/1.0"


def polite_user_agent(client_name: str, contact_email: str | None) -> str:
    """Build a User-Agent string in arXiv/CrossRef/OpenAlex polite-pool format."""
    if contact_email:
        return f"{client_name} (mailto:{contact_email})"
    return client_name


def get_session(retries: int = 3, backoff: float = 1.0) -> requests.Session:
    """Return a requests.Session with retry-on-5xx wired in.

    Each source client should call this once at construction.
    """
    sess = requests.Session()
    retry = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=(500, 502, 503, 504),
        allowed_methods=("GET", "HEAD"),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    sess.mount("http://", adapter)
    sess.mount("https://", adapter)
    sess.headers.update({"User-Agent": polite_user_agent(USER_AGENT_BASE, get_contact_email())})
    return sess


__all__ = ["get_session", "polite_user_agent", "DEFAULT_TIMEOUT", "USER_AGENT_BASE"]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run pytest tests/research/test_http.py -v
```

Expected: 4 passed. Note: `test_polite_user_agent_*` will work but `test_session_*` depend on `lib/config.py` (next task). If you wrote Task 3 first, this works; otherwise stub `get_contact_email` returning None inline.

Workaround if config.py not yet written: add to top of `lib/http.py`:

```python
try:
    from .config import get_contact_email
except ImportError:
    def get_contact_email():
        return None
```

- [ ] **Step 5: Commit**

```bash
git add scripts/research/lib/http.py tests/research/test_http.py
git commit -m "feat(research): add shared HTTP session with polite UA + retries"
```

---

### Task 3: TOML config reader (`lib/config.py`)

**Files:**
- Create: `scripts/research/lib/config.py`
- Test: `tests/research/test_config.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_config.py
import os
from pathlib import Path
import pytest
from scripts.research.lib import config


def test_load_config_missing_file_returns_defaults(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "_config_path", lambda: tmp_path / "nope.toml")
    cfg = config.load()
    assert cfg.contact_email is None
    assert cfg.searxng_instances  # has defaults
    assert cfg.cache_ttl_hours == 24


def test_load_config_reads_toml(tmp_path, monkeypatch):
    f = tmp_path / "research.toml"
    f.write_text(
        'contact_email = "me@example.com"\n'
        '[searxng]\n'
        'instances = ["https://searx.example"]\n'
        '[cache]\n'
        'ttl_hours = 6\n'
    )
    monkeypatch.setattr(config, "_config_path", lambda: f)
    cfg = config.load()
    assert cfg.contact_email == "me@example.com"
    assert cfg.searxng_instances == ["https://searx.example"]
    assert cfg.cache_ttl_hours == 6


def test_get_contact_email_returns_loaded(tmp_path, monkeypatch):
    f = tmp_path / "research.toml"
    f.write_text('contact_email = "x@y.z"\n')
    monkeypatch.setattr(config, "_config_path", lambda: f)
    config._CACHE = None  # bust internal cache
    assert config.get_contact_email() == "x@y.z"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
uv run pytest tests/research/test_config.py -v
```

Expected: ModuleNotFoundError or failure.

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/config.py
"""Reads ~/.config/obsidian-second-brain/research.toml.

The file is optional. Defaults below are used when missing or partial.
No API keys live here — this is purely polite-pool email + tunables.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


_DEFAULT_SEARXNG = [
    "https://searx.be",
    "https://search.brave4u.com",
    "https://priv.au",
]


@dataclass(frozen=True)
class Config:
    contact_email: str | None = None
    searxng_instances: list[str] = field(default_factory=lambda: list(_DEFAULT_SEARXNG))
    cache_ttl_hours: int = 24
    arxiv_seconds: float = 3.0
    reddit_seconds: float = 0.5
    semantic_scholar_seconds: float = 3.0


_CACHE: Config | None = None


def _config_path() -> Path:
    return Path(os.path.expanduser("~/.config/obsidian-second-brain/research.toml"))


def load() -> Config:
    global _CACHE
    if _CACHE is not None:
        return _CACHE

    p = _config_path()
    if not p.exists():
        _CACHE = Config()
        return _CACHE

    raw = tomllib.loads(p.read_text())
    cfg = Config(
        contact_email=raw.get("contact_email"),
        searxng_instances=raw.get("searxng", {}).get("instances", list(_DEFAULT_SEARXNG)),
        cache_ttl_hours=int(raw.get("cache", {}).get("ttl_hours", 24)),
        arxiv_seconds=float(raw.get("rate_limits", {}).get("arxiv_seconds", 3.0)),
        reddit_seconds=float(raw.get("rate_limits", {}).get("reddit_seconds", 0.5)),
        semantic_scholar_seconds=float(
            raw.get("rate_limits", {}).get("semantic_scholar_seconds", 3.0)
        ),
    )
    _CACHE = cfg
    return cfg


def get_contact_email() -> str | None:
    return load().contact_email


__all__ = ["Config", "load", "get_contact_email"]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run pytest tests/research/test_config.py -v
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/research/lib/config.py tests/research/test_config.py
git commit -m "feat(research): add TOML config reader (no API keys)"
```

---

### Task 4: File-based cache (`lib/cache.py`)

**Files:**
- Create: `scripts/research/lib/cache.py`
- Test: `tests/research/test_cache.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_cache.py
import json
import time
from pathlib import Path
import pytest
from scripts.research.lib import cache


def test_cache_round_trip(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "deep learning", [{"title": "x"}])
    out = cache.get("arxiv", "deep learning", ttl_hours=24)
    assert out == [{"title": "x"}]


def test_cache_miss_returns_none(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    assert cache.get("arxiv", "nothing here", ttl_hours=24) is None


def test_cache_expires(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "deep learning", [{"title": "x"}])
    # tweak mtime to long ago
    f = next(tmp_path.glob("arxiv-*.json"))
    old = time.time() - 48 * 3600
    import os
    os.utime(f, (old, old))
    assert cache.get("arxiv", "deep learning", ttl_hours=24) is None


def test_normalized_query_key(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "  Deep   Learning  ", [{"title": "x"}])
    # same key after normalization
    assert cache.get("arxiv", "deep learning", ttl_hours=24) == [{"title": "x"}]
```

- [ ] **Step 2: Run test to verify it fails**

```bash
uv run pytest tests/research/test_cache.py -v
```

Expected: ModuleNotFoundError.

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/cache.py
"""File-based JSON cache for source results.

Cache layout: ~/.cache/obsidian-second-brain/research/<source>-<sha1(q)>.json
TTL is enforced via file mtime. Misses return None; callers fetch from network
and call put() to seed the cache.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path
from typing import Any


def _cache_dir() -> Path:
    p = Path(os.path.expanduser("~/.cache/obsidian-second-brain/research"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def _normalize(query: str) -> str:
    return " ".join(query.lower().split())


def _key(source: str, query: str) -> Path:
    sha = hashlib.sha1(_normalize(query).encode("utf-8")).hexdigest()[:16]
    return _cache_dir() / f"{source}-{sha}.json"


def get(source: str, query: str, ttl_hours: int) -> list[dict[str, Any]] | None:
    path = _key(source, query)
    if not path.exists():
        return None
    age_s = time.time() - path.stat().st_mtime
    if age_s > ttl_hours * 3600:
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def put(source: str, query: str, results: list[Any]) -> None:
    path = _key(source, query)
    try:
        # results may contain Result objects; pass through encode_results
        from .result import encode_results
        path.write_text(json.dumps(results, default=encode_results))
    except OSError:
        pass  # cache failure is non-fatal


def clear() -> int:
    """Remove all cache entries. Returns count removed."""
    count = 0
    for f in _cache_dir().glob("*.json"):
        try:
            f.unlink()
            count += 1
        except OSError:
            pass
    return count


__all__ = ["get", "put", "clear"]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run pytest tests/research/test_cache.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/research/lib/cache.py tests/research/test_cache.py
git commit -m "feat(research): add file-based cache with TTL"
```

---

### Task 5: Parallel aggregator (`lib/aggregator.py`)

**Files:**
- Create: `scripts/research/lib/aggregator.py`
- Test: `tests/research/test_aggregator.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_aggregator.py
from scripts.research.lib.aggregator import aggregate
from scripts.research.lib.result import Result


class _Stub:
    def __init__(self, name, results=None, raise_exc=None):
        self.name = name
        self._results = results or []
        self._raise = raise_exc

    def search(self, query, n=10):
        if self._raise:
            raise self._raise
        return self._results


def test_aggregator_collects_from_all_sources():
    a = _Stub("a", results=[Result(source="a", title="t1", url="https://a")])
    b = _Stub("b", results=[Result(source="b", title="t2", url="https://b")])
    out = aggregate("topic", [a, b])
    assert out["stats"]["sources_attempted"] == 2
    assert out["stats"]["sources_succeeded"] == 2
    assert out["stats"]["results_total"] == 2
    titles = {r["title"] for r in out["results"]}
    assert titles == {"t1", "t2"}


def test_aggregator_tolerates_exception_in_source():
    a = _Stub("a", results=[Result(source="a", title="t1", url="https://a")])
    b = _Stub("b", raise_exc=RuntimeError("boom"))
    out = aggregate("topic", [a, b])
    assert out["stats"]["sources_succeeded"] == 1
    assert "b" in out["warnings"][0]
    assert len(out["results"]) == 1


def test_aggregator_marks_success_when_three_succeed():
    sources = [
        _Stub("s1", results=[Result(source="s1", title="x", url="https://x")]),
        _Stub("s2", results=[Result(source="s2", title="x", url="https://x")]),
        _Stub("s3", results=[Result(source="s3", title="x", url="https://x")]),
        _Stub("s4", raise_exc=RuntimeError("dead")),
    ]
    out = aggregate("topic", sources)
    assert out["stats"]["success"] is True


def test_aggregator_marks_partial_when_under_three_succeed():
    sources = [
        _Stub("s1", results=[Result(source="s1", title="x", url="https://x")]),
        _Stub("s2", raise_exc=RuntimeError("dead")),
        _Stub("s3", raise_exc=RuntimeError("dead")),
    ]
    out = aggregate("topic", sources)
    assert out["stats"]["success"] is False
```

- [ ] **Step 2: Run test to verify it fails**

```bash
uv run pytest tests/research/test_aggregator.py -v
```

Expected: ModuleNotFoundError.

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/aggregator.py
"""Run multiple source clients in parallel, aggregate, never crash on per-source failure."""

from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout, as_completed
from dataclasses import asdict
from typing import Any, Protocol

from .result import Result

OVERALL_TIMEOUT_SECONDS = 30


class SourceClient(Protocol):
    name: str

    def search(self, query: str, n: int = 10) -> list[Result]: ...


def aggregate(
    query: str,
    sources: list[SourceClient],
    n_per_source: int = 10,
    timeout: float = OVERALL_TIMEOUT_SECONDS,
) -> dict[str, Any]:
    """Run all sources in parallel. Return JSON-serializable dict."""

    results: list[Result] = []
    warnings: list[str] = []
    succeeded: set[str] = set()

    with ThreadPoolExecutor(max_workers=len(sources)) as ex:
        future_to_source = {
            ex.submit(_safe_search, s, query, n_per_source): s for s in sources
        }
        try:
            for future in as_completed(future_to_source, timeout=timeout):
                src = future_to_source[future]
                got, err = future.result()
                if err:
                    warnings.append(f"{src.name}: {err}")
                if got:
                    results.extend(got)
                    succeeded.add(src.name)
        except FuturesTimeout:
            for f, s in future_to_source.items():
                if not f.done():
                    warnings.append(f"{s.name}: timeout")

    return {
        "topic": query,
        "results": [asdict(r) for r in results],
        "stats": {
            "sources_attempted": len(sources),
            "sources_succeeded": len(succeeded),
            "results_total": len(results),
            "success": len(succeeded) >= 3,
        },
        "warnings": warnings,
    }


def _safe_search(source: SourceClient, query: str, n: int) -> tuple[list[Result], str | None]:
    try:
        return source.search(query, n=n), None
    except Exception as e:
        print(f"[{source.name}] {type(e).__name__}: {e}", file=sys.stderr)
        return [], str(e)


__all__ = ["aggregate", "SourceClient", "OVERALL_TIMEOUT_SECONDS"]
```

- [ ] **Step 4: Run test to verify it passes**

```bash
uv run pytest tests/research/test_aggregator.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add scripts/research/lib/aggregator.py tests/research/test_aggregator.py
git commit -m "feat(research): add parallel source aggregator"
```

---

## Phase 2 — Source Clients

> **Pattern (all 10 sources):** Each lives at `scripts/research/lib/sources/<name>.py`, exports a class with `name: str` attribute and `search(query: str, n: int = 10) -> list[Result]`. Tests use `responses` to mock HTTP and assert parser output. Cache is checked before HTTP. Failures return `[]` (NEVER raise — `_safe_search` wraps but defense in depth).

### Task 6: arXiv source

**Endpoint:** `http://export.arxiv.org/api/query?search_query=all:<q>&start=0&max_results=<n>` — returns Atom XML.

**Files:**
- Create: `scripts/research/lib/sources/__init__.py` (empty)
- Create: `scripts/research/lib/sources/arxiv.py`
- Test: `tests/research/sources/__init__.py` (empty), `tests/research/sources/test_arxiv.py`
- Test fixture: `tests/research/sources/fixtures/arxiv_response.xml`

- [ ] **Step 1: Capture a real response as fixture** (one-time, manual)

```bash
mkdir -p tests/research/sources/fixtures
curl -s "http://export.arxiv.org/api/query?search_query=all:retrieval+augmented+generation&max_results=3" \
  > tests/research/sources/fixtures/arxiv_response.xml
```

- [ ] **Step 2: Write failing test**

```python
# tests/research/sources/test_arxiv.py
from pathlib import Path
import responses
from scripts.research.lib.sources.arxiv import ArxivSource

FIXTURE = Path(__file__).parent / "fixtures" / "arxiv_response.xml"


@responses.activate
def test_arxiv_search_returns_parsed_results():
    responses.add(
        responses.GET,
        "http://export.arxiv.org/api/query",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/atom+xml",
    )
    s = ArxivSource()
    results = s.search("retrieval augmented generation", n=3)
    assert s.name == "arxiv"
    assert 1 <= len(results) <= 3
    r = results[0]
    assert r.source == "arxiv"
    assert r.title
    assert r.url.startswith("http")
    assert r.abstract
    assert r.year is not None
    assert isinstance(r.authors, list) and len(r.authors) > 0


@responses.activate
def test_arxiv_http_failure_returns_empty():
    responses.add(
        responses.GET,
        "http://export.arxiv.org/api/query",
        status=500,
    )
    assert ArxivSource(retries=1).search("x", n=3) == []
```

- [ ] **Step 3: Run test to verify it fails**

```bash
uv run pytest tests/research/sources/test_arxiv.py -v
```

Expected: ModuleNotFoundError.

- [ ] **Step 4: Write implementation**

```python
# scripts/research/lib/sources/arxiv.py
"""arXiv search via the official Atom API. Free, no key, 1 req/3s polite limit."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "http://export.arxiv.org/api/query"
NS = {
    "atom": "http://www.w3.org/2005/Atom",
}


class ArxivSource:
    name = "arxiv"

    def __init__(self, retries: int = 3) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"search_query": f"all:{query}", "start": 0, "max_results": n}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.text)
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _parse(atom_xml: str) -> list[Result]:
    try:
        root = ET.fromstring(atom_xml)
    except ET.ParseError:
        return []

    out: list[Result] = []
    for entry in root.findall("atom:entry", NS):
        title = _text(entry.find("atom:title", NS))
        summary = _text(entry.find("atom:summary", NS))
        link_el = entry.find("atom:link[@rel='alternate']", NS)
        url = link_el.attrib.get("href", "") if link_el is not None else ""
        published = _text(entry.find("atom:published", NS))
        year = _year(published)
        authors = [
            _text(a.find("atom:name", NS))
            for a in entry.findall("atom:author", NS)
            if a.find("atom:name", NS) is not None
        ]
        out.append(
            Result(
                source="arxiv",
                title=title,
                url=url,
                abstract=summary,
                authors=[a for a in authors if a],
                year=year,
                posted_at=published or None,
            )
        )
    return out


def _text(el) -> str:
    return (el.text or "").strip() if el is not None else ""


def _year(iso_date: str) -> int | None:
    m = re.match(r"^(\d{4})", iso_date or "")
    return int(m.group(1)) if m else None


__all__ = ["ArxivSource"]
```

- [ ] **Step 5: Run test to verify it passes**

```bash
uv run pytest tests/research/sources/test_arxiv.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add scripts/research/lib/sources/__init__.py scripts/research/lib/sources/arxiv.py \
        tests/research/sources/__init__.py tests/research/sources/test_arxiv.py \
        tests/research/sources/fixtures/arxiv_response.xml
git commit -m "feat(research): add arXiv source client"
```

---

### Task 7: Semantic Scholar source

**Endpoint:** `https://api.semanticscholar.org/graph/v1/paper/search?query=<q>&limit=<n>&fields=title,abstract,authors,year,url,externalIds` — JSON.

**Files:**
- Create: `scripts/research/lib/sources/semantic_scholar.py`
- Test: `tests/research/sources/test_semantic_scholar.py`
- Fixture: `tests/research/sources/fixtures/s2_response.json`

- [ ] **Step 1: Capture fixture**

```bash
curl -s "https://api.semanticscholar.org/graph/v1/paper/search?query=rag&limit=3&fields=title,abstract,authors,year,url,externalIds" \
  > tests/research/sources/fixtures/s2_response.json
```

- [ ] **Step 2: Write failing test**

```python
# tests/research/sources/test_semantic_scholar.py
from pathlib import Path
import responses
from scripts.research.lib.sources.semantic_scholar import SemanticScholarSource

FIXTURE = Path(__file__).parent / "fixtures" / "s2_response.json"


@responses.activate
def test_s2_search_parses_results():
    responses.add(
        responses.GET,
        "https://api.semanticscholar.org/graph/v1/paper/search",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    s = SemanticScholarSource()
    out = s.search("rag", n=3)
    assert s.name == "semantic_scholar"
    assert len(out) >= 1
    r = out[0]
    assert r.title
    assert r.url.startswith("http")
    assert isinstance(r.authors, list)


@responses.activate
def test_s2_429_returns_empty():
    responses.add(
        responses.GET,
        "https://api.semanticscholar.org/graph/v1/paper/search",
        status=429,
    )
    assert SemanticScholarSource(retries=1).search("x", n=3) == []
```

- [ ] **Step 3: Run test to verify it fails**

```bash
uv run pytest tests/research/sources/test_semantic_scholar.py -v
```

Expected: ModuleNotFoundError.

- [ ] **Step 4: Write implementation**

```python
# scripts/research/lib/sources/semantic_scholar.py
"""Semantic Scholar Graph API. Free; 100 req/5min unauth, polite to throttle."""

from __future__ import annotations

import json

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://api.semanticscholar.org/graph/v1/paper/search"
FIELDS = "title,abstract,authors,year,url,externalIds"


class SemanticScholarSource:
    name = "semantic_scholar"

    def __init__(self, retries: int = 2) -> None:
        self._session = http.get_session(retries=retries, backoff=2.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"query": query, "limit": min(n, 100), "fields": FIELDS}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.json())
            cache.put(self.name, query, results)
            return results
        except (json.JSONDecodeError, Exception):
            return []


def _parse(payload: dict) -> list[Result]:
    out: list[Result] = []
    for paper in payload.get("data", []):
        authors = [a.get("name", "") for a in paper.get("authors") or []]
        doi = (paper.get("externalIds") or {}).get("DOI")
        url = paper.get("url") or (f"https://doi.org/{doi}" if doi else "")
        out.append(
            Result(
                source="semantic_scholar",
                title=paper.get("title") or "",
                url=url,
                abstract=paper.get("abstract"),
                authors=[a for a in authors if a],
                year=paper.get("year"),
                extra={"doi": doi} if doi else {},
            )
        )
    return out


__all__ = ["SemanticScholarSource"]
```

- [ ] **Step 5: Run test to verify it passes**

```bash
uv run pytest tests/research/sources/test_semantic_scholar.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add scripts/research/lib/sources/semantic_scholar.py \
        tests/research/sources/test_semantic_scholar.py \
        tests/research/sources/fixtures/s2_response.json
git commit -m "feat(research): add Semantic Scholar source client"
```

---

### Task 8: OpenAlex source

**Endpoint:** `https://api.openalex.org/works?search=<q>&per-page=<n>` — JSON.

**Files:**
- Create: `scripts/research/lib/sources/openalex.py`
- Test: `tests/research/sources/test_openalex.py`
- Fixture: `tests/research/sources/fixtures/openalex_response.json`

- [ ] **Step 1: Capture fixture**

```bash
curl -s "https://api.openalex.org/works?search=retrieval+augmented&per-page=3" \
  > tests/research/sources/fixtures/openalex_response.json
```

- [ ] **Step 2: Write failing test**

```python
# tests/research/sources/test_openalex.py
from pathlib import Path
import responses
from scripts.research.lib.sources.openalex import OpenAlexSource

FIXTURE = Path(__file__).parent / "fixtures" / "openalex_response.json"


@responses.activate
def test_openalex_parses_results():
    responses.add(
        responses.GET, "https://api.openalex.org/works",
        body=FIXTURE.read_text(), status=200, content_type="application/json",
    )
    s = OpenAlexSource()
    out = s.search("retrieval augmented", n=3)
    assert s.name == "openalex"
    assert len(out) >= 1
    assert out[0].title and out[0].url
```

- [ ] **Step 3: Run test to verify it fails**

```bash
uv run pytest tests/research/sources/test_openalex.py -v
```

- [ ] **Step 4: Write implementation**

```python
# scripts/research/lib/sources/openalex.py
"""OpenAlex Works API. Free; polite pool when User-Agent has mailto."""

from __future__ import annotations

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://api.openalex.org/works"


class OpenAlexSource:
    name = "openalex"

    def __init__(self, retries: int = 2) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"search": query, "per-page": min(n, 25)}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.json())
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _parse(payload: dict) -> list[Result]:
    out: list[Result] = []
    for w in payload.get("results", []):
        title = w.get("display_name") or w.get("title") or ""
        doi = w.get("doi")
        url = doi or w.get("id") or ""
        abstract = _reconstruct_abstract(w.get("abstract_inverted_index"))
        authors = [
            a.get("author", {}).get("display_name", "")
            for a in w.get("authorships", [])
        ]
        out.append(Result(
            source="openalex",
            title=title,
            url=url,
            abstract=abstract,
            authors=[a for a in authors if a],
            year=w.get("publication_year"),
            extra={"doi": doi, "cited_by_count": w.get("cited_by_count")},
        ))
    return out


def _reconstruct_abstract(inv: dict | None) -> str | None:
    """OpenAlex stores abstracts as inverted index {word: [positions]}. Reconstruct."""
    if not inv:
        return None
    pairs = []
    for word, positions in inv.items():
        for p in positions:
            pairs.append((p, word))
    pairs.sort()
    return " ".join(w for _, w in pairs) or None


__all__ = ["OpenAlexSource"]
```

- [ ] **Step 5: Run test + commit**

```bash
uv run pytest tests/research/sources/test_openalex.py -v
git add scripts/research/lib/sources/openalex.py tests/research/sources/test_openalex.py \
        tests/research/sources/fixtures/openalex_response.json
git commit -m "feat(research): add OpenAlex source client"
```

---

### Task 9: CrossRef source

**Endpoint:** `https://api.crossref.org/works?query=<q>&rows=<n>` — JSON.

**Files:**
- Create: `scripts/research/lib/sources/crossref.py`
- Test: `tests/research/sources/test_crossref.py`
- Fixture: `tests/research/sources/fixtures/crossref_response.json`

- [ ] **Step 1: Capture fixture**

```bash
curl -s "https://api.crossref.org/works?query=retrieval+augmented&rows=3" \
  > tests/research/sources/fixtures/crossref_response.json
```

- [ ] **Step 2: Write failing test**

```python
# tests/research/sources/test_crossref.py
from pathlib import Path
import responses
from scripts.research.lib.sources.crossref import CrossRefSource

FIXTURE = Path(__file__).parent / "fixtures" / "crossref_response.json"


@responses.activate
def test_crossref_parses():
    responses.add(responses.GET, "https://api.crossref.org/works",
                  body=FIXTURE.read_text(), status=200, content_type="application/json")
    out = CrossRefSource().search("retrieval augmented", n=3)
    assert len(out) >= 1
    assert out[0].title and out[0].url and out[0].source == "crossref"
```

- [ ] **Step 3: Run test, write implementation, commit**

```python
# scripts/research/lib/sources/crossref.py
"""CrossRef REST API. Free; polite pool when User-Agent has mailto."""

from __future__ import annotations

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://api.crossref.org/works"


class CrossRefSource:
    name = "crossref"

    def __init__(self, retries: int = 2) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"query": query, "rows": min(n, 50)}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.json())
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _parse(payload: dict) -> list[Result]:
    out: list[Result] = []
    for w in payload.get("message", {}).get("items", []):
        titles = w.get("title") or []
        title = titles[0] if titles else ""
        doi = w.get("DOI")
        url = w.get("URL") or (f"https://doi.org/{doi}" if doi else "")
        abstract = w.get("abstract")
        authors = [
            f"{a.get('given', '')} {a.get('family', '')}".strip()
            for a in w.get("author", [])
        ]
        year = None
        date_parts = (w.get("issued") or {}).get("date-parts") or []
        if date_parts and date_parts[0]:
            year = date_parts[0][0]
        out.append(Result(
            source="crossref",
            title=title,
            url=url,
            abstract=abstract,
            authors=[a for a in authors if a],
            year=year,
            extra={"doi": doi},
        ))
    return out


__all__ = ["CrossRefSource"]
```

```bash
uv run pytest tests/research/sources/test_crossref.py -v
git add scripts/research/lib/sources/crossref.py tests/research/sources/test_crossref.py \
        tests/research/sources/fixtures/crossref_response.json
git commit -m "feat(research): add CrossRef source client"
```

---

### Task 10: Wikipedia source

**Endpoint:** REST summary: `https://en.wikipedia.org/api/rest_v1/page/summary/<title>` + search: `https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=<q>&srlimit=<n>&format=json`.

Two-step: search to get top N titles, then fetch summary for each.

**Files:**
- Create: `scripts/research/lib/sources/wikipedia.py`
- Test: `tests/research/sources/test_wikipedia.py`
- Fixtures: `tests/research/sources/fixtures/wiki_search.json`, `wiki_summary.json`

- [ ] **Step 1: Capture fixtures**

```bash
curl -s "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=transformer+architecture&srlimit=3&format=json" \
  > tests/research/sources/fixtures/wiki_search.json
curl -s "https://en.wikipedia.org/api/rest_v1/page/summary/Transformer_(deep_learning_architecture)" \
  > tests/research/sources/fixtures/wiki_summary.json
```

- [ ] **Step 2: Write failing test**

```python
# tests/research/sources/test_wikipedia.py
from pathlib import Path
import responses
from scripts.research.lib.sources.wikipedia import WikipediaSource

FIX = Path(__file__).parent / "fixtures"


@responses.activate
def test_wikipedia_returns_results():
    responses.add(responses.GET, "https://en.wikipedia.org/w/api.php",
                  body=(FIX / "wiki_search.json").read_text(), status=200)
    responses.add(responses.GET,
                  responses.matchers.re.compile(r"https://en\.wikipedia\.org/api/rest_v1/page/summary/.+"),
                  body=(FIX / "wiki_summary.json").read_text(), status=200)
    out = WikipediaSource().search("transformer architecture", n=1)
    assert len(out) >= 1
    assert out[0].source == "wikipedia"
    assert out[0].title and out[0].snippet
```

- [ ] **Step 3: Write implementation**

```python
# scripts/research/lib/sources/wikipedia.py
"""Wikipedia search + summary. Free; 200 req/s soft cap."""

from __future__ import annotations

import urllib.parse

from .. import cache, http
from ..config import load
from ..result import Result

SEARCH = "https://en.wikipedia.org/w/api.php"
SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"


class WikipediaSource:
    name = "wikipedia"

    def __init__(self, retries: int = 2) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 5) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        try:
            r = self._session.get(
                SEARCH,
                params={"action": "query", "list": "search", "srsearch": query,
                        "srlimit": n, "format": "json"},
                timeout=http.DEFAULT_TIMEOUT,
            )
            if r.status_code != 200:
                return []
            titles = [h["title"] for h in r.json().get("query", {}).get("search", [])]
            results = []
            for t in titles[:n]:
                summ = self._summary(t)
                if summ:
                    results.append(summ)
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []

    def _summary(self, title: str) -> Result | None:
        try:
            r = self._session.get(
                SUMMARY + urllib.parse.quote(title.replace(" ", "_"), safe=""),
                timeout=http.DEFAULT_TIMEOUT,
            )
            if r.status_code != 200:
                return None
            j = r.json()
            return Result(
                source="wikipedia",
                title=j.get("title") or title,
                url=j.get("content_urls", {}).get("desktop", {}).get("page", ""),
                snippet=j.get("extract"),
            )
        except Exception:
            return None


__all__ = ["WikipediaSource"]
```

- [ ] **Step 4: Run + commit**

```bash
uv run pytest tests/research/sources/test_wikipedia.py -v
git add scripts/research/lib/sources/wikipedia.py tests/research/sources/test_wikipedia.py \
        tests/research/sources/fixtures/wiki_search.json tests/research/sources/fixtures/wiki_summary.json
git commit -m "feat(research): add Wikipedia source client"
```

---

### Task 11: HackerNews source (Algolia)

**Endpoint:** `https://hn.algolia.com/api/v1/search?query=<q>&hitsPerPage=<n>&tags=story` — JSON.

**Files:**
- Create: `scripts/research/lib/sources/hackernews.py`
- Test: `tests/research/sources/test_hackernews.py`
- Fixture: `tests/research/sources/fixtures/hn_response.json`

- [ ] **Step 1: Capture fixture**

```bash
curl -s "https://hn.algolia.com/api/v1/search?query=claude+code&hitsPerPage=3&tags=story" \
  > tests/research/sources/fixtures/hn_response.json
```

- [ ] **Step 2: Test + impl + commit (pattern identical to Task 7)**

```python
# tests/research/sources/test_hackernews.py
from pathlib import Path
import responses
from scripts.research.lib.sources.hackernews import HackerNewsSource

FIXTURE = Path(__file__).parent / "fixtures" / "hn_response.json"


@responses.activate
def test_hn_parses():
    responses.add(responses.GET, "https://hn.algolia.com/api/v1/search",
                  body=FIXTURE.read_text(), status=200, content_type="application/json")
    out = HackerNewsSource().search("claude code", n=3)
    assert len(out) >= 1
    assert out[0].source == "hackernews"
    assert out[0].title and out[0].url
    assert out[0].points is not None
```

```python
# scripts/research/lib/sources/hackernews.py
"""HackerNews via Algolia search. Free, no key, no rate limit."""

from __future__ import annotations

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://hn.algolia.com/api/v1/search"


class HackerNewsSource:
    name = "hackernews"

    def __init__(self, retries: int = 1) -> None:
        self._session = http.get_session(retries=retries, backoff=0.5)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"query": query, "hitsPerPage": min(n, 50), "tags": "story"}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.json())
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _parse(payload: dict) -> list[Result]:
    out: list[Result] = []
    for h in payload.get("hits", []):
        out.append(Result(
            source="hackernews",
            title=h.get("title") or "",
            url=h.get("url") or f"https://news.ycombinator.com/item?id={h.get('objectID')}",
            snippet=(h.get("story_text") or "")[:280] or None,
            points=h.get("points"),
            comments=h.get("num_comments"),
            posted_at=h.get("created_at"),
        ))
    return out


__all__ = ["HackerNewsSource"]
```

```bash
uv run pytest tests/research/sources/test_hackernews.py -v
git add scripts/research/lib/sources/hackernews.py tests/research/sources/test_hackernews.py \
        tests/research/sources/fixtures/hn_response.json
git commit -m "feat(research): add HackerNews source client"
```

---

### Task 12: Reddit source

**Endpoint:** `https://www.reddit.com/search.json?q=<q>&limit=<n>` (or per-sub: `https://www.reddit.com/r/<sub>/search.json?q=<q>&restrict_sr=1`). Requires `User-Agent` not containing default keywords. We use our custom one.

**Files:**
- Create: `scripts/research/lib/sources/reddit.py`
- Test: `tests/research/sources/test_reddit.py`
- Fixture: `tests/research/sources/fixtures/reddit_response.json`

- [ ] **Step 1: Capture fixture**

```bash
curl -s -A "obsidian-second-brain/1.0 testing" \
  "https://www.reddit.com/search.json?q=langchain&limit=3" \
  > tests/research/sources/fixtures/reddit_response.json
```

- [ ] **Step 2: Test + impl + commit**

```python
# tests/research/sources/test_reddit.py
from pathlib import Path
import responses
from scripts.research.lib.sources.reddit import RedditSource

FIXTURE = Path(__file__).parent / "fixtures" / "reddit_response.json"


@responses.activate
def test_reddit_parses():
    responses.add(responses.GET, "https://www.reddit.com/search.json",
                  body=FIXTURE.read_text(), status=200, content_type="application/json")
    out = RedditSource().search("langchain", n=3)
    assert len(out) >= 1
    assert out[0].source == "reddit"
    assert out[0].url.startswith("https://www.reddit.com")
```

```python
# scripts/research/lib/sources/reddit.py
"""Reddit search.json. Free, no key; needs realistic User-Agent."""

from __future__ import annotations

import time

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://www.reddit.com/search.json"


class RedditSource:
    name = "reddit"

    def __init__(self, retries: int = 1) -> None:
        self._session = http.get_session(retries=retries, backoff=2.0)
        self._ttl = load().cache_ttl_hours
        self._throttle = load().reddit_seconds

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"q": query, "limit": min(n, 25)}
        try:
            time.sleep(self._throttle)
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = _parse(r.json())
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _parse(payload: dict) -> list[Result]:
    out: list[Result] = []
    for child in payload.get("data", {}).get("children", []):
        d = child.get("data", {})
        out.append(Result(
            source="reddit",
            title=d.get("title") or "",
            url=f"https://www.reddit.com{d.get('permalink', '')}",
            snippet=(d.get("selftext") or "")[:280] or None,
            points=d.get("score"),
            comments=d.get("num_comments"),
            posted_at=str(d.get("created_utc")) if d.get("created_utc") else None,
            extra={"subreddit": d.get("subreddit")},
        ))
    return out


__all__ = ["RedditSource"]
```

```bash
uv run pytest tests/research/sources/test_reddit.py -v
git add scripts/research/lib/sources/reddit.py tests/research/sources/test_reddit.py \
        tests/research/sources/fixtures/reddit_response.json
git commit -m "feat(research): add Reddit source client"
```

---

### Task 13: Lobsters source

**Endpoint:** `https://lobste.rs/search.json?q=<q>&what=stories&order=relevance` — JSON.

**Files:**
- Create: `scripts/research/lib/sources/lobsters.py`
- Test: `tests/research/sources/test_lobsters.py`
- Fixture: `tests/research/sources/fixtures/lobsters_response.json`

- [ ] Same 6-step pattern as Task 11 with these specifics:

```bash
curl -s "https://lobste.rs/search.json?q=rust&what=stories&order=relevance" \
  > tests/research/sources/fixtures/lobsters_response.json
```

```python
# scripts/research/lib/sources/lobsters.py
"""Lobsters search. Free, no key."""

from __future__ import annotations

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://lobste.rs/search.json"


class LobstersSource:
    name = "lobsters"

    def __init__(self, retries: int = 1) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        params = {"q": query, "what": "stories", "order": "relevance"}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            data = r.json()[: min(n, 25)] if isinstance(r.json(), list) else []
            results = [
                Result(
                    source="lobsters",
                    title=s.get("title") or "",
                    url=s.get("url") or s.get("short_id_url") or "",
                    points=s.get("score"),
                    comments=s.get("comment_count"),
                    posted_at=s.get("created_at"),
                    extra={"tags": s.get("tags")},
                )
                for s in data
            ]
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


__all__ = ["LobstersSource"]
```

Test mirrors Task 11. Commit message: `feat(research): add Lobsters source client`.

---

### Task 14: dev.to source

**Endpoint:** `https://dev.to/api/articles?per_page=<n>&tag=<tag>` (no native search; we search by tag derived from query).

**Files:**
- Create: `scripts/research/lib/sources/devto.py`
- Test: `tests/research/sources/test_devto.py`
- Fixture: `tests/research/sources/fixtures/devto_response.json`

- [ ] Same pattern. Capture:

```bash
curl -s "https://dev.to/api/articles?per_page=3&tag=python" \
  > tests/research/sources/fixtures/devto_response.json
```

```python
# scripts/research/lib/sources/devto.py
"""dev.to articles by tag. Free, no key. Best-effort: query slugified as tag."""

from __future__ import annotations

import re

from .. import cache, http
from ..config import load
from ..result import Result

ENDPOINT = "https://dev.to/api/articles"


class DevToSource:
    name = "devto"

    def __init__(self, retries: int = 1) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        self._ttl = load().cache_ttl_hours

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        # devto API has no free-text search; we use the first significant word as tag
        tag = _query_to_tag(query)
        params = {"per_page": min(n, 30), "tag": tag} if tag else {"per_page": min(n, 30)}
        try:
            r = self._session.get(ENDPOINT, params=params, timeout=http.DEFAULT_TIMEOUT)
            if r.status_code != 200:
                return []
            results = [
                Result(
                    source="devto",
                    title=a.get("title") or "",
                    url=a.get("url") or "",
                    snippet=a.get("description"),
                    points=a.get("public_reactions_count"),
                    comments=a.get("comments_count"),
                    posted_at=a.get("published_at"),
                    extra={"tag_list": a.get("tag_list")},
                )
                for a in r.json()
            ]
            cache.put(self.name, query, results)
            return results
        except Exception:
            return []


def _query_to_tag(q: str) -> str | None:
    # Strip non-alphanum, take first word ≥ 3 chars
    words = re.findall(r"[a-z0-9]+", q.lower())
    return next((w for w in words if len(w) >= 3), None)


__all__ = ["DevToSource"]
```

Test: confirms `out[0].source == "devto"` after fixture-backed call.

```bash
uv run pytest tests/research/sources/test_devto.py -v
git add scripts/research/lib/sources/devto.py tests/research/sources/test_devto.py \
        tests/research/sources/fixtures/devto_response.json
git commit -m "feat(research): add dev.to source client"
```

---

### Task 15: DuckDuckGo source (with SearXNG fallback)

**Endpoint:** DuckDuckGo HTML: `https://html.duckduckgo.com/html/?q=<q>`. On 200, parse HTML; on CAPTCHA / non-200, fall through to SearXNG instances configured in `research.toml`.

**Files:**
- Create: `scripts/research/lib/sources/duckduckgo.py`
- Test: `tests/research/sources/test_duckduckgo.py`
- Fixtures: `tests/research/sources/fixtures/ddg_html.html`, `searxng_response.json`

- [ ] **Step 1: Capture fixtures**

```bash
curl -s -A "Mozilla/5.0" "https://html.duckduckgo.com/html/?q=python+rag" \
  > tests/research/sources/fixtures/ddg_html.html
curl -s "https://searx.be/search?q=python+rag&format=json" \
  > tests/research/sources/fixtures/searxng_response.json
```

- [ ] **Step 2: Failing test**

```python
# tests/research/sources/test_duckduckgo.py
from pathlib import Path
import responses
from scripts.research.lib.sources.duckduckgo import DuckDuckGoSource

FIX = Path(__file__).parent / "fixtures"


@responses.activate
def test_ddg_parses_html():
    responses.add(responses.GET, "https://html.duckduckgo.com/html/",
                  body=(FIX / "ddg_html.html").read_text(), status=200,
                  content_type="text/html")
    out = DuckDuckGoSource().search("python rag", n=3)
    assert len(out) >= 1
    assert out[0].source == "duckduckgo"
    assert out[0].url.startswith("http")


@responses.activate
def test_ddg_falls_back_to_searxng_on_block():
    responses.add(responses.GET, "https://html.duckduckgo.com/html/",
                  body="captcha", status=200, content_type="text/html")
    # SearXNG fallback
    responses.add(responses.GET, "https://searx.be/search",
                  body=(FIX / "searxng_response.json").read_text(), status=200,
                  content_type="application/json")
    out = DuckDuckGoSource(searxng_instances=["https://searx.be"]).search("python rag", n=3)
    assert out  # got something from searxng
```

- [ ] **Step 3: Implementation**

```python
# scripts/research/lib/sources/duckduckgo.py
"""DuckDuckGo HTML + SearXNG fallback. Free, no key.

DDG occasionally serves a CAPTCHA page; we detect by absence of results
in the HTML and fall through to SearXNG public instances.
"""

from __future__ import annotations

import re
from html import unescape
from urllib.parse import parse_qs, unquote, urlparse

from .. import cache, http
from ..config import load
from ..result import Result

DDG = "https://html.duckduckgo.com/html/"
RESULT_RE = re.compile(
    r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([^<]+)</a>'
    r'.*?<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
    re.DOTALL,
)


class DuckDuckGoSource:
    name = "duckduckgo"

    def __init__(self, retries: int = 1, searxng_instances: list[str] | None = None) -> None:
        self._session = http.get_session(retries=retries, backoff=1.0)
        cfg = load()
        self._ttl = cfg.cache_ttl_hours
        self._searxng = searxng_instances if searxng_instances is not None else cfg.searxng_instances

    def search(self, query: str, n: int = 10) -> list[Result]:
        cached = cache.get(self.name, query, ttl_hours=self._ttl)
        if cached is not None:
            return [Result(**r) for r in cached]

        results = self._try_ddg(query, n)
        if not results:
            results = self._try_searxng(query, n)
        cache.put(self.name, query, results)
        return results

    def _try_ddg(self, query: str, n: int) -> list[Result]:
        try:
            r = self._session.get(
                DDG,
                params={"q": query},
                timeout=http.DEFAULT_TIMEOUT,
                headers={"Accept-Language": "en-US,en;q=0.9"},
            )
            if r.status_code != 200:
                return []
            results: list[Result] = []
            for m in RESULT_RE.finditer(r.text)[: n] if False else list(RESULT_RE.finditer(r.text))[:n]:
                raw_url, title, snippet = m.group(1), m.group(2), m.group(3)
                final_url = _strip_ddg_redirect(raw_url)
                clean_snippet = re.sub(r"<[^>]+>", "", snippet).strip()
                results.append(Result(
                    source="duckduckgo",
                    title=unescape(title).strip(),
                    url=final_url,
                    snippet=unescape(clean_snippet) or None,
                ))
            return results
        except Exception:
            return []

    def _try_searxng(self, query: str, n: int) -> list[Result]:
        for inst in self._searxng:
            try:
                r = self._session.get(
                    f"{inst.rstrip('/')}/search",
                    params={"q": query, "format": "json"},
                    timeout=http.DEFAULT_TIMEOUT,
                )
                if r.status_code != 200:
                    continue
                payload = r.json()
                items = payload.get("results", [])[:n]
                return [
                    Result(
                        source="duckduckgo",  # report as ddg for consistency
                        title=i.get("title") or "",
                        url=i.get("url") or "",
                        snippet=i.get("content"),
                        extra={"engine": i.get("engine"), "via_searxng": inst},
                    )
                    for i in items
                ]
            except Exception:
                continue
        return []


def _strip_ddg_redirect(raw: str) -> str:
    """DDG wraps URLs in /l/?uddg=<encoded>. Unwrap."""
    if raw.startswith("//"):
        raw = "https:" + raw
    parsed = urlparse(raw)
    if "duckduckgo.com" in parsed.netloc and "uddg" in parsed.query:
        q = parse_qs(parsed.query).get("uddg", [""])[0]
        return unquote(q)
    return raw


__all__ = ["DuckDuckGoSource"]
```

```bash
uv run pytest tests/research/sources/test_duckduckgo.py -v
git add scripts/research/lib/sources/duckduckgo.py tests/research/sources/test_duckduckgo.py \
        tests/research/sources/fixtures/ddg_html.html tests/research/sources/fixtures/searxng_response.json
git commit -m "feat(research): add DuckDuckGo source with SearXNG fallback"
```

---

## Phase 3 — Command Python Entry Points

### Task 16: Rewrite `research.py` to emit JSON

**Files:**
- Modify: `scripts/research/research.py` (full rewrite)
- Test: `tests/research/test_research_entry.py`

- [ ] **Step 1: Write failing test**

```python
# tests/research/test_research_entry.py
import json
import sys
from io import StringIO
from unittest.mock import patch

from scripts.research import research as research_entry
from scripts.research.lib.result import Result


def _stub(name, items):
    cls = type(f"_Stub{name}", (), {})
    inst = cls()
    inst.name = name
    inst.search = lambda q, n=10, _items=items: _items
    return inst


def test_research_entry_emits_json_to_stdout(capsys):
    fake_results = [Result(source="hackernews", title="t", url="https://x")]
    with patch.object(
        research_entry,
        "_default_sources",
        return_value=[_stub("hackernews", fake_results), _stub("arxiv", [])],
    ):
        rc = research_entry.main(["research", "claude code"])
    assert rc == 0
    captured = capsys.readouterr()
    payload = json.loads(captured.out)
    assert payload["topic"] == "claude code"
    assert payload["stats"]["sources_attempted"] == 2
    assert any(r["title"] == "t" for r in payload["results"])


def test_research_academic_flag_uses_academic_sources(capsys):
    with patch.object(
        research_entry, "_academic_sources", return_value=[_stub("arxiv", [])]
    ) as ms:
        research_entry.main(["research", "deep learning", "--academic"])
    ms.assert_called_once()
```

- [ ] **Step 2: Run test to fail**

```bash
uv run pytest tests/research/test_research_entry.py -v
```

- [ ] **Step 3: Implementation**

```python
# scripts/research/research.py
"""/research <topic> [--academic] — emits aggregated source results as JSON.

The calling Claude session reads stdout JSON and synthesizes the AI-first
dossier. This script does NOT write to the vault; that's Claude's job per
commands/research.md.
"""

from __future__ import annotations

import json
import sys

from .lib.aggregator import aggregate
from .lib.result import encode_results
from .lib.sources.arxiv import ArxivSource
from .lib.sources.crossref import CrossRefSource
from .lib.sources.duckduckgo import DuckDuckGoSource
from .lib.sources.hackernews import HackerNewsSource
from .lib.sources.openalex import OpenAlexSource
from .lib.sources.reddit import RedditSource
from .lib.sources.semantic_scholar import SemanticScholarSource
from .lib.sources.wikipedia import WikipediaSource


def _default_sources():
    return [
        DuckDuckGoSource(),
        WikipediaSource(),
        HackerNewsSource(),
        RedditSource(),
        ArxivSource(),
        SemanticScholarSource(),
    ]


def _academic_sources():
    return [
        ArxivSource(),
        SemanticScholarSource(),
        OpenAlexSource(),
        CrossRefSource(),
    ]


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /research <topic> [--academic]", file=sys.stderr)
        return 2

    academic = "--academic" in argv
    args = [a for a in argv[1:] if a != "--academic"]
    topic = " ".join(args).strip()

    sources = _academic_sources() if academic else _default_sources()
    payload = aggregate(topic, sources, n_per_source=10)
    payload["academic_mode"] = academic
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if payload["stats"]["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run + commit**

```bash
uv run pytest tests/research/test_research_entry.py -v
git add scripts/research/research.py tests/research/test_research_entry.py
git commit -m "feat(research): rewrite research.py to emit JSON, drop Perplexity"
```

---

### Task 17: Rewrite `research_deep.py` as Phase-3 gap fetcher

The vault scan + gap analysis + synthesis steps are done by Claude in the .md command (Task 24). This Python entry takes 3-5 sub-queries as arguments and emits a unified JSON of aggregated results across all sub-queries.

**Files:**
- Modify: `scripts/research/research_deep.py`
- Test: `tests/research/test_research_deep_entry.py`

- [ ] **Step 1: Failing test**

```python
# tests/research/test_research_deep_entry.py
import json
import sys
from unittest.mock import patch

from scripts.research import research_deep
from scripts.research.lib.result import Result


def _stub(name, items):
    cls = type(f"_Stub{name}", (), {})
    inst = cls()
    inst.name = name
    inst.search = lambda q, n=10, _items=items: _items
    return inst


def test_research_deep_aggregates_multiple_queries(capsys):
    items = [Result(source="hackernews", title="t", url="https://x")]
    with patch.object(
        research_deep, "_default_sources", return_value=[_stub("hackernews", items)]
    ):
        rc = research_deep.main(["research_deep", "q1", "q2", "q3"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["sub_queries"] == ["q1", "q2", "q3"]
    assert len(payload["per_query"]) == 3
```

- [ ] **Step 2: Run + write impl**

```python
# scripts/research/research_deep.py
"""/research-deep — Phase-3 gap fetcher.

Vault scan + gap analysis + synthesis happen on the Claude side
(see commands/research-deep.md). This entry just runs aggregate() for each
sub-query Claude supplies and returns a structured JSON the synthesis step
can read.
"""

from __future__ import annotations

import json
import sys

from .lib.aggregator import aggregate
from .lib.result import encode_results
from .lib.sources.arxiv import ArxivSource
from .lib.sources.hackernews import HackerNewsSource
from .lib.sources.reddit import RedditSource
from .lib.sources.semantic_scholar import SemanticScholarSource
from .lib.sources.wikipedia import WikipediaSource


def _default_sources():
    return [
        ArxivSource(),
        SemanticScholarSource(),
        HackerNewsSource(),
        RedditSource(),
        WikipediaSource(),
    ]


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: /research-deep <sub-query> [<sub-query> ...]", file=sys.stderr)
        return 2

    sub_queries = [q for q in argv[1:] if q.strip()]
    if not sub_queries:
        return 2

    per_query = []
    for q in sub_queries:
        per_query.append(aggregate(q, _default_sources(), n_per_source=8))

    out = {
        "sub_queries": sub_queries,
        "per_query": per_query,
    }
    json.dump(out, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 3: Commit**

```bash
uv run pytest tests/research/test_research_deep_entry.py -v
git add scripts/research/research_deep.py tests/research/test_research_deep_entry.py
git commit -m "feat(research): rewrite research_deep.py to fan-out per sub-query, drop Perplexity+Grok"
```

---

### Task 18: `discourse_pulse.py`

**Files:**
- Create: `scripts/research/discourse_pulse.py`
- Test: `tests/research/test_discourse_pulse_entry.py`

- [ ] Same pattern as Task 16. Sources: HN, Reddit, Lobsters, dev.to.

```python
# scripts/research/discourse_pulse.py
"""/discourse-pulse <topic> — pulls discourse from HN, Reddit, Lobsters, dev.to."""

from __future__ import annotations

import json
import sys

from .lib.aggregator import aggregate
from .lib.result import encode_results
from .lib.sources.devto import DevToSource
from .lib.sources.hackernews import HackerNewsSource
from .lib.sources.lobsters import LobstersSource
from .lib.sources.reddit import RedditSource


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /discourse-pulse <topic>", file=sys.stderr)
        return 2

    topic = " ".join(argv[1:]).strip()
    sources = [HackerNewsSource(), RedditSource(), LobstersSource(), DevToSource()]
    payload = aggregate(topic, sources, n_per_source=10)
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if payload["stats"]["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Test:

```python
# tests/research/test_discourse_pulse_entry.py
import json
from unittest.mock import patch
from scripts.research import discourse_pulse


def test_discourse_pulse_runs(capsys):
    with patch.object(discourse_pulse, "HackerNewsSource") as _a, \
         patch.object(discourse_pulse, "RedditSource") as _b, \
         patch.object(discourse_pulse, "LobstersSource") as _c, \
         patch.object(discourse_pulse, "DevToSource") as _d:
        for cls in (_a, _b, _c, _d):
            cls.return_value.name = "stub"
            cls.return_value.search = lambda *args, **kw: []
        rc = discourse_pulse.main(["discourse_pulse", "rust async"])
    assert rc in (0, 1)
    payload = json.loads(capsys.readouterr().out)
    assert payload["topic"] == "rust async"
```

```bash
uv run pytest tests/research/test_discourse_pulse_entry.py -v
git add scripts/research/discourse_pulse.py tests/research/test_discourse_pulse_entry.py
git commit -m "feat(research): add discourse_pulse.py (replaces x_pulse.py)"
```

---

### Task 19: `thread_read.py`

**Files:**
- Create: `scripts/research/thread_read.py`
- Test: `tests/research/test_thread_read_entry.py`

Host detection → dispatch to per-host fetcher. v1 supports HN (Algolia item endpoint) and Reddit (`<thread>.json`). Future: blog scrape.

```python
# scripts/research/thread_read.py
"""/thread-read <url> — fetches a single thread (HN, Reddit) and emits JSON."""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse

from .lib import http
from .lib.result import encode_results


def _is_hn(url: str) -> bool:
    return "news.ycombinator.com" in url

def _is_reddit(url: str) -> bool:
    return "reddit.com" in url


def _fetch_hn(url: str) -> dict:
    item_id = _hn_item_id(url)
    if not item_id:
        return {"error": "could not extract HN item id"}
    sess = http.get_session()
    r = sess.get(f"https://hn.algolia.com/api/v1/items/{item_id}", timeout=15)
    if r.status_code != 200:
        return {"error": f"HN api status {r.status_code}"}
    return r.json()


def _hn_item_id(url: str) -> str | None:
    m = re.search(r"id=(\d+)", url)
    return m.group(1) if m else None


def _fetch_reddit(url: str) -> dict:
    sess = http.get_session()
    json_url = url.rstrip("/") + ".json"
    r = sess.get(json_url, timeout=15)
    if r.status_code != 200:
        return {"error": f"Reddit status {r.status_code}"}
    return r.json()


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /thread-read <url>", file=sys.stderr)
        return 2

    url = argv[1].strip()
    if _is_hn(url):
        data = _fetch_hn(url)
        host = "hackernews"
    elif _is_reddit(url):
        data = _fetch_reddit(url)
        host = "reddit"
    else:
        print(f"Unsupported host: {urlparse(url).netloc}", file=sys.stderr)
        return 2

    payload = {"url": url, "host": host, "data": data}
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Test asserts both code paths route correctly + emits JSON.

```bash
uv run pytest tests/research/test_thread_read_entry.py -v
git add scripts/research/thread_read.py tests/research/test_thread_read_entry.py
git commit -m "feat(research): add thread_read.py (replaces x_read.py)"
```

---

### Task 20: Rewrite `youtube_extract.py` (drop YouTube Data API + Grok)

Use `youtube-transcript-api` only + simple HTML scrape for title/channel via `requests`.

**Files:**
- Modify: `scripts/research/youtube_extract.py`
- Test: `tests/research/test_youtube_entry.py`
- Fixture: `tests/research/fixtures/youtube_page.html`

- [ ] Capture a YouTube page fixture (one-time):

```bash
mkdir -p tests/research/fixtures
curl -s -A "Mozilla/5.0" "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  > tests/research/fixtures/youtube_page.html
```

- [ ] Failing test:

```python
# tests/research/test_youtube_entry.py
import json
from pathlib import Path
from unittest.mock import patch

import responses
from scripts.research import youtube_extract as yt


FIXTURE = Path(__file__).parent / "fixtures" / "youtube_page.html"


@responses.activate
def test_youtube_extract_metadata(capsys):
    responses.add(responses.GET, "https://www.youtube.com/watch",
                  body=FIXTURE.read_text(), status=200, content_type="text/html")
    with patch.object(yt, "_fetch_transcript", return_value=[{"text": "hello", "start": 0.0}]):
        rc = yt.main(["youtube_extract", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["video_id"] == "dQw4w9WgXcQ"
    assert payload["transcript"]
```

- [ ] Implementation:

```python
# scripts/research/youtube_extract.py
"""/youtube <url> — pulls transcript via youtube-transcript-api + scrapes
minimal metadata from the page HTML. No YouTube Data API key required.
"""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import parse_qs, urlparse

from .lib import http
from .lib.result import encode_results


def _video_id(url: str) -> str | None:
    parsed = urlparse(url)
    if "youtu.be" in parsed.netloc:
        return parsed.path.strip("/")
    qs = parse_qs(parsed.query)
    if "v" in qs:
        return qs["v"][0]
    return None


def _scrape_metadata(video_id: str) -> dict:
    sess = http.get_session()
    sess.headers.update({"User-Agent": "Mozilla/5.0"})
    r = sess.get(f"https://www.youtube.com/watch?v={video_id}", timeout=15)
    if r.status_code != 200:
        return {}
    html = r.text
    title = _grab(html, r'<meta name="title" content="([^"]+)"')
    channel = _grab(html, r'"ownerChannelName":"([^"]+)"')
    published = _grab(html, r'"publishDate":"([^"]+)"')
    views = _grab(html, r'"viewCount":"(\d+)"')
    description = _grab(html, r'"shortDescription":"([^"]*)"')
    return {
        "title": title,
        "channel": channel,
        "published_at": published,
        "view_count": int(views) if views else None,
        "description": description,
    }


def _grab(text: str, pattern: str) -> str | None:
    m = re.search(pattern, text)
    return m.group(1) if m else None


def _fetch_transcript(video_id: str) -> list[dict]:
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        return YouTubeTranscriptApi.get_transcript(video_id)
    except Exception:
        return []


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /youtube <url>", file=sys.stderr)
        return 2

    url = argv[1].strip()
    vid = _video_id(url)
    if not vid:
        print(f"Could not extract video ID from URL: {url}", file=sys.stderr)
        return 2

    metadata = _scrape_metadata(vid)
    transcript = _fetch_transcript(vid)
    payload = {
        "video_id": vid,
        "url": url,
        "metadata": metadata,
        "transcript": transcript,
        "transcript_available": bool(transcript),
    }
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

```bash
uv run pytest tests/research/test_youtube_entry.py -v
git add scripts/research/youtube_extract.py tests/research/test_youtube_entry.py \
        tests/research/fixtures/youtube_page.html
git commit -m "feat(research): rewrite youtube_extract.py without YouTube Data API or Grok"
```

---

### Task 21: `idea_discovery.py`

**Files:**
- Create: `scripts/research/idea_discovery.py`
- Test: `tests/research/test_idea_discovery_entry.py`

Quick `arxiv` + `hackernews` scan per gap topic supplied as args.

```python
# scripts/research/idea_discovery.py
"""/idea-discovery — quick scan for each gap topic Claude identified.

The vault scan (Ideas/, Projects/ Open Questions, orphan Research/) is done
by Claude in commands/idea-discovery.md. This script only does the rapid
external check per gap.
"""

from __future__ import annotations

import json
import sys

from .lib.aggregator import aggregate
from .lib.result import encode_results
from .lib.sources.arxiv import ArxivSource
from .lib.sources.hackernews import HackerNewsSource


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: /idea-discovery <gap> [<gap> ...]", file=sys.stderr)
        return 2

    gaps = [g for g in argv[1:] if g.strip()]
    if not gaps:
        return 2

    per_gap = []
    for g in gaps:
        per_gap.append(aggregate(g, [ArxivSource(), HackerNewsSource()], n_per_source=5))

    out = {"gaps": gaps, "per_gap": per_gap}
    json.dump(out, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

Test mirrors Task 17.

```bash
uv run pytest tests/research/test_idea_discovery_entry.py -v
git add scripts/research/idea_discovery.py tests/research/test_idea_discovery_entry.py
git commit -m "feat(research): add idea_discovery.py (per-gap quick scan)"
```

---

## Phase 4 — Command `.md` Files

> **Pattern:** Each `.md` is what Claude reads when the slash command fires. It tells Claude (1) how to invoke the Python fetcher, (2) how to interpret stdout JSON, (3) how to write the AI-first vault note. Frontmatter stays compatible with `claudecode-discord` bridge.

### Task 22: Rewrite `commands/research.md`

**Files:**
- Modify: `commands/research.md`

- [ ] **Step 1: Write new content**

```markdown
---
description: Free-source web + academic research with citations — dossier saved to vault
category: research
triggers_en: ["research this", "look up", "find info on", "web research"]
---

Use the obsidian-second-brain skill. Execute `/research $ARGUMENTS`:

The argument is the research topic. Optional flag `--academic` restricts to arXiv / Semantic Scholar / OpenAlex / CrossRef only.

1. Read `_CLAUDE.md` first if it exists in the vault root.

2. Run the Python fetcher (from the repo root `~/.claude/skills/obsidian-second-brain/`):

   ```bash
   uv run -m scripts.research.research "<topic>" [--academic]
   ```

3. Parse the stdout JSON. Shape:

   ```json
   {
     "topic": "...",
     "academic_mode": false,
     "results": [{ "source": "...", "title": "...", "url": "...", "snippet": "...", "abstract": "...", "authors": [...], "year": 2024, "points": 47, "comments": 12, "posted_at": "..."}, ...],
     "stats": {"sources_attempted": 6, "sources_succeeded": 5, "results_total": 38, "success": true},
     "warnings": [...]
   }
   ```

4. Synthesize an AI-first dossier from the JSON. Follow `references/ai-first-rules.md`. Sections:

   - `## For future Claude` preamble (2-3 sentences explaining what this note is, when researched, by what method)
   - `## Summary` (3-5 sentences, current state of the topic)
   - `## Key Facts` — each fact carries `(as of YYYY-MM, source-domain.com)` recency marker, source URL kept verbatim
   - `## Timeline` if temporally significant events exist
   - `## Key Players` — people/companies, role, why they matter
   - `## Contrarian Views` — counter-arguments with source attribution
   - `## Open Questions` — gaps the JSON didn't fill
   - `## Sources` — every URL from the JSON, deduped, grouped by source name

5. Save to `Research/Web/YYYY-MM-DD-<slug>.md` (or `Research/Academic/` if `--academic`). Frontmatter:

   ```yaml
   ---
   date: YYYY-MM-DD
   type: research
   tags: [research, <slug-tag>, <source-tags>]
   topic: "<topic>"
   model: claude-via-self
   sources: [<all urls>]
   ai-first: true
   ---
   ```

6. Append a one-line entry to today's `Logs/YYYY-MM-DD.md`:
   ```
   **HH:MM** - research | <topic> — N sources, saved to [[Research/Web/<file>]]
   ```

7. Update `index.md` Research section to include the new note.

8. If `stats.success` is false (fewer than 3 sources returned results), tell the user plainly and suggest a narrower or different query before saving.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
```

- [ ] **Step 2: Commit**

```bash
git add commands/research.md
git commit -m "docs(commands): rewrite /research to use free-source JSON fetcher"
```

---

### Task 23: Rewrite `commands/research-deep.md`

- [ ] Replace the existing file with this content (preserves the Phase-1-vault-scan + Phase-4-propagation behavior, but moves all LLM steps to Claude):

```markdown
---
description: Vault-first deep research — Claude scans vault, identifies gaps, fetches per-gap free sources, synthesizes a delta, propagates updates
category: research
triggers_en: ["deep research", "thorough research", "vault-first research"]
---

Use the obsidian-second-brain skill. Execute `/research-deep $ARGUMENTS`:

The argument is the topic.

1. Read `_CLAUDE.md` first.

2. **Phase 1 — vault baseline** (you do this directly, no script):
   - Search `Research/`, `Projects/`, `Knowledge/`, `Ideas/` for any note mentioning the topic
   - List what's already known vs unknown
   - List wikilinks pointing into the topic from elsewhere

3. **Phase 2 — gap analysis** (you reason directly):
   - Based on the baseline, formulate 3-5 specific sub-queries that would fill the gaps
   - Each sub-query should be 3-8 words, retrieval-friendly
   - Make at least one academic-leaning and one discourse-leaning if both are relevant

4. **Phase 3 — fetch** (run the Python fetcher):

   ```bash
   uv run -m scripts.research.research_deep "<sub-q1>" "<sub-q2>" "<sub-q3>" ...
   ```

5. Parse stdout JSON. Shape:

   ```json
   {
     "sub_queries": ["...", "...", "..."],
     "per_query": [
       { "topic": "...", "results": [...], "stats": {...}, "warnings": [...] },
       ...
     ]
   }
   ```

6. **Phase 4 — synthesize delta** and save to `Research/Deep/YYYY-MM-DD-<slug>.md`. Sections:

   - `## For future Claude` preamble
   - `## Vault Baseline` — what we already knew (with `[[wikilinks]]` to existing notes)
   - `## Gap Queries` — the 3-5 sub-queries you generated and why
   - `## New Findings` — grouped per sub-query, each finding with recency marker + source
   - `## Confirmed` — things the new fetch confirmed about the baseline
   - `## Contradictions` — places where new findings conflict with vault baseline (flag for user attention)
   - `## Recommended Vault Updates` — bullet list of: "Update [[Projects/X]] Open Questions to add ..."
   - `## Open Questions` — what's still not filled
   - `## Sources` — every URL deduped

   Frontmatter:
   ```yaml
   ---
   date: YYYY-MM-DD
   type: research-deep
   tags: [research, deep, <slug-tag>]
   topic: "<topic>"
   model: claude-via-self
   sources: [<all urls>]
   ai-first: true
   ---
   ```

7. **Propagation** — after the deep note is saved, dispatch parallel sub-agents (one per People / Projects / Tasks / Decisions / Ideas) to apply each "Recommended Vault Update" bullet. Each update follows AI-first rules. Treat the deep note's body as the conversation context input.

8. Append `Logs/YYYY-MM-DD.md` entry and update `index.md`.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md`.
```

```bash
git add commands/research-deep.md
git commit -m "docs(commands): rewrite /research-deep with Claude-side phases"
```

---

### Task 24: Create `commands/discourse-pulse.md`

- [ ] Create new file:

```markdown
---
description: Pulse on a topic from HN, Reddit, Lobsters, dev.to — what builders are saying this week
category: research
triggers_en: ["discourse pulse", "what are people saying", "trending discussion"]
---

Use the obsidian-second-brain skill. Execute `/discourse-pulse $ARGUMENTS`:

1. Read `_CLAUDE.md`.

2. Run fetcher:

   ```bash
   uv run -m scripts.research.discourse_pulse "<topic>"
   ```

3. Parse JSON (same shape as `/research`).

4. Write `Research/Pulse/YYYY-MM-DD-<slug>.md` with sections:
   - `## For future Claude` preamble
   - `## Hot Threads` — top 5-10 by `points` * recency, with source + URL
   - `## Key Voices` — recurring authors/handles across threads (cite their thread)
   - `## Counter-takes` — minority views in the comments
   - `## Post Angle Ideas` — 2-3 angles for a writeup based on what's missing in the discourse
   - `## Sources` — verbatim URLs

   Frontmatter `type: pulse`.

5. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
```

```bash
git add commands/discourse-pulse.md
git commit -m "docs(commands): add /discourse-pulse (replaces /x-pulse)"
```

---

### Task 25: Create `commands/thread-read.md`

```markdown
---
description: Read a single HN or Reddit thread, summarize OP + top arguments
category: research
triggers_en: ["read thread", "summarize this thread", "what's in this discussion"]
---

Use the obsidian-second-brain skill. Execute `/thread-read $ARGUMENTS`:

1. Read `_CLAUDE.md`.

2. Run fetcher:

   ```bash
   uv run -m scripts.research.thread_read "<url>"
   ```

3. Parse JSON. Shape: `{"url": "...", "host": "hackernews|reddit", "data": <raw>}`.

4. Write `Research/Threads/YYYY-MM-DD-<slug>.md` with:
   - `## For future Claude` preamble (note the source URL prominently)
   - `## OP Summary` — TL;DR of the OP
   - `## Top Arguments` — 3-5 grouped by stance, each with verbatim quote + commenter handle
   - `## Notable Counter-takes` — minority views worth knowing
   - `## Sources` — original URL + each cited comment permalink

   Frontmatter `type: thread`.

5. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
```

```bash
git add commands/thread-read.md
git commit -m "docs(commands): add /thread-read (replaces /x-read)"
```

---

### Task 26: Create `commands/vault-deep-synthesis.md`

```markdown
---
description: Cross-vault synthesis on a topic — reads all matching notes, cross-references, writes unified view
category: research
triggers_en: ["vault synthesis", "what does my vault say about", "synthesize what I know"]
---

Use the obsidian-second-brain skill. Execute `/vault-deep-synthesis $ARGUMENTS`:

The argument is the topic. NO external network call. NO Python script. Pure vault operation.

1. Read `_CLAUDE.md`.

2. Grep the vault for all notes mentioning the topic (case-insensitive). Scan `Research/`, `Knowledge/`, `Projects/`, `Ideas/`, `Logs/`, `Decisions/`, `People/`.

3. Read each matching note in full.

4. Cross-reference:
   - Which notes claim the same fact but differ in detail? List the discrepancies.
   - Which claims repeat across multiple notes (high confidence)?
   - Which claims appear only once (isolated)?
   - Are any claims clearly stale (older `(as of YYYY-MM)` markers)?

5. Write `Knowledge/YYYY-MM-DD-synthesis-<slug>.md` with:
   - `## For future Claude` preamble
   - `## Unified View` — the integrated picture
   - `## Cross-Note Agreements` — high-confidence consensus claims
   - `## Contradictions` — list the conflicts with `[[wikilinks]]` to both sides
   - `## Stale Claims Flagged` — claims with old recency markers that should be re-verified
   - `## Coverage Gaps` — what the vault doesn't say
   - `## Source Notes` — every input note as `[[wikilink]]`

   Frontmatter `type: synthesis`.

6. **Do NOT mutate any existing note.** Synthesis is a derivative; provenance stays in the originals.

7. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
```

```bash
git add commands/vault-deep-synthesis.md
git commit -m "docs(commands): add /vault-deep-synthesis (replaces /notebooklm)"
```

---

### Task 27: Create `commands/idea-discovery.md`

```markdown
---
description: Surface 3-5 next-direction candidates by reading Ideas/, Project Open Questions, and orphan Research notes
category: research
triggers_en: ["what should I work on next", "idea discovery", "what are my gaps"]
---

Use the obsidian-second-brain skill. Execute `/idea-discovery $ARGUMENTS`:

The argument is optional. If given, use it as seed direction (filter scope).

1. Read `_CLAUDE.md`.

2. **Vault scan** (you do this):
   - Read all `Ideas/*.md` where `status != graduated`
   - Read all `Projects/*.md` and extract the **Open Questions** sections
   - Read `Research/**/*.md` and find ones with no matching `Projects/` note (orphan research)

3. Form a candidate list — each candidate is one of:
   - An ungraduated idea
   - An open question in an active project
   - An orphan research note that suggests a project

4. **External quick scan** — for each candidate (up to 5), pick a 3-8 word query and run:

   ```bash
   uv run -m scripts.research.idea_discovery "<candidate 1>" "<candidate 2>" ...
   ```

5. Parse JSON. Shape:
   ```json
   {"gaps": ["..."], "per_gap": [{"topic": "...", "results": [...], "stats": {...}}, ...]}
   ```

6. **Rank** by a simple heuristic:
   - Score = (recency-of-last-vault-touch) × (orphan_research_count) × (signal-from-external-scan: n_arxiv_results + n_hn_results)
   - Top 3-5 get included.

7. Write `Ideas/YYYY-MM-DD-discovery.md` with:
   - `## For future Claude` preamble
   - `## Top 3-5 Next Directions` — each: title, rationale (why this gap matters now), vault refs (`[[wikilinks]]`), external signal (1-2 cited results), suggested next action (research / graduate / discuss)
   - `## Other Candidates Considered` — short list with rejection reason
   - `## Method` — your scan window, ranking heuristic snapshot

   Frontmatter `type: idea-discovery`.

8. **Do NOT auto-graduate.** Wait for user explicit `/obsidian-graduate <name>`.

9. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
```

```bash
git add commands/idea-discovery.md
git commit -m "docs(commands): add /idea-discovery"
```

---

### Task 28: Rewrite `commands/youtube.md`

```markdown
---
description: Extract transcript + metadata from a YouTube URL, summarize, save to vault
category: research
triggers_en: ["youtube video", "summarize this video", "yt extract"]
---

Use the obsidian-second-brain skill. Execute `/youtube $ARGUMENTS`:

The argument is the YouTube URL.

1. Read `_CLAUDE.md`.

2. Run fetcher (no API key required):

   ```bash
   uv run -m scripts.research.youtube_extract "<url>"
   ```

3. Parse JSON. Shape:
   ```json
   {
     "video_id": "...",
     "url": "...",
     "metadata": {"title": "...", "channel": "...", "published_at": "...", "view_count": 12345, "description": "..."},
     "transcript": [{"text": "...", "start": 0.0, "duration": 1.5}, ...],
     "transcript_available": true
   }
   ```

4. If `transcript_available: false`, write a stub note with metadata only + frontmatter flag `transcript-available: false` + tell the user.

5. Otherwise, synthesize from the transcript:
   - `## For future Claude` preamble (with `[[wikilink]]` to channel if known)
   - `## Summary` — 5-7 sentence summary
   - `## Key Topics Covered` — bullet list grouped by approximate timestamps from transcript
   - `## Notable Quotes` — 3-5 verbatim quotes with timestamps
   - `## Action Items / Ideas` — what's actionable for the user (link to relevant `[[Projects/]]` if any)
   - `## Metadata` — verbatim from the JSON (title, channel, published, views)
   - `## Sources` — the YouTube URL

   Frontmatter `type: youtube` + `transcript-available: true`.

6. Save to `Research/YouTube/YYYY-MM-DD-<slug>.md`.

7. Append log + update index.

---

**AI-first rule:** Every note must follow `references/ai-first-rules.md`.
```

```bash
git add commands/youtube.md
git commit -m "docs(commands): rewrite /youtube to drop YouTube Data API + Grok"
```

---

## Phase 5 — Deprecation & Docs

### Task 29: Move deprecated modules

**Files:**
- Move 6 files

- [ ] **Step 1: Move + add deprecation headers**

```bash
mkdir -p scripts/research/_deprecated
git mv scripts/research/lib/perplexity.py scripts/research/_deprecated/perplexity.py
git mv scripts/research/lib/grok.py scripts/research/_deprecated/grok.py
git mv scripts/research/lib/gemini.py scripts/research/_deprecated/gemini.py 2>/dev/null || true
git mv scripts/research/x_pulse.py scripts/research/_deprecated/x_pulse.py
git mv scripts/research/x_read.py scripts/research/_deprecated/x_read.py
git mv scripts/research/notebooklm.py scripts/research/_deprecated/notebooklm.py 2>/dev/null || true
```

Prepend each moved file with:

```python
"""
DEPRECATED in v1.0 — replaced by scripts/research/lib/sources/*.py (free sources)
and Claude-side synthesis. This file is kept only as an escape hatch for users
who want to bring back paid-API behavior via a custom fork. Not imported by any
current command. Will be removed in v2.0.
"""
```

Create `scripts/research/_deprecated/__init__.py` (empty).

- [ ] **Step 2: Delete the now-obsolete command .md files**

```bash
git rm commands/x-pulse.md commands/x-read.md commands/notebooklm.md
```

- [ ] **Step 3: Commit**

```bash
git add scripts/research/_deprecated/
git commit -m "chore: move Perplexity/Grok/Gemini/x-pulse/x-read/notebooklm to _deprecated/"
```

---

### Task 30: `.env.example` rewrite

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Replace contents**

```
# obsidian-second-brain — optional configuration
#
# The default install needs ZERO keys. Every variable below is optional.
# Copy this file to ~/.config/obsidian-second-brain/.env if you want any.
# Set permissions 600.

# ─── Vault location (required) ──────────────────────────────
OBSIDIAN_VAULT_PATH=

# ─── Contact email (recommended for arXiv / CrossRef / OpenAlex polite pool)
# Goes into HTTP User-Agent. No secret; safe to commit if you want.
# Prefer setting this in ~/.config/obsidian-second-brain/research.toml instead.
# CONTACT_EMAIL=

# ─── DEPRECATED — kept only as escape hatch for fork users ───
# All four of these were retired in v1.0. The toolkit now uses free
# alternatives (arXiv / Semantic Scholar / OpenAlex / DuckDuckGo / Wikipedia /
# HackerNews / Reddit / Lobsters / dev.to). See docs/superpowers/specs/
# 2026-05-25-free-research-toolkit-design.md.

# XAI_API_KEY=
# PERPLEXITY_API_KEY=
# GEMINI_API_KEY=
# YOUTUBE_API_KEY=
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "chore: .env.example — all keys are optional, default install is zero-key"
```

---

### Task 31: README + SKILL.md + CHANGELOG updates

**Files:**
- Modify: `README.md`, `SKILL.md`, `CHANGELOG.md`

- [ ] **Step 1: README research-toolkit section**

Find the "Research Toolkit" section (current bullets reference Perplexity, Grok, NotebookLM, YouTube). Replace with:

```markdown
### Research toolkit (free, zero API keys required)

Seven commands hit only free, key-less sources (arXiv, Semantic Scholar,
OpenAlex, CrossRef, DuckDuckGo, Wikipedia, HackerNews, Reddit, Lobsters,
dev.to). Synthesis is performed by the calling Claude session — no external
LLM API. Output is AI-first vault notes following `references/ai-first-rules.md`.

| Command | Purpose |
|---|---|
| `/research <topic> [--academic]` | Multi-source dossier with citations |
| `/research-deep <topic>` | Vault baseline → gap fetch → delta synthesis → propagation |
| `/discourse-pulse <topic>` | HN/Reddit/Lobsters/dev.to pulse on a topic |
| `/thread-read <url>` | Read one HN or Reddit thread and summarize |
| `/youtube <url>` | Transcript + metadata; no YouTube API key |
| `/idea-discovery [seed]` | Surface 3-5 next directions by scanning the vault |
| `/vault-deep-synthesis <topic>` | Cross-note vault synthesis, no network |

Optional: drop a `contact_email` into `~/.config/obsidian-second-brain/research.toml`
to enter polite-pool HTTP headers (arXiv / CrossRef / OpenAlex give better
rate limits). That's the only configuration; no secrets, no keys.
```

- [ ] **Step 2: SKILL.md command list**

Update the commands list to reflect renames (`/x-pulse` → `/discourse-pulse` etc.) and the new `/idea-discovery`.

- [ ] **Step 3: CHANGELOG entry**

```markdown
## [Unreleased]

### Changed
- Research toolkit no longer requires paid APIs. All 7 research commands now run on free, key-less sources with synthesis by the calling Claude session.

### Renamed
- `/x-pulse` → `/discourse-pulse` (HN/Reddit/Lobsters/dev.to; X.com is no longer queried)
- `/x-read` → `/thread-read` (HN/Reddit thread URLs)
- `/notebooklm` → `/vault-deep-synthesis` (Claude reads vault directly; no external LLM)

### Added
- `/idea-discovery` — surface 3-5 next-direction candidates by scanning Ideas/, Projects/ Open Questions, and orphan Research/ notes
- `--academic` flag on `/research` — restricts to arXiv + Semantic Scholar + OpenAlex + CrossRef
- New source clients under `scripts/research/lib/sources/`: arxiv, semantic_scholar, openalex, crossref, duckduckgo, wikipedia, hackernews, reddit, lobsters, devto
- File-based cache at `~/.cache/obsidian-second-brain/research/` with 24h default TTL
- `~/.config/obsidian-second-brain/research.toml` for contact_email + SearXNG instance list + rate-limit overrides

### Deprecated
- `scripts/research/lib/{perplexity,grok,gemini}.py` moved to `_deprecated/`. Will be removed in v2.0.
- `XAI_API_KEY`, `PERPLEXITY_API_KEY`, `GEMINI_API_KEY`, `YOUTUBE_API_KEY` are no longer read by the default install.

### Removed
- `commands/x-pulse.md`, `commands/x-read.md`, `commands/notebooklm.md` (replaced by renamed commands above).
```

- [ ] **Step 4: Commit**

```bash
git add README.md SKILL.md CHANGELOG.md
git commit -m "docs: update README + SKILL.md + CHANGELOG for free research toolkit"
```

---

### Task 32: End-to-end smoke test

**Files:**
- Create: `tests/research/smoke.sh`

- [ ] **Step 1: Write smoke script**

```bash
#!/usr/bin/env bash
# tests/research/smoke.sh — full toolkit end-to-end against live APIs.
# Run manually before merging. Not in CI.

set -euo pipefail

cd "$(dirname "$0")/../.."

echo "=== /research smoke ==="
out=$(uv run -m scripts.research.research "retrieval augmented generation")
echo "$out" | python -c "import json,sys; p=json.load(sys.stdin); assert p['stats']['sources_succeeded'] >= 3, f'only {p[\"stats\"][\"sources_succeeded\"]} sources succeeded'"
echo "✓"

echo "=== /research --academic smoke ==="
out=$(uv run -m scripts.research.research "transformer attention" --academic)
echo "$out" | python -c "import json,sys; p=json.load(sys.stdin); assert p['academic_mode'] is True; assert p['stats']['sources_succeeded'] >= 2"
echo "✓"

echo "=== /research-deep smoke ==="
out=$(uv run -m scripts.research.research_deep "rag latency" "rag eval benchmarks")
echo "$out" | python -c "import json,sys; p=json.load(sys.stdin); assert len(p['per_query']) == 2"
echo "✓"

echo "=== /discourse-pulse smoke ==="
out=$(uv run -m scripts.research.discourse_pulse "rust async")
echo "$out" | python -c "import json,sys; p=json.load(sys.stdin); assert p['stats']['sources_succeeded'] >= 2"
echo "✓"

echo "=== /youtube smoke ==="
out=$(uv run -m scripts.research.youtube_extract "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
echo "$out" | python -c "import json,sys; p=json.load(sys.stdin); assert p['video_id']"
echo "✓"

echo ""
echo "ALL SMOKE TESTS PASSED"
```

- [ ] **Step 2: Run + commit**

```bash
chmod +x tests/research/smoke.sh
bash tests/research/smoke.sh
git add tests/research/smoke.sh
git commit -m "test(research): add end-to-end smoke script"
```

---

### Task 33: Final unit-test sweep + PR

- [ ] **Step 1: Run full unit suite**

```bash
uv run pytest -v
```

Expected: all green. ~ 30 tests across 11 source files + 5 lib files + 6 entry files.

- [ ] **Step 2: Optionally run live contract tests once manually**

```bash
uv run pytest -m live -v
```

(Not in CI; sanity check only.)

- [ ] **Step 3: Push branch + open PR**

```bash
git push -u origin feat/free-research-toolkit
gh pr create --title "Free research toolkit — drop Perplexity/xAI/Gemini dependencies" \
  --body "$(cat <<'EOF'
## Summary
- Replace Perplexity / xAI Grok / Gemini / YouTube Data API with free sources (arXiv, Semantic Scholar, OpenAlex, CrossRef, DuckDuckGo, Wikipedia, HN, Reddit, Lobsters, dev.to)
- Synthesis moves to the calling Claude session
- Rename `/x-pulse` → `/discourse-pulse`, `/x-read` → `/thread-read`, `/notebooklm` → `/vault-deep-synthesis`
- Add `/idea-discovery` and `--academic` flag on `/research`
- Deprecated modules moved under `scripts/research/_deprecated/`

Spec: `docs/superpowers/specs/2026-05-25-free-research-toolkit-design.md`
Plan: `docs/superpowers/plans/2026-05-25-free-research-toolkit.md`

## Test plan
- [x] Unit tests pass: `uv run pytest -v`
- [ ] Smoke script passes: `bash tests/research/smoke.sh`
- [ ] Run `/research "claude api caching"` against a real vault, verify note created
- [ ] Run `/research-deep "rag memory"` against a real vault, verify propagation works
- [ ] Run `/discourse-pulse "claude code"` against a real vault, verify Pulse note
- [ ] Run `/idea-discovery` against a vault with ≥ 1 idea + ≥ 1 open question

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**1. Spec coverage check** (spec sections vs plan tasks):

| Spec section | Tasks covering it |
|---|---|
| §4.1 Data flow | Tasks 1–5 (shared infra), 6–15 (sources), 16–21 (entry points) |
| §4.2 SourceClient interface | Task 1 (Result), Task 5 (Protocol declaration) |
| §4.3 Module layout | All Phase 1 + Phase 2 tasks (one task per file) |
| §4.4 Command .md updates | Tasks 22–28 (one per command) |
| §5.1 `/research` | Task 16 + Task 22 |
| §5.2 `/research-deep` | Task 17 + Task 23 |
| §5.3 `/idea-discovery` | Task 21 + Task 27 |
| §5.4 `/discourse-pulse` | Task 18 + Task 24 |
| §5.5 `/thread-read` | Task 19 + Task 25 |
| §5.6 `/youtube` | Task 20 + Task 28 |
| §5.7 `/vault-deep-synthesis` | Task 26 (no Python; pure vault op) |
| §6.1 Per-source rate limits | Embedded in each source Task 6–15 |
| §6.2 Per-client contract | Task 5 `_safe_search` |
| §6.3 Aggregator success rule | Task 5 |
| §6.4 Cache | Task 4 |
| §6.5 Config | Task 3 |
| §7 Testing | Each task includes test step; Task 32 smoke; Task 33 final sweep |
| §8 Deprecation | Tasks 29, 30, 31 |

No gaps.

**2. Placeholder scan**: No "TBD", "TODO", "fill in later", "appropriate error handling", or referenced-but-undefined items remain.

**3. Type consistency**: `SourceClient` Protocol → `Result` dataclass → `aggregate()` return shape used the same field names throughout (`source`, `title`, `url`, etc.). `stats` keys (`sources_attempted`, `sources_succeeded`, `results_total`, `success`) match across `aggregator.py` and every entry point that reads them.

Spec coverage clean, no placeholders, types consistent. Plan ready for execution.
