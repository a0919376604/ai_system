#!/usr/bin/env bats
load helpers
bats_require_minimum_version 1.5.0

setup() {
  AD="$SHIP_SKILL_ROOT/../draw-arch/lib"
  FX="$SHIP_SKILL_ROOT/tests/fixtures/draw-arch"
  S="$(make_scratch draw-arch)"
}
teardown() { rm -rf "$S"; }

@test "page is deterministic and has every section in order" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 "$AD/render.py" page "$FX/clean.json" "$S/b.html"
  cmp "$S/a.html" "$S/b.html"
  python3 - "$S/a.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
positions = [s.index(x) for x in ('<h1', 'class="diagram"', 'class="route"', '<table class="cond"', '<footer')]
assert positions == sorted(positions)
route = s[s.index('<section class="route"'):s.index('<table class="cond"')]
assert route.count('class="badge"') == 1
assert '<tr><th>節點</th><th>做什麼</th><th>什麼條件走到這、離開時往哪</th><th>程式碼</th></tr>' in s
PY
  [ "$(grep -c 'data-node="a"' "$S/a.html")" -ge 1 ] || return 1
  grep -qF 'data-edge="a->b"' "$S/a.html" || return 1
  [ "$(grep -c 'class="warn"' "$S/a.html")" -eq 1 ] || return 1
  grep -qF 'Webhook / PostgreSQL' "$S/a.html" || return 1
  grep -qF '<footer>Commit 0123456789abcdef0123456789abcdef01234567</footer>' "$S/a.html" || return 1
}

@test "escapes code-like text in text and attributes" {
  python3 - "$FX/clean.json" "$S/escaped.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
s['title'] = '<script>alert(1)</script>'
s['nodes'][0]['sub'] = 'List[str] & "q"'
s['edges'][0]['path'] = 'M0 0" onload="x'
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f)
PY
  python3 "$AD/render.py" page "$S/escaped.json" "$S/out.html"
  grep -qF '&lt;script&gt;' "$S/out.html" || return 1
  grep -qF '&amp;' "$S/out.html" || return 1
  [ "$(grep -c '<script' "$S/out.html" || true)" -eq 0 ] || return 1
  [ "$(grep -cE ' on[a-z]+=' "$S/out.html" || true)" -eq 0 ] || return 1
  [ -z "$(grep -oE 'https?://[^"]*' "$S/out.html" | grep -v '^http://www.w3.org/' || true)" ] || return 1
}

@test "minimal spec renders without optional sections" {
  python3 "$AD/render.py" page "$FX/minimal.json" "$S/out.html"
  [ "$(grep -c 'class="route"' "$S/out.html" || true)" -eq 0 ] || return 1
  [ "$(grep -c '<table' "$S/out.html" || true)" -eq 0 ] || return 1
  [ "$(grep -c '<h2></h2>' "$S/out.html" || true)" -eq 0 ] || return 1
}

@test "not-JSON input exits 2 and writes nothing" {
  echo '{nope' > "$S/bad.json"
  run python3 "$AD/render.py" page "$S/bad.json" "$S/out.html"
  [ "$status" -eq 2 ] || return 1
  [ ! -e "$S/out.html" ] || return 1
}

make_pack() {
  mkdir -p "$1"
  python3 - "$FX/clean.json" "$1" <<'PY'
import json, sys
from pathlib import Path
s = json.load(open(sys.argv[1], encoding='utf-8'))
for topic in ('langgraph', 'csat', 'overview'):
    s['topic'] = topic
    (Path(sys.argv[2]) / (topic + '.json')).write_text(json.dumps(s), encoding='utf-8')
PY
}

@test "index lists overview first then by topic" {
  make_pack "$S/pack"
  python3 "$AD/render.py" index "$S/pack" "$S/index.html"
  python3 - "$S/index.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
assert s.index('href="overview.html"') < s.index('href="csat.html"') < s.index('href="langgraph.html"')
PY
  [ "$(grep -c 'href="' "$S/index.html")" -eq 3 ] || return 1
}

@test "index refuses an unreadable spec" {
  make_pack "$S/pack"
  echo '{x' > "$S/pack/broken.json"
  run python3 "$AD/render.py" index "$S/pack" "$S/index.html"
  [ "$status" -eq 2 ] || return 1
  echo "$output" | grep -qF 'broken.json' || return 1
  [ ! -e "$S/index.html" ] || return 1
}

@test "index and page handle paths with spaces" {
  mkdir -p "$S/10 Projects/pack"
  cp "$FX/clean.json" "$S/10 Projects/pack/demo.json"
  python3 "$AD/render.py" page "$S/10 Projects/pack/demo.json" "$S/10 Projects/pack/demo.html"
  python3 "$AD/render.py" index "$S/10 Projects/pack" "$S/10 Projects/pack/index.html"
  [ -f "$S/10 Projects/pack/demo.html" ] || return 1
  [ -f "$S/10 Projects/pack/index.html" ] || return 1
}

mutate() {
  python3 - "$FX/clean.json" "$S/m.json" "$1" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
exec(sys.argv[3])
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f)
PY
}

check_rule() {
  run python3 "$AD/check.py" "$S/m.json"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  echo "$output" | grep -q "^check: $1:" || return 1
  [ -z "$(echo "$output" | grep '^check: ' | grep -v "^check: $1:" || true)" ] || { echo "$output"; return 1; }
}

@test "check clean spec passes" {
  run python3 "$AD/check.py" "$FX/clean.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || return 1
}

@test "check duplicate id" {
  mutate "s['nodes'].append(dict(s['nodes'][0], x=20, y=200))"
  check_rule id
}

@test "check dangling edge" {
  mutate "s['edges'][0]['to']='zz'"
  check_rule edge
}

@test "check dangling condition id in a list" {
  mutate "s['conditions'][1]['node']=['a','zz']"
  check_rule edge
}

@test "check off canvas" {
  mutate "s['nodes'][1]['x']=500"
  check_rule bounds
}

@test "check overlapping nodes" {
  mutate "s['nodes'][1].update(x=150, y=90)"
  check_rule overlap
}

@test "check label on a node" {
  mutate "s['edges'][0]['lx']=100"
  check_rule label
}

@test "check title too wide" {
  mutate "s['nodes'][0]['title']='這是一個非常非常非常非常長的標題文字'"
  check_rule fit
}

@test "check unknown kind" {
  mutate "s['nodes'][0]['kind']='xx'"
  check_rule schema
}

@test "check bad path" {
  mutate "s['edges'][0]['path']='M0 0\" onload=\"x'"
  check_rule schema
}

mutate_lg() {
  python3 - "$FX/lg.json" "$S/lg.json" "$1" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
exec(sys.argv[3])
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f)
PY
}

@test "langgraph spec matching the AST passes without running the file" {
  run python3 "$AD/check.py" "$FX/lg.json" --repo "$FX"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || return 1
}

@test "langgraph missing edge is named" {
  mutate_lg "s['edges']=[e for e in s['edges'] if (e['from'],e['to']) != ('b','END')]"
  run python3 "$AD/check.py" "$S/lg.json" --repo "$FX"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'check: langgraph: missing edge b->END' || return 1
}

@test "langgraph extra node is named" {
  mutate_lg "s['nodes'].append(dict(id='c',kind='be',x=700,y=40,w=140,h=50,title='c'))"
  run python3 "$AD/check.py" "$S/lg.json" --repo "$FX"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'check: langgraph: extra node c' || return 1
}

@test "langgraph unmapped conditional edge is reported" {
  mutate_lg "s['langgraph']['file']='graph_unmapped.py'; s['edges']=[e for e in s['edges'] if e['to'] != 'END2']"
  run python3 "$AD/check.py" "$S/lg.json" --repo "$FX"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'check: langgraph: unresolved conditional edge from a' || return 1
}

@test "skill files exist and the spec-format example passes check.py" {
  grep -qF 'name: draw-arch' "$AD/../SKILL.md" || return 1
  [ -f "$AD/../references/spec-format.md" ] || return 1
  [ -f "$AD/../references/cocoon-style.md" ] || return 1
  awk '/^```json/{inside=1;next} inside && /^```/{exit} inside{print}' \
    "$AD/../references/spec-format.md" > "$S/example.json"
  run python3 "$AD/check.py" "$S/example.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run python3 "$AD/render.py" page "$S/example.json" "$S/example.html"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF 'MIT License' "$AD/../references/cocoon-style.md" || return 1
}

@test "check rejects external region paint" {
  mutate "s['regions'][0]['color']='url(https://example.com/paint.svg#p)'"
  check_rule schema
}

@test "page refuses external region paint without writing output" {
  mutate "s['regions'][0]['color']='url(https://example.com/paint.svg#p)'"
  run python3 "$AD/render.py" page "$S/m.json" "$S/out.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/out.html" ] || return 1
}

@test "page preserves visible URL text without literal external URLs" {
  mutate "s['title']='API https://example.com/x'"
  python3 "$AD/render.py" page "$S/m.json" "$S/out.html"
  python3 - "$S/out.html" <<'PY'
import re, sys
from html.parser import HTMLParser
class Text(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
    def handle_data(self, data):
        self.parts.append(data)
s = open(sys.argv[1], encoding='utf-8').read()
p = Text()
p.feed(s)
assert 'API https://example.com/x' in p.parts
assert not re.search(r'https?://(?!www\.w3\.org/)', s)
PY
}

@test "index refuses topics that could link to external pages" {
  mutate "s['topic']='https://example.com/pack'"
  mkdir -p "$S/pack"
  cp "$S/m.json" "$S/pack/demo.json"
  run python3 "$AD/render.py" index "$S/pack" "$S/index.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/index.html" ] || return 1
}

@test "page refuses topics that could inject SVG resource identifiers" {
  mutate "s['topic']='demo) url(https://example.com/paint.svg#p)'"
  run python3 "$AD/render.py" page "$S/m.json" "$S/out.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/out.html" ] || return 1
}

@test "legend defaults to the kinds the diagram uses, in zh-TW" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 - "$S/a.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
legend = s[s.index('<div class="legend">'):]
legend = legend[:legend.index('</div>')]
assert '後端' in legend and '資料庫' in legend, legend
for absent in ('前端', '佇列', '外部', 'Backend', 'Frontend'):
    assert absent not in legend, (absent, legend)
PY
}

@test "a spec legend replaces the default labels" {
  mutate 's["legend"] = [{"kind": "be", "label": "FAQ · RAG"}, {"kind": "db", "label": "圖片"}]'
  python3 "$AD/check.py" "$S/m.json"
  python3 "$AD/render.py" page "$S/m.json" "$S/m.html"
  grep -qF 'FAQ · RAG' "$S/m.html" || return 1
  grep -qF '圖片' "$S/m.html" || return 1
  python3 - "$S/m.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
legend = s[s.index('<div class="legend">'):]
assert '後端' not in legend[:legend.index('</div>')]
PY
}

@test "check rejects a legend entry with an unknown kind" {
  mutate 's["legend"] = [{"kind": "xx", "label": "壞"}]'
  check_rule schema
}

@test "node titles are bold white; centered without lines, left-aligned with lines" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 - "$S/a.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
svg = s[s.index('class="diagram"'):s.index('</section>')]
def title(node, text):
    g = svg[svg.index('data-node="%s"' % node):]
    g = g[:g.index('</g>')]
    m = re.search(r'<text ([^>]*)>%s</text>' % re.escape(text), g)
    assert m, (node, g)
    return m.group(1)
a = title('a', 'Webhook')        # node a has lines: x=20 → left edge + 14
b = title('b', 'PostgreSQL')     # node b has none: x=300,w=160 → center 380
assert 'x="34"' in a and 'text-anchor="start"' in a, a
assert 'x="380"' in b and 'text-anchor="middle"' in b, b
for t in (a, b):
    assert 'font-weight="700"' in t and 'fill="#f8fafc"' in t, t
PY
}

@test "condition table names nodes by their titles" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 - "$S/a.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
table = s[s.index('<table class="cond"'):]
rows = table[table.index('<tbody>'):]
assert '<td>Webhook</td>' in rows, rows[:300]
assert 'Webhook / PostgreSQL' in rows
PY
}

@test "index title names the pack in zh-TW with the repo name" {
  mkdir -p "$S/pack"
  cp "$FX/clean.json" "$S/pack/demo.json"
  python3 "$AD/render.py" index "$S/pack" "$S/pack/index.html"
  grep -qF '<h1>架構圖包 · demo</h1>' "$S/pack/index.html" || return 1
}

@test "every diagram sits in one pan box under the swipe hint" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 "$AD/render.py" page "$FX/minimal.json" "$S/m.html"
  python3 - "$S/a.html" "$S/m.html" <<'PY'
import re, sys
for path, n in ((sys.argv[1], 2), (sys.argv[2], 1)):
    s = open(path, encoding='utf-8').read()
    pairs = re.findall(r'<p class="pan-hint">← 左右滑動看整張圖 →</p><div class="pan"><svg [^>]*style="--w:(\d+)px"', s)
    assert len(pairs) == n, (path, pairs)
    assert set(pairs) == {'600'}, pairs
    assert s.count('<div class="pan">') == s.count('<svg ') == n, path
PY
}

@test "phone CSS hides the hint by default and turns the table into cards below 700px" {
  python3 "$AD/render.py" page "$FX/clean.json" "$S/a.html"
  python3 - "$S/a.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
css = s[s.index('<style>'):s.index('</style>')]
hidden, media = css.find('.pan-hint{display:none}'), css.find('@media (max-width:700px)')
assert -1 < hidden < media, (hidden, media)
block = css[media:]
assert css.count('@media (max-width:700px)') == 1
for rule in ('.pan-hint{display:block', 'calc(var(--w)*0.8)', '.cond thead{display:none}', 'content:"做什麼　"', 'content:"條件　"', 'font-weight:700;overflow-wrap:anywhere'):
    assert rule in block, rule
PY
}

@test "a non-numeric canvas width is refused, not written into the style attribute" {
  python3 - "$FX/minimal.json" "$S/m.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
s['canvas']['w'] = '1;background-image:url(//127.0.0.1:8765/beacon);--z:0'
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f)
PY
  run python3 "$AD/render.py" page "$S/m.json" "$S/m.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/m.html" ] || return 1
}

mutate_catalog() {
  python3 - "$FX/$1.json" "$S/$1.json" "$2" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
exec(sys.argv[3])
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f, ensure_ascii=False)
PY
}

@test "AC-1 diagram output is byte-identical to the frozen golden" {
  for name in clean minimal lg; do
    python3 "$AD/render.py" page "$FX/$name.json" "$S/$name.html"
    cmp "$S/$name.html" "$FX/golden/$name.html" || return 1
  done
  mutate 's["page"] = "diagram"'
  python3 "$AD/render.py" page "$S/m.json" "$S/explicit.html"
  cmp "$S/explicit.html" "$FX/golden/clean.html"
}

@test "AC-2 table page groups rows, marks warn and draws no svg" {
  python3 "$AD/render.py" page "$FX/jobs.json" "$S/jobs.html"
  python3 - "$S/jobs.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
assert s.count('<h2>事件</h2>') == s.count('<h2>排程</h2>') == 1
assert s.index('<h2>事件</h2>') < s.index('<h2>排程</h2>')
assert s.index('id="row-csat_worker"') < s.index('id="row-media_consumer"') < s.index('id="row-dw_sync"')
assert s.count('<tr class="warn"') == s.count('⚠') == 1
assert '<th>類型</th><th>頻率</th><th>做什麼</th><th>程式碼</th>' in s
assert '<td data-label="類型">consumer</td>' in s
assert '<svg' not in s
PY
  run python3 "$AD/check.py" "$FX/jobs.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "AC-3 registry check names the missing row and never runs the file" {
  mutate_catalog jobs 's["registry"] = {"file": "registry_ok.py", "call": "Meta"}'
  run python3 "$AD/check.py" "$S/jobs.json" --repo "$FX"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || return 1
  mutate_catalog jobs 's["registry"] = {"file": "registry_ok.py", "call": "Meta"}; s["rows"] = s["rows"][:2]'
  run python3 "$AD/check.py" "$S/jobs.json" --repo "$FX"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = 'check: registry: missing row media_consumer' ]
}

@test "registry call with a non-literal name is reported" {
  cp "$FX/registry_ok.py" "$S/registry_ok.py"
  cat >> "$S/registry_ok.py" <<'PY'
Meta(name=n)
Meta(name=f"job_{n}")
Meta()
PY
  mutate_catalog jobs 's["registry"] = {"file": "registry_ok.py", "call": "Meta"}'
  run python3 "$AD/check.py" "$S/jobs.json" --repo "$S"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = $'check: registry: unresolved name at line 6\ncheck: registry: unresolved name at line 7\ncheck: registry: unresolved name at line 8' ]
}

@test "registry reports missing files and parse errors" {
  mutate_catalog jobs 's["registry"] = {"file": "missing.py", "call": "Meta"}'
  run python3 "$AD/check.py" "$S/jobs.json" --repo "$S"
  [ "$status" -eq 1 ] || return 1
  [ "$output" = "check: registry: file not found $S/missing.py" ] || return 1
  printf 'raise SystemExit(9)\nMeta(\n' > "$S/missing.py"
  run python3 "$AD/check.py" "$S/jobs.json" --repo "$S"
  [ "$status" -eq 1 ] || return 1
  [[ "$output" == "check: registry: cannot parse $S/missing.py:"* ]]
}

@test "AC-8 unknown page is a schema finding and writes nothing" {
  mutate 's["page"] = "bogus"'
  check_rule schema
  run python3 "$AD/render.py" page "$S/m.json" "$S/out.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/out.html" ]
}

@test "AC-2 matrix is no longer a page type" {
  mutate 's.update(page="matrix", roots=[], modules=[], matrix=[], cycles=[])'
  run python3 "$AD/check.py" "$S/m.json"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == 'check: schema:'* ]] || return 1
  run python3 "$AD/render.py" page "$S/m.json" "$S/out.html"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$S/out.html" ] || return 1
  [ ! -e "$AD/modules.py" ] || return 1
  ! grep -rq 'modules.py' "$AD/../SKILL.md" "$AD/../references"
}

@test "empty table renders title and footer only" {
  mutate_catalog jobs 's["rows"] = []'
  python3 "$AD/render.py" page "$S/jobs.json" "$S/jobs.html"
  grep -qF '<h1>背景程式</h1>' "$S/jobs.html" || return 1
  grep -qF '<footer>' "$S/jobs.html" || return 1
  ! grep -qF '<table' "$S/jobs.html" || return 1
  run python3 "$AD/check.py" "$S/jobs.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "table schema and duplicate row ids are checked" {
  mutate_catalog jobs 's["rows"].append(s["rows"][0])'
  run python3 "$AD/check.py" "$S/jobs.json"
  [ "$status" -eq 1 ] || return 1
  [ "$output" = 'check: id: duplicate row csat_worker' ] || return 1
  for change in 's["columns"] = None' 's["rows"][0]["id"] = "bad id"' 's["rows"][0]["warn"] = "yes"' 's["rows"][0]["cells"]["kind"] = 1'; do
    mutate_catalog jobs "$change"
    run python3 "$AD/check.py" "$S/jobs.json"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == 'check: schema:'* ]] || return 1
  done
}

@test "table puts ungrouped rows first and leaves missing cells empty" {
  mutate_catalog jobs 's["rows"][1].pop("group"); s["rows"][1]["cells"] = {}; s["rows"][1]["src"] = ["a.py:1", "b.py:2"]'
  python3 "$AD/render.py" page "$S/jobs.json" "$S/jobs.html"
  python3 - "$S/jobs.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
assert s.index('id="row-dw_sync"') < s.index('<h2>事件</h2>')
assert '<td data-label="頻率"></td>' in s
assert 'a.py:1 / b.py:2' in s
PY
}

@test "AC-4 cards link topics and jobs and the check finds dangling links" {
  cp "$FX/features.json" "$FX/jobs.json" "$S/"
  python3 - "$FX/minimal.json" "$S/csat.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
s['topic'] = 'csat'
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(s, f)
PY
  run python3 "$AD/check.py" "$S/features.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || return 1
  python3 "$AD/render.py" page "$S/features.json" "$S/features.html"
  for text in '<article class="card" id="card-csat">' 'href="csat.html"' 'href="jobs.html#row-csat_worker"' '入口' '資料'; do
    grep -qF "$text" "$S/features.html" || return 1
  done
  mutate_catalog features 's["cards"][0].update(topics=["nope"], jobs=["ghost"])'
  run python3 "$AD/check.py" "$S/features.json"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = $'check: link: missing topic nope\ncheck: link: missing job ghost' ]
}

@test "cards job link without jobs.json is missing" {
  cp "$FX/features.json" "$S/"
  run python3 "$AD/check.py" "$S/features.json"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'check: link: missing job csat_worker'
}

@test "empty cards renders title and footer only" {
  mutate_catalog features 's["cards"] = []'
  python3 "$AD/render.py" page "$S/features.json" "$S/features.html"
  grep -qF '<h1>功能目錄</h1>' "$S/features.html" || return 1
  grep -qF '<footer>' "$S/features.html" || return 1
  ! grep -qF '<div class="cards">' "$S/features.html" || return 1
  ! grep -qF '<article' "$S/features.html" || return 1
  run python3 "$AD/check.py" "$S/features.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "cards schema and duplicate card ids are checked" {
  mutate_catalog features 's["cards"].append(s["cards"][0])'
  cp "$FX/jobs.json" "$S/"
  cp "$FX/minimal.json" "$S/csat.json"
  run python3 "$AD/check.py" "$S/features.json"
  [ "$status" -eq 1 ] || return 1
  [ "$output" = 'check: id: duplicate card csat' ] || return 1
  for change in 's["cards"] = None' 's["cards"][0]["src"] = "a.py:1"' 's["cards"][0]["topics"] = ["../outside"]' 's["cards"][0]["jobs"] = ["bad id"]'; do
    mutate_catalog features "$change"
    run python3 "$AD/check.py" "$S/features.json"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == 'check: schema:'* ]] || return 1
  done
}

@test "cards treat unreadable jobs as having no ids" {
  cp "$FX/features.json" "$S/"
  cp "$FX/minimal.json" "$S/csat.json"
  for content in '{nope' '[]' '{"rows": null}'; do
    printf '%s\n' "$content" > "$S/jobs.json"
    run python3 "$AD/check.py" "$S/features.json"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [ "$output" = 'check: link: missing job csat_worker' ] || return 1
  done
}

init_seamrepo() {
  cp -R "$FX/seamrepo" "$S/repo"
  cp "$FX/seams.json" "$S/seams.json"
  git -C "$S/repo" init -q
  git -C "$S/repo" config user.name 'Draw Arch Test'
  git -C "$S/repo" config user.email 'draw-arch@example.invalid'
  git -C "$S/repo" add .
  git -C "$S/repo" commit -qm fixture
}

@test "AC-3 seams.py finds import and text touchpoints, marks adapters, skips tests and excludes" {
  init_seamrepo
  run --separate-stderr python3 "$AD/seams.py" "$S/repo" "$S/seams.json"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 0 ] || { echo "$stderr"; return 1; }
  [ "$stderr" = 'seams: cannot parse core/py2.py' ] || { echo "$stderr"; return 1; }
  python3 - "$S/seams.json" <<'PY'
import json, re, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
assert s['systems'][0]['touchpoints'] == [
    {'file': 'adapters/line.py', 'lines': [2], 'adapter': True},
    {'file': 'core/a.py', 'lines': [2, 3, 4], 'adapter': False},
    {'file': 'core/py2.py', 'lines': [2], 'adapter': False},
], s
assert s['systems'][1]['touchpoints'] == []
assert re.fullmatch('[0-9a-f]{40}', s['repo']['commit'])
PY
  cp "$S/seams.json" "$S/first.json"
  run python3 "$AD/seams.py" "$S/repo" "$S/seams.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$S/first.json" "$S/seams.json" || return 1
  python3 - "$S/seams.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
s = json.loads(p.read_text(encoding='utf-8'))
s['systems'][0]['touchpoints'][1]['note'] = 'x'
p.write_text(json.dumps(s, ensure_ascii=False), encoding='utf-8')
PY
  run python3 "$AD/seams.py" "$S/repo" "$S/seams.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 - "$S/seams.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding='utf-8'))
assert s['systems'][0]['touchpoints'][1]['note'] == 'x'
PY
}

@test "seams.py with a missing repo or spec exits 2 and writes nothing" {
  cp "$FX/seams.json" "$S/seams.json"
  cp "$S/seams.json" "$S/first.json"
  run --separate-stderr python3 "$AD/seams.py" "$S/missing-repo" "$S/seams.json"
  [ "$status" -eq 2 ] || { echo "$stderr"; return 1; }
  [ -z "$output" ] && [ -n "$stderr" ] || return 1
  cmp "$S/first.json" "$S/seams.json" || return 1
  [ ! -e "$S/missing-repo" ] || return 1
  init_seamrepo
  run --separate-stderr python3 "$AD/seams.py" "$S/repo" "$S/missing.json"
  [ "$status" -eq 2 ] || { echo "$stderr"; return 1; }
  [ -z "$output" ] && [ -n "$stderr" ] || return 1
  [ ! -e "$S/missing.json" ]
}

@test "AC-4 check reports a stale system after the code changes" {
  init_seamrepo
  run python3 "$AD/seams.py" "$S/repo" "$S/seams.json"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run python3 "$AD/check.py" "$S/seams.json" --repo "$S/repo"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
  printf 'import linebot\n' >> "$S/repo/core/b.py"
  git -C "$S/repo" add .
  git -C "$S/repo" commit -qm 'add touchpoint'
  run python3 "$AD/check.py" "$S/seams.json" --repo "$S/repo"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = 'check: seams: stale line' ]
}

@test "AC-6 seams schema findings" {
  mutate_catalog seams 's["systems"].append(s["systems"][0])'
  run python3 "$AD/check.py" "$S/seams.json"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = 'check: id: duplicate system line' ] || { echo "$output"; return 1; }
  for change in 's["systems"][0]["verdict"] = "maybe"' 's["systems"][0]["probes"] = []' 's["systems"][0]["probes"][1]["pattern"] = "("' 's["systems"][0]["probes"][1]["pattern"] = "a{4294967296}"'; do
    mutate_catalog seams "$change"
    run python3 "$AD/check.py" "$S/seams.json"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == 'check: schema:'* ]] || { echo "$output"; return 1; }
  done
}

@test "AC-5 seams page leads with a summary and lists leaks first" {
  mutate_catalog seams 's["systems"][0]["touchpoints"] = [{"file": "adapters/line.py", "lines": [2], "adapter": True}, {"file": "core/a.py", "lines": [2, 3], "adapter": False}]'
  python3 "$AD/render.py" page "$S/seams.json" "$S/seams.html"
  python3 - "$S/seams.html" <<'PY'
import re, sys
from html import unescape
s = open(sys.argv[1], encoding='utf-8').read()
assert s.index('<table class="cat sum">') < s.index('<section id="sys-line">')
summary = re.search(r'<table class="cat sum">(.*?)</table>', s, re.S).group(1)
assert re.findall(r'<th>(.*?)</th>', summary) == ['系統', '能不能換', '接觸檔', '漏進核心', '一句話']
rows = re.findall(r'<tr>(.*?)</tr>', summary, re.S)[1:]
cells = [[unescape(re.sub('<[^>]*>', '', value)) for value in re.findall(r'<td[^>]*>(.*?)</td>', row)] for row in rows]
assert [row[:4] for row in cells] == [['LINE', '很難換', '2', '1'], ['資料倉儲', '容易換', '0', '0']], cells
assert 'href="#sys-line"' in summary and 'href="#sys-dw"' in summary
line = re.search(r'<section id="sys-line">(.*?)</section>', s, re.S).group(1)
assert '<h2>LINE' in line and '很難換' in line
assert line.index('❌ 漏進核心') < line.index('✅ 在 adapter 內')
assert '<tr class="warn">' in line
assert 'core/a.py' in line and '>2, 3</td>' in line
assert re.findall(r'<th>(.*?)</th>', line) == ['檔案', '行', '位置', '說明']
dw = re.search(r'<section id="sys-dw">(.*?)</section>', s, re.S).group(1)
assert '沒有找到接觸點' in dw
assert '換掉要改' in s and '<svg' not in s
PY
}

@test "seams.py counts lines on newlines only and survives NUL bytes and unreadable files" {
  mkdir -p "$S/r"
  printf 'raise SystemExit(9)\nx = "a\fb\xe2\x80\xa8c"\ny = 1\nURL = "api.line.me"\n' > "$S/r/ff.py"
  printf 'raise SystemExit(9)\nURL = "api.line.me"\x00\n' > "$S/r/nul.py"
  printf 'raise SystemExit(9)\nURL = "api.line.me" # \xe9\n' > "$S/r/latin.py"
  git -C "$S/r" init -q && git -C "$S/r" add . && git -C "$S/r" -c user.name=t -c user.email=t@example.invalid commit -qm i
  python3 - "$S/s.json" <<'PY2'
import json, sys
json.dump({"topic": "seams", "page": "seams", "title": "t", "repo": {"name": "r", "commit": "0000000"},
           "systems": [{"id": "line", "title": "L", "verdict": "hard", "summary": "", "change": [],
                        "probes": [{"kind": "text", "pattern": "api\\.line\\.me"}, {"kind": "import", "pattern": "linebot"}],
                        "adapters": [], "touchpoints": []}]}, open(sys.argv[1], "w"))
PY2
  run python3 "$AD/seams.py" "$S/r" "$S/s.json"
  [ "$status" -ne 9 ] || return 1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'seams: cannot parse nul.py' || { echo "$output"; return 1; }
  echo "$output" | grep -qF 'seams: cannot read latin.py' || { echo "$output"; return 1; }
  python3 -c "import json,sys; t=json.load(open(sys.argv[1]))['systems'][0]['touchpoints']; assert t == [{'file':'ff.py','lines':[4],'adapter':False},{'file':'nul.py','lines':[2],'adapter':False}], t" "$S/s.json"
  run python3 "$AD/check.py" "$S/s.json" --repo "$S/r"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "seams verdicts carry a tone class in the summary and the section heading" {
  python3 - "$S/v.json" <<'PY2'
import json, sys
spec = {"topic": "seams", "page": "seams", "title": "t", "repo": {"name": "r", "commit": "0123456"},
        "systems": [{"id": i, "title": i, "verdict": v, "summary": "s", "change": [], "probes": [{"kind": "import", "pattern": "x"}],
                     "adapters": [], "touchpoints": []} for i, v in (("a", "easy"), ("b", "medium"), ("c", "hard"))]}
json.dump(spec, open(sys.argv[1], "w"))
PY2
  python3 "$AD/render.py" page "$S/v.json" "$S/v.html"
  for v in easy medium hard; do grep -qF "class=\"v-$v\"" "$S/v.html" || return 1; done
  [ "$(grep -o 'class="v-hard"' "$S/v.html" | wc -l | tr -d ' ')" -eq 2 ] || return 1
}

@test "AC-7 index puts overview, features, seams, jobs first" {
  mkdir -p "$S/pack"
  cp "$FX/jobs.json" "$FX/features.json" "$FX/seams.json" "$S/pack/"
  python3 - "$FX/clean.json" "$S/pack" <<'PY'
import json, sys
from pathlib import Path
s = json.load(open(sys.argv[1], encoding='utf-8'))
for topic in ('overview', 'csat'):
    s['topic'] = topic
    (Path(sys.argv[2]) / (topic + '.json')).write_text(json.dumps(s), encoding='utf-8')
PY
  python3 "$AD/render.py" index "$S/pack" "$S/index.html"
  python3 - "$S/index.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
assert re.findall(r'href="([^"]+)"', s) == ['overview.html', 'features.html', 'seams.html', 'jobs.html', 'csat.html']
PY
}

@test "AC-8 seams text is escaped and offline" {
  mutate_catalog seams 'text = "<script>alert(1)</script> https://evil.example"; s["systems"][0].update(summary=text, change=[text], touchpoints=[{"file": "core/a.py", "lines": [2], "adapter": False, "note": text}])'
  python3 "$AD/render.py" page "$S/seams.json" "$S/seams.html"
  python3 "$AD/render.py" page "$S/seams.json" "$S/again.html"
  cmp "$S/seams.html" "$S/again.html" || return 1
  python3 - "$S/seams.html" <<'PY'
import re, sys
from html import unescape
s = open(sys.argv[1], encoding='utf-8').read()
assert '<script>alert' not in s and not re.search(r' on[a-z]+=', s)
assert not re.search(r'https?://', s)
assert s.count('&lt;script&gt;alert(1)&lt;/script&gt;') == 4
assert 'https://evil.example' in unescape(s)
PY
}

@test "AC-9 catalog pages stay offline" {
  mutate_catalog jobs 's["rows"][0]["cells"]["does"] = "https://evil.example <script>bad</script> & quote\""'
  mutate_catalog features 's["cards"][0]["does"] = "https://evil.example <script>bad</script> & quote\""'
  for topic in jobs features; do
    python3 "$AD/render.py" page "$S/$topic.json" "$S/$topic.html"
    python3 "$AD/render.py" page "$S/$topic.json" "$S/again.html"
    cmp "$S/$topic.html" "$S/again.html" || return 1
  done
  python3 - "$S" <<'PY'
import re, sys
from pathlib import Path
from html import unescape
for topic in ('jobs', 'features'):
    s = (Path(sys.argv[1]) / (topic + '.html')).read_text(encoding='utf-8')
    assert '<script' not in s and not re.search(r' on[a-z]+=', s), topic
    assert not re.search(r'https?://', s), topic
    assert '&lt;script&gt;' in s and '&amp;' in s and '&quot;' in s
    assert 'https://evil.example' in unescape(s)
PY
}

@test "spec-format documents the new page types" {
  for field in page columns registry cards seams probes adapters touchpoints; do
    grep -qF "$field" "$AD/../references/spec-format.md" || return 1
  done
  python3 - "$AD/../references/spec-format.md" "$S/table.json" <<'PY'
import json, re, sys
from pathlib import Path
examples = [json.loads(s) for s in re.findall(r'```json\n(.*?)\n```', Path(sys.argv[1]).read_text(encoding='utf-8'), re.S)]
table = next(s for s in examples if s.get('page') == 'table')
Path(sys.argv[2]).write_text(json.dumps(table), encoding='utf-8')
PY
  run python3 "$AD/check.py" "$S/table.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 "$AD/render.py" page "$S/table.json" "$S/table.html"
}

@test "spec-format seams example passes check.py" {
  python3 - "$AD/../references/spec-format.md" "$S/seams.json" <<'PY'
import json, re, sys
from pathlib import Path
examples = [json.loads(s) for s in re.findall(r'```json\n(.*?)\n```', Path(sys.argv[1]).read_text(encoding='utf-8'), re.S)]
seams = next(s for s in examples if s.get('page') == 'seams')
Path(sys.argv[2]).write_text(json.dumps(seams), encoding='utf-8')
PY
  run python3 "$AD/check.py" "$S/seams.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || return 1
  python3 "$AD/render.py" page "$S/seams.json" "$S/seams.html"
}
