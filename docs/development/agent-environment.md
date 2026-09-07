# Agent and developer environment

The Admin repository is a Linux-only Flutter desktop application. Every human
and automated contributor must be able to format, analyze, test and compile the
actual release bundle. `tools/agent-setup.sh` is the canonical vendor-neutral,
idempotent bootstrap. Editor- or agent-specific hooks may call it but must not
duplicate setup logic.

## Bootstrap

On Ubuntu or Debian:

```bash
bash tools/agent-setup.sh
source .agent-env
```

The script installs the Linux desktop toolchain, downloads the pinned official
Flutter archive, verifies its SHA-256 digest, prepares Linux artifacts, obtains
packages and writes only non-secret session configuration to `.agent-env`.
Node 22.14.0 is installed from its checksum-pinned official Linux x64 archive
because contract generation and coverage enforcement are executable build
inputs; the host distribution's moving `nodejs` package is not used. Both SDK
installers stage replacements atomically, validate cached runtimes and repair a
truncated or otherwise unhealthy cache instead of silently reusing it.
Override `PROVIDENTIA_AGENT_CACHE` when the default repository-local cache is
not durable. The cache and `.agent-env` are ignored by Git.

Cloud sandboxes must allow the hosts listed in
`tools/agent-requirements.json`. Runtime access is limited to the configured
HTTPS backend origin. No PayPal or AI provider network access belongs in Admin.
The same manifest declares Debian packaging, GnuPG, D-Bus and Xvfb so an agent
can build packages, validate native linkage and boot the real Flutter bundle
without relying on a maintainer workstation.

The Linux-only dependency graph deliberately overrides
`path_provider_android` to 2.2.23. Its 2.3.x line introduces Android JNI native
assets through Flutter's cross-platform resolver and can make a Linux bundle
depend on whether the build host happens to expose a JDK. The lock, generated
plugin list, CMake configuration and packaged-artifact verifier all reject JNI;
do not remove this pin until the upstream Linux graph is demonstrably JNI-free.

Authentication uses an eight-digit email code entered in the Admin client.
The Linux desktop package launches the application normally and does not register
an authentication URI scheme. No application-link base, browser approval page,
callback listener or polling worker is required. The backend email service must
be configured; local development can use its Mailpit service to read the code.
The requesting installation retains its binding proof in the isolated Admin
keyring namespace and sends it only to the code-verification JSON endpoint.

Create the first system owner in the backend before signing in:

```bash
php bin/providentia system:owner owner@example.com
```

This command authorizes one bootstrap identity. Sign in to Admin with that
address, enter the email code, complete the profile and country agreement, then
configure administrator groups and approve additional applicants. Repeating the
command with the same address is idempotent; it cannot replace the system owner.

## Validate

```bash
bash tools/agent-check.sh
```

Use `--check` to skip host-package installation when the image already contains
the declared packages. The canonical check builds the Linux release, produces
DEB/AppImage/tar packages, validates every bundled native library and runs a
15-second D-Bus/Xvfb launch smoke. Pull-request CI repeats the DEB validation
after installing it on a fresh Ubuntu job.

Protected Linux releases run from an exact `vVERSION` tag or a manual workflow
dispatch. The production backend origin is supplied only through the protected
`PRODUCTION_API_BASE_URL` variable and compiled with
`PROVIDENTIA_API_BASE_URL`; it is never committed. Tag publication requires
`LINUX_SIGNING_KEY_BASE64`, `LINUX_SIGNING_KEY_ID` and
`LINUX_SIGNING_PASSPHRASE`. Missing signing configuration blocks publication,
while a manual `publish=false` dispatch can still prove the unsigned candidate.

Never place access tokens, refresh tokens, backend credentials, provider keys,
or production URLs in repository files or build logs. Native credentials are
stored under the `providentia.admin.*` keyring namespace and are cleared on any
loss of operator authorization.
