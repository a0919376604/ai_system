from pathlib import Path

from scripts.architect.todos import aggregate_todos


def _setup_repo(tmp_path: Path):
    (tmp_path / "src" / "auth").mkdir(parents=True)
    (tmp_path / "src" / "api").mkdir(parents=True)
    (tmp_path / "src" / "auth" / "login.py").write_text(
        "def login():\n"
        "    # TODO: rate limit this\n"
        "    # TODO(future): switch to OAuth2\n"
        "    # FIXME: handle empty password\n"
        "    pass\n"
    )
    (tmp_path / "src" / "api" / "routes.py").write_text(
        "# TODO: pagination\n"
        "# TODO(idea): GraphQL endpoint\n"
        "# TODO(roadmap): rate limiting at gateway level\n"
    )


def test_collects_todos_with_path_and_line(tmp_path: Path):
    _setup_repo(tmp_path)
    todos = aggregate_todos(tmp_path, module_paths={"auth": ["src/auth"], "api": ["src/api"]})
    auth = todos["auth"]
    assert any(t.text == "rate limit this" and t.label is None for t in auth)
    assert any(t.label == "future" for t in auth)
    assert any(t.kind == "FIXME" for t in auth)


def test_groups_by_module(tmp_path: Path):
    _setup_repo(tmp_path)
    todos = aggregate_todos(tmp_path, module_paths={"auth": ["src/auth"], "api": ["src/api"]})
    assert set(todos.keys()) == {"auth", "api"}
    assert len(todos["api"]) == 3


def test_unattributed_files_under_other(tmp_path: Path):
    (tmp_path / "stray.py").write_text("# TODO: this is not in any module\n")
    todos = aggregate_todos(tmp_path, module_paths={"foo": ["src/foo"]})
    assert "_unmapped" in todos
    assert todos["_unmapped"][0].text == "this is not in any module"


def test_skips_binary_and_oversize_files(tmp_path: Path):
    (tmp_path / "big.bin").write_bytes(b"\x00" * 200)
    todos = aggregate_todos(tmp_path, module_paths={})
    assert "_unmapped" not in todos or todos["_unmapped"] == []
