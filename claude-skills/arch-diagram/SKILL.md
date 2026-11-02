---
name: arch-diagram
description: Use when asked to draw or update a Cocoon-style architecture pack from repository code into the vault project's Architecture/diagrams/.
---

# Architecture pack

Use `/arch-diagram [<topic>…] [--out <dir>]` to produce one saved JSON spec and one
static HTML page per topic, plus `index.html`. Trace current code; choose the
content and coordinates; let the Python 3.9 stdlib CLIs check and render them.
Never write into the target repo. Never read `env.json`, `.env*` or key files
(including private keys, `*.key` and `*.pem`). Template key names are allowed;
secret values are not. Do not use stale UA material or call archify.

1. **Resolve the repo and destination.** Use cwd or the repo argument. Run
   `git -C "$REPO" rev-parse HEAD` and `git -C "$REPO" status --short`.
   Record the full commit and dirty paths; never cite dirty paths.
   Set `SKILL_DIR` to the directory holding this SKILL.md, including when using
   an uninstalled worktree copy. Call the scripts through their interpreter:
   `python3 "$SKILL_DIR/lib/check.py"` and `python3 "$SKILL_DIR/lib/render.py"`.
   Resolve the vault project with the sibling ship-workflow's
   `bash "$SKILL_DIR/../ship-workflow/lib/airos-binding.sh" project_path`, run
   from the target repo. The installed equivalent is
   `~/.claude/skills/ship-workflow/lib/airos-binding.sh project_path`.
   Default to `<project_path>/Architecture/diagrams/`; `--out <dir>` overrides
   this. If neither binding nor override works, stop and ask for a destination.
   If a destination is inside the target repo, ask for an external directory.

2. **Choose topics.** Use named topics. With none, re-run the saved specs in the
   output directory if present. Otherwise start with overview, the message route,
   and a flow per `StateGraph(` outside test directories. When multiple graphs
   exist, confirm which first graph to draw and ask before adding a second
   StateGraph. Ask before adding other pipelines or features. For line-oa the
   first graph is `lang_ai_customer`.

3. **Trace each topic.** Start from entry points, manifests and deployment files.
   Follow imports and call sites to the actual input, output and side effects;
   record `path:line` ranges at the recorded commit. Exclude secrets from every
   search and read. Every node and condition row needs code evidence. For a
   LangGraph flow, read the StateGraph definition and set `langgraph.file`;
   `check.py` compares its AST without importing or executing the source.

4. **Write or update the saved spec.** Read [spec-format.md](references/spec-format.md)
   for fields and [cocoon-style.md](references/cocoon-style.md) for the visual rules.
   Save `<topic>.json` in the output directory. On a re-run, edit that saved spec
   in place: preserve ids and coordinates unless a code or layout change requires
   moving a node, and keep a per-topic list of changes, naming affected nodes.
   Message topics use numbered step cards in a snake layout: numbered title,
   plain-language lines, `cond` and `warn` tones; include the route steps. The
   overview can carry the one-message route as a numbered overlay.
   Condition rows use the three content columns 做什麼 /
   什麼條件走到這、離開時往哪 / 程式碼, with 節點 as the identifier column.
   State when each node is reached and where it goes next. Set `warn: true`
   only when the cited code shows a real risk; uncertainty alone gets no ⚠.

5. **Check, render, look: at most three rounds per topic.**
   Run these commands with quoted paths:
   ```bash
   python3 "$SKILL_DIR/lib/check.py" "$OUT/$topic.json" --repo "$REPO"
   python3 "$SKILL_DIR/lib/render.py" page "$OUT/$topic.json" "$OUT/$topic.html"
   ```
   Fix every checker finding before rendering. Then take a full-page headless
   Chrome screenshot. Choose `h` tall enough to include the footer (the diagram,
   all route copies, steps and condition rows). Set `png` to a file in the output
   directory and `url` to a URL-encoded absolute file URL, e.g. using
   `pathlib.Path(page).resolve().as_uri()`; spaces must be percent-encoded.
   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1280,"$h" --screenshot="$png" "$url"
   ```
   Read the screenshot. Check labels, text fit, node gaps, route badges and table
   readability, then fix the saved spec and repeat check → render → screenshot
   → Read. After the third round deliver and list any remaining visual issues.

6. **Build the pack index.** After all topics:
   ```bash
   python3 "$SKILL_DIR/lib/render.py" index "$OUT" "$OUT/index.html"
   ```

7. **Report.** Link the index and pages; give the full commit, dirty-path note,
   simplifications, uncertainties and remaining layout issues. On a re-run list
   what changed per topic and node. Confirm the target repo's status is unchanged.
