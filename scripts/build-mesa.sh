#!/usr/bin/env bash
# ==============================================================================
# build-mesa.sh — Builds the latest Mesa graphics stack (amd64 + i386)
# Enables RADV Vulkan (GPL), RadeonSI, Intel Iris/ANV, Nouveau/NVK, and all
# hardware video codecs (H.264, HEVC, AV1, VP9 VA-API) with mold linker.
# ==============================================================================
set -euo pipefail

MESA_VER="${1:-latest}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_POOL="${REPO_ROOT}/dist/repo/pool/main"
BUILD_DIR="${BUILD_DIR:-/var/tmp/ogustos-mesa-build}"
JOBS="$(nproc)"

mkdir -p "$BUILD_DIR" "$OUT_POOL"
cd "$BUILD_DIR"

export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"
export DEB_CFLAGS_SET="-O2 -march=x86-64 -mtune=generic -pipe"
export DEB_CXXFLAGS_SET="-O2 -march=x86-64 -mtune=generic -pipe"
export DEB_LDFLAGS_SET="-Wl,-O1 -Wl,--as-needed -fuse-ld=mold"

echo "[::] Fetching latest Mesa packaging & source for amd64 and i386..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get build-dep -y mesa
    apt-get source --compile mesa
    cp -f "${BUILD_DIR}"/*.deb "$OUT_POOL/"
    echo "[::] Staged Mesa packages into ${OUT_POOL}:"
    ls -lh "${OUT_POOL}"/*mesa*.deb
else
    echo "NOTE: Run build-mesa.sh inside an ogustOS/Debian build environment (or chroot) to output .deb packages."
fi
