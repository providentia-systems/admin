#!/usr/bin/env bash
set -Eeuo pipefail
admin_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend_root="$(cd -- "${1:?Usage: bash tool/run_backend_compatibility.sh BACKEND_CHECKOUT}" && pwd)"
if [[ -n "${DATABASE_URL:-}" ]]; then
  echo 'Paired Admin acceptance requires its own disposable SQLite database; unset DATABASE_URL.' >&2
  exit 2
fi
command -v php >/dev/null
command -v flutter >/dev/null
node "$admin_root/tool/verify_backend_compatibility.mjs" "$backend_root"
temporary="$(mktemp -d)"
pid=''
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$temporary"
}
trap cleanup EXIT
export DATABASE_URL="sqlite:///$temporary/admin-compatibility.sqlite"
export APP_ENV=test PROVIDENTIA_STEP2_CONFORMANCE=1 QUEUE_REQUIRED=0
export AUTH_TOKEN_PEPPER=paired-admin-isolated-pepper-at-least-32-bytes
export PROVIDENTIA_ADMIN_COMPATIBILITY_FIXTURE="$temporary/fixture.json"
port="${PROVIDENTIA_ADMIN_COMPATIBILITY_PORT:-18089}"
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || ((port < 1024 || port > 65535)); then
  echo 'Paired Admin HTTP port must be an unprivileged TCP port.' >&2
  exit 2
fi
export PROVIDENTIA_ADMIN_COMPATIBILITY_URL="http://127.0.0.1:$port"
(
  cd "$backend_root"
  php bin/doctrine-migrations migrations:migrate --no-interaction >/dev/null
  php "$admin_root/tool/seed_admin_compatibility.php" "$backend_root" "$PROVIDENTIA_ADMIN_COMPATIBILITY_FIXTURE"
)
(cd "$backend_root" && exec php -S "127.0.0.1:$port" -t public public/index.php) >"$temporary/http.log" 2>&1 &
pid=$!
ready=0
for attempt in $(seq 1 50); do
  kill -0 "$pid" 2>/dev/null || { echo 'Paired backend failed to start.' >&2; exit 1; }
  if grep -Fq "Development Server (http://127.0.0.1:$port) started" "$temporary/http.log" \
      && curl --fail --silent --connect-timeout 2 --max-time 5 "$PROVIDENTIA_ADMIN_COMPATIBILITY_URL/health/live" >/dev/null; then
    kill -0 "$pid" 2>/dev/null || exit 1
    ready=1
    break
  fi
  sleep 0.1
done
test "$ready" = 1
(cd "$admin_root" && flutter test --no-pub test/integration/backend_compatibility_live_test.dart --reporter expanded)
printf 'Authenticated synthetic native Admin/backend compatibility passed. No installed acceptance is implied.\n'
