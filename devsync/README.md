# devsync bootstrap

Static config + automated installer for the devsync CLI on a fresh Mac.
The Python source lives at `src/` (vendored from upstream v0.1.0). The
runtime config (`~/.config/devsync/config.toml`) is bidirectionally synced
by the parent `sync.sh`. The 7-step installer (`bootstrap.sh`) handles
the rest.

## One-command install on a new Mac

```bash
git clone git@github.com:a0919376604/ai_system.git ~/Desktop/code/ai_system
cd ~/Desktop/code/ai_system
./sync.sh restore
# Walk through [Y/n] prompts (~5).
# Type each server's password once when ssh-copy-id runs (~4 prompts).
# Done.
```

You can also run the installer directly without `sync.sh`:

```bash
./devsync/bootstrap.sh         # interactive
./devsync/bootstrap.sh --yes   # auto-confirm everything except passwords
```

`bootstrap.sh` is idempotent — re-running on a fully-installed Mac prints
all ✓ with no prompts.

## Layout

| Path | What it is |
|---|---|
| `src/` | Vendored devsync v0.1.0 source. `uv tool install -e src` is what's on `~/.local/bin/devsync`. |
| `config.toml` | Runtime config, bidirectionally synced with `~/.config/devsync/config.toml`. |
| `ssh-config-snippet.txt` | Appended to `~/.ssh/config` if no `dl01` host block exists. |
| `bootstrap.sh` | 7-step installer (mutagen / uv / devsync / sshkey / sshconfig / keytrust / verify). |

## What `bootstrap.sh` does

1. **mutagen** — `brew install mutagen-io/mutagen/mutagen` if missing; register daemon for auto-start.
2. **uv** — `brew install uv` if missing.
3. **devsync CLI** — `uv tool install -e src --force` to ensure `~/.local/bin/devsync` points at the vendored source.
4. **SSH key** — `ssh-keygen -t ed25519` if `~/.ssh/id_ed25519` is missing.
5. **ssh config** — Append `ssh-config-snippet.txt` if `~/.ssh/config` has no `Host dl01` line.
6. **server key trust** — `ssh-copy-id dl0N` for each server not yet trusting your key (interactive password prompt, one per server).
7. **verify** — `devsync doctor` — should show all 4 servers reachable.

Every step first checks state and skips if already done. Re-running is safe.

## What's not in this repo (security)

- `~/.ssh/id_ed25519` — the private key. Never bake into a backup; generate fresh per machine.
- Server passwords — never persisted. One-time use during `ssh-copy-id`.

## NAS write permission (one-time per cluster)

If `devsync start` reports "Transition problems: 1" against the NAS path
(`/nas02/home/leric/code`), the 4 servers' `leric` uid likely don't match
the directory owner. Fix once:

```bash
ssh dl01 'chmod 777 /nas02/home/leric/code'
```

(NAS filesystem doesn't support POSIX ACL, so `chmod` is the path of least
resistance. Internal lab NAS — acceptable trade-off.)
