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
Version: 1.0.3-1ogustos1
Section: admin
Priority: required
Architecture: all
Recommends: fakeroot
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
rm -rf "${PKG_STAGE}/etc/calamares" "${PKG_STAGE}/etc/default/keyboard" "${PKG_STAGE}/etc/default/locale"
chmod 0440 "${PKG_STAGE}/etc/sudoers.d/99-ogustos-nopasswd"
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

if [[ ! -f /etc/default/locale ]]; then
    cat > /etc/default/locale <<'LOC'
LANG=en_GB.UTF-8
LC_TIME=tr_TR.UTF-8
LOC
fi
if [[ ! -f /etc/default/keyboard ]]; then
    cat > /etc/default/keyboard <<'KBD'
XKBMODEL="pc105"
XKBLAYOUT="tr"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD
fi

# Divert Debian's stock systemd-boot initramfs hook so zz-ogustos-boot is the sole bootloader manager
if ! dpkg-divert --list /etc/initramfs/post-update.d/systemd-boot | grep -q ogustos-base; then
    dpkg-divert --package ogustos-base --divert /etc/initramfs/post-update.d/systemd-boot.disabled --rename /etc/initramfs/post-update.d/systemd-boot >/dev/null 2>&1 || true
fi
rm -f /etc/initramfs/post-update.d/systemd-boot

# Divert Discover background notifier autostart so DiscoverNotifier + packagekitd never consume idle RAM
if ! dpkg-divert --list /etc/xdg/autostart/org.kde.discover.notifier.desktop | grep -q ogustos-base; then
    dpkg-divert --package ogustos-base --divert /etc/xdg/autostart/org.kde.discover.notifier.desktop.disabled --rename /etc/xdg/autostart/org.kde.discover.notifier.desktop >/dev/null 2>&1 || true
fi
rm -f /etc/xdg/autostart/org.kde.discover.notifier.desktop /etc/xdg/autostart/org.kde.kalendarac.desktop

# Remove any untracked /usr/local/bin/ogust* copies so /usr/bin/ogust is never shadowed
rm -f /usr/local/bin/ogust /usr/local/bin/ogust-install /usr/local/bin/ogust-calamares-postinstall /usr/local/bin/ogust-reboot

# Provide standard 'bat' and 'fd' binary names on Debian
[[ -x /usr/bin/batcat ]] && ln -sf /usr/bin/batcat /usr/local/bin/bat || true
[[ -x /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind /usr/local/bin/fd || true

# Copy PAM configs from /usr/lib/pam.d to /etc/pam.d to silence Debian libpam0g warnings
for pam_svc in systemd-user polkit-1; do
    if [[ -f "/usr/lib/pam.d/${pam_svc}" && ! -f "/etc/pam.d/${pam_svc}" ]]; then
        cp -a "/usr/lib/pam.d/${pam_svc}" "/etc/pam.d/${pam_svc}"
    fi
done

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
mkdir -p /etc/systemd/user /etc/systemd/system
ln -sf /dev/null /etc/systemd/user/drkonqi-coredump-launcher.socket
ln -sf /dev/null /etc/systemd/user/drkonqi-coredump-pickup.service
ln -sf /dev/null /etc/systemd/system/drkonqi-coredump-processor@.service

# Guarantee /etc/shadow and /etc/gshadow are root:shadow (0640) so unprivileged unix_chkpwd (kscreenlocker_greet) works
if getent group shadow >/dev/null 2>&1; then
    chown root:shadow /etc/shadow /etc/gshadow /etc/shadow- /etc/gshadow- 2>/dev/null || true
    chmod 0640 /etc/shadow /etc/gshadow /etc/shadow- /etc/gshadow- 2>/dev/null || true
fi
if [[ -f /usr/sbin/unix_chkpwd ]] && getent group shadow >/dev/null 2>&1; then
    chown root:shadow /usr/sbin/unix_chkpwd
    chmod 2755 /usr/sbin/unix_chkpwd
fi

# Prevent non-interactive PAM workers (kde-fingerprint, kde-smartcard) from falling through
# missing pam_fprintd.so / pam_sss.so into pam_kwallet5.so password prompt inside kscreenlocker_greet
if [[ -f /etc/pam.d/kde-fingerprint ]]; then
    sed -i 's/^auth[[:space:]]\+required[[:space:]]\+pam_fprintd\.so/auth\trequisite\tpam_fprintd.so/' /etc/pam.d/kde-fingerprint || true
fi
if [[ -f /etc/pam.d/kde-smartcard ]]; then
    sed -i 's/^auth[[:space:]]\+required[[:space:]]\+pam_sss\.so/auth    requisite       pam_sss.so/' /etc/pam.d/kde-smartcard || true
fi
EOF
chmod 0755 "${PKG_STAGE}/DEBIAN/postinst"

install -m 0755 "${REPO_ROOT}/bin/ogust" "${PKG_STAGE}/usr/bin/ogust"
install -m 0755 "${REPO_ROOT}/bin/ogust-reboot" "${PKG_STAGE}/usr/bin/ogust-reboot"
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
dpkg-deb --build --root-owner-group "$PKG_STAGE" "${OUT_DIR}/pool/main/ogustos-base_1.0.3-1ogustos1_all.deb"

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
