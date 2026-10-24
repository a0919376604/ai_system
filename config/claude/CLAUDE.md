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

## Research output language

All research artifacts (research-deep, research-brief, ce-web-researcher
output, in-vault `Research/*.md` files, any "find prior art / synthesize
findings" task output) MUST be written in **Traditional Chinese (繁體中文)**.

This applies to:
- Documents saved into the AIR-OS vault `Research/` directory
- Discussion briefs, synthesis docs, prior-art summaries
- Anything dispatched via `/ship-research`, `/obsidian-research-deep`,
  or `ce-web-researcher` subagents

Citation URLs, code snippets, technical proper nouns (`flag.X`, `entry_when`,
class names, library names, papers' English titles) stay in their original
form. Only the prose narrative, section headings, summaries, and rationale
text translates to Chinese.

When dispatching a research subagent, include this constraint explicitly
in the prompt (e.g. "Output language: Traditional Chinese; technical
identifiers and citations stay verbatim").

## Project mockups go to the vault as HTML

When asked for a mockup / proposal mockup for a project, write a single
self-contained HTML file to
`/Users/leric/Documents/SecondBrain/10 Projects/<name>/Proposals/mockups/`
— never markdown or ASCII art. Read and follow **Project Mockup Convention**
in `/Users/leric/Documents/SecondBrain/_CLAUDE.md` first (structure, base
styles, linking, headless-Chrome verification).

## Feature flags default ON

When shipping a new user-facing feature behind a kill-switch flag
(`FEATURE_X_ENABLED`, `VITE_ENABLE_FEATURE_X`, config `feature_x.enabled`,
GrowthBook `feature-x`, etc.), **default it to ON** — in prod config,
in code (`os.getenv("...", "true") != "false"`, not `... == "true"`),
and in whatever schema drives the runtime.

Rationale: the person who asked for the feature wants to use / see /
test it the moment it deploys. Shipping default-off hides the thing
they built from themselves and delays every downstream signal (does it
even render? does it break other pages? do CS reports come in?) until
someone remembers to flip it. The kill switch's job is being a kill
switch — it doesn't need to also be a rollout gate. Two different jobs.

**Exceptions — genuinely default OFF:**
- **Safety / security-critical mutation surfaces** (delete-everything
  button, bulk mailer, mass-refund tool): default off until manually
  verified in prod.
- **Auth / authz / quota / tenant-isolation gates**: deny by default is
  the pattern (see `opt-in-gate-when-retrofitting-a-cross-cutting-governor`
  in AIR-OS 30 Engineering — this is that pattern's stated exception).
- **Expensive-per-invocation features** (paid third-party API burn,
  large-model inference costs) where enabling on every pod immediately
  is a spend risk.
- **Explicitly staged rollouts** the user asked for ("prod default off,
  ramp 10% → 50% → 100%"). If the user asks for staging, do staging.

**Read-only observability / admin-visibility / display features are
never in these exceptions.** They pay no per-request cost, they can't
break user data, they can't leak secrets past their auth gate. Ship on.

If a spec says "prod default false, staged rollout" and it's a read-only
display feature, push back once before implementing that way. If the
user re-affirms, do what they asked — but the pushback happens.

## Code review feedback: verify before agreeing

When someone points at review feedback — a PR/MR number plus "look at this",
in any language — reproduce the claim yourself before accepting or implementing
it. State what you observed, then whether the feedback was right, too weak, or
wrong.

This is not politeness about disagreement; it is about being wrong in both
directions. A real case: feedback was accepted and the fix applied, and the
reproduction showed the defect was *worse* than reported — and a test written
three tasks earlier had pinned the broken behaviour as the spec. Neither fact
surfaces if you just do what the comment says.

## Clarifying questions: ask, then commit

Cap clarifying questions at roughly three rounds. After that, state the
assumption you are proceeding on and continue; the person can correct you.

Rationale: a past session asked eleven rounds for one slash command. Seven were
answered with a bare "Ok", then two interrupts and "什麼狀況". Past about three,
questions stop gathering information and start transferring your uncertainty to
someone with less context than you.

## langlive VPN: reconnect it yourself

When langlive infra (k8s `*_ll_eks`, bastion, internal hosts, `61.216.4.193`)
hangs or times out, or the VPN looks down, run `~/vpn.sh status`. If it prints
`DOWN`, use the `langlive-vpn-login` skill to connect, then retry the original
command. Don't ask the user to click FortiClient, and ignore `scutil --nc
status` (it always says Disconnected). Never disconnect unless asked.
