"""Render a diagram spec as deterministic, offline Cocoon-style HTML (Python 3.9)."""
import html
import json
import re
import sys
from pathlib import Path
from typing import Optional

KINDS = {
    "fe": ("rgba(8,51,68,0.4)", "#22d3ee"),
    "be": ("rgba(6,78,59,0.4)", "#34d399"),
    "db": ("rgba(76,29,149,0.4)", "#a78bfa"),
    "bus": ("rgba(251,146,60,0.3)", "#fb923c"),
    "ext": ("rgba(30,41,59,0.5)", "#94a3b8"),
    "sec": ("rgba(136,19,55,0.4)", "#fb7185"),
    "cloud": ("rgba(120,53,15,0.3)", "#fbbf24"),
}
TONES = {"body": "#cbd5e1", "cond": "#fcd34d", "warn": "#fb7185", "muted": "#94a3b8"}
SHAPES = ("box", "pill")
CSS = """
*{box-sizing:border-box}body{margin:0;background:#020617;color:#cbd5e1;
font-family:'JetBrains Mono',SFMono-Regular,Menlo,'PingFang TC',monospace;font-size:13px}
main{max-width:1440px;margin:auto;padding:40px}h1{font-size:26px;color:#f8fafc}
h2{font-size:18px;color:#f8fafc}.sub,footer{color:#94a3b8;line-height:1.8}
section{margin:28px 0}svg{width:100%;height:auto;display:block}
.legend{display:flex;gap:20px;flex-wrap:wrap;margin:12px 0;font-size:11px}
.route{border-top:1px solid #1e293b;padding-top:16px}.steps{line-height:1.8;padding-left:30px}
.steps li{margin:12px 0}.steps span{display:block}.cond{width:100%;border-collapse:collapse;
margin:32px 0;line-height:1.8}th,td{border:1px solid #1e293b;padding:12px;text-align:left;
vertical-align:top;overflow-wrap:anywhere}th{color:#94a3b8}
.cond th:nth-child(1){width:17%}.cond th:nth-child(2){width:20%}.cond th:nth-child(4){width:24%}
.cond td:nth-child(1){overflow-wrap:normal;color:#f8fafc}.cond td:nth-child(4){font-size:11.5px;color:#94a3b8}.cond tr.warn td{color:#fb7185}tr.warn{color:#fb7185}
footer{border-top:1px solid #1e293b;padding-top:20px}a{color:#22d3ee}
.pack a{display:block;border:1px solid #1e293b;padding:20px;margin:16px 0;text-decoration:none}
.pack span{display:block;color:#94a3b8;margin-top:8px}
.pan-hint{display:none}
@media (max-width:700px){main{padding:16px}h1{font-size:20px}.sub{font-size:12px;overflow-wrap:anywhere}
.pan{overflow-x:auto;border:1px solid #1e293b;border-radius:8px}
.pan svg{width:calc(var(--w)*0.8);max-width:none}.pan-hint{display:block;color:#94a3b8;font-size:12px;margin:6px 0 8px}
table.cond,.cond thead,.cond tbody,.cond tr,.cond td{display:block}.cond thead{display:none}
.cond tr{border:1px solid #1e293b;border-radius:8px;margin:12px 0;padding:10px 12px}.cond td{border:0;padding:3px 0}
.cond td:nth-child(1){font-size:15px;font-weight:700;overflow-wrap:anywhere}.cond td:nth-child(2)::before{content:"做什麼　";color:#64748b}
.cond td:nth-child(3)::before{content:"條件　";color:#64748b}.cond td:nth-child(4){font-size:11px;overflow-wrap:anywhere}}
"""


class SpecError(Exception):
    """An unreadable or invalid JSON spec."""


def text_width(s: str, size: float) -> float:
    return sum(1.0 if ord(c) > 0x2E80 else 0.62 for c in s) * size


def label_box(edge: dict) -> tuple:
    width = text_width(edge.get("label", ""), 10) + 10
    return edge["lx"] - width / 2, edge["ly"] - 8, width, 16


def load_spec(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as source:
            return json.load(source)
    except (OSError, ValueError, UnicodeError) as exc:
        raise SpecError("{}: {}".format(path, exc)) from exc


def esc(value) -> str:
    # Keep URLs readable as text without serializing external URL literals.
    return re.sub(r"(https?):(?=//)", r"\1&#58;", html.escape(str(value), quote=True), flags=re.I)


def attr(value) -> str:
    # Encode whitespace too: untrusted path text cannot resemble a new attribute.
    return "".join("&#{};".format(ord(c)) if c.isspace() else c for c in esc(value))


def svg_text(x, y, value, size=10, color="#cbd5e1", anchor="start", bold=False) -> str:
    weight = ' font-weight="700"' if bold else ""
    return ('<text x="{}" y="{}" font-size="{}"{} fill="{}" text-anchor="{}">{}</text>'
            .format(attr(x), attr(y), size, weight, attr(color), anchor, esc(value)))


def node_text(node: dict, accent: str) -> list:
    """Cocoon layout: a node with lines reads left-aligned; one without is centered."""
    x, y, nw, nh = (node[k] for k in ("x", "y", "w", "h"))
    out = []
    if node.get("lines"):
        cursor = y + 22
        out.append(svg_text(x + 14, cursor, node["title"], 13, "#f8fafc", bold=True))
        for field in ("sub", "port"):
            if node.get(field):
                cursor += 16
                out.append(svg_text(x + 14, cursor, node[field], 10, accent))
        cursor += 6
        for line in node["lines"]:
            cursor += 15
            out.append(svg_text(x + 14, cursor, line["text"], 10.5, TONES[line.get("tone", "body")]))
        return out
    extra = (1 if node.get("sub") else 0) + (1 if node.get("port") else 0)
    cx, cursor = x + nw / 2, y + nh / 2 + 4 - extra * 8
    out.append(svg_text(_num(cx), _num(cursor), node["title"], 13, "#f8fafc", "middle", bold=True))
    if node.get("sub"):
        cursor += 16
        out.append(svg_text(_num(cx), _num(cursor), node["sub"], 10, TONES["muted"], "middle"))
    if node.get("port"):
        cursor += 15
        out.append(svg_text(_num(cx), _num(cursor), node["port"], 10, accent, "middle"))
    return out


def _num(v):
    return int(v) if float(v).is_integer() else round(v, 1)


def render_svg(spec: dict, uid: str, route: Optional[dict] = None) -> str:
    w, h = spec["canvas"]["w"], spec["canvas"]["h"]
    for v in (w, h):
        # canvas.w reaches a style attribute: only a positive number may get there.
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not 0 < v < float("inf"):
            raise SpecError("canvas.w and canvas.h must be positive numbers")
    ident = attr(uid)
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {} {}" role="img" aria-label="{}" style="--w:{}px">'
             .format(attr(w), attr(h), attr(spec["title"]), attr(w)), '<defs>']
    parts.append('<pattern id="{}-grid" width="40" height="40" patternUnits="userSpaceOnUse">'
                 '<path d="M40 0 H0 V40" fill="none" stroke="#1e293b" stroke-width="0.5"/></pattern>'.format(ident))
    for name, color in (("arrow", "#64748b"), ("amber", "#fbbf24")):
        parts.append('<marker id="{}-{}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
                     'markerHeight="6" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 Z" fill="{}"/></marker>'
                     .format(ident, name, color))
    parts.extend(['</defs>', '<rect width="100%" height="100%" fill="#020617"/>',
                  '<rect width="100%" height="100%" fill="url(#{})"/>'.format(ident + '-grid')])
    for region in spec.get("regions", []):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", region["color"]):
            raise SpecError("region.color must be a six-digit hex color")
        parts.append('<rect x="{}" y="{}" width="{}" height="{}" rx="8" fill="none" stroke="{}" stroke-dasharray="8,4"/>'
                     .format(*(attr(region[k]) for k in ("x", "y", "w", "h")), attr(region["color"])))
        parts.append(svg_text(region["x"] + 12, region["y"] + 17, region["label"], color=region["color"]))
    for edge in spec["edges"]:
        key = edge["from"] + "->" + edge["to"]
        active = route is not None and key in route.get("edges", [])
        opacity = "0.2" if route is not None and not active else "1"
        color, weight, marker = ("#fbbf24", 2.2, "amber") if active else ("#64748b", 1.5, "arrow")
        # The arrow separator is fixed HTML text; each spec endpoint is escaped.
        data_key = attr(edge["from"]) + "->" + attr(edge["to"])
        parts.append('<g data-edge="{}" opacity="{}">'.format(data_key, opacity))
        arrow = ' marker-end="url(#{}-{})"'.format(ident, marker) if edge.get("arrow", True) else ""
        dash = ' stroke-dasharray="8,4"' if edge.get("dash", False) else ""
        parts.append('<path d="{}" fill="none" stroke="{}" stroke-width="{}"{}{}/>'
                     .format(attr(edge["path"]), color, weight, arrow, dash))
        if edge.get("label"):
            x, y, bw, bh = label_box(edge)
            parts.append('<rect x="{}" y="{}" width="{}" height="{}" rx="3" fill="#020617"/>'
                         .format(attr(x), attr(y), attr(bw), attr(bh)))
            parts.append(svg_text(edge["lx"], edge["ly"] + 3.5, edge["label"], color=color, anchor="middle"))
        parts.append('</g>')
    for node in spec["nodes"]:
        active = route is not None and node["id"] in route.get("nodes", [])
        opacity = "0.2" if route is not None and not active else "1"
        fill, stroke = KINDS[node["kind"]]
        if active:
            stroke = "#fbbf24"
        x, y, nw, nh = (node[k] for k in ("x", "y", "w", "h"))
        radius = nh / 2 if node.get("shape", "box") == "pill" else 6
        parts.append('<g data-node="{}" opacity="{}">'.format(attr(node["id"]), opacity))
        if node.get("src"):
            parts.append('<title>{}</title>'.format(esc(" / ".join(node["src"]))))
        rect = 'x="{}" y="{}" width="{}" height="{}" rx="{}"'.format(*(attr(v) for v in (x, y, nw, nh, radius)))
        parts.append('<rect {} fill="#0f172a"/>'.format(rect))
        dash = ' stroke-dasharray="8,4"' if node.get("dash", False) else ""
        parts.append('<rect {} fill="{}" stroke="{}" stroke-width="1.5"{}/>'.format(rect, fill, stroke, dash))
        parts.extend(node_text(node, KINDS[node["kind"]][1]))
        parts.append('</g>')
    if route is not None:
        for badge in route.get("badges", []):
            parts.append('<g class="badge"><circle cx="{}" cy="{}" r="11" fill="#fbbf24" stroke="#020617"/>{}</g>'
                         .format(attr(badge["x"]), attr(badge["y"]),
                                 svg_text(badge["x"], badge["y"] + 3.5, badge["n"], color="#020617", anchor="middle")))
    parts.append('</svg>')
    return "\n".join(parts)


def document(title: str, parts: list) -> str:
    return ('<!doctype html>\n<html lang="zh-Hant"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>{}</title><style>{}</style></head><body><main>\n{}\n</main></body></html>\n'
            .format(esc(title), CSS, "\n".join(parts)))


KIND_NAMES = {"fe": "前端", "be": "後端", "db": "資料庫", "bus": "佇列", "ext": "外部", "sec": "安全", "cloud": "雲端"}


def legend_items(spec: dict) -> list:
    """The spec's own legend, else the kinds its nodes use, in KINDS order."""
    if spec.get("legend"):
        return [(item["kind"], item["label"]) for item in spec["legend"]]
    used = {node["kind"] for node in spec["nodes"]}
    return [(k, KIND_NAMES[k]) for k in KINDS if k in used]


def pan(svg: str) -> str:
    """A diagram in a horizontally scrollable box; the hint shows only on phones."""
    return '<p class="pan-hint">← 左右滑動看整張圖 →</p><div class="pan">' + svg + '</div>'


def render_page(spec: dict) -> str:
    topic = spec["topic"]
    if not re.fullmatch(r"[a-z0-9-]+", topic):
        raise SpecError("invalid topic: " + topic)
    repo = spec["repo"]
    parts = ['<h1>{}</h1>'.format(esc(spec["title"])),
             '<p class="sub">{}</p>'.format(esc(" · ".join(filter(None, [spec.get("subtitle", ""), repo["name"], repo["commit"][:7]])))),
             '<section class="diagram">', pan(render_svg(spec, "{}-0".format(topic))), '</section>']
    parts.append('<div class="legend">' + "".join('<span style="color:{}">{}</span>'.format(KINDS[k][1], esc(label)) for k, label in legend_items(spec)) + '</div>')
    for i, route in enumerate(spec.get("routes", [])):
        parts.extend(['<section class="route">', '<h2>{}</h2>'.format(esc(route["name"])),
                      pan(render_svg(spec, "{}-r{}".format(topic, i), route)), '<ol class="steps">'])
        for step in route.get("steps", []):
            parts.append('<li>{}<span style="color:{}">{}</span></li>'.format(
                esc(step["title"]), TONES[step.get("tone", "body")], esc(step.get("note", ""))))
        parts.extend(['</ol>', '</section>'])
    titles = {n["id"]: n["title"] for n in spec["nodes"]}
    if spec.get("conditions"):
        parts.extend(['<table class="cond">', '<thead><tr><th>節點</th><th>做什麼</th><th>什麼條件走到這、離開時往哪</th><th>程式碼</th></tr></thead>', '<tbody>'])
        for row in spec["conditions"]:
            ids = row["node"] if isinstance(row["node"], list) else [row["node"]]
            node = " / ".join(titles.get(i, i) for i in ids)
            warning = row.get("warn", False)
            parts.append('<tr{}><td>{}{}</td><td>{}</td><td>{}</td><td>{}</td></tr>'.format(
                ' class="warn"' if warning else "", "⚠ " if warning else "", esc(node),
                esc(row["does"]), esc(row["when"]), esc(row["src"])))
        parts.extend(['</tbody>', '</table>'])
    parts.append('<footer>Commit {}</footer>'.format(esc(repo["commit"])))
    return document(spec["title"], parts)


def render_index(specs: list) -> str:
    repos = sorted({spec["repo"]["name"] for spec in specs})
    title = " · ".join(["架構圖包"] + repos)
    parts = ['<h1>{}</h1>'.format(esc(title)), '<nav class="pack">']
    for spec in sorted(specs, key=lambda s: (s["topic"] != "overview", s["topic"])):
        if not re.fullmatch(r"[a-z0-9-]+", spec["topic"]):
            raise SpecError("invalid topic: " + spec["topic"])
        parts.append('<a href="{}.html">{}<span>{}</span></a>'.format(
            attr(spec["topic"]), esc(spec["title"]), esc(spec.get("subtitle", ""))))
    parts.append('</nav>')
    return document(title, parts)


def main(argv: list) -> int:
    if len(argv) != 3 or argv[0] not in ("page", "index"):
        print("usage: render.py page <spec.json> <out.html> | index <dir> <out.html>", file=sys.stderr)
        return 2
    try:
        if argv[0] == "page":
            page = render_page(load_spec(argv[1]))
        else:
            directory = Path(argv[1])
            if not directory.is_dir():
                raise SpecError("{}: not a directory".format(directory))
            page = render_index([load_spec(str(p)) for p in sorted(directory.glob("*.json"))])
        Path(argv[2]).write_text(page, encoding="utf-8")
    except (SpecError, OSError, KeyError, TypeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
