"""Validate diagram structure and geometry without third-party dependencies."""
import argparse
import ast
import contextlib
import io
import math
import os
import re
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render import KINDS, TONES, SHAPES, PAGES, text_width, label_box, load_spec, SpecError


def schema_errors(spec: dict) -> list:
    errors = []

    def require(ok, detail):
        if not ok:
            errors.append("check: schema: " + detail)

    def number(value):
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)

    def fields(obj, names, where):
        require(isinstance(obj, dict), where + " must be an object")
        if not isinstance(obj, dict):
            return False
        for name in names:
            require(name in obj, where + "." + name + " is required")
        return True

    def strings(obj, names, where):
        for name in names:
            if name in obj:
                require(isinstance(obj[name], str), where + "." + name + " must be text")

    def geometry(obj, where):
        for name in ("x", "y", "w", "h"):
            require(number(obj.get(name)), where + "." + name + " must be a finite number")
        for name in ("w", "h"):
            if number(obj.get(name)):
                require(obj[name] > 0, where + "." + name + " must be positive")

    def choice(obj, name, choices, where):
        if name in obj:
            require(isinstance(obj[name], str) and obj[name] in choices, where + "." + name + " is unknown")

    def array(name):
        value = spec.get(name, [])
        require(isinstance(value, list), name + " must be a list")
        return value if isinstance(value, list) else []

    if not fields(spec, ("topic", "title", "repo"), "spec"):
        return errors
    choice(spec, "page", PAGES, "spec")
    strings(spec, ("topic", "title", "subtitle"), "spec")
    require(isinstance(spec.get("topic"), str) and re.fullmatch(r"[a-z0-9-]+", spec.get("topic", "")), "invalid topic")
    repo = spec.get("repo")
    if fields(repo, ("name", "commit"), "repo"):
        strings(repo, ("name", "commit"), "repo")
        require(isinstance(repo.get("commit"), str) and re.fullmatch(r"[0-9a-f]{7,40}", repo.get("commit", "")), "invalid repo.commit")
    page = spec.get("page", "diagram")
    if page == "table":
        fields(spec, ("columns", "rows"), "spec")
        for column in array("columns"):
            if fields(column, ("key", "label"), "column"):
                strings(column, ("key", "label"), "column")
        for row in array("rows"):
            if not fields(row, ("id", "cells", "src"), "row"):
                continue
            strings(row, ("id", "group"), "row")
            require(isinstance(row.get("id"), str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", row["id"]), "row.id is invalid")
            cells = row.get("cells")
            require(isinstance(cells, dict) and all(isinstance(v, str) for v in cells.values()), "row.cells must be an object of text")
            src = row.get("src")
            require(isinstance(src, str) or isinstance(src, list) and all(isinstance(v, str) for v in src), "row.src must be text or a list of text")
            if "warn" in row:
                require(isinstance(row["warn"], bool), "row.warn must be boolean")
        if "registry" in spec and fields(spec["registry"], ("file", "call"), "registry"):
            strings(spec["registry"], ("file", "call", "key"), "registry")
        return errors
    if page == "cards":
        fields(spec, ("cards",), "spec")
        for card in array("cards"):
            if not fields(card, ("id", "title", "does", "src"), "card"):
                continue
            strings(card, ("id", "title", "does", "entry", "data"), "card")
            require(isinstance(card.get("id"), str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", card["id"]), "card.id is invalid")
            require(isinstance(card.get("src"), list) and all(isinstance(v, str) for v in card["src"]), "card.src must be a list of text")
            for key, pattern in (("topics", r"[a-z0-9-]+"), ("jobs", r"[A-Za-z0-9_.:-]+")):
                value = card.get(key, [])
                require(isinstance(value, list) and all(isinstance(v, str) and re.fullmatch(pattern, v) for v in value), "card." + key + " must be a list of ids")
        return errors
    if page == "seams":
        fields(spec, ("systems",), "spec")
        exclude = spec.get("exclude", [])
        require(isinstance(exclude, list) and all(isinstance(v, str) for v in exclude), "exclude must be a list of text")
        for system in array("systems"):
            if not fields(system, ("id", "title", "verdict", "summary", "change", "probes", "adapters", "touchpoints"), "system"):
                continue
            strings(system, ("id", "title", "verdict", "summary"), "system")
            require(isinstance(system.get("id"), str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", system["id"]), "system.id is invalid")
            choice(system, "verdict", ("easy", "medium", "hard"), "system")
            for key in ("change", "adapters"):
                value = system.get(key)
                require(isinstance(value, list) and all(isinstance(v, str) for v in value), "system." + key + " must be a list of text")
            probes = system.get("probes")
            require(isinstance(probes, list) and bool(probes), "system.probes must be a non-empty list")
            for probe in probes if isinstance(probes, list) else []:
                if fields(probe, ("kind", "pattern"), "probe"):
                    strings(probe, ("kind", "pattern"), "probe")
                    choice(probe, "kind", ("import", "text"), "probe")
                    if probe.get("kind") == "text" and isinstance(probe.get("pattern"), str):
                        try:
                            re.compile(probe["pattern"])
                        except (re.error, OverflowError):
                            require(False, "probe.pattern must be a valid regex")
            points = system.get("touchpoints")
            require(isinstance(points, list), "system.touchpoints must be a list")
            for point in points if isinstance(points, list) else []:
                if fields(point, ("file", "lines", "adapter"), "touchpoint"):
                    strings(point, ("file", "note"), "touchpoint")
                    lines = point.get("lines")
                    require(isinstance(lines, list) and all(type(line) is int for line in lines), "touchpoint.lines must be a list of integers")
                    require(isinstance(point.get("adapter"), bool), "touchpoint.adapter must be boolean")
        return errors
    if page == "contract":
        fields(spec, ("graph", "nodes", "declared", "scenarios"), "spec")
        graph = spec.get("graph")
        if fields(graph, ("file", "state", "roots"), "graph"):
            strings(graph, ("file", "state"), "graph")
            file = graph.get("file")
            require(isinstance(file, str) and bool(file) and not Path(file).is_absolute() and
                    ".." not in Path(file).parts, "graph.file must be repo-relative")
            roots = graph.get("roots")
            require(isinstance(roots, list) and bool(roots) and all(
                isinstance(root, str) and bool(root) and not Path(root).is_absolute() and
                ".." not in Path(root).parts for root in roots), "graph.roots must be a list of repo-relative directories")
        for node in array("nodes"):
            if not fields(node, ("id", "kind", "file", "line", "reads", "writes", "partial", "resolved"), "node"):
                continue
            strings(node, ("id", "file", "note", "verdict"), "node")
            require(isinstance(node.get("id"), str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", node["id"]), "node.id is invalid")
            require(type(node.get("line")) is int and node["line"] >= 0, "node.line must be a non-negative integer")
            require(isinstance(node.get("resolved"), bool), "node.resolved must be boolean")
            choice(node, "kind", ("node", "router"), "node")
            choice(node, "verdict", ("easy", "medium", "hard"), "node")
            for key in ("reads", "writes", "partial"):
                value = node.get(key)
                require(isinstance(value, list) and all(isinstance(v, str) for v in value), "node." + key + " must be a list of text")
        declared = spec.get("declared")
        require(isinstance(declared, list) and all(isinstance(v, str) for v in declared), "declared must be a list of text")
        for scenario in array("scenarios"):
            if fields(scenario, ("title", "nodes", "summary"), "scenario"):
                strings(scenario, ("title", "summary"), "scenario")
                value = scenario.get("nodes")
                require(isinstance(value, list) and all(isinstance(v, str) for v in value), "scenario.nodes must be a list of ids")
        return errors
    if page != "diagram":
        return errors
    fields(spec, ("canvas", "nodes", "edges"), "spec")
    canvas = spec.get("canvas")
    if fields(canvas, ("w", "h"), "canvas"):
        for name in ("w", "h"):
            require(number(canvas.get(name)) and canvas[name] > 0, "canvas." + name + " must be positive")
    for i, node in enumerate(array("nodes")):
        where = "nodes[{}]".format(i)
        if not fields(node, ("id", "x", "y", "w", "h", "kind", "title"), where):
            continue
        strings(node, ("id", "title", "sub", "port", "graph_id"), where)
        require(isinstance(node.get("id"), str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", node.get("id", "")), where + ".id is invalid")
        geometry(node, where)
        choice(node, "kind", KINDS, where)
        choice(node, "shape", SHAPES, where)
        lines = node.get("lines", [])
        require(isinstance(lines, list), where + ".lines must be a list")
        for line in lines if isinstance(lines, list) else []:
            if fields(line, ("text",), where + ".lines"):
                strings(line, ("text",), where + ".lines")
                choice(line, "tone", TONES, where + ".lines")
        if "src" in node:
            require(isinstance(node["src"], list) and all(isinstance(s, str) for s in node["src"]), where + ".src must be a list of text")
        if "dash" in node:
            require(isinstance(node["dash"], bool), where + ".dash must be boolean")
    for i, edge in enumerate(array("edges")):
        where = "edges[{}]".format(i)
        if not fields(edge, ("from", "to", "path"), where):
            continue
        strings(edge, ("from", "to", "path", "label"), where)
        require(isinstance(edge.get("path"), str) and re.fullmatch(r"[MLHVCQZmlhvcqz0-9 .,-]+", edge.get("path", "")), where + ".path is invalid")
        if edge.get("label"):
            for name in ("lx", "ly"):
                require(number(edge.get(name)), where + "." + name + " must be a finite number")
        for name in ("dash", "arrow"):
            if name in edge:
                require(isinstance(edge[name], bool), where + "." + name + " must be boolean")
    for region in array("regions"):
        if fields(region, ("x", "y", "w", "h", "color", "label"), "region"):
            geometry(region, "region")
            strings(region, ("color", "label"), "region")
            require(isinstance(region.get("color"), str) and re.fullmatch(r"#[0-9a-fA-F]{6}", region["color"]),
                    "region.color must be a six-digit hex color")
    for item in array("legend"):
        if fields(item, ("kind", "label"), "legend"):
            strings(item, ("kind", "label"), "legend")
            require(item.get("kind") in KINDS, "legend.kind is unknown: {}".format(item.get("kind")))
    for route in array("routes"):
        if not fields(route, ("name", "nodes", "edges"), "route"):
            continue
        strings(route, ("name",), "route")
        for name in ("nodes", "edges"):
            require(isinstance(route.get(name), list) and all(isinstance(v, str) for v in route[name]), "route." + name + " must be a list of text")
        badges = route.get("badges", [])
        require(isinstance(badges, list), "route.badges must be a list")
        for badge in badges if isinstance(badges, list) else []:
            if fields(badge, ("n", "x", "y"), "badge"):
                for name in ("n", "x", "y"):
                    require(number(badge.get(name)), "badge." + name + " must be a finite number")
        steps = route.get("steps", [])
        require(isinstance(steps, list), "route.steps must be a list")
        for step in steps if isinstance(steps, list) else []:
            if fields(step, ("title",), "step"):
                strings(step, ("title", "note"), "step")
                choice(step, "tone", TONES, "step")
    for condition in array("conditions"):
        if not fields(condition, ("node", "does", "when", "src"), "condition"):
            continue
        strings(condition, ("does", "when", "src"), "condition")
        ids = condition.get("node")
        require(isinstance(ids, str) or (isinstance(ids, list) and all(isinstance(v, str) for v in ids)), "condition.node must be an id or list of ids")
        if "warn" in condition:
            require(isinstance(condition["warn"], bool), "condition.warn must be boolean")
    if "langgraph" in spec and fields(spec["langgraph"], ("file",), "langgraph"):
        strings(spec["langgraph"], ("file",), "langgraph")
    return errors


def intersects(a: tuple, b: tuple) -> bool:
    return (max(a[0], b[0]) < min(a[0] + a[2], b[0] + b[2]) and
            max(a[1], b[1]) < min(a[1] + a[3], b[1] + b[3]))


def extract_graph(path: str) -> tuple:
    tree = ast.parse(Path(path).read_text(encoding="utf-8"), filename=str(path))
    nodes, edges, unresolved = set(), set(), []

    def name(expr):
        if isinstance(expr, ast.Constant) and isinstance(expr.value, str):
            return expr.value
        if isinstance(expr, ast.Name) and expr.id in ("START", "END"):
            return expr.id
        return None

    for call in ast.walk(tree):
        if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Attribute) or not call.args:
            continue
        method = call.func.attr
        src = name(call.args[0])
        if src is None:
            continue
        if method == "add_node":
            nodes.add(src)
        elif method == "add_edge" and len(call.args) >= 2:
            dst = name(call.args[1])
            if dst is not None:
                edges.add((src, dst))
        elif method == "add_conditional_edges":
            mapping = call.args[2] if len(call.args) >= 3 else next(
                (kw.value for kw in call.keywords if kw.arg == "path_map"), None)
            if not isinstance(mapping, ast.Dict):
                unresolved.append(src)
                continue
            for value in mapping.values:
                dst = name(value)
                if dst is None:
                    unresolved.append(src)
                else:
                    edges.add((src, dst))
    return nodes, edges, unresolved


def extract_registry(path: str, call: str, key: str = "name") -> tuple:
    tree = ast.parse(Path(path).read_text(encoding="utf-8"), filename=str(path))
    names, unresolved = [], []
    calls = sorted((n for n in ast.walk(tree) if isinstance(n, ast.Call)), key=lambda n: (n.lineno, n.col_offset))
    for node in calls:
        func = node.func
        if not ((isinstance(func, ast.Name) and func.id == call) or
                (isinstance(func, ast.Attribute) and func.attr == call)):
            continue
        value = next((kw.value for kw in node.keywords if kw.arg == key), None)
        if isinstance(value, ast.Constant) and isinstance(value.value, str):
            names.append(value.value)
        else:
            unresolved.append(node.lineno)
    return names, unresolved


def check_spec(spec: dict, repo: Optional[str] = None, spec_dir: Optional[str] = None) -> list:
    findings = schema_errors(spec)
    if findings:
        return findings
    if spec.get("page") == "table":
        ids = set()
        for row in spec["rows"]:
            if row["id"] in ids:
                findings.append("check: id: duplicate row " + row["id"])
            ids.add(row["id"])
        if repo is not None and "registry" in spec:
            registry = spec["registry"]
            path = Path(repo) / registry["file"]
            if not path.is_file():
                findings.append("check: registry: file not found " + str(path))
            else:
                try:
                    names, unresolved = extract_registry(str(path), registry["call"], registry.get("key", "name"))
                except (OSError, UnicodeError, SyntaxError) as exc:
                    findings.append("check: registry: cannot parse {}: {}".format(path, exc))
                    return findings
                findings.extend("check: registry: missing row " + name for name in names if name not in ids)
                findings.extend("check: registry: unresolved name at line " + str(n) for n in unresolved)
        return findings
    if spec.get("page") == "cards":
        ids = set()
        for card in spec["cards"]:
            if card["id"] in ids:
                findings.append("check: id: duplicate card " + card["id"])
            ids.add(card["id"])
        if spec_dir is not None:
            try:
                jobs = load_spec(str(Path(spec_dir) / "jobs.json"))
            except SpecError:
                jobs = {}
            rows = jobs.get("rows", []) if isinstance(jobs, dict) else []
            job_ids = {row["id"] for row in rows if isinstance(row, dict) and isinstance(row.get("id"), str)} if isinstance(rows, list) else set()
            for card in spec["cards"]:
                for topic in card.get("topics", []):
                    if not (Path(spec_dir) / (topic + ".json")).is_file():
                        findings.append("check: link: missing topic " + topic)
                for job in card.get("jobs", []):
                    if job not in job_ids:
                        findings.append("check: link: missing job " + job)
        return findings
    if spec.get("page") == "seams":
        ids = set()
        for system in spec["systems"]:
            if system["id"] in ids:
                findings.append("check: id: duplicate system " + system["id"])
            ids.add(system["id"])
        if findings:
            return findings
        if repo is not None:
            from seams import scan
            try:
                # The scanner CLI owns parse warnings; a clean check is silent.
                with contextlib.redirect_stderr(io.StringIO()):
                    actual = scan(repo, spec["systems"], spec.get("exclude", []))
            except (OSError, UnicodeError, ValueError) as exc:
                return ["check: seams: cannot scan " + str(exc)]
            for system in spec["systems"]:
                recorded = {(point["file"], tuple(sorted(set(point["lines"]))), point["adapter"])
                            for point in system["touchpoints"]}
                current = {(point["file"], tuple(point["lines"]), point["adapter"])
                           for point in actual[system["id"]]}
                if recorded != current:
                    findings.append("check: seams: stale " + system["id"])
        return findings
    if spec.get("page") == "contract":
        ids = set()
        for node in spec["nodes"]:
            if node["id"] in ids:
                findings.append("check: id: duplicate node " + node["id"])
            ids.add(node["id"])
        for scenario in spec["scenarios"]:
            for node in scenario["nodes"]:
                if node not in ids:
                    findings.append("check: edge: unknown scenario node " + node)
        if repo is not None and not findings:
            from contract import scan
            try:
                actual = scan(repo, spec["graph"])
            except (OSError, UnicodeError, SyntaxError, ValueError) as exc:
                return ["check: contract: cannot scan " + str(exc)]
            computed = ("id", "kind", "file", "line", "reads", "writes", "partial", "resolved")
            recorded = [{key: node[key] for key in computed} for node in spec["nodes"]]
            if actual != {"nodes": recorded, "declared": spec["declared"]}:
                findings.append("check: contract: stale")
        return findings
    nodes, edges = spec["nodes"], spec["edges"]
    ids = set()
    for node in nodes:
        if node["id"] in ids:
            findings.append("check: id: duplicate node " + node["id"])
        ids.add(node["id"])
    for edge in edges:
        for name in ("from", "to"):
            if edge[name] not in ids:
                findings.append("check: edge: unknown node " + edge[name])
    edge_ids = {e["from"] + "->" + e["to"] for e in edges}
    for route in spec.get("routes", []):
        for node in route["nodes"]:
            if node not in ids:
                findings.append("check: edge: unknown route node " + node)
        for edge in route["edges"]:
            if edge not in edge_ids:
                findings.append("check: edge: unknown route edge " + edge)
    for row in spec.get("conditions", []):
        for node in row["node"] if isinstance(row["node"], list) else [row["node"]]:
            if node not in ids:
                findings.append("check: edge: unknown condition node " + node)
    boxes = [tuple(node[k] for k in ("x", "y", "w", "h")) for node in nodes]
    for node, (x, y, w, h) in zip(nodes, boxes):
        if x < 0 or y < 0 or x + w > spec["canvas"]["w"] or y + h > spec["canvas"]["h"]:
            findings.append("check: bounds: node " + node["id"])
    # ponytail: O(n²) pairs are enough for hand-drawn packs; spatial index if that grows.
    for i, box in enumerate(boxes):
        for j in range(i + 1, len(boxes)):
            if intersects(box, boxes[j]):
                findings.append("check: overlap: {} and {}".format(nodes[i]["id"], nodes[j]["id"]))
    labels = [(e, label_box(e)) for e in edges if e.get("label")]
    for i, (edge, box) in enumerate(labels):
        for node, node_box in zip(nodes, boxes):
            if intersects(box, node_box):
                findings.append("check: label: {}->{} on node {}".format(edge["from"], edge["to"], node["id"]))
        for other, other_box in labels[i + 1:]:
            if intersects(box, other_box):
                findings.append("check: label: {} and {}".format(edge["label"], other["label"]))
    for node in nodes:
        texts = [("title", node["title"], 13), ("sub", node.get("sub", ""), 10), ("port", node.get("port", ""), 10)]
        texts.extend(("line", line["text"], 10.5) for line in node.get("lines", []))
        for name, value, size in texts:
            if text_width(value, size) > node["w"] - 24:
                findings.append("check: fit: {} {} is too wide".format(node["id"], name))
    if repo is not None and spec.get("langgraph", {}).get("file"):
        path = Path(repo) / spec["langgraph"]["file"]
        if not path.is_file():
            findings.append("check: langgraph: file not found " + str(path))
        else:
            try:
                actual_nodes, actual_edges, unresolved = extract_graph(str(path))
            except (OSError, UnicodeError, SyntaxError) as exc:
                findings.append("check: langgraph: cannot parse {}: {}".format(path, exc))
                return findings
            identities = {n["id"]: n.get("graph_id", n["id"]) for n in nodes}
            diagram_nodes = set(identities.values()) - {"START", "END"}
            diagram_edges = {(identities[e["from"]], identities[e["to"]]) for e in edges
                             if e["from"] in identities and e["to"] in identities}
            for missing in sorted(actual_nodes - diagram_nodes):
                findings.append("check: langgraph: missing node " + missing)
            for extra in sorted(diagram_nodes - actual_nodes):
                findings.append("check: langgraph: extra node " + extra)
            for src, dst in sorted(actual_edges - diagram_edges):
                findings.append("check: langgraph: missing edge {}->{}".format(src, dst))
            for src, dst in sorted(diagram_edges - actual_edges):
                findings.append("check: langgraph: extra edge {}->{}".format(src, dst))
            for src in sorted(set(unresolved)):
                findings.append("check: langgraph: unresolved conditional edge from " + src)
    return findings


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec")
    parser.add_argument("--repo")
    args = parser.parse_args(argv)
    try:
        findings = check_spec(load_spec(args.spec), args.repo, spec_dir=os.path.dirname(os.path.abspath(args.spec)))
    except SpecError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
