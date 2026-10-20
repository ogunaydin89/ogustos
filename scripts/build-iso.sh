#!/usr/bin/env bash
# ==============================================================================
# build-iso.sh — Assembles the ogustOS Offline SquashFS & Instant-Boot USB ISO
# Boots straight into ogust-install on tty1 (timeout 0, no boot menu, no Live GUI)
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/var/tmp/ogustos-iso-work}"
CHROOT_DIR="${WORK_DIR}/chroot"
ISO_DIR="${WORK_DIR}/iso"

echo "[::] ogustOS ISO Builder"
echo "     1. Bootstraps Debian Testing + Pardus 25 + ogustOS 3-repo rootfs into ${CHROOT_DIR}"
echo "     2. Installs packages/manifest.txt + linux-image-7.3.x-ogustOS"
echo "     3. Compresses ${CHROOT_DIR} into ${ISO_DIR}/live/filesystem.squashfs (zstd -Xcompression-level 19)"
echo "     4. Configures systemd-boot (timeout 0) + getty@tty1 -> /usr/bin/ogust-install"
echo "     5. Generates hybrid UEFI bootable image: ogustOS-kde-amd64.iso"
