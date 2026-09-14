# Step 2 operator contract handoff

Companions: backend PR #23 and household client PR #19. This operator-only PR #11
pairs the backend-owned contract; it does not add private homeowner AI controls,
Step 3 publication workflows, or Step 4 resilience changes.

Canonical JSON SHA-256:
`d8263a996b1382a0b0742ba4b3ca232e1d6f291644a2659d966e95b2abb038fc`.
The generated facade, archived source, lock, materializer and structural
verification pins must all identify this document.

```sh
bash tool/materialize_contract.sh
node tool/generate_admin_api_client.mjs
bash tools/agent-check.sh
```

`test/features/step_2_inventory_identity_test.dart` covers a catalog family with
no selected pack across repeated operator parsing and audited metadata writes.
The operator already accepts this supported identity. It remains catalog-backed:
an ordinary metadata edit cannot overwrite its global identity or original pack
wording. A private record has neither global identifier; an explicitly resolved
pack has its actual parent product. Do not choose a pack automatically.

The backend's Household AI response now carries an atomic authorized profile,
shared-policy and nullable transmission-plan snapshot. A null plan is a setup
state, not permission to disclose a private profile or execute a legacy/null-ID
recipient. No new operator route or permission is introduced here.

Deploy the paired backend before the new household client; this Admin build can
then be deployed with it. No schema migration or production data rewrite is
introduced. Preserve the previous binaries, image digest and database backup.
Rollback a contract-incompatible household client/backend pair together. Do not
remove source bind-mount overrides until the matching permanent fix is confirmed
in the deployed backend image. The backend release note describes dry-run-first
identity reconciliation and owner-attributed, append-only correction; this Admin
PR does not execute that command or clear household records.

Validation is recorded on this PR against exact commits. A generated contract
alone is not an end-to-end test. The native Admin quality workflow runs with a
clean checkout and validates formatting, strict analysis, tests, coverage, Linux
packages and clean-host launch. Backend PR #23 owns the real three-database
HTTP-to-Dart response conformance evidence. No merge or deployment is performed
by this assignment.
