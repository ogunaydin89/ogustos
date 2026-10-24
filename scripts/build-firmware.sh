#!/usr/bin/env bash
# ==============================================================================
# build-firmware.sh — Packages the latest upstream kernel.org linux-firmware
# Ensures RDNA 2 / RDNA 3 / RDNA 4 (amdgpu), Intel, Wi-Fi, and CPU microcode
# blobs in ogustOS are always at the latest upstream snapshot.
# ==============================================================================
set -euo pipefail

FW_DATE="${1:-20261019}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_POOL="${REPO_ROOT}/dist/repo/pool/main"
BUILD_DIR="${BUILD_DIR:-/var/tmp/ogustos-firmware-build}"

mkdir -p "$BUILD_DIR" "$OUT_POOL"
cd "$BUILD_DIR"

TARBALL="linux-firmware-${FW_DATE}.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
    echo "[::] Downloading linux-firmware-${FW_DATE} from kernel.org..."
    curl -fLO "https://cdn.kernel.org/pub/linux/kernel/firmware/${TARBALL}"
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/firmware/sha256sums.asc" | grep "  ${TARBALL}\$" | sha256sum -c -
fi

STAGE="${BUILD_DIR}/stage-linux-firmware"
rm -rf "$STAGE" "linux-firmware-${FW_DATE}"
mkdir -p "${STAGE}/DEBIAN" "${STAGE}/lib/firmware"

tar -xf "$TARBALL"
cd "linux-firmware-${FW_DATE}"

echo "[::] Installing firmware blobs into staging tree..."
./copy-firmware.sh "${STAGE}/lib/firmware"

cat > "${STAGE}/DEBIAN/control" <<EOF
Package: linux-firmware
Version: ${FW_DATE}-1ogustos1
Section: kernel
Priority: optional
Architecture: all
Provides: firmware-amd-graphics, firmware-misc-nonfree, firmware-iwlwifi, firmware-realtek
Conflicts: firmware-amd-graphics, firmware-misc-nonfree
Replaces: firmware-amd-graphics, firmware-misc-nonfree
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Upstream kernel.org Linux firmware snapshot for ogustOS (${FW_DATE})
EOF

dpkg-deb -Zxz -z6 --build --root-owner-group "$STAGE" "${OUT_POOL}/linux-firmware_${FW_DATE}-1ogustos1_all.deb"
echo "[::] Built ${OUT_POOL}/linux-firmware_${FW_DATE}-1ogustos1_all.deb"
