from pathlib import Path

import responses

from scripts.research.lib.sources.duckduckgo import DuckDuckGoSource

FIX = Path(__file__).parent / "fixtures"


@responses.activate
def test_ddg_parses_html():
    responses.add(
        responses.GET,
        "https://html.duckduckgo.com/html/",
        body=(FIX / "ddg_html.html").read_text(),
        status=200,
        content_type="text/html",
    )
    out = DuckDuckGoSource().search("python rag", n=3)
    assert len(out) >= 1
    assert out[0].source == "duckduckgo"
    assert out[0].url.startswith("http")


@responses.activate
def test_ddg_falls_back_to_searxng_on_block():
    responses.add(
        responses.GET,
        "https://html.duckduckgo.com/html/",
        body="captcha",
        status=200,
        content_type="text/html",
    )
    responses.add(
        responses.GET,
        "https://searx.be/search",
        body=(FIX / "searxng_response.json").read_text(),
        status=200,
        content_type="application/json",
    )
    out = DuckDuckGoSource(searxng_instances=["https://searx.be"]).search("python rag", n=3)
    assert out  # got something from searxng
