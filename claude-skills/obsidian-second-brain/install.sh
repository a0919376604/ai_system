#!/bin/bash

set -e

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SKILLS_DIR="$CLAUDE_DIR/skills"
CONFIG_DIR="$HOME/.config/obsidian-second-brain"
ENV_FILE="$CONFIG_DIR/.env"

echo "Installing obsidian-second-brain..."

# Create directories if needed
mkdir -p "$COMMANDS_DIR"
mkdir -p "$SKILLS_DIR"

# Link or copy commands to ~/.claude/commands/
echo "Installing slash commands..."
for file in "$SKILL_DIR/commands/"*.md; do
  name=$(basename "$file")
  dest="$COMMANDS_DIR/$name"
  if [ -f "$dest" ]; then
    echo "  skipping $name (already exists)"
  else
    cp "$file" "$dest"
    echo "  installed $name"
  fi
done

# Link skill into ~/.claude/skills/
SKILL_LINK="$SKILLS_DIR/obsidian-second-brain"
if [ -e "$SKILL_LINK" ]; then
  echo "Skill already linked at $SKILL_LINK"
else
  ln -s "$SKILL_DIR" "$SKILL_LINK"
  echo "Skill linked at $SKILL_LINK"
fi

# ── Research toolkit setup (optional, zero API keys required) ──────
echo ""
echo "Research toolkit (free, zero API keys):"
echo "  /research, /research-deep, /discourse-pulse, /thread-read, /youtube,"
echo "  /idea-discovery, /vault-deep-synthesis"
echo ""
echo "Sources: arXiv, Semantic Scholar, OpenAlex, CrossRef, DuckDuckGo,"
echo "  Wikipedia, HackerNews, Reddit, Lobsters, dev.to."
echo ""
read -r -p "Install Python deps for the research toolkit now? [y/N] " setup_research
setup_research=${setup_research:-N}

if [[ "$setup_research" =~ ^[Yy]$ ]]; then
  # Verify uv is available
  if ! command -v uv >/dev/null 2>&1; then
    echo "  'uv' not found. Install with: brew install uv"
    echo "  Then re-run this installer to finish research toolkit setup."
  else
    echo "  Installing Python deps via uv..."
    (cd "$SKILL_DIR" && uv sync --quiet)
    echo "  Python deps ready."
  fi

  # Optional polite-pool contact email
  mkdir -p "$CONFIG_DIR"
  TOML_FILE="$CONFIG_DIR/research.toml"
  if [ -f "$TOML_FILE" ]; then
    echo "  $TOML_FILE already exists - leaving it untouched."
  else
    echo ""
    echo "  Optional: drop your contact email into $TOML_FILE so polite-pool"
    echo "  source APIs (arXiv, CrossRef, OpenAlex) give you better rate limits."
    echo "  Example:"
    echo '    contact_email = "you@example.com"'
  fi
fi

echo ""
echo "Done. Restart Claude Code to activate the commands."
echo ""
echo "Next steps:"
echo "  1. Run /obsidian-init to generate your vault's _CLAUDE.md"
echo "  2. (If research toolkit installed) Verify keys: cat $ENV_FILE"
