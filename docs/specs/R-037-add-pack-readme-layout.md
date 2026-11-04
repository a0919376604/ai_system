---
date: 2026-11-04
updated: 2026-11-04
type: spec
id: R-037
tags: [spec, ai_system]
ai-first: true
project: "[[ai_system]]"
roadmap-item: R-037
---

## For future Claude
> R-037 gives the architecture pack a three-entry layout: `README.md`, `html/` and `specs/`.
> `render.py readme <pack>` builds the README from the specs. It says how to read the pack,
> gives each page's key points with a link, and says how to update the pack. The README is
> the pack's front door on GitLab, which shows Markdown but not HTML.

## Decisions

- Door: two-way. The change sits inside `claude-skills/draw-arch/`, and the existing
  `page`/`index` commands keep their behaviour. (my call)
- The operator plans to commit the pack to the langlive-line-oa GitLab repo. GitLab shows
  `.html` as source, not as a page. The operator chose option A, files in the repo with no
  GitLab Pages, and asked for an auto-generated README: 「A 自動產生 README 但要有一個 說明怎麼用這包吧」.
  (operator)
- The operator found that `index.html`, mixed in with a dozen other files, does not read as
  the place to start: 「index.html 放一起會讓人不知道要先點這個去看的感覺」. The top level
  therefore holds only `README.md`, `html/` and `specs/`. (operator + my proposal)
- The vault pack uses the same layout, so there is only one way to arrange a pack. (my call)
- The README carries conclusions only, never copies of page bodies:
  - the seams summary table;
  - jobs counts per group;
  - feature titles;
  - contract highlights;
  - for other diagrams, their subtitle.

  Everything comes from spec data, so it cannot drift from the pages. (my call)
- The README has a fixed layout: `<pack>/README.md` links `html/<topic>.html` and reads
  `<pack>/specs/*.json`. There is no option to change it. (my call)
- Spec text is made display-safe for Markdown. Whitespace, including newlines, collapses
  to single spaces, so the text cannot start a heading, list or table row; a leading block marker (`#`, `-`, `+`, `=`, `~`, `>`, `1.`) is escaped too. Markdown
  punctuation (`\`, `<`, `>`, `|`, `[`, `]`, `(`, `)`, `*`, `_`, backticks) is
  backslash-escaped so it shows as written. This is **not** a security boundary. Specs
  live in the same repo as the README, and whoever can edit one can edit the other.
  Review attempt 1 showed that GitLab ignores some backslash escapes, so an intentional
  link can still be crafted; code spans were rejected because they turn all prose
  monospace. (my call, revised after review)

## Seams

| Seam | Interface | Guaranteed behavior |
|------|-----------|---------------------|
| readme command | `python3 lib/render.py readme <pack dir>` | Reads every `<pack>/specs/*.json` and writes `<pack>/README.md`, UTF-8, ending in a newline. Identical specs produce byte-identical output. A missing `specs/` directory or an unreadable spec exits 2 and writes nothing. |
| readme content | the README body | It has three parts in this order. Each section starts with an `##` heading. (1) `# 架構圖包 · <repo names>`, then a `Commit` line listing every distinct `repo.commit` in short form. (2) `## 怎麼看這包`, a fixed text: on GitLab, read this README's key points; to see the full pages, clone or download this folder and open `html/index.html` in a browser; the pages work offline and on a phone. (3) `## 每一頁` lists one `### [<title>](html/<topic>.html)` per spec, in index order (overview, features, seams, jobs, then the rest by topic). Under each heading is the subtitle line, if present, followed by page-type content. A seams page gets a Markdown table 系統 \| 能不能換 \| 接觸檔 \| 漏進核心 with 容易換 / 要改一些 / 很難換. A table page gets one bullet per group, `<group>：N 個`, in first-seen order; ungrouped rows count under `其他`. A cards page gets `共 N 個：` and the card titles joined by `、`. A diagram with `contract.highlights` gets a `節點契約重點` line, then the highlights as bullets. Any other diagram gets nothing more. (4) `## 怎麼更新` is fixed text: re-run `/draw-arch` from the repo; `python3 <skill>/lib/check.py specs/<topic>.json --repo <repo>` reports stale pages; the files in `specs/` are the sources and `html/` plus `README.md` are generated. All spec text is display-escaped as in Decisions (collapsed whitespace, backslash-escaped punctuation). |
| pack layout | `SKILL.md` | An old flat pack is migrated first, with `find` (never a glob, which zsh aborts on when it matches nothing): top-level `*.json` move into `specs/` and top-level `*.html` are deleted; it works under bash and zsh, with or without an old pack. The output directory holds `README.md`, `html/` (every page and `index.html`) and `specs/` (every `<topic>.json`). Step 5 renders `specs/<topic>.json` to `html/<topic>.html`. Step 6 renders `html/index.html` from `specs/` and then runs `render.py readme`. The seams, contract and jobs commands point at `specs/`. |
| unchanged | `render.py page`, `render.py index`, `check.py`, `seams.py`, `contract.py` | Behaviour and output are byte-identical for the same inputs. Cross-page links keep working because every page and `index.html` share `html/`. |

## Acceptance

- **AC-1** Given the existing golden and page tests, then all pass unchanged.
- **AC-2** Given a pack dir whose `specs/` holds:
  - the overview diagram (`clean.json` as `overview`);
  - `features.json` (cards);
  - a seams spec with systems `line` (hard, 2 files, 1 leak) and `dw` (easy, 0 files);
  - `jobs.json` (groups 事件 ×2 and 排程 ×1);
  - a diagram `lg` with `contract.highlights: ["h1"]`,

  when `render.py readme` runs, then README.md:
  - starts with `# 架構圖包 · demo`;
  - has `## 怎麼看這包`, then `## 每一頁`, then `## 怎麼更新`, in that order;
  - has its `###` links in the order overview, features, seams, jobs, lg, each pointing to `html/<topic>.html`;
  - contains the seams rows `| LINE | 很難換 | 2 | 1 |` and `| 資料倉儲 | 容易換 | 0 | 0 |`, using the fixture titles;
  - contains `- 事件：2 個` and `- 排程：1 個`;
  - contains `共 1 個：` with the card title;
  - contains `- h1` under `節點契約重點`;
  - comes out byte-identical on a second run.
- **AC-3** Given no `specs/` directory, or a spec that is not JSON, then the command exits 2
  and no README.md is written.
- **AC-4** Given spec text `<script>alert(1)</script> [x](https://evil.example) | *a*`, then
  the README shows it as written, with every Markdown punctuation character
  backslash-escaped and no unescaped `|` inside a table cell. Given multi-line spec text
  (`first\n# Injected heading\n- injected bullet\n| a | b |`), then no README line starts
  with the injected heading or bullet, and each table row keeps exactly 5 unescaped `|`.
- **AC-5** Given SKILL.md, then it describes the `README.md` + `html/` + `specs/` layout and the
  `render.py readme` step, and no command in it writes `.html` into `specs/`.
- **AC-6** (done when) Given the langlive-line-oa vault pack, after it is moved to the new
  layout, then:
  - its top level holds only `README.md`, `html/` and `specs/`;
  - every spec passes `check.py --repo`;
  - `html/index.html` links every page and the pages link each other;
  - README.md reads correctly;
  - a screenshot of `html/index.html` was read.
