from pathlib import Path

import responses

from scripts.research.lib.sources.semantic_scholar import SemanticScholarSource

FIXTURE = Path(__file__).parent / "fixtures" / "s2_response.json"


@responses.activate
def test_s2_search_parses_results():
    responses.add(
        responses.GET,
        "https://api.semanticscholar.org/graph/v1/paper/search",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    s = SemanticScholarSource()
    out = s.search("rag", n=3)
    assert s.name == "semantic_scholar"
    assert len(out) >= 1
    r = out[0]
    assert r.title
    assert r.url.startswith("http")
    assert isinstance(r.authors, list)


@responses.activate
def test_s2_429_returns_empty():
    responses.add(
        responses.GET,
        "https://api.semanticscholar.org/graph/v1/paper/search",
        status=429,
    )
    assert SemanticScholarSource(retries=1).search("x", n=3) == []
