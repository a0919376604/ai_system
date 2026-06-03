"""Typer CLI entry point. Commands are implemented across later tasks."""

from __future__ import annotations

import fnmatch
import os
import time
from pathlib import Path

import typer

from devsync import __version__
from devsync.config import load_global_config, load_repo_config, resolve_effective_config
from devsync.errors import (
    DevsyncError,
    NoSuchRepo,
    ServerUnreachable,
    SessionAlreadyExists,
)
from devsync.mutagen import (
    daemon_status,
    ensure_daemon_running,
    list_managed_sessions,
    sync_create,
    sync_flush,
    sync_monitor_argv,
    sync_status_raw,
    sync_terminate,
    sync_terminate_all_managed,
    sync_terminate_by_repo,
)
from devsync.repo import resolve_repo
from devsync.server import ensure_remote_dir, probe_ssh
from devsync.session import SessionSpec
from devsync.ui import format_doctor_table, format_ls_table

app = typer.Typer(
    name="devsync",
    help="Sync-and-SSH wrapper around Mutagen for internal dev servers.",
    no_args_is_help=True,
    add_completion=False,
)

LARGE_FILE_WARN_THRESHOLD = 100 * 1024 * 1024  # 100 MB total
COUNTDOWN_SECONDS = 3


def scan_repo_for_large_files(
    repo_path: Path, top_n: int, ignore_globs: list[str]
) -> tuple[int, list[tuple[Path, int]]]:
    """Return (total_bytes, top_n largest files) after ignore filtering.

    Filters out .git/, .venv/, node_modules/ regardless of globs to keep the scan fast.
    """
    HARD_SKIP = {".git", ".venv", "node_modules", "__pycache__"}
    total = 0
    sizes: list[tuple[Path, int]] = []
    for p in repo_path.rglob("*"):
        if not p.is_file() or p.is_symlink():
            continue
        # Hard skip
        if any(part in HARD_SKIP for part in p.relative_to(repo_path).parts):
            continue
        # Ignore globs
        rel = p.relative_to(repo_path).as_posix()
        if any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(p.name, g) for g in ignore_globs):
            continue
        try:
            size = p.stat().st_size
        except OSError:
            continue
        total += size
        sizes.append((p, size))
    sizes.sort(key=lambda x: x[1], reverse=True)
    return total, sizes[:top_n]


def _maybe_warn_large(repo_path: Path, ignore_globs: list[str]) -> None:
    total, top = scan_repo_for_large_files(repo_path, top_n=5, ignore_globs=ignore_globs)
    if total < LARGE_FILE_WARN_THRESHOLD:
        return
    typer.echo(f"⚠ Initial scan: {total / 1_000_000:.1f} MB across this repo")
    typer.echo("  Largest files:")
    for p, s in top:
        typer.echo(f"    {p.relative_to(repo_path)}  {s / 1_000_000:.1f} MB")
    typer.echo("  Hit Ctrl+C now to abort and add to .devsync.toml ignore list.")
    for remaining in range(COUNTDOWN_SECONDS, 0, -1):
        typer.echo(f"  Continuing in {remaining}s...")
        time.sleep(1)


def _version_callback(value: bool) -> None:
    if value:
        typer.echo(__version__)
        raise typer.Exit()


def _single_session_for(repo: str) -> dict:
    sessions = list_managed_sessions(f"repo={repo}")
    if not sessions:
        typer.echo(f"✗ No session for repo '{repo}'.", err=True)
        raise typer.Exit(1)
    if len(sessions) > 1:
        typer.echo(
            f"✗ Multiple sessions for repo '{repo}'. Stop the extras first.",
            err=True,
        )
        raise typer.Exit(2)
    return sessions[0]


@app.callback()
def main(
    version: bool = typer.Option(
        False,
        "--version",
        callback=_version_callback,
        is_eager=True,
        help="Print version and exit.",
    ),
) -> None:
    pass


@app.command()
def start(
    repo: str = typer.Argument(None, help="Repo name (fuzzy match) or omit to use cwd."),
    server: str = typer.Argument(..., help="Target server name (e.g., dl02)."),
    no_ssh: bool = typer.Option(False, "--no-ssh", help="Don't auto-SSH after starting sync."),
) -> None:
    """Create a sync session and (optionally) SSH into the server."""
    try:
        cfg = load_global_config()
    except FileNotFoundError as e:
        typer.echo(f"✗ Config missing: {e}", err=True)
        raise typer.Exit(2) from e

    try:
        repo_spec = resolve_repo(repo, code_root=Path(cfg.defaults.code_root))
    except NoSuchRepo as e:
        typer.echo(f"✗ {e}", err=True)
        raise typer.Exit(2) from e

    if server not in cfg.servers:
        typer.echo(
            f"✗ Unknown server '{server}'. Known: {', '.join(sorted(cfg.servers))}",
            err=True,
        )
        raise typer.Exit(2)

    repo_cfg = load_repo_config(repo_spec.local_path)
    eff = resolve_effective_config(
        global_cfg=cfg,
        repo_cfg=repo_cfg,
        repo_name=repo_spec.name,
        server_name=server,
    )

    ensure_daemon_running()

    # Pre-flight: server reachable + remote dir exists
    try:
        probe_ssh(server, eff.host)
    except ServerUnreachable as e:
        typer.echo(f"✗ {e}", err=True)
        typer.echo("  ▸ Check VPN: /vpn status", err=True)
        typer.echo(f"  ▸ Check SSH: ssh {eff.host}", err=True)
        raise typer.Exit(3) from e

    remote_parent = "/".join(eff.remote_path.rstrip("/").split("/")[:-1]) or "/"
    ensure_remote_dir(eff.host, remote_parent)

    _maybe_warn_large(repo_spec.local_path, eff.ignore)

    spec = SessionSpec(repo=repo_spec, server_name=server)
    name = spec.name

    existing = list_managed_sessions(f"repo={repo_spec.name},server={server}")
    if existing:
        existing_name = existing[0].get("name", name)
        typer.echo(f"ⓘ Session {existing_name} already exists.")
        choice = typer.prompt(
            "  [r] Reuse  [R] Restart  [c] Cancel",
            default="r",
            show_default=True,
        ).strip()
        if choice == "c":
            typer.echo("Cancelled.")
            raise typer.Exit(1)
        if choice == "R":
            sync_terminate(existing_name)
            sync_create(spec, eff)
            typer.echo(f"→ Restarted session: {name}")
        else:
            typer.echo(f"→ Reusing session: {existing_name}")
    else:
        try:
            sync_create(spec, eff)
        except SessionAlreadyExists:
            typer.echo(f"ⓘ Session {name} already exists. Reusing.")
        typer.echo(f"→ Sync session created: {name}")
        typer.echo(f"  Local : {repo_spec.local_path}")
        typer.echo(f"  Remote: {eff.host}:{eff.remote_path}")

    if no_ssh or not eff.ssh_after_start:
        typer.echo(f"  (use `devsync stop {repo_spec.name}` when done)")
        return

    typer.echo(f"  SSHing to {eff.host}:{eff.remote_path} ...")
    # `exec` replaces this process; mutagen daemon keeps the sync alive.
    os.execvp(
        "ssh",
        [
            "ssh",
            eff.host,
            "-t",
            f"cd {eff.remote_path} && exec $SHELL -l",
        ],
    )


@app.command(name="ls")
def list_sessions() -> None:
    """List active sync sessions managed by devsync."""
    sessions = list_managed_sessions()
    typer.echo(format_ls_table(sessions))


@app.command()
def stop(
    repo: str = typer.Argument(None),
    all: bool = typer.Option(False, "--all", help="Terminate every devsync-managed session."),
) -> None:
    """Terminate sync session(s)."""
    if all and repo:
        typer.echo("✗ Pass either <repo> or --all, not both.", err=True)
        raise typer.Exit(2)
    if not all and not repo:
        typer.echo("✗ Specify a repo or pass --all.", err=True)
        raise typer.Exit(2)

    if all:
        managed = list_managed_sessions()
        if not managed:
            typer.echo("(no sessions to terminate)")
            return
        sync_terminate_all_managed()
        typer.echo(f"✓ Terminated {len(managed)} session(s).")
        return

    matching = list_managed_sessions(f"repo={repo}")
    if not matching:
        typer.echo(f"✗ No session found for repo '{repo}'.", err=True)
        raise typer.Exit(1)
    sync_terminate_by_repo(repo)
    typer.echo(f"✓ Terminated {len(matching)} session(s) for repo '{repo}'.")


@app.command()
def doctor() -> None:
    """Health-check: daemon, server reachability, config."""
    try:
        cfg = load_global_config()
    except FileNotFoundError as e:
        typer.echo(f"✗ Config not found: {e}", err=True)
        raise typer.Exit(2) from e
    except DevsyncError as e:
        typer.echo(f"✗ Config invalid: {e}", err=True)
        raise typer.Exit(2) from e

    rows = []
    for name, server in cfg.servers.items():
        try:
            probe_ssh(name, server.host)
            rows.append({"name": name, "host": server.host, "reachable": True, "detail": "ok"})
        except ServerUnreachable as e:
            detail = e.args[0].split(":", 1)[-1].strip() if ":" in e.args[0] else "unreachable"
            rows.append({"name": name, "host": server.host, "reachable": False, "detail": detail})

    typer.echo(format_doctor_table(daemon_ok=daemon_status(), server_rows=rows))


@app.command()
def ssh(repo: str) -> None:
    """SSH into the server for an existing session."""
    sessions = list_managed_sessions(f"repo={repo}")
    if not sessions:
        typer.echo(f"✗ No session found for repo '{repo}'. Use `devsync ls`.", err=True)
        raise typer.Exit(1)
    if len(sessions) > 1:
        names = ", ".join(s.get("name", "?") for s in sessions)
        typer.echo(
            f"✗ Multiple sessions match repo '{repo}': {names}. "
            f"Use `devsync ssh <full-name>` (not yet supported) or stop the extras first.",
            err=True,
        )
        raise typer.Exit(2)
    s = sessions[0]
    beta = s.get("beta", {}) or {}
    # Support both nested ({"url": {"host": ..., "path": ...}}) and flat shapes.
    beta_url = beta.get("url", {}) if isinstance(beta.get("url"), dict) else {}
    host = beta_url.get("host") or beta.get("host")
    path = beta_url.get("path") or beta.get("path")
    if not host or not path:
        typer.echo(f"✗ Session metadata missing host/path: {s}", err=True)
        raise typer.Exit(2)
    os.execvp("ssh", ["ssh", host, "-t", f"cd {path} && exec $SHELL -l"])


@app.command()
def status(repo: str) -> None:
    """Show detailed sync status for a session."""
    s = _single_session_for(repo)
    typer.echo(sync_status_raw(s["name"]))


@app.command()
def flush(repo: str) -> None:
    """Force an immediate sync cycle."""
    s = _single_session_for(repo)
    sync_flush(s["name"])
    typer.echo(f"✓ Flushed {s['name']}.")


@app.command()
def logs(repo: str) -> None:
    """Tail mutagen monitor for this session (Ctrl+C to exit)."""
    s = _single_session_for(repo)
    argv = sync_monitor_argv(s["name"])
    os.execvp(argv[0], argv)
