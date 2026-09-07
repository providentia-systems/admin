# Providentia Admin

> **Proprietary software.** Copyright (c) 2026 Vast Development Method Trading
> Pty Ltd. All rights reserved. No licence is granted; see [LICENSE](LICENSE).

Providentia Admin is the separate Flutter administration client for the
Providentia home-stock platform. Its first supported target is Linux desktop;
there are deliberately no Android, iOS, macOS, web or Windows runners in this
repository.

Sign in by entering an email address and the eight-digit code delivered to that
mailbox. The backend sends the email; the client verifies the code using the
requesting installation's secret binding proof. Codes expire after ten minutes,
allow at most five incorrect attempts and have a sixty-second resend cooldown.
The application has its own installation, device, session and Linux keyring
namespace. Rotating refresh credentials are persisted atomically and are never
activated in memory if keyring storage fails.

Authorization comes from backend-managed administrator groups. The initial
system owner is authorized using `php bin/providentia system:owner EMAIL` in the
backend. This does not bypass email verification. Other administrator sign-ins
create an approval request; an authorized administrator selects their group and
approves access. The protected system-owner group has all administrator rights.
Other groups grant only their configured capabilities, including separate rights
for approving administrators, managing groups, inspecting people and homes,
maintaining catalog data, configuring countries and viewing audit events.

Authorized operators can inspect household products, categories, quantities and
other application records through dedicated `/api/v1/admin/` routes. This access
is independent of public catalog sharing and is audited by the backend. Public
sharing still means contributing catalog metadata for use by other homes; it does
not publish household quantities or grant access to another home's inventory.
The household client remains isolated by home membership. Admin never displays
session proofs, provider credentials or other stored secrets.

The access workspace manages separate account, home and administrator groups.
Each subject has one group in its scope. Account groups govern home ownership;
home groups govern features, quotas, role defaults and the permissions an owner
may delegate. Reducing a quota preserves existing records and blocks additions
over the new limit. Disabling an operation removes permission to perform it.

Country settings select starter groups, currency, timezone and a versioned
privacy agreement. Namibia is the only initially published country. The reference
data workspace requests backend updates from the official countries, states and
cities source. Profiles support names, verified email aliases, an opt-in Gravatar
or a cropped uploaded avatar. A verified primary email must always remain.

Billing enforcement and paid platform AI are future work. Manual group assignment
is available now; no payment or AI charge is required for the current rollout.

## Start development

```bash
bash tools/agent-setup.sh
source .agent-env
flutter run -d linux \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

See [the agent environment guide](docs/development/agent-environment.md) for the
pinned toolchain, host dependencies, network allowlist and complete validation
lane. The canonical backend contract is checksum-pinned under
`contracts/source/` and materialized only for validation and generation.

Pull-request CI builds the release bundle, produces checksum-pinned DEB,
AppImage and tar artifacts, installs the DEB on a fresh Ubuntu runner, verifies
every native library, and proves that the installed application remains alive
under D-Bus and Xvfb. `.github/workflows/release-linux.yml` provides the
protected tag/manual release lane. Manual dry runs remain unsigned; publishing
fails closed unless the exact tag, HTTPS production API origin and protected
Linux signing credentials are present.

## Security invariants

- All runtime operations go through the backend API; there is no database or
  server-shell access from Admin.
- Privileged UI and cached state fail closed immediately after any 401/403.
- Mutations carry expected revisions and conflicts cause a canonical reload.
- Moderation previews require WebP, `Cache-Control: no-store`, bounded bytes and
  a matching `X-Content-SHA256`; preview buffers are overwritten on disposal.
- Secrets never enter source, logs, analytics or the homeowner-client keyring.
- Admin rejects non-Admin session bindings and household-client API routes.
  Operator inspection uses the separate backend-authorized administrator API.

## License

Copyright (c) 2026 Vast Development Method Trading Pty Ltd. All rights reserved.

This repository is proprietary software. No licence is granted to use, copy,
modify, merge, publish, distribute, sublicense, or sell the software except as
expressly authorised in writing by Vast Development Method Trading Pty Ltd.
Viewing or forking this repository on GitHub does not grant a licence. See the
[LICENSE](LICENSE) file for the complete terms.
