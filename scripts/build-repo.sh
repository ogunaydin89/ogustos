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
mkdir -p "${PKG_STAGE}/usr/local/bin"
mkdir -p "${PKG_STAGE}/usr/share/ogustos"
mkdir -p "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps"
mkdir -p "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images"
mkdir -p "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images_dark"
mkdir -p "${PKG_STAGE}/usr/share/sddm/themes/breeze"

cat > "${PKG_STAGE}/DEBIAN/control" <<'EOF'
Package: ogustos-base
Version: 1.0.1-1ogustos1
Section: admin
Priority: required
Architecture: all
Provides: xserver
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Core configuration, APT pinning, branding, and CLI for ogustOS KDE
EOF

cat > "${PKG_STAGE}/DEBIAN/triggers" <<'EOF'
interest-noawait /usr/lib/os-release
interest-noawait /usr/share/plasma/look-and-feel
interest-noawait /usr/share/plasma/desktoptheme
interest-noawait /usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel
interest-noawait /usr/share/icons/breeze
interest-noawait /usr/share/icons/breeze-dark
EOF

cp -a "${REPO_ROOT}/etc" "${PKG_STAGE}/"
cp -a "${REPO_ROOT}/apt/." "${PKG_STAGE}/etc/apt/"
install -m 0644 "${REPO_ROOT}/etc/os-release" "${PKG_STAGE}/usr/share/ogustos/os-release"
rm -f "${PKG_STAGE}/etc/os-release"

cat > "${PKG_STAGE}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
if ! dpkg-divert --list /usr/lib/os-release | grep -q ogustos-base; then
    dpkg-divert --package ogustos-base --divert /usr/lib/os-release.debian --rename /usr/lib/os-release >/dev/null 2>&1 || true
fi
cp -f /usr/share/ogustos/os-release /usr/lib/os-release
ln -sf ../usr/lib/os-release /etc/os-release

# Provide standard 'bat' and 'fd' binary names on Debian
[[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat /usr/local/bin/bat || true
[[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind /usr/local/bin/fd || true

# Set ogustOS wallpaper as default across KDE Plasma 6 themes & look-and-feel packages
for f in /usr/share/plasma/desktoptheme/*/plasmarc; do
    [[ -f "$f" ]] && sed -i 's/^defaultWallpaperTheme=.*/defaultWallpaperTheme=ogustOS/' "$f" || true
done
for f in /usr/share/plasma/look-and-feel/org.kde.breeze*.desktop/contents/defaults; do
    [[ -f "$f" ]] && sed -i 's/^Image=.*/Image=ogustOS/' "$f" || true
done

# Set ogustOS emblem as the KDE Application Launcher (Kickoff) taskbar icon in full color
rm -f /usr/share/icons/breeze*/places/*/start-here-kde*-symbolic.svg 2>/dev/null || true
for icon in /usr/share/icons/breeze*/places/*/start-here-kde.svg /usr/share/icons/breeze*/places/*/start-here-kde-plasma.svg; do
    [[ -e "$icon" || -L "$icon" ]] && ln -sf /usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg "$icon" || true
done
LAYOUT_JS="/usr/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
if [[ -f "$LAYOUT_JS" ]] && ! grep -q 'ogustos-logo' "$LAYOUT_JS"; then
    sed -i 's/panel\.addWidget("org\.kde\.plasma\.kickoff")/var kickoff = panel.addWidget("org.kde.plasma.kickoff"); kickoff.currentConfigGroup = ["General"]; kickoff.writeConfig("icon", "ogustos-logo");/' "$LAYOUT_JS" || true
fi

# Prevent duplicate Google Chrome APT source file (keep 04-google-chrome.sources)
rm -f /etc/apt/sources.list.d/google-chrome.sources /etc/apt/sources.list.d/google-chrome.list

# Mask drkonqi coredump units globally since coredumps are disabled by design
mkdir -p /etc/systemd/user
ln -sf /dev/null /etc/systemd/user/drkonqi-coredump-launcher.socket
ln -sf /dev/null /etc/systemd/user/drkonqi-coredump-pickup.service
EOF
chmod 0755 "${PKG_STAGE}/DEBIAN/postinst"

install -m 0755 "${REPO_ROOT}/bin/ogust" "${PKG_STAGE}/usr/bin/ogust"
install -m 0755 "${REPO_ROOT}/bin/ogust-install" "${PKG_STAGE}/usr/bin/ogust-install"
install -m 0644 "${REPO_ROOT}/branding/ogustos-ascii.txt" "${PKG_STAGE}/usr/share/ogustos/ogustos-ascii.txt"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg"
install -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${PKG_STAGE}/usr/share/icons/hicolor/scalable/apps/start-here-kde.svg"
install -m 0644 "${REPO_ROOT}/branding/wallpaper.jpg" "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg"
ln -sf ../images/3840x2160.jpg "${PKG_STAGE}/usr/share/wallpapers/ogustOS/contents/images_dark/3840x2160.jpg"

cat > "${PKG_STAGE}/usr/share/sddm/themes/breeze/theme.conf.user" <<'EOF'
[General]
type=image
background=/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg
EOF

cat > "${PKG_STAGE}/usr/share/wallpapers/ogustOS/metadata.json" <<'EOF'
{
    "KPlugin": {
        "Id": "ogustOS",
        "Name": "ogustOS"
    }
}
EOF

mkdir -p "${OUT_DIR}/pool/main" "${OUT_DIR}/pool/apps"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-amd64" "${OUT_DIR}/dists/stable/apps/binary-amd64"
mkdir -p "${OUT_DIR}/dists/stable/main/binary-i386"  "${OUT_DIR}/dists/stable/apps/binary-i386"

rm -f "${OUT_DIR}/pool/main/ogustos-base_"*.deb
dpkg-deb --build --root-owner-group "$PKG_STAGE" "${OUT_DIR}/pool/main/ogustos-base_1.0.1-1ogustos1_all.deb"

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
