#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo 'Usage: sign_linux_artifacts.sh ARTIFACT_DIRECTORY' >&2
  exit 64
fi

ARTIFACT_DIRECTORY="$(realpath "$1")"
[[ -d "${ARTIFACT_DIRECTORY}" ]] || {
  echo "Artifact directory does not exist: ${ARTIFACT_DIRECTORY}" >&2
  exit 66
}

: "${LINUX_SIGNING_KEY_BASE64:?Missing protected Linux signing key}"
: "${LINUX_SIGNING_KEY_ID:?Missing protected Linux signing key identifier}"
: "${LINUX_SIGNING_PASSPHRASE:?Missing protected Linux signing passphrase}"
[[ "${LINUX_SIGNING_KEY_ID}" =~ ^[0-9A-Fa-f]{16,40}$ ]] || {
  echo 'LINUX_SIGNING_KEY_ID must be a 16-40 character hexadecimal key identifier.' >&2
  exit 65
}

(cd "${ARTIFACT_DIRECTORY}" && sha256sum --check SHA256SUMS)

SIGNING_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${SIGNING_ROOT}"' EXIT
export GNUPGHOME="${SIGNING_ROOT}/gnupg"
install -d -m 0700 "${GNUPGHOME}"
KEY_FILE="${SIGNING_ROOT}/key.asc"
PASSPHRASE_FILE="${SIGNING_ROOT}/passphrase"
printf '%s' "${LINUX_SIGNING_KEY_BASE64}" | base64 --decode > "${KEY_FILE}"
printf '%s' "${LINUX_SIGNING_PASSPHRASE}" > "${PASSPHRASE_FILE}"
chmod 0600 "${KEY_FILE}" "${PASSPHRASE_FILE}"

gpg --batch --quiet --import "${KEY_FILE}"
gpg --batch --list-secret-keys "${LINUX_SIGNING_KEY_ID}" >/dev/null

ARTIFACTS=(
  "${ARTIFACT_DIRECTORY}"/*.deb
  "${ARTIFACT_DIRECTORY}"/*.AppImage
  "${ARTIFACT_DIRECTORY}"/*.tar.gz
  "${ARTIFACT_DIRECTORY}/SHA256SUMS"
)
for artifact in "${ARTIFACTS[@]}"; do
  [[ -f "${artifact}" ]] || {
    echo "Expected release artifact is missing: ${artifact}" >&2
    exit 66
  }
  gpg --batch --yes --pinentry-mode loopback \
    --passphrase-file "${PASSPHRASE_FILE}" \
    --local-user "${LINUX_SIGNING_KEY_ID}" \
    --armor --detach-sign --output "${artifact}.asc" "${artifact}"
  gpg --batch --verify "${artifact}.asc" "${artifact}"
done

echo 'Linux release artifacts were signed and verified.'
