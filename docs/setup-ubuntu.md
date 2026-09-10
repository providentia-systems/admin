# Set up Providentia Admin on Ubuntu

This guide builds and runs the separate Providentia Admin desktop application.
It is intended for an administrator using an Ubuntu PC and a Providentia server
that is already reachable through a public HTTPS API origin.

For a production workstation, prefer a signed Admin package from a normal
Providentia release. The source setup below is useful for evaluation, local
development and teams testing a reviewed release branch. It does not replace
the backend release, deployment or post-release acceptance process.

## Before you start

You need:

- an x86-64 Ubuntu or Debian-based graphical desktop;
- a normal, non-root desktop login with `sudo` access for initial packages;
- Git and outbound internet access to the hosts in
  [`tools/agent-requirements.json`](../tools/agent-requirements.json);
- the public origin of a working Providentia backend, normally similar to
  `https://api.example.com`; and
- access to the mailbox used for the eight-digit Admin sign-in code.

The public backend origin is not a database connection string. Do not put a
username, password, token or path in it. The Admin application never connects
to MySQL/MariaDB, Redis, a server shell or an AI provider directly.

## Guided setup

Install Git if it is not already installed, clone this repository, and run the
guide as your desktop user:

```bash
sudo apt update
sudo apt install --yes git
git clone https://github.com/providentia-systems/admin.git
cd admin
bash tools/providentia-admin.sh
```

When prompted, enter the public backend origin. The script accepts HTTPS for a
remote server and plain HTTP only for loopback development:

```text
https://api.example.com
https://api.example.com:8443
http://localhost:8080
```

Automation and repeat builds can pass the value explicitly:

```bash
bash tools/providentia-admin.sh \
  --api-url https://api.example.com
```

The script:

1. rejects credentials, paths, queries, fragments and invalid ports in the
   backend value;
2. installs the declared Ubuntu build dependencies through `apt`;
3. uses the repository-pinned, checksum-verified Node and Flutter releases;
4. verifies the locked API contract and generated Admin operations;
5. creates a Linux release build with that backend origin compiled into it; and
6. launches `build/linux/x64/release/bundle/providentia_admin`.

Do not run the whole script with `sudo`. It invokes `sudo` only for packages and
then builds as the desktop user. Build caches stay repository-local in a
subshell; the application starts in the user's normal graphical D-Bus session
so `libsecret` can use the normal Admin keyring namespace.

Use `--no-launch` on a build host or when you want to start the bundle later:

```bash
bash tools/providentia-admin.sh \
  --api-url https://api.example.com \
  --no-launch
```

Use `--skip-system-packages` only after all packages in
`tools/agent-requirements.json` are installed. This option skips `apt`; the
bootstrap and build fail if a required command, library or header is absent.

## Validate a server value

URL validation has no installation or build side effects:

```bash
bash tools/providentia-admin.sh \
  --validate-url https://api.example.com/
```

The result is normalized to `https://api.example.com`. A trailing slash is
fine, but `/api`, `/api/v1`, `?query`, `#fragment` and embedded credentials are
not. The client adds API paths itself.

The backend origin is a compile-time setting. To move this checkout to another
server, rerun the script with the new origin and replace the old local build.
User sessions are server-bound; sign in normally on the new server.

## Server ports and firewall boundary

Only the reverse proxy's TLS listener should be reachable from the Admin PC.
The common topology is:

| Service | Typical port | Exposure |
| --- | ---: | --- |
| Public HTTPS API/reverse proxy | `443` | Allow from intended clients |
| Optional custom HTTPS API | for example `8443` | Allow only if deliberately configured |
| SSH administration | `22` | Restrict to trusted administrator addresses or a VPN |
| Backend application/PHP-FPM | commonly `9000` internally | Never publish directly |
| MySQL or MariaDB | commonly `3306` internally | Never publish to client networks |
| Redis | commonly `6379` internally | Never publish to client networks |
| Internal metrics/health collectors | deployment-specific | Restrict to the server network |

Providentia production persistence is MySQL or MariaDB. PostgreSQL is not a
supported production datastore for this release. Database credentials belong
only in the backend's protected deployment secrets, never in this script or
the Admin client.

On the Admin PC, permit outbound DNS and HTTPS to the selected API. No inbound
Admin application port is required. On a simple Ubuntu server, an initial UFW
policy might allow HTTPS and tightly restricted SSH:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from YOUR_ADMIN_PUBLIC_IP to any port 22 proto tcp
sudo ufw allow 443/tcp
sudo ufw status verbose
```

Replace `YOUR_ADMIN_PUBLIC_IP` before running the SSH rule. Confirm that a
second SSH session works before enabling or changing a remote firewall. Keep
database, Redis, PHP-FPM and metrics ports on the private container/server
network. If the server uses OPNsense, a cloud firewall or another perimeter,
apply the same allow-list there as well.

Terminate TLS at the reverse proxy with a certificate valid for the exact API
hostname. Forward requests to the backend over the private network and retain
the original HTTPS scheme and host headers. Do not work around certificate
errors by exposing an unencrypted remote API.

Admin is a native Linux client, so browser CORS rules do not grant its access.
If a browser client is also deployed, configure the backend with its exact
HTTPS origin(s); do not use a credentialed wildcard origin. Keep the Admin
authorization checks on the backend regardless of client visibility.

The backend repository's `docs/deployment/server-quick-start.md` and
`docs/deployment/environment-reference.md` are the authoritative sources for
Compose services, generated secrets, mail, proxy and CORS settings.

## First sign-in

From the released backend application environment, authorize the initial
system owner once:

```bash
php bin/providentia system:owner owner@example.com
```

Then open Admin, request the eight-digit code for that address, enter the code,
and complete the name, country and current privacy-notice fields. Region and
city are optional and can be cleared later. Running the owner command does not
bypass email verification and does not place credentials in the client.

Subsequent Admin applicants complete the same email and profile flow, then wait
for an authorized operator to approve them into an administrator group.

## AI configuration boundary

Admin does not call OpenAI, Anthropic or any other AI provider, and this setup
does not ask for a provider key. Provider credentials are submitted only
through an authorized product flow, stored encrypted and write-only by the
backend, and never returned to Admin.

The backend keeps two capabilities separate:

- `ai.credentials.use` permits approved bring-your-own-key use; and
- `ai.platform.use` is reserved for operator-funded platform AI.

AI output remains a proposal that a user reviews before it changes inventory.
See the backend repository's `docs/deployment/ai-byok.md` for provider and
worker configuration. Do not add provider keys to this script, Flutter build
defines, Compose files committed to Git, screenshots or support logs.

## Update or rebuild

Review and commit any local work before updating. On a clean checkout:

```bash
git pull --ff-only
bash tools/providentia-admin.sh \
  --api-url https://api.example.com
```

Rerunning the script reuses healthy, checksum-verified tool downloads and
rebuilds the application. Use the same command whenever the API origin changes.
Production changes should arrive through reviewed branches and normal signed
releases. Do not mount corrected source files into a read-only container, edit
a live database by hand, or make the backend application filesystem writable.

Contributors should additionally run the complete repository gate:

```bash
bash tools/agent-check.sh
```

That gate formats, analyzes, tests, checks coverage, builds all Linux packages
and launches the installed bundle under D-Bus/Xvfb.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `Invalid backend origin` | Use one HTTPS origin with a valid port and no `/api`, credentials, query or fragment. |
| Remote HTTP is rejected | Install a valid TLS certificate and use HTTPS. HTTP is intentionally loopback-only. |
| API cannot be reached | Check DNS, the certificate, reverse-proxy routing, server health and outbound/inbound port `443` rules. |
| No graphical desktop or D-Bus session | Run from a terminal inside the logged-in Ubuntu desktop, not SSH or `sudo`. |
| Keyring errors | Ensure `libsecret-1-0` is installed and the desktop keyring is unlocked; do not source `.agent-env` to launch the app manually. |
| No email code arrives | Check backend SMTP/outbox workers, spam filtering, the 60-second resend limit and the ten-minute expiry. |
| Access becomes pending or is denied | Ask the system owner to approve the account and assign an administrator group; the client cannot bypass backend authorization. |
| A changed server still appears | Rebuild with the new `--api-url`; the origin is compiled into the bundle. |
| Tool download fails | Allow the exact hosts in `tools/agent-requirements.json`, then rerun. Partial or unhealthy caches are repaired. |

Do not paste access tokens, sign-in codes, provider keys, database credentials
or unredacted private server details into issue reports. Health output and
screenshots used for documentation must use synthetic accounts and redact
identifiers.
