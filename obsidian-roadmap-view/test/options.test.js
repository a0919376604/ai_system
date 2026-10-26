// R-024 AC-1..AC-5: 完成條件 as a list, the picked option and its mockup panel.
// Fixture text is invented (this repo is public).
const test = require("node:test");
const assert = require("node:assert/strict");
const P = require("./load");

test("splitConditions: top-level ；, ; and · split; brackets, quotes and backticks protect (AC-1)", () => {
  assert.deepEqual(P.splitConditions("「A；B」（含 x；y） · C；"), ["「A；B」（含 x；y）", "C"]);
  assert.deepEqual(P.splitConditions("清單沒有比例欄；新增排序 · 每列有趨勢; 點得開"),
    ["清單沒有比例欄", "新增排序", "每列有趨勢", "點得開"]);
  assert.deepEqual(P.splitConditions("`a · b` 照舊 (x; y) 【m；n】 『p · q』 [r; s]"),
    ["`a · b` 照舊 (x; y) 【m；n】 『p · q』 [r; s]"]);
  assert.deepEqual(P.splitConditions("沒有分隔的一句"), ["沒有分隔的一句"]);
  assert.deepEqual(P.splitConditions(" ； · "), []);
  assert.deepEqual(P.splitConditions("a·b"), ["a·b"]);   // only the spaced ` · ` separates
});

test("parseRoadmap: picked from 定案 on the row, else 方案 X on a ↳ line that mentions a mockup (AC-2)", () => {
  const items = P.parseRoadmap([
    "- [x] **R-1** [FEATURE · mockup 定案 B · ✅ 2026-10-20] 一",
    "- [x] **R-2** 二 · ✅ 2026-10-20",
    "    ↳ explain: mockup `Proposals/mockups/two-mockup.html` 方案 C（精簡版）。",
    "- [ ] **R-3** 三",
    "    ↳ mockup 同上（方案 A）· 代價：多一步",
    "- [ ] **R-4** 四",
    "    ↳ done when: 方案 B 的按鈕要能按",
    "- [ ] **R-5** 五",
    "    ↳ mockup [[Proposals/mockups/five-mockup.html|五的 mockup（方案 甲）]]",
    "- [ ] **R-6** 六",
    "    ↳ mockup 方案 b 小寫不算 · 方案 ZZ 也不算",
    "- [ ] **R-7** 七",
    "    ↳ done when: 有採用方案（mockup 定案 X 或 方案 X）的項目都顯示",
  ].join("\n"));
  assert.deepEqual(items.map((i) => i.picked), ["B", "C", "A", null, "甲", null, null]);
});

const PAGE = (body) => `<html><head><style>.panel{border:1px}</style></head><body>${body}<script>x()</script></body></html>`;

test("optionDoc: the label wins over the class — 版面甲 can sit in optB (AC-3)", () => {
  const html = PAGE('<div class="panel now">現況</div>'
    + '<div class="panel optA"><h2>版面乙　沿用熱度表</h2><p>乙的內容</p></div>'
    + '<div class="panel optB"><h2>版面甲　先排原因<span class="tag">建議</span></h2><div><p>甲的內容</p></div></div>');
  const r = P.optionDoc(html, "甲");
  assert.ok(r.doc.includes("甲的內容") && !r.doc.includes("乙的內容") && !r.doc.includes("現況"));
  assert.equal(r.label, "版面甲 先排原因 建議");   // a tag's text is a word of its own
  assert.ok(r.doc.includes(".panel{border:1px}"));
});

test("optionDoc: a heading before the panel labels it; an unlabelled mockup matches by class (AC-4)", () => {
  const labelled = PAGE('<h2>方案 A · 一頁看板</h2><div class="panel optA">A 內容</div>'
    + '<h2>方案 B · 白話週報</h2><div class="panel optB">B 內容</div>');
  const r = P.optionDoc(labelled, "B");
  assert.equal(r.label, "方案 B · 白話週報");
  assert.ok(r.doc.includes("B 內容") && !r.doc.includes("A 內容"));
  const bare = PAGE('<div class="panel optA">A</div><section class="optB panel"><div>B 本體</div></section>');
  const b = P.optionDoc(bare, "B");
  assert.ok(b.doc.includes("<section class=\"optB panel\"><div>B 本體</div></section>"));
  assert.equal(b.label, "");   // no heading at all: matched by class, no caption
  // the heading before optA belongs to optA, never to the panel after it
  const after = PAGE('<h2>方案 A · 看板</h2><div class="panel optA"><p>A</p></div><div class="panel optB"><p>B</p></div>');
  const b2 = P.optionDoc(after, "B");
  assert.ok(b2.doc.includes("<p>B</p>") && !b2.doc.includes("<p>A</p>"));
  assert.equal(b2.label, "");
});

test("optionDoc: no such option → null; scripts never reach the doc (AC-5)", () => {
  const html = PAGE('<div class="panel optA">A</div><div class="panel optD">D<script>alert(1)</script></div>');
  assert.equal(P.optionDoc(html, "C"), null);
  assert.equal(P.optionDoc(html, null), null);
  assert.equal(P.optionDoc("", "A"), null);
  assert.equal(P.optionDoc(html, "甲"), null);   // no label, and 甲 has no class form
  assert.ok(!/<script/i.test(P.optionDoc(html, "D").doc));
});

test("optionDoc: only a heading that starts with 方案/版面 X names the option, even after a number", () => {
  // the real option's title sits before it; a later optB panel only mentions 方案 B mid-sentence
  const html = PAGE('<h2>方案 B · 另開一頁</h2><div class="panel optB"><h3>跟推播一樣的步驟</h3><p>主方案</p></div>'
    + '<div class="panel optB"><h3>匯入名單時，方案 B 一起做</h3><p>補充</p></div>');
  const r = P.optionDoc(html, "B");
  assert.ok(r.doc.includes("主方案") && !r.doc.includes("補充"));
  assert.equal(r.label, "方案 B · 另開一頁");
  const numbered = PAGE('<h2>4 · 方案 A · 發邀請時記下工單 /csat/new?&lt;篩選&gt;&amp;x</h2><div class="panel optC">C 的內容</div>');
  assert.equal(P.optionDoc(numbered, "A").label, "4 · 方案 A · 發邀請時記下工單 /csat/new?<篩選>&x");
  const mention = PAGE('<div class="panel optC"><h3>比方案 A 更快的做法</h3>C</div>');
  assert.equal(P.optionDoc(mention, "A"), null);
});

// --- R-024 review attempt 1 -------------------------------------------------------

test("optionDoc: an unclosed option panel ends where the next one starts; its heading never labels the next", () => {
  // as in a real mockup: optB's markup never closes, then optA follows
  const html = PAGE('<!-- 甲 --><div class="panel optB"><h2>版面甲 先排原因</h2><div class="ui"><p>甲的畫面</p>'
    + '<div class="panel optA"><h2>版面乙 沿用熱度表</h2><p>乙的畫面</p></div>');
  const jia = P.optionDoc(html, "甲");
  assert.ok(jia.doc.includes("甲的畫面") && !jia.doc.includes("乙的畫面"));
  assert.equal(jia.label, "版面甲 先排原因");
  const yi = P.optionDoc(html, "乙");
  assert.ok(yi.doc.includes("乙的畫面") && !yi.doc.includes("甲的畫面"));
  assert.equal(P.optionDoc(html, "A").label, "版面乙 沿用熱度表");   // class match keeps optA's own heading
});

test("optionDoc: says whether it matched by label or by class", () => {
  const html = PAGE('<h2>方案 A · 甲</h2><div class="panel optA">A</div><div class="panel optB">B</div>');
  assert.equal(P.optionDoc(html, "A").by, "label");
  assert.equal(P.optionDoc(html, "B").by, "class");
});

test("parseRoadmap: the row form 方案 X 定案 names the picked option too", () => {
  const items = P.parseRoadmap([
    "- [x] **R-1** [FEATURE · ✅ merged 2026-10-22 · 方案 A 定案 · learning `x.md`] 一",
    "- [x] **R-2** [FEATURE · 方案B定案] 二",
    "- [x] **R-3** [FEATURE · mockup 定案 C · 方案 A 定案] 三",
    "- [ ] **R-4** 四 —— 方案 A 還沒定案",
  ].join("\n"));
  assert.deepEqual(items.map((i) => i.picked), ["A", "B", "C", null]);
});

test("optionDoc: a class match is captioned with the panel's own heading, not a shared section heading", () => {
  const html = PAGE('<h2>第三部分 · 三個做法</h2><div class="panel optA"><h3>A · 清單最上面一條</h3>A</div>'
    + '<div class="panel optB"><h3>B · 另開一頁</h3>B</div>');
  const r = P.optionDoc(html, "A");
  assert.equal(r.by, "class");
  assert.equal(r.label, "A · 清單最上面一條");
});
