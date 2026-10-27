#!/usr/bin/env bats
load helpers
bats_require_minimum_version 1.5.0
setup() {
  export P="$SHIP_SKILL_ROOT/templates/pocock"
  export SCRATCH="$(make_scratch refactor-scan)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME" "$SCRATCH/10 Projects/Reports"
  S="$SCRATCH/10 Projects/Reports/refactor-scan-T"
  if [ -f "$SHIP_LIB/refactor-scan.sh" ]; then source "$SHIP_LIB/refactor-scan.sh"; fi
  case "$BATS_TEST_DESCRIPTION" in
    rs_write_rows:*)
      mkrepo
      mkdir -p docs/product
      printf '%s\n' '**R-001**' '**R-002**' '**R-003**' > docs/product/ROADMAP.md
      RM="$(make_fake_airos "$SCRATCH" demo)/10 Projects/demo/ROADMAP.md"
      ;;
  esac
}
teardown() { rm -rf "$SCRATCH"; }

@test "pocock: vendored files are byte-identical to the shas in SOURCE.md" {
  [ -f "$P/LICENSE.upstream" ]
  n=0
  while IFS= read -r line; do
    path=$(printf '%s' "$line" | sed -E 's/^- `([^`]+)`.*/\1/')
    sha=$(printf '%s' "$line" | sed -E 's/.*blob `([0-9a-f]{40})`$/\1/')
    [ "$(git hash-object "$P/$path")" = "$sha" ] || { echo "drift: $path"; return 1; }
    n=$((n + 1))
  done < <(grep -E '^- `[^`]+` · upstream `[^`]+` · blob `[0-9a-f]{40}`$' "$P/SOURCE.md")
  [ "$n" -eq 5 ]
  grep -qF '5beb35b040e3de97e54fa9e386d7e42d15c295c2' "$P/SOURCE.md"
  grep -qF 'DESIGN-IT-TWICE.md' "$P/SOURCE.md"
}

mkrepo() {
  git init -q -b main "$SCRATCH/r"
  cd "$SCRATCH/r"
  git config user.name test
  git config user.email test@example.com
  counter=0
}
commit_file() {
  local file="$1" lines="$2" when="${3:-}" stamp
  counter=$((counter + 1))
  mkdir -p "$(dirname "$file")"
  { printf '# %s\n' "$counter"; awk -v n="$lines" 'BEGIN {for(i=1;i<n;i++) print "code"}'; } > "$file"
  git add -- "$file"
  if [ -n "$when" ]; then
    stamp=$(date -v-8m '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -d "$when" '+%Y-%m-%dT%H:%M:%S')
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git commit -qm "$counter"
  else
    git commit -qm "$counter"
  fi
}

@test "rs_hotspots: lines come from HEAD, not the working tree (review attempt 1)" {
  mkrepo
  commit_file a.py 10
  commit_file b.py 20
  printf 'x\n%.0s' $(seq 40) >> a.py   # uncommitted edit: 50 lines on disk
  rm b.py                               # deleted on disk, still tracked at HEAD
  run rs_hotspots 6 10
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '20\t1\t20\tb.py\n10\t1\t10\ta.py')" ]
}

@test "rs_hotspots: churn x lines, code only, tests/migrations/deleted/non-code skipped (AC-1)" {
  mkrepo
  for i in 1 2 3; do commit_file a.py 10; done
  commit_file b.ts 100
  for i in 1 2 3 4 5; do commit_file tests/test_a.py 50; done
  for i in 1 2; do commit_file migrations/0001.py 50; done
  for i in 1 2 3 4; do commit_file README.md 50; done
  commit_file c.py 100
  git rm -q c.py && git commit -qm delete
  run rs_hotspots 6 10
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '100\t1\t100\tb.ts\n30\t3\t10\ta.py')" ]
}
@test "rs_hotspots: the window counts commits by date (AC-2)" {
  mkrepo
  commit_file a.py 10 "8 months ago"
  commit_file a.py 10
  [ "$(rs_hotspots 6 10 | cut -f2)" = "1" ]
  [ "$(rs_hotspots 12 10 | cut -f2)" = "2" ]
}
@test "rs_hotspots: top limits the lines (AC-3)" {
  mkrepo
  commit_file a.py 10
  commit_file b.ts 20
  commit_file c.go 30
  [ "$(rs_hotspots 6 2 | wc -l | tr -d ' ')" = "2" ]
}
@test "rs_hotspots: outside a git repo -> exit 1, stderr only (AC-4)" {
  cd "$SCRATCH"
  export GIT_CEILING_DIRECTORIES="$(dirname "$SCRATCH")"
  run --separate-stderr rs_hotspots
  [ "$status" -eq 1 ]; [ -z "$output" ]; [ -n "$stderr" ]
}
@test "rs_hotspots: non-ASCII and spaced paths print as real paths" {   # Review Focus 1
  mkrepo
  commit_file 中文.py 2
  commit_file "a b.py" 3
  rs_hotspots 6 10 | cut -f4 | grep -qxF '中文.py'
  rs_hotspots 6 10 | cut -f4 | grep -qxF 'a b.py'
}
@test "rs_hotspots: nothing in the window -> no output, exit 0" {   # Review Focus 5
  mkrepo
  commit_file a.py 10 "8 months ago"
  run rs_hotspots 6 10
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "rs_done_when: outcome + three guardrails, Door only with a reason (AC-5)" {
  G1='先補「固定現有行為」的測試（打在重構後模組的介面上），全綠才動結構'
  G2='搬動結構期間既有測試一行都不改且保持全綠；介面測試涵蓋後，才在最後一個獨立 commit 刪掉被取代的淺層測試'
  G3='只動結構不改行為，行為改動另開項目'
  [ "$(rs_done_when 'X 收進一個 module')" = "X 收進一個 module；${G1}；${G2}；${G3}" ]
  [ "$(rs_done_when 'X 收進一個 module' '改到 /api/x 回應')" = "X 收進一個 module；${G1}；${G2}；${G3}；Door: one-way — 改到 /api/x 回應" ]
  run rs_done_when ''
  [ "$status" -eq 2 ]
}

@test "rs_write_rows: four rows in input order, chained, linked, guarded (AC-10)" {
  run rs_write_rows "$RM" x.html < <(printf '%s\n' \
    $'new\t1\tA 收進一個 module\tsa\toa\t' \
    $'new\t2\tB 新增新介面\tsb\tob\t改到 /api/x 回應' \
    $'after\t2\tB 遷移呼叫點\tsc\toc\t' \
    $'after\t2\tB 刪舊介面\tsd\tod\t')
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | cut -f1 | tr '\n' ' ')" = "R-004 R-005 R-006 R-007 " ]
  order=$(grep -oE '^- \[ \] \*\*R-00[4-7]\*\*' "$RM" | grep -oE 'R-00[4-7]' | tr '\n' ' ')
  [ "$order" = "R-004 R-005 R-006 R-007 " ]
  grep -F '**R-006**' "$RM" | grep -qF '；接在 R-005 之後做（報告：Reports/x.ai.md#c2）'
  grep -F '**R-007**' "$RM" | grep -qF '；接在 R-006 之後做（報告：Reports/x.ai.md#c2）'
  grep -F '**R-004**' "$RM" | grep -qF 'A 收進一個 module（報告：Reports/x.ai.md#c1）'
  grep -F '**R-004**' -A1 "$RM" | grep -qF '↳ explain: sa（看報告：Reports/x.html#c1）'
  [ "$(grep -c '↳ done when: .*只動結構不改行為，行為改動另開項目' "$RM")" -eq 4 ]
  [ "$(grep -c 'Door: one-way' "$RM")" -eq 1 ]
  grep -A2 -F '**R-005**' "$RM" | grep -qF 'Door: one-way — 改到 /api/x 回應'
  ! grep -E 'R-00[4-7]' "$RM" | grep -qF 'status='
}
@test "rs_write_rows: first line after / 5 fields / empty summary / bad card -> exit 2, nothing reserved (AC-10b)" {
  before=$(shasum "$RM")
  for bad in $'after\t1\td\ts\to\t' $'new\t1\td\ts\to' $'new\t1\td\t\to\t' $'new\tx\td\ts\to\t'; do
    run rs_write_rows "$RM" x.html <<<"$bad"
    [ "$status" -eq 2 ] || { echo "accepted: $bad"; return 1; }
  done
  [ ! -s .claude/.id-reservations ]
  [ "$(shasum "$RM")" = "$before" ]
}
@test "rs_write_rows: shell-special text reaches the ROADMAP unchanged" {   # Review Focus 3
  rs_write_rows "$RM" x.html <<<$'new\t3\t改 /api/x & y「z」（w）\ts & t\to\t' >/dev/null
  grep -qF '改 /api/x & y「z」（w）（報告：Reports/x.ai.md#c3）' "$RM"
  grep -qF '↳ explain: s & t' "$RM"
}
@test "rs_write_rows: empty stdin -> exit 0, no output" {
  run rs_write_rows "$RM" x.html </dev/null
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "rs_write_rows: same rows when sourced under zsh" {   # Review Focus 4
  command -v zsh >/dev/null || skip "zsh not installed"
  printf '%s\n' $'new\t1\tA\tsa\toa\t' $'after\t1\tB\tsb\tob\t' > "$SCRATCH/rows.tsv"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_write_rows '$RM' x.html < '$SCRATCH/rows.tsv'"
  [ "$status" -eq 0 ]
  grep -F '**R-005**' "$RM" | grep -qF '；接在 R-004 之後做'
  [ "$(grep -oE '^- \[ \] \*\*R-00[45]\*\*' "$RM" | grep -oE 'R-00[45]' | tr '\n' ' ')" = "R-004 R-005 " ]
}

@test "rs_merge_label: one_way_paths at the base ref decide the label (AC-1)" {
  mkrepo
  mkdir -p .claude
  printf '%s\n' 'merge_mode: mr' 'one_way_paths:' '  - backend/app/domain/line_service.py   # LINE' '  - backend/app/domain/push_*.py' > .claude/ship-config.yml
  git add .claude/ship-config.yml && git commit -qm cfg
  [ "$(rs_merge_label HEAD backend/app/api/admin_dashboard.py)" = "自動合併" ]
  [ "$(rs_merge_label HEAD backend/app/domain/push_x.py)" = "要人審" ]
  [ "$(rs_merge_label HEAD a.py backend/app/domain/line_service.py)" = "要人審" ]
  [ "$(rs_merge_label HEAD)" = "自動合併" ]
  git rm -q .claude/ship-config.yml && git commit -qm rm
  [ "$(rs_merge_label HEAD backend/app/domain/line_service.py)" = "自動合併" ]
}

@test "rs_report_check: a valid pair passes silently; jargon in style/attributes is fine" {
  good_pair "$S"; run --separate-stderr rs_report_check "$S"
  [ "$status" -eq 0 ]; [ -z "$output" ]; [ -z "$stderr" ]
}
@test "rs_report_check: each broken rule exits 1 and names itself (AC-3)" {
  for case in script external-url anchors ai-sections cross-link jargon zoom missing; do
    good_pair "$S"; break_rule "$case" "$S"
    run --separate-stderr rs_report_check "$S"
    [ "$status" -eq 1 ] || { echo "passed: $case"; return 1; }
    [[ "$stderr" == *"rs_report_check: $case:"* ]] || { echo "wrong rule for $case: $stderr"; return 1; }
  done
}
@test "rs_report_check: same verdicts sourced under zsh" {
  command -v zsh >/dev/null || skip "zsh not installed"
  good_pair "$S"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_report_check '$S'"
  [ "$status" -eq 0 ]
  break_rule jargon "$S"
  run zsh -c "SHIP_LIB='$SHIP_LIB'; source '$SHIP_LIB/refactor-scan.sh'; rs_report_check '$S'"
  [ "$status" -eq 1 ]
}

good_pair() {
  cat > "$1.html" <<HTML
<header id="top">報告</header>
<style>
.deep{} .seam{}
</style>
<!-- Deep module
interface -->
<a href="#c1">先做</a><a href="#c1">候選</a>
<section id="c1"><a href="#z1">放大</a><div id="z1" class="zoom"></div></section>
<a href="${1##*/}.ai.md">AI</a>
<div class="deep">細節</div>
HTML
  printf '## c1 · Deepen the ticket population\n[human](%s.html)\n' "${1##*/}" > "$1.ai.md"
}
break_rule() {
  case "$1" in
    script) echo '<script>x</script>' >> "$2.html" ;;
    external-url) echo '<a href="https://cdn.example/x.js">' >> "$2.html" ;;
    anchors) echo '<section id="c3">' >> "$2.html" ;;
    ai-sections) sed '/^## c1 · /d' "$2.ai.md" > "$2.tmp"; mv "$2.tmp" "$2.ai.md" ;;
    cross-link) sed '/\.ai\.md/d' "$2.html" > "$2.tmp"; mv "$2.tmp" "$2.html" ;;
    jargon) echo '<p>Deep module</p>' >> "$2.html" ;;
    zoom) echo '<div id="z2" class="zoom">' >> "$2.html" ;;
    missing) rm "$2.ai.md" ;;
  esac
}

@test "rs_merge_label: base config gives the same labels under zsh" {
  command -v zsh >/dev/null || skip "zsh not installed"
  mkrepo
  mkdir -p .claude
  printf '%s\n' 'one_way_paths:' '  - backend/push_*.py' > .claude/ship-config.yml
  git add .claude/ship-config.yml && git commit -qm cfg
  run zsh -c 'SHIP_LIB="$1"; source "$SHIP_LIB/refactor-scan.sh"; rs_merge_label HEAD backend/push_x.py; rs_merge_label HEAD a.py; rs_merge_label HEAD' _ "$SHIP_LIB"
  [ "$status" -eq 0 ]
  [ "$output" = $'要人審\n自動合併\n自動合併' ]
}

@test "template: with {{STEM}} filled and a matching .ai.md it passes rs_report_check (AC-2)" {
  T="$SHIP_SKILL_ROOT/templates/refactor-report.html"; [ -f "$T" ]
  ! grep -qiE '<script|https?://' "$T"
  sed 's/{{STEM}}/refactor-scan-T/g' "$T" > "$S.html"
  n=$(grep -oE 'id="c[0-9]+"' "$S.html" | sort -u | wc -l | tr -d ' ')
  { echo '[human](refactor-scan-T.html)'; for i in $(seq 1 "$n"); do echo "## c$i · x"; done; } > "$S.ai.md"
  run --separate-stderr rs_report_check "$S"
  [ "$status" -eq 0 ] || { echo "$stderr"; return 1; }
}
@test "rs_report_shot: 390px iframe harness, fold line, fragment mode, skip without Chrome (AC-4)" {
  mkdir -p "$SCRATCH/bin"
  cat > "$SCRATCH/bin/chrome" <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in --screenshot=*) out="${a#--screenshot=}";; file://*) h="${a#file://}";; esac; done
dirname "$h" > "$SCRATCH_HARNESS.dir"
cp "$h" "$SCRATCH_HARNESS"; : > "$out"
SH
  chmod +x "$SCRATCH/bin/chrome"
  export RS_CHROME="$SCRATCH/bin/chrome" SCRATCH_HARNESS="$SCRATCH/harness.html"
  echo '<p>x</p>' > "$SCRATCH/10 Projects/x.html"
  rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/out.png"
  [ -f "$SCRATCH/out.png" ]
  [ ! -d "$(cat "$SCRATCH_HARNESS.dir")" ]
  grep -q 'width:390px;height:6000px' "$SCRATCH/harness.html"
  grep -q 'top:844px' "$SCRATCH/harness.html"
  grep -qF '10%20Projects/x.html"' "$SCRATCH/harness.html"
  rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/z.png" z1
  grep -q 'width:390px;height:844px' "$SCRATCH/harness.html"
  grep -qF 'x.html#z1"' "$SCRATCH/harness.html"
  [ ! -d "$(cat "$SCRATCH_HARNESS.dir")" ]
  RS_CHROME=/nonexistent run --separate-stderr rs_report_shot "$SCRATCH/10 Projects/x.html" "$SCRATCH/n.png"
  [ "$status" -eq 0 ]; [[ "$stderr" == *"rs_report_shot: Chrome not found — skipped"* ]]
}

@test "rs_report_shot: encodes reserved path characters under bash and zsh" {
  cat > "$SCRATCH/chrome" <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in --screenshot=*) out="${a#--screenshot=}";; file://*) h="${a#file://}";; esac; done
cp "$h" "$SCRATCH_HARNESS"
: > "$out"
SH
  chmod +x "$SCRATCH/chrome"
  export RS_CHROME="$SCRATCH/chrome" SCRATCH_HARNESS="$SCRATCH/harness.html"
  echo x > "$SCRATCH/10 Projects/x%#?.html"
  for shell in bash zsh; do
    command -v "$shell" >/dev/null || continue
    run "$shell" -c 'source "$1/refactor-scan.sh"; rs_report_shot "$2" "$3" z1' _ "$SHIP_LIB" "$SCRATCH/10 Projects/x%#?.html" "$SCRATCH/out.png"
    [ "$status" -eq 0 ]
    grep -qF '10%20Projects/x%25%23%3F.html#z1"' "$SCRATCH/harness.html"
  done
}

@test "rs_report_shot: Chrome failure or absent PNG fails and removes harness" {
  cat > "$SCRATCH/chrome" <<'SH'
#!/bin/sh
for a in "$@"; do case "$a" in file://*) dirname "${a#file://}" > "$SCRATCH_HARNESS";; esac; done
exit "$CHROME_EXIT"
SH
  chmod +x "$SCRATCH/chrome"
  export RS_CHROME="$SCRATCH/chrome" SCRATCH_HARNESS="$SCRATCH/dir"
  echo x > "$S.html"
  for code in 0 3; do
    CHROME_EXIT="$code" run rs_report_shot "$S.html" "$SCRATCH/out.png"
    [ "$status" -eq 1 ]
    [ ! -d "$(cat "$SCRATCH_HARNESS")" ]
  done
}

@test "rs_write_rows: stem and html basename produce identical rows" {
  for suffix in x x.html; do
    mkdir -p "$SCRATCH/$suffix"
    git init -q -b main "$SCRATCH/$suffix/repo"
    cd "$SCRATCH/$suffix/repo"
    mkdir -p docs/product
    printf '%s\n' '**R-001**' '**R-002**' '**R-003**' > docs/product/ROADMAP.md
    roadmap="$(make_fake_airos "$SCRATCH/$suffix" demo)/10 Projects/demo/ROADMAP.md"
    rs_write_rows "$roadmap" "$suffix" <<<$'new\t1\tA\tsa\toa\t' > /dev/null
  done
  cmp "$SCRATCH/x/airos/10 Projects/demo/ROADMAP.md" "$SCRATCH/x.html/airos/10 Projects/demo/ROADMAP.md"
}

@test "rs_report_shot: Chrome's own log stays quiet on success and surfaces on failure (review attempt 1)" {
  mkdir -p "$SCRATCH/bin"
  cat > "$SCRATCH/bin/chrome" <<'SH'
#!/bin/sh
echo "CVDisplayLinkCreateWithCGDisplay failed" >&2
for a in "$@"; do case "$a" in --screenshot=*) out="${a#--screenshot=}";; esac; done
[ -n "$CHROME_FAIL" ] && exit 3
: > "$out"
SH
  chmod +x "$SCRATCH/bin/chrome"
  echo '<p>x</p>' > "$SCRATCH/x.html"
  RS_CHROME="$SCRATCH/bin/chrome" run --separate-stderr rs_report_shot "$SCRATCH/x.html" "$SCRATCH/ok.png"
  [ "$status" -eq 0 ] || return 1
  [ -z "$stderr" ] || { echo "noise leaked: $stderr"; return 1; }
  CHROME_FAIL=1 RS_CHROME="$SCRATCH/bin/chrome" run --separate-stderr rs_report_shot "$SCRATCH/x.html" "$SCRATCH/bad.png"
  [ "$status" -eq 1 ] || return 1
  [[ "$stderr" == *"CVDisplayLinkCreateWithCGDisplay failed"* ]] || return 1
}

@test "rs_report_check: event-handler attributes and javascript: URLs count as script (security pass)" {
  for bad in '<img src="x" onerror="fetch(1)">' '<svg onload=alert(1)></svg>' '<a href="javascript:void(0)">x</a>'; do
    good_pair "$S"; printf '%s\n' "$bad" >> "$S.html"
    run --separate-stderr rs_report_check "$S"
    [ "$status" -eq 1 ] || { echo "passed: $bad"; return 1; }
    [[ "$stderr" == *"rs_report_check: script:"* ]] || { echo "wrong rule for $bad: $stderr"; return 1; }
  done
  good_pair "$S"; printf '%s\n' '<p>button 不算 onclick 文字</p>' >> "$S.html"
  run --separate-stderr rs_report_check "$S"
  [ "$status" -eq 0 ] || { echo "visible text flagged: $stderr"; return 1; }
}

@test "rs_report_shot: Chrome gets no file-access flag (security pass)" {
  mkdir -p "$SCRATCH/bin"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$@" > "$ARGS_OUT"' 'for a in "$@"; do case "$a" in --screenshot=*) : > "${a#--screenshot=}";; esac; done' > "$SCRATCH/bin/chrome"
  chmod +x "$SCRATCH/bin/chrome"
  echo '<p>x</p>' > "$SCRATCH/x.html"
  ARGS_OUT="$SCRATCH/args" RS_CHROME="$SCRATCH/bin/chrome" rs_report_shot "$SCRATCH/x.html" "$SCRATCH/o.png"
  [ -s "$SCRATCH/args" ] || return 1
  ! grep -qF -- '--allow-file-access-from-files' "$SCRATCH/args"
}
