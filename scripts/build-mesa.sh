#!/usr/bin/env bash
# ==============================================================================
# build-mesa.sh — Builds the latest upstream Mesa graphics stack (amd64 + i386)
# Auto-detects the newest stable release on archive.mesa3d.org, builds inside a
# clean Debian stable (trixie) build chroot so all binary packages link cleanly
# against Debian stable's libc6 and llvm-19, and outputs amd64 + i386 .debs.
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
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"

if ! command -v debootstrap >/dev/null 2>&1; then
    echo "[::] Installing debootstrap from Debian stable..."
    curl -fsSL "https://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.141_all.deb" -o /tmp/debootstrap.deb
    sudo dpkg -i /tmp/debootstrap.deb
    rm -f /tmp/debootstrap.deb
fi

if [[ -n "${1:-}" && "${1:-}" != "latest" ]]; then
    MESA_VER="$1"
else
    echo "[::] Querying archive.mesa3d.org for latest upstream Mesa release..."
    MESA_VER="$(curl -fsSL https://archive.mesa3d.org/ | grep -oE 'mesa-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz' | sed -E 's/mesa-(.*)\.tar\.xz/\1/' | sort -V | tail -n 1)"
fi

echo "[::] Querying dri.freedesktop.org/libdrm/ for latest upstream libdrm release..."
LIBDRM_VER="$(curl -fsSL https://dri.freedesktop.org/libdrm/ | grep -oE 'libdrm-[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz' | sed -E 's/libdrm-(.*)\.tar\.xz/\1/' | sort -V | tail -n 1)"

mkdir -p "$BUILD_DIR" "$OUT_POOL"
cd "$BUILD_DIR"

MESA_TARBALL="mesa-${MESA_VER}.tar.xz"
if [[ ! -f "$MESA_TARBALL" ]]; then
    echo "[::] Downloading upstream ${MESA_TARBALL} from archive.mesa3d.org..."
    curl -fLO "https://archive.mesa3d.org/${MESA_TARBALL}"
fi

LIBDRM_TARBALL="libdrm-${LIBDRM_VER}.tar.xz"
if [[ ! -f "$LIBDRM_TARBALL" ]]; then
    echo "[::] Downloading upstream ${LIBDRM_TARBALL} from dri.freedesktop.org..."
    curl -fLO "https://dri.freedesktop.org/libdrm/${LIBDRM_TARBALL}"
fi

echo "[::] Fetching Debian packaging metadata for libdrm and mesa..."
DEBIAN_POOL="https://deb.debian.org/debian/pool/main"
LIBDRM_DEB_TAR="$(curl -fsSL "${DEBIAN_POOL}/libd/libdrm/" | grep -oE 'libdrm_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.debian\.tar\.xz' | sort -V | tail -n 1)"
MESA_DEB_TAR="$(curl -fsSL "${DEBIAN_POOL}/m/mesa/" | grep -oE 'mesa_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.debian\.tar\.xz' | sort -V | tail -n 1)"

[[ -f "$LIBDRM_DEB_TAR" ]] || curl -fLO "${DEBIAN_POOL}/libd/libdrm/${LIBDRM_DEB_TAR}"
[[ -f "$MESA_DEB_TAR" ]]   || curl -fLO "${DEBIAN_POOL}/m/mesa/${MESA_DEB_TAR}"

unmount_chroot() {
    local root="$1"
    for mp in dev/pts dev proc sys; do
        if mountpoint -q "${root}/${mp}" 2>/dev/null; then
            sudo umount -lf "${root}/${mp}" || true
        fi
    done
}

build_arch_in_chroot() {
    local arch="$1"
    local dpkg_flag="$2"
    if [[ -f "${OUT_POOL}/mesa-vulkan-drivers_${MESA_VER}-1ogustos1_${arch}.deb" ]]; then
        echo "[::] Mesa ${MESA_VER} (${arch}) already present in ${OUT_POOL}; skipping."
        return 0
    fi
    local arch_cflags="-O2 -march=x86-64 -mtune=generic -pipe"
    [[ "$arch" == "i386" ]] && arch_cflags="-O2 -march=i686 -msse2 -mfpmath=sse -mtune=generic -pipe"
    local chroot_dir="${BUILD_DIR}/chroot-${arch}"
    local runner=(sudo chroot "$chroot_dir")
    [[ "$arch" == "i386" ]] && runner=(sudo linux32 chroot "$chroot_dir")

    echo "[::] Preparing clean Debian stable (${arch}) build chroot at ${chroot_dir}..."
    unmount_chroot "$chroot_dir"
    if [[ ! -x "${chroot_dir}/usr/bin/dpkg-buildpackage" ]]; then
        sudo rm -rf "$chroot_dir"
        sudo debootstrap --arch="$arch" --variant=buildd --no-check-gpg stable "$chroot_dir" https://deb.debian.org/debian
    fi

    sudo mount --bind /proc "${chroot_dir}/proc"
    sudo mount --bind /sys "${chroot_dir}/sys"
    sudo mount --bind /dev "${chroot_dir}/dev"
    sudo mount --bind /dev/pts "${chroot_dir}/dev/pts"
    trap "unmount_chroot '$chroot_dir'" EXIT

    sudo cp -f /etc/resolv.conf "${chroot_dir}/etc/resolv.conf"
    cat <<'EOF' | sudo tee "${chroot_dir}/etc/apt/sources.list" >/dev/null
deb https://deb.debian.org/debian stable main contrib non-free non-free-firmware
deb-src https://deb.debian.org/debian stable main contrib non-free non-free-firmware
deb https://deb.debian.org/debian stable-updates main contrib non-free non-free-firmware
deb https://deb.debian.org/debian stable-backports main contrib non-free non-free-firmware
deb-src https://deb.debian.org/debian stable-backports main contrib non-free non-free-firmware
EOF

    "${runner[@]}" env LC_ALL=C apt-get update
    if [[ -f "${OUT_POOL}/libdrm-common_${LIBDRM_VER}-3ogustos1_all.deb" ]]; then
        sudo cp -f "${OUT_POOL}/libdrm-common_${LIBDRM_VER}-3ogustos1_all.deb" "${chroot_dir}/tmp/"
        "${runner[@]}" dpkg -i "/tmp/libdrm-common_${LIBDRM_VER}-3ogustos1_all.deb" || true
        "${runner[@]}" dpkg --configure -a || true
    fi
    "${runner[@]}" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential devscripts dpkg-dev equivs mold ca-certificates

    # 1. Build libdrm
    if [[ ! -f "${OUT_POOL}/libdrm2_${LIBDRM_VER}-3ogustos1_${arch}.deb" ]]; then
        sudo rm -rf "${chroot_dir}/build/libdrm"
        sudo mkdir -p "${chroot_dir}/build/libdrm"
        sudo tar -xf "${BUILD_DIR}/${LIBDRM_TARBALL}" -C "${chroot_dir}/build/libdrm"
        sudo tar -xf "${BUILD_DIR}/${LIBDRM_DEB_TAR}" -C "${chroot_dir}/build/libdrm/libdrm-${LIBDRM_VER}"
        "${runner[@]}" env LC_ALL=C bash -lc "
            set -euo pipefail
            cd /build/libdrm/libdrm-${LIBDRM_VER}
            DEBFULLNAME='Ogun Aydin' DEBEMAIL='251391298+ogunaydin89@users.noreply.github.com' \
                dch -b -v '${LIBDRM_VER}-3ogustos1' --distribution stable --force-distribution \
                'Upstream libdrm ${LIBDRM_VER} release built for ogustOS.'
            DEBIAN_FRONTEND=noninteractive mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
            rm -f *build-deps*
            DEB_BUILD_OPTIONS='parallel=${JOBS} nocheck noautodbgsym' \
            DEB_CFLAGS_SET='${arch_cflags}' \
            DEB_CXXFLAGS_SET='${arch_cflags}' \
            DEB_LDFLAGS_SET='-Wl,-O1 -Wl,--as-needed -fuse-ld=mold' \
                dpkg-buildpackage -us -uc -b
            dpkg -i /build/libdrm/*.deb
        "
        sudo cp -f "${chroot_dir}/build/libdrm/"*.deb "$OUT_POOL/"
    fi

    # 2. Build Mesa
    sudo rm -rf "${chroot_dir}/build/mesa"
    sudo mkdir -p "${chroot_dir}/build/mesa"
    sudo tar -xf "${BUILD_DIR}/${MESA_TARBALL}" -C "${chroot_dir}/build/mesa"
    sudo tar -xf "${BUILD_DIR}/${MESA_DEB_TAR}" -C "${chroot_dir}/build/mesa/mesa-${MESA_VER}"
    "${runner[@]}" env LC_ALL=C bash -lc "
        set -euo pipefail
        cd /build/mesa/mesa-${MESA_VER}
        sed -i 's/LLVM_VERSION = [0-9]\+/LLVM_VERSION = 19/' debian/rules
        sed -i -E 's/(llvm|clang|clc)(-cpp|spirvlib|-spirv)?-[0-9]+/\1\2-19/g; s/spirv-tools-dev/spirv-tools/g' debian/control
        DEBFULLNAME='Ogun Aydin' DEBEMAIL='251391298+ogunaydin89@users.noreply.github.com' \
            dch -b -v '${MESA_VER}-1ogustos1' --distribution stable --force-distribution \
            'Upstream Mesa ${MESA_VER} release built for ogustOS (amd64 + i386).'
        DEBIAN_FRONTEND=noninteractive apt-get install -y -t stable-backports \
            directx-headers-dev wayland-protocols || true
        DEBIAN_FRONTEND=noninteractive mk-build-deps -i -r -t 'apt-get -y --no-install-recommends' debian/control
        rm -f *build-deps*
        DEB_BUILD_OPTIONS='parallel=${JOBS} nocheck noautodbgsym' \
        DEB_CFLAGS_SET='${arch_cflags}' \
        DEB_CXXFLAGS_SET='${arch_cflags}' \
        DEB_LDFLAGS_SET='-Wl,-O1 -Wl,--as-needed -fuse-ld=mold' \
            dpkg-buildpackage -us -uc ${dpkg_flag}
    "
    sudo cp -f "${chroot_dir}/build/mesa/"*.deb "$OUT_POOL/"
    sudo rm -f "${OUT_POOL}"/*-dbgsym_*.deb

    unmount_chroot "$chroot_dir"
    sudo rm -rf "$chroot_dir"
    trap - EXIT
}

build_arch_in_chroot "amd64" "-b"
build_arch_in_chroot "i386"  "-B"

echo "[::] Staged libdrm ${LIBDRM_VER} and Mesa ${MESA_VER} (amd64 + i386) packages into ${OUT_POOL}:"
ls -lh "${OUT_POOL}"/*mesa*.deb "${OUT_POOL}"/*drm*.deb
