# Admin household editing, stock and compatibility

Tracks #19, #20 and #21. The PR was opened before implementation, with subsequent
commits referencing their target issue.

## Scope

- #19: preserve effective local, explicit global and inherited categories; expose household-only name, pack and stock-unit overrides with backend safeguards.
- #20: render resolved backend stock metadata with exact signed quantities, diagnostic identifiers and stable paging.
- #21: adopt the paired supported backend contract reproducibly, validate adapters and compatibility, and document installed-release evidence.

## Implemented behavior

| Issue | Result | Regression coverage |
| --- | --- | --- |
| #19 | Local/global/inherited category state, omitted versus explicit-null updates, household name/pack overrides on linked and private products, guarded stock-unit edits, archived-reference preservation and conflict handling | 23 focused editor/repository/identity tests |
| #20 | Backend-resolved Stock names, packs, units, reference states, exact signed quantities, uncertainty/pending evidence and diagnostic identifiers with stable paging | 12 focused widget tests at narrow/wide widths and 100-row offsets |
| #21 | Exact backend artifact and lock, reproducible 92-operation Admin facade, immutable backend compatibility manifest, real synthetic HTTP adapter gate, package provenance and installed acceptance procedure | Contract/Node tamper and dirty-source checks, real operator fixture and release gates |

Canonical support identities live in
[`contracts/backend-compatibility.json`](../../contracts/backend-compatibility.json)
and the generated manifest; duplicated version labels are not the support
authority. Backend PR #39 supplies the paired Stock projection and contract.

## Validation and acceptance boundaries

Full analysis is clean. The standard Flutter suite passes 216 tests; its live
test is skipped unless the disposable backend fixture is supplied. Handwritten
production line coverage is 78.13% (4721/6042), above the enforced 50% minimum.
The exact immutable-pair gate passes against a clean checkout of backend
`769518dc50e89004db1e1718417e8daad378618e`, with all 32 migrations applied to
disposable SQLite. Real HTTP requests exercise the production native Admin
adapters, including same-session capability loss and restoration. The paired
backend contract verifier and PlatformAccessWorkflow suite pass (29 tests,
774 assertions; local PHP 8.5.12, CI pins 8.5.9).

The Linux release bundle and DEB/AppImage/tar packages build successfully;
checksums, native linkage and release-script safeguards pass. This workspace
blocks the Unix sockets needed for D-Bus/Xvfb launch, so the existing clean-host
CI installation/first-frame lane remains the launch evidence authority. The
canonical agent check was run; its environment-blocked steps were continued
after installing the declared host dependencies. Required PR CI remains visible
on PR #22.

The tests exercise synthetic products and native operator sessions. They do not
inspect this operator's actual household/import records or establish production
deployment, data recovery or installed authenticated acceptance. Those checks
follow [`admin-release-acceptance.md`](../admin-release-acceptance.md), recording
actual deployed revision, contract digest, origin and migration status while
excluding credentials and household records.

## Canonical API 2.4 pin

The canonical artifact and lock now match backend commit
`769518dc50e89004db1e1718417e8daad378618e`, API `2.4.0`, OpenAPI SHA-256
`2b7b38490dc42ad967cfff7e32dd56db41d30842a7d39845b9beecb7f7d4e254`.
The existing 92-operation Admin facade is regenerated from those exact bytes.
The compatibility manifest identifies this as a candidate pending required CI
and installed acceptance; this pin update does not establish those results.
