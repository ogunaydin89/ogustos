#!/usr/bin/env bash
# ==============================================================================
# build-apps.sh — Packages custom ogustOS applications (.deb)
#   1. emerge-pdf          -> pool/apps/emerge-pdf_1.0.0_all.deb
#   2. meb-sertifika       -> pool/apps/meb-sertifika_1.0.0_all.deb (Provides: fatihca, meb-ser)
#   3. libreoffice-fresh   -> pool/apps/libreoffice-fresh_26.8.0-1ogustos1_all.deb
#   4. proton-ge-custom    -> pool/main/proton-ge-custom_<ver>_amd64.deb
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
Depends: python3, python3-venv, python3-pip, python3-pyqt6, python3-pil, python3-ebooklib, python3-pymupdf
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Universal Offline Document & PDF Manipulation Suite
 Compatible with both ogustOS KDE and Pardus (23/25/ETAP).
EOF

    cp -a "${EMERGE_PDF_SRC}/src" "${EMERGE_PDF_SRC}/requirements.txt" "${STAGE}/usr/share/emerge-pdf/"
    cat > "${STAGE}/usr/share/emerge-pdf/src/fitz.py" <<'EOF'
from pymupdf import *
from pymupdf import __doc__, __version__
EOF
    install -m 0644 "${EMERGE_PDF_SRC}/icon.svg" "${STAGE}/usr/share/icons/hicolor/scalable/apps/emerge-pdf.svg"

    cat > "${STAGE}/DEBIAN/postinst" <<'EOF'
#!/usr/bin/env bash
set -e
if [[ -d /usr/lib/python3/dist-packages/pymupdf && ! -e /usr/lib/python3/dist-packages/fitz ]]; then
    ln -sf pymupdf /usr/lib/python3/dist-packages/fitz || true
fi
EOF
    chmod 0755 "${STAGE}/DEBIAN/postinst"

    cat > "${STAGE}/usr/bin/emerge-pdf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/usr/share/emerge-pdf"
SYS_VENV="${APP_DIR}/venv"
USER_VENV="${XDG_DATA_HOME:-$HOME/.local/share}/emerge-pdf/venv"

if [[ -x "${SYS_VENV}/bin/python" ]]; then
    exec "${SYS_VENV}/bin/python" "${APP_DIR}/src/main.py" "$@"
fi

if python3 -c "import fitz, PIL, PyQt6" >/dev/null 2>&1; then
    exec python3 "${APP_DIR}/src/main.py" "$@"
fi

if [[ ! -x "${USER_VENV}/bin/python" ]]; then
    mkdir -p "$(dirname "$USER_VENV")"
    python3 -m venv --system-site-packages "$USER_VENV"
    "${USER_VENV}/bin/pip" install --disable-pip-version-check --no-input -r "${APP_DIR}/requirements.txt"
fi

exec "${USER_VENV}/bin/python" "${APP_DIR}/src/main.py" "$@"
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
Version: 26.8.0-1ogustos1
Section: editors
Priority: optional
Architecture: all
Depends: libreoffice, libreoffice-kf6 | libreoffice-qt6, libreoffice-l10n-tr
Maintainer: Ogun Aydin <251391298+ogunaydin89@users.noreply.github.com>
Description: Latest LibreOffice Fresh suite with KDE Plasma 6 (KF6/Qt6) integration
EOF
dpkg-deb --build --root-owner-group "$LO_STAGE" "${OUT_DIR}/pool/apps/libreoffice-fresh_26.8.0-1ogustos1_all.deb"
echo "[::] Packaged ${OUT_DIR}/pool/apps/libreoffice-fresh_26.8.0-1ogustos1_all.deb"

# ------------------------------------------------------------------------------
# 4. Package Proton-GE Custom (/usr/share/steam/compatibilitytools.d/)
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
