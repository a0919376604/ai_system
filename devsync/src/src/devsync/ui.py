"""Rich-based table and prompt helpers."""

from __future__ import annotations

from io import StringIO

from rich.console import Console
from rich.table import Table


def format_doctor_table(*, daemon_ok: bool, server_rows: list[dict]) -> str:
    """Render the doctor health-check table to a string."""
    buf = StringIO()
    console = Console(file=buf, force_terminal=False, width=100)

    daemon_line = "[green]✓[/green] running" if daemon_ok else "[red]✗[/red] NOT RUNNING"
    console.print(f"Mutagen daemon: {daemon_line}")

    table = Table(title="Servers", show_lines=False)
    table.add_column("Name")
    table.add_column("Host")
    table.add_column("Status")
    table.add_column("Detail")

    for row in server_rows:
        status = "[green]reachable[/green]" if row["reachable"] else "[red]unreachable[/red]"
        table.add_row(row["name"], row["host"], status, row["detail"])

    console.print(table)
    return buf.getvalue()


def format_ls_table(sessions: list[dict]) -> str:
    """Render `devsync ls` table."""
    buf = StringIO()
    console = Console(file=buf, force_terminal=False, width=140)

    if not sessions:
        console.print("[dim]No active sessions.[/dim]")
        return buf.getvalue()

    table = Table(show_lines=False)
    table.add_column("Name", overflow="fold")
    table.add_column("Server")
    table.add_column("Status")
    table.add_column("Staged")
    table.add_column("Local", overflow="fold")
    table.add_column("Remote", overflow="fold")

    for s in sessions:
        labels = s.get("labels", {})
        alpha = s.get("alpha", {}) or {}
        # mutagen emits endpoint fields flat in v0.18 (`alpha.path`); older/forward
        # versions may nest them under `alpha.url`. Accept either shape.
        alpha_url = alpha.get("url", {}) or {}
        alpha_path = alpha_url.get("path") or alpha.get("path", "?")
        beta = s.get("beta", {}) or {}
        beta_url = beta.get("url", {}) or {}
        beta_host = beta_url.get("host") or beta.get("host", "?")
        beta_path = beta_url.get("path") or beta.get("path", "?")
        table.add_row(
            s.get("name", "?"),
            labels.get("server", "?"),
            s.get("status", "?"),
            str(s.get("stagedFiles", 0)),
            alpha_path,
            f"{beta_host}:{beta_path}",
        )

    console.print(table)
    return buf.getvalue()
