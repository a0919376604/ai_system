"""/research-deep - Phase-3 gap fetcher.

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
