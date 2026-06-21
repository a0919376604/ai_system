# Code Review for ship/R-001.3-wire-scene-engine

## Findings

### handler.py:45 — SQL injection in `cache_get`
**Severity:** blocking
**Suggestion:** Use parameterized query.

### cache.py:12 — Unhandled None when key missing
**Severity:** Blocking
**Suggestion:** Default to empty dict.

### service.py:88 — N+1 query in scene fetch
**Severity:** major
**Suggestion:** Batch fetch with IN clause.

### service.py:104 — Magic number 1024
[major] consider extracting to constant.

### dialogue.py:312 — Function exceeds 50 lines
**Severity:** minor

### tests/test_engine.py:8 — Missing assertion message
[minor] add message for clarity.

### tests/test_engine.py:42 — Excellent test coverage of edge cases
**Severity:** praise
nice work.

### service.py:200 — Clean abstraction over old chapter API
[praise] readable and well-factored.

### dialogue.py:420 — Good docstring
**Severity:** Praise

## Summary
Blocking issues block merge per ship-workflow contract.
