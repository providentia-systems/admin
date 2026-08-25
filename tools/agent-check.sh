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
flutter build linux --release \
  --dart-define=PROVIDENTIA_API_BASE_URL=https://api.example.invalid

echo "Admin format, contract, analysis, tests, coverage and Linux release are green."
