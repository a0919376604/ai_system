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
  assert.equal(view.docs.get(`${D}/Proposals/mockups/R-3-a-mockup.html`).h, 500);
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
