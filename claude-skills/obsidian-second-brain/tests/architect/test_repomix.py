from pathlib import Path
from unittest.mock import patch

from scripts.architect.repomix import is_available, pack_module, pack_repo_metadata


def test_is_available_detects_repomix():
    # Just exercises the function. The actual return depends on whether
    # repomix is installed in the test environment. Should not raise.
    result = is_available()
    assert isinstance(result, bool)


def test_pack_module_returns_string_corpus(single_lang_python: Path):
    # Fall back to Python implementation if repomix not installed.
    corpus = pack_module(single_lang_python, include=["src/"])
    assert "src/auth/login.py" in corpus
    assert "def authenticate" in corpus


def test_pack_repo_metadata_returns_token_counts(single_lang_python: Path):
    meta = pack_repo_metadata(single_lang_python)
    # Shape: {"files": [{"path": ..., "tokens": N}], "total_tokens": N}
    assert "files" in meta
    assert "total_tokens" in meta
    assert meta["total_tokens"] > 0
    assert any(f["path"] == "src/auth/login.py" for f in meta["files"])
