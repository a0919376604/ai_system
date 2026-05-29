from scripts.architect.api_surface_render import (
    render_cli_table, render_http_table, render_exports_table, render_env_table,
)


def test_cli_table_en():
    rows = [{"name": "foo", "description": "do foo", "source": "src/cli.py:1", "module": "cli"}]
    table = render_cli_table(rows, lang="en")
    assert "| Command | Description | Source | Module |" in table
    assert "| `foo` | do foo | `src/cli.py:1` | [[modules/cli]] |" in table


def test_cli_table_zh():
    rows = [{"name": "foo", "description": "做 foo", "source": "src/cli.py:1", "module": "cli"}]
    table = render_cli_table(rows, lang="zh-TW")
    assert "| 指令 | 說明 | 來源 | 模組 |" in table


def test_empty_table_returns_empty_string():
    assert render_cli_table([], lang="en") == ""
    assert render_http_table([], lang="en") == ""


def test_http_table():
    rows = [{"method": "GET", "path": "/x", "handler": "get_x", "source": "src/api.py:5", "module": "api"}]
    table = render_http_table(rows, lang="en")
    assert "| Method | Path | Handler | Module |" in table
    assert "GET" in table and "`/x`" in table


def test_env_table_marks_required():
    rows = [
        {"name": "API_KEY", "required": True, "default": None, "source": "src/c.py:1", "used_by": "api"},
        {"name": "DB_URL", "required": False, "default": "sqlite://", "source": "src/c.py:2", "used_by": "db"},
    ]
    table = render_env_table(rows, lang="en")
    assert "API_KEY" in table and "yes" in table
    assert "DB_URL" in table and "sqlite://" in table


def test_render_interface_overview_groups_routes_by_prefix():
    """v3 — HTTP routes are bucketed by URL prefix, not listed one-by-one."""
    from scripts.architect.api_surface_render import render_interface_overview
    rows = [
        {"method": "GET", "path": "/auth/me", "handler": "me", "source": "src/api/auth.py:10"},
        {"method": "POST", "path": "/auth/login", "handler": "login", "source": "src/api/auth.py:20"},
        {"method": "GET", "path": "/admin/users", "handler": "list_users", "source": "src/api/admin.py:5"},
        {"method": "GET", "path": "/admin/metrics", "handler": "metrics", "source": "src/api/admin.py:15"},
        {"method": "POST", "path": "/chat/send", "handler": "send", "source": "src/api/chat.py:1"},
    ]
    overview = render_interface_overview(rows, lang="en")
    # Should mention total + grouping
    assert "5 routes" in overview or "Total: 5" in overview
    # Each prefix group cited as a bucket
    assert "/auth" in overview
    assert "/admin" in overview
    assert "/chat" in overview
    # Should NOT dump full table
    assert "list_users" not in overview or overview.count("/admin") < 5


def test_render_env_overview_groups_by_prefix():
    from scripts.architect.api_surface_render import render_env_overview
    rows = [
        {"name": "REDIS_HOST", "required": True, "default": None, "source": "x"},
        {"name": "REDIS_PORT", "required": True, "default": "6379", "source": "x"},
        {"name": "REDIS_PASSWORD", "required": False, "default": None, "source": "x"},
        {"name": "OPENAI_API_KEY", "required": True, "default": None, "source": "x"},
        {"name": "ADMIN_PASSWORD_HASH", "required": False, "default": None, "source": "x"},
    ]
    overview = render_env_overview(rows, lang="en")
    assert "5" in overview  # total count
    # Grouped by prefix (REDIS_*, OPENAI_*, ADMIN_*)
    assert "REDIS" in overview
    assert "OPENAI" in overview
    assert "ADMIN" in overview


def test_render_interface_overview_empty():
    from scripts.architect.api_surface_render import render_interface_overview
    assert render_interface_overview([], lang="en") == ""
