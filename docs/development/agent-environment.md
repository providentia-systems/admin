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

The Linux desktop package registers `providentia-admin://` for application-owned
login approvals. Development and test links must carry approval credentials in
the URI fragment, never the query string. The native runner forwards accepted
links through the isolated `providentia.admin.application_links` channel and
does not print or persist them. The Flutter parser enforces the Admin scheme,
host, path, application kind, request identifier and credential bounds before
any network call.

## Validate

```bash
bash tools/agent-check.sh
```

Use `--check` to skip host-package installation when the image already contains
the declared packages. CI runs the same commands and publishes installable
artifacts from the release bundle.

Never place access tokens, refresh tokens, backend credentials, provider keys,
or production URLs in repository files or build logs. Native credentials are
stored under the `providentia.admin.*` keyring namespace and are cleared on any
loss of operator authorization.
