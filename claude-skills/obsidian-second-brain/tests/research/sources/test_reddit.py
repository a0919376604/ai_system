from pathlib import Path
from unittest.mock import patch

import responses

from scripts.research.lib.sources.reddit import RedditSource

FIXTURE = Path(__file__).parent / "fixtures" / "reddit_response.json"


@responses.activate
def test_reddit_parses():
    responses.add(
        responses.GET,
        "https://www.reddit.com/search.json",
        body=FIXTURE.read_text(),
        status=200,
        content_type="application/json",
    )
    with patch("scripts.research.lib.sources.reddit.time.sleep"):
        out = RedditSource().search("langchain", n=3)
    assert len(out) >= 1
    assert out[0].source == "reddit"
    assert out[0].url.startswith("https://www.reddit.com")
