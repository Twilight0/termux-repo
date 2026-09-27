#!/bin/sh
set -e

SOURCES_FILE="$PREFIX/etc/apt/sources.list.d/twilight0-repo.list"

echo "Removing Twilight0 custom repository..."

rm -f "$SOURCES_FILE"

echo "Updating package lists..."
pkg update -y 2>/dev/null || apt update -y

echo ""
echo "Repository removed."
echo "Installed packages were NOT removed. To remove them:"
echo "  pkg uninstall wrangler muse-code opencode antigravity-cli oh-my-pi"
