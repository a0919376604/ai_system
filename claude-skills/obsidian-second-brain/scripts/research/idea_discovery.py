"""/idea-discovery - quick scan for each gap topic Claude identified.

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
