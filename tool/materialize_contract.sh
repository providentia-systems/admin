#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT}/contracts/source/providentia-v1.json.gz"
OUTPUT="${ROOT}/contracts/providentia-v1.json"
ARCHIVE_SHA256='5e1e3f7224b85e52e09a298d2ad4c5a82d564c35d21d90e2b872bf33b3e9db8f'
OUTPUT_SHA256='40a8477521baa6c41cf2c5d872068f5ae1bf255a8d0bbccc97a05688d705ad57'

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
