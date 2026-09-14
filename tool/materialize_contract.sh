#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT}/contracts/source/providentia-v1.json.gz"
OUTPUT="${ROOT}/contracts/providentia-v1.json"
ARCHIVE_SHA256='feaba5779b8f8070c0de5d241641792ea29f44af4845302b3ea10af3d06586b8'
OUTPUT_SHA256='f6591ae866efbcc9e661528c7f595da0d7093d959d64c66c09b0c5be1dcb7c58'

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
echo "Materialized Providentia API 2.1.0 contract."
