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
echo "  pkg install 9router            # Free AI coding router"
echo "  pkg install curl-cffi          # TLS impersonation for Python"
echo "  pkg install yt-dlp-git         # Video downloader (git master)"
echo "  pkg install agentty            # AI pair programmer (native)"
echo "  pkg install pipx               # Isolated Python app runner"
echo "  pkg install yt-tui             # Curses TUI for yt-dlp"
echo "  pkg install termux-mcp         # REST API + MCP server for AI agents"
echo "  pkg install muse-code          # Meta's Muse Code agent"
echo "  pkg install opencode           # AI coding assistant (v2, no proot)"
echo "  pkg install opencode-legacy    # AI coding assistant (v1, proot)"
echo "  pkg install antigravity-cli    # Google Antigravity CLI"
echo "  pkg install oh-my-pi           # Oh-My-Pi plugin manager"
echo ""
echo "Note: opencode, antigravity-cli, and oh-my-pi require glibc-repo."
echo "Install it with: pkg install glibc-repo"
echo ""
echo "Support continued development and new package ports:"
echo "  https://ko-fi.com/alivegr_twilight0"
