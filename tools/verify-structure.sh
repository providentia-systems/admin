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
test ! -f tool/generate_api_client.mjs
bash tool/materialize_contract.sh
bash -n tools/agent-setup.sh tool/install_flutter_linux.sh \
  tool/materialize_contract.sh \
  tools/agent-check.sh \
  packaging/linux/build-packages.sh packaging/linux/AppRun \
  packaging/linux/providentia_admin packaging/linux/debian-postinst \
  packaging/linux/debian-postrm

grep -Fqx 'Exec=providentia_admin %u' \
  packaging/linux/com.vastdevelopmentmethod.providentia.admin.desktop
grep -Fqx 'MimeType=x-scheme-handler/providentia-admin;' \
  packaging/linux/com.vastdevelopmentmethod.providentia.admin.desktop

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

if grep -En '^[[:space:]]+(camera|drift|drift_flutter|file_picker|image_picker|sqlite3):' pubspec.yaml; then
  echo "Admin contains a forbidden homeowner/media persistence dependency." >&2
  exit 1
fi

EXPECTED="f01c320e1900f523661bbba24225583f1d61bc00f3949cb0e7b5b2f6fd5a524e"
ACTUAL="$(sha256sum contracts/providentia-v1.json | cut -d' ' -f1)"
test "${ACTUAL}" = "${EXPECTED}"

node tool/verify_contract.mjs
node tool/generate_admin_api_client.mjs --check

echo "Admin structural and contract boundaries verified."
