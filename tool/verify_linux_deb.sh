#!/usr/bin/env bash
set -euo pipefail

verify_linkage() {
  local native_file="$1"
  local library_path="$2"
  local linkage
  linkage="$(
    LD_LIBRARY_PATH="${library_path}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
      ldd "${native_file}"
  )"
  if grep -Fq 'not found' <<<"${linkage}"; then
    echo "Unresolved native dependency in ${native_file}:" >&2
    grep -F 'not found' <<<"${linkage}" >&2
    exit 66
  fi
}

if (( $# != 1 )); then
  echo 'Usage: verify_linux_deb.sh DEBIAN_PACKAGE' >&2
  exit 64
fi

for command in dbus-run-session dpkg-deb find grep ldconfig ldd realpath timeout; do
  command -v "${command}" >/dev/null || {
    echo "Missing Linux package verification command: ${command}" >&2
    exit 69
  }
done

PACKAGE="$(realpath "$1")"
[[ -f "${PACKAGE}" ]] || {
  echo "Debian package does not exist: ${PACKAGE}" >&2
  exit 66
}

[[ "$(dpkg-deb --field "${PACKAGE}" Package)" == 'providentia-admin' ]] || {
  echo 'Debian package name is not providentia-admin.' >&2
  exit 65
}
[[ "$(dpkg-deb --field "${PACKAGE}" Architecture)" == 'amd64' ]] || {
  echo 'Debian package architecture is not amd64.' >&2
  exit 65
}
[[ "$(dpkg-deb --field "${PACKAGE}" Version)" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || {
  echo 'Debian package version is not semantic.' >&2
  exit 65
}

DEPENDENCIES=",$(dpkg-deb --field "${PACKAGE}" Depends | tr -d ' '),"
for dependency in libegl1 libgles2 libgtk-3-0 libsecret-1-0; do
  [[ "${DEPENDENCIES}" == *",${dependency},"* ]] || {
    echo "Debian package is missing runtime dependency: ${dependency}" >&2
    exit 65
  }
done

LDCONFIG_OUTPUT="$(ldconfig -p)"
for runtime_library in libEGL.so.1 libGLESv2.so.2; do
  grep -Fq "${runtime_library}" <<<"${LDCONFIG_OUTPUT}" || {
    echo "Clean host cannot resolve required Flutter runtime: ${runtime_library}" >&2
    exit 69
  }
done

EXTRACTION_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${EXTRACTION_ROOT}"' EXIT
dpkg-deb --extract "${PACKAGE}" "${EXTRACTION_ROOT}"
BUNDLE_ROOT="${EXTRACTION_ROOT}/opt/providentia-admin"
BINARY="${BUNDLE_ROOT}/providentia_admin"
LIBRARY_ROOT="${BUNDLE_ROOT}/lib"
DESKTOP_FILE="${EXTRACTION_ROOT}/usr/share/applications/com.vastdevelopmentmethod.providentia.admin.desktop"

[[ -x "${BINARY}" ]] || {
  echo 'Installed Providentia Admin executable is missing.' >&2
  exit 66
}
[[ -f "${LIBRARY_ROOT}/libflutter_linux_gtk.so" ]] || {
  echo 'Installed Flutter Linux runtime is missing.' >&2
  exit 66
}
[[ -f "${LIBRARY_ROOT}/libflutter_secure_storage_linux_plugin.so" ]] || {
  echo 'Installed Admin keyring plugin is missing.' >&2
  exit 66
}
[[ ! -e "${LIBRARY_ROOT}/libdartjni.so" ]] || {
  echo 'Installed Linux package contains an Android-only JNI runtime.' >&2
  exit 66
}
[[ -f "${DESKTOP_FILE}" ]] || {
  echo 'Installed Admin desktop registration is missing.' >&2
  exit 66
}
grep -Fqx 'Exec=providentia_admin %u' "${DESKTOP_FILE}"
grep -Fqx 'MimeType=x-scheme-handler/providentia-admin;' "${DESKTOP_FILE}"

verify_linkage "${BINARY}" "${LIBRARY_ROOT}"
while IFS= read -r -d '' native_library; do
  verify_linkage "${native_library}" "${LIBRARY_ROOT}"
done < <(find "${LIBRARY_ROOT}" -type f -name '*.so' -print0)

if [[ "${PROVIDENTIA_LINUX_LAUNCH_SMOKE:-false}" == true ]]; then
  command -v xvfb-run >/dev/null || {
    echo 'xvfb-run is required for the Linux launch smoke.' >&2
    exit 69
  }
  LAUNCH_BINARY="${PROVIDENTIA_LINUX_INSTALLED_BINARY:-${BINARY}}"
  [[ -x "${LAUNCH_BINARY}" ]] || {
    echo "Linux launch target is not executable: ${LAUNCH_BINARY}" >&2
    exit 66
  }
  set +e
  dbus-run-session -- timeout --signal=TERM --kill-after=5s 15s \
    xvfb-run -a "${LAUNCH_BINARY}"
  LAUNCH_STATUS=$?
  set -e
  [[ "${LAUNCH_STATUS}" -eq 124 ]] || {
    echo "Providentia Admin exited before the 15-second launch smoke completed (status ${LAUNCH_STATUS})." >&2
    exit 70
  }
fi

echo "Verified Providentia Admin Debian package: ${PACKAGE}"
