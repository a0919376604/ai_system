from pathlib import Path

import responses

from scripts.research.lib.sources.openalex import OpenAlexSource

FIXTURE = Path(__file__).parent / "fixtures" / "openalex_response.json"


@responses.activate
def test_openalex_parses_results():
    responses.add(
        responses.GET,
        "https://api.openalex.org/works",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    s = OpenAlexSource()
    out = s.search("retrieval augmented", n=3)
    assert s.name == "openalex"
    assert len(out) >= 1
    assert out[0].title and out[0].url
