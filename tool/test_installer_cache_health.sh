#!/usr/bin/env bash
set -euo pipefail

readonly VERSION='22.14.0'

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 NODE_INSTALL_PARENT" >&2
  exit 64
fi

install_parent=$1
target="$install_parent/node"
if [[ -z "$install_parent" || "$install_parent" == '/' ||
  ! -x "$target/bin/node" ]]; then
  echo 'Cache-repair test requires an isolated, installed Node target.' >&2
  exit 64
fi

if bash "$(dirname "${BASH_SOURCE[0]}")/install_node_linux.sh" / \
  >/dev/null 2>&1; then
  echo 'Installer accepted an unsafe target.' >&2
  exit 1
fi

printf '#!/bin/sh\nexit 99\n' > "$target/bin/node"
chmod 0755 "$target/bin/node"
if "$target/bin/node" --version >/dev/null 2>&1; then
  echo 'The corruption fixture unexpectedly remained executable.' >&2
  exit 1
fi

bash "$(dirname "${BASH_SOURCE[0]}")/install_node_linux.sh" "$install_parent"
if [[ "$($target/bin/node --version)" != "v$VERSION" ]]; then
  echo 'Installer did not atomically repair the corrupted Node runtime.' >&2
  exit 1
fi

echo 'Pinned Node cache corruption was detected and repaired.'
