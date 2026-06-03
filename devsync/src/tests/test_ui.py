from devsync.ui import format_doctor_table


def test_doctor_table_renders_4_servers():
    rows = [
        {"name": "dl01", "host": "dl01", "reachable": True, "detail": "ok"},
        {"name": "dl02", "host": "dl02", "reachable": True, "detail": "ok"},
        {"name": "dl03", "host": "dl03", "reachable": False, "detail": "timeout"},
        {"name": "dl04", "host": "dl04", "reachable": True, "detail": "ok"},
    ]
    out = format_doctor_table(daemon_ok=True, server_rows=rows)
    assert "dl01" in out
    assert "dl03" in out
    assert "timeout" in out
