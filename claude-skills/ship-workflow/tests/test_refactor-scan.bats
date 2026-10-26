#!/usr/bin/env bats
load helpers
bats_require_minimum_version 1.5.0
setup() {
  export P="$SHIP_SKILL_ROOT/templates/pocock"
  export SCRATCH="$(make_scratch refactor-scan)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
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
  grep -F '**R-006**' "$RM" | grep -qF '；接在 R-005 之後做（報告：Reports/x.html#c2）'
  grep -F '**R-007**' "$RM" | grep -qF '；接在 R-006 之後做（報告：Reports/x.html#c2）'
  grep -F '**R-004**' "$RM" | grep -qF 'A 收進一個 module（報告：Reports/x.html#c1）'
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
  grep -qF '改 /api/x & y「z」（w）（報告：Reports/x.html#c3）' "$RM"
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
