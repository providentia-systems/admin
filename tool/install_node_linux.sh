#!/usr/bin/env bash
set -euo pipefail

readonly VERSION='22.14.0'
readonly ARCHIVE="node-v${VERSION}-linux-x64.tar.xz"
readonly SHA256='69b09dba5c8dcb05c4e4273a4340db1005abeafe3927efda2bc5b249e80437ec'
readonly URL="https://nodejs.org/dist/v${VERSION}/${ARCHIVE}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 INSTALL_PARENT" >&2
  exit 64
fi

install_parent=$1
if [[ -z "$install_parent" || "$install_parent" == '/' ]]; then
  echo 'Refusing unsafe Node installation parent.' >&2
  exit 64
fi

target="$install_parent/node"
if [[ -x "$target/bin/node" ]] &&
  [[ "$($target/bin/node --version 2>/dev/null)" == "v$VERSION" ]]; then
  echo "Using verified Node $VERSION at $target"
  exit 0
fi

mkdir -p "$install_parent"
download_directory="$install_parent/.downloads"
mkdir -p "$download_directory"
archive_path="$download_directory/$ARCHIVE"
if ! printf '%s  %s\n' "$SHA256" "$archive_path" |
  sha256sum --check --status 2>/dev/null; then
  curl --fail --location --retry 3 --output "$archive_path.part" "$URL"
  printf '%s  %s\n' "$SHA256" "$archive_path.part" |
    sha256sum --check --status
  mv "$archive_path.part" "$archive_path"
else
  echo "Using checksum-verified cached Node $VERSION archive."
fi

stage=$(mktemp -d "$install_parent/.node-install.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
tar --no-same-owner --extract --xz --file "$archive_path" --directory "$stage"
candidate="$stage/node-v$VERSION-linux-x64"
if [[ ! -x "$candidate/bin/node" ]] ||
  [[ "$($candidate/bin/node --version 2>/dev/null)" != "v$VERSION" ]]; then
  echo "The verified Node archive did not produce Node $VERSION." >&2
  exit 65
fi

previous="$stage/previous-node"
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

echo "Installed verified Node $VERSION at $target"
