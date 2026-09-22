#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

for command in bash cut find grep gzip node sha256sum; do
  command -v "${command}" >/dev/null || {
    echo "Missing structural-gate prerequisite: ${command}" >&2
    exit 1
  }
done

test -f pubspec.yaml
test -f pubspec.lock
test -f contracts/source/providentia-v1.json.gz
test -f contracts/contract.lock.json
test -f contracts/generated/providentia_api_client/lib/providentia_api_client.dart
test -f tools/agent-requirements.json
test -f tools/agent-setup.sh
test -x tools/providentia-admin.sh
test -f tool/providentia_admin_setup.test.mjs
test -f tool/install_node_linux.sh
test -f tool/test_installer_cache_health.sh
test -f tool/test_linux_release_scripts.sh
test -f tool/verify_linux_deb.sh
test -f tool/sign_linux_artifacts.sh
test -f .github/workflows/release-linux.yml
test ! -f tool/generate_api_client.mjs
test ! -f tool/verify_toolchain.mjs
bash tool/materialize_contract.sh
bash -n tools/agent-setup.sh tools/providentia-admin.sh \
  tool/install_flutter_linux.sh \
  tool/install_node_linux.sh \
  tool/test_installer_cache_health.sh \
  tool/test_linux_release_scripts.sh \
  tool/verify_linux_deb.sh \
  tool/sign_linux_artifacts.sh \
  tool/materialize_contract.sh \
  tools/agent-check.sh \
  packaging/linux/build-packages.sh packaging/linux/AppRun \
  packaging/linux/providentia_admin packaging/linux/debian-postinst \
  packaging/linux/debian-postrm
node --test tool/providentia_admin_setup.test.mjs

test -f docs/index.md
test -f docs/setup-ubuntu.md
grep -Fq 'MySQL or MariaDB' docs/setup-ubuntu.md
grep -Fq 'plain HTTP only for loopback' docs/setup-ubuntu.md

grep -Fqx 'Exec=providentia_admin' \
  packaging/linux/com.vastdevelopmentmethod.providentia.admin.desktop
if grep -En 'x-scheme-handler|%[uUfF]' \
  packaging/linux/com.vastdevelopmentmethod.providentia.admin.desktop \
  || grep -En 'G_APPLICATION_HANDLES_OPEN|application_links|pending_link|login-link' \
    linux/runner/my_application.cc; then
  echo 'Admin must not retain the retired authentication URI handler.' >&2
  exit 1
fi
grep -Fq 'set(CMAKE_DISABLE_FIND_PACKAGE_JNI TRUE CACHE BOOL' \
  linux/CMakeLists.txt
grep -Fq 'path_provider_android: 2.2.23' pubspec.yaml
if grep -Eq '^  (jni|jni_flutter|jni_util):' pubspec.lock; then
  echo 'Linux-only Admin dependency lock must not contain JNI packages.' >&2
  exit 1
fi
if grep -Fq 'jni' linux/flutter/generated_plugins.cmake; then
  echo 'Linux-only Admin generated plugins must not contain JNI.' >&2
  exit 1
fi
grep -Fq "actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c" \
  .github/workflows/quality.yml .github/workflows/release-linux.yml
grep -Fq 'environment: production-release' .github/workflows/release-linux.yml
grep -Fq 'PRODUCTION_API_BASE_URL' .github/workflows/release-linux.yml
grep -Fq 'LINUX_SIGNING_KEY_BASE64' .github/workflows/release-linux.yml
grep -Fq "PROVIDENTIA_LINUX_LAUNCH_SMOKE: 'true'" \
  .github/workflows/quality.yml .github/workflows/release-linux.yml
grep -Fq 'eight-digit email code' docs/development/agent-environment.md

for forbidden in android ios macos web windows; do
  if [ -d "${forbidden}" ]; then
    echo "Admin must remain Linux-only; found ${forbidden}/" >&2
    exit 1
  fi
done

if grep -RIn --include='*.dart' '/api/v1/homes' lib; then
  echo "Admin must not call any household endpoint." >&2
  exit 1
fi

if grep -RIn --include='*.dart' 'providentia\.' lib \
  | grep -v 'providentia\.admin\.'; then
  echo "Admin must use an isolated credential namespace." >&2
  exit 1
fi

for forbidden in ai_integration catalog_sharing data_governance homes inventory \
  purchasing reporting shopping sync_conflicts; do
  if [ -n "$(find lib -type d -name "${forbidden}" -print -quit)" ]; then
    echo "Admin contains forbidden homeowner feature directory: ${forbidden}" >&2
    exit 1
  fi
done

# file_picker selects a profile avatar for a bounded API upload; it does not
# add household capture or inventory persistence to Admin.
if grep -En '^[[:space:]]+(camera|drift|drift_flutter|image_picker|sqlite3):' pubspec.yaml; then
  echo "Admin contains a forbidden homeowner/media persistence dependency." >&2
  exit 1
fi

EXPECTED="13ccdc2d37e73955394a7b7c52da6d9ff7aeefdfd763ac809876737867d15c44"
ACTUAL="$(sha256sum contracts/providentia-v1.json | cut -d' ' -f1)"
test "${ACTUAL}" = "${EXPECTED}"

node tool/verify_contract.mjs
node tool/generate_admin_api_client.mjs --check

echo "Admin structural and contract boundaries verified."
