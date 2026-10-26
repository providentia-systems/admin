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
The real HTTP adapter diagnostic passes against the synthetic migrated backend;
final immutable-pair and Linux package evidence will be recorded after the
supported backend commit is pinned.

The tests exercise synthetic products and native operator sessions. They do not
inspect this operator's actual household/import records or establish production
deployment, data recovery or installed authenticated acceptance. Those checks
follow [`admin-release-acceptance.md`](../admin-release-acceptance.md), recording
actual deployed revision, contract digest, origin and migration status while
excluding credentials and household records.
