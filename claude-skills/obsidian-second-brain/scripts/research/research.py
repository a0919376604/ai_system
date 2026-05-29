"""/research <topic> [--academic] - emits aggregated source results as JSON.

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
    # rc 0 = ran cleanly and emitted JSON; the `success` field inside the JSON
    # tells the calling Claude how much to trust the aggregate (>=3 sources).
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
