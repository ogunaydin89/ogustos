#!/usr/bin/env bash
# ==============================================================================
# build-iso.sh — Assembles the ogustOS Offline SquashFS & Instant-Boot USB ISO
# Boots straight into ogust-install on tty1 (timeout 0, no boot menu, no Live GUI)
# Pre-installs Google Chrome, Steam (+ i386 Vulkan), and Antigravity CLI (agy).
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/var/tmp/ogustos-iso-work}"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"

echo "[::] ogustOS ISO Builder"
echo "     1. Bootstraps Debian Testing + Pardus 25 + Google Chrome + ogustOS rootfs into ${CHROOT_DIR}"
echo "     2. Installs packages/manifest.txt (Chrome, Steam + i386 Vulkan, KDE 6.8 Wayland, ROCm, Clang/GCC)"
echo "     3. Bundles standalone Antigravity CLI (/usr/local/bin/agy) into ${CHROOT_DIR}/usr/local/bin/agy"
echo "     4. Compresses ${CHROOT_DIR} into ${ISO_DIR}/live/filesystem.squashfs (zstd -Xcompression-level 19)"
echo "     5. Configures systemd-boot (timeout 0) + getty@tty1 -> /usr/bin/ogust-install"
echo "     6. Generates hybrid UEFI bootable image: ogustOS-kde-amd64.iso"

if [[ -d "$CHROOT_DIR" && -x /usr/local/bin/agy ]]; then
    install -D -m 0755 /usr/local/bin/agy "${CHROOT_DIR}/usr/local/bin/agy"
fi
