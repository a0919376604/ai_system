// Roadmap 檢視 (R-013) — a live, read-only, phone-first view of one project's ROADMAP.
// ROADMAP.md stays written for AI; this picks what a person needs and shows it.
// Plain CommonJS, no build: Obsidian loads this one file. The pure functions are static
// members of the plugin class so `node --test test/` can reach them.
const { Plugin, ItemView, Modal, Notice } = require("obsidian");

// ---------------------------------------------------------------- parsing (pure)

// A ROADMAP item row. Real rows seen 2026-10-25: `**R-001 (epic)**`, `**R-193.3a-2.1**`,
// `~~**R-093** …~~`, `⚠️ **R-300** (epic)`, and `- [~]` for work in progress.
const ROW = /^(\s*)- \[( |x|X|~)\] (⚠️ )?(~~)?\*\*(R-\d[\w.-]*)((?: \([^)*]*\))?)\*\*( \(epic\))?/;

// Index of the `]` closing the `[` at s[0], counting nested brackets; -1 if unbalanced.
function closeBracket(s) {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "[") depth++;
    else if (s[i] === "]" && --depth === 0) return i;
  }
  return -1;
}

// The option a row says was picked: `mockup 定案 X` or `方案 X 定案` on the row, else the first `方案 X` on a
// `↳` line that mentions a mockup (never done-when text, where 方案 can mean anything).
const OPTION = "([A-Z]|[甲乙丙丁])(?![A-Za-z])";
function pickedOf(row, ann) {
  const own = row.match(new RegExp(`mockup 定案\\s*${OPTION}`)) || row.match(new RegExp(`方案\\s*${OPTION}\\s*定案`));
  if (own) return own[1];
  for (const a of ann) {
    if (!/mockup/i.test(a) || a.startsWith("↳ done when:")) continue;
    const m = a.match(new RegExp(`方案\\s*${OPTION}`));
    if (m) return m[1];
  }
  return null;
}

// 完成條件 as a list: split at `；`, `;` and ` · ` outside brackets, quotes and backticks.
const OPENS = "（(「『[【", CLOSES = "）)」』]】";
function splitConditions(text) {
  const s = String(text || "");
  const out = [];
  const stack = [];
  let cur = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    const top = stack[stack.length - 1];
    if (top === "`") { if (c === "`") stack.pop(); cur += c; continue; }
    if (c === "`") { stack.push("`"); cur += c; continue; }
    const o = OPENS.indexOf(c);
    if (o >= 0) { stack.push(CLOSES[o]); cur += c; continue; }
    if (c === top) { stack.pop(); cur += c; continue; }
    if (!stack.length && (c === "；" || c === ";")) { out.push(cur); cur = ""; continue; }
    if (!stack.length && s.startsWith(" · ", i)) { out.push(cur); cur = ""; i += 2; continue; }
    cur += c;
  }
  out.push(cur);
  return out.map((x) => x.trim()).filter(Boolean);
}

function itemFrom(row, m, ann, section, line) {
  const rest = row.slice(m[0].length).trim();
  let tags = "";
  let body = rest;
  if (rest.startsWith("[") && !rest.startsWith("[[")) {
    const end = closeBracket(rest);
    if (end > 0) { tags = rest.slice(1, end); body = rest.slice(end + 1).trim(); }
  }
  let headline = body.split(/\s*——|\*\*來源/)[0].replace(/~~/g, "")
    // trailing annotations written by ship-workflow: ` · ✅ …` to the end, then ` · status=…` / ` · mr=…`
    .replace(/\s*·\s*✅.*$/, "")
    .replace(/(\s*·\s*[a-z][\w-]*=\S*)+\s*$/, "").trim();
  if (!headline) headline = body.replace(/^[\s—]+/, "").slice(0, 120);
  const explainLine = ann.find((a) => a.startsWith("↳ explain:"));
  const explain = explainLine ? explainLine.replace(/^↳ explain:\s*/, "").trim() : null;
  const pick = (re) => { const x = row.match(re); return x ? x[1].trim() : null; };
  const mrUrl = row.match(/mr=\S*?\/(\d+)\/?(?=\s|$)/);
  const mrBang = row.match(/(?:^|[^\w&])!(\d+)\b/);
  const refs = [];
  for (const r of [row, ...ann].join("\n").match(/Proposals\/mockups\/[^`\s)|\]]+?\.html/g) || []) {
    if (!refs.includes(r)) refs.push(r);
  }
  const undeployed = row.match(/尚未部署\s*([A-Za-z][\w／/-]*)?/);
  return {
    id: m[5],
    checked: m[2] === "x" || m[2] === "X",
    inProgress: m[2] === "~",
    section,
    line,
    tags,
    headline,
    raw: row,
    ann,
    doneWhen: ann.filter((a) => a.startsWith("↳ done when:")).map((a) => a.replace(/^↳ done when:\s*/, "").trim()),
    explain: explain && !/^mockup\b/i.test(explain) ? explain : null,
    refs,
    sameAsAbove: ann.some((a) => /mockup 同上/.test(a)),
    done: pick(/✅[^\d\n]{0,40}?(\d{4}-\d{2}-\d{2})/),
    undeployed: undeployed ? (undeployed[1] || "") : null,
    blocked: pick(/blocked:\s*([^·\]\n]*[^·\]\n\s])/),
    needsBrainstorm: /needs-brainstorm/.test(row),
    picked: pickedOf(row, ann),
    inReview: /status=in-review/.test(row),
    epic: /epic/i.test(m[6]) || !!m[7] || /^EPIC\b/.test(tags),
    commit: pick(/`([0-9a-f]{7,10})`/),
    mr: mrUrl ? `!${mrUrl[1]}` : mrBang ? `!${mrBang[1]}` : null,
  };
}

function parseRoadmap(md) {
  const lines = String(md || "").split("\n");
  const items = [];
  let section = "";
  for (let i = 0; i < lines.length; i++) {
    if (/^## /.test(lines[i])) { section = lines[i].slice(3).trim(); continue; }
    const m = lines[i].match(ROW);
    if (!m) continue;
    const ann = [];
    for (let j = i + 1; j < lines.length && /^\s+↳/.test(lines[j]); j++) ann.push(lines[j].trim());
    items.push(itemFrom(lines[i], m, ann, section, i));
  }
  return items;
}

// R-094.3 vs R-094.2: compare dot-separated parts, numerically where both are numbers.
function compareIds(a, b) {
  const pa = a.slice(2).split("."), pb = b.slice(2).split(".");
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if (pa[i] === undefined) return -1;
    if (pb[i] === undefined) return 1;
    const na = parseInt(pa[i], 10), nb = parseInt(pb[i], 10);
    if (na !== nb && !isNaN(na) && !isNaN(nb)) return na - nb;
    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

// `files`: mockup paths relative to the project dir ("Proposals/mockups/x.html").
function mockupsFor(item, items, files) {
  const own = (it) => [
    ...(files || []).filter((f) => /\.html$/i.test(f) && f.split("/").pop().startsWith(`${it.id}-`)),
    ...(it.refs || []),
  ];
  const out = [];
  for (const f of own(item)) if (!out.includes(f)) out.push(f);
  if (item.sameAsAbove) {
    const base = item.id.split(".")[0];
    const sibs = items.filter((o) => o.id !== item.id && o.id.split(".")[0] === base && own(o).length)
      .sort((a, b) => compareIds(a.id, b.id));
    // "同上" means the one written above it: the closest smaller id, else the closest larger.
    const before = sibs.filter((o) => compareIds(o.id, item.id) < 0).pop();
    const after = sibs.find((o) => compareIds(o.id, item.id) > 0);
    for (const f of own(before || after || { refs: [] })) if (!out.includes(f)) out.push(f);
  }
  return out;
}

const PHASE_TEXT = {
  brainstorm: "討論中", plan: "寫計畫", build: "實作中", review: "審查中",
  landing: "合併中", "in-review": "等 MR 合併", done: "完成", blocked: "卡住",
};
const monthDay = (d) => `${d.getMonth() + 1}/${d.getDate()}`;

// `phaseFile`: the parsed ship-status/<id>.json, or null. A ROADMAP date counts as the end
// of that day, so on the same day the row's own tags win.
function statusOf(item, phaseFile, now = new Date(), recentDays = 14) {
  const pf = phaseFile && PHASE_TEXT[phaseFile.phase] ? phaseFile : null;
  const pfAt = pf ? Date.parse(pf.updated) : NaN;
  const tagAt = item.done ? Date.parse(`${item.done}T23:59:59`) : NaN;
  const usePhase = !!pf && (isNaN(pfAt) ? !item.checked && !item.done : !(tagAt >= pfAt));
  const phase = usePhase ? pf.phase : null;
  let doneAt = null;
  let isDone = false;
  if (phase === "done") { isDone = true; doneAt = isNaN(pfAt) ? null : new Date(pfAt); }
  else if (!phase && (item.done || item.checked)) {
    isDone = true;
    doneAt = item.done ? new Date(`${item.done}T00:00:00`) : null;
  }
  const chips = [];
  if (phase && phase !== "done") {
    chips.push(phase === "blocked"
      ? { kind: "blocked", text: pf.note ? `卡住：${pf.note}` : "卡住" }
      : { kind: "phase", text: PHASE_TEXT[phase] });
  }
  if (isDone) chips.push({ kind: "done", text: doneAt ? `完成 ${monthDay(doneAt)}` : "完成" });
  if (item.blocked) chips.push({ kind: "blocked", text: `卡住：${item.blocked}` });
  if (item.undeployed !== null && item.undeployed !== undefined) {
    chips.push({ kind: "wait", text: `尚未部署${item.undeployed ? ` ${item.undeployed}` : ""}` });
  }
  if (item.inReview && !phase) chips.push({ kind: "phase", text: PHASE_TEXT["in-review"] });
  if (item.inProgress && !phase && !isDone) chips.push({ kind: "phase", text: "進行中" });
  if (item.needsBrainstorm) chips.push({ kind: "wait", text: "待討論" });
  if (item.picked) chips.push({ kind: "pick", text: `方案 ${item.picked}` });
  if (item.epic) chips.push({ kind: "epic", text: "epic" });
  let group;
  if ((phase && phase !== "done") || item.blocked || ((item.inReview || item.inProgress) && !isDone)) group = "active";
  else if (isDone) group = doneAt && now - doneAt <= recentDays * 864e5 ? "recent" : "done";
  else group = "todo";
  return { group, chips, phase };
}

// ---------------------------------------------------------------- 現況 extraction (pure)

const classesOf = (attrs) => {
  const m = attrs.match(/\bclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
  return m ? (m[1] ?? m[2] ?? m[3]).split(/\s+/) : [];
};

// From the opening tag at `start`, the index just past its balanced close; -1 if unclosed.
function elementEnd(scan, start, name) {
  const re = new RegExp(`<(/?)${name}\\b[^>]*?(/?)>`, "gi");
  re.lastIndex = start;
  let depth = 0;
  for (let m; (m = re.exec(scan));) {
    if (m[1]) depth--;
    else if (!m[2]) depth++;
    if (depth === 0) return re.lastIndex;
  }
  return -1;
}

// The mockup's styles, a copy with style/script bodies blanked (same length, so a `<div`
// inside them is not counted), and every `.panel` element with its extent.
function panelsOf(html) {
  const styles = (html.match(/<style\b[^>]*>[\s\S]*?<\/style>/gi) || []).join("\n");
  const scan = html.replace(/<(style|script)\b[\s\S]*?<\/\1>/gi, (s) => " ".repeat(s.length));
  const panels = [];
  for (const m of scan.matchAll(/<([a-zA-Z][\w-]*)\b([^>]*)>/g)) {
    const cls = classesOf(m[2]);
    if (cls.includes("panel")) panels.push({ at: m.index, name: m[1], cls, end: elementEnd(scan, m.index, m[1]) });
  }
  // An option, 現況 or facts panel whose markup never closes ends where the next one starts
  // (they are siblings); otherwise its headings would be read as the next panel's.
  const top = (p) => p.cls.some((c) => /^opt/.test(c) || c === "now" || c === "facts");
  panels.forEach((p, i) => {
    if (p.end > 0 || !top(p)) return;
    const next = panels.slice(i + 1).find(top);
    if (next) p.end = next.at;
  });
  return { styles, scan, panels };
}

// One element of the mockup as a document of its own, with every style and no script.
function wrapDoc(styles, el) {
  return `<!DOCTYPE html><html><head><meta charset="utf-8">${styles}
<style>html,body{margin:0;background:#fff;overflow:hidden}body{padding:12px}.panel{margin:0!important}</style>
</head><body>${el.replace(/<script\b[\s\S]*?<\/script>/gi, "")}</body></html>`;
}

// A string scanner, not DOMParser: testable under node and the same on every platform.
function currentStateDoc(html) {
  if (typeof html !== "string" || !html) return null;
  const { styles, panels } = panelsOf(html);
  const pick = panels.find((t) => t.cls.includes("now")) || panels.find((t) => !t.cls.includes("facts"));
  let el = pick && pick.end > 0 ? html.slice(pick.at, pick.end) : null;
  if (!el) {
    const b = html.match(/<body\b[^>]*>([\s\S]*)<\/body>/i);
    el = b && b[1].trim() ? b[1] : null;
  }
  return el ? wrapDoc(styles, el) : null;
}

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " " };
const textOf = (h) => h.replace(/<[^>]+>/g, " ").replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) => ENTITIES[e])
  .replace(/\s+/g, " ").trim();

// The picked option's panel: the first `opt*` panel with a heading — right before it, or its
// own first — that starts with 方案/版面 X (after an optional "4 · "); else class `opt<X>`.
// A heading that only mentions 方案 X mid-sentence does not count.
function optionDoc(html, picked) {
  if (typeof html !== "string" || !html || !picked) return null;
  const { styles, scan, panels } = panelsOf(html);
  const heads = [...scan.matchAll(/<h([1-4])\b[^>]*>([\s\S]*?)<\/h\1>/gi)].map((m) => ({ at: m.index, text: m[2] }));
  const opts = panels.filter((p) => p.end > 0 && p.cls.some((c) => /^opt/.test(c))).map((p) => {
    const inside = heads.find((h) => h.at > p.at && h.at < p.end);
    const floor = Math.max(0, ...panels.filter((q) => q.end > 0 && q.end <= p.at).map((q) => q.end));
    const before = heads.filter((h) => h.at >= floor && h.at < p.at).pop();
    return { ...p, labels: [before, inside].filter(Boolean).map((h) => textOf(h.text).slice(0, 80)) };
  });
  const named = new RegExp(`^(\\d+\\s*[·.、:：]\\s*)?(方案|版面)\\s*${picked}(?![A-Za-z])`);
  let label = "";
  let by = "label";
  let hit = opts.find((o) => (label = o.labels.find((l) => named.test(l)) || "") !== "");
  if (!hit && /^[A-Z]$/.test(picked)) {
    by = "class";
    hit = opts.find((o) => o.cls.includes(`opt${picked}`));
    label = hit ? hit.labels[hit.labels.length - 1] || "" : "";   // its own heading, else the one before it
  }
  return hit ? { doc: wrapDoc(styles, html.slice(hit.at, hit.end)), label, by } : null;
}

// ---------------------------------------------------------------- rendering

const VIEW = "roadmap-view";
const DEFAULTS = { projectsDir: "10 Projects", recentDays: 14, project: "" };
const WATCHED = ["ROADMAP.md", "Proposals/mockups/", "Specs/", "Brainstorms/", "ship-status/"];
const W = 1100;          // mockups are laid out at desktop width, then scaled down
const MAX_THUMBS = 2;    // thumbnails rendering at once

function isWatched(path, projectDir) {
  if (!path || !projectDir || !path.startsWith(`${projectDir}/`)) return false;
  const rel = path.slice(projectDir.length + 1);
  return WATCHED.some((w) => (w.endsWith("/") ? rel.startsWith(w) : rel === w));
}

// An iframe showing `srcdoc` at width W, scaled by `scale`. No scripts run in it; it is
// same-origin only so its height can be read. It ignores touches, so its box scrolls.
function frameIn(box, srcdoc, scale, onHeight) {
  // Set before the frame is inserted, so even its first document is sandboxed.
  const frame = box.createEl("iframe", { attr: { sandbox: "allow-same-origin", scrolling: "no", srcdoc } });
  Object.assign(frame.style, { width: `${W}px`, height: "800px", border: "0", transformOrigin: "0 0",
    transform: `scale(${scale})`, pointerEvents: "none", background: "#fff" });
  frame.addEventListener("load", () => {
    let h = 800;
    try { h = frame.contentDocument.body.scrollHeight || h; } catch (e) { /* unreadable: keep 800 */ }
    frame.style.height = `${h}px`;
    onHeight(h);
  });
  return frame;
}

const scaleOf = (box) => (box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 300) / W;

// Size `box` for a document `h` px tall at width W. The ratio stays right in a hidden pane
// (nothing to measure); a pixel height is set only when the width is known.
function fitBox(box, h, maxHeight) {
  box.style.aspectRatio = `${W} / ${h}`;
  const w = box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 0;
  if (!w) {
    box.style.height = "auto";
    if (maxHeight) box.style.maxHeight = `${maxHeight}px`;
    return;
  }
  const px = (h * w) / W;
  box.style.height = `${maxHeight ? Math.min(px, maxHeight) : px}px`;
}

// Resolves with the document's height once drawn, or 0 when it has not loaded within
// 3 s (the box is marked until it does). `onHeight` also hears a load after the timeout.
function thumb(box, srcdoc, maxHeight, onHeight) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { box.addClass("rv-slow"); resolve(0); }, 3000);
    frameIn(box, srcdoc, scaleOf(box), (h) => {
      fitBox(box, h, maxHeight);
      box.removeClass("rv-slow");
      if (onHeight) onHeight(h);
      clearTimeout(timer);
      resolve(h);
    });
  });
}

// Tap a thumbnail: the 現況 full-screen at fit-width / 2× / 3×, scrollable.
class ZoomModal extends Modal {
  constructor(app, title, srcdoc) { super(app); this.title = title; this.srcdoc = srcdoc; }
  onOpen() {
    this.modalEl.addClass("rv-zoom-modal");
    this.titleEl.setText(this.title);
    const bar = this.contentEl.createDiv({ cls: "rv-zoom-bar" });
    const scroller = this.contentEl.createDiv({ cls: "rv-zoom-scroll" });
    const draw = (f) => {
      for (const b of bar.querySelectorAll("button")) b.toggleClass("is-on", b.dataset.f === String(f));
      scroller.empty();
      const scale = ((scroller.clientWidth || 340) / W) * f;
      const inner = scroller.createDiv({ cls: "rv-zoom-inner" });
      inner.style.width = `${W * scale}px`;
      frameIn(inner, this.srcdoc, scale, (h) => { inner.style.height = `${h * scale}px`; });
    };
    for (const [label, f] of [["符合寬度", 1], ["2×", 2], ["3×", 3]]) {
      const b = bar.createEl("button", { text: label });
      b.dataset.f = String(f);
      b.addEventListener("click", () => draw(f));
    }
    draw(1);
  }
  onClose() { this.contentEl.empty(); }
}

class RoadmapView extends ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    // Never a field named `open`: it shadows View.open and blanks the pane (spike v0.0.2).
    this.tab = "near";          // near | all
    this.detail = null;         // id of the item on the detail page
    this.query = "";
    this.todoExpanded = false;
    this.folds = new Set();     // titles of the detail page's open folds
    this.listScroll = 0;        // the list's scroll position when a card was opened
    this.shown = null;          // the screen last drawn: a tab, or `detail:<id>`
    this.docs = new Map();      // "<mockup path>#now|opt:X" → { mtime, doc, label, h }
    this.chosen = new Map();    // thumbnail slot → the docs key it last drew, to pre-size a redraw
    this.renders = 0;
    this.gen = 0;
    this.resetThumbs();
  }
  getViewType() { return VIEW; }
  getDisplayText() { return "Roadmap 檢視"; }
  getIcon() { return "layout-list"; }
  async onOpen() { await this.render(); }
  async onClose() {
    this.renders++;   // a render still loading must not draw into the closed view
    clearTimeout(this.typing);
    this.resetThumbs();
  }

  async render() {
    const n = ++this.renders;
    const root = this.contentEl;
    try {
      const data = await this.readProject();
      if (n !== this.renders) return;   // a newer render started meanwhile
      clearTimeout(this.typing);        // a pending search would redraw the old list
      // A redraw of the same screen (a live refresh, 待做 opening) keeps the reader's place.
      const screen = this.detail ? `detail:${this.detail}` : this.tab;
      const top = this.shown === screen ? root.scrollTop || 0 : this.detail ? 0 : this.listScroll;
      root.empty();
      root.addClass("rv");
      this.resetThumbs();
      this.draw(root, data);
      const drawn = this.detail ? `detail:${this.detail}` : this.tab;   // draw() may leave a vanished item
      root.scrollTop = drawn === screen ? top : this.listScroll;
      this.shown = drawn;
    } catch (e) {
      if (n !== this.renders) return;
      root.empty();
      root.addClass("rv");
      root.createEl("pre", { cls: "rv-err", text: `Roadmap 檢視出錯了：\n${(e && (e.stack || e.message)) || e}` });
      console.error("roadmap-view", e);
    }
  }

  // Not `load`: View.open() calls Component.load(), and overriding it breaks the view.
  async readProject() {
    const s = this.plugin.settings;
    const adapter = this.app.vault.adapter;
    const all = this.app.vault.getFiles().map((f) => f.path);
    const pre = `${s.projectsDir}/`;
    const projects = all.filter((p) => p.startsWith(pre) && /^[^/]+\/ROADMAP\.md$/.test(p.slice(pre.length)))
      .map((p) => p.slice(pre.length).split("/")[0]).sort();
    if (!projects.length) { this.plugin.current = null; return { projects }; }
    const project = projects.includes(s.project) ? s.project : projects[0];
    const dir = `${pre}${project}`;
    this.plugin.current = dir;
    const items = parseRoadmap(await adapter.read(`${dir}/ROADMAP.md`));
    const list = async (sub) => { try { return (await adapter.list(`${dir}/${sub}`)).files; } catch (e) { return []; } };
    const mockups = (await list("Proposals/mockups")).filter((p) => /\.html$/i.test(p))
      .map((p) => p.slice(dir.length + 1)).sort();   // list order differs by platform
    const phases = {};
    // ponytail: reads every status file on each render; index them if hundreds get slow
    await Promise.all((await list("ship-status")).filter((p) => /\/R-[^/]+\.json$/.test(p)).map(async (p) => {
      try { phases[p.split("/").pop().slice(0, -5)] = JSON.parse(await adapter.read(p)); } catch (e) { /* half-synced: skip */ }
    }));
    const now = this.plugin.now();
    const rows = items.map((item) => ({
      item, status: statusOf(item, phases[item.id] || null, now, s.recentDays), mockups: mockupsFor(item, items, mockups),
    }));
    const docs = all.filter((p) => p.startsWith(`${dir}/Specs/`) || p.startsWith(`${dir}/Brainstorms/`));
    return { projects, project, dir, rows, docs };
  }

  draw(root, d) {
    if (!d.projects.length) {
      root.createDiv({ cls: "rv-empty", text: `「${this.plugin.settings.projectsDir}」底下沒有含 ROADMAP.md 的專案資料夾` });
      return;
    }
    const row = this.detail && d.rows.find((r) => r.item.id === this.detail);
    if (this.detail && !row) { this.detail = null; this.folds.clear(); }   // its row went away: back to the list
    const bar = root.createDiv({ cls: "rv-bar" });
    const sel = bar.createEl("select", { cls: "dropdown rv-project" });
    for (const p of d.projects) sel.createEl("option", { text: p, value: p });
    sel.value = d.project;
    sel.addEventListener("change", async () => {
      this.plugin.settings.project = sel.value;
      this.detail = null;
      this.listScroll = 0;
      await this.plugin.saveSettings();
      await this.render();
    });
    const tabs = bar.createDiv({ cls: "rv-tabs" });
    for (const [k, label] of [["near", "近況"], ["all", "全部"]]) {
      const b = tabs.createEl("button", { text: label });
      if (this.tab === k && !this.detail) b.addClass("is-on");
      b.addEventListener("click", () => { this.tab = k; this.detail = null; this.listScroll = 0; this.render(); });
    }
    if (row) return this.drawDetail(root, d, row);
    if (this.tab === "all") this.drawAll(root, d);
    else this.drawNear(root, d);
  }

  drawNear(root, d) {
    const groups = [["active", "進行中／卡住"], ["recent", `最近完成（${this.plugin.settings.recentDays} 天內）`], ["todo", "待做"]];
    for (const [g, label] of groups) {
      const rows = d.rows.filter((r) => r.status.group === g);
      if (g === "recent") rows.sort((a, b) => (b.item.done || "").localeCompare(a.item.done || ""));
      const h = root.createDiv({ cls: "rv-group", text: `${label} · ${rows.length}` });
      if (g === "todo") {
        h.addClass("rv-foldable");
        const shown = this.todoExpanded;   // two taps before the redraw must not cancel out
        h.addEventListener("click", () => { this.todoExpanded = !shown; this.render(); });
        if (!this.todoExpanded) { h.setText(`${label} · ${rows.length}（點開）`); continue; }
      }
      if (!rows.length) root.createDiv({ cls: "rv-none", text: "沒有" });
      for (const r of rows) this.card(root, d, r);
    }
  }

  drawAll(root, d) {
    const input = root.createEl("input", { type: "search", cls: "rv-search", placeholder: "搜尋 id、標題、說明…" });
    input.value = this.query;
    const list = root.createDiv();
    const fill = () => {
      list.empty();
      this.resetThumbs();
      const q = this.query.trim().toLowerCase();
      const rows = q ? d.rows.filter((r) => [r.item.id, r.item.headline, r.item.explain || "", r.item.tags]
        .join(" ").toLowerCase().includes(q)) : d.rows;
      list.createDiv({ cls: "rv-group", text: `${rows.length} 項` });
      for (const r of rows) this.card(list, d, r);
    };
    input.addEventListener("input", () => {
      this.query = input.value;
      clearTimeout(this.typing);
      this.typing = setTimeout(fill, 200);
    });
    fill();
  }

  chips(parent, item, status) {
    const top = parent.createDiv({ cls: "rv-top" });
    top.createSpan({ cls: "rv-id", text: item.id });
    for (const c of status.chips) top.createSpan({ cls: `rv-chip rv-${c.kind}`, text: c.text });
  }

  card(parent, d, r) {
    const c = parent.createDiv({ cls: `rv-card rv-g-${r.status.group}` });
    const left = c.createDiv({ cls: "rv-left" });
    this.chips(left, r.item, r.status);
    left.createDiv({ cls: "rv-title", text: r.item.headline });
    if (r.item.explain) left.createDiv({ cls: "rv-exp", text: r.item.explain });
    if (r.mockups.length) {
      // A done item shows what was built: its picked option, else 現況.
      const done = r.status.group === "recent" || r.status.group === "done";
      const now = this.nowSource(d, r);
      const opt = done && r.item.picked ? this.optionSource(d, r) : null;
      const find = opt ? async () => (await opt()) || now() : now;   // optionSource skips what it cannot read
      this.lazyThumb(c.createDiv({ cls: "rv-thumb" }), `${d.dir}|card:${r.item.id}`, find, 70);
    } else c.addClass("rv-nothumb");
    c.addEventListener("click", () => {
      this.listScroll = this.contentEl.scrollTop || 0;
      this.detail = r.item.id;
      this.folds.clear();
      this.render();
    });
  }

  drawDetail(root, d, r) {
    const { item, status } = r;
    const back = root.createEl("button", { cls: "rv-back", text: "← 返回" });
    back.addEventListener("click", () => { this.detail = null; this.folds.clear(); this.render(); });
    this.chips(root, item, status);
    root.createDiv({ cls: "rv-title rv-headline", text: item.headline });
    root.createDiv({ cls: item.explain ? "rv-exp rv-full" : "rv-exp rv-faint", text: item.explain || "還沒有白話說明" });
    if (r.mockups.length && item.picked) {
      // From the cache when this item's option was drawn before, so a refresh moves nothing;
      // hidden until found the first time, so a missing option never flashes.
      const fromCard = this.chosen.get(`${d.dir}|card:${item.id}`);
      const optKey = this.chosen.get(`${d.dir}|opt:${item.id}`) || (fromCard && fromCard.includes("#opt:") ? fromCard : null);
      const cached = this.docs.get(optKey);
      const seen = cached && cached.doc && optKey.endsWith(`#opt:${item.picked}`) ? cached : null;
      const lbl = root.createDiv({ cls: "rv-lbl", text: `採用方案 ${item.picked}` });
      const box = root.createDiv({ cls: "rv-big" });
      const cap = root.createDiv({ cls: "rv-cap", text: seen && seen.label ? `${seen.label} · 點圖放大` : "點圖放大" });
      if (!seen) {   // the box stays laid out (an observer must still see it), just invisible
        lbl.style.display = "none";
        cap.style.display = "none";
        box.style.visibility = "hidden";
      }
      this.lazyThumb(box, `${d.dir}|opt:${item.id}`, this.optionSource(d, r), 0, {
        presize: optKey,
        label: (l) => {
          cap.setText(l ? `${l} · 點圖放大` : "點圖放大");
          lbl.style.display = "";
          cap.style.display = "";
          box.style.visibility = "";
        },
        missing: () => { lbl.remove(); box.remove(); cap.remove(); },   // no such panel: say nothing
      });
    }
    if (r.mockups.length) {
      root.createDiv({ cls: "rv-lbl", text: "MOCKUP · 現況" });
      const big = root.createDiv({ cls: "rv-big" });
      this.lazyThumb(big, `${d.dir}|now:${item.id}`, this.nowSource(d, r), 0, { presize: `${d.dir}/${r.mockups[0]}#now` });
      root.createDiv({ cls: "rv-cap", text: "點圖放大" });
    }
    root.createDiv({ cls: "rv-lbl", text: "相關文件" });
    const links = [
      ...d.docs.filter((p) => p.startsWith(`${d.dir}/Specs/${item.id}-`)).map((p) => ["spec", p]),
      ...d.docs.filter((p) => p.startsWith(`${d.dir}/Brainstorms/${item.id}-`)).map((p) => ["brainstorm", p]),
      ...r.mockups.map((m) => ["mockup", `${d.dir}/${m}`]),
    ];
    if (!links.length) root.createDiv({ cls: "rv-faint", text: "沒有相關文件" });
    for (const [kind, p] of links) {
      const a = root.createEl("a", { cls: "rv-link", text: `${kind} · ${p.slice(d.dir.length + 1)}` });
      a.addEventListener("click", (e) => {
        e.preventDefault();
        if (kind === "mockup") this.openMockup(p);
        else this.app.workspace.openLinkText(p, "", true);
      });
    }
    const refs = [item.commit && `commit ${item.commit}`, item.mr && `MR ${item.mr}`].filter(Boolean);
    if (refs.length) root.createDiv({ cls: "rv-link rv-off", text: refs.join(" · ") });
    const fold = (title, lines) => {
      const det = root.createEl("details", { cls: "rv-fold" });
      det.createEl("summary", { text: title });
      det.open = this.folds.has(title);   // a live refresh keeps what the reader opened
      det.addEventListener("toggle", () => { if (det.open) this.folds.add(title); else this.folds.delete(title); });
      for (const l of lines) det.createDiv({ cls: "rv-raw", text: l });
      return det;
    };
    if (item.doneWhen.length) {
      const ul = fold("完成條件", []).createEl("ul", { cls: "rv-dw" });
      for (const line of item.doneWhen) for (const c of splitConditions(line)) ul.createEl("li", { text: c });
    }
    fold("給 AI 的原文", [item.raw, ...item.ann]);
    const jump = root.createEl("a", { cls: "rv-link", text: "在 ROADMAP.md 打開這一行" });
    jump.addEventListener("click", async (e) => {
      e.preventDefault();
      const f = this.app.vault.getAbstractFileByPath(`${d.dir}/ROADMAP.md`);
      if (f) await this.app.workspace.getLeaf(true).openFile(f, { eState: { line: item.line } });
    });
  }

  openMockup(path) {
    const f = this.app.vault.getAbstractFileByPath(path);
    const reg = this.app.viewRegistry;
    if (f && reg && reg.getTypeByExtension && reg.getTypeByExtension("html")) return this.app.workspace.getLeaf(true).openFile(f);
    if (this.app.openWithDefaultApp) return this.app.openWithDefaultApp(path);
    new Notice(`沒有可以打開 HTML 的檢視器：${path}`);
  }

  // ---- thumbnails: lazy (only cards in view), at most MAX_THUMBS at once, cached per mtime

  resetThumbs() {
    this.gen++;   // jobs still in flight from an older render no longer hold a slot
    this.running = 0;
    this.queue = [];
    this.jobs = new Map();
    if (this.io) this.io.disconnect();
    this.io = null;
  }

  // What a thumbnail shows is found lazily: `find` resolves to { key, title } of a cached
  // entry, or null. `slot` (project dir + role + id) names the box across redraws;
  // `on.label` / `on.missing` hear the result; `on.presize` is a cache key to size from first.
  nowSource(d, r) {
    const path = `${d.dir}/${r.mockups[0]}`;
    return async () => {
      const e = await this.entryFor(path, "now");
      return e && e.doc ? { key: `${path}#now`, title: `${r.item.id} · 現況` } : null;
    };
  }

  // A label match in any of the item's mockups beats a class match in an earlier one.
  optionSource(d, r) {
    const x = r.item.picked;
    return async () => {
      for (const by of ["label", "class"]) {
        for (const m of r.mockups) {
          const path = `${d.dir}/${m}`;
          let e;
          try { e = await this.entryFor(path, `opt:${x}`); } catch (err) { continue; }   // half-synced: try the next
          if (e && e.doc && e.by === by) return { key: `${path}#opt:${x}`, title: `${r.item.id} · 採用方案 ${x}` };
        }
      }
      return null;
    };
  }

  lazyThumb(box, slot, find, maxHeight, on = {}) {
    const hit = this.docs.get(this.chosen.get(slot) || on.presize);   // `presize`: what the card already measured
    if (hit && hit.h) fitBox(box, hit.h, maxHeight);   // a redraw does not collapse to 0 px first
    const job = () => this.drawThumb(box, slot, find, maxHeight, on);
    if (typeof IntersectionObserver === "undefined") { this.enqueue(job); return; }
    if (!this.io) {
      this.io = new IntersectionObserver((entries) => {
        for (const e of entries) {
          const j = e.isIntersecting && this.jobs.get(e.target);
          if (!j) continue;
          this.io.unobserve(e.target);
          this.jobs.delete(e.target);
          this.enqueue(j);
        }
      }, { root: this.contentEl, rootMargin: "200px" });
    }
    this.jobs.set(box, job);
    this.io.observe(box);
  }

  enqueue(job) { this.queue.push(job); this.pump(); }

  pump() {
    while (this.running < MAX_THUMBS && this.queue.length) {
      const job = this.queue.shift();
      const gen = this.gen;
      this.running++;
      Promise.resolve().then(job).catch((e) => console.error("roadmap-view thumbnail", e))
        .finally(() => { if (gen === this.gen) { this.running--; this.pump(); } });
    }
  }

  async drawThumb(box, slot, find, maxHeight, on) {
    let got;
    try { got = await find(); } catch (e) { box.setText("讀不到 mockup"); return; }
    const entry = got && this.docs.get(got.key);
    if (!entry) { if (on.missing) on.missing(); else box.setText("沒有現況"); return; }
    this.chosen.set(slot, got.key);
    if (on.label) on.label(entry.label);
    box.addEventListener("click", (e) => {
      e.stopPropagation();   // a thumbnail tap zooms; it does not open the card
      new ZoomModal(this.app, got.title, entry.doc).open();
    });
    await thumb(box, entry.doc, maxHeight, (h) => { entry.h = h; });
  }

  // One mockup's 現況 (`now`) or option panel (`opt:X`), cached per path + kind + mtime.
  async entryFor(path, kind) {
    const adapter = this.app.vault.adapter;
    const st = await adapter.stat(path);
    if (!st) return null;
    const key = `${path}#${kind}`;
    const hit = this.docs.get(key);
    if (hit && hit.mtime === st.mtime) return hit;
    const html = await adapter.read(path);
    const o = kind === "now" ? { doc: currentStateDoc(html), label: "" } : optionDoc(html, kind.slice(4)) || { doc: null, label: "" };
    const entry = { mtime: st.mtime, doc: o.doc, label: o.label, by: o.by };
    this.docs.set(key, entry);
    return entry;
  }
}

// ---------------------------------------------------------------- plugin

class RoadmapViewPlugin extends Plugin {
  async onload() {
    this.settings = Object.assign({}, DEFAULTS, await this.loadData());
    this.current = null;   // the project dir on screen, set by the view
    this.registerView(VIEW, (leaf) => new RoadmapView(leaf, this));
    this.addRibbonIcon("layout-list", "Roadmap 檢視", () => this.activate());
    this.addCommand({ id: "open", name: "打開 Roadmap 檢視", callback: () => this.activate() });
    // After layout-ready, so the vault's start-up `create` burst is not replayed at us.
    this.app.workspace.onLayoutReady(() => {
      // A project's ROADMAP.md appearing, going or moving changes the picker, even when
      // no project is on screen yet (the phone's first sync).
      const pre = () => `${this.settings.projectsDir}/`;
      const isRoadmap = (p) => !!p && p.startsWith(pre()) && /^[^/]+\/ROADMAP\.md$/.test(p.slice(pre().length));
      for (const ev of ["modify", "create", "delete", "rename"]) {
        this.registerEvent(this.app.vault.on(ev, (f, oldPath) => {
          const p = f && f.path;
          if (isWatched(p, this.current) || isWatched(oldPath, this.current)
            || (ev !== "modify" && (isRoadmap(p) || isRoadmap(oldPath)))) this.refreshSoon();
        }));
      }
    });
  }
  onunload() { clearTimeout(this.timer); clearTimeout(this.retry); }
  now() { return new Date(); }
  async saveSettings() { await this.saveData(this.settings); }
  refreshSoon() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.refresh(), 500);
  }
  refresh(only) {
    const waiting = [];
    for (const leaf of only || this.app.workspace.getLeavesOfType(VIEW)) {
      const v = leaf.view;
      if (!(v instanceof RoadmapView)) continue;
      // Redrawing would remove this leaf's focused search box and close the phone's
      // keyboard: that leaf waits. A window without focus has no keyboard to protect.
      const doc = v.contentEl.ownerDocument;
      const a = doc && doc.hasFocus && doc.hasFocus() && doc.activeElement;
      if (a && a.matches && a.matches(".rv-search") && v.contentEl.contains(a)) { waiting.push(leaf); continue; }
      v.render();
    }
    if (waiting.length) {
      clearTimeout(this.retry);
      this.retry = setTimeout(() => this.refresh(waiting), 500);
    }
  }
  async activate() {
    const { workspace } = this.app;
    let leaf = workspace.getLeavesOfType(VIEW)[0];
    if (!leaf) { leaf = workspace.getLeaf(true); await leaf.setViewState({ type: VIEW, active: true }); }
    workspace.revealLeaf(leaf);
  }
}

Object.assign(RoadmapViewPlugin, { parseRoadmap, mockupsFor, statusOf, currentStateDoc, splitConditions, optionDoc });
module.exports = RoadmapViewPlugin;
