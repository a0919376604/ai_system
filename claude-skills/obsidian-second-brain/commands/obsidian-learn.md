---
description: Review vault learnings (default), OR capture a single learning at write time (--capture flag) — the vault's lessons compound or expire
category: thinking
triggers_en: ["review learnings", "what have I learned", "show lessons", "prune learnings"]
---

Use the obsidian-second-brain skill. Execute `/obsidian-learn $ARGUMENTS`:

The optional argument is a scope: `recent` (last 30 days, default), `all` (entire vault), or a topic name. Pass `--capture` (followed by the learning text) to run Capture mode instead.

## Modes

### Capture mode (`--capture` flag)

Use when the user has JUST learned something during dev (Checkpoint 3: post-PR or post-implementation). Write a single learning note.

1. Resolve project (see Project routing below). If unresolvable, ASK.
2. Parse the learning from `$ARGUMENTS` (after the `--capture` flag) or from recent conversation context.
3. Write `Projects/<P>/Learnings/YYYY-MM-DD-<slug>.md`:
   ```
   ---
   date: YYYY-MM-DD
   type: learning
   project: "[[<P>]]"
   tags: [learning, <P>]
   related-task: "[[T-XXX]]"   # if known
   ai-first: true
   ---

   ## For future Claude
   [one-line summary of what was learned + why future-Claude would care]

   ## What I learned
   [the lesson, 2-4 sentences]

   ## How I learned it
   [the trigger — a bug, a successful pattern, a colleague's comment]

   ## When this applies
   [pattern recognition — what situations will hit this again]

   ## Source
   [task / spec / commit SHA]
   ```
4. Append a one-line entry to today's `Logs/YYYY-MM-DD.md`: `**HH:MM** - learn-capture | <P>/<slug> - <one-line>`
5. STOP. Do not run review mode.

### Review mode (no `--capture` flag — default, original behavior)

The existing numbered steps below apply unchanged. They survey the vault.

## Project routing

For capture mode: resolve project name in priority: (1) `--project=<name>` in `$ARGUMENTS`; (2) vault `_CLAUDE.md` active project; (3) codebase CLAUDE.md. If none resolves: ASK — never default.

Target (capture mode): `Projects/<P>/Learnings/YYYY-MM-DD-<slug>.md`

1. Read `_CLAUDE.md` first if it exists in the vault root
2. Read `index.md` and recent operation log for vault context (if `Logs/` exists: read the last 2-3 `Logs/YYYY-MM-DD.md` files; otherwise read `log.md`)

3. Spawn parallel subagents to gather learnings:

   - **Lessons agent**: scan all daily notes for "Lesson learned" sections, "What didn't" sections, evening review insights
   - **Decisions agent**: read all ADRs in `Projects/*/Decisions/` (project-scoped, new layout) and `Knowledge/ADR-*.md` (legacy location, may still exist) — extract the rationale and outcome of each
   - **Learnings agent**: read all per-project learnings in `Projects/*/Learnings/` (new in hybrid layout) — these are the explicit captures from `/obsidian-learn --capture`
   - **Reports agent**: read recent emerge/synthesize/connect/challenge reports in `Knowledge/` (the auto-generated pattern reports)
   - **Mistakes agent**: scan dev logs and daily notes for "what didn't work", "wasted time on", "next time", "lesson", phrases indicating learning from failure
   - **Wins agent**: scan for patterns that worked — "this saved time", "this approach worked", recurring success patterns

4. For each learning found, classify:
   - **Active**: still relevant, recurring, reinforced by recent activity
   - **Stale**: 6+ months old with no recent reinforcement, or contradicted by newer evidence
   - **Superseded**: explicitly replaced by a newer ADR or pattern
   - **Promoted**: appeared 3+ times — should become a permanent rule in `_CLAUDE.md`

5. Generate the Learnings Report:

   ## Active Learnings (still applies)
   - List learnings reinforced in the last 90 days
   - Cite the original source and most recent reinforcement

   ## Stale Learnings (consider archiving)
   - List learnings with no recent reinforcement
   - Suggest: keep, archive, or convert to history note

   ## Superseded Learnings (already replaced)
   - Old position → New position with ADR reference

   ## Promotion Candidates (appeared 3+ times)
   - Learnings strong enough to become permanent rules in `_CLAUDE.md`
   - Suggest exact wording for the operating manual

   ## Top 5 Lessons of the Period
   - Most impactful learnings ranked by frequency × recency × consequence

6. Save the report to `Reviews/YYYY-MM-DD - Learnings Review.md` (vault-wide review default; if `--project=<P>` was passed to review mode, save to `Projects/<P>/Recaps/YYYY-MM-DD-learnings-review.md` instead)
7. Append to the operation log: if `Logs/` exists write `**HH:MM** - learn | X active, Y stale, Z superseded, N promotion candidates` to `Logs/YYYY-MM-DD.md`; otherwise append `## [YYYY-MM-DD] learn | X active, Y stale, Z superseded, N promotion candidates` to `log.md`
8. Update today's daily note with a brief summary
9. Offer to:
   - Promote candidates to `_CLAUDE.md` (with user confirmation)
   - Archive stale learnings (with user confirmation)
   - Export top 5 as a shareable markdown for content/journaling

Lessons that aren't reviewed don't compound. This command turns scattered notes into a living rulebook.

---

**AI-first rule:** Every note created or updated by this command MUST follow `references/ai-first-rules.md` — `## For future Claude` preamble, rich frontmatter (`type`, `date`, `tags`, `ai-first: true`, plus type-specific fields), recency markers per external claim, mandatory `[[wikilinks]]` for every person/project/concept referenced, sources preserved verbatim with URLs inline, and confidence levels where applicable. The vault is for future-Claude retrieval — not human reading.
