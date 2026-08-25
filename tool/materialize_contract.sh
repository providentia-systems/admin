#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT}/contracts/source/providentia-v1.json.gz"
OUTPUT="${ROOT}/contracts/providentia-v1.json"
ARCHIVE_SHA256="805337b836abc8e581df628a77da0cbbdb67173aab4c3b82ba1c6921a45f9415"
OUTPUT_SHA256="61d49a5b0c857b532e27cfc243a2701731f7b0f2c4d5f5ab39d3fb0636790cdd"

sha256_file() {
  sha256sum "$1" | cut -d' ' -f1
}

if [ "$(sha256_file "${ARCHIVE}")" != "${ARCHIVE_SHA256}" ]; then
  echo "Pinned Admin contract archive checksum mismatch." >&2
  exit 1
fi

if [ -f "${OUTPUT}" ] && [ "$(sha256_file "${OUTPUT}")" = "${OUTPUT_SHA256}" ]; then
  exit 0
fi

TEMP_OUTPUT="$(mktemp "${OUTPUT}.part.XXXXXX")"
trap 'rm -f "${TEMP_OUTPUT}"' EXIT
gzip --decompress --stdout "${ARCHIVE}" > "${TEMP_OUTPUT}"

if [ "$(sha256_file "${TEMP_OUTPUT}")" != "${OUTPUT_SHA256}" ]; then
  echo "Materialized Admin contract checksum mismatch." >&2
  exit 1
fi

mv "${TEMP_OUTPUT}" "${OUTPUT}"
trap - EXIT
echo "Materialized Providentia API 1.15.0 contract."
