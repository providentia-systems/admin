#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${ROOT}/contracts/source/providentia-v1.json.gz"
OUTPUT="${ROOT}/contracts/providentia-v1.json"
ARCHIVE_SHA256="3943fd9c186b32ece7a14930a497d5dcca7dd826bab1262db072508135568815"
OUTPUT_SHA256="f01c320e1900f523661bbba24225583f1d61bc00f3949cb0e7b5b2f6fd5a524e"

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
echo "Materialized Providentia API 1.16.0 contract."
