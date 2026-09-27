#!/usr/bin/env bash
# Stage Termux's own Android-built OpenSSL + nghttp2 (headers and shared
# libs) into a prefix for the CI cross-compile job.
#
# Rationale: compiling OpenSSL with newer NDKs is fragile (its Configure
# expects removed wrapper layouts), while Termux's debs are already built
# for Bionic on every arch we target -- and they are exactly what the
# final package links against at runtime (Depends: openssl, libnghttp2).
#
# Usage: build-deps-android.sh <arm64-v8a|x86_64> <install-prefix>
set -euo pipefail

ABI="${1:?usage: build-deps-android.sh <arm64-v8a|x86_64> <prefix>}"
PREFIX="${2:?usage: build-deps-android.sh <arm64-v8a|x86_64> <prefix>}"

case "$ABI" in
    arm64-v8a) TARCH="aarch64" ;;
    x86_64)    TARCH="x86_64" ;;
    *) echo "Error: unsupported ABI $ABI" >&2; exit 1 ;;
esac

BASE="https://packages.termux.dev/apt/termux-main"
mkdir -p "$PREFIX"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "=== Fetching Termux package index ($TARCH) ==="
curl -fsSL "$BASE/dists/stable/main/binary-$TARCH/Packages" -o Packages

fetch_deb() {
    local pkg="$1" filename url
    filename="$(awk -v p="$pkg" 'BEGIN{RS=""; FS="\n"} $0 ~ "(^|\n)Package: "p"(\n|$)" {for (i=1;i<=NF;i++) if ($i ~ /^Filename: /) {sub(/^Filename: /,"",$i); print $i; exit}}' Packages)"
    if [ -z "$filename" ]; then
        echo "Error: package $pkg not found in Termux index" >&2
        exit 1
    fi
    url="$BASE/$filename"
    echo "Downloading $pkg ($url)..."
    curl -fSL "$url" -o "$(basename "$filename")"
    echo "Extracting $(basename "$filename")..."
    dpkg-deb --fsys-tarfile "$(basename "$filename")" \
        | tar -x -C "$PREFIX" --strip-components=6 './data/data/com.termux/files/usr'
}

fetch_deb openssl
fetch_deb libnghttp2

# .pc files ship with Termux's device prefix baked in (prefix=,
# includedir=, libdir= are often absolute, not ${prefix}-relative).
# Rewrite every occurrence so pkg-config consumers get working flags.
# pkg-config runs outside CMake, immune to NDK find-root restrictions.
if ls "$PREFIX"/lib/pkgconfig/*.pc >/dev/null 2>&1; then
    sed -i "s|/data/data/com.termux/files/usr|$PREFIX|g" "$PREFIX"/lib/pkgconfig/*.pc
    grep -H -E '^(prefix|includedir|libdir)=' "$PREFIX"/lib/pkgconfig/*.pc
else
    echo "Warning: no .pc files staged (nghttp2 pkg-config discovery may fail)"
fi

echo "=== Staged files ==="
ls "$PREFIX/include/openssl/ssl.h" "$PREFIX/include/nghttp2/nghttp2.h" \
   "$PREFIX/lib/libcrypto.so" "$PREFIX/lib/libnghttp2.so"
echo "Deps staged under $PREFIX"
