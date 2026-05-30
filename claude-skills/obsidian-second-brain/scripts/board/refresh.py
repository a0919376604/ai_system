"""Refresh Projects/<P>/board.md via deterministic git + spec/plan walk."""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


_FRONTMATTER_LAST_REFRESH_RE = re.compile(
    r'^last-refresh:\s*"?(?P<ts>[^"\n]+)"?\s*$', re.MULTILINE
)
_FRONTMATTER_LOCAL_PATH_RE = re.compile(
    r'^local-path:\s*"?(?P<path>[^"\n]+)"?\s*$', re.MULTILINE
)
_BRAINSTORM_REF_RE = re.compile(r"\brefs/(?:remotes/origin/)?(?:HEAD->\s*)?(?P<ref>\S+)")
_BUCKET_HEADING_RE = re.compile(r"^##\s+(?P<name>[^\n#].*?)\s*$", re.MULTILINE)


@dataclass
class RefreshResult:
    status: str
    project_slug: str = ""
    board_path: Path | None = None
    done_count: int = 0
    in_flight_count: int = 0
    backlog_count: int = 0
    buckets: list[str] = field(default_factory=list)
    new_items: list[dict] = field(default_factory=list)
    last_refresh_before: str | None = None
    last_refresh_after: str = ""
    message: str = ""


def refresh_board(
    project_dir: Path,
    *,
    signals: dict | None = None,
    full: bool = False,
) -> RefreshResult:
    project_slug = project_dir.name
    board_path = project_dir / "board.md"
    if not board_path.is_file():
        return RefreshResult(
            status="skipped",
            project_slug=project_slug,
            board_path=board_path,
            message=f"no board.md in {project_slug} - run /obsidian-project to bootstrap",
        )

    board_text = board_path.read_text(encoding="utf-8")
    last_refresh_before = _read_last_refresh(board_text)
    local_path = _resolve_local_path(project_dir, project_slug)

    if signals is None:
        since = None if full else last_refresh_before
        new_items = _walk_signals(local_path, since=since) if local_path else []
    else:
        new_items = _new_items_from_signals(signals)

    done, in_flight, backlog = _classify_items(new_items)

    existing_buckets = _existing_bucket_names(board_text)
    bucket_assignments = _cluster_items(done + in_flight + backlog, existing_buckets)
    buckets = sorted(set(bucket_assignments.values()))
    if "Misc / Untriaged" not in buckets and any(
        bucket == "Misc / Untriaged" for bucket in bucket_assignments.values()
    ):
        buckets.append("Misc / Untriaged")

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    new_board_text = _update_frontmatter_last_refresh(board_text, now_iso)
    new_board_text = _update_frontmatter_totals(
        new_board_text,
        done=len(done),
        in_flight=len(in_flight),
        backlog=len(backlog),
    )
    board_path.write_text(new_board_text, encoding="utf-8")

    return RefreshResult(
        status="ok",
        project_slug=project_slug,
        board_path=board_path,
        done_count=len(done),
        in_flight_count=len(in_flight),
        backlog_count=len(backlog),
        buckets=buckets,
        new_items=new_items,
        last_refresh_before=last_refresh_before,
        last_refresh_after=now_iso,
        message=f"walked {len(new_items)} items into {len(buckets)} bucket(s)",
    )


def _read_last_refresh(text: str) -> str | None:
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    fm = m.group(1)
    sm = _FRONTMATTER_LAST_REFRESH_RE.search(fm)
    return sm.group("ts").strip() if sm else None


def _resolve_local_path(project_dir: Path, project_slug: str) -> Path | None:
    hub_path = project_dir / f"{project_slug}.md"
    if not hub_path.is_file():
        return None
    text = hub_path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return None
    fm = m.group(1)
    sm = _FRONTMATTER_LOCAL_PATH_RE.search(fm)
    if not sm:
        return None
    return Path(sm.group("path").strip())


def _walk_signals(local_path: Path, *, since: str | None) -> list[dict]:
    """Walk git log + spec/plan files. Each entry: {title, kind, when, source}."""
    if not local_path or not local_path.exists():
        return []
    items: list[dict] = []
    items.extend(_git_log_items(local_path, since=since))
    items.extend(_spec_plan_items(local_path, since=since))
    return items


def _git_log_items(repo: Path, *, since: str | None) -> list[dict]:
    cmd = [
        "git",
        "log",
        "--all",
        "--pretty=format:%H%x09%ad%x09%s%x09%D",
        "--date=iso-strict",
    ]
    if since:
        cmd.append(f"--since={since}")
    try:
        proc = subprocess.run(cmd, cwd=str(repo), capture_output=True, text=True, check=False)
    except (FileNotFoundError, OSError):
        return []
    if proc.returncode != 0:
        return []
    items: list[dict] = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        sha, when, subject = parts[0], parts[1], parts[2]
        refs = parts[3] if len(parts) > 3 else ""
        items.append(
            {
                "title": subject,
                "kind": "commit",
                "when": when,
                "source": f"commit {sha[:8]}",
                "refs": refs,
            }
        )
    return items


def _spec_plan_items(repo: Path, *, since: str | None) -> list[dict]:
    """List spec/plan files under docs/superpowers/. Filter by mtime if since set."""
    docs = repo / "docs" / "superpowers"
    if not docs.is_dir():
        return []
    items: list[dict] = []
    cutoff = _parse_iso_ts(since) if since else None
    for sub in ("specs", "plans"):
        d = docs / sub
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.md")):
            mtime = f.stat().st_mtime
            if cutoff is not None and mtime < cutoff:
                continue
            items.append(
                {
                    "title": f.stem,
                    "kind": sub.rstrip("s"),
                    "when": datetime.fromtimestamp(mtime).isoformat(),
                    "source": f.relative_to(repo).as_posix(),
                }
            )
    return items


def _parse_iso_ts(ts: str) -> float | None:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None


def _new_items_from_signals(signals: dict) -> list[dict]:
    """Reuse caller-provided signals."""
    items: list[dict] = []
    for commit in signals.get("git_commits", []):
        items.append(
            {
                "title": commit.get("title", ""),
                "kind": commit.get("kind", "commit"),
                "when": commit.get("when", ""),
                "source": commit.get("source", ""),
                "refs": commit.get("refs", ""),
            }
        )
    for spec_path in signals.get("spec_files", []):
        p = Path(spec_path)
        items.append(
            {
                "title": p.stem,
                "kind": "spec",
                "when": "",
                "source": str(p),
                "refs": "",
            }
        )
    for plan_path in signals.get("plan_files", []):
        p = Path(plan_path)
        items.append(
            {
                "title": p.stem,
                "kind": "plan",
                "when": "",
                "source": str(p),
                "refs": "",
            }
        )
    return items


def _update_frontmatter_last_refresh(text: str, new_ts: str) -> str:
    """Replace or add `last-refresh:` in the first frontmatter block."""
    m = re.match(r"^(---\n)(.*?)(\n---)", text, re.DOTALL)
    if not m:
        return f"---\nlast-refresh: {new_ts}\n---\n\n{text}"
    head, fm, tail = m.group(1), m.group(2), m.group(3)
    if _FRONTMATTER_LAST_REFRESH_RE.search(fm):
        new_fm = _FRONTMATTER_LAST_REFRESH_RE.sub(f"last-refresh: {new_ts}", fm, count=1)
    else:
        new_fm = fm + f"\nlast-refresh: {new_ts}"
    return head + new_fm + tail + text[m.end() :]


def _update_frontmatter_totals(text: str, *, done: int, in_flight: int, backlog: int) -> str:
    """Ensure frontmatter contains current totals."""
    m = re.match(r"^(---\n)(.*?)(\n---)", text, re.DOTALL)
    if not m:
        return text
    head, fm, tail = m.group(1), m.group(2), m.group(3)
    pairs = [("done", done), ("in-flight", in_flight), ("backlog", backlog)]
    new_fm = fm
    for key, value in pairs:
        pat = re.compile(rf"^{re.escape(key)}:\s*\d+\s*$", re.MULTILINE)
        if pat.search(new_fm):
            new_fm = pat.sub(f"{key}: {value}", new_fm)
        else:
            new_fm = new_fm + f"\n{key}: {value}"
    return head + new_fm + tail + text[m.end() :]


def _classify_items(items: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    """Return (done, in_flight, backlog) lists."""
    done: list[dict] = []
    in_flight: list[dict] = []
    backlog: list[dict] = []
    for item in items:
        kind = item["kind"]
        if kind == "commit":
            refs = item.get("refs", "")
            if _has_brainstorm_ref(refs):
                in_flight.append(item)
            elif any(branch in refs for branch in ("main", "master", "trunk")) or refs == "":
                done.append(item)
            else:
                in_flight.append(item)
        elif kind == "plan":
            in_flight.append(item)
        elif kind == "spec":
            backlog.append(item)
        else:
            backlog.append(item)
    return done, in_flight, backlog


def _has_brainstorm_ref(refs: str) -> bool:
    if "brainstorm/" in refs:
        return True
    return any("brainstorm/" in match.group("ref") for match in _BRAINSTORM_REF_RE.finditer(refs))


def _existing_bucket_names(board_text: str) -> list[str]:
    """Extract H2 bucket names from existing board.md, excluding synthesis sections."""
    synthesis_section_names = {
        "🔥 This Week",
        "待辦",
        "進行中",
        "已完成",
        "已完成 (本週)",
        "Patterns observed",
        "Bucket summary",
        "給未來 Claude",
    }
    buckets: list[str] = []
    for match in _BUCKET_HEADING_RE.finditer(board_text):
        name = match.group("name").strip()
        if name in synthesis_section_names:
            continue
        if any(name.endswith(suffix) for suffix in (" 本週", " (本週)")):
            continue
        buckets.append(name)
    return buckets


def _cluster_items(items: list[dict], existing_buckets: list[str]) -> dict[str, str]:
    """Assign each item to an existing bucket by keyword overlap; else Misc / Untriaged."""
    assignments: dict[str, str] = {}
    bucket_keywords = {bucket: set(_tokenize_for_match(bucket)) for bucket in existing_buckets}
    for item in items:
        title = item["title"]
        title_tokens = set(_tokenize_for_match(title))
        best_bucket = None
        best_overlap = 0
        for bucket, keywords in bucket_keywords.items():
            overlap = len(title_tokens & keywords)
            if overlap > best_overlap:
                best_overlap = overlap
                best_bucket = bucket
        assignments[title] = best_bucket or "Misc / Untriaged"
    return assignments


def _tokenize_for_match(text: str) -> list[str]:
    """Lower-case word tokens with length >= 3."""
    return [word for word in re.findall(r"[A-Za-z一-鿿]+", text.lower()) if len(word) >= 3]
