# CONTEXT — ai_system vocabulary

- **tdd-rules fragment** — `docs/tdd-rules.d/<R-NNN>.md`, one ship's learned TDD rules. Readers see the legacy `docs/tdd-rules.md` first, then every fragment by name.
- **security pass** — ship-next Phase 6 steps 1.5–1.6 (R-003): a vendored copy of Anthropic's `/security-review` prompt, run every review attempt next to code-review-skill. Its HIGH findings block like code-review blockers; it never fails open.
- **pre-existing finding** — a review finding tagged `[pre-existing]` right after its severity tag (`PRE_EXISTING_RE`): the defect is already on the base branch. It never blocks; step 4.5 files it once.
- **pre-existing key** — `<file>:<category>` or `<file>:<first 40 bytes of the description>`, written into the follow-up as `(pre-existing-key: <key>)` so the next ship that meets the same defect does not file it again.
- **live checkout** — the checkout behind `~/.claude/skills/ship-workflow` (a symlink made by `./sync.sh restore`). Every session on the machine runs it, uncommitted edits included, so it stays on `main`; ship-next Phase 1 warns otherwise (R-004).
- **command copy** — a `<repo>/.claude/commands/ship-*.md` file the old `/ship-init` copied in. They went stale; `remove_command_copies <repo>` clears them, and no repo needs one (R-004).
- **displaced** — what `./sync.sh restore` does to a real file or directory that sits where a link or a restored config belongs: moved to `~/.claude/.ai_system-displaced/<name>-<UTC time>`, never deleted.
- **land (mr mode)** — `/ship-land R-NNN` after the review merges: runs `/ship-compound` in a throwaway worktree at `origin/<base>` and pushes one `[skip ci]` push; review branches never write shared files (R-008).
