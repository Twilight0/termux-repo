#!/bin/sh
set -e

REPO_URL="https://twilight0.github.io/termux-repo"
RELEASE_URL="https://github.com/Twilight0/termux-repo/releases/download/latest"
SOURCES_FILE="$PREFIX/etc/apt/sources.list.d/twilight0-repo.list"

echo "Adding Twilight0 custom repository..."

mkdir -p "$PREFIX/etc/apt/sources.list.d"

if [ -f "$SOURCES_FILE" ]; then
    echo "Repository already configured."
else
    echo "deb [trusted=yes] ${REPO_URL} stable main" > "$SOURCES_FILE"
    echo "Repository added: ${SOURCES_FILE}"
fi

echo ""
echo "Updating package lists..."
pkg update -y 2>/dev/null || apt update -y

echo ""
echo "Done! Available packages:"
echo "  pkg install wrangler           # Cloudflare Workers CLI"
echo "  pkg install muse-code          # Meta's Muse Code agent"
echo "  pkg install opencode           # AI coding assistant"
echo "  pkg install antigravity-cli    # Google Antigravity CLI"
echo "  pkg install oh-my-pi           # Oh-My-Pi plugin manager"
echo ""
echo "Note: opencode, antigravity-cli, and oh-my-pi require glibc-repo."
echo "Install it with: pkg install glibc-repo"
