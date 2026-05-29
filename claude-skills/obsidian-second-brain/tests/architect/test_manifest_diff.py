from scripts.architect.manifest_diff import diff_modules


def test_added_modules():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}, {"slug": "api", "paths": ["src/api/"]}]
    d = diff_modules(old, new)
    assert d.added == ["api"]
    assert d.removed == []
    assert d.renamed == []


def test_removed_modules():
    old = [{"slug": "auth", "paths": ["src/auth/"]}, {"slug": "old", "paths": ["src/old/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}]
    d = diff_modules(old, new)
    assert d.added == []
    assert d.removed == ["old"]
    assert d.renamed == []


def test_renamed_paths():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/authentication/"]}]
    d = diff_modules(old, new)
    assert d.renamed == [("auth", ["src/auth/"], ["src/authentication/"])]


def test_unchanged():
    old = [{"slug": "auth", "paths": ["src/auth/"]}]
    new = [{"slug": "auth", "paths": ["src/auth/"]}]
    d = diff_modules(old, new)
    assert d.added == []
    assert d.removed == []
    assert d.renamed == []
