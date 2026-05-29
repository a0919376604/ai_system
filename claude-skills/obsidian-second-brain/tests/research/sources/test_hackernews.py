from pathlib import Path

import responses

from scripts.research.lib.sources.hackernews import HackerNewsSource

FIXTURE = Path(__file__).parent / "fixtures" / "hn_response.json"


@responses.activate
def test_hn_parses():
    responses.add(
        responses.GET,
        "https://hn.algolia.com/api/v1/search",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    out = HackerNewsSource().search("claude code", n=3)
    assert len(out) >= 1
    assert out[0].source == "hackernews"
    assert out[0].title and out[0].url
    assert out[0].points is not None
