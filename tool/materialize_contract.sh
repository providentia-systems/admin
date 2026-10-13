#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT}/contracts/source/providentia-v1.json.gz"
OUTPUT="${ROOT}/contracts/providentia-v1.json"
ARCHIVE_SHA256='c7ca8e3b7ef29530fc64f5e47ed005202e85c931563bf794529b93f275432995'
OUTPUT_SHA256='b6b7f8b5aed3c79c8cb751b21ab1c9dc21786124bb56ab08d21955ace8d7bd36'

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
echo "Materialized Providentia API 2.2.0 contract."
