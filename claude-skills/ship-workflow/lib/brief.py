#!/usr/bin/env python3
"""brief.py: the human-readable overview behind /ship-brief.

  brief.py extract <ROADMAP.md> [--kg KG.json] [--repo DIR] [--days N] [--today YYYY-MM-DD]
      Prints slim facts JSON. Claude reads this instead of the ROADMAP itself
      (langlive-line-oa: a 679 KB ROADMAP becomes ~40 KB of facts).

  brief.py render --roadmap R.md --facts F.json --brief B.json [--arch A.json] --out DIR
      Writes DIR/brief.html, plus DIR/architecture.html when the --arch file exists.
      (--kg and --arch may point at missing files, so callers can pass them unconditionally.)
      Every R-id cited in the brief or arch JSON must exist in the ROADMAP;
      otherwise nothing is written and the exit code is 1.

Claude writes the words, this script owns the numbers, dates, IDs and markup.
Stdlib only, Python 3.9+.
"""
import argparse
import datetime as dt
import html
import json
import re
import subprocess
import sys
from pathlib import Path

ROW_RE = re.compile(r"^(\s*)- \[( |x|X)\] (.*)$")
HEAD_RE = re.compile(r"^\*\*(R-\d+(?:[./-][0-9A-Za-z]+)*)[^*]*\*\*\s*(.*)$")
DATE_RE = re.compile(r"20\d\d-\d\d-\d\d")
DONE_HINT_RE = re.compile(r"merged|已 ?merge|待部署|(?<![\w-])shipped(?!-in-branch)", re.I)
TITLE_SPLIT_RE = re.compile(r"\s*——\s*|\s+—\s+")
SECTIONS = (("Now", "now"), ("Next", "next"), ("Later", "later"), ("Done", "done"))


def _split_tags(rest):
    """'[A · [[link]]] title' -> ('A · [[link]]', 'title'); brackets may nest."""
    if not rest.startswith("["):
        return "", rest
    depth = 0
    for i, ch in enumerate(rest):
        depth += ch == "["
        depth -= ch == "]"
        if depth == 0:
            return rest[1:i], rest[i + 1:].strip()
    return "", rest


def _clean(text, cap):
    text = text.replace("**", "").strip()
    return text if len(text) <= cap else text[: cap - 1] + "…"


def parse_roadmap(text):
    """Every R-row in document order, with its section and annotations."""
    rows, section, cur = [], "other", None
    for line in text.splitlines():
        if line.startswith("## "):
            section = next((k for word, k in SECTIONS if word in line), "other")
            cur = None
            continue
        m = ROW_RE.match(line)
        if m:
            cur = None
            head = HEAD_RE.match(m.group(3))
            if not head:
                continue
            tags, rest = _split_tags(head.group(2))
            title = TITLE_SPLIT_RE.split(rest, maxsplit=1)[0]
            cur = {
                "id": head.group(1),
                "section": section,
                "checked": m.group(2) != " ",
                "tags": _clean(tags, 120),
                "title": _clean(title.replace("~~", ""), 120),
                "withdrawn": title.startswith("~~"),
                "last_date": max(DATE_RE.findall(m.group(3)), default=""),
                "tags_say_done": bool(DONE_HINT_RE.search(tags)),
                "explain": "",
                "done_when": "",
            }
            est = re.search(r"est=(\S+)", m.group(3))
            if est:
                cur["est"] = est.group(1)
            rows.append(cur)
            continue
        if cur is not None:
            s = line.strip()
            if s.startswith("↳ explain:") and not cur["explain"]:
                cur["explain"] = _clean(s[len("↳ explain:"):], 300)
            elif s.startswith("↳ done when:") and not cur["done_when"]:
                cur["done_when"] = _clean(s[len("↳ done when:"):], 200)
    return rows


def _frontmatter_updated(text):
    m = re.search(r"^updated:\s*(\S+)", text, re.M) or re.search(r"^date:\s*(\S+)", text, re.M)
    if not m:
        return ""
    day = DATE_RE.search(m.group(1))  # "2026-10-12-r232-in-review" -> "2026-10-12"
    return day.group(0) if day else m.group(1)


def _git(repo, *args):
    try:
        out = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=20)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def extract(args):
    text = Path(args.roadmap).read_text(encoding="utf-8")
    rows = parse_roadmap(text)
    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()
    cutoff = (today - dt.timedelta(days=args.days)).isoformat()

    def slim(r, *keys):
        return {k: r[k] for k in ("id", "title", *keys) if r.get(k) not in ("", False, None)}

    detail = ("tags", "explain", "done_when", "est", "last_date", "tags_say_done")
    active = [slim(r, "section", *detail) for r in rows
              if not r["checked"] and not r["withdrawn"] and r["section"] in ("now", "next")]
    later = [slim(r, "section") for r in rows
             if not r["checked"] and not r["withdrawn"] and r["section"] in ("later", "other")]
    shipped = [r for r in rows if r["checked"] and not r["withdrawn"]]
    recent = [r for r in shipped if r["last_date"] >= cutoff]
    if not recent:  # undated Done rows: the section is newest-first by convention
        recent = [r for r in shipped if r["section"] == "done"][:3]

    counts = {}
    for r in rows:
        key = r["section"] + ("_checked" if r["checked"] else "_open")
        counts[key] = counts.get(key, 0) + 1

    facts = {
        "generated": today.isoformat(),
        "roadmap": {"path": args.roadmap, "updated": _frontmatter_updated(text),
                    "bytes": len(text.encode("utf-8")), "rows": len(rows)},
        "counts": counts,
        "active": active,
        "later": later,
        "recent_done": [slim(r, "last_date", "explain") for r in recent],
        "checked_in_now": [r["id"] for r in rows if r["checked"] and r["section"] == "now"],
        "tags_say_done_unchecked": [r["id"] for r in rows if not r["checked"] and r["tags_say_done"]],
    }
    if args.repo:
        facts["head"] = _git(args.repo, "rev-parse", "--short", "HEAD")
    if args.kg and Path(args.kg).is_file():
        kg = json.loads(Path(args.kg).read_text(encoding="utf-8"))
        proj = kg.get("project", {})
        info = {
            "analyzed_at": str(proj.get("analyzedAt", ""))[:10],
            "commit": proj.get("gitCommitHash", ""),
            "description": proj.get("description", ""),
            "layers": [{"name": l.get("name", ""), "description": _clean(str(l.get("description", "")), 160),
                        "files": len(l.get("nodeIds", []))} for l in kg.get("layers", [])],
            "tour": [{"step": t.get("order"), "title": t.get("title", ""),
                      "description": _clean(str(t.get("description", "")), 160)}
                     for t in kg.get("tour", [])],
        }
        if args.repo and info["commit"]:
            behind = _git(args.repo, "rev-list", "--count", f"{info['commit']}..HEAD")
            if behind.isdigit():
                info["commits_behind"] = int(behind)
        facts["kg"] = info
    json.dump(facts, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")
    return 0


# ----------------------------------------------------------------- render ---

CSS = """
* { box-sizing: border-box; }
body { margin: 0; background: #f5f7fb; color: #111827; font-size: 14px; line-height: 1.65;
       font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans TC", sans-serif; }
main { max-width: 760px; margin: 0 auto; background: #fff; min-height: 100vh; padding: 24px 22px 32px; }
nav { font-size: 12px; margin-bottom: 14px; color: #94a3b8; }
nav a { color: #2563eb; text-decoration: none; } nav b { color: #111827; }
h1 { font-size: 20px; margin: 0 0 2px; }
.meta { color: #94a3b8; font-size: 12px; }
h2 { font-size: 14px; color: #334155; margin: 22px 0 6px; }
code { background: #eef2f7; padding: 0 4px; border-radius: 3px; font-size: 12px; }
.rid { display: inline-block; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px;
       color: #64748b; background: #f1f5f9; border: 1px solid #e2e8f0; border-radius: 4px; padding: 0 5px;
       line-height: 1.5; white-space: nowrap; margin-left: 3px; cursor: help; }
.lead { background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; padding: 10px 12px; margin-top: 12px; color: #14532d; font-size: 15px; }
.done { list-style: none; padding: 0; margin: 0; }
.done li { padding: 6px 0 6px 20px; position: relative; border-bottom: 1px dashed #eef2f7; }
.done li::before { content: "✓"; position: absolute; left: 2px; color: #10b981; font-weight: 800; }
.stat { font-size: 11px; padding: 0 7px; border-radius: 999px; border: 1px solid; margin-left: 4px; white-space: nowrap; font-weight: 700; }
.stat.ok { color: #047857; background: #ecfdf5; border-color: #6ee7b7; }
.stat.wait { color: #b45309; background: #fffbeb; border-color: #fcd34d; }
.theme { border: 1px solid #e2e8f0; border-radius: 8px; padding: 10px 12px; margin-top: 8px;
         display: grid; grid-template-columns: 1fr 132px; gap: 12px; align-items: center; }
.theme .tn { font-weight: 700; font-size: 15px; }
.theme .why { color: #475569; margin-top: 2px; }
.theme .ids { margin-top: 6px; }
.stuck { font-size: 12px; color: #b91c1c; font-weight: 700; margin-left: 6px; }
.hill svg { width: 128px; height: 38px; display: block; }
.hill .hl { font-size: 11px; color: #64748b; text-align: center; }
.ask { border: 1px solid #fca5a5; background: #fef2f2; border-radius: 8px; padding: 8px 12px; margin-top: 6px; }
.empty { color: #94a3b8; font-size: 13px; }
.later span { display: inline-block; border: 1px dashed #cbd5e1; border-radius: 999px; padding: 1px 10px; margin: 4px 4px 0 0; color: #475569; }
.shop { display: grid; grid-template-columns: repeat(auto-fit, minmax(118px, 1fr)); gap: 10px; margin-top: 14px; }
.stall { border: 1.5px solid #cbd5e1; border-radius: 8px; padding: 12px 8px 8px; text-align: center; position: relative; }
.stall .no { position: absolute; top: -9px; left: 50%; transform: translateX(-50%); background: #0ea5e9; color: #fff;
             font-size: 10px; font-weight: 700; width: 18px; height: 18px; border-radius: 50%; line-height: 18px; }
.stall .n { font-weight: 700; }
.stall .r { font-size: 12px; color: #64748b; margin-top: 2px; line-height: 1.45; }
.stall .real { font-size: 10px; color: #94a3b8; margin-top: 4px; font-family: ui-monospace, Menlo, monospace; }
.stall.hot { border-color: #f97316; background: #fff7ed; }
.stall.hot::after { content: "整修中"; position: absolute; top: -9px; right: -4px; background: #f97316; color: #fff;
                    font-size: 10px; padding: 0 6px; border-radius: 999px; }
.side { margin-top: 10px; border: 1.5px dashed #cbd5e1; border-radius: 8px; padding: 6px 10px; font-size: 13px; color: #475569; }
.steps { margin: 6px 0 0; padding: 0; list-style: none; counter-reset: s; }
.steps li { counter-increment: s; position: relative; padding: 6px 0 6px 24px; border-left: 2px solid #e0f2fe; margin-left: 10px; }
.steps li::before { content: counter(s); position: absolute; left: -11px; top: 7px; width: 20px; height: 20px; border-radius: 50%;
                    background: #0ea5e9; color: #fff; font-size: 11px; font-weight: 700; display: flex; align-items: center; justify-content: center; }
.src { font-size: 11px; color: #94a3b8; margin-left: 4px; white-space: nowrap; }
.warn { margin-top: 12px; font-size: 12px; color: #b45309; background: #fffbeb; border: 1px solid #fde68a; border-radius: 6px; padding: 6px 10px; }
.foot { margin-top: 26px; padding-top: 10px; border-top: 1px dashed #e2e8f0; font-size: 11px; color: #94a3b8; }
@media (max-width: 560px) { .theme { grid-template-columns: 1fr; } main { padding: 18px 14px; } }
"""

HILL = {
    "uphill": (34, 16, "#94a3b8", "上坡 · 還在想怎麼做"),
    "crest": (78, 13, "#f59e0b", "過山頭 · 執行中"),
    "downhill": (106, 23, "#10b981", "下坡 · 收尾中"),
}


def _text(s):
    """Escape, then allow `code` and **bold** only."""
    s = html.escape(str(s or ""))
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)


def _cited(brief, arch):
    ids = []
    for key in ("done", "themes", "asks"):
        for item in brief.get(key, []):
            ids += item.get("ids", []) + item.get("stuck", [])
    if arch:
        ids += (arch.get("side") or {}).get("ids", [])
    return ids


def _page(title, nav, body, foot):
    return (f'<!DOCTYPE html>\n<html lang="zh-Hant">\n<head>\n<meta charset="utf-8">\n'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f"<title>{html.escape(title)}</title>\n<style>{CSS}</style>\n</head>\n<body>\n<main>\n"
            f"<nav>{nav}</nav>\n{body}\n<div class=\"foot\">{foot}</div>\n</main>\n</body>\n</html>\n")


def _footer(facts, extra=""):
    kg = facts.get("kg") or {}
    parts = [f"{facts.get('generated', '')} 產生", f"ROADMAP 更新於 {facts['roadmap'].get('updated') or '?'}"]
    if facts.get("head"):
        parts.append(f"程式 {facts['head']}")
    if kg.get("analyzed_at"):
        behind = kg.get("commits_behind")
        parts.append(f"KG {kg['analyzed_at']}" + (f"（落後 {behind} 個 commit）" if behind else ""))
    return (html.escape(" · ".join(parts)) + "<br>這頁是給人看的導覽，不是驗收。細節請問 Claude（ROADMAP.md、spec）。"
            + extra)


def render_brief(project, facts, brief, index, has_arch):
    def chips(ids):
        out = []
        for i in ids:
            r = index[i]
            tip = r["title"] + (f" · done when: {r['done_when']}" if r["done_when"] else "")
            out.append(f'<span class="rid" title="{html.escape(tip)}">{html.escape(i)}</span>')
        return "".join(out)

    done = "".join(
        f"<li>{_text(d.get('text'))}"
        + (f' <span class="stat {"wait" if re.search("待|等|review", d["status"]) else "ok"}">'
           f'{html.escape(d["status"])}</span>' if d.get("status") else "")
        + f"{chips(d.get('ids', []))}</li>" for d in brief.get("done", []))
    themes = []
    for t in brief.get("themes", []):
        x, y, color, label = HILL.get(t.get("hill"), HILL["crest"])
        stuck = "".join(f'<span class="stuck">卡住：{html.escape(i)}</span>' for i in t.get("stuck", []))
        themes.append(
            f'<div class="theme"><div><div class="tn">{_text(t.get("name"))}</div>'
            f'<div class="why">{_text(t.get("why"))}</div><div class="ids">{chips(t.get("ids", []))}{stuck}</div></div>'
            f'<div class="hill"><svg viewBox="0 0 128 38"><path d="M2 35 Q64 -11 126 35" fill="none" stroke="#cbd5e1" stroke-width="2"/>'
            f'<line x1="64" y1="6" x2="64" y2="37" stroke="#e2e8f0" stroke-dasharray="2 2"/>'
            f'<circle cx="{x}" cy="{y}" r="5" fill="{color}"/></svg><div class="hl">{label}</div></div></div>')
    asks = "".join(f'<div class="ask">{_text(a.get("text"))}{chips(a.get("ids", []))}</div>'
                   for a in brief.get("asks", []))
    later = "".join(f"<span>{_text(x)}</span>" for x in brief.get("later", []))

    body = (f"<h1>{html.escape(project)} 這兩週</h1>"
            f'<div class="meta">灰色小標籤是出處，滑上去看 ROADMAP 原文</div>'
            f'<div class="lead"><strong>一句話：</strong>{_text(brief["headline"])}</div>'
            f"<h2>✅ 做完了</h2>" + (f'<ul class="done">{done}</ul>' if done else '<div class="empty">這段期間沒有完成的項目。</div>')
            + "<h2>🔨 正在做</h2>" + ("".join(themes) or '<div class="empty">目前沒有進行中的項目。</div>')
            + "<h2>✋ 需要你決定</h2>" + (asks or '<div class="empty">目前沒有。</div>')
            + ("<h2>🕐 之後</h2>" f'<div class="later">{later}</div>' if later else ""))

    stale_now, unchecked = facts.get("checked_in_now", []), facts.get("tags_say_done_unchecked", [])
    extra = ""
    if stale_now or unchecked:
        def few(ids):
            return "、".join(ids[:6]) + ("…" if len(ids) > 6 else "")
        bits = []
        if stale_now:
            bits.append(f"{len(stale_now)} 列已打勾卻還在 Now（{few(stale_now)}）")
        if unchecked:
            bits.append(f"{len(unchecked)} 列括號寫 merged / shipped 卻沒打勾（{few(unchecked)}）")
        extra = "<br>狀態有疑問：" + html.escape("；".join(bits)) + " → 跑 <code>/ship-roadmap</code> 整理。"
    nav = "<b>Roadmap</b>" + (' · <a href="architecture.html">架構</a>' if has_arch else "")
    return _page(f"{project} 這兩週", nav, body, _footer(facts, extra))


def render_arch(project, facts, brief, arch):
    hot = {}
    for t in brief.get("themes", []):
        if isinstance(t.get("stall"), int):
            hot.setdefault(t["stall"], []).append(t.get("name", ""))
    stalls = "".join(
        f'<div class="stall{" hot" if n in hot else ""}"><span class="no">{n}</span>'
        f'<div class="n">{_text(s.get("name"))}</div><div class="r">{_text(s.get("role"))}</div>'
        f'<div class="real">{_text(s.get("real"))}</div></div>'
        for n, s in enumerate(arch.get("stalls", []), 1))
    side = arch.get("side") or {}
    side_html = ""
    if side.get("text"):
        ids = "".join(f'<span class="rid">{html.escape(i)}</span>' for i in side.get("ids", []))
        side_html = f'<div class="side">{_text(side["text"])}{ids}</div>'
    steps = "".join(
        f"<li>{_text(s.get('text'))}" + (f'<span class="src">tour {html.escape(str(s["tour"]))}</span>' if s.get("tour") else "")
        + "</li>" for s in arch.get("steps", []))
    names = [s.get("name", "") for s in arch.get("stalls", [])]
    repair = "".join(
        f"<li>{_text(names[n - 1] if 0 < n <= len(names) else '?')}：{_text('、'.join(ts))}</li>"
        for n, ts in sorted(hot.items()))
    kg = facts.get("kg") or {}
    warn = ""
    if (kg.get("commits_behind") or 0) > 50:
        warn = (f'<div class="warn">KG 是 {html.escape(kg.get("analyzed_at", ""))} 的版本，落後 {kg["commits_behind"]} 個 commit。'
                "之後新增的功能可能還沒畫進來，跑 <code>/understand</code> 後再 <code>/ship-brief --refresh-arch</code>。</div>")
    body = (f"<h1>{_text(arch.get('title') or project + ' 的架構')}</h1>"
            f'<div class="meta">{_text(arch.get("basis", ""))}</div>'
            f'<div class="shop">{stalls}</div>{side_html}'
            + (f"<h2>{_text(arch.get('steps_title') or '跟一則訊息走一遍')}</h2><ol class=\"steps\">{steps}</ol>" if steps else "")
            + (f'<h2>最近在整修的地方</h2><ul>{repair}</ul>' if repair else "") + warn)
    return _page(f"{project} 架構", '<a href="brief.html">Roadmap</a> · <b>架構</b>', body, _footer(facts))


def render(args):
    index = {r["id"]: r for r in parse_roadmap(Path(args.roadmap).read_text(encoding="utf-8"))}
    facts = json.loads(Path(args.facts).read_text(encoding="utf-8"))
    brief = json.loads(Path(args.brief).read_text(encoding="utf-8"))
    has_arch = bool(args.arch) and Path(args.arch).is_file()  # absent file = no architecture page
    arch = json.loads(Path(args.arch).read_text(encoding="utf-8")) if has_arch else None
    if not str(brief.get("headline", "")).strip():
        print("ERROR: brief JSON has no headline", file=sys.stderr)
        return 1
    unknown = sorted(set(_cited(brief, arch)) - index.keys())
    if unknown:
        print("ERROR: cited IDs not found in ROADMAP (fix the JSON, nothing written): "
              + ", ".join(unknown), file=sys.stderr)
        return 1
    project = args.project or Path(args.roadmap).resolve().parent.name
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "brief.html").write_text(render_brief(project, facts, brief, index, bool(arch)), encoding="utf-8")
    print(out / "brief.html")
    if arch:
        (out / "architecture.html").write_text(render_arch(project, facts, brief, arch), encoding="utf-8")
        print(out / "architecture.html")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("roadmap")
    e.add_argument("--kg")
    e.add_argument("--repo")
    e.add_argument("--days", type=int, default=14)
    e.add_argument("--today")
    r = sub.add_parser("render")
    r.add_argument("--roadmap", required=True)
    r.add_argument("--facts", required=True)
    r.add_argument("--brief", required=True)
    r.add_argument("--arch")
    r.add_argument("--out", required=True)
    r.add_argument("--project")
    args = p.parse_args(argv)
    return extract(args) if args.cmd == "extract" else render(args)


if __name__ == "__main__":
    sys.exit(main())
