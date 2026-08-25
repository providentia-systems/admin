#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_CACHE="${PROVIDENTIA_AGENT_CACHE:-${PROJECT_ROOT}/.agent-tools}"
FLUTTER_VERSION="3.44.7"
FLUTTER_SHA256="a0edd646c159c0e816788c0e46a4f071199c1320495898f5a679599b583a05a4"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_ROOT="${TOOL_CACHE}/flutter-${FLUTTER_VERSION}"

install_linux_packages() {
  local packages=(
    ca-certificates clang cmake curl git jq libgtk-3-dev liblzma-dev
    libsecret-1-dev ninja-build pkg-config ripgrep unzip xz-utils zip
  )
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Unsupported host package manager. Install tools/agent-requirements.json manually." >&2
    return 1
  fi
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
  else
    echo "Root or sudo is required once for Linux build dependencies." >&2
    return 1
  fi
}

install_flutter() {
  if [ -x "${FLUTTER_ROOT}/bin/flutter" ]; then
    return
  fi
  mkdir -p "${TOOL_CACHE}"
  local archive="${TOOL_CACHE}/flutter-${FLUTTER_VERSION}.tar.xz"
  curl --fail --location --retry 3 --output "${archive}" "${FLUTTER_URL}"
  echo "${FLUTTER_SHA256}  ${archive}" | sha256sum --check --status
  local extract="${TOOL_CACHE}/extract-${FLUTTER_VERSION}"
  rm -rf "${extract}"
  mkdir -p "${extract}"
  tar -xJf "${archive}" -C "${extract}"
  mv "${extract}/flutter" "${FLUTTER_ROOT}"
  rmdir "${extract}"
}

if [ "${1:-}" = "--check" ]; then
  for command in curl git sha256sum tar xz; do
    command -v "${command}" >/dev/null || {
      echo "Missing required command: ${command}" >&2
      exit 1
    }
  done
else
  install_linux_packages
fi
install_flutter

export PATH="${FLUTTER_ROOT}/bin:${PATH}"
export PUB_CACHE="${PROVIDENTIA_PUB_CACHE:-${TOOL_CACHE}/pub-cache}"
mkdir -p "${PUB_CACHE}"

cd "${PROJECT_ROOT}"
flutter config --no-analytics --enable-linux-desktop
flutter precache --linux
flutter pub get

cat > "${PROJECT_ROOT}/.agent-env" <<EOF
export PATH="${FLUTTER_ROOT}/bin:\${PATH}"
export PUB_CACHE="${PUB_CACHE}"
export PROVIDENTIA_API_BASE_URL="${PROVIDENTIA_API_BASE_URL:-http://localhost:8080}"
EOF

flutter doctor -v
echo "Agent environment ready. Source ${PROJECT_ROOT}/.agent-env before validating."
