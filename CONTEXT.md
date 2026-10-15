# CONTEXT — ai_system vocabulary

- **Ship-Log trailer** — a `Ship-Log: <row>` git trailer on an empty commit. How an mr-mode review branch records its `docs/learnings/_log.md` row without touching the shared file; read back with `git log --format='%(trailers:key=Ship-Log,valueonly)'`.
- **ship-pending queue** — `docs/ship-pending/<R-NNN>-context.md`: the CONTEXT.md entries an mr-mode ship queues on its review branch. `/ship-land` folds them into CONTEXT.md after the MR merges.
- **land commit** — the single `context: land <R-NNN> [skip ci]` commit `/ship-land` pushes to the base branch. Made only when the ship queued CONTEXT entries.
- **tdd-rules fragment** — `docs/tdd-rules.d/<R-NNN>.md`, one ship's learned TDD rules. Readers see the legacy `docs/tdd-rules.md` first, then every fragment by name.
