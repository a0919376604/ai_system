#!/usr/bin/env bash
# Phase glue for ship-next. Command blocks do not share a shell, so values
# needed by later phases live in <worktree>/.ship/state.env.

sn_state_set() {
  [ -n "$1" ] || { echo "sn_state_set: empty worktree" >&2; return 2; }
  local sn_file="$1/.ship/state.env" sn_key="$2" sn_value="$3"
  mkdir -p "$1/.ship" || return
  if [ -f "$sn_file" ]; then
    command grep -v "^${sn_key}=" "$sn_file" > "$sn_file.tmp" || true
  else
    : > "$sn_file.tmp"
  fi
  printf '%s=%q\n' "$sn_key" "$sn_value" >> "$sn_file.tmp"
  mv "$sn_file.tmp" "$sn_file"
}

# sn_state_archive_path <ID> — where Phase 9 keeps the state once the worktree is
# gone: inside the repo's own git dir, not a predictable path in shared /tmp that
# another local user could pre-create and have sourced.
sn_state_archive_path() {
  echo "$(git rev-parse --path-format=absolute --git-common-dir)/ship-${1}-state.env"
}

sn_state_load() {
  if [ -f "$1/.ship/state.env" ]; then
    source "$1/.ship/state.env"
  fi
}

# sn_status <worktree> <phase> [note] — record this ship's phase for the Roadmap 檢視
# plugin (R-013) in <vault project>/ship-status/<ID>.json. ID and BRANCH come from
# <worktree>/.ship/state.env, else from the caller's ID/BRANCH (/ship-land passes the
# main checkout). Observability only: any failure prints one WARN and returns 0.
sn_status() {
  local wt="${1:-}" phase="${2:-}" note="${3:-}" id branch proj dir tmp now
  case "$phase" in
    brainstorm|plan|build|review|landing|in-review|done|blocked) ;;
    *) echo "WARN: sn_status: unknown phase '$phase' — not recorded" >&2; return 0 ;;
  esac
  id=$(sn_state_load "$wt"; printf '%s' "${ID:-}")
  branch=$(sn_state_load "$wt"; printf '%s' "${BRANCH:-}")
  case "$id" in
    R-[0-9]*) case "$id" in *[!A-Za-z0-9.-]*) id="" ;; esac ;;
    *) id="" ;;
  esac
  [ -n "$id" ] || { echo "WARN: sn_status: no R-NNN ID for '$wt' — $phase not recorded" >&2; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "WARN: sn_status: jq not found — $phase not recorded" >&2; return 0; }
  proj=$(cd "$wt" 2>/dev/null && "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/airos-binding.sh" project_path 2>/dev/null) || proj=""
  # Never mkdir the project itself: a wrong name would plant a bogus vault folder (R-004).
  if [ -z "$proj" ] || [ ! -d "$proj" ]; then
    echo "WARN: sn_status: no vault project for '$wt' — $phase not recorded" >&2; return 0
  fi
  dir="$proj/ship-status"
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if mkdir -p "$dir" 2>/dev/null && tmp=$(mktemp "$dir/.$id.XXXXXX" 2>/dev/null); then
    if { cat "$dir/$id.json" 2>/dev/null || echo '{}'; } \
        | jq --arg id "$id" --arg phase "$phase" --arg at "$now" --arg branch "$branch" --arg note "$note" \
            '.id = $id | .phase = $phase | .updated = $at | .branch = $branch | .note = $note
             | .phases = ((.phases // []) + [{phase: $phase, at: $at, note: $note}])' > "$tmp" 2>/dev/null \
        && mv "$tmp" "$dir/$id.json" 2>/dev/null; then
      return 0
    fi
    rm -f "$tmp"
  fi
  echo "WARN: sn_status: could not write $dir/$id.json — $phase not recorded" >&2
  return 0
}

sn_mech_gates() {
  local WORKTREE="$1" ORIG_BRANCH="$2" PLAN_FILE
  cd "$WORKTREE" || return
  # shellcheck disable=SC1091
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/test-budget.sh"

  # (a) Refactor violation: a `Seam: none` task must not add test lines.
  MECH_BLOCKERS=0
  PLAN_FILE="$3"
  if [ -f "$PLAN_FILE" ] && grep -qF 'Seam: none' "$PLAN_FILE"; then
    for sha in $(git log --format=%H "${ORIG_BRANCH}..HEAD"); do
      SUBJ=$(git log -1 --format=%s "$sha")
      TASK_NO=$(echo "$SUBJ" | grep -oE 'Task [0-9]+' | head -1)
      [ -z "$TASK_NO" ] && continue
      grep -A6 "### ${TASK_NO}:" "$PLAN_FILE" | grep -qF 'Seam: none' || continue
      ADDED=$(tb_test_lines_added "$sha")
      if [ "${ADDED:-0}" -gt 0 ]; then
        echo "🛑 blocking: refactor task added test lines (${TASK_NO}, +${ADDED} in tests)" >&2
        MECH_BLOCKERS=$((MECH_BLOCKERS + 1))
      fi
    done
  fi

  # (b) Test budget, relative to this repo's own baseline.
  BASELINE_RATIO_BP=$(tb_baseline_ratio)
  SHIP_RATIO_BP=$(tb_ship_ratio "$ORIG_BRANCH" HEAD)
  TB_LINES=$(tb_ship_lines "$ORIG_BRANCH" HEAD)
  TEST_LINES_ADDED=${TB_LINES% *}; SRC_LINES_ADDED=${TB_LINES#* }
  TEST_BUDGET_VERDICT=$(tb_verdict "$SHIP_RATIO_BP" "$BASELINE_RATIO_BP")

  if tb_shadow_active; then
    echo "Test budget: ship=${SHIP_RATIO_BP}bp baseline=${BASELINE_RATIO_BP}bp verdict=${TEST_BUDGET_VERDICT} (shadow mode — reporting only)"
    TEST_BUDGET_VERDICT=pass
  else
    echo "Test budget: ship=${SHIP_RATIO_BP}bp baseline=${BASELINE_RATIO_BP}bp verdict=${TEST_BUDGET_VERDICT}"
    [ "$TEST_BUDGET_VERDICT" = "blocking" ] && MECH_BLOCKERS=$((MECH_BLOCKERS + 1))
  fi

  # (c) Extra review checks handed to the LLM reviewer.
  mkdir -p .ship
  cat > .ship/review-extra-checks.md <<'CHECKS'
In addition to your normal findings, tag any finding that matches one of these
categories by appending the literal tag to the finding line:

- `[seam-violation]` — a test asserts something not declared in the spec's `## Seams`
- `[assertion-roulette]` — one test bundles multiple unrelated assertions
- `[weak-assertion]` — an assertion that cannot fail for any valid input
- `[pre-existing]` — the defect exists on the base branch already, and this diff
  neither introduces nor worsens it. Put the tag right after the severity tag and add
  an indented line `Base evidence: <file>:<line> exists unchanged on <base branch>`.
  A pre-existing finding is reported but never blocks this ship.

Keep your usual severity tag as well; these categories are orthogonal to severity.
CHECKS
  sn_state_set "$WORKTREE" MECH_BLOCKERS "$MECH_BLOCKERS"
  sn_state_set "$WORKTREE" TEST_BUDGET_VERDICT "$TEST_BUDGET_VERDICT"
  sn_state_set "$WORKTREE" SHIP_RATIO_BP "$SHIP_RATIO_BP"
  sn_state_set "$WORKTREE" BASELINE_RATIO_BP "$BASELINE_RATIO_BP"
  sn_state_set "$WORKTREE" TEST_LINES_ADDED "$TEST_LINES_ADDED"
  sn_state_set "$WORKTREE" SRC_LINES_ADDED "$SRC_LINES_ADDED"
}

sn_codex_after_exit() {
  local WORKTREE="$1" PLAN="$2" SLOT="$3"
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/codex-verdict.sh"
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/codex-rounds.sh"
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/codex-supervise-state.sh"
  CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
  CODEX_LOG="/tmp/run-plan-codex-${SLOT}.log"
  CODEX_FINAL_VERDICT=$(codex_verdict "$CODEX_LOG")
  CODEX_REASON=$(codex_verdict_reason "$CODEX_LOG")

  # Extract the report by the same whole-log rule codex_verdict uses. An empty
  # extraction is an error, never an empty round: preserving the executor's
  # bullet-list report verbatim is the point of this loop.
  CODEX_REPORT="/tmp/codex-report-${SLOT}.md"
  if ! codex_report_extract "$CODEX_LOG" "$CODEX_REPORT"; then
    echo "codex: no report could be extracted from $CODEX_LOG" >&2
    CODEX_FINAL_VERDICT=infra
    CODEX_REASON="no extractable report — $CODEX_REASON"
  fi

  case "$CODEX_FINAL_VERDICT" in
    done|done_with_concerns) CODEX_ROUTE=continue ;;
    blocked)                 CODEX_ROUTE=classify ;;
    infra)                   CODEX_ROUTE=stop_infra ;;
    *)                       CODEX_ROUTE=stop_infra ;;
  esac
  if [ "$CODEX_ROUTE" = continue ]; then
    codex_round_append "$WORKTREE" "$((CODEX_ATTEMPT + 1))" "$CODEX_FINAL_VERDICT" \
      "$CODEX_REPORT" "n/a" "executor completed"
    CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
    # Clear the blocked state. Phase 6 re-enters this loop for fix-plans and
    # must not inherit a verdict from a round that has already been resolved.
    codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" \
      "$CODEX_FINAL_VERDICT" "n/a" "n/a"
    rm -f "$WORKTREE/.ship/codex.pid"

  fi
  # R-013: the Roadmap 檢視 plugin shows the stop; the reason is only known here.
  if [ "$CODEX_ROUTE" = stop_infra ]; then
    sn_status "$WORKTREE" blocked "codex infra: $CODEX_REASON"
  fi
  sn_state_set "$WORKTREE" CODEX_FINAL_VERDICT "$CODEX_FINAL_VERDICT"
  sn_state_set "$WORKTREE" CODEX_ROUNDS "${CODEX_ROUNDS:-0}"
  sn_state_set "$WORKTREE" CODEX_REPORT "$CODEX_REPORT"
  sn_state_set "$WORKTREE" CODEX_REASON "$CODEX_REASON"
  printf 'CODEX_ROUTE=%s\nCODEX_REASON=%s\n' "$CODEX_ROUTE" "$CODEX_REASON"
}

sn_ship_body() {
  sn_state_load "$1"
  local WORKTREE="$1" ID="$2" SLUG="$3" SHIP_BODY="$4"
  cd "$WORKTREE" || return
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
   MERGE_MODE=$(merge_mode)

   ROADMAP_PATH="$("${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/airos-binding.sh" project_path)/ROADMAP.md"
   ROW=$(grep "\*\*${ID}\*\*" "$ROADMAP_PATH" | head -1)
   DONE_WHEN=$(grep -A1 "\*\*${ID}\*\*" "$ROADMAP_PATH" | grep "↳ done when:" | sed 's/.*↳ done when: //' | head -1)

   SHIP_TITLE="feat: ${ID} ${DESCRIPTION}"
   SHIP_BODY="$4"
   cat > "$SHIP_BODY" <<EOF
↳ done when: ${DONE_WHEN}

Tasks (from docs/plans/${ID}-${SLUG}.md):
$( [ -f "docs/plans/${ID}-${SLUG}.md" ] && grep -E '^### Task [0-9]+:' "docs/plans/${ID}-${SLUG}.md" | sed 's/^### /  - /')

Code review (awesome-skills/code-review-skill):
- blocking: 0 ✓
- major:    ${MAJOR_COUNT} (see plan §Execution log)
- minor:    ${MINOR_COUNT}
- praise:   ${PRAISE_COUNT}

Security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})"; fi)

Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
Spec:  docs/specs/${ID}-${SLUG}.md (removed by /ship-compound; kept in the "spec: ${ID}" commit and the vault Specs/)
Plan:  docs/plans/${ID}-${SLUG}.md (removed by /ship-compound; kept in the "plan: ${ID}" commit)
Notes: docs/roadmap-notes/${ID}-${SLUG}.md (if exists)

🤖 ${BRANCH}
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
  sn_state_set "$WORKTREE" SHIP_TITLE "$SHIP_TITLE"
  sn_state_set "$WORKTREE" SHIP_BODY "$SHIP_BODY"
}

sn_land() {
  sn_state_load "$1"
  local WORKTREE="$1" ID="$2" BRANCH="$3" ORIG_BRANCH="$4" SHIP_TITLE="$5" SHIP_BODY="$6"
  # The checkout /ship-next ran from (Phase 2 stored it) — a linked worktree is
  # valid; the main checkout is only the fallback for state written before REPO.
  REPO="${REPO:-$(dirname "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-common-dir)")}"
   cd "$REPO"
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
   MERGE_MODE=$(merge_mode)

   case "$MERGE_MODE" in
     squash)
       git checkout "$ORIG_BRANCH" || exit 1
       git merge --squash "$BRANCH"
       git commit -m "$(printf '%s\n\n%s' "$SHIP_TITLE" "$(cat "$SHIP_BODY")")"
       SHIP_REVIEW_URL=""
       ;;

     mr)
       # The branch must exist on the remote before a review can point at it.
       git push -u origin "$BRANCH" || {
         echo "push failed — not opening a review for a branch the remote cannot see" >&2
         exit 1
       }
       MR_CMD=$(forge_mr_cmd "$BRANCH" "$ORIG_BRANCH" "$SHIP_TITLE" "$SHIP_BODY") || {
         echo "unknown forge for origin — push succeeded, open the review by hand" >&2
         exit 1
       }
       echo "opening review: $MR_CMD"
       SHIP_REVIEW_URL=$(eval "$MR_CMD" | grep -oE 'https?://[^[:space:]]+' | tail -1)
       [ -n "$SHIP_REVIEW_URL" ] || {
         echo "the review command produced no URL — check it by hand before continuing" >&2
         exit 1
       }
       echo "review open: $SHIP_REVIEW_URL"
       ;;
   esac
  MERGE_SHA=$(git rev-parse HEAD)
  sn_state_set "$WORKTREE" SHIP_REVIEW_URL "$SHIP_REVIEW_URL"
  sn_state_set "$WORKTREE" MERGE_SHA "$MERGE_SHA"
}

sn_capture() {
  sn_state_load "$1"
  local WORKTREE="$1" ID="$2"
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
  MERGE_MODE=$(merge_mode)
   # Phase 9 is a different shell from Phase 5: nothing sourced there is in
   # scope here. Source what this phase calls.
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/codex-rounds.sh"

   # Whether Phase 6 ran the security review (step 1.5 wrote it). Step 4 is its own
   # shell and runs after step 1 removed the worktree, so copy the file out — a shell
   # variable set here would be gone by then. No state → no copy, never a stale one.
   cp "$WORKTREE/.ship/security-review-state" "/tmp/ship-${ID}-security-review-state" 2>/dev/null \
     || rm -f "/tmp/ship-${ID}-security-review-state"

   CODEX_ROUNDS_ARCHIVE=""
   CODEX_LAST_FINDINGS=""
   if [ -f "$WORKTREE/.ship/codex-rounds.md" ]; then
     CODEX_ROUNDS=$(codex_round_count "$WORKTREE")
     CODEX_LAST_FINDINGS=$(codex_round_last_findings "$WORKTREE")
     # Bound what goes into the notification. A report with a long bullet list
     # would otherwise be interpolated whole into $SUMMARY and can exceed a
     # Discord message limit — at which point the operator gets nothing at all
     # rather than a truncated list. The archive has the full text.
     CODEX_FINDINGS_TOTAL=$(printf '%s\n' "$CODEX_LAST_FINDINGS" | grep -c '^- ' || true)
     if [ "${CODEX_FINDINGS_TOTAL:-0}" -gt 12 ] 2>/dev/null; then
       CODEX_LAST_FINDINGS="$(printf '%s\n' "$CODEX_LAST_FINDINGS" | head -12)
... and $((CODEX_FINDINGS_TOTAL - 12)) more — see the archive below"
     fi
     # Copy it out. `.ship/` dies with the worktree, and a post-mortem of an
     # unattended overnight run has nothing else to read.
     CODEX_ROUNDS_ARCHIVE="/tmp/ship-${ID}-codex-rounds.md"
     cp "$WORKTREE/.ship/codex-rounds.md" "$CODEX_ROUNDS_ARCHIVE" 2>/dev/null \
       || CODEX_ROUNDS_ARCHIVE=""
   fi
  sn_state_set "$WORKTREE" CODEX_ROUNDS "${CODEX_ROUNDS:-0}"
  sn_state_set "$WORKTREE" CODEX_LAST_FINDINGS "$CODEX_LAST_FINDINGS"
  sn_state_set "$WORKTREE" CODEX_ROUNDS_ARCHIVE "$CODEX_ROUNDS_ARCHIVE"
  cp "$WORKTREE/.ship/state.env" "$(sn_state_archive_path "$ID")"
}

sn_cleanup() {
  local WORKTREE="$1" BRANCH="$2"
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     echo "review open — the worktree is kept at $WORKTREE"
   else
     git worktree remove "$WORKTREE"
   fi
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     echo "review open — branch $BRANCH is kept (the remote review needs it)"
   else
     git branch -d "$BRANCH"
   fi
}

sn_log() {
  if [ -n "$1" ] && [ -f "$1/.ship/state.env" ]; then
    sn_state_load "$1"
  elif [ -n "$1" ] && [ -f "$(sn_state_archive_path "$2")" ]; then
    source "$(sn_state_archive_path "$2")"
  fi
  local WORKTREE="$1" ID="$2"
  local SHIP_LOG_ROW="$3"
   # Only ships that actually ran codex carry a codex fragment. Ships that ran
   # executor 1 or 2 have no codex state, and an empty "codex:  round(s)" on
   # every row is noise that hides the rows where it means something.
   CODEX_LOG_FRAGMENT=""
   if [ "${CODEX_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
     CODEX_LOG_FRAGMENT=", codex: ${CODEX_ROUNDS} round(s) ${CODEX_FINAL_VERDICT}"
   fi
   if [ -z "${SHIP_LOG_ROW:-}" ]; then
     SHIP_LOG_ROW="| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp${CODEX_LOG_FRAGMENT}) | n |"
   fi
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/ship-log.sh"
   # Each block runs in its own shell: resolve the mode here, never rely on a
   # MERGE_MODE set by an earlier block.
   # shellcheck disable=SC1091
   source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
   MERGE_MODE=$(merge_mode)
   if [ "$MERGE_MODE" = "mr" ]; then
     (
       [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ] \
         || { echo "Phase 9: WORKTREE is not set — nothing logged" >&2; exit 1; }
       CUR=$(git -C "$WORKTREE" branch --show-current)
       case "$CUR" in
         "ship/${ID}-"*) : ;;
         *) echo "Phase 9: refusing to log into '$CUR' — expected ship/${ID}-*" >&2; exit 1 ;;
       esac
       (cd "$WORKTREE" && ship_log "$SHIP_LOG_ROW")
     )
   else
     ship_log "$SHIP_LOG_ROW"
     git add docs/learnings/_log.md
     git commit -m "log: ship ${ID}"
   fi
}

sn_summary() {
  if [ -n "$1" ] && [ -f "$1/.ship/state.env" ]; then
    sn_state_load "$1"
  elif [ -n "$1" ] && [ -f "$(sn_state_archive_path "$2")" ]; then
    source "$(sn_state_archive_path "$2")"
  fi
  local WORKTREE="$1" ID="$2"
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
  MERGE_MODE=$(merge_mode)
   if [ "$AUTO" = "1" ]; then
     # Built from what step 0 captured, so it survives the worktree removal.
     CODEX_SUMMARY_BLOCK=""
     if [ "${CODEX_ROUNDS:-0}" -gt 0 ] 2>/dev/null; then
       CODEX_SUMMARY_BLOCK="
• codex: ${CODEX_ROUNDS} round(s), final ${CODEX_FINAL_VERDICT}
${CODEX_LAST_FINDINGS}
• full round history: ${CODEX_ROUNDS_ARCHIVE:-(not archived)}"
     fi
     SUMMARY="✅ ${ID} ${DESCRIPTION} shipped (squash ${MERGE_SHA})
• blocking: 0 ✓
• major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
• minor: ${MINOR_COUNT}
• praise: ${PRAISE_COUNT}
• security review: $(if [ "$(cat "/tmp/ship-${ID}-security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
• CONTEXT.md: ${CONTEXT_MD_STATUS}
• Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
• ponytail: ${PONYTAIL_STATUS}${CODEX_SUMMARY_BLOCK}
• decisions log: ${WORKTREE}/.claude/.ship-auto-decisions.md (kept in worktree pre-cleanup; copy if you want post-mortem)"

     printf '%s\n' "$SUMMARY"
   fi
}
