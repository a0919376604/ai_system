# Cocoon style

| Kind | Meaning | Fill | Stroke |
|---|---|---|---|
| `fe` | Frontend | `rgba(8,51,68,0.4)` | `#22d3ee` |
| `be` | Backend | `rgba(6,78,59,0.4)` | `#34d399` |
| `db` | Database | `rgba(76,29,149,0.4)` | `#a78bfa` |
| `bus` | Message bus | `rgba(251,146,60,0.3)` | `#fb923c` |
| `ext` | External | `rgba(30,41,59,0.5)` | `#94a3b8` |
| `sec` | Security | `rgba(136,19,55,0.4)` | `#fb7185` |
| `cloud` | Cloud | `rgba(120,53,15,0.3)` | `#fbbf24` |

Background `#020617`; 40 px grid `#1e293b`; opaque node under-rect `#0f172a`.
Arrows `#64748b`; route highlight `#fbbf24`, 2.2 px, amber markers. Other route
nodes and edges have opacity 0.2. Regions use dashed `8,4` borders. Nodes have
1.5 px borders and radius 6; pills use half their height as radius. Badges have
radius 11.

| Tone | Color |
|---|---|
| `body` | `#cbd5e1` |
| `cond` | `#fcd34d` |
| `warn` | `#fb7185` |
| `muted` | `#94a3b8` |

Use the local font stack `'JetBrains Mono',SFMono-Regular,Menlo,'PingFang TC',monospace`.
No web fonts, scripts, event handlers or external URLs. Every page opens offline.
Node titles are 13 px; subtitles and ports 10 px; lines 10.5 px; edge labels 10 px.
Estimate a character with `ord(c) > 0x2E80` at 1 em and all others at 0.62 em.
Reserve 24 px of horizontal padding. Label boxes are estimated text width + 10 px
by 16 px, centered at `(lx, ly)`.

- Draw edges before nodes, with opaque under-rects hiding crossing paths.
- Keep at least 30 px between nodes. Touching rectangles pass the checker but
  still need visual spacing.
- Put labels on straight segments, clear of all nodes and other labels.
- Use one subtitle line and at most four `lines`. Put detail in condition rows.
- Message topics are numbered step cards in a snake layout with plain-language
  text. Use `cond` for branching and `warn` for code-backed risk.
- Keep route badges clear of text. Review the full-page screenshot, including
  route copies and the condition table.

Palette and design rules adapted from Cocoon AI's architecture-diagram-generator (MIT License).
