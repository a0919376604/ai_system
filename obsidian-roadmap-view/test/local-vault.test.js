// R-013 AC-4b: the real vault, when this machine has one. Skipped elsewhere (CI, other
// machines); the fixtures in parse.test.js cover the formats.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const P = require("./load");

function vault() {
  try {
    const cfg = fs.readFileSync(path.join(os.homedir(), ".claude", "ship-workflow.yml"), "utf8");
    const m = cfg.match(/^airos_vault:\s*"?([^"#\n]+?)"?\s*(#.*)?$/m);
    return m && fs.existsSync(path.join(m[1], "10 Projects")) ? m[1] : null;
  } catch { return null; }
}
const V = vault();
const projects = V ? fs.readdirSync(path.join(V, "10 Projects"))
  .map((p) => path.join(V, "10 Projects", p)).filter((p) => fs.existsSync(path.join(p, "ROADMAP.md"))) : [];
const ROW = /^\s*- \[[^\]]\] [^*]{0,6}\*\*R-\d[\w.-]*(?: \([^)*]*\))?\*\*/;   // any checkbox state

test("the real ROADMAPs: every **R-…** row is parsed", { skip: !V && "no vault on this machine" }, () => {
  for (const p of projects) {
    const md = fs.readFileSync(path.join(p, "ROADMAP.md"), "utf8");
    const want = md.split("\n").filter((l) => ROW.test(l)).length;
    assert.equal(P.parseRoadmap(md).length, want, path.basename(p));
  }
});

test("the real mockups: each R-NNN mockup yields a 現況 document", { skip: !V && "no vault on this machine" }, () => {
  for (const p of projects) {
    const dir = path.join(p, "Proposals", "mockups");
    if (!fs.existsSync(dir)) continue;
    for (const f of fs.readdirSync(dir).filter((f) => /^R-.*\.html$/.test(f))) {
      assert.ok(P.currentStateDoc(fs.readFileSync(path.join(dir, f), "utf8")), f);
    }
  }
});

test("the real vault: every picked option whose opt panel exists yields an option doc (R-024 AC-10)", { skip: !V && "no vault on this machine" }, () => {
  for (const p of projects) {
    const items = P.parseRoadmap(fs.readFileSync(path.join(p, "ROADMAP.md"), "utf8"));
    const dir = path.join(p, "Proposals", "mockups");
    const files = fs.existsSync(dir) ? fs.readdirSync(dir).map((f) => `Proposals/mockups/${f}`) : [];
    for (const it of items.filter((i) => i.picked)) {
      const htmls = P.mockupsFor(it, items, files).filter((f) => fs.existsSync(path.join(p, f)))
        .map((f) => fs.readFileSync(path.join(p, f), "utf8"));
      if (!htmls.some((h) => /class="[^"]*\bopt\w*/.test(h))) continue;   // AC-10: any opt* panel
      assert.ok(htmls.some((h) => P.optionDoc(h, it.picked)), `${path.basename(p)} ${it.id} 方案 ${it.picked}`);
    }
  }
});
