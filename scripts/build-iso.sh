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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/var/tmp/ogustos-iso-work}"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"
OUT_ISO="${REPO_ROOT}/dist/ogustOS-kde-amd64.iso"

mkdir -p "$WORK_DIR" "${ISO_DIR}/live" "${ISO_DIR}/EFI/BOOT" "${ISO_DIR}/loader/entries" "${REPO_ROOT}/dist"

# ------------------------------------------------------------------------------
# 1. Bootstrap Base Rootfs (Debian Testing amd64)
# ------------------------------------------------------------------------------
if [[ ! -d "${CHROOT_DIR}/etc" ]]; then
    echo "[::] Bootstrapping Debian Testing base rootfs into ${CHROOT_DIR}..."
    KEYRING_ARG="--no-check-gpg"
    [[ -f /usr/share/keyrings/debian-archive-keyring.gpg ]] && KEYRING_ARG="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
    debootstrap "$KEYRING_ARG" --arch=amd64 --variant=minbase \
        --include=ca-certificates,curl,gnupg,debian-archive-keyring,locales \
        testing "$CHROOT_DIR" https://deb.debian.org/debian
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
chmod 0440 "${CHROOT_DIR}/etc/sudoers.d/99-ogustos-nopasswd" 2>/dev/null || true
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
mkdir -p "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images_dark"
ln -sf ../images/3840x2160.jpg "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images_dark/3840x2160.jpg"

if [[ "${BUNDLE_AGY:-0}" == "1" && -x /usr/local/bin/agy ]]; then
    echo "[::] Bundling Antigravity CLI (/usr/local/bin/agy)..."
    install -D -m 0755 /usr/local/bin/agy "${CHROOT_DIR}/usr/local/bin/agy"
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
Components: main apps
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

# Preseed EULAs for non-interactive installation of Microsoft Core Fonts & Steam
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections
echo "steam steam/question select I AGREE" | debconf-set-selections
echo "steam steam/license note ''" | debconf-set-selections

apt-get update

# Reinstall updated ogustos-base first (diverts /usr/lib/os-release & provides xserver)
apt-get install -y --reinstall ogustos-base
dpkg --configure -a

# Install initramfs & live-boot tools first so kernel installation builds a complete initrd
apt-get install -y \
    initramfs-tools live-boot live-boot-initramfs-tools zstd \
    squashfs-tools parted fdisk udev kbd console-setup dosfstools e2fsprogs efibootmgr \
    calamares qml6-module-qtquick-window qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    os-prober cryptsetup cryptsetup-initramfs keyutils

# Install full ogustOS package manifest (with standard Debian Recommends enabled)
xargs -a /tmp/manifest.list apt-get install -y
apt-get dist-upgrade -y
apt-get install -y --allow-downgrades viewnior/forky 2>/dev/null || apt-get install -y --allow-downgrades viewnior/testing 2>/dev/null || true
dpkg -i /tmp/ogustos-repo/pool/main/ogustos-base_*.deb \
        /tmp/ogustos-repo/pool/main/linux-image-*.deb \
        /tmp/ogustos-repo/pool/main/linux-headers-*.deb \
        /tmp/ogustos-repo/pool/apps/emerge-pdf_*.deb \
        /tmp/ogustos-repo/pool/apps/libreoffice-fresh_*.deb
apt-get purge -y 'exim4*' 'courier*' 2>/dev/null || true
dpkg --purge --force-all courier-mta courier-base courier-authdaemon courier-authlib libcourier-authlib0 libcourier-unicode12 2>/dev/null || true
userdel -r courier 2>/dev/null || true
groupdel courier 2>/dev/null || true
rm -rf /etc/courier /var/lib/courier
apt-get autoremove -y 2>/dev/null || true
rc_pkgs="$(dpkg -l | awk '/^rc/ {print $2}')"
if [[ -n "$rc_pkgs" ]]; then
    # shellcheck disable=SC2086
    dpkg --purge $rc_pkgs 2>/dev/null || true
fi
rm -f /etc/kernel/postinst.d/zz-update-grub /etc/kernel/postrm.d/zz-update-grub

# Remove duplicate Google Chrome APT source file (keep 04-google-chrome.sources)
rm -f /etc/apt/sources.list.d/google-chrome.sources /etc/apt/sources.list.d/google-chrome.list

# Re-run ogustos-base postinst so wallpaper & binary symlinks (bat, fd) are applied over kde-full
/var/lib/dpkg/info/ogustos-base.postinst configure

# Pre-stage official Valve Steam icons, StartupWMClass=steam desktop file, and bootstrapper archive
if [[ -x /usr/games/steam ]]; then
    mkdir -p /usr/share/steam /tmp/steam-stage
    STEAM_TAR="/usr/share/steam/steam_1.0.0.87.tar.gz"
    if [[ ! -f "$STEAM_TAR" ]]; then
        curl -fsSL "https://repo.steampowered.com/steam/archive/beta/steam_1.0.0.87.tar.gz" -o "$STEAM_TAR" || true
    fi
    if [[ -f "$STEAM_TAR" ]]; then
        tar -C /tmp/steam-stage -zxf "$STEAM_TAR" steam-launcher/icons steam-launcher/steam.desktop 2>/dev/null || true
        for i in 16 24 32 48 256; do
            mkdir -p "/usr/share/icons/hicolor/${i}x${i}/apps"
            if [[ -f "/tmp/steam-stage/steam-launcher/icons/${i}/steam.png" ]]; then
                cp -f "/tmp/steam-stage/steam-launcher/icons/${i}/steam.png" "/usr/share/icons/hicolor/${i}x${i}/apps/steam.png"
            fi
            if [[ -f "/tmp/steam-stage/steam-launcher/icons/${i}/steam_tray_mono.png" ]]; then
                cp -f "/tmp/steam-stage/steam-launcher/icons/${i}/steam_tray_mono.png" "/usr/share/icons/hicolor/${i}x${i}/apps/steam_tray_mono.png"
            fi
        done
        mkdir -p /usr/share/icons/breeze/apps/48 /usr/share/icons/breeze-dark/apps/48
        cp -f /usr/share/icons/hicolor/48x48/apps/steam.png /usr/share/icons/breeze/apps/48/steam.png 2>/dev/null || true
        cp -f /usr/share/icons/hicolor/48x48/apps/steam.png /usr/share/icons/breeze-dark/apps/48/steam.png 2>/dev/null || true
        if [[ -f /tmp/steam-stage/steam-launcher/steam.desktop ]]; then
            sed -e '/^Exec=/ s,/usr/bin/steam,/usr/games/steam,g' \
                -e 's,^Exec=steam ,Exec=/usr/games/steam ,' \
                -e '/^Icon=steam/a StartupWMClass=steam' \
                /tmp/steam-stage/steam-launcher/steam.desktop > /usr/share/applications/steam.desktop
        fi
        rm -rf /tmp/steam-stage
    fi
    if ! grep -q '^StartupWMClass=steam' /usr/share/applications/steam.desktop 2>/dev/null; then
        echo "StartupWMClass=steam" >> /usr/share/applications/steam.desktop
    fi
    sed -i 's/^Name=Install Steam/Name=Steam/' /usr/share/applications/steam.desktop 2>/dev/null || true
    # Patch /usr/games/steam to use pre-staged archive without Zenity nag, add StartupWMClass=steam, and copy files instead of symlinks
    sed -i 's/if \[ -n "\$new_installation" \]; then/if [ -n "$new_installation" ] \&\& [ ! -f "\/usr\/share\/steam\/steam_${version}.tar.gz" ]; then/' /usr/games/steam 2>/dev/null || true
    sed -i 's|curl -o "\$STEAMDIR/deb-installer/steam_\${version}.tar.gz.\$\$" "\$url"|if [ -f "/usr/share/steam/steam_${version}.tar.gz" ]; then cp -f "/usr/share/steam/steam_${version}.tar.gz" "$STEAMDIR/deb-installer/steam_${version}.tar.gz.$$"; else curl -o "$STEAMDIR/deb-installer/steam_${version}.tar.gz.$$" "$url"; fi|' /usr/games/steam 2>/dev/null || true
    sed -i "s|-e '/^Actions=/ a Keywords=Games'|-e '/^Actions=/ a Keywords=Games\\\\nStartupWMClass=steam'|" /usr/games/steam 2>/dev/null || true
    sed -i 's/ln -fns "\$target" "\$dest"/cp -f "$target" "$dest"/g' /usr/games/steam 2>/dev/null || true
fi

# Pre-build EmergePDF offline virtualenv (with pillow-heif) so first launch is instant & 100% offline
if [[ -d /usr/share/emerge-pdf ]]; then
    rm -rf /usr/share/emerge-pdf/venv
    python3 -m venv --system-site-packages /usr/share/emerge-pdf/venv
    /usr/share/emerge-pdf/venv/bin/pip install --disable-pip-version-check --no-input pillow-heif || true
fi

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

# Ensure initramfs is built with live-boot support for 7.3.x-ogustOS
KVER="$(ls -1 /lib/modules | sort -V | tail -n 1)"
update-initramfs -c -k "$KVER" || update-initramfs -u -k "$KVER"

# Remove any legacy X11 desktop session files so SDDM offers strictly Plasma Wayland
rm -f /usr/share/xsessions/*.desktop

# Enable core services, Bluetooth, mDNS printer discovery, weekly SSD fstrim, and UFW firewall
systemctl enable sddm NetworkManager systemd-resolved bluetooth avahi-daemon ufw chrony cups fstrim.timer 2>/dev/null || true
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

# Stage local on-disk /var/lib/ogustos-repo (apps + kernel & base packages) so
# 'ogust up' and offline 'ogust in meb-sertifika' always work without network/TLS chicken-and-egg
rm -rf "${CHROOT_DIR}/var/lib/ogustos-repo/pool"
mkdir -p "${CHROOT_DIR}/var/lib/ogustos-repo/pool/main" "${CHROOT_DIR}/var/lib/ogustos-repo/pool/apps"
cp -a "${REPO_ROOT}/dist/repo/pool/apps/." "${CHROOT_DIR}/var/lib/ogustos-repo/pool/apps/"
cp -a "${REPO_ROOT}/dist/repo/pool/main/ogustos-base_"*.deb \
      "${REPO_ROOT}/dist/repo/pool/main/linux-image-"*.deb \
      "${REPO_ROOT}/dist/repo/pool/main/linux-headers-"*.deb \
      "${CHROOT_DIR}/var/lib/ogustos-repo/pool/main/" 2>/dev/null || true

cp -f "${REPO_ROOT}/apt/sources.list.d/01-ogustos.sources" "${CHROOT_DIR}/etc/apt/sources.list.d/01-ogustos.sources"

chroot "$CHROOT_DIR" /usr/bin/env -i HOME=/root TERM=xterm PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C.UTF-8 /bin/bash -e <<'EOF'
cd /var/lib/ogustos-repo
mkdir -p dists/stable/main/binary-amd64 dists/stable/apps/binary-amd64 \
         dists/stable/main/binary-i386  dists/stable/apps/binary-i386
for comp in main apps; do
    for arch in amd64 i386; do
        dpkg-scanpackages --multiversion --arch "$arch" "pool/${comp}" > "dists/stable/${comp}/binary-${arch}/Packages"
        gzip -9c "dists/stable/${comp}/binary-${arch}/Packages" > "dists/stable/${comp}/binary-${arch}/Packages.gz"
    done
done
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="ogustOS" \
    -o APT::FTPArchive::Release::Label="ogustOS" \
    -o APT::FTPArchive::Release::Suite="stable" \
    -o APT::FTPArchive::Release::Codename="stable" \
    -o APT::FTPArchive::Release::Architectures="amd64 i386" \
    -o APT::FTPArchive::Release::Components="main apps" \
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
    -comp zstd -Xcompression-level 19 -noappend \
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
options boot=live quiet loglevel=0 systemd.unit=multi-user.target
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
