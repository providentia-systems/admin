# Paired Admin release acceptance

`contracts/backend-compatibility.json` identifies the exact supported backend
revision, API version, canonical artifact and generation counts. CI checks out
that immutable revision and compares the lock, gzip archive and materialized
contract byte for byte before running real HTTP operator requests with synthetic
native bearer sessions. This complements the editor, Stock and authorization
widget/repository regressions. It does not establish the state of an installed
application or a deployed database.

The current Linux Admin uses native bearer sessions in its own credential
namespace. Browser cookie context headers apply only to a browser adapter;
their absence is not evidence of a native Admin cookie collision.

## Build evidence

Build and package with the same public API origin. The protected release
workflow supplies both values from its existing protected configuration. A local
contributor candidate can use:

```bash
source .agent-env
export PROVIDENTIA_BUILD_API_ORIGIN=https://api.example.invalid
export PROVIDENTIA_RELEASE_VERSION=0.1.0-dev
flutter build linux --release \
  --dart-define=PROVIDENTIA_API_BASE_URL="$PROVIDENTIA_BUILD_API_ORIGIN"
bash packaging/linux/build-packages.sh
```

The packager embeds `release-provenance.json` inside DEB, AppImage and tar
bundles and includes a copy in the checksummed artifact collection. It records
the actual Admin commit, dirty-source flag, package version, compiled API origin,
supported backend commit, API version and contract SHA-256. It validates the
canonical archive and lock before writing evidence, and rejects origins that
contain credentials, paths, queries or fragments. A dirty build is identified
explicitly; it is not evidence for a clean release revision.

The build record leaves deployed backend revision and migration status
unverified, and installed/authenticated acceptance marked `not-run`. Those facts
cannot be inferred from a source build or an API version label. Signing keys,
protected release environments and exact-tag publication gates remain required
by the existing release workflow.

## Installed operator acceptance

Use an approved staging home and synthetic products for mutation checks. Apply
the supported backend's documented migrations using the normal deployment
procedure before testing. Preserve backups and existing identities. Install the
checksummed package using the established Ubuntu setup or DEB procedure. Read
`/opt/providentia-admin/release-provenance.json` for a DEB installation; confirm it
matches the package's external checksummed record. Then record:

| Evidence | Required value |
| --- | --- |
| Admin | Exact revision, package version, package checksum, clean-source flag |
| API | Configured origin and API version |
| Backend | Actual deployed revision and its agreement with the supported pin |
| Contract | Exact SHA-256 from the installed build and backend release |
| Migrations | Backend migration head and deployment result |
| Installation | Linux version, installation/launch result and test date |
| Acceptance | Pass/fail for each check below, with failure reason if applicable |

Sign in with the normal native Admin email-code flow, using an operator with the
appropriate capabilities. Keep tokens, codes, proofs, email addresses, actual
household records and provider credentials out of the evidence.

1. Select the approved home. Confirm Products and Stock show readable names,
   packs and units. Include linked/private products, missing/archived references,
   unspecified packs and zero, negative and fractional balances. Preserve exact
   decimal values and navigate more than 100 balance rows and a narrow window.
2. Open and save unchanged local, explicit global and inherited categories.
   Reload and compare the effective result. Switch category scopes and clear an
   override; confirm the advertised catalog fallback after reload.
3. Change household name/pack overrides on linked and private products. Clear
   supported overrides and confirm fallback. Confirm product IDs, quantities,
   history and shared catalog records retain their expected values.
4. Change a unit on a product with no stock evidence. On a product with history,
   confirm the backend rejects a prohibited unit change and the editor retains
   the canonical projection without claiming success or converting quantities.
5. Make a concurrent revision change with a second authorized session. Confirm
   a stale save reports a conflict and reloads canonical records. Reduce an
   operator capability and confirm forbidden data is invalidated; revoke a
   session and confirm privileged views and stored credentials are purged.

For a wrong category or unspecified pack, inspect the raw household overrides,
catalog product/pack IDs, reference states and available authorized provenance.
Separate a display error from stored source data. Similar names with different
packs do not establish duplicate products. Record any confirmed additional
defect in the repository that owns its cause. This workflow neither repairs
balances nor rewrites existing household data.

Production acceptance remains pending until an operator records this evidence
against the installed package and actual deployed backend. Passing CI does not
mean deployment, data recovery or production sign-in has occurred.
