#!/usr/bin/env bash
# ==============================================================================
# build-kernel.sh — Builds linux-image-7.3.x-ogustOS .deb from kernel.org source
# Applies BORE + BBRv3 patches, compiles with LLVM=1 + Clang ThinLTO (portable
# x86_64), and generates the linux-image-ogustos / linux-headers-ogustos meta-debs.
# ==============================================================================
set -euo pipefail

KVER="${1:-7.3}"
KMAJOR_MINOR="$(cut -d. -f1-2 <<<"$KVER")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_POOL="${REPO_ROOT}/dist/repo/pool/main"
BUILD_DIR="${BUILD_DIR:-/var/tmp/ogustos-kernel-build}"
JOBS="$(nproc)"

echo "[::] Preparing build directory in ${BUILD_DIR}..."
mkdir -p "$BUILD_DIR" "$OUT_POOL" "${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}"
cd "$BUILD_DIR"

TARBALL="linux-${KVER}.tar.xz"
if [[ ! -f "$TARBALL" ]]; then
    echo "[::] Downloading Linux ${KVER} from kernel.org..."
    curl -fLO "https://cdn.kernel.org/pub/linux/kernel/v7.x/${TARBALL}"
fi

# Fetch GPLv2 BORE + BBRv3 + Cachy base patches for this kernel series if not cached
PATCH_BASE_URL="https://raw.githubusercontent.com/CachyOS/kernel-patches/master/${KMAJOR_MINOR}"
for patch_name in "0001-bore-cachy.patch" "0002-bbr3.patch" "0003-cachy.patch"; do
    target_patch="${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}/${patch_name}"
    if [[ ! -f "$target_patch" ]]; then
        echo "[::] Fetching ${patch_name} for Linux ${KMAJOR_MINOR}..."
        curl -fsSL "${PATCH_BASE_URL}/${patch_name}" -o "$target_patch" || rm -f "$target_patch"
    fi
done

rm -rf "linux-${KVER}"
tar -xf "$TARBALL"
cd "linux-${KVER}"

if compgen -G "${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}/*.patch" >/dev/null; then
    for p in "${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}"/*.patch; do
        echo "[::] Applying patch $(basename "$p")..."
        patch -Np1 < "$p"
    done
fi

echo "[::] Installing base config-7.3-ogustOS and merging portable ThinLTO overrides..."
cp "${REPO_ROOT}/kernel/config-7.3-ogustOS" .config
scripts/kconfig/merge_config.sh -m .config "${REPO_ROOT}/kernel/fragments/ogustos-overrides.config"
make LLVM=1 LLVM_IAS=1 olddefconfig

KREL="$(make -s kernelrelease)"
PKGVER="$(make -s kernelversion)-1ogustos1"

echo "[::] Compiling ${KREL} Debian packages (-j${JOBS} with Clang/LLVM + ThinLTO)..."
make -j"${JOBS}" LLVM=1 LLVM_IAS=1 bindeb-pkg \
    LOCALVERSION="" \
    KDEB_PKGVERSION="$PKGVER"

cp -f "${BUILD_DIR}"/linux-image-${KREL}_*.deb "$OUT_POOL/"
cp -f "${BUILD_DIR}"/linux-headers-${KREL}_*.deb "$OUT_POOL/"

# ------------------------------------------------------------------------------
# Build linux-image-ogustos & linux-headers-ogustos Meta-Packages
# (Ensures 'ogust up' automatically upgrades across 7.3.0 -> 7.3.1 -> 7.4)
# ------------------------------------------------------------------------------
for kind in image headers; do
    META_STAGE="${BUILD_DIR}/meta-linux-${kind}-ogustos"
    rm -rf "$META_STAGE"
    mkdir -p "${META_STAGE}/DEBIAN"
    cat > "${META_STAGE}/DEBIAN/control" <<EOF
Package: linux-${kind}-ogustos
Version: ${PKGVER}
Section: kernel
Priority: required
Architecture: amd64
Depends: linux-${kind}-${KREL} (= ${PKGVER})
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Latest ogustOS Linux kernel ${kind} meta-package (tracks ${KREL})
EOF
    dpkg-deb --build --root-owner-group "$META_STAGE" "${OUT_POOL}/linux-${kind}-ogustos_${PKGVER}_amd64.deb"
done

echo "[::] Kernel & meta-packages staged in ${OUT_POOL}:"
ls -lh "${OUT_POOL}"/linux-*.deb
