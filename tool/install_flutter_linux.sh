#!/usr/bin/env bash
set -euo pipefail

readonly VERSION='3.44.7'
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

target="$install_parent/flutter"
if [[ -x "$target/bin/flutter" && -f "$target/version" ]] &&
  [[ "$(tr -d '\r\n' < "$target/version" 2>/dev/null)" == "$VERSION" ]]; then
  echo "Using verified Flutter $VERSION at $target"
  exit 0
fi

mkdir -p "$install_parent"
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

actual_version=$(tr -d '\r\n' < "$candidate/version")
if [[ "$actual_version" != "$VERSION" ]]; then
  echo "Expected Flutter $VERSION, found $actual_version." >&2
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
