# devsync bootstrap

Static config + helper for [devsync](https://github.com/a0919376604/devsync) —
the Python CLI that wraps Mutagen for one-way Mac→Linux sync against the
internal dl01..dl04 cluster.

`../sync.sh restore` populates `~/.config/devsync/config.toml` from
`config.toml` here, then runs a post-restore check that walks the rest of
the bootstrap (mutagen install, SSH key, ssh config snippet, devsync CLI
install) and prints exactly what's missing.

## Layout

| File | What it is |
|---|---|
| `config.toml` | Current `~/.config/devsync/config.toml` snapshot — synced bidirectionally by `sync.sh`. |
| `ssh-config-snippet.txt` | The 4 `Host dl0N` blocks. `sync.sh` appends if `~/.ssh/config` has no `dl01` host yet. |
| `README.md` | This file. |

## Manual fallback (when `sync.sh restore` post-check flags missing pieces)

1. **Mutagen**
   ```bash
   brew install mutagen-io/mutagen/mutagen
   mutagen daemon register   # optional: auto-start on login
   ```

2. **SSH key** (if `~/.ssh/id_ed25519` doesn't exist)
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "leric@$(hostname -s) devsync"
   ```

3. **SSH config** (if `~/.ssh/config` has no `dl01` host)
   ```bash
   cat ai_system/devsync/ssh-config-snippet.txt >> ~/.ssh/config
   chmod 600 ~/.ssh/config
   ```

4. **Push key to each server** (one password prompt per host, then never again)
   ```bash
   for h in dl01 dl02 dl03 dl04; do ssh-copy-id $h; done
   ```

5. **devsync CLI** (clone the repo somewhere, then editable install)
   ```bash
   git clone git@github.com:a0919376604/devsync.git ~/Desktop/code/devsync
   cd ~/Desktop/code/devsync
   uv tool install -e .
   ```

6. **Verify** — should show all 4 servers reachable
   ```bash
   devsync doctor
   ```

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
