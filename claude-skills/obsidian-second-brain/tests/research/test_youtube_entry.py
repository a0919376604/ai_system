import json
from pathlib import Path
from unittest.mock import patch

import responses
from scripts.research import youtube_extract as yt


FIXTURE = Path(__file__).parent / "fixtures" / "youtube_page.html"


@responses.activate
def test_youtube_extract_metadata(capsys):
    responses.add(responses.GET, "https://www.youtube.com/watch",
                  body=FIXTURE.read_text(), status=200, content_type="text/html")
    with patch.object(yt, "_fetch_transcript", return_value=[{"text": "hello", "start": 0.0}]):
        rc = yt.main(["youtube_extract", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["video_id"] == "dQw4w9WgXcQ"
    assert payload["transcript"]
