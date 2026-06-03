"""Server-side helpers (SSH reachability probes, remote dir creation)."""

from __future__ import annotations

import subprocess

from devsync.errors import ServerUnreachable

SSH_PROBE_TIMEOUT = 5


def probe_ssh(name: str, host: str, *, timeout: int = SSH_PROBE_TIMEOUT) -> None:
    """Verify SSH key auth works to `host`. Raises ServerUnreachable on failure."""
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={timeout}",
        "-o",
        "StrictHostKeyChecking=accept-new",
        host,
        "true",
    ]
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0:
        reason = res.stderr.decode(errors="replace").strip().splitlines()[-1] if res.stderr else ""
        raise ServerUnreachable(name, host, reason)


def ensure_remote_dir(host: str, path: str) -> None:
    """Create `path` on `host` if it does not exist. Idempotent."""
    cmd = ["ssh", "-o", "BatchMode=yes", host, f"mkdir -p {path!r}"]
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0:
        raise ServerUnreachable(
            host,
            host,
            f"could not create remote dir {path}: {res.stderr.decode(errors='replace').strip()}",
        )
