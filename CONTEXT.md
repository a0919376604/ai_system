# CONTEXT — ai_system vocabulary

- **Ship-Log trailer** — a `Ship-Log: <row>` git trailer on an empty commit. How an mr-mode review branch records its `docs/learnings/_log.md` row without touching the shared file; read back with `git log --format='%(trailers:key=Ship-Log,valueonly)'`.
- **ship-pending queue** — `docs/ship-pending/<R-NNN>-context.md`: the CONTEXT.md entries an mr-mode ship queues on its review branch. `/ship-land` folds them into CONTEXT.md after the MR merges.
- **land commit** — the single `context: land <R-NNN> [skip ci]` commit `/ship-land` pushes to the base branch. Made only when the ship queued CONTEXT entries.
- **tdd-rules fragment** — `docs/tdd-rules.d/<R-NNN>.md`, one ship's learned TDD rules. Readers see the legacy `docs/tdd-rules.md` first, then every fragment by name.
- **security pass** — ship-next Phase 6 steps 1.5–1.6 (R-003): a vendored copy of Anthropic's `/security-review` prompt, run every review attempt next to code-review-skill. Its HIGH findings block like code-review blockers; it never fails open.
- **pre-existing finding** — a review finding tagged `[pre-existing]` right after its severity tag (`PRE_EXISTING_RE`): the defect is already on the base branch. It never blocks; step 4.5 files it once.
- **pre-existing key** — `<file>:<category>` or `<file>:<first 40 bytes of the description>`, written into the follow-up as `(pre-existing-key: <key>)` so the next ship that meets the same defect does not file it again.
