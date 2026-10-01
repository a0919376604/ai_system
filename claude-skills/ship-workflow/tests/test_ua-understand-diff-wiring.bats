#!/usr/bin/env bats
# Phase 6 and ship-compound's blast-radius work is delegated to the UA plugin's
# /understand-diff instead of re-deriving it from the graph in bash. The hand-rolled
# version produced Changed + Affected components only; /understand-diff additionally
# gives affected layers, a risk assessment and a dashboard overlay, and its staleness
# check is more precise.
load helpers

setup() {
  export LIB="$SHIP_LIB/ua-integration.sh"
  export NEXT="$SHIP_SKILL_ROOT/commands/ship-next.md"
  export COMPOUND="$SHIP_SKILL_ROOT/commands/ship-compound.md"
}

@test "the duplicated graph-walking helpers are gone from the lib" {
  for fn in _ua_extract_layers ua_get_diff_report ua_get_shipped_facts; do
    if grep -qE "^${fn}\(\)" "$LIB"; then
      echo "$fn is still defined; /understand-diff supersedes it"
      return 1
    fi
  done
}

@test "helpers Phase 3 still needs are kept" {
  for fn in ua_check_installed ua_check_drift ua_get_pre_brainstorm_context \
            _ua_extract_file_summary _ua_extract_callers; do
    grep -qE "^${fn}\(\)" "$LIB" || { echo "$fn was deleted but Phase 3 needs it"; return 1; }
  done
}

@test "nothing calls a deleted helper any more" {
  # Executable content only. The prose deliberately names these functions while
  # recording why they were removed, and a whole-file scan would match its own
  # explanation — the same trap a guard in this repo fell into two changes ago.
  for f in "$NEXT" "$COMPOUND"; do
    code=$(awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f' "$f")
    for fn in _ua_extract_layers ua_get_diff_report ua_get_shipped_facts; do
      if echo "$code" | grep -qF "$fn"; then
        echo "$(basename "$f") still calls $fn"
        return 1
      fi
    done
  done
  for fn in _ua_extract_layers ua_get_diff_report ua_get_shipped_facts; do
    if grep -v '^[[:space:]]*#' "$LIB" | grep -qF "$fn"; then
      echo "the lib still references $fn"
      return 1
    fi
  done
}

@test "Phase 6 invokes understand-diff and keeps writing the report file" {
  block=$(awk '/^## Phase 6/,/^0\.5\./' "$NEXT")
  echo "$block" | grep -qF 'understand-diff' || { echo "Phase 6 does not invoke understand-diff"; return 1; }
  echo "$block" | grep -qF '.ship/ua-diff-report.md' || { echo "Phase 6 stopped writing the report file"; return 1; }
  # The REMINDERS cross-ref is independent bash and must survive untouched.
  echo "$block" | grep -qF 'REMINDERS.md' || { echo "the REMINDERS cross-ref was lost"; return 1; }
}

@test "ship-compound invokes understand-diff and fills the template without sed-parsing it" {
  block=$(awk '/^5\.5\./,/^6\./' "$COMPOUND")
  echo "$block" | grep -qF 'understand-diff' || { echo "Step 5.5 does not invoke understand-diff"; return 1; }
  echo "$block" | grep -qF 'CASE_ELI5.md' || { echo "the CASE_ELI5 render was lost"; return 1; }
  # Parsing prose for `### Changed components` was the contract this change removes.
  # Check the bash, not the paragraph that explains the removal.
  code=$(echo "$block" | awk '/^[[:space:]]*```bash[[:space:]]*$/{f=1;next} /^[[:space:]]*```[[:space:]]*$/{f=0} f')
  if echo "$code" | grep -qF 'sed -n'; then
    echo "Step 5.5 still sed-parses the report; LLM prose is not a contract"
    return 1
  fi
}

@test "ua_check_drift scopes its diff to the project, like understand-diff does" {
  # A hash mismatch alone is not stale when the project diff is empty — a sibling
  # monorepo project moving the hash must not mark this graph stale.
  grep -qF "':(exclude).ua'" "$LIB" || { echo "drift check does not exclude graph artifacts"; return 1; }
  awk '/^ua_check_drift\(\)/,/^}/' "$LIB" | grep -qF -- '-- .' \
    || { echo "drift check lacks the '-- .' project pathspec"; return 1; }
}
