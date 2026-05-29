"""/youtube <url> - pulls transcript via youtube-transcript-api + scrapes
minimal metadata from the page HTML. No YouTube Data API key required.
"""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import parse_qs, urlparse

from .lib import http
from .lib.result import encode_results


def _video_id(url: str) -> str | None:
    parsed = urlparse(url)
    if "youtu.be" in parsed.netloc:
        return parsed.path.strip("/")
    qs = parse_qs(parsed.query)
    if "v" in qs:
        return qs["v"][0]
    return None


def _scrape_metadata(video_id: str) -> dict:
    sess = http.get_session()
    sess.headers.update({"User-Agent": "Mozilla/5.0"})
    r = sess.get(f"https://www.youtube.com/watch?v={video_id}", timeout=15)
    if r.status_code != 200:
        return {}
    html = r.text
    title = _grab(html, r'<meta name="title" content="([^"]+)"')
    channel = _grab(html, r'"ownerChannelName":"([^"]+)"')
    published = _grab(html, r'"publishDate":"([^"]+)"')
    views = _grab(html, r'"viewCount":"(\d+)"')
    description = _grab(html, r'"shortDescription":"([^"]*)"')
    return {
        "title": title,
        "channel": channel,
        "published_at": published,
        "view_count": int(views) if views else None,
        "description": description,
    }


def _grab(text: str, pattern: str) -> str | None:
    m = re.search(pattern, text)
    return m.group(1) if m else None


def _fetch_transcript(video_id: str) -> list[dict]:
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        return YouTubeTranscriptApi.get_transcript(video_id)
    except Exception:
        return []


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /youtube <url>", file=sys.stderr)
        return 2

    url = argv[1].strip()
    vid = _video_id(url)
    if not vid:
        print(f"Could not extract video ID from URL: {url}", file=sys.stderr)
        return 2

    metadata = _scrape_metadata(vid)
    transcript = _fetch_transcript(vid)
    payload = {
        "video_id": vid,
        "url": url,
        "metadata": metadata,
        "transcript": transcript,
        "transcript_available": bool(transcript),
    }
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
