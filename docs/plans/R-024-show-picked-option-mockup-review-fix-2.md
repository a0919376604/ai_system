# R-024 review fix 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding of R-024's first review round (spec review, correctness, races), each reproduced against the vault: 5 blocking, 1 important, 5 nits (`/tmp/ship-next-review-R-024-1.md`, `/tmp/ship-next-spec-R-024-1.md`).

**Architecture:** Same method as the main plan (`docs/plans/R-024-show-picked-option-mockup.md`, already executed on this branch). Every code step is a `git apply` patch from a working prototype, replayed red/green task by task in a linked worktree of this branch.

**Tech Stack:** plain CommonJS Obsidian plugin (desktop + mobile, no Node APIs), Node ≥ 22 `node:test` with the fake `obsidian` module, bats 1.13 for the full suite.

**Spec:** `docs/specs/R-024-show-picked-option-mockup.md` (its "Review attempt 1" decisions)

## Global Constraints

- **Scope.** Edit only `obsidian-roadmap-view/` in this repository. Do NOT read, edit or create anything under `~/.claude/`, `~/.agents/`, the home directory or the Obsidian vault. `obsidian-roadmap-view/test/local-vault.test.js` reads the vault read-only when there is one: run it, do not change it.
- Do not run `./sync.sh restore` / `backup`; do not touch Obsidian.
- **Not part of this plan:** `.ship/` (scratch state; `.ship/proto` is a nested git repository). Stage only the paths each commit step names; never `git add -A`.
- **Working directory:** the repository (worktree) root. Patches are the code, generated against this exact base (`1b1ab28` plus this plan's commit): if one does not apply, STOP — do not hand-edit around it.
- `main.js` may `require` only `"obsidian"`. No `package.json`, no `npm install`.
- Read `.ship/tdd-rules.md` before tests and `.ship/ponytail-rules.md` before code, if present.
- **Known pre-existing failure** in a linked worktree: `cwd-guard: exits 0 when not in a git repo at all`. It must stay the ONLY failure of the full suite.
- One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

1. A mockup whose option panel never closes — the heading inside it labels it, never the panel after it. → Task 1.
2. An item with two mockups — a heading that names 方案 X in the second beats a bare `optX` class in the first. → Task 1.
3. A live refresh on a detail page whose option has a long title — nothing below the caption moves. → Task 1.
4. A row that writes `方案 X 定案` — it has a picked option. → Task 2.
5. A mockup that is half-synced on the phone — skipped; the card and the page still show what can be found. → Task 2.

---
### Task 1: Unclosed panels, label-first across mockups, caption from cache, no flash, 現況 fallback

Seam: `optionDoc` / `RoadmapViewPlugin` (its view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1 (spec review + correctness + races, all reproduced on the vault). An unclosed option, 現況 or facts panel now ends where the next one starts: in the real insights-handoff-reasons mockup, `optB`'s markup never closes and its 「版面甲」 heading labelled the `optA` after it, so 甲 returned 乙's panel. `optionDoc` reports `by: label | class`, and the view prefers a label match in any of the item's mockups over a class match in an earlier one (R-257). The detail page draws the 採用方案 caption from the cache and keeps the label and caption hidden until the option is found the first time, so a refresh moves nothing and a missing option never flashes. A done card falls back to 現況 when the option search fails. AC-10's local test now checks every picked row whose mockups hold any `opt*` panel, as AC-10 says.

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/local-vault.test.js`
- Modify: `obsidian-roadmap-view/test/options.test.js`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: the main plan's `optionDoc`, `optionSource`, `entryFor`, `drawDetail`.
- Produces: `optionDoc(...).by`; cache entries carry `by`.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R024_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/test/local-vault.test.js b/obsidian-roadmap-view/test/local-vault.test.js
index 2f74518..4cbabc4 100644
--- a/obsidian-roadmap-view/test/local-vault.test.js
+++ b/obsidian-roadmap-view/test/local-vault.test.js
@@ -45,7 +45,7 @@ test("the real vault: every picked option whose opt panel exists yields an optio
     for (const it of items.filter((i) => i.picked)) {
       const htmls = P.mockupsFor(it, items, files).filter((f) => fs.existsSync(path.join(p, f)))
         .map((f) => fs.readFileSync(path.join(p, f), "utf8"));
-      if (!htmls.some((h) => new RegExp(`class="[^"]*\\bopt${it.picked}\\b|(方案|版面)\\s*${it.picked}`).test(h))) continue;
+      if (!htmls.some((h) => /class="[^"]*\bopt\w*/.test(h))) continue;   // AC-10: any opt* panel
       assert.ok(htmls.some((h) => P.optionDoc(h, it.picked)), `${path.basename(p)} ${it.id} 方案 ${it.picked}`);
     }
   }
diff --git a/obsidian-roadmap-view/test/options.test.js b/obsidian-roadmap-view/test/options.test.js
index 8435284..b2d9f06 100644
--- a/obsidian-roadmap-view/test/options.test.js
+++ b/obsidian-roadmap-view/test/options.test.js
@@ -84,3 +84,23 @@ test("optionDoc: only a heading that starts with 方案/版面 X names the optio
   const mention = PAGE('<div class="panel optC"><h3>比方案 A 更快的做法</h3>C</div>');
   assert.equal(P.optionDoc(mention, "A"), null);
 });
+
+// --- R-024 review attempt 1 -------------------------------------------------------
+
+test("optionDoc: an unclosed option panel ends where the next one starts; its heading never labels the next", () => {
+  // as in a real mockup: optB's markup never closes, then optA follows
+  const html = PAGE('<!-- 甲 --><div class="panel optB"><h2>版面甲 先排原因</h2><div class="ui"><p>甲的畫面</p>'
+    + '<div class="panel optA"><h2>版面乙 沿用熱度表</h2><p>乙的畫面</p></div>');
+  const jia = P.optionDoc(html, "甲");
+  assert.ok(jia.doc.includes("甲的畫面") && !jia.doc.includes("乙的畫面"));
+  assert.equal(jia.label, "版面甲 先排原因");
+  const yi = P.optionDoc(html, "乙");
+  assert.ok(yi.doc.includes("乙的畫面") && !yi.doc.includes("甲的畫面"));
+  assert.equal(P.optionDoc(html, "A").label, "版面乙 沿用熱度表");   // class match keeps optA's own heading
+});
+
+test("optionDoc: says whether it matched by label or by class", () => {
+  const html = PAGE('<h2>方案 A · 甲</h2><div class="panel optA">A</div><div class="panel optB">B</div>');
+  assert.equal(P.optionDoc(html, "A").by, "label");
+  assert.equal(P.optionDoc(html, "B").by, "class");
+});
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index 9a64f18..4ff76a7 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -648,3 +648,69 @@ test("完成條件 is one list of every line's split conditions, in order (AC-9)
   assert.deepEqual(lists[0].children.map((li) => [li.tag, li.text]),
     [["li", "畫面上看得到"], ["li", "點得開"], ["li", "能放大（含「手機；平板」）"], ["li", "手機也行"]]);
 });
+
+// --- R-024 review attempt 1 -------------------------------------------------------
+
+const TWO = {
+  ...FILES,
+  [`${D}/ROADMAP.md`]: `## 🔥 Now
+- [x] **R-9** [FEATURE · mockup 定案 B · ✅ 2026-10-21] 兩份 mockup 的事
+    ↳ mockup [[Proposals/mockups/second-mockup.html|二號（方案 B）]]
+- [x] **R-8** [FEATURE · mockup 定案 C · ✅ 2026-10-22] 方案找不到的事
+`,
+  // the item's own file comes first and has an unlabelled optB; the labelled 方案 B is in the second
+  [`${D}/Proposals/mockups/R-9-a-mockup.html`]: `<html><body><div class="panel now">九的現況</div><div class="panel optB">一號的B</div></body></html>`,
+  [`${D}/Proposals/mockups/second-mockup.html`]: OPT("二號的現況", "二號的方案B"),
+  [`${D}/Proposals/mockups/R-8-a-mockup.html`]: OPT("八的現況", "八的方案B"),
+};
+
+test("a label match in any of the item's mockups beats a class match in an earlier one", async () => {
+  observed = [];
+  const { view } = await setup(TWO);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  assert.ok(framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc.includes("二號的方案B"));
+});
+
+test("a refresh draws the 採用方案 caption from the cache, so nothing below it moves", async () => {
+  observed = [];
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  cardOf(view, "R-6").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  observed = [];
+  await view.render();   // nothing seen yet in this render
+  const caps = view.contentEl.findAll((e) => e.hasClass("rv-cap")).map((c) => c.text);
+  assert.equal(caps[0], "方案 B · 乙版 · 點圖放大");
+});
+
+test("an option that is not found shows no 採用方案 label while it is looked for", async () => {
+  observed = [];
+  const { view } = await setup(PICKED);
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  cardOf(view, "R-8").fire("click");
+  await flush();
+  const lbl = view.contentEl.findAll((e) => e.text === "採用方案 C")[0];
+  assert.equal(lbl.style.display, "none");
+  observed.forEach(seen);
+  await flush();
+  assert.equal(view.contentEl.findAll((e) => e.text === "採用方案 C").length, 0);
+});
+
+test("a done card whose option search fails still shows 現況", async () => {
+  observed = [];
+  const { view, app } = await setup(TWO);
+  app.failRead = "second-mockup.html";
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  const src = framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc;
+  assert.ok(src.includes("九的現況"), src.slice(0, 200));
+});
R024_FIX2_PATCH
````

- [ ] **Step 2: Run the plugin tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 66`, `ℹ pass 60`, `ℹ fail 6` — these fail:
  - `✖ optionDoc: an unclosed option panel ends where the next one starts; its heading never labels the next`
  - `✖ optionDoc: says whether it matched by label or by class`
  - `✖ a label match in any of the item's mockups beats a class match in an earlier one`
  - `✖ a refresh draws the 採用方案 caption from the cache, so nothing below it moves`
  - `✖ an option that is not found shows no 採用方案 label while it is looked for`
  - `✖ a done card whose option search fails still shows 現況`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R024_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index e5ffe22..3716199 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -228,6 +228,14 @@ function panelsOf(html) {
     const cls = classesOf(m[2]);
     if (cls.includes("panel")) panels.push({ at: m.index, name: m[1], cls, end: elementEnd(scan, m.index, m[1]) });
   }
+  // An option, 現況 or facts panel whose markup never closes ends where the next one starts
+  // (they are siblings); otherwise its headings would be read as the next panel's.
+  const top = (p) => p.cls.some((c) => /^opt/.test(c) || c === "now" || c === "facts");
+  panels.forEach((p, i) => {
+    if (p.end > 0 || !top(p)) return;
+    const next = panels.slice(i + 1).find(top);
+    if (next) p.end = next.at;
+  });
   return { styles, scan, panels };
 }
 
@@ -270,12 +278,14 @@ function optionDoc(html, picked) {
   });
   const named = new RegExp(`^(\\d+\\s*[·.、:：]\\s*)?(方案|版面)\\s*${picked}(?![A-Za-z])`);
   let label = "";
+  let by = "label";
   let hit = opts.find((o) => (label = o.labels.find((l) => named.test(l)) || "") !== "");
   if (!hit && /^[A-Z]$/.test(picked)) {
+    by = "class";
     hit = opts.find((o) => o.cls.includes(`opt${picked}`));
     label = hit && hit.labels[0] ? hit.labels[0] : "";
   }
-  return hit ? { doc: wrapDoc(styles, html.slice(hit.at, hit.end)), label } : null;
+  return hit ? { doc: wrapDoc(styles, html.slice(hit.at, hit.end)), label, by } : null;
 }
 
 // ---------------------------------------------------------------- rendering
@@ -532,7 +542,8 @@ class RoadmapView extends ItemView {
       const done = r.status.group === "recent" || r.status.group === "done";
       const now = this.nowSource(d, r);
       const opt = done && r.item.picked ? this.optionSource(d, r) : null;
-      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `card:${r.item.id}`, opt ? async () => (await opt()) || now() : now, 70);
+      const find = opt ? async () => (await opt().catch(() => null)) || now() : now;   // a failed search still shows 現況
+      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `card:${r.item.id}`, find, 70);
     } else c.addClass("rv-nothumb");
     c.addEventListener("click", () => {
       this.listScroll = this.contentEl.scrollTop || 0;
@@ -550,11 +561,19 @@ class RoadmapView extends ItemView {
     root.createDiv({ cls: "rv-title rv-headline", text: item.headline });
     root.createDiv({ cls: item.explain ? "rv-exp rv-full" : "rv-exp rv-faint", text: item.explain || "還沒有白話說明" });
     if (r.mockups.length && item.picked) {
+      // From the cache when this item's option was drawn before, so a refresh moves nothing;
+      // hidden until found the first time, so a missing option never flashes.
+      const seen = this.docs.get(this.chosen.get(`opt:${item.id}`));
       const lbl = root.createDiv({ cls: "rv-lbl", text: `採用方案 ${item.picked}` });
       const box = root.createDiv({ cls: "rv-big" });
-      const cap = root.createDiv({ cls: "rv-cap", text: "點圖放大" });
+      const cap = root.createDiv({ cls: "rv-cap", text: seen && seen.label ? `${seen.label} · 點圖放大` : "點圖放大" });
+      if (!seen) { lbl.style.display = "none"; cap.style.display = "none"; }
       this.lazyThumb(box, `opt:${item.id}`, this.optionSource(d, r), 0, {
-        label: (l) => { if (l) cap.setText(`${l} · 點圖放大`); },
+        label: (l) => {
+          if (l) cap.setText(`${l} · 點圖放大`);
+          lbl.style.display = "";
+          cap.style.display = "";
+        },
         missing: () => { lbl.remove(); box.remove(); cap.remove(); },   // no such panel: say nothing
       });
     }
@@ -631,13 +650,16 @@ class RoadmapView extends ItemView {
     };
   }
 
+  // A label match in any of the item's mockups beats a class match in an earlier one.
   optionSource(d, r) {
     const x = r.item.picked;
     return async () => {
-      for (const m of r.mockups) {
-        const path = `${d.dir}/${m}`;
-        const e = await this.entryFor(path, `opt:${x}`);
-        if (e && e.doc) return { key: `${path}#opt:${x}`, title: `${r.item.id} · 採用方案 ${x}` };
+      for (const by of ["label", "class"]) {
+        for (const m of r.mockups) {
+          const path = `${d.dir}/${m}`;
+          const e = await this.entryFor(path, `opt:${x}`);
+          if (e && e.doc && e.by === by) return { key: `${path}#opt:${x}`, title: `${r.item.id} · 採用方案 ${x}` };
+        }
       }
       return null;
     };
@@ -699,7 +721,7 @@ class RoadmapView extends ItemView {
     if (hit && hit.mtime === st.mtime) return hit;
     const html = await adapter.read(path);
     const o = kind === "now" ? { doc: currentStateDoc(html), label: "" } : optionDoc(html, kind.slice(4)) || { doc: null, label: "" };
-    const entry = { mtime: st.mtime, doc: o.doc, label: o.label };
+    const entry = { mtime: st.mtime, doc: o.doc, label: o.label, by: o.by };
     this.docs.set(key, entry);
     return entry;
   }
R024_FIX2_PATCH
````

- [ ] **Step 4: Run the plugin tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 66`, `ℹ pass 66`, `ℹ fail 0`.

  On a machine without a vault, the `the real …` tests (AC-4b, AC-10) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/local-vault.test.js obsidian-roadmap-view/test/options.test.js obsidian-roadmap-view/test/view.test.js
git commit -m "fix(roadmap-view): R-024 review 1 — unclosed panels, label-first across mockups, stable caption"
```

### Task 2: `方案 X 定案` rows; own-heading captions; skip unreadable mockups; project-keyed sizes

Seam: `parseRoadmap` (picked) / `optionDoc` / `RoadmapViewPlugin` (its view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 1. `picked` also reads `方案 X 定案` on the row — the vault's three newest done items (R-253 to R-255) use it and showed no option. A class match is captioned with the panel's own heading rather than a section heading shared by every option. A tag inside a heading reads as a word break, so badges no longer glue onto the caption. The option search skips a mockup it cannot read (half-synced) and goes on. Thumbnail slots are keyed by project dir + role + id, and the detail page's images start at the height the card already measured.

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/options.test.js`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: Task 1 of this plan.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R024_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/test/options.test.js b/obsidian-roadmap-view/test/options.test.js
index b2d9f06..02ca6e6 100644
--- a/obsidian-roadmap-view/test/options.test.js
+++ b/obsidian-roadmap-view/test/options.test.js
@@ -42,7 +42,7 @@ test("optionDoc: the label wins over the class — 版面甲 can sit in optB (AC
     + '<div class="panel optB"><h2>版面甲　先排原因<span class="tag">建議</span></h2><div><p>甲的內容</p></div></div>');
   const r = P.optionDoc(html, "甲");
   assert.ok(r.doc.includes("甲的內容") && !r.doc.includes("乙的內容") && !r.doc.includes("現況"));
-  assert.equal(r.label, "版面甲 先排原因建議");
+  assert.equal(r.label, "版面甲 先排原因 建議");   // a tag's text is a word of its own
   assert.ok(r.doc.includes(".panel{border:1px}"));
 });
 
@@ -104,3 +104,21 @@ test("optionDoc: says whether it matched by label or by class", () => {
   assert.equal(P.optionDoc(html, "A").by, "label");
   assert.equal(P.optionDoc(html, "B").by, "class");
 });
+
+test("parseRoadmap: the row form 方案 X 定案 names the picked option too", () => {
+  const items = P.parseRoadmap([
+    "- [x] **R-1** [FEATURE · ✅ merged 2026-10-22 · 方案 A 定案 · learning `x.md`] 一",
+    "- [x] **R-2** [FEATURE · 方案B定案] 二",
+    "- [x] **R-3** [FEATURE · mockup 定案 C · 方案 A 定案] 三",
+    "- [ ] **R-4** 四 —— 方案 A 還沒定案",
+  ].join("\n"));
+  assert.deepEqual(items.map((i) => i.picked), ["A", "B", "C", null]);
+});
+
+test("optionDoc: a class match is captioned with the panel's own heading, not a shared section heading", () => {
+  const html = PAGE('<h2>第三部分 · 三個做法</h2><div class="panel optA"><h3>A · 清單最上面一條</h3>A</div>'
+    + '<div class="panel optB"><h3>B · 另開一頁</h3>B</div>');
+  const r = P.optionDoc(html, "A");
+  assert.equal(r.by, "class");
+  assert.equal(r.label, "A · 清單最上面一條");
+});
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index 4ff76a7..529471d 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -703,14 +703,68 @@ test("an option that is not found shows no 採用方案 label while it is looked
   assert.equal(view.contentEl.findAll((e) => e.text === "採用方案 C").length, 0);
 });
 
-test("a done card whose option search fails still shows 現況", async () => {
+test("a mockup that cannot be read is skipped: card and detail page use what can be found", async () => {
   observed = [];
   const { view, app } = await setup(TWO);
-  app.failRead = "second-mockup.html";
+  app.failRead = "second-mockup.html";   // half-synced on the phone
   byText(view.contentEl, "全部").fire("click");
   await flush();
   observed.forEach(seen);
   await flush();
-  const src = framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc;
-  assert.ok(src.includes("九的現況"), src.slice(0, 200));
+  assert.ok(framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc.includes("一號的B"));
+  observed = [];
+  cardOf(view, "R-9").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  assert.ok(framesIn(view.contentEl.findAll((e) => e.hasClass("rv-big"))[0])[0].attrs.srcdoc.includes("一號的B"));
+});
+
+test("a done card still shows 現況 when its option search throws outright", async () => {
+  observed = [];
+  const { view } = await setup(TWO);
+  view.optionSource = () => async () => { throw new Error("boom"); };
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  observed.forEach(seen);
+  await flush();
+  assert.ok(framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc.includes("九的現況"));
+});
+
+test("the detail page's images start at the height the card already measured", async () => {
+  observed = [];
+  const { view } = await setup();
+  const card = cardOf(view, "R-3");
+  observed.filter((o) => card.contains(o.el)).forEach(seen);
+  await flush();
+  const f = framesIn(card)[0];
+  f.contentDocument = { body: { scrollHeight: 400 } };
+  f.fire("load");
+  await flush();
+  observed = [];
+  card.fire("click");
+  await flush();
+  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
+  assert.equal(framesIn(big).length, 0);              // not drawn yet
+  assert.equal(big.style.aspectRatio, "1100 / 400");  // but already sized
+});
+
+test("a thumbnail's remembered size belongs to its project, not to an id another project reuses", async () => {
+  observed = [];
+  const files = { ...FILES, "10 Projects/other/ROADMAP.md": "- [x] **R-3** 別的專案的 R-3 · ✅ 2026-10-20\n",
+    "10 Projects/other/Proposals/mockups/R-3-a-mockup.html": MOCK("別的") };
+  const { view, plugin } = await setup(files);
+  const card = cardOf(view, "R-3");
+  observed.filter((o) => card.contains(o.el)).forEach(seen);
+  await flush();
+  const f = framesIn(card)[0];
+  f.contentDocument = { body: { scrollHeight: 400 } };
+  f.fire("load");
+  await flush();
+  plugin.settings.project = "other";
+  observed = [];
+  await view.render();
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  assert.equal(cardOf(view, "R-3").findAll((e) => e.hasClass("rv-thumb"))[0].style.aspectRatio, undefined);
 });
R024_FIX2_PATCH
````

- [ ] **Step 2: Run the plugin tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 71`, `ℹ pass 65`, `ℹ fail 6` — these fail:
  - `✖ optionDoc: the label wins over the class — 版面甲 can sit in optB (AC-3)`
  - `✖ parseRoadmap: the row form 方案 X 定案 names the picked option too`
  - `✖ optionDoc: a class match is captioned with the panel's own heading, not a shared section heading`
  - `✖ a mockup that cannot be read is skipped: card and detail page use what can be found`
  - `✖ the detail page's images start at the height the card already measured`
  - `✖ a thumbnail's remembered size belongs to its project, not to an id another project reuses`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R024_FIX2_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index 3716199..e2ea862 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -20,11 +20,11 @@ function closeBracket(s) {
   return -1;
 }
 
-// The option a row says was picked: `mockup 定案 X` on the row, else the first `方案 X` on a
+// The option a row says was picked: `mockup 定案 X` or `方案 X 定案` on the row, else the first `方案 X` on a
 // `↳` line that mentions a mockup (never done-when text, where 方案 can mean anything).
 const OPTION = "([A-Z]|[甲乙丙丁])(?![A-Za-z])";
 function pickedOf(row, ann) {
-  const own = row.match(new RegExp(`mockup 定案\\s*${OPTION}`));
+  const own = row.match(new RegExp(`mockup 定案\\s*${OPTION}`)) || row.match(new RegExp(`方案\\s*${OPTION}\\s*定案`));
   if (own) return own[1];
   for (const a of ann) {
     if (!/mockup/i.test(a) || a.startsWith("↳ done when:")) continue;
@@ -260,7 +260,7 @@ function currentStateDoc(html) {
 }
 
 const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " " };
-const textOf = (h) => h.replace(/<[^>]+>/g, "").replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) => ENTITIES[e])
+const textOf = (h) => h.replace(/<[^>]+>/g, " ").replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) => ENTITIES[e])
   .replace(/\s+/g, " ").trim();
 
 // The picked option's panel: the first `opt*` panel with a heading — right before it, or its
@@ -283,7 +283,7 @@ function optionDoc(html, picked) {
   if (!hit && /^[A-Z]$/.test(picked)) {
     by = "class";
     hit = opts.find((o) => o.cls.includes(`opt${picked}`));
-    label = hit && hit.labels[0] ? hit.labels[0] : "";
+    label = hit ? hit.labels[hit.labels.length - 1] || "" : "";   // its own heading, else the one before it
   }
   return hit ? { doc: wrapDoc(styles, html.slice(hit.at, hit.end)), label, by } : null;
 }
@@ -543,7 +543,7 @@ class RoadmapView extends ItemView {
       const now = this.nowSource(d, r);
       const opt = done && r.item.picked ? this.optionSource(d, r) : null;
       const find = opt ? async () => (await opt().catch(() => null)) || now() : now;   // a failed search still shows 現況
-      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `card:${r.item.id}`, find, 70);
+      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `${d.dir}|card:${r.item.id}`, find, 70);
     } else c.addClass("rv-nothumb");
     c.addEventListener("click", () => {
       this.listScroll = this.contentEl.scrollTop || 0;
@@ -563,12 +563,15 @@ class RoadmapView extends ItemView {
     if (r.mockups.length && item.picked) {
       // From the cache when this item's option was drawn before, so a refresh moves nothing;
       // hidden until found the first time, so a missing option never flashes.
-      const seen = this.docs.get(this.chosen.get(`opt:${item.id}`));
+      const fromCard = this.chosen.get(`${d.dir}|card:${item.id}`);
+      const optKey = this.chosen.get(`${d.dir}|opt:${item.id}`) || (fromCard && fromCard.includes("#opt:") ? fromCard : null);
+      const seen = this.docs.get(optKey);
       const lbl = root.createDiv({ cls: "rv-lbl", text: `採用方案 ${item.picked}` });
       const box = root.createDiv({ cls: "rv-big" });
       const cap = root.createDiv({ cls: "rv-cap", text: seen && seen.label ? `${seen.label} · 點圖放大` : "點圖放大" });
       if (!seen) { lbl.style.display = "none"; cap.style.display = "none"; }
-      this.lazyThumb(box, `opt:${item.id}`, this.optionSource(d, r), 0, {
+      this.lazyThumb(box, `${d.dir}|opt:${item.id}`, this.optionSource(d, r), 0, {
+        presize: optKey,
         label: (l) => {
           if (l) cap.setText(`${l} · 點圖放大`);
           lbl.style.display = "";
@@ -580,7 +583,7 @@ class RoadmapView extends ItemView {
     if (r.mockups.length) {
       root.createDiv({ cls: "rv-lbl", text: "MOCKUP · 現況" });
       const big = root.createDiv({ cls: "rv-big" });
-      this.lazyThumb(big, `now:${item.id}`, this.nowSource(d, r), 0);
+      this.lazyThumb(big, `${d.dir}|now:${item.id}`, this.nowSource(d, r), 0, { presize: `${d.dir}/${r.mockups[0]}#now` });
       root.createDiv({ cls: "rv-cap", text: "點圖放大" });
     }
     root.createDiv({ cls: "rv-lbl", text: "相關文件" });
@@ -641,7 +644,8 @@ class RoadmapView extends ItemView {
   }
 
   // What a thumbnail shows is found lazily: `find` resolves to { key, title } of a cached
-  // entry, or null. `slot` names the box across redraws; `on.label` / `on.missing` hear the result.
+  // entry, or null. `slot` (project dir + role + id) names the box across redraws;
+  // `on.label` / `on.missing` hear the result; `on.presize` is a cache key to size from first.
   nowSource(d, r) {
     const path = `${d.dir}/${r.mockups[0]}`;
     return async () => {
@@ -657,7 +661,8 @@ class RoadmapView extends ItemView {
       for (const by of ["label", "class"]) {
         for (const m of r.mockups) {
           const path = `${d.dir}/${m}`;
-          const e = await this.entryFor(path, `opt:${x}`);
+          let e;
+          try { e = await this.entryFor(path, `opt:${x}`); } catch (err) { continue; }   // half-synced: try the next
           if (e && e.doc && e.by === by) return { key: `${path}#opt:${x}`, title: `${r.item.id} · 採用方案 ${x}` };
         }
       }
@@ -666,7 +671,7 @@ class RoadmapView extends ItemView {
   }
 
   lazyThumb(box, slot, find, maxHeight, on = {}) {
-    const hit = this.docs.get(this.chosen.get(slot));
+    const hit = this.docs.get(this.chosen.get(slot) || on.presize);   // `presize`: what the card already measured
     if (hit && hit.h) fitBox(box, hit.h, maxHeight);   // a redraw does not collapse to 0 px first
     const job = () => this.drawThumb(box, slot, find, maxHeight, on);
     if (typeof IntersectionObserver === "undefined") { this.enqueue(job); return; }
R024_FIX2_PATCH
````

- [ ] **Step 4: Run the plugin tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 71`, `ℹ pass 71`, `ℹ fail 0`.

  On a machine without a vault, the `the real …` tests (AC-4b, AC-10) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/options.test.js obsidian-roadmap-view/test/view.test.js
git commit -m "fix(roadmap-view): R-024 review 1 — 方案 X 定案 rows, own-heading captions, skip unreadable mockups"
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

Expected: `ℹ tests 71`, `ℹ fail 0`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 and Step 2 counts.
