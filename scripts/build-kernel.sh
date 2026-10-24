#!/usr/bin/env bash
# ==============================================================================
# build-kernel.sh — Builds universal linux-image-7.3.x-ogustOS .deb from kernel.org
# Applies the Clang DKMS patch, merges Universal Debian amd64 config +
# ogustos-overrides.config, compiles with LLVM=1 + Clang ThinLTO, and builds meta-debs.
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
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc" | grep "  ${TARBALL}\$" | sha256sum -c -
fi

# Fetch the Clang DKMS patch (the only patch carried) if not already cached in repo
PATCH_DIR="${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}"
[[ -f "${PATCH_DIR}/0004-dkms-clang.patch" ]] || curl -fsSL "https://raw.githubusercontent.com/CachyOS/kernel-patches/master/${KMAJOR_MINOR}/misc/dkms-clang.patch" -o "${PATCH_DIR}/0004-dkms-clang.patch"

if [[ ! -f "linux-${KVER}/.patched_ogustos" ]]; then
    rm -rf "linux-${KVER}"
    tar -xf "$TARBALL"
    cd "linux-${KVER}"

    for p in "${PATCH_DIR}"/*.patch; do
        echo "[::] Applying patch $(basename "$p")..."
        patch -Np1 < "$p"
    done
    rm -f localversion*
    touch .patched_ogustos
else
    echo "[::] Reusing patched kernel tree in linux-${KVER}..."
    cd "linux-${KVER}"
    rm -f localversion*
fi

# ogustOS branding: replace the stock Tux boot logo (also used by the DRM panic screen)
echo "[::] Installing ogustOS boot logo..."
install -m 0644 "${REPO_ROOT}/kernel/branding/logo_linux_clut224.ppm" drivers/video/logo/logo_linux_clut224.ppm

if [[ ! -f .config ]]; then
    echo "[::] Installing Universal Debian base config-7.3-ogustOS..."
    cp "${REPO_ROOT}/kernel/config-7.3-ogustOS" .config
fi
echo "[::] Merging ogustos-overrides.config and running olddefconfig..."
scripts/kconfig/merge_config.sh -m .config "${REPO_ROOT}/kernel/fragments/ogustos-overrides.config"
make LLVM=1 LLVM_IAS=1 olddefconfig
cp -f .config "${REPO_ROOT}/kernel/config-7.3-ogustOS"

# Ensure Debian Package: names are strictly lowercase while keeping uname -r as 7.3.x-ogustOS
if ! grep -q 'KR_LOWER=' scripts/package/mkdebian; then
    sed -i '/^sourcename=/a KR_LOWER=$(echo "${KERNELRELEASE}" | tr "[:upper:]" "[:lower:]")' scripts/package/mkdebian
    sed -i 's/^Package: $packagename-${KERNELRELEASE}/Package: $packagename-${KR_LOWER}/' scripts/package/mkdebian
    sed -i 's/^Package: linux-headers-${KERNELRELEASE}/Package: linux-headers-${KR_LOWER}/' scripts/package/mkdebian
    sed -i 's/^Package: linux-image-${KERNELRELEASE}-dbg/Package: linux-image-${KR_LOWER}-dbg/' scripts/package/mkdebian
fi
sed -i 's/version=${1#linux-headers-}/version=${KERNELRELEASE}/' scripts/package/builddeb
if ! grep -q 'linux-headers-\${version}/\.config' scripts/package/builddeb; then
    sed -i '/ln -s \/usr\/src\/linux-headers-\$version/i \	cp "${KCONFIG_CONFIG}" "${pdir}/usr/src/linux-headers-${version}/.config"' scripts/package/builddeb
fi
sed -i 's/-j$(JOBS)/-j8/g; s/-j$(or $(JOBS),8)/-j8/g' scripts/Makefile.btf

KREL="$(make -s kernelrelease)"
KREL_LOWER="$(echo "$KREL" | tr '[:upper:]' '[:lower:]')"
PKGVER="$(make -s kernelversion)-1ogustos1"

echo "[::] Compiling ${KREL} Debian packages (-j${JOBS} with Clang/LLVM + ThinLTO)..."
export LLVM=1 LLVM_IAS=1
export KBUILD_BUILD_USER="ogust"
export KBUILD_BUILD_HOST="ogustos"
export DEBFULLNAME="Ogun Aydin"
export DEBEMAIL="251391298+ogunaydin89@users.noreply.github.com"
make -j"${JOBS}" LLVM=1 LLVM_IAS=1 bindeb-pkg \
    LOCALVERSION="" \
    KDEB_PKGVERSION="$PKGVER" \
    DPKG_FLAGS="-Ppkg.linux-upstream.nokerneldbg"

cp -f "${BUILD_DIR}"/linux-image-${KREL_LOWER}_*.deb "$OUT_POOL/"
cp -f "${BUILD_DIR}"/linux-headers-${KREL_LOWER}_*.deb "$OUT_POOL/"

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
Depends: linux-${kind}-${KREL_LOWER} (= ${PKGVER})
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Latest ogustOS Linux kernel ${kind} meta-package (tracks ${KREL})
EOF
    dpkg-deb --build --root-owner-group "$META_STAGE" "${OUT_POOL}/linux-${kind}-ogustos_${PKGVER}_amd64.deb"
done

echo "[::] Kernel & meta-packages staged in ${OUT_POOL}:"
ls -lh "${OUT_POOL}"/linux-*.deb
