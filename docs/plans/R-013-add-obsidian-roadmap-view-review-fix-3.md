# R-013 review fix 3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding of R-013's second code review, each reproduced first: 1 blocking, 2 important, 3 nits (`/tmp/ship-next-review-R-013-2.md`).

**Architecture:** Same method as the main plan and review fix 2 (both already executed on this branch): every code step is a `git apply` patch from the prototype, replayed red/green, task by task, in a linked worktree of this branch.

**Tech Stack:** bash + zsh (sourced libs), bats 1.13, jq, Node ≥ 22 (`node:test`), Obsidian plugin API.

**Spec:** `docs/specs/R-013-add-obsidian-roadmap-view.md` (its "Review attempt 1" and "Review attempt 2" decisions).

## Global Constraints

The main plan's Global Constraints all apply. In short:
- Edit only this repository; never `~/.claude/`, `~/.agents/`, the home directory or the vault. `obsidian-roadmap-view/test/local-vault.test.js` reads the vault read-only — run it, do not change it.
- Do not run `./sync.sh restore` / `backup` against the real home; do not touch Obsidian.
- `.ship/` is not part of this plan. Stage only the paths each commit step names; never `git add -A`.
- Run every command from the repository (worktree) root. Patches are the code, generated against this exact base (`f70a772` plus this plan's commit): if one does not apply, STOP.
- `main.js` may `require` only `"obsidian"`. No `package.json`, no `npm install`.
- Read `.ship/tdd-rules.md` before tests and `.ship/ponytail-rules.md` before code, if present.
- Known pre-existing failure in a linked worktree: `cwd-guard: exits 0 when not in a git repo at all`. It must stay the ONLY failure.
- One commit per task with the exact message given. Never amend, never push, never switch branches.

## Review Focus

1. A command block run in a fresh shell must never write supervise state with an empty plan or slot, and the cap must still stop the loop. → Task 1.
2. A live refresh while the Roadmap tab is hidden — nothing is measured, so nothing may be sized from a guessed width. → Task 2.
3. Obsidian in the background with a search box that last had focus — live updates must still arrive. → Task 2.
4. Two Roadmap leaves, one being searched — only that one waits. → Task 2.
5. The open item's row deleted or renamed — the view returns to the list, not to a page that no longer exists. → Task 2.

---
### Task 1: The record-the-round block rebuilds its own variables in a fresh shell

Seam: ship-next Phase 5 record-the-round block (executed by `test_command-blocks.bats`)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 2, blocking (this ship's regression): round 1 sourced the libs in the stop_exhausted block, so `codex_state_write` began to run for real — but `CODEX_ATTEMPT_CAP`, `CODEX_ATTEMPT`, `PLAN` and `SLOT` were never set in that shell. Reproduced: `[: : integer expression expected`, `ROUTE=relaunch`, and `.ship/codex-supervise.md` rewritten with an empty plan and slot, so a later re-entry starts at attempt 0 and can relaunch without end. The block now rebuilds them from `state.env` and the supervise state, the same way the launch block derives them.

**Files:**
- Modify: `claude-skills/ship-workflow/commands/ship-next.md`
- Modify: `claude-skills/ship-workflow/tests/test_command-blocks.bats`

**Interfaces:**
- Consumes: `sn_state_load` (ID, SLUG, CODEX_REPORT from state.env), `codex_state_attempt`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_FIX3_PATCH'
diff --git a/claude-skills/ship-workflow/tests/test_command-blocks.bats b/claude-skills/ship-workflow/tests/test_command-blocks.bats
index c0c3da2..f9396da 100644
--- a/claude-skills/ship-workflow/tests/test_command-blocks.bats
+++ b/claude-skills/ship-workflow/tests/test_command-blocks.bats
@@ -660,3 +660,34 @@ land_case() {
   run env MODE=discard TARGET=../x bash "$SCRATCH/d.sh"
   [ -e "$vault/10 Projects/repo/x.json" ]
 }
+
+# R-013 review 2: the block runs in a fresh shell; it must not write a state with an
+# empty plan, and the cap must still stop the loop.
+@test "ship-next P5 record-the-round block, in a fresh shell, keeps the plan and stops at the cap" {
+  WT="$SCRATCH/wt"
+  vault=$(make_fake_airos "$SCRATCH" wt)
+  write_global_config "$HOME" "$vault"
+  echo report > "$SCRATCH/report.md"
+  block ship-next.md '^     Record the round, then relaunch or stop:' '^     On `relaunch`' > "$SCRATCH/r.sh"
+  [ -s "$SCRATCH/r.sh" ]
+  for shell in bash zsh; do
+    for start in 0 2; do
+      rm -rf "$WT" "$vault/10 Projects/wt/ship-status"
+      mkdir -p "$WT/.ship"
+      printf 'ID=R-9\nSLUG=x\nBRANCH=ship/R-9-x\nCODEX_REPORT=%s\n' "$SCRATCH/report.md" > "$WT/.ship/state.env"
+      printf 'plan: docs/plans/R-9-x.md\nslot: R-9-x_\nattempt: %s\nlast_verdict: blocked\n' "$start" > "$WT/.ship/codex-supervise.md"
+      run env WORKTREE="$WT" CODEX_CLASS="plan defect" CODEX_NOTE=n CODEX_BLOCKED_AT="Task 1" \
+        "$shell" -c 'source "$1"; echo "ROUTE=$CODEX_ROUTE"' -- "$SCRATCH/r.sh"
+      [[ "$output" != *"integer expression"* ]] || { echo "$shell: $output"; return 1; }
+      grep -qxF 'plan: docs/plans/R-9-x.md' "$WT/.ship/codex-supervise.md" || { echo "$shell: plan lost"; return 1; }
+      grep -qxF 'slot: R-9-x_' "$WT/.ship/codex-supervise.md" || return 1
+      grep -qxF "attempt: $((start + 1))" "$WT/.ship/codex-supervise.md" || { cat "$WT/.ship/codex-supervise.md"; return 1; }
+      if [ "$start" -eq 2 ]; then
+        [[ "$output" == *"ROUTE=stop_exhausted"* ]] || { echo "$shell: $output"; return 1; }
+        [ "$(jq -r .phase "$vault/10 Projects/wt/ship-status/R-9.json")" = blocked ] || return 1
+      else
+        [[ "$output" == *"ROUTE=relaunch"* ]] || { echo "$shell: $output"; return 1; }
+      fi
+    done
+  done
+}
R013_FIX3_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-lib.bats tests/test_no-positional-params.bats; cd - >/dev/null`

Expected: `1..80`, 79 ok, these 1 fail:
  - `not ok 49 ship-next P5 record-the-round block, in a fresh shell, keeps the plan and stops at the cap`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_FIX3_PATCH'
diff --git a/claude-skills/ship-workflow/commands/ship-next.md b/claude-skills/ship-workflow/commands/ship-next.md
index d97e235..7f06b54 100644
--- a/claude-skills/ship-workflow/commands/ship-next.md
+++ b/claude-skills/ship-workflow/commands/ship-next.md
@@ -366,6 +366,11 @@ You are taking a ROADMAP row from "Now" all the way to a squashed commit on the
      source ~/.claude/skills/ship-workflow/lib/codex-rounds.sh
      source ~/.claude/skills/ship-workflow/lib/codex-supervise-state.sh
      sn_state_load "$WORKTREE"
+     # A fresh shell: rebuild what the launch block set — never write an empty plan or slot.
+     CODEX_ATTEMPT_CAP=3
+     PLAN="docs/plans/${ID}-${SLUG}.md"
+     SLOT=$(basename "$PLAN" .md | tr -c 'A-Za-z0-9_.-' '_')
+     CODEX_ATTEMPT=$(codex_state_attempt "$WORKTREE")
      CODEX_ATTEMPT=$((CODEX_ATTEMPT + 1))
      codex_round_append "$WORKTREE" "$CODEX_ATTEMPT" blocked "$CODEX_REPORT" "$CODEX_CLASS" "$CODEX_NOTE"
      codex_state_write "$WORKTREE" "$PLAN" "$SLOT" "$CODEX_ATTEMPT" blocked "$CODEX_CLASS" "$CODEX_BLOCKED_AT"
R013_FIX3_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `cd claude-skills/ship-workflow && bats tests/test_command-blocks.bats tests/test_ship-next-lib.bats tests/test_no-positional-params.bats; cd - >/dev/null`

Expected: `1..80`, all 80 ok, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add claude-skills/ship-workflow/commands/ship-next.md claude-skills/ship-workflow/tests/test_command-blocks.bats
git commit -m "fix(ship-next): R-013 review 2 — record-the-round block rebuilds its variables in a fresh shell"
```

### Task 2: Thumbnails sized by ratio in a hidden pane; the search wait is per leaf and needs window focus

Seam: `RoadmapViewPlugin` (its registered `roadmap-view` view)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Why:** Review attempt 2: a refresh in a hidden tab measured width 0 and sized the big 現況 for a 300 px pane (the page jumped twice on return) — `fitBox` now sets `aspect-ratio` and a pixel height only when the width is known; the search-focus wait ignored window focus (on desktop, a search box that last had focus froze live updates while Obsidian was in the background) and re-rendered every leaf on retry — now only a leaf whose own search box has focus, in a focused window, waits; a 現況 that loads after the 3 s timeout now stores its height; when the open item's row disappears, the view goes back to the list where it was.

**Files:**
- Modify: `obsidian-roadmap-view/main.js`
- Modify: `obsidian-roadmap-view/test/fake-obsidian.js`
- Modify: `obsidian-roadmap-view/test/view.test.js`

**Interfaces:**
- Consumes: the review-fix-2 view (`fitBox`, `thumb`, `refresh`, `this.shown`).
- Produces: `refresh(only)` — an optional list of leaves; the retry passes the ones that waited.

- [ ] **Step 1: Write the failing test(s)**

````bash
git apply <<'R013_FIX3_PATCH'
diff --git a/obsidian-roadmap-view/test/fake-obsidian.js b/obsidian-roadmap-view/test/fake-obsidian.js
index f7382b9..82d9171 100644
--- a/obsidian-roadmap-view/test/fake-obsidian.js
+++ b/obsidian-roadmap-view/test/fake-obsidian.js
@@ -41,6 +41,7 @@ class El {
   }
   querySelectorAll(tag) { return this.findAll((e) => e.tag === tag); }
   matches(sel) { return sel.startsWith(".") && this.classes.has(sel.slice(1)); }
+  contains(node) { for (let e = node; e; e = e.parentElement) if (e === this) return true; return false; }
 }
 
 class Plugin {
diff --git a/obsidian-roadmap-view/test/view.test.js b/obsidian-roadmap-view/test/view.test.js
index 5c536a8..f9db4e8 100644
--- a/obsidian-roadmap-view/test/view.test.js
+++ b/obsidian-roadmap-view/test/view.test.js
@@ -393,10 +393,10 @@ test("a refresh waits while the search box has focus", async (t) => {
   let n = 0;
   view.render = async () => { n++; };
   const input = view.contentEl.findAll((e) => e.tag === "input")[0];
-  view.contentEl.ownerDocument = { activeElement: input };
+  view.contentEl.ownerDocument = { activeElement: input, hasFocus: () => true };
   plugin.refresh();
   assert.equal(n, 0);
-  view.contentEl.ownerDocument = { activeElement: null };
+  view.contentEl.ownerDocument = { activeElement: null, hasFocus: () => true };
   t.mock.timers.tick(500);
   assert.equal(n, 1);
 });
@@ -461,3 +461,98 @@ test("an item's mockups come in name order, whatever order the vault lists them
   const links = view.contentEl.findAll((e) => e.hasClass("rv-link")).map((e) => e.text).filter((t) => t.startsWith("mockup"));
   assert.deepEqual(links, ["mockup · Proposals/mockups/R-2-a-mockup.html", "mockup · Proposals/mockups/R-2-b-mockup.html"]);
 });
+
+// --- R-013 review attempt 2 -------------------------------------------------------
+
+test("a hidden pane sizes the big 現況 by its ratio, not by a width it cannot measure", async () => {
+  observed = [];
+  const { view } = await setup();
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
+  await flush();
+  const big = () => view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
+  big().clientWidth = 550;   // visible: a measurable width
+  observed.filter((o) => o.el === big()).forEach(seen);
+  await flush();
+  const frame = big().findAll((e) => e.tag === "iframe")[0];
+  frame.contentDocument = { body: { scrollHeight: 400 } };
+  frame.fire("load");
+  await flush();
+  assert.equal(big().style.height, "200px");
+  assert.equal(big().style.aspectRatio, "1100 / 400");
+  observed = [];
+  await view.render();       // the pane is hidden now: nothing has a width
+  assert.equal(big().style.aspectRatio, "1100 / 400");
+  assert.equal(big().style.height, "auto");
+});
+
+test("the search box holds a refresh only while its window has focus", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });   // a wrong wait would re-arm forever
+  const { view, plugin, app } = await setup();
+  app.workspace.getLeavesOfType = () => [{ view }];
+  byText(view.contentEl, "全部").fire("click");
+  await flush();
+  let n = 0;
+  view.render = async () => { n++; };
+  const input = view.contentEl.findAll((e) => e.tag === "input")[0];
+  view.contentEl.ownerDocument = { activeElement: input, hasFocus: () => false };
+  plugin.refresh();
+  assert.equal(n, 1);
+});
+
+test("only the leaf whose own search box has focus waits; the others redraw once", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });
+  const { view: a, plugin, app } = await setup();
+  const b = plugin.views["roadmap-view"]({ app });
+  await b.onOpen();
+  app.workspace.getLeavesOfType = () => [{ view: a }, { view: b }];
+  byText(a.contentEl, "全部").fire("click");
+  await flush();
+  const input = a.contentEl.findAll((e) => e.tag === "input")[0];
+  const doc = { activeElement: input, hasFocus: () => true };
+  a.contentEl.ownerDocument = doc;
+  b.contentEl.ownerDocument = doc;
+  let na = 0, nb = 0;
+  a.render = async () => { na++; };
+  b.render = async () => { nb++; };
+  plugin.refresh();
+  assert.deepEqual([na, nb], [0, 1]);
+  t.mock.timers.tick(500);
+  assert.deepEqual([na, nb], [0, 1]);
+  doc.activeElement = null;
+  t.mock.timers.tick(500);
+  assert.deepEqual([na, nb], [1, 1]);
+});
+
+test("a 現況 that loads after the 3 s timeout still keeps its height", async (t) => {
+  t.mock.timers.enable({ apis: ["setTimeout"] });
+  observed = [];
+  const { view } = await setup();
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-3")).fire("click");
+  await flush();
+  const big = view.contentEl.findAll((e) => e.hasClass("rv-big"))[0];
+  observed.filter((o) => o.el === big).forEach(seen);
+  await flush();
+  t.mock.timers.tick(3000);
+  await flush();
+  assert.ok(big.hasClass("rv-slow"));
+  const frame = big.findAll((e) => e.tag === "iframe")[0];
+  frame.contentDocument = { body: { scrollHeight: 500 } };
+  frame.fire("load");
+  assert.equal(view.docs.get(`${D}/Proposals/mockups/R-3-a-mockup.html`).h, 500);
+  assert.ok(!big.hasClass("rv-slow"));
+});
+
+test("when the open item's row disappears, a refresh goes back to the list where it was", async () => {
+  const { view, app } = await setup();
+  view.contentEl.scrollTop = 300;
+  view.contentEl.findAll((e) => e.hasClass("rv-card")).find((c) => c.textContent.includes("R-2")).fire("click");
+  await flush();
+  assert.equal(view.detail, "R-2");
+  const read = app.vault.adapter.read;
+  app.vault.adapter.read = async (p) => (p.endsWith("ROADMAP.md") ? ROADMAP.replace(/^- \[ \] \*\*R-2\*\*.*\n/m, "") : read(p));
+  await view.render();
+  assert.equal(view.detail, null);
+  assert.equal(byText(view.contentEl, "← 返回"), undefined);
+  assert.ok(byText(view.contentEl, "近況").hasClass("is-on"));
+  assert.equal(view.contentEl.scrollTop, 300);
+});
R013_FIX3_PATCH
````

- [ ] **Step 2: Run the scoped tests — confirm the new ones fail**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 49`, `ℹ pass 44`, `ℹ fail 5` — these fail:
  - `✖ a hidden pane sizes the big 現況 by its ratio, not by a width it cannot measure`
  - `✖ the search box holds a refresh only while its window has focus`
  - `✖ only the leaf whose own search box has focus waits; the others redraw once`
  - `✖ a 現況 that loads after the 3 s timeout still keeps its height`
  - `✖ when the open item's row disappears, a refresh goes back to the list where it was`

- [ ] **Step 3: Apply the implementation**

````bash
git apply <<'R013_FIX3_PATCH'
diff --git a/obsidian-roadmap-view/main.js b/obsidian-roadmap-view/main.js
index 6892a39..d308573 100644
--- a/obsidian-roadmap-view/main.js
+++ b/obsidian-roadmap-view/main.js
@@ -238,20 +238,29 @@ function frameIn(box, srcdoc, scale, onHeight) {
 
 const scaleOf = (box) => (box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 300) / W;
 
-// Size `box` for a document `h` px tall at width W.
+// Size `box` for a document `h` px tall at width W. The ratio stays right in a hidden pane
+// (nothing to measure); a pixel height is set only when the width is known.
 function fitBox(box, h, maxHeight) {
-  const px = h * scaleOf(box);
+  box.style.aspectRatio = `${W} / ${h}`;
+  const w = box.clientWidth || (box.parentElement && box.parentElement.clientWidth) || 0;
+  if (!w) {
+    box.style.height = "auto";
+    if (maxHeight) box.style.maxHeight = `${maxHeight}px`;
+    return;
+  }
+  const px = (h * w) / W;
   box.style.height = `${maxHeight ? Math.min(px, maxHeight) : px}px`;
 }
 
 // Resolves with the document's height once drawn, or 0 when it has not loaded within
-// 3 s (the box is marked until it does).
-function thumb(box, srcdoc, maxHeight) {
+// 3 s (the box is marked until it does). `onHeight` also hears a load after the timeout.
+function thumb(box, srcdoc, maxHeight, onHeight) {
   return new Promise((resolve) => {
     const timer = setTimeout(() => { box.addClass("rv-slow"); resolve(0); }, 3000);
     frameIn(box, srcdoc, scaleOf(box), (h) => {
       fitBox(box, h, maxHeight);
       box.removeClass("rv-slow");
+      if (onHeight) onHeight(h);
       clearTimeout(timer);
       resolve(h);
     });
@@ -325,8 +334,9 @@ class RoadmapView extends ItemView {
       root.addClass("rv");
       this.resetThumbs();
       this.draw(root, data);
-      root.scrollTop = top;
-      this.shown = screen;
+      const drawn = this.detail ? `detail:${this.detail}` : this.tab;   // draw() may leave a vanished item
+      root.scrollTop = drawn === screen ? top : this.listScroll;
+      this.shown = drawn;
     } catch (e) {
       if (n !== this.renders) return;
       root.empty();
@@ -370,6 +380,8 @@ class RoadmapView extends ItemView {
       root.createDiv({ cls: "rv-empty", text: `「${this.plugin.settings.projectsDir}」底下沒有含 ROADMAP.md 的專案資料夾` });
       return;
     }
+    const row = this.detail && d.rows.find((r) => r.item.id === this.detail);
+    if (this.detail && !row) { this.detail = null; this.folds.clear(); }   // its row went away: back to the list
     const bar = root.createDiv({ cls: "rv-bar" });
     const sel = bar.createEl("select", { cls: "dropdown rv-project" });
     for (const p of d.projects) sel.createEl("option", { text: p, value: p });
@@ -387,7 +399,6 @@ class RoadmapView extends ItemView {
       if (this.tab === k && !this.detail) b.addClass("is-on");
       b.addEventListener("click", () => { this.tab = k; this.detail = null; this.listScroll = 0; this.render(); });
     }
-    const row = this.detail && d.rows.find((r) => r.item.id === this.detail);
     if (row) return this.drawDetail(root, d, row);
     if (this.tab === "all") this.drawAll(root, d);
     else this.drawNear(root, d);
@@ -559,9 +570,10 @@ class RoadmapView extends ItemView {
       e.stopPropagation();   // a thumbnail tap zooms; it does not open the card
       new ZoomModal(this.app, `${id} · 現況`, doc).open();
     });
-    const h = await thumb(box, doc, maxHeight);
-    const hit = this.docs.get(path);
-    if (h && hit) hit.h = h;
+    await thumb(box, doc, maxHeight, (h) => {
+      const hit = this.docs.get(path);
+      if (hit) hit.h = h;
+    });
   }
 
   async docFor(path) {
@@ -600,23 +612,29 @@ class RoadmapViewPlugin extends Plugin {
       }
     });
   }
-  onunload() { clearTimeout(this.timer); }
+  onunload() { clearTimeout(this.timer); clearTimeout(this.retry); }
   now() { return new Date(); }
   async saveSettings() { await this.saveData(this.settings); }
   refreshSoon() {
     clearTimeout(this.timer);
     this.timer = setTimeout(() => this.refresh(), 500);
   }
-  refresh() {
-    for (const leaf of this.app.workspace.getLeavesOfType(VIEW)) {
+  refresh(only) {
+    const waiting = [];
+    for (const leaf of only || this.app.workspace.getLeavesOfType(VIEW)) {
       const v = leaf.view;
       if (!(v instanceof RoadmapView)) continue;
-      // Redrawing would remove the focused search box and close the phone's keyboard: wait.
+      // Redrawing would remove this leaf's focused search box and close the phone's
+      // keyboard: that leaf waits. A window without focus has no keyboard to protect.
       const doc = v.contentEl.ownerDocument;
-      const a = doc && doc.activeElement;
-      if (a && a.matches && a.matches(".rv-search")) { this.refreshSoon(); continue; }
+      const a = doc && doc.hasFocus && doc.hasFocus() && doc.activeElement;
+      if (a && a.matches && a.matches(".rv-search") && v.contentEl.contains(a)) { waiting.push(leaf); continue; }
       v.render();
     }
+    if (waiting.length) {
+      clearTimeout(this.retry);
+      this.retry = setTimeout(() => this.refresh(waiting), 500);
+    }
   }
   async activate() {
     const { workspace } = this.app;
R013_FIX3_PATCH
````

- [ ] **Step 4: Run the scoped tests — confirm they pass**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 49`, `ℹ pass 49`, `ℹ fail 0`.

  On a machine without a vault, the two `the real …` tests (AC-4b) show as skipped instead; that is expected.

- [ ] **Step 5: Commit**

```bash
git add obsidian-roadmap-view/main.js obsidian-roadmap-view/test/fake-obsidian.js obsidian-roadmap-view/test/view.test.js
git commit -m "fix(roadmap-view): R-013 review 2 — ratio-sized thumbnails, per-leaf search wait, vanished detail"
```

### Task 3: Full-suite verification

Seam: none (verification only — adds no code and no tests)

Read .ship/tdd-rules.md before writing tests.
Read .ship/ponytail-rules.md before writing code.

**Files:** none modified.

- [ ] **Step 1: Run the whole bats suite** (it includes the plugin's `node --test`)

Run: `cd claude-skills/ship-workflow && bats tests/; cd - >/dev/null`

Expected: `1..605`, 604 ok, exactly one failure — the known `cwd-guard: exits 0 when not in a git repo at all`. Any other failure: STOP and report it.

- [ ] **Step 2: Run the plugin tests on their own**

Run: `node --test obsidian-roadmap-view/test/`

Expected: `ℹ tests 49`, `ℹ fail 0`.

- [ ] **Step 3: No commit** — report DONE with the Step 1 and Step 2 counts.
