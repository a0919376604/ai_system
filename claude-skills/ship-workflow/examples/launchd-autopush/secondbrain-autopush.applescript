-- SecondBrainAutopush: runs the vault autopush script as an app, so the macOS
-- privacy grant for ~/Documents belongs to this app (launchd jobs get none).
try
	do shell script "/Users/leric/.local/bin/secondbrain-autopush.sh"
end try
