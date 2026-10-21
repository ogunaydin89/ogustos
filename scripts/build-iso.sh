#!/usr/bin/env bash
# ==============================================================================
# build-iso.sh — End-to-End ogustOS Offline SquashFS & Instant-Boot USB Builder
# Boots straight into ogust-install on tty1 (timeout 0, no boot menu, no Live GUI)
# Pre-installs 7.3-ogustOS Kernel, KDE Plasma 6.8+ Wayland, Chrome, Steam, & agy.
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
    debootstrap --no-check-gpg --arch=amd64 --variant=minbase \
        --include=ca-certificates,curl,gnupg,debian-archive-keyring,locales \
        testing "$CHROOT_DIR" https://deb.debian.org/debian
fi

# ------------------------------------------------------------------------------
# 2. Overlay ogustOS Configurations, Branding, APT Pinning & Scripts
# ------------------------------------------------------------------------------
echo "[::] Applying ogustOS /etc, APT 3-repo pinning, branding, and CLI tools..."
cp -a --no-preserve=ownership "${REPO_ROOT}/etc/." "${CHROOT_DIR}/etc/"
ln -sf ../usr/lib/os-release "${CHROOT_DIR}/etc/os-release"
cp -a --no-preserve=ownership "${REPO_ROOT}/apt/." "${CHROOT_DIR}/etc/apt/"
chown -R 0:0 "${CHROOT_DIR}/etc"
rm -f "${CHROOT_DIR}/etc/apt/sources.list"
cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

install -D -m 0755 "${REPO_ROOT}/bin/ogust" "${CHROOT_DIR}/usr/bin/ogust"
install -D -m 0755 "${REPO_ROOT}/bin/ogust-install" "${CHROOT_DIR}/usr/bin/ogust-install"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-ascii.txt" "${CHROOT_DIR}/usr/share/ogustos/ogustos-ascii.txt"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${CHROOT_DIR}/usr/share/icons/hicolor/scalable/apps/ogustos-logo.svg"
install -D -m 0644 "${REPO_ROOT}/branding/ogustos-logo.svg" "${CHROOT_DIR}/usr/share/icons/hicolor/scalable/apps/start-here-kde.svg"
install -D -m 0644 "${REPO_ROOT}/branding/wallpaper.jpg" "${CHROOT_DIR}/usr/share/wallpapers/ogustOS/contents/images/3840x2160.jpg"

if [[ -x /usr/local/bin/agy ]]; then
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
apt-get install -y --reinstall --no-install-recommends ogustos-base
dpkg --configure -a

# Install initramfs & live-boot tools first so kernel installation builds a complete initrd
apt-get install -y --no-install-recommends \
    initramfs-tools live-boot live-boot-initramfs-tools zstd \
    squashfs-tools parted fdisk udev kbd console-setup dosfstools e2fsprogs efibootmgr

# Install full ogustOS package manifest (--no-install-recommends enforced)
xargs -a /tmp/manifest.list apt-get install -y --no-install-recommends

# Remove legacy Xorg server packages if any were pulled in earlier
apt-get purge -y 'xserver-xorg*' 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Generate locales
cat > /etc/locale.gen <<'LOC'
en_US.UTF-8 UTF-8
tr_TR.UTF-8 UTF-8
LOC
locale-gen

# Ensure initramfs is built with live-boot support for 7.3.x-ogustOS
KVER="$(ls -1 /lib/modules | sort -V | tail -n 1)"
update-initramfs -c -k "$KVER" || update-initramfs -u -k "$KVER"

# Remove any legacy X11 desktop session files so SDDM offers strictly Plasma Wayland
rm -f /usr/share/xsessions/*.desktop

# Enable core services and mask network-wait-online
systemctl enable sddm NetworkManager systemd-resolved ufw chrony cups 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

rm -f /usr/sbin/policy-rc.d /tmp/manifest.list
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Restore canonical 01-ogustos.sources and install live USB tty1 installer unit
cp -f "${REPO_ROOT}/apt/sources.list.d/01-ogustos.sources" "${CHROOT_DIR}/etc/apt/sources.list.d/01-ogustos.sources"

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
    -e boot/vmlinuz-* boot/initrd.img-*

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

echo "────────────────────────────────────────────────────────────────"
echo "[::] Bootable ogustOS ISO built: ${OUT_ISO}"
ls -lh "$OUT_ISO"
