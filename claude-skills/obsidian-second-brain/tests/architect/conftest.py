"""Shared test helpers for tests/architect/."""

from pathlib import Path

import pytest

FIXTURES_DIR = Path(__file__).parent / "fixtures"

collect_ignore_glob = ["fixtures/*/tests/*.py"]


@pytest.fixture
def single_lang_python() -> Path:
    return FIXTURES_DIR / "single-lang-python"


@pytest.fixture
def monorepo_pnpm() -> Path:
    return FIXTURES_DIR / "monorepo-pnpm"


@pytest.fixture
def polyglot_repo() -> Path:
    return FIXTURES_DIR / "polyglot"


@pytest.fixture
def docs_only_repo() -> Path:
    return FIXTURES_DIR / "docs-only"


@pytest.fixture
def flat_repo() -> Path:
    return FIXTURES_DIR / "flat-repo"
