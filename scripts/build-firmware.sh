#!/usr/bin/env bash
# ==============================================================================
# build-firmware.sh — Packages the latest upstream kernel.org linux-firmware
# Auto-detects the newest snapshot on cdn.kernel.org/pub/linux/kernel/firmware/
# and stages into /usr/lib/firmware (merged-/usr compliant).
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_POOL="${REPO_ROOT}/dist/repo/pool/main"
if mountpoint -q /var/tmp/build; then
    BUILD_DIR="${BUILD_DIR:-/var/tmp/build/ogustos-firmware-build}"
else
    BUILD_DIR="${BUILD_DIR:-/var/tmp/ogustos-firmware-build}"
fi

mkdir -p "$BUILD_DIR" "$OUT_POOL"
cd "$BUILD_DIR"

SHA_ASC="$(curl -fsSL https://cdn.kernel.org/pub/linux/kernel/firmware/sha256sums.asc)"
if [[ -n "${1:-}" ]]; then
    FW_DATE="$1"
else
    FW_DATE="$(awk '/linux-firmware-[0-9]+\.tar\.gz$/ {print $2}' <<<"$SHA_ASC" | sed -E 's/linux-firmware-([0-9]+)\.tar\.gz/\1/' | sort -n | tail -n 1)"
fi

TARBALL="linux-firmware-${FW_DATE}.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
    echo "[::] Downloading ${TARBALL} from kernel.org..."
    curl -fLO "https://cdn.kernel.org/pub/linux/kernel/firmware/${TARBALL}"
fi
grep "  ${TARBALL}\$" <<<"$SHA_ASC" | sha256sum -c -

STAGE="${BUILD_DIR}/stage-linux-firmware"
rm -rf "$STAGE" "linux-firmware-${FW_DATE}"
mkdir -p "${STAGE}/DEBIAN" "${STAGE}/usr/lib/firmware"

tar -xf "$TARBALL"
cd "linux-firmware-${FW_DATE}"

echo "[::] Installing firmware blobs into ${STAGE}/usr/lib/firmware..."
./copy-firmware.sh "${STAGE}/usr/lib/firmware"

cat > "${STAGE}/DEBIAN/control" <<EOF
Package: linux-firmware
Version: ${FW_DATE}-1ogustos1
Section: kernel
Priority: optional
Architecture: all
Provides: firmware-amd-graphics, firmware-misc-nonfree, firmware-iwlwifi, firmware-realtek, firmware-intel-sound, firmware-sof-signed
Conflicts: firmware-amd-graphics, firmware-misc-nonfree, firmware-iwlwifi, firmware-realtek
Replaces: firmware-amd-graphics, firmware-misc-nonfree, firmware-iwlwifi, firmware-realtek
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Upstream kernel.org Linux firmware snapshot for ogustOS (${FW_DATE})
EOF

rm -f "${OUT_POOL}/linux-firmware_"*.deb
dpkg-deb -Zxz -z6 --build --root-owner-group "$STAGE" "${OUT_POOL}/linux-firmware_${FW_DATE}-1ogustos1_all.deb"
echo "[::] Built ${OUT_POOL}/linux-firmware_${FW_DATE}-1ogustos1_all.deb"
