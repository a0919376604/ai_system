"""Deterministic markdown table renderers for api-surface.md sections.

These do not call an LLM. They turn scanner output into structured tables.
"""

from __future__ import annotations


_HEADERS = {
    "cli": {
        "en": ("Command", "Description", "Source", "Module"),
        "zh-TW": ("指令", "說明", "來源", "模組"),
    },
    "http": {
        "en": ("Method", "Path", "Handler", "Module"),
        "zh-TW": ("方法", "路徑", "Handler", "模組"),
    },
    "exports": {
        "en": ("Symbol", "Kind", "Source", "Module"),
        "zh-TW": ("符號", "種類", "來源", "模組"),
    },
    "env": {
        "en": ("Var", "Required", "Default", "Source"),
        "zh-TW": ("變數", "必填", "預設值", "來源"),
    },
}


def _table(headers: tuple[str, ...], rows: list[list[str]]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join(["---"] * len(headers)) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)
    return "\n".join([head, sep, body])


def render_cli_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["cli"][lang]
    body = [[f"`{r['name']}`", r.get("description", ""), f"`{r['source']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_http_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["http"][lang]
    body = [[r["method"], f"`{r['path']}`", f"`{r['handler']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_exports_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["exports"][lang]
    body = [[f"`{r['symbol']}`", r.get("kind", ""), f"`{r['source']}`",
             f"[[modules/{r.get('module', '')}]]" if r.get("module") else ""] for r in rows]
    return _table(h, body)


def render_env_table(rows: list[dict], lang: str) -> str:
    if not rows:
        return ""
    h = _HEADERS["env"][lang]
    yes_no = ("yes" if lang == "en" else "是", "no" if lang == "en" else "否")
    body = []
    for r in rows:
        body.append([
            f"`{r['name']}`",
            yes_no[0] if r.get("required") else yes_no[1],
            f"`{r['default']}`" if r.get("default") is not None else "",
            f"`{r['source']}`",
        ])
    return _table(h, body)


def render_interface_overview(http_rows: list[dict], lang: str = "en") -> str:
    """High-level HTTP route grouping by URL prefix.

    Returns a markdown summary (not the full table). Designed to live in
    api-surface.md under v3, where the exhaustive table moves out to scan-report.json.
    """
    if not http_rows:
        return ""
    # Bucket by first URL segment.
    buckets: dict[str, list[dict]] = {}
    for r in http_rows:
        path = r.get("path", "")
        first = path.lstrip("/").split("/")[0] or "(root)"
        buckets.setdefault(f"/{first}" if first != "(root)" else "/", []).append(r)

    n = len(http_rows)
    lines = [f"**{n} routes** grouped by URL prefix:"] if lang == "en" else [f"**{n} 條路由**,以 URL 前綴分組:"]
    for prefix in sorted(buckets):
        rows = buckets[prefix]
        methods = sorted({r.get("method", "") for r in rows})
        lines.append(f"- `{prefix}` — {len(rows)} routes, methods: {', '.join(methods)}")
    lines.append("")
    if lang == "en":
        lines.append("> Full route table lives in `/tmp/architect-<hash>/scan-report.json` "
                     "under `api_surface.http_routes`.")
    else:
        lines.append("> 完整路由表在 `/tmp/architect-<hash>/scan-report.json` 的 "
                     "`api_surface.http_routes`。")
    return "\n".join(lines)


def render_env_overview(env_rows: list[dict], lang: str = "en") -> str:
    """High-level env var grouping by name prefix."""
    if not env_rows:
        return ""
    buckets: dict[str, list[dict]] = {}
    for r in env_rows:
        name = r.get("name", "")
        prefix = name.split("_")[0] if "_" in name else name
        buckets.setdefault(prefix, []).append(r)

    n = len(env_rows)
    required_n = sum(1 for r in env_rows if r.get("required"))
    if lang == "en":
        lines = [f"**{n} variables** ({required_n} required), grouped by prefix:"]
    else:
        lines = [f"**{n} 個變數**({required_n} 個必填),以前綴分組:"]
    for prefix in sorted(buckets):
        rows = buckets[prefix]
        req = sum(1 for r in rows if r.get("required"))
        if lang == "en":
            lines.append(f"- `{prefix}_*` — {len(rows)} variables, {req} required")
        else:
            lines.append(f"- `{prefix}_*` — {len(rows)} 個,{req} 個必填")
    lines.append("")
    if lang == "en":
        lines.append("> Full env table lives in `/tmp/architect-<hash>/scan-report.json` "
                     "under `api_surface.env_vars`.")
    else:
        lines.append("> 完整環境變數表在 `/tmp/architect-<hash>/scan-report.json` 的 "
                     "`api_surface.env_vars`。")
    return "\n".join(lines)
