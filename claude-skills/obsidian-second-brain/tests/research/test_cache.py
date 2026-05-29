# tests/research/test_cache.py
import json
import time
from pathlib import Path
import pytest
from scripts.research.lib import cache


def test_cache_round_trip(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "deep learning", [{"title": "x"}])
    out = cache.get("arxiv", "deep learning", ttl_hours=24)
    assert out == [{"title": "x"}]


def test_cache_miss_returns_none(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    assert cache.get("arxiv", "nothing here", ttl_hours=24) is None


def test_cache_expires(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "deep learning", [{"title": "x"}])
    # tweak mtime to long ago
    f = next(tmp_path.glob("arxiv-*.json"))
    old = time.time() - 48 * 3600
    import os
    os.utime(f, (old, old))
    assert cache.get("arxiv", "deep learning", ttl_hours=24) is None


def test_normalized_query_key(tmp_path, monkeypatch):
    monkeypatch.setattr(cache, "_cache_dir", lambda: tmp_path)
    cache.put("arxiv", "  Deep   Learning  ", [{"title": "x"}])
    # same key after normalization
    assert cache.get("arxiv", "deep learning", ttl_hours=24) == [{"title": "x"}]
