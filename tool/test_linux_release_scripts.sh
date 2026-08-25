#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${FIXTURE_ROOT}"' EXIT

make_fixture() {
  local fixture="$1"
  local dependencies="$2"
  install -d "${fixture}/DEBIAN" \
    "${fixture}/opt/providentia-admin/lib" \
    "${fixture}/usr/share/applications"
  cat > "${fixture}/DEBIAN/control" <<EOF
Package: providentia-admin
Version: 9.8.7
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Providentia Release Test
Depends: ${dependencies}
Description: Focused Linux release fixture
 Test-only package used to verify fail-closed release scripts.
EOF
  install -m 0755 /bin/true \
    "${fixture}/opt/providentia-admin/providentia_admin"
  install -m 0755 /bin/true \
    "${fixture}/opt/providentia-admin/lib/libflutter_linux_gtk.so"
  install -m 0755 /bin/true \
    "${fixture}/opt/providentia-admin/lib/libflutter_secure_storage_linux_plugin.so"
  cat > "${fixture}/usr/share/applications/com.vastdevelopmentmethod.providentia.admin.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Providentia Admin
Exec=providentia_admin %u
MimeType=x-scheme-handler/providentia-admin;
EOF
}

install -d "${FIXTURE_ROOT}/bin"
cat > "${FIXTURE_ROOT}/bin/ldconfig" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'libEGL.so.1 (libc6,x86-64) => /usr/lib/libEGL.so.1' \
  'libGLESv2.so.2 (libc6,x86-64) => /usr/lib/libGLESv2.so.2'
EOF
chmod 0755 "${FIXTURE_ROOT}/bin/ldconfig"

GOOD_ROOT="${FIXTURE_ROOT}/good"
make_fixture "${GOOD_ROOT}" 'libegl1, libgles2, libgtk-3-0, libsecret-1-0'
dpkg-deb --root-owner-group --build "${GOOD_ROOT}" "${FIXTURE_ROOT}/good.deb" >/dev/null
PATH="${FIXTURE_ROOT}/bin:${PATH}" \
  bash "${ROOT}/tool/verify_linux_deb.sh" "${FIXTURE_ROOT}/good.deb" >/dev/null

BAD_ROOT="${FIXTURE_ROOT}/bad"
make_fixture "${BAD_ROOT}" 'libegl1, libgtk-3-0, libsecret-1-0'
dpkg-deb --root-owner-group --build "${BAD_ROOT}" "${FIXTURE_ROOT}/bad.deb" >/dev/null
if PATH="${FIXTURE_ROOT}/bin:${PATH}" \
  bash "${ROOT}/tool/verify_linux_deb.sh" "${FIXTURE_ROOT}/bad.deb" \
  >/dev/null 2>&1; then
  echo 'Verifier accepted a package without the libgles2 runtime dependency.' >&2
  exit 1
fi

if PROVIDENTIA_RELEASE_VERSION='../invalid' \
  bash "${ROOT}/packaging/linux/build-packages.sh" "${FIXTURE_ROOT}/missing" \
  >/dev/null 2>&1; then
  echo 'Packager accepted an unsafe release version.' >&2
  exit 1
fi

install -d "${FIXTURE_ROOT}/unsigned"
if env -u LINUX_SIGNING_KEY_BASE64 -u LINUX_SIGNING_KEY_ID \
  -u LINUX_SIGNING_PASSPHRASE \
  bash "${ROOT}/tool/sign_linux_artifacts.sh" "${FIXTURE_ROOT}/unsigned" \
  >/dev/null 2>&1; then
  echo 'Signing gate accepted missing protected credentials.' >&2
  exit 1
fi

echo 'Linux release scripts reject missing runtimes, unsafe versions and unsigned publication.'
