// R-013 the view, against a scratch vault on disk and the fake obsidian module.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const P = require("./load");
const { Modal } = require("./fake-obsidian");

const MAIN = fs.readFileSync(path.join(__dirname, "..", "main.js"), "utf8");
const NOW = new Date("2026-10-25T12:00:00Z");
const ROADMAP = `## 🔥 Now
- [ ] **R-1** [FEATURE] 待做的事 —— 細節
- [ ] **R-2** [FEATURE · blocked: 等 API 金鑰] 卡住的事
- [x] **R-3** [FEATURE · ✅ 2026-10-20 · main \`abc1234\`] 最近做完的事
    ↳ done when: 畫面上看得到
    ↳ explain: 給人看的一句話。
- [ ] **R-4** 正在審查的事
- [ ] **R-5** 另一件待做
`;
function vault(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "rv-"));
  for (const [p, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true });
    fs.writeFileSync(path.join(root, p), body);
  }
  return root;
}
const D = "10 Projects/demo";
const MOCK = (t) => `<html><head><style>.x{}</style></head><body><div class="panel now">${t}</div></body></html>`;
const FILES = {
  [`${D}/ROADMAP.md`]: ROADMAP,
  [`${D}/Specs/R-3-did-it.md`]: "spec",
  [`${D}/Specs/R-30-other.md`]: "not R-3's",
  [`${D}/Brainstorms/R-3-talk.md`]: "brainstorm",
  [`${D}/Proposals/mockups/R-2-a-mockup.html`]: MOCK("兩"),
  [`${D}/Proposals/mockups/R-3-a-mockup.html`]: MOCK("三"),
  [`${D}/Proposals/mockups/R-4-a-mockup.html`]: MOCK("四"),
  [`${D}/ship-status/R-4.json`]: JSON.stringify({ id: "R-4", phase: "review", updated: "2026-10-25T09:00:00Z" }),
  [`${D}/ship-status/R-9.json`]: "{ half-synced",
  "10 Projects/other/ROADMAP.md": "- [ ] **R-77** 別的專案\n",
  "10 Projects/no-roadmap/README.md": "x",
};

function fakeApp(root, leaves = []) {
  const walk = (d, pre = "") => fs.readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name), `${pre}${e.name}/`) : [`${pre}${e.name}`]));
  const handlers = {};
  const opened = [];
  const app = {
    handlers, opened, failRead: null,
    vault: {
      getFiles: () => walk(root).map((p) => ({ path: p })),
      getAbstractFileByPath: (p) => (fs.existsSync(path.join(root, p)) ? { path: p } : null),
      on: (ev, f) => { (handlers[ev] = handlers[ev] || []).push(f); return { ev }; },
      adapter: {
        read: async (p) => {
          if (app.failRead && p.endsWith(app.failRead)) throw new Error(`EACCES: ${p}`);
          return fs.readFileSync(path.join(root, p), "utf8");
        },
        list: async (p) => ({ files: fs.readdirSync(path.join(root, p)).map((f) => `${p}/${f}`), folders: [] }),
        stat: async (p) => { try { return { mtime: fs.statSync(path.join(root, p)).mtimeMs }; } catch { return null; } },
      },
    },
    workspace: {
      onLayoutReady: (f) => f(),
      getLeavesOfType: () => leaves,
      openLinkText: (p, src, newLeaf) => opened.push(["link", p, newLeaf]),
      getLeaf: () => ({ openFile: async (f, st) => opened.push(["file", f.path, st]) }),
    },
  };
  return app;
}

async function setup(files = FILES, settings = null) {
  const app = fakeApp(vault(files));
  const plugin = new P(app, { id: "roadmap-view" });
  plugin.stored = settings;
  plugin.now = () => NOW;
  await plugin.onload();
  const leaf = { app };
  const view = plugin.views["roadmap-view"](leaf);
  await view.onOpen();
  return { app, plugin, view };
}
const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
const ids = (el) => el.findAll((e) => e.hasClass("rv-id")).map((e) => e.text);
const byText = (el, t) => el.findAll((e) => e.text === t)[0];

let observed = [];
global.IntersectionObserver = class {
  constructor(cb, opts) { this.cb = cb; this.opts = opts; }
  observe(el) { observed.push({ el, io: this }); }
  unobserve() {}
  disconnect() {}
};
const seen = (o) => o.io.cb([{ isIntersecting: true, target: o.el }]);

test("main.js needs nothing but the obsidian module — the phone has no Node APIs", () => {
  const reqs = [...MAIN.matchAll(/require\(\s*["']([^"']+)["']\s*\)/g)].map((m) => m[1]);
  assert.deepEqual(reqs, ["obsidian"]);
  const man = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"));
  assert.equal(man.id, "roadmap-view");
  assert.equal(man.isDesktopOnly, false);
  assert.equal(man.name, "Roadmap 檢視");
  assert.ok(fs.statSync(path.join(__dirname, "..", "styles.css")).size > 0);
});

test("onload registers the view, a ribbon icon and 打開 Roadmap 檢視, with default settings", async () => {
  const { plugin } = await setup();
  assert.ok(plugin.views["roadmap-view"]);
  assert.equal(plugin.ribbons.length, 1);
  assert.deepEqual(plugin.commands.map((c) => c.name), ["打開 Roadmap 檢視"]);
  assert.deepEqual(plugin.settings, { projectsDir: "10 Projects", recentDays: 14, project: "" });
  assert.deepEqual(plugin.events.map((e) => e.ev).sort(), ["create", "delete", "modify", "rename"]);
});

test("the view never has its own `open` field — it would shadow View.open and blank the pane", async () => {
  const { view } = await setup();
  view.contentEl.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
  await flush();
  assert.equal(Object.prototype.hasOwnProperty.call(view, "open"), false);
  assert.equal(view.open(), "View.open");
});

test("近況: 進行中／卡住, then 最近完成, then 待做 collapsed until tapped", async () => {
  const { view } = await setup();
  const root = view.contentEl;
  const groups = root.findAll((e) => e.hasClass("rv-group")).map((e) => e.text);
  assert.match(groups[0], /^進行中／卡住 · 2/);
  assert.match(groups[1], /^最近完成.* · 1/);
  assert.match(groups[2], /^待做 · 2/);
  assert.deepEqual(ids(root), ["R-2", "R-4", "R-3"]);
  assert.ok(root.textContent.includes("審查中"));
  root.findAll((e) => e.hasClass("rv-group"))[2].fire("click");
  await flush();
  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3", "R-1", "R-5"]);
});

test("the project picker lists folders holding a ROADMAP.md and remembers the pick", async () => {
  const { view, plugin } = await setup();
  const sel = view.contentEl.findAll((e) => e.tag === "select")[0];
  assert.deepEqual(sel.children.map((o) => o.value), ["demo", "other"]);
  assert.equal(sel.value, "demo");
  sel.value = "other";
  sel.fire("change");
  await flush();
  assert.equal(plugin.stored.project, "other");
  assert.equal(plugin.current, "10 Projects/other");
  view.contentEl.findAll((e) => e.text === "全部")[0].fire("click");
  await flush();
  assert.deepEqual(ids(view.contentEl), ["R-77"]);
});

test("全部 lists every item, and search filters by id, headline and explain", async () => {
  const { view } = await setup();
  byText(view.contentEl, "全部").fire("click");
  await flush();
  assert.deepEqual(ids(view.contentEl), ["R-1", "R-2", "R-3", "R-4", "R-5"]);
  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
  input.value = "給人看";
  input.fire("input");
  await new Promise((r) => setTimeout(r, 250));
  assert.deepEqual(ids(view.contentEl), ["R-3"]);
});

test("a card opens its detail page: spec, brainstorm and mockup links, commit, folds; back returns", async () => {
  const { view, app } = await setup();
  const card = view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3"));
  card.fire("click");
  await flush();
  const root = view.contentEl;
  const links = root.findAll((e) => e.hasClass("rv-link")).map((e) => e.text);
  assert.deepEqual(links, ["spec · Specs/R-3-did-it.md", "brainstorm · Brainstorms/R-3-talk.md",
    "mockup · Proposals/mockups/R-3-a-mockup.html", "commit abc1234", "在 ROADMAP.md 打開這一行"]);
  assert.ok(root.textContent.includes("給人看的一句話。"));
  const folds = root.findAll((e) => e.tag === "summary").map((e) => e.text);
  assert.deepEqual(folds, ["完成條件", "給 AI 的原文"]);
  byText(root, "spec · Specs/R-3-did-it.md").fire("click");
  assert.deepEqual(app.opened.at(-1), ["link", `${D}/Specs/R-3-did-it.md`, true]);
  byText(root, "在 ROADMAP.md 打開這一行").fire("click");
  await flush();
  assert.deepEqual(app.opened.at(-1), ["file", `${D}/ROADMAP.md`, { eState: { line: 3 } }]);
  byText(root, "← 返回").fire("click");
  await flush();
  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3"]);
});

test("an item with no explain says so faintly", async () => {
  const { view } = await setup();
  view.contentEl.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
  await flush();
  assert.ok(view.contentEl.textContent.includes("還沒有白話說明"));
});

test("a failed read shows the error in the pane, never a blank pane", async () => {
  const { view, app } = await setup();
  app.failRead = "ROADMAP.md";
  await view.render();
  const t = view.contentEl.textContent;
  assert.ok(t.includes("出錯了") && t.includes("EACCES"), t);
});

test("no project folder with a ROADMAP.md says so", async () => {
  const { view } = await setup({ "10 Projects/x/README.md": "x" });
  assert.ok(view.contentEl.textContent.includes("沒有含 ROADMAP.md 的專案"));
});

test("thumbnails are lazy, at most 2 render at once, sandboxed with no scripts", async () => {
  observed = [];
  const { view } = await setup();
  assert.equal(observed.length, 3);
  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 0);
  observed.forEach(seen);
  await flush();
  let frames = view.contentEl.findAll((e) => e.tag === "iframe");
  assert.equal(frames.length, 2);
  assert.equal(frames[0].attrs.sandbox, "allow-same-origin");
  assert.ok(frames[0].attrs.srcdoc.includes('<div class="panel now">兩</div>'));
  assert.equal(frames[0].style.pointerEvents, "none");
  frames[0].contentDocument = { body: { scrollHeight: 400 } };
  frames[0].fire("load");
  await flush();
  frames = view.contentEl.findAll((e) => e.tag === "iframe");
  assert.equal(frames.length, 3);
  assert.equal(frames[0].style.height, "400px");
});

test("tapping a thumbnail zooms at 符合寬度 / 2× / 3× and does not open the card", async () => {
  observed = [];
  Modal.opened = [];
  const { view } = await setup();
  observed.forEach(seen);
  await flush();
  const box = view.contentEl.findAll((e) => e.hasClass("rv-thumb"))[0];
  box.fire("click");
  assert.equal(view.detail, null);
  assert.equal(Modal.opened.length, 1);
  const bar = Modal.opened[0].contentEl.findAll((e) => e.tag === "button").map((b) => b.text);
  assert.deepEqual(bar, ["符合寬度", "2×", "3×"]);
  assert.equal(Modal.opened[0].contentEl.findAll((e) => e.tag === "iframe").length, 1);
});

test("the 現況 is read once per mockup version", async () => {
  observed = [];
  const { view, app } = await setup();
  let reads = 0;
  const read = app.vault.adapter.read;
  app.vault.adapter.read = async (p) => { if (p.endsWith(".html")) reads++; return read(p); };
  observed.forEach(seen);
  await flush();
  view.contentEl.findAll((e) => e.tag === "iframe").forEach((f) => f.fire("load"));
  await flush();
  const first = reads;
  observed = [];
  await view.render();
  observed.forEach(seen);
  await flush();
  assert.equal(first, 3);
  assert.equal(reads, 3);
});

test("vault changes under the project re-render once, debounced 500 ms; other paths do not", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { plugin, app } = await setup();
  let n = 0;
  plugin.refresh = () => { n++; };
  const fire = (ev, p, old) => app.handlers[ev].forEach((f) => f({ path: p }, old));
  fire("modify", `${D}/ROADMAP.md`);
  fire("create", `${D}/ship-status/R-4.json`);
  fire("rename", "elsewhere.md", `${D}/Specs/R-3-did-it.md`);
  fire("modify", `${D}/notes.md`);
  fire("modify", "10 Projects/other/ROADMAP.md");
  t.mock.timers.tick(499);
  assert.equal(n, 0);
  t.mock.timers.tick(1);
  assert.equal(n, 1);
  fire("modify", `${D}/notes.md`);
  fire("delete", `${D}/Proposals/mockup.html`);
  t.mock.timers.tick(600);
  assert.equal(n, 1);
  fire("delete", `${D}/Proposals/mockups/R-2-a-mockup.html`);
  t.mock.timers.tick(500);
  assert.equal(n, 2);
});

test("after a re-render, the old render's thumbnails neither hold nor add slots", async () => {
  observed = [];
  const { view } = await setup();
  observed.forEach(seen);
  await flush();
  const old = view.contentEl.findAll((e) => e.tag === "iframe");
  assert.equal(old.length, 2);
  observed = [];
  await view.render();   // the two old iframes are gone from the pane, still loading
  observed.forEach(seen);
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
  old.forEach((f) => f.fire("load"));   // finishing late must not let a third one start
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
});

// --- R-013 review attempt 1 -------------------------------------------------------

test("a re-render keeps the reader's place; the detail page opens at the top; back returns", async () => {
  const { view } = await setup();
  const root = view.contentEl;
  root.scrollTop = 600;
  await view.render();                       // a live refresh
  assert.equal(root.scrollTop, 600);
  root.findAll((e) => e.hasClass("rv-group"))[2].fire("click");   // expand 待做
  await flush();
  assert.equal(root.scrollTop, 600);
  root.findAll((e) => e.hasClass("rv-card"))[0].fire("click");
  await flush();
  assert.equal(root.scrollTop, 0);
  byText(root, "← 返回").fire("click");
  await flush();
  assert.equal(root.scrollTop, 600);
  byText(root, "全部").fire("click");
  await flush();
  assert.equal(root.scrollTop, 0);
});

test("two quick taps on 待做, before it redraws, still leave it open", async () => {
  const { view } = await setup();
  const h = () => view.contentEl.findAll((e) => e.hasClass("rv-group"))[2];
  h().fire("click");
  h().fire("click");
  await flush();
  assert.equal(view.todoExpanded, true);
  assert.deepEqual(ids(view.contentEl), ["R-2", "R-4", "R-3", "R-1", "R-5"]);
});

test("a refresh on the detail page keeps open folds and the 現況's height", async () => {
  observed = [];
  const { view } = await setup();
  const card = view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3"));
  card.fire("click");
  await flush();
  const fold = () => view.contentEl.findAll((e) => e.tag === "details")[1];
  fold().open = true;
  fold().fire("toggle");
  const big = () => view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
  observed.filter((o) => o.el === big()).forEach(seen);
  await flush();
  const frame = big().findAll((e) => e.tag === "iframe")[0];
  frame.contentDocument = { body: { scrollHeight: 400 } };
  frame.fire("load");
  await flush();
  const height = big().style.height;
  assert.ok(height && height !== "0px", height);
  observed = [];
  await view.render();
  assert.equal(fold().open, true);
  assert.equal(big().style.height, height);
  byText(view.contentEl, "← 返回").fire("click");
  await flush();
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
  await flush();
  assert.equal(fold().open, false);   // another visit starts closed
});

test("the detail page's big 現況 waits until it is in view", async () => {
  observed = [];
  const { view } = await setup();
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
  await flush();
  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
  assert.equal(big.findAll((e) => e.tag === "iframe").length, 0);
  assert.ok(observed.some((o) => o.el === big));
  assert.equal(observed[0].io.opts.root, view.contentEl);
});

test("the iframe is sandboxed before it is inserted", async () => {
  observed = [];
  const { view } = await setup();
  observed.forEach(seen);
  await flush();
  const f = view.contentEl.findAll((e) => e.tag === "iframe")[0];
  assert.equal(f.initialAttrs.sandbox, "allow-same-origin");
  assert.ok(f.initialAttrs.srcdoc.includes("panel now"));
});

test("a refresh waits while the search box has focus", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { view, plugin, app } = await setup();
  const leaves = [{ view }];
  app.workspace.getLeavesOfType = () => leaves;
  byText(view.contentEl, "全部").fire("click");
  await flush();
  let n = 0;
  view.render = async () => { n++; };
  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
  view.contentEl.ownerDocument = { activeElement: input, hasFocus: () => true };
  plugin.refresh();
  assert.equal(n, 0);
  view.contentEl.ownerDocument = { activeElement: null, hasFocus: () => true };
  t.mock.timers.tick(500);
  assert.equal(n, 1);
});

test("a search typed just before a re-render does not wipe the new screen's thumbnails", async () => {
  observed = [];
  const { view } = await setup();
  byText(view.contentEl, "全部").fire("click");
  await flush();
  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
  input.value = "R-";
  input.fire("input");
  observed = [];
  await view.render();
  await new Promise((r) => setTimeout(r, 250));   // the old search timer would have fired
  observed.forEach(seen);
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.tag === "iframe").length, 2);
});

test("closing the view stops a render in flight from drawing", async () => {
  const { view } = await setup();
  view.contentEl.empty();
  const p = view.render();
  await view.onClose();
  await p;
  assert.equal(view.contentEl.children.length, 0);
});

test("a new project's ROADMAP.md refreshes the picker, even with no project shown", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { plugin, app } = await setup({ "10 Projects/x/README.md": "x" });
  let n = 0;
  plugin.refresh = () => { n++; };
  assert.equal(plugin.current, null);
  app.handlers.create.forEach((f) => f({ path: "10 Projects/new/ROADMAP.md" }));
  app.handlers.create.forEach((f) => f({ path: "10 Projects/new/notes/ROADMAP.md" }));
  t.mock.timers.tick(500);
  assert.equal(n, 1);
});

test("the view overrides none of Obsidian's View lifecycle methods", async () => {
  const { view } = await setup();
  const own = Object.getOwnPropertyNames(Object.getPrototypeOf(view));
  for (const k of ["open", "load", "unload", "close"]) {
    assert.ok(!own.includes(k) && !Object.prototype.hasOwnProperty.call(view, k), k);
  }
});

test("an item's mockups come in name order, whatever order the vault lists them in", async () => {
  const files = { ...FILES, [`${D}/Proposals/mockups/R-2-b-mockup.html`]: MOCK("乙") };
  const app = fakeApp(vault(files));
  const list = app.vault.adapter.list;
  app.vault.adapter.list = async (p) => { const r = await list(p); return { ...r, files: [...r.files].reverse() }; };
  const plugin = new P(app, { id: "roadmap-view" });
  plugin.now = () => NOW;
  await plugin.onload();
  const view = plugin.views["roadmap-view"]({ app });
  await view.onOpen();
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-2")).fire("click");
  await flush();
  const links = view.contentEl.findAll((e) => e.hasClass("rv-link")).map((e) => e.text).filter((t) => t.startsWith("mockup"));
  assert.deepEqual(links, ["mockup · Proposals/mockups/R-2-a-mockup.html", "mockup · Proposals/mockups/R-2-b-mockup.html"]);
});

// --- R-013 review attempt 2 -------------------------------------------------------

test("a hidden pane sizes the big 現況 by its ratio, not by a width it cannot measure", async () => {
  observed = [];
  const { view } = await setup();
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
  await flush();
  const big = () => view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
  big().clientWidth = 550;   // visible: a measurable width
  observed.filter((o) => o.el === big()).forEach(seen);
  await flush();
  const frame = big().findAll((e) => e.tag === "iframe")[0];
  frame.contentDocument = { body: { scrollHeight: 400 } };
  frame.fire("load");
  await flush();
  assert.equal(big().style.height, "200px");
  assert.equal(big().style.aspectRatio, "1100 / 400");
  observed = [];
  await view.render();       // the pane is hidden now: nothing has a width
  assert.equal(big().style.aspectRatio, "1100 / 400");
  assert.equal(big().style.height, "auto");
});

test("the search box holds a refresh only while its window has focus", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });   // a wrong wait would re-arm forever
  const { view, plugin, app } = await setup();
  app.workspace.getLeavesOfType = () => [{ view }];
  byText(view.contentEl, "全部").fire("click");
  await flush();
  let n = 0;
  view.render = async () => { n++; };
  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
  view.contentEl.ownerDocument = { activeElement: input, hasFocus: () => false };
  plugin.refresh();
  assert.equal(n, 1);
});

test("only the leaf whose own search box has focus waits; the others redraw once", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { view: a, plugin, app } = await setup();
  const b = plugin.views["roadmap-view"]({ app });
  await b.onOpen();
  app.workspace.getLeavesOfType = () => [{ view: a }, { view: b }];
  byText(a.contentEl, "全部").fire("click");
  await flush();
  const input = a.contentEl.findAll((e) => e.tag === "input")[0];
  const doc = { activeElement: input, hasFocus: () => true };
  a.contentEl.ownerDocument = doc;
  b.contentEl.ownerDocument = doc;
  let na = 0, nb = 0;
  a.render = async () => { na++; };
  b.render = async () => { nb++; };
  plugin.refresh();
  assert.deepEqual([na, nb], [0, 1]);
  t.mock.timers.tick(500);
  assert.deepEqual([na, nb], [0, 1]);
  doc.activeElement = null;
  t.mock.timers.tick(500);
  assert.deepEqual([na, nb], [1, 1]);
});

test("a 現況 that loads after the 3 s timeout still keeps its height", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  observed = [];
  const { view } = await setup();
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
  await flush();
  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
  observed.filter((o) => o.el === big).forEach(seen);
  await flush();
  t.mock.timers.tick(3000);
  await flush();
  assert.ok(big.hasClass("rv-slow"));
  const frame = big.findAll((e) => e.tag === "iframe")[0];
  frame.contentDocument = { body: { scrollHeight: 500 } };
  frame.fire("load");
  assert.equal(view.docs.get(`${D}/Proposals/mockups/R-3-a-mockup.html#now`).h, 500);
  assert.ok(!big.hasClass("rv-slow"));
});

test("when the open item's row disappears, a refresh goes back to the list where it was", async () => {
  const { view, app } = await setup();
  view.contentEl.scrollTop = 300;
  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-2")).fire("click");
  await flush();
  assert.equal(view.detail, "R-2");
  const read = app.vault.adapter.read;
  app.vault.adapter.read = async (p) => (p.endsWith("ROADMAP.md") ? ROADMAP.replace(/^- \[ \] \*\*R-2\*\*.*\n/m, "") : read(p));
  await view.render();
  assert.equal(view.detail, null);
  assert.equal(byText(view.contentEl, "← 返回"), undefined);
  assert.ok(byText(view.contentEl, "近況").hasClass("is-on"));
  assert.equal(view.contentEl.scrollTop, 300);
});

// --- R-024: 完成條件 as a list; the picked option -------------------------------------

const OPT = (now, b) => `<html><head><style>.y{}</style></head><body><div class="panel now">${now}</div>`
  + `<h2>方案 A · 甲版</h2><div class="panel optA">A 版</div><h2>方案 B · 乙版</h2><div class="panel optB">${b}</div></body></html>`;
const PICKED = {
  ...FILES,
  [`${D}/ROADMAP.md`]: `## 🔥 Now
- [x] **R-6** [FEATURE · mockup 定案 B · ✅ 2026-10-21] 做完的事
    ↳ done when: 畫面上看得到；點得開 · 能放大（含「手機；平板」）
    ↳ done when: 手機也行
- [ ] **R-7** [FEATURE · mockup 定案 B] 還沒做完的事
- [x] **R-8** [FEATURE · mockup 定案 C · ✅ 2026-10-22] 方案找不到的事
`,
  [`${D}/Proposals/mockups/R-6-a-mockup.html`]: OPT("六的現況", "六的方案B"),
  [`${D}/Proposals/mockups/R-7-a-mockup.html`]: OPT("七的現況", "七的方案B"),
  [`${D}/Proposals/mockups/R-8-a-mockup.html`]: OPT("八的現況", "八的方案B"),
};
const cardOf = (view, id) => view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes(id));
const framesIn = (el) => el.findAll((e) => e.tag === "iframe");

test("a done item's card shows the picked option; a not-done or unmatched one shows 現況 (AC-6, AC-8)", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  for (let i = 0; i < 3; i++) { view.contentEl.findAll((e) => e.tag === "iframe").forEach((f) => f.fire("load")); await flush(); }
  const src = (id) => framesIn(cardOf(view, id))[0].attrs.srcdoc;
  assert.ok(src("R-6").includes("六的方案B") && !src("R-6").includes("六的現況"));
  assert.ok(src("R-7").includes("七的現況") && !src("R-7").includes("七的方案B"));
  assert.ok(src("R-8").includes("八的現況"));   // 方案 C is not in its mockup
});

test("the detail page shows 採用方案 X with its caption first, then 現況; both zoom (AC-7)", async () => {
  observed = [];
  Modal.opened = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-6").fire("click");
  await flush();
  const root = view.contentEl;
  const lbls = root.findAll((e) => e.hasClass("rv-lbl")).map((e) => e.text);
  assert.deepEqual(lbls.slice(0, 2), ["採用方案 B", "MOCKUP · 現況"]);
  observed.forEach(seen);
  await flush();
  for (let i = 0; i < 3; i++) { framesIn(root).forEach((f) => f.fire("load")); await flush(); }
  const [opt, now] = root.findAll((e) => e.hasClass("rv-big"));
  assert.ok(framesIn(opt)[0].attrs.srcdoc.includes("六的方案B"));
  assert.ok(framesIn(now)[0].attrs.srcdoc.includes("六的現況"));
  assert.ok(root.findAll((e) => e.hasClass("rv-cap")).some((c) => c.text.startsWith("方案 B · 乙版")));
  const lbl = root.findAll((e) => e.text === "採用方案 B")[0];
  const cap = root.findAll((e) => e.hasClass("rv-cap"))[0];
  assert.notEqual(lbl.style.display, "none");
  assert.notEqual(cap.style.display, "none");
  assert.notEqual(opt.style.visibility, "hidden");
  opt.fire("click");
  now.fire("click");
  assert.deepEqual(Modal.opened.map((m) => m.title), ["R-6 · 採用方案 B", "R-6 · 現況"]);
});

test("a not-done item's detail page still shows the decided option; an unmatched one drops the section (AC-8)", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-7").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.hasClass("rv-lbl"))[0].text, "採用方案 B");
  assert.ok(framesIn(view.contentEl.findAll((e) => e.hasClass("rv-big"))[0])[0].attrs.srcdoc.includes("七的方案B"));
  byText(view.contentEl, "← 返回").fire("click");
  await flush();
  observed = [];
  cardOf(view, "R-8").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  const lbls = view.contentEl.findAll((e) => e.hasClass("rv-lbl")).map((e) => e.text);
  assert.ok(!lbls.includes("採用方案 C"), lbls.join(","));
  assert.equal(view.contentEl.findAll((e) => e.hasClass("rv-big")).length, 1);
});

test("完成條件 is one list of every line's split conditions, in order (AC-9)", async () => {
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-6").fire("click");
  await flush();
  const lists = view.contentEl.findAll((e) => e.tag === "ul" && e.hasClass("rv-dw"));
  assert.equal(lists.length, 1);
  assert.deepEqual(lists[0].children.map((li) => [li.tag, li.text]),
    [["li", "畫面上看得到"], ["li", "點得開"], ["li", "能放大（含「手機；平板」）"], ["li", "手機也行"]]);
});

// --- R-024 review attempt 1 -------------------------------------------------------

const TWO = {
  ...FILES,
  [`${D}/ROADMAP.md`]: `## 🔥 Now
- [x] **R-9** [FEATURE · mockup 定案 B · ✅ 2026-10-21] 兩份 mockup 的事
    ↳ mockup [[Proposals/mockups/second-mockup.html|二號（方案 B）]]
- [x] **R-8** [FEATURE · mockup 定案 C · ✅ 2026-10-22] 方案找不到的事
`,
  // the item's own file comes first and has an unlabelled optB; the labelled 方案 B is in the second
  [`${D}/Proposals/mockups/R-9-a-mockup.html`]: `<html><body><div class="panel now">九的現況</div><div class="panel optB">一號的B</div></body></html>`,
  [`${D}/Proposals/mockups/second-mockup.html`]: OPT("二號的現況", "二號的方案B"),
  [`${D}/Proposals/mockups/R-8-a-mockup.html`]: OPT("八的現況", "八的方案B"),
};

test("a label match in any of the item's mockups beats a class match in an earlier one", async () => {
  observed = [];
  const { view } = await setup(TWO);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  assert.ok(framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc.includes("二號的方案B"));
});

test("a refresh draws the 採用方案 caption from the cache, so nothing below it moves", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-6").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  observed = [];
  await view.render();   // nothing seen yet in this render
  const caps = view.contentEl.findAll((e) => e.hasClass("rv-cap")).map((c) => c.text);
  assert.equal(caps[0], "方案 B · 乙版 · 點圖放大");
});

test("an option that is not found shows no 採用方案 label while it is looked for", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-8").fire("click");
  await flush();
  const lbl = view.contentEl.findAll((e) => e.text === "採用方案 C")[0];
  assert.equal(lbl.style.display, "none");
  observed.forEach(seen);
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.text === "採用方案 C").length, 0);
});

test("a mockup that cannot be read is skipped: card and detail page use what can be found", async () => {
  observed = [];
  const { view, app } = await setup(TWO);
  app.failRead = "second-mockup.html";   // half-synced on the phone
  byText(view.contentEl, "全部").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  assert.ok(framesIn(cardOf(view, "R-9"))[0].attrs.srcdoc.includes("一號的B"));
  observed = [];
  cardOf(view, "R-9").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  assert.ok(framesIn(view.contentEl.findAll((e) => e.hasClass("rv-big"))[0])[0].attrs.srcdoc.includes("一號的B"));
});

test("the detail page's images start at the height the card already measured", async () => {
  observed = [];
  const { view } = await setup();
  const card = cardOf(view, "R-3");
  observed.filter((o) => card.contains(o.el)).forEach(seen);
  await flush();
  const f = framesIn(card)[0];
  f.contentDocument = { body: { scrollHeight: 400 } };
  f.fire("load");
  await flush();
  observed = [];
  card.fire("click");
  await flush();
  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
  assert.equal(framesIn(big).length, 0);              // not drawn yet
  assert.equal(big.style.aspectRatio, "1100 / 400");  // but already sized
});

test("a thumbnail's remembered size belongs to its project, not to an id another project reuses", async () => {
  observed = [];
  const files = { ...FILES, "10 Projects/other/ROADMAP.md": "- [x] **R-3** 別的專案的 R-3 · ✅ 2026-10-20\n",
    "10 Projects/other/Proposals/mockups/R-3-a-mockup.html": MOCK("別的") };
  const { view, plugin } = await setup(files);
  const card = cardOf(view, "R-3");
  observed.filter((o) => card.contains(o.el)).forEach(seen);
  await flush();
  const f = framesIn(card)[0];
  f.contentDocument = { body: { scrollHeight: 400 } };
  f.fire("load");
  await flush();
  plugin.settings.project = "other";
  observed = [];
  await view.render();
  byText(view.contentEl, "全部").fire("click");
  await flush();
  assert.equal(cardOf(view, "R-3").findAll((e) => e.hasClass("rv-thumb"))[0].style.aspectRatio, undefined);
});

// --- R-024 review attempt 2 -------------------------------------------------------

test("a detail page opened from a drawn card starts with the option's size, caption and label", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  const card = cardOf(view, "R-6");
  observed.filter((o) => card.contains(o.el)).forEach(seen);
  await flush();
  const f = framesIn(card)[0];
  f.contentDocument = { body: { scrollHeight: 300 } };
  f.fire("load");
  await flush();
  observed = [];
  card.fire("click");
  await flush();
  const root = view.contentEl;
  const opt = root.findAll((e) => e.hasClass("rv-big"))[0];
  assert.equal(framesIn(opt).length, 0);                 // no job has run yet
  assert.equal(opt.style.aspectRatio, "1100 / 300");
  assert.equal(root.findAll((e) => e.hasClass("rv-cap"))[0].text, "方案 B · 乙版 · 點圖放大");
  assert.notEqual(root.findAll((e) => e.text === "採用方案 B")[0].style.display, "none");
});

test("while an option is looked for, its empty box is invisible too", async () => {
  observed = [];
  const { view } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-8").fire("click");
  await flush();
  assert.equal(view.contentEl.findAll((e) => e.hasClass("rv-big"))[0].style.visibility, "hidden");
});

test("a caption cached for another option, or for one without a heading, is not reused", async () => {
  observed = [];
  const { view, app } = await setup(PICKED);
  byText(view.contentEl, "全部").fire("click");
  await flush();
  cardOf(view, "R-6").fire("click");
  await flush();
  observed.forEach(seen);
  await flush();
  // R-6 is now 定案 A, whose panel has a heading; then a heading-less C
  const read = app.vault.adapter.read;
  let picked = "A";
  app.vault.adapter.read = async (p) => (p.endsWith("ROADMAP.md")
    ? (await read(p)).replace("mockup 定案 B", `mockup 定案 ${picked}`) : read(p));
  observed = [];
  await view.render();
  const caps = () => view.contentEl.findAll((e) => e.hasClass("rv-cap")).map((c) => c.text);
  assert.ok(!caps().some((c) => c.startsWith("方案 B")), caps().join(" | "));
  observed.forEach(seen);
  await flush();
  assert.equal(caps()[0], "方案 A · 甲版 · 點圖放大");
});
