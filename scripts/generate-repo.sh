#!/usr/bin/env bash
set -e

DIST="stable"
COMP="main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEBS_DIR="${REPO_DIR}/debs"

cd "$REPO_DIR"
mkdir -p "dists/${DIST}/${COMP}" "pool/${COMP}"

# Copy debs into pool + arch dirs
for deb in "$DEBS_DIR"/*.deb; do
    arch=$(dpkg-deb -f "$deb" Architecture)
    mkdir -p "dists/${DIST}/${COMP}/binary-${arch}"
    cp "$deb" "dists/${DIST}/${COMP}/binary-${arch}/"
    cp "$deb" "pool/${COMP}/"
done

# Generate Packages + Packages.xz per arch
for arch_dir in "dists/${DIST}/${COMP}"/binary-*; do
    arch=$(basename "$arch_dir" | sed 's/binary-//')
    echo "Generating Packages for ${arch}..."
    PKG_FILE="${arch_dir}/Packages"
    > "$PKG_FILE"

    first=1
    for deb in "$arch_dir"/*.deb; do
        [ -f "$deb" ] || continue
        deb_name=$(basename "$deb")
        pkg=$(dpkg-deb -f "$deb" Package)
        ver=$(dpkg-deb -f "$deb" Version)
        desc=$(dpkg-deb -f "$deb" Description)
        depends=$(dpkg-deb -f "$deb" Depends)
        maint=$(dpkg-deb -f "$deb" Maintainer)
        section=$(dpkg-deb -f "$deb" Section)
        priority=$(dpkg-deb -f "$deb" Priority)
        homepage=$(dpkg-deb -f "$deb" Homepage)
        size=$(stat -c%s "$deb")
        # Installed-Size must come from the deb's own control data so it
        # matches what dpkg records in status at install time. apt's version
        # merge hash covers Installed-Size: a fabricated value means equal
        # versions never merge, causing perpetual same-version "upgrades".
        isize=$(dpkg-deb -f "$deb" Installed-Size 2>/dev/null || echo $((size/1024)))
        md5=$(md5sum "$deb" | cut -d' ' -f1)
        sha1=$(sha1sum "$deb" | cut -d' ' -f1)
        sha256=$(sha256sum "$deb" | cut -d' ' -f1)

        [ "$first" -eq 1 ] && first=0 || printf '\n' >> "$PKG_FILE"

        printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: %s\nInstalled-Size: %s\nDepends: %s\nSection: %s\nPriority: %s\nHomepage: %s\nDescription: %s\nFilename: pool/%s/%s\nSize: %s\nMD5sum: %s\nSHA1: %s\nSHA256: %s\n' \
            "$pkg" "$ver" "$arch" "$maint" "$isize" "$depends" "$section" "$priority" "$homepage" "$desc" "$COMP" "$deb_name" "$size" "$md5" "$sha1" "$sha256" \
            >> "$PKG_FILE"
    done
    xz -9kf "$PKG_FILE"
done

# Generate Release
ARCHS=$(ls -d "dists/${DIST}/${COMP}"/binary-* | xargs -I{} basename {} | sed 's/binary-//' | sort | tr '\n' ' ')
{
    echo "Origin: Twilight"
    echo "Label: termux-repo"
    echo "Codename: ${DIST}"
    echo "Architectures: ${ARCHS}"
    echo "Components: ${COMP}"
    echo "Description: Twilight custom termux repository"
    echo "Suite: ${DIST}"
    echo "Date: $(date -Ru)"
    echo "SHA256:"
    for arch_dir in "dists/${DIST}/${COMP}"/binary-*; do
        arch=$(basename "$arch_dir" | sed 's/binary-//')
        for f in Packages Packages.xz; do
            filepath="${arch_dir}/${f}"
            if [ -f "$filepath" ]; then
                hash=$(sha256sum "$filepath" | cut -d' ' -f1)
                fsize=$(stat -c%s "$filepath")
                echo " ${hash} ${fsize} ${COMP}/binary-${arch}/${f}"
            fi
        done
    done
} > "dists/${DIST}/Release"

echo "Repository generated:"
find dists/ pool/ -type f | sort
