#!/usr/bin/env bash
# ship-workflow/lib/tdd-rules.sh
# The testing rules handed to the Phase 5 executor, in three layers.
#
# They used to be four hardcoded `echo` lines inside commands/ship-next.md.
# That made the one layer that shapes what the executor WRITES the only layer
# in this workflow that could not compound: CONTEXT.md grows, learnings
# accumulate, patterns get promoted — the rules stayed frozen at whatever the
# skill author typed. Adding one meant editing and re-shipping the skill.
#
# Worse, the skill is a single symlinked copy shared by every repo, so a
# lesson learned in one repo was asserted at all of them. An early rule cited
# "conftest.py was changed 31 times in this project" — a measurement from one
# product repo, shipped to every other.
#
#   universal  — true everywhere; lives here, in the skill
#   learned    — this repo's own scars, git-tracked: one fragment per ship in
#                docs/tdd-rules.d/<R-NNN>.md, plus the legacy docs/tdd-rules.md
#                if the repo has one. Fragments exist because every ship used to
#                append to the one file, and parallel MRs conflicted on its tail.
#   seams      — this ship only; from the spec's ## Seams table
#
# Caps exist for the same reason CONTEXT.md has them: rules accumulate and
# nothing expires them. Forty rules nobody reads is the original problem in a
# new shape — context spent on instructions instead of on the work.

TDD_RULES_ENFORCED_MARK=' · enforced by '
TDD_RULES_MAX=20
TDD_RULES_REL="docs/tdd-rules.md"
TDD_RULES_DIR_REL="docs/tdd-rules.d"

# tdd_rules_path — echo the repo's learned-rules file, or nothing.
tdd_rules_path() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  [ -f "$root/$TDD_RULES_REL" ] || return 0
  echo "$root/$TDD_RULES_REL"
}

# tdd_rules_files — every learned-rule file: the legacy file first, then the
# per-ship fragments by name. `find`, not a glob: an unmatched glob is an error
# in zsh, and these helpers run under the operator's zsh.
tdd_rules_files() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$root" ] || return 0
  if [ -f "$root/$TDD_RULES_REL" ]; then echo "$root/$TDD_RULES_REL"; fi
  if [ -d "$root/$TDD_RULES_DIR_REL" ]; then
    find "$root/$TDD_RULES_DIR_REL" -maxdepth 1 -type f -name '*.md' | sort
  fi
  return 0
}

# tdd_rules_bullets — every learned rule line (`- ...`), in tdd_rules_files order.
tdd_rules_bullets() {
  local f
  tdd_rules_files | while IFS= read -r f; do
    grep '^- ' "$f" 2>/dev/null || true
  done
  return 0
}

# tdd_rules_count — echo how many judgment rules, 0 when none.
tdd_rules_count() {
  tdd_rules_bullets | awk -v mark="$TDD_RULES_ENFORCED_MARK" '
    !index($0,mark) { n++ } END { print n+0 }
  '
}

# tdd_rules_table — all learned rules, their enforcers and original sources.
tdd_rules_table() {
  tdd_rules_bullets | awk -v mark="$TDD_RULES_ENFORCED_MARK" '
    function escape(cell) { gsub(/\|/, "\\|", cell); return cell }
    NR == 1 {
      print "| Rule | Enforced by | Source |"
      print "| --- | --- | --- |"
    }
    {
      rule=substr($0,3); enforcer="judgment"; source="—"
      pos=index(rule,mark)
      if (pos) {
        enforcer=substr(rule,pos+length(mark))
        rule=substr(rule,1,pos-1)
      }
      pos=index(rule," ← ")
      if (pos) {
        source=substr(rule,pos+length(" ← "))
        rule=substr(rule,1,pos-1)
      }
      print "| " escape(rule) " | " escape(enforcer) " | " escape(source) " |"
    }
  '
}

# tdd_rules_over_cap — exit 0 when the repo has more rules than it can carry.
tdd_rules_over_cap() {
  local n
  n=$(tdd_rules_count)
  [ "$n" -gt "$TDD_RULES_MAX" ]
}

# tdd_rules_unsourced — learned rules with no `← R-NNN` provenance.
# Without a source a rule cannot be judged still-relevant, so it can never be
# pruned. That is how the file silently becomes unprunable.
tdd_rules_unsourced() {
  tdd_rules_bullets | grep -v '← R-[0-9]' || true
}

# tdd_rules_append <R-NNN> <rule text> [<enforcer>] — add a sourced rule
# to this ship's fragment. With an enforcer, promote an existing judgment
# rule in place (including legacy rules), preserving its original source.
# Already-enforced rules are unchanged; matching rule text is literal.
tdd_rules_append() {
  local id="$1" text="$2" enforcer="${3:-}" root f tmp
  case "$id" in
    R-[0-9]*) : ;;
    *) echo "tdd_rules_append: need an R-NNN source, got '$id'" >&2; return 2 ;;
  esac
  [ -n "$text" ] || { echo "tdd_rules_append: empty rule" >&2; return 2; }
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
  if [ -z "$enforcer" ]; then
    tdd_rules_bullets | command grep -qF -- "$text" && return 0
  else
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if TDD_TEXT="$text" awk -v mark="$TDD_RULES_ENFORCED_MARK" '
        /^- / { rule=substr($0,3); pos=index(rule,mark);
          if (pos) rule=substr(rule,1,pos-1)
          pos=index(rule," ← ");
          if (pos) rule=substr(rule,1,pos-1)
          if (rule == ENVIRON["TDD_TEXT"]) found=1
        }
        END { exit !found }
      ' "$f"; then
        tmp=$(mktemp "${f}.XXXXXX") || return 2
        TDD_TEXT="$text" TDD_ENFORCER="$enforcer" awk -v mark="$TDD_RULES_ENFORCED_MARK" '
          /^- / { rule=substr($0,3); pos=index(rule,mark);
            if (pos) rule=substr(rule,1,pos-1)
            pos=index(rule," ← ");
            if (pos) rule=substr(rule,1,pos-1)
            if (rule == ENVIRON["TDD_TEXT"] && !index($0,mark))
              $0=$0 mark ENVIRON["TDD_ENFORCER"]
          }
          { print }
        ' "$f" > "$tmp" && mv "$tmp" "$f" || { rm -f "$tmp"; return 2; }
        return 0
      fi
    done <<EOF
$(tdd_rules_files)
EOF
  fi
  f="$root/$TDD_RULES_DIR_REL/$id.md"
  mkdir -p "$(dirname "$f")" || return 2
  if [ -n "$enforcer" ]; then
    printf -- '- %s ← %s%s%s\n' "$text" "$id" "$TDD_RULES_ENFORCED_MARK" "$enforcer" >> "$f"
  else
    printf -- '- %s ← %s\n' "$text" "$id" >> "$f"
  fi
}

# tdd_rules_render <R-NNN> <spec file> — the full ruleset for one ship.
tdd_rules_render() {
  local id="$1" spec="$2" learned
  echo "# TDD rules for ${id}"
  echo
  echo "1. Tests attach only to the seams listed below."
  echo "2. \`Seam: none\` tasks add no tests. Behavior unchanged => tests unchanged."
  echo "3. Existing shared fixtures are READ-ONLY. Need a different shape? Add a new"
  echo "   fixture. Editing a shared one edits every test that uses it."
  echo "4. One test, one behavior. Do not pack unrelated assertions into a single test."
  echo "5. Assert on behavior at the seam, never on how it is implemented. A test that"
  echo "   must change when the implementation changes, while the behavior did not,"
  echo "   reports churn instead of regressions."
  learned=$(tdd_rules_bullets | awk -v mark="$TDD_RULES_ENFORCED_MARK" '!index($0,mark)')
  if [ -n "$learned" ]; then
    echo
    echo "## Learned in this repo"
    printf '%s\n' "$learned"
  fi
  echo
  echo "## Declared seams"
  [ -f "$spec" ] && sed -n '/^## Seams/,/^## /p' "$spec" | sed '$d'
  return 0
}

# tdd_rules_prove <red-ref> <check-command> <check-path>...
# Overlay only the named checks in a detached worktree, prove red then green.
tdd_rules_prove() (
  local red_ref="${1:-}" check_cmd="${2:-}" red_sha green_sha tmp check_path red_exit
  if [ "$#" -lt 3 ] || ! red_sha=$(git rev-parse --verify --quiet "${red_ref}^{commit}"); then
    echo 'usage: tdd_rules_prove <red-ref> <check-command> <check-path>...' >&2
    return 2
  fi
  shift 2
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/tdd-prove.XXXXXX") || return 2
  trap 'git worktree remove --force "$tmp/wt" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
  git worktree add --detach -q "$tmp/wt" "$red_sha" || return 2
  for check_path in "$@"; do
    mkdir -p "$tmp/wt/$(dirname "$check_path")" || return 2
    cp -- "$check_path" "$tmp/wt/$check_path" || return 2
  done
  red_exit=0
  (cd "$tmp/wt" && bash -c "$check_cmd") >"$tmp/red.out" 2>&1 || red_exit=$?
  if [ "$red_exit" -eq 0 ]; then
    echo 'check does not fail on the mistake' >&2
    return 1
  fi
  if ! bash -c "$check_cmd" >"$tmp/green.out" 2>&1; then
    echo 'check fails on the fix' >&2
    return 1
  fi
  red_sha=$(git rev-parse --short=7 "$red_sha") || return 2
  green_sha=$(git rev-parse --short=7 HEAD) || return 2
  printf 'proof: red at %s (exit %s) · green at %s\n' "$red_sha" "$red_exit" "$green_sha"
  # ponytail: an environmental red (e.g. a missing dependency) looks like a
  # real red in a bare worktree; inspect this tail before accepting the proof.
  tail -3 "$tmp/red.out" | sed 's/^/  /'
)
