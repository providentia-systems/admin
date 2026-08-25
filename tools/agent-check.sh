#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ -f .agent-env ]; then
  # The generated file contains only project-local tool/cache paths and the
  # non-secret local test-lane URL.
  # shellcheck disable=SC1091
  source .agent-env
fi

export DART_SUPPRESS_ANALYTICS="true"
export ANALYZER_STATE_LOCATION_OVERRIDE="${ANALYZER_STATE_LOCATION_OVERRIDE:-${XDG_CACHE_HOME:-${ROOT}/.agent-tools/xdg/cache}/dart-analysis}"
mkdir -p "${ANALYZER_STATE_LOCATION_OVERRIDE}"

bash tool/materialize_contract.sh
bash tools/verify-structure.sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
node tool/check_coverage.mjs
bash tool/test_linux_release_scripts.sh
flutter build linux --release \
  --dart-define=PROVIDENTIA_API_BASE_URL=https://api.example.invalid
PROVIDENTIA_RELEASE_VERSION=0.1.0-dev \
  bash packaging/linux/build-packages.sh
PROVIDENTIA_LINUX_LAUNCH_SMOKE=true \
  bash tool/verify_linux_deb.sh \
    build/packages/providentia-admin_0.1.0-dev_amd64.deb

echo "Admin format, contract, analysis, tests, coverage, Linux packages and launch are green."
