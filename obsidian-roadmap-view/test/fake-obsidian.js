// A stand-in for the `obsidian` module, which exists only inside the app: just enough
// DOM (Obsidian's createEl helpers) and plugin plumbing for test/*.test.js.
class El {
  constructor(tag, o = {}) {
    Object.assign(this, { tag, children: [], classes: new Set(), attrs: {}, style: {}, dataset: {},
      listeners: {}, text: "", value: "", parentElement: null, clientWidth: 0 });
    if (o.cls) for (const c of String(o.cls).split(/\s+/).filter(Boolean)) this.classes.add(c);
    if (o.text !== undefined) this.text = String(o.text);
    if (o.value !== undefined) this.value = o.value;
    for (const k of ["type", "placeholder"]) if (o[k] !== undefined) this.attrs[k] = o[k];
    if (o.attr) Object.assign(this.attrs, o.attr);
    this.initialAttrs = { ...(o.attr || {}) };   // what was set before the element was inserted
  }
  createEl(tag, o) { const e = new El(tag, o); e.parentElement = this; this.children.push(e); return e; }
  createDiv(o) { return this.createEl("div", o); }
  createSpan(o) { return this.createEl("span", o); }
  empty() { this.children = []; this.text = ""; }
  addClass(c) { this.classes.add(c); }
  removeClass(c) { this.classes.delete(c); }
  toggleClass(c, on) { if (on) this.addClass(c); else this.removeClass(c); }
  hasClass(c) { return this.classes.has(c); }
  setText(t) { this.text = String(t); this.children = []; }
  setAttr(k, v) { this.attrs[k] = v; }
  addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }
  fire(t, e = {}) {
    let stopped = false;
    for (const f of this.listeners[t] || []) {
      f({ stopPropagation() { stopped = true; }, preventDefault() {}, target: this, ...e });
    }
    if (!stopped && this.parentElement && t === "click") this.parentElement.fire(t, e);
  }
  remove() {
    if (this.parentElement) this.parentElement.children = this.parentElement.children.filter((c) => c !== this);
  }
  get textContent() { return [this.text, ...this.children.map((c) => c.textContent)].filter(Boolean).join(" "); }
  findAll(pred) {
    const out = [];
    const walk = (e) => { if (pred(e)) out.push(e); e.children.forEach(walk); };
    walk(this);
    return out;
  }
  querySelectorAll(tag) { return this.findAll((e) => e.tag === tag); }
  matches(sel) { return sel.startsWith(".") && this.classes.has(sel.slice(1)); }
  contains(node) { for (let e = node; e; e = e.parentElement) if (e === this) return true; return false; }
}

class Plugin {
  constructor(app, manifest) {
    Object.assign(this, { app, manifest, views: {}, commands: [], ribbons: [], events: [], stored: null });
  }
  registerView(type, make) { this.views[type] = make; }
  addRibbonIcon(icon, title, cb) { this.ribbons.push({ icon, title, cb }); }
  addCommand(c) { this.commands.push(c); }
  registerEvent(ref) { this.events.push(ref); }
  async loadData() { return this.stored; }
  async saveData(d) { this.stored = JSON.parse(JSON.stringify(d)); }
}
// Obsidian's View.open() runs Component.load() and then onOpen(); a subclass field or
// method with one of these names silently replaces them.
class ItemView {
  constructor(leaf) { this.leaf = leaf; this.app = leaf.app; this.contentEl = new El("div"); }
  open() { return "View.open"; }
  load() { this._loaded = true; }
  unload() { this._loaded = false; }
  close() {}
}
class Modal {
  constructor(app) { this.app = app; this.contentEl = new El("div"); this.titleEl = new El("div"); this.modalEl = new El("div"); }
  open() { Modal.opened.push(this); this.onOpen(); }
  close() { this.onClose(); }
}
Modal.opened = [];
class Notice { constructor(text) { Notice.shown.push(text); } }
Notice.shown = [];
module.exports = { Plugin, ItemView, Modal, Notice, El };
