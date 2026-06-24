# Global Claude operating notes

These notes apply across all projects. Per-project `CLAUDE.md` / `AGENTS.md`
files override anything here. Keep this file short — it loads into every
session.

## Specification edits

When a project has a `spec/` directory and the current task modifies or adds
content to any file inside it, prefer the `update-specification` skill to
guide the edit. The skill enforces an AI-friendly format: explicit
`REQ-NNN` / `SEC-NNN` / `CON-NNN` / `PAT-NNN` / `AC-NNN` IDs,
Given-When-Then acceptance criteria, and the 11-section template documented
inside the skill itself.

Do **not** invoke the skill for:

- Projects without a `spec/` directory (most small scripts, experiments,
  frontend-only repos, learning projects).
- Read-only spec lookups — only when writing or updating a spec.
- Surgical typo / wording fixes inside an existing spec that already
  conforms to the format.

The skill's template includes some .NET-flavored test-framework defaults
(MSTest, FluentAssertions, Moq). Substitute the project's actual test
stack (pytest / vitest / jest / etc.) when applying.

## Post-pull sync

After every `git pull` (or any operation that fast-forwards / merges remote
changes into the working tree), immediately run:

```bash
./sync.sh restore
```

This applies the project's restore step so the local environment stays in
sync with what was just pulled. Run it even if the pull reported "Already
up to date" only when the user explicitly asks; otherwise run it whenever
the pull actually updated files.
