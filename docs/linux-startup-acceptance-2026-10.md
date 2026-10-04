# Linux startup acceptance: October 2026 repair

## Runtime dependency

Admin's Debian package and agent setup now include `xdg-user-dirs`, which provides
`xdg-user-dir` for Linux user-directory discovery. A minimal host can satisfy all
shared-library linkage checks yet still fail startup when this command is absent.
Users launching the raw Linux bundle must install this package themselves; Debian
installation resolves it through the declared package dependency.

No existing database location, keyring credential, authentication flow or operator
permission is changed. Do not clear user data to test this dependency repair.

## Verification

`tool/verify_linux_deb.sh` retains the existing checks for package identity,
architecture, semantic version, declared runtimes, native linkage, keyring plugin,
absence of Android-only JNI libraries and absence of retired authentication URI
registration.

When `PROVIDENTIA_LINUX_LAUNCH_SMOKE=true`, it now requires a visible Flutter first
frame and rejects startup exceptions. The Linux runner makes the `Providentia
Admin` window visible only after its first Flutter frame. A process merely staying
alive until a timeout no longer counts as a successful launch.

The verifier creates a private temporary HOME and XDG configuration/cache/data
profile, observes the application for 60 quarter-second samples inside an outer
timeout, and checks for startup exceptions throughout. It then terminates only
its own test process and deletes its temporary profile. The installed-binary
override remains supported for clean-host acceptance.

Headless verification needs `dbus-run-session`, `xvfb` and `x11-utils`
(`xwininfo`) in addition to application runtimes. The CI and release verification
jobs provision these tools; `tools/agent-requirements.json` and agent setup also
include them. They are verification tools, not new production privileges.

From the repository root:

```sh
node --test tool/*.test.mjs
bash tool/test_linux_release_scripts.sh
PROVIDENTIA_LINUX_INSTALLED_BINARY=/usr/bin/providentia_admin \
  PROVIDENTIA_LINUX_LAUNCH_SMOKE=true \
  bash tool/verify_linux_deb.sh \
  build/packages/providentia-admin_0.1.0-dev_amd64.deb
```

The default package path above is produced by `packaging/linux/build-packages.sh`
when no release-version override is supplied. For a differently versioned build,
pass its actual generated package path. The installed-binary override should be
used only after installing that same package.

`tool/first_frame_smoke.test.mjs` tests visible success, an invisible live process,
a live process logging a startup exception, immediate exit and child cleanup.
`tool/test_linux_release_scripts.sh` additionally rejects a package missing
`xdg-user-dirs`, while retaining its existing runtime, URI, version and signing
guards. CI also launches the real built application on its clean-host job.

This verifies rendering and startup, not authenticated operator workflows. The
full Flutter tests, coverage threshold, Linux release build, security checks and
clean-host package acceptance remain required. Publication/signing still uses the
existing protected release procedure; these changes do not trigger a release.
