# devsync

One-command sync-and-SSH wrapper around [Mutagen](https://mutagen.io) for working with internal Linux dev servers from macOS.

## What it does

Run `devsync start <repo> <server>` and:

1. Start a one-way (Mac → server) continuous sync of the repo.
2. Drop you into an SSH shell on the server, already cd'd into the synced directory.
3. Keep the sync session alive in the background after you exit SSH.
4. `devsync stop <repo>` to terminate.

## Prerequisites

- macOS, Python ≥ 3.11
- [Mutagen](https://mutagen.io) installed and daemon registered (`brew install mutagen-io/mutagen/mutagen`)
- SSH key trust established with each target server (see `docs/superpowers/plans/2026-06-02-devsync.md` Task 1)
- `uv` (https://docs.astral.sh/uv/) installed

## Install

```bash
git clone <this repo> ~/Desktop/code/devsync
cd ~/Desktop/code/devsync
uv tool install -e .
devsync --version
```

## Configure

Edit `~/.config/devsync/config.toml`. Minimal example:

```toml
[defaults]
code_root = "/Users/yourname/Desktop/code"
remote_base = "/home/yourname/code"
sync_mode = "one-way-replica"
ignore_vcs = true
ssh_after_start = true

[servers.dl01]
host = "dl01"  # name from ~/.ssh/config

[servers.dl02]
host = "dl02"
```

Per-repo overrides go in `<repo>/.devsync.toml` (all fields optional):

```toml
default_server = "dl02"
remote_path = "/data/leric/custom/path"
ignore = ["datasets/", "models/"]
```

## Usage

```bash
devsync doctor                       # health-check: daemon + all servers
devsync start <repo> <server>        # create sync + auto-SSH
devsync start <repo> <server> --no-ssh   # sync only, no SSH
devsync ls                           # list all active sessions
devsync ssh <repo>                   # SSH into an existing session
devsync status <repo>                # detailed sync status
devsync flush <repo>                 # force immediate sync
devsync logs <repo>                  # tail mutagen monitor
devsync stop <repo>                  # terminate one session
devsync stop --all                   # terminate every devsync-managed session
```

## Smoke checklist (run after every release)

```
[ ] devsync doctor                          → daemon green, 4/4 servers reachable
[ ] devsync start <test-repo> dl01 --no-ssh → session appears in `devsync ls`
[ ] echo "x" > <test-repo>/foo.txt          → ssh dl01 sees foo.txt within 1s
[ ] rm <test-repo>/foo.txt                  → ssh dl01 sees foo.txt gone
[ ] devsync stop <test-repo>                → session removed
```

## How it works

Stateless: devsync never persists its own state — all session metadata lives in the mutagen daemon and is queried via `mutagen sync list --label-selector=managed-by=devsync`. Labels (`repo`, `server`, `worktree`, `created-at`) identify devsync-managed sessions.

Configuration: TOML loaded with `tomllib` and validated by pydantic. Four-layer override precedence: CLI flags > per-repo `.devsync.toml` > per-server config > defaults.

SSH: devsync never implements SSH; it shells out to system `ssh`, which honors your `~/.ssh/config`. Key-based auth only — no password handling.

## Design docs

See `docs/superpowers/specs/2026-06-02-devsync-design.md` for the full spec and `docs/superpowers/plans/2026-06-02-devsync.md` for the implementation plan.

## License

MIT
