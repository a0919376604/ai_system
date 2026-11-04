---
date: 2026-11-04
updated: 2026-11-04
type: learning
id: R-037
tags: [learning, ai_system, draw-arch, markdown, gitlab, zsh]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-037
shipped: true
shipped-date: 2026-11-04
---

## For future Claude
> R-037 gave the architecture pack a front door. The top level holds only `README.md`,
> `html/` and `specs/`. `render.py readme <pack>` builds the README from the specs: how to
> read the pack, each page's key points with a link, and how to update it. It exists
> because GitLab shows Markdown but not HTML.
>
> **Headline lesson:** know what your guarantee protects before you promise it. The spec
> promised that Markdown escaping "cannot inject links on GitLab". That was false, since
> GitLab ignores some backslash escapes, and it was also the wrong promise. Specs share the
> repo with the README, so anyone who can edit one can edit the other. The real job was
> display safety: keep ordinary text from breaking the page.

## What Shipped
- **`render.py readme <pack>`.** It writes a fixed, deterministic structure:
  1. a title and a Commit line;
  2. 怎麼看這包;
  3. 每一頁, with one `###` link to `html/<topic>.html` per page, in index order:
     - seams page: a table of each system's verdict;
     - jobs page: counts per group;
     - features page: the card titles;
     - LangGraph page: the contract highlights;
     - other diagrams: their subtitle;
  4. 怎麼更新.
- **`md_escape`.** It collapses whitespace, backslash-escapes Markdown punctuation, and escapes a leading block marker (`#`, `-`, `+`, `=`, `~`, `>`, `1.`).
- **SKILL.md.** It writes the new layout and migrates an old flat pack with `find`, which is zsh-safe. It then runs `render.py readme` last.
- **Tests:** 98 in `test_draw-arch.bats`.
- **The langlive-line-oa vault pack** is migrated: README.md + html/ (10 pages) + specs/ (9 specs). Every check is clean.

## Key Decisions
- The operator chose option A (files in the repo, no GitLab Pages) with an auto-generated README that explains how to use the pack. The operator noted that an `index.html` mixed in with every other file does not read as the starting point, so I proposed three top-level entries and the operator agreed.
- The vault uses the same layout as the repo (my call).
- The README carries conclusions taken from spec data only, never copied page bodies (my call).
- Escaping is for display only, not a security boundary. I revised this after review. Code spans were rejected because they turn all the prose monospace.
- Door: two-way.

## What Changed From Plan
- Codex ran Tasks 1–2 in one round. Its one deviation: it also escapes `(` and `)`.
- Task 3 (Claude) migrated the vault pack and checked every cross-link.
- Review attempt 1 (2 blocking, 2 important):
  - newline injection broke the structure;
  - the false injection guarantee was corrected in the spec;
  - old flat packs needed a migration;
  - the test was weak.
- Review attempt 2 (1 blocking, 1 important): my own migration used a glob that zsh aborts on when it matches nothing; leading block markers were not escaped. Both were reproduced in tests first.
- Attempt 3 was clean.

## Bugs
- A `for f in "$OUT"/*.json` loop in a SKILL block aborts under zsh, the shell Claude's Bash tool runs, whenever nothing matches. That was the normal case, a fresh pack.
- Collapsing newlines does not stop a line that already starts with `-`, `#`, `1.` or `~~~` from changing block type on GitLab.
- GitLab ignores some backslash escapes, so `\[c\]\(//x\)` still renders as a link.

## Lessons → checks
- In SKILL or command shell blocks, never rely on a glob that may match nothing — use find; the Bash tool runs zsh, which aborts on no match — enforced by `cd claude-skills/ship-workflow && bats tests/test_draw-arch.bats -f 'under zsh'` · proof: red at d8bd3fc (exit 1) · green at 8a9b43e
- Before promising a sanitiser blocks injection, name who controls the input; if they can already edit the output, promise display safety instead — judgment

## Reusable Patterns
- **A front-door README for generated HTML on GitLab.** Keep only README + `html/` + `specs/` at the top level, and generate the README from the same specs as the pages so it cannot drift.
- **Display-safe one-line Markdown.** Collapse whitespace, backslash-escape punctuation, and escape a leading block marker.

## Technical Debt
- Review nits not taken:
  - bare URLs and `@mentions` in spec text are still autolinked by GitLab, which is acceptable under the display-only contract;
  - an empty `OUT` is guarded only on the mkdir line;
  - some tests pin source text.
- The `draw-arch` rule "never write into the target repo" still holds. Putting the pack into langlive-line-oa means copying the vault pack into that repo's `docs/architecture/` through its own MR.

## Future Follow-ups
- Copy the pack into langlive-line-oa `docs/architecture/` through an MR on its GitLab.
