#!/usr/bin/env bash
# ==============================================================================
# build-iso.sh — End-to-End ogustOS Offline SquashFS & Instant-Boot USB Builder
# Boots straight into ogust-install on tty1 (timeout 0, no boot menu, no Live GUI)
# Pre-installs 7.3-ogustOS Kernel, KDE Plasma 6.8+ Wayland, Chrome, and Steam.
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: build-iso.sh must be run as root (for debootstrap/chroot/mount)."
    exit 1
fi

for req_cmd in debootstrap mksquashfs xorriso mkfs.vfat mmd mcopy; do
    if ! command -v "$req_cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing required host tool '$req_cmd' (install debootstrap squashfs-tools xorriso dosfstools mtools)." >&2
        exit 1
    fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/var/tmp/ogustos-iso-work}"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"
OUT_ISO="${REPO_ROOT}/dist/ogustOS-kde-amd64.iso"

mkdir -p "$WORK_DIR" "${ISO_DIR}/live" "${ISO_DIR}/EFI/BOOT" "${ISO_DIR}/loader/entries" "${REPO_ROOT}/dist"

# ------------------------------------------------------------------------------
# 1. Bootstrap Base Rootfs (Debian Stable amd64)
# ------------------------------------------------------------------------------
if [[ ! -d "${CHROOT_DIR}/etc" ]]; then
    echo "[::] Bootstrapping Debian Stable base rootfs into ${CHROOT_DIR}..."
    KEYRING_ARG="--no-check-gpg"
    [[ -f /usr/share/keyrings/debian-archive-keyring.gpg ]] && KEYRING_ARG="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
    debootstrap "$KEYRING_ARG" --arch=amd64 --variant=minbase \
        --include=ca-certificates,curl,gnupg,debian-archive-keyring,locales \
        stable "$CHROOT_DIR" https://deb.debian.org/debian
fi

# ------------------------------------------------------------------------------
# 2. Overlay ogustOS Configurations, Branding, APT Pinning & Scripts
# ------------------------------------------------------------------------------
echo "[::] Applying ogustOS /etc, APT 3-repo pinning, branding, and CLI tools..."
rm -f "${CHROOT_DIR}/etc/sysctl.d/99-disable-ipv6.conf"
cp -a --no-preserve=ownership "${REPO_ROOT}/etc/." "${CHROOT_DIR}/etc/"
ln -sf ../usr/lib/os-release "${CHROOT_DIR}/etc/os-release"
cp -a --no-preserve=ownership "${REPO_ROOT}/apt/." "${CHROOT_DIR}/etc/apt/"
chown -R 0:0 "${CHROOT_DIR}/etc"
chgrp 42 "${CHROOT_DIR}/etc/shadow" "${CHROOT_DIR}/etc/gshadow" "${CHROOT_DIR}/etc/shadow-" "${CHROOT_DIR}/etc/gshadow-" 2>/dev/null || true
chmod 0640 "${CHROOT_DIR}/etc/shadow" "${CHROOT_DIR}/etc/gshadow" "${CHROOT_DIR}/etc/shadow-" "${CHROOT_DIR}/etc/gshadow-" 2>/dev/null || true
rm -f "${CHROOT_DIR}/etc/apt/sources.list" "${CHROOT_DIR}/etc/resolv.conf" \
      "${CHROOT_DIR}/usr/local/bin/ogust" \
      "${CHROOT_DIR}/usr/local/bin/ogust-install" \
      "${CHROOT_DIR}/usr/local/bin/ogust-calamares-postinstall" \
      "${CHROOT_DIR}/usr/local/bin/ogust-reboot"
cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

install -D -m 0755 "${REPO_ROOT}/bin/ogust" "${CHROOT_DIR}/usr/bin/ogust"
install -D -m 0755 "${REPO_ROOT}/bin/ogust-install" "${CHROOT_DIR}/usr/bin/ogust-install"
install -D -m 0755 "${REPO_ROOT}/bin/ogust-calamares-postinstall" "${CHROOT_DIR}/usr/bin/ogust-calamares-postinstall"
install -D -m 0755 "${REPO_ROOT}/bin/ogust-reboot" "${CHROOT_DIR}/usr/bin/ogust-reboot"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-ascii.txt" "${CHROOT_DIR}/usr/share/ogustos/ogustos-ascii.txt"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${CHROOT_DIR}/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${CHROOT_DIR}/usr/share/icons/hicolor/scalable/apps/start-here-kde.svg"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${CHROOT_DIR}/etc/calamares/branding/ogustos/ogustos-logo.svg"
install -D -m 0644 "${REPO_ROOT}/branding/wallpaper.jpg" "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg"
install -d "${CHROOT_DIR}/usr/share/plymouth/themes/ogustos"
install -m 0644 "${REPO_ROOT}"/plymouth/ogustos/* "${CHROOT_DIR}/usr/share/plymouth/themes/ogustos/"
mkdir -p "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images_dark"
cat > "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/metadata.json" <<'WPEOF'
{"KPlugin":{"Id":"ogustOS","Name":"ogustOS","License":"CC-BY-SA-4.0"}}
WPEOF
mkdir -p "${CHROOT_DIR}/usr/share/sddm/themes/breeze"
cat > "${CHROOT_DIR}/usr/share/sddm/themes/breeze/theme.conf.user" <<'SDDMEOF'
[General]
showlogo=shown
showClock=true
logo=/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg
type=image
color=#94042B
fontSize=10
background=/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg
needsFullUserModel=false
SDDMEOF
ln -sf ../images/3840x2160.jpg "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images_dark/3840x2160.jpg"

# Bundle Antigravity CLI (agy) & Antigravity Desktop GUI (/opt/Antigravity)
if [[ -x /usr/local/bin/agy ]]; then
    echo "[::] Bundling Antigravity CLI (/usr/local/bin/agy)..."
    install -D -m 0755 /usr/local/bin/agy "${CHROOT_DIR}/usr/local/bin/agy"
elif [[ -x /home/ogusto/.local/bin/agy ]]; then
    echo "[::] Bundling Antigravity CLI (/home/ogusto/.local/bin/agy -> /usr/local/bin/agy)..."
    install -D -m 0755 /home/ogusto/.local/bin/agy "${CHROOT_DIR}/usr/local/bin/agy"
fi

if [[ -d /opt/Antigravity ]]; then
    echo "[::] Bundling Antigravity Desktop GUI (/opt/Antigravity)..."
    mkdir -p "${CHROOT_DIR}/opt" "${CHROOT_DIR}/usr/local/bin"
    if [[ ! -x "${CHROOT_DIR}/opt/Antigravity/antigravity" ]]; then
        rm -rf "${CHROOT_DIR}/opt/Antigravity"
        cp -a /opt/Antigravity "${CHROOT_DIR}/opt/Antigravity"
    fi
    chown -R 0:0 "${CHROOT_DIR}/opt/Antigravity"
    chmod 4755 "${CHROOT_DIR}/opt/Antigravity/chrome-sandbox"
    ln -sfn /opt/Antigravity/antigravity "${CHROOT_DIR}/usr/local/bin/antigravity"
    [[ -f /usr/share/pixmaps/antigravity.png ]] && install -D -m 0644 /usr/share/pixmaps/antigravity.png "${CHROOT_DIR}/usr/share/pixmaps/antigravity.png"
    [[ -f /usr/share/icons/hicolor/512x512/apps/antigravity.png ]] && install -D -m 0644 /usr/share/icons/hicolor/512x512/apps/antigravity.png "${CHROOT_DIR}/usr/share/icons/hicolor/512x512/apps/antigravity.png"
    [[ -f /usr/share/applications/antigravity.desktop ]] && install -D -m 0644 /usr/share/applications/antigravity.desktop "${CHROOT_DIR}/usr/share/applications/antigravity.desktop"
fi

if [[ -x /usr/local/bin/claude ]]; then
    echo "[::] Bundling Claude Code (/usr/local/bin/claude)..."
    install -D -m 0755 /usr/local/bin/claude "${CHROOT_DIR}/usr/local/bin/claude"
fi

if [[ -d /opt/hermes ]]; then
    echo "[::] Bundling Hermes Agent (/opt/hermes & /usr/local/bin/hermes*)..."
    mkdir -p "${CHROOT_DIR}/opt" "${CHROOT_DIR}/usr/local/bin"
    if [[ ! -f "${CHROOT_DIR}/opt/hermes/manifest.json" ]]; then
        rm -rf "${CHROOT_DIR}/opt/hermes"
        cp -a /opt/hermes "${CHROOT_DIR}/opt/hermes"
    fi
    chown -R 0:0 "${CHROOT_DIR}/opt/hermes"
    chmod -R a+rX "${CHROOT_DIR}/opt/hermes"
    for hbin in hermes hermes-acp hermes-agent; do
        [[ -x "/usr/local/bin/${hbin}" ]] && install -D -m 0755 "/usr/local/bin/${hbin}" "${CHROOT_DIR}/usr/local/bin/${hbin}"
    done
fi

# ------------------------------------------------------------------------------
# 3. Chroot Package Installation (Manifest + Local ogustOS APT Repo + Defaults)
# ------------------------------------------------------------------------------
mkdir -p "${CHROOT_DIR}/tmp/ogustos-repo"
for dir in dev dev/pts proc sys run; do
    mountpoint -q "${CHROOT_DIR}/$dir" || mount --bind "/$dir" "${CHROOT_DIR}/$dir"
done
mountpoint -q "${CHROOT_DIR}/tmp/ogustos-repo" || mount --bind "${REPO_ROOT}/dist/repo" "${CHROOT_DIR}/tmp/ogustos-repo"

cleanup_iso_mounts() {
    for dir in tmp/ogustos-repo run sys proc dev/pts dev; do
        umount -lf "${CHROOT_DIR}/$dir" 2>/dev/null || true
    done
}
trap cleanup_iso_mounts EXIT

cat > "${CHROOT_DIR}/etc/apt/sources.list.d/01-ogustos.sources" <<'EOF'
Types: deb
URIs: file:///tmp/ogustos-repo
Suites: stable
Components: main
Architectures: amd64 i386
Trusted: yes
EOF

grep -vE '^\s*#|^\s*$' "${REPO_ROOT}/packages/manifest.txt" > "${CHROOT_DIR}/tmp/manifest.list"

chroot "$CHROOT_DIR" /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8 LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive /bin/bash -e <<'EOF'
# Prevent daemons from starting inside the chroot during package installation
cat > /usr/sbin/policy-rc.d <<'PRC'
#!/bin/sh
exit 101
PRC
chmod 0755 /usr/sbin/policy-rc.d

dpkg --add-architecture i386

# Fetch Google Chrome & Pardus signing keys
mkdir -p /usr/share/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --batch --yes --dearmor -o /usr/share/keyrings/google-chrome.gpg
curl -fsSL https://depo.pardus.org.tr/pardus/pool/main/p/pardus-archive-keyring/pardus-archive-keyring_2025.1_all.deb -o /tmp/pardus-keyring.deb
dpkg -i /tmp/pardus-keyring.deb
rm -f /tmp/pardus-keyring.deb

# Preseed EULA for non-interactive installation of Microsoft Core Fonts
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections

apt-get update

# Reinstall updated ogustos-base first (diverts /usr/lib/os-release & provides xserver)
apt-get install -y --reinstall ogustos-base
dpkg --configure -a
cat > /etc/apt/sources.list.d/01-ogustos.sources <<'REPEOF'
Types: deb
URIs: file:///tmp/ogustos-repo
Suites: stable
Components: main
Architectures: amd64 i386
Trusted: yes
REPEOF
apt-get update -o Dir::Etc::sourcelist="sources.list.d/01-ogustos.sources" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

# Install initramfs & live-boot tools first so kernel installation builds a complete initrd
apt-get install -y \
    initramfs-tools live-boot live-boot-initramfs-tools zstd \
    squashfs-tools parted fdisk udev kbd console-setup dosfstools e2fsprogs efibootmgr \
    calamares qml6-module-qtquick-window qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    os-prober cryptsetup cryptsetup-initramfs keyutils

# Install full ogustOS package manifest (with standard Debian Recommends enabled)
BLOAT_PKGS="$(dpkg -l | awk '/^ii/ {print $2}' | grep -E '^(kde-full|kde-standard|kdeedu|kdegames|kdepim|akonadi|kmail|kalendarac|merkuro|korganizer|kaddressbook|kalarm|dragonplayer|juk|k3b|kamera|kmag|kmousetool|kmouth|konqueror|ktimetracker|sweeper|libakonadi|libkpim)' || true)"
if [[ -n "$BLOAT_PKGS" ]]; then
    # shellcheck disable=SC2086
    apt-get purge -y $BLOAT_PKGS
fi
# Pre-fetch missing .deb archives in 16 parallel connections so Fastly single-stream throttling never slows the build
mkdir -p /var/cache/apt/archives
xargs -a /tmp/manifest.list apt-get install -y --print-uris \
    | awk -F"'" '/^'\''https?:\/\// {print $2, $4}' \
    | xargs -P 16 -n 2 bash -c '
        url="$1"; fn="$2"; dst="/var/cache/apt/archives/${fn}"
        [[ -s "$dst" ]] && exit 0
        curl -fsSL --retry 3 "$url" -o "${dst}.tmp.$$" && mv -f "${dst}.tmp.$$" "$dst" || rm -f "${dst}.tmp.$$"
    ' _

xargs -a /tmp/manifest.list apt-get install -y
apt-get dist-upgrade -y
apt-get install -y --allow-downgrades viewnior/stable 2>/dev/null || apt-get install -y viewnior 2>/dev/null || true
dpkg -i /tmp/ogustos-repo/pool/main/ogustos-base_*.deb \
        /tmp/ogustos-repo/pool/main/linux-image-*.deb \
        /tmp/ogustos-repo/pool/main/linux-headers-*.deb
apt-get purge -y 'exim4*' 'courier*' 2>/dev/null || true
BLOAT_PKGS="$(dpkg -l | awk '/^ii/ {print $2}' | grep -E '^(kde-full|kde-standard|kdeedu|kdegames|kdepim|akonadi|kmail|kalendarac|merkuro|korganizer|kaddressbook|kalarm|dragonplayer|juk|k3b|kamera|kmag|kmousetool|kmouth|konqueror|ktimetracker|sweeper|libakonadi|libkpim)' || true)"
if [[ -n "$BLOAT_PKGS" ]]; then
    # shellcheck disable=SC2086
    apt-get purge -y $BLOAT_PKGS
fi
dpkg --purge --force-all courier-mta courier-base courier-authdaemon courier-authlib libcourier-authlib0 libcourier-unicode12 2>/dev/null || true
userdel -r courier 2>/dev/null || true
groupdel courier 2>/dev/null || true
rm -rf /etc/courier /var/lib/courier /etc/xdg/autostart/org.kde.kalendarac.desktop
apt-get autoremove --purge -y 2>/dev/null || true
rc_pkgs="$(dpkg -l | awk '/^rc/ {print $2}')"
if [[ -n "$rc_pkgs" ]]; then
    # shellcheck disable=SC2086
    dpkg --purge $rc_pkgs 2>/dev/null || true
fi
rm -f /etc/kernel/postinst.d/zz-update-grub /etc/kernel/postrm.d/zz-update-grub

# Remove duplicate Google Chrome APT source file (keep 04-google-chrome.sources)
rm -f /etc/apt/sources.list.d/google-chrome.sources /etc/apt/sources.list.d/google-chrome.list

# Re-run ogustos-base postinst so wallpaper & binary symlinks (bat, fd) are applied
/var/lib/dpkg/info/ogustos-base.postinst configure

# Pre-configure Flathub remote for KDE Discover
if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
fi

# Generate full /etc/locale.gen from /usr/share/i18n/SUPPORTED so Calamares offers every world locale
if [[ -f /usr/share/i18n/SUPPORTED ]]; then
    sed 's/^/# /' /usr/share/i18n/SUPPORTED > /etc/locale.gen
    sed -i -E 's/^# (en_GB\.UTF-8 UTF-8|en_US\.UTF-8 UTF-8|tr_TR\.UTF-8 UTF-8)/\1/' /etc/locale.gen
else
    cat > /etc/locale.gen <<'LOC'
en_GB.UTF-8 UTF-8
en_US.UTF-8 UTF-8
tr_TR.UTF-8 UTF-8
LOC
fi
locale-gen

# Select the ogustOS Plymouth theme before the initramfs is (re)built
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme ogustos
fi

# Ensure initramfs is built with live-boot support for 7.3.x-ogustOS
KVER="$(ls -1 /lib/modules | sort -V | tail -n 1)"
update-initramfs -c -k "$KVER" || update-initramfs -u -k "$KVER"

# Remove any legacy X11 desktop session files so SDDM offers strictly Plasma Wayland
rm -f /usr/share/xsessions/*.desktop

# Enable core services, Bluetooth, mDNS printer discovery, weekly SSD fstrim, TTY NumLock, and UFW firewall
systemctl enable sddm NetworkManager systemd-resolved bluetooth avahi-daemon ufw chrony cups fstrim.timer ogustos-numlock-tty.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
if command -v ufw >/dev/null 2>&1; then
    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw logging off || true
    sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf 2>/dev/null || true
    sed -i 's/^LOGLEVEL=.*/LOGLEVEL=off/' /etc/ufw/ufw.conf 2>/dev/null || true
fi

dpkg --configure -a
ldconfig

rm -f /usr/sbin/policy-rc.d /tmp/manifest.list
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Stage local on-disk /var/lib/ogustos-repo (kernel, headers, firmware, mesa, ogustos-base)
rm -rf "${CHROOT_DIR}/var/lib/ogustos-repo/pool"
mkdir -p "${CHROOT_DIR}/var/lib/ogustos-repo/pool/main"
cp -a "${REPO_ROOT}/dist/repo/pool/main/." "${CHROOT_DIR}/var/lib/ogustos-repo/pool/main/" 2>/dev/null || true

cp -f "${REPO_ROOT}/apt/sources.list.d/01-ogustos.sources" "${CHROOT_DIR}/etc/apt/sources.list.d/01-ogustos.sources"

chroot "$CHROOT_DIR" /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8 /bin/bash -e <<'EOF'
cd /var/lib/ogustos-repo
mkdir -p dists/stable/main/binary-amd64 dists/stable/main/binary-i386
for arch in amd64 i386; do
    dpkg-scanpackages --multiversion --arch "$arch" "pool/main" > "dists/stable/main/binary-${arch}/Packages"
    gzip -9c "dists/stable/main/binary-${arch}/Packages" > "dists/stable/main/binary-${arch}/Packages.gz"
done
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="ogustOS" \
    -o APT::FTPArchive::Release::Label="ogustOS" \
    -o APT::FTPArchive::Release::Suite="stable" \
    -o APT::FTPArchive::Release::Codename="stable" \
    -o APT::FTPArchive::Release::Architectures="amd64 i386" \
    -o APT::FTPArchive::Release::Components="main" \
    release dists/stable > dists/stable/Release

# Pre-index the local on-disk repository in /var/lib/apt/lists so offline installs work on first boot
apt-get update -o Dir::Etc::sourcelist="sources.list.d/01-ogustos.sources" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

# Restore systemd-resolved stub symlink so DNSOverTLS & NetworkManager DNS work dynamically on target machines
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Restore _chrony group ownership on /etc/chrony/chrony.keys if chrony is installed
if [[ -f /etc/chrony/chrony.keys ]] && getent group _chrony >/dev/null 2>&1; then
    chgrp _chrony /etc/chrony/chrony.keys
    chmod 0640 /etc/chrony/chrony.keys
fi
EOF

cat > "${CHROOT_DIR}/etc/systemd/system/ogust-installer.service" <<'EOF'
[Unit]
Description=ogustOS Interactive Disk Installer
ConditionKernelCommandLine=boot=live
After=systemd-user-sessions.service
Before=getty@tty1.service
Conflicts=getty@tty1.service sddm.service

[Service]
Type=idle
ExecStart=/usr/bin/ogust-install
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "${CHROOT_DIR}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/ogust-installer.service "${CHROOT_DIR}/etc/systemd/system/multi-user.target.wants/ogust-installer.service"

cleanup_iso_mounts
rmdir "${CHROOT_DIR}/tmp/ogustos-repo" 2>/dev/null || true
find "$CHROOT_DIR" -uid 1000 -exec chown -h 0:0 {} +
find "$CHROOT_DIR" -gid 1000 -exec chgrp -h 0 {} +
# Enforce root:shadow (gid 42, mode 0640) on /etc/shadow and /etc/gshadow so kscreenlocker_greet / unix_chkpwd works
chown 0:42 "${CHROOT_DIR}/etc/shadow" "${CHROOT_DIR}/etc/gshadow" "${CHROOT_DIR}/etc/shadow-" "${CHROOT_DIR}/etc/gshadow-" 2>/dev/null || true
chmod 0640 "${CHROOT_DIR}/etc/shadow" "${CHROOT_DIR}/etc/gshadow" "${CHROOT_DIR}/etc/shadow-" "${CHROOT_DIR}/etc/gshadow-" 2>/dev/null || true
if [[ -f "${CHROOT_DIR}/usr/sbin/unix_chkpwd" ]]; then
    chown 0:42 "${CHROOT_DIR}/usr/sbin/unix_chkpwd"
    chmod 2755 "${CHROOT_DIR}/usr/sbin/unix_chkpwd"
fi
if [[ -f "${CHROOT_DIR}/opt/Antigravity/chrome-sandbox" ]]; then
    chown 0:0 "${CHROOT_DIR}/opt/Antigravity/chrome-sandbox"
    chmod 4755 "${CHROOT_DIR}/opt/Antigravity/chrome-sandbox"
fi
chroot "$CHROOT_DIR" ldconfig
chroot "$CHROOT_DIR" systemd-hwdb update 2>/dev/null || true
chroot "$CHROOT_DIR" journalctl --update-catalog 2>/dev/null || true
touch "${CHROOT_DIR}/etc/.updated" "${CHROOT_DIR}/var/.updated"

# ------------------------------------------------------------------------------
# 4. Prepare Instant-Boot USB Kernel & Initrd (timeout 0 -> tty1 -> ogust-install)
# ------------------------------------------------------------------------------
KVER="$(ls -1 "${CHROOT_DIR}/boot" | sed -n 's/^vmlinuz-//p' | sort -V | tail -n 1)"
cp -f "${CHROOT_DIR}/boot/vmlinuz-${KVER}" "${ISO_DIR}/live/vmlinuz"
cp -f "${CHROOT_DIR}/boot/initrd.img-${KVER}" "${ISO_DIR}/live/initrd.img"

# ------------------------------------------------------------------------------
# 5. Build Pure-Data Target SquashFS (Clean Installed System Image)
# ------------------------------------------------------------------------------
echo "[::] Compressing clean rootfs into ${ISO_DIR}/live/filesystem.squashfs..."
rm -f "${ISO_DIR}/live/filesystem.squashfs"
mksquashfs "$CHROOT_DIR" "${ISO_DIR}/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 9 -noappend \
    -wildcards -e "boot/vmlinuz-*" "boot/initrd.img-*"

cp -f "${CHROOT_DIR}/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"

cat > "${ISO_DIR}/loader/loader.conf" <<'EOF'
default ogustos-installer.conf
timeout 0
console-mode max
editor no
EOF

cat > "${ISO_DIR}/loader/entries/ogustos-installer.conf" <<'EOF'
title   ogustOS KDE Installer
linux   /live/vmlinuz
initrd  /live/initrd.img
options boot=live quiet splash loglevel=0 systemd.unit=multi-user.target
EOF

# ------------------------------------------------------------------------------
# 6. Generate Bootable UEFI Hybrid ISO Image (GPT + 256M EFI System Partition)
# ------------------------------------------------------------------------------
echo "[::] Building hybrid UEFI ISO at ${OUT_ISO}..."
EFI_IMG="${WORK_DIR}/efiboot.img"
rm -f "$EFI_IMG"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=256
mkfs.vfat -F 32 "$EFI_IMG"
mmd -i "$EFI_IMG" ::/EFI ::/EFI/BOOT ::/loader ::/loader/entries ::/live
mcopy -i "$EFI_IMG" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$EFI_IMG" "${ISO_DIR}/loader/loader.conf" ::/loader/loader.conf
mcopy -i "$EFI_IMG" "${ISO_DIR}/loader/entries/ogustos-installer.conf" ::/loader/entries/ogustos-installer.conf
mcopy -i "$EFI_IMG" "${ISO_DIR}/live/vmlinuz" ::/live/vmlinuz
mcopy -i "$EFI_IMG" "${ISO_DIR}/live/initrd.img" ::/live/initrd.img

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "OGUSTOS_KDE" \
    -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$EFI_IMG" \
    -appended_part_as_gpt \
    -partition_offset 16 \
    -output "$OUT_ISO" \
    "$ISO_DIR"

echo "----------------------------------------------------------------"
echo "[::] Bootable ogustOS ISO built: ${OUT_ISO}"
ls -lh "$OUT_ISO"
