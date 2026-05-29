from pathlib import Path

import responses

from scripts.research.lib.sources.lobsters import LobstersSource

FIXTURE = Path(__file__).parent / "fixtures" / "lobsters_response.json"


@responses.activate
def test_lobsters_parses():
    responses.add(
        responses.GET,
        "https://lobste.rs/search.json",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    out = LobstersSource().search("rust", n=3)
    assert len(out) >= 1
    assert out[0].source == "lobsters"
    assert out[0].title and out[0].url
