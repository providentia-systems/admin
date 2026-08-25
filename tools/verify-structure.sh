#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

test -f pubspec.yaml
test -f contracts/providentia-v1.json
test -f contracts/contract.lock.json
test -f contracts/generated/providentia_api_client/lib/providentia_api_client.dart
test -f tools/agent-requirements.json
test -f tools/agent-setup.sh
bash -n tools/agent-setup.sh tool/install_flutter_linux.sh \
  packaging/linux/build-packages.sh packaging/linux/AppRun \
  packaging/linux/providentia_admin

for forbidden in android ios macos web windows; do
  if [ -d "${forbidden}" ]; then
    echo "Admin must remain Linux-only; found ${forbidden}/" >&2
    exit 1
  fi
done

if rg -n '/api/v1/homes' lib; then
  echo "Admin must not call any household endpoint." >&2
  exit 1
fi

if rg -n "providentia\.(?!admin\.)" lib --pcre2; then
  echo "Admin must use an isolated credential namespace." >&2
  exit 1
fi

for forbidden in ai_integration catalog_sharing data_governance homes inventory \
  purchasing reporting shopping sync_conflicts; do
  if find lib -type d -name "${forbidden}" -print -quit | grep -q .; then
    echo "Admin contains forbidden homeowner feature directory: ${forbidden}" >&2
    exit 1
  fi
done

if rg -n '^\s+(camera|drift|drift_flutter|file_picker|image_picker|sqlite3):' pubspec.yaml; then
  echo "Admin contains a forbidden homeowner/media persistence dependency." >&2
  exit 1
fi

EXPECTED="61d49a5b0c857b532e27cfc243a2701731f7b0f2c4d5f5ab39d3fb0636790cdd"
ACTUAL="$(sha256sum contracts/providentia-v1.json | cut -d' ' -f1)"
test "${ACTUAL}" = "${EXPECTED}"

node tool/verify_contract.mjs
node tool/generate_admin_api_client.mjs --check

echo "Admin structural and contract boundaries verified."
