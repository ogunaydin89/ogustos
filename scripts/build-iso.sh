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
    debootstrap --arch=amd64 --variant=minbase testing "$CHROOT_DIR" https://deb.debian.org/debian
fi

# ------------------------------------------------------------------------------
# 2. Overlay ogustOS Configurations, Branding, APT Pinning & Scripts
# ------------------------------------------------------------------------------
echo "[::] Applying ogustOS /etc, APT 3-repo pinning, branding, and CLI tools..."
cp -a "${REPO_ROOT}/etc/." "${CHROOT_DIR}/etc/"
cp -a "${REPO_ROOT}/apt/." "${CHROOT_DIR}/etc/apt/"
rm -f "${CHROOT_DIR}/etc/apt/sources.list"

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

# Copy locally built 7.3-ogustOS kernel & custom .deb packages into chroot staging
mkdir -p "${CHROOT_DIR}/tmp/ogustos-debs"
if compgen -G "${REPO_ROOT}/dist/repo/pool/*/*.deb" >/dev/null; then
    cp -f "${REPO_ROOT}"/dist/repo/pool/*/*.deb "${CHROOT_DIR}/tmp/ogustos-debs/"
fi
if compgen -G "/var/tmp/ogustos-kernel-build/linux-*.deb" >/dev/null; then
    cp -f /var/tmp/ogustos-kernel-build/linux-*.deb "${CHROOT_DIR}/tmp/ogustos-debs/"
fi

# ------------------------------------------------------------------------------
# 3. Chroot Package Installation (Manifest + Custom .debs + Defaults)
# ------------------------------------------------------------------------------
for dir in dev dev/pts proc sys run; do
    mountpoint -q "${CHROOT_DIR}/$dir" || mount --bind "/$dir" "${CHROOT_DIR}/$dir"
done

grep -vE '^\s*#|^\s*$' "${REPO_ROOT}/packages/manifest.txt" > "${CHROOT_DIR}/tmp/manifest.list"

chroot "$CHROOT_DIR" /bin/bash -e <<'EOF'
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386

# Fetch Google Chrome & Pardus signing keys if not present
mkdir -p /usr/share/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg || true

apt-get update

# Install locally built 7.3-ogustOS kernel & ogustOS .debs first
if compgen -G "/tmp/ogustos-debs/*.deb" >/dev/null; then
    apt-get install -y --no-install-recommends /tmp/ogustos-debs/*.deb
fi

# Install manifest packages + live-boot support for ISO booting
xargs -a /tmp/manifest.list apt-get install -y --no-install-recommends
apt-get install -y --no-install-recommends live-boot squashfs-tools parted dosfstools e2fsprogs

# Enable core services and mask network-wait-online
systemctl enable sddm NetworkManager systemd-resolved ufw chrony cups
systemctl mask systemd-networkd-wait-online.service

rm -rf /tmp/ogustos-debs /tmp/manifest.list
apt-get clean
EOF

for dir in run sys proc dev/pts dev; do
    umount -lf "${CHROOT_DIR}/$dir" 2>/dev/null || true
done

# ------------------------------------------------------------------------------
# 4. Build Pure-Data Target SquashFS (Clean Installed System Image)
# ------------------------------------------------------------------------------
echo "[::] Compressing clean rootfs into ${ISO_DIR}/live/filesystem.squashfs..."
rm -f "${ISO_DIR}/live/filesystem.squashfs"
mksquashfs "$CHROOT_DIR" "${ISO_DIR}/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 19 -noappend \
    -e boot/vmlinuz-* boot/initrd.img-*

# ------------------------------------------------------------------------------
# 5. Prepare Instant-Boot USB Environment (timeout 0 -> tty1 -> ogust-install)
# ------------------------------------------------------------------------------
KVER="$(ls -1 "${CHROOT_DIR}/boot" | sed -n 's/^vmlinuz-//p' | sort -V | tail -n 1)"
cp -f "${CHROOT_DIR}/boot/vmlinuz-${KVER}" "${ISO_DIR}/live/vmlinuz"
cp -f "${CHROOT_DIR}/boot/initrd.img-${KVER}" "${ISO_DIR}/live/initrd.img"

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
options boot=live quiet loglevel=0 systemd.unit=multi-user.target systemd.run=/usr/bin/ogust-install
EOF

# ------------------------------------------------------------------------------
# 6. Generate Bootable UEFI Hybrid ISO Image
# ------------------------------------------------------------------------------
echo "[::] Building hybrid UEFI ISO at ${OUT_ISO}..."
EFI_IMG="${ISO_DIR}/boot/efiboot.img"
mkdir -p "${ISO_DIR}/boot"
dd if=/dev/zero of="$EFI_IMG" bs=1M count=64
mkfs.vfat -F 32 "$EFI_IMG"
mmd -i "$EFI_IMG" ::/EFI ::/EFI/BOOT ::/loader ::/loader/entries ::/live
mcopy -i "$EFI_IMG" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$EFI_IMG" "${ISO_DIR}/loader/loader.conf" ::/loader/loader.conf
mcopy -i "$EFI_IMG" "${ISO_DIR}/loader/entries/ogustos-installer.conf" ::/loader/entries/ogustos-installer.conf

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "OGUSTOS_KDE" \
    -eltorito-alt-boot \
    -e boot/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output "$OUT_ISO" \
    "$ISO_DIR"

echo "────────────────────────────────────────────────────────────────"
echo "[::] Bootable ogustOS ISO built: ${OUT_ISO}"
ls -lh "$OUT_ISO"
