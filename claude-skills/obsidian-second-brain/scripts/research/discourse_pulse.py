"""/discourse-pulse <topic> - pulls discourse from HN, Reddit, Lobsters, dev.to."""

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
