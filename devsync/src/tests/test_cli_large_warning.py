from devsync.cli import scan_repo_for_large_files


def test_scan_returns_total_and_top_files(tmp_path):
    (tmp_path / "small.txt").write_bytes(b"x" * 10)
    (tmp_path / "big.bin").write_bytes(b"x" * 1_500_000)
    (tmp_path / "huge.dat").write_bytes(b"x" * 50_000_000)

    total, top = scan_repo_for_large_files(tmp_path, top_n=2, ignore_globs=[])
    assert total >= 51_500_010
    assert top[0][0].name == "huge.dat"
    assert top[1][0].name == "big.bin"


def test_scan_respects_ignore_globs(tmp_path):
    (tmp_path / "keep.txt").write_bytes(b"x" * 100)
    (tmp_path / "model.ckpt").write_bytes(b"x" * 999_999_999)

    total, top = scan_repo_for_large_files(tmp_path, top_n=5, ignore_globs=["*.ckpt"])
    assert total == 100
    names = [p.name for p, _ in top]
    assert "model.ckpt" not in names
