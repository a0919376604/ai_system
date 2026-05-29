from pathlib import Path

from scripts.architect.stack import detect_stack


def test_python_pyproject(tmp_path: Path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\n'
        'name = "x"\n'
        'dependencies = ["fastapi>=0.110", "sqlalchemy>=2.0"]\n'
        '[tool.pytest.ini_options]\n'
        'testpaths = ["tests"]\n'
    )
    stack = detect_stack(tmp_path)
    assert stack["primary-language"] == "Python"
    assert "FastAPI" in stack["frameworks"]
    assert "SQLAlchemy" in stack["frameworks"]
    assert stack["test"] == "pytest"


def test_typescript_nextjs(tmp_path: Path):
    (tmp_path / "package.json").write_text(
        '{"name":"x","dependencies":{"next":"14.0.0","react":"18.0.0",'
        '"@prisma/client":"5.0.0"},"devDependencies":{"vitest":"1.0.0"}}'
    )
    (tmp_path / "next.config.js").write_text("module.exports = {};\n")
    stack = detect_stack(tmp_path)
    assert stack["primary-language"] == "TypeScript or JavaScript"
    assert "Next.js" in stack["frameworks"]
    assert "Prisma" in stack["frameworks"]
    assert stack["test"] == "vitest"


def test_returns_empty_when_no_config(tmp_path: Path):
    assert detect_stack(tmp_path) == {}


def test_unrecognized_deps_are_dropped(tmp_path: Path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "x"\ndependencies = ["some-random-lib"]\n'
    )
    stack = detect_stack(tmp_path)
    # primary-language is keyed off pyproject existence, so still present.
    assert stack.get("primary-language") == "Python"
    # No frameworks line in output because nothing recognized.
    assert "frameworks" not in stack or stack["frameworks"] == []


def test_monorepo_backend_python_frontend_js(tmp_path: Path):
    """Real-world: no root pyproject, but backend/ has Python and frontend/ has JS deps."""
    (tmp_path / "backend").mkdir()
    (tmp_path / "backend" / "pyproject.toml").write_text(
        '[project]\nname = "back"\ndependencies = ["fastapi>=0.110"]\n'
    )
    (tmp_path / "frontend").mkdir()
    (tmp_path / "frontend" / "package.json").write_text(
        '{"name":"front","dependencies":{"react":"19.0.0"},"devDependencies":{"vite":"7.0.0"}}'
    )
    stack = detect_stack(tmp_path)
    # Primary language reflects mixed monorepo.
    assert stack["primary-language"] in ("Python + TypeScript or JavaScript", "TypeScript or JavaScript + Python")
    # Frameworks merged from both subdirs.
    assert "FastAPI" in stack["frameworks"]
    assert "React" in stack["frameworks"]
    # Per-subdir breakdown for traceability.
    assert stack["modules"]["backend"]["language"] == "Python"
    assert stack["modules"]["frontend"]["language"] == "TypeScript or JavaScript"


def test_monorepo_only_one_subdir_has_metadata(tmp_path: Path):
    """Only frontend/package.json — backend has nothing detectable."""
    (tmp_path / "backend").mkdir()
    (tmp_path / "frontend").mkdir()
    (tmp_path / "frontend" / "package.json").write_text(
        '{"name":"front","dependencies":{"react":"19.0.0"}}'
    )
    stack = detect_stack(tmp_path)
    assert stack["primary-language"] == "TypeScript or JavaScript"
    assert "React" in stack["frameworks"]
    assert "frontend" in stack["modules"]
    assert "backend" not in stack["modules"]


def test_monorepo_does_not_descend_into_node_modules(tmp_path: Path):
    """Heuristic safety: probe known monorepo dir names only, not node_modules etc."""
    (tmp_path / "node_modules").mkdir()
    (tmp_path / "node_modules" / "package.json").write_text(
        '{"name":"dep","dependencies":{"react":"99"}}'
    )
    stack = detect_stack(tmp_path)
    # node_modules ignored -> no language detected.
    assert stack == {} or "modules" not in stack
