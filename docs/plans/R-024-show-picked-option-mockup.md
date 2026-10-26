# R-024 Roadmap 檢視: 完成條件 list and the picked option — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In Roadmap 檢視, list each 完成條件 as a bullet, and show the option a row says was picked — its mockup panel on the detail page before 現況, and as a done item's card thumbnail.

**Architecture:** Two pure functions (`splitConditions`, `optionDoc`) and a wider `picked` in `obsidian-roadmap-view/main.js`, then the view uses them. Every code step is a `git apply` patch from a working prototype, replayed red/green task by task in a linked worktree of this branch.

**Tech Stack:** plain CommonJS Obsidian plugin (desktop + mobile, no Node APIs), Node ≥ 22 `node:test` with the fake `obsidian` module, bats 1.13 for the full suite.

**Spec:** `docs/specs/R-024-show-picked-option-mockup.md`

## Global Constraints

- **Scope.** Edit only `obsidian-roadmap-view/` in this repository. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/`, the home directory or the Obsidian vault. `obsidian-roadmap-view/test/local-vault.test.js` reads the vault read-only when there is one: run it, do not change it.
- Do not run `./sync.sh restore` / `backup`; do not touch Obsidian.
- **Not part of this plan:** `.ship/` (scratch state; `.ship/proto` is a nested git repository). Stage only the paths each commit step names; never `git add -A`.
- **Working directory:** the repository (worktree) root. Patches are the code, generated against this exact base (`5772d83` plus this plan's commit): if one does not apply, STOP — do not hand-edit around it.
- `main.js` may `require` only `"obsidian"`. No `package.json`, no `npm install`.
- Read `.ship/tdd-rules.md` before tests and `.ship/ponytail-rules.md` before code, if present.
- **Known pre-existing failure** in a linked worktree: `cwd-guard: exits 0 when not in a git repo at all`. It must stay the ONLY failure of the full suite.
- One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

1. A done-when line whose brackets or quotes hold a `；` or ` · ` — the content stays one condition. → Task 1.
2. A mockup whose labels do not follow the class names (「版面甲」 in `optB`), or with a second `optB` panel that only mentions 方案 B — the real option is chosen. → Task 1.
3. A `方案 X` inside a done-when line — never read as the picked option. → Task 1.
4. A picked option the mockup does not hold — the card keeps 現況 and the detail page drops the 採用方案 section silently. → Task 2.
5. A not-done item with a decided option — its card keeps 現況; its detail page shows the option. → Task 2.

---
### Task 1: Pure core: `splitConditions`, the picked option, `optionDoc`

Seam: `splitConditions` / `parseRoadmap` (picked) / `optionDoc`

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.1–§3.3, AC-1..AC-5, AC-10. `splitConditions` splits a done-when line at top-level `；`, `;` and ` · `. `picked` comes from `mockup 定案 X` on the row, else the first `方案 X` on a `↳` line that mentions a mockup — never a done-when line. `optionDoc` finds the picked option's panel: first an `opt*` panel with a heading (right before it, or its own first) that *starts* with 方案/版面 X — in the vault 「版面甲」 sits in `optB`, and a later `optB` panel can merely mention 方案 B — else the class `opt<X>`. `currentStateDoc` now shares `panelsOf` / `wrapDoc` with it; its behaviour is unchanged (its tests stay green).

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/local-vault.test.js`
- Create: `obsidian-roadmap-view/test/options.test.js`

**Interfaces:**
- Consumes: R-013's `classesOf`, `elementEnd`, `currentStateDoc`.
- Produces: `RoadmapViewPlugin.splitConditions(text) → string[]`; `RoadmapViewPlugin.optionDoc(html, picked) → {doc, label} | null`; `item.picked` (A–Z or 甲乙丙丁, else null).

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R024_PATCH'
diff --git a/obsidian-roadmap-view/test/local-vault.test.js b/obsidian-roadmap-view/test/local-vault.test.js
index 8fc0169..2f74518 100644
--- a/obsidian-roadmap-view/test/local-vault.test.js
+++ b/obsidian-roadmap-view/test/local-vault.test.js
@@ -36,3 +36,17 @@ test("the real mockups: each R-NNN mockup yields a 現況 document", { skip: !V
     }
   }
 });
+
+test("the real vault: every picked option whose opt panel exists yields an option doc (R-024 AC-10)", { skip: !V && "no vault on this machine" }, () => {
+  for (const p of projects) {
+    const items = P.parseRoadmap(fs.readFileSync(path.join(p, "ROADMAP.md"), "utf8"));
+    const dir = path.join(p, "Proposals", "mockups");
+    const files = fs.existsSync(dir) ? fs.readdirSync(dir).map((f) => `Proposals/mockups/${f}`) : [];
+    for (const it of items.filter((i) => i.picked)) {
+      const htmls = P.mockupsFor(it, items, files).filter((f) => fs.existsSync(path.join(p, f)))
+        .map((f) => fs.readFileSync(path.join(p, f), "utf8"));
+      if (!htmls.some((h) => new RegExp(`class="[^"]*\\bopt${it.picked}\\b|(方案|版面)\\s*${it.picked}`).test(h))) continue;
+      assert.ok(htmls.some((h) => P.optionDoc(h, it.picked)), `${path.basename(p)} ${it.id} 方案 ${it.picked}`);
+    }
+  }
+});
diff --git a/obsidian-roadmap-view/test/options.test.js b/obsidian-roadmap-view/test/options.test.js
new file mode 100644
index 0000000..8435284
--- /dev/null
+++ b/obsidian-roadmap-view/test/options.test.js
@@ -0,0 +1,86 @@
+// R-024 AC-1..AC-5: 完成條件 as a list, the picked option and its mockup panel.
+// Fixture text is invented (this repo is public).
+const test = require("node:test");
+const assert = require("node:assert/strict");
+const P = require("./load");
+
+test("splitConditions: top-level ；, ; and · split; brackets, quotes and backticks protect (AC-1)", () => {
+  assert.deepEqual(P.splitConditions("「A；B」（含 x；y） · C；"), ["「A；B」（含 x；y）", "C"]);
+  assert.deepEqual(P.splitConditions("清單沒有比例欄；新增排序 · 每列有趨勢; 點得開"),
+    ["清單沒有比例欄", "新增排序", "每列有趨勢", "點得開"]);
+  assert.deepEqual(P.splitConditions("`a · b` 照舊 (x; y) 【m；n】 『p · q』 [r; s]"),
+    ["`a · b` 照舊 (x; y) 【m；n】 『p · q』 [r; s]"]);
+  assert.deepEqual(P.splitConditions("沒有分隔的一句"), ["沒有分隔的一句"]);
+  assert.deepEqual(P.splitConditions(" ； · "), []);
+  assert.deepEqual(P.splitConditions("a·b"), ["a·b"]);   // only the spaced ` · ` separates
+});
+
+test("parseRoadmap: picked from 定案 on the row, else 方案 X on a ↳ line that mentions a mockup (AC-2)", () => {
+  const items = P.parseRoadmap([
+    "- [x] **R-1** [FEATURE · mockup 定案 B · ✅ 2026-10-20] 一",
+    "- [x] **R-2** 二 · ✅ 2026-10-20",
+    "    ↳ explain: mockup `Proposals/mockups/two-mockup.html` 方案 C（精簡版）。",
+    "- [ ] **R-3** 三",
+    "    ↳ mockup 同上（方案 A）· 代價：多一步",
+    "- [ ] **R-4** 四",
+    "    ↳ done when: 方案 B 的按鈕要能按",
+    "- [ ] **R-5** 五",
+    "    ↳ mockup [[Proposals/mockups/five-mockup.html|五的 mockup（方案 甲）]]",
+    "- [ ] **R-6** 六",
+    "    ↳ mockup 方案 b 小寫不算 · 方案 ZZ 也不算",
+    "- [ ] **R-7** 七",
+    "    ↳ done when: 有採用方案（mockup 定案 X 或 方案 X）的項目都顯示",
+  ].join("\n"));
+  assert.deepEqual(items.map((i) => i.picked), ["B", "C", "A", null, "甲", null, null]);
+});
+
+const PAGE = (body) => `<html><head><style>.panel{border:1px}</style></head><body>${body}<script>x()</script></body></html>`;
+
+test("optionDoc: the label wins over the class — 版面甲 can sit in optB (AC-3)", () => {
+  const html = PAGE('<div class="panel now">現況</div>'
+    + '<div class="panel optA"><h2>版面乙　沿用熱度表</h2><p>乙的內容</p></div>'
+    + '<div class="panel optB"><h2>版面甲　先排原因<span class="tag">建議</span></h2><div><p>甲的內容</p></div></div>');
+  const r = P.optionDoc(html, "甲");
+  assert.ok(r.doc.includes("甲的內容") && !r.doc.includes("乙的內容") && !r.doc.includes("現況"));
+  assert.equal(r.label, "版面甲 先排原因建議");
+  assert.ok(r.doc.includes(".panel{border:1px}"));
+});
+
+test("optionDoc: a heading before the panel labels it; an unlabelled mockup matches by class (AC-4)", () => {
+  const labelled = PAGE('<h2>方案 A · 一頁看板</h2><div class="panel optA">A 內容</div>'
+    + '<h2>方案 B · 白話週報</h2><div class="panel optB">B 內容</div>');
+  const r = P.optionDoc(labelled, "B");
+  assert.equal(r.label, "方案 B · 白話週報");
+  assert.ok(r.doc.includes("B 內容") && !r.doc.includes("A 內容"));
+  const bare = PAGE('<div class="panel optA">A</div><section class="optB panel"><div>B 本體</div></section>');
+  const b = P.optionDoc(bare, "B");
+  assert.ok(b.doc.includes("<section class=\"optB panel\"><div>B 本體</div></section>"));
+  assert.equal(b.label, "");   // no heading at all: matched by class, no caption
+  // the heading before optA belongs to optA, never to the panel after it
+  const after = PAGE('<h2>方案 A · 看板</h2><div class="panel optA"><p>A</p></div><div class="panel optB"><p>B</p></div>');
+  const b2 = P.optionDoc(after, "B");
+  assert.ok(b2.doc.includes("<p>B</p>") && !b2.doc.includes("<p>A</p>"));
+  assert.equal(b2.label, "");
+});
+
+test("optionDoc: no such option → null; scripts never reach the doc (AC-5)", () => {
+  const html = PAGE('<div class="panel optA">A</div><div class="panel optD">D<script>alert(1)</script></div>');
+  assert.equal(P.optionDoc(html, "C"), null);
+  assert.equal(P.optionDoc(html, null), null);
+  assert.equal(P.optionDoc("", "A"), null);
+  assert.equal(P.optionDoc(html, "甲"), null);   // no label, and 甲 has no class form
+  assert.ok(!/<script/i.test(P.optionDoc(html, "D").doc));
+});
+
+test("optionDoc: only a heading that starts with 方案/版面 X names the option, even after a number", () => {
+  // the real option's title sits before it; a later optB panel only mentions 方案 B mid-sentence
+  const html = PAGE('<h2>方案 B · 另開一頁</h2><div class="panel optB"><h3>跟推播一樣的步驟</h3><p>主方案</p></div>'
+    + '<div class="panel optB"><h3>匯入名單時，方案 B 一起做</h3><p>補充</p></div>');
+  const r = P.optionDoc(html, "B");
+  assert.ok(r.doc.includes("主方案") && !r.doc.includes("補充"));
+  assert.equal(r.label, "方案 B · 另開一頁");
+  const numbered = PAGE('<h2>4 · 方案 A · 發邀請時記下工單 /csat/new?&lt;篩選&gt;&amp;x</h2><div class="panel optC">C 的內容</div>');
+  assert.equal(P.optionDoc(numbered, "A").label, "4 · 方案 A · 發邀請時記下工單 /csat/new?<篩選>&x");
+  const mention = PAGE('<div class="panel optC"><h3>比方案 A 更快的做法</h3>C</div>');
+  assert.equal(P.optionDoc(mention, "A"), null);
+});
R024_PATCH
````

- [ ] **Step 2: Run the plugin tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 56`, `ℹ pass 49`, `ℹ fail 7` — these fail:
  - `✖ the real vault: every picked option whose opt panel exists yields an option doc (R-024 AC-10)`
  - `✖ splitConditions: top-level ；, ; and · split; brackets, quotes and backticks protect (AC-1)`
  - `✖ parseRoadmap: picked from 定案 on the row, else 方案 X on a ↳ line that mentions a mockup (AC-2)`
  - `✖ optionDoc: the label wins over the class — 版面甲 can sit in optB (AC-3)`
  - `✖ optionDoc: a heading before the panel labels it; an unlabelled mockup matches by class (AC-4)`
  - `✖ optionDoc: no such option → null; scripts never reach the doc (AC-5)`
  - `✖ optionDoc: only a heading that starts with 方案/版面 X names the option, even after a number`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R024_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index d308573..4fa3d4c 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -20,6 +20,43 @@ function closeBracket(s) {
   return -1;
 }
 
+// The option a row says was picked: `mockup 定案 X` on the row, else the first `方案 X` on a
+// `↳` line that mentions a mockup (never done-when text, where 方案 can mean anything).
+const OPTION = "([A-Z]|[甲乙丙丁])(?![A-Za-z])";
+function pickedOf(row, ann) {
+  const own = row.match(new RegExp(`mockup 定案\\s*${OPTION}`));
+  if (own) return own[1];
+  for (const a of ann) {
+    if (!/mockup/i.test(a) || a.startsWith("↳ done when:")) continue;
+    const m = a.match(new RegExp(`方案\\s*${OPTION}`));
+    if (m) return m[1];
+  }
+  return null;
+}
+
+// 完成條件 as a list: split at `；`, `;` and ` · ` outside brackets, quotes and backticks.
+const OPENS = "（(「『[【", CLOSES = "）)」』]】";
+function splitConditions(text) {
+  const s = String(text || "");
+  const out = [];
+  const stack = [];
+  let cur = "";
+  for (let i = 0; i < s.length; i++) {
+    const c = s[i];
+    const top = stack[stack.length - 1];
+    if (top === "`") { if (c === "`") stack.pop(); cur += c; continue; }
+    if (c === "`") { stack.push("`"); cur += c; continue; }
+    const o = OPENS.indexOf(c);
+    if (o >= 0) { stack.push(CLOSES[o]); cur += c; continue; }
+    if (c === top) { stack.pop(); cur += c; continue; }
+    if (!stack.length && (c === "；" || c === ";")) { out.push(cur); cur = ""; continue; }
+    if (!stack.length && s.startsWith(" · ", i)) { out.push(cur); cur = ""; i += 2; continue; }
+    cur += c;
+  }
+  out.push(cur);
+  return out.map((x) => x.trim()).filter(Boolean);
+}
+
 function itemFrom(row, m, ann, section, line) {
   const rest = row.slice(m[0].length).trim();
   let tags = "";
@@ -61,7 +98,7 @@ function itemFrom(row, m, ann, section, line) {
     undeployed: undeployed ? (undeployed[1] || "") : null,
     blocked: pick(/blocked:\s*([^·\]\n]*[^·\]\n\s])/),
     needsBrainstorm: /needs-brainstorm/.test(row),
-    picked: pick(/mockup 定案\s*([^\s·\]]+)/),
+    picked: pickedOf(row, ann),
     inReview: /status=in-review/.test(row),
     epic: /epic/i.test(m[6]) || !!m[7] || /^EPIC\b/.test(tags),
     commit: pick(/`([0-9a-f]{7,10})`/),
@@ -181,29 +218,64 @@ function elementEnd(scan, start, name) {
   return -1;
 }
 
-// A string scanner, not DOMParser: testable under node and the same on every platform.
-function currentStateDoc(html) {
-  if (typeof html !== "string" || !html) return null;
+// The mockup's styles, a copy with style/script bodies blanked (same length, so a `<div`
+// inside them is not counted), and every `.panel` element with its extent.
+function panelsOf(html) {
   const styles = (html.match(/<style\b[^>]*>[\s\S]*?<\/style>/gi) || []).join("\n");
-  // Blank out style/script bodies (same length) so a `<div` inside them is not counted.
   const scan = html.replace(/<(style|script)\b[\s\S]*?<\/\1>/gi, (s) => " ".repeat(s.length));
-  const tags = [];
+  const panels = [];
   for (const m of scan.matchAll(/<([a-zA-Z][\w-]*)\b([^>]*)>/g)) {
     const cls = classesOf(m[2]);
-    if (cls.includes("panel")) tags.push({ at: m.index, name: m[1], cls });
+    if (cls.includes("panel")) panels.push({ at: m.index, name: m[1], cls, end: elementEnd(scan, m.index, m[1]) });
   }
-  const pick = tags.find((t) => t.cls.includes("now")) || tags.find((t) => !t.cls.includes("facts"));
-  const end = pick ? elementEnd(scan, pick.at, pick.name) : -1;
-  let el = end > 0 ? html.slice(pick.at, end) : null;
+  return { styles, scan, panels };
+}
+
+// One element of the mockup as a document of its own, with every style and no script.
+function wrapDoc(styles, el) {
+  return `<!DOCTYPE html><html><head><meta charset="utf-8">${styles}
+<style>html,body{margin:0;background:#fff;overflow:hidden}body{padding:12px}.panel{margin:0!important}</style>
+</head><body>${el.replace(/<script\b[\s\S]*?<\/script>/gi, "")}</body></html>`;
+}
+
+// A string scanner, not DOMParser: testable under node and the same on every platform.
+function currentStateDoc(html) {
+  if (typeof html !== "string" || !html) return null;
+  const { styles, panels } = panelsOf(html);
+  const pick = panels.find((t) => t.cls.includes("now")) || panels.find((t) => !t.cls.includes("facts"));
+  let el = pick && pick.end > 0 ? html.slice(pick.at, pick.end) : null;
   if (!el) {
     const b = html.match(/<body\b[^>]*>([\s\S]*)<\/body>/i);
     el = b && b[1].trim() ? b[1] : null;
   }
-  if (!el) return null;
-  el = el.replace(/<script\b[\s\S]*?<\/script>/gi, "");
-  return `<!DOCTYPE html><html><head><meta charset="utf-8">${styles}
-<style>html,body{margin:0;background:#fff;overflow:hidden}body{padding:12px}.panel{margin:0!important}</style>
-</head><body>${el}</body></html>`;
+  return el ? wrapDoc(styles, el) : null;
+}
+
+const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " " };
+const textOf = (h) => h.replace(/<[^>]+>/g, "").replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) => ENTITIES[e])
+  .replace(/\s+/g, " ").trim();
+
+// The picked option's panel: the first `opt*` panel with a heading — right before it, or its
+// own first — that starts with 方案/版面 X (after an optional "4 · "); else class `opt<X>`.
+// A heading that only mentions 方案 X mid-sentence does not count.
+function optionDoc(html, picked) {
+  if (typeof html !== "string" || !html || !picked) return null;
+  const { styles, scan, panels } = panelsOf(html);
+  const heads = [...scan.matchAll(/<h([1-4])\b[^>]*>([\s\S]*?)<\/h\1>/gi)].map((m) => ({ at: m.index, text: m[2] }));
+  const opts = panels.filter((p) => p.end > 0 && p.cls.some((c) => /^opt/.test(c))).map((p) => {
+    const inside = heads.find((h) => h.at > p.at && h.at < p.end);
+    const floor = Math.max(0, ...panels.filter((q) => q.end > 0 && q.end <= p.at).map((q) => q.end));
+    const before = heads.filter((h) => h.at >= floor && h.at < p.at).pop();
+    return { ...p, labels: [before, inside].filter(Boolean).map((h) => textOf(h.text).slice(0, 80)) };
+  });
+  const named = new RegExp(`^(\\d+\\s*[·.、:：]\\s*)?(方案|版面)\\s*${picked}(?![A-Za-z])`);
+  let label = "";
+  let hit = opts.find((o) => (label = o.labels.find((l) => named.test(l)) || "") !== "");
+  if (!hit && /^[A-Z]$/.test(picked)) {
+    hit = opts.find((o) => o.cls.includes(`opt${picked}`));
+    label = hit && hit.labels[0] ? hit.labels[0] : "";
+  }
+  return hit ? { doc: wrapDoc(styles, html.slice(hit.at, hit.end)), label } : null;
 }
 
 // ---------------------------------------------------------------- rendering
@@ -644,5 +716,5 @@ class RoadmapViewPlugin extends Plugin {
   }
 }
 
-Object.assign(RoadmapViewPlugin, { parseRoadmap, mockupsFor, statusOf, currentStateDoc });
+Object.assign(RoadmapViewPlugin, { parseRoadmap, mockupsFor, statusOf, currentStateDoc, splitConditions, optionDoc });
 module.exports = RoadmapViewPlugin;
R024_PATCH
````

- [ ] **Step 4: Run the plugin tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 56`, `ℹ pass 56`, `ℹ fail 0`.

  On a machine without a vault, the `the real …` tests (AC-4b, AC-10) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/local-vault.test.js obsidian-roadmap-view/test/options.test.js
git commit -m "feat(roadmap-view): R-024 Task 1 — split 完成條件, read the picked option, find its mockup panel"
```

### Task 2: The view: 完成條件 as a list; 採用方案 X on the detail page; a done card shows the option

Seam: `RoadmapViewPlugin` (its registered `roadmap-view` view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Spec §3.4, G1, G3, G4, AC-6..AC-9. The detail page lists every done-when condition in one `<ul class="rv-dw">`, and shows 「採用方案 X」 (image + its heading as caption, zoomable) before 現況; when no panel matches, that section removes itself. A done item (`recent` / `done` group) uses its option as the card thumbnail, falling back to 現況; every other card keeps 現況. Mockup entries are cached per `path#now` / `path#opt:X` + mtime; finding the option runs inside the lazy thumbnail job, so a list render reads no mockup until a card is in view.

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/styles.css`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Task 1's `splitConditions`, `optionDoc`, `item.picked`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R024_PATCH'
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index f9db4e8..9a64f18 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -538,7 +538,7 @@ test("a 現況 that loads after the 3 s timeout still keeps its height", async (
   const frame = big.findAll((e) => e.tag === "iframe")[0];
   frame.contentDocument = { body: { scrollHeight: 500 } };
   frame.fire("load");
-  assert.equal(view.docs.get(`${D}/Proposals/mockups/R-3-a-mockup.html`).h, 500);
+  assert.equal(view.docs.get(`${D}/Proposals/mockups/R-3-a-mockup.html#now`).h, 500);
   assert.ok(!big.hasClass("rv-slow"));
 });
 
@@ -556,3 +556,95 @@ test("when the open item's row disappears, a refresh goes back to the list where
   assert.ok(byText(view.contentEl, "近況").hasClass("is-on"));
   assert.equal(view.contentEl.scrollTop, 300);
 });
+
+// --- R-024: 完成條件 as a list; the picked option -------------------------------------
+
+const OPT = (now, b) => `<html><head><style>.y{}</style></head><body><div class="panel now">${now}</div>`
+  + `<h2>方案 A · 甲版</h2><div class="panel optA">A 版</div><h2>方案 B · 乙版</h2><div class="panel optB">${b}</div></body></html>`;
+const PICKED = {
+  ...FILES,
+  [`${D}/ROADMAP.md`]: `## 🔥 Now
+- [x] **R-6** [FEATURE · mockup 定案 B · ✅ 2026-10-21] 做完的事
+    ↳ done when: 畫面上看得到；點得開 · 能放大（含「手機；平板」）
+    ↳ done when: 手機也行
+- [ ] **R-7** [FEATURE · mockup 定案 B] 還沒做完的事
+- [x] **R-8** [FEATURE · mockup 定案 C · ✅ 2026-10-22] 方案找不到的事
+`,
+  [`${D}/Proposals/mockups/R-6-a-mockup.html`]: OPT("六的現況", "六的方案B"),
+  [`${D}/Proposals/mockups/R-7-a-mockup.html`]: OPT("七的現況", "七的方案B"),
+  [`${D}/Proposals/mockups/R-8-a-mockup.html`]: OPT("八的現況", "八的方案B"),
+};
+const cardOf = (view, id) => view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes(id));
+const framesIn = (el) => el.findAll((e) => e.tag === "iframe");
+
+test("a done item's card shows the picked option; a not-done or unmatched one shows 現況 (AC-6, AC-8)", async () => {
+  observed = [];
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  for (let i = 0; i < 3; i++) { view.contentEl.findAll((e) => e.tag === "iframe").forEach((f) => f.fire("load")); await flush(); }
+  const src = (id) => framesIn(cardOf(view, id))[0].attrs.srcdoc;
+  assert.ok(src("R-6").includes("六的方案B") && !src("R-6").includes("六的現況"));
+  assert.ok(src("R-7").includes("七的現況") && !src("R-7").includes("七的方案B"));
+  assert.ok(src("R-8").includes("八的現況"));   // 方案 C is not in its mockup
+});
+
+test("the detail page shows 採用方案 X with its caption first, then 現況; both zoom (AC-7)", async () => {
+  observed = [];
+  Modal.opened = [];
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  cardOf(view, "R-6").fire("click");
+  await flush();
+  const root = view.contentEl;
+  const lbls = root.findAll((e) => e.hasClass("rv-lbl")).map((e) => e.text);
+  assert.deepEqual(lbls.slice(0, 2), ["採用方案 B", "MOCKUP · 現況"]);
+  observed.forEach(seen);
+  await flush();
+  for (let i = 0; i < 3; i++) { framesIn(root).forEach((f) => f.fire("load")); await flush(); }
+  const [opt, now] = root.findAll((e) => e.hasClass("rv-big"));
+  assert.ok(framesIn(opt)[0].attrs.srcdoc.includes("六的方案B"));
+  assert.ok(framesIn(now)[0].attrs.srcdoc.includes("六的現況"));
+  assert.ok(root.findAll((e) => e.hasClass("rv-cap")).some((c) => c.text.startsWith("方案 B · 乙版")));
+  opt.fire("click");
+  now.fire("click");
+  assert.deepEqual(Modal.opened.map((m) => m.title), ["R-6 · 採用方案 B", "R-6 · 現況"]);
+});
+
+test("a not-done item's detail page still shows the decided option; an unmatched one drops the section (AC-8)", async () => {
+  observed = [];
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  cardOf(view, "R-7").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  assert.equal(view.contentEl.findAll((e) => e.hasClass("rv-lbl"))[0].text, "採用方案 B");
+  assert.ok(framesIn(view.contentEl.findAll((e) => e.hasClass("rv-big"))[0])[0].attrs.srcdoc.includes("七的方案B"));
+  byText(view.contentEl, "← 返回").fire("click");
+  await flush();
+  observed = [];
+  cardOf(view, "R-8").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  const lbls = view.contentEl.findAll((e) => e.hasClass("rv-lbl")).map((e) => e.text);
+  assert.ok(!lbls.includes("採用方案 C"), lbls.join(","));
+  assert.equal(view.contentEl.findAll((e) => e.hasClass("rv-big")).length, 1);
+});
+
+test("完成條件 is one list of every line's split conditions, in order (AC-9)", async () => {
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  cardOf(view, "R-6").fire("click");
+  await flush();
+  const lists = view.contentEl.findAll((e) => e.tag === "ul" && e.hasClass("rv-dw"));
+  assert.equal(lists.length, 1);
+  assert.deepEqual(lists[0].children.map((li) => [li.tag, li.text]),
+    [["li", "畫面上看得到"], ["li", "點得開"], ["li", "能放大（含「手機；平板」）"], ["li", "手機也行"]]);
+});
R024_PATCH
````

- [ ] **Step 2: Run the plugin tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 60`, `ℹ pass 55`, `ℹ fail 5` — these fail:
  - `✖ a 現況 that loads after the 3 s timeout still keeps its height`
  - `✖ a done item's card shows the picked option; a not-done or unmatched one shows 現況 (AC-6, AC-8)`
  - `✖ the detail page shows 採用方案 X with its caption first, then 現況; both zoom (AC-7)`
  - `✖ a not-done item's detail page still shows the decided option; an unmatched one drops the section (AC-8)`
  - `✖ 完成條件 is one list of every line's split conditions, in order (AC-9)`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R024_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index 4fa3d4c..e5ffe22 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -377,7 +377,8 @@ class RoadmapView extends ItemView {
     this.folds = new Set();     // titles of the detail page's open folds
     this.listScroll = 0;        // the list's scroll position when a card was opened
     this.shown = null;          // the screen last drawn: a tab, or `detail:<id>`
-    this.docs = new Map();      // mockup path → { mtime, doc }
+    this.docs = new Map();      // "<mockup path>#now|opt:X" → { mtime, doc, label, h }
+    this.chosen = new Map();    // thumbnail slot → the docs key it last drew, to pre-size a redraw
     this.renders = 0;
     this.gen = 0;
     this.resetThumbs();
@@ -526,8 +527,13 @@ class RoadmapView extends ItemView {
     this.chips(left, r.item, r.status);
     left.createDiv({ cls: "rv-title", text: r.item.headline });
     if (r.item.explain) left.createDiv({ cls: "rv-exp", text: r.item.explain });
-    if (r.mockups.length) this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `${d.dir}/${r.mockups[0]}`, r.item.id, 70);
-    else c.addClass("rv-nothumb");
+    if (r.mockups.length) {
+      // A done item shows what was built: its picked option, else 現況.
+      const done = r.status.group === "recent" || r.status.group === "done";
+      const now = this.nowSource(d, r);
+      const opt = done && r.item.picked ? this.optionSource(d, r) : null;
+      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `card:${r.item.id}`, opt ? async () => (await opt()) || now() : now, 70);
+    } else c.addClass("rv-nothumb");
     c.addEventListener("click", () => {
       this.listScroll = this.contentEl.scrollTop || 0;
       this.detail = r.item.id;
@@ -543,10 +549,19 @@ class RoadmapView extends ItemView {
     this.chips(root, item, status);
     root.createDiv({ cls: "rv-title rv-headline", text: item.headline });
     root.createDiv({ cls: item.explain ? "rv-exp rv-full" : "rv-exp rv-faint", text: item.explain || "還沒有白話說明" });
+    if (r.mockups.length && item.picked) {
+      const lbl = root.createDiv({ cls: "rv-lbl", text: `採用方案 ${item.picked}` });
+      const box = root.createDiv({ cls: "rv-big" });
+      const cap = root.createDiv({ cls: "rv-cap", text: "點圖放大" });
+      this.lazyThumb(box, `opt:${item.id}`, this.optionSource(d, r), 0, {
+        label: (l) => { if (l) cap.setText(`${l} · 點圖放大`); },
+        missing: () => { lbl.remove(); box.remove(); cap.remove(); },   // no such panel: say nothing
+      });
+    }
     if (r.mockups.length) {
       root.createDiv({ cls: "rv-lbl", text: "MOCKUP · 現況" });
       const big = root.createDiv({ cls: "rv-big" });
-      this.lazyThumb(big, `${d.dir}/${r.mockups[0]}`, item.id, 0);
+      this.lazyThumb(big, `now:${item.id}`, this.nowSource(d, r), 0);
       root.createDiv({ cls: "rv-cap", text: "點圖放大" });
     }
     root.createDiv({ cls: "rv-lbl", text: "相關文件" });
@@ -572,8 +587,12 @@ class RoadmapView extends ItemView {
       det.open = this.folds.has(title);   // a live refresh keeps what the reader opened
       det.addEventListener("toggle", () => { if (det.open) this.folds.add(title); else this.folds.delete(title); });
       for (const l of lines) det.createDiv({ cls: "rv-raw", text: l });
+      return det;
     };
-    if (item.doneWhen.length) fold("完成條件", item.doneWhen);
+    if (item.doneWhen.length) {
+      const ul = fold("完成條件", []).createEl("ul", { cls: "rv-dw" });
+      for (const line of item.doneWhen) for (const c of splitConditions(line)) ul.createEl("li", { text: c });
+    }
     fold("給 AI 的原文", [item.raw, ...item.ann]);
     const jump = root.createEl("a", { cls: "rv-link", text: "在 ROADMAP.md 打開這一行" });
     jump.addEventListener("click", async (e) => {
@@ -602,10 +621,32 @@ class RoadmapView extends ItemView {
     this.io = null;
   }
 
-  lazyThumb(box, path, id, maxHeight) {
-    const hit = this.docs.get(path);
+  // What a thumbnail shows is found lazily: `find` resolves to { key, title } of a cached
+  // entry, or null. `slot` names the box across redraws; `on.label` / `on.missing` hear the result.
+  nowSource(d, r) {
+    const path = `${d.dir}/${r.mockups[0]}`;
+    return async () => {
+      const e = await this.entryFor(path, "now");
+      return e && e.doc ? { key: `${path}#now`, title: `${r.item.id} · 現況` } : null;
+    };
+  }
+
+  optionSource(d, r) {
+    const x = r.item.picked;
+    return async () => {
+      for (const m of r.mockups) {
+        const path = `${d.dir}/${m}`;
+        const e = await this.entryFor(path, `opt:${x}`);
+        if (e && e.doc) return { key: `${path}#opt:${x}`, title: `${r.item.id} · 採用方案 ${x}` };
+      }
+      return null;
+    };
+  }
+
+  lazyThumb(box, slot, find, maxHeight, on = {}) {
+    const hit = this.docs.get(this.chosen.get(slot));
     if (hit && hit.h) fitBox(box, hit.h, maxHeight);   // a redraw does not collapse to 0 px first
-    const job = () => this.drawThumb(box, path, id, maxHeight);
+    const job = () => this.drawThumb(box, slot, find, maxHeight, on);
     if (typeof IntersectionObserver === "undefined") { this.enqueue(job); return; }
     if (!this.io) {
       this.io = new IntersectionObserver((entries) => {
@@ -634,29 +675,33 @@ class RoadmapView extends ItemView {
     }
   }
 
-  async drawThumb(box, path, id, maxHeight) {
-    let doc;
-    try { doc = await this.docFor(path); } catch (e) { box.setText("讀不到 mockup"); return; }
-    if (!doc) { box.setText("沒有現況"); return; }
+  async drawThumb(box, slot, find, maxHeight, on) {
+    let got;
+    try { got = await find(); } catch (e) { box.setText("讀不到 mockup"); return; }
+    const entry = got && this.docs.get(got.key);
+    if (!entry) { if (on.missing) on.missing(); else box.setText("沒有現況"); return; }
+    this.chosen.set(slot, got.key);
+    if (on.label) on.label(entry.label);
     box.addEventListener("click", (e) => {
       e.stopPropagation();   // a thumbnail tap zooms; it does not open the card
-      new ZoomModal(this.app, `${id} · 現況`, doc).open();
-    });
-    await thumb(box, doc, maxHeight, (h) => {
-      const hit = this.docs.get(path);
-      if (hit) hit.h = h;
+      new ZoomModal(this.app, got.title, entry.doc).open();
     });
+    await thumb(box, entry.doc, maxHeight, (h) => { entry.h = h; });
   }
 
-  async docFor(path) {
+  // One mockup's 現況 (`now`) or option panel (`opt:X`), cached per path + kind + mtime.
+  async entryFor(path, kind) {
     const adapter = this.app.vault.adapter;
     const st = await adapter.stat(path);
     if (!st) return null;
-    const hit = this.docs.get(path);
-    if (hit && hit.mtime === st.mtime) return hit.doc;
-    const doc = currentStateDoc(await adapter.read(path));
-    this.docs.set(path, { mtime: st.mtime, doc });
-    return doc;
+    const key = `${path}#${kind}`;
+    const hit = this.docs.get(key);
+    if (hit && hit.mtime === st.mtime) return hit;
+    const html = await adapter.read(path);
+    const o = kind === "now" ? { doc: currentStateDoc(html), label: "" } : optionDoc(html, kind.slice(4)) || { doc: null, label: "" };
+    const entry = { mtime: st.mtime, doc: o.doc, label: o.label };
+    this.docs.set(key, entry);
+    return entry;
   }
 }
 
diff --git a/obsidian-roadmap-view/styles.css b/obsidian-roadmap-view/styles.css
index e33aef3..b69b9f4 100644
--- a/obsidian-roadmap-view/styles.css
+++ b/obsidian-roadmap-view/styles.css
@@ -51,3 +51,5 @@
 .rv-zoom-scroll { overflow: auto; -webkit-overflow-scrolling: touch; height: calc(92vh - 120px);
   background: #fff; border-radius: 8px; border: 1px solid var(--background-modifier-border); }
 .rv-zoom-inner { overflow: hidden; }
+.rv-dw { margin: 6px 0 6px 18px; padding: 0; }
+.rv-dw li { margin: 3px 0; line-height: 1.45; color: var(--text-normal); }
R024_PATCH
````

- [ ] **Step 4: Run the plugin tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 60`, `ℹ pass 60`, `ℹ fail 0`.

  On a machine without a vault, the `the real …` tests (AC-4b, AC-10) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/styles.css obsidian-roadmap-view/test/view.test.js
git commit -m "feat(roadmap-view): R-024 Task 2 — 完成條件 list, 採用方案 X image, done cards show the option"
```

### Task 3: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole bats suite** (it includes the plugin's `node --test`)

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..698`, 697 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Run the plugin tests on their own**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 60`, `ℹ fail 0`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 and Step 2 counts.
