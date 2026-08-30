# Ship Workflow ↔ Discord Integration

## What the integration gives you

Once **claudecode-discord** is running on a machine and a Discord channel is `/register`-bound to a repo, the ship-workflow's slash commands automatically become Discord slash commands. Type `/ship-idea` in Discord, the bot routes to a Claude Code session on the host machine, ship-idea runs there, output streams back to the channel.

No special integration code in ship-workflow itself — it falls out of claudecode-discord's plugin command bridge.

## Visibility split

Not every ship-* command makes sense from Discord. Frontmatter `discord-visible: true|false` controls registration:

| Command | Discord-visible | Why |
|---|---|---|
| `/ship-idea <description>` | ✅ true | Fast capture, perfect for mobile |
| `/ship-decision <topic>` | ✅ true | Record ADR from any conversation |
| `/ship-roadmap` | ✅ true | Bounded, async-friendly |
| `/ship-compound` | ✅ true | One-shot wrap-up |
| `/ship-research <topic>` | ✅ true | Async, perfect for Discord |
| `/ship-propose [R-NNN]` | ✅ true | Async proposal drafting before implementation |
| `/ship-init` | ❌ false | Filesystem bootstrap; do on terminal |
| `/ship-next` | ❌ false | Interactive brainstorming; doesn't fit Discord roundtrips |

`discord-visible: false` is honored by claudecode-discord's `discovery.ts` parser. The command still works in the Claude CLI (terminal).

## Channel ↔ repo binding

Each Discord channel must be `/register`-bound to a specific repo before ship-* commands work there:

```
Discord #langlive-line-oa channel  ─ /register ─▶  /Users/leric/Desktop/code/langlive-line-oa
Discord #ai-eden-service channel   ─ /register ─▶  /Users/leric/Desktop/code/ai-eden-service
```

When the bot receives `/ship-idea <desc>` in #langlive-line-oa, it spawns a Claude Code session with `cwd = /Users/leric/Desktop/code/langlive-line-oa`. That session reads `.claude/commands/ship-idea.md` from the repo, runs the script, and writes to `docs/ideas/IDEA-NNN-*.md` plus AIR-OS.

## Multi-machine hub considerations

claudecode-discord supports a multi-PC hub: separate bots per machine, each bound to channels for that machine's repos. Ship workflow inherits these properties:

### What works automatically

| Concern | Why it's fine |
|---|---|
| Per-machine ROADMAP edits | Each repo lives on exactly one machine; only that machine's bot writes to AIR-OS `10 Projects/<repo>/ROADMAP.md` |
| Per-machine R-NNN allocation | `id-gen.sh` scans the local repo for next R-NNN; no cross-machine coordination needed since R-NNN is per-repo |
| AIR-OS reads | `sync.sh` reads strategy files from AIR-OS into the local repo mirror; safe even if AIR-OS lives on a synced cloud folder |

### Constraints you must honor

1. **One repo lives on one machine.** Don't have machine-A and machine-B both holding `langlive-line-oa` clones bound to ship-* commands. If they do, both machines' ship-idea independently allocate the same IDEA-NNN, conflicting at git merge.
2. **AIR-OS vault has one canonical location.** Either:
   - Local-only on the "primary" machine (other bots can't reach it; they can't run ship-* commands that need AIR-OS write).
   - **Cloud-synced** (iCloud / Dropbox / Syncthing) — sync.sh's atomic-write protects against half-written files, but two bots writing the same file at the same millisecond is still a race. In practice, ship-* commands take seconds, and same-file collisions across machines are extremely rare.
   - **Git-synced** — each machine periodically `git pull` on AIR-OS. More controlled but adds operational overhead.
3. **`discord:access` skill controls who** can invoke ship-* from Discord. Configure per-channel allowlists; don't expose AIR-OS write access to random Discord users.

### Recommended topology for solo dev with multiple machines

```
Mac (primary)
├── /Users/leric/Documents/SecondBrain  ← AIR-OS canonical
├── repos: ai_system, claudecode-discord, ai-eden-service
└── bot #1 (channels for these repos)

Cloud sync (iCloud) ────▶ AIR-OS replicated to other machines as a backup

PC (secondary)
├── ~/Documents/SecondBrain  ← read-only (or cloud-synced)
├── repos: langlive-line-oa, lang-anchor-recommendation
└── bot #2 (channels for these repos)
```

Both bots write to AIR-OS but to **different `10 Projects/<repo>/` subfolders**, so they never collide. Read-side (sync.sh) is independent.

## Verifying integration

After updating ship-workflow:

1. **Rebuild claudecode-discord:**
   ```bash
   cd /path/to/claudecode-discord
   npm run build
   ```

2. **Restart the bot.** It re-runs discovery on startup.

3. **In Discord, type `/`.** You should see:
   - `/ship-idea`, `/ship-decision`, `/ship-roadmap`, `/ship-compound`, `/ship-research`, `/ship-propose` (6 visible)
   - NOT `/ship-init`, `/ship-next` (2 hidden by `discord-visible: false`)

4. **In a registered channel, try `/ship-idea test from discord`.** Bot should respond with streaming Claude Code output, and `docs/ideas/IDEA-NNN-test-from-discord.md` should appear in the repo.

## Failure modes + fix

| Symptom | Cause | Fix |
|---|---|---|
| `/ship-*` doesn't appear in Discord at all | Discovery didn't pick them up | Run `npm run build` + restart bot; check `.claude/commands/ship-*.md` exists in the channel's repo |
| `/ship-init` / `/ship-next` showing in Discord | Old build before `discord-visible` patch | Rebuild claudecode-discord |
| Slash commands show generic `args` only | Old `argument-hint` parser | Ensure `argument-hint:` is in the frontmatter and rebuild |
| Channel says "not registered to a project" | Channel ↔ repo not bound | Run `/register` first |
| ship-idea works but AIR-OS file not created | Global config missing or wrong vault path | Check `~/.claude/ship-workflow.yml` on the machine running the bot |
