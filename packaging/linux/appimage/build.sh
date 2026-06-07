#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/app-rs/target/appimage"
APPDIR="${BUILD_DIR}/ClaudeUsageBar.AppDir"

BINARY="${REPO_ROOT}/app-rs/target/release/claude-usage-bar"
if [ ! -x "${BINARY}" ]; then
    echo "Building release binary first…"
    (cd "${REPO_ROOT}/app-rs" && cargo build --release)
fi

rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/share/applications" \
         "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

cp "${BINARY}" "${APPDIR}/usr/bin/claude-usage-bar"
cp "${SCRIPT_DIR}/claude-usage-bar.desktop" "${APPDIR}/usr/share/applications/"
cp "${SCRIPT_DIR}/claude-usage-bar.desktop" "${APPDIR}/claude-usage-bar.desktop"
cp "${REPO_ROOT}/packaging/linux/debian/claude-usage-bar.png" \
   "${APPDIR}/usr/share/icons/hicolor/256x256/apps/claude-usage-bar.png"
cp "${REPO_ROOT}/packaging/linux/debian/claude-usage-bar.png" \
   "${APPDIR}/claude-usage-bar.png"
cp "${SCRIPT_DIR}/AppRun" "${APPDIR}/AppRun"
chmod +x "${APPDIR}/AppRun"

APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
if ! command -v "${APPIMAGETOOL}" >/dev/null 2>&1; then
    echo "Downloading appimagetool…"
    TOOL_DIR="${BUILD_DIR}/tools"
    mkdir -p "${TOOL_DIR}"
    APPIMAGETOOL="${TOOL_DIR}/appimagetool"
    curl -fsSL \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" \
        -o "${APPIMAGETOOL}"
    chmod +x "${APPIMAGETOOL}"
fi

cd "${BUILD_DIR}"
ARCH=x86_64 "${APPIMAGETOOL}" --no-appstream \
    "${APPDIR}" \
    "${BUILD_DIR}/ClaudeUsageBar-x86_64.AppImage"

echo
echo "Built: ${BUILD_DIR}/ClaudeUsageBar-x86_64.AppImage"
ls -lh "${BUILD_DIR}/ClaudeUsageBar-x86_64.AppImage"
