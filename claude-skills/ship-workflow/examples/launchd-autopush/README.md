# SecondBrain auto-push to GitHub (macOS launchd)

Background job that commits + pushes the SecondBrain (AIR-OS) Obsidian vault to GitHub every 6 hours. Complementary to **Obsidian Sync** (which handles cross-device + UI conflict resolution); this is the "GitHub mirror" layer for off-platform backup + dev-flavor diff history.

## Files

| File | Where it goes on disk | Purpose |
|---|---|---|
| `secondbrain-autopush.sh` | `~/.local/bin/secondbrain-autopush.sh` (chmod +x) | The actual git pull + commit + push script |
| `com.leric.secondbrain-autopush.plist` | `~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist` | launchd schedule (every 6 hours) |

## Install

```bash
# Copy script + plist
mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/Library/Logs
cp secondbrain-autopush.sh ~/.local/bin/
chmod +x ~/.local/bin/secondbrain-autopush.sh
cp com.leric.secondbrain-autopush.plist ~/Library/LaunchAgents/

# Validate + load
plutil -lint ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
launchctl load -w ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist

# Verify scheduled
launchctl list | grep secondbrain
# Expect: -  0  com.leric.secondbrain-autopush

# Optional: trigger manually to confirm it works
~/.local/bin/secondbrain-autopush.sh
tail ~/Library/Logs/secondbrain-autopush.log
```

## Behavior

Every 6 hours, launchd fires the script:

1. `cd /Users/leric/Documents/SecondBrain`
2. `git pull --rebase origin main` — in case any other device manually pushed
3. `git add -A` — stage everything (vault edits, `.obsidian/` plugin configs)
4. `git commit -m "auto: YYYY-MM-DD HH:MM · N file(s) · file1,file2,..."` (skipped if nothing changed)
5. `git push origin main`

All output is appended to `~/Library/Logs/secondbrain-autopush.log` for inspection.

## Why every 6 hours

- Long enough to not spam GitHub with tiny commits during heavy editing
- Short enough that worst-case data loss between sync events is < 6 hours
- Obsidian Sync handles minute-by-minute cross-device sync; GitHub is the wider safety net

## Adjust frequency

Edit the plist:
```xml
<key>StartInterval</key>
<integer>21600</integer>   <!-- seconds; 21600 = 6h; 3600 = 1h; 86400 = 1d -->
```

Then reload:
```bash
launchctl unload ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
launchctl load -w ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
```

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
rm ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
rm ~/.local/bin/secondbrain-autopush.sh
# Logs left in ~/Library/Logs/secondbrain-autopush*.log — delete if you want
```

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Log says "push failed" | Mac is offline | Will retry next interval; nothing to do |
| Log says "rebase conflict" | You pushed from another device while local had uncommitted changes | Open vault, resolve, manually commit |
| `launchctl list` doesn't show the job | Plist syntax error or not loaded | `plutil -lint` the plist; reload |
| Commits are huge / spammy | `.gitignore` not respecting workspace files | Check `.gitignore` excludes `.obsidian/workspace*`, `.obsidian/cache`, `.trash/`, `_assets/` |

## Multi-machine note

This job is **per-machine**. If you set up the AIR-OS vault on a second machine via `git clone`, you'd install this same agent on that machine too. Both machines pulling-then-pushing every 6 hours will converge fine via git's rebase logic, **provided you don't make conflicting edits on two machines without one of them syncing in between** — but Obsidian Sync makes that rare in practice.
