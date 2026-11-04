#!/usr/bin/env bats
load helpers

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
