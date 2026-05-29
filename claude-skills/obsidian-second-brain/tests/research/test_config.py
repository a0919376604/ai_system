import os
from pathlib import Path
import pytest
from scripts.research.lib import config


def test_load_config_missing_file_returns_defaults(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "_config_path", lambda: tmp_path / "nope.toml")
    config._CACHE = None
    cfg = config.load()
    assert cfg.contact_email is None
    assert cfg.searxng_instances
    assert cfg.cache_ttl_hours == 24


def test_load_config_reads_toml(tmp_path, monkeypatch):
    f = tmp_path / "research.toml"
    f.write_text(
        'contact_email = "me@example.com"\n'
        '[searxng]\n'
        'instances = ["https://searx.example"]\n'
        '[cache]\n'
        'ttl_hours = 6\n'
    )
    monkeypatch.setattr(config, "_config_path", lambda: f)
    config._CACHE = None
    cfg = config.load()
    assert cfg.contact_email == "me@example.com"
    assert cfg.searxng_instances == ["https://searx.example"]
    assert cfg.cache_ttl_hours == 6


def test_get_contact_email_returns_loaded(tmp_path, monkeypatch):
    f = tmp_path / "research.toml"
    f.write_text('contact_email = "x@y.z"\n')
    monkeypatch.setattr(config, "_config_path", lambda: f)
    config._CACHE = None
    assert config.get_contact_email() == "x@y.z"
