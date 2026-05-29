import json
import subprocess
import sys
from pathlib import Path


def _make_minimal_project(root: Path):
    arch = root / "Architecture"
    (arch / "modules").mkdir(parents=True)
    (arch / "overview.md").write_text(
        "## 跨模組改進機會\n\n"
        "### Imp 1: 抽 AI 引擎 adapter\n"
        "- **為什麼:** 目前 provider 切換成本高\n"
        "- **證據:** [[modules/backend#改進機會]] Imp 1 | [[modules/frontend#改進機會]] Imp 1\n"
        "- **Effort:** L\n"
        "- **未做的風險:** vendor lock-in\n"
        "- **Confidence:** medium\n"
    )
    (arch / "modules" / "backend.md").write_text(
        "## 改進機會\n\n"
        "### Imp 1: 加 streaming API\n"
        "- **為什麼:** UI 需要即時回饋\n"
        "- **證據:** `backend/main.py:42`\n"
        "- **Effort:** M\n"
        "- **未做的風險:** 回覆延遲高\n"
        "- **Confidence:** high\n"
    )
    (arch / "decisions.md").write_text(
        "## 建議升級為 ADR\n\n1. **為什麼 Redis Cluster** — TBD\n"
        "\n## 已知限制\n\n- backend/.env deprecated\n"
    )


def test_cli_dry_run_emits_candidates(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    _make_minimal_project(proj)
    out_dir = tmp_path / "out"
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(out_dir),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode == 0, f"stderr: {result.stderr}"
    candidates_file = out_dir / "candidates.json"
    assert candidates_file.exists()
    data = json.loads(candidates_file.read_text())
    assert len(data) >= 3
    kinds = {c["kind"] for c in data}
    assert "improvement" in kinds
    assert "limitation" in kinds
    assert "promote-to-adr" in kinds


def test_cli_emits_keyword_prompt(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    _make_minimal_project(proj)
    out_dir = tmp_path / "out"
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(out_dir),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode == 0
    kp = out_dir / "keyword_extraction_prompt.txt"
    assert kp.exists()
    text = kp.read_text()
    assert "streaming" in text or "AI 引擎" in text or "Redis" in text


def test_cli_aborts_when_no_architecture_dir(tmp_path: Path):
    proj = tmp_path / "Projects" / "p"
    proj.mkdir(parents=True)  # no Architecture subfolder
    result = subprocess.run(
        [sys.executable, "scripts/roadmap_synth.py",
         "--project-root", str(proj),
         "--vault-root", str(tmp_path),
         "--out", str(tmp_path / "out"),
         "--dry-run"],
        capture_output=True, text=True, cwd=Path(__file__).resolve().parents[2],
    )
    assert result.returncode != 0
    assert "Architecture" in result.stderr or "Architecture" in result.stdout
