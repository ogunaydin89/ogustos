#!/usr/bin/env bash
# ==============================================================================
# build-apps.sh — Packages custom ogustOS applications (.deb)
#   1. emerge-pdf          -> pool/apps/emerge-pdf_1.0.0_all.deb
#   2. meb-sertifika       -> pool/apps/meb-sertifika_1.0.0_all.deb (Provides: fatihca, meb-ser)
#   3. libreoffice-fresh   -> pool/apps/libreoffice-fresh_25.8-1ogustos1_all.deb
#   4. viewnior            -> pool/apps/viewnior_1.8-1ogustos1_amd64.deb
#   5. proton-ge-custom    -> pool/main/proton-ge-custom_<ver>_amd64.deb
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/repo"
BUILD_TMP="${BUILD_TMP:-/var/tmp/ogustos-apps-build}"
EMERGE_PDF_SRC="${EMERGE_PDF_SRC:-/home/helin/Code/emerge-pdf}"

mkdir -p "${OUT_DIR}/pool/apps" "${OUT_DIR}/pool/main" "$BUILD_TMP"

# ------------------------------------------------------------------------------
# 1. Package EmergePDF (emerge-pdf_1.0.0_all.deb)
# ------------------------------------------------------------------------------
if [[ -d "$EMERGE_PDF_SRC" ]]; then
    STAGE="${REPO_ROOT}/dist/stage/emerge-pdf"
    rm -rf "$STAGE"
    mkdir -p "${STAGE}/DEBIAN"
    mkdir -p "${STAGE}/usr/bin"
    mkdir -p "${STAGE}/usr/share/emerge-pdf"
    mkdir -p "${STAGE}/usr/share/applications"
    mkdir -p "${STAGE}/usr/share/icons/hicolor/scalable/apps"

    cat > "${STAGE}/DEBIAN/control" <<'EOF'
Package: emerge-pdf
Version: 1.0.0
Section: utils
Priority: optional
Architecture: all
Depends: python3, python3-venv, python3-pip
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Universal Offline Document & PDF Manipulation Suite
 Compatible with both ogustOS KDE and Pardus (23/25/ETAP).
EOF

    cp -a "${EMERGE_PDF_SRC}/src" "${EMERGE_PDF_SRC}/requirements.txt" "${STAGE}/usr/share/emerge-pdf/"
    install -m 0644 "${EMERGE_PDF_SRC}/icon.svg" "${STAGE}/usr/share/icons/hicolor/scalable/apps/emerge-pdf.svg"

    cat > "${STAGE}/usr/bin/emerge-pdf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/usr/share/emerge-pdf"
VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/emerge-pdf/venv"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    mkdir -p "$(dirname "$VENV_DIR")"
    python3 -m venv "$VENV_DIR"
    "${VENV_DIR}/bin/pip" install --upgrade pip
    "${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"
fi

exec "${VENV_DIR}/bin/python" "${APP_DIR}/src/main.py" "$@"
EOF
    chmod 0755 "${STAGE}/usr/bin/emerge-pdf"

    cat > "${STAGE}/usr/share/applications/emerge-pdf.desktop" <<'EOF'
[Desktop Entry]
Name=EmergePDF
Comment=Universal Offline Document & PDF Converter
Exec=/usr/bin/emerge-pdf %F
Icon=emerge-pdf
Terminal=false
Type=Application
Categories=Office;Utility;Graphics;
StartupWMClass=emerge-pdf
EOF

    dpkg-deb --build --root-owner-group "$STAGE" "${OUT_DIR}/pool/apps/emerge-pdf_1.0.0_all.deb"
    echo "[::] Packaged ${OUT_DIR}/pool/apps/emerge-pdf_1.0.0_all.deb"
fi

# ------------------------------------------------------------------------------
# 2. Package MEB FATIH Root Certificate (meb-sertifika_1.0.0_all.deb)
#    Optional on-demand install via: ogust in meb-sertifika (or fatihca / meb-ser)
#    Installs into OpenSSL, Google Chrome NSSDB (~/.pki/nssdb), and Python/Node env
# ------------------------------------------------------------------------------
if [[ -f "${REPO_ROOT}/certs/MEB_FATIH_CA.crt" ]]; then
    MEB_STAGE="${REPO_ROOT}/dist/stage/meb-sertifika"
    rm -rf "$MEB_STAGE"
    mkdir -p "${MEB_STAGE}/DEBIAN"
    mkdir -p "${MEB_STAGE}/usr/local/share/ca-certificates"
    mkdir -p "${MEB_STAGE}/etc/environment.d"

    install -m 0644 "${REPO_ROOT}/certs/MEB_FATIH_CA.crt" "${MEB_STAGE}/usr/local/share/ca-certificates/MEB_FATIH_CA.crt"

    cat > "${MEB_STAGE}/etc/environment.d/99-meb-fatih-ca.conf" <<'EOF'
SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/MEB_FATIH_CA.crt
EOF

    cat > "${MEB_STAGE}/DEBIAN/control" <<'EOF'
Package: meb-sertifika
Version: 1.0.0
Section: net
Priority: optional
Architecture: all
Provides: fatihca, meb-ser
Depends: ca-certificates, libnss3-tools
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: MEB FATIH Network Root CA Certificate (CN=fatihca, valid to 2036)
 Optional system-wide installer for computers connected to MEB FATIH networks.
 Automatically registers the certificate in system OpenSSL, Google Chrome/Chromium
 NSS databases (~/.pki/nssdb), and Python/Node/curl TLS environments.
EOF

    cat > "${MEB_STAGE}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
CERT="/usr/local/share/ca-certificates/MEB_FATIH_CA.crt"
update-ca-certificates

if command -v certutil >/dev/null 2>&1; then
    for dir in /etc/skel /root /home/*; do
        [[ -d "$dir" ]] || continue
        nssdir="${dir}/.pki/nssdb"
        mkdir -p "$nssdir"
        if [[ ! -f "${nssdir}/cert9.db" ]]; then
            certutil -d "sql:${nssdir}" -N --empty-password || true
        fi
        certutil -d "sql:${nssdir}" -D -n "MEB FATIH CA" 2>/dev/null || true
        certutil -d "sql:${nssdir}" -A -t "CT,C,C" -n "MEB FATIH CA" -i "$CERT" || true
        if [[ "$dir" == /home/* ]]; then
            usr="$(stat -c '%U:%G' "$dir")"
            chown -R "$usr" "${dir}/.pki" || true
        fi
    done
fi
EOF

    cat > "${MEB_STAGE}/DEBIAN/postrm" <<'EOF'
#!/usr/bin/env bash
set -e
update-ca-certificates --fresh >/dev/null 2>&1 || true
if command -v certutil >/dev/null 2>&1; then
    for nssdir in /etc/skel/.pki/nssdb /root/.pki/nssdb /home/*/.pki/nssdb; do
        [[ -d "$nssdir" ]] && certutil -d "sql:${nssdir}" -D -n "MEB FATIH CA" 2>/dev/null || true
    done
fi
EOF

    chmod 0755 "${MEB_STAGE}/DEBIAN/postinst" "${MEB_STAGE}/DEBIAN/postrm"
    dpkg-deb --build --root-owner-group "$MEB_STAGE" "${OUT_DIR}/pool/apps/meb-sertifika_1.0.0_all.deb"
    echo "[::] Packaged ${OUT_DIR}/pool/apps/meb-sertifika_1.0.0_all.deb"
fi

# ------------------------------------------------------------------------------
# 3. Package libreoffice-fresh (KDE/Qt6 Native Meta-Package) & GitHub CLI (gh)
# ------------------------------------------------------------------------------
if ! compgen -G "${OUT_DIR}/pool/apps/gh_*_amd64.deb" >/dev/null; then
    GH_URL="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"browser_download_url": "\([^"]*linux_amd64\.deb\)".*/\1/p' | head -n1)"
    if [[ -n "$GH_URL" ]]; then
        curl -fL "$GH_URL" -o "${OUT_DIR}/pool/apps/$(basename "$GH_URL")"
        echo "[::] Bundled $(basename "$GH_URL") into pool/apps/"
    fi
fi

LO_STAGE="${REPO_ROOT}/dist/stage/libreoffice-fresh"
rm -rf "$LO_STAGE"
mkdir -p "${LO_STAGE}/DEBIAN"
cat > "${LO_STAGE}/DEBIAN/control" <<'EOF'
Package: libreoffice-fresh
Version: 25.8.0-1ogustos1
Section: editors
Priority: optional
Architecture: all
Depends: libreoffice, libreoffice-kf6 | libreoffice-qt6, libreoffice-l10n-tr
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Latest LibreOffice Fresh suite with KDE Plasma 6 (KF6/Qt6) integration
EOF
dpkg-deb --build --root-owner-group "$LO_STAGE" "${OUT_DIR}/pool/apps/libreoffice-fresh_25.8.0-1ogustos1_all.deb"
echo "[::] Packaged ${OUT_DIR}/pool/apps/libreoffice-fresh_25.8.0-1ogustos1_all.deb"

# ------------------------------------------------------------------------------
# 4. Compile & Package Viewnior 1.8 (Removed from Debian Testing; hosted in apps)
# ------------------------------------------------------------------------------
if [[ "${BUILD_VIEWNIOR:-0}" == "1" && ! -f "${OUT_DIR}/pool/apps/viewnior_1.8-1ogustos1_amd64.deb" ]]; then
    echo "[::] Compiling Viewnior 1.8 from source (portable x86_64)..."
    VN_DIR="${BUILD_TMP}/viewnior-src"
    VN_STAGE="${REPO_ROOT}/dist/stage/viewnior"
    rm -rf "$VN_DIR" "$VN_STAGE"
    git clone --depth=1 -b viewnior-1.8 https://github.com/hellosiyan/Viewnior.git "$VN_DIR"
    sed -i 's/Exiv2::Image::AutoPtr/Exiv2::Image::UniquePtr/g; s/Exiv2::AnyError/Exiv2::Error/g' "${VN_DIR}/src/uni-exiv2.cpp"
    CFLAGS="-O2 -pipe" CXXFLAGS="-O2 -pipe" LDFLAGS="-Wl,-O1 -Wl,--as-needed -fuse-ld=mold" \
        meson setup "${VN_DIR}/build" "$VN_DIR" --prefix=/usr --buildtype=release
    ninja -C "${VN_DIR}/build"
    DESTDIR="$VN_STAGE" ninja -C "${VN_DIR}/build" install
    mkdir -p "${VN_STAGE}/DEBIAN"
    cat > "${VN_STAGE}/DEBIAN/control" <<'EOF'
Package: viewnior
Version: 1.8-1ogustos1
Section: graphics
Priority: optional
Architecture: amd64
Depends: libc6, libglib2.0-0t64 | libglib2.0-0, libgtk2.0-0t64 | libgtk2.0-0, libexiv2-28 | libexiv2-27
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Fast, simple, and elegant image viewer for ogustOS and Pardus
EOF
    dpkg-deb --build --root-owner-group "$VN_STAGE" "${OUT_DIR}/pool/apps/viewnior_1.8-1ogustos1_amd64.deb"
    echo "[::] Packaged ${OUT_DIR}/pool/apps/viewnior_1.8-1ogustos1_amd64.deb"
fi

# ------------------------------------------------------------------------------
# 5. Package Proton-GE Custom (/usr/share/steam/compatibilitytools.d/)
# ------------------------------------------------------------------------------
if [[ "${BUILD_PROTON_GE:-0}" == "1" ]]; then
    GE_TAG="$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n1)"
    GE_VER="${GE_TAG#GE-Proton}"
    GE_TAR="${BUILD_TMP}/${GE_TAG}-x86_64.tar.gz"
    if [[ ! -f "$GE_TAR" ]]; then
        echo "[::] Downloading ${GE_TAG} (x86_64)..."
        curl -fL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_TAG}/${GE_TAG}-x86_64.tar.gz" -o "$GE_TAR" \
            || curl -fL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_TAG}/${GE_TAG}.tar.gz" -o "$GE_TAR"
    fi
    GE_STAGE="${REPO_ROOT}/dist/stage/proton-ge-custom"
    rm -rf "$GE_STAGE"
    mkdir -p "${GE_STAGE}/DEBIAN" "${GE_STAGE}/usr/share/steam/compatibilitytools.d"
    tar -xf "$GE_TAR" -C "${GE_STAGE}/usr/share/steam/compatibilitytools.d"
    cat > "${GE_STAGE}/DEBIAN/control" <<EOF
Package: proton-ge-custom
Version: ${GE_VER}-1ogustos1
Section: games
Priority: optional
Architecture: amd64
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Custom Proton-GE (${GE_TAG}) pre-installed for Steam on ogustOS
EOF
    dpkg-deb -Zxz -z3 --build --root-owner-group "$GE_STAGE" "${OUT_DIR}/pool/main/proton-ge-custom_${GE_VER}-1ogustos1_amd64.deb"
    echo "[::] Packaged ${OUT_DIR}/pool/main/proton-ge-custom_${GE_VER}-1ogustos1_amd64.deb"
fi
