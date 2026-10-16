#!/usr/bin/env bash
set -euo pipefail

# copilot-cli: GitHub Copilot CLI (unofficial) for Termux.
#
# Strategy: the .deb ships only the launcher + docs. The large (~180 MB)
# upstream glibc Node SEA is downloaded and checksum-verified by postinst, so we
# never redistribute upstream's proprietary binary (see helper/README.md). The
# binary runs on Termux's glibc bridge (glibc-repo); no proot is required.
#
# Usage: build.sh [aarch64|x86_64]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEBS_DIR="$REPO_ROOT/debs"
mkdir -p "$DEBS_DIR"

VERSION="${COPILOT_CLI_VERSION:-$(cat "$SCRIPT_DIR/VERSION")}"
DEB_VERSION="${VERSION}-1"
PREFIX="data/data/com.termux/files/usr"
ARCH="${1:-aarch64}"

case "$ARCH" in
    aarch64) UP_ARCH="arm64" ;;
    x86_64)  UP_ARCH="x64" ;;
    *) echo "Usage: $0 [aarch64|x86_64]" >&2; exit 1 ;;
esac

echo "=== Building copilot-cli ${DEB_VERSION} (${ARCH}) ==="

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

PKG_DIR="${BUILD_DIR}/copilot-cli_${DEB_VERSION}_${ARCH}"
mkdir -p "${PKG_DIR}/DEBIAN" \
         "${PKG_DIR}/${PREFIX}/bin" \
         "${PKG_DIR}/${PREFIX}/lib/copilot-cli" \
         "${PKG_DIR}/${PREFIX}/share/doc/copilot-cli"

install -Dm755 "$SCRIPT_DIR/helper/copilot.sh"        "${PKG_DIR}/${PREFIX}/bin/copilot"
install -Dm644 "$SCRIPT_DIR/helper/README.md"         "${PKG_DIR}/${PREFIX}/share/doc/copilot-cli/README.md"
install -Dm644 "$SCRIPT_DIR/helper/auth-token.example" "${PKG_DIR}/${PREFIX}/share/doc/copilot-cli/auth-token.example"

INSTALLED_SIZE="$(du -sk "${PKG_DIR}/${PREFIX}" | cut -f1)"

cat > "${PKG_DIR}/DEBIAN/control" << EOF
Package: copilot-cli
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: Twilight <twilight@aliveos.org>
Installed-Size: ${INSTALLED_SIZE}
Depends: glibc-repo, glibc, gcc-libs-glibc, patchelf, ripgrep, git, bash, curl, ca-certificates
Section: devel
Priority: optional
Homepage: https://github.com/github/copilot-cli
Description: GitHub Copilot CLI (unofficial Termux port)
 Agentic coding assistant for the terminal. Unofficial; not affiliated with
 or endorsed by GitHub. Runs on the Termux glibc bridge (no proot). Requires
 an active Copilot subscription. The ~180 MB upstream binary is downloaded
 and checksum-verified at install time. Authenticate with COPILOT_GITHUB_TOKEN
 or 'copilot login --device-code'.
EOF

cat > "${PKG_DIR}/DEBIAN/postinst" << 'POSTINST'
#!/bin/sh
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LIB_DIR="$PREFIX/lib/copilot-cli"
BIN_FILE="$LIB_DIR/copilot"
STAMP_FILE="$LIB_DIR/.upstream-version"

DEB_VER="$(dpkg -s copilot-cli 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p')"
# Strip the Debian revision (e.g. 1.0.98-1 -> 1.0.98) to get the upstream tag.
UP_VER="${DEB_VER%-*}"

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    aarch64)      UP_ARCH="arm64"; LOADER="ld-linux-aarch64.so.1" ;;
    x86_64|amd64) UP_ARCH="x64";   LOADER="ld-linux-x86-64.so.2" ;;
    *) echo "copilot-cli: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

command -v patchelf >/dev/null 2>&1 || {
    echo "copilot-cli: patchelf is required (pkg install patchelf)" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || {
    echo "copilot-cli: curl is required" >&2; exit 1; }

CACHED_VER="$(cat "$STAMP_FILE" 2>/dev/null || true)"
if [ ! -f "$BIN_FILE" ] || [ "$CACHED_VER" != "$DEB_VER" ]; then
    TMP="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/copilot-cli.XXXXXX")"
    trap 'rm -rf "$TMP"' EXIT INT TERM

    BASE="https://github.com/github/copilot-cli/releases/download/v${UP_VER}"
    ASSET="copilot-linux-${UP_ARCH}.tar.gz"

    echo "copilot-cli: downloading ${UP_VER} (${UP_ARCH})..."
    curl -fSL "$BASE/SHA256SUMS.txt" -o "$TMP/SHA256SUMS.txt"
    curl -fSL "$BASE/$ASSET"          -o "$TMP/$ASSET"

    echo "copilot-cli: verifying checksum..."
    ( cd "$TMP" \
      && grep -E "[[:space:]]\*?${ASSET}\$" SHA256SUMS.txt > .sums \
      && [ -s .sums ] \
      && sha256sum -c .sums )

    tar -xzf "$TMP/$ASSET" -C "$TMP"
    [ -f "$TMP/copilot" ] || { echo "copilot-cli: 'copilot' not found in archive" >&2; exit 1; }

    mkdir -p "$LIB_DIR"
    install -m755 "$TMP/copilot" "$BIN_FILE"

    echo "copilot-cli: patching ELF interpreter -> $PREFIX/glibc/lib/$LOADER"
    patchelf --set-interpreter "$PREFIX/glibc/lib/$LOADER" "$BIN_FILE"

    echo "$DEB_VER" > "$STAMP_FILE"
    rm -rf "$TMP"
    trap - EXIT INT TERM
fi

# glibc reads nsswitch.conf from its own etc dir (where glibc-repo symlinks
# resolv.conf/hosts). Provide it if absent so host lookups resolve via DNS.
NSS="$PREFIX/glibc/etc/nsswitch.conf"
if [ ! -e "$NSS" ]; then
    mkdir -p "$(dirname "$NSS")"
    printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\n' > "$NSS"
fi

echo ""
echo "copilot-cli ${UP_VER} installed."
echo "  Authenticate with a token:  docs at $PREFIX/share/doc/copilot-cli/auth-token.example"
echo "  Or device flow:             copilot login --device-code"
echo "  Requires an active GitHub Copilot subscription."
echo ""
POSTINST
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

find "$PKG_DIR" -type d -exec chmod 755 {} +

DEB_FILE="${DEBS_DIR}/copilot-cli_${DEB_VERSION}_termux_${ARCH}.deb"
export REPRO_MTIME
REPRO_MTIME="$(git -C "$REPO_ROOT" log -1 --format=%ct -- packages/copilot-cli 2>/dev/null || git -C "$REPO_ROOT" log -1 --format=%ct)"
bash "$REPO_ROOT/scripts/build-deb.sh" "$PKG_DIR" "$DEB_FILE"
echo "Built: $DEB_FILE ($(du -h "$DEB_FILE" | cut -f1))"
