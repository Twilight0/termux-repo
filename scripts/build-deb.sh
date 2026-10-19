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
#   <PKG>_VERSION e.g. WRANGLER_VERSION / TERMUX_MCP_VERSION: the latest
#                upstream version, resolved by scripts/resolve-versions.sh
#                at build time. Stamps the control Version (as X-1) and
#                any version literal pinned in DEBIAN/postinst, so each
#                CI run packages the newest upstream release.
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
    ORIG_SRC="$SRC"

    # --- CI version tracking: stamp resolved upstream version ---
    PKG="$(grep -m1 '^Package:' "$SRC/DEBIAN/control" | awk '{print $2}')"
    NEW_UP_VERSION=""
    case "$PKG" in
        curl-cffi)  NEW_UP_VERSION="${CURL_CFFI_VERSION:-}"
                    NEW_TAG="${CURL_CFFI_TAG:-}" ;;
        *)          VAR="$(printf '%s' "$PKG" | tr 'a-z-' 'A-Z_')_VERSION"
                    [ "$PKG" = 9router ] && VAR=NINE_ROUTER_VERSION
                    NEW_UP_VERSION="${!VAR:-}" ;;
    esac

    if [ -n "${NEW_UP_VERSION:-}" ]; then
        # Never downgrade: keep the existing version if the resolved
        # upstream version is not actually newer (e.g. a transient API
        # answer behind a manual bump).
        CUR="$(grep -m1 '^Version:' "$ORIG_SRC/DEBIAN/control" | awk '{print $2}')"
        if dpkg --compare-versions "$CUR" gt "${NEW_UP_VERSION}-1" 2>/dev/null; then
            echo "build-deb: ${PKG}: resolved $NEW_UP_VERSION is not newer than pinned $CUR; keeping $CUR" >&2
            NEW_UP_VERSION=""
        fi
    fi

    if [ -n "${NEW_UP_VERSION:-}" ]; then
        STAMPDIR="$(mktemp -d)"
        cp -a "$ORIG_SRC" "$STAMPDIR/staged"
        sed -i -E "s/^Version:.*/Version: ${NEW_UP_VERSION}-1/" "$STAMPDIR/staged/DEBIAN/control"
        POSTINST="$STAMPDIR/staged/DEBIAN/postinst"
        if [ -f "$POSTINST" ]; then
            stamp_var() { sed -i -E "s/^($1)=\".*\"/\1=\"$2\"/" "$POSTINST"; }
            case "$PKG" in
                wrangler)   stamp_var WRANGLER_VERSION "$NEW_UP_VERSION" ;;
                9router)    stamp_var NINE_ROUTER_VERSION "$NEW_UP_VERSION" ;;
                termux-mcp) stamp_var TERMUX_MCP_VERSION "$NEW_UP_VERSION" ;;
                yt-tui)     stamp_var YT_TUI_VERSION "$NEW_UP_VERSION" ;;
                pipx)       stamp_var PIPX_VERSION "$NEW_UP_VERSION" ;;
                curl-cffi)  stamp_var BUILDER_VERSION "$NEW_UP_VERSION"
                            case "$NEW_TAG" in
                                v*) stamp_var BUILDER_TAG "$NEW_TAG" ;;
                                *)  stamp_var BUILDER_TAG "v$NEW_TAG" ;;
                            esac ;;
                *)          ;;  # yt-dlp-git installs master; pipx has no pin
            esac
        fi
        SRC="$STAMPDIR/staged"
        echo "build-deb: stamped ${PKG} to $NEW_UP_VERSION (CI version tracking)"
    fi

    MTIME="$(resolve_mtime "$ORIG_SRC")"
    STAGE="$SRC"
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
trap 'rm -rf "$TMPDIR" ${STAMPDIR:+$STAMPDIR}' EXIT

TAR_OPTS=(--sort=name "--mtime=@${MTIME}" --owner=0 --group=0 --numeric-owner)

echo "2.0" > "$TMPDIR/debian-binary"

# data filelist first: needed both for the archive and for Installed-Size
# data archive: everything except DEBIAN/ (leading ./ root entry like dpkg-deb)
{
    echo ./;
    ( cd "$STAGE" && find . -mindepth 1 -not -path './DEBIAN' -not -path './DEBIAN/*' | LC_ALL=C sort )
} > "$TMPDIR/filelist"

# Installed-Size must be identical in control.tar (→ dpkg status) and the
# Packages index (read via dpkg-deb -f by generate-repo.sh): apt's version
# merge hash covers Installed-Size, and a mismatch means equal versions
# never merge → perpetual same-version "upgrades". Computed as a pure
# function of payload file sizes (dpkg-deb uses du block counts, but those
# vary by filesystem; self-consistency is what matters).
INSTALLED_SIZE="$(cd "$STAGE" && find . -mindepth 1 -not -path './DEBIAN' -not -path './DEBIAN/*' -type f -printf '%s\n' | awk '{s+=($1+1023)/1024} END {printf "%d", s+0}')"
echo "Installed-Size: $INSTALLED_SIZE"

# control.tar from a copy with Installed-Size injected (never mutates source)
mkdir -p "$TMPDIR/ctrl"
cp -a "$STAGE/DEBIAN/." "$TMPDIR/ctrl/"
grep -v -i '^Installed-Size:' "$TMPDIR/ctrl/control" > "$TMPDIR/ctrl/control.new" || true
mv "$TMPDIR/ctrl/control.new" "$TMPDIR/ctrl/control"
printf 'Installed-Size: %s\n' "$INSTALLED_SIZE" >> "$TMPDIR/ctrl/control"

tar "${TAR_OPTS[@]}" -cf "$TMPDIR/control.tar" -C "$TMPDIR/ctrl" .
xz -9 -c "$TMPDIR/control.tar" > "$TMPDIR/control.tar.xz"

tar "${TAR_OPTS[@]}" --no-recursion -cf "$TMPDIR/data.tar" -C "$STAGE" -T "$TMPDIR/filelist"
xz -9 -c "$TMPDIR/data.tar" > "$TMPDIR/data.tar.xz"

# deterministic ar (D = zero uid/gid/timestamps)
ar Dcq "$OUT" "$TMPDIR/debian-binary" "$TMPDIR/control.tar.xz" "$TMPDIR/data.tar.xz"
echo "Built: $OUT"
