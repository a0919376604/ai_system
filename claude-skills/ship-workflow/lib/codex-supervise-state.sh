#!/usr/bin/env bash
# ship-workflow/lib/codex-supervise-state.sh
# Persist the supervise loop's state in <worktree>/.ship/codex-supervise.md so
# Phase 5 can be re-entered after a Claude session restart.
#
# This exists because sessions restarted nine times during the 19 runs that
# motivated the loop. Codex survived each one — `/run-plan` detaches via nohup —
# but the supervisor did not, and progress was re-derived by hand every time.
#
# The plan path is part of the state and is checked on resume: a state file left
# by a previous, unrelated ship must not silently resume someone else's loop.

# Values are single-line by construction. Two of them — last_class and
# blocked_at — are the supervisor's own prose about a model's report, so they can
# contain newlines. Unscrubbed, a newline in blocked_at writes a second
# `attempt:` line and the file stops meaning what it says.
_codex_state_scrub() {
  printf '%s' "$1" | tr -d '\r\n'
}

# codex_state_write <wt> <plan> <slot> <attempt> <verdict> <class> <blocked_at>
codex_state_write() {
  local wt="$1" f
  [ -d "$wt" ] || return 2
  mkdir -p "$wt/.ship" || return 2
  f="$wt/.ship/codex-supervise.md"
  {
    printf 'plan: %s\n'         "$(_codex_state_scrub "$2")"
    printf 'slot: %s\n'         "$(_codex_state_scrub "$3")"
    printf 'attempt: %s\n'      "$(_codex_state_scrub "$4")"
    printf 'last_verdict: %s\n' "$(_codex_state_scrub "$5")"
    printf 'last_class: %s\n'   "$(_codex_state_scrub "$6")"
    printf 'blocked_at: %s\n'   "$(_codex_state_scrub "$7")"
    printf 'updated: %s\n'      "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$f"
}

# codex_state_get <wt> <key> — echo the value, or nothing.
codex_state_get() {
  local f="$1/.ship/codex-supervise.md" key="$2"
  [ -f "$f" ] || return 0
  # The key lands in a sed regex. Callers pass literals today; keeping the guard
  # means a future caller cannot turn a key into a pattern.
  case "$key" in
    ''|*[!a-z0-9_]*) return 0 ;;
  esac
  sed -n "s/^$key: //p" "$f" | head -1
}

# codex_state_attempt <wt> — echo the attempt count, 0 when absent.
codex_state_attempt() {
  local n
  n=$(codex_state_get "$1" attempt)
  [ -n "$n" ] || n=0
  echo "$n"
}

# codex_state_matches <wt> <plan> — exit 0 only if the state is for this plan.
codex_state_matches() {
  local recorded
  recorded=$(codex_state_get "$1" plan)
  [ -n "$recorded" ] || return 1
  [ "$recorded" = "$2" ]
}

# codex_state_alive <wt> — exit 0 while the recorded codex process is running.
# Relaunching over a live run would put two executors on one branch.
#
# Both error directions were weighed. A false "alive" makes Phase 5 wait forever
# on a process that does not exist — a permanent stall, which is the one failure
# this whole feature exists to prevent. A false "dead" makes it relaunch, and
# /run-plan refuses a second launch for a live slot (SKILL.md:149-155). So when
# liveness cannot be established, report NOT alive.
codex_state_alive() {
  local pidf="$1/.ship/codex.pid" pid cmd match
  match="${CODEX_STATE_PROCESS_MATCH:-codex}"
  [ -f "$pidf" ] || return 1
  pid=$(tr -d '[:space:]' < "$pidf")
  # A pid must be a positive integer. `kill -0 -1` and `kill -0 0` both exit 0:
  # they are process-GROUP queries, not process queries, so a truncated or
  # hand-edited pid file would otherwise read as alive forever.
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$pid" -gt 0 ] 2>/dev/null || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  # The pid was recorded before a possible session restart, and resume can happen
  # hours later; macOS recycles pids inside that window. Confirm the live process
  # is still ours before trusting it.
  cmd=$(ps -p "$pid" -o command= 2>/dev/null) || return 1
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    *"$match"*) return 0 ;;
  esac
  return 1
}
