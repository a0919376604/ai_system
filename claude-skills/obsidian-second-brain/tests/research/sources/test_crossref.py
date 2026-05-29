from pathlib import Path

import responses

from scripts.research.lib.sources.crossref import CrossRefSource

FIXTURE = Path(__file__).parent / "fixtures" / "crossref_response.json"


@responses.activate
def test_crossref_parses():
    responses.add(
        responses.GET,
        "https://api.crossref.org/works",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    out = CrossRefSource().search("retrieval augmented", n=3)
    assert len(out) >= 1
    assert out[0].title and out[0].url and out[0].source == "crossref"
