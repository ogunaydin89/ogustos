#!/usr/bin/env bash
# ==============================================================================
# build-kernel.sh — Builds universal linux-image-7.3.x-ogustOS .deb from kernel.org
# Applies Cachy + BBRv3 + BORE patches, merges Universal Debian amd64 config +
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

# Fetch Cachy + BBRv3 + BORE + Clang DKMS patches if not already cached in repo
PATCH_DIR="${REPO_ROOT}/kernel/patches/${KMAJOR_MINOR}"
[[ -f "${PATCH_DIR}/0001-cachy.patch" ]] || curl -fsSL "https://github.com/CachyOS/linux/compare/e4cd5992b0de~1...52dc9bb47a1b.patch" -o "${PATCH_DIR}/0001-cachy.patch"
[[ -f "${PATCH_DIR}/0002-bbr3.patch" ]]  || curl -fsSL "https://github.com/CachyOS/linux/compare/5b121d2f9e4f~1...a52f724cc56d.patch" -o "${PATCH_DIR}/0002-bbr3.patch"
[[ -f "${PATCH_DIR}/0003-bore-cachy.patch" ]] || curl -fsSL "https://raw.githubusercontent.com/CachyOS/kernel-patches/master/${KMAJOR_MINOR}/sched/0001-bore-cachy.patch" -o "${PATCH_DIR}/0003-bore-cachy.patch"
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

if [[ ! -f .config ]] || ! grep -q '^CONFIG_TCP_CONG_BBR3=y' .config; then
    echo "[::] Installing Universal Debian base config-7.3-ogustOS and merging ogustos-overrides.config..."
    cp "${REPO_ROOT}/kernel/config-7.3-ogustOS" .config
    scripts/kconfig/merge_config.sh -m .config "${REPO_ROOT}/kernel/fragments/ogustos-overrides.config"
    make LLVM=1 LLVM_IAS=1 olddefconfig
fi

# Ensure Debian Package: names are strictly lowercase while keeping uname -r as 7.3.x-ogustOS
if ! grep -q 'KR_LOWER=' scripts/package/mkdebian; then
    sed -i '/^sourcename=/a KR_LOWER=$(echo "${KERNELRELEASE}" | tr "[:upper:]" "[:lower:]")' scripts/package/mkdebian
    sed -i 's/^Package: $packagename-${KERNELRELEASE}/Package: $packagename-${KR_LOWER}/' scripts/package/mkdebian
    sed -i 's/^Package: linux-headers-${KERNELRELEASE}/Package: linux-headers-${KR_LOWER}/' scripts/package/mkdebian
    sed -i 's/^Package: linux-image-${KERNELRELEASE}-dbg/Package: linux-image-${KR_LOWER}-dbg/' scripts/package/mkdebian
fi
sed -i 's/version=${1#linux-headers-}/version=${KERNELRELEASE}/' scripts/package/builddeb
sed -i 's/-j$(JOBS)/-j8/g; s/-j$(or $(JOBS),8)/-j8/g' scripts/Makefile.btf

KREL="$(make -s kernelrelease)"
KREL_LOWER="$(echo "$KREL" | tr '[:upper:]' '[:lower:]')"
PKGVER="$(make -s kernelversion)-1ogustos1"

echo "[::] Compiling ${KREL} Debian packages (-j${JOBS} with Clang/LLVM + ThinLTO)..."
export LLVM=1 LLVM_IAS=1
export KBUILD_BUILD_USER="ogust"
export KBUILD_BUILD_HOST="ogustos"
export DEBFULLNAME="ogustOS"
export DEBEMAIL="builder@ogustos.local"
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
