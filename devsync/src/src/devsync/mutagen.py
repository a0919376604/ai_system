"""Subprocess wrapper around the mutagen CLI.

All mutagen calls funnel through this module so that future CLI/format changes
can be patched in one place (see Risks in the spec).
"""

from __future__ import annotations

import json
import subprocess

from devsync.config import EffectiveConfig
from devsync.errors import MutagenDaemonError, SessionAlreadyExists
from devsync.session import SessionSpec


def _run(cmd: list[str], *, check: bool = False) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(cmd, capture_output=True, check=check)


def daemon_status() -> bool:
    """Return True if the mutagen daemon is currently running."""
    res = _run(["mutagen", "daemon", "status"])
    return res.returncode == 0


def ensure_daemon_running() -> None:
    """Start the daemon if it isn't already. Raises MutagenDaemonError on failure."""
    if daemon_status():
        return
    start = _run(["mutagen", "daemon", "start"])
    if start.returncode != 0:
        raise MutagenDaemonError(
            f"mutagen daemon start failed (rc={start.returncode}): "
            f"{start.stderr.decode(errors='replace').strip()}"
        )
    if not daemon_status():
        raise MutagenDaemonError("daemon start returned 0 but status still reports down")


def build_create_argv(spec: SessionSpec, cfg: EffectiveConfig) -> list[str]:
    """Construct argv for `mutagen sync create`."""
    argv: list[str] = [
        "mutagen",
        "sync",
        "create",
        f"--name={spec.name}",
        f"--sync-mode={cfg.sync_mode}",
        "--default-file-mode-beta=0644",
        "--default-directory-mode-beta=0755",
        f"--symlink-mode={cfg.symlink_mode}",
    ]
    if cfg.ignore_vcs:
        argv.append("--ignore-vcs")
    for pat in cfg.ignore:
        argv.append(f"--ignore={pat}")
    for k, v in spec.labels():
        argv.extend(["--label", f"{k}={v}"])
    # Endpoints last
    argv.append(str(spec.repo.local_path))
    argv.append(f"{cfg.host}:{cfg.remote_path}")
    return argv


def sync_create(spec: SessionSpec, cfg: EffectiveConfig) -> None:
    """Create a sync session. Raises SessionAlreadyExists if name collides."""
    res = _run(build_create_argv(spec, cfg))
    if res.returncode != 0:
        stderr = res.stderr.decode(errors="replace")
        if "already exists" in stderr:
            raise SessionAlreadyExists(spec.name)
        raise RuntimeError(f"mutagen sync create failed (rc={res.returncode}): {stderr.strip()}")


def list_managed_sessions(extra_selector: str | None = None) -> list[dict]:
    """Return all sessions tagged `managed-by=devsync`, optionally filtered further."""
    selector = "managed-by=devsync"
    if extra_selector:
        selector += f",{extra_selector}"
    cmd = [
        "mutagen",
        "sync",
        "list",
        f"--label-selector={selector}",
        "--template",
        "{{json .}}",
    ]
    res = _run(cmd)
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync list failed (rc={res.returncode}): "
            f"{res.stderr.decode(errors='replace').strip()}"
        )
    raw = res.stdout.decode(errors="replace").strip()
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"could not parse mutagen sync list output: {e}") from e
    return parsed if isinstance(parsed, list) else [parsed]


def sync_terminate(name: str) -> None:
    """Terminate a specific session by name."""
    res = _run(["mutagen", "sync", "terminate", name])
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync terminate {name!r} failed: {res.stderr.decode(errors='replace').strip()}"
        )


def sync_terminate_by_repo(repo_name: str) -> None:
    """Terminate all devsync-managed sessions for a given repo."""
    res = _run(
        [
            "mutagen",
            "sync",
            "terminate",
            f"--label-selector=managed-by=devsync,repo={repo_name}",
        ]
    )
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync terminate (repo={repo_name}) failed: "
            f"{res.stderr.decode(errors='replace').strip()}"
        )


def sync_terminate_all_managed() -> None:
    """Terminate every devsync-managed session."""
    res = _run(
        [
            "mutagen",
            "sync",
            "terminate",
            "--label-selector=managed-by=devsync",
        ]
    )
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync terminate (all) failed: {res.stderr.decode(errors='replace').strip()}"
        )


def sync_flush(name: str) -> None:
    """Force an immediate sync cycle."""
    res = _run(["mutagen", "sync", "flush", name])
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync flush {name!r} failed: {res.stderr.decode(errors='replace').strip()}"
        )


def sync_status_raw(name: str) -> str:
    """Return raw `mutagen sync list <name>` (long-form) output as text."""
    res = _run(["mutagen", "sync", "list", name])
    if res.returncode != 0:
        raise RuntimeError(
            f"mutagen sync list {name!r} failed: {res.stderr.decode(errors='replace').strip()}"
        )
    return res.stdout.decode(errors="replace")


def sync_monitor_argv(name: str) -> list[str]:
    """Argv to tail-follow status (caller uses os.execvp or subprocess)."""
    return ["mutagen", "sync", "monitor", name]
