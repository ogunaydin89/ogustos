#!/usr/bin/env bash
# ==============================================================================
# build-apps.sh — Packages custom ogustOS & School Pardus applications (.deb)
# Places universal packages in pool/apps/ (works on ogustOS AND Pardus 23/25!)
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/repo"
EMERGE_PDF_SRC="${EMERGE_PDF_SRC:-/home/helin/Code/emerge-pdf}"

mkdir -p "${OUT_DIR}/pool/apps" "${OUT_DIR}/pool/main"

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
