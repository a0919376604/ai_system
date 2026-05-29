import re
from pathlib import Path

import responses

from scripts.research.lib.sources.wikipedia import WikipediaSource

FIX = Path(__file__).parent / "fixtures"


@responses.activate
def test_wikipedia_returns_results():
    responses.add(
        responses.GET,
        "https://en.wikipedia.org/w/api.php",
        body=(FIX / "wiki_search.json").read_text(),
        status=200,
    )
    responses.add(
        responses.GET,
        re.compile(r"https://en\.wikipedia\.org/api/rest_v1/page/summary/.+"),
        body=(FIX / "wiki_summary.json").read_text(),
        status=200,
    )
    out = WikipediaSource().search("transformer architecture", n=1)
    assert len(out) >= 1
    assert out[0].source == "wikipedia"
    assert out[0].title and out[0].snippet
