#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_CACHE="${PROVIDENTIA_AGENT_CACHE:-${PROJECT_ROOT}/.agent-tools}"
FLUTTER_VERSION="3.44.7"
FLUTTER_FRAMEWORK_REVISION="84fc5cbb223bc12f83d65b647ff8a56caf779ffd"
FLUTTER_SHA256="a0edd646c159c0e816788c0e46a4f071199c1320495898f5a679599b583a05a4"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_ROOT="${TOOL_CACHE}/flutter-${FLUTTER_VERSION}"
NODE_VERSION="22.14.0"
NODE_PARENT="${TOOL_CACHE}/node-${NODE_VERSION}-linux-x64"
NODE_ROOT="${NODE_PARENT}/node"
PUB_CACHE_PATH="${PROVIDENTIA_PUB_CACHE:-${TOOL_CACHE}/pub-cache}"
XDG_CONFIG_PATH="${PROVIDENTIA_XDG_CONFIG_HOME:-${TOOL_CACHE}/xdg/config}"
XDG_CACHE_PATH="${PROVIDENTIA_XDG_CACHE_HOME:-${TOOL_CACHE}/xdg/cache}"
XDG_DATA_PATH="${PROVIDENTIA_XDG_DATA_HOME:-${TOOL_CACHE}/xdg/data}"
ANALYZER_STATE_PATH="${PROVIDENTIA_ANALYZER_STATE_LOCATION:-${XDG_CACHE_PATH}/dart-analysis}"

install_linux_packages() {
  local packages=(
    ca-certificates clang cmake coreutils curl git gzip jq libgtk-3-dev liblzma-dev
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
  flutter_is_healthy() {
    local root="$1"
    [ -x "${root}/bin/flutter" ] || return 1
    local machine
    machine="$(
      CI=true \
        DART_SUPPRESS_ANALYTICS=true \
        PUB_CACHE="${PUB_CACHE_PATH}" \
        XDG_CONFIG_HOME="${XDG_CONFIG_PATH}" \
        XDG_CACHE_HOME="${XDG_CACHE_PATH}" \
        XDG_DATA_HOME="${XDG_DATA_PATH}" \
        ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_PATH}" \
        PATH="${NODE_ROOT}/bin:${root}/bin:${PATH}" \
        timeout 60s "${root}/bin/flutter" --version --machine 2>/dev/null
    )" || return 1
    printf '%s' "${machine}" | "${NODE_ROOT}/bin/node" -e '
      let input = "";
      process.stdin.on("data", chunk => input += chunk);
      process.stdin.on("end", () => {
        const value = JSON.parse(input);
        const version = value.flutterVersion ?? value.frameworkVersion;
        process.exit(
          version === "3.44.7" &&
          value.frameworkRevision === "84fc5cbb223bc12f83d65b647ff8a56caf779ffd"
            ? 0 : 1,
        );
      });
    '
  }

  if flutter_is_healthy "${FLUTTER_ROOT}"; then
    echo "Using healthy cached Flutter ${FLUTTER_VERSION} SDK."
    return
  fi
  mkdir -p "${TOOL_CACHE}"
  local archive="${TOOL_CACHE}/flutter-${FLUTTER_VERSION}.tar.xz"
  if ! echo "${FLUTTER_SHA256}  ${archive}" | sha256sum --check --status 2>/dev/null; then
    local partial="${archive}.part"
    rm -f "${partial}"
    curl --fail --location --retry 3 --output "${partial}" "${FLUTTER_URL}"
    echo "${FLUTTER_SHA256}  ${partial}" | sha256sum --check --status
    mv "${partial}" "${archive}"
  else
    echo "Using verified cached Flutter ${FLUTTER_VERSION} archive."
  fi
  local extract
  extract="$(mktemp -d "${TOOL_CACHE}/flutter-extract.XXXXXX")"
  # Cloud workspaces commonly reject the numeric uid/gid stored in Flutter's
  # release archive.  Extract as the current agent user so bootstrap remains
  # portable across restricted containers and ordinary developer machines.
  tar --extract --xz --no-same-owner --file "${archive}" --directory "${extract}"
  if ! flutter_is_healthy "${extract}/flutter"; then
    rm -rf -- "${extract}"
    echo "The verified Flutter archive produced an unhealthy SDK." >&2
    return 1
  fi

  local previous="${extract}/previous-flutter"
  if [ -e "${FLUTTER_ROOT}" ] || [ -L "${FLUTTER_ROOT}" ]; then
    mv "${FLUTTER_ROOT}" "${previous}"
  fi
  if ! mv "${extract}/flutter" "${FLUTTER_ROOT}"; then
    if [ -e "${previous}" ] || [ -L "${previous}" ]; then
      mv "${previous}" "${FLUTTER_ROOT}"
    fi
    rm -rf -- "${extract}"
    return 1
  fi
  rm -rf -- "${previous}" "${extract}"
}

if [ "${1:-}" = "--check" ]; then
  for command in curl git gzip sha256sum tar timeout xz; do
    command -v "${command}" >/dev/null || {
      echo "Missing required command: ${command}" >&2
      exit 1
    }
  done
else
  install_linux_packages
fi
mkdir -p "${PUB_CACHE_PATH}" "${XDG_CONFIG_PATH}" "${XDG_CACHE_PATH}" \
  "${XDG_DATA_PATH}" "${ANALYZER_STATE_PATH}"
bash "${PROJECT_ROOT}/tool/install_node_linux.sh" "${NODE_PARENT}"
install_flutter

export PATH="${NODE_ROOT}/bin:${FLUTTER_ROOT}/bin:${PATH}"
export PUB_CACHE="${PUB_CACHE_PATH}"
export XDG_CONFIG_HOME="${XDG_CONFIG_PATH}"
export XDG_CACHE_HOME="${XDG_CACHE_PATH}"
export XDG_DATA_HOME="${XDG_DATA_PATH}"
export ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_PATH}"
export DART_SUPPRESS_ANALYTICS="true"
# Flutter otherwise probes the Azure instance metadata endpoint while trying
# to infer whether it runs on a bot. Agent bootstrap is CI by definition, so
# declare that explicitly and keep instance credentials outside its reach.
export CI="${CI:-true}"
mkdir -p "${PUB_CACHE}" "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" \
  "${XDG_DATA_HOME}" "${ANALYZER_STATE_LOCATION_OVERRIDE}"

cd "${PROJECT_ROOT}"
bash tool/materialize_contract.sh
flutter config --no-analytics --enable-linux-desktop
flutter precache --linux
flutter pub get --enforce-lockfile

cat > "${PROJECT_ROOT}/.agent-env" <<EOF
export PATH="${NODE_ROOT}/bin:${FLUTTER_ROOT}/bin:\${PATH}"
export PUB_CACHE="${PUB_CACHE}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME}"
export XDG_DATA_HOME="${XDG_DATA_HOME}"
export ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_LOCATION_OVERRIDE}"
export DART_SUPPRESS_ANALYTICS="${DART_SUPPRESS_ANALYTICS}"
export CI="${CI}"
export PROVIDENTIA_API_BASE_URL="${PROVIDENTIA_API_BASE_URL:-http://localhost:8080}"
EOF

flutter doctor -v
echo "Agent environment ready. Source ${PROJECT_ROOT}/.agent-env before validating."
