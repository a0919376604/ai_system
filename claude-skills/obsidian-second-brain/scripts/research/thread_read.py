"""/thread-read <url> - fetches a single thread (HN, Reddit) and emits JSON."""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse

from .lib import http
from .lib.result import encode_results


def _is_hn(url: str) -> bool:
    return "news.ycombinator.com" in url


def _is_reddit(url: str) -> bool:
    return "reddit.com" in url


def _fetch_hn(url: str) -> dict:
    item_id = _hn_item_id(url)
    if not item_id:
        return {"error": "could not extract HN item id"}
    sess = http.get_session()
    r = sess.get(f"https://hn.algolia.com/api/v1/items/{item_id}", timeout=15)
    if r.status_code != 200:
        return {"error": f"HN api status {r.status_code}"}
    return r.json()


def _hn_item_id(url: str) -> str | None:
    m = re.search(r"id=(\d+)", url)
    return m.group(1) if m else None


def _fetch_reddit(url: str) -> dict:
    sess = http.get_session()
    json_url = url.rstrip("/") + ".json"
    r = sess.get(json_url, timeout=15)
    if r.status_code != 200:
        return {"error": f"Reddit status {r.status_code}"}
    return r.json()


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        print("Usage: /thread-read <url>", file=sys.stderr)
        return 2

    url = argv[1].strip()
    if _is_hn(url):
        data = _fetch_hn(url)
        host = "hackernews"
    elif _is_reddit(url):
        data = _fetch_reddit(url)
        host = "reddit"
    else:
        print(f"Unsupported host: {urlparse(url).netloc}", file=sys.stderr)
        return 2

    payload = {"url": url, "host": host, "data": data}
    json.dump(payload, sys.stdout, default=encode_results, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
