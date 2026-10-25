# SecondBrain auto-push to GitHub (macOS launchd)

Background job that commits + pushes the SecondBrain (AIR-OS) Obsidian vault to GitHub every 6 hours. Complementary to **Obsidian Sync** (which handles cross-device + UI conflict resolution); this is the "GitHub mirror" layer for off-platform backup + dev-flavor diff history.

## Files

| File | Where it goes on disk | Purpose |
|---|---|---|
| `secondbrain-autopush.sh` | `~/.local/bin/secondbrain-autopush.sh` (chmod +x) | The actual git commit + pull + push script |
| `secondbrain-autopush.applescript` | built into `~/Applications/SecondBrainAutopush.app` | Runs the script as an app, so the macOS privacy grant for `~/Documents` belongs to it |
| `com.leric.secondbrain-autopush.plist` | `~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist` | launchd schedule (every 6 hours) — opens the app |

**Why an app.** The vault lives in `~/Documents`, which macOS blocks for launchd jobs (`Operation not permitted`). A job running the script directly fails every time — from 2026-06-15 it failed 520 times in a row while reporting "no origin remote". Launched with `open`, the app is the process macOS asks about, and its one-time Documents grant covers the script it runs.

## Install

```bash
# Copy script + plist
mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/Library/Logs ~/Applications
cp secondbrain-autopush.sh ~/.local/bin/
chmod +x ~/.local/bin/secondbrain-autopush.sh
cp com.leric.secondbrain-autopush.plist ~/Library/LaunchAgents/

# Build the app that holds the Documents grant (rebuilding or editing it voids the grant;
# editing the script does not)
A=~/Applications/SecondBrainAutopush.app
osacompile -x -o "$A" secondbrain-autopush.applescript
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.leric.SecondBrainAutopush" "$A/Contents/Info.plist" \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.leric.SecondBrainAutopush" "$A/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$A/Contents/Info.plist"
codesign --force --deep -s - "$A"

# Validate + load
plutil -lint ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist
launchctl load -w ~/Library/LaunchAgents/com.leric.secondbrain-autopush.plist

# Verify scheduled
launchctl list | grep secondbrain
# Expect: -  0  com.leric.secondbrain-autopush

# First run: macOS asks "SecondBrainAutopush would like to access files in your Documents
# folder" — click Allow (or System Settings › Privacy & Security › Files and Folders ›
# SecondBrainAutopush › Documents Folder). The run waits until you answer.
launchctl kickstart gui/$(id -u)/com.leric.secondbrain-autopush
tail ~/Library/Logs/secondbrain-autopush.log   # expect "push OK"
```

## Behavior

Every 6 hours, launchd fires the script:

1. `cd /Users/leric/Documents/SecondBrain` (override with `SECONDBRAIN_VAULT`; the log path with `SECONDBRAIN_AUTOPUSH_LOG`)
2. `git add -A` — stage everything (vault edits, `.obsidian/` plugin configs)
3. `git commit -m "auto: YYYY-MM-DD HH:MM · N file(s) · file1,file2,..."` (skipped if nothing changed)
4. `git pull --rebase origin main` — after committing: a rebase refuses to run over uncommitted changes
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
rm -rf ~/Applications/SecondBrainAutopush.app
# Logs left in ~/Library/Logs/secondbrain-autopush*.log — delete if you want
```

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Log says "cannot read … macOS privacy blocks this process" (exit 5) | The job ran without the app's Documents grant | Check the plist opens the app; allow it under Privacy & Security › Files and Folders. Rebuilt the app? The grant was voided — allow it again |
| Log says "push failed" | Mac is offline | Will retry next interval; nothing to do |
| Log says "pull --rebase failed … rebase aborted" then "push failed" | The same note changed here and on another machine | The script aborts the rebase and keeps your commit; open the vault, `git pull --rebase`, resolve, push. Until then every run logs the same two lines |
| Log says "a rebase is in progress" (exit 6) | A rebase was left half-done | Finish (`git rebase --continue`) or `git rebase --abort` by hand |
| `launchctl list` doesn't show the job | Plist syntax error or not loaded | `plutil -lint` the plist; reload |
| Commits are huge / spammy | `.gitignore` not respecting workspace files | Check `.gitignore` excludes `.obsidian/workspace*`, `.obsidian/cache`, `.trash/`, `_assets/` |

## Multi-machine note

This job is **per-machine**. If you set up the AIR-OS vault on a second machine via `git clone`, you'd install this same agent on that machine too. Both machines pulling-then-pushing every 6 hours will converge fine via git's rebase logic, **provided you don't make conflicting edits on two machines without one of them syncing in between** — but Obsidian Sync makes that rare in practice.
