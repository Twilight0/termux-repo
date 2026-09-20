#!/usr/bin/env bash
set -e

DIST="stable"
COMP="main"
REPO_URL="https://github.com/Twilight0/termux-repo/releases/download/latest"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEBS_DIR="${REPO_DIR}/debs"
OUT_DIR="${REPO_DIR}/repo"

mkdir -p "$OUT_DIR/dists/${DIST}/${COMP}"

# Copy debs into arch-specific dirs
for deb in "$DEBS_DIR"/*.deb; do
    arch=$(dpkg-deb -f "$deb" Architecture)
    mkdir -p "$OUT_DIR/dists/${DIST}/${COMP}/binary-${arch}"
    cp "$deb" "$OUT_DIR/dists/${DIST}/${COMP}/binary-${arch}/"
done

# Generate Packages + Packages.xz per arch
for arch_dir in "$OUT_DIR/dists/${DIST}/${COMP}"/binary-*; do
    arch=$(basename "$arch_dir" | sed 's/binary-//')
    echo "Generating Packages for ${arch}..."
    PKG_FILE="${arch_dir}/Packages"
    > "$PKG_FILE"

    first=1
    for deb in "$arch_dir"/*.deb; do
        [ -f "$deb" ] || continue
        deb_name=$(basename "$deb")
        control=$(dpkg-deb -I "$deb")
        pkg=$(echo "$control" | grep '^Package:' | awk '{print $2}')
        ver=$(echo "$control" | grep '^Version:' | awk '{print $2}')
        desc=$(echo "$control" | grep '^Description:' | sed 's/^Description: //')
        depends=$(echo "$control" | grep '^Depends:' | sed 's/^Depends: //')
        maint=$(echo "$control" | grep '^Maintainer:' | sed 's/^Maintainer: //')
        section=$(echo "$control" | grep '^Section:' | awk '{print $2}')
        priority=$(echo "$control" | grep '^Priority:' | awk '{print $2}')
        homepage=$(echo "$control" | grep '^Homepage:' | sed 's/^Homepage: //')
        size=$(stat -c%s "$deb")
        md5=$(md5sum "$deb" | cut -d' ' -f1)
        sha1=$(sha1sum "$deb" | cut -d' ' -f1)
        sha256=$(sha256sum "$deb" | cut -d' ' -f1)
        filename="${REPO_URL}/${deb_name}"

        if [ "$first" -eq 1 ]; then
            first=0
        else
            printf '\n' >> "$PKG_FILE"
        fi

        cat >> "$PKG_FILE" <<PKGEOF
Package: ${pkg}
Version: ${ver}
Architecture: ${arch}
Maintainer: ${maint}
Installed-Size: $(( size / 1024 ))
Depends: ${depends}
Section: ${section}
Priority: ${priority}
Homepage: ${homepage}
Description: ${desc}
Filename: ${filename}
Size: ${size}
MD5sum: ${md5}
SHA1: ${sha1}
SHA256: ${sha256}
PKGEOF
    done
    xz -9kf "$PKG_FILE"
done

# Generate Release file
RELEASE_FILE="$OUT_DIR/dists/${DIST}/Release"
ARCHS=$(ls -d "$OUT_DIR/dists/${DIST}/${COMP}"/binary-* | xargs -I{} basename {} | sed 's/binary-//' | sort | tr '\n' ' ')

cat > "$RELEASE_FILE" <<RELEOF
Origin: Twilight
Label: termux-repo
Codename: ${DIST}
Architectures: ${ARCHS}
Components: ${COMP}
Description: Twilight custom termux repository
Suite: ${DIST}
Date: $(date -Ru)
RELEOF

for arch_dir in "$OUT_DIR/dists/${DIST}/${COMP}"/binary-*; do
    arch=$(basename "$arch_dir" | sed 's/binary-//')
    for f in Packages Packages.xz; do
        filepath="${arch_dir}/${f}"
        if [ -f "$filepath" ]; then
            hash=$(sha256sum "$filepath" | cut -d' ' -f1)
            size=$(stat -c%s "$filepath")
            echo " ${hash} ${size} ${COMP}/binary-${arch}/${f}" >> "$RELEASE_FILE"
        fi
    done
done

echo "Repository metadata generated:"
find "$OUT_DIR" -type f | sort
