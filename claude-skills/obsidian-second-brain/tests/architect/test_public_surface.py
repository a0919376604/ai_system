from pathlib import Path

from scripts.architect.api_surface import ApiSurface, CliCommand, Export, HttpRoute
from scripts.architect.public_surface import eligible_functions


def test_collects_from_each_source(tmp_path: Path):
    surf = ApiSurface(
        cli_commands=[CliCommand(name="foo", description="do foo", source="src/cli.py:42")],
        http_routes=[HttpRoute(method="GET", path="/x", handler="get_x", source="src/api.py:10")],
        exports=[Export(symbol="login", kind="named", source="src/auth/__init__.py:3")],
    )
    elig = eligible_functions(surf, module_paths={"cli": ["src/cli.py"], "api": ["src/api.py"], "auth": ["src/auth"]})
    keys = {(e.module_slug, e.name) for e in elig}
    assert ("cli", "foo") in keys
    assert ("api", "get_x") in keys
    assert ("auth", "login") in keys


def test_unmapped_function_skipped():
    surf = ApiSurface(cli_commands=[CliCommand(name="orphan", description="", source="elsewhere/orphan.py:1")])
    elig = eligible_functions(surf, module_paths={"cli": ["src/cli.py"]})
    assert elig == []


def test_deduplicates_same_symbol():
    surf = ApiSurface(
        exports=[
            Export(symbol="login", kind="named", source="src/auth/login.py:5"),
            Export(symbol="login", kind="all", source="src/auth/__init__.py:3"),
        ],
    )
    elig = eligible_functions(surf, module_paths={"auth": ["src/auth"]})
    assert len(elig) == 1
