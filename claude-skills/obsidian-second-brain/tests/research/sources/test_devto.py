from pathlib import Path

import responses

from scripts.research.lib.sources.devto import DevToSource

FIXTURE = Path(__file__).parent / "fixtures" / "devto_response.json"


@responses.activate
def test_devto_parses():
    responses.add(
        responses.GET,
        "https://dev.to/api/articles",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    out = DevToSource().search("python", n=3)
    assert len(out) >= 1
    assert out[0].source == "devto"
    assert out[0].title and out[0].url
