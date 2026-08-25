#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

test -f pubspec.yaml
test -f contracts/openapi/providentia-v1.json
test -f contracts/openapi/contract.lock.json
test -f tools/agent-requirements.json
test -x tools/agent-setup.sh

for forbidden in android ios macos web windows; do
  if [ -d "${forbidden}" ]; then
    echo "Admin must remain Linux-only; found ${forbidden}/" >&2
    exit 1
  fi
done

if rg -n '/api/v1/homes/.+(stock|receipt|purchase|location|report)' lib; then
  echo "Admin must not call household-content endpoints." >&2
  exit 1
fi

if rg -n "providentia\.client\.|providentia\.homeowner\." lib; then
  echo "Admin must use an isolated credential namespace." >&2
  exit 1
fi

EXPECTED="61d49a5b0c857b532e27cfc243a2701731f7b0f2c4d5f5ab39d3fb0636790cdd"
ACTUAL="$(sha256sum contracts/openapi/providentia-v1.json | cut -d' ' -f1)"
test "${ACTUAL}" = "${EXPECTED}"

echo "Admin structural and contract boundaries verified."

