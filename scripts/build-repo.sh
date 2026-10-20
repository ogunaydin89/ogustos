#!/usr/bin/env bash
# ==============================================================================
# build-repo.sh — Packages ogustOS .debs, builds Multi-Version APT Catalogue,
# and generates GPG-signed Release / InRelease metadata.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/repo"
PKG_STAGE="${REPO_ROOT}/dist/stage/ogustos-base"

rm -rf "$PKG_STAGE"
mkdir -p "${PKG_STAGE}/DEBIAN"
mkdir -p "${PKG_STAGE}/usr/bin"
mkdir -p "${PKG_STAGE}/usr/share/ogustos"
mkdir -p "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps"
mkdir -p "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images"

cat > "${PKG_STAGE}/DEBIAN/control" <<'EOF'
Package: ogustos-base
Version: 1.0.0
Section: admin
Priority: required
Architecture: all
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Core configuration, APT pinning, branding, and CLI for ogustOS KDE
EOF

cp -a "${REPO_ROOT}/etc" "${PKG_STAGE}/"
cp -a "${REPO_ROOT}/apt/." "${PKG_STAGE}/etc/apt/"
install -m 0755 "${REPO_ROOT}/bin/ogust" "${PKG_STAGE}/usr/bin/ogust"
install -m 0755 "${REPO_ROOT}/bin/ogust-install" "${PKG_STAGE}/usr/bin/ogust-install"
install -m 0644 "${REPO_ROOT}/branding/ogustos-ascii.txt" "${PKG_STAGE}/usr/share/ogustos/ogustos-ascii.txt"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/start-here-kde.svg"
install -m 0644 "${REPO_ROOT}/branding/wallpaper.jpg" "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg"

cat > "${PKG_STAGE}/usr/share/wallpapers/ogustOS/metadata.json" <<'EOF'
{
    "KPlugin": {
        "Id": "ogustOS",
        "Name": "ogustOS 4D Crimson & Gold"
    }
}
EOF

mkdir -p "${OUT_DIR}/pool/main" "${OUT_DIR}/pool/apps"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-amd64" "${OUT_DIR}/dists/stable/apps/binary-amd64"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-i386"  "${OUT_DIR}/dists/stable/apps/binary-i386"

dpkg-deb --build --root-owner-group "$PKG_STAGE" "${OUT_DIR}/pool/main/ogustos-base_1.0.0_all.deb"

# Build custom apps (emerge-pdf, etc.)
if [[ -x "${REPO_ROOT}/scripts/build-apps.sh" ]]; then
    "${REPO_ROOT}/scripts/build-apps.sh"
fi

# Generate Multi-Version Packages indices & top-level Release / InRelease
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    cd "$OUT_DIR"
    for comp in main apps; do
        for arch in amd64 i386; do
            dpkg-scanpackages --multiversion --arch "$arch" "pool/${comp}" > "dists/stable/${comp}/binary-${arch}/Packages"
            gzip -9c "dists/stable/${comp}/binary-${arch}/Packages" > "dists/stable/${comp}/binary-${arch}/Packages.gz"
        done
    done

    if command -v apt-ftparchive >/dev/null 2>&1; then
        apt-ftparchive \
            -o APT::FTPArchive::Release::Origin="ogustOS" \
            -o APT::FTPArchive::Release::Label="ogustOS" \
            -o APT::FTPArchive::Release::Suite="stable" \
            -o APT::FTPArchive::Release::Codename="stable" \
            -o APT::FTPArchive::Release::Architectures="amd64 i386" \
            -o APT::FTPArchive::Release::Components="main apps" \
            release dists/stable > dists/stable/Release

        if [[ -n "${GPG_KEY_ID:-}" ]]; then
            gpg --default-key "$GPG_KEY_ID" --batch --yes --clearsign -o dists/stable/InRelease dists/stable/Release
            gpg --default-key "$GPG_KEY_ID" --batch --yes -abs -o dists/stable/Release.gpg dists/stable/Release
            gpg --export "$GPG_KEY_ID" > ogustos-archive-keyring.gpg
        fi
    fi
fi

echo "[::] Multi-version repository ready at ${OUT_DIR}"
