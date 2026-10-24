#!/usr/bin/env bash
# ==============================================================================
# build-mesa.sh — Builds the latest upstream Mesa graphics stack (amd64 + i386)
# Auto-detects the newest stable release on archive.mesa3d.org, overlays Debian
# packaging metadata, and compiles both amd64 and i386 .deb packages in lockstep
# with RADV Vulkan (GPL), RadeonSI, Intel Iris/ANV, NVK, and full VA-API codecs.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_POOL="${REPO_ROOT}/dist/repo/pool/main"
if mountpoint -q /var/tmp/build; then
    BUILD_DIR="${BUILD_DIR:-/var/tmp/build/ogustos-mesa-build}"
else
    BUILD_DIR="${BUILD_DIR:-/var/tmp/ogustos-mesa-build}"
fi
JOBS="$(nproc)"

if [[ -n "${1:-}" && "${1:-}" != "latest" ]]; then
    MESA_VER="$1"
else
    echo "[::] Querying archive.mesa3d.org for latest upstream Mesa release..."
    MESA_VER="$(curl -fsSL https://archive.mesa3d.org/ | grep -oE 'mesa-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz' | sed -E 's/mesa-(.*)\.tar\.xz/\1/' | sort -V | tail -n 1)"
fi

mkdir -p "$BUILD_DIR" "$OUT_POOL"
cd "$BUILD_DIR"

TARBALL="mesa-${MESA_VER}.tar.xz"
if [[ ! -f "$TARBALL" ]]; then
    echo "[::] Downloading upstream ${TARBALL} from archive.mesa3d.org..."
    curl -fLO "https://archive.mesa3d.org/${TARBALL}"
fi

export DEB_BUILD_OPTIONS="parallel=${JOBS} nocheck"
export DEB_CFLAGS_SET="-O2 -march=x86-64 -mtune=generic -pipe"
export DEB_CXXFLAGS_SET="-O2 -march=x86-64 -mtune=generic -pipe"
export DEB_LDFLAGS_SET="-Wl,-O1 -Wl,--as-needed -fuse-ld=mold"

echo "[::] Fetching Debian Mesa packaging metadata and building amd64 + i386 .debs for Mesa ${MESA_VER}..."
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get build-dep -y mesa

rm -rf "${BUILD_DIR}/pkg-src"
mkdir -p "${BUILD_DIR}/pkg-src"
cd "${BUILD_DIR}/pkg-src"
apt-get source --download-only mesa
DSC_FILE="$(ls -1 mesa_*.dsc | tail -n 1)"
dpkg-source -x "$DSC_FILE" mesa-deb

rm -rf "mesa-${MESA_VER}"
tar -xf "${BUILD_DIR}/${TARBALL}"
cp -a mesa-deb/debian "mesa-${MESA_VER}/"
cd "mesa-${MESA_VER}"

DEBFULLNAME="Ogun Aydin" DEBEMAIL="251391298+ogunaydin89@users.noreply.github.com" \
    dch -v "${MESA_VER}-1ogustos1" --distribution stable --force-distribution \
    "Upstream Mesa ${MESA_VER} release built for ogustOS (amd64 + i386)."

dpkg-buildpackage -us -uc -b -aamd64
if sudo apt-get build-dep -y -ai386 mesa 2>/dev/null; then
    dpkg-buildpackage -us -uc -B -ai386
fi

cp -f "${BUILD_DIR}/pkg-src/"*.deb "$OUT_POOL/"
echo "[::] Staged Mesa ${MESA_VER} packages into ${OUT_POOL}:"
ls -lh "${OUT_POOL}"/*mesa*.deb
