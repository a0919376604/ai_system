// R-013 AC-1..AC-4. Fixture rows copy the exact formats of langlive's R-248, R-256,
// R-094.2/.3 and R-231 and of ai_system's trailing annotations; the text is synthetic
// (this repo is public, langlive's roadmap is company data).
const test = require("node:test");
const assert = require("node:assert/strict");
const P = require("./load");

const MD = `# ROADMAP

## 🔥 Now (3-5 items)

- [ ] **R-094.3** [FEATURE · P2 · UIUX · blocked: 等待正式環境的金鑰 · 接續 R-094.2] 分享連結追蹤＋點擊後自動分類 —— 訊息裡的網址換成追蹤連結
    ↳ mockup 同上（方案 A）· 代價：第一次點會多一個確認畫面
    ↳ done when: 訊息網址自動換成追蹤連結（可關）
- [x] **R-248** [FEATURE · P2 · UIUX · mockup 定案 B · ✅ merged 2026-10-19 · main \`a1b2c3d4\`（squash 直接 push，未開 MR）· 尚未部署 test · learning \`docs/learnings/R-248-x.md\`] 首頁「熱門分類／分類細節」清單調整 —— 拿掉比例欄
  ↳ done when: 清單沒有比例欄
  ↳ explain: mockup \`Proposals/mockups/home-list-polish-mockup.html\` 方案 B（以人為主版）。

- [x] **R-256** [FEATURE · P2 · UIUX · mockup 定案 A · ✅ 2026-10-22～24 · squash 直接 push main：第 1 步 \`0f1e2d3c\` · 第 2 步 \`4b5a6978\`] 訊息面板改良（\`MessagePanel\`，四個分頁共用）—— 圖片可放大
- [ ] **R-014** 審查中的項目 · status=in-review · mr=https://gitlab.example.com/g/p/-/merge_requests/285

## 🔜 Next

- [ ] **R-231** [EPIC · P2 · needs-brainstorm] 使用者標籤：從紀錄自動長出可篩選的 tag —— **來源：** 使用者討論。
    ↳ done when: 能用 tag 篩出名單
    ↳ done when: 每個 tag 點得到來源紀錄
    ↳ explain: 要先知道誰對什麼有興趣，這個 epic 把紀錄變成可以篩選的標籤。
  - [ ] **R-231.2** [FEATURE · P3] 子項目 **來源：** 討論
- [ ] ⚠️ **R-300** (epic) 大項目

## ✅ Done

- [x] **R-094.2** [FEATURE · P2 · UIUX · ✅ 2026-10-23 · squash \`9e8d7c6b\` 直接 push main · 接續 R-094.1] 分享成效：收到後 7 天回訪率 —— 每則訊息顯示回訪率
    ↳ mockup [[Proposals/mockups/share-link-tracking-mockup.html|分享成效 mockup（方案 D）]] · 建議對照組預設 10%
- [x] **R-012** vault 自動備份範例同步實機修正 · ✅ 2026-10-25
- [x] **R-001 (epic)** 劇情 pipeline · ✅ shipped · merged 2026-09-01
- [x] ~~**R-093** 流失預測~~ —— **superseded by [[R-206]]**
- [x] **R-193.3a-2.1** [FIX · P3 · ✅ 7c8d9e0f] 子項 · MR !288
- [x] ✅ **R-193 號碼衝突已結案** —— not an item
`;
const items = P.parseRoadmap(MD);
const by = (id) => items.find((i) => i.id === id);

test("parseRoadmap: one item per R row, children and odd ids included, notes excluded", () => {
  assert.deepEqual(items.map((i) => i.id), ["R-094.3", "R-248", "R-256", "R-014", "R-231", "R-231.2", "R-300",
    "R-094.2", "R-012", "R-001", "R-093", "R-193.3a-2.1"]);
  assert.equal(by("R-248").section, "🔥 Now (3-5 items)");
  assert.equal(by("R-094.2").section, "✅ Done");
  assert.equal(by("R-094.3").line, 4);
  assert.equal(by("R-248").raw, MD.split("\n")[by("R-248").line]);
});

test("parseRoadmap: R-248 — headline, done date, undeployed env, picked option, commit, no explain", () => {
  const r = by("R-248");
  assert.equal(r.headline, "首頁「熱門分類／分類細節」清單調整");
  assert.equal(r.checked, true);
  assert.equal(r.done, "2026-10-19");
  assert.equal(r.undeployed, "test");
  assert.equal(r.picked, "B");
  assert.equal(r.commit, "a1b2c3d4");
  assert.equal(r.explain, null);
  assert.deepEqual(r.refs, ["Proposals/mockups/home-list-polish-mockup.html"]);
  assert.deepEqual(r.doneWhen, ["清單沒有比例欄"]);
  assert.match(r.tags, /^FEATURE · P2 · UIUX · mockup 定案 B/);
});

test("parseRoadmap: R-094.3 — blocked reason, mockup 同上", () => {
  const r = by("R-094.3");
  assert.equal(r.blocked, "等待正式環境的金鑰");
  assert.equal(r.sameAsAbove, true);
  assert.equal(r.checked, false);
  assert.equal(r.done, null);
  assert.equal(r.headline, "分享連結追蹤＋點擊後自動分類");
});

test("parseRoadmap: R-231 — explain kept, needs-brainstorm, epic, headline stops at **來源", () => {
  const r = by("R-231");
  assert.equal(r.explain, "要先知道誰對什麼有興趣，這個 epic 把紀錄變成可以篩選的標籤。");
  assert.equal(r.needsBrainstorm, true);
  assert.equal(r.epic, true);
  assert.equal(r.headline, "使用者標籤：從紀錄自動長出可篩選的 tag");
  assert.deepEqual(r.doneWhen, ["能用 tag 篩出名單", "每個 tag 點得到來源紀錄"]);
  assert.equal(by("R-231.2").headline, "子項目");
});

test("parseRoadmap: date range, trailing annotations, wikilink mockup ref, MR numbers, epic markers", () => {
  assert.equal(by("R-256").done, "2026-10-22");
  assert.equal(by("R-256").commit, "0f1e2d3c");
  assert.equal(by("R-256").headline, "訊息面板改良（`MessagePanel`，四個分頁共用）");
  assert.equal(by("R-012").headline, "vault 自動備份範例同步實機修正");
  assert.equal(by("R-012").done, "2026-10-25");
  assert.equal(by("R-012").tags, "");
  assert.equal(by("R-014").headline, "審查中的項目");
  assert.equal(by("R-014").inReview, true);
  assert.equal(by("R-014").mr, "!285");
  assert.equal(by("R-193.3a-2.1").mr, "!288");
  assert.equal(by("R-193.3a-2.1").commit, null);
  assert.equal(by("R-193.3a-2.1").done, null);
  assert.deepEqual(by("R-094.2").refs, ["Proposals/mockups/share-link-tracking-mockup.html"]);
  assert.equal(by("R-001").done, "2026-09-01");
  assert.equal(by("R-001").epic, true);
  assert.equal(by("R-300").epic, true);
  assert.equal(by("R-093").headline, "流失預測");
  assert.equal(by("R-248").epic, false);
});

test("parseRoadmap: an unknown tag format degrades to no status, never throws", () => {
  const [r] = P.parseRoadmap("- [ ] **R-7** [ODD · ✅ soon · blocked:] 文字");
  assert.equal(r.done, null);
  assert.equal(r.blocked, null);
  assert.equal(r.headline, "文字");
  assert.deepEqual(P.parseRoadmap(""), []);
});

test("mockupsFor: own <id>- files, then refs, de-duplicated; R-248 never takes R-2480's", () => {
  const files = ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/R-2480-x-mockup.html",
    "Proposals/mockups/home-list-polish-mockup.html", "Proposals/mockups/R-248-notes.md"];
  const r = { ...by("R-248"), refs: [...by("R-248").refs, "Proposals/mockups/R-248-a-mockup.html"] };
  assert.deepEqual(P.mockupsFor(r, items, files),
    ["Proposals/mockups/R-248-a-mockup.html", "Proposals/mockups/home-list-polish-mockup.html"]);
});

test("mockupsFor: 同上 takes the nearest same-base id that has a mockup, not the nearest line (AC-2)", () => {
  assert.deepEqual(P.mockupsFor(by("R-094.3"), items, []),
    ["Proposals/mockups/share-link-tracking-mockup.html"]);
  const it = (id, refs, same = false) => ({ id, refs, sameAsAbove: same });
  const list = [it("R-5.4", [], true), it("R-5.1", ["a.html"]), it("R-5.3", [], true), it("R-5.2", ["b.html"]),
    it("R-50", ["c.html"]), it("R-5.9", ["d.html"])];
  assert.deepEqual(P.mockupsFor(list[0], list, []), ["b.html"]);
  assert.deepEqual(P.mockupsFor(it("R-5.0", [], true), list, []), ["a.html"]);
  assert.deepEqual(P.mockupsFor(it("R-6", [], true), list, []), []);
});

test("statusOf: active / recent / done / todo (AC-3)", () => {
  const now = new Date("2026-10-25T12:00:00Z");
  const plain = by("R-300");
  assert.equal(P.statusOf(plain, { phase: "review", updated: "2026-10-25T08:00:00Z" }, now, 14).group, "active");
  assert.equal(P.statusOf(by("R-248"), null, now, 14).group, "recent");
  assert.equal(P.statusOf(by("R-001"), null, now, 14).group, "done");
  assert.equal(P.statusOf(plain, null, now, 14).group, "todo");
  assert.equal(P.statusOf(by("R-094.3"), null, now, 14).group, "active");
  assert.equal(P.statusOf(by("R-014"), null, now, 14).group, "active");
  assert.equal(P.statusOf(by("R-093"), null, now, 14).group, "done");
});

test("statusOf: a status file wins only when it is newer than the tags", () => {
  const now = new Date("2026-10-25T12:00:00Z");
  const stale = P.statusOf(by("R-248"), { phase: "landing", updated: "2026-10-18T09:00:00Z" }, now, 14);
  assert.equal(stale.group, "recent");
  assert.equal(stale.phase, null);
  const s = P.statusOf(by("R-300"), { phase: "blocked", updated: "2026-10-25T09:00:00Z", note: "codex: 3 attempts" }, now, 14);
  assert.equal(s.group, "active");
  assert.equal(s.phase, "blocked");
  assert.ok(s.chips.some((c) => c.kind === "blocked" && c.text.includes("codex: 3 attempts")));
  const d = P.statusOf(by("R-300"), { phase: "done", updated: "2026-10-24T09:00:00Z" }, now, 14);
  assert.equal(d.group, "recent");
  assert.equal(P.statusOf(by("R-300"), { phase: "nonsense", updated: "2026-10-25T09:00:00Z" }, now, 14).group, "todo");
  assert.equal(P.statusOf(by("R-300"), { phase: "done", updated: "2026-01-01T00:00:00Z" }, now, 14).group, "done");
});

test("statusOf: chips carry what the row says", () => {
  const c = P.statusOf(by("R-248"), null, new Date("2026-10-25T12:00:00Z"), 14).chips.map((x) => x.text);
  assert.deepEqual(c, ["完成 10/19", "尚未部署 test", "方案 B"]);
});

const PAGE = (body) => `<!DOCTYPE html><html><head><style>.a{color:red}</style>
<style media="screen">.panel{border:1px}</style></head><body>${body}</body></html>`;

test("currentStateDoc: the whole .panel.now with nested divs, every style kept (AC-4)", () => {
  const now = '<div class="panel now"><div><div>現況</div></div><p>y</p></div>';
  const doc = P.currentStateDoc(PAGE(`<div class="panel facts">F</div>${now}<div class="panel">later</div>`));
  assert.ok(doc.startsWith("<!DOCTYPE html>"));
  assert.ok(doc.includes(now));
  assert.ok(doc.includes(".a{color:red}") && doc.includes(".panel{border:1px}"));
  assert.ok(!doc.includes(">F<") && !doc.includes("later"));
});

test("currentStateDoc: no .panel.now → first non-facts panel; no panel → body; panel-title is not a panel", () => {
  const a = P.currentStateDoc(PAGE('<div class="panel-title">T</div><div class="panel facts">F</div><section class=\'optA panel\'>A<section>in</section></section>'));
  assert.ok(a.includes("<section class='optA panel'>A<section>in</section></section>"));
  assert.ok(!a.includes(">F<") && !a.includes(">T<"));
  const b = P.currentStateDoc(PAGE("<h1>hi</h1>"));
  assert.ok(b.includes("<h1>hi</h1>"));
  const c = P.currentStateDoc(PAGE('<div class="now panel" id=x>N</div>'));
  assert.ok(c.includes('<div class="now panel" id=x>N</div>'));
});

test("currentStateDoc: drops scripts, and returns null for no html", () => {
  const doc = P.currentStateDoc(PAGE('<div class="panel now">ok<script>alert(1)</script></div><script>x()</script>'));
  assert.ok(doc.includes("ok") && !/<script/i.test(doc));
  assert.equal(P.currentStateDoc(""), null);
  assert.equal(P.currentStateDoc(null), null);
  assert.equal(P.currentStateDoc("<html><head></head></html>"), null);
});

test("parseRoadmap: [~] (in progress) and [X] rows are items too; [~] is active", () => {
  const [a, b] = P.parseRoadmap("- [~] **R-170** [FEATURE · shipped-in-branch] 做到一半的事\n- [X] **R-171** 大寫 X 的完成列");
  assert.equal(a.id, "R-170");
  assert.equal(a.checked, false);
  assert.equal(a.inProgress, true);
  assert.equal(P.statusOf(a, null, new Date("2026-10-25T12:00:00Z"), 14).group, "active");
  assert.equal(b.id, "R-171");
  assert.equal(b.checked, true);
  assert.equal(b.inProgress, false);
});

test("parseRoadmap: a trailing ✅ annotation is stripped whole, words before its date included", () => {
  assert.equal(by("R-001").headline, "劇情 pipeline");
  const [r] = P.parseRoadmap("- [x] **R-8** 一件事 · ✅ shipped · merged 2026-09-01 · status=done");
  assert.equal(r.headline, "一件事");
});
