#!/usr/bin/env bash
set -euo pipefail

readonly VERSION='3.44.7'
readonly FRAMEWORK_REVISION='84fc5cbb223bc12f83d65b647ff8a56caf779ffd'
readonly ARCHIVE='flutter_linux_3.44.7-stable.tar.xz'
readonly SHA256='a0edd646c159c0e816788c0e46a4f071199c1320495898f5a679599b583a05a4'
readonly BASE_URL='https://storage.googleapis.com/flutter_infra_release/releases'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 INSTALL_PARENT" >&2
  exit 64
fi

install_parent=$1
if [[ -z "$install_parent" || "$install_parent" == '/' ]]; then
  echo 'Refusing unsafe Flutter installation parent.' >&2
  exit 64
fi

mkdir -p "$install_parent"
command -v node >/dev/null || {
  echo 'Pinned Node must be on PATH before installing Flutter.' >&2
  exit 69
}

flutter_is_healthy() {
  local root=$1
  [[ -x "$root/bin/flutter" ]] || return 1
  local health_directory machine status
  health_directory=$(mktemp -d "$install_parent/.flutter-health.XXXXXX")
  status=0
  if ! machine=$(
    CI=true \
      DART_SUPPRESS_ANALYTICS=true \
      PUB_CACHE="$health_directory/pub-cache" \
      XDG_CONFIG_HOME="$health_directory/xdg/config" \
      XDG_CACHE_HOME="$health_directory/xdg/cache" \
      XDG_DATA_HOME="$health_directory/xdg/data" \
      ANALYZER_STATE_LOCATION_OVERRIDE="$health_directory/dart-analysis" \
      timeout 60s "$root/bin/flutter" --version --machine 2>/dev/null
  ); then
    status=1
  elif ! printf '%s' "$machine" | node -e '
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
  '; then
    status=1
  fi
  rm -rf -- "$health_directory"
  return "$status"
}

target="$install_parent/flutter"
if flutter_is_healthy "$target"; then
  echo "Using verified Flutter $VERSION ($FRAMEWORK_REVISION) at $target"
  exit 0
fi

download_directory=$(mktemp -d "$install_parent/.flutter-install.XXXXXX")
trap 'rm -rf -- "$download_directory"' EXIT
archive_path="$download_directory/$ARCHIVE"
curl --fail --location --retry 3 --output "$archive_path.part" \
  "$BASE_URL/stable/linux/$ARCHIVE"
printf '%s  %s\n' "$SHA256" "$archive_path.part" |
  sha256sum --check --status
mv "$archive_path.part" "$archive_path"
tar --no-same-owner --extract --xz --file "$archive_path" \
  --directory "$download_directory"
candidate="$download_directory/flutter"

if ! flutter_is_healthy "$candidate"; then
  echo "Expected healthy Flutter $VERSION ($FRAMEWORK_REVISION)." >&2
  exit 65
fi

previous="$download_directory/previous-flutter"
if [[ -e "$target" || -L "$target" ]]; then
  mv "$target" "$previous"
fi
if ! mv "$candidate" "$target"; then
  if [[ -e "$previous" || -L "$previous" ]]; then
    mv "$previous" "$target"
  fi
  exit 73
fi
rm -rf -- "$previous"

echo "Installed verified Flutter $VERSION at $target"
