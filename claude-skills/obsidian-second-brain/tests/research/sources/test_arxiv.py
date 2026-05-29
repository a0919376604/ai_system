from pathlib import Path

import responses

from scripts.research.lib.sources.arxiv import ArxivSource

FIXTURE = Path(__file__).parent / "fixtures" / "arxiv_response.xml"


@responses.activate
def test_arxiv_search_returns_parsed_results():
    responses.add(
        responses.GET,
        "http://export.arxiv.org/api/query",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/atom+xml",
    )
    s = ArxivSource()
    results = s.search("retrieval augmented generation", n=3)
    assert s.name == "arxiv"
    assert 1 <= len(results) <= 3
    r = results[0]
    assert r.source == "arxiv"
    assert r.title
    assert r.url.startswith("http")
    assert r.abstract
    assert r.year is not None
    assert isinstance(r.authors, list) and len(r.authors) > 0


@responses.activate
def test_arxiv_http_failure_returns_empty():
    responses.add(
        responses.GET,
        "http://export.arxiv.org/api/query",
        status=500,
    )
    assert ArxivSource(retries=1).search("x", n=3) == []
