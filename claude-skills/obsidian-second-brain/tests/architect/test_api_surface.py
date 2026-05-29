from pathlib import Path

from scripts.architect.api_surface import detect_api_surface


def test_python_argparse_cli(tmp_path: Path):
    (tmp_path / "cli.py").write_text(
        "import argparse\n"
        "p = argparse.ArgumentParser()\n"
        "sub = p.add_subparsers()\n"
        "foo = sub.add_parser('foo', help='do foo')\n"
        "bar = sub.add_parser('bar', help='do bar')\n"
    )
    surf = detect_api_surface(tmp_path)
    cmds = {c.name for c in surf.cli_commands}
    assert "foo" in cmds
    assert "bar" in cmds


def test_fastapi_routes(tmp_path: Path):
    (tmp_path / "routes.py").write_text(
        "from fastapi import FastAPI\n"
        "app = FastAPI()\n"
        "@app.get('/items/{id}')\n"
        "def get_item(id: int): ...\n"
        "@app.post('/items')\n"
        "def create_item(): ...\n"
    )
    surf = detect_api_surface(tmp_path)
    assert any(r.method == "GET" and r.path == "/items/{id}" for r in surf.http_routes)
    assert any(r.method == "POST" and r.path == "/items" for r in surf.http_routes)


def test_python_all_exports(tmp_path: Path):
    (tmp_path / "pkg").mkdir()
    (tmp_path / "pkg" / "__init__.py").write_text(
        '__all__ = ["login", "logout"]\n'
        'def login(): pass\n'
        'def logout(): pass\n'
        'def _internal(): pass\n'
    )
    surf = detect_api_surface(tmp_path)
    names = {e.symbol for e in surf.exports}
    assert "login" in names
    assert "logout" in names
    assert "_internal" not in names


def test_env_var_detection_python(tmp_path: Path):
    (tmp_path / "config.py").write_text(
        "import os\n"
        "DB_URL = os.getenv('DATABASE_URL', 'sqlite:///dev.db')\n"
        "API_KEY = os.environ['API_KEY']\n"
    )
    surf = detect_api_surface(tmp_path)
    vars_seen = {v.name for v in surf.env_vars}
    assert "DATABASE_URL" in vars_seen
    assert "API_KEY" in vars_seen
    db = next(v for v in surf.env_vars if v.name == "DATABASE_URL")
    assert db.default == "sqlite:///dev.db"


def test_empty_project_returns_detection_status_none(tmp_path: Path):
    surf = detect_api_surface(tmp_path)
    assert surf.detection_status == "none"
    assert surf.cli_commands == []
    assert surf.http_routes == []


def test_excludes_venv_node_modules_dist_etc(tmp_path: Path):
    """Vendored deps and build artefacts must not pollute the surface."""
    # Real source file with one route.
    (tmp_path / "app.py").write_text(
        "from fastapi import FastAPI\napp = FastAPI()\n@app.get('/real')\ndef real(): ...\n"
    )
    # Should be ignored — .venv (Python virtualenv).
    (tmp_path / ".venv" / "lib" / "x").mkdir(parents=True)
    (tmp_path / ".venv" / "lib" / "x" / "__init__.py").write_text(
        '__all__ = ["from_venv"]\ndef from_venv(): pass\n'
    )
    # Should be ignored — dist (build artefact).
    (tmp_path / "dist").mkdir()
    (tmp_path / "dist" / "out.py").write_text(
        "from fastapi import FastAPI\napp = FastAPI()\n@app.post('/from-dist')\ndef bad(): ...\n"
    )
    # Should be ignored — __pycache__.
    (tmp_path / "__pycache__").mkdir()
    (tmp_path / "__pycache__" / "junk.py").write_text('__all__ = ["from_cache"]\n')
    surf = detect_api_surface(tmp_path)
    paths = [r.path for r in surf.http_routes]
    assert "/real" in paths
    assert "/from-dist" not in paths
    names = [e.symbol for e in surf.exports]
    assert "from_venv" not in names
    assert "from_cache" not in names


def test_fastapi_apirouter_prefix_prepended(tmp_path: Path):
    """When APIRouter is declared with prefix=, decorator paths are joined.

    Repro from langlive-line-oa: workspace.py has
        router = APIRouter(prefix="/api/v1/workspace")
        @router.post("/reply-images")
    The full mounted path is /api/v1/workspace/reply-images — scanner must
    capture that, not the bare /reply-images.
    """
    (tmp_path / "ws.py").write_text(
        "from fastapi import APIRouter\n"
        'router = APIRouter(prefix="/api/v1/workspace", tags=["workspace"])\n'
        "\n"
        "@router.post('/reply-images')\n"
        "def reply_images(): ...\n"
        "\n"
        "@router.get('/users/{user_id}/tickets')\n"
        "def tickets(): ...\n"
    )
    from scripts.architect.api_surface import detect_api_surface

    surf = detect_api_surface(tmp_path)
    paths = [r.path for r in surf.http_routes]
    assert "/api/v1/workspace/reply-images" in paths, (
        f"router prefix not joined; got {paths}"
    )
    assert "/api/v1/workspace/users/{user_id}/tickets" in paths


def test_fastapi_apirouter_no_prefix_passes_through(tmp_path: Path):
    """When APIRouter has no prefix kwarg, decorator paths stay verbatim."""
    (tmp_path / "ws.py").write_text(
        "from fastapi import APIRouter\n"
        'router = APIRouter(tags=["misc"])\n'
        "\n"
        "@router.get('/health')\n"
        "def health(): ...\n"
    )
    from scripts.architect.api_surface import detect_api_surface

    surf = detect_api_surface(tmp_path)
    paths = [r.path for r in surf.http_routes]
    assert "/health" in paths


def test_fastapi_app_decorator_no_prefix_lookup(tmp_path: Path):
    """`@app.get(...)` decorators don't go through APIRouter prefix lookup.

    Some files use the bare FastAPI app instance (`app = FastAPI()`) directly.
    Those routes should be captured verbatim with no spurious prefix join.
    """
    (tmp_path / "main.py").write_text(
        "from fastapi import FastAPI\n"
        "app = FastAPI()\n"
        "\n"
        "@app.get('/health')\n"
        "def health(): ...\n"
    )
    from scripts.architect.api_surface import detect_api_surface

    surf = detect_api_surface(tmp_path)
    paths = [r.path for r in surf.http_routes]
    assert "/health" in paths
