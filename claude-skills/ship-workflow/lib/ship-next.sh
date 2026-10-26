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

# _sn_dep_names <kind> — dependency names in the manifest on stdin, one per line.
# Only real dependency sections count (R-015 review: scripts, engines, overrides,
# classifiers, keywords and lint selections are not dependencies).
_sn_dep_names() {
  case "$1" in
    package.json)
      command -v jq >/dev/null 2>&1 || { echo "WARN: jq not found — package.json dependencies not checked" >&2; return 0; }
      jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
             | map(select(type == "object") | keys[]) | .[]' 2>/dev/null ;;
    requirements)
      awk '{ l=$0; sub(/#.*/,"",l); gsub(/^[ \t]+|[ \t]+$/,"",l)
             if (l == "" || l ~ /^-/) next
             n=l; sub(/[<>=!~;\[ ].*/,"",n); print n }' | _sn_pep503 ;;
    pyproject)
      awk '
        /^[ \t]*\[/ { t=$0; gsub(/[ \t\[\]]/,"",t); inarr=0; next }
        t == "project" && /^[ \t]*dependencies[ \t]*=/ { inarr=1 }
        (t == "project.optional-dependencies" || t == "dependency-groups") && /=[ \t]*\[/ { inarr=1 }
        inarr {
          rest=$0
          sub(/^[ \t]*("[^"]*"|[A-Za-z0-9_.-]+)[ \t]*=[ \t]*/,"",rest)   # only a "key =" opener
          gsub(/\{[^}]*\}/,"",rest)                              # {include-group = "…"} is not a package
          sub(/^[ \t]*#.*/,"",rest); sub(/[ \t]#.*$/,"",rest)  # comments
          bare=rest; gsub(/"[^"]*"/,"",bare)                     # brackets outside strings
          while (match(rest, /"[A-Za-z0-9][A-Za-z0-9._-]*/)) {
            print substr(rest, RSTART+1, RLENGTH-1)
            rest=substr(rest, RSTART+RLENGTH); sub(/^[^"]*"/,"",rest)
          }
          if (bare ~ /\]/) inarr=0
          next
        }
        (t == "tool.poetry.dependencies" || t ~ /^tool\.poetry\.group\..*\.dependencies$/) &&
          /^[ \t]*[A-Za-z0-9][A-Za-z0-9._-]*[ \t]*=/ {
          n=$0; sub(/^[ \t]*/,"",n); sub(/[ \t]*=.*/,"",n); if (n != "python") print n }' | _sn_pep503 ;;
  esac
}

# _sn_pep503 — Python package names compare case-insensitively with -, _ and .
# equivalent (PEP 503), so "FastAPI" -> "fastapi" is an edit, not a new dependency.
_sn_pep503() { tr 'A-Z' 'a-z' | sed -E 's/[-_.]+/-/g'; }

# sn_new_deps <base> <head> — one "<file>\t<name>" line per dependency present in a
# manifest at <head> but not at merge-base(<base>,<head>) (R-015). Comparing parsed
# dependency sets, not diff lines, means formatting edits and version bumps never count.
sn_new_deps() {
  local base="$1" head="$2" mb f kind old new
  mb=$(git merge-base "$base" "$head" 2>/dev/null) || return 0
  # quotePath off: a non-ASCII directory would otherwise arrive C-quoted and match no case.
  git -c core.quotePath=false diff --name-only "$mb" "$head" 2>/dev/null | while IFS= read -r f; do
    case "$(basename "$f")" in
      package.json) kind=package.json ;;
      requirements*.txt) kind=requirements ;;
      pyproject.toml) kind=pyproject ;;
      *) continue ;;
    esac
    old=$(git show "$mb:$f" 2>/dev/null | tr -d '\r' | _sn_dep_names "$kind" | sort -u)
    new=$(git show "$head:$f" 2>/dev/null | tr -d '\r' | _sn_dep_names "$kind" | sort -u)
    printf '%s\n' "$new" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      printf '%s\n' "$old" | grep -qxF -- "$n" || printf '%s\t%s\n' "$f" "$n"
    done
  done
}

sn_mech_gates() {
  local WORKTREE="$1" ORIG_BRANCH="$2" PLAN_FILE
  cd "$WORKTREE" || return
  sn_state_load "$WORKTREE"   # ID, SLUG for the dependency gate
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

  # (d) A new dependency needs a reason in the spec's Decisions (R-015; ponytail:
  # never add a dependency for what a few lines can do). Explicit marker only.
  local spec_file="docs/specs/${ID:-}-${SLUG:-}.md" dep_file dep
  while IFS="$(printf '\t')" read -r dep_file dep; do
    [ -n "$dep" ] || continue
    # Whole-name match on any "New dependency:" line, so one line can list several
    # ("New dependency: react, react-dom — new LIFF app") and react-dom never vouches for react.
    if [ -f "$spec_file" ] && grep -F 'New dependency:' "$spec_file" | sed 's/.*New dependency://' \
         | tr -c 'A-Za-z0-9@/._-' '\n' | _sn_pep503 | grep -qxF -- "$(printf '%s' "$dep" | _sn_pep503)"; then
      continue
    fi
    echo "🛑 blocking: new dependency ${dep} (${dep_file}) without a 'New dependency: ${dep}' line in the spec's Decisions" >&2
    MECH_BLOCKERS=$((MECH_BLOCKERS + 1))
  done <<EOF
$(sn_new_deps "$ORIG_BRANCH" HEAD)
EOF

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

Over-engineering (ponytail-review's vocabulary; `.ship/ponytail-rules.md` is the ladder).
These findings are nit or important, never blocking on their own:

- `[ponytail:delete]` — dead code, unused flexibility, a speculative feature
- `[ponytail:stdlib]` — hand-rolled what the standard library ships (name the function)
- `[ponytail:native]` — a dependency or code doing what the platform already does (name the feature)
- `[ponytail:yagni]` — an abstraction with one implementation, config nobody sets, a layer with one caller
- `[ponytail:shrink]` — the same logic in fewer lines (show the shorter form)

Keep your usual severity tag as well; these categories are orthogonal to severity.
CHECKS
  sn_state_set "$WORKTREE" MECH_BLOCKERS "$MECH_BLOCKERS"
  sn_state_set "$WORKTREE" TEST_BUDGET_VERDICT "$TEST_BUDGET_VERDICT"
  sn_state_set "$WORKTREE" SHIP_RATIO_BP "$SHIP_RATIO_BP"
  sn_state_set "$WORKTREE" BASELINE_RATIO_BP "$BASELINE_RATIO_BP"
  sn_state_set "$WORKTREE" TEST_LINES_ADDED "$TEST_LINES_ADDED"
  sn_state_set "$WORKTREE" SRC_LINES_ADDED "$SRC_LINES_ADDED"
}

# Shell case globs behave consistently even when the caller is zsh.
_sn_glob_match() {
  bash -c 'case "$2" in $1) exit 0;; esac; exit 1' _ "$1" "$2"
}

_sn_one_way_paths() {
  if ! command -v _sr_base_file >/dev/null 2>&1; then
    source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/security-review.sh"
  fi
  { _sr_base_file "$1" .claude/ship-config.yml || true; } | awk '
    /^one_way_paths:/ { collect=1; next }
    collect && /^[^[:space:]]/ { exit }
    collect && /^[[:space:]]+- / {
      sub(/^[[:space:]]+-[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^[\047"]|[\047"]$/, "")
      if (length) print
    }'
}

sn_door() {
  sn_state_set "$1" SHIP_DOOR one-way
  sn_state_set "$1" SHIP_DOOR_REASONS 'door check failed — treated as one-way'
  sn_state_set "$1" SHIP_MERGE_MODE mr
  sn_state_set "$1" SHIP_AUTO_MERGE 0
  sn_state_load "$1"
  cd "$1" || return
  local wt="$PWD" spec_line door reasons paths f glob dep repo_mode mode auto_merge
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
  spec_line=$(awk '/^## Decisions/{d=1;next} /^## /{d=0} d && /^[-*[:space:]]*Door:[[:space:]]*(one-way|two-way)/ {
      if (!first) first=$0
      if ($0 ~ /^[-*[:space:]]*Door:[[:space:]]*one-way/) {first=$0; exit}
    } END {if (first) print first}' \
    "docs/specs/${ID}-${SLUG}.md" 2>/dev/null | sed 's/^[-*[:space:]]*Door:[[:space:]]*/Door: /')
  door=one-way
  reasons="spec: ${spec_line:-no Door line}"
  case "$spec_line" in 'Door: two-way'*) door=two-way ;; esac
  paths=$(git -c core.quotePath=false diff --name-only "$(git merge-base "$ORIG_BRANCH" HEAD)" HEAD) || return
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for glob in '*migrations/*' '*/alembic/versions/*' 'db/migrate/*'; do
      if _sn_glob_match "$glob" "$f"; then
        reasons="$reasons; signal: migration $f"; door=one-way; break
      fi
    done
    for glob in 'Dockerfile*' '*/Dockerfile*' 'docker-compose*' '*/docker-compose*' '.gitlab-ci.yml' '.github/workflows/*' 'env_template*' '*/env_template*'; do
      if _sn_glob_match "$glob" "$f"; then
        reasons="$reasons; signal: deploy $f"; door=one-way; break
      fi
    done
  done <<< "$paths"
  while IFS="$(printf '\t')" read -r f dep; do
    [ -n "$dep" ] || continue
    reasons="$reasons; signal: new dependency $dep ($f)"; door=one-way
  done < <(sn_new_deps "$ORIG_BRANCH" HEAD)
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if _sn_glob_match "$glob" "$f"; then
        reasons="$reasons; signal: one_way_paths $f"; door=one-way
      fi
    done <<< "$paths"
  done < <(_sn_one_way_paths "$ORIG_BRANCH")
  repo_mode=$(SHIP_MERGE_MODE= merge_mode)
  mode=mr; auto_merge=0
  if [ "$door" = two-way ]; then
    if [ "$repo_mode" = squash ]; then mode=squash; else auto_merge=1; fi
  fi
  sn_state_set "$wt" SHIP_DOOR "$door"
  sn_state_set "$wt" SHIP_DOOR_REASONS "$reasons"
  sn_state_set "$wt" SHIP_MERGE_MODE "$mode"
  sn_state_set "$wt" SHIP_AUTO_MERGE "$auto_merge"
  printf 'door: %s\n' "$door"
  printf '%s\n' "$reasons" | sed 's/; /\
/g'
}

# Render invocation context for the read-only Spec reviewer.
sn_spec_review_render() {
  sn_state_load "$1"
  local spec="$1/docs/specs/${ID}-${SLUG}.md"
  [ -f "$spec" ] || { echo "spec review: no spec at $spec" >&2; return 1; }
  {
    printf 'Read docs/specs/%s-%s.md in full. Read the diff with git diff %s...HEAD.\n' "$ID" "$SLUG" "$ORIG_BRANCH"
    cat <<'PROMPT'
Check the spec's acceptance criteria: Given-When-Then rows, AC-N rows, or a
"done when" line. With no such rows, check its stated requirements.
Report gaps only with evidence; do not block on criteria the diff cannot show.

Missing, partial or wrong criteria use these forms:
🔴 [blocking] [spec:missing] <what>
   Spec: "<the spec line, quoted>"
🔴 [blocking] [spec:wrong] <what> — <file>:<line>
   Spec: "<the spec line, quoted>"

Behaviour the spec did not ask for uses:
🟢 [nit] [spec:extra] [ponytail:yagni] <what> — <file>:<line>
Use 🟡 [important] in place of 🟢 [nit], keeping both tags, when it adds surface
area (a flag, an option, a public function). Extras never block on their own.

Before reporting a criterion as missing, look for it in the worktree, not only
in the diff. A criterion met by existing code is not missing.
Never tag a spec finding [pre-existing].
When nothing is found, write the single line:
No spec gaps.

Write only the report to the output path you are given. Edit nothing else.
PROMPT
  } > "$1/.ship/spec-review-prompt.md"
}

# Fail closed before the report can be counted by code-review-parse.sh.
sn_spec_review_check() {
  [ -f "$1" ] || { echo "spec report: missing file: $1" >&2; return 1; }
  awk '
    function fail(reason, line) {
      print "spec report: " reason ": " line > "/dev/stderr"
      failed = 1
      exit 1
    }
    function close_block() {
      if (needs_quote && !quoted) fail("missing Spec: quote", finding)
      finding = ""; needs_quote = 0; quoted = 0
    }
    {
      sub(/\r$/, "")
      sub(/[[:space:]]+$/, "")
      if ($0 == "") { close_block(); next }
      if ($0 ~ /^[[:space:]]/) {
        if (finding == "") fail("detail outside finding", $0)
        detail = $0
        sub(/^[[:space:]]+/, "", detail)
        if (index(detail, "🔴") == 1 || index(detail, "🟡") == 1 ||
            index(detail, "🟢") == 1 || index(detail, "🎉") == 1 ||
            index(detail, "[") == 1) fail("indented finding", $0)
        if (index(detail, "Spec:") == 1) quoted = 1
        next
      }
      close_block()
      if ($0 == "No spec gaps.") { sentinel = 1; next }
      blocking = index($0, "🔴") == 1 || index($0, "[blocking]") == 1
      if (!(index($0, "🔴") == 1 || index($0, "🟡") == 1 ||
            index($0, "🟢") == 1 ||
            $0 ~ /^\[(blocking|important|major|minor|nit)\]/))
        fail("expected spec finding", $0)
      tags = $0
      if (gsub(/\[spec:(missing|wrong|extra)\]/, "", tags) != 1)
        fail("expected exactly one spec tag", $0)
      if (index($0, "[pre-existing]")) fail("pre-existing spec finding", $0)
      needs_quote = $0 ~ /\[spec:(missing|wrong)\]/
      if (needs_quote && !blocking) fail("spec gap must block", $0)
      if (!needs_quote && (blocking || !index($0, "[ponytail:yagni]")))
        fail("extra must be non-blocking ponytail:yagni", $0)
      finding = $0
      findings++
    }
    END {
      if (failed) exit 1
      close_block()
      if (findings && sentinel) fail("findings contradict sentinel", "No spec gaps.")
      if (!findings && !sentinel) fail("empty report", "")
    }
  ' "$1"
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

# sn_done_when <roadmap> <ID> — the row's done-when, read from the whole `↳` block under
# it (R-020). A fixed `grep -A1` broke once rows gained a `↳ explain:` line first.
sn_done_when() {
  ID_MARK="**$2**" awk '
    found && /^[[:space:]]*↳/ { if (sub(/^[[:space:]]*↳ done when: /, "")) { print; exit } next }
    found { exit }
    index($0, ENVIRON["ID_MARK"]) { found = 1 }
  ' "$1" 2>/dev/null
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
   DONE_WHEN=$(sn_done_when "$ROADMAP_PATH" "$ID")

   SHIP_TITLE="feat: ${ID} ${DESCRIPTION}"
   SHIP_BODY="$4"
   {
     if [ -f "$WORKTREE/.ship/pr-head.md" ]; then
       awk '/^## / {blast=0} /^\*\*Blast Radius:\*\*/ {blast=1} !blast' "$WORKTREE/.ship/pr-head.md"
     else
       echo "WARN: missing $WORKTREE/.ship/pr-head.md — Summary and Evidence unavailable" >&2
     fi
     printf '\n## Merge Danger\n**Door:** %s\n' "${SHIP_DOOR:-one-way}"
     printf '%s\n' "${SHIP_DOOR_REASONS:-}" | awk 'BEGIN {RS="; "} NF {sub(/\n$/, ""); print "- " $0}'
     if [ -f "$WORKTREE/.ship/pr-head.md" ] && command grep -q '^\*\*Blast Radius:\*\*' "$WORKTREE/.ship/pr-head.md"; then
       awk '/^## / {blast=0} /^\*\*Blast Radius:\*\*/ {blast=1} blast' "$WORKTREE/.ship/pr-head.md"
     else
       echo '**Blast Radius:** unstated'
     fi
     printf '\n## Ship details\n'
   } > "$SHIP_BODY"
   cat >> "$SHIP_BODY" <<EOF
↳ done when: ${DONE_WHEN}

Tasks (from docs/plans/${ID}-${SLUG}.md):
$( [ -f "docs/plans/${ID}-${SLUG}.md" ] && grep -E '^### Task [0-9]+:' "docs/plans/${ID}-${SLUG}.md" | sed 's/^### /  - /')

Code review (awesome-skills/code-review-skill):
- blocking: 0 ✓
- major:    ${MAJOR_COUNT} (see plan §Execution log)
- minor:    ${MINOR_COUNT}
- praise:   ${PRAISE_COUNT}

Security review: $(if [ "$(cat "$WORKTREE/.ship/security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "blocking 0 ✓ (security findings: ${SECURITY_COUNT:-0}, pre-existing: ${PRE_EXISTING_COUNT:-0})"; fi)
Spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed

Tests: +${TEST_LINES_ADDED} / Src: +${SRC_LINES_ADDED}  (ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp)
Spec:  docs/specs/${ID}-${SLUG}.md (removed by /ship-compound; kept in the "spec: ${ID}" commit and the vault Specs/)
Plan:  docs/plans/${ID}-${SLUG}.md (removed by /ship-compound; kept in the "plan: ${ID}" commit)
Notes: docs/roadmap-notes/${ID}-${SLUG}.md (if exists)

🤖 ${BRANCH}
${SHIP_COAUTHOR:-Co-Authored-By: Claude <noreply@anthropic.com>}
EOF
  sn_state_set "$WORKTREE" SHIP_TITLE "$SHIP_TITLE"
  sn_state_set "$WORKTREE" SHIP_BODY "$SHIP_BODY"
}

sn_auto_merge() {
  local url="$1" cli iid pipeline elapsed=0 wait="${SN_PIPELINE_WAIT:-90}" cmd
  source "${SHIP_LIB:-$HOME/.claude/skills/ship-workflow/lib}/merge-mode.sh"
  cli=$(forge_cli) || { echo "WARN: unknown forge — auto-merge not set" >&2; return 1; }
  if [ "$cli" = glab ] && ! command -v jq >/dev/null 2>&1; then
    echo "WARN: jq not found — auto-merge not set" >&2; return 1
  fi
  if [ "$cli" = glab ]; then iid=$(_sn_mr_iid "$url") || return 1; fi
  while :; do
    case "$cli" in
      glab)
        pipeline=$(glab mr view "$iid" -F json | jq -r '.head_pipeline.status // empty') || pipeline=
        case "$pipeline" in
          running|pending|created|waiting_for_resource|preparing|scheduled|success) ;;
          '') ;;
          *) echo "WARN: pipeline $pipeline — auto-merge not set" >&2; return 1 ;;
        esac
        ;;
      gh) pipeline=$(gh pr checks "$url" 2>/dev/null) ;;
    esac
    if [ -n "$pipeline" ]; then
      cmd=$(forge_automerge_cmd "$url") || return 1
      if eval "$cmd"; then return 0; fi
      echo "WARN: auto-merge command failed on $url — a human merges it" >&2
      return 1
    fi
    [ "$elapsed" -lt "$wait" ] || break
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "WARN: no pipeline on $url after ${wait}s — auto-merge not set; a human merges it" >&2
  return 1
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
         echo "unknown forge for origin — push succeeded, open the review by hand$(if [ "${SHIP_DOOR:-}" = one-way ]; then printf ' — a one-way door needs a review; merge it by hand after one'; fi)" >&2
         exit 1
       }
       echo "opening review: $MR_CMD"
       SHIP_REVIEW_URL=$(eval "$MR_CMD" | grep -oE 'https?://[^[:space:]]+' | tail -1)
       [ -n "$SHIP_REVIEW_URL" ] || {
         echo "the review command produced no URL — check it by hand before continuing" >&2
         exit 1
       }
       echo "review open: $SHIP_REVIEW_URL"
       SHIP_AUTO_MERGED=0
       if [ "${SHIP_AUTO_MERGE:-0}" = 1 ] && sn_auto_merge "$SHIP_REVIEW_URL"; then SHIP_AUTO_MERGED=1; fi
       sn_state_set "$WORKTREE" SHIP_AUTO_MERGED "$SHIP_AUTO_MERGED"
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
  if [ -f "$1/.ship/state.env" ]; then sn_state_load "$1"; fi
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
     SHIP_LOG_ROW="| $(date +%Y-%m-%d\ %H:%M) | ship-next | ${ID} | shipped (review: blocking=0, major=${MAJOR_COUNT}, ponytail=${PONYTAIL_COUNT:-0}, spec_gaps=${SPEC_GAPS_FOUND:-0}, door=${SHIP_DOOR:-unset}, ratio ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp${CODEX_LOG_FRAGMENT}) | n |"
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
     local landing="awaiting human review: ${SHIP_REVIEW_URL:-}"
     if [ "$MERGE_MODE" = squash ]; then
       landing=squash-merged
     elif [ "${SHIP_AUTO_MERGED:-0}" = 1 ]; then
       landing='auto-merge set (merges after CI)'
     fi
     SUMMARY="✅ ${ID} ${DESCRIPTION} shipped (squash ${MERGE_SHA})
• blocking: 0 ✓
• major: ${MAJOR_COUNT} → IDEA-NNN auto-logged
• minor: ${MINOR_COUNT}
• praise: ${PRAISE_COUNT}
• security review: $(if [ "$(cat "/tmp/ship-${ID}-security-review-state" 2>/dev/null)" = off ]; then echo "off (ship-config on ${ORIG_BRANCH})"; else echo "${SECURITY_COUNT:-0} finding(s), pre-existing ${PRE_EXISTING_COUNT:-0} → IDEA-NNN"; fi)
• spec review: ${SPEC_GAPS_FOUND:-0} gap(s) found on attempt 1, all closed
• door: ${SHIP_DOOR:-unset} → ${landing}
• CONTEXT.md: ${CONTEXT_MD_STATUS}
• Test budget: ship ${SHIP_RATIO_BP}bp vs baseline ${BASELINE_RATIO_BP}bp (${TEST_BUDGET_VERDICT})
• ponytail: ${PONYTAIL_STATUS} · ${PONYTAIL_COUNT:-0} over-engineering finding(s)${CODEX_SUMMARY_BLOCK}
• decisions log: ${WORKTREE}/.claude/.ship-auto-decisions.md (kept in worktree pre-cleanup; copy if you want post-mortem)"

     printf '%s\n' "$SUMMARY"
   fi
}
