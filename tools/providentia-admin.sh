#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT_ROOT

usage() {
  cat <<'USAGE'
Build and launch Providentia Admin on Ubuntu or Debian.

Usage:
  bash tools/providentia-admin.sh [options]

Options:
  --api-url URL              Public Providentia backend origin.
  --no-launch                Build without starting the application.
  --skip-system-packages     Skip apt; missing prerequisites fail the build.
  --validate-url URL         Validate and normalize a URL, then exit.
  -h, --help                 Show this help.

The backend origin must be HTTPS. Plain HTTP is accepted only for localhost,
127.0.0.1, or [::1]. Supply an origin only: no credentials, path, query, or
fragment. The value is compiled into this local Admin build; it is not a
database address and must not contain a password or API key.
USAGE
}

origin_error() {
  echo "Invalid backend origin: $1" >&2
  exit 64
}

validate_ipv4() {
  local value=$1
  local -a octets
  local octet
  IFS='.' read -r -a octets <<<"$value"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

validate_dns_name() {
  local value=$1
  local -a labels
  local label
  [[ ${#value} -le 253 && "$value" != .* && "$value" != *. &&
    "$value" != *..* ]] || return 1
  IFS='.' read -r -a labels <<<"$value"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9-]+$ ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9] && "$label" =~ [A-Za-z0-9]$ ]] || return 1
  done
}

validate_origin() {
  local value=$1
  local scheme remainder authority suffix host port='' ipv6=''
  [[ -n "$value" ]] || origin_error 'enter a URL.'
  [[ "$value" != *[$'\t\r\n ']* ]] ||
    origin_error 'whitespace is not allowed.'
  [[ "$value" != *'?'* && "$value" != *'#'* ]] ||
    origin_error 'queries and fragments are not allowed.'

  case "$value" in
    https://*) scheme='https' ;;
    http://*) scheme='http' ;;
    *) origin_error 'use https:// (or http:// for loopback development).' ;;
  esac
  remainder=${value#*://}
  authority=${remainder%%/*}
  suffix=${remainder#"$authority"}
  [[ -n "$authority" ]] || origin_error 'the host is missing.'
  [[ -z "$suffix" || "$suffix" == '/' ]] ||
    origin_error 'provide an origin without a path.'
  [[ "$authority" != *'@'* ]] ||
    origin_error 'embedded credentials are not allowed.'

  if [[ "$authority" =~ ^\[([^]]+)\](:([0-9]+))?$ ]]; then
    ipv6=${BASH_REMATCH[1]}
    port=${BASH_REMATCH[3]}
    [[ "$ipv6" == '::1' ]] ||
      origin_error 'use a DNS name for remote IPv6 servers.'
    host='[::1]'
  else
    [[ "$authority" != *:*:* ]] || origin_error 'the host is malformed.'
    if [[ "$authority" == *:* ]]; then
      host=${authority%:*}
      port=${authority##*:}
      [[ -n "$port" ]] ||
        origin_error 'the port must be a number from 1 to 65535.'
    else
      host=$authority
    fi
    [[ -n "$host" ]] || origin_error 'the host is missing.'
    if [[ "$host" =~ ^[0-9.]+$ ]]; then
      validate_ipv4 "$host" || origin_error 'the IPv4 address is malformed.'
    else
      validate_dns_name "$host" || origin_error 'the DNS name is malformed.'
    fi
  fi

  if [[ -n "$port" ]]; then
    [[ "$port" =~ ^[0-9]{1,5}$ ]] ||
      origin_error 'the port must be a number from 1 to 65535.'
    ((10#$port >= 1 && 10#$port <= 65535)) ||
      origin_error 'the port must be a number from 1 to 65535.'
  fi

  local lower_host=${host,,}
  local loopback=false
  if [[ "$lower_host" == 'localhost' || "$lower_host" == '127.0.0.1' ||
    "$lower_host" == '[::1]' ]]; then
    loopback=true
  fi
  if [[ "$scheme" == 'http' && "$loopback" != true ]]; then
    origin_error 'plain HTTP is allowed only on the local loopback interface.'
  fi

  printf '%s://%s\n' "$scheme" "$authority"
}

api_url=${PROVIDENTIA_API_BASE_URL:-}
no_launch=false
skip_system_packages=false
validate_only=false

while (($# > 0)); do
  case "$1" in
    --api-url)
      (($# >= 2)) || { echo '--api-url requires a value.' >&2; exit 64; }
      api_url=$2
      shift 2
      ;;
    --api-url=*)
      api_url=${1#*=}
      shift
      ;;
    --no-launch)
      no_launch=true
      shift
      ;;
    --skip-system-packages)
      skip_system_packages=true
      shift
      ;;
    --validate-url)
      (($# >= 2)) || { echo '--validate-url requires a value.' >&2; exit 64; }
      api_url=$2
      validate_only=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$api_url" ]]; then
  if [[ -t 0 ]]; then
    read -r -p 'Public backend origin (for example, https://api.example.com): ' \
      api_url
  else
    echo 'Pass --api-url URL when input is not interactive.' >&2
    exit 64
  fi
fi
api_url=$(validate_origin "$api_url")
if [[ "$validate_only" == true ]]; then
  echo "Valid backend origin: $api_url"
  exit 0
fi

[[ "$(uname -s)" == 'Linux' ]] || {
  echo 'Providentia Admin supports Linux only.' >&2
  exit 69
}
case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo 'The pinned Admin toolchain currently supports Linux x86_64 only.' >&2
    exit 69
    ;;
esac
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *' ubuntu '*|*' debian '*) ;;
    *)
      echo 'This guided setup supports Ubuntu and Debian-based systems.' >&2
      exit 69
      ;;
  esac
fi
if [[ $(id -u) -eq 0 ]]; then
  echo 'Run this script as your desktop user, not with sudo.' >&2
  exit 77
fi

echo "Building Providentia Admin for $api_url"
setup_arguments=()
if [[ "$skip_system_packages" == true ]]; then
  setup_arguments+=(--check)
fi

# Build tooling deliberately uses repository-local caches. Keeping this work
# inside a subshell prevents those XDG paths from reaching the launched app,
# which must use the desktop user's normal D-Bus keyring session.
(
  export PROVIDENTIA_API_BASE_URL="$api_url"
  bash "$PROJECT_ROOT/tools/agent-setup.sh" "${setup_arguments[@]}"
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.agent-env"
  cd "$PROJECT_ROOT"
  bash tool/materialize_contract.sh
  node tool/verify_contract.mjs
  node tool/generate_admin_api_client.mjs --check
  flutter build linux --release \
    --dart-define="PROVIDENTIA_API_BASE_URL=$api_url"
)

admin_binary="$PROJECT_ROOT/build/linux/x64/release/bundle/providentia_admin"
readonly admin_binary
if [[ ! -x "$admin_binary" ]]; then
  echo "The Admin build did not produce $admin_binary" >&2
  exit 70
fi

echo "Admin build ready: $admin_binary"
if [[ "$no_launch" == true ]]; then
  echo 'Build complete. Launch it from your normal desktop session when ready.'
  exit 0
fi
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo 'Build complete, but no graphical desktop session is available.' >&2
  echo "Run $admin_binary from your Ubuntu desktop." >&2
  exit 69
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  echo 'No desktop D-Bus session was detected; the keyring may be unavailable.' >&2
  echo 'Sign in to the graphical desktop and run this script again.' >&2
  exit 69
fi

cd "$PROJECT_ROOT"
exec "$admin_binary"
