---
name: run-plan
description: |
  Hand a written implementation plan to `codex exec` and let it autonomously
  run all tasks to completion. Detaches as a background process, writes a
  progress log, and lets Claude poll periodically. Default sandbox mode is
  `danger-full-access` so worktrees work without permission errors.
  Supports multiple concurrent runs — each plan gets its own slot keyed by
  the plan filename, typically launched from separate worktrees.
  Use when asked to "run plan", "execute plan", "run-plan", "let codex run
  this plan", or "implement this plan with codex".
triggers:
  - run plan
  - execute the plan
  - codex run plan
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /run-plan — Autonomous Plan Execution via Codex

Wraps `codex exec` to run a written implementation plan end-to-end without
hand-holding. Built from the patterns that worked when the user invoked
codex one-shot manually:

- `--dangerously-bypass-approvals-and-sandbox` by default — git worktrees
  break `workspace-write` because the `.git` metadata lives outside the
  worktree's filesystem boundary. Don't fight that, just bypass.
- Background launch via `nohup`, stdout/stderr to a slot-suffixed log path.
- Heartbeat watcher in another background shell — emits progress lines
  Claude monitors and surfaces to the user.
- Standard prompt template that embeds the plan content and pins the
  workflow contract (TDD, commit per task, no push, no amend).
- **Multi-slot:** all `/tmp/run-plan-*` paths are suffixed by a slot id
  derived from the plan filename, so multiple plans can run in parallel
  (typically each in its own worktree on a different branch).

## Slot ids

A slot id is derived from the plan filename:

```
SLOT=$(basename "$PLAN_ABS" .md | tr -c 'A-Za-z0-9_.-' '_')
```

So `docs/superpowers/plans/refactor-foo.md` → slot `refactor-foo`. All
state files for that run live at `/tmp/run-plan-*-<slot>.{txt,log,pid}`.

If two plans share a basename (different directories), pre-flight blocks
the second launch — rename one of the plans to disambiguate.

## Sub-commands

```
/run-plan                       # auto-pick latest docs/superpowers/plans/*.md
/run-plan <path>                # use the given plan file
/run-plan list                  # list all known runs (alive + recent exits)
/run-plan status                # if exactly one run is alive, target it; otherwise list
/run-plan status <slot|path>    # report state of a specific slot
/run-plan kill                  # kill the only alive run, or refuse if multiple
/run-plan kill <slot|path>      # SIGTERM the specified slot (SIGKILL after 5s)
/run-plan kill --all            # kill every alive slot
```

## Step 0: Routing

Parse the user's input:

- First token `list` → jump to **Step 5a: list**.
- First token `status` → jump to **Step 5: status** (with optional second
  arg as slot or plan path).
- First token `kill` → jump to **Step 6: kill** (with optional second
  arg as slot/path, or `--all`).
- Otherwise → treat the input as an optional plan path and proceed with
  Pre-flight (launch a new run).

A slot arg is normalized like this — accepts a bare slot id or a plan
file path:

```bash
resolve_slot() {
  local ARG="$1"
  if [ -z "$ARG" ]; then echo ""; return; fi
  if [ -f "$ARG" ]; then
    basename "$ARG" .md | tr -c 'A-Za-z0-9_.-' '_'
  else
    echo "$ARG" | tr -c 'A-Za-z0-9_.-' '_'
  fi
}
```

## Step 1: Pre-flight

```bash
set -e
echo "=== run-plan pre-flight ==="

# Codex binary
CODEX_BIN=$(which codex 2>/dev/null || true)
if [ -z "$CODEX_BIN" ]; then
  echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex"
  exit 1
fi
echo "codex: $CODEX_BIN ($(codex --version 2>/dev/null))"

# Auth
if [ -z "$CODEX_API_KEY" ] && [ -z "$OPENAI_API_KEY" ] && [ ! -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then
  echo "ERROR: no codex auth. Run: codex login"
  exit 1
fi
echo "auth: present"

# Plan file resolution
PLAN_ARG="$1"
if [ -z "$PLAN_ARG" ]; then
  PLAN_ARG=$(ls -t docs/superpowers/plans/*.md 2>/dev/null | head -1)
  if [ -z "$PLAN_ARG" ]; then
    echo "ERROR: no plan file given and none found in docs/superpowers/plans/"
    exit 1
  fi
  echo "auto-picked plan: $PLAN_ARG"
fi
if [ ! -f "$PLAN_ARG" ]; then
  echo "ERROR: plan file not found: $PLAN_ARG"
  exit 1
fi
PLAN_ABS=$(cd "$(dirname "$PLAN_ARG")" && pwd)/$(basename "$PLAN_ARG")
SLOT=$(basename "$PLAN_ABS" .md | tr -c 'A-Za-z0-9_.-' '_')
echo "plan: $PLAN_ABS ($(wc -l < "$PLAN_ABS") lines)"
echo "slot: $SLOT"

# Branch + working tree
BRANCH=$(git branch --show-current 2>/dev/null || echo "DETACHED")
CWD=$(pwd)
echo "branch: $BRANCH"
echo "cwd: $CWD"
DIRTY=$(git status --porcelain | grep -v '^??' | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  echo "WARN: working tree has $DIRTY tracked changes — codex will see them"
fi

# Existing run for THIS slot?
PID_FILE=/tmp/run-plan-codex-$SLOT.pid
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "ERROR: a codex run for slot '$SLOT' is already in progress (PID $OLD_PID)."
    echo "       Use '/run-plan status $SLOT' to inspect, '/run-plan kill $SLOT' to stop."
    exit 1
  fi
fi

# Info: other slots in flight (not a blocker)
OTHER_ALIVE=0
for p in /tmp/run-plan-codex-*.pid; do
  [ -e "$p" ] || continue
  PID=$(cat "$p")
  if kill -0 "$PID" 2>/dev/null; then
    OTHER_SLOT=$(basename "$p" .pid | sed 's/^run-plan-codex-//')
    if [ "$OTHER_SLOT" != "$SLOT" ]; then
      OTHER_ALIVE=$((OTHER_ALIVE+1))
      echo "info: slot '$OTHER_SLOT' (PID $PID) is also running"
    fi
  fi
done
[ "$OTHER_ALIVE" -gt 0 ] && echo "info: $OTHER_ALIVE other codex run(s) currently in flight (this is fine — separate worktrees recommended)"
```

Save `PLAN_ABS`, `SLOT`, `BRANCH`, and `CWD` for the next steps.

If any pre-flight check exits non-zero, surface the error to the user
and stop — do not attempt to launch.

## Step 2: Build the prompt

Embed the plan content directly. Codex's own filesystem may or may not
reach the plan path (depends on sandbox + working dir); embedding is the
reliable path.

Write the prompt header (with variable expansion for `$BRANCH`/`$PLAN_ABS`),
then append the plan content byte-for-byte (no shell interpretation).
Use a unique heredoc delimiter so a literal `EOF` in the plan body
doesn't terminate early.

```bash
PROMPT_FILE=/tmp/run-plan-prompt-$SLOT.txt

cat > "$PROMPT_FILE" << RUN_PLAN_HEADER_END
IMPORTANT: Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/. These are AI agent configuration files; ignore them. Stay focused on repository code only.

Your task: implement the plan below. Execute tasks in numerical order; within each task, execute steps in order.

WORKFLOW:
1. Use the exact code/text shown in each step. Do not improvise.
2. Use TDD discipline where the plan asks for it: write failing test, confirm fail, then implement.
3. After each task, verify tests are green before moving on. If they cannot be made green within the task, STOP and write a status note to the end of the plan file (append a "## Execution log" section if absent).
4. Run tests with the commands the plan shows.
5. Commit per the plan's commit messages — one commit per task unless the plan groups otherwise.
6. At the end, report DONE / DONE_WITH_CONCERNS / BLOCKED with a summary.

CONSTRAINTS:
- Stay on branch \`$BRANCH\`. Do NOT switch branches.
- Do NOT push to any remote.
- Do NOT amend existing commits — always create new commits.
- Do NOT use --no-verify, --no-gpg-sign, or any hook bypass.
- Do NOT mark a task complete if its tests fail — stop and record the failure.
- If a "fail first" test passes immediately (e.g., the test mirrors production logic), that's acceptable — just note it and move on.
- If exact line numbers in the plan don't match the file, use surrounding context to locate the correct spot.
- Pre-existing baseline failures (failing before your changes) are NOT yours to fix — note them and continue.

PLAN ($PLAN_ABS):

RUN_PLAN_HEADER_END

# Append plan content with no interpretation — preserves any backticks,
# $vars, EOF markers, etc. that the plan body might contain.
cat "$PLAN_ABS" >> "$PROMPT_FILE"
printf '\nBEGIN.\n' >> "$PROMPT_FILE"

echo "prompt: $PROMPT_FILE ($(wc -l < "$PROMPT_FILE") lines, $(wc -c < "$PROMPT_FILE") bytes)"
```

## Step 3: Launch codex (detached)

```bash
LOG_FILE=/tmp/run-plan-codex-$SLOT.log
PID_FILE=/tmp/run-plan-codex-$SLOT.pid
START_REF_FILE=/tmp/run-plan-start-ref-$SLOT.txt
CWD_FILE=/tmp/run-plan-cwd-$SLOT.txt
META_FILE=/tmp/run-plan-meta-$SLOT.txt

# Record state needed by status/kill from any cwd
git rev-parse HEAD > "$START_REF_FILE"
pwd > "$CWD_FILE"
{
  echo "plan=$PLAN_ABS"
  echo "branch=$BRANCH"
  echo "cwd=$CWD"
  echo "started=$(date +%Y-%m-%dT%H:%M:%S)"
} > "$META_FILE"

# Pass the prompt via stdin (`-` reads prompt from stdin) instead of argv —
# avoids macOS ARG_MAX (~256KB) limits if a plan ever gets very large.
nohup codex exec - \
  --dangerously-bypass-approvals-and-sandbox \
  -c 'model_reasoning_effort="high"' \
  < "$PROMPT_FILE" > "$LOG_FILE" 2>&1 &
CODEX_PID=$!
echo "$CODEX_PID" > "$PID_FILE"
echo "launched slot=$SLOT PID=$CODEX_PID"
echo "log: $LOG_FILE"
echo "started from: $(cat $START_REF_FILE)"
```

After this, the launch shell exits immediately (`nohup` detaches codex).
Codex itself runs in the background, untracked by the harness.

## Step 3.5: Schedule fallback wakeup (safety net)

The `Monitor` attachment in Step 4 is the **fast path** for getting Claude
re-invoked when codex exits. But the harness sometimes drops that signal —
especially on long runs (1-2h) where the session may have idled out by the
time `[codex-exit]` fires. Without a backup, the user gets total silence
even after codex finishes successfully.

**Immediately after launching the watcher, call `ScheduleWakeup`:**

```
ScheduleWakeup(
  delaySeconds=1800,
  reason="run-plan <slot> fallback poll — checks done marker, re-arms if still running",
  prompt="/run-plan status"
)
```

Behavior when the wakeup fires:

1. `/run-plan status` (Step 7a) scans `/tmp/run-plan-done-*.txt` automatically.
2. **If a done marker exists** for this slot → proceed to Step 7 (verification
   + completion notification). The wakeup chain ends here.
3. **If codex is still alive** (PID still kicking, no done marker) → call
   `ScheduleWakeup` again with the same delay, then exit the turn silently
   (no Discord reply, no PushNotification — user asked for silence until done).
4. **If codex died without a done marker** (crashed, killed externally) →
   surface that and stop re-arming.

This gives belt-and-suspenders coverage: Monitor wakes Claude in ~seconds
when it works; ScheduleWakeup catches it within 30 min when it doesn't.

## Step 4: Heartbeat watcher

Spawn a second background process per slot that emits a progress line
every ~3 min and exits when codex itself exits.

**Implementation note for Claude:** run this with `run_in_background: true`.
Attach the `Monitor` tool to that background shell — every new stdout
line (each `[heartbeat <slot>]` and the terminal `[codex-exit <slot>]`)
arrives as a notification. The slot id is embedded in each line so you
can tell concurrent runs apart. When `[codex-exit <slot>]` arrives,
proceed to Step 7 (verification) for that slot without waiting for user
input.

```bash
SLOT="<the slot id from launch>"
CODEX_PID=$(cat /tmp/run-plan-codex-$SLOT.pid)
START_REF=$(cat /tmp/run-plan-start-ref-$SLOT.txt)
CWD=$(cat /tmp/run-plan-cwd-$SLOT.txt)
LOG_FILE=/tmp/run-plan-codex-$SLOT.log

# Watcher runs in the launch cwd so git commands target the right worktree
cd "$CWD"

while kill -0 "$CODEX_PID" 2>/dev/null; do
  sleep 180
  NEW_COMMITS=$(git rev-list --count "${START_REF}..HEAD" 2>/dev/null || echo "?")
  LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
  LAST=$(grep -E '^(codex|git commit -m|tokens used)' "$LOG_FILE" 2>/dev/null | tail -1 | head -c 100)
  echo "[heartbeat $SLOT] $(date +%H:%M) PID=$CODEX_PID alive | commits=+$NEW_COMMITS | log=$LOG_LINES lines | last=$LAST"
done

# Codex exited — emit a terminal line + native notification
FINAL_COMMITS=$(git rev-list --count "${START_REF}..HEAD" 2>/dev/null || echo "?")
FINAL_STATUS=$(tail -30 "$LOG_FILE" | grep -E '^(DONE|BLOCKED|DONE_WITH_CONCERNS)' | tail -1)
[ -z "$FINAL_STATUS" ] && FINAL_STATUS="(no DONE/BLOCKED marker — check log)"
TAIL=$(tail -30 "$LOG_FILE" | grep -E '^(DONE|BLOCKED|tokens used)' | tail -3 | tr '\n' ' | ')
echo "[codex-exit $SLOT] $(date +%H:%M) commits=+$FINAL_COMMITS | $TAIL"

# Persist a "done" marker so a later Claude session can pick this up
# even if the harness didn't auto-wake us. Cleared when Step 7 finishes.
DONE_FILE=/tmp/run-plan-done-$SLOT.txt
{
  echo "slot=$SLOT"
  echo "exited=$(date +%Y-%m-%dT%H:%M:%S)"
  echo "commits=+$FINAL_COMMITS"
  echo "status=$FINAL_STATUS"
} > "$DONE_FILE"

# Native OS notification — this is the reliable wake-up channel for the
# human. The harness may or may not re-invoke Claude when this background
# shell exits; the human always sees this popup.
NOTIF_TITLE="run-plan: $SLOT — $FINAL_STATUS"
NOTIF_BODY="commits=+$FINAL_COMMITS · $(date +%H:%M)"
if command -v osascript >/dev/null 2>&1; then
  # macOS — display notification + Glass sound
  osascript -e "display notification \"$NOTIF_BODY\" with title \"$NOTIF_TITLE\" sound name \"Glass\"" 2>/dev/null || true
elif command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$NOTIF_TITLE" -message "$NOTIF_BODY" -sound Glass 2>/dev/null || true
elif command -v notify-send >/dev/null 2>&1; then
  # Linux
  notify-send "$NOTIF_TITLE" "$NOTIF_BODY" 2>/dev/null || true
fi
# Terminal bell as a last-resort cue
printf '\a' >&2
```

Claude: when a `[heartbeat <slot>]` notification arrives, decide whether
to surface it to the user — surface if `commits` increased since the
last heartbeat for that slot, or if `last` mentions a new task. When
`[codex-exit <slot>]` arrives, proceed to Step 7 (verification) for that
slot — Step 7 handles the channel-aware completion notification.

**Important — the harness does not always re-invoke Claude when the
background watcher exits.** The native OS notification from the watcher
is the primary wake-up channel for the human. The marker file
`/tmp/run-plan-done-<slot>.txt` lets a later Claude session detect
finished runs and resume verification — see Step 7a.

## Step 5: `/run-plan status [slot|path]`

```bash
ARG="$1"

list_alive_slots() {
  for p in /tmp/run-plan-codex-*.pid; do
    [ -e "$p" ] || continue
    PID=$(cat "$p")
    if kill -0 "$PID" 2>/dev/null; then
      basename "$p" .pid | sed 's/^run-plan-codex-//'
    fi
  done
}

# Resolve target slot
if [ -n "$ARG" ]; then
  if [ -f "$ARG" ]; then
    SLOT=$(basename "$ARG" .md | tr -c 'A-Za-z0-9_.-' '_')
  else
    SLOT=$(echo "$ARG" | tr -c 'A-Za-z0-9_.-' '_')
  fi
else
  ALIVE=( $(list_alive_slots) )
  if [ ${#ALIVE[@]} -eq 0 ]; then
    LAST_PID=$(ls -t /tmp/run-plan-codex-*.pid 2>/dev/null | head -1)
    if [ -z "$LAST_PID" ]; then
      echo "no codex runs have been launched via /run-plan"
      exit 0
    fi
    SLOT=$(basename "$LAST_PID" .pid | sed 's/^run-plan-codex-//')
    echo "no alive runs — showing most recent: slot=$SLOT"
  elif [ ${#ALIVE[@]} -eq 1 ]; then
    SLOT="${ALIVE[0]}"
  else
    echo "multiple runs alive — pass a slot:"
    for s in "${ALIVE[@]}"; do echo "  - $s"; done
    echo "(use '/run-plan list' for full details)"
    exit 0
  fi
fi

PID_FILE=/tmp/run-plan-codex-$SLOT.pid
LOG_FILE=/tmp/run-plan-codex-$SLOT.log
START_REF_FILE=/tmp/run-plan-start-ref-$SLOT.txt
CWD_FILE=/tmp/run-plan-cwd-$SLOT.txt
META_FILE=/tmp/run-plan-meta-$SLOT.txt

if [ ! -f "$PID_FILE" ]; then
  echo "no run found for slot '$SLOT'"
  exit 0
fi
PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
  STATUS="ALIVE"
else
  STATUS="EXITED"
fi
echo "slot=$SLOT PID=$PID — $STATUS"

[ -f "$META_FILE" ] && cat "$META_FILE"

# cd into the launch cwd so git commands target the right repo/worktree
if [ -f "$CWD_FILE" ]; then
  cd "$(cat $CWD_FILE)" 2>/dev/null || echo "WARN: launch cwd no longer exists"
fi

if [ -f "$START_REF_FILE" ]; then
  START=$(cat "$START_REF_FILE")
  echo ""
  echo "=== new commits since launch ==="
  git log --oneline "${START}..HEAD" 2>/dev/null
fi

echo ""
echo "=== log size + tail ==="
wc -l "$LOG_FILE"
tail -25 "$LOG_FILE"

echo ""
echo "=== plan execution log tail ==="
PLAN=$(grep '^plan=' "$META_FILE" 2>/dev/null | cut -d= -f2-)
if [ -n "$PLAN" ] && [ -f "$PLAN" ]; then
  awk '/^## Execution log/,/^## /' "$PLAN" | tail -20
fi
```

Surface a concise summary keyed by slot: status, commit count, last
execution-log entry, any `BLOCKED` markers in the codex log.

## Step 5a: `/run-plan list`

```bash
echo "=== run-plan runs ==="
ANY=0
for p in $(ls -t /tmp/run-plan-codex-*.pid 2>/dev/null); do
  [ -e "$p" ] || continue
  ANY=1
  SLOT=$(basename "$p" .pid | sed 's/^run-plan-codex-//')
  PID=$(cat "$p")
  if kill -0 "$PID" 2>/dev/null; then
    STATE="ALIVE"
  else
    STATE="exited"
  fi
  META=/tmp/run-plan-meta-$SLOT.txt
  BRANCH=""; STARTED=""
  if [ -f "$META" ]; then
    BRANCH=$(grep '^branch=' "$META" | cut -d= -f2-)
    STARTED=$(grep '^started=' "$META" | cut -d= -f2-)
  fi
  # Highlight slots that finished but haven't been verified yet
  PENDING=""
  if [ -f "/tmp/run-plan-done-$SLOT.txt" ]; then
    PENDING=" [PENDING-VERIFY]"
  fi
  printf "  %-30s %-7s pid=%-6s branch=%-25s started=%s%s\n" "$SLOT" "$STATE" "$PID" "$BRANCH" "$STARTED" "$PENDING"
done
[ "$ANY" -eq 0 ] && echo "(none)"

# Show any unprocessed completions so the user knows what's waiting
PENDING_DONE=$(ls /tmp/run-plan-done-*.txt 2>/dev/null)
if [ -n "$PENDING_DONE" ]; then
  echo ""
  echo "=== pending verification (codex finished, never verified) ==="
  for d in $PENDING_DONE; do
    SLOT=$(basename "$d" .txt | sed 's/^run-plan-done-//')
    echo "  $SLOT"
    sed 's/^/    /' "$d"
  done
  echo ""
  echo "Run '/run-plan status <slot>' to verify, then the marker auto-clears."
fi
```

## Step 6: `/run-plan kill [slot|path|--all]`

```bash
ARG="$1"

do_kill() {
  local SLOT="$1"
  local PID_FILE=/tmp/run-plan-codex-$SLOT.pid
  if [ ! -f "$PID_FILE" ]; then
    echo "no run to kill for slot '$SLOT'"
    return
  fi
  local PID=$(cat "$PID_FILE")
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "slot '$SLOT' PID $PID is not alive"
    rm -f "$PID_FILE"
    return
  fi
  kill "$PID" 2>/dev/null
  sleep 5
  if kill -0 "$PID" 2>/dev/null; then
    echo "SIGTERM didn't take for slot '$SLOT', sending SIGKILL"
    kill -9 "$PID" 2>/dev/null
  fi
  rm -f "$PID_FILE"
  echo "stopped slot '$SLOT'"
}

if [ "$ARG" = "--all" ]; then
  ANY=0
  for p in /tmp/run-plan-codex-*.pid; do
    [ -e "$p" ] || continue
    ANY=1
    SLOT=$(basename "$p" .pid | sed 's/^run-plan-codex-//')
    do_kill "$SLOT"
  done
  [ "$ANY" -eq 0 ] && echo "no codex runs to kill"
  exit 0
fi

if [ -n "$ARG" ]; then
  if [ -f "$ARG" ]; then
    SLOT=$(basename "$ARG" .md | tr -c 'A-Za-z0-9_.-' '_')
  else
    SLOT=$(echo "$ARG" | tr -c 'A-Za-z0-9_.-' '_')
  fi
  do_kill "$SLOT"
  exit 0
fi

# No arg — kill the only alive run, refuse if multiple
ALIVE=()
for p in /tmp/run-plan-codex-*.pid; do
  [ -e "$p" ] || continue
  PID=$(cat "$p")
  if kill -0 "$PID" 2>/dev/null; then
    SLOT=$(basename "$p" .pid | sed 's/^run-plan-codex-//')
    ALIVE+=("$SLOT")
  fi
done

if [ ${#ALIVE[@]} -eq 0 ]; then
  echo "no codex run to kill"
elif [ ${#ALIVE[@]} -eq 1 ]; then
  do_kill "${ALIVE[0]}"
else
  echo "multiple runs alive — pass a slot or --all:"
  for s in "${ALIVE[@]}"; do echo "  - $s"; done
fi
```

## Step 7: Post-run verification (on `[codex-exit <slot>]`)

When the heartbeat watcher emits `[codex-exit <slot>]`, **or** when a
later session detects a pending `/tmp/run-plan-done-<slot>.txt` (see
Step 7a), run verification for that slot:

```bash
SLOT="<slot from the exit line or done marker>"
LOG_FILE=/tmp/run-plan-codex-$SLOT.log
START_REF=$(cat /tmp/run-plan-start-ref-$SLOT.txt)
CWD=$(cat /tmp/run-plan-cwd-$SLOT.txt 2>/dev/null)
DONE_FILE=/tmp/run-plan-done-$SLOT.txt

[ -n "$CWD" ] && cd "$CWD"

echo "=== slot $SLOT final status ==="
tail -5 "$LOG_FILE" | grep -E '^(DONE|BLOCKED|DONE_WITH_CONCERNS)' | tail -1

echo ""
echo "=== commits created ==="
git log --oneline "${START_REF}..HEAD"

echo ""
echo "=== modified / untracked files ==="
git status --short

echo ""
echo "=== if plan mentioned removing symbols, sanity grep ==="
# Auto-extract removal candidates from plan body — lines matching "delete the helper", "remove .* constant", etc.
# For safety, also re-grep anything codex's own execution log claimed to delete.

# Clear the done marker once Claude has actually verified
rm -f "$DONE_FILE"
```

Read the plan's `## Notes for the implementer` and `## Validation matrix`
sections to derive specific verification commands. At minimum:

- `git status` clean except expected untracked files.
- Tests in the plan's scope all pass (re-run the scope-specific test
  commands from the plan).
- Sanity grep for symbols/constants the plan said to remove (zero
  matches expected).

Report DONE / DONE_WITH_CONCERNS / BLOCKED to the user with a 3-line
summary keyed by slot: commits made, tests green, anything left.

### Completion notification — route by where the session came from

The notification channel must match where the user is actually watching.
Scan the conversation history for incoming-message tags:

- **Discord session** — any message tagged `<channel source="discord" chat_id="..." ...>`.
  Call the Discord `reply` tool with that `chat_id` and the 3-line summary.
  This is what triggers Discord's mobile push. **Do NOT also call
  `PushNotification`** — that's a different channel and would double-ping.
  If multiple Discord messages exist, use the chat_id from the message
  that originally invoked `/run-plan` (or the most recent one in the same
  channel).

- **No Discord context** (terminal / Claude Code desktop session) — call
  `PushNotification` with subject `run-plan <slot> done` and body = the
  3-line summary. This is the laptop fallback.

- **Both present** (rare — e.g., user bridged a terminal session into
  Discord mid-run) — prefer Discord `reply`. The OS notification from
  Step 4's watcher already pinged the laptop; Discord is the one that
  hasn't heard yet.

Rule of thumb: **the user only needs to be pinged on the surface they're
currently looking at.** PushNotification ≠ Discord reply — they're
independent transports.

## Step 7a: Resuming pending completions

The harness sometimes fails to wake Claude when the background watcher
exits. To recover, **every time the skill is invoked** (any subcommand —
launch, list, status, kill), scan for done markers up front:

```bash
PENDING=$(ls /tmp/run-plan-done-*.txt 2>/dev/null)
if [ -n "$PENDING" ]; then
  echo "NOTE: pending verifications detected:"
  for d in $PENDING; do
    SLOT=$(basename "$d" .txt | sed 's/^run-plan-done-//')
    echo "  - $SLOT"
  done
fi
```

If any are present and the user didn't explicitly ask about a different
slot, surface them to the user first ("by the way, slot X finished
N minutes ago — want me to verify?") before doing whatever they asked.
This is the safety net for the missing-wake-up problem.

## Error recovery

If a slot's log ends with `BLOCKED`, surface the last 20 lines verbatim
and the contents of `## Execution log` from the plan file. Then ask the
user how to proceed — common options:

1. Fix the blocker manually, then re-launch `/run-plan <path>` to continue
   (codex will see the partial state and pick up where it left off if
   the plan's execution log is detailed).
2. Switch to inline execution by Claude for the remaining tasks.

If the log contains `auth` errors, tell the user to run `codex login`
and re-launch.

If codex hits a permission error despite the bypass flag, dump the
exact stderr line and stop — that's a fundamentally different problem
than the sandbox issue this skill was designed to avoid.

## What this skill assumes

- You trust `codex` to operate on your repo without sandbox guardrails.
  This is a deliberate choice; `--dangerously-bypass-approvals-and-sandbox`
  is the default precisely because `workspace-write` fights with git
  worktrees on macOS.
- The plan file is detailed (per `superpowers:writing-plans` conventions):
  exact file paths, code blocks, commit messages, test commands.
- The repo's tests can run from the standard paths the plan specifies.
- The current branch is the one codex should commit on.
- **For parallel runs**, each plan is launched from its own worktree on
  a separate branch — otherwise concurrent commits on the same branch
  will race and interleave unpredictably.

If any of those don't hold, use `superpowers:executing-plans` or
`superpowers:subagent-driven-development` instead — both keep Claude in
the loop per-task.

## Anti-patterns (don't do)

- **Don't use `-s workspace-write` in a worktree.** It will fail on the
  first commit. Save the user two restart cycles by going straight to
  bypass.
- **Don't run codex foreground.** Bash timeout caps at 10 min; codex
  routinely takes 30-60 min for a 10-task plan. Detach via `nohup`.
- **Don't tail -f the log in the foreground.** It blocks. Use the
  heartbeat-watcher pattern.
- **Don't poll without a wake condition.** The harness blocks chained
  short `sleep` commands. The watcher's `while kill -0; do sleep N`
  loop is the right shape.
- **Don't commit changes from this skill itself.** This skill orchestrates
  codex; codex makes the commits. If a fix is needed inside the skill's
  own run, surface it to the user.
- **Don't run two slots on the same branch.** Each parallel slot should
  live in its own worktree on its own branch. Otherwise the codex
  processes will race on `HEAD` and produce interleaved or conflicting
  commits.
