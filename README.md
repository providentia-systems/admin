# Providentia Admin

Providentia Admin is the separate Flutter administration client for the
Providentia home-stock platform. Its first supported target is Linux desktop;
there are deliberately no Android, iOS, macOS, web or Windows runners in this
repository.

The application uses the backend's native login-link authentication protocol
and an Admin-specific installation, device, session and Linux keyring namespace.
Backend platform roles select the available workspaces:

- platform administrators inspect privacy-safe account and home-membership
  summaries, activate or suspend accounts, close accounts permanently, and
  grant or revoke platform roles;
- catalog reviewers approve or reject sanitized, consent-bound proposals and
  contributions;
- catalog curators link approved facts to the ordinary proposal pipeline and
  publish only server-sanitized, digest-verified product images;
- billing operators can inspect the billing control plane. Enforcement remains
  disabled during the free stabilization phase (`BILLING_ENABLED=0`).

Admin never exposes household stock, counts, receipts, purchases, locations,
prices, notes, reports, private AI media, provider credentials or full backend
access. Owner-only bootstrap/recovery stays in the backend CLI.

## Start development

```bash
bash tools/agent-setup.sh
source .agent-env
flutter run -d linux \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

See [the agent environment guide](docs/development/agent-environment.md) for the
pinned toolchain, host dependencies, network allowlist and complete validation
lane. The canonical backend contract is frozen under `contracts/openapi/`.

## Security invariants

- All runtime operations go through the backend API; there is no database or
  server-shell access from Admin.
- Privileged UI and cached state fail closed immediately after any 401/403.
- Mutations carry expected revisions and conflicts cause a canonical reload.
- Moderation previews require WebP, `Cache-Control: no-store`, bounded bytes and
  a matching `X-Content-SHA256`; preview buffers are overwritten on disposal.
- Secrets never enter source, logs, analytics or the homeowner-client keyring.

This repository contains proprietary Providentia product source. The owner has
authorized development through public branches and draft pull requests; this
does not grant redistribution or relicensing rights.
