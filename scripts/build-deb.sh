#!/usr/bin/env bash
# Deterministic .deb builder.
#
# Same staged content -> byte-identical .deb, so APT only offers upgrades
# when package content actually changes (plain `dpkg-deb --build` stamps
# fresh ar-member timestamps on every run, causing phantom same-version
# "upgrades").
#
# Usage:
#   build-deb.sh <stage-dir> <output.deb>   # staged dir with DEBIAN/
#   build-deb.sh <package-dir> <out-dir>     # direct: packages/<name>/ with DEBIAN/
#
# Env:
#   REPRO_MTIME  epoch seconds for all archive members. If unset and the
#                first arg is inside a git repo, derived from
#                `git log -1 --format=%ct -- <dir>` (CI checks out full
#                history, so this only changes when the package changes).
set -euo pipefail

SRC="$1"
DEST="$2"

resolve_mtime() {
    local dir="$1"
    if [ -n "${REPRO_MTIME:-}" ]; then
        printf '%s' "$REPRO_MTIME"
        return
    fi
    if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        (git -C "$dir" log -1 --format=%ct -- . 2>/dev/null \
            || git -C "$dir" log -1 --format=%ct)
        return
    fi
    date +%s
}

if [ -d "$SRC/DEBIAN" ]; then
    STAGE="$SRC"
    MTIME="$(resolve_mtime "$SRC")"
    OUT="$DEST"
    if [ -d "$OUT" ]; then
        PKG="$(grep -m1 '^Package:' "$STAGE/DEBIAN/control" | awk '{print $2}')"
        VER="$(grep -m1 '^Version:' "$STAGE/DEBIAN/control" | awk '{print $2}')"
        ARCH="$(grep -m1 '^Architecture:' "$STAGE/DEBIAN/control" | awk '{print $2}')"
        OUT="${OUT%/}/${PKG}_${VER}_${ARCH}.deb"
    fi
else
    echo "Error: $SRC has no DEBIAN/ directory" >&2
    exit 1
fi

for tool in tar xz ar; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Error: $tool not found" >&2; exit 1; }
done

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TAR_OPTS=(--sort=name "--mtime=@${MTIME}" --owner=0 --group=0 --numeric-owner)

echo "2.0" > "$TMPDIR/debian-binary"

tar "${TAR_OPTS[@]}" -cf "$TMPDIR/control.tar" -C "$STAGE/DEBIAN" .
xz -9 -c "$TMPDIR/control.tar" > "$TMPDIR/control.tar.xz"

# data archive: everything except DEBIAN/ (leading ./ root entry like dpkg-deb)
{
    echo ./;
    ( cd "$STAGE" && find . -mindepth 1 -not -path './DEBIAN' -not -path './DEBIAN/*' | LC_ALL=C sort )
} > "$TMPDIR/filelist"
tar "${TAR_OPTS[@]}" --no-recursion -cf "$TMPDIR/data.tar" -C "$STAGE" -T "$TMPDIR/filelist"
xz -9 -c "$TMPDIR/data.tar" > "$TMPDIR/data.tar.xz"

# deterministic ar (D = zero uid/gid/timestamps)
ar Dcq "$OUT" "$TMPDIR/debian-binary" "$TMPDIR/control.tar.xz" "$TMPDIR/data.tar.xz"
echo "Built: $OUT"
