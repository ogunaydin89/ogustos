#!/usr/bin/env bash
# ==============================================================================
# build-repo.sh — Packages ogustOS .debs & builds Multi-Version APT Catalogue
# Uses dpkg-scanpackages --multiversion so ALL versions stay in the catalogue
# (Gentoo ebuild/slot style: ogust versions <pkg> & ogust in <pkg>=<version>)
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
install -m 0644 "${REPO_ROOT}/branding/ogustos-ascii.txt" "${PKG_STAGE}/usr/share/ogustos/ogustos-ascii.txt"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/start-here-kde.svg"
install -m 0644 "${REPO_ROOT}/branding/wallpaper.jpg" "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg"

mkdir -p "${OUT_DIR}/pool/main" "${OUT_DIR}/pool/apps"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-amd64" "${OUT_DIR}/dists/stable/apps/binary-amd64"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-i386"  "${OUT_DIR}/dists/stable/apps/binary-i386"

dpkg-deb --build --root-owner-group "$PKG_STAGE" "${OUT_DIR}/pool/main/ogustos-base_1.0.0_all.deb"

if command -v dpkg-scanpackages >/dev/null 2>&1; then
    cd "$OUT_DIR"
    for comp in main apps; do
        for arch in amd64 i386; do
            dpkg-scanpackages --multiversion --arch "$arch" "pool/${comp}" > "dists/stable/${comp}/binary-${arch}/Packages"
            gzip -9c "dists/stable/${comp}/binary-${arch}/Packages" > "dists/stable/${comp}/binary-${arch}/Packages.gz"
        done
    done
fi

echo "[::] Multi-version repository updated at ${OUT_DIR}"
