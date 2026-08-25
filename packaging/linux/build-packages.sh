#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="${1:-${ROOT}/build/linux/x64/release/bundle}"
OUTPUT="${ROOT}/build/packages"
VERSION="0.1.0"
APP_ID="com.vastdevelopmentmethod.providentia.admin"
APPIMAGE_TOOL_SHA256="b90f4a8b18967545fda78a445b27680a1642f1ef9488ced28b65398f2be7add2"
APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

test -x "${BUNDLE}/providentia_admin"
mkdir -p "${OUTPUT}"

tar --create --gzip --file "${OUTPUT}/providentia-admin-${VERSION}-linux-x86_64.tar.gz" \
  --directory "${BUNDLE}" .

DEB_ROOT="$(mktemp -d)"
install -d "${DEB_ROOT}/DEBIAN" "${DEB_ROOT}/opt/providentia-admin" \
  "${DEB_ROOT}/usr/bin" "${DEB_ROOT}/usr/share/applications" \
  "${DEB_ROOT}/usr/share/icons/hicolor/scalable/apps" \
  "${DEB_ROOT}/usr/share/metainfo"
cp -a "${BUNDLE}/." "${DEB_ROOT}/opt/providentia-admin/"
install -m 0755 "${ROOT}/packaging/linux/providentia_admin" \
  "${DEB_ROOT}/usr/bin/providentia_admin"
install -m 0644 "${ROOT}/packaging/linux/debian-control" "${DEB_ROOT}/DEBIAN/control"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.desktop" \
  "${DEB_ROOT}/usr/share/applications/${APP_ID}.desktop"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.svg" \
  "${DEB_ROOT}/usr/share/icons/hicolor/scalable/apps/${APP_ID}.svg"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.metainfo.xml" \
  "${DEB_ROOT}/usr/share/metainfo/${APP_ID}.metainfo.xml"
dpkg-deb --root-owner-group --build "${DEB_ROOT}" \
  "${OUTPUT}/providentia-admin_${VERSION}_amd64.deb"

APPDIR="$(mktemp -d)/Providentia_Admin.AppDir"
install -d "${APPDIR}/usr/lib/providentia-admin" "${APPDIR}/usr/share/applications" \
  "${APPDIR}/usr/share/icons/hicolor/scalable/apps"
cp -a "${BUNDLE}/." "${APPDIR}/usr/lib/providentia-admin/"
install -m 0755 "${ROOT}/packaging/linux/AppRun" "${APPDIR}/AppRun"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.desktop" \
  "${APPDIR}/${APP_ID}.desktop"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.svg" "${APPDIR}/${APP_ID}.svg"
install -m 0644 "${ROOT}/packaging/linux/${APP_ID}.svg" "${APPDIR}/.DirIcon"

TOOL_CACHE="${PROVIDENTIA_AGENT_CACHE:-${ROOT}/.agent-tools}/packaging"
TOOL="${TOOL_CACHE}/appimagetool-x86_64.AppImage"
mkdir -p "${TOOL_CACHE}"
if ! echo "${APPIMAGE_TOOL_SHA256}  ${TOOL}" | sha256sum --check --status 2>/dev/null; then
  curl --fail --location --retry 3 --output "${TOOL}.part" "${APPIMAGE_TOOL_URL}"
  echo "${APPIMAGE_TOOL_SHA256}  ${TOOL}.part" | sha256sum --check --status
  mv "${TOOL}.part" "${TOOL}"
  chmod 0755 "${TOOL}"
fi
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "${TOOL}" "${APPDIR}" \
  "${OUTPUT}/Providentia_Admin-${VERSION}-x86_64.AppImage"

sha256sum "${OUTPUT}"/* > "${OUTPUT}/SHA256SUMS"
echo "Linux packages written to ${OUTPUT}."

